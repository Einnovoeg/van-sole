## 2026-03-31 - [Haptic Feedback for Core Game Events]
**Learning:** Integrating Haptic Feedback with Audio Cues in the centralized `_drainAudioCue` method provides a multi-sensory confirmation of state changes, which is particularly useful in high-intensity combat where visual focus is elsewhere.
**Action:** Always pair `HapticFeedback` with `SystemSound` in the `_drainAudioCue` method for consistent sensory feedback.

## 2026-03-31 - [Micro-UX: Stepper Button Feedback]
**Learning:** Adding `HapticFeedback.selectionClick()` to UI controls like `_StepperButton` enhances the perceived responsiveness of the interface.
**Action:** When creating custom interactive widgets, consider adding tactile feedback to the `onTap` handler.
