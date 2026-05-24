Mission: Validate the review findings in the available review artifact and fix any confirmed Mobidex defects.

Done criteria:
- Sync the worktree with the latest `origin/master`.
- Locate and parse the requested review file or the nearest matching review artifact.
- Classify review claims as confirmed, not reproducible, or already addressed.
- Fix confirmed defects only, with focused regression coverage when code changes are needed.
- Run a subagent review after each coherent chunk of review/fix work.
- Run focused verification for the validated scope.

Guardrails:
- Respect the current detached worktree and do not rewrite unrelated state.
- Prefer hard, simple fixes over compatibility shims or dead paths.
- Keep iOS and Android behavior aligned when the same state/model issue exists in both clients.
- Do not invent findings from historical review-log entries that already include fixes and verification.

Critical learnings:
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
