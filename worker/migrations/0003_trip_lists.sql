-- Named lists inside a trip. Places can sit on a day and/or in a list;
-- unscheduled places group by list in the app.
CREATE TABLE IF NOT EXISTS trip_lists (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS trip_lists_trip_idx ON trip_lists (trip_id, position);

ALTER TABLE places ADD COLUMN list_id TEXT REFERENCES trip_lists (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS places_list_idx ON places (trip_id, list_id);
