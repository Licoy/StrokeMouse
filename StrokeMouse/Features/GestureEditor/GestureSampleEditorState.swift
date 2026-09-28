import Foundation

struct GestureSampleEditorState: Equatable {
    enum RecordingTarget: Equatable {
        case append
        case replace(Int)
    }

    private(set) var samples: [[CodablePoint]]
    private(set) var selectedIndex: Int?
    private(set) var recordingTarget: RecordingTarget?
    private(set) var pendingPath: [CodablePoint] = []

    init(paths: [[CodablePoint]]) {
        samples = paths.count == 1 && paths[0].isEmpty ? [] : paths
        selectedIndex = samples.isEmpty ? nil : 0
    }

    var canAppend: Bool { samples.count < DrawnGesture.maximumSampleCount }
    var canSave: Bool {
        !samples.isEmpty
            && samples.count <= DrawnGesture.maximumSampleCount
            && samples.allSatisfy { path in
                path.count >= 2
                    && path.allSatisfy { $0.x.isFinite && $0.y.isFinite }
                    && zip(path, path.dropFirst()).contains { lhs, rhs in
                        lhs.x != rhs.x || lhs.y != rhs.y
                    }
            }
    }
    var selectedPath: [CodablePoint]? {
        guard let selectedIndex, samples.indices.contains(selectedIndex) else { return nil }
        return samples[selectedIndex]
    }

    func drawnGesture(
        activation: DrawActivation,
        trackpadModifierKey: GestureModifierKey? = nil
    ) -> DrawnGesture {
        DrawnGesture(
            activation: activation,
            points: samples.first ?? [],
            trackpadModifierKey: trackpadModifierKey,
            additionalPaths: Array(samples.dropFirst())
        )
    }

    mutating func select(_ index: Int) {
        guard samples.indices.contains(index) else { return }
        selectedIndex = index
    }

    mutating func beginAppend() {
        guard canAppend else { return }
        recordingTarget = .append
        pendingPath = []
    }

    mutating func beginReplaceSelected() {
        guard let selectedIndex else { return }
        recordingTarget = .replace(selectedIndex)
        pendingPath = []
    }

    mutating func updatePendingPath(_ path: [CodablePoint]) {
        guard recordingTarget != nil else { return }
        pendingPath = path
    }

    @discardableResult
    mutating func commitRecording() -> Bool {
        guard pendingPath.count >= 2, let recordingTarget else { return false }
        switch recordingTarget {
        case .append:
            guard canAppend else { return false }
            samples.append(pendingPath)
            selectedIndex = samples.count - 1
        case .replace(let index):
            guard samples.indices.contains(index) else { return false }
            samples[index] = pendingPath
            selectedIndex = index
        }
        cancelRecording()
        return true
    }

    mutating func cancelRecording() {
        recordingTarget = nil
        pendingPath = []
    }

    mutating func deleteSelected() {
        guard let selectedIndex, samples.indices.contains(selectedIndex) else { return }
        samples.remove(at: selectedIndex)
        self.selectedIndex = samples.isEmpty ? nil : min(selectedIndex, samples.count - 1)
    }

    mutating func promoteSelected() {
        guard let selectedIndex, selectedIndex > 0 else { return }
        let selected = samples.remove(at: selectedIndex)
        samples.insert(selected, at: 0)
        self.selectedIndex = 0
    }
}
