import XCTest
@testable import Mobidex

final class RemoteCodexDiscoveryTests: XCTestCase {
    func testShellCommandWrapsPythonDiscoveryScript() {
        XCTAssertTrue(RemoteCodexDiscovery.shellCommand.hasPrefix("mobidex_shell_rc=\"${HOME}\"/'.zshrc';"))
        XCTAssertTrue(RemoteCodexDiscovery.shellCommand.contains("python3 - <<'PY'\n"))
        XCTAssertTrue(RemoteCodexDiscovery.shellCommand.hasSuffix("\nPY\nmobidex_status=$?;exit $mobidex_status"))
        XCTAssertTrue((RemoteCodexDiscovery.shellCommand + ";exit\n").contains("\nPY\nmobidex_status=$?;exit $mobidex_status;exit\n"))
        XCTAssertFalse((RemoteCodexDiscovery.shellCommand + ";exit\n").contains("\nPY;exit"))
        XCTAssertFalse((RemoteCodexDiscovery.shellCommand + ";exit\n").contains("\n;exit"))
        XCTAssertTrue(RemoteCodexDiscovery.shellCommand.contains("CODEX_HOME"))
        XCTAssertFalse(RemoteCodexDiscovery.shellCommand.contains("archived_sessions"))
        XCTAssertFalse(RemoteCodexDiscovery.shellCommand.contains("rollout-"))
        XCTAssertTrue(RemoteCodexDiscovery.shellCommand.contains("state_5.sqlite"))
        XCTAssertTrue(RemoteCodexDiscovery.shellCommand.contains("thread-workspace-root-hints"))
        XCTAssertTrue(RemoteCodexDiscovery.shellCommand.contains("os.path.isdir"))
    }

    func testShellCommandUsesConfiguredLaunchEnvironment() {
        let command = RemoteCodexDiscovery.shellCommand(targetShellRCFile: "~/custom rc")

        XCTAssertTrue(command.hasPrefix("mobidex_shell_rc=\"${HOME}\"/'custom rc';"), command)
        XCTAssertTrue(command.contains("export PATH="), command)
        XCTAssertTrue(command.contains("python3 - <<'PY'\n"), command)
    }

    func testDecodeProjectsUsesSecondsSinceEpochDates() throws {
        let projects = try RemoteCodexDiscovery.decodeProjects(from: """
        [{"path":"/srv/app","discoveredSessionCount":2,"lastDiscoveredAt":1770000300}]
        """)

        XCTAssertEqual(projects, [
            RemoteProject(
                path: "/srv/app",
                discoveredSessionCount: 2,
                lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_300)
            )
        ])
    }

    func testDecodeProjectsFailureIncludesDiscoveryContext() throws {
        do {
            _ = try RemoteCodexDiscovery.decodeProjects(from: "python3: command not found")
            XCTFail("Expected invalid discovery output to throw.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("invalid Codex discovery data"), error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("Output: python3: command not found"), error.localizedDescription)
        }
    }
}
