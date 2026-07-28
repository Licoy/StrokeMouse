import CoreGraphics
import XCTest
@testable import StrokeMouse

final class TrackpadGestureClassifierTests: XCTestCase {
    func testAllThirtyFourDirectGesturesResolveThroughPipeline() throws {
        var resolved = Set<DirectTrackpadGesture>()
        for fingerValue in 3...5 {
            let fingers = try XCTUnwrap(
                StandardFingerCount(rawValue: fingerValue)
            )
            XCTAssertEqual(
                classifyTap(fingers: fingerValue),
                .recognized(.tap(fingers: fingerValue))
            )
            let firstTap = TrackpadTap(
                deviceID: 1,
                fingers: fingerValue,
                centroid: .zero,
                timestamp: 0
            )
            var singleResolver = TrackpadTapSequenceResolver(
                doubleClickInterval: 0.5
            )
            XCTAssertEqual(
                singleResolver.register(
                    firstTap,
                    availability: .singleOnly
                ),
                [.single(firstTap)]
            )
            resolved.insert(.tap(fingers, .single))

            var doubleResolver = TrackpadTapSequenceResolver(
                doubleClickInterval: 0.5
            )
            XCTAssertTrue(doubleResolver.register(
                firstTap,
                availability: .doubleOnly
            ).isEmpty)
            let secondTap = TrackpadTap(
                deviceID: 1,
                fingers: fingerValue,
                centroid: .zero,
                timestamp: 0.2
            )
            XCTAssertEqual(
                doubleResolver.register(
                    secondTap,
                    availability: .doubleOnly
                ),
                [.double(first: firstTap, second: secondTap)]
            )
            resolved.insert(.tap(fingers, .double))

            for (delta, direction) in [
                (CGPoint(x: 0.16, y: 0), CardinalDirection.right),
                (CGPoint(x: -0.16, y: 0), .left),
                (CGPoint(x: 0, y: 0.16), .up),
                (CGPoint(x: 0, y: -0.16), .down),
            ] {
                XCTAssertNotNil(classify(fingers: fingerValue) {
                    translate($0, by: delta)
                })
                resolved.insert(.swipe(fingers, direction))
            }
        }

        for fingerValue in 2...5 {
            let fingers = try XCTUnwrap(
                TransformFingerCount(rawValue: fingerValue)
            )
            for (factor, direction) in [
                (CGFloat(1.25), PinchDirection.outward),
                (CGFloat(0.75), .inward),
            ] {
                XCTAssertNotNil(classify(fingers: fingerValue) {
                    scale($0, by: factor)
                })
                resolved.insert(.pinch(fingers, direction))
            }
            for (angle, direction) in [
                (CGFloat.pi / 9, RotationDirection.counterclockwise),
                (-CGFloat.pi / 9, .clockwise),
            ] {
                XCTAssertNotNil(classify(fingers: fingerValue) {
                    rotate($0, radians: angle)
                })
                resolved.insert(.rotate(fingers, direction))
            }
        }

        XCTAssertEqual(resolved.count, 34)
    }

    func testEveryRawGestureFamilyAndFingerCountIsRecognized() {
        for fingers in 3...5 {
            for (delta, direction) in [
                (CGPoint(x: 0.16, y: 0), TrackpadSwipeDirection.right),
                (CGPoint(x: -0.16, y: 0), .left),
                (CGPoint(x: 0, y: 0.16), .up),
                (CGPoint(x: 0, y: -0.16), .down),
            ] {
                XCTAssertEqual(
                    classify(fingers: fingers) { translate($0, by: delta) },
                    .recognized(.swipe(fingers: fingers, direction: direction))
                )
            }
            XCTAssertEqual(
                classifyTap(fingers: fingers),
                .recognized(.tap(fingers: fingers))
            )
        }

        for fingers in 2...5 {
            XCTAssertEqual(
                classify(fingers: fingers) { scale($0, by: 1.25) },
                .recognized(.pinch(fingers: fingers, direction: .outward))
            )
            XCTAssertEqual(
                classify(fingers: fingers) { scale($0, by: 0.75) },
                .recognized(.pinch(fingers: fingers, direction: .inward))
            )
            XCTAssertEqual(
                classify(fingers: fingers) { rotate($0, radians: .pi / 9) },
                .recognized(.rotate(fingers: fingers, direction: .counterclockwise))
            )
            XCTAssertEqual(
                classify(fingers: fingers) { rotate($0, radians: -.pi / 9) },
                .recognized(.rotate(fingers: fingers, direction: .clockwise))
            )
        }
    }

