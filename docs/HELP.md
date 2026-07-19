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
| 🔴 Corner › ›› ››› | Graded rally-style, see below | "Tight corner in 400 meters" |

Corners are graded in **rally chevrons**, like the roadside boards:

| Grade | Meaning | Callout |
|---|---|---|
| › Mild | Noticeable bend, ease off | "Corner in 400 meters" |
| ›› Tight | Genuinely tight, brake first | "Tight corner in 400 meters" |
| ››› Hairpin | Switchback territory | "Hairpin in 200 meters. Slow down" |

The marker on the map shows the chevron count (on the Explorer's Map, a
hairpin is marked with a dragon).

The **"Only for current direction of travel"** toggle makes a feature fire
only when you're heading the way you are now — useful for a passing lane
that only exists on one side of the road.

**While driving — one tap.** During a drive, the bottom of the screen has
**Pass** and **Homes** buttons plus a row of three corner buttons —
**› Mild**, **›› Tight**, **››› Hairpin**. Tap one as you pass the spot;
the feature is dropped at your current location and direction, confirmed
with a buzz and a spoken "Marked". No looking at the screen needed.

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

## Auto-detecting features

Rally Buddy scans every route **automatically when you save it** and adds
what it finds as suggestions. You can re-scan any route later — swipe
right on it in the **Routes** tab (or long-press → **Detect Features**),
useful after the map data improves or for routes shared to you. The scan
finds:

- **Corners, graded in chevrons** — from the actual geometry of the route
  (works offline). Curve radius decides the grade: under ~35 m is a
  ››› hairpin, under ~75 m is ›› tight, under ~150 m is › mild. Each
  suggestion notes the measured radius.
- **Residential zones** — where the route enters residential areas mapped
  in OpenStreetMap (needs internet during the scan).
- **Passing lanes** — where OpenStreetMap tags an extra travel lane
  (needs internet; best-effort — lane tagging varies a lot by region, so
  expect missed ones and double-check what it finds).

Detected features appear as **suggestions**: faded, dash-ringed markers on
the map and a SUGGESTED badge in the Features tab. They alert during
drives like normal features. Swipe right on one in the Features tab to
**confirm** it (it becomes a regular feature), or swipe left to delete a
bad guess. Scanning twice won't duplicate anything.

## Turn-by-turn navigation

Select a route (Routes tab, or the route chip on the Drive screen) and
tap **Start Drive** — Rally Buddy now navigates it: spoken turn
instructions ("In 500 meters, turn right onto East Road"), a guidance
banner with the next turn and distance-to-go, plus all the usual feature
callouts layered on top.

- **Off route?** After a few seconds it says "Rerouting" and calculates
  a fresh path to your destination. Rerouting needs a data connection —
  with no signal you'll still see the original trail on the map to find
  your way back.
- **Older routes** (planned before this version) have no stored
  instructions — you'll get the route line and off-route warnings, but
  no spoken turns. Replan the route once to upgrade it.

## AI co-driver scripts

A route can carry a written pace-note script — instead of independent
callouts, the co-driver links what's ahead: "Tightens after the crest,
then clear to pass."

Routes tab → long-press a route → **Co-Driver Script** → **Generate
Script**. With a Claude API key (optional — entered once, kept in your
Keychain), Claude writes natural linked notes from the route's features;
without one, a built-in template writes basic callouts. Either way you
can edit or delete individual lines before saving. Routes with a script
show a purple waveform icon, and drives replay the saved lines entirely
offline — the internet is only used while generating.

If the generate button is grayed out, the route has no confirmed
features yet — mark some or run **Detect Features** first.

## Routes

Routes let you plan a drive ahead of time and share it.

**Planning:** Routes tab → **+** → **Plan Route** → tap waypoints on the
map in order. After each tap the path snaps to real roads and the running
distance updates. **Undo** removes the last waypoint. **Save** names the
route.

**Generating a loop:** no route in mind? Routes tab → **+** →
**Generate Loop**. The start marker defaults to where you are (tap the
map to move it), the slider picks a distance from 20 to 200 km, and
**Generate** does the rest: Rally Buddy reads the surrounding roads from
OpenStreetMap and proposes up to three loop drives that favor curvy,
paved, quiet roads — skipping gravel and traffic lights where the map
data allows. Each proposal is a colored line on the map with a card
showing distance, estimated time, corner count, and traffic signals; tap
a card to preview, then **Save** the one you like. It becomes a normal
route — turn-by-turn guidance included, features auto-scanned — so you
can share it, download offline maps for it, or generate a co-driver
script. Generating takes up to half a minute and needs internet. Road
quality is only as good as the local map data — treat the first drive as
reconnaissance.

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

## CarPlay

Plug in (or connect wirelessly) and Rally Buddy appears on your car's
screen with two tabs:

- **Ahead** — the next few features coming up, each with its chevron
  grade and a live countdown distance, plus your speed and a **Start
  Drive / End Drive** button. Run whole drives without touching the
  phone.
- **Mark** — five big buttons (› ›› ››› corners, passing lane,
  residential) that drop a feature at your current spot, confirmed out
  loud. Marking from the car screen, eyes mostly on the road.

Spoken callouts come through the car speakers. Apple's rules for this
app category allow cards and buttons but not maps on the car screen —
for the map, glance at the phone in its mount.

## Map styles

Two looks, switchable any time with the scroll/map button at the bottom of
the Drive screen:

- **Standard** — the full modern map.
- **Explorer's Map** — a parchment chart in sepia ink: roads drawn like an
  old atlas, your route as a dotted trail, a compass rose, and aged edges.
  Tight corners are marked with a dragon, naturally. Same map data
  underneath, so offline downloads work in both styles.

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

A few things still need a connection: **planning** a route (road
snapping uses an online service), **generating a loop** (road data
comes from OpenStreetMap), **generating a co-driver script**, and
downloading new map areas. Plan at home, drive anywhere.

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

Rally Buddy keeps your data on your device. Your location is used live
for callouts and is not stored or logged. Online actions you trigger
send only what they need: planning a route sends its waypoints to
Apple's routing service, generating a loop asks OpenStreetMap for roads
around your chosen start point, and generating an AI co-driver script
sends that route's features to the Claude API (only if you've added an
API key). Nothing is sent in the background, and routes and features
leave your phone only when *you* share them as a file.
