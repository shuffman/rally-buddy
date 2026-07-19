# Rally Buddy Proposed Features

This document details a list of useful, reasonable, and highly beneficial features that could be added to Rally Buddy in future releases to improve usability, offline robustness, and companion-mode utility.

---

## 1. Core Driving Companion Features

### Feature Editing & Visual Bearing Wheel
* **Description**: Allow the user to tap on any marker on the map (when not in drive mode) or select a row in the "Features" tab to edit its details.
* **UI/UX Details**:
  * Present a detail sheet where the user can update the co-driver [RoadFeatureType](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Models/RoadFeature.swift#L6), edit the text note, and change the corner severity rating.
  * Provide a visual, rotatable compass dial for setting or adjusting the exact bearing direction (heading) so that announcements only trigger when driving in that direction.
* **Files impacted**:
  * [FeatureListTab.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/FeatureListTab.swift)
  * [AddFeatureSheet.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/AddFeatureSheet.swift)

### Feature Spans (Passing Lane & Residential Zone Ranges)
* **Description**: Transition from modeling passing lanes and residential zones as single points to modeling them as spans with discrete starting and ending points.
* **UI/UX Details**:
  * When approaching a span, the co-driver announces "Residential zone ahead."
  * Once the driver enters the zone, a persistent visual badge is displayed in the HUD.
  * When the driver exits the zone, the co-driver calls out "End of residential zone."
* **Files impacted**:
  * [RoadFeature.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Models/RoadFeature.swift)
  * [AlertEngine.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/AlertEngine.swift)
  * [FeatureDetector.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/FeatureDetector.swift#L217)

### Drive Recording Mode
* **Description**: Allow the user to record their actual drive using the GPS track history rather than having to manually plan routes by tapping waypoints on a map beforehand.
* **UI/UX Details**:
  * Add a "Record Drive" button on the [DriveView](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/DriveView.swift).
  * The app records coordinate points in the background, snaps the final track to roads when finished, and lets the user save it as a new [Route](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Models/Route.swift).
  * Automatically prompt the user to scan the recorded drive for features.
* **Files impacted**:
  * [DriveView.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/DriveView.swift)
  * [LocationService.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/LocationService.swift)

---

## 2. Advanced Navigation & Routing

### Off-Route Detection & Recalculation
* **Description**: Implement a check while driving a selected route to detect if the vehicle has panned off-track.
* **UI/UX Details**:
  * If the distance to the closest point on the planned route exceeds a threshold (e.g. 100 meters), display an "Off Route" badge on the HUD.
  * Offer a one-tap button to recalculate the route to the next upcoming waypoint from the driver's current position.
* **Files impacted**:
  * [AlertEngine.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/AlertEngine.swift)
  * [DriveView.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/DriveView.swift)

### Maneuver Turn Warnings
* **Description**: Incorporate directions callouts (e.g. "Left turn in 300 meters") directly into the co-driver voice queue alongside the custom-marked features.
* **UI/UX Details**:
  * Since [Route](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Models/Route.swift) already stores step boundaries in `maneuverCoords`, the app can read these coordinate markers and feed them to [AlertEngine](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/AlertEngine.swift) during navigation.
* **Files impacted**:
  * [AlertEngine.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/AlertEngine.swift)
  * [SpeechService.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/SpeechService.swift)

---

## 3. CarPlay & Audio Integrations

### CarPlay Dashboard
* **Description**: Build a dedicated CarPlay interface so that Rally Buddy can run on vehicle infotainment screens.
* **UI/UX Details**:
  * Implement CarPlay templates to show the co-driver map, upcoming warnings banner, current speed pill, and quick-action buttons on the dashboard.
  * Route voice callouts directly to the car's native audio channel, properly pausing background music instead of just ducking it.
* **Files impacted**:
  * [RallyBuddyApp.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/App/RallyBuddyApp.swift) (adding a Scene Delegate for CarPlay)
  * [SpeechService.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/SpeechService.swift)

### Co-Driver Personality & Voice Pacenotes
* **Description**: Add settings to customize the TTS voice and callout styling.
* **UI/UX Details**:
  * Let the user pick from multiple preset co-driver personalities (e.g., standard Siri voice, professional co-driver, calm guide).
  * Add a setting for "Rally Pacenote Style" that changes callouts to classic rally terms (e.g. "Hairpin left" instead of "Tight corner in 100 meters. Slow down").
* **Files impacted**:
  * [SpeechService.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/SpeechService.swift)
  * [AlertEngine.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/AlertEngine.swift#L12)

### AI Voice Co-Driver (LLM-Generated Pace-Note Script)
* **Status: ✅ shipped 2026-07-19** (`CalloutPlanner` + `CoDriverScriptSheet`; optional API key with a templated offline fallback). The pre-generated-audio extension below remains open.
* **Description**: Upgrade callouts from independent per-feature announcements to a coherent, context-aware pace-note narration — the co-driver looks ahead along the route and links features naturally ("Tightens after the crest, then clear to pass") instead of firing two disconnected alerts.
* **Design approach — compile at plan time, not live**:
  * No LLM call in the driving hot path. When a [Route](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Models/Route.swift) is planned (or re-scanned), a "callout planner" walks the route polyline, assembles the ordered sequence of features/maneuvers with spacing and severity, and sends that to Claude once to generate the full drive's pace-note script — phrased lines anchored to trigger coordinates.
  * The script is persisted with the route, so drives work fully offline (consistent with the offline-maps philosophy) with no latency, cost, or cell-coverage failure modes mid-drive.
  * At drive time, [AlertEngine](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/AlertEngine.swift) triggers pre-scripted lines by proximity/bearing exactly as it does today; ad-hoc self-marked features fall back to the current templated callouts.
  * Note: this is the one feature that bends the "on-device only" rule — an API call is needed at *planning* time (plan at home, like route planning via MKDirections). Drives remain offline.
* **Optional extension — pre-generated audio**: at plan time, also render the script's lines to audio clips via a TTS API for a real co-driver voice; fall back to AVSpeechSynthesizer when clips are absent. Pairs with the personality presets above.
* **UI/UX Details**:
  * A "Generate co-driver script" step in the route planner (with a preview list of the lines, editable before saving).
  * Grouped callouts respect a lookahead window scaled by current speed (~30–60 s) so linked phrasing matches what the driver actually experiences.
* **Files impacted**:
  * [Route.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Models/Route.swift) (persist the script + trigger coords)
  * [AlertEngine.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/AlertEngine.swift)
  * [SpeechService.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/SpeechService.swift)
  * [RoutePlannerView.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/RoutePlannerView.swift)
  * New service: callout planner + Claude API client (plan-time only)

---

## 4. Connectivity & Data Transfer

### Multipeer Nearby Sync
* **Description**: Implement a live, peer-to-peer route and feature sync screen using Apple's `MultipeerConnectivity` framework.
* **UI/UX Details**:
  * Allows multiple drivers parked next to each other (e.g., at a rally stage start-line with no cellular service) to pair their devices and instantly transfer routes, waypoints, and custom co-driver notes.
* **Files impacted**:
  * New service files for peer discovery and session management.
  * [RoutesTab.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/RoutesTab.swift)

### GPX and KML Import/Export Support
* **Description**: Expand route sharing options beyond the custom `.rallybuddy` binary by supporting industry-standard GPX and KML file types.
* **UI/UX Details**:
  * Users can plan routes on desktop maps, export them to GPX, open them in Rally Buddy, and automatically generate corner suggestions before driving.
* **Files impacted**:
  * [RouteShare.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/RouteShare.swift)
  * [ContentView.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/App/ContentView.swift#L41)

---

## 5. Map & Offline Optimizations

### Interactive Offline Map Region Selection
* **Description**: Add a visual, interactive map view for selecting custom bounding boxes for offline map downloads.
* **UI/UX Details**:
  * Replace the simple "download around me" button with a map sheet where users can drag, pan, zoom, and resize a rectangular download overlay.
  * Show estimated storage sizes before starting the download.
* **Files impacted**:
  * [OfflineMapsTab.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/OfflineMapsTab.swift)
  * [OfflineMapManager.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/OfflineMapManager.swift)

### Imperial/Metric Localization Toggle
* **Description**: Add a user preference setting (or automatically respect device locale) to format distances in miles/yards and speeds in mph.
* **UI/UX Details**:
  * Integrates with co-driver speech synthesis so callouts say "Passing lane in a quarter mile" or "Tight corner in three hundred yards."
* **Files impacted**:
  * [AlertEngine.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/AlertEngine.swift)
  * [DriveView.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/DriveView.swift)
  * [RoutesTab.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/RoutesTab.swift)
