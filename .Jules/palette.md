## 2025-05-15 - [Haptic Feedback Integration in Flutter]
**Learning:** Adding haptic feedback to nullable callbacks requires careful handling to preserve the "disabled" state of the widget. Simply wrapping a callback in an anonymous function makes it non-null, which can lead to UI regressions (e.g., buttons appearing enabled when they should be disabled) and potential crashes.
**Action:** Always use the pattern `onTap: original == null ? null : () { original!(); effect(); }` when adding haptics or other side effects to nullable callbacks in Flutter.
