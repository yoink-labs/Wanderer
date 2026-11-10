# Stack and identity migration — plan and status

## Target

| Layer | Today | Target | Cost |
| --- | --- | --- | --- |
| App | SwiftUI, iOS 18+ | unchanged | free |
| Auth | Supabase Auth (email/password) | **Clerk** (same Yoink production instance as yoinklabs.dev) | free tier |
| Data | Supabase Postgres + RLS | **Cloudflare D1** (SQLite) | free tier |
| Files | Supabase Storage | **Cloudflare R2** | free tier |
| Email | Supabase Edge Function + Resend | **Worker + Resend** | free tier |
| Realtime | Supabase Realtime | polling (no paid Durable Objects needed) | free |
| Errors | none | Sentry (bounded, deduped) — later | free |
| Analytics | none | PostHog (manual events only, no autocapture/replay) — later | free |

Nothing here adds recurring spend. No Vercel or Supabase resource is retired as
part of this change.

## Identity rules

- Clerk is the only identity store. No second user table with passwords.
- The Worker verifies Clerk session JWTs (RS256 via JWKS) itself; no Clerk
  server SDK is needed.
- Clerk `sub` is **not** used as a data key. The Worker maps `clerk_sub` to an
  internal UUID (`users.id`) so every existing table, JSON shape and Swift
  decoder keeps working.
- Yoink organization membership never grants staff access. The Worker only
  checks `sub` → `users.id` and trip membership; it does not read org roles.
- Same-account proof across site and app is **not claimed** until the site and
  this app authenticate the same person and the Worker returns the same
  `users.id` for both. That check needs Clerk keys and is still open.

## Phases

### Phase A — Worker + D1 (this change)

- `worker/` package: TypeScript Cloudflare Worker.
- D1 schema mirroring the Postgres model, with UUID text keys and ISO-8601
  timestamps so the existing Swift models decode unchanged.
- Clean REST routes for trips, days, places, reservations, expenses + splits +
  settlements, checklist, members, invites, guides, visited places, profile,
  attachments and uploads.
- Authorization enforced in code (D1 has no RLS): every read/write is scoped by
  verified trip membership; role checks for read vs write.
- Idempotency keys for POST, bounded request bodies, rate limiting for email.
- Vitest + `@cloudflare/vitest-pool-workers` tests against real local D1/R2.
- Supabase migration + seed retained for reference and rollback until the
  cutover is verified.

### Phase B — Swift client and Clerk sign-in (in progress)

Done:

- `CloudConfiguration` reads the Worker URL and Clerk Frontend API from
  Info.plist (`Config/Cloud.local.xcconfig`, gitignored).
- `WandererAPI`: typed client for the Worker API (trips, days, places,
  bookings, money, checklist, members, invites, attachments, guides, visited,
  profile, media) with typed `APIError`, offline mapping, idempotency keys for
  POST and bearer auth from `CloudSession`.
- `ClerkAuthClient`: Clerk Frontend API email/password sign-in, sign-up and
  token refresh, with the session in the Keychain. `AuthStore` now fronts both
  backends and refreshes an expiring JWT before each request.
- `TripsStore` moved behind a `TripsBacking` protocol with a Supabase and a
  Cloud implementation; the screens are unchanged. The backend switch appears
  in Profile only when the cloud build is configured.
- 12 Swift tests cover request shaping, decoding, auth failure, offline
  mapping, error mapping and Clerk JWT/error parsing.

- The remaining stores now have cloud paths too: trip detail (days, places,
  bookings, expenses + splits, settlements, checklist, members), profile,
  guides/explore, visited places, share/invites and attachments. Supabase stays
  the default; cloud mode is selected in Profile when configured.
- Verified end to end locally: the app read a trip, its days and a mapped place
  from a local `wrangler dev` Worker + D1. That run also caught a real bug --
  Swift sends uppercase UUIDs and D1 compares text case-sensitively -- which is
  now normalized in the Worker with a regression test.

Still open:

- Sign-in has not been exercised against a live Clerk instance (no keys in
  this worktree), so "same Yoink account works in the app and the site" is not
  claimed. The Clerk client follows the public Frontend API; bot protection and
  CAPTCHA policy on the Clerk instance still need to be checked.
- Google/Apple/Facebook buttons are still not wired; in cloud mode they should
  go through Clerk OAuth.
- Supabase Realtime is replaced by a load-on-open fetch; live collaboration is
  not built.
- The Worker has not been deployed, no D1/R2 resources exist yet, and no
  Supabase data has been imported.
- Media signing secret, Clerk JWKS/issuer/parties and Resend keys are not set.
- Account deletion is implemented for the cloud backend (Worker endpoint,
  confirmation body, app button in Profile) and leaves a fresh empty account
  on next sign-in because Clerk owns the identity. Supabase mode has no delete
  endpoint, so the button is hidden there.

### Phase C — UI/UX

- Keep the existing native design language.
- Close the cheap comparability gaps found in `docs/wanderlog-parity.md`.

## Cutover and rollback

1. Deploy the Worker to a preview environment, apply D1 migrations.
2. Import existing Supabase rows with a scripted, idempotent copy keyed by the
   existing UUIDs; map Supabase `auth.users` emails to Clerk users.
3. Verify counts and checksums per table, then flip the app config.
4. Rollback is config-only while the Supabase project and migrations remain.

## Data import

`worker/scripts/import-supabase.ts` turns `<table>.ndjson` Supabase exports
into an idempotent D1 import: original UUIDs kept, UUIDs lowercased (Swift
sends uppercase while D1 compares text exactly), booleans and `split_with`
arrays converted, parents written before children. Tests run the same plan
twice against local D1 and assert no duplicates.

## Open items (not done)

- Clerk publishable key/domain and Worker URL are not configured in this
  worktree, so no live sign-in or deploy has been exercised.
- Realtime collaboration is replaced by polling; live presence is not built.
- Data import from the existing Supabase project is not run (no project
  access here).
- Sentry/PostHog wiring is not added.
