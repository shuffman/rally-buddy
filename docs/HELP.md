# Rally Buddy — User Guide

Rally Buddy is your co-driver for everyday roads. You mark road features —
passing lanes, residential zones, tight corners — on roads you drive, and
while driving, Rally Buddy watches your position and calls them out before
you reach them, like a rally co-driver reading pace notes.

All data stays on your phone. No account, no cloud.

---

## Installing (TestFlight)

Rally Buddy is currently in beta, distributed through Apple's TestFlight:

1. Install the free **TestFlight** app from the App Store.
2. Tap the invite link you were given
   (https://testflight.apple.com/join/Yfgj5x49) or the **View in
   TestFlight** button in your invitation email.
3. Tap **Accept**, then **Install**.

Beta builds expire after 90 days; TestFlight will offer updates as new
builds ship.

## First launch

- **Allow location access** when asked — Rally Buddy can't do anything
  without it. "While Using the App" is sufficient.
- The main screen is a map centered on you. There are three tabs:
  **Drive** (the map you'll use in the car), **Routes** (plan and share
  routes), and **Features** (everything you've marked, as a list).

## Marking road features

There are two ways to mark a feature:

**Parked / at home — tap the map.** On the Drive tab (when not driving),
tap any spot on the map. Choose the feature type, optionally add a note,
and save:

| Feature | Meaning | Callout |
|---|---|---|
| 🟢 Passing lane | An overtaking lane starts here | "Passing lane in 400 meters" |
| 🟠 Residential zone | Houses ahead, mind your speed | "Residential zone in 400 meters" |
| 🔴 Tight corner | A corner that deserves respect | "Tight corner in 400 meters" |

The **"Only for current direction of travel"** toggle makes a feature fire
only when you're heading the way you are now — useful for a passing lane
that only exists on one side of the road.

**While driving — one tap.** During a drive, three big buttons sit at the
bottom of the screen: **Pass**, **Homes**, **Corner**. Tap one as you pass
the spot; the feature is dropped at your current location and direction,
confirmed with a buzz and a spoken "Marked". No looking at the screen
needed.

## Driving

1. On the **Drive** tab, tap **Start Drive**.
2. The map follows you heading-up, your speed shows at the bottom left,
   and the tab bar disappears — the whole screen is for driving.
3. When a marked feature is ahead of you (within about 600 m and roughly
   in your direction of travel), Rally Buddy speaks it — "Tight corner in
   450 meters" — and shows a banner at the top with a live distance.
   Callouts duck your music or podcast rather than pausing it.
4. Tap **End Drive** when you're done.

Each feature is announced once per approach. Features you marked yourself
during the drive are not announced back to you.

## Routes

Routes let you plan a drive ahead of time and share it.

**Planning:** Routes tab → **+** → tap waypoints on the map in order.
After each tap the path snaps to real roads and the running distance
updates. **Undo** removes the last waypoint. **Save** names the route.

**Driving a route:** select it — either tap it in the Routes tab (green
checkmark) or use the route chip at the bottom of the Drive screen. The
route draws on the map for your drive. Callouts work exactly as normal.

## Sharing routes with friends

A shared route carries the route itself **plus every marked feature within
200 m of it** — so your corner warnings travel with the road.

**To share:** Routes tab → tap the share icon next to a route → **AirDrop**
(or Messages, Mail, etc.). This produces a `.rallybuddy` file.

**To receive:** open the `.rallybuddy` file (tap the AirDrop notification,
or the attachment) and choose Rally Buddy. The route and its features are
imported. Features nearly identical to ones you already have are skipped,
so importing twice won't create duplicates.

## Offline maps

Driving with no cell signal? GPS, callouts, routes, and features all work
without a connection — only the background map needs data, and you can
download that ahead of time:

1. Go to the **Offline** tab.
2. Tap **"Area around me (40 km)"** to grab the region you're in, or tap a
   route name to download a corridor around that route.
3. The download runs with a progress indicator; a green checkmark means
   it's complete. A 40 km area is roughly 30–60 MB — use Wi-Fi.

Downloaded areas render at full street detail with no signal at all.
Swipe left on an area to delete it and free the space.

Two things still need a connection: **planning** a new route (road
snapping uses an online service) and downloading new map areas. Plan at
home, drive anywhere.

## Troubleshooting

**The map is blank or fuzzy while driving in the backcountry.**
You're offline and that area isn't downloaded. Everything still works —
callouts, route line, features — but to get the full map, download the
area from the Offline tab next time you're on Wi-Fi.

**No spoken callouts while driving.**
Check the ring/silent switch and volume. Callouts play through whatever
audio route is active — if your phone is connected to the car via
Bluetooth, they come through the car speakers.

**Callouts don't fire for a feature I marked.**
Features only fire when they're roughly *ahead* of you (within about 50°
of your direction of travel). If the feature was saved as
direction-specific (an ↑ arrow shows next to it in the Features tab), it
also won't fire when traveling the opposite way. Delete and re-mark it if
the direction is wrong.

**Speed shows "--".**
The GPS hasn't got a fix yet, or you're stationary. It resolves once
you're moving with a clear sky view.

**The app can't find me / map doesn't follow.**
Settings → Privacy & Security → Location Services → Rally Buddy → set to
**While Using the App** and enable **Precise Location**.

**I deleted something by accident.**
Features and routes are deleted immediately and there's no undo yet —
re-mark the feature, or ask a friend who has the route to share it back.

## Privacy

Rally Buddy keeps everything on your device. Your location is used live
for callouts and is not stored, transmitted, or logged. Routes and
features leave your phone only when *you* share them as a file.
