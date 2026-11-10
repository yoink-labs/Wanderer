-- Per-place status and cost.

-- When a place was actually visited (null = not visited). Used by the trip
-- journal and the itinerary row state.
ALTER TABLE places ADD COLUMN visited_at TEXT;

-- Expenses can point at the place they belong to, so the itinerary can show
-- what a stop cost without a second ledger.
ALTER TABLE expenses ADD COLUMN place_id TEXT REFERENCES places (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS expenses_place_idx ON expenses (place_id);
