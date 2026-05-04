import Foundation

enum ProjectCatalog {
    static func refreshedProjects(
        existing existingProjects: [ProjectRecord],
        discovered discoveredProjects: [RemoteProject],
        openSessions: [CodexThread]?
    ) -> [ProjectRecord] {
        var recordsByPath = Dictionary(uniqueKeysWithValues: existingProjects.map { ($0.path, $0) })
        let discoveredPaths = Set(discoveredProjects.map(\.path))

        for path in Array(recordsByPath.keys) where !discoveredPaths.contains(path) {
            guard var record = recordsByPath[path], record.discovered else {
                continue
            }
            guard record.isFavorite else {
                recordsByPath.removeValue(forKey: path)
                continue
            }
            record.discovered = false
            record.sessionPaths = [record.path]
            record.discoveredSessionCount = 0
            record.lastDiscoveredAt = nil
            recordsByPath[path] = record
        }

        for project in discoveredProjects {
            var record = recordsByPath[project.path] ?? ProjectRecord(path: project.path)
            record.discovered = true
            record.sessionPaths = ProjectRecord.normalizedSessionPaths(project.sessionPaths, primaryPath: project.path)
            record.discoveredSessionCount = project.discoveredSessionCount
            record.lastDiscoveredAt = project.lastDiscoveredAt
            recordsByPath[project.path] = record
        }

        if let openSessions {
            applyOpenSessionCounts(openSessions, to: &recordsByPath)
        }

        return recordsByPath.values.sorted { lhs, rhs in
            if lhs.discoveredSessionCount != rhs.discoveredSessionCount {
                return lhs.discoveredSessionCount > rhs.discoveredSessionCount
            }
            if lhs.activeChatCount != rhs.activeChatCount {
                return lhs.activeChatCount > rhs.activeChatCount
            }
            let lhsSeenAt = lhs.lastActiveChatAt ?? lhs.lastDiscoveredAt ?? .distantPast
            let rhsSeenAt = rhs.lastActiveChatAt ?? rhs.lastDiscoveredAt ?? .distantPast
            return lhsSeenAt > rhsSeenAt
        }
    }

    private static func applyOpenSessionCounts(_ sessions: [CodexThread], to projects: inout [String: ProjectRecord]) {
        for path in projects.keys {
            guard var record = projects[path] else { continue }
            record.activeChatCount = 0
            record.lastActiveChatAt = nil
            projects[path] = record
        }

        var projectPathBySessionPath: [String: String] = [:]
        var projectPathByCodexWorktreeName: [String: String] = [:]
        var ambiguousCodexWorktreeNames = Set<String>()
        for (path, record) in projects {
            for sessionPath in ProjectRecord.normalizedSessionPaths(record.sessionPaths, primaryPath: record.path) {
                projectPathBySessionPath[sessionPath] = path
            }
            guard !isCodexWorktreePath(record.path) else { continue }
            let name = URL(fileURLWithPath: record.path).lastPathComponent
            if projectPathByCodexWorktreeName[name] != nil {
                ambiguousCodexWorktreeNames.insert(name)
            } else {
                projectPathByCodexWorktreeName[name] = path
            }
        }
        for name in ambiguousCodexWorktreeNames {
            projectPathByCodexWorktreeName.removeValue(forKey: name)
        }

        for session in sessions {
            let projectPath = projectPathBySessionPath[session.cwd]
                ?? codexWorktreeMainProjectPath(for: session.cwd, candidates: projectPathByCodexWorktreeName)
                ?? session.cwd
            var record = projects[projectPath] ?? ProjectRecord(path: projectPath, discovered: true)
            record.discovered = true
            record.sessionPaths = ProjectRecord.normalizedSessionPaths(record.sessionPaths + [session.cwd], primaryPath: record.path)
            record.activeChatCount += 1
            record.lastActiveChatAt = max(record.lastActiveChatAt ?? .distantPast, session.updatedAt)
            projects[projectPath] = record
        }
    }

    private static func codexWorktreeMainProjectPath(for cwd: String, candidates: [String: String]) -> String? {
        guard isCodexWorktreePath(cwd) else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return candidates[name]
    }

    private static func isCodexWorktreePath(_ path: String) -> Bool {
        let components = (path as NSString).pathComponents
        guard let codexIndex = components.lastIndex(of: ".codex") else {
            return false
        }
        let worktreesIndex = codexIndex + 1
        let hashIndex = codexIndex + 2
        let projectIndex = codexIndex + 3
        return components.indices.contains(projectIndex)
            && components.indices.contains(hashIndex)
            && components.indices.contains(worktreesIndex)
            && components[worktreesIndex] == "worktrees"
            && !components[hashIndex].isEmpty
            && !components[projectIndex].isEmpty
    }
}
