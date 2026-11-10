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
| Guest planning with “Skip and sign up later” | Observed | impl (guest mode in `RootView`) |
| Guest can add places / times | Observed | impl (local guest stores) |
| Guest can add expenses / share / save | Gated — sign-up modal | Guest keeps full local data, no gate |
| Trip cover photo + cover color | Observed (overview) | impl (`updateCover`, `cover_color`) |
| Trip overview hub (reservations, budget, notes, places, explore) | Observed | partial — tools are tabs inside the trip, no single overview hub |
| Multiple named lists per trip (“Places to visit” + custom titled lists) | Observed | todo — Wanderer is day-only plus one unscheduled bucket |
| One-click Notes / Checklist sections inside the itinerary | Observed (notes section inserted from rail) | impl — separate notes screen and checklist screen |
| AI Assistant (10 free messages, then paid) | Observed, gated after quota | Deliberately out of scope (inference cost) |

## Itinerary / planner

| Capability | Wanderlog | Wanderer |
| --- | --- | --- |
| Collapsible days with per-day menu | Observed | partial — day chips + sheet, no collapse |
| Insert day after / delete day | Observed | impl — day-chip context menu, shifts later days and the trip end date |
| Day subheading | Observed | todo |
| Day color | Observed | todo |
| Expand all days | Observed | n/a (single selected day) |
| Numbered pins synced to itinerary rows | Observed | impl (`PlannerMapView`, `PlannerView`) |
| Numbered-day route line and distance/time | Observed (`< 1 min, 0 ft`) | impl (routed day line + connectors) |
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
| Budget total, set budget, breakdown | Gated (add expense) for guest; screen visible | impl (budget, total, category breakdown) |
| Group balances / split expenses | Gated for guest; entry point observed | impl (equal/exact/percent/shares, settle-up, fewest-payments suggestion) |
| Trip members / invite tripmates | Observed (create form) | impl (invites table + Resend edge function, Mail fallback) |
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
| Share trip with link | Gated for guest; Share button observed | impl (app/web link, copy, share sheet) |
| Export to PDF / Google Maps / calendar | Gated PRO | todo — PDF export is feasible with free native rendering |
| Trip journal (route + visited places on a map) | Observed (menu item) | todo — visited places exist on profile, not per trip |
| Undo / redo | Observed | todo |
| Offline editing | Not observed | todo |
| Push notifications | Not observed | todo |
| Native mobile apps | iOS/Android exist (marketing claim) | iOS native SwiftUI (this repo) |

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
