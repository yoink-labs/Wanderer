-- Optional OSM/place-source details. Existing Swift clients ignore new keys.
ALTER TABLE places ADD COLUMN description TEXT;
ALTER TABLE places ADD COLUMN opening_hours TEXT;
ALTER TABLE private_places ADD COLUMN description TEXT;
ALTER TABLE private_places ADD COLUMN opening_hours TEXT;

ALTER TABLE places ADD COLUMN photo_credit TEXT;
ALTER TABLE places ADD COLUMN photo_source_url TEXT;
ALTER TABLE private_places ADD COLUMN photo_credit TEXT;
ALTER TABLE private_places ADD COLUMN photo_source_url TEXT;

-- Cache public place queries; never cache account or itinerary information here.
CREATE TABLE place_search_cache (
 query TEXT PRIMARY KEY,
 payload TEXT NOT NULL,
 expires_at INTEGER NOT NULL
);

CREATE TABLE place_search_gate (id INTEGER PRIMARY KEY CHECK(id=1), requested_at INTEGER NOT NULL DEFAULT 0);
INSERT INTO place_search_gate (id,requested_at) VALUES (1,0);