    func testThreeFingerSwipeRightProducesOneRecognition() {
        var classifier = TrackpadGestureClassifier()

        XCTAssertNil(classifier.process(frame(
            at: 0,
            points: [
                1: CGPoint(x: 0.20, y: 0.40),
                2: CGPoint(x: 0.30, y: 0.50),
                3: CGPoint(x: 0.40, y: 0.40),
            ]
        )))
        XCTAssertNil(classifier.process(frame(
            at: 0.07,
            points: [
                1: CGPoint(x: 0.20, y: 0.40),
                2: CGPoint(x: 0.30, y: 0.50),
                3: CGPoint(x: 0.40, y: 0.40),
            ]
        )))
        XCTAssertNil(classifier.process(frame(
            at: 0.14,
            points: [
                1: CGPoint(x: 0.36, y: 0.40),
                2: CGPoint(x: 0.46, y: 0.50),
                3: CGPoint(x: 0.56, y: 0.40),
            ]
        )))

        let event = classifier.process(frame(at: 0.18, points: [:]))

        XCTAssertEqual(
            event,
            .recognized(.swipe(fingers: 3, direction: .right))
        )
        XCTAssertNil(classifier.process(frame(at: 0.20, points: [:])))
    }

    func testShortStationaryThreeFingerContactProducesTap() {
        var classifier = TrackpadGestureClassifier()
        let points = [
            1: CGPoint(x: 0.20, y: 0.40),
            2: CGPoint(x: 0.30, y: 0.50),
            3: CGPoint(x: 0.40, y: 0.40),
        ]

        XCTAssertNil(classifier.process(frame(at: 0, points: points)))
        XCTAssertNil(classifier.process(frame(at: 0.07, points: points)))

        XCTAssertEqual(
            classifier.process(frame(at: 0.15, points: [:])),
            .recognized(.tap(fingers: 3))
        )
    }

    func testTwoFingerSpreadProducesOutwardPinch() {
        var classifier = TrackpadGestureClassifier()

        XCTAssertNil(classifier.process(frame(
            at: 0,
            points: [
                1: CGPoint(x: 0.40, y: 0.50),
                2: CGPoint(x: 0.60, y: 0.50),
            ]
        )))
        XCTAssertNil(classifier.process(frame(
            at: 0.07,
            points: [
                1: CGPoint(x: 0.40, y: 0.50),
                2: CGPoint(x: 0.60, y: 0.50),
            ]
        )))
        XCTAssertNil(classifier.process(frame(
            at: 0.14,
            points: [
                1: CGPoint(x: 0.36, y: 0.50),
                2: CGPoint(x: 0.64, y: 0.50),
            ]
        )))

        XCTAssertEqual(
            classifier.process(frame(at: 0.20, points: [:])),
            .recognized(.pinch(fingers: 2, direction: .outward))
        )
    }

    func testTwoFingerRotationProducesCounterclockwiseGesture() {
        var classifier = TrackpadGestureClassifier()

        XCTAssertNil(classifier.process(frame(
            at: 0,
            points: [
                1: CGPoint(x: 0.40, y: 0.50),
                2: CGPoint(x: 0.60, y: 0.50),
            ]
        )))
        XCTAssertNil(classifier.process(frame(
            at: 0.07,
            points: [
                1: CGPoint(x: 0.40, y: 0.50),
                2: CGPoint(x: 0.60, y: 0.50),
            ]
        )))
        XCTAssertNil(classifier.process(frame(
            at: 0.14,
            points: [
                1: CGPoint(x: 0.4134, y: 0.45),
                2: CGPoint(x: 0.5866, y: 0.55),
            ]
        )))

        XCTAssertEqual(
            classifier.process(frame(at: 0.20, points: [:])),
            .recognized(.rotate(fingers: 2, direction: .counterclockwise))
        )
    }

