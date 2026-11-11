# Wanderlog comparison — feature and edge-case matrix

Read-only inspection of wanderlog.com in the shared ADE browser profile.
No real trips, bookings, purchases, invites or outbound messages were touched.
The demo trip used for inspection is a **guest** trip created with throwaway
data ("Trip to Lisbon", Nov 12–16 2026) — guest trips live in that browser
profile only.

## Evidence status

| Evidence | Status |
| --- | --- |
| Public marketing pages, guide index/detail, hotels search | Observed in browser |
| Guest planner (trip create, day panel, place rows, add place, add time, day menu) | Observed in browser |
| Signed-in home, saved trip overview, reservations, Pro upsell | Observed in the signed-in tab (see below) |
| Signed-in budget, checklist, notes, export, invite dialog, settings, journal | **Not yet observed** — the tab went unreachable mid-pass |
| Every gated action (expenses, share, save) | Observed *paywall/sign-up gate* only |

The signed-in pass started: home, a saved trip, its flight reservations and the
Pro upsell were observed. It stopped when the user's machine became unreachable
mid-scroll. Remaining signed-in flows are listed as not observed rather than
guessed.

### Signed-in observations (2026-11-10)

- **Home**: "Recently viewed and upcoming", one-tap "Plan new trip", trip cards
  with cover, status pill ("In 6 days"), per-card Share and overflow, title,
  member avatars with a "+N" overflow, dates and place count ("35 places"),
  "See all".
- **Opening a saved trip** shows a Pro upsell first: offline access is paid
  ($39.99/year, one-week trial), with "Maybe later".
- **Trip overview**: cover with edit affordance, title card with dates and
  member avatars, collapsible Explore suggestions with "Browse all", and a
  persistent "Map view" switch at the bottom.
- **Reservations** render as travel cards: airport codes with city names
  (ATL → EZE), date and time range with a next-day marker, airline and flight
  number, free-text notes, and "Add another flight".
- **Top bar**: "SAVED" state, undo/redo, Share, overflow menu. The left rail
  collapses to a hamburger plus a theme control.
- Offline access being a paid feature is a real product boundary; Wanderer has
  no offline cache yet and should not claim parity there.

## Legend

- **Observed** — seen directly on wanderlog.com.
- **Gated** — page/feature exists but the guest view asks for an account or PRO.
- **Not observed** — not reachable in this pass.
- Wanderer column: **impl** = implemented in this repo (code), **tested** =
  covered by a unit test in `WandererTests`, **todo** = not implemented.

## Plan creation and structure

| Capability | Wanderlog | Wanderer |
| --- | --- | --- |
| Create trip with destination autosuggest (disambiguated cities) | Observed | impl (MapKit search), not tested |
| Date range optional, two-month range picker | Observed | impl (start/end pickers), not tested |
| Guest planning with “Skip and sign up later” | Observed | impl — guest trips persist to disk and copy into the account on sign-in |
| Guest can add places / times | Observed | impl, tested — guest trips run through an on-device copy of the API (`LocalTripServer`), so days, places, lists, bookings, costs and checklist all work offline |
| Guest can add expenses / share / save | Gated — sign-up modal | impl, tested — expenses and checklist work locally; share and files say they need an account. On sign-in the trip's contents (not just the trip) copy into the account (`GuestTripImporter`) |
| Trip cover photo + cover color | Observed (overview) | impl (`updateCover`, `cover_color`) |
| Trip overview hub (reservations, budget, notes, places, explore) | Observed | partial — tools are tabs inside the trip, no single overview hub |
| Multiple named lists per trip (“Places to visit” + custom titled lists) | Observed | impl — unscheduled tray groups by named list; create/delete in the tray, assign in the place sheet |
| One-click Notes / Checklist sections inside the itinerary | Observed (notes section inserted from rail) | impl — separate notes screen and checklist screen |
| AI Assistant (10 free messages, then paid) | Observed, gated after quota | Deliberately out of scope (inference cost) |

## Itinerary / planner

| Capability | Wanderlog | Wanderer |
| --- | --- | --- |
| Collapsible days with per-day menu | Observed | partial — day strip (weekday, date, fullness dots, springing selection) + per-day menu; opens on today while the trip is underway; no collapse |
| Insert day after / delete day | Observed | impl — day-chip context menu, shifts later days and the trip end date |
| Day subheading | Observed | todo |
| Day color | Observed | todo |
| Expand all days | Observed | n/a (single selected day) |
| Numbered pins synced to itinerary rows | Observed | impl (`PlannerMapView`, `PlannerView`) |
| Numbered-day route line and distance/time | Observed (`< 1 min, 0 ft`) | impl — the list threads stops on a continuous route line with numbered beads, matching the map line, with walk time beside it |
| Auto-fill day (free) | Observed | todo — this is an AI/paid-data feature |
| Optimize route | Gated PRO | impl (nearest-neighbour reorder, free) |
| Start/end time per place, 30-minute steps | Observed | impl (`start_time` / `end_time`) |
| Mark as visited | Observed | impl — swipe/context menu on the row and a toggle in the place sheet |
| Add note / link per place | Observed (inline) | partial — notes + website fields in place editor |
| Add cost per place | Gated (expense) | impl — cost from the place sheet tags an expense with `place_id`; the row shows the total |
| Drag to reorder, manual arrange | Observed | impl (drag rows, manual arrange) |
| Add place from anywhere (Chrome extension) | Observed (extension promo) | todo (share extension plausible, free) |

## Bookings and money

