# Mission

Mission: Rebase Bro's folderless Codex chats branch onto current master, verify the Codex cwd semantics from `~/Code/codex`, and reshape the feature to match Mobidex's existing session UI.

Done criteria:
- The contributor branch is integrated on a fresh `codex/` branch rebased onto current `origin/master`.
- Folderless chat detection is based on Codex protocol/source behavior, not a user-specific `Documents/Codex` path guess unless the source proves that convention.
- iOS and Android expose folderless chats through the app's existing toolbar/session controls.
- Existing new-worktree visibility fixes remain intact.
- Focused shared, iOS, and Android tests/build checks pass.

Guardrails:
- Keep the contributor's original branch intact for comparison.
- Prefer hard alignment with app style over backward-compatible UI clutter.
- Avoid broad rewrites outside the folderless-session surface.

Checklist:
- [x] Create a fresh integration branch and start the rebase.
- [x] Resolve Android rebase conflicts while preserving new-worktree session tracking.
- [x] Verify Codex cwd semantics against `~/Code/codex`.
- [x] Replace author-machine-specific folderless path logic.
- [x] Move folderless new-chat entry points into toolbars on iOS and Android.
- [x] Run focused tests/build checks and fix failures.
- [x] Review the final diff with a subagent and address confirmed findings.

Critical learnings:
- Issue #5 points at `george-bucky:codex/non-folder-chats`, commit `5128873`.
- The branch forked before the build-49 new-worktree visibility fix, so conflict resolution must intentionally preserve newly-started thread retention and worktree path tracking.
- Codex app-server accepts optional `thread/start.cwd`, but returned and stored threads always have a concrete absolute `cwd`; no `Documents/Codex` convention exists in `~/Code/codex`.
- Mobidex-created projectless chats are now tracked by app-owned unscoped thread ids rather than inferred from a path shape.
- Swift and Android no-folder thread refreshes now publish state only after the same scope/client generation guards as the main thread list.
