# Wanderer web v2 review

The redesign follows the iOS Atlas system documented in
[the iOS design language](../../ios-design-language.md): deep-sea ink,
marigold routes, cool paper, SF-like sans typography, 12/18/26px corners,
4px spacing rhythm, and glass only over imagery. The web self-hosts Inter.

Airbnb's live homepage informed the white space, rounded photo cards, soft
shadows, and pill search. Tesla's live homepage informed the cinematic hero,
large confident headings, minimal chrome, and paired CTAs. Reference captures
are in `references/`; their logos, copy, and imagery are not used by the app.

## Capture matrix

`before/` shows main at `2e0bc84`; `after/` shows this PR. Desktop captures
are 1440 × 1000; mobile captures are 390 × 844. Each page is captured in
light and dark. Files use `<page>-<width>-<theme>.png`:

- `landing` — main's empty guest home → the new marketing landing.
- `sign-in` — main's guest account welcome → the new sign-in welcome.
- `trips` — populated guest trips.
- `itinerary` and `map` — real Leaflet workspace. At desktop both panes
  are visible together; on mobile each tab is captured separately.
- `clerk` (before only) — the real production Clerk modal, captured on the
  unchanged live site without submitting credentials.
- `guides`, `guide`, and `profile` (after) — additional responsive coverage.

Guest capture data is isolated localStorage data, not a user's account.
The same Kyoto itinerary is used for before and after. Guides for after
come from the actual read-only production guide API through a temporary
localhost CORS proxy. The temporary setup page, proxy, and layout diagnostics
are not shipped. The before home includes its existing guide CORS error;
that is an environment limitation, not a design change.

## Checks and limits

- `npm run build` in `web/` typechecks and builds the production Worker assets.
- Browser review covers landing, sign-in welcome, trips, guides/detail,
  profile, itinerary, map, and trip tools in responsive layouts.
- Layout diagnostics check document width and out-of-bounds elements at
  320, 375, 390, 768, 1024 and 1440px; deliberately clipped photo/map and
  horizontal day rails are excluded from element overflow checks.
- The initial selected day no longer scrolls the page past its header;
  subsequent day selections continue to scroll to that day.
- Clerk's existing provider, key, modal, session token flow, and all API
  methods remain in place. Its appearance now follows the theme. Production
  Clerk keys reject localhost: the new credential modal and authenticated
  cloud writes require a follow-up check on an approved hosted origin.
  Local screenshots of the sign-in welcome show its disabled button while
  the production provider is unavailable. No credentials were submitted.
- Created a guest trip at 320px, added and checked a checklist item, then
  reloaded and confirmed the checked state persisted.
- No deployment, production mutations, backend, or iOS app code changes.

Full-resolution reusable originals are in [marketing](../../marketing/).
