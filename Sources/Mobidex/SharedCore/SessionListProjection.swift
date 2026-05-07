import Foundation

struct SessionListSection: Equatable, Identifiable {
    var id: String
    var title: String
    var threads: [CodexThread]

    init(id: String, title: String, threads: [CodexThread]) {
        self.id = id
        self.title = title
        self.threads = threads
    }
}

enum SessionListSections {
    static func sections(threads: [CodexThread], projects: [ProjectRecord]) -> [SessionListSection] {
        SharedKMPBridge.sessionListSections(threads: threads, projects: projects)
    }
}
