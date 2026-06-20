# Mission

Mission: Fix qlaw/scoped Codex thread visibility on current `master`, remove stale Android tests, and ship Mobidex to Internal and External TestFlight.

Done criteria:
- [x] Pull latest `origin/master` and work from current `master`.
- [x] Port the scoped thread-list fix without dragging older build-49 conflicts onto build-55 code.
- [x] Remove stale Android tests that wait for ignored folder `thread/started` events to refresh.
- [x] Run focused Android/iOS verification from current `master`.
- [ ] Build and upload a new TestFlight build for Internal and External testers.

Guardrails:
- Build release artifacts only from up-to-date `master`.
- Keep `thread/loaded/list` out of project discovery/list visibility.
- Preserve current build-55 release changes while porting only the missing scoped-list behavior.

Critical learnings:
- The attempted merge from the build-49 work branch conflicted broadly because `master` has advanced through build 55 with overlapping folderless/session changes.
- Current `master` already had several newer session-list pieces, but still exact-listed every saved project `sessionPath` during bounded refresh before the unscoped grouped query.
- The qlaw handoff failure requires bounded refresh to exact-list only the primary project cwd, then run the unscoped grouped query promptly; existing visible rows are retained until the exhaustive background load reconciles.
- The stale Android tests timed out because they waited for folder `thread/started` events to trigger `thread/list` refreshes in scopes where those events should be ignored.
- Verification on current `master`: Android `AppViewModelNewSessionTest`, iOS `MobidexTests` build, iOS `Mobidex` build, and focused qlaw AppViewModel XCTest cases pass.
