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
}