    func testGroupedSequentialLiftUsesLastCompleteFrame() {
        var classifier = TrackpadGestureClassifier()
        let start = [
            1: CGPoint(x: 0.20, y: 0.40),
            2: CGPoint(x: 0.30, y: 0.50),
            3: CGPoint(x: 0.40, y: 0.40),
        ]
        let end = [
            1: CGPoint(x: 0.36, y: 0.40),
            2: CGPoint(x: 0.46, y: 0.50),
            3: CGPoint(x: 0.56, y: 0.40),
        ]

        XCTAssertNil(classifier.process(frame(at: 0, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.07, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.14, points: end)))
        XCTAssertNil(classifier.process(TrackpadTouchFrame(
            timestamp: 0.18,
            contacts: [
                TrackpadTouchContact(
                    id: 1,
                    phase: .ended,
                    position: end[1]!
                ),
                TrackpadTouchContact(
                    id: 2,
                    phase: .moved,
                    position: end[2]!
                ),
                TrackpadTouchContact(
                    id: 3,
                    phase: .moved,
                    position: end[3]!
                ),
            ]
        )))

        XCTAssertEqual(
            classifier.process(frame(at: 0.22, points: [:])),
            .recognized(.swipe(fingers: 3, direction: .right))
        )
    }

    func testEndedContactPositionsContributeToTerminalTranslation() {
        var classifier = TrackpadGestureClassifier()
        let start = basePoints(fingers: 3)
        let end = translate(start, by: CGPoint(x: 0.16, y: 0))

        XCTAssertNil(classifier.process(frame(at: 0, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.07, points: start)))
        let terminal = TrackpadTouchFrame(
            timestamp: 0.15,
            contacts: end.map {
                TrackpadTouchContact(
                    id: $0.key,
                    phase: .ended,
                    position: $0.value
                )
            }
        )

        XCTAssertEqual(
            classifier.process(terminal),
            .recognized(.swipe(fingers: 3, direction: .right))
        )
    }

    func testEndedContactPositionsContributeToMaximumTapTravel() {
        var classifier = TrackpadGestureClassifier()
        let start = basePoints(fingers: 3)
        let end = translate(start, by: CGPoint(x: 0.03, y: 0))

        XCTAssertNil(classifier.process(frame(at: 0, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.07, points: start)))
        let terminal = TrackpadTouchFrame(
            timestamp: 0.15,
            contacts: end.map {
                TrackpadTouchContact(
                    id: $0.key,
                    phase: .ended,
                    position: $0.value
                )
            }
        )

        XCTAssertEqual(
            classifier.process(terminal),
            .rejected(.unsupported)
        )
    }

    func testLaterGroupedLiftPositionsContributeToMaximumTravel() {
        var classifier = TrackpadGestureClassifier()
        let start = basePoints(fingers: 3)
        XCTAssertNil(classifier.process(frame(at: 0, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.07, points: start)))
        XCTAssertNil(classifier.process(TrackpadTouchFrame(
            timestamp: 0.12,
            contacts: [
                TrackpadTouchContact(
                    id: 1,
                    phase: .ended,
                    position: start[1]!
                ),
                TrackpadTouchContact(
                    id: 2,
                    phase: .moved,
                    position: start[2]!
                ),
                TrackpadTouchContact(
                    id: 3,
                    phase: .moved,
                    position: start[3]!
                ),
            ]
        )))
        let terminal = TrackpadTouchFrame(
            timestamp: 0.18,
            contacts: [2, 3].map { id in
                TrackpadTouchContact(
                    id: id,
                    phase: .ended,
                    position: CGPoint(
                        x: start[id]!.x + 0.03,
                        y: start[id]!.y
                    )
                )
            }
        )

        XCTAssertEqual(
            classifier.process(terminal),
            .rejected(.unsupported)
        )
    }

    func testTwoFingerTranslationParticipatesButIsNeverRecognizedAsTransform() {
        XCTAssertEqual(
            classify(fingers: 2) {
                translate($0, by: CGPoint(x: 0.18, y: 0))
            },
            .rejected(.unsupported)
        )
    }

