# Mission

Mission: Emulate the iOS "new worktree then start session" flow against the Linux server and determine where the path fails, if it fails.

Done criteria:
- Create or reuse a remote worktree using the same shape as the iOS path.
- Start a Codex app-server thread in that worktree over SSH/stdio.
- Compare list/start behavior with the original project cwd.
- Record whether the failure is in worktree creation, app-server thread start, list scoping, or app-side state/grouping.

Guardrails:
- Keep remote changes limited to a test worktree and test thread/session.
- Clean up or archive test artifacts when safe.
- Do not discard the Android race fix already in progress.

Checklist:
- [x] Verify the remote test worktree exists.
- [x] Start a thread in the remote worktree via app-server stdio.
- [x] Compare thread/list results for worktree cwd and original project cwd.
- [x] Interpret the result against the iOS launch flow.
- [x] Patch confirmed app-side state/model gaps.
- [x] Run focused verification and subagent review.

Critical learnings:
- User confirmed `uuidgen` exists on both Mac and Linux hosts; read-only SSH probing also found `/usr/bin/uuidgen` and `/usr/bin/mktemp` on `framework.tail866988.ts.net`.
- The old iOS shell shape successfully created `/home/mazdak/.codex/worktrees/7e89/mobile` from `/home/mazdak/Code/mobile`, so worktree creation itself is not currently failing on this server for that repo.
- Live app-server emulation on `framework.tail866988.ts.net` showed `thread/start` succeeds for both `/home/mazdak/.codex/worktrees/7e89/mobile` and `/home/mazdak/Code/mobile`; `thread/loaded/list` and `thread/read(includeTurns:false)` can see the new no-turn threads, but scoped `thread/list` returns empty until a first user message materializes the rollout.
- Fix: newly-created Codex worktree paths are now recorded in the owning project's `sessionPaths`, and newly-started threads are temporarily preserved when `thread/list` has not surfaced them yet.
- Review follow-up: event-driven iOS refreshes now use the same preservation path, and worktree failure logs no longer prevent removing failed empty worktree bases.
- Cleanup: the temporary remote test worktree `/home/mazdak/.codex/worktrees/7e89/mobile` was removed.
