## 2025-05-14 - Tactile Feedback for Game Events and UI
**Learning:** Adding haptic feedback (tactile confirmation) significantly enhances the "feel" of a space combat game, especially when paired with audio cues. Differentiating haptic intensity (light vs. medium vs. click) helps users distinguish between frequent actions (firing) and significant state changes (taking hits or docking).
**Action:** Always pair 'HapticFeedback' calls with corresponding 'SystemSound' calls in centralized feedback methods like '_drainAudioCue' to ensure a multi-sensory experience.