    func testDiagonalSwipeIsRejected() {
        XCTAssertEqual(
            classify(fingers: 3) {
                translate($0, by: CGPoint(x: 0.15, y: 0.11))
            },
            .rejected(.unsupported)
        )
    }

    func testMixedScaleAndRotationIsAmbiguous() {
        XCTAssertEqual(
            classify(fingers: 3) {
                rotate(scale($0, by: 1.25), radians: .pi / 9)
            },
            .rejected(.ambiguous)
        )
    }

    func testSubthresholdRunnerUpStillEnforcesDominanceRatio() {
        XCTAssertEqual(
            classify(fingers: 3) {
                rotate(
                    scale($0, by: 1.189),
                    radians: (.pi / 12) * 0.95
                )
            },
            .rejected(.ambiguous)
        )
    }

    func testSingleMovingFingerFailsCoherenceGate() {
        XCTAssertEqual(
            classify(fingers: 3) { points in
                var result = points
                result[1] = CGPoint(
                    x: points[1]!.x + 0.40,
                    y: points[1]!.y
                )
                return result
            },
            .rejected(.unsupported)
        )
    }

    func testFingerLandingSpreadOverOneHundredMillisecondsIsRejected() {
        var classifier = TrackpadGestureClassifier()

        XCTAssertNil(classifier.process(frame(
            at: 0,
            points: [1: CGPoint(x: 0.4, y: 0.5)]
        )))

        XCTAssertEqual(
            classifier.process(frame(
                at: 0.101,
                points: basePoints(fingers: 3)
            )),
            .rejected(.landingSpreadExceeded)
        )
    }

    func testContactIDReplacementCancelsAndDrainsUntilEmpty() {
        var classifier = TrackpadGestureClassifier()
        let start = basePoints(fingers: 3)
        XCTAssertNil(classifier.process(frame(at: 0, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.07, points: start)))

        var replaced = start
        replaced[3] = nil
        replaced[4] = CGPoint(x: 0.5, y: 0.5)
        XCTAssertEqual(
            classifier.process(frame(at: 0.10, points: replaced)),
            .rejected(.contactSetChanged)
        )
        XCTAssertNil(classifier.process(frame(at: 0.20, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.21, points: [:])))
        XCTAssertNil(classifier.process(frame(at: 0.22, points: start)))
    }

    func testGroupedReleaseOverWindowIsRejected() {
        var classifier = TrackpadGestureClassifier()
        let start = basePoints(fingers: 3)
        XCTAssertNil(classifier.process(frame(at: 0, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.07, points: start)))
        XCTAssertNil(classifier.process(frame(
            at: 0.12,
            points: Dictionary(uniqueKeysWithValues: start.filter { $0.key != 1 })
        )))

        XCTAssertEqual(
            classifier.process(frame(at: 0.241, points: [:])),
            .rejected(.releaseTimedOut)
        )
    }

    func testInvalidFramesAreRejected() {
        var classifier = TrackpadGestureClassifier()
        XCTAssertNil(classifier.process(frame(
            at: 1,
            points: basePoints(fingers: 3)
        )))
        XCTAssertEqual(
            classifier.process(frame(
                at: 0.9,
                points: basePoints(fingers: 3)
            )),
            .rejected(.invalidFrame)
        )

        var duplicateClassifier = TrackpadGestureClassifier()
        XCTAssertEqual(
            duplicateClassifier.process(TrackpadTouchFrame(
                timestamp: 0,
                contacts: [
                    TrackpadTouchContact(
                        id: 1,
                        phase: .moved,
                        position: .zero
                    ),
                    TrackpadTouchContact(
                        id: 1,
                        phase: .moved,
                        position: CGPoint(x: 0.1, y: 0.1)
                    ),
                ]
            )),
            .rejected(.invalidFrame)
        )

        var nanClassifier = TrackpadGestureClassifier()
        XCTAssertEqual(
            nanClassifier.process(frame(
                at: 0,
                points: [1: CGPoint(x: CGFloat.nan, y: 0)]
            )),
            .rejected(.invalidFrame)
        )
    }

