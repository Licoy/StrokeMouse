import SwiftUI

/// Segmented picker that turns into a pop-up menu when its options do not fit.
///
/// A segmented control sizes every segment to the widest title and never
/// compresses, so a long localization would push a fixed-width pane, form row
/// or window past its edges instead of truncating.
struct AdaptiveSegmentedPicker<SelectionValue: Hashable, Content: View>: View {
    private let title: String
    @Binding private var selection: SelectionValue
    private let compactMenu: Bool
    private let formRow: Bool
    private let content: Content

    /// `compactMenu` keeps the fallback menu at its own width; otherwise it
    /// stretches like any pop-up button, e.g. to fill a form row.
    ///
    /// `formRow` is for a titled row in a grouped `Form`: the form's labeled-row
    /// layout reports a segmented control narrower than it draws, so the title
    /// is laid out here and only the bare control is measured.
    init(
        _ title: String,
        selection: Binding<SelectionValue>,
        compactMenu: Bool = false,
        formRow: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _selection = selection
        self.compactMenu = compactMenu
        self.formRow = formRow
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if formRow {
                HStack(spacing: 8) {
                    Text(title)
                    Spacer(minLength: 0)
                    segmented
                        .labelsHidden()
                }
            } else {
                segmented
            }

            Picker(title, selection: $selection) {
                content
            }
            .pickerStyle(.menu)
            .fixedSize(horizontal: compactMenu, vertical: false)
        }
    }

    private var segmented: some View {
        Picker(title, selection: $selection) {
            content
        }
        .pickerStyle(.segmented)
    }
}
