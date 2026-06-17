# Mission

Mission: Publish Mobidex build 53 to Internal and External TestFlight from latest `master`.

Done criteria:
- [x] Pull latest `origin/master`.
- [x] Commit the Linux-focused remote worktree session fix on `master`.
- [x] Bump Android release metadata to match the next TestFlight build number.
- [x] Validate distribution configuration and release build inputs.
- [x] Upload iOS TestFlight build 53 to Internal Testers.
- [x] Verify external TestFlight review metadata.
- [x] Submit build 53 to External Testers.
- [x] Record build IDs/run status in release notes.
- [x] Push updated `master`.

Guardrails:
- Build from up-to-date `master`.
- Keep iOS and Android build numbers aligned.
- Do not change unrelated signing or release workflow configuration.

Critical learnings:
- The current Mobidex release works against this Mac over Tailscale, so build 53 targets Linux/framework-specific worktree creation fragility rather than a generic remote-session failure.
- Direct SSH/TCP 22 from this environment to `framework.tail866988.ts.net` timed out, so validation is focused on command shape, client timeout behavior, and release distribution.
- Use `/Users/mazdak/.codex/worktrees/8d76/mobidex` for release work because it is the `master` worktree with `.secrets` and `.asc/runs`.
- Internal and external TestFlight build 53 BUILD_ID is `546234ac-df0d-49a7-8eff-83f50b9da0d4`.
- The first archive attempt failed until the repo-generated distribution key/certificate and Apple WWDR G3 intermediate were imported into a temporary keychain; the workflow then resumed successfully.
