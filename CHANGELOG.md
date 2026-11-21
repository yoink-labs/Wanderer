# Changelog

All notable changes to Wanderer are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions match the iOS app's marketing version. The TestFlight build number
is noted next to each release.

## [Unreleased]

### Added

- iOS: a pink heart "Tip the devs" button in the Home top bar, for guests and
  signed-in users on every screen size. It opens the optional tip jar, now
  titled "Tip the devs" (the Profile row too). Tips unlock nothing.
- Web: a pink "Tip the devs" pill in the header on every page, linking to
  [yoinklabs.dev/tip](https://yoinklabs.dev/tip), plus a footer link.

- Privacy policy at [wanderer.yoinklabs.dev/privacy](https://wanderer.yoinklabs.dev/privacy),
  served as a full page that also loads without JavaScript
  ([#13](https://github.com/yoink-labs/Wanderer/pull/13)).
- Web: a trip overview and a day planner next to a map that stays on screen,
  with named saved-place lists, a place detail panel, lodging check-in and
  check-out, overnight flight arrivals in airport-local time, and stop photos
  ([#16](https://github.com/yoink-labs/Wanderer/pull/16)).
- iOS: place search suggests places as you type and favours the trip's
  destination. Before you type, it shows category shortcuts and popular
  places near the destination
  ([#18](https://github.com/yoink-labs/Wanderer/pull/18)).
- iOS: "Argentina: Buenos Aires & Iguazú", a seven-day sample trip with 29
  stops and bookings. Sample trips fill in the first time they open
  ([#20](https://github.com/yoink-labs/Wanderer/pull/20)).
- iOS 26 with Apple Intelligence: "Plan my day" and "Suggest a packing list",
  running on Apple's on-device model. Nothing is sent off the phone, and both
  are hidden when the model isn't available
  ([#20](https://github.com/yoink-labs/Wanderer/pull/20)).

### Changed

- Web sign-in and sign-up now sit on Wanderer's own welcome page instead of
  a separate modal, and signing in from a guest trip returns to that trip
  ([#14](https://github.com/yoink-labs/Wanderer/pull/14)).
- Web place search goes through a cached, rate-limited endpoint on the
  Worker ([#16](https://github.com/yoink-labs/Wanderer/pull/16)).
- iOS: deleting a day, an expense or a private item now asks first
  ([#20](https://github.com/yoink-labs/Wanderer/pull/20)).
- The copyright holder in `LICENSE` is now Undrift LLC. The license is
  still MIT.
- Build number 8 ([#19](https://github.com/yoink-labs/Wanderer/pull/19)) and
  9 ([#21](https://github.com/yoink-labs/Wanderer/pull/21)).

### Fixed

- Web: switching between sign-in and sign-up no longer loses the trip you
  started from ([#15](https://github.com/yoink-labs/Wanderer/pull/15)).
- iOS: the same place can't be added twice, the planner panel's header is no
  longer cut off at its smallest size, and an empty day's map opens on the
  trip's destination ([#18](https://github.com/yoink-labs/Wanderer/pull/18)).
- iOS: a failed trip load can be retried, a day note can be saved after an
  error, nearby ideas only show as added once they are, adding a place shows
  its errors, a stop's cost no longer doubles when added again, and arrange
  mode has a visible Done button
  ([#20](https://github.com/yoink-labs/Wanderer/pull/20)).

## [0.1.0] - 2026-11-14

TestFlight build 6 ([#12](https://github.com/yoink-labs/Wanderer/pull/12)).

### Added

- The iOS trip planner: trips with days and stops on a MapKit map, bookings,
  budgets and expense splitting with settle-up, checklist, notes, files,
  guides, sharing and invites. Guest trips can be planned fully on the device
  and are copied into the account on sign-in.
- Cloudflare backend: a Worker API at `api.yoinklabs.dev` with D1 for data
  and private R2 storage for files, replacing Supabase as the only runtime
  backend.
- Sign-in through the shared Yoink Labs Clerk account with Apple, Google, or
  an emailed code. Account deletion from Profile.
- Atlas design: a new Home, a day strip and route line in the planner,
  spending by day in the budget, bookings shown as tickets, a files grid,
  Explore and guide pages, real share links and invites, undo and redo for
  planner edits, and offline reading of signed-in trips.
- Visited stops, per-stop costs, inserting and deleting days, named lists, a
  PDF export and a per-trip journal. Dark mode, and layouts that hold up at
  large accessibility text sizes.
- Layouts for iPhone Duo and iPad, a personal layer for private stops and
  bookings, live flight status, calendar and Google Maps exports, and the web
  app ([#4](https://github.com/yoink-labs/Wanderer/pull/4)).
- A tip jar screen built on StoreKit 2 that unlocks nothing. Its App Store
  products aren't set up yet
  ([#6](https://github.com/yoink-labs/Wanderer/pull/6),
  [#8](https://github.com/yoink-labs/Wanderer/pull/8)).
- One-command TestFlight uploads with `scripts/testflight.sh`
  ([#9](https://github.com/yoink-labs/Wanderer/pull/9)).
- `CONTRIBUTING.md` ([#1](https://github.com/yoink-labs/Wanderer/pull/1)),
  the Yoink Labs agent guide
  ([#2](https://github.com/yoink-labs/Wanderer/pull/2),
  [#3](https://github.com/yoink-labs/Wanderer/pull/3)) and the MIT license
  ([#5](https://github.com/yoink-labs/Wanderer/pull/5)).

### Changed

- iOS headings and the shared design language were polished
  ([#7](https://github.com/yoink-labs/Wanderer/pull/7)).
- The web app was redesigned to match the iOS app, with a photo-led landing
  page and phone layouts down to 320px
  ([#10](https://github.com/yoink-labs/Wanderer/pull/10)).

### Fixed

- The Worker returns 400 instead of 500 for invalid fixed-choice values, and
  normalizes UUIDs in request bodies.
- Trip settings and notes now work for guest trips.
- iOS trip forms are readable in dark mode and at large text sizes, and the
  web no longer crashes when adding a pin while the map is hidden
  ([#11](https://github.com/yoink-labs/Wanderer/pull/11)).

[Unreleased]: https://github.com/yoink-labs/Wanderer/compare/8e702dc...main
[0.1.0]: https://github.com/yoink-labs/Wanderer/tree/8e702dc724b507d1ea4a0e29141a679d39ac2333
