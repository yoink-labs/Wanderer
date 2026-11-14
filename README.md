# Wanderer

A trip planner for iOS. Build a day-by-day itinerary, pin every stop on the
map, keep flights, stays, notes and files together, split the costs, and share
the plan.

AI features are intentionally out of scope.

## Stack

| Layer | Choice | Cost |
| --- | --- | --- |
| App | SwiftUI, iOS 18+, XcodeGen | free |
| Backend | Cloudflare Worker + D1 + R2 (`worker/`) | free tier |
| Auth | Clerk production (same Yoink Labs account as yoinklabs.dev): Apple, Google, email codes | free tier |
| Maps & place search | MapKit / MKLocalSearch | free |
| Weather | Open-Meteo | free, no key |
| FX rates | Frankfurter | free, no key |
| Photos | Curated CDN + user uploads | free |
| Email | Resend (invites) | free tier |
| Tips | StoreKit 2 consumables, no third-party SDK | Apple's commission only |

The backend lives at `https://api.yoinklabs.dev` on the Yoink Labs Cloudflare
account.

## What is built

- **iPhone Duo / iPad** — the same SwiftUI app adapts by available width: the
  tab bar becomes a sidebar on a regular-width canvas, Home becomes a grid, and
  the planner puts the itinerary and map side by side. Large accessibility text
  falls back to the single-column map + sheet layout rather than squeezing two
  columns. No device-specific branches.
- **Live flight status** — AeroDataBox through RapidAPI, shared-cached per
  flight and date with a monthly unit budget, attribution, gate/terminal/delay
  chips on booking tickets, and local alerts when a tracked flight changes.
- **Personal layer** — any member can hide a shared stop or booking, save their
  own version of it, or add private stops and bookings that only they see. The
  group plan is never changed. "Only you" in the trip tools lists and restores
  everything.
- **Exports** — native PDF, a calendar `.ics` of timed stops and bookings, and
  per-day Google Maps route links.
- **Fast-enough sync** — the planner re-reads the collaborative rows every 30
  seconds and supports pull-to-refresh, so a tripmate's edit appears without
  reopening the trip.
- **Web app** — `web/`: the same product as a responsive three-pane workspace
  (day rail, itinerary, map) with a single-column phone layout, guest plans,
  offline read cache, private layer, live flight status, budgets, checklist,
  notes, sharing, print, calendar and Google Maps export. Live at
  `https://wanderer.yoinklabs.dev` (Cloudflare Workers static assets).
- **Auth** — Clerk (same Yoink Labs account as yoinklabs.dev): native Sign in
  with Apple, Google (Clerk OAuth, returns to `com.wanderer.ios://callback`),
  or a six-digit emailed code. Team `64PUT29XZ8`, Sign in with Apple entitlement
  in `Wanderer/Resources/Wanderer.entitlements`.
- **Onboarding** — language picker, persisted locale.
- **Home** — smart ordering (in progress / recently opened / up next), combined
  trip-and-guide search, covers, guide carousel, Booking.com stay search,
  travel stats, loading skeletons and a recoverable load error.
- **Planner** — day-scoped MapKit map with numbered pins and a routed day line,
  a draggable sheet, day chips, place rows, booking strips, editable day notes,
  add-place search, place detail, manual arrange, route optimize, pin↔row
  selection sync, travel connectors, pin spreading and a fit-day control.
- **Named lists** — unscheduled places group by list; create/delete in the tray
  and assign from the place sheet.
- **Day management** — insert a day after another or delete one; later days and
  dates shift and the trip end date follows. Deleting a day unschedules its
  places.
- **Visited & cost** — mark a stop visited (swipe or context menu) and record
  what it cost; the row shows both.
- **Trip journal** — a per-trip map and date-grouped timeline of visited stops.
- **Export** — native PDF of the itinerary, bookings and spend, shared with the
  system sheet.
- **Bookings** — flights, lodging, rental cars, trains and other reservations
  with times, confirmation codes, costs and notes, rendered in the trip's
  timezone.
- **Money** — Splitwise-style balances with equal / exact / percentage / share
  splits, settle-up payments, fewest-payments suggestion, budget, per-trip and
  per-person totals, category breakdown and currency conversion.
- **Checklist** — packing/task list with progress and toggles.
- **Share** — links, copy, share sheet, invites stored in D1 and emailed with
  Resend, with a Mail fallback when email is unconfigured.
- **Nearby ideas** — MapKit local search around the selected day.
- **Files** — private R2 attachments with short-lived signed links.
- **Guides** — searchable public guides and one-tap copy into a trip.
- **Profile** — avatar, stats, language, currency, units, appearance
  (System/Light/Dark), visited countries/cities, sign out, delete account.
