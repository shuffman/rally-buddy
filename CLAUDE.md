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
- **Routes are planned, not recorded** (agreed 2026-07-12): the user taps
  waypoints on a map and MKDirections snaps the path to public roads.
  "Replaying" a route = selecting it before a drive; it draws on the map and
  the normal feature callouts apply.
- **Sharing: AirDrop file first, peer-to-peer later.** Routes export as
  `.rallybuddy` JSON (route + features within 200 m of the path) via
  ShareLink; the app claims the UTI `com.shuffman.rallybuddy.route` so
  receiving via AirDrop opens and imports it (features deduped within 25 m).
  True tap-to-share (NameDrop) is not available to third-party apps;
  MultipeerConnectivity "live nearby sync" is the planned follow-up.
- **Driver-centric main screen:** map is front and center; while driving,
  marking a feature is ONE tap on a big bottom-row button (drops it at the
  current location + course, haptic + spoken confirmation, no announcement
  for self-marked features). Map-tap annotation is only available when not
  driving. Tab bar hides during a drive.
- **MapKit** (agreed 2026-07-12): easiest that's pretty good — no API keys,
  no SDK dependency, free MKDirections routing.

## Build

Requires Xcode and XcodeGen (`brew install xcodegen`). The `.xcodeproj` is
generated and gitignored.

```sh
xcodegen generate   # after editing project.yml or adding/removing files
xcodebuild -project RallyBuddy.xcodeproj -scheme RallyBuddy \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## TestFlight release

ASC credentials live in `~/.keys.yaml` (`app_store_connect:` — API key
4C8LJ62B46, team VC353TUHG2). Rally Buddy: ASC app id 6790257858, bundle
`com.shuffman.rallybuddy` (bundle-id resource T4NFL4ZKT9). Signing is
**manual**: "Apple Distribution: Sam Huffman" cert (ASC id A482WMGG2X, in
login keychain) + "Rally Buddy App Store" profile — the ASC API key lacks
cloud-signing permission, which is why automatic distribution signing fails
with "Cloud signing permission error". Internal TestFlight group "Internal"
has access to all builds. External group "Friends" has a public link —
https://testflight.apple.com/join/Yfgj5x49 — new builds must be attached to
the group (only the first build of a version needs beta review). Beta review
contact details are already configured in App Store Connect.

```sh
xcodebuild archive -project RallyBuddy.xcodeproj -scheme RallyBuddy \
  -destination 'generic/platform=iOS' -archivePath build/RallyBuddy.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_4C8LJ62B46.p8 \
  -authenticationKeyID 4C8LJ62B46 \
  -authenticationKeyIssuerID 467cad01-fed5-45da-9b77-2826c8a2c588
xcodebuild -exportArchive -archivePath build/RallyBuddy.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_4C8LJ62B46.p8 \
  -authenticationKeyID 4C8LJ62B46 \
  -authenticationKeyIssuerID 467cad01-fed5-45da-9b77-2826c8a2c588
```

`manageAppVersionAndBuildNumber` in ExportOptions.plist auto-bumps the build
number on upload, so repeat uploads need no project edits; bump
MARKETING_VERSION in project.yml for user-visible versions.

## Architecture

- `Models/RoadFeature.swift` — SwiftData model. A feature is a point with a
  type, optional travel-direction bearing (nil = both directions), and note.
- `Models/Route.swift` — SwiftData model; waypoints + road-snapped path
  stored as interleaved lat/lon `[Double]` arrays.
- `Services/LocationService.swift` — CLLocationManager wrapper (@Observable);
  best-for-navigation accuracy, background updates while a drive is active.
- `Services/AlertEngine.swift` — pure-ish logic: given a location + features,
  computes what's ahead (distance + heading cone) and announces each feature
  once per approach via SpeechService.
- `Services/SpeechService.swift` — AVSpeechSynthesizer with audio ducking.
- `Services/RouteBuilder.swift` — MKDirections leg-by-leg planning.
- `Services/RouteShare.swift` — `.rallybuddy` export (Transferable) + import.
- `Views/` — three tabs: Drive (full-screen map HUD, quick-mark buttons,
  route picker), Routes (list/share/plan via RoutePlannerView), Features
  (list/delete).

## Open questions / recorded assumptions

- **Units:** metric (km/h, meters) hard-coded for v1. Should become
  locale-aware or a setting.
- **Spans vs points:** passing lanes and residential zones are really spans
  (start/end), but v1 models every feature as a point. Revisit when it hurts.
- **Alert tuning:** lookahead 600 m, 50° heading cone, re-announce after
  leaving 1.5× lookahead — all untested guesses; tune on real drives.
- **Background location UX** and CarPlay entitlement are deferred.
- **Route planner replans every leg on each waypoint tap** — fine for a
  handful of waypoints, but MKDirections throttles aggressive use; cache
  per-leg results if this becomes a problem.
- **Off-route detection** while driving a route: not implemented; the route
  is currently just drawn on the map.
