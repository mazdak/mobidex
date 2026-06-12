import Foundation
import MobidexShared

enum SharedKMPBridge {
    typealias SharedChangedFileDiff = MobidexShared.ChangedFileDiff
    typealias SharedCodexAccessMode = MobidexShared.CodexAccessMode
    typealias SharedCodexInputItem = MobidexShared.CodexInputItem
    typealias SharedCodexInputItemImageURL = MobidexShared.CodexInputItemImageUrl
    typealias SharedCodexInputItemLocalImage = MobidexShared.CodexInputItemLocalImage
    typealias SharedCodexInputItemMention = MobidexShared.CodexInputItemMention
    typealias SharedCodexInputItemSkill = MobidexShared.CodexInputItemSkill
    typealias SharedCodexInputItemText = MobidexShared.CodexInputItemText
    typealias SharedCodexReasoningEffortOption = MobidexShared.CodexReasoningEffortOption
    typealias SharedCodexRpcErrorInfo = MobidexShared.CodexRpcErrorInfo
    typealias SharedCodexRpcNotification = MobidexShared.CodexRpcNotification
    typealias SharedCodexRpcClientCore = MobidexShared.CodexRpcClientCore
    typealias SharedCodexRpcInboundClassification = MobidexShared.CodexRpcInboundClassification
    typealias SharedCodexRpcInboundEnvelope = MobidexShared.CodexRpcInboundEnvelope
    typealias SharedCodexRpcOutboundRequest = MobidexShared.CodexRpcOutboundRequest
    typealias SharedCodexRpcRequest = MobidexShared.CodexRpcRequest
    typealias SharedCodexRpcResultResponse = MobidexShared.CodexRpcResultResponse
    typealias SharedCodexSessionFileChange = MobidexShared.CodexSessionFileChange
    typealias SharedCodexSessionItem = MobidexShared.CodexSessionItem
    typealias SharedCodexSessionItemAgentEvent = MobidexShared.CodexSessionItemAgentEvent
    typealias SharedCodexSessionItemAgentMessage = MobidexShared.CodexSessionItemAgentMessage
    typealias SharedCodexSessionItemCommand = MobidexShared.CodexSessionItemCommand
    typealias SharedCodexSessionItemContextCompaction = MobidexShared.CodexSessionItemContextCompaction
    typealias SharedCodexSessionItemFileChange = MobidexShared.CodexSessionItemFileChange
    typealias SharedCodexSessionItemImage = MobidexShared.CodexSessionItemImage
    typealias SharedCodexSessionItemPlan = MobidexShared.CodexSessionItemPlan
    typealias SharedCodexSessionItemReasoning = MobidexShared.CodexSessionItemReasoning
    typealias SharedCodexSessionItemReview = MobidexShared.CodexSessionItemReview
    typealias SharedCodexSessionItemToolCall = MobidexShared.CodexSessionItemToolCall
    typealias SharedCodexSessionItemUnknown = MobidexShared.CodexSessionItemUnknown
    typealias SharedCodexSessionItemUserMessage = MobidexShared.CodexSessionItemUserMessage
    typealias SharedCodexSessionItemWebSearch = MobidexShared.CodexSessionItemWebSearch
    typealias SharedCodexSessionThread = MobidexShared.CodexSessionThread
    typealias SharedCodexSessionTurn = MobidexShared.CodexSessionTurn
    typealias SharedCodexSessionCachePolicy = MobidexShared.CodexSessionCachePolicy
    typealias SharedCodexThreadSummary = MobidexShared.CodexThreadSummary
    typealias SharedCodexTurnOptions = MobidexShared.CodexTurnOptions
    typealias SharedConversationSection = MobidexShared.ConversationSection
    typealias SharedConversationSectionKind = MobidexShared.ConversationSectionKind
    typealias SharedJsonValue = MobidexShared.JsonValue
    typealias SharedJsonValueArray = MobidexShared.JsonValueArrayValue
    typealias SharedJsonValueBool = MobidexShared.JsonValueBoolValue
    typealias SharedJsonValueDouble = MobidexShared.JsonValueDoubleValue
    typealias SharedJsonValueInt = MobidexShared.JsonValueIntValue
    typealias SharedJsonValueNull = MobidexShared.JsonValueNull
    typealias SharedJsonValueObject = MobidexShared.JsonValueObjectValue
    typealias SharedJsonValueString = MobidexShared.JsonValueStringValue
    typealias SharedKotlinByteArray = MobidexShared.KotlinByteArray
    typealias SharedProjectRecord = MobidexShared.ProjectRecord
    typealias SharedRemoteProject = MobidexShared.RemoteProject
    typealias SharedRemoteDirectoryEntry = MobidexShared.RemoteDirectoryEntry
    typealias SharedRemoteDirectoryListing = MobidexShared.RemoteDirectoryListing
    typealias SharedRemoteServerLaunchConfig = MobidexShared.RemoteServerLaunchConfig
    typealias SharedSessionListSection = MobidexShared.SessionListSection
    typealias SharedWebSocketFrame = MobidexShared.WebSocketFrame
    typealias SharedWebSocketFrameCodec = MobidexShared.WebSocketFrameCodec
    typealias SharedWebSocketFrameParser = MobidexShared.WebSocketFrameParser
    typealias SharedWebSocketMessageAssembler = MobidexShared.WebSocketMessageAssembler

    static var defaultCodexPath: String {
        MobidexShared.RemoteServerLaunchDefaults.shared.codexPath
    }

    static var defaultExecutionPath: String {
        MobidexShared.RemoteServerLaunchDefaults.shared.executionPath
    }

    static var defaultSessionListCacheTTL: TimeInterval {
        TimeInterval(MobidexShared.CodexSessionCachePolicy.shared.DEFAULT_SESSION_LIST_TTL_SECONDS)
    }

    static var defaultThreadDetailCacheTTL: TimeInterval {
        TimeInterval(MobidexShared.CodexSessionCachePolicy.shared.DEFAULT_THREAD_DETAIL_TTL_SECONDS)
    }

