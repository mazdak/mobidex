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
    typealias SharedCodexRpcNotification = MobidexShared.CodexRpcNotification
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
    typealias SharedProjectRecord = MobidexShared.ProjectRecord
    typealias SharedRemoteProject = MobidexShared.RemoteProject

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
        showInactiveDiscoveredProjects: Bool
    ) -> ProjectListSections {
        let existingByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let sections = MobidexShared.ProjectListSections.companion.from(
            projects: projects.map(toSharedProjectRecord),
            searchText: searchText,
            showInactiveDiscoveredProjects: showInactiveDiscoveredProjects
        )
        return ProjectListSections(
            favorites: sections.favorites.map { toProjectRecord($0, existing: existingByPath[$0.path]) },
            discovered: sections.discovered.map { toProjectRecord($0, existing: existingByPath[$0.path]) },
            added: sections.added.map { toProjectRecord($0, existing: existingByPath[$0.path]) },
            showInactiveDiscoveredFilter: sections.showInactiveDiscoveredFilter,
            discoveredTitle: sections.discoveredTitle
        )
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

    static func threadListParams(cwd: String?, limit: Int, cursor: String?) -> JSONValue? {
        params(
            from: MobidexShared.CodexRpcRequests.shared.threadList(
                id: 0,
                cwd: cwd,
                limit: Int32(limit),
                cursor: cursor
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

    private static func toSharedProjectRecord(_ record: ProjectRecord) -> SharedProjectRecord {
        SharedProjectRecord(
            path: record.path,
            sessionPaths: record.sessionPaths,
            displayName: record.displayName,
            discovered: record.discovered,
            discoveredSessionCount: Int32(record.discoveredSessionCount),
            activeChatCount: Int32(record.activeChatCount),
            lastDiscoveredAtEpochSeconds: kotlinLong(from: record.lastDiscoveredAt),
            lastActiveChatAtEpochSeconds: kotlinLong(from: record.lastActiveChatAt),
            isFavorite: record.isFavorite
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
            activeChatCount: Int(record.activeChatCount),
            lastDiscoveredAt: date(from: record.lastDiscoveredAtEpochSeconds),
            lastActiveChatAt: date(from: record.lastActiveChatAtEpochSeconds),
            isFavorite: record.isFavorite
        )
    }

    private static func toSharedRemoteProject(_ project: RemoteProject) -> SharedRemoteProject {
        SharedRemoteProject(
            path: project.path,
            sessionPaths: project.sessionPaths,
            discoveredSessionCount: Int32(project.discoveredSessionCount),
            lastDiscoveredAtEpochSeconds: kotlinLong(from: project.lastDiscoveredAt)
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
        SharedCodexSessionTurn(id: turn.id, items: turn.items.map(toSharedSessionItem), status: turn.status)
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

    private static func kotlinLong(from date: Date?) -> KotlinLong? {
        date.map { KotlinLong(value: Int64($0.timeIntervalSince1970)) }
    }

    private static func date(from value: KotlinLong?) -> Date? {
        value.map { Date(timeIntervalSince1970: TimeInterval($0.int64Value)) }
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }
}
