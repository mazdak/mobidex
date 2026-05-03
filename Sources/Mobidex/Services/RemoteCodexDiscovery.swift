import Foundation

enum RemoteCodexDiscovery {
    static let shellCommand = "python3 - <<'PY'\n\(pythonSource)\nPY\nmobidex_status=$?;exit $mobidex_status"

    static func decodeProjects(from output: String) throws -> [RemoteProject] {
        guard let data = output.data(using: .utf8) else {
            throw SSHServiceError.invalidDiscoveryOutput
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode([RemoteProject].self, from: data)
    }

    static let pythonSource = #"""
import glob
import json
import os
import re
from collections import defaultdict

MAX_PROJECTS = 200
MAX_SESSION_SCAN_LINES = 80


def find_cwd(value):
    if isinstance(value, dict):
        for key in ("cwd", "current_dir"):
            candidate = value.get(key)
            if isinstance(candidate, str) and candidate:
                return candidate
        for nested in value.values():
            found = find_cwd(nested)
            if found:
                return found
    elif isinstance(value, list):
        for nested in value:
            found = find_cwd(nested)
            if found:
                return found
    return None


home = os.path.expanduser(os.environ.get("CODEX_HOME", "~/.codex"))
paths = defaultdict(lambda: {"threadCount": 0, "lastSeenAt": None})


def existing_directory(path):
    if not isinstance(path, str) or not path:
        return None
    expanded = os.path.expanduser(path)
    if not os.path.isabs(expanded) or not os.path.isdir(expanded):
        return None
    return expanded


config = os.path.join(home, "config.toml")
if os.path.exists(config):
    try:
        text = open(config, "r", encoding="utf-8", errors="ignore").read()
        for match in re.finditer(r'^\s*\[projects\."([^"]+)"\]', text, flags=re.MULTILINE):
            path = existing_directory(match.group(1))
            if path:
                paths[path]["lastSeenAt"] = paths[path]["lastSeenAt"] or int(os.path.getmtime(config))
    except Exception:
        pass

for root in ("sessions", "archived_sessions"):
    pattern = os.path.join(home, root, "**", "rollout-*.jsonl")
    for filename in glob.iglob(pattern, recursive=True):
        try:
            mtime = int(os.path.getmtime(filename))
            cwd = None
            with open(filename, "r", encoding="utf-8", errors="ignore") as handle:
                for index, line in enumerate(handle):
                    if index >= MAX_SESSION_SCAN_LINES:
                        break
                    if '"cwd"' not in line and '"current_dir"' not in line:
                        continue
                    try:
                        payload = json.loads(line)
                    except Exception:
                        continue
                    cwd = find_cwd(payload)
                    if cwd:
                        break
            cwd = existing_directory(cwd)
            if cwd:
                paths[cwd]["threadCount"] += 1
                paths[cwd]["lastSeenAt"] = max(paths[cwd]["lastSeenAt"] or 0, mtime)
        except Exception:
            pass

result = [
    {"path": path, "threadCount": value["threadCount"], "lastSeenAt": value["lastSeenAt"]}
    for path, value in paths.items()
]
result.sort(key=lambda item: (item["lastSeenAt"] or 0, item["path"]), reverse=True)
print(json.dumps(result[:MAX_PROJECTS]))
"""#
}
