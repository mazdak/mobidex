import XCTest
import NIOCore
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
                "appServer"
            ]
        )

        transport.receive("""
        {"id":\(id),"result":{"data":[
          {"id":"thread-subagent","preview":"Review worker","cwd":"/srv/app","source":{"subagent":"review"},"status":{"type":"idle"},"updatedAt":1770000400,"createdAt":1770000000,"turns":[]},
          {"id":"thread-1","preview":"Build check","cwd":"/srv/app","source":"appServer","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]},
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
        XCTAssertNil(params["effort"])
        XCTAssertNil(params["approvalPolicy"])
        XCTAssertNil(params["sandboxPolicy"])

        transport.receive("""
        {"id":\(id),"result":{"turn":{"id":"turn-1","status":"inProgress","items":[]}}}
        """)

        let turn = try await task.value
        XCTAssertEqual(turn.id, "turn-1")
        await client.close()
    }

    func testStartTurnEncodesReasoningAndSandboxOptions() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let task = Task {
            try await client.startTurn(
                threadID: "thread-1",
                input: [.text("Run tests")],
                options: CodexTurnOptions(
                    reasoningEffort: .xhigh,
                    accessMode: .workspaceWrite,
                    cwd: "/srv/app"
                )
            )
        }

        let line = try await waitForSentLine(in: transport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let id = try XCTUnwrap(object["id"] as? Int)
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        let sandboxPolicy = try XCTUnwrap(params["sandboxPolicy"] as? [String: Any])

        XCTAssertEqual(object["method"] as? String, "turn/start")
        XCTAssertEqual(params["effort"] as? String, "xhigh")
        XCTAssertEqual(params["approvalPolicy"] as? String, "on-request")
        XCTAssertEqual(sandboxPolicy["type"] as? String, "workspaceWrite")
        XCTAssertEqual(sandboxPolicy["writableRoots"] as? [String], ["/srv/app"])
        XCTAssertEqual(sandboxPolicy["networkAccess"] as? Bool, true)

        transport.receive("""
        {"id":\(id),"result":{"turn":{"id":"turn-1","status":"inProgress","items":[]}}}
        """)

        _ = try await task.value
        await client.close()
    }

    func testStartTurnEncodesFullAccessOptionsWhenExplicit() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let task = Task {
            try await client.startTurn(
                threadID: "thread-1",
                input: [.text("Run tests")],
                options: CodexTurnOptions(reasoningEffort: .medium, accessMode: .fullAccess)
            )
        }

        let line = try await waitForSentLine(in: transport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let id = try XCTUnwrap(object["id"] as? Int)
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        let sandboxPolicy = try XCTUnwrap(params["sandboxPolicy"] as? [String: Any])

        XCTAssertEqual(params["effort"] as? String, "medium")
        XCTAssertEqual(params["approvalPolicy"] as? String, "never")
        XCTAssertEqual(sandboxPolicy["type"] as? String, "dangerFullAccess")

        transport.receive("""
        {"id":\(id),"result":{"turn":{"id":"turn-1","status":"inProgress","items":[]}}}
        """)

        _ = try await task.value
        await client.close()
    }

    func testStartTurnEncodesReadOnlyOptionsWhenExplicit() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let task = Task {
            try await client.startTurn(
                threadID: "thread-1",
                input: [.text("Run tests")],
                options: CodexTurnOptions(reasoningEffort: .low, accessMode: .readOnly)
            )
        }

        let line = try await waitForSentLine(in: transport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let id = try XCTUnwrap(object["id"] as? Int)
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        let sandboxPolicy = try XCTUnwrap(params["sandboxPolicy"] as? [String: Any])

        XCTAssertEqual(params["effort"] as? String, "low")
        XCTAssertEqual(params["approvalPolicy"] as? String, "on-request")
        XCTAssertEqual(sandboxPolicy["type"] as? String, "readOnly")
        XCTAssertEqual(sandboxPolicy["networkAccess"] as? Bool, false)

        transport.receive("""
        {"id":\(id),"result":{"turn":{"id":"turn-1","status":"inProgress","items":[]}}}
        """)

        _ = try await task.value
        await client.close()
    }

    func testStartTurnEncodesLocalImageInput() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let imagePath = "/Users/mazdak/Downloads/download-latest-macos-app-badge-2x.png"
        let task = Task {
            try await client.startTurn(
                threadID: "thread-1",
                input: [.text("Describe this image."), .localImage(path: imagePath)]
            )
        }

        let line = try await waitForSentLine(in: transport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let id = try XCTUnwrap(object["id"] as? Int)
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        let input = try XCTUnwrap(params["input"] as? [[String: Any]])

        XCTAssertEqual(object["method"] as? String, "turn/start")
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["type"] as? String, "text")
        XCTAssertEqual(input[0]["text"] as? String, "Describe this image.")
        XCTAssertEqual(input[1]["type"] as? String, "localImage")
        XCTAssertEqual(input[1]["path"] as? String, imagePath)

        transport.receive("""
        {"id":\(id),"result":{"turn":{"id":"turn-1","status":"inProgress","items":[]}}}
        """)

        _ = try await task.value
        await client.close()
    }

    func testGitDiffToRemoteReturnsChangedFilePaths() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let task = Task { try await client.changedFiles(cwd: "/srv/app") }

        let line = try await waitForSentLine(in: transport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let id = try XCTUnwrap(object["id"] as? Int)
        let params = try XCTUnwrap(object["params"] as? [String: Any])

        XCTAssertEqual(object["method"] as? String, "gitDiffToRemote")
        XCTAssertEqual(params["cwd"] as? String, "/srv/app")

        transport.receive("""
        {"id":\(id),"result":{"sha":"abc123","diff":"diff --git a/Sources/App.swift b/Sources/App.swift\\n--- a/Sources/App.swift\\n+++ b/Sources/App.swift\\n@@\\n-old\\n+new\\ndiff --git a/Old.swift b/New.swift\\nsimilarity index 90%\\nrename from Old.swift\\nrename to New.swift\\n"}}
        """)

        let files = try await task.value
        XCTAssertEqual(files, ["Sources/App.swift", "New.swift"])
        await client.close()
    }

    func testResumeThreadSendsThreadResumeRequest() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let task = Task { try await client.resumeThread(threadID: "thread-1") }

        let line = try await waitForSentLine(in: transport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let id = try XCTUnwrap(object["id"] as? Int)
        let params = try XCTUnwrap(object["params"] as? [String: Any])

        XCTAssertEqual(object["method"] as? String, "thread/resume")
        XCTAssertEqual(params["threadId"] as? String, "thread-1")

        transport.receive("""
        {"id":\(id),"result":{"thread":{
          "id":"thread-1",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"active","activeFlags":[]},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)

        let thread = try await task.value
        XCTAssertEqual(thread.id, "thread-1")
        XCTAssertTrue(thread.status.isActive)
        await client.close()
    }

    func testReadThreadSummaryOmitsTurns() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let task = Task { try await client.readThreadSummary(threadID: "thread-1") }

        let line = try await waitForSentLine(in: transport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let id = try XCTUnwrap(object["id"] as? Int)
        let params = try XCTUnwrap(object["params"] as? [String: Any])

        XCTAssertEqual(object["method"] as? String, "thread/read")
        XCTAssertEqual(params["threadId"] as? String, "thread-1")
        XCTAssertEqual(params["includeTurns"] as? Bool, false)

        transport.receive("""
        {"id":\(id),"result":{"thread":{
          "id":"thread-1",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000
        }}}
        """)

        let thread = try await task.value
        XCTAssertEqual(thread.id, "thread-1")
        XCTAssertTrue(thread.turns.isEmpty)
        await client.close()
    }

    func testGitDiffParserBuildsFileDiffs() {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@
        -old
        +new
        diff --git a/Tests/AppTests.swift b/Tests/AppTests.swift
        --- a/Tests/AppTests.swift
        +++ b/Tests/AppTests.swift
        @@
        -old
        +new
        """

        let files = GitDiffFileParser.files(from: diff)
        XCTAssertEqual(files.map(\.path), ["Sources/App.swift", "Tests/AppTests.swift"])
        XCTAssertTrue(files[0].diff.contains("Sources/App.swift"))
        XCTAssertFalse(files[0].diff.contains("Tests/AppTests.swift"))
    }

    func testGitDiffParserIncludesDeletedFilesFromOldPath() {
        let diff = """
        diff --git a/Removed.swift b/Removed.swift
        deleted file mode 100644
        --- a/Removed.swift
        +++ /dev/null
        @@
        -old
        """

        XCTAssertEqual(GitDiffChangedFileParser.paths(from: diff), ["Removed.swift"])
    }

    func testGitDiffParserHandlesQuotedPathsWithSpaces() {
        let diff = """
        diff --git "a/My File.swift" "b/My File.swift"
        --- "a/My File.swift"
        +++ "b/My File.swift"
        @@
        -old
        +new
        """

        XCTAssertEqual(GitDiffChangedFileParser.paths(from: diff), ["My File.swift"])
    }

    func testGitDiffParserHandlesUnquotedPathsWithSpaces() {
        let diff = """
        diff --git a/My File.swift b/My File.swift
        --- a/My File.swift
        +++ b/My File.swift
        @@
        -old
        +new
        """

        XCTAssertEqual(GitDiffChangedFileParser.paths(from: diff), ["My File.swift"])
    }

    func testThreadListFollowsPaginationCursor() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let task = Task { try await client.listThreads(limit: 1) }

        let firstLine = try await waitForSentLine(in: transport)
        let firstObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(firstLine.utf8)) as? [String: Any])
        let firstID = try XCTUnwrap(firstObject["id"] as? Int)
        let firstParams = try XCTUnwrap(firstObject["params"] as? [String: Any])
        XCTAssertNil(firstParams["cursor"])
        XCTAssertEqual(firstParams["archived"] as? Bool, false)

        transport.receive("""
        {"id":\(firstID),"result":{"data":[
          {"id":"thread-1","preview":"First","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":"cursor-2"}}
        """)

        let secondLine = try await waitForSentLine(in: transport, after: 1)
        let secondObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(secondLine.utf8)) as? [String: Any])
        let secondID = try XCTUnwrap(secondObject["id"] as? Int)
        let secondParams = try XCTUnwrap(secondObject["params"] as? [String: Any])
        XCTAssertEqual(secondParams["cursor"] as? String, "cursor-2")
        XCTAssertEqual(secondParams["archived"] as? Bool, false)

        transport.receive("""
        {"id":\(secondID),"result":{"data":[
          {"id":"thread-2","preview":"Second","cwd":"/srv/other","status":{"type":"idle"},"updatedAt":1770000400,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)

        let threads = try await task.value
        XCTAssertEqual(threads.map(\.id), ["thread-1", "thread-2"])
        await client.close()
    }

    func testThreadListIncludeArchivedMergesActiveAndArchivedRequests() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let task = Task { try await client.listThreads(cwd: "/srv/app", limit: 20, includeArchived: true) }

        let activeLine = try await waitForSentLine(in: transport)
        let activeObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(activeLine.utf8)) as? [String: Any])
        let activeID = try XCTUnwrap(activeObject["id"] as? Int)
        let activeParams = try XCTUnwrap(activeObject["params"] as? [String: Any])
        XCTAssertEqual(activeParams["archived"] as? Bool, false)

        transport.receive("""
        {"id":\(activeID),"result":{"data":[
          {"id":"active","preview":"Active","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)

        let archivedLine = try await waitForSentLine(in: transport, after: 1)
        let archivedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(archivedLine.utf8)) as? [String: Any])
        let archivedID = try XCTUnwrap(archivedObject["id"] as? Int)
        let archivedParams = try XCTUnwrap(archivedObject["params"] as? [String: Any])
        XCTAssertEqual(archivedParams["archived"] as? Bool, true)

        transport.receive("""
        {"id":\(archivedID),"result":{"data":[
          {"id":"archived","preview":"Archived","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000400,"createdAt":1770000000,"turns":[]},
          {"id":"active","preview":"Active duplicate","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000200,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)

        let threads = try await task.value
        XCTAssertEqual(threads.map(\.id), ["archived", "active"])
        await client.close()
    }

    func testThreadListDecodeFailureIncludesMethodContext() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        let task = Task { try await client.listThreads(limit: 1) }

        let line = try await waitForSentLine(in: transport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let id = try XCTUnwrap(object["id"] as? Int)

        transport.receive("""
        {"id":\(id),"result":{"data":[{"id":"thread-bad"}],"nextCursor":null}}
        """)

        do {
            _ = try await task.value
            XCTFail("Expected malformed thread data to fail decoding.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("thread/list"), error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("missing key `cwd`"), error.localizedDescription)
        }

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

    func testResponseEncodingKeepsLargeIntegerIDs() async throws {
        let transport = MockCodexLineTransport()
        let client = CodexAppServerClient(transport: transport)
        try await client.respondToServerRequest(id: .int(Int(Int32.max) + 1), result: .object([:]))

        let line = try await waitForSentLine(in: transport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(object["id"] as? Int, Int(Int32.max) + 1)
        XCTAssertEqual(object["jsonrpc"] as? String, "2.0")
        await client.close()
    }

    func testInboundResponseRoutingKeepsLargeIntegerIDs() async throws {
        let core = SharedKMPBridge.makeRPCClientCore()
        let id = Int(Int32.max) + 1
        let result = SharedKMPBridge.classifyInbound(
            core: core,
            envelope: CodexRPCInboundEnvelope(id: .int(id), result: .string("ok"))
        )
        let error = SharedKMPBridge.classifyInbound(
            core: core,
            envelope: CodexRPCInboundEnvelope(id: .int(id), error: CodexRPCErrorInfo(code: -1, message: "nope"))
        )

        guard case let .resultResponse(responseID, .string(value)) = result else {
            return XCTFail("Expected large-id result response, got \(String(describing: result))")
        }
        XCTAssertEqual(responseID, id)
        XCTAssertEqual(value, "ok")
        guard case let .errorResponse(errorID, info) = error else {
            return XCTFail("Expected large-id error response, got \(String(describing: error))")
        }
        XCTAssertEqual(errorID, id)
        XCTAssertEqual(info.message, "nope")
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

    func testTransportChannelErrorUsesReadableDisconnectMessage() async throws {
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
        transport.finishInbound(throwing: ChannelError.inputClosed)

        do {
            _ = try await task.value
            XCTFail("Expected the in-flight request to fail when the transport closes.")
        } catch let error as CodexAppServerClientError {
            XCTAssertEqual(error.localizedDescription, "The app-server SSH channel closed.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let receivedEvents = await events.value
        XCTAssertEqual(receivedEvents, [.disconnected("The app-server SSH channel closed.")])
        await client.close()
    }

    func testThreadReadResponseDecodingKeepsConversationItems() throws {
        let response = try decodeThreadFixture()

        XCTAssertEqual(response.thread.id, "thread-1")
        XCTAssertEqual(response.thread.status.label, "Active: waitingOnApproval")
        XCTAssertEqual(response.thread.turns.first?.items.count, 6)
    }

    private func waitForSentLine(in transport: MockCodexLineTransport, after cursor: Int = 0) async throws -> String {
        for _ in 0..<100 {
            let lines = transport.sentLinesSnapshot
            if lines.count > cursor {
                return lines[cursor]
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
