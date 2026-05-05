import Foundation

enum ProjectCatalog {
    static func refreshedProjects(
        existing existingProjects: [ProjectRecord],
        discovered discoveredProjects: [RemoteProject],
        openSessions: [CodexThread]?
    ) -> [ProjectRecord] {
        SharedKMPBridge.refreshedProjects(
            existing: existingProjects,
            discovered: discoveredProjects,
            openSessions: openSessions
        )
    }
}
