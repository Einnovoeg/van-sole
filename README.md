# Van Solè

Van Solè is an ambitious cross-platform spacefaring action RPG built with Flutter. Inspired by the classic SolarWinds DOS games, it combines 3D space exploration, real-time combat, and an economic simulation.

## 🚀 Overview

Explore a vast galaxy of connected sectors, engage in tactical ship combat, trade commodities, and complete daring contracts. Upgrade your ship from a humble freighter to a galactic powerhouse.

### Core Gameplay
- **Free-Flight Exploration**: Navigate a pseudo-3D universe with deep-sorted rendering and parallax stars.
- **Tactical Combat**: Manage power between engines, shields, and weapons. Lock onto targets and fire precision weapons or homing missiles.
- **Economy & Trade**: Dynamic commodity markets at stations. Buy low, sell high, and deliver cargo across sectors.
- **Ship Progression**: Upgrade hull, engines, weapons, and cargo capacity. Choose a specialization (Combat, Exploration, Trade, or Survival) to gain unique passive bonuses.
- **Campaign & Lore**: Follow a story-driven campaign, uncover ancient alien relics, and build reputation with various factions.

## 🛠️ Installation

### Prerequisites
- Flutter `3.38.9` or newer (Stable channel)
- Dart `3.10.8` or newer
- Platform toolchains for your target:
  - **macOS**: Xcode and CocoaPods
  - **Windows**: Visual Studio with Desktop C++ workload
  - **Linux**: GTK 3 development packages, Clang/GCC
  - **Android**: Android SDK and platform tools

### Setup
1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/van-sole.git
   cd van-sole
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run -d macos
   ```

## ⚠️ Current State & Known Issues

This project is in active development. While the core loop is functional, the following areas still need work:

- **AI Behavior**: Pirate AI is basic; needs more complex flanking and tactical maneuvers.
- **Performance**: 3D rendering can drop frames in very dense sectors.
- **UI/UX**: The cockpit interface is functional but needs a more modern, polished look.
- **Quest System**: Many campaign missions are linear; needs more branching and emergent objectives.
- **Sound/Music**: Currently uses basic audio cues; needs a full atmospheric soundtrack.

**We need your help!** If you are a Flutter developer or a space-sim enthusiast, please contribute! Open an issue or submit a pull request to help us make Van Solè the ultimate space RPG.

## 📦 Dependencies

Full dependency list can be found in `pubspec.yaml`. Key libraries used:
- `window_manager`: For desktop window control.
- `flutter_riverpod` (or similar state management): For game state handling.

## ☕ Support

Support the development of Van Solè at [buymeacoffee.com/einnovoeg](https://buymeacoffee.com/einnovoeg).

## 📜 License

This project is licensed under the **MIT License**. See the `LICENSE` file for full details.

### Credits
Full credit to the original authors of the SolarWinds DOS series for the inspiration and the foundational gameplay concepts.
