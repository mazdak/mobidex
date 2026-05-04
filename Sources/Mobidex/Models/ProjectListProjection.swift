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

    init(projects: [ProjectRecord], searchText: String, showInactiveDiscoveredProjects: Bool) {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searching = !trimmedSearch.isEmpty
        let matching = projects.filter { project in
            guard searching else { return true }
            return project.displayName.localizedCaseInsensitiveContains(trimmedSearch)
                || project.path.localizedCaseInsensitiveContains(trimmedSearch)
        }
        let sorted = matching.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite && !rhs.isFavorite
            }
            if lhs.discoveredSessionCount != rhs.discoveredSessionCount {
                return lhs.discoveredSessionCount > rhs.discoveredSessionCount
            }
            if lhs.activeChatCount != rhs.activeChatCount {
                return lhs.activeChatCount > rhs.activeChatCount
            }
            let lhsDate = lhs.lastActiveChatAt ?? lhs.lastDiscoveredAt ?? .distantPast
            let rhsDate = rhs.lastActiveChatAt ?? rhs.lastDiscoveredAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        favorites = sorted.filter(\.isFavorite)
        discovered = sorted.filter { project in
            guard project.discovered, !project.isFavorite else { return false }
            return project.discoveredSessionCount > 0 || showInactiveDiscoveredProjects || searching
        }
        added = sorted.filter { project in
            !project.discovered && !project.isFavorite
        }
        showInactiveDiscoveredFilter = projects.contains { $0.discovered && !$0.isFavorite && $0.discoveredSessionCount == 0 }
        discoveredTitle = "Discovered"
    }
}
