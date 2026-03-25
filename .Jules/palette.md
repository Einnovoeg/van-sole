## 2025-01-24 - Centralizing Tactile Feedback
**Learning:** In a high-intensity action game with complex state changes (like Van Solè), visual-only feedback can be easily missed. Centralizing haptic feedback within established event drains (like `_drainAudioCue`) ensures consistency between audio and tactile cues.
**Action:** Always map game events to specific haptic strengths (light for frequent, medium for impactful, selection for UI) and integrate them alongside existing audio notifications.
