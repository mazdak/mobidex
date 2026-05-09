package mobidex.shared

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

class RemoteCodexDiscoveryException(message: String) : Exception(message)

object RemoteCodexDiscovery {
    val pythonSource: String = """
import json
import os
import re
import sqlite3
import subprocess
from collections import defaultdict

MAX_PROJECTS = 200
USER_FACING_SOURCES = ("cli", "vscode", "exec", "appServer")


home = os.path.expanduser(os.environ.get("CODEX_HOME", "~/.codex"))
paths = defaultdict(lambda: {
    "discoveredSessionCount": 0,
    "archivedSessionCount": 0,
    "lastDiscoveredAt": None,
    "sessionPaths": set(),
})


def existing_directory(path):
    if not isinstance(path, str) or not path:
        return None
    expanded = os.path.expanduser(path)
    if not os.path.isabs(expanded) or not os.path.isdir(expanded):
        return None
    return os.path.realpath(expanded)


def is_codex_worktree_path(path):
    parts = path.split(os.sep)
    for index, part in enumerate(parts):
        if part == ".codex" and index + 3 < len(parts) and parts[index + 1] == "worktrees":
            return True
    return False


def is_hidden_project_path(path):
    parts = [part for part in path.split(os.sep) if part]
    if is_codex_worktree_path(path):
        return False
    return any(part.startswith(".") for part in parts)


def main_worktree(path):
    try:
        output = subprocess.check_output(
            ["git", "-C", path, "worktree", "list", "--porcelain"],
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=2,
        )
        for line in output.splitlines():
            if line.startswith("worktree "):
                candidate = existing_directory(line[len("worktree "):])
                if candidate:
                    return candidate
                break
    except Exception:
        pass

    try:
        common_dir = subprocess.check_output(
            ["git", "-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir"],
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=2,
        ).strip()
        if common_dir.endswith("/.git"):
            return existing_directory(os.path.dirname(common_dir))
    except Exception:
        pass

    return path


def add_project_path(path, active_thread_count=0, archived_thread_count=0, last_seen_at=None):
    existing = existing_directory(path)
    if not existing:
        return
    canonical = main_worktree(existing)
    paths[canonical]["sessionPaths"].add(canonical)
    paths[canonical]["sessionPaths"].add(existing)
    paths[canonical]["discoveredSessionCount"] += active_thread_count
    paths[canonical]["archivedSessionCount"] += archived_thread_count
    if last_seen_at is not None:
        paths[canonical]["lastDiscoveredAt"] = max(paths[canonical]["lastDiscoveredAt"] or 0, last_seen_at)


def add_official_project(path, last_seen_at=None):
    existing = existing_directory(path)
    if not existing:
        return None
    paths[existing]["sessionPaths"].add(existing)
    if last_seen_at is not None:
        paths[existing]["lastDiscoveredAt"] = max(paths[existing]["lastDiscoveredAt"] or 0, last_seen_at)
    return existing


def ordered_workspace_roots(state):
    result = []
    seen = set()
    remote_paths_by_id = {
        project.get("id"): project.get("remotePath")
        for project in state.get("remote-projects", []) or []
        if isinstance(project, dict)
        and isinstance(project.get("id"), str)
        and isinstance(project.get("remotePath"), str)
    }

    def append_root(path):
        if not isinstance(path, str) or not path.startswith("/"):
            return
        if path in seen:
            return
        seen.add(path)
        result.append(path)

    for key in ("project-order", "electron-saved-workspace-roots", "active-workspace-roots"):
        for value in state.get(key, []) or []:
            if isinstance(value, str) and value.startswith("/"):
                append_root(value)
            elif isinstance(value, str):
                append_root(remote_paths_by_id.get(value))
    return result


def top_level_threads(db_path):
    if not os.path.exists(db_path):
        return []
    try:
        connection = sqlite3.connect(db_path)
        connection.row_factory = sqlite3.Row
        return connection.execute(
            '''
            select id, cwd, title, updated_at, archived
            from threads
            where source in (?, ?, ?, ?)
            order by updated_at desc
            limit 5000
            ''',
            USER_FACING_SOURCES,
        ).fetchall()
    except Exception:
        return []


def discover_from_official_state():
    state_path = os.path.join(home, ".codex-global-state.json")
    db_path = os.path.join(home, "state_5.sqlite")
    if not os.path.exists(state_path):
        return False
    try:
        with open(state_path, "r", encoding="utf-8", errors="ignore") as handle:
            state = json.load(handle)
    except Exception:
        return False

    roots = ordered_workspace_roots(state)
    if not roots:
        return False

    official_roots = set()
    for root in roots:
        official = add_official_project(root)
        if official:
            official_roots.add(official)

    hints = state.get("thread-workspace-root-hints", {}) or {}
    for row in top_level_threads(db_path):
        cwd = existing_directory(row["cwd"])
        if not cwd:
            continue
        candidates = []
        hinted_root = existing_directory(hints.get(row["id"]))
        if hinted_root:
            candidates.append(hinted_root)
        candidates.append(cwd)
        if is_codex_worktree_path(cwd):
            candidates.append(main_worktree(cwd))
        root = next((candidate for candidate in candidates if candidate in official_roots), None)
        if root not in official_roots:
            continue
        paths[root]["sessionPaths"].add(root)
        paths[root]["sessionPaths"].add(cwd)
        if int(row["archived"] or 0) == 0:
            paths[root]["discoveredSessionCount"] += 1
        else:
            paths[root]["archivedSessionCount"] += 1
        paths[root]["lastDiscoveredAt"] = max(paths[root]["lastDiscoveredAt"] or 0, int(row["updated_at"]))
    return bool(official_roots)


def discover_from_thread_database():
    db_path = os.path.join(home, "state_5.sqlite")
    rows = top_level_threads(db_path)
    if not rows:
        return False

    found = False
    for row in rows:
        cwd = existing_directory(row["cwd"])
        if not cwd or is_hidden_project_path(cwd):
            continue
        if int(row["archived"] or 0) == 0:
            add_project_path(cwd, active_thread_count=1, last_seen_at=int(row["updated_at"]))
        else:
            add_project_path(cwd, archived_thread_count=1, last_seen_at=int(row["updated_at"]))
        found = True
    return found


discovered_official_projects = discover_from_official_state()
discovered_thread_database = discovered_official_projects or discover_from_thread_database()

config = os.path.join(home, "config.toml")
if not discovered_thread_database and os.path.exists(config):
    try:
        text = open(config, "r", encoding="utf-8", errors="ignore").read()
        for match in re.finditer(r'^\s*\[projects\."([^"]+)"\]', text, flags=re.MULTILINE):
            path = existing_directory(match.group(1))
            if path:
                add_official_project(path, last_seen_at=int(os.path.getmtime(config)))
    except Exception:
        pass

result = [
    {
        "path": path,
        "sessionPaths": sorted(value["sessionPaths"]),
        "discoveredSessionCount": value["discoveredSessionCount"],
        "archivedSessionCount": value["archivedSessionCount"],
        "lastDiscoveredAt": value["lastDiscoveredAt"],
    }
    for path, value in paths.items()
]
result.sort(key=lambda item: (item["lastDiscoveredAt"] or 0, item["path"]), reverse=True)
print(json.dumps(result[:MAX_PROJECTS]))
""".trimIndent()

