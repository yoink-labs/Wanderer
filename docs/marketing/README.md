# Wanderer marketing images

Reusable, clean PNG originals for the Yoink Labs site. Captured 2026-11-14.

- `landing-hero-desktop.png` — redesigned web hero, 1440 × 940.
- `landing-hero-mobile.png` — redesigned web hero, 390 × 1128, showing the complete phone.
- `ios-home-light.png`, `ios-home-dark.png` — Trips, light and dark.
- `ios-planner-light.png`, `ios-planner-dark.png` — real itinerary and map, light and dark.
- `ios-bookings-light.png` — flight and stay tickets.
- `ios-expenses-dark.png` — expenses, daily spend and categories.

The six iOS images are unaltered ADE simulator framebuffer captures at
1206 × 2622, from main `2e0bc84`, a lane-owned iPhone simulator / iOS 26.4. The built-in local
guest demo supplies the sample trips. Captured in ADE's own simulator panel;
Simulator.app was not opened. The status bar is standardized to 9:41.
The existing simulator code-signing issue was worked around locally with
`CODE_SIGNING_ALLOWED=NO`; both project files were restored before commit.

The landing uses optimized 604px-wide WebP copies of the app captures in
`web/public/images/app/`, inside CSS device frames. The original iOS app,
its typography, and its data were not redesigned or fabricated for the images.

Wanderer is in **TestFlight beta**, not on the App Store. It is open source,
free to use, and has an optional tip jar in the iOS app, with no paywall.

Photography provenance and licensing: [web asset credits](../../web/public/images/CREDITS.md).
Inter's SIL Open Font License: [OFL.txt](../../web/public/fonts/OFL.txt).
