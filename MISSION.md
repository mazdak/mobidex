# Mission

Mission: Publish Mobidex build 52 to external TestFlight from latest `master`.

Done criteria:
- [x] Pull latest `origin/master`.
- [x] Confirm build 52 internal TestFlight BUILD_ID.
- [x] Verify external TestFlight review metadata.
- [x] Submit build 52 to External Testers.
- [x] Record external submission run/status in release notes.

Guardrails:
- Build from up-to-date `master`.
- Keep iOS and Android build numbers aligned.
- Do not create a new internal build.
- Do not change unrelated signing or release workflow configuration.

Critical learnings:
- Internal build 52 BUILD_ID is `0af77bee-af08-4e5b-bd2e-58f3ca367bcc`.
- The active 7e2e worktree lacks `.secrets`; run `asc` from sibling worktree `8d76/mobidex`, which is on the same `origin/master` commit.
- External TestFlight run `.asc/runs/testflight_external-20260616T131716Z-85d3180e.json` completed with status ok and submitted build 52 for beta app review.
