# Private trip import

Keep input outside version control. `import-trip.mjs` reads JSON containing:

- `source_key`: stable unique import identity; keep it on every retry.
- `owner_email`, `owner_clerk_sub`: confirmed against production profiles/identities before any write.
- `trip`: title, destination, start_date, end_date, timezone, currency, optional cover_url.
- `days`: optional object keyed by YYYY-MM-DD with title/notes.
- `lists`: array of `{key,title}`.
- `places`: array of `{key,date?,list_key?,name,...}` using the shared Swift/API place fields. Coordinates must come from an actual geocoder. Missing coordinates remain null.
- `reservations`: array of `{key,type,title,...,metadata?}` using the shared reservation fields. Flight metadata uses flight_number, flight_date, departure_timezone, arrival_timezone. Times are ISO 8601 with explicit offsets.

Run from worker with ADE's Cloudflare secret injected. The default creates a reviewable SQL file under the lane's ignored `.ade/imports`; add `--remote` to import. It refuses an ambiguous owner or a conflicting same-name trip. Stable UUIDs and INSERT OR IGNORE avoid duplicate rows and preserve later edits on reruns. Only the owner membership is inserted. No Clerk changes or invitations occur.

A small one-time Nominatim geocoding pass must identify Wanderer in User-Agent, cache its results, run sequentially on one machine, and wait at least 1.1 seconds between requests. Read https://operations.osmfoundation.org/policies/nominatim/. Never send private notes or traveler data to the geocoder.