| Capability | Wanderlog | Wanderer |
| --- | --- | --- |
| Reservation types: flight, lodging, rental car, train, attachment, other | Observed | impl (flight, lodging, car, restaurant, train, other) |
| Reservation detail panel with Book / Reviews / Photos tabs | Observed | partial — place detail has photos + rating; no booking tab |
| “Need a place to stay?” lodging prompt + hotel booking | Observed (affiliate) | partial — Booking.com deep-link stay search |
| Budget total, set budget, breakdown | Gated (add expense) for guest; screen visible | impl, tested — total, budget bar, distinct category colours, plus a spend-by-day chart against the daily budget (prepaid costs as a separate bar); not observed in Wanderlog |
| Group balances / split expenses | Gated for guest; entry point observed | impl (equal/exact/percent/shares, settle-up, fewest-payments suggestion) |
| Trip members / invite tripmates | Observed (create form) | impl, tested — Resend email links to an invite page; invites are claimed on sign-in by matching email (needs the email claim in Clerk's session token) |
| Multi-currency | Observed (`$0.00`, currency in expense form) | impl (trip currency + FX conversion) |

## Guides / Explore

| Capability | Wanderlog | Wanderer |
| --- | --- | --- |
| Public guide index with destination search and popular chips | Observed | impl (`ExploreView` search/filter) |
| Guide detail: cover, badges, author, follow, likes, comments, map pins | Observed | partial — cover, title, summary, stops, map; no author/follow/likes/comments |
| Copy guide into my trips | Observed (guide → plan) | impl ("Copy to my trips" imports every stop) |
| Verified-guide badge | Observed | todo (needs moderation policy, no cost) |
| Hotels search with price-drop alerts | Observed (affiliate/paid data) | not promised — deep links only, no paid API |

## Sharing / export / platform

| Capability | Wanderlog | Wanderer |
| --- | --- | --- |
| Share trip with link | Gated for guest; Share button observed | impl, tested — public read-only page at api.yoinklabs.dev/s/<token> (days and stops only; no people, notes, costs, files), "Make a new link" turns the old one off; guests see an account prompt. Worker deploy pending approval |
| Export to PDF / Google Maps / calendar | Gated PRO | PDF impl — native UIGraphicsPDFRenderer, shared with the system sheet; Maps/calendar still todo |
| Trip journal (route + visited places on a map) | Observed (menu item) | impl — per-trip map and visited timeline from mark-as-visited |
| Undo / redo | Observed | impl, tested — remove stop (restored in place with all details), reorder, move between days, visited, optimize route; Undo toast, trip-menu Undo/Redo, ⌘Z/⇧⌘Z; bounded to 30 steps |
| Offline access | Gated PRO ("offline access" upsell, observed) | impl, tested — signed in: last-loaded trips readable offline from a per-account cache cleared on sign-out (`OfflineReadCache`); guest: full offline editing. Signed-in offline *editing* still todo |
| Push notifications | Not observed | todo |
| Native mobile apps | iOS/Android exist (marketing claim) | iOS native SwiftUI (this repo) |

## UI redo (2026-11-10)

Native SwiftUI, own identity ("Atlas": map paper, deep-sea ink, marigold route),
no Wanderlog branding, assets or copy. Each slice was captured light and dark
on the simulator; proof is on the `ade-proof` branch under
`proof/2026-11-10/ui-redo/`.

| Slice | Screens | Proof folder |
| --- | --- | --- |
| 1 | Tokens, Home postcard with route spine, countdowns, zoom into planner | `01-home` |
| 2 | Guest trips fully plannable on device, carried over on sign-in | `02-guest-planning` |
| 3 | Planner day strip, route line, legible dark-mode pins | `03-planner` |
| 4 | Budget: spend by day, budget bar, grouped expenses; dark-mode controls | `04-budget` |
| 5 | Guest profile, sign-in, onboarding titles | `05-profile-onboarding` |
| 6 | Offline reading for signed-in trips | `06-offline` |
| 7 | Explore and guide detail | `07-explore` |
| 8 | Explore guides seeded in production | `08-prod-guides` |
| 9 | Sign in with Apple and Google | `09-social-sign-in` |
| 11 | Bookings as tickets | `11-bookings` |
| 12 | Files grid with thumbnails; guest files on device | `12-files` |
| 13 | Public share page, working invites, guest share state | `13-share` |
| 14 | Undo / redo for planner edits | `14-undo` |

Not yet done: signed-in offline editing, and a check of every screen at
accessibility text sizes (Home and bookings were checked).

## UX observations worth matching

1. **One screen, three panes**: rail (modes), list (itinerary), map. Wanderer
   already has list + map; the rail for budget/notes/checklist is a modal or
   tab today, which costs an extra tap.
2. **Inline actions per row** (`Mark as visited`, `Add time`, `Add cost`) keep
   the itinerary the primary surface instead of routing to a separate screen.
3. **Place detail opens beside the itinerary**, not as a full-screen push.
4. **Numbered pins are large, high-contrast and labelled by day colour** — good
   for glanceability; Wanderer's pins are lighter.
5. **Guest mode gates money and sharing, not planning.** Wanderer gates
   nothing locally, which is friendlier, but means guest data must survive the
   migration into a real account.
6. **Paywall boundaries are explicit** (PRO badges on Optimize route, Export,
   Attach). Wanderer has no paid tier, so those features should stay free where
   they cost nothing.

## Honest parity statement

Wanderer covers the core planning loop (days, map pins, routed day, places,
bookings, split money, checklist, notes, files, guides) with a native UI.
It does not yet have: named lists, day insert/delete, mark-as-visited,
per-place cost from the itinerary, comments/follows on guides, export, undo,
trip journal, AI, or a signed-in Wanderlog pass to compare saved-trip flows.
Paid-data surfaces (live hotel/flight availability, price alerts) are
deliberately not promised.