    func testMaximumDurationBoundaryIsEnforced() {
        var classifier = TrackpadGestureClassifier()
        let start = basePoints(fingers: 3)
        XCTAssertNil(classifier.process(frame(at: 0, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.07, points: start)))
        XCTAssertEqual(
            classifier.process(frame(at: 2.001, points: start)),
            .rejected(.durationExceeded)
        )

        var endingClassifier = TrackpadGestureClassifier()
        XCTAssertNil(endingClassifier.process(frame(at: 0, points: start)))
        XCTAssertNil(endingClassifier.process(frame(at: 0.07, points: start)))
        XCTAssertNil(endingClassifier.process(frame(
            at: 0.14,
            points: translate(start, by: CGPoint(x: 0.16, y: 0))
        )))
        XCTAssertEqual(
            endingClassifier.process(frame(at: 2.001, points: [:])),
            .rejected(.durationExceeded)
        )
    }

    func testCancelledContactInterruptsAndDrainsSequence() {
        var classifier = TrackpadGestureClassifier()
        let start = basePoints(fingers: 3)
        XCTAssertNil(classifier.process(frame(at: 0, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.07, points: start)))

        XCTAssertEqual(
            classifier.process(TrackpadTouchFrame(
                timestamp: 0.10,
                contacts: start.map {
                    TrackpadTouchContact(
                        id: $0.key,
                        phase: $0.key == 1 ? .cancelled : .moved,
                        position: $0.value
                    )
                }
            )),
            .rejected(.interrupted)
        )
        XCTAssertNil(classifier.process(frame(at: 0.12, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.13, points: [:])))
    }

    func testRecognitionThresholdBoundariesAreInclusive() {
        XCTAssertEqual(
            classify(fingers: 3) {
                translate($0, by: CGPoint(x: 0.12, y: 0))
            },
            .recognized(.swipe(fingers: 3, direction: .right))
        )
        XCTAssertEqual(
            classify(fingers: 2) { scale($0, by: 1.18) },
            .recognized(.pinch(fingers: 2, direction: .outward))
        )
        XCTAssertEqual(
            classify(fingers: 2) { scale($0, by: 0.82) },
            .recognized(.pinch(fingers: 2, direction: .inward))
        )
        XCTAssertEqual(
            classify(fingers: 2) { rotate($0, radians: .pi / 12) },
            .recognized(.rotate(
                fingers: 2,
                direction: .counterclockwise
            ))
        )
    }

    func testNearMissesBelowRecognitionThresholdAreRejected() {
        XCTAssertEqual(
            classify(fingers: 3) {
                translate($0, by: CGPoint(x: 0.119, y: 0))
            },
            .rejected(.unsupported)
        )
        XCTAssertEqual(
            classify(fingers: 2) { scale($0, by: 1.179) },
            .rejected(.unsupported)
        )
        XCTAssertEqual(
            classify(fingers: 2) {
                rotate($0, radians: .pi / 12 - 0.001)
            },
            .rejected(.unsupported)
        )
    }

    func testSwipeAxisRatioBoundaryIsInclusive() {
        XCTAssertEqual(
            classify(fingers: 3) {
                translate($0, by: CGPoint(x: 0.12, y: 0.08))
            },
            .recognized(.swipe(fingers: 3, direction: .right))
        )
        XCTAssertEqual(
            classify(fingers: 3) {
                translate($0, by: CGPoint(x: 0.12, y: 0.081))
            },
            .rejected(.unsupported)
        )
    }

    func testTapDurationAndTravelBoundariesAreInclusive() {
        let start = basePoints(fingers: 3)
        let boundary = translate(start, by: CGPoint(x: 0.025, y: 0))
        var classifier = TrackpadGestureClassifier()
        XCTAssertNil(classifier.process(frame(at: 0, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.07, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.20, points: boundary)))
        XCTAssertEqual(
            classifier.process(frame(at: 0.25, points: [:])),
            .recognized(.tap(fingers: 3))
        )

        var tooLong = TrackpadGestureClassifier()
        XCTAssertNil(tooLong.process(frame(at: 0, points: start)))
        XCTAssertNil(tooLong.process(frame(at: 0.07, points: start)))
        XCTAssertEqual(
            tooLong.process(frame(at: 0.251, points: [:])),
            .rejected(.unsupported)
        )
    }

