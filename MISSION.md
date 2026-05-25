Mission: Ship the latest project-add, remote-browser, SSH directory, E2E harness, and recording-indicator fixes to TestFlight internal and external testers.

Done criteria:
- Confirm `master` is based on the latest `origin/master`.
- Commit the release-candidate fixes with a conventional commit.
- Run focused/shared/iOS validation required for the release candidate.
- Push the release commit to `origin/master`.
- Upload a fresh TestFlight build and add it to internal testing.
- Submit the same build to the external TestFlight group for beta review.

Guardrails:
- Build from up-to-date `master`, per repo release policy.
- Prefer hard, simple fixes over compatibility shims or dead paths.
- Do not revert unrelated local changes.
- Do not ship if the release tooling or high-signal validation fails.

Critical learnings:
- `master` was current with `origin/master` before release work; release candidate changes were uncommitted on top of build 32.
- Validation passed for the release candidate: `git diff --check`, `Scripts/verify-ios-distribution-config.sh`, shared-core debug unit tests, XcodeBuildMCP simulator tests (`168 passed, 0 failed, 4 skipped`), real-host remote directory browse smoke, and real-host add discovered project smoke.
- The add-discovered smoke failed once with Xcode exit 65 only when run concurrently with another live-host smoke; rerunning it alone passed.
- `origin/master` and the current `HEAD` both resolve to `b7bfcc1ce6c374b15cf4b46a6c685e7881d881d4`; the worktree is already up to date.
- The requested `REVIEW.md` is not present in this worktree. The available matching artifact is `REVIEW_NOTES.md`.
- `REVIEW_NOTES.md` reads as a historical review log: every listed finding has adjacent fix/verification notes, and the latest completion-audit section ends with no blocking findings.
- Focused validation found two still-real reachability gaps in the latest completion-audit area: iOS compact project taps did not promote to detail, and Android selected-project/no-thread detail did not expose the composer.
- The iOS selected-project empty detail now shows the composer whenever `canSendMessage` is true, and compact project taps promote to detail.
- The iOS tap UI smoke now asserts the project composer is visible before any explicit New Session action.
- Android project selection in compact mode now opens chat detail, and the project-empty conversation pane reuses `ChatTimeline` so the same composer path can start the first thread.
- Subagent review caught an Android callback signature regression in the first patch; fixed by calling the zero-argument `onOpenDetail()`.
- Validation passed: `Scripts/verify-ios-build.sh MobidexTests`, `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" build/gradle-8.13/bin/gradle :android-app:compileDebugKotlin`, `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" build/gradle-8.13/bin/gradle :android-app:testDebugUnitTest`, `Scripts/verify-ios-build.sh Mobidex`, `Scripts/verify-ios-build.sh MobidexUITests`, `MOBIDEX_UI_SMOKE_TIMEOUT=120 Scripts/verify-tap-ui-smoke.sh`, and `git diff --check`.
- Cursor's New Session audit was the intended review input. Follow-up fixes addressed remaining Android parity gaps: disconnected New Session now connects inside the operation, the UI promotes detail only after successful creation, thread opening is blocked during session mutations, and Android `thread/started`/creation adoption is guarded by the selected scope.
- Follow-up validation passed: `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" build/gradle-8.13/bin/gradle :android-app:compileDebugKotlin :android-app:testDebugUnitTest`, `Scripts/verify-ios-build.sh Mobidex`, and `git diff --check`.
- Test polish added Android ViewModel coverage for disconnected New Session connect/start, blocking `openThread` while explicit session creation is in flight, and blocking `openThread` while a send is starting a turn. This required Robolectric, AndroidX test core, and coroutine-test for local JVM coverage.
- Final review pass found and fixed a stuck-`Connecting` Android failure path when disconnected New Session auto-connect fails, with a regression test for the failure state.
- Final validation passed after test polish: focused `AppViewModelNewSessionTest`, full `:shared-core:jvmTest :android-app:testDebugUnitTest`, `Scripts/verify-ios-build.sh Mobidex`, and `git diff --check`.
