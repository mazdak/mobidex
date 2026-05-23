Mission: Add a clear swipe-right affordance for steering a queued message into the active turn.

Done criteria:
- Confirm whether a queued-message swipe-to-steer gesture already exists.
- Add the smallest queued-row swipe action that sends the queued item through the existing steer path.
- Keep the action available only when it can steer an active turn.
- Preserve existing queue management and send-button behavior.
- Run focused checks for the changed SwiftUI surface.

Guardrails:
- Do not introduce a second steering backend path.
- Do not change queued-message behavior except where required by the new gesture.
- Keep the interaction immediate because the requested gesture is "steer now."

Critical learnings:
- No queued-message swipe-right action existed; steering was available from the queued-message sheet context menu.
- `AppViewModel.steerQueuedTurnInputNow(_:)` already performs the immediate steer and restores the queue item on send failure, so the row gesture can reuse existing model behavior.
- Validation: simulator build passed, and the focused composer/queued-steer model test passed.
