# Mission

Mission: Disable server-scoped New Chat controls whenever the selected server is not connected.

Done criteria:
- [x] Pull latest `origin/master`.
- [x] Tighten iOS and Android new-session capability predicates to require an active connection.
- [x] Add focused regression coverage for disconnected state.
- [x] Run focused validation.
- [x] Commit and push the fix.

Guardrails:
- Keep the change limited to UI capability/enablement state.
- Preserve existing programmatic start-session behavior unless tests prove it is unsafe.
- Fix both native clients when the same state bug exists.

Critical learnings:
- iOS and Android both allowed `canStartNoFolderSession` while disconnected.
