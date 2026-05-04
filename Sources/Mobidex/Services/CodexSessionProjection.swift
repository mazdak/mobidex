import Foundation

struct ConversationSection: Identifiable, Equatable {
    enum Kind: Equatable {
        case user
        case assistant
        case reasoning
        case plan
        case command
        case fileChange
        case tool
        case agent
        case search
        case media
        case review
        case system
    }

    var id: String
    var kind: Kind
    var title: String
    var body: String
    var detail: String?
    var status: String?

    var isCollapsedByDefault: Bool {
        switch kind {
        case .command, .fileChange, .tool, .agent:
            true
        case .user, .assistant, .reasoning, .plan, .search, .media, .review, .system:
            false
        }
    }

    var rendersMarkdown: Bool {
        switch kind {
        case .assistant, .reasoning, .plan, .review, .system:
            true
        case .user, .command, .fileChange, .tool, .agent, .search, .media:
            false
        }
    }

    var usesCompactTypography: Bool {
        switch kind {
        case .command, .fileChange, .tool, .agent:
            true
        case .user, .assistant, .reasoning, .plan, .search, .media, .review, .system:
            false
        }
    }
}

enum CodexSessionProjection {
    static func sections(from thread: CodexThread) -> [ConversationSection] {
        thread.turns.flatMap { turn in
            turn.items.map { item in
                section(from: item, turnID: turn.id)
            }
        }
    }

    static func sections(from items: [CodexThreadItem]) -> [ConversationSection] {
        items.map { item in
            section(from: item, turnID: "live")
        }
    }

    private static func section(from item: CodexThreadItem, turnID: String) -> ConversationSection {
        switch item {
        case .userMessage(let id, let text):
            return ConversationSection(id: id, kind: .user, title: "You", body: text, detail: nil, status: nil)
        case .agentMessage(let id, let text):
            return ConversationSection(id: id, kind: .assistant, title: "Codex", body: text, detail: nil, status: nil)
        case .reasoning(let id, let summary, let content):
            let body = (summary + content).joined(separator: "\n\n")
            return ConversationSection(id: id, kind: .reasoning, title: "Reasoning", body: body, detail: nil, status: nil)
        case .plan(let id, let text):
            return ConversationSection(id: id, kind: .plan, title: "Plan", body: text, detail: nil, status: nil)
        case .command(let id, let command, let cwd, let status, let output):
            return ConversationSection(id: id, kind: .command, title: command, body: output ?? "", detail: cwd, status: status)
        case .fileChange(let id, let changes, let status):
            let body = changes.map { change in
                [change.path, change.diff].filter { !$0.isEmpty }.joined(separator: "\n")
            }.joined(separator: "\n\n")
            return ConversationSection(id: id, kind: .fileChange, title: "File changes", body: body, detail: nil, status: status)
        case .toolCall(let id, let label, let status, let detail):
            return ConversationSection(id: id, kind: .tool, title: label, body: detail ?? "", detail: nil, status: status)
        case .agentEvent(let id, let label, let status, let detail):
            return ConversationSection(id: id, kind: .agent, title: label, body: detail ?? "", detail: nil, status: status)
        case .webSearch(let id, let query):
            return ConversationSection(id: id, kind: .search, title: "Web search", body: query, detail: nil, status: nil)
        case .image(let id, let label):
            return ConversationSection(id: id, kind: .media, title: "Image", body: label, detail: nil, status: nil)
        case .review(let id, let label):
            return ConversationSection(id: id, kind: .review, title: "Review", body: label, detail: nil, status: nil)
        case .contextCompaction(let id):
            return ConversationSection(id: id, kind: .system, title: "Compaction", body: "Context was compacted.", detail: nil, status: nil)
        case .unknown(let id, let type):
            return ConversationSection(id: id, kind: .system, title: type, body: "Unsupported app-server item in turn \(turnID).", detail: nil, status: nil)
        }
    }
}
