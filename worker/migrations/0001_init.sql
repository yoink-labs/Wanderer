-- Wanderer D1 schema.
--
-- Keys are TEXT UUIDs and timestamps are ISO-8601 text so the existing Swift
-- models decode these rows without changes from the Postgres/PostgREST shape.
-- D1 has no row-level security: every query is scoped by the Worker.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS profiles (
    id TEXT PRIMARY KEY,
    email TEXT,
    display_name TEXT,
    avatar_url TEXT,
    locale TEXT NOT NULL DEFAULT 'en',
    currency TEXT NOT NULL DEFAULT 'USD',
    units TEXT NOT NULL DEFAULT 'metric',
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- Clerk subject -> internal profile id. Clerk ids are opaque strings; the
-- profile id stays a UUID so existing rows and app models keep working.
CREATE TABLE IF NOT EXISTS identities (
    clerk_sub TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL UNIQUE REFERENCES profiles (id) ON DELETE CASCADE,
    email TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    last_seen_at TEXT
);

CREATE TABLE IF NOT EXISTS trips (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    destination TEXT,
    start_date TEXT,
    end_date TEXT,
    currency TEXT NOT NULL DEFAULT 'USD',
    cover_url TEXT,
    cover_color TEXT,
    notes TEXT,
    timezone TEXT NOT NULL DEFAULT 'UTC',
    share_token TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS trips_owner_idx ON trips (owner_id);

CREATE TABLE IF NOT EXISTS trip_members (
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'editor' CHECK (role IN ('owner', 'editor', 'viewer')),
    joined_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    PRIMARY KEY (trip_id, user_id)
);

CREATE INDEX IF NOT EXISTS trip_members_user_idx ON trip_members (user_id);

CREATE TABLE IF NOT EXISTS trip_invites (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'editor' CHECK (role IN ('owner', 'editor', 'viewer')),
    token TEXT NOT NULL UNIQUE,
    expires_at TEXT,
    accepted_at TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE (trip_id, email)
);

CREATE TABLE IF NOT EXISTS trip_days (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
    day_index INTEGER NOT NULL CHECK (day_index >= 0),
    date TEXT,
    title TEXT,
    notes TEXT,
    UNIQUE (trip_id, day_index)
);

CREATE INDEX IF NOT EXISTS trip_days_trip_idx ON trip_days (trip_id, day_index);

CREATE TABLE IF NOT EXISTS places (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
    day_id TEXT REFERENCES trip_days (id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    address TEXT,
    lat REAL,
    lng REAL,
    category TEXT NOT NULL DEFAULT 'sight'
        CHECK (category IN ('sight', 'food', 'lodging', 'activity', 'transport', 'shopping', 'note')),
    notes TEXT,
    website TEXT,
    phone TEXT,
    price_level INTEGER CHECK (price_level IS NULL OR price_level BETWEEN 0 AND 4),
    rating REAL,
    photo_url TEXT,
    start_time TEXT,
    end_time TEXT,
    position INTEGER NOT NULL DEFAULT 0,
    created_by TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS places_trip_idx ON places (trip_id, day_id, position);

CREATE TABLE IF NOT EXISTS reservations (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
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
    created_by TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS reservations_trip_idx ON reservations (trip_id, start_at);

CREATE TABLE IF NOT EXISTS expenses (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    amount REAL NOT NULL CHECK (amount >= 0),
    currency TEXT NOT NULL DEFAULT 'USD',
    category TEXT NOT NULL DEFAULT 'other'
        CHECK (category IN ('food', 'lodging', 'transport', 'activities', 'shopping', 'other')),
    paid_by TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    -- JSON array of profile ids, kept as text so D1 needs no array type.
    split_with TEXT NOT NULL DEFAULT '[]',
    split_mode TEXT NOT NULL DEFAULT 'equal'
        CHECK (split_mode IN ('equal', 'exact', 'percent', 'shares')),
    spent_at TEXT NOT NULL,
    notes TEXT,
    created_by TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS expenses_trip_idx ON expenses (trip_id, spent_at);

CREATE TABLE IF NOT EXISTS expense_splits (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
    expense_id TEXT NOT NULL REFERENCES expenses (id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    amount REAL NOT NULL,
    weight REAL,
    UNIQUE (expense_id, user_id)
);

CREATE INDEX IF NOT EXISTS expense_splits_trip_idx ON expense_splits (trip_id);

CREATE TABLE IF NOT EXISTS settlements (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
    from_user TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    to_user TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    amount REAL NOT NULL CHECK (amount >= 0),
    currency TEXT NOT NULL DEFAULT 'USD',
    settled_at TEXT NOT NULL,
    note TEXT,
    created_by TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS checklist_items (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    is_checked INTEGER NOT NULL DEFAULT 0,
    position INTEGER NOT NULL DEFAULT 0,
    created_by TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS checklist_trip_idx ON checklist_items (trip_id, position);

CREATE TABLE IF NOT EXISTS guides (
    id TEXT PRIMARY KEY,
    author_id TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    summary TEXT,
    destination TEXT,
    cover_url TEXT,
    is_published INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS guides_published_idx ON guides (is_published, created_at DESC);

CREATE TABLE IF NOT EXISTS guide_places (
    id TEXT PRIMARY KEY,
    guide_id TEXT NOT NULL REFERENCES guides (id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    address TEXT,
    lat REAL,
    lng REAL,
    notes TEXT,
    photo_url TEXT,
    position INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS guide_places_guide_idx ON guide_places (guide_id, position);

CREATE TABLE IF NOT EXISTS visited_places (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    country_code TEXT NOT NULL,
    city TEXT,
    year INTEGER,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS visited_unique_idx
    ON visited_places (user_id, country_code, COALESCE(city, ''), COALESCE(year, -1));

CREATE TABLE IF NOT EXISTS attachments (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
    reservation_id TEXT REFERENCES reservations (id) ON DELETE SET NULL,
    place_id TEXT REFERENCES places (id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    mime_type TEXT,
    size_bytes INTEGER,
    created_by TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS attachments_trip_idx ON attachments (trip_id);

-- Replay protection for POSTs that carry an Idempotency-Key.
CREATE TABLE IF NOT EXISTS idempotency_keys (
    user_id TEXT NOT NULL,
    key TEXT NOT NULL,
    method TEXT NOT NULL,
    path TEXT NOT NULL,
    status INTEGER NOT NULL,
    body TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    PRIMARY KEY (user_id, key)
);

-- Simple bounded counters for email/upload throttles. Rows expire by age.
CREATE TABLE IF NOT EXISTS rate_limits (
    bucket TEXT NOT NULL,
    window_start INTEGER NOT NULL,
    count INTEGER NOT NULL,
    PRIMARY KEY (bucket, window_start)
);