    static func normalizedRemoteLaunchConfig(codexPath: String?, executionPath: String?) -> (codexPath: String, executionPath: String) {
        let config = MobidexShared.RemoteServerLaunchDefaults.shared.normalize(
            codexPath: codexPath,
            executionPath: executionPath
        )
        return (codexPath: config.codexPath, executionPath: config.executionPath)
    }

    static func appServerCommand(codexPath: String, executionPath: String) -> String {
        MobidexShared.RemoteCodexAppServerCommand.shared.stdioCommand(
            codexPath: codexPath,
            executionPath: executionPath
        )
    }

    static func appServerProxyCommand(codexPath: String, executionPath: String) -> String {
        MobidexShared.RemoteCodexAppServerCommand.shared.proxyCommand(
            codexPath: codexPath,
            executionPath: executionPath
        )
    }

    static var remoteCodexDiscoveryShellCommand: String {
        MobidexShared.RemoteCodexDiscovery.shared.shellCommand
    }

    static func remoteCodexDiscoveryShellCommand(executionPath: String) -> String {
        MobidexShared.RemoteCodexDiscovery.shared.shellCommand(executionPath: executionPath)
    }

    static var remoteCodexDiscoveryPythonSource: String {
        MobidexShared.RemoteCodexDiscovery.shared.pythonSource
    }

    static func decodeRemoteProjects(from output: String) throws -> [RemoteProject] {
        try MobidexShared.RemoteCodexDiscovery.shared.decodeProjects(output: output).map(toRemoteProject)
    }

    static func remoteDirectoryBrowserShellCommand(path: String) -> String {
        MobidexShared.RemoteDirectoryBrowser.shared.shellCommand(path: path)
    }

    static func remoteDirectoryCreateShellCommand(parentPath: String, folderName: String) -> String {
        MobidexShared.RemoteDirectoryBrowser.shared.createDirectoryShellCommand(parentPath: parentPath, folderName: folderName)
    }

    static func remoteDirectoryEnsureShellCommand(path: String) -> String {
        MobidexShared.RemoteDirectoryBrowser.shared.ensureDirectoryShellCommand(path: path)
    }

    static func decodeRemoteDirectoryListing(from output: String) throws -> RemoteDirectoryListing {
        toRemoteDirectoryListing(try MobidexShared.RemoteDirectoryBrowser.shared.decodeListing(output: output))
    }

    // MARK: - ACP agent launch
    // Shell one-liner for any ACP stdio agent over openRawExec (CodexLineTransport).
    // Mirrors appServerCommand pattern; delegates to KMP RemoteAcpCommand.
    // No agent keys from the phone: auth is the remote user's concern after SSH login (same as Codex).
    static var defaultAcpLaunchCommand: String {
        MobidexShared.RemoteAcpCommand.shared.defaultLaunchCommand
    }

    static var acpGrokLaunchCommand: String {
        MobidexShared.RemoteAcpCommand.shared.grokLaunchCommand
    }

    static var acpClaudeLaunchCommand: String {
        MobidexShared.RemoteAcpCommand.shared.claudeLaunchCommand
    }

    static func acpShellCommand(launchCommand: String, executionPath: String) -> String {
        MobidexShared.RemoteAcpCommand.shared.shellCommand(
            launchCommand: launchCommand,
            executionPath: executionPath
        )
    }

    // MARK: - ACP / Grok protocol surface (item 5 iOS AcpClient parity)
    // Minimal bridge mirroring the Codex RPC section below. Exposes request builders + classify + mapper
    // so AcpClient can drive `grok agent stdio` over CodexLineTransport (openRawExec) and feed the
    // exact same SharedCodexSessionItem instances (AgentMessage, Reasoning, ToolCall, Plan, AgentEvent)
    // into the existing conversation UI with zero new rendering code.
    typealias SharedAcpRpcRequests = MobidexShared.AcpRpcRequests
    typealias SharedAcpProtocolCore = MobidexShared.AcpProtocolCore
    typealias SharedAcpRpcInboundClassification = MobidexShared.AcpRpcInboundClassification
    typealias SharedAcpRpcInboundEnvelope = MobidexShared.AcpRpcInboundEnvelope
    typealias SharedAcpSessionUpdate = MobidexShared.AcpSessionUpdate
    typealias SharedAcpContentChunk = MobidexShared.AcpContentChunk
    typealias SharedAcpContentChunkAgentMessageChunk = MobidexShared.AcpContentChunkAgentMessageChunk
    typealias SharedAcpContentChunkAgentThoughtChunk = MobidexShared.AcpContentChunkAgentThoughtChunk
    typealias SharedAcpContentChunkToolCall = MobidexShared.AcpContentChunkToolCall
    typealias SharedAcpContentChunkToolCallUpdate = MobidexShared.AcpContentChunkToolCallUpdate
    typealias SharedAcpContentChunkPlan = MobidexShared.AcpContentChunkPlan
    typealias SharedAcpContentChunkApprovalRequest = MobidexShared.AcpContentChunkApprovalRequest
    typealias SharedAcpContentChunkOther = MobidexShared.AcpContentChunkOther

    static func acpInitializeParams(clientName: String = "mobidex", clientTitle: String = "Mobidex", clientVersion: String = "0.1.0") -> JSONValue? {
        let req = MobidexShared.AcpRpcRequests.shared.initialize(
            id: 0,
            clientName: clientName,
            clientTitle: clientTitle,
            clientVersion: clientVersion
        )
        return params(from: req)
    }

    /// Auth method ids advertised in an `initialize` result (`authMethods[].id`).
    static func acpAuthMethodIds(initializeResult: JSONValue?) -> [String] {
        MobidexShared.AcpProtocolCoreKt.acpAuthMethodIds(initializeResult: initializeResult.map(toSharedJSONValue))
    }

    static func acpAuthenticateParams(methodId: String) -> JSONValue? {
        params(from: MobidexShared.AcpRpcRequests.shared.authenticate(id: 0, methodId: methodId))
    }

