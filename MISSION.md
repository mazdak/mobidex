# Mission

Mission: Verify this exact Mac task is eligible in Mobidex, integrate the completed visibility/UI fixes into current `master`, and submit a new Internal and External TestFlight build.

Done criteria:
- [x] Prove the current task’s source, cwd, discovery mapping, and real app-server listing behavior.
- [x] Review and commit the complete intended release diff.
- [x] Merge onto clean, latest `origin/master` and run release verification.
- [x] Build and upload a new iOS archive from updated `master`.
- [x] Add the build to Internal testers and submit it for External TestFlight review.

Guardrails:
- Release only from an up-to-date, clean `master` worktree.
- Preserve all completed Chats archive/unarchive, `notLoaded`, `source.subAgent`, and exec-filter fixes.
- Do not claim the installed app is fixed until a new build is uploaded; current server-side evidence proves eligibility, not the phone’s installed binary or selected connection.
- Do not treat `.claude/worktrees` as Codex projects.

Critical learnings:
- Current task `019f4973-ea2b-7552-bc22-491f85b4d8f5` is `source=vscode`, not `exec`.
- Production discovery maps its cwd `/Users/mazdak/.codex/worktrees/71a6/mobidex` into `/Users/mazdak/Code/mobidex` and includes that session path.
- A real local app-server `thread/list` using Mobidex’s new source filter returns this exact task ID.
- The release diff received an independent no-findings review and landed on `master` as `d201aba`.
- Shared tests, focused iOS tests, Android assembly, app-server schema, discovery, distribution configuration, and the release iOS build passed. The full Android suite retains one order-dependent `AppViewModelNewSessionTest` baseline failure that passes in isolation.
- TestFlight `1.0 (61)` is `VALID`; App Store Connect reports both Internal and External states `IN_BETA_TESTING`, with beta review `APPROVED`.
