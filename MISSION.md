Mission: Fix the TestFlight crash and make New Session reliable, clear, and ready-to-type from a selected project.

Done criteria:
- Identify the SwiftUI control and code path involved in long pressing the blue button.
- Confirm the likely crash mechanism from code and the provided crash stack.
- Implement the smallest clear fix, without legacy compatibility paths.
- Make the New Session button path deterministic enough for the smoke UI flow to reach the composer.
- Let a selected project open the New Session chooser without waiting on refresh or app-server state.
- Start cleanly from either worktree or project directory, connecting first when needed and surfacing errors.
- Prevent stale session refreshes from pulling the UI back to an older chat while a new session starts.
- Focus the composer after a fresh session is created.
- Add or update focused regression coverage where practical.
- Build or run the most relevant available checks.

Guardrails:
- Keep the fix scoped to the long-press crash path.
- Keep related New Session changes scoped to the same SwiftUI button/context-menu surface.
- Prefer one obvious New Session flow over preserving flickery or stale-selection behavior.
- Check the corresponding native client only if the same state/model issue is shared.

Critical learnings:
- The likely blue button is the composer send button in `ConversationView`.
- Its long-press context menu was attached even when the selected thread was not active, producing an empty menu body.
- The crash stack is consistent with UIKit/TextInputUI presenting long-press menu UI and SwiftUI/AttributeGraph aborting before app code appears in the stack.
- Subagent review confirmed the root cause and found Android/shared unaffected because Android only opens send options for an active turn.
- Validation: iOS simulator build succeeded, and simulator tests passed with 158 passed, 0 failed, 1 skipped.
- Attempted tap-level UI smoke coverage for the long press, but the existing new-session setup path did not reach the composer before the send-button step; no UI test change was kept.
- The New Session path also used `Button` plus hidden context-menu choices plus a separate confirmation dialog, which made tap behavior inconsistent in the toolbar smoke path.
- New Session is now an explicit menu in both the toolbar and project header, so tap and choice presentation use one SwiftUI primitive.
- The tap-level smoke fixture uses a plain temp project directory, so its visible UI path should start in the project directory after confirming the New Worktree option is present.
- The control smoke's second message must use the active-turn context menu's "Steer Active Turn" option; a plain send tap correctly queues while the turn is active.
- New Session must not depend on session refresh finishing; the chooser is a project-level action.
- Starting a new session now clears the visible old session and suppresses auto-selection before connecting/creating, so background list loads cannot pull the UI back to stale chat.
