# Mission

Mission: Ship the new-worktree session fix from `master` to TestFlight and produce a signed Android team APK from the same release state.

Done criteria:
- `master` is up to date with `origin/master` and contains the fix commit.
- TestFlight build `1.0 (49)` is archived, uploaded, compliance-marked, added to `Internal Testers`, and submitted to `External Testers`.
- A signed Android release APK with `versionCode 49` is built and signature-verified.
- Release notes/checklist files are updated and pushed after the artifacts are confirmed.

Guardrails:
- Build release artifacts only from up-to-date `master`.
- Do not create unsigned Android release output when the request is for a signed APK.
- Keep generated build products out of git unless they are already tracked release metadata.

Checklist:
- [x] Confirm fix commit is merged to `master` and pushed to `origin/master`.
- [x] Run the TestFlight workflow for version `1.0`.
- [x] Build and verify the signed Android release APK.
- [x] Record release details in `NEXT.md`.
- [x] Commit and push release metadata, if changed.

Critical learnings:
- `master` and `origin/master` are at `e9aaefe` (`fix(sessions): keep new worktree sessions visible`).
- ASC internal workflow completed build `1.0 (49)` with BUILD_ID `5fdae14f-8861-477c-af69-2992b2e82e6e` and run `.asc/runs/testflight-20260614T002044Z-37ea11a8.json`.
- ASC external workflow completed for `External Testers` with run `.asc/runs/testflight_external-20260614T002631Z-bc51dbac.json`.
- Android release signing requires `.secrets/android-signing.properties` plus the referenced keystore in `.secrets`; those local secret files were copied into this `master` worktree from the existing sibling release worktree and remain gitignored.
- Signed Android APK `Mobidex-1.0-49-release.apk` was built with versionCode `49` and verified with APK Signature Scheme v2.
