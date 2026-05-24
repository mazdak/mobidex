## New Session And SSH Incident

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

## Swipe Right Steer Now

- [x] Confirm whether the gesture already exists.
- [x] Add leading swipe action to queued messages.
- [x] Run review/checks and fix findings.

## Parked

- [ ] Split Ad Hoc signing from Release App Store signing if the Ad Hoc workflow is still needed.

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
