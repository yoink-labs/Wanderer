-- Personal layer: what one traveller sees differently from the group.
--
-- A shared trip holds the group's plan. Each member can hide an item, replace
-- its details, or add stops and bookings only they see. Nothing here is ever
-- returned to another member: every query is scoped by user_id in the Worker.

CREATE TABLE IF NOT EXISTS personal_overrides (
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    item_type TEXT NOT NULL CHECK (item_type IN ('place', 'reservation')),
    item_id TEXT NOT NULL,
    hidden INTEGER NOT NULL DEFAULT 0,
    -- JSON object of replacement fields, applied over the shared row by the
    -- client. Only whitelisted columns are accepted by the Worker.
    data TEXT NOT NULL DEFAULT '{}',
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    PRIMARY KEY (trip_id, user_id, item_type, item_id)
);

CREATE INDEX IF NOT EXISTS personal_overrides_user_idx
    ON personal_overrides (trip_id, user_id);

CREATE TABLE IF NOT EXISTS private_places (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    day_id TEXT REFERENCES trip_days (id) ON DELETE SET NULL,
    list_id TEXT REFERENCES trip_lists (id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    address TEXT,
    lat REAL,
    lng REAL,
    category TEXT NOT NULL DEFAULT 'sight'
        CHECK (category IN ('sight', 'food', 'lodging', 'activity', 'transport', 'shopping', 'note')),
    notes TEXT,
    website TEXT,
    phone TEXT,
    photo_url TEXT,
    start_time TEXT,
    end_time TEXT,
    position INTEGER NOT NULL DEFAULT 0,
    visited_at TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS private_places_user_idx
    ON private_places (trip_id, user_id, day_id, position);

CREATE TABLE IF NOT EXISTS private_reservations (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    type TEXT NOT NULL DEFAULT 'other'
        CHECK (type IN ('flight', 'lodging', 'car', 'restaurant', 'train', 'other')),
    title TEXT NOT NULL,
    provider TEXT,
    confirmation_code TEXT,
    start_at TEXT,
    end_at TEXT,
    start_location TEXT,
    end_location TEXT,
    cost REAL,
    currency TEXT DEFAULT 'USD',
    notes TEXT,
    metadata TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS private_reservations_user_idx
    ON private_reservations (trip_id, user_id, start_at);

-- Flight status cache, shared by every user who tracks the same flight.
-- AeroDataBox permits seven-day caching; one lookup can serve many members.
CREATE TABLE IF NOT EXISTS flight_cache (
    cache_key TEXT PRIMARY KEY,
    flight_number TEXT NOT NULL,
    flight_date TEXT NOT NULL,
    payload TEXT NOT NULL,
    fetched_at TEXT NOT NULL,
    expires_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS flight_cache_expiry_idx ON flight_cache (expires_at);

-- Monthly API-unit and request budget for the free AeroDataBox plan. Counters
-- are incremented before a call so a race can overshoot at most one call.
CREATE TABLE IF NOT EXISTS flight_usage (
    month TEXT PRIMARY KEY,
    units INTEGER NOT NULL DEFAULT 0,
    requests INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
