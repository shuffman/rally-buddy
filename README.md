# Rally Buddy

Your co-driver for everyday roads. Mark passing lanes, residential zones, and
tight corners on roads you drive — Rally Buddy watches your position and calls
them out before you reach them, like a rally co-driver reading pace notes.

Native SwiftUI iOS app. All data stays on your device.

## Getting started

```sh
brew install xcodegen   # once
xcodegen generate
open RallyBuddy.xcodeproj
```

Run on a device or simulator (simulate a drive with Debug → Location →
Freeway Drive in the simulator).

## Status

Working early build:

- Driver-centric main screen: full-screen map, one-tap quick-mark buttons
  while driving, speed pill, callout banner, spoken alerts.
- Plan routes ahead of time by tapping waypoints (snapped to roads via
  MKDirections), then select one before a drive.
- Share a route + its datapoints as a `.rallybuddy` file over AirDrop;
  opening one imports it.

CarPlay and live peer-to-peer nearby sync are planned. See `CLAUDE.md` for
decisions and roadmap.
