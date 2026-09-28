import AppKit
import SwiftUI
import XCTest
@testable import StrokeMouse

final class GestureSampleEditorStateTests: XCTestCase {
    override func tearDown() {
        L10n.apply(.system)
        super.tearDown()
    }

    func testAppendKeepsExistingSamplesAndSelectsNewSample() {
        let first = path(0)
        let second = path(10)
        var state = GestureSampleEditorState(paths: [first])

        state.beginAppend()
        state.updatePendingPath(second)
        XCTAssertTrue(state.commitRecording())

        XCTAssertEqual(state.samples, [first, second])
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testCancelRerecordKeepsExistingSample() {
        let original = path(0)
        var state = GestureSampleEditorState(paths: [original])

        state.beginReplaceSelected()
        state.updatePendingPath(path(20))
        state.cancelRecording()

        XCTAssertEqual(state.samples, [original])
        XCTAssertNil(state.recordingTarget)
        XCTAssertTrue(state.pendingPath.isEmpty)
    }

    func testCommittedRerecordOnlyReplacesSelectedSample() {
        let first = path(0)
        let second = path(10)
        let replacement = path(20)
        var state = GestureSampleEditorState(paths: [first, second])

        state.select(1)
        state.beginReplaceSelected()
        state.updatePendingPath(replacement)
        XCTAssertTrue(state.commitRecording())

        XCTAssertEqual(state.samples, [first, replacement])
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testDeletingPrimaryPromotesNextSample() {
        let first = path(0)
        let second = path(10)
        var state = GestureSampleEditorState(paths: [first, second])

        state.deleteSelected()

        XCTAssertEqual(state.samples, [second])
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func testPromoteMovesSelectedSampleToPrimary() {
        let first = path(0)
        let second = path(10)
        let third = path(20)
        var state = GestureSampleEditorState(paths: [first, second, third])

        state.select(2)
        state.promoteSelected()

        XCTAssertEqual(state.samples, [third, first, second])
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func testAppendStopsAtMaximumSampleCount() {
        var state = GestureSampleEditorState(
            paths: (0..<DrawnGesture.maximumSampleCount).map { path(Double($0)) }
        )

        state.beginAppend()

        XCTAssertFalse(state.canAppend)
        XCTAssertNil(state.recordingTarget)
    }

    func testDeletingLastSampleAllowsEmptyDraft() {
        var state = GestureSampleEditorState(paths: [path(0)])

        state.deleteSelected()

        XCTAssertTrue(state.samples.isEmpty)
        XCTAssertNil(state.selectedIndex)
    }

    func testNewEmptyGestureRecordsFirstSampleAndBecomesSavable() {
        let newGesture = DrawnGesture(activation: .mouse(.default), points: [])
        var state = GestureSampleEditorState(paths: newGesture.allPaths)

        XCTAssertTrue(state.samples.isEmpty)
        XCTAssertFalse(state.canSave)

        state.beginAppend()
        state.updatePendingPath(path(10))
        XCTAssertTrue(state.commitRecording())

        XCTAssertTrue(state.canSave)
        XCTAssertEqual(
            state.drawnGesture(activation: newGesture.activation).allPaths,
            [path(10)]
        )
    }

    func testMouseAndModifierGesturesKeepEverySample() {
        let paths = [path(0), path(10), path(20)]
        let state = GestureSampleEditorState(paths: paths)

        let mouse = state.drawnGesture(
            activation: .mouse(.default),
            trackpadModifierKey: .function
        )
        let modifier = state.drawnGesture(activation: .modifier(.option))

        XCTAssertEqual(mouse.allPaths, paths)
        XCTAssertEqual(modifier.allPaths, paths)
    }

    func testEditingDraftDoesNotMutateSourceGestureUntilSaved() {
        let source = DrawnGesture(activation: .mouse(.default), points: path(0))
        var state = GestureSampleEditorState(paths: source.allPaths)

        state.beginAppend()
        state.updatePendingPath(path(10))
        XCTAssertTrue(state.commitRecording())

        XCTAssertEqual(source.allPaths, [path(0)])
        XCTAssertEqual(state.samples, [path(0), path(10)])
    }

    private func path(_ offset: Double) -> [CodablePoint] {
        [
            CodablePoint(x: offset, y: offset),
            CodablePoint(x: offset + 1, y: offset + 2),
        ]
    }

    @MainActor
    func testRenderSampleEditorVisualFixtures() throws {
        guard ProcessInfo.processInfo.environment["STROKEMOUSE_RENDER_SAMPLE_EDITOR"] == "1" else {
            throw XCTSkip("Set STROKEMOUSE_RENDER_SAMPLE_EDITOR=1 to render visual fixtures")
        }

        let samples = (0..<DrawnGesture.maximumSampleCount).map(samplePath)
        let fixtures: [(String, LanguageOverride, [[CodablePoint]])] = [
            ("en-1", .english, [samples[0]]),
            ("en-5", .english, samples),
            ("zh-Hans-1", .simplifiedChinese, [samples[0]]),
            ("zh-Hans-5", .simplifiedChinese, samples),
        ]

        for (name, language, paths) in fixtures {
            L10n.apply(language)
            let state = GestureSampleEditorState(paths: paths)
            let sampleURL = URL(fileURLWithPath: "/tmp/strokemouse-samples-\(name).png")
            try render(
                GestureSampleEditorView(state: .constant(state))
                    .frame(width: 340, height: 430, alignment: .top),
                size: CGSize(width: 372, height: 462),
                padding: 16,
                to: sampleURL
            )

            let inputURL = URL(fileURLWithPath: "/tmp/strokemouse-input-\(name).png")
            let drawn = state.drawnGesture(
                activation: .mouse(.default),
                trackpadModifierKey: .function
            )
            try render(
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.string("editor.pattern"))
                        .font(.headline)
                    GestureInputEditorView(
                        input: .constant(.drawn(drawn)),
                        sampleState: .constant(state)
                    )
                }
                .frame(width: 308, height: 495, alignment: .top),
                size: CGSize(width: 340, height: 527),
                padding: 16,
                to: inputURL
            )

            XCTAssertTrue(FileManager.default.fileExists(atPath: sampleURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: inputURL.path))
        }
    }

    @MainActor
    private func render<Content: View>(
        _ content: Content,
        size: CGSize,
        padding: CGFloat,
        to outputURL: URL
    ) throws {
        let root = content
            .padding(padding)
            .background(Color(nsColor: .windowBackgroundColor))
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Could not create bitmap for \(outputURL.lastPathComponent)")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode \(outputURL.lastPathComponent)")
            return
        }
        try png.write(to: outputURL, options: .atomic)
    }

    private func samplePath(_ index: Int) -> [CodablePoint] {
        (0..<24).map { step in
            let t = Double(step) / 23
            let phase = Double(index) * 0.45
            return CodablePoint(
                x: t,
                y: 0.5 + sin(t * .pi * (1.5 + Double(index) * 0.2) + phase) * 0.36
            )
        }
    }
}
