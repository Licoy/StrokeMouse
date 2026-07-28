import SwiftUI

private enum GestureEditorInputKind: String, CaseIterable, Identifiable {
    case mouseDraw
    case modifierDraw
    case directTrackpad

    var id: String { rawValue }
    var titleKey: String { "editor.input.\(rawValue)" }
}

private enum DirectGestureCategory: String, CaseIterable, Identifiable {
    case swipe
    case tap
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
    @Binding var pathPoints: [CodablePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(
                L10n.string("editor.inputSource"),
                selection: inputKind
            ) {
                ForEach(GestureEditorInputKind.allCases) { kind in
                    Text(L10n.string(kind.titleKey)).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            switch input {
            case .drawn(let drawn):
                drawnEditor(drawn)
            case .trackpad(let gesture):
                directEditor(gesture)
            }
        }
    }

    @ViewBuilder
    private func drawnEditor(_ drawn: DrawnGesture) -> some View {
        GestureRecorderView(path: $pathPoints)
            .frame(maxHeight: .infinity)

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
    private func directEditor(
        _ gesture: DirectTrackpadGesture
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: gesture.systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity)
            Text(gesture.displaySummary)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )

        Picker(
            L10n.string("editor.direct.category"),
            selection: directCategory
        ) {
            ForEach(DirectGestureCategory.allCases) { category in
                Text(L10n.string(category.titleKey)).tag(category)
            }
        }
        .pickerStyle(.segmented)

        switch gesture {
        case .tap:
            standardFingerPicker
            Picker(
                L10n.string("editor.direct.tapCount"),
                selection: tapCount
            ) {
                ForEach(TapCount.allCases) { count in
                    Text(L10n.string("trackpad.tap.\(count.rawValue)"))
                        .tag(count)
                }
            }
            .pickerStyle(.segmented)
        case .swipe:
            standardFingerPicker
            Picker(
                L10n.string("editor.direct.direction"),
                selection: swipeDirection
            ) {
                ForEach(CardinalDirection.allCases) { direction in
                    Text(L10n.string("trackpad.swipe.\(direction.rawValue)"))
                        .tag(direction)
                }
            }
            .pickerStyle(.segmented)
        case .pinch, .rotate:
            transformFingerPicker
            Picker(
                L10n.string("editor.direct.transformKind"),
                selection: transformKind
            ) {
                ForEach(DirectTransformKind.allCases) { kind in
                    Text(L10n.string(kind.titleKey)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            transformDirectionPicker
        }

        Label(
            L10n.string("trackpad.experimentalWarning"),
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.orange)
    }

    private var standardFingerPicker: some View {
        Picker(
            L10n.string("editor.direct.fingers"),
            selection: standardFingers
        ) {
            ForEach(StandardFingerCount.allCases) { count in
                Text("\(count.rawValue)").tag(count)
            }
        }
        .pickerStyle(.segmented)
    }

    private var transformFingerPicker: some View {
        Picker(
            L10n.string("editor.direct.fingers"),
            selection: transformFingers
        ) {
            ForEach(TransformFingerCount.allCases) { count in
                Text("\(count.rawValue)").tag(count)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var transformDirectionPicker: some View {
        switch input {
        case .trackpad(.pinch):
            Picker(
                L10n.string("editor.direct.direction"),
                selection: pinchDirection
            ) {
                ForEach(PinchDirection.allCases) { direction in
                    Text(L10n.string("trackpad.pinch.\(direction.rawValue)"))
                        .tag(direction)
                }
            }
            .pickerStyle(.segmented)
        case .trackpad(.rotate):
            Picker(
                L10n.string("editor.direct.direction"),
                selection: rotationDirection
            ) {
                ForEach(RotationDirection.allCases) { direction in
                    Text(L10n.string("trackpad.rotate.\(direction.rawValue)"))
                        .tag(direction)
                }
            }
            .pickerStyle(.segmented)
        default:
            EmptyView()
        }
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
                }
            },
            set: { kind in
                switch kind {
                case .mouseDraw:
                    input = .drawn(DrawnGesture(
                        activation: .mouse(.default),
                        points: pathPoints
                    ))
                case .modifierDraw:
                    input = .drawn(DrawnGesture(
                        activation: .modifier(.function),
                        points: pathPoints
                    ))
                case .directTrackpad:
                    input = .trackpad(.swipe(.three, .up))
                }
            }
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
                input = .drawn(DrawnGesture(
                    activation: .mouse(GestureTrigger(button: button)),
                    points: pathPoints
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
                input = .drawn(DrawnGesture(
                    activation: .modifier(key),
                    points: pathPoints
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
                case .pinch, .rotate: return .transform
                }
            },
            set: { category in
                switch category {
                case .swipe: input = .trackpad(.swipe(.three, .up))
                case .tap: input = .trackpad(.tap(.three, .single))
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
                case .tap(let count, _), .swipe(let count, _): return count
                default: return .three
                }
            },
            set: { count in
                guard case .trackpad(let gesture) = input else { return }
                switch gesture {
                case .tap(_, let taps): input = .trackpad(.tap(count, taps))
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
            if case .tap(_, let value) = $0 { return value }
            return nil
        } set: { gesture, value in
            guard case .tap(let fingers, _) = gesture else { return gesture }
            return .tap(fingers, value)
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
