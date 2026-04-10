## 2026-04-10 - Missing Haptic Feedback for Game Events and UI
**Learning:** Haptic feedback was completely absent from the centralized `_drainAudioCue` and the `_StepperButton` UI component, missing an opportunity for tactile confirmation of critical game states and interactions.
**Action:** Integrate `HapticFeedback` (lightImpact, mediumImpact, selectionClick) alongside audio cues and UI interactions to provide a multi-sensory feedback layer.