    func testSequentialLandingAtBoundaryCanFormAValidTap() {
        var classifier = TrackpadGestureClassifier()
        let all = basePoints(fingers: 3)
        XCTAssertNil(classifier.process(frame(
            at: 0,
            points: [1: all[1]!]
        )))
        XCTAssertNil(classifier.process(frame(at: 0.10, points: all)))
        XCTAssertNil(classifier.process(frame(at: 0.16, points: all)))
        XCTAssertEqual(
            classifier.process(frame(at: 0.20, points: [:])),
            .recognized(.tap(fingers: 3))
        )
    }

    func testSequentialLandingDoesNotForgetEarlyFingerTravel() {
        var classifier = TrackpadGestureClassifier()
        let all = basePoints(fingers: 3)
        let movedFirst = CGPoint(
            x: all[1]!.x + 0.026,
            y: all[1]!.y
        )
        XCTAssertNil(classifier.process(frame(
            at: 0,
            points: [1: all[1]!]
        )))
        XCTAssertNil(classifier.process(frame(
            at: 0.04,
            points: [1: movedFirst]
        )))
        var landed = all
        landed[1] = movedFirst
        XCTAssertNil(classifier.process(frame(at: 0.08, points: landed)))
        XCTAssertNil(classifier.process(frame(at: 0.14, points: landed)))
        XCTAssertEqual(
            classifier.process(frame(at: 0.20, points: [:])),
            .rejected(.unsupported)
        )
    }

    func testStableAndFormingTimeoutBoundaries() {
        let points = basePoints(fingers: 3)
        var stable = TrackpadGestureClassifier()
        XCTAssertNil(stable.process(frame(at: 0, points: points)))
        XCTAssertNil(stable.process(frame(at: 0.059, points: points)))
        XCTAssertEqual(
            stable.process(frame(at: 0.10, points: [:])),
            .rejected(.unsupported)
        )

        var stableBoundary = TrackpadGestureClassifier()
        XCTAssertNil(stableBoundary.process(frame(at: 0, points: points)))
        XCTAssertNil(stableBoundary.process(frame(at: 0.060, points: points)))
        XCTAssertEqual(
            stableBoundary.process(frame(at: 0.10, points: [:])),
            .recognized(.tap(fingers: 3))
        )

        let six = basePoints(fingers: 6)
        var formingBoundary = TrackpadGestureClassifier()
        XCTAssertNil(formingBoundary.process(frame(at: 0, points: six)))
        XCTAssertNil(formingBoundary.process(frame(at: 0.180, points: six)))
        XCTAssertEqual(
            formingBoundary.process(frame(at: 0.181, points: six)),
            .rejected(.formingTimedOut)
        )
    }

    func testReleaseWindowBoundaryAndTotalDurationAreEnforced() {
        let start = basePoints(fingers: 3)
        let end = translate(start, by: CGPoint(x: 0.16, y: 0))
        var boundary = TrackpadGestureClassifier()
        XCTAssertNil(boundary.process(frame(at: 0, points: start)))
        XCTAssertNil(boundary.process(frame(at: 0.06, points: start)))
        XCTAssertNil(boundary.process(frame(at: 0.14, points: end)))
        XCTAssertNil(boundary.process(frame(
            at: 0.18,
            points: Dictionary(
                uniqueKeysWithValues: end.filter { $0.key != 1 }
            )
        )))
        XCTAssertEqual(
            boundary.process(frame(at: 0.30, points: [:])),
            .recognized(.swipe(fingers: 3, direction: .right))
        )

        var duration = TrackpadGestureClassifier()
        XCTAssertNil(duration.process(frame(at: 0, points: start)))
        XCTAssertNil(duration.process(frame(at: 0.06, points: start)))
        XCTAssertNil(duration.process(frame(
            at: 1.99,
            points: Dictionary(
                uniqueKeysWithValues: start.filter { $0.key != 1 }
            )
        )))
        XCTAssertEqual(
            duration.process(frame(at: 2.10, points: [:])),
            .rejected(.durationExceeded)
        )
    }

