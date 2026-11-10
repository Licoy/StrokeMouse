import SwiftUI

struct WindowLayoutEditor: View {
    @Binding var layout: WindowLayout

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.secondary.opacity(0.12))
                    if layout.isValid {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2))
                            .frame(width: proxy.size.width * layout.width / 100,
                                   height: proxy.size.height * layout.height / 100)
                            .offset(x: proxy.size.width * layout.x / 100,
                                    y: proxy.size.height * layout.y / 100)
                    }
                }
            }
            .frame(height: 160)
            .accessibilityLabel(L10n.string("window.layoutPreview"))

            Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    field("X", value: $layout.x)
                    field(L10n.string("window.layoutWidth"), value: $layout.width)
                }
                GridRow {
                    field("Y", value: $layout.y)
                    field(L10n.string("window.layoutHeight"), value: $layout.height)
                }
            }
            HStack {
                preset("window.leftHalf", WindowLayout(x: 0, y: 0, width: 50, height: 100))
                preset("window.rightHalf", WindowLayout(x: 50, y: 0, width: 50, height: 100))
                preset("window.center80", WindowLayout())
            }
            Text(L10n.string(layout.isValid ? "window.layoutHint" : "window.error.invalidLayout"))
                .font(.caption)
                .foregroundStyle(layout.isValid ? Color.secondary : Color.red)
        }
        .padding(.vertical, 8)
    }

    private func field(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 68)
                .accessibilityLabel(title)
            Text("%")
        }
    }

    private func preset(_ key: String, _ value: WindowLayout) -> some View {
        Button(L10n.string(key)) { layout = value }
            .buttonStyle(.bordered)
    }
}
