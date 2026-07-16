import XCTest
@testable import StrokeMouse

final class ScriptSyntaxHighlighterTests: XCTestCase {
    func testShellHighlightsCommentStringAndKeyword() {
        let text = """
        # greeting
        echo "hi"
        """
        let tokens = ScriptSyntaxHighlighter.tokens(in: text, language: .shell)
        let kinds = tokens.map(\.kind)
        XCTAssertTrue(kinds.contains(.comment))
        XCTAssertTrue(kinds.contains(.string))
        XCTAssertTrue(kinds.contains(.keyword))

        let ns = text as NSString
        let comment = tokens.first { $0.kind == .comment }
        XCTAssertEqual(ns.substring(with: comment!.range), "# greeting")

        let string = tokens.first { $0.kind == .string }
        XCTAssertEqual(ns.substring(with: string!.range), "\"hi\"")

        let keyword = tokens.first { $0.kind == .keyword }
        XCTAssertEqual(ns.substring(with: keyword!.range), "echo")
    }

    func testShellDoesNotHighlightKeywordInsideString() {
        let text = #"echo "if then else""#
        let tokens = ScriptSyntaxHighlighter.tokens(in: text, language: .shell)
        let keywords = tokens.filter { $0.kind == .keyword }
        XCTAssertEqual(keywords.count, 1)
        XCTAssertEqual((text as NSString).substring(with: keywords[0].range), "echo")
    }

    func testAppleScriptHighlightsTellAndLineComment() {
        let text = """
        -- notify
        tell application "Finder" to activate
        """
        let tokens = ScriptSyntaxHighlighter.tokens(in: text, language: .appleScript)
        let ns = text as NSString

        XCTAssertTrue(tokens.contains { $0.kind == .comment })
        XCTAssertTrue(tokens.contains { $0.kind == .string })
        XCTAssertTrue(tokens.contains {
            $0.kind == .keyword && ns.substring(with: $0.range).lowercased() == "tell"
        })
        XCTAssertTrue(tokens.contains {
            $0.kind == .keyword && ns.substring(with: $0.range).lowercased() == "application"
        })
    }

    func testAppleScriptBlockComment() {
        let text = "(* block *) set x to 1"
        let tokens = ScriptSyntaxHighlighter.tokens(in: text, language: .appleScript)
        let comments = tokens.filter { $0.kind == .comment }
        XCTAssertEqual(comments.count, 1)
        XCTAssertEqual((text as NSString).substring(with: comments[0].range), "(* block *)")
        XCTAssertTrue(tokens.contains { $0.kind == .keyword })
    }

    func testEmptyTextHasNoTokens() {
        XCTAssertTrue(ScriptSyntaxHighlighter.tokens(in: "", language: .shell).isEmpty)
    }
}
