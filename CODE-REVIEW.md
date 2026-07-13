# Rally Buddy Code Review

This document contains a comprehensive code review of the Rally Buddy codebase. It identifies functional bugs, logical inconsistencies, performance concerns, and SwiftUI/Swift Concurrency best-practice violations.

---

## 1. Critical Bugs & Functional Issues

### Audio Session Ducking is Never Restored (Permanent Background Audio Muting)
* **File & Lines**: [SpeechService.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/SpeechService.swift#L8-L18)
* **Issue**: The co-driver speech service configures the `AVAudioSession` category with the option `.duckOthers`. When [say(_:)](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/SpeechService.swift#L15) is invoked, it sets the audio session to active:
  ```swift
  try? AVAudioSession.sharedInstance().setActive(true)
  ```
  However, it **never deactivates** the session when speech completes.
* **Consequence**: After the first callout is spoken (or when a feature is marked), background audio (such as music or podcasts from Spotify/Apple Podcasts) will remain ducked (attenuated) **permanently** until the app is force-closed or another app reclaims audio focus.
* **Fix**: Conform the [SpeechService](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/SpeechService.swift) to `AVSpeechSynthesizerDelegate`. Set the synthesizer's delegate to `self`, and in the delegate callbacks `speechSynthesizer(_:didFinish:)` and `speechSynthesizer(_:didCancel:)`, deactivate the audio session:
  ```swift
  try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  ```

### User Tracking Mode Desynchronization (Map Stops Following)
* **File & Lines**: [MapLibreView.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/MapLibreView.swift#L148-L155)
* **Issue**: [updateUIView(_:context:)](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/MapLibreView.swift#L81) sets the map's user tracking mode based on `followsCourse`:
  ```swift
  if followsCourse != coordinator.wasFollowingCourse {
      coordinator.wasFollowingCourse = followsCourse
      mapView.setUserTrackingMode(
          followsCourse ? .followWithCourse : .none,
          animated: true,
          completionHandler: nil
      )
  }
  ```
  In MapLibre, whenever the user manually pans or drags the map, the tracking mode automatically reverts to `.none`. However, `MapLibreView` does not implement the delegate method `mapView(_:didChangeUserTrackingMode:animated:)` or update the state.
* **Consequence**: If the user pans the map, tracking is cancelled internally by MapLibre, but `followsCourse` (bound to `locationService.isTracking`) remains `true` in SwiftUI. Because the values remain `true` in both places, future re-renders will not trigger the `if followsCourse != coordinator.wasFollowingCourse` condition, and the map will **never snap back** to following the user.
* **Fix**: Change `followsCourse` to a `Binding<Bool>` and implement `mapView(_:didChangeUserTrackingMode:animated:)` in the [Coordinator](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/MapLibreView.swift#L168) to update that binding to `false` when the tracking mode changes to `.none` via manual gesture.

### Route Planner Spinner Stuck on Cancellation
* **File & Lines**: [RoutePlannerView.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/RoutePlannerView.swift#L112-L126)
* **Issue**: The route replanning task sets `isPlanning = true` and kicks off an asynchronous path-finding operation. If a user quickly makes a new tap or performs an undo, the previous task is cancelled:
  ```swift
  planTask = Task {
      do {
          let planned = try await RouteBuilder.plan(through: snapshot)
          guard !Task.isCancelled else { return } // <-- Returns without resetting isPlanning
          ...
      } catch is CancellationError {
          return // <-- Returns without resetting isPlanning
      } catch {
          ...
      }
      isPlanning = false
  }
  ```
* **Consequence**: When the task returns early on cancellation, `isPlanning = false` is bypassed. The UI status bar spinner ("Finding roads...") will spin **indefinitely** unless another task successfully finishes to clean it up.
* **Fix**: Use a `defer` block inside the `Task` to guarantee `isPlanning = false` is called:
  ```swift
  planTask = Task {
      defer { isPlanning = false }
      do { ... }
  }
  ```

---

## 2. SwiftUI & Swift Concurrency Warnings

### SwiftUI Identifier Anti-Pattern (Unstable IDs in Loop)
* **File & Lines**: [OfflineMapsTab.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/OfflineMapsTab.swift#L49)
* **Issue**: The list of offline packs uses the loop array's offset as its identifier:
  ```swift
  ForEach(Array(offlineManager.packs.enumerated()), id: \.offset) { _, pack in
      OfflinePackRow(pack: pack, manager: offlineManager)
  }
  ```
* **Consequence**: Using array indices/offsets as identifiers in dynamic `ForEach` structures is a SwiftUI anti-pattern. If a pack is deleted, the indices shift. SwiftUI's layout and diffing engine will confuse the rows, leading to list rendering glitches, wrong item details being populated, and animation jumps.
* **Fix**: Retrieve a stable, unique identifier from each `MLNOfflinePack` (e.g., wrap it in an `Identifiable` helper struct or use `ObjectIdentifier(pack)` if the native type is not hashable/identifiable).

### Non-Unique MapMarker IDs when Importing/Scanning
* **File & Lines**: [DriveView.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/DriveView.swift#L29)
* **Issue**: Markers are identified by their feature's creation timestamp:
  ```swift
  id: "f-\(feature.createdAt.timeIntervalSince1970)"
  ```
  When importing a route or running the auto-detector, multiple [RoadFeature](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Models/RoadFeature.swift) instances are inserted simultaneously in a single transaction, meaning they share the **exact same** `createdAt` timestamp.
* **Consequence**: Multiple map markers will share duplicate IDs. In MapLibre or SwiftUI loops, this leads to unpredictable rendering glitches, missing markers, or markers jumping locations.
* **Fix**: Use the database-backed unique identifier `feature.id.uuidString` or `feature.id.description`.

### Non-Sendable SwiftData Model Crossings
* **File & Lines**: [FeatureDetector.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/FeatureDetector.swift#L53-L58) and [RoutesTab.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/RoutesTab.swift#L111-L119)
* **Issue**: The `@MainActor` function `scanAndInsert` accepts `existingFeatures: [RoadFeature]`. It then suspends execution with `await scan(...)` which runs on a cooperative background thread. Under Swift 6.0 Strict Concurrency, SwiftData model classes are not `Sendable` because they are bound to a specific `ModelContext` (and thread/actor).
* **Consequence**: Passing an array of non-Sendable `RoadFeature` class instances across an asynchronous boundary triggers strict concurrency compiler warnings.
* **Fix**: Only pass `Sendable` representations across boundaries (e.g. `[CLLocationCoordinate2D]` coordinates, types, or a lightweight thread-safe struct), or perform database fetches directly within the actor-isolated scope.

---

## 3. Architecture & Performance Concerns

### High-Flicker Marker Updates
* **File & Lines**: [MapLibreView.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/MapLibreView.swift#L92-L128)
* **Issue**: In `updateUIView`, whenever `markers` or `theme` changes, the coordinator removes **every single annotation** and adds them all back:
  ```swift
  if coordinator.markers != markers || themeChanged {
      coordinator.markers = markers
      if !coordinator.markerAnnotations.isEmpty {
          mapView.removeAnnotations(coordinator.markerAnnotations)
      }
      coordinator.markerAnnotations = markers.map { ... }
      mapView.addAnnotations(coordinator.markerAnnotations)
  }
  ```
* **Consequence**: This causes massive visual flickering and micro-stutters, especially while driving or when new/suggested features are updated, since the entire map overlay has to clear and re-render.
* **Fix**: Perform a diff between `coordinator.markers` and `markers`, and only add/remove the specific annotations that changed.

### Sequentially Blocking Network Requests in Route Planning
* **File & Lines**: [RouteBuilder.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/RouteBuilder.swift#L24-L40)
* **Issue**: When snapping a route to the road layout, `RouteBuilder.plan(through:)` performs sequential `MKDirections.calculate()` requests in a loop (one leg at a time).
* **Consequence**: MapKit directions are online-only and subject to strict API throttling. If a route has many waypoints, the planning step takes a long time and is prone to triggering rate limiting, which results in "No drivable road found for that leg" errors.
* **Fix**: Implement an in-memory or persistent cache of calculated route legs indexed by rounded coordinates. This would bypass network requests for already-snapped segments.

---

## 4. Minor Style & Layout Improvements

* **Missing Deinitializers for Notification Observers**: [OfflineMapManager.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Services/OfflineMapManager.swift#L20-L33) registers observers in `init` but never removes them. Although this is a long-lived singleton-like class, standard best practices require a `deinit` block that calls `NotificationCenter.default.removeObserver` to avoid dangling references during testing or state resets.
* **Dead Code in AddFeatureSheet**: [AddFeatureSheet.swift](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/AddFeatureSheet.swift#L40) displays the toggle "Only for current direction of travel" only if `course != nil`. However, [DriveView](file:///Users/shuffman/Projects/rally-buddy/RallyBuddy/Views/DriveView.swift#L66) passes `course: nil` in its sheet initializer. Since features are otherwise added directly/automatically via quick-mark buttons, this toggle is unreachable dead UI code.
* **Hardcoded Metric Units**: Spans, distances, lookahead cones, and speed readouts are hardcoded to metric measurements. This limits accessibility in countries using imperial systems (miles, yards, mph). Use Foundation's `Measurement` and `MeasurementFormatter` structures to achieve native localization.
