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
| GET/PATCH | `/v1/me` | profile |
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

Create the D1 database and R2 bucket, then replace the placeholder ids in
`wrangler.jsonc`:

```bash
npx wrangler d1 create wanderer
npx wrangler r2 bucket create wanderer-media
npx wrangler d1 migrations apply wanderer --remote
npx wrangler secret put MEDIA_SIGNING_SECRET
```

## Test-only auth

`Authorization: Bearer test:<subject>` is accepted only when
`ENVIRONMENT === "test"` **and** `ALLOW_TEST_AUTH === "true"`. Production
configuration never sets the flag, and a test asserts that both conditions are
required.
