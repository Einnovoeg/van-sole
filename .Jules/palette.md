## 2025-05-14 - [Centralized Multi-Sensory Feedback]
**Learning:** For game engines built on UI frameworks like Flutter, centralizing feedback (audio + haptics) in a single drain method (like `_drainAudioCue`) ensures consistency across platform-specific implementations and simplifies the addition of new sensory layers without touching business logic.
**Action:** Always look for centralized event dispatchers or "drain" methods when adding global UI/UX enhancements like haptics or system sounds.

## 2025-05-14 - [Avoiding Test Artifact Contamination]
**Learning:** Automated visual regression tests can generate transient failure artifacts (like `tool/failures/*.png`) that are easily staged if using `git add .` or similar broad commands.
**Action:** Explicitly check `git status` for unexpected binary files or directories like `failures/` before committing, and ensure they are ignored or cleaned up.
