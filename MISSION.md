# Mission

Mission: Reproduce and fix the iOS new-worktree session launch hang/error where `thread/list` times out after starting a session.

Done criteria:
- [x] Pull latest `origin/master`.
- [x] Trace the iOS new-worktree start path and identify where `thread/list` is being invoked or cancelled.
- [x] Reproduce or emulate the server/client sequence for a new-worktree start.
- [x] Implement the smallest fix that keeps new-worktree sessions visible without blocking launch on an expensive list refresh.
- [x] Add focused regression coverage.
- [x] Run focused validation.
- [ ] Commit and push the fix if behavior is corrected.

Guardrails:
- Keep the fix aligned with Codex app-server behavior, not a local-path special case.
- Avoid hiding real start-session failures; only decouple non-critical refresh work if proven to be the blocker.
- Check Android if the same state/model issue exists there.

Critical learnings:
- Screenshots show the iOS launch overlay stuck on “Starting New Session...” while surfacing either `Swift.CancellationError` or a `thread/list` 30-second timeout.
- iOS allowed New Session while `refreshingSessions` was active; Android already blocks this through its `isBusy` predicate.
- Notification-driven iOS thread-list refresh errors were foregrounded through `statusMessage`, so a background `thread/list` timeout could appear in the new-session empty state.
