import XCTest
@testable import Mobidex

final class RemoteCodexDiscoveryTests: XCTestCase {
    func testShellCommandWrapsPythonDiscoveryScript() {
        XCTAssertTrue(RemoteCodexDiscovery.shellCommand.hasPrefix("python3 - <<'PY'\n"))
        XCTAssertTrue(RemoteCodexDiscovery.shellCommand.hasSuffix("\nPY\nmobidex_status=$?;exit $mobidex_status"))
        XCTAssertTrue((RemoteCodexDiscovery.shellCommand + ";exit\n").contains("\nPY\nmobidex_status=$?;exit $mobidex_status;exit\n"))
        XCTAssertFalse((RemoteCodexDiscovery.shellCommand + ";exit\n").contains("\nPY;exit"))
        XCTAssertFalse((RemoteCodexDiscovery.shellCommand + ";exit\n").contains("\n;exit"))
        XCTAssertTrue(RemoteCodexDiscovery.shellCommand.contains("CODEX_HOME"))
        XCTAssertTrue(RemoteCodexDiscovery.shellCommand.contains("archived_sessions"))
        XCTAssertTrue(RemoteCodexDiscovery.shellCommand.contains("os.path.isdir"))
    }

    func testDecodeProjectsUsesSecondsSinceEpochDates() throws {
        let projects = try RemoteCodexDiscovery.decodeProjects(from: """
        [{"path":"/srv/app","threadCount":2,"lastSeenAt":1770000300}]
        """)

        XCTAssertEqual(projects, [
            RemoteProject(
                path: "/srv/app",
                threadCount: 2,
                lastSeenAt: Date(timeIntervalSince1970: 1_770_000_300)
            )
        ])
    }
}
