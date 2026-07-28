import XCTest
@testable import StrokeMouse

final class GestureSessionGateTests: XCTestCase {
    func testFirstInputWinsUntilItReleases() {
        let gate = makeGate()

        let modifier = gate.claim(.modifier(.function))
        XCTAssertNotNil(modifier)
        XCTAssertNil(gate.claim(.mouse(.right)))
        XCTAssertNil(gate.claim(.multitouch))
        XCTAssertEqual(gate.activeSource, .modifier(.function))

        gate.release(tryUnwrap(modifier))

        XCTAssertNotNil(gate.claim(.mouse(.right)))
        XCTAssertEqual(gate.activeSource, .mouse(.right))
    }

    func testWrongSourceCannotReleaseOwner() {
        let gate = makeGate()
        XCTAssertNotNil(gate.claim(.multitouch))

        gate.forceRelease(.mouse(.right))

        XCTAssertEqual(gate.activeSource, .multitouch)
        XCTAssertNil(gate.claim(.modifier(.shift)))
    }

    func testInterruptedOwnerBlocksEverySourceUntilPhysicalDrain() {
        let gate = makeGate()
        let mouse = tryUnwrap(gate.claim(.mouse(.right)))

        XCTAssertTrue(gate.interrupt(.mouse(.right)))
        XCTAssertFalse(gate.isValid(mouse))
        XCTAssertEqual(gate.activeSource, .mouse(.right))
        XCTAssertNil(gate.claim(.mouse(.right)))
        XCTAssertNil(gate.claim(.modifier(.function)))
        XCTAssertNil(gate.claim(.multitouch))

        XCTAssertTrue(gate.completeDrain(.mouse(.right)))
        XCTAssertNil(gate.activeSource)
        XCTAssertNotNil(gate.claim(.modifier(.function)))
    }

    func testWrongSourceCannotCompleteInterruptedDrain() {
        let gate = makeGate()
        XCTAssertNotNil(gate.claim(.modifier(.function)))
        XCTAssertTrue(gate.interrupt(.modifier(.function)))

        XCTAssertFalse(gate.completeDrain(.mouse(.right)))
        XCTAssertEqual(gate.activeSource, .modifier(.function))
        XCTAssertNil(gate.claim(.multitouch))
    }

    func testClaimIsIdempotentForCurrentPhysicalSource() {
        let gate = makeGate()

        let first = tryUnwrap(gate.claim(.mouse(.middle)))
        let repeated = tryUnwrap(gate.claim(.mouse(.middle)))
        XCTAssertEqual(repeated.id, first.id)
        gate.release(first)

        XCTAssertNil(gate.activeSource)
    }

    func testHardResetInvalidatesQueuedAdmissionButPhysicalReleaseDoesNot() {
        let gate = makeGate()
        let physicallyCompleted = tryUnwrap(gate.claim(.mouse(.right)))
        gate.release(physicallyCompleted)
        XCTAssertTrue(gate.isValid(physicallyCompleted))

        let cancelled = tryUnwrap(gate.claim(.modifier(.function)))
        gate.reset()
        XCTAssertFalse(gate.isValid(cancelled))
    }

    func testDisablingDrawInputsInvalidatesDrawOnly() {
        let gate = makeGate()
        let mouse = tryUnwrap(gate.claim(.mouse(.right)))
        gate.release(mouse)
        let multitouch = tryUnwrap(gate.claim(.multitouch))

        gate.disableAndInvalidateDrawInputs()

        XCTAssertFalse(gate.isValid(mouse))
        XCTAssertTrue(gate.isValid(multitouch))
        XCTAssertNil(gate.claim(.mouse(.right)))
        gate.release(multitouch)
        XCTAssertNil(gate.claim(.modifier(.function)))

        gate.enableDrawInputs()
        XCTAssertNotNil(gate.claim(.modifier(.function)))
    }

