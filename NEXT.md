## Long Press Blue Button Crash

- [x] Locate the blue button and long-press/context-menu path.
- [x] Confirm the crash cause from code and stack evidence.
- [x] Implement the smallest fix.
- [x] Run subagent review and address confirmed findings.
- [x] Run focused tests/build checks.

## New Session Button Weirdness

- [x] Reproduce and localize the smoke failure around `projectNewSessionButton`.
- [x] Fix the New Session tap/long-press path.
- [x] Add or restore UI regression coverage for the send-button long press.
- [x] Run subagent review and address confirmed findings.
- [x] Run focused tests and tap-level smoke.
- [x] Make New Session available from a selected project independent of refresh/app-server timing.
- [x] Suppress stale session selection while a new session is starting.
- [x] Focus the fresh composer after successful session creation.
- [x] Add model regression tests for disconnected start and stale refresh suppression.
- [x] Run subagent review and address confirmed findings for the stronger New Session flow.
- [x] Run focused model/UI checks.

## TestFlight External

- [x] Confirm current branch and signing failure state.
- [x] Make app-target Release signing fully App Store distribution scoped.
- [x] Validate distribution configuration.
- [x] Pin TestFlight export signing to exact App Store profile.
- [x] Upload build to TestFlight.
- [x] Submit build to external testers.

## Parked

- [ ] Split Ad Hoc signing from Release App Store signing if the Ad Hoc workflow is still needed.
