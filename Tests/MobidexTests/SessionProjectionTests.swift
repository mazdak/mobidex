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
}
