# Wanderer API (Cloudflare Worker)

The Wanderer backend: Cloudflare Worker + D1 + R2, with Clerk for identity and
Resend for transactional email. It replaces the Supabase Postgres/RLS/Storage
surface while keeping the same row shapes, so the Swift app decodes the same
JSON it always did.

## What it does

- Verifies Clerk session JWTs (RS256, JWKS) itself — no Clerk server SDK.
- Maps Clerk `sub` to an internal UUID in `identities`, so no data key changes
  when the identity provider does.
- Enforces trip membership in every query. D1 has no row-level security, so the
  Worker is the security boundary: reads need membership, writes need owner or
  editor, viewer is read-only, and a missing trip and a foreign trip both
  answer `404`.
- Idempotency keys for POST, bounded request bodies (1 MB JSON, 10 MB upload),
  rate limits for invite email and uploads.
- R2 for covers/avatars (public) and attachments (private, HMAC-signed,
  expiring links).

## Routes

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/health` | readiness |
| GET/PATCH/DELETE | `/v1/me` | profile; DELETE needs `{"confirm":"delete"}` |
| POST | `/v1/me/avatar` | raw image bytes |
| GET/POST | `/v1/trips` | list / create (creates days from the date range) |
| GET/PATCH/DELETE | `/v1/trips/:tripId` | owner-only delete |
| POST | `/v1/trips/:tripId/cover` | raw image bytes |
| GET/POST/PATCH/DELETE | `/v1/trips/:tripId/days` | |
| GET/POST/PATCH/DELETE | `/v1/trips/:tripId/places` | bulk POST supported |
| GET/POST/PATCH/DELETE | `/v1/trips/:tripId/reservations` | |
| GET/POST/PATCH/DELETE | `/v1/trips/:tripId/expenses` | body may include `splits` |
| GET | `/v1/trips/:tripId/expense-splits` | |
| GET/POST/PATCH/DELETE | `/v1/trips/:tripId/settlements` | |
| GET/POST/PATCH/DELETE | `/v1/trips/:tripId/checklist` | `is_checked` is a JSON boolean |
| GET | `/v1/trips/:tripId/members` | includes a small `profiles` object |
| GET/POST/DELETE | `/v1/trips/:tripId/invites` | POST sends resend email when configured |
| POST | `/v1/invites/:token/accept` | invite email must match the profile email |
| GET/POST/DELETE | `/v1/trips/:tripId/attachments` | raw bytes, `x-file-name` header |
| GET | `/v1/trips/:tripId/attachments/:id/url` | signed, 1 hour |
| GET | `/v1/guides`, `/v1/guides/:id`, `/v1/guides/:id/places` | public |
| GET | `/v1/trips/:tripId/bundle` | one read for the whole trip + the caller's personal layer |
| GET | `/v1/trips/:tripId/personal` | overrides, private places and private bookings for the caller |
| PUT/DELETE | `/v1/trips/:tripId/personal/overrides/:itemType/:itemId` | hide or replace a shared row for one member |
| GET/POST/PATCH/DELETE | `/v1/trips/:tripId/personal/places` | places only the caller sees |
| GET/POST/PATCH/DELETE | `/v1/trips/:tripId/personal/reservations` | bookings only the caller sees |
| GET | `/v1/trips/:tripId/flights` | live status for the trip's flight reservations |
| GET | `/v1/flights/:flightNumber/:date` | one flight, shared-cached |
| GET/POST/DELETE | `/v1/visited` | |
| GET | `/media/*` | public objects, or signed private objects |

## Local development

```bash
cd worker
npm install
npx wrangler d1 migrations apply wanderer --local
npm test
npm run dev
```

`npm test` runs the Worker inside workerd against a real local D1 and R2.

## Required configuration before deploy

Set these as Worker secrets/vars; never commit values:

| Name | Purpose |
| --- | --- |
| `CLERK_JWKS_URL` | `https://<clerk-frontend-api>/.well-known/jwks.json` |
| `CLERK_ISSUER` | `https://<clerk-frontend-api>` |
| `CLERK_AUTHORIZED_PARTIES` | comma-separated app callback / associated domains |
| `MEDIA_SIGNING_SECRET` | random 32+ byte secret for attachment links |
| `RESEND_API_KEY` | optional; invite email falls back to the Mail sheet |
| `RESEND_FROM_EMAIL` | verified sender on the Yoink domain |
| `RAPIDAPI_KEY` | AeroDataBox key from the RapidAPI marketplace |
| `RAPIDAPI_HOST` | optional; defaults to `aerodatabox.p.rapidapi.com` |
| `WEB_ORIGINS` | optional comma list of browser origins allowed by CORS |
| `FLIGHT_MONTHLY_UNIT_CAP` | optional; defaults to 380 (Basic plan is 400 units) |

## Flight status budget

The AeroDataBox Basic plan allows 400 API units and 1,600 requests per month,
with a 7-day caching allowance. A flight-status lookup is Tier 2 (2 units), so
the Worker is built around a shared cache rather than per-user calls:

- one `flight_cache` row per flight number + local departure date serves every
  member tracking it;
- a refresh only happens when the cached copy has expired (20 min near
  departure, 2 h within three days, 12 h further out, 7 days once landed);
- `flight_usage` enforces the monthly unit and request caps before any upstream
  call; when the budget is spent the last known status is served with
  `budget_exhausted: true`;
- a trip page refresh spends at most three upstream lookups.

AeroDataBox requires attribution on the free plan. Every flight payload carries
`attribution` and both apps render "Flight data by AeroDataBox" linked to
`https://aerodatabox.com`. The Basic plan has no commercial-use license; check
the terms before charging for the app.

## Browser clients (CORS)

The iOS app needs no CORS. The web app is allowed by `WEB_ORIGINS` (defaults to
the two localhost ports and `wanderer.yoinklabs.dev`). Preflight is answered
before authentication and never allows credentials — the API expects a bearer
token.

Create the D1 database and R2 bucket, then replace the placeholder ids in
`wrangler.jsonc`:

```bash
npx wrangler d1 create wanderer
npx wrangler r2 bucket create wanderer-media
npx wrangler d1 migrations apply wanderer --remote
npx wrangler secret put MEDIA_SIGNING_SECRET
```

## Local end-to-end with the iOS app

The Worker accepts test subjects only in test mode, and the app only sends them
in Debug builds:

```bash
cd worker
npx wrangler d1 migrations apply wanderer --local
npx wrangler dev --port 8787 --var ENVIRONMENT:test --var ALLOW_TEST_AUTH:true
```

Then point `Config/Cloud.local.xcconfig` at `http://127.0.0.1:8787` and launch
with `SIMCTL_CHILD_WANDERER_TEST_TOKEN=test:<subject>` and
`-wanderer.backendMode cloud`. Release builds cannot produce the test header
and the Worker rejects it unless `ENVIRONMENT === "test"` and
`ALLOW_TEST_AUTH === "true"`.

## Test-only auth

`Authorization: Bearer test:<subject>` is accepted only when
`ENVIRONMENT === "test"` **and** `ALLOW_TEST_AUTH === "true"`. Production
configuration never sets the flag, and a test asserts that both conditions are
required.

## Importing existing Supabase data

Export each table to NDJSON (`<table>.ndjson`) from the Supabase table editor,
then:

```bash
npm run import:supabase -- --dir ./export --out ./import.sql --dry-run
npm run import:supabase -- --dir ./export --out ./import.sql
npx wrangler d1 execute wanderer --remote --file import.sql
```

Rows keep their original UUIDs and every statement is an upsert, so the import
is safe to run twice. UUIDs are lowercased because Swift sends uppercase and
D1 compares text exactly. Provide `identities.ndjson` (`{clerk_sub,
profile_id, email}`) to map old users to Clerk subjects; unmapped profiles
still import, they just cannot sign in yet.
