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
- **Guest trips** — created before sign-in, persisted on device, copied into the
  account once and then cleared.
- **Accessibility** — Dynamic Type (including AX sizes), dark mode, VoiceOver
  labels and 44pt targets on the main flows.

## Deliberately not built

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
geometry, API client shaping/decoding, PDF and calendar export, and guest-trip
persistence.

The web app builds independently:

```bash
cd web
npm install
npm run build          # tsc --noEmit + vite build
npm run dev            # http://localhost:5173
```

`web/README.md` covers the local Worker, test auth and production env.

## Backend

See `worker/README.md` for routes, local development, deployment and secrets.
Schema changes go in `worker/migrations/` and are applied with:

```bash
cd worker
npx wrangler d1 migrations apply wanderer --remote
npx wrangler deploy
```