    val shellCommand: String
        get() = shellCommand()

    fun shellCommand(targetShellRCFile: String = RemoteServerLaunchDefaults.targetShellRCFile): String =
        listOf(
            RemoteCodexAppServerCommand.environmentBootstrapCommand(targetShellRCFile),
            "python3 - <<'PY'\n$pythonSource\nPY\nmobidex_status=\$?;exit \$mobidex_status",
        ).joinToString("; ")

    @Throws(RemoteCodexDiscoveryException::class)
    fun decodeProjects(output: String): List<RemoteProject> {
        try {
            return discoveryJson.decodeFromString<List<RemoteProjectWire>>(output).map { project ->
                RemoteProject(
                    path = project.path,
                    sessionPaths = project.sessionPaths ?: listOf(project.path),
                    discoveredSessionCount = project.discoveredSessionCount,
                    archivedSessionCount = project.archivedSessionCount,
                    lastDiscoveredAtEpochSeconds = project.lastDiscoveredAt,
                )
            }
        } catch (error: Throwable) {
            val preview = DecodePreview.preview(output)
            val details = listOfNotNull(
                error.message?.takeIf { it.isNotBlank() },
                preview.takeIf { it.isNotBlank() }?.let { "Output: $it" },
            ).joinToString(" ")
            throw RemoteCodexDiscoveryException(details.ifBlank { "output was not valid discovery JSON" })
        }
    }

    private val discoveryJson = Json {
        ignoreUnknownKeys = true
    }
}

@Serializable
private data class RemoteProjectWire(
    val path: String,
    val sessionPaths: List<String>? = null,
    val discoveredSessionCount: Int,
    val archivedSessionCount: Int = 0,
    val lastDiscoveredAt: Long? = null,
)

private object DecodePreview {
    fun preview(value: String, limit: Int = 320): String {
        val trimmed = value.trim().replace('\n', ' ')
        return if (trimmed.length <= limit) trimmed else "${trimmed.take(limit)}..."
    }
}