- **Tip jar** — "Support Wanderer" on Profile (guests too): three optional
  consumable tips through StoreKit 2. Prices are whatever the App Store
  returns for the user's storefront. A thank-you card after a tip; cancel
  returns quietly; Ask to Buy shows a pending note and thanks on approval;
  failures show an inline message. Tips unlock nothing. See
  [Tip jar](#tip-jar) for the App Store Connect setup.
- **Guest trips** — created before sign-in, persisted on device, copied into the
  account once and then cleared.
- **Accessibility** — Dynamic Type (including AX sizes), dark mode, VoiceOver
  labels and 44pt targets on the main flows.

## Deliberately not built

- Paywalls, a Pro tier or subscriptions. Wanderer is free; the only
  monetization is the optional tip jar.

- AI features (trip generation, chat assistant) — out of scope.
- Server push notifications — flight alerts are local notifications raised when
  the app refreshes a tracked flight.
- Hotel/flight price feeds — the AeroDataBox free plan has no commercial-use
  licence; hotel search remains a Booking.com deep link.
- Google Maps / Google Places — MapKit and OpenStreetMap are free; Google Maps
  is used only as an outbound directions link.

## Repo layout

```
Wanderer/                     SwiftUI app (Cloudflare + Clerk only)
  App/                        entry point, root flow, tabs
  Core/Design/                theme, components, haptics
  Core/Models/                Trip, records, language options
  Core/Cloud/                 API client, Clerk session bridge, trip backing
  Core/Stores/                API-backed stores
  Core/Services/              MapKit search, weather, FX, PDF export
  Features/…                  Onboarding, Auth, Trips, Planner, TripTools,
                              TripSettings, Explore, Profile
  Resources/                  asset catalog, app icon
worker/                       Cloudflare Worker + D1 migrations + tests
web/                          Vite + React web app (see web/README.md)
supabase/                     legacy schema and edge function (reference only)
Archive/Supabase/             frozen pre-migration Swift stores (not compiled)
Config/                       App.xcconfig (public API/Clerk values)
project.yml                   XcodeGen source of truth
```

Supabase is **not** linked or used at runtime. Its schema, the edge function
and frozen store copies are kept for reference; the hosted project was left
untouched. The one-off importer remains at `worker/scripts/import-supabase.ts`
and is not part of the app.

## Local setup

```bash
asdf install
xcodegen generate
open Wanderer.xcodeproj
```

`Config/App.xcconfig` already points at the production Worker and the Clerk
publishable key. Copy `Config/App.local.example.xcconfig` to
`Config/App.local.xcconfig` only to target a different backend.

Run tests:

```bash
xcodebuild test -project Wanderer.xcodeproj -scheme Wanderer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

cd worker && npm test
```

`WandererTests` covers split/settle-up math, Home search and ordering, planner
geometry, API client shaping/decoding, PDF and calendar export, guest-trip
persistence, and the tip jar's purchase states and StoreKit configuration.

The web app builds independently:

```bash
cd web
npm install
npm run build          # tsc --noEmit + vite build
npm run dev            # http://localhost:5173
```

`web/README.md` covers the local Worker, test auth and production env.

## Tip jar

`Wanderer/Core/Services/TipJar.swift` (StoreKit 2) and
`Wanderer/Features/Profile/TipJarView.swift`. The product ids are
placeholders:

| Product id | Type |
| --- | --- |
| `dev.yoinklabs.wanderer.tip.small` | Consumable |
| `dev.yoinklabs.wanderer.tip.medium` | Consumable |
| `dev.yoinklabs.wanderer.tip.large` | Consumable |

**A human must create these in App Store Connect** (In-App Purchases →
Consumable), choose their prices there, add a display name, description and
review screenshot, and attach them to the next app version for review. Until
they exist, the screen says tips aren't available and the rest of the app is
unaffected. If the ids change, update `TipTier.productID` and
`Wanderer/Resources/Wanderer.storekit` together (a unit test checks they
match).

Local testing: the Wanderer scheme points at `Wanderer/Resources/Wanderer.storekit`,
so **Run from Xcode** gives working tips in the simulator, with purchases
listed under Debug → StoreKit → Manage Transactions. The prices in that file
exist only for local testing. Launches outside Xcode (simctl, ADE) don't apply
a StoreKit configuration; in Debug builds pass `-uiTipJar config` (and
optionally `-uiTipOutcome thanks|pending|failed|cancel`) to serve the tips
from that file instead, e.g. with `-uiTab profile -uiRoute tipJar` for
screenshots. Release builds ignore these flags.

## TestFlight

One command archives the app and uploads it to App Store Connect:

```bash
scripts/testflight.sh              # next build number (project.yml + 1)
scripts/testflight.sh 9            # a specific build number
scripts/testflight.sh --skip-tests # skip the simulator unit tests
scripts/testflight.sh --no-upload  # archive and export an .ipa locally only
```

It sets `CURRENT_PROJECT_VERSION` in `project.yml`, runs `xcodegen`, runs the
unit tests (no upload if they fail), archives Release for
`generic/platform=iOS` with automatic signing, then exports with
`scripts/ExportOptions.plist` (`app-store-connect`, `destination: upload`),
which uploads straight to App Store Connect. Commit the `project.yml` and
`Wanderer.xcodeproj` bump afterwards. Logs, the archive and DerivedData go
to `~/Library/Developer/Wanderer-TestFlight/` (outside this folder, whose
File Provider xattrs break codesign).

Signing uses an App Store Connect API key, read from the environment:

| Variable | Default |
| --- | --- |
| `ASC_KEY_ID` | `2VGQN75FV5` |
| `ASC_KEY_PATH` | `~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8` |
| `ASC_ISSUER_ID` | none: required (Undrift LLC team issuer, from App Store Connect → Users and Access → Integrations) |
| `ASC_ENV_FILE` | `~/.appstoreconnect/asc.env`, sourced if present; put `ASC_ISSUER_ID=…` there once |
| `TEST_DESTINATION` | `platform=iOS Simulator,name=iPhone 17 Pro` |

The key must have cloud signing permission (Admin): with
`23TY3H4W7Z` the export fails with "Cloud signing permission error". No key
material or issuer id is committed. Apple processes an upload for roughly
5–30 minutes before it shows in TestFlight.

## Backend

See `worker/README.md` for routes, local development, deployment and secrets.
Schema changes go in `worker/migrations/` and are applied with:

```bash
cd worker
npx wrangler d1 migrations apply wanderer --remote
npx wrangler deploy
```
