# Van Solè v0.1.1

Release date: 2026-03-14
Build version: `0.1.1+2`

## Highlights

- Full-resolution flight rendering replaces the earlier low-resolution cockpit presentation in live play.
- The immersive viewport now uses the available window area, with deeper space backdrops, updated post-processing, and stronger ship readability.
- Hover tooltips now cover the interactive shell controls for desktop usability.

## Verification

- `flutter analyze`
- `flutter test -r compact`
- `flutter test tool/capture_playing_view_test.dart --update-goldens`
- `flutter run -d macos --no-resident`
