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
        SharedKMPBridge.conversationSections(from: thread)
    }

    static func sections(from items: [CodexThreadItem]) -> [ConversationSection] {
        SharedKMPBridge.conversationSections(from: items)
    }
}
