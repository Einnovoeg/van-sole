## 2025-05-15 - Tactile Game Feedback & Accessible Form Context

**Learning:** In single-file Flutter games, centralized event handling (like `_drainAudioCue`) is the ideal point to inject multi-sensory feedback like `HapticFeedback` to ensure consistency across combat, docking, and UI events. Additionally, `TextField` inputs in games often lack persistent context if they rely only on `hintText`, making `labelText` essential for accessibility and long-term usability.

**Action:** Always pair audio cues with corresponding haptic impacts (`lightImpact` for weapons, `mediumImpact` for collisions/docking) and ensure all dialog inputs have persistent labels.
