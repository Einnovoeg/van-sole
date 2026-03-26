## 2025-05-14 - Multi-sensory Feedback in Spacefaring RPGs
**Learning:** Integrating `HapticFeedback` (e.g., lightImpact, mediumImpact, selectionClick) alongside `SystemSound` calls in a centralized audio cue handler ensures a consistent tactile experience that complements audio events, which is particularly useful for low-visual-feedback actions like firing or being hit in a space sim.
**Action:** Always pair audio-only feedback with corresponding haptic triggers for primary game interactions to improve immersion and accessibility.

## 2025-05-14 - Form Label Persistency
**Learning:** Using `labelText` instead of `hintText` in Flutter `InputDecoration` ensures that critical context (like the "Save Code" format) remains visible once the user starts typing, preventing cognitive load for users with memory impairments or during long-form data entry.
**Action:** Prioritize `labelText` for important form fields to maintain persistent semantic context.
