# Mission

Mission: Fix Mobidex new-worktree session creation so Ubuntu remote Codex app-server sessions remain visible/selectable after successful creation.

Done criteria:
- [x] Pull latest `origin/master`.
- [x] Reproduce the remote Ubuntu behavior on `spark-d240.tail866988.ts.net`.
- [x] Identify the Mobidex state path that hides or drops the newly-created worktree session.
- [x] Patch the smallest clear client/shared logic in both native clients where applicable.
- [x] Add focused regression coverage for the failure mode.
- [x] Run targeted tests/build checks.
- [x] Review changes and address confirmed findings.

Guardrails:
- Keep the fix scoped to new-session/worktree visibility and project/thread refresh behavior.
- Preserve existing Mac-over-Tailscale behavior that already works.
- Avoid legacy compatibility layers unless the current Codex app-server contract requires them.

Critical learnings:
- On `spark-d240`, direct SSH and `codex app-server proxy` work, and `thread/start` succeeds for a created worktree.
- On the same host, filtered `thread/list` immediately returns no rows for the newly-created empty thread, while `thread/loaded/list` includes it.
- The remaining defect was client-side reconciliation after a successful start rather than shell stderr contamination or failed `git worktree add`.
- `thread/start` is the authoritative creation response; Mobidex now preserves just-started sessions through the empty-list window.
- Project discovery can lag local worktree creation, so project refresh now preserves locally learned session paths instead of replacing them with stale discovery aliases.
- Validated with shared JVM tests, the Android new-session test class, and the targeted iOS AppViewModel regression.
