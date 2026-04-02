## 2025-05-14 - Integrated Tactile Feedback Pattern
**Learning:** For a high-intensity space RPG, haptic feedback provides a critical non-visual layer that helps players distinguish between different game events (firing vs. being hit vs. status changes). Centralizing this in the audio cue handler ensures sensory synchronization.
**Action:** Always pair 'HapticFeedback' calls with corresponding 'SystemSound' calls within the centralized '_drainAudioCue' method to ensure consistent multi-sensory feedback for state changes.
