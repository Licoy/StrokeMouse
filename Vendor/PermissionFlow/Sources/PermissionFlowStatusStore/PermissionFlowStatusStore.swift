#if os(macOS)
import AppKit
import Combine
import Foundation
import PermissionFlow

@available(macOS 13.0, *)
@MainActor
public final class PermissionFlowStatusStore: ObservableObject {
    @Published public private(set) var states: [PermissionFlowPane: PermissionAuthorizationState]

    private var trackedPanes: [PermissionFlowPane]
    private var didBecomeActiveCancellable: AnyCancellable?

    public init(
        panes: [PermissionFlowPane] = PermissionFlowPane.allCases,
        refreshOnAppActivation: Bool = true
    ) {
        self.trackedPanes = panes
        self.states = Dictionary(
            uniqueKeysWithValues: panes.map { ($0, PermissionAuthorizationState.checking) }
        )

        if refreshOnAppActivation {
            didBecomeActiveCancellable = NotificationCenter.default
                .publisher(for: NSApplication.didBecomeActiveNotification)
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.refresh()
                    }
                }
        }

        refresh()
    }

    public func state(for pane: PermissionFlowPane) -> PermissionAuthorizationState {
        states[pane] ?? PermissionStatusRegistry.provider(for: pane).authorizationState()
    }

    public func capability(for pane: PermissionFlowPane) -> PermissionStatusCapability {
        PermissionStatusRegistry.provider(for: pane).capability
    }

    public func refresh() {
        for pane in trackedPanes {
            refresh(pane)
        }
    }

    public func refresh(_ pane: PermissionFlowPane) {
        states[pane] = PermissionStatusRegistry.provider(for: pane).authorizationState()
    }

    public func track(_ panes: [PermissionFlowPane], refreshImmediately: Bool = true) {
        trackedPanes = panes

        for pane in panes where states[pane] == nil {
            states[pane] = .checking
        }

        if refreshImmediately {
            refresh()
        }
    }
}
#endif
