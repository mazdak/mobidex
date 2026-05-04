import Foundation

struct ChangedFileDiff: Identifiable, Equatable, Sendable {
    var id: String { path }
    var path: String
    var diff: String
}

struct GitDiffSnapshot: Equatable, Sendable {
    var sha: String
    var diff: String
    var files: [ChangedFileDiff]

    static let empty = GitDiffSnapshot(sha: "", diff: "", files: [])

    var isEmpty: Bool {
        diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || files.isEmpty
    }
}
