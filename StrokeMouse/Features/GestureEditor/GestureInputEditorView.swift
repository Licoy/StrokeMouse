import SwiftUI

private enum GestureEditorInputKind: String, CaseIterable, Identifiable {
    case mouseDraw
    case mouseButton
    case mouseCombination
    case modifierDraw
    case directTrackpad

    var id: String { rawValue }
    var titleKey: String { "editor.input.\(rawValue)" }
}

private enum DirectGestureCategory: String, CaseIterable, Identifiable {
    case swipe
    case tap
    /// Physically presses the trackpad; a tap only touches it.
    case click
    case transform

    var id: String { rawValue }
    var titleKey: String { "editor.direct.category.\(rawValue)" }
}

private enum DirectTransformKind: String, CaseIterable, Identifiable {
    case pinch
    case rotate

    var id: String { rawValue }
    var titleKey: String { "editor.direct.transform.\(rawValue)" }
}

struct GestureInputEditorView: View {
    @Binding var input: GestureInput
    @Binding var sampleState: GestureSampleEditorState

    /// Shared label column so option controls share one left edge.
    private let directLabelColumnWidth: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputSourceControl

            switch input {
            case .drawn(let drawn):
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        drawnEditor(drawn)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
                }
            case .trackpad(let gesture):
                directEditor(gesture)
            case .mouseButton:
                mouseButtonEditor
            case .mouseCombination:
                MouseCombinationEditor(gesture: combinationGesture)
            }
        }
    }

    private var inputSourceControl: some View {
        AdaptiveSegmentedPicker(
            L10n.string("editor.inputSource"),
            selection: inputKind
        ) {
            ForEach(GestureEditorInputKind.allCases) { kind in
                Text(L10n.string(kind.titleKey)).tag(kind)
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func drawnEditor(_ drawn: DrawnGesture) -> some View {
        GestureSampleEditorView(state: $sampleState)

        switch drawn.activation {
        case .mouse:
            Picker(
                L10n.string("editor.trigger"),
                selection: mouseButton
            ) {
                ForEach(MouseTriggerButton.allCases) { button in
                    Text(L10n.string(button.displayKey)).tag(button)
                }
            }
            Text(L10n.string("editor.triggerPerGestureHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(
                L10n.string("editor.trackpadModifierSupport"),
                isOn: trackpadModifierSupport
            )
            if drawn.trackpadModifierKey != nil {
                Picker(
                    L10n.string("editor.trackpadModifierKey"),
                    selection: trackpadModifierKey
                ) {
                    ForEach(GestureModifierKey.allCases) { key in
                        Text(L10n.string(key.displayKey)).tag(key)
                    }
                }
                Text(L10n.string("editor.trackpadModifierHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .modifier:
            Picker(
                L10n.string("editor.modifierKey"),
                selection: modifierKey
            ) {
                ForEach(GestureModifierKey.allCases) { key in
                    Text(L10n.string(key.displayKey)).tag(key)
                }
            }
            Text(L10n.string("editor.modifierDrawHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var mouseButtonEditor: some View {
        inputCard

        Picker(
            L10n.string("editor.trigger"),
            selection: mappedGesture.button
        ) {
            ForEach(MouseButtonGesture.supportedButtons) { button in
                Text(L10n.string(button.displayKey)).tag(button)
            }
        }
        Text(L10n.string("editor.mouseButtonHint"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Toggle(
            L10n.string("editor.mouseButtonModifierSupport"),
            isOn: mappedModifierSupport
        )
        if mappedModifierSupport.wrappedValue {
            Picker(
                L10n.string("editor.modifierKey"),
                selection: mappedModifier
            ) {
                ForEach(GestureModifierKey.allCases) { key in
                    Text(L10n.string(key.displayKey)).tag(key)
                }
            }
        }
        Text(L10n.string("editor.mouseButtonModifierHint"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var inputCard: some View {
        VStack(spacing: 16) {
            Image(systemName: input.systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity)
            Text(input.displaySummary)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private func directEditor(
        _ gesture: DirectTrackpadGesture
    ) -> some View {
        inputCard

        VStack(alignment: .leading, spacing: 10) {
            labeledSegmentedPicker(
                title: L10n.string("editor.direct.category"),
                selection: directCategory
            ) {
                ForEach(DirectGestureCategory.allCases) { category in
                    Text(L10n.string(category.titleKey)).tag(category)
                }
            }

            switch gesture {
            case .tap, .click:
                let family = if case .click = gesture { "click" } else { "tap" }
                standardFingerPicker
                labeledSegmentedPicker(
                    title: L10n.string("editor.direct.tapCount"),
                    selection: tapCount
                ) {
                    ForEach(TapCount.allCases) { count in
                        Text(L10n.string(
                            "trackpad.\(family).\(count.rawValue)"
                        ))
                        .tag(count)
                    }
                }
                if case .click = gesture {
                    Text(L10n.string("editor.direct.clickHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, directLabelColumnWidth + 12)
                }
            case .swipe:
                standardFingerPicker
                labeledSegmentedPicker(
                    title: L10n.string("editor.direct.direction"),
                    selection: swipeDirection
                ) {
                    ForEach(CardinalDirection.allCases) { direction in
                        Text(L10n.string("trackpad.swipe.\(direction.rawValue)"))
                            .tag(direction)
                    }
                }
            case .pinch, .rotate:
                transformFingerPicker
                labeledSegmentedPicker(
                    title: L10n.string("editor.direct.transformKind"),
                    selection: transformKind
                ) {
                    ForEach(DirectTransformKind.allCases) { kind in
                        Text(L10n.string(kind.titleKey)).tag(kind)
                    }
                }
                transformDirectionPicker
            }
        }

        Label(
            L10n.string("trackpad.experimentalWarning"),
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var standardFingerPicker: some View {
        labeledSegmentedPicker(
            title: L10n.string("editor.direct.fingers"),
            selection: standardFingers
        ) {
            ForEach(StandardFingerCount.allCases) { count in
                Text("\(count.rawValue)").tag(count)
            }
        }
    }

    private var transformFingerPicker: some View {
        labeledSegmentedPicker(
            title: L10n.string("editor.direct.fingers"),
            selection: transformFingers
        ) {
            ForEach(TransformFingerCount.allCases) { count in
                Text("\(count.rawValue)").tag(count)
            }
        }
    }

    @ViewBuilder
    private var transformDirectionPicker: some View {
        switch input {
        case .trackpad(.pinch):
            labeledSegmentedPicker(
                title: L10n.string("editor.direct.direction"),
                selection: pinchDirection
            ) {
                ForEach(PinchDirection.allCases) { direction in
                    Text(L10n.string("trackpad.pinch.\(direction.rawValue)"))
                        .tag(direction)
                }
            }
        case .trackpad(.rotate):
            labeledSegmentedPicker(
                title: L10n.string("editor.direct.direction"),
                selection: rotationDirection
            ) {
                ForEach(RotationDirection.allCases) { direction in
                    Text(L10n.string("trackpad.rotate.\(direction.rawValue)"))
                        .tag(direction)
                }
            }
        default:
            EmptyView()
        }
    }

    private func labeledSegmentedPicker<SelectionValue: Hashable, Content: View>(
        title: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: directLabelColumnWidth, alignment: .leading)
            AdaptiveSegmentedPicker(title, selection: selection) {
                content()
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputKind: Binding<GestureEditorInputKind> {
        Binding(
            get: {
                switch input {
                case .drawn(let drawn):
                    if case .mouse = drawn.activation { return .mouseDraw }
                    return .modifierDraw
                case .trackpad:
                    return .directTrackpad
                case .mouseButton:
                    return .mouseButton
                case .mouseCombination:
                    return .mouseCombination
                }
            },
            set: { kind in
                switch kind {
                case .mouseDraw:
                    input = .drawn(sampleState.drawnGesture(
                        activation: .mouse(.default),
                        trackpadModifierKey: nil
                    ))
                case .modifierDraw:
                    input = .drawn(sampleState.drawnGesture(
                        activation: .modifier(.function)
                    ))
                case .mouseCombination:
                    input = .mouseCombination(MouseCombinationGesture())
                case .mouseButton:
                    input = .mouseButton(MouseButtonGesture(button: .sideBack))
                case .directTrackpad:
                    input = .trackpad(.swipe(.three, .up))
                }
            }
        )
    }

    private var combinationGesture: Binding<MouseCombinationGesture> {
        Binding(get: {
            if case .mouseCombination(let gesture) = input { return gesture }
            return MouseCombinationGesture()
        }, set: { input = .mouseCombination($0) })
    }

    private var mappedGesture: Binding<MouseButtonGesture> {
        Binding(
            get: {
                guard case .mouseButton(let gesture) = input else {
                    return MouseButtonGesture(button: .sideBack)
                }
                return gesture
            },
            set: { input = .mouseButton($0) }
        )
    }

    private var mappedModifierSupport: Binding<Bool> {
        Binding(
            get: { mappedGesture.wrappedValue.modifier != nil },
            set: { mappedGesture.wrappedValue.modifier = $0 ? .command : nil }
        )
    }

    private var mappedModifier: Binding<GestureModifierKey> {
        Binding(
            get: { mappedGesture.wrappedValue.modifier ?? .command },
            set: { mappedGesture.wrappedValue.modifier = $0 }
        )
    }

    private var mouseButton: Binding<MouseTriggerButton> {
        Binding(
            get: {
                guard case .drawn(let drawn) = input,
                      case .mouse(let trigger) = drawn.activation
                else { return .right }
                return trigger.button
            },
            set: { button in
                guard case .drawn(let drawn) = input else { return }
                input = .drawn(sampleState.drawnGesture(
                    activation: .mouse(GestureTrigger(button: button)),
                    trackpadModifierKey: drawn.trackpadModifierKey
                ))
            }
        )
    }

    private var trackpadModifierSupport: Binding<Bool> {
        Binding(
            get: {
                guard case .drawn(let drawn) = input,
                      case .mouse = drawn.activation
                else { return false }
                return drawn.trackpadModifierKey != nil
            },
            set: { isEnabled in
                guard case .drawn(let drawn) = input,
                      case .mouse(let trigger) = drawn.activation
                else { return }
                input = .drawn(sampleState.drawnGesture(
                    activation: .mouse(trigger),
                    trackpadModifierKey: isEnabled
                        ? (drawn.trackpadModifierKey ?? .function)
                        : nil
                ))
            }
        )
    }

    private var trackpadModifierKey: Binding<GestureModifierKey> {
        Binding(
            get: {
                guard case .drawn(let drawn) = input,
                      case .mouse = drawn.activation
                else { return .function }
                return drawn.trackpadModifierKey ?? .function
            },
            set: { key in
                guard case .drawn(let drawn) = input,
                      case .mouse(let trigger) = drawn.activation
                else { return }
                input = .drawn(sampleState.drawnGesture(
                    activation: .mouse(trigger),
                    trackpadModifierKey: key
                ))
            }
        )
    }

    private var modifierKey: Binding<GestureModifierKey> {
        Binding(
            get: {
                guard case .drawn(let drawn) = input,
                      case .modifier(let key) = drawn.activation
                else { return .function }
                return key
            },
            set: { key in
                input = .drawn(sampleState.drawnGesture(
                    activation: .modifier(key)
                ))
            }
        )
    }

    private var directCategory: Binding<DirectGestureCategory> {
        Binding(
            get: {
                guard case .trackpad(let gesture) = input else {
                    return .swipe
                }
                switch gesture {
                case .swipe: return .swipe
                case .tap: return .tap
                case .click: return .click
                case .pinch, .rotate: return .transform
                }
            },
            set: { category in
                switch category {
                case .swipe: input = .trackpad(.swipe(.three, .up))
                case .tap: input = .trackpad(.tap(.three, .single))
                case .click: input = .trackpad(.click(.three, .single))
                case .transform: input = .trackpad(.pinch(.two, .outward))
                }
            }
        )
    }

    private var standardFingers: Binding<StandardFingerCount> {
        Binding(
            get: {
                guard case .trackpad(let gesture) = input else {
                    return .three
                }
                switch gesture {
                case .tap(let count, _), .click(let count, _),
                     .swipe(let count, _):
                    return count
                default: return .three
                }
            },
            set: { count in
                guard case .trackpad(let gesture) = input else { return }
                switch gesture {
                case .tap(_, let taps): input = .trackpad(.tap(count, taps))
                case .click(_, let clicks):
                    input = .trackpad(.click(count, clicks))
                case .swipe(_, let direction):
                    input = .trackpad(.swipe(count, direction))
                default: break
                }
            }
        )
    }

    private var transformFingers: Binding<TransformFingerCount> {
        Binding(
            get: {
                guard case .trackpad(let gesture) = input else { return .two }
                switch gesture {
                case .pinch(let count, _), .rotate(let count, _): return count
                default: return .two
                }
            },
            set: { count in
                guard case .trackpad(let gesture) = input else { return }
                switch gesture {
                case .pinch(_, let direction):
                    input = .trackpad(.pinch(count, direction))
                case .rotate(_, let direction):
                    input = .trackpad(.rotate(count, direction))
                default: break
                }
            }
        )
    }

    private var tapCount: Binding<TapCount> {
        directBinding(default: .single) {
            switch $0 {
            case .tap(_, let value), .click(_, let value): return value
            default: return nil
            }
        } set: { gesture, value in
            switch gesture {
            case .tap(let fingers, _): return .tap(fingers, value)
            case .click(let fingers, _): return .click(fingers, value)
            default: return gesture
            }
        }
    }

    private var swipeDirection: Binding<CardinalDirection> {
        directBinding(default: .up) {
            if case .swipe(_, let value) = $0 { return value }
            return nil
        } set: { gesture, value in
            guard case .swipe(let fingers, _) = gesture else { return gesture }
            return .swipe(fingers, value)
        }
    }

    private var pinchDirection: Binding<PinchDirection> {
        directBinding(default: .outward) {
            if case .pinch(_, let value) = $0 { return value }
            return nil
        } set: { gesture, value in
            guard case .pinch(let fingers, _) = gesture else { return gesture }
            return .pinch(fingers, value)
        }
    }

    private var rotationDirection: Binding<RotationDirection> {
        directBinding(default: .clockwise) {
            if case .rotate(_, let value) = $0 { return value }
            return nil
        } set: { gesture, value in
            guard case .rotate(let fingers, _) = gesture else { return gesture }
            return .rotate(fingers, value)
        }
    }

    private var transformKind: Binding<DirectTransformKind> {
        Binding(
            get: {
                guard case .trackpad(let gesture) = input else { return .pinch }
                if case .rotate = gesture { return .rotate }
                return .pinch
            },
            set: { kind in
                let fingers = transformFingers.wrappedValue
                switch kind {
                case .pinch: input = .trackpad(.pinch(fingers, .outward))
                case .rotate: input = .trackpad(.rotate(fingers, .clockwise))
                }
            }
        )
    }

    private func directBinding<Value>(
        default defaultValue: Value,
        get: @escaping (DirectTrackpadGesture) -> Value?,
        set: @escaping (
            DirectTrackpadGesture,
            Value
        ) -> DirectTrackpadGesture
    ) -> Binding<Value> {
        Binding(
            get: {
                guard case .trackpad(let gesture) = input else {
                    return defaultValue
                }
                return get(gesture) ?? defaultValue
            },
            set: { value in
                guard case .trackpad(let gesture) = input else { return }
                input = .trackpad(set(gesture, value))
            }
        )
    }

}


private struct MouseCombinationEditor: View {
    @Binding var gesture: MouseCombinationGesture

    var body: some View {
        Form {
            Section {
                Picker(L10n.string("combination.mode"), selection: edgeMode) {
                    Text(L10n.string("combination.mode.held")).tag(false)
                    Text(L10n.string("combination.mode.edge")).tag(true)
                }
                if gesture.edge != nil {
                    Picker(L10n.string("combination.edge"), selection: edge) {
                        ForEach(MouseScreenEdge.allCases) { edge in
                            Text(L10n.string(edge.displayKey)).tag(edge)
                        }
                    }
                }
                Picker(L10n.string("combination.action"), selection: $gesture.action) {
                    ForEach(MouseCombinationAction.allCases.filter {
                        gesture.edge == nil ? $0 != .rightClick : $0 != .leftClick && $0 != .dragScroll
                    }) { action in
                        Text(L10n.string(action.displayKey)).tag(action)
                    }
                }
            }
            if gesture.action == .dragScroll {
                Section {
                    HStack {
                        Text(L10n.string("dragScroll.sensitivity"))
                        Slider(value: dragConfiguration.sensitivity,
                               in: MouseDragScrollConfiguration.sensitivityRange) {
                            Text(L10n.string("dragScroll.sensitivity"))
                        }
                        .labelsHidden()
                        Text(gesture.resolvedDragScrollConfiguration.sensitivity, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                    Toggle(L10n.string("dragScroll.reversesDirection"),
                           isOn: dragConfiguration.reversesDirection)
                    Text(L10n.string("dragScroll.hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Label(gesture.displaySummary, systemImage: "computermouse.fill")
                    .font(.headline)
                Text(L10n.string(gesture.action == .dragScroll ? "editor.dragScrollTestHint" : (gesture.edge == nil ? "combination.hint.held" : "combination.hint.edge")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var dragConfiguration: Binding<MouseDragScrollConfiguration> {
        Binding(get: { gesture.resolvedDragScrollConfiguration },
                set: { gesture.dragScroll = $0 })
    }

    private var edgeMode: Binding<Bool> {
        Binding(get: { gesture.edge != nil }, set: { enabled in
            gesture.edge = enabled ? .top : nil
            if !gesture.isValid { gesture.action = .wheelUp }
        })
    }
    private var edge: Binding<MouseScreenEdge> {
        Binding(get: { gesture.edge ?? .top }, set: { gesture.edge = $0 })
    }
}
