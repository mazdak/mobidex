import XCTest
@testable import Mobidex

final class SessionProjectionTests: XCTestCase {
    func testProjectionCoversUserAssistantReasoningCommandFileAndToolEvents() throws {
        let response = try decodeThreadFixture()
        let sections = CodexSessionProjection.sections(from: response.thread)

        XCTAssertEqual(sections.map(\.kind), [.user, .reasoning, .command, .fileChange, .tool, .assistant])
        XCTAssertEqual(sections.first?.body, "Run tests")
        XCTAssertEqual(sections.first(where: { $0.kind == .command })?.title, "bun test")
        XCTAssertTrue(sections.first(where: { $0.kind == .fileChange })?.body.contains("src/app.ts") == true)
        XCTAssertEqual(sections.last?.body, "Tests pass.")
    }

    func testConversationSectionPresentationHintsSeparateNarrativeFromDetailLogs() throws {
        let response = try decodeThreadFixture()
        let sections = CodexSessionProjection.sections(from: response.thread)

        let assistant = try XCTUnwrap(sections.first(where: { $0.kind == .assistant }))
        XCTAssertTrue(assistant.rendersMarkdown)
        XCTAssertFalse(assistant.isCollapsedByDefault)
        XCTAssertFalse(assistant.usesCompactTypography)

        let command = try XCTUnwrap(sections.first(where: { $0.kind == .command }))
        XCTAssertFalse(command.rendersMarkdown)

        let tool = try XCTUnwrap(sections.first(where: { $0.kind == .tool }))
        XCTAssertFalse(tool.rendersMarkdown)

        let fileChange = try XCTUnwrap(sections.first(where: { $0.kind == .fileChange }))
        XCTAssertFalse(fileChange.rendersMarkdown)

        let collapsedDetailSections = [
            command,
            fileChange,
            tool,
            ConversationSection(
                id: "agent-section",
                kind: .agent,
                title: "Worker",
                body: "Spawned reviewer",
                detail: nil,
                status: "completed"
            ),
        ]
        for section in collapsedDetailSections {
            XCTAssertTrue(section.isCollapsedByDefault, "\(section.kind) should be collapsed by default")
            XCTAssertTrue(section.usesCompactTypography, "\(section.kind) should use compact typography")
            XCTAssertFalse(section.rendersMarkdown, "\(section.kind) should render details verbatim")
        }
    }

    func testConversationTextPresentationStripsCodexAppDirectivesAndKeepsBlocks() {
        let body = """
        Pushed straight to `master`.

        Commit: `1eae538e4e fix(infra): stabilize rq worker health check`

        Pre-push hooks passed.

        ::git-stage{cwd="/Users/mazdak/.codex/worktrees/73e9/fullstack"} ::git-commit{cwd="/Users/mazdak/.codex/worktrees/73e9/fullstack"} ::git-push{cwd="/Users/mazdak/.codex/worktrees/73e9/fullstack" branch="master"}
        """

        let displayBody = ConversationTextPresentation.displayBody(from: body)

        XCTAssertFalse(displayBody.contains("::git-stage"))
        XCTAssertFalse(displayBody.contains("::git-commit"))
        XCTAssertFalse(displayBody.contains("::git-push"))
        XCTAssertEqual(
            ConversationTextPresentation.markdownBlocks(from: displayBody),
            [
                "Pushed straight to `master`.",
                "Commit: `1eae538e4e fix(infra): stabilize rq worker health check`",
                "Pre-push hooks passed.",
            ]
        )
    }

    func testConversationTextPresentationPreservesFencedCodeAndLiteralDirectiveExamples() {
        let body = """
        Keep this literal example: `::git-stage{cwd="/tmp/example"}`.

        ```swift
        let first = true

        let example = "::git-stage{cwd=\\"/tmp/example\\"}"
        ```

        ::git-stage{cwd="/tmp/hidden"}
        """

        let displayBody = ConversationTextPresentation.displayBody(from: body)
        let blocks = ConversationTextPresentation.markdownBlocks(from: displayBody)

        XCTAssertTrue(displayBody.contains("Keep this literal example"))
        XCTAssertTrue(displayBody.contains("::git-stage{cwd=\"/tmp/example\"}"))
        XCTAssertFalse(displayBody.contains("::git-stage{cwd=\"/tmp/hidden\"}"))
        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(blocks[1].contains("let first = true\n\nlet example"))
    }

    func testConversationTextPresentationTurnsSoftLineBreaksIntoRenderedBreaksOutsideCode() {
        let block = """
        Details:
        Branch: codex/include-qlaw-devbox
        Validation passed:
        ```bash
        one
        two
        ```
        """

        let markdown = ConversationTextPresentation.markdownForRendering(from: block)

        XCTAssertTrue(markdown.contains("Details:  \nBranch:"))
        XCTAssertTrue(markdown.contains("Validation passed:  \n```bash"))
        XCTAssertTrue(markdown.contains("one\ntwo"))
        XCTAssertFalse(markdown.contains("one  \ntwo"))
    }
}
