import Foundation

enum GestureInputSource: Equatable, Sendable {
    case mouse(MouseTriggerButton)
    case modifier(GestureModifierKey)
    case multitouch
}

struct GestureInputAdmissionContext: Equatable, Sendable {
    let configuration: GestureRuntimeConfiguration
    let isDiagnostic: Bool
    let isSuppressed: Bool

    func accepts(_ source: GestureInputSource) -> Bool {
        guard configuration.isEnabled || isDiagnostic,
              !isSuppressed
        else {
            return false
        }
        switch source {
        case .mouse(let button):
            return configuration.profiles.contains { profile in
                guard profile.isEnabled,
                      case .drawn(let drawn) = profile.input,
                      case .mouse(let trigger) = drawn.activation
                else {
                    return false
                }
                return trigger.button == button
            }
        case .modifier(let key):
            return configuration.profiles.contains { profile in
                guard profile.isEnabled,
                      case .drawn(let drawn) = profile.input,
                      case .modifier(let configured) = drawn.activation
                else {
                    return false
                }
                return configured == key
            }
        case .multitouch:
            guard configuration.directTrackpadEnabled else { return false }
            return isDiagnostic || configuration.profiles.contains {
                guard $0.isEnabled, case .trackpad = $0.input else {
                    return false
                }
                return true
            }
        }
    }
}

struct GestureInputAdmission: Equatable, Sendable {
    let id: UInt64
    let epoch: UInt64
    let source: GestureInputSource
    let context: GestureInputAdmissionContext
}

final class GestureSessionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var currentContext: GestureInputAdmissionContext?
    private var activeAdmission: GestureInputAdmission?
    private var drainingSource: GestureInputSource?
    private var nextAdmissionID: UInt64 = 0
    private var drawEpoch: UInt64 = 0
    private var multitouchEpoch: UInt64 = 0
    private var drawInputsEnabled = true

    var activeSource: GestureInputSource? {
        lock.lock()
        defer { lock.unlock() }
        return activeAdmission?.source ?? drainingSource
    }

    func updateContext(_ context: GestureInputAdmissionContext) {
        lock.lock()
        currentContext = context
        lock.unlock()
    }

    func claim(_ proposed: GestureInputSource) -> GestureInputAdmission? {
        lock.lock()
        defer { lock.unlock() }
        guard drawInputsEnabled || proposed == .multitouch else {
            return nil
        }
        guard drainingSource == nil else { return nil }
        if let activeAdmission {
            return activeAdmission.source == proposed
                ? activeAdmission
                : nil
        }
        guard let currentContext, currentContext.accepts(proposed) else {
            return nil
        }
        nextAdmissionID &+= 1
        let admission = GestureInputAdmission(
            id: nextAdmissionID,
            epoch: epoch(for: proposed),
            source: proposed,
            context: currentContext
        )
        activeAdmission = admission
        return admission
    }

    func admission(for source: GestureInputSource) -> GestureInputAdmission? {
        lock.lock()
        defer { lock.unlock() }
        guard activeAdmission?.source == source else { return nil }
        return activeAdmission
    }

    func release(_ completed: GestureInputAdmission) {
        lock.lock()
        defer { lock.unlock() }
        guard activeAdmission?.id == completed.id,
              activeAdmission?.source == completed.source
        else {
            return
        }
        activeAdmission = nil
    }

    @discardableResult
    func interrupt(_ source: GestureInputSource) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if drainingSource == source {
            return true
        }
        guard drainingSource == nil,
              activeAdmission?.source == source
        else {
            return false
        }
        advanceEpoch(for: source)
        activeAdmission = nil
        drainingSource = source
        return true
    }

    @discardableResult
    func completeDrain(_ source: GestureInputSource) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard drainingSource == source else { return false }
        drainingSource = nil
        return true
    }

    @discardableResult
    func forceRelease(_ completed: GestureInputSource) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard activeAdmission?.source == completed
                || drainingSource == completed
        else {
            return false
        }
        advanceEpoch(for: completed)
        activeAdmission = nil
        drainingSource = nil
        return true
    }

    func isValid(_ admission: GestureInputAdmission) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return admission.epoch == epoch(for: admission.source)
    }

    /// Rejects new drawn-input claims and invalidates any draw admission that
    /// has already left the input-core queue but has not reached the main actor.
    /// Multitouch admissions remain valid because Accessibility is unrelated to
    /// the private touch device lifecycle.
    func disableAndInvalidateDrawInputs() {
        lock.lock()
        guard drawInputsEnabled else {
            lock.unlock()
            return
        }
        drawInputsEnabled = false
        drawEpoch &+= 1
        if let activeAdmission,
           activeAdmission.source != .multitouch
        {
            self.activeAdmission = nil
        }
        if let drainingSource,
           drainingSource != .multitouch
        {
            self.drainingSource = nil
        }
        lock.unlock()
    }

    func enableDrawInputs() {
        lock.lock()
        drawInputsEnabled = true
        lock.unlock()
    }

    @discardableResult
    func reset() -> Bool {
        lock.lock()
        let hadActiveAdmission =
            activeAdmission != nil || drainingSource != nil
        drawEpoch &+= 1
        multitouchEpoch &+= 1
        activeAdmission = nil
        drainingSource = nil
        lock.unlock()
        return hadActiveAdmission
    }

    private func epoch(for source: GestureInputSource) -> UInt64 {
        source == .multitouch ? multitouchEpoch : drawEpoch
    }

    private func advanceEpoch(for source: GestureInputSource) {
        if source == .multitouch {
            multitouchEpoch &+= 1
        } else {
            drawEpoch &+= 1
        }
    }
}

struct MultitouchAdmission: Equatable, Sendable {
    let sequenceID: UInt64
    let admission: GestureInputAdmission?
    let isBeginning: Bool

    var isAccepted: Bool { admission != nil }
}

/// Latches one arbitration decision for a complete physical contact sequence.
/// A rejected sequence cannot claim again after the current owner releases.
final class MultitouchSessionAdmission: @unchecked Sendable {
    private struct ActiveSequence {
        let id: UInt64
        let admission: GestureInputAdmission?
    }

    private let lock = NSLock()
    private var nextSequenceID: UInt64 = 0
    private var activeSequence: ActiveSequence?

    func process(
        _ frame: TrackpadTouchFrame,
        gate: GestureSessionGate
    ) -> MultitouchAdmission {
        let hasActiveContact = frame.contacts.contains(
            where: \.phase.isActive
        )
        lock.lock()
        defer { lock.unlock() }

        if hasActiveContact {
            if let activeSequence {
                return MultitouchAdmission(
                    sequenceID: activeSequence.id,
                    admission: activeSequence.admission,
                    isBeginning: false
                )
            }
            nextSequenceID &+= 1
            let sequence = ActiveSequence(
                id: nextSequenceID,
                admission: gate.claim(.multitouch)
            )
            activeSequence = sequence
            return MultitouchAdmission(
                sequenceID: sequence.id,
                admission: sequence.admission,
                isBeginning: true
            )
        }

        let completed = activeSequence
        activeSequence = nil
        if let admission = completed?.admission {
            gate.release(admission)
        }
        return MultitouchAdmission(
            sequenceID: completed?.id ?? nextSequenceID,
            admission: completed?.admission,
            isBeginning: false
        )
    }

    @discardableResult
    func reset() -> Bool {
        lock.lock()
        let hadActiveSequence = activeSequence != nil
        activeSequence = nil
        lock.unlock()
        return hadActiveSequence
    }
}
