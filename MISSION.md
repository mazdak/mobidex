# Mission

Mission: Review changes against master merge base 8929571a6860474df39ff392a8f7a8c98a7968ed and report prioritized actionable findings.

Done criteria:
- Inspect repo instructions and current diff.
- Identify discrete introduced bugs with precise locations.
- Return findings in required JSON schema.

Guardrails:
- Do not modify production code.
- Keep review comments brief and actionable.
- Only flag issues introduced by the patch that the author would likely fix.

Checklist:
- [x] Inspect diff against merge base.
- [x] Analyze changed code for bugs.
- [x] Produce JSON review verdict.

Critical learnings:
- iOS build and shared-core tests pass, but review found correctness issues in session refresh and ACP session reopening.
