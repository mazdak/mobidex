import Foundation

struct ProjectListSections: Equatable {
    var favorites: [ProjectRecord]
    var discovered: [ProjectRecord]
    var added: [ProjectRecord]
    var showInactiveDiscoveredFilter: Bool
    var discoveredTitle: String

    var isEmpty: Bool {
        favorites.isEmpty && discovered.isEmpty && added.isEmpty
    }

    init(
        favorites: [ProjectRecord],
        discovered: [ProjectRecord],
        added: [ProjectRecord],
        showInactiveDiscoveredFilter: Bool,
        discoveredTitle: String
    ) {
        self.favorites = favorites
        self.discovered = discovered
        self.added = added
        self.showInactiveDiscoveredFilter = showInactiveDiscoveredFilter
        self.discoveredTitle = discoveredTitle
    }

    init(projects: [ProjectRecord], searchText: String, showInactiveDiscoveredProjects: Bool) {
        self = SharedKMPBridge.projectListSections(
            projects: projects,
            searchText: searchText,
            showInactiveDiscoveredProjects: showInactiveDiscoveredProjects
        )
    }
}
