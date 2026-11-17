# Wanderer roadmap

Wanderer is a free trip planner from [Yoink Labs](https://yoinklabs.dev).
There is no paywall, no Pro tier and no subscription, and every feature
below is free.

This page only lists work that exists in the repo or is written down in it.
There are no dates. For what changed in each build, see
[CHANGELOG.md](CHANGELOG.md).

## Shipped

- **iOS app, public beta on
  [TestFlight](https://testflight.apple.com/join/dF6VZksu).** SwiftUI,
  iOS 18+. Day-by-day planner on a map, bookings, budgets and expense
  splitting, checklist, notes, files, guides, sharing and invites, PDF /
  calendar / Google Maps export, guest trips that work before sign-in, and
  layouts for iPad and iPhone Duo. Version 0.1.0 is TestFlight build 6
  ([#12](https://github.com/yoink-labs/Wanderer/pull/12)).
- **Web planner** at [wanderer.yoinklabs.dev](https://wanderer.yoinklabs.dev).
  The same trips in the browser, with a trip overview and the day planner
  next to a map that stays on screen
  ([#4](https://github.com/yoink-labs/Wanderer/pull/4),
  [#10](https://github.com/yoink-labs/Wanderer/pull/10),
  [#16](https://github.com/yoink-labs/Wanderer/pull/16)).
- **Sign-in with Clerk** (the shared Yoink Labs account): Sign in with
  Apple, Google, or an emailed six-digit code, on iOS and the web. On the
  web, sign-in is part of Wanderer's own page
  ([#14](https://github.com/yoink-labs/Wanderer/pull/14)).
- **Backend on Cloudflare.** A Worker at `api.yoinklabs.dev` with D1 for
  data and private R2 storage for files, all on free tiers (`worker/`).
- **Privacy policy** at
  [wanderer.yoinklabs.dev/privacy](https://wanderer.yoinklabs.dev/privacy)
  ([#13](https://github.com/yoink-labs/Wanderer/pull/13)).

## In progress

- **The next iOS beta.** Merged since 0.1.0 and listed under "Unreleased"
  in the changelog:
  - On-device AI on iOS 26 with Apple Intelligence: "Plan my day" and a
    suggested packing list. It runs on Apple's on-device model, so nothing
    leaves the phone ([#20](https://github.com/yoink-labs/Wanderer/pull/20)).
  - Place search biased to the trip's destination, no duplicate stops, and
    a planner panel that no longer gets cut off
    ([#18](https://github.com/yoink-labs/Wanderer/pull/18)).
  - A fully planned Argentina sample trip, and confirmation before deleting
    a day, an expense or a private item
    ([#20](https://github.com/yoink-labs/Wanderer/pull/20)).
- **Tip jar.** The screen is built (StoreKit 2, unlocks nothing), but its
  App Store products haven't been created, so it isn't live.
- **Project funding.** GitHub Sponsors for the `yoink-labs` organization is
  being set up and isn't live yet.

## Planned

Open items written down in the repo, in no particular order:

- **Error reporting and basic analytics.** Sentry for errors, and PostHog
  with manual events only (no autocapture, no session replay)
  ([migration plan](docs/migration-plan.md)).
- **Live collaboration.** Tripmates' edits appear by re-reading every 30
  seconds today. Live updates and presence aren't built.
- **Editing signed-in trips offline.** Signed-in trips can be read offline.
  Guest trips can already be edited offline.
- **Adding places from other apps** through an iOS share extension.
- **Day subheadings and day colours** in the planner.
- **Richer guides:** authors, likes and comments on guide pages, and a
  verified-guide badge (that one needs a moderation policy first).
- **A single trip overview on iOS**, like the one the web planner has.

## Not planned

From the README's "Deliberately not built" list:

- Paywalls, a Pro tier or subscriptions.
- Cloud or third-party AI, such as a chat assistant or generating a trip
  from a blank prompt. The on-device features above are the only AI.
- Server push notifications. Flight alerts are local notifications.
- Paid hotel or flight price feeds.
- Google Maps or Google Places inside the app. Maps use MapKit and
  OpenStreetMap, and Google Maps is only an outbound directions link.

Want to help with something here? See [CONTRIBUTING.md](CONTRIBUTING.md).
