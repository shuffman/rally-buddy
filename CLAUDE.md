# Rally Buddy

A native iOS driving companion, tongue-in-cheek named after a rally co-driver.
The driver marks road features (passing lanes, residential zones, tight
corners) on roads they drive; while driving, the app tracks position and calls
out what's ahead — spoken audio plus a glanceable heads-up view.

## Product decisions (agreed 2026-07-12)

- **Native SwiftUI**, iOS 18+. A web app may follow later, built separately.
- **On-device only.** No backend, no accounts. Persistence via SwiftData.
  *(One scoped exception, 2026-07-19: the AI co-driver script calls the
  Claude API once at planning time — like MKDirections, plan at home;
  drives replay the stored script offline. API key lives in the Keychain.)*
- **User-annotated data.** The user marks features themselves on the map;
  no derivation from OSM or other map data.
- **Companion mode first** (v0.1–0.5); **turn-by-turn navigation since
  v0.6.0** (2026-07-16): `NavigationEngine` guides along planned routes —
  MKDirections step instructions stored per route (`guidanceCoords` /
  `guidanceInstructions`; share format v4), announcements at 500 m/120 m,
  off-route >60 m for 3 fixes → reroute to final destination (network
  required; offline shows the trail only), arrival at <45 m. Harness-
  tested (nav-test). **CarPlay navigation plan:** with guidance shipped,
  apply for the `carplay-maps` navigation entitlement; once granted,
  replace the driving-task template UI with CPMapTemplate + a MapLibre
  map drawn in the CarPlay window, navigation session maneuvers, and
  CPNavigationAlert feature callouts.
- **Delivery:** audio callouts + visual heads-up view + CarPlay.
  CarPlay (granted 2026-07-15, **driving-task** entitlement): tab bar via
  `CarPlaySceneDelegate` — "Ahead" (top 3 upcoming + speed + drive
  toggle) and "Mark" (grid of 5 one-tap quick-mark buttons). No custom
  map on the car screen unless we later get the navigation entitlement —
  which requires building real turn-by-turn route guidance first (we
  already store MKDirections step locations per route; the planned
  stepping stone).
  `AppServices` (singleton) owns location→alert wiring so both UIs share
  one engine. The entitlement is a "managed capability": it must be
  ticked on the App ID under Additional Capabilities (portal UI only,
  not API), and doing so invalidates provisioning profiles — recreate
  the App Store profile via the ASC API afterwards.
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
- **Map display: MapLibre + OpenFreeMap** (agreed 2026-07-12, superseding
  the earlier MapKit choice): switched so map regions can be **downloaded
  for offline use** (Apple provides no offline API for MapKit).
  Vector tiles from tiles.openfreemap.org (style "liberty", free, no key,
  © OpenStreetMap contributors). Offline packs are tile pyramids z0–14 via
  MLNOfflineStorage. **MKDirections is still used for route planning**
  (online-only; plan at home, drive offline).

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
number on upload, so repeat uploads need no project edits.

**Versioning is semver** on MARKETING_VERSION, tagged `vX.Y.Z` in git:
- Bump with `scripts/bump-version.sh major|minor|patch` (edits project.yml,
  regenerates the Xcode project, commits "Release vX.Y.Z", tags). Then
  `git push && git push --tags` and archive/upload as above.
- Pre-1.0 policy: **minor** = new features, **patch** = fixes/tuning.
  1.0.0 = App Store release. Build numbers are a separate axis, assigned
  at upload — never encode meaning in them.
- Note: a new MARKETING_VERSION starts a new TestFlight version train, so
  the first build of each version re-runs external beta review for the
  public-link group (internal testers are unaffected).
- The running version shows in the app: Offline tab → About.

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
- `Services/CalloutPlanner.swift` — AI co-driver script: orders confirmed
  features along a route (corridor 100 m, direction-filtered), one Claude
  API call (`claude-opus-4-8`, structured output) phrases them as linked
  pace notes keyed by feature index; lines are anchored to feature
  coordinates and stored on the Route (`scriptCoords`/`scriptLines`).
  During a drive AlertEngine speaks script lines by proximity/bearing and
  mutes the templated callout for features within 60 m of a line; ad-hoc
  quick-marks still use templated speech. UI: Routes tab → context menu →
  Co-Driver Script (CoDriverScriptSheet: generate/preview/edit/save;
  key stored via `KeychainStore`).
- `Services/RouteShare.swift` — `.rallybuddy` export (Transferable) + import.
- `Services/OfflineMapManager.swift` — MapLibre offline packs (download /
  list / delete regions), bounding-box helpers.
- `Services/FeatureDetector.swift` — route scanning: corners via
  circumradius over the resampled path (offline; intersection turns are
  excluded using the route's stored maneuver points), residential zones +
  passing lanes via Overpass (needs a User-Agent header or overpass-api.de
  406s; lane data filtered against turn:lanes/overtaking=no false
  positives). Results insert as `RoadFeature(isSuggested: true)`; user
  confirms via swipe in the Features tab. Detector math is standalone-
  compilable — synthetic tests (hairpin/sweeper/intersection) pass.
- `Views/MapLibreView.swift` — UIViewRepresentable over MLNMapView, shared
  by Drive and the planner: markers, route line (a style layer, so it can
  be dashed), course-follow camera, tap-to-coordinate, theme switching.
- **Map themes** (`MapTheme`, stored in `@AppStorage("mapTheme")`):
  Standard (OpenFreeMap liberty) and Explorer — a bundled parchment style
  (`Resources/ParchmentStyle.json`, same tile source so offline packs
  serve both) plus `ParchmentOverlay` (vignette/frame/compass rose),
  serif HUD fonts, and sepia marker art.
- `Views/` — four tabs: Drive (full-screen map HUD, quick-mark buttons,
  route picker), Routes (list/share/plan via RoutePlannerView), Features
  (list/delete), Offline (download map regions).

## Open questions / recorded assumptions

- **Units:** metric (km/h, meters) hard-coded for v1. Should become
  locale-aware or a setting.
- **Spans vs points:** passing lanes and residential zones are really spans
  (start/end), but v1 models every feature as a point. Revisit when it hurts.
- **Alert tuning:** lookahead 600 m, 50° heading cone, re-announce after
  leaving 1.5× lookahead — all untested guesses; tune on real drives.
- **Corner severity = rally chevrons** (RoadFeature.severity 1–3; only
  meaningful for .tightCorner): ‹35 m radius = 3 (hairpin), ‹75 m = 2
  (tight), ‹150 m = 1 (mild). Grade names: Corner / Tight corner /
  Hairpin; hairpin callouts append "Slow down". Radius bands are guesses
  pending real drives.
- **Background location UX** and CarPlay entitlement are deferred.
- **Route planner replans every leg on each waypoint tap** — fine for a
  handful of waypoints, but MKDirections throttles aggressive use; cache
  per-leg results if this becomes a problem.
- **Off-route detection** while driving a route: not implemented; the route
  is currently just drawn on the map.
- **OpenFreeMap has no formal SLA or offline-bulk policy**; downloads are
  region-sized (tens of MB), which is polite use. If the app ever grows a
  real user base, self-host the tiles or switch to a paid tile plan.
