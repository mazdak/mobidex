import Foundation

enum GitDiffChangedFileParser {
    static func paths(from diff: String) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()
        var pendingOldPath: String?

        func append(_ path: String?) {
            guard let path,
                  !path.isEmpty,
                  path != "/dev/null",
                  seen.insert(path).inserted
            else {
                return
            }
            paths.append(path)
        }

        for line in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("diff --git ") {
                append(diffGitDestinationPath(from: line))
                pendingOldPath = nil
            } else if line.hasPrefix("--- ") {
                pendingOldPath = normalizedDiffPath(String(line.dropFirst(4)))
            } else if line.hasPrefix("+++ ") {
                let nextPath = normalizedDiffPath(String(line.dropFirst(4)))
                append(nextPath == nil ? pendingOldPath : nextPath)
                pendingOldPath = nil
            } else if line.hasPrefix("rename to ") {
                append(String(line.dropFirst("rename to ".count)))
            }
        }

        return paths
    }

    private static func diffGitDestinationPath(from line: String) -> String? {
        let payload = String(line.dropFirst("diff --git ".count))
        if let unquotedPath = unquotedDiffGitDestinationPath(from: payload) {
            return unquotedPath
        }
        let pathTokens = parseDiffPathTokens(payload)
        guard pathTokens.count >= 2 else {
            return nil
        }
        return normalizedDiffPath(pathTokens[1])
    }

    private static func unquotedDiffGitDestinationPath(from value: String) -> String? {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("\""),
              let separator = value.range(of: " b/", options: .backwards)
        else {
            return nil
        }
        let destinationStart = value.index(after: separator.lowerBound)
        return normalizedDiffPath(String(value[destinationStart...]))
    }

    private static func parseDiffPathTokens(_ value: String) -> [String] {
        var tokens: [String] = []
        var index = value.startIndex

        func advancePastWhitespace() {
            while index < value.endIndex, value[index].isWhitespace {
                index = value.index(after: index)
            }
        }

        while index < value.endIndex {
            advancePastWhitespace()
            guard index < value.endIndex else {
                break
            }

            if value[index] == "\"" {
                index = value.index(after: index)
                var token = ""
                var isEscaped = false
                while index < value.endIndex {
                    let character = value[index]
                    index = value.index(after: index)
                    if isEscaped {
                        token.append(unescapedGitQuotedCharacter(character))
                        isEscaped = false
                    } else if character == "\\" {
                        isEscaped = true
                    } else if character == "\"" {
                        break
                    } else {
                        token.append(character)
                    }
                }
                tokens.append(token)
            } else {
                let start = index
                while index < value.endIndex, !value[index].isWhitespace {
                    index = value.index(after: index)
                }
                tokens.append(String(value[start..<index]))
            }
        }

        return tokens
    }

    private static func normalizedDiffPath(_ path: String) -> String? {
        let trimmed = unquotedGitPath(path).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "/dev/null" else {
            return nil
        }
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func unquotedGitPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") else {
            return trimmed
        }
        return parseDiffPathTokens(trimmed).first ?? trimmed
    }

    private static func unescapedGitQuotedCharacter(_ character: Character) -> Character {
        switch character {
        case "n": "\n"
        case "t": "\t"
        case "r": "\r"
        default: character
        }
    }
}

enum GitDiffFileParser {
    static func files(from diff: String) -> [ChangedFileDiff] {
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.contains(where: { $0.hasPrefix("diff --git ") }) else {
            let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [ChangedFileDiff(path: "Working Tree", diff: diff)]
        }

        var files: [ChangedFileDiff] = []
        var currentLines: [String] = []

        func flush() {
            guard !currentLines.isEmpty else { return }
            let fileDiff = currentLines.joined(separator: "\n")
            let path = GitDiffChangedFileParser.paths(from: fileDiff).first ?? "Changed File"
            files.append(ChangedFileDiff(path: path, diff: fileDiff))
            currentLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                flush()
            }
            currentLines.append(line)
        }
        flush()

        return files
    }
}
