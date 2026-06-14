package mobidex.shared

object RemoteCodexWorktreeCommand {
    fun shellCommand(projectPath: String): String =
        """
        set -eu
        root_log=${'$'}(mktemp "${'$'}{TMPDIR:-/tmp}/mobidex-worktree-root.XXXXXX")
        log=""
        cleanup() {
          rm -f "${'$'}root_log"
          [ -z "${'$'}log" ] || rm -f "${'$'}log"
        }
        trap cleanup EXIT
        if ! root=${'$'}(git -C ${projectPath.shellQuoted()} rev-parse --show-toplevel 2>"${'$'}root_log"); then
          printf 'git rev-parse failed for project path: ' >&2
          cat "${'$'}root_log" >&2
          exit 1
        fi
        name=${'$'}(basename "${'$'}root" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^-*//;s/-*${'$'}//')
        [ -n "${'$'}name" ] || name=repo
        parent="${'$'}HOME/.codex/worktrees"
        mkdir -p "${'$'}parent"
        if ! base=${'$'}(mktemp -d "${'$'}parent/XXXXXX" 2>"${'$'}root_log"); then
          printf 'could not create Codex worktree directory: ' >&2
          cat "${'$'}root_log" >&2
          exit 1
        fi
        target="${'$'}base/${'$'}name"
        log=${'$'}(mktemp "${'$'}{TMPDIR:-/tmp}/mobidex-worktree-add.XXXXXX")
        GIT_TERMINAL_PROMPT=0 git -C "${'$'}root" worktree add --detach "${'$'}target" HEAD >"${'$'}log" 2>&1 &
        worktree_pid=${'$'}!
        elapsed=0
        while kill -0 "${'$'}worktree_pid" 2>/dev/null; do
          if [ "${'$'}elapsed" -ge 25 ]; then
            kill "${'$'}worktree_pid" 2>/dev/null || true
            wait "${'$'}worktree_pid" 2>/dev/null || true
            printf 'git worktree add timed out after 25 seconds. ' >&2
            cat "${'$'}log" >&2
            rm -rf "${'$'}target"
            rmdir "${'$'}base" 2>/dev/null || true
            exit 124
          fi
          sleep 1
          elapsed=${'$'}((elapsed + 1))
        done
        if ! wait "${'$'}worktree_pid"; then
          printf 'git worktree add failed: ' >&2
          cat "${'$'}log" >&2
          rm -rf "${'$'}target"
          rmdir "${'$'}base" 2>/dev/null || true
          exit 1
        fi
        printf '%s\n' "${'$'}target"
        """.trimIndent()
}

private fun String.shellQuoted(): String = "'${replace("'", "'\"'\"'")}'"
