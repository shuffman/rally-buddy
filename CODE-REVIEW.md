# Rally Buddy Code Review — 2026-07-31

Full read of `Models/`, `Services/`, `Views/`, and `App/` at v1.0.6 (build 19).
**Every finding below has been fixed**; this file is the record of what was
wrong and how it was addressed. Verified by a clean build — the only remaining
warnings are two pre-existing `@preconcurrency` notices on the CarPlay scene
delegates, untouched.

Nothing here has been tested on a real drive yet. The two findings whose
symptoms depend on runtime timing (feature suppression, off-route rerouting)
deserve a road test or a simulated Freeway Drive before the next release.

---

## Fixed: bugs a driver would have noticed

### The map stopped following you for the rest of the drive after one pan

**Was**: `MapLibreView.updateUIView` only re-applied the tracking mode when
`followsCourse != coordinator.wasFollowingCourse`. MapLibre silently drops
tracking to `.none` when the user pans, but both values stayed `true`, so the
condition never fired again — and the recenter button lived in the *not
driving* branch of `DriveView.controls`, so there was no way back mid-drive.

**Now**: `Coordinator` implements `mapView(_:didChange:animated:)` (MapLibre's
renamed `didChangeUserTrackingMode`), mirrors the cancellation into
`wasFollowingCourse`, and reports it via a new `onFollowBroken` callback.
`DriveView` owns `followsCourse` as state, synced to `isTracking` with
`.onChange(initial: true)` so drives started from CarPlay behave the same, and
shows a **Recenter** button beside the speed pill whenever following is off.

### Music and podcasts stayed ducked forever after the first callout

**Was**: `SpeechService.say(_:)` called `AVAudioSession.setActive(true)` and
nothing ever deactivated it, so background audio stayed attenuated until the
app was force-quit.

**Now**: a stateless `SpeechDelegate` shim receives `didFinish` / `didCancel`
and deactivates with `.notifyOthersOnDeactivation`, guarded on
`synthesizer.isSpeaking` so back-to-back callouts don't make music stutter.
The delegate is a separate class so `SpeechService` stays a plain Swift type —
making it an `NSObject` itself introduced a `Sendable` warning, and a stored
callback closure just moved that warning to the shim.

### After a successful reroute the map still drew the old route

**Was**: `NavigationEngine.reroute` replaced its private `path`, but the drawn
line came from `AppServices.activeRoute?.path`, which nothing updated. The
driver was guided along one path and shown another.

**Now**: the engine's path is `private(set) var activePath`, and `DriveView`
draws `navigationEngine.activePath` while navigating, falling back to the
stored route otherwise. The saved `Route` is deliberately left untouched — a
reroute shouldn't rewrite the route you planned.

### Features you marked yourself could be announced back at you

**Was**: `AlertEngine.announced` was a `Set<PersistentIdentifier>`. For a
newly inserted model that identifier is *temporary* and changes when SwiftData
autosaves, so the suppression recorded by `suppress(_:)` stopped matching and
the corner you had just marked got read back to you — the `|| distance < 30`
bypass meant the heading cone didn't prevent it either.

**Now**: `RoadFeature` carries a `uuid` plus a `stableID` that survives saves;
`announced`, `UpcomingFeature.id`, the drive-map marker keys, and the CarPlay
marker keys all use it. `uuid` is optional so existing stores migrate without
a rewrite — rows saved before it existed fall back to a composite of values
that never change after insertion.

### A leg with no drivable road was silently skipped, leaving a gap

**Was**: `RouteBuilder.plan` did `guard let fetched = ... else { continue }`,
stitching a discontinuous path with an under-reported distance and no error —
the planner's "No drivable road" message only fired when `plan` *threw*.

**Now**: a typed `RouteBuilder.PlanningError.noDrivableRoad` is thrown.
`RoutePlannerView` surfaces `error.localizedDescription` (so network failures
finally report themselves instead of being mislabelled as unroutable legs), and
`RouteGenerator` already dropped candidates whose planning threw.

