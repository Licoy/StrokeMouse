import AppKit
import SwiftUI

// MARK: - Language

enum ScriptLanguage: Equatable, Sendable {
    case shell
    case appleScript
}

// MARK: - Token kinds (for tests / mapping to colors)

enum ScriptTokenKind: Equatable, Sendable {
    case keyword
    case string
    case comment
}

struct ScriptToken: Equatable, Sendable {
    let range: NSRange
    let kind: ScriptTokenKind
}

// MARK: - Highlighter (pure)

enum ScriptSyntaxHighlighter {
    static func tokens(in text: String, language: ScriptLanguage) -> [ScriptToken] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        var occupied = [Bool](repeating: false, count: ns.length)
        var result: [ScriptToken] = []

        func mark(_ range: NSRange, kind: ScriptTokenKind) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            let end = min(range.location + range.length, ns.length)
            let start = max(0, range.location)
            guard start < end else { return }
            for i in start..<end {
                if occupied[i] { return }
            }
            for i in start..<end {
                occupied[i] = true
            }
            result.append(ScriptToken(range: NSRange(location: start, length: end - start), kind: kind))
        }

        // Comments first (highest priority over strings/keywords in those spans).
        switch language {
        case .shell:
            enumerateMatches(#"(?m)#.*$"#, in: ns, range: full) { mark($0, kind: .comment) }
        case .appleScript:
            enumerateMatches(#"(?m)--.*$"#, in: ns, range: full) { mark($0, kind: .comment) }
            enumerateMatches(#"\(\*[\s\S]*?\*\)"#, in: ns, range: full) { mark($0, kind: .comment) }
        }

        // Strings: double then single (simple escapes).
        enumerateMatches(#""(?:\\.|[^"\\])*""#, in: ns, range: full) { mark($0, kind: .string) }
        enumerateMatches(#"'(?:\\.|[^'\\])*'"#, in: ns, range: full) { mark($0, kind: .string) }

        // Keywords on remaining spans.
        let keywords = keywordSet(for: language)
        let wordPattern = #"\b[A-Za-z_][A-Za-z0-9_]*\b"#
        enumerateMatches(wordPattern, in: ns, range: full) { range in
            let word = ns.substring(with: range)
            let key = language == .appleScript ? word.lowercased() : word
            if keywords.contains(key) {
                mark(range, kind: .keyword)
            }
        }

        return result.sorted { $0.range.location < $1.range.location }
    }

    /// Applies base style + token colors into `storage`. Caller should preserve selection.
    static func applyHighlighting(
        to storage: NSTextStorage,
        language: ScriptLanguage,
        font: NSFont
    ) {
        let text = storage.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        guard full.length > 0 else { return }

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes(
            [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ],
            range: full
        )

        for token in tokens(in: text, language: language) {
            storage.addAttributes(
                [
                    .font: font,
                    .foregroundColor: color(for: token.kind),
                ],
                range: token.range
            )
        }
    }

    static func color(for kind: ScriptTokenKind) -> NSColor {
        switch kind {
        case .keyword:
            return NSColor.systemPurple
        case .string:
            return NSColor.systemRed
        case .comment:
            return NSColor.secondaryLabelColor
        }
    }

    private static func keywordSet(for language: ScriptLanguage) -> Set<String> {
        switch language {
        case .shell:
            return [
                "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
                "case", "esac", "in", "function", "return", "export", "local", "readonly",
                "echo", "printf", "cd", "exit", "shift", "break", "continue", "select",
                "time", "coproc", "declare", "typeset", "unset", "true", "false",
                "source", "alias", "unalias", "wait", "trap", "eval", "exec", "set",
                "test", "read", "mapfile", "getopts",
            ]
        case .appleScript:
            // Matched case-insensitively via lowercased lookup.
            return [
                "tell", "end", "set", "to", "of", "if", "then", "else",
                "on", "repeat", "return", "with", "without", "display", "notification",
                "dialog", "button", "buttons", "default", "answer", "as", "the", "my",
                "its", "and", "or", "not", "is", "are", "equal", "equals", "contains",
                "begin", "considering", "ignoring", "error", "try", "from", "into",
                "given", "by", "whose", "where", "through", "thru", "every",
                "some", "first", "last", "front", "back", "middle", "named", "id",
                "property", "script", "using", "terms", "application",
                "process", "system", "events", "finder", "activate", "open", "close",
                "count", "copy", "get", "make", "new", "delete", "move", "save",
                "true", "false", "missing", "value", "null", "me", "it",
            ]
        }
    }

    private static func enumerateMatches(
        _ pattern: String,
        in ns: NSString,
        range: NSRange,
        body: (NSRange) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        regex.enumerateMatches(in: ns as String, options: [], range: range) { match, _, _ in
            guard let match else { return }
            body(match.range)
        }
    }
}

// MARK: - SwiftUI text area

/// Scrollable monospaced code editor with light syntax highlighting.
struct ScriptTextArea: View {
    @Binding var text: String
    var language: ScriptLanguage
    var minHeight: CGFloat = 100
    var placeholder: String = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScriptCodeTextView(text: $text, language: language)
                .frame(minHeight: minHeight, maxHeight: .infinity)

            if text.isEmpty, !placeholder.isEmpty {
                Text(placeholder)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - NSTextView bridge

private struct ScriptCodeTextView: NSViewRepresentable {
    @Binding var text: String
    var language: ScriptLanguage

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, language: language)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let textView = ScriptNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFindBar = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.font = context.coordinator.font
        textView.string = text
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applyHighlighting()
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.language = language
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let selected = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selected
            context.coordinator.applyHighlighting()
        } else if context.coordinator.lastLanguage != language {
            context.coordinator.applyHighlighting()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var language: ScriptLanguage
        var lastLanguage: ScriptLanguage
        weak var textView: NSTextView?
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        init(text: Binding<String>, language: ScriptLanguage) {
            self.text = text
            self.language = language
            self.lastLanguage = language
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let value = textView.string
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
            applyHighlighting()
        }

        func applyHighlighting() {
            guard let textView, let storage = textView.textStorage else { return }
            let selected = textView.selectedRanges
            ScriptSyntaxHighlighter.applyHighlighting(to: storage, language: language, font: font)
            textView.selectedRanges = selected
            lastLanguage = language
        }
    }
}

private final class ScriptNSTextView: NSTextView {}
