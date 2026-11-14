# Mobile release verification

Web redesign PR #10 is merged and deployed to https://wanderer.yoinklabs.dev.
Initial production version: `66962e64-a568-43a5-946a-d5716ce3d946`.

This follow-up fixes issues found while checking the actual mobile flows:

- iOS Plan a trip, day note, nearby ideas and related cards use adaptive Atlas
  surfaces. Fixed white cards previously made dark-mode text nearly invisible.
- The trip form's cards share full-width gutters. Dates stack when they do not
  fit horizontally, and the traveler row stacks at accessibility text sizes.
  Only the compact native date-picker value is capped at XXXL; surrounding
  headings, labels and fields continue scaling through AX5.
- Nearby names can wrap, and the place-search retry has a 44pt minimum target.
- The web map waits for a visible viewport, refreshes Leaflet's cached size
  before camera movement, and refits when shown or resized. Adding the first
  pin while the map was hidden previously threw `Invalid LatLng` and blanked
  the app, including on production.
- Clerk's dark-mode Apple icon and provider labels remain readable.

## Checks

- `ade apple test --scheme Wanderer`: **85 tests, 0 failures, 0 skipped** on a
  lane-owned iPhone SE (3rd generation), iOS 26.4. Simulator signing was disabled
  temporarily for the known local signing problem; both project files restored.
- Actual 375×667 native UI checked in light/dark and at Large/AX5 text, including
  the form and planner. Before/after captures are under these folders. Original
  402×874 iPhone captures remain in `docs/marketing/`.
- `npm run build` in `web/`: TypeScript and production build pass.
- Reproduced the hidden-map crash on production. Verified the fix locally at
  320px: create guest trip, add first stop with coordinates while on Itinerary,
  switch to Map (1 pin), switch back, add second stop, switch to Map (2 pins),
  resize to 1440px, restore map. The app remains mounted and the map fits both.
- Opened production sign-in at 390px in both themes. Clerk loaded and displayed
  Apple, Google and email sign-in. No credentials submitted or account writes.

## Reproduce the map regression check

1. Use a fresh guest browser at 320px and create a Lisbon trip.
2. On Itinerary, add a stop manually with `38.7190, -9.1329`.
3. Switch to Map; it should show one numbered pin.
4. Return to Itinerary and add a second stop at `38.7139, -9.1335`.
5. Switch to Map, then resize to desktop and show the map. Both pins should fit.

Native changes require a new Xcode Cloud/TestFlight build before beta testers
receive them. No App Store release or TestFlight upload is claimed here.
Physical devices, authenticated cloud writes and a full VoiceOver walkthrough
were not tested.