    static func acpSessionNewParams(cwd: String, title: String?) -> JSONValue? {
        let req = MobidexShared.AcpRpcRequests.shared.sessionNew(id: 0, cwd: cwd, title: title)
        return params(from: req)
    }

    static func acpSessionPromptParams(sessionId: String, prompt: String, context: [JSONValue] = []) -> JSONValue? {
        let req = MobidexShared.AcpRpcRequests.shared.sessionPrompt(
            id: 0,
            sessionId: sessionId,
            prompt: prompt,
            context: context.map(toSharedJSONValue)
        )
        return params(from: req)
    }

    /// Params for the spec `session/cancel` notification.
    static func acpSessionCancelParams(sessionId: String) -> JSONValue {
        toJSONValue(MobidexShared.AcpRpcRequests.shared.sessionCancelParams(sessionId: sessionId))
    }

    static func acpSessionSetModelParams(sessionId: String, modelId: String) -> JSONValue? {
        params(from: MobidexShared.AcpRpcRequests.shared.sessionSetModel(id: 0, sessionId: sessionId, modelId: modelId))
    }

    static func acpSessionListParams() -> JSONValue? {
        params(from: MobidexShared.AcpRpcRequests.shared.sessionList(id: 0))
    }

    static func acpSessionLoadParams(sessionId: String, cwd: String) -> JSONValue? {
        params(from: MobidexShared.AcpRpcRequests.shared.sessionLoad(id: 0, sessionId: sessionId, cwd: cwd))
    }

