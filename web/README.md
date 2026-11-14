# Wanderer for the web

The same trip planner as the iOS app, laid out for a large screen: a day rail,
a day-by-day itinerary, and a live map in a three-pane workspace. Below 900px
it becomes a single column with an Itinerary/Map switch.

Stack: Vite, React, TypeScript, React Router, Clerk, Leaflet with
OpenStreetMap tiles. No Tailwind, no UI kit — one CSS token sheet.

## Run locally

```bash
cd worker
npm install
npx wrangler d1 migrations apply wanderer --local
npx wrangler dev --ip 127.0.0.1 --port 8787 \
  --var ENVIRONMENT:test --var ALLOW_TEST_AUTH:true
```

In another terminal:

```bash
cd web
npm install
cp .env.example .env.local   # or use the values below
npm run dev
```

`web/.env.local` for the local Worker:

```dotenv
VITE_USE_TEST_AUTH=1
VITE_API_URL=http://127.0.0.1:8787
VITE_WANDERER_TEST_TOKEN=test:webuser|web@example.com
```

The Worker accepts `test:` tokens only when it is running with
`ENVIRONMENT=test` and `ALLOW_TEST_AUTH=true`. Production builds must leave
`VITE_USE_TEST_AUTH` unset and use Clerk.

## Production

Live at **https://wanderer.yoinklabs.dev** (and
`https://wanderer-trips.yoinklabs.workers.dev`). Both are Cloudflare Workers
static assets, configured in `web/wrangler.jsonc`.

```dotenv
VITE_API_URL=https://api.yoinklabs.dev
VITE_CLERK_PUBLISHABLE_KEY=pk_live_Y2xlcmsueW9pbmtsYWJzLmRldiQ
```

Clerk must allow the deployed origin before sign-in works (Clerk dashboard →
Domains / allowed origins). Guest planning works without it. The Worker's
`WEB_ORIGINS` already lists the live origins for CORS.

Build with `npm run build`; deploy with `npx wrangler deploy` from `web/`.

## What is here

- Sign-in through Clerk, plus guest trips kept in `localStorage`.
- Home with search, trip covers, countdowns and guides.
- Trip workspace: days, places, route map, day notes, drag-free reordering,
  private stops and per-person overrides, bookings with live AeroDataBox
  status, budgets and splits, checklist, notes and sharing.
- Offline read cache of the last bundle per trip; writes resume on retry.
- Print stylesheet, `.ics` download and Google Maps route links.

`npm run build` runs `tsc --noEmit` first, so a type error fails the build.
