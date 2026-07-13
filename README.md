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

Early scaffold: map annotation, feature list, drive HUD with spoken callouts.
CarPlay and routing are planned. See `CLAUDE.md` for decisions and roadmap.
