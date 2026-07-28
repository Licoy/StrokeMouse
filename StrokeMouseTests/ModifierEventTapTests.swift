import CoreGraphics
import XCTest
@testable import StrokeMouse

final class ModifierEventTapTests: XCTestCase {
    func testTapIsListenOnlyAndOnlyObservesFlagsChanged() {
        XCTAssertEqual(ModifierEventTap.tapOptions, .listenOnly)
        XCTAssertEqual(
            ModifierEventTap.eventsOfInterestMask,
            CGEventMask(1) << CGEventType.flagsChanged.rawValue
        )
    }

    func testEachSupportedSingleKeyBeginsAndEnds() {
        for key in GestureModifierKey.allCases {
            var machine = ModifierFlagsStateMachine(watchedKeys: [key])

            XCTAssertEqual(machine.process(keys: [key]), .began(key))
            XCTAssertNil(machine.process(keys: [key]))
            XCTAssertEqual(machine.process(keys: []), .ended(key))
            XCTAssertNil(machine.process(keys: []))
        }
    }

    func testAdditionalSupportedKeyCancelsUntilEveryKeyIsReleased() {
        var machine = ModifierFlagsStateMachine(watchedKeys: [.function])

        XCTAssertEqual(
            machine.process(keys: [.function]),
            .began(.function)
        )
        XCTAssertEqual(
            machine.process(keys: [.function, .shift]),
            .cancelled(.function)
        )
        XCTAssertNil(machine.process(keys: [.function]))
        XCTAssertEqual(machine.process(keys: []), .drained(.function))
        XCTAssertEqual(
            machine.process(keys: [.function]),
            .began(.function)
        )
    }

    func testInterruptInvalidatesActiveKeyUntilEveryKeyIsReleased() {
        var machine = ModifierFlagsStateMachine(watchedKeys: [.function])

        XCTAssertEqual(machine.process(keys: [.function]), .began(.function))
        XCTAssertEqual(
            machine.interrupt(keys: [.function]),
            .interrupted(.function)
        )
        XCTAssertNil(machine.process(keys: [.function]))
        XCTAssertNil(machine.process(keys: [.function, .shift]))
        XCTAssertEqual(machine.process(keys: []), .drained(.function))
        XCTAssertEqual(machine.process(keys: [.function]), .began(.function))
    }

    func testUnwatchedKeyCannotArmGestureMidChord() {
        var machine = ModifierFlagsStateMachine(watchedKeys: [.function])

        XCTAssertNil(machine.process(keys: [.shift]))
        XCTAssertNil(machine.process(keys: [.shift, .function]))
        XCTAssertNil(machine.process(keys: [.function]))
        XCTAssertNil(machine.process(keys: []))
        XCTAssertEqual(
            machine.process(keys: [.function]),
            .began(.function)
        )
    }

    func testSupportedFlagsIgnoreCapsLockAndDeviceIndependentBits() {
        let flags: CGEventFlags = [
            .maskSecondaryFn,
            .maskAlphaShift,
            .maskNonCoalesced,
        ]

        XCTAssertEqual(
            ModifierEventTap.supportedKeys(in: flags),
            [.function]
        )
    }

    func testTapDisableInterruptsAndDrainsBeforeRearming() throws {
        let tap = ModifierEventTap(physicalKeysProvider: {
            [.function]
        })
        tap.watchedKeys = [.function]
        var observed: [(
            event: ModifierFlagsStateMachine.Event,
            generation: UInt64
        )] = []
        tap.onEvent = { event, _, generation in
            observed.append((event, generation))
        }
        let functionDown = try makeFlagsEvent([.maskSecondaryFn])
        let functionAndShift = try makeFlagsEvent([
            .maskSecondaryFn,
            .maskShift,
        ])
        let allUp = try makeFlagsEvent([])

        XCTAssertNotNil(tap.handle(
            type: .flagsChanged,
            event: functionDown
        ))
        XCTAssertNotNil(tap.handle(
            type: .tapDisabledByUserInput,
            event: functionDown
        ))
        XCTAssertFalse(tap.isCurrentEventGeneration(0))
        XCTAssertTrue(tap.isCurrentEventGeneration(1))

        XCTAssertNotNil(tap.handle(
            type: .flagsChanged,
            event: functionAndShift
        ))
        XCTAssertNotNil(tap.handle(type: .flagsChanged, event: allUp))
        XCTAssertNotNil(tap.handle(
            type: .flagsChanged,
            event: functionDown
        ))

        XCTAssertEqual(observed.map(\.event), [
            .began(.function),
            .interrupted(.function),
            .drained(.function),
            .began(.function),
        ])
        XCTAssertEqual(observed.map(\.generation), [0, 1, 1, 1])
    }

    func testTapDisableImmediatelyDrainsModifierAlreadyReleased()
        throws
    {
        let tap = ModifierEventTap(physicalKeysProvider: { [] })
        tap.watchedKeys = [.function]
        var observed: [ModifierFlagsStateMachine.Event] = []
        tap.onEvent = { event, _, _ in
            observed.append(event)
        }
        let functionDown = try makeFlagsEvent([.maskSecondaryFn])

        XCTAssertNotNil(tap.handle(
            type: .flagsChanged,
            event: functionDown
        ))
        XCTAssertNotNil(tap.handle(
            type: .tapDisabledByTimeout,
            event: functionDown
        ))

        XCTAssertEqual(observed, [
            .began(.function),
            .interrupted(.function),
            .drained(.function),
        ])
    }

    private func makeFlagsEvent(
        _ flags: CGEventFlags
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        ))
        event.flags = flags
        return event
    }
}
