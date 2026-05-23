Mission: Submit the current Mobidex iOS build to external TestFlight.

Done criteria:
- `master` is up to date with `origin/master`.
- Release signing can archive for App Store distribution.
- A TestFlight build uploads successfully.
- The uploaded build is submitted to the external TestFlight group.

Guardrails:
- Keep Debug signing automatic for local development.
- Do not apply app provisioning settings to Swift package or test targets.
- Do not expose signing secrets or tokens in notes.

Critical learnings:
- Release archives were using automatic development signing while a distribution identity was specified.