    func testRejectedMultitouchSequenceCannotReclaimUntilEmpty() {
        let gate = makeGate()
        let admission = MultitouchSessionAdmission()
        let mouse = tryUnwrap(gate.claim(.mouse(.right)))

        let first = admission.process(
            touchFrame(at: 0, isActive: true),
            gate: gate
        )
        XCTAssertFalse(first.isAccepted)
        gate.release(mouse)

        let later = admission.process(
            touchFrame(at: 0.1, isActive: true),
            gate: gate
        )
        XCTAssertEqual(later.sequenceID, first.sequenceID)
        XCTAssertFalse(later.isAccepted)
        XCTAssertFalse(later.isBeginning)
        XCTAssertNil(gate.activeSource)

        let completed = admission.process(
            touchFrame(at: 0.2, isActive: false),
            gate: gate
        )
        XCTAssertFalse(completed.isAccepted)
        let next = admission.process(
            touchFrame(at: 0.3, isActive: true),
            gate: gate
        )
        XCTAssertTrue(next.isAccepted)
        XCTAssertEqual(gate.activeSource, .multitouch)
    }

    func testPhysicalEmptyReleasesBeforeNextSequenceAndStaleReleaseIsSafe() {
        let gate = makeGate()
        let admission = MultitouchSessionAdmission()
        let first = admission.process(
            touchFrame(at: 0, isActive: true),
            gate: gate
        )
        _ = admission.process(
            touchFrame(at: 0.1, isActive: false),
            gate: gate
        )
        XCTAssertNil(gate.activeSource)
        gate.updateContext(context(revision: 2))
        let second = admission.process(
            touchFrame(at: 0.2, isActive: true),
            gate: gate
        )

        XCTAssertTrue(first.isAccepted)
        XCTAssertTrue(second.isAccepted)
        XCTAssertGreaterThan(second.sequenceID, first.sequenceID)
        XCTAssertNotEqual(first.admission?.id, second.admission?.id)
        XCTAssertEqual(second.admission?.context.configuration.revision, 2)

        gate.release(tryUnwrap(first.admission))
        XCTAssertEqual(gate.activeSource, .multitouch)
    }

    private func touchFrame(
        at timestamp: TimeInterval,
        isActive: Bool
    ) -> TrackpadTouchFrame {
        TrackpadTouchFrame(
            timestamp: timestamp,
            contacts: isActive
                ? [
                    TrackpadTouchContact(
                        id: 1,
                        phase: .moved,
                        position: .zero
                    ),
                ]
                : []
        )
    }

    private func makeGate() -> GestureSessionGate {
        let gate = GestureSessionGate()
        gate.updateContext(context(revision: 1))
        return gate
    }

    private func context(
        revision: UInt64
    ) -> GestureInputAdmissionContext {
        let drawnPoints = PathTemplates.up
        let mouse = MouseTriggerButton.allCases.map {
            GestureProfile(
                name: $0.rawValue,
                input: .drawn(DrawnGesture(
                    activation: .mouse(GestureTrigger(button: $0)),
                    points: drawnPoints
                ))
            )
        }
        let modifiers = GestureModifierKey.allCases.map {
            GestureProfile(
                name: $0.rawValue,
                input: .drawn(DrawnGesture(
                    activation: .modifier($0),
                    points: drawnPoints
                ))
            )
        }
        return GestureInputAdmissionContext(
            configuration: GestureRuntimeConfiguration(
                revision: revision,
                isEnabled: true,
                profiles: mouse + modifiers + [
                    GestureProfile(
                        name: "Direct",
                        input: .trackpad(.swipe(.three, .right))
                    ),
                ],
                minimumStrokeDistance: 40,
                pathMatchThreshold: 0.7,
                showsHUD: false,
                directTrackpadEnabled: true
            ),
            isDiagnostic: false,
            isSuppressed: false
        )
    }

    private func tryUnwrap<Value>(
        _ value: Value?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Value {
        guard let value else {
            XCTFail("Expected a value", file: file, line: line)
            fatalError("Test cannot continue without value")
        }
        return value
    }
}
