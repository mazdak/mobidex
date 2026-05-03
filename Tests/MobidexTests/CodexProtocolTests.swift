import XCTest
@testable import Mobidex

final class CodexProtocolTests: XCTestCase {
    func testThreadListRequestEncodingUsesAppServerV2ShapeAndFiltersByProject() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let task = Task { try await client.listThreads(cwd: "/srv/app", limit: 20) }

        let line = try await waitForSentLine(in: transport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let id = try XCTUnwrap(object["id"] as? Int)
        let params = try XCTUnwrap(object["params"] as? [String: Any])

        XCTAssertEqual(object["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(object["method"] as? String, "thread/list")
        XCTAssertEqual(params["limit"] as? Int, 20)
        XCTAssertEqual(params["cwd"] as? String, "/srv/app")
        XCTAssertEqual(params["sortKey"] as? String, "updated_at")
        XCTAssertEqual(params["sortDirection"] as? String, "desc")
        XCTAssertEqual(params["archived"] as? Bool, false)
        XCTAssertEqual(
            params["sourceKinds"] as? [String],
            [
                "cli",
                "vscode",
                "exec",
                "appServer",
                "subAgent",
                "subAgentReview",
                "subAgentCompact",
                "subAgentThreadSpawn",
                "subAgentOther",
                "unknown"
            ]
        )

        transport.receive("""
        {"id":\(id),"result":{"data":[
          {"id":"thread-1","preview":"Build check","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]},
          {"id":"thread-2","preview":"Other","cwd":"/srv/other","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)

        let threads = try await task.value
        XCTAssertEqual(threads.map(\.id), ["thread-1"])
        await client.close()
    }

    func testStartTurnEncodesTextInputWithCurrentAppServerShape() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let task = Task { try await client.startTurn(threadID: "thread-1", text: "Run tests") }

        let line = try await waitForSentLine(in: transport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let id = try XCTUnwrap(object["id"] as? Int)
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        let input = try XCTUnwrap(params["input"] as? [[String: Any]])
        let textInput = try XCTUnwrap(input.first)

        XCTAssertEqual(object["method"] as? String, "turn/start")
        XCTAssertEqual(params["threadId"] as? String, "thread-1")
        XCTAssertEqual(textInput["type"] as? String, "text")
        XCTAssertEqual(textInput["text"] as? String, "Run tests")
        XCTAssertNotNil(textInput["text_elements"])
        XCTAssertNil(textInput["textElements"])

        transport.receive("""
        {"id":\(id),"result":{"turn":{"id":"turn-1","status":"inProgress","items":[]}}}
        """)

        let turn = try await task.value
        XCTAssertEqual(turn.id, "turn-1")
        await client.close()
    }

    func testSteerEncodesExpectedTurnPrecondition() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let task = Task { try await client.steer(threadID: "thread-1", expectedTurnID: "turn-1", text: "Keep going") }

        let line = try await waitForSentLine(in: transport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let id = try XCTUnwrap(object["id"] as? Int)
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        let input = try XCTUnwrap(params["input"] as? [[String: Any]])

        XCTAssertEqual(object["method"] as? String, "turn/steer")
        XCTAssertEqual(params["threadId"] as? String, "thread-1")
        XCTAssertEqual(params["expectedTurnId"] as? String, "turn-1")
        XCTAssertEqual(input.first?["text"] as? String, "Keep going")

        transport.receive(#"{"id":\#(id),"result":{"turnId":"turn-1"}}"#)
        try await task.value
        await client.close()
    }

    func testInterruptTurnUsesSupportedAppServerMethod() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let task = Task { try await client.interrupt(threadID: "thread-1", turnID: "turn-1") }

        let line = try await waitForSentLine(in: transport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let id = try XCTUnwrap(object["id"] as? Int)
        let params = try XCTUnwrap(object["params"] as? [String: Any])

        XCTAssertEqual(object["method"] as? String, "turn/interrupt")
        XCTAssertEqual(params["threadId"] as? String, "thread-1")
        XCTAssertEqual(params["turnId"] as? String, "turn-1")

        transport.receive(#"{"id":\#(id),"result":{}}"#)
        try await task.value
        await client.close()
    }

    func testTransportEOFClosesClientAndFailsLaterRequests() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let events = Task { () -> [CodexAppServerEvent] in
            var received: [CodexAppServerEvent] = []
            for await event in client.events {
                received.append(event)
            }
            return received
        }
        let task = Task { try await client.listThreads(cwd: "/srv/app", limit: 20) }

        _ = try await waitForSentLine(in: transport)
        transport.finishInbound()

        do {
            _ = try await task.value
            XCTFail("Expected the in-flight request to fail when the transport ends.")
        } catch CodexAppServerClientError.disconnected {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await client.listThreads(cwd: "/srv/app", limit: 20)
            XCTFail("Expected later requests to fail immediately after EOF.")
        } catch CodexAppServerClientError.disconnected {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let receivedEvents = await events.value
        XCTAssertEqual(receivedEvents, [.disconnected("The app-server stream ended.")])
        await client.close()
    }

    func testThreadReadResponseDecodingKeepsConversationItems() throws {
        let response = try decodeThreadFixture()

        XCTAssertEqual(response.thread.id, "thread-1")
        XCTAssertEqual(response.thread.status.label, "Active: waitingOnApproval")
        XCTAssertEqual(response.thread.turns.first?.items.count, 6)
    }

    private func waitForSentLine(in transport: MockCodexLineTransport) async throws -> String {
        for _ in 0..<100 {
            if let line = transport.sentLinesSnapshot.last {
                return line
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return try XCTUnwrap(nil as String?, "Timed out waiting for a JSON-RPC request.")
    }
}

func decodeThreadFixture() throws -> ThreadReadResponse {
    let data = Data(threadReadFixture.utf8)
    return try JSONDecoder().decode(ThreadReadResponse.self, from: data)
}

let threadReadFixture = """
{
  "thread": {
    "id": "thread-1",
    "forkedFromId": null,
    "preview": "Please inspect the build",
    "ephemeral": false,
    "modelProvider": "openai",
    "createdAt": 1770000000,
    "updatedAt": 1770000300,
    "status": { "type": "active", "activeFlags": ["waitingOnApproval"] },
    "path": "/Users/me/.codex/sessions/2026/05/02/rollout.jsonl",
    "cwd": "/srv/app",
    "cliVersion": "1.0.0",
    "source": { "type": "cli" },
    "agentNickname": null,
    "agentRole": null,
    "gitInfo": null,
    "name": "Build check",
    "turns": [
      {
        "id": "turn-1",
        "status": "inProgress",
        "error": null,
        "startedAt": 1770000001,
        "completedAt": null,
        "durationMs": null,
        "items": [
          {
            "type": "userMessage",
            "id": "item-user",
            "content": [{ "type": "text", "text": "Run tests" }]
          },
          {
            "type": "reasoning",
            "id": "item-reasoning",
            "summary": ["Need inspect package scripts"],
            "content": []
          },
          {
            "type": "commandExecution",
            "id": "item-command",
            "command": "bun test",
            "cwd": "/srv/app",
            "processId": null,
            "source": "shell",
            "status": "completed",
            "commandActions": [],
            "aggregatedOutput": "ok",
            "exitCode": 0,
            "durationMs": 120
          },
          {
            "type": "fileChange",
            "id": "item-file",
            "status": "completed",
            "changes": [
              {
                "path": "src/app.ts",
                "kind": { "type": "update", "movePath": null },
                "diff": "@@\\n-old\\n+new"
              }
            ]
          },
          {
            "type": "mcpToolCall",
            "id": "item-tool",
            "server": "github",
            "tool": "pull_request_read",
            "status": "completed",
            "arguments": {},
            "mcpAppResourceUri": null,
            "result": null,
            "error": null,
            "durationMs": 4
          },
          {
            "type": "agentMessage",
            "id": "item-agent",
            "text": "Tests pass.",
            "phase": null,
            "memoryCitation": null
          }
        ]
      }
    ]
  }
}
"""
