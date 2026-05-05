import Foundation

enum GitDiffChangedFileParser {
    static func paths(from diff: String) -> [String] {
        SharedKMPBridge.changedFilePaths(from: diff)
    }
}

enum GitDiffFileParser {
    static func files(from diff: String) -> [ChangedFileDiff] {
        SharedKMPBridge.changedFileDiffs(from: diff)
    }
}
