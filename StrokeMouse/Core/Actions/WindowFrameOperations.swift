import ApplicationServices
import Foundation
import OSLog

/// MainActor reentrancy must not allow frame reads/writes for one AX window to overlap.
@MainActor
final class WindowFrameOperationQueue {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private struct Entry {
        let window: AXUIElement
        var waiters: [Waiter] = []
    }
    private var entries: [Entry] = []

    func acquire(_ window: AXUIElement) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if let index = entries.firstIndex(where: { CFEqual($0.window, window) }) {
                    entries[index].waiters.append(Waiter(id: id, continuation: continuation))
                } else {
                    entries.append(Entry(window: window))
                    continuation.resume()
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    func release(_ window: AXUIElement) {
        guard let index = entries.firstIndex(where: { CFEqual($0.window, window) }) else {
            preconditionFailure("Releasing a window operation without ownership")
        }
        if entries[index].waiters.isEmpty {
            entries.remove(at: index)
        } else {
            entries[index].waiters.removeFirst().continuation.resume()
        }
    }

    private func cancel(_ id: UUID) {
        for index in entries.indices {
            if let waiter = entries[index].waiters.firstIndex(where: { $0.id == id }) {
                entries[index].waiters.remove(at: waiter).continuation.resume(throwing: CancellationError())
                return
            }
        }
    }
}

extension MacGestureTargetSystemClient {
    /// Read both the starting frame and history only after taking this window's turn.
    func performFrameChange(
        _ window: AXUIElement,
        using suppliedResizer: WindowMaximizer? = nil,
        maximize: Bool = false,
        destination: (CGRect) throws -> CGRect
    ) async throws {
        try await frameOperations.acquire(window)
        defer { frameOperations.release(window) }
        try Task.checkCancellation()
        var resizer = suppliedResizer ?? frameResizer
        if suppliedResizer == nil && !maximize { resizer.completionTimeout = .milliseconds(1500) }
        let current = try resizer.ax.readFrame(window)
        let requested = try destination(current)
        let knownSize = maximize ? nil : acceptedLayoutSizes.last {
            CFEqual($0.window, window) && $0.requested == requested.size
        }?.accepted
        let expected = CGRect(origin: requested.origin, size: knownSize ?? requested.size)
        guard !WindowMaximizer.framesMatch(current, expected) else { return }
        do {
            if maximize {
                try await resizer.maximize(window, to: requested)
            } else {
                let applied = try await resizer.applyLayout(window, to: requested, knownAcceptedSize: knownSize)
                acceptedLayoutSizes.removeAll { CFEqual($0.window, window) }
                acceptedLayoutSizes.append((window, requested.size, applied.size))
                if acceptedLayoutSizes.count > 100 { acceptedLayoutSizes.removeFirst() }
            }
            try rememberChangedFrame(window, original: current, ax: resizer.ax)
        } catch {
            let originalError = error
            do {
                try rememberChangedFrame(window, original: current, ax: resizer.ax)
            } catch {
                // Unknown partial writes must remain recoverable, without replacing the original error.
                rememberFrame(window, frame: current)
                Self.frameLogger.error("Could not verify failed window operation: \(String(describing: error), privacy: .public)")
            }
            throw originalError
        }
    }

    private func rememberChangedFrame(_ window: AXUIElement, original: CGRect, ax: WindowFrameAXClient) throws {
        if !WindowMaximizer.framesMatch(try ax.readFrame(window), original) {
            rememberFrame(window, frame: original)
        }
    }

    private static let frameLogger = Logger(subsystem: "com.strokemouse.app", category: "WindowFrame")
}
