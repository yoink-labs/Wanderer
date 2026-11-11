---
name: yoink-labs
description: What Yoink Labs is and how every Yoink Labs app plugs into the shared stack (Cloudflare Workers/D1/R2/KV/Queues, the shared Clerk app, Resend, Sentry, PostHog, StoreKit 2/RevenueCat). Read before adding a backend, auth, email, analytics, payments, secrets, a deploy, or anything that costs money.
---

# Yoink Labs

Yoink Labs (GitHub org `yoink-labs`, site https://yoinklabs.dev) is arul
(GitHub `arul28`) and Harris building a portfolio of small subscription apps,
mostly iOS utilities. This file is the same in every Yoink Labs repo; keep it
generic and put app-specific detail in that repo's README.

## Product rule

- Pick categories where people already pay. Wanderlog is the model.
- Premium features are **software locks**: things that cost us nothing to
  serve. Avoid features whose cost grows per user (paid APIs, AI calls on our
  bill, live data feeds) unless the user's own subscription or device pays.
- Never invent numbers: no made-up ratings, user counts, prices, revenue or
  testimonials, in the app, the site or the docs.
- Legal pages (privacy, terms) stay drafts until a human approves them.
- There is no admin role and no staff area. Every account is a normal user.
  The team changes published content by changing code or data and pushing.

## Cost rule

Zero infrastructure cost until there is traction. Everything runs on free
tiers. Do not create paid resources, enable paid plans or add a paid API.
If a free limit is about to be hit, say so and stop; arul decides.
The first expected paid step is Cloudflare Workers Paid ($5/mo) if the 10 ms
CPU-per-request limit is exceeded (see yoink-lab-web `docs/MIGRATION.md`).

## Shared accounts (one per provider, all named "Yoink Labs")

| Job | Service | Notes |
| --- | --- | --- |
| Backend API, web apps | Cloudflare Workers | account `2bc9c3c136a62ea9dcbddaa6f59edca4`, zone `yoinklabs.dev` |
| Database | Cloudflare D1 | one database per app |
| Files / media | Cloudflare R2 | one bucket per purpose per app; keep buckets private, serve through the Worker |
| Rate limits, small cache | Cloudflare KV | per app |
| Background jobs | Cloudflare Queues | per app |
| Sign-in | Clerk, shared app "Yoink Labs" (`app_3Lt7t81PyHTTMtIsxbptC675uqs`), production instance `ins_3Lt7xKsnFA9BxgJD0u433Ub0RLZ`, frontend API `https://clerk.yoinklabs.dev` | one Yoink Labs account per person across every app |
| Transactional email | Resend, domain `yoinklabs.dev` verified | |
| Errors | Sentry org `yoink-labs` (free Developer plan) | one project per app, errors only |
| Product analytics | PostHog org "Yoink Labs" (free) | one project per app; no autocapture/replay, no cookies |
| In-app purchases | StoreKit 2, RevenueCat | not wired in any repo yet |
| Code, CI | GitHub org `yoink-labs`, Xcode Cloud for iOS builds | |

Never change the shared Clerk instance's SSO providers, Apple/Google sign-in
or native-app settings without arul. Never mix Clerk development and
production keys. Do not enable PostHog in production until the privacy page
covers it.

## How a new app plugs in

1. **Worker.** One Worker per app backend, on a subdomain of `yoinklabs.dev`
   (custom-domain route). Existing: `yoink-lab-web` serves `yoinklabs.dev`;
   `wanderer-api` serves `api.yoinklabs.dev`. New apps pick their own
   subdomain (e.g. `<app>.yoinklabs.dev` or `<app>-api.yoinklabs.dev`).
2. **Resources, named after the app:** D1 `<app>`, R2 `<app>-media` (and
   `<app>-<purpose>` for anything else), KV and Queues `<app>-<purpose>`.
   Pin resource ids in the Worker config once created so a rename can't
   create a second, empty resource.
3. **Auth.** Use the shared Clerk app. Native apps get their own native
   application/bundle id and callback inside the same production instance
   (added by arul). The Worker verifies Clerk session JWTs itself
   (RS256 via JWKS, or networkless with `CLERK_JWT_KEY`) and checks
   `CLERK_AUTHORIZED_PARTIES`. Map Clerk `sub` to an internal id.
4. **Authorization is server code.** D1 has no row-level security; the Worker
   is the security boundary. Browsers and apps never talk to D1 directly.
5. **Sentry project and PostHog project** per app, created when the app is
   ready for them; both stay off when their key/DSN is empty.
6. **Email** through Resend from a sender on `yoinklabs.dev`. yoinklabs.dev
   has no inbox; replies and internal notifications go to
   `operations@undrift.dev`.
7. **iOS apps**: SwiftUI, XcodeGen (`project.yml` is the source of truth;
   don't hand-edit the generated `.xcodeproj`), Apple team `64PUT29XZ8`.
   Only publishable values (API URL, Clerk publishable key) go in committed
   `.xcconfig`; local overrides in gitignored `*.local.xcconfig`.

## Secrets

Values never go in the repo, in chat, in logs or in commit messages. They live
in three places:

- **ADE project secrets** (`ade secrets list --text` shows names only). Agents
  read one with `ade secrets get NAME --text` only inside a command, e.g.
  `CLOUDFLARE_API_TOKEN="$(ade secrets get CLOUDFLARE_API_TOKEN --text)" npx wrangler deploy`.
  Never print it. If one is missing, use `ade secrets request NAME --reason "..."`;
  never ask a person to paste a secret into chat.
- **Worker secrets** (Cloudflare dashboard → Worker → Variables and Secrets,
  or `wrangler secret put`). Local dev uses gitignored `.dev.vars`.
- **Workers Builds build variables** for anything inlined at build time
  (`NEXT_PUBLIC_*`).

Shared Yoink stack secret names (same values in every app's ADE project):

| Name | What it is |
| --- | --- |
| `CLOUDFLARE_ACCOUNT_ID` | Yoink Labs Cloudflare account id |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token for wrangler/cf (Workers, D1, R2, KV, Queues) |
| `CLERK_SECRET_KEY` | Clerk production secret key (server only, never `NEXT_PUBLIC_`) |
| `CLERK_JWT_KEY` | Clerk production PEM public key for networkless JWT verification |
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | Clerk production publishable key (public; safe in client builds) |
| `RESEND_FULL_ACCESS_KEY` | Resend full-access API key for the Yoink Labs team. Inside a Worker the Resend key is the secret `RESEND_API_KEY` (yoink-lab-web and Wanderer both use that name) |
| `EMAIL_FROM` | Verified Resend sender on yoinklabs.dev |
| `NEXT_PUBLIC_POSTHOG_HOST` | PostHog ingest host (US cloud) |

Per-app secret names (different value per app, never copied between apps):
`SENTRY_DSN`, `NEXT_PUBLIC_POSTHOG_KEY` (or the app's PostHog project key),
`NEXT_PUBLIC_SITE_URL` / the app's public URL, app-specific salts and signing secrets (e.g. `NOMINATION_IP_SALT`,
`MEDIA_SIGNING_SECRET`), Resend audience ids, bundle ids.

## Deploy

- Production from the start: deploy to the real account and domain, not a
  throwaway sandbox.
- yoink-lab-web: Cloudflare Workers Builds deploys every push to `main`
  (`npm run build`, then `npx cf deploy --prebuilt`). Other branches build
  only. GitHub Actions run checks only and hold no deploy credentials.
  Merge to deploy; don't deploy from a laptop.
- The Cloudflare GitHub app is installed on all `yoink-labs` repos, so new
  app Workers should use a Workers Builds trigger on `main` the same way.
  (Wanderer's `worker/` is currently deployed with `npx wrangler deploy`.)
- D1 schema changes are numbered SQL files in the app's `migrations/`,
  applied with `wrangler d1 migrations apply <db> --remote` before the deploy
  that needs them.
- iOS builds go through Xcode Cloud / TestFlight.

## Who owns what

Each repo has one agent that owns day-to-day work. Coordinate through it
rather than editing another app's repo.

| Repo | Owner agent |
| --- | --- |
| `yoink-labs/yoink-lab-web` (yoinklabs.dev) | Michael Scott |
| `yoink-labs/Wanderer` (trip planner, `api.yoinklabs.dev`) | Wanderer Worker |
| `yoink-labs/receipts` (group-chat party game) | Receipts |

Humans: arul (owner, all accounts) and Harris (partner).