---

## Fixed: latent and lower-severity

* **Every exported file claimed format version 1.** `payload()` never set
  `version`, so files carrying v2 maneuvers, v3 severities, and v4 guidance all
  went out stamped v1. Now stamped `SharedRoute.currentVersion`, with the
  historical caveat documented on the type and in CLAUDE.md.
* **Route planner spinner could hang.** Both cancellation paths skipped
  `isPlanning = false`; now a `defer` at the top of the task.
* **Offline manager leaked notification observers.** No `deinit`, combined with
  `@State private var offlineManager = OfflineMapManager()` re-evaluating its
  initializer on every view re-init. Tokens now live in a small `ObserverBag`
  whose own `deinit` unregisters them — a separate non-isolated class because a
  `@MainActor` type's `deinit` can't touch its isolated stored properties.
* **Arrival fired immediately on a two-point route.** `progressIndex >= count - 2`
  is `0 >= 0` on the first fix; the end-of-path branch now also requires
  `progressIndex > 0`.
* **Marker churn.** Every marker change removed and re-added the whole
  annotation set, flickering the map on each quick-mark. Now diffed by
  `MapMarker.id`, rebuilding wholesale only on a theme change (marker art is
  theme-specific).
* **Sharing a long route scanned the whole polyline per feature.** A padded
  bounding-box reject now runs before the per-point distance check.
* **Co-driver sheet discarded unsaved edits** when `onAppear` re-fired; guarded
  with `hasLoadedSavedScript`.
* **Offline pack rows keyed by array offset.** Now keyed on
  `ObjectIdentifier(pack)` via a small `MLNOfflinePack` extension.
* **CarPlay map ignored a live theme change.** `refresh()` now reloads the
  style when the theme differs, and `didFinishLoading` removes existing
  annotations rather than just forgetting them — without that, the newly
  reachable style reload would have doubled every marker.

---

## One judgment call worth reviewing

The **"Only for current direction of travel"** toggle in `AddFeatureSheet` was
unreachable: it renders only when `course != nil`, and the sole presenter
passed `course: nil`. Rather than wire a course through, the toggle and its
`course` parameter were **removed** — a point tapped on the map isn't somewhere
the driver was heading, so there is no meaningful direction to record.
Direction-specific marking still exists where it makes sense: quick-marks made
while driving record the live course automatically. `docs/HELP.md` was updated
to match.

If you'd rather keep a direction control for map-tapped features, the right
shape is the bearing wheel already proposed in FEATURES.md ("Feature Editing &
Visual Bearing Wheel") — say the word and I'll build that instead.

---

## Checked and found correct

* **`CalloutPlanner`'s Claude API usage.** `claude-opus-4-8` is a current model
  ID, and the request shape — adaptive thinking plus `output_config.format`
  with a `json_schema` — is right for it. Two optional notes, not defects:
  `claude-opus-5` is now the recommended default at the same price, and
  `max_tokens: 8192` is shared between thinking and output, so a
  feature-dense route could truncate (handled gracefully with "The script was
  cut off").
* **"Non-unique MapMarker IDs" from the previous review was overstated.**
  `MapMarker.id` was never used as a rendering or diffing key, so duplicates
  changed nothing. It *is* a real key now that markers are diffed by id — which
  is why the ids were moved to `stableID` in the same pass.
* **RouteBuilder leg cache** — already existed and is used by the generator.
  `RoutePlannerView` still doesn't pass one; that remains a deliberate open
  question in CLAUDE.md, not a bug.
* **Non-Sendable SwiftData model crossings** — still architecturally true
  (`FeatureDetector.scanAndInsert` takes `[RoadFeature]` across an `await`),
  but every caller is `@MainActor` and the project doesn't build under Swift 6
  strict concurrency, so it produces no warnings today. Left alone; revisit
  when strict concurrency is enabled.
