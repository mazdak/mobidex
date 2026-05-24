Mission: Remove misleading loading UI around session resume, prevent duplicate refreshes while content is loading, and keep queued messages visible when they auto-send.

Done criteria:
- Explain what the screenshot is and why it can appear after a long resume.
- Remove the placeholder from the detail/conversation pane so refreshing sessions does not look like a real page.
- Keep toolbar reload disabled or visibly busy while project/session refresh work is in flight.
- Ensure queued messages do not disappear after auto-starting; once accepted by the server they should appear in the selected conversation.
- Check the same state in both native clients and keep behavior aligned.
- Run a focused review and tests for the changed labels/UI logic.

Guardrails:
- Do not change session fetching, reconnect, or selection semantics unless the UI-only fix proves insufficient.
- Keep real empty states for projects with no sessions.
- Leave the session list's loading state intact because that is where loading status belongs.

Critical learnings:
- The screenshot is the selected-project detail fallback: a project is selected, no thread is selected yet, and session refresh is active.
- Review finding: keep real project chrome visible during refresh; only the fake centered empty-state copy should disappear.
- Validation: `MobidexTests`, Android `ProjectLabelsTest`, and `git diff --check` passed after the fix.
- Refresh action: toolbar reload now disables and shows a spinner for the active project/session refresh mode until completion or failure clears the refresh flag.
- Validation: refreshed patch passed subagent review, `MobidexTests`, Android `ProjectLabelsTest`, and `git diff --check`.
- Queue visibility: accepted queued input now gets a local user echo when `turn/start` omits user items, and sparse lifecycle/read updates preserve that echo until a real `userMessage` replaces it.
- Review finding: the iOS replacement also has to update `selectedThread.turns`, and Android must cache the preserved display thread in the current-thread hydration path.
- Validation: queued-message patch passed subagent review, `MobidexTests`, Android `ProjectLabelsTest`, Android debug Kotlin compile, and `git diff --check`.
