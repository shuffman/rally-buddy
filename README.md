# Rally Buddy

Your co-driver for everyday roads. Mark passing lanes, residential zones, and
tight corners on roads you drive — Rally Buddy watches your position and calls
them out before you reach them, like a rally co-driver reading pace notes.

Native SwiftUI iOS app. All data stays on your device.

**[Join the beta on TestFlight →](https://testflight.apple.com/join/Yfgj5x49)**

## Documentation

- **[User guide / help](docs/HELP.md)** — installing, marking features,
  driving, planning and sharing routes, troubleshooting
- **[CLAUDE.md](CLAUDE.md)** — product decisions, architecture, build and
  TestFlight release process, roadmap

## Features

- **Driver-centric drive screen** — full-screen map, heading-up follow
  camera, big one-tap buttons to mark features without looking, speed
  readout, and a callout banner
- **Spoken callouts** — "Tight corner in 450 meters", ducking your music
  like a good co-driver
- **Planned routes** — tap waypoints on a map; the path snaps to real
  roads via MKDirections
- **Route sharing** — AirDrop a route and every marked feature along it as
  a `.rallybuddy` file; opening one imports it, duplicates skipped

Planned: CarPlay, live peer-to-peer nearby sync, off-route detection.

## Development

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The `.xcodeproj` is generated and gitignored.

```sh
xcodegen generate
open RallyBuddy.xcodeproj
```

Run on a device or simulator — in the simulator, use **Features →
Location → Freeway Drive** to simulate movement, after marking a few
features along the simulated highway.

Build from the command line:

```sh
xcodebuild -project RallyBuddy.xcodeproj -scheme RallyBuddy \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

TestFlight releases: see the "TestFlight release" section of
[CLAUDE.md](CLAUDE.md).
