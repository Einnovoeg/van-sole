# Changelog

All notable changes to this project will be documented in this file.

## [0.1.1] - 2026-03-14

### Changed

- Reworked the live flight view to render at the real window resolution instead of a fixed low-resolution cockpit buffer.
- Expanded the immersive play viewport to use the full play surface when the standalone HUD shell is hidden.
- Added a new deep-space backdrop, stronger bloom/post-processing, larger ship presence, and tighter opening scene composition for a more modern 3D presentation.
- Added hover tooltips to interactive shell controls including title actions, touch controls, market actions, power routing, upgrades, dock services, comms responses, and save/load actions.

### Removed

- Removed the untracked cockpit frame asset path so the shipped build does not depend on those extra HUD images.

### Verified

- `flutter analyze`
- `flutter test -r compact`
- `flutter test tool/capture_playing_view_test.dart --update-goldens`
- `flutter run -d macos --no-resident`

## [0.1.0] - 2026-03-13

### Added

- Initial public release of Van Solè.
- Cross-platform Flutter game shell for macOS, Windows, Linux, Android, iOS, and web.
- Playable exploration, combat, docking, trading, harvesting, comms, and campaign systems.
- Save-code export/import workflow.
- Golden capture test for the main playing view.

### Changed

- Renamed the standalone package, app metadata, and public documentation to Van Solè.
- Removed legacy reference-review tooling, unused copied asset hooks, and dead startup dependencies.
- Cleaned package metadata, platform display names, and release documentation for public distribution.
- Added targeted code comments around the simulation loop and renderer entry points.

### Fixed

- Removed stale startup code that depended on an unneeded window-management package.
- Removed generated references to non-project media from the shipped source tree.
- Updated tests to match the standalone public app shell.

### Verified

- `flutter analyze`
- `flutter test -r compact`
- `flutter test tool/capture_playing_view_test.dart --update-goldens`
- `flutter run -d macos --no-resident`
