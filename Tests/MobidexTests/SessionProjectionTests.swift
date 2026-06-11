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

    func testConversationInlineMarkdownParsesLinksAndCodeSpans() throws {
        let runs = ConversationInlineMarkdownParser.runs(
            from: "Updated [worker.rs](/Users/mazdak/Code/qlaw/worker.rs) with `Capacity available`."
        )

        XCTAssertEqual(
            runs,
            [
                .text("Updated "),
                .link(label: "worker.rs", destination: "/Users/mazdak/Code/qlaw/worker.rs"),
                .text(" with "),
                .code("Capacity available"),
                .text("."),
            ]
        )

        XCTAssertNil(ConversationInlineMarkdownParser.url(from: "/Users/mazdak/Code/qlaw/worker.rs"))
        XCTAssertEqual(ConversationInlineMarkdownParser.url(from: "https://example.com")?.scheme, "https")
    }

    // MARK: - ConversationSectionAccumulator invariant
    // After any operation sequence, accumulator.sections must equal the full projection of the
    // same item list — including the #n dedup suffixes.

    func testAccumulatorAppendAndUpdateMatchFullProjectionIncludingDedupSuffixes() {
        var items: [CodexThreadItem] = []
        let accumulator = ConversationSectionAccumulator()

        func appendBoth(_ item: CodexThreadItem) {
            items.append(item)
            accumulator.append(item)
        }

        appendBoth(.userMessage(id: "item-1", text: "Run tests"))
        appendBoth(.agentMessage(id: "item-2", text: "On it"))
        appendBoth(.agentMessage(id: "item-2", text: "duplicate id"))
        appendBoth(.toolCall(id: "item-2", label: "tool", status: "inProgress", detail: nil))
        XCTAssertEqual(accumulator.sections, CodexSessionProjection.sections(from: items))
        XCTAssertEqual(accumulator.sections.map(\.id), ["item-1", "item-2", "item-2#2", "item-2#3"])

        // Streaming update re-projects in place and preserves the allocated (suffixed) id.
        items[2] = .agentMessage(id: "item-2", text: "duplicate id grew")
        XCTAssertTrue(accumulator.updateAt(2, with: items[2]))
        XCTAssertEqual(accumulator.sections, CodexSessionProjection.sections(from: items))

        XCTAssertFalse(accumulator.updateAt(99, with: items[2]))
    }

    func testAccumulatorResetAdoptsPrebuiltProjectionAndReplaysIdAllocation() {
        let items: [CodexThreadItem] = [
            .userMessage(id: "item-1", text: "Hello"),
            .agentMessage(id: "item-1", text: "duplicate id"),
            .command(id: "item-2", command: "bun test", cwd: "/srv", status: "completed", output: "ok"),
        ]
        let prebuilt = CodexSessionProjection.sections(from: items)
        let accumulator = ConversationSectionAccumulator()
        accumulator.reset(items: items, prebuilt: prebuilt)
        XCTAssertEqual(accumulator.sections, prebuilt)

        // Allocation state was replayed: the next duplicate id keeps suffixing where the
        // full projection would.
        var extended = items
        let appended = CodexThreadItem.plan(id: "item-1", text: "step")
        extended.append(appended)
        accumulator.append(appended)
        XCTAssertEqual(accumulator.sections, CodexSessionProjection.sections(from: extended))
        XCTAssertEqual(accumulator.sections.last?.id, "item-1#3")

        // Mismatched prebuilt is rejected in favor of a fresh projection.
        accumulator.reset(items: items, prebuilt: Array(prebuilt.dropLast()))
        XCTAssertEqual(accumulator.sections, prebuilt)

        accumulator.reset(items: [])
        XCTAssertTrue(accumulator.sections.isEmpty)
    }
}
