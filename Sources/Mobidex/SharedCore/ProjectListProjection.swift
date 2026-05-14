import Foundation

struct ProjectListSections: Equatable {
    var projects: [ProjectRecord]
    var discovered: [ProjectRecord]
    var added: [ProjectRecord]
    var showInactiveDiscoveredFilter: Bool
    var showArchivedSessionFilter: Bool
    var discoveredTitle: String

    var isEmpty: Bool {
        projects.isEmpty && discovered.isEmpty && added.isEmpty
    }

    init(
        projects: [ProjectRecord],
        discovered: [ProjectRecord],
        added: [ProjectRecord],
        showInactiveDiscoveredFilter: Bool,
        showArchivedSessionFilter: Bool,
        discoveredTitle: String
    ) {
        self.projects = projects
        self.discovered = discovered
        self.added = added
        self.showInactiveDiscoveredFilter = showInactiveDiscoveredFilter
        self.showArchivedSessionFilter = showArchivedSessionFilter
        self.discoveredTitle = discoveredTitle
    }

    init(projects: [ProjectRecord], searchText: String, showInactiveDiscoveredProjects: Bool, showArchivedSessionProjects: Bool) {
        self = SharedKMPBridge.projectListSections(
            projects: projects,
            searchText: searchText,
            showInactiveDiscoveredProjects: showInactiveDiscoveredProjects,
            showArchivedSessionProjects: showArchivedSessionProjects
        )
    }
}
