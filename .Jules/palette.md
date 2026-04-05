## 2026-04-05 - [Haptic Feedback Integration]
**Learning:** Integrating `HapticFeedback` alongside `SystemSound` in a centralized method (`_drainAudioCue`) provides a consistent multi-sensory feedback layer that enhances immersion, especially during high-intensity combat.
**Action:** Always pair tactile feedback with audio cues for game state changes and ensure interactive UI elements (like `_StepperButton`) provide immediate tactile confirmation.

## 2026-04-05 - [Properly Wrapping Nullable Callbacks]
**Learning:** When wrapping a nullable callback to add side effects (like haptics), it's crucial to preserve the `null` state to ensure the underlying widget (e.g., `InkWell`) correctly renders its disabled state.
**Action:** Use the pattern `onTap: original == null ? null : () { original!(); effect(); }`.
