# Mission

Mission: Merge the desktop-folderless chat fix into `master` and produce new iOS TestFlight and Android signed APK builds.

Done criteria:
- [x] Pull latest `origin/master` and merge the fix branch into `master`.
- [x] Bump Android release metadata to the new build number.
- [x] Build/upload TestFlight from up-to-date `master`.
- [x] Build signed Android release APK from the same code.
- [x] Record build artifacts/run IDs and push release metadata.

Guardrails:
- Build from `master`, not the feature branch.
- Keep iOS and Android build numbers aligned.
- Do not alter unrelated release/signing config.

Critical learnings:
- Previous release was iOS/Android build 50; this release should be build 51.
- TestFlight build 51 uploaded successfully, compliance was set, and it was added to Internal Testers with build ID `3f1836b0-38d3-4b33-a527-c74905d731da`.
- Android signed APK was built at `.asc/artifacts/Mobidex-1.0-51-release.apk` and verified with APK Signature Scheme v2.
