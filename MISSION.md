# Mission

Mission: Build and publish Mobidex build 52 from latest `master`, producing TestFlight and signed Android artifacts.

Done criteria:
- [x] Pull latest `origin/master`.
- [x] Bump Android release metadata to match the next TestFlight build number.
- [x] Upload iOS TestFlight build 52 to Internal Testers.
- [x] Build and verify signed Android release APK 52.
- [x] Record artifact paths/run IDs in release notes.
- [x] Commit and push release metadata.

Guardrails:
- Build from up-to-date `master`.
- Keep iOS and Android build numbers aligned.
- Do not change unrelated signing or release workflow configuration.

Critical learnings:
- Last recorded iOS/Android release was build 51.
- `asc` resolves the next iOS build number automatically; Android versionCode must be bumped manually.
- The iOS archive needs the current Apple WWDR G3 intermediate when using the repo-generated distribution certificate/key from a temporary keychain.
