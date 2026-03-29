## 2025-05-15 - Haptic Feedback Mapping Pattern
**Learning:** Haptic feedback in this application follows a specific mapping pattern: `lightImpact` for frequent actions (firing), `mediumImpact` for significant events (hits, docking, jumping), and `selectionClick` for UI notifications and status changes (warnings, contracts, comms).
**Action:** Always pair 'HapticFeedback' calls with corresponding 'SystemSound' calls within the '_drainAudioCue' method to ensure consistent multi-sensory feedback for state changes.
