# Wanderer iOS design language

Atlas uses cool paper, deep-sea ink, and a marigold route accent. Type and
spacing carry the hierarchy; color is reserved for actions and travel state.

## Type

Use `wandererHeading` for structural headings and `Font.wanderer` for values
or controls with the same visual weight. Keep `.ligga` for body copy, metadata,
and SF Symbols. Never apply header traits to icons, amounts, or action labels.

| Role | Native style | Default size | Weight | Use |
| --- | --- | --- | --- | --- |
| screen | largeTitle | 34 | bold | Trips, Explore, Profile, onboarding |
| hero | title | 28 | semibold | Featured trip and guide names |
| title | title2 | 22 | semibold | Planner trip name, custom sheet title |
| section | title3 | 20 | semibold | Sections and empty-state titles |
| card | headline | 17 | semibold | Card and itinerary row titles |
| group | subheadline | 15 | semibold | Date and list group headings |

These are native text styles, not fixed point sizes. SF provides optical
spacing and line metrics. Screen/hero text has modest tracking (-0.4/-0.2pt);
other roles use native tracking. Accessibility sizes drop the tightening.
Headings add 2pt of scaled leading without imposing a fixed line height.
Native navigation and form sheet titles retain the system's scaling and
VoiceOver semantics. Ticket endpoints, totals and statistics are values,
not headings. Small map-pin numbers and decorative icons retain their own
geometry rather than growing into the surrounding map. The Planner retains
its existing AX2 cap on fixed map chrome so the stop list has room; stop text
continues to the user's full accessibility size. Route beads cap at 44pt to
leave that text a usable reading width.

## Layout and surfaces

- Screen gutter: 20pt. Section separation: 24pt. Heading to content: 12pt.
  Title to subtitle: 4pt. Keep compact data rows on the 4pt spacing grid.
- Control/card/postcard radii: 12/18/26pt. Use the shared card and button
  treatments instead of duplicating fills, shadows and rounding.
- Surface text uses `ink` and `muted`; photos use white on a dark scrim.
  Primary buttons use `primaryFill` / `onPrimary`. Accent text uses
  `accentText`, which has more contrast than the marigold fill.
- Buttons have at least 44pt targets; primary actions have a 52pt minimum.
  Labels wrap and add height. Section actions stack at accessibility sizes.
- Keep headings readable at AX5: grow cards, allow wrapping, and avoid text
  shrinking or fixed-height title containers.

## Audit coverage

Screen titles: Trips, Explore, Profile, onboarding and sign-in.
Trip and guide titles: featured cards, Planner, guide detail and trip detail.
Section titles: shared SectionHeader, Planner day/list headings, tool/date
labels, personal items, journal, profile and visited places.
Sheets: system navigation titles plus Trip tools and place detail's custom
headers. Empty, loading and retry states use the same hierarchy.
Body copy, editable fields, monetary values, airport codes, tab labels and
SF Symbols are deliberately distinct from structural headings.
