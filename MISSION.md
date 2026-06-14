# Mission

Mission: Merge the projectless chats fix into `master` and cut new iOS TestFlight and Android signed release versions from that state.

Done criteria:
- [x] Fetch and update `master` from `origin/master`.
- [x] Merge `codex/folderless-chats-rebased` into `master`.
- [x] Run required iOS, Android, and shared validation after merge.
- [x] Cut/upload the next TestFlight build from `master`.
- [x] Bump Android to the matching release code and build a signed APK.
- [x] Record release details, commit, and push `master`.

Guardrails:
- Build release artifacts only from an up-to-date `master`.
- Do not create unsigned Android release output when the request is for a signed APK.
- Keep generated build products and secret files out of git.

Critical learnings:
- `master` fast-forwarded from `789bdef` to `d4f5e2c` with the projectless chats feature.
- ASC TestFlight workflow resolves the next iOS build number from App Store Connect.
- Validation passed: shared core, iOS build, full simulator XCTest gate, Android focused session test, and signed release APK verification.
- Internal TestFlight build `1.0 (50)` uploaded with BUILD_ID `a0139f63-e234-49f3-9708-aca34b8f8142`; external submission also succeeded.
- The first TestFlight archive attempt failed because the login keychain was not usable from the non-interactive shell; retrying with the generated distribution key/certificate in a temporary keychain fixed signing.
- Android APK `Mobidex-1.0-50-release.apk` was built with `versionCode 50` and verified with APK Signature Scheme v2.