    // ISO8601DateFormatter is documented thread-safe; the type just isn't marked Sendable.
    nonisolated(unsafe) private static let acpSessionDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Past sessions from a session/list result.
    static func acpPastSessions(result: JSONValue?) -> [AcpPastSession] {
        let summaries = MobidexShared.AcpProtocolCoreKt.acpSessionList(result: result.map(toSharedJSONValue))
        return summaries.compactMap { entry -> AcpPastSession? in
            guard let summary = entry as? MobidexShared.AcpSessionSummary else { return nil }
            let updatedAt = summary.updatedAt.flatMap {
                acpSessionDateFormatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0)
            }
            return AcpPastSession(
                sessionId: summary.sessionId,
                cwd: summary.cwd,
                title: summary.title,
                updatedAt: updatedAt
            )
        }
    }

    /// Model state the agent advertised in a session/new result (empty options = no switching).
    static func acpSessionModels(result: JSONValue?) -> (options: [AcpModelOption], currentModelId: String?) {
        guard let models = MobidexShared.AcpProtocolCoreKt.acpSessionModels(sessionNewResult: result.map(toSharedJSONValue)) else {
            return ([], nil)
        }
        let options = models.available.compactMap { entry -> AcpModelOption? in
            guard let info = entry as? MobidexShared.AcpModelInfo else { return nil }
            return AcpModelOption(modelId: info.modelId, name: info.name, description: info.description_)
        }
        return (options, models.currentModelId)
    }

    /// Displayable summary for a `session/request_permission` request.
    static func acpPermissionSummary(params: JSONValue?) -> (title: String, detail: String) {
        let parsed = MobidexShared.AcpProtocolCore.shared.parsePermissionRequest(params: params.map(toSharedJSONValue))
        return (title: parsed.title ?? "Permission required", detail: parsed.detail ?? "")
    }

    /// Spec outcome result for a permission request: selects the agent-advertised option that
    /// matches accept/decline, falling back to the cancelled outcome when none matches.
    static func acpPermissionResponse(params: JSONValue?, accept: Bool) -> JSONValue {
        let core = MobidexShared.AcpProtocolCore.shared
        let sharedParams = params.map(toSharedJSONValue)
        if let optionId = core.choosePermissionOptionId(params: sharedParams, accept: accept) {
            return toJSONValue(core.permissionSelectedResult(optionId: optionId))
        }
        return toJSONValue(core.permissionCancelledResult())
    }

    /// Spec cancelled outcome for an unanswered permission request (sent when a turn is cancelled).
    static func acpPermissionCancelledResult() -> JSONValue {
        toJSONValue(MobidexShared.AcpProtocolCore.shared.permissionCancelledResult())
    }

    /// Human-readable ACP error text (turns auth_required into host-login guidance).
    static func acpReadableError(code: Int, message: String) -> String {
        MobidexShared.AcpProtocolCore.shared.readableError(code: Int32(code), message: message)
    }

    static var acpAuthRequiredErrorCode: Int {
        Int(MobidexShared.AcpProtocolCore.shared.AUTH_REQUIRED_ERROR_CODE)
    }

    static var acpPermissionRequestMethod: String {
        MobidexShared.AcpProtocolCore.shared.PERMISSION_REQUEST_METHOD
    }

    static func makeAcpProtocolCore() -> SharedAcpProtocolCore {
        SharedAcpProtocolCore()
    }

    static func acpClassifyInbound(core: SharedAcpProtocolCore, envelope: (id: JSONValue?, method: String?, params: JSONValue?, result: JSONValue?, error: CodexRPCErrorInfo?)) -> AcpInboundAction? {
        let sharedEnvelope = SharedAcpRpcInboundEnvelope(
            id: envelope.id.map(toSharedJSONValue),
            method: envelope.method,
            params: envelope.params.map(toSharedJSONValue),
            result: envelope.result.map(toSharedJSONValue),
            error: envelope.error.map { SharedCodexRpcErrorInfo(code: Int32($0.code), message: $0.message) }
        )
        guard let classification = core.classifyInbound(envelope: sharedEnvelope) else { return nil }

        // Map KMP classification to a simple Swift action (mirrors Codex classifyInbound switch)
        switch classification.kind {
        case "errorResponse":
            guard let id = swiftInt(from: classification.numericId), let error = classification.error else { return nil }
            return .errorResponse(id: id, error: CodexRPCErrorInfo(code: Int(error.code), message: error.message))
        case "resultResponse":
            guard let id = swiftInt(from: classification.numericId), let result = classification.result else { return nil }
            return .resultResponse(id: id, result: toJSONValue(result))
        case "serverRequest":
            guard let id = classification.id, let method = classification.method else { return nil }
            return .serverRequest(id: toJSONValue(id), method: method, params: classification.params.map(toJSONValue))
        case "sessionUpdate":
            // Special for ACP: return the classification itself so caller can map chunks to items
            return .sessionUpdate(classification: classification)
        case "notification":
            guard let method = classification.method else { return nil }
            return .notification(method: method, params: classification.params.map(toJSONValue))
        default:
            return nil
        }
    }

    /// Maps an ACP classification (from session/update) into the exact CodexSessionItem instances
    /// used by the conversation UI (Reasoning for thoughts, AgentMessage, ToolCall, Plan, AgentEvent).
    /// This is the iOS-side realization of the "properly translated to right UI elements" requirement.
    /// (Small pure-Swift mirror of the KMP AcpContentChunk.toCodexSessionItem + toCodexSessionItems
    /// so we get identical rendering without new UI components.)
    static func acpClassificationToSessionItems(_ classification: SharedAcpRpcInboundClassification) -> [CodexThreadItem] {
        guard let update = classification.sessionUpdate, let chunk = update.chunk else { return [] }
        guard let item = acpChunkToThreadItem(chunk) else { return [] }
        return [item]
    }

    private static func acpChunkToThreadItem(_ chunk: SharedAcpContentChunk) -> CodexThreadItem? {
        // Mirror the KMP mapper (toCodexSessionItem + toCodexSessionItems): same item kinds and the
        // same stable per-kind ids so appendingAcpThreadItem can coalesce deltas and resolve tool cards.
        if let m = chunk as? SharedAcpContentChunkAgentMessageChunk {
            let text = m.delta
            guard !text.isEmpty else { return nil }
            return .agentMessage(id: "acp-message", text: text)
        }
        if let t = chunk as? SharedAcpContentChunkAgentThoughtChunk {
            let content = t.delta
            let summaryList = t.summary.map { [$0] } ?? []
            let contentList = content.isEmpty ? [] : [content]
            guard !summaryList.isEmpty || !contentList.isEmpty else { return nil }
            return .reasoning(id: "acp-thought", summary: summaryList, content: contentList)
        }
        if let tc = chunk as? SharedAcpContentChunkToolCall {
            let label = tc.name ?? "tool"
            let detail = tc.args.map { MobidexShared.JsonValueCodec.shared.encode(value: $0) } ?? tc.status
            return .toolCall(id: tc.toolCallId ?? "acp-tool", label: label, status: tc.status ?? "running", detail: detail)
        }
        if let tu = chunk as? SharedAcpContentChunkToolCallUpdate {
            // Empty status = "this update did not carry a status"; the accumulator keeps the
            // existing card's status in that case instead of regressing a completed card.
            return .toolCall(id: tu.toolCallId ?? "acp-tool", label: tu.name ?? "tool", status: tu.status ?? "", detail: tu.output)
        }
        if let p = chunk as? SharedAcpContentChunkPlan {
            let text = [p.title, p.content].compactMap { $0 }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return .plan(id: "acp-plan", text: text)
        }
        if let a = chunk as? SharedAcpContentChunkApprovalRequest {
            let label = a.title ?? "Approval required"
            let detail = a.detail
            return .agentEvent(id: "acp-\(UUID().uuidString.prefix(8))", label: label, status: "pending", detail: detail)
        }
        // Other / unknown variants (available_commands_update, current_mode_update, ...) tolerated: no UI item.
        return nil
    }

    /// Mirror of the KMP `appendingAcpSessionItem` streaming accumulator:
    /// - consecutive agentMessage / reasoning deltas merge into the previous item (one bubble per turn)
    /// - toolCall items update-in-place by id (tool_call_update resolves the original card)
    /// - plan items replace the previous plan with the same id
    /// - anything else appends
    static func appendingAcpThreadItem(_ items: [CodexThreadItem], _ item: CodexThreadItem) -> [CodexThreadItem] {
        switch item {
        case .agentMessage(let id, let text):
            if case .agentMessage(let lastID, let lastText) = items.last, lastID == id {
                return items.dropLast() + [.agentMessage(id: id, text: lastText + text)]
            }
        case .reasoning(let id, let summary, let content):
            if case .reasoning(let lastID, let lastSummary, let lastContent) = items.last, lastID == id {
                let mergedText = (lastContent + content).joined()
                var mergedSummary = lastSummary
                for entry in summary where !mergedSummary.contains(entry) {
                    mergedSummary.append(entry)
                }
                return items.dropLast() + [
                    .reasoning(id: id, summary: mergedSummary, content: mergedText.isEmpty ? [] : [mergedText])
                ]
            }
        case .toolCall(let id, let label, let status, let detail):
            if let index = items.lastIndex(where: { existing in
                if case .toolCall(let existingID, _, _, _) = existing { return existingID == id }
                return false
            }), case .toolCall(_, let existingLabel, let existingStatus, let existingDetail) = items[index] {
                var merged = items
                merged[index] = .toolCall(
                    id: id,
                    label: label == "tool" ? existingLabel : label,
                    status: status.isEmpty ? existingStatus : status,
                    detail: detail ?? existingDetail
                )
                return merged
            }
            if status.isEmpty {
                return items + [.toolCall(id: id, label: label, status: "running", detail: detail)]
            }
        case .plan(let id, _):
            if let index = items.lastIndex(where: { existing in
                if case .plan(let existingID, _) = existing { return existingID == id }
                return false
            }) {
                var merged = items
                merged[index] = item
                return merged
            }
        default:
            break
        }
        return items + [item]
    }

    static func parseWebSocketFrame(buffer: Data) throws -> SharedWebSocketFrameParseResult? {
        guard let result = try MobidexShared.WebSocketFrameCodec.shared.parseServerFrame(buffer: toSharedByteArray(buffer)) else {
            return nil
        }
        return SharedWebSocketFrameParseResult(
            frame: SharedWebSocketFrameData(
                fin: result.frame.fin,
                opcode: UInt8(result.frame.opcode),
                payload: data(from: result.frame.payload)
            ),
            remaining: data(from: result.remaining)
        )
    }

    static func makeWebSocketFrameParser() -> SharedWebSocketFrameParser {
        SharedWebSocketFrameParser(requireUnmasked: true)
    }

    static func appendWebSocketBytes(_ data: Data, parser: SharedWebSocketFrameParser) {
        parser.append(bytes: toSharedByteArray(data))
    }

    static func nextWebSocketFrame(parser: SharedWebSocketFrameParser) throws -> SharedWebSocketFrameData? {
        guard let frame = try parser.nextFrame() else {
            return nil
        }
        return SharedWebSocketFrameData(
            fin: frame.fin,
            opcode: UInt8(frame.opcode),
            payload: data(from: frame.payload)
        )
    }

    static func appendWebSocketFrame(_ frame: SharedWebSocketFrameData, assembler: SharedWebSocketMessageAssembler) throws -> Data? {
        let sharedFrame = SharedWebSocketFrame(
            fin: frame.fin,
            opcode: Int32(frame.opcode),
            payload: toSharedByteArray(frame.payload)
        )
        guard let payload = try assembler.append(frame: sharedFrame) else {
            return nil
        }
        return data(from: payload)
    }

    static func encodeClientWebSocketFrame(opcode: UInt8, payload: Data, mask: [UInt8]) throws -> Data {
        let encoded = try MobidexShared.WebSocketFrameCodec.shared.encodeClientFrame(
            opcode: Int32(opcode),
            payload: toSharedByteArray(payload),
            mask: toSharedByteArray(Data(mask))
        )
        return data(from: encoded)
    }

    static func changedFilePaths(from diff: String) -> [String] {
        MobidexShared.GitDiffChangedFileParser.shared.paths(diff: diff)
    }

    static func changedFileDiffs(from diff: String) -> [ChangedFileDiff] {
        MobidexShared.GitDiffFileParser.shared.files(diff: diff).map {
            ChangedFileDiff(path: $0.path, diff: $0.diff)
        }
    }

    static func refreshedProjects(
        existing existingProjects: [ProjectRecord],
        discovered discoveredProjects: [RemoteProject],
        openSessions: [CodexThread]?
    ) -> [ProjectRecord] {
        let existingByPath = Dictionary(uniqueKeysWithValues: existingProjects.map { ($0.path, $0) })
        return MobidexShared.ProjectCatalog.shared.refreshedProjects(
            existingProjects: existingProjects.map(toSharedProjectRecord),
            discoveredProjects: discoveredProjects.map(toSharedRemoteProject),
            openSessions: openSessions?.map(toSharedCodexThreadSummary)
        )
        .map { toProjectRecord($0, existing: existingByPath[$0.path]) }
    }

    static func projectListSections(
        projects: [ProjectRecord],
        searchText: String,
        showInactiveDiscoveredProjects: Bool,
        showArchivedSessionProjects: Bool
    ) -> ProjectListSections {
        let existingByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let sections = MobidexShared.ProjectListSections.companion.from(
            projects: projects.map(toSharedProjectRecord),
            searchText: searchText,
            showInactiveDiscoveredProjects: showInactiveDiscoveredProjects,
            showArchivedSessionProjects: showArchivedSessionProjects
        )
        return ProjectListSections(
            projects: sections.projects.map { toProjectRecord($0, existing: existingByPath[$0.path]) },
            discovered: sections.discovered.map { toProjectRecord($0, existing: existingByPath[$0.path]) },
            added: sections.added.map { toProjectRecord($0, existing: existingByPath[$0.path]) },
            showInactiveDiscoveredFilter: sections.showInactiveDiscoveredFilter,
            showArchivedSessionFilter: sections.showArchivedSessionFilter,
            discoveredTitle: sections.discoveredTitle
        )
    }

    static func sessionListSections(threads: [CodexThread], projects: [ProjectRecord]) -> [SessionListSection] {
        let threadsByID = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0) })
        let sections = MobidexShared.SessionListSections.shared.from(
            sessions: threads.map(toSharedCodexThreadSummary),
            projects: projects.map(toSharedProjectRecord)
        )
        return sections.map { section in
            SessionListSection(
                id: section.id,
                title: section.title,
                threads: section.sessionIds.compactMap { threadsByID[$0] }
            )
        }
    }

    static func sessionIDsForProject(
        threads: [CodexThread],
        projects: [ProjectRecord],
        projectPath: String
    ) -> Set<String> {
        Set(MobidexShared.SessionListSections.shared.sessionIdsForProject(
            sessions: threads.map(toSharedCodexThreadSummary),
            projects: projects.map(toSharedProjectRecord),
            projectPath: projectPath
        ))
    }

    static func normalizedSessionPaths(_ paths: [String], primaryPath: String) -> [String] {
        MobidexShared.ProjectRecord.companion.normalizedSessionPaths(paths: paths, primaryPath: primaryPath)
    }

    static func conversationSections(from thread: CodexThread) -> [ConversationSection] {
        MobidexShared.CodexSessionProjection.shared.sections(thread: toSharedSessionThread(thread))
            .map(toConversationSection)
    }

    static func conversationSections(from items: [CodexThreadItem]) -> [ConversationSection] {
        MobidexShared.CodexSessionProjection.shared.sections(items: items.map(toSharedSessionItem))
            .map(toConversationSection)
    }

    /// Single-item projection for live/incremental updates: one item crosses the KMP bridge
    /// instead of the whole conversation per streamed delta. `id` is the caller-allocated
    /// stable section id (see ConversationSectionAccumulator).
    static func conversationSection(from item: CodexThreadItem, id: String) -> ConversationSection {
        toConversationSection(
            MobidexShared.CodexSessionProjection.shared.liveSection(item: toSharedSessionItem(item), id: id)
        )
    }

    static func jsonFields(from options: CodexTurnOptions) -> [String: JSONValue] {
        toSharedTurnOptions(options).jsonFields.mapValues(toJSONValue)
    }

    static func jsonValue(from item: CodexInputItem) -> JSONValue {
        toJSONValue(toSharedInputItem(item).jsonValue)
    }

    static func inputItems(_ items: [CodexInputItem]) -> JSONValue {
        toJSONValue(MobidexShared.CodexProtocolCoreKt.inputItems(items: items.map(toSharedInputItem)))
    }

    static func canIgnoreForLoadedThreadSummary(_ error: CodexRPCErrorInfo) -> Bool {
        MobidexShared.CodexRpcErrorInfo(code: Int32(error.code), message: error.message).canIgnoreForLoadedThreadSummary
    }

    static func initializeParams() -> JSONValue? {
        params(
            from: MobidexShared.CodexRpcRequests.shared.initialize(
                id: 0,
                name: "mobidex",
                title: "Mobidex",
                version: "0.1.0"
            )
        )
    }

    static func threadListParams(cwd: String?, limit: Int, cursor: String?, archived: Bool) -> JSONValue? {
        params(
            from: MobidexShared.CodexRpcRequests.shared.threadList(
                id: 0,
                cwd: cwd,
                limit: Int32(limit),
                cursor: cursor,
                archived: archived
            )
        )
    }

    static func loadedThreadListParams(limit: Int) -> JSONValue? {
        params(from: MobidexShared.CodexRpcRequests.shared.loadedThreadList(id: 0, limit: Int32(limit)))
    }

    static func readThreadParams(threadID: String, includeTurns: Bool) -> JSONValue? {
        params(
            from: MobidexShared.CodexRpcRequests.shared.readThread(
                id: 0,
                threadId: threadID,
                includeTurns: includeTurns
            )
        )
    }

    static func resumeThreadParams(threadID: String) -> JSONValue? {
        params(from: MobidexShared.CodexRpcRequests.shared.resumeThread(id: 0, threadId: threadID))
    }

    static func archiveThreadParams(threadID: String) -> JSONValue? {
        params(from: MobidexShared.CodexRpcRequests.shared.archiveThread(id: 0, threadId: threadID))
    }

    static func unarchiveThreadParams(threadID: String) -> JSONValue? {
        params(from: MobidexShared.CodexRpcRequests.shared.unarchiveThread(id: 0, threadId: threadID))
    }

    static func startThreadParams(cwd: String?) -> JSONValue? {
        params(from: MobidexShared.CodexRpcRequests.shared.startThread(id: 0, cwd: cwd))
    }

    static func startTurnParams(threadID: String, input: [CodexInputItem], options: CodexTurnOptions) -> JSONValue? {
        params(
            from: MobidexShared.CodexRpcRequests.shared.startTurn(
                id: 0,
                threadId: threadID,
                input: input.map(toSharedInputItem),
                options: toSharedTurnOptions(options)
            )
        )
    }

    static func interruptTurnParams(threadID: String, turnID: String) -> JSONValue? {
        params(
            from: MobidexShared.CodexRpcRequests.shared.interruptTurn(
                id: 0,
                threadId: threadID,
                turnId: turnID
            )
        )
    }

    static func steerTurnParams(threadID: String, expectedTurnID: String, input: [CodexInputItem]) -> JSONValue? {
        params(
            from: MobidexShared.CodexRpcRequests.shared.steerTurn(
                id: 0,
                threadId: threadID,
                expectedTurnId: expectedTurnID,
                input: input.map(toSharedInputItem)
            )
        )
    }

    static func gitDiffToRemoteParams(cwd: String) -> JSONValue? {
        params(from: MobidexShared.CodexRpcRequests.shared.gitDiffToRemote(id: 0, cwd: cwd))
    }

    static func encode(_ request: CodexRPCRequest) -> String {
        SharedCodexRpcRequest(
            id: Int64(request.id),
            method: request.method,
            params: request.params.map(toSharedJSONValue),
            jsonrpc: request.jsonrpc
        ).encodeJsonLine()
    }

    static func encode(_ notification: CodexRPCNotification) -> String {
        SharedCodexRpcNotification(
            method: notification.method,
            params: notification.params.map(toSharedJSONValue),
            jsonrpc: notification.jsonrpc
        ).encodeJsonLine()
    }

    static func encode(_ response: CodexRPCResultResponse) -> String {
        SharedCodexRpcResultResponse(
            id: toSharedJSONValue(response.id),
            result: toSharedJSONValue(response.result),
            jsonrpc: response.jsonrpc
        ).encodeJsonLine()
    }

    static func makeRPCClientCore() -> SharedCodexRpcClientCore {
        SharedCodexRpcClientCore(initialRequestId: 1)
    }

    static func nextRequestLine(core: SharedCodexRpcClientCore, method: String, params: JSONValue?) -> (id: Int, line: String) {
        let request = core.nextRequest(method: method, params: params.map(toSharedJSONValue))
        return (id: Int(request.id), line: request.line)
    }

    static func notificationLine(core: SharedCodexRpcClientCore, method: String, params: JSONValue?) -> String {
        core.notificationLine(method: method, params: params.map(toSharedJSONValue))
    }

    static func resultLine(core: SharedCodexRpcClientCore, id: JSONValue, result: JSONValue) -> String {
        core.resultLine(id: toSharedJSONValue(id), result: toSharedJSONValue(result))
    }

    static func classifyInbound(core: SharedCodexRpcClientCore, envelope: CodexRPCInboundEnvelope) -> CodexRPCInboundAction? {
        guard let classification = core.classifyInbound(
            envelope: SharedCodexRpcInboundEnvelope(
                id: envelope.id.map(toSharedJSONValue),
                method: envelope.method,
                params: envelope.params.map(toSharedJSONValue),
                result: envelope.result.map(toSharedJSONValue),
                error: envelope.error.map { SharedCodexRpcErrorInfo(code: Int32($0.code), message: $0.message) }
            )
        ) else {
            return nil
        }

        switch classification.kind {
        case "errorResponse":
            guard let id = swiftInt(from: classification.numericId), let error = classification.error else {
                return nil
            }
            return .errorResponse(id: id, error: CodexRPCErrorInfo(code: Int(error.code), message: error.message))
        case "resultResponse":
            guard let id = swiftInt(from: classification.numericId), let result = classification.result else {
                return nil
            }
            return .resultResponse(id: id, result: toJSONValue(result))
        case "serverRequest":
            guard let id = classification.id, let method = classification.method else {
                return nil
            }
            return .serverRequest(
                id: toJSONValue(id),
                method: method,
                params: classification.params.map(toJSONValue)
            )
        case "notification":
            guard let method = classification.method else {
                return nil
            }
            return .notification(method: method, params: classification.params.map(toJSONValue))
        default:
            return nil
        }
    }

    private static func toSharedProjectRecord(_ record: ProjectRecord) -> SharedProjectRecord {
        SharedProjectRecord(
            path: record.path,
            sessionPaths: record.sessionPaths,
            displayName: record.displayName,
            discovered: record.discovered,
            discoveredSessionCount: Int32(record.discoveredSessionCount),
            archivedSessionCount: Int32(record.archivedSessionCount),
            activeChatCount: Int32(record.activeChatCount),
            lastDiscoveredAtEpochSeconds: kotlinLong(from: record.lastDiscoveredAt),
            lastActiveChatAtEpochSeconds: kotlinLong(from: record.lastActiveChatAt),
            isAdded: record.isAdded
        )
    }

    private static func params(from request: SharedCodexRpcRequest) -> JSONValue? {
        request.params.map(toJSONValue)
    }

    private static func toProjectRecord(_ record: SharedProjectRecord, existing: ProjectRecord?) -> ProjectRecord {
        ProjectRecord(
            id: existing?.id ?? UUID(),
            path: record.path,
            sessionPaths: record.sessionPaths,
            displayName: record.displayName,
            discovered: record.discovered,
            discoveredSessionCount: Int(record.discoveredSessionCount),
            archivedSessionCount: Int(record.archivedSessionCount),
            activeChatCount: Int(record.activeChatCount),
            lastDiscoveredAt: date(from: record.lastDiscoveredAtEpochSeconds),
            lastActiveChatAt: date(from: record.lastActiveChatAtEpochSeconds),
            isAdded: record.isAdded
        )
    }

    private static func toSharedRemoteProject(_ project: RemoteProject) -> SharedRemoteProject {
        SharedRemoteProject(
            path: project.path,
            sessionPaths: project.sessionPaths,
            discoveredSessionCount: Int32(project.discoveredSessionCount),
            archivedSessionCount: Int32(project.archivedSessionCount),
            lastDiscoveredAtEpochSeconds: kotlinLong(from: project.lastDiscoveredAt)
        )
    }

    private static func toRemoteProject(_ project: SharedRemoteProject) -> RemoteProject {
        RemoteProject(
            path: project.path,
            sessionPaths: project.sessionPaths,
            discoveredSessionCount: Int(project.discoveredSessionCount),
            archivedSessionCount: Int(project.archivedSessionCount),
            lastDiscoveredAt: date(from: project.lastDiscoveredAtEpochSeconds)
        )
    }

    private static func toRemoteDirectoryListing(_ listing: SharedRemoteDirectoryListing) -> RemoteDirectoryListing {
        RemoteDirectoryListing(
            path: listing.path,
            entries: listing.entries.map { entry in
                RemoteDirectoryEntry(name: entry.name, path: entry.path)
            }
        )
    }

    private static func toSharedCodexThreadSummary(_ thread: CodexThread) -> SharedCodexThreadSummary {
        SharedCodexThreadSummary(
            id: thread.id,
            cwd: thread.cwd,
            updatedAtEpochSeconds: Int64(thread.updatedAt.timeIntervalSince1970)
        )
    }

    private static func toSharedSessionThread(_ thread: CodexThread) -> SharedCodexSessionThread {
        SharedCodexSessionThread(turns: thread.turns.map(toSharedSessionTurn))
    }

    private static func toSharedSessionTurn(_ turn: CodexTurn) -> SharedCodexSessionTurn {
        var items = turn.items.map(toSharedSessionItem)
        if let errorItem = failedTurnErrorItem(turn) {
            items.append(toSharedSessionItem(errorItem))
        }
        return SharedCodexSessionTurn(id: turn.id, items: items, status: turn.status)
    }

    private static func failedTurnErrorItem(_ turn: CodexTurn) -> CodexThreadItem? {
        guard turn.status == "failed", let error = turn.error else {
            return nil
        }
        return .agentEvent(
            id: "turn-error-\(turn.id)",
            label: "Turn Failed",
            status: "failed",
            detail: [error.message.nilIfEmpty, error.displayDetail].compactMap { $0 }.joined(separator: "\n")
        )
    }

    private static func toSharedSessionItem(_ item: CodexThreadItem) -> SharedCodexSessionItem {
        switch item {
        case .userMessage(let id, let text):
            SharedCodexSessionItemUserMessage(id: id, text: text)
        case .agentMessage(let id, let text):
            SharedCodexSessionItemAgentMessage(id: id, text: text)
        case .reasoning(let id, let summary, let content):
            SharedCodexSessionItemReasoning(id: id, summary: summary, content: content)
        case .plan(let id, let text):
            SharedCodexSessionItemPlan(id: id, text: text)
        case .command(let id, let command, let cwd, let status, let output):
            SharedCodexSessionItemCommand(id: id, command: command, cwd: cwd, status: status, output: output)
        case .fileChange(let id, let changes, let status):
            SharedCodexSessionItemFileChange(
                id: id,
                changes: changes.map { SharedCodexSessionFileChange(path: $0.path, diff: $0.diff) },
                status: status
            )
        case .toolCall(let id, let label, let status, let detail):
            SharedCodexSessionItemToolCall(id: id, label: label, status: status, detail: detail)
        case .agentEvent(let id, let label, let status, let detail):
            SharedCodexSessionItemAgentEvent(id: id, label: label, status: status, detail: detail)
        case .webSearch(let id, let query):
            SharedCodexSessionItemWebSearch(id: id, query: query)
        case .image(let id, let label):
            SharedCodexSessionItemImage(id: id, label: label)
        case .review(let id, let label):
            SharedCodexSessionItemReview(id: id, label: label)
        case .contextCompaction(let id):
            SharedCodexSessionItemContextCompaction(id: id)
        case .unknown(let id, let type):
            SharedCodexSessionItemUnknown(id: id, type: type)
        }
    }

    private static func toConversationSection(_ section: SharedConversationSection) -> ConversationSection {
        ConversationSection(
            id: section.id,
            kind: toConversationSectionKind(section.kind),
            title: section.title,
            body: section.body,
            detail: section.detail,
            status: section.status
        )
    }

    private static func toConversationSectionKind(_ kind: SharedConversationSectionKind) -> ConversationSection.Kind {
        switch kind {
        case .user: .user
        case .assistant: .assistant
        case .reasoning: .reasoning
        case .plan: .plan
        case .command: .command
        case .filechange: .fileChange
        case .tool: .tool
        case .agent: .agent
        case .search: .search
        case .media: .media
        case .review: .review
        case .system: .system
        default: .system
        }
    }

    private static func toSharedTurnOptions(_ options: CodexTurnOptions) -> SharedCodexTurnOptions {
        SharedCodexTurnOptions(
            reasoningEffort: options.reasoningEffort.map(toSharedReasoningEffort),
            accessMode: options.accessMode.map(toSharedAccessMode),
            cwd: options.cwd
        )
    }

    private static func toSharedReasoningEffort(_ option: CodexReasoningEffortOption) -> SharedCodexReasoningEffortOption {
        switch option {
        case .low: .low
        case .medium: .medium
        case .high: .high
        case .xhigh: .xhigh
        }
    }

    private static func toSharedAccessMode(_ mode: CodexAccessMode) -> SharedCodexAccessMode {
        switch mode {
        case .fullAccess: .fullaccess
        case .workspaceWrite: .workspacewrite
        case .readOnly: .readonly
        }
    }

    private static func toSharedInputItem(_ item: CodexInputItem) -> SharedCodexInputItem {
        switch item {
        case .text(let text):
            SharedCodexInputItemText(text: text)
        case .imageURL(let url):
            SharedCodexInputItemImageURL(url: url)
        case .localImage(let path):
            SharedCodexInputItemLocalImage(path: path)
        case .skill(let name, let path):
            SharedCodexInputItemSkill(name: name, path: path)
        case .mention(let name, let path):
            SharedCodexInputItemMention(name: name, path: path)
        }
    }

    private static func toSharedJSONValue(_ value: JSONValue) -> SharedJsonValue {
        switch value {
        case .null:
            SharedJsonValueNull.shared
        case .bool(let value):
            SharedJsonValueBool(value: value)
        case .int(let value):
            SharedJsonValueInt(value: Int64(value))
        case .double(let value):
            SharedJsonValueDouble(value: value)
        case .string(let value):
            SharedJsonValueString(value: value)
        case .array(let value):
            SharedJsonValueArray(value: value.map(toSharedJSONValue))
        case .object(let value):
            SharedJsonValueObject(value: value.mapValues(toSharedJSONValue))
        }
    }

    private static func toJSONValue(_ value: SharedJsonValue) -> JSONValue {
        switch value {
        case is SharedJsonValueNull:
            .null
        case let value as SharedJsonValueBool:
            .bool(value.value)
        case let value as SharedJsonValueInt:
            .int(Int(value.value))
        case let value as SharedJsonValueDouble:
            .double(value.value)
        case let value as SharedJsonValueString:
            .string(value.value)
        case let value as SharedJsonValueArray:
            .array(value.value.map(toJSONValue))
        case let value as SharedJsonValueObject:
            .object(value.value.mapValues(toJSONValue))
        default:
            .null
        }
    }

    // Bulk marshalling via the KMP NSData helpers: one memcpy per direction instead of
    // per-byte interop calls (audit P2 — the WS path crosses these for every chunk).
    private static func toSharedByteArray(_ data: Data) -> SharedKotlinByteArray {
        MobidexShared.ByteArrayBridgingKt.toByteArray(data)
    }

    private static func data(from array: SharedKotlinByteArray) -> Data {
        array.toNSData()
    }

    private static func swiftInt(from value: KotlinLong?) -> Int? {
        guard let value else {
            return nil
        }
        let int64 = value.int64Value
        guard int64 >= Int64(Int.min), int64 <= Int64(Int.max) else {
            return nil
        }
        return Int(int64)
    }

    private static func kotlinLong(from date: Date?) -> KotlinLong? {
        date.map { KotlinLong(value: Int64($0.timeIntervalSince1970)) }
    }

    private static func date(from value: KotlinLong?) -> Date? {
        value.map { Date(timeIntervalSince1970: TimeInterval($0.int64Value)) }
    }
}

struct SharedWebSocketFrameData {
    var fin: Bool
    var opcode: UInt8
    var payload: Data
}

struct SharedWebSocketFrameParseResult {
    var frame: SharedWebSocketFrameData
    var remaining: Data
}

enum CodexRPCInboundAction {
    case errorResponse(id: Int, error: CodexRPCErrorInfo)
    case resultResponse(id: Int, result: JSONValue)
    case serverRequest(id: JSONValue, method: String, params: JSONValue?)
    case notification(method: String, params: JSONValue?)
}

// Dedicated ACP classification result (keeps CodexRPCInboundAction clean for the existing Codex client).
enum AcpInboundAction {
    case errorResponse(id: Int, error: CodexRPCErrorInfo)
    case resultResponse(id: Int, result: JSONValue)
    case serverRequest(id: JSONValue, method: String, params: JSONValue?)
    case notification(method: String, params: JSONValue?)
    case sessionUpdate(classification: MobidexShared.AcpRpcInboundClassification)
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
