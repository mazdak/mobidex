import XCTest

final class MobidexUITests: XCTestCase {
    private let timeout = TimeInterval(ProcessInfo.processInfo.environment["MOBIDEX_UI_SMOKE_TIMEOUT"] ?? "") ?? 90

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSeededControlFlowThroughVisibleUI() throws {
        let app = XCUIApplication()
        app.launchEnvironment = try smokeLaunchEnvironment()
        app.launch()

        let connectButton = app.buttons["connectButton"]
        if !connectButton.waitForExistence(timeout: 5) {
            let serverRow = app.descendants(matching: .any)["serverRow"]
            XCTAssertTrue(serverRow.waitForExistence(timeout: timeout), "Seeded server row did not appear.")
            serverRow.tap()
        }
        XCTAssertTrue(connectButton.waitForExistence(timeout: timeout), "Connect button did not appear.")
        connectButton.tap()

        let projectRow = app.buttons["projectRow"].firstMatch
        XCTAssertTrue(projectRow.waitForExistence(timeout: timeout), "Seeded project row did not appear.")
        projectRow.tap()

        let newThreadButton = app.buttons["newThreadButton"]
        XCTAssertTrue(waitForEnabled(newThreadButton, timeout: timeout), "New Thread button did not become enabled after opening the seeded project.")
        newThreadButton.tap()

        let composer = app.descendants(matching: .any)["messageComposer"]
        XCTAssertTrue(composer.waitForExistence(timeout: timeout), "Composer did not appear after starting a new thread.")
        composer.tap()
        composer.typeText(smokeText("PROMPT", defaultValue: "Start control smoke"))

        let sendButton = app.buttons["sendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: timeout), "Send button did not appear.")
        sendButton.tap()

        let approveButton = app.buttons["approveButton"]
        XCTAssertTrue(approveButton.waitForExistence(timeout: timeout), "Approval button did not appear.")
        approveButton.tap()
        XCTAssertTrue(waitForDisappearance(of: approveButton, timeout: timeout), "Approval button remained visible after approving.")

        XCTAssertTrue(composer.waitForExistence(timeout: timeout), "Composer disappeared before steering.")
        composer.tap()
        composer.typeText(smokeText("STEER_TEXT", defaultValue: "Steer control smoke"))
        sendButton.tap()

        let expectedText = smokeText("EXPECTED_TEXT", defaultValue: "control steer accepted")
        let assistantText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", expectedText)).firstMatch
        XCTAssertTrue(assistantText.waitForExistence(timeout: timeout), "Expected steered assistant text did not appear.")

        let stopButton = app.buttons["stopTurnButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: timeout), "Stop turn button did not appear.")
        let beforeInterrupt = XCTAttachment(screenshot: app.screenshot())
        beforeInterrupt.name = "Before interrupt"
        beforeInterrupt.lifetime = .keepAlways
        add(beforeInterrupt)
        stopButton.tap()
        XCTAssertTrue(waitForDisappearance(of: stopButton, timeout: timeout), "Stop turn button remained visible after interrupt.")
    }

    private func smokeLaunchEnvironment() throws -> [String: String] {
        let environment = ProcessInfo.processInfo.environment
        let requiredKeys = [
            "MOBIDEX_SMOKE_AUTH",
            "MOBIDEX_SMOKE_CODEX_PATH",
            "MOBIDEX_SMOKE_CWD",
            "MOBIDEX_SMOKE_HOST",
            "MOBIDEX_SMOKE_MODE",
            "MOBIDEX_SMOKE_PASSWORD",
            "MOBIDEX_SMOKE_PORT",
            "MOBIDEX_SMOKE_USER",
        ]
        for key in requiredKeys where environment[key, default: ""].isEmpty {
            throw XCTSkip("Missing required UI smoke environment value: \(key)")
        }

        var launchEnvironment = [
            "MOBIDEX_SMOKE": "1",
            "MOBIDEX_SMOKE_PROMOTE_DETAIL": "1",
            "MOBIDEX_SMOKE_AUTH": environment["MOBIDEX_SMOKE_AUTH"]!,
            "MOBIDEX_SMOKE_CODEX_PATH": environment["MOBIDEX_SMOKE_CODEX_PATH"]!,
            "MOBIDEX_SMOKE_CWD": environment["MOBIDEX_SMOKE_CWD"]!,
            "MOBIDEX_SMOKE_HOST": environment["MOBIDEX_SMOKE_HOST"]!,
            "MOBIDEX_SMOKE_MODE": environment["MOBIDEX_SMOKE_MODE"]!,
            "MOBIDEX_SMOKE_PASSWORD": environment["MOBIDEX_SMOKE_PASSWORD"]!,
            "MOBIDEX_SMOKE_PORT": environment["MOBIDEX_SMOKE_PORT"]!,
            "MOBIDEX_SMOKE_USER": environment["MOBIDEX_SMOKE_USER"]!,
            "MOBIDEX_SMOKE_TIMEOUT": environment["MOBIDEX_UI_SMOKE_TIMEOUT"] ?? "90",
        ]
        if let prompt = environment["MOBIDEX_UI_SMOKE_PROMPT"] {
            launchEnvironment["MOBIDEX_SMOKE_PROMPT"] = prompt
        }
        if let steerText = environment["MOBIDEX_UI_SMOKE_STEER_TEXT"] {
            launchEnvironment["MOBIDEX_SMOKE_STEER_TEXT"] = steerText
        }
        if let expectedText = environment["MOBIDEX_UI_SMOKE_EXPECTED_TEXT"] {
            launchEnvironment["MOBIDEX_SMOKE_EXPECTED_TEXT"] = expectedText
        }
        return launchEnvironment
    }

    private func smokeText(_ key: String, defaultValue: String) -> String {
        let environment = ProcessInfo.processInfo.environment
        return environment["MOBIDEX_UI_SMOKE_\(key)"] ?? environment["MOBIDEX_SMOKE_\(key)"] ?? defaultValue
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return !element.exists
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isEnabled {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return element.exists && element.isEnabled
    }
}
