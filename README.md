# Van Solè

Van Solè is a cross-platform spacefaring action RPG built with Flutter.

## Features

- Free-flight exploration across connected sectors
- Real-time ship combat with target tracking and power routing
- Docking, outfitting, and ship progression
- Commodity trading, cargo contracts, and resource harvesting
- Lore-driven campaign structure with comms encounters and station reputation
- Save-code export/import for quick persistence across platforms

## Release

- Current release: `v0.1.1`
- Build version: `0.1.1+2`
- Change history: see `CHANGELOG.md`
- Release notes: see `RELEASE_NOTES.md`

## Requirements

- Flutter `3.38.9` or newer on the stable channel
- Dart `3.10.8` or newer
- Platform toolchains for your target:
  - Android: Android SDK and platform tools
  - iOS/macOS: Xcode and CocoaPods
  - Windows: Visual Studio with Desktop C++ workload
  - Linux: GTK 3 development packages and a recent Clang/GCC toolchain

## Install

```bash
flutter pub get
flutter run
```

Examples:

```bash
flutter run -d macos
flutter run -d chrome
flutter run -d windows
```

## Build

```bash
flutter build macos
flutter build apk
flutter build web
```

## Verification

Use the same checks that were used for the release:

```bash
flutter analyze
flutter test -r compact
flutter test tool/capture_playing_view_test.dart --update-goldens
flutter run -d macos --no-resident
```

## Dependencies

A reproducible dependency summary is in `DEPENDENCIES.md`.

## Support

Support development at [buymeacoffee.com/einnovoeg](https://buymeacoffee.com/einnovoeg).

## License

- Project license: MIT. See `LICENSE`.
- Third-party notices: see `THIRD_PARTY_NOTICES.md`.
