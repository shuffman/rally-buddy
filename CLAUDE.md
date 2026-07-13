# Rally Buddy

A native iOS driving companion, tongue-in-cheek named after a rally co-driver.
The driver marks road features (passing lanes, residential zones, tight
corners) on roads they drive; while driving, the app tracks position and calls
out what's ahead — spoken audio plus a glanceable heads-up view.

## Product decisions (agreed 2026-07-12)

- **Native SwiftUI**, iOS 18+. A web app may follow later, built separately.
- **On-device only.** No backend, no accounts. Persistence via SwiftData.
- **User-annotated data.** The user marks features themselves on the map;
  no derivation from OSM or other map data.
- **Companion mode first.** No destination entry or routing in v1; the app
  watches the road you're on. Design should not preclude adding routing later.
- **Delivery:** audio callouts + visual heads-up view now; CarPlay later
  (note: CarPlay requires a driving-task/navigation entitlement approved by
  Apple — apply well before that milestone).

## Build

Requires Xcode and XcodeGen (`brew install xcodegen`). The `.xcodeproj` is
generated and gitignored.

```sh
xcodegen generate   # after editing project.yml or adding/removing files
xcodebuild -project RallyBuddy.xcodeproj -scheme RallyBuddy \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Architecture

- `Models/RoadFeature.swift` — SwiftData model. A feature is a point with a
  type, optional travel-direction bearing (nil = both directions), and note.
- `Services/LocationService.swift` — CLLocationManager wrapper (@Observable);
  best-for-navigation accuracy, background updates while a drive is active.
- `Services/AlertEngine.swift` — pure-ish logic: given a location + features,
  computes what's ahead (distance + heading cone) and announces each feature
  once per approach via SpeechService.
- `Services/SpeechService.swift` — AVSpeechSynthesizer with audio ducking.
- `Views/` — three tabs: Drive (HUD), Map (tap to mark features), Features
  (list/delete).

## Open questions / recorded assumptions

- **Units:** metric (km/h, meters) hard-coded for v1. Should become
  locale-aware or a setting.
- **Spans vs points:** passing lanes and residential zones are really spans
  (start/end), but v1 models every feature as a point. Revisit when it hurts.
- **Alert tuning:** lookahead 600 m, 50° heading cone, re-announce after
  leaving 1.5× lookahead — all untested guesses; tune on real drives.
- **Background location UX** and CarPlay entitlement are deferred.