    func testJitterAndFormationIDReplacementAreRejected() {
        let points = basePoints(fingers: 3)
        var jitter = TrackpadGestureClassifier()
        XCTAssertNil(jitter.process(frame(at: 0, points: points)))
        XCTAssertNil(jitter.process(frame(at: 0.06, points: points)))
        XCTAssertNil(jitter.process(frame(
            at: 0.10,
            points: translate(points, by: CGPoint(x: 0.026, y: 0))
        )))
        XCTAssertNil(jitter.process(frame(at: 0.14, points: points)))
        XCTAssertEqual(
            jitter.process(frame(at: 0.20, points: [:])),
            .rejected(.unsupported)
        )

        var replacement = TrackpadGestureClassifier()
        XCTAssertNil(replacement.process(frame(
            at: 0,
            points: [
                1: points[1]!,
                2: points[2]!,
            ]
        )))
        XCTAssertEqual(
            replacement.process(frame(
                at: 0.03,
                points: [
                    1: points[1]!,
                    3: points[3]!,
                ]
            )),
            .rejected(.contactSetChanged)
        )
    }

    func testAddingFingerAfterLockIsRejected() {
        var classifier = TrackpadGestureClassifier()
        let three = basePoints(fingers: 3)
        var four = three
        four[4] = CGPoint(x: 0.5, y: 0.3)
        XCTAssertNil(classifier.process(frame(at: 0, points: three)))
        XCTAssertNil(classifier.process(frame(at: 0.06, points: three)))
        XCTAssertEqual(
            classifier.process(frame(at: 0.10, points: four)),
            .rejected(.contactSetChanged)
        )
    }

    private func classifyTap(fingers: Int) -> TrackpadClassifierEvent? {
        var classifier = TrackpadGestureClassifier()
        let start = basePoints(fingers: fingers)
        XCTAssertNil(classifier.process(frame(at: 0, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.07, points: start)))
        return classifier.process(frame(at: 0.15, points: [:]))
    }

    private func classify(
        fingers: Int,
        transform: ([Int: CGPoint]) -> [Int: CGPoint]
    ) -> TrackpadClassifierEvent? {
        var classifier = TrackpadGestureClassifier()
        let start = basePoints(fingers: fingers)
        XCTAssertNil(classifier.process(frame(at: 0, points: start)))
        XCTAssertNil(classifier.process(frame(at: 0.07, points: start)))
        XCTAssertNil(classifier.process(frame(
            at: 0.14,
            points: transform(start)
        )))
        return classifier.process(frame(at: 0.20, points: [:]))
    }

    private func basePoints(fingers: Int) -> [Int: CGPoint] {
        let radius: CGFloat = 0.12
        return Dictionary(uniqueKeysWithValues: (0..<fingers).map { index in
            let angle = CGFloat(index) * 2 * .pi / CGFloat(fingers)
            return (
                index + 1,
                CGPoint(
                    x: 0.5 + cos(angle) * radius,
                    y: 0.5 + sin(angle) * radius
                )
            )
        })
    }

    private func translate(
        _ points: [Int: CGPoint],
        by delta: CGPoint
    ) -> [Int: CGPoint] {
        points.mapValues {
            CGPoint(x: $0.x + delta.x, y: $0.y + delta.y)
        }
    }

    private func scale(
        _ points: [Int: CGPoint],
        by factor: CGFloat
    ) -> [Int: CGPoint] {
        points.mapValues {
            CGPoint(
                x: 0.5 + ($0.x - 0.5) * factor,
                y: 0.5 + ($0.y - 0.5) * factor
            )
        }
    }

    private func rotate(
        _ points: [Int: CGPoint],
        radians: CGFloat
    ) -> [Int: CGPoint] {
        let c = cos(radians)
        let s = sin(radians)
        return points.mapValues {
            let x = $0.x - 0.5
            let y = $0.y - 0.5
            return CGPoint(
                x: 0.5 + x * c - y * s,
                y: 0.5 + x * s + y * c
            )
        }
    }

    private func frame(
        at timestamp: TimeInterval,
        points: [Int: CGPoint]
    ) -> TrackpadTouchFrame {
        TrackpadTouchFrame(
            timestamp: timestamp,
            contacts: points.map {
                TrackpadTouchContact(
                    id: $0.key,
                    phase: .moved,
                    position: $0.value
                )
            }
        )
    }
}
