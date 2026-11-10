# Wanderer

A trip planner for iOS. Build a day-by-day itinerary, pin every stop on the
map, keep flights, stays, notes and files together, split the costs, and share
the plan.

AI features are intentionally out of scope for now.

## Stack

| Layer | Choice | Cost |
| --- | --- | --- |
| App | SwiftUI, iOS 18+, XcodeGen | free |
| Backend | Supabase today; Cloudflare Worker + D1 + R2 as the migration target | free tiers |
| Maps & place search | MapKit / MKLocalSearch | free |
| Weather | Open-Meteo | free, no key |
| FX rates | Frankfurter | free, no key |
| Photos | Unsplash CDN + user uploads | free |
| Auth | Clerk production (same Yoink account as the website), email codes | free tier |

## What is built

- **Onboarding** — language picker, persisted locale.
- **Auth** — Clerk (same Yoink Labs instance as yoinklabs.dev), email-only:
  a six-digit emailed code signs in, guest mode, session restore, sign out.
  Social sign-in is intentionally removed for this round.
- **Home** — smart ordering (in progress / recently opened / up next), combined
  trip-and-guide search, photo covers, guide carousel, Booking.com stay search,
  travel stats, loading skeletons and a recoverable load error.
- **Planner** — day-scoped MapKit map with numbered pins and a routed day line,
  a draggable three-position sheet, day chips, place rows, booking strips,
  editable day notes, add-place search, place detail with photos/rating/price,
  manual arrange, route optimize, pin↔row selection sync, travel connectors,
  pin spreading and a fit-day control.
- **Bookings** — flights, lodging, rental cars, trains and other reservations
  with times, confirmation codes, costs and notes. Times render in the trip's
  own timezone.
- **Money** — Splitwise-style balances with equal / exact / percentage / share
  splits, per-person "gets back / owes", settle-up payments, suggested
  fewest-payments settlement, per-trip budget, trip total, per-person total,
  category breakdown and currency conversion.
- **Checklist** — packing/task list with progress and toggles.
- **Share** — app/web links, copy, share sheet, trip invites stored in
  Postgres, and an optional Resend-backed invite email through a Supabase Edge
  Function. If no provider is configured, the app offers a Mail-app fallback.
- **Nearby ideas** — MapKit local search around the selected day, filtered
  against places already in the trip.
- **Cover image** — replace a trip cover from the photo library; stored in the
  `trip-covers` bucket and rendered from `cover_url`.
- **Trip notes** — one editable long-form note per trip.
- **Attachments** — private Storage bucket; add PDFs/images/text files and open
  or share them.
- **Trip settings** — rename, destination, dates, delete trip.
- **Explore** — searchable/filterable published guides, guide details and a
  one-tap "Copy to my trips" that creates a trip and imports every guide stop.
- **Profile** — avatar upload, trip/country/city stats, language, currency,
  units, visited countries/cities, add/remove visited places, sign out.
- **Time zones** — every trip has a timezone, so reservation times render in
  the trip's local time instead of the device's timezone.

## What is deliberately not built

- AI features (trip generation, autofill, chat assistant) — excluded by scope.
- Live flight status / live hotel availability — paid APIs; deep links and
  manual records instead.
- Google Maps / Google Places — MapKit is free and does the job.
- Push notifications, offline mode, Apple/Google auth, and App Store submission
  — next milestones. (Invite email delivery is built, but a Resend account
  needs a verified sender domain before it can reach arbitrary recipients.)

## Repo layout

```
Wanderer/                     SwiftUI app
  App/                        entry point, root flow, tabs
  Core/Design/                theme + reusable components
  Core/Models/                Trip, records, language options
  Core/Stores/                Supabase-backed stores
  Core/Services/              MapKit search, weather, FX, image catalog
  Features/Onboarding/        language picker
  Features/Auth/              sign-in + email sheet
  Features/Trips/             home, plan sheet, trips store
  Features/Planner/           map, day panel, place search/detail, store
  Features/TripTools/         reservations, expenses, checklist, share
  Features/TripSettings/      settings, notes, attachments
  Features/Explore/           guides + guide detail
  Features/Profile/           profile + visited places
  Resources/                  asset catalog, app icon
supabase/
  config.toml                 local Supabase config
  migrations/                 SQL schema, RLS, storage, timezone
  seed.sql                    public Explore guides
Config/                       Supabase build settings
project.yml                   XcodeGen source of truth
```

## Local setup

Node 20 is pinned in `.tool-versions` (asdf). The Supabase CLI is installed as
a **project dev dependency**, not globally:

```bash
asdf install
npm install
npx supabase --version   # 3.x
```

Generate and open the Xcode project:

```bash
xcodegen generate
open Wanderer.xcodeproj
```

Run the tests:

```bash
xcodebuild test -project Wanderer.xcodeproj -scheme Wanderer \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The `WandererTests` target covers split and settle-up math, Home search/order
and planner geometry.

## Cloud backend

`worker/` is the Cloudflare Worker + D1 + R2 backend. It is deployed at
`https://api.yoinklabs.dev` and the app defaults to it.
Supabase remains as a compile-time fallback and is not retired.

```bash
cd worker
npm install
npx wrangler d1 migrations apply wanderer --local
npm test
```

To point a build at the Worker, copy `Config/Cloud.local.example.xcconfig` to
`Config/Cloud.local.xcconfig`, fill in the Worker URL and Clerk Frontend API,
then switch Backend in Profile. See `worker/README.md` and
`docs/migration-plan.md`.

## Supabase

Wanderer needs your own Supabase project. A fresh clone builds without one, but
sign-in and trips won't work until it is configured.

```bash
cp Config/Supabase.local.example.xcconfig Config/Supabase.local.xcconfig
```

Fill in your project URL and publishable key, then apply the schema:

```bash
npx supabase link --project-ref <your-project-ref>
npx supabase db push
```

`Config/Supabase.local.xcconfig` is gitignored. Only the project URL and
publishable key belong there; never put the database password or service-role
key in the app.

Invite email is optional. To enable it, deploy `supabase/functions/send-trip-invite`
and set `RESEND_API_KEY` and `INVITE_FROM_EMAIL` as function secrets.
