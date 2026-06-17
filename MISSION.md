# Mission

Mission: Publish Mobidex build 53 to Internal and External TestFlight from latest `master`.

Done criteria:
- [x] Pull latest `origin/master`.
- [x] Commit the Linux-focused remote worktree session fix on `master`.
- [x] Bump Android release metadata to match the next TestFlight build number.
- [ ] Validate distribution configuration and release build inputs.
- [ ] Upload iOS TestFlight build 53 to Internal Testers.
- [ ] Verify external TestFlight review metadata.
- [ ] Submit build 53 to External Testers.
- [ ] Record build IDs/run status in release notes.
- [ ] Push updated `master`.

Guardrails:
- Build from up-to-date `master`.
- Keep iOS and Android build numbers aligned.
- Do not change unrelated signing or release workflow configuration.

Critical learnings:
- The current Mobidex release works against this Mac over Tailscale, so build 53 targets Linux/framework-specific worktree creation fragility rather than a generic remote-session failure.
- Direct SSH/TCP 22 from this environment to `framework.tail866988.ts.net` timed out, so validation is focused on command shape, client timeout behavior, and release distribution.
- Use `/Users/mazdak/.codex/worktrees/8d76/mobidex` for release work because it is the `master` worktree with `.secrets` and `.asc/runs`.
