## TestFlight Build 33

- [x] Confirm `master` is current.
- [x] Run focused release validation.
- [ ] Push the release commit to `origin/master`.
- [ ] Upload TestFlight build and assign internal testers.
- [ ] Submit the build to external TestFlight review.

## Review Notes Validation

- [x] Sync the detached worktree with `origin/master`.
- [x] Locate the requested review artifact and record the path mismatch.
- [x] Validate the latest potentially actionable review section against code and tests.
- [x] Review the validation/fix chunk with a subagent.
- [x] Run focused verification and record the outcome.
- [x] Add Android New Session ViewModel race tests for disconnected start, blocked open during start, and blocked open during send.
- [x] Fix review-found Android auto-connect failure recovery and add a regression test.

## New Session And SSH Incident

- [x] Make iOS New Session show an immediate visible starting state and phase text.
- [x] Add iOS deadlines for connect/worktree/thread-start so New Session cannot spin forever.
- [x] Add regression tests for iOS New Session timeout/visibility behavior.
- [x] Inventory every visible app page/surface and name the phantom page.
- [x] Fix iOS New Session navigation so it starts/selects a session before showing detail.
- [x] Review the New Session/navigation change with a subagent.
- [x] Fix SSH app-server startup on Mac without breaking Linux/shared Android command generation.
- [x] Review the SSH bootstrap change with a subagent.
- [x] Harden SSH launch against stored/custom interactive shell startup files such as `~/.zshrc`.
- [x] Review the hardened SSH launch fix with a subagent.
- [x] Re-run shared, Android, Xcode, simulator, and SSH smoke validation for the hardened fix.
- [x] Correct SSH launch to source rc files after installing Mobidex's launch PATH.
- [x] Review the corrected rc-sourcing launch fix with a subagent.
- [x] Re-run shared, Android, Xcode, simulator, and SSH smoke validation with real `.zshrc` sourcing.
- [x] Change the default startup file to `.zprofile` and migrate stored `.zshrc` paths.
- [x] Review the `.zprofile` default/migration change with a subagent.
- [x] Re-run shared, Android, Xcode, simulator, and SSH smoke validation for `.zprofile` migration.
- [x] Run focused unit tests, shared/Android checks, xcodebuild tests, and simulator launch/screenshot validation.
- [x] Publish TestFlight build `1.0 (30)` to internal testers and submit it for external beta review.
- [x] Record final critical learnings and remaining risks.
- [x] Replace remote shell startup-file sourcing with explicit SSH execution PATH.
- [x] Validate manual project paths before saving and ask before creating missing folders.
- [x] Review the SSH execution PATH and project path validation changes with a subagent.
- [x] Run shared, Android, Xcode, simulator, and SSH smoke validation.
- [x] Add `.env.test` real-host E2E harness for connection, new session, join, and visible UI New Session paths.
- [x] Validate real Mac SSH connection, project-directory New Session, join existing session, and New Worktree visible UI smoke.
- [x] Review the latest iOS E2E/TestFlight readiness changes with a subagent and apply release-blocking fixes.
- [x] Publish TestFlight build `1.0 (32)` to internal testers and submit it for external beta review.

## Swipe Right Steer Now

- [x] Confirm whether the gesture already exists.
- [x] Add leading swipe action to queued messages.
- [x] Run review/checks and fix findings.

## Parked

- [ ] Split Ad Hoc signing from Release App Store signing if the Ad Hoc workflow is still needed.

## Project Add And Browser Smoke

- [x] Fix discovered-project add from the Add Project sheet.
- [x] Add live-host UI smoke for adding a discovered project.
- [x] Add live-host UI smoke for remote folder browsing.
- [x] Add visible recording activity while audio capture is active.
- [x] Review and run focused/full iOS validation.

## Project Detail Loading Placeholder

- [x] Remove fake project-level session loading page from iOS detail pane.
- [x] Mirror the detail-pane behavior in Android.
- [x] Review the change with a subagent.
- [x] Run focused tests/checks and fix any failures.

## Refresh Button Loading State

- [x] Disable/spin iOS refresh button while current pane is refreshing.
- [x] Disable/spin Android refresh button while current pane is refreshing.
- [x] Review refresh-button change with a subagent.
- [x] Run focused checks after the refresh-button change.

## Queued Message Visibility

- [x] Reproduce/cover queued auto-send disappearing when the turn response has no user item.
- [x] Render accepted queued input optimistically in iOS.
- [x] Mirror optimistic queued input rendering in Android.
- [x] Review queued-message fix with a subagent.
- [x] Run focused checks after the queued-message fix.
