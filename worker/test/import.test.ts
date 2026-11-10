import { describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import { buildPlan, normalizeRow, TABLE_ORDER } from "../scripts/import-supabase";

const profileId = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA";
const tripId = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB";
const dayId = "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC";
const placeId = "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD";
const guideId = "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE";

const tables = {
  profiles: [
    { id: profileId, email: "arul@example.com", display_name: "Arul", locale: "en", currency: "EUR", units: "metric" }
  ],
  trips: [
    {
      id: tripId,
      owner_id: profileId,
      title: "Kyoto in autumn",
      destination: "Kyoto, Japan",
      start_date: "2026-11-12",
      end_date: "2026-11-16",
      currency: "JPY",
      timezone: "Asia/Tokyo",
      share_token: "11111111-1111-4111-8111-111111111111",
      created_at: "2026-11-01T10:00:00.123456+00:00",
      updated_at: "2026-11-01T10:00:00.123456+00:00"
    }
  ],
  trip_members: [{ trip_id: tripId, user_id: profileId, role: "owner" }],
  trip_days: [{ id: dayId, trip_id: tripId, day_index: 0, date: "2026-11-12", title: null, notes: "Arrive late" }],
  places: [
    {
      id: placeId,
      trip_id: tripId,
      day_id: dayId,
      name: "Fushimi Inari Shrine",
      category: "sight",
      lat: 34.9671,
      lng: 135.7727,
      position: 0,
      created_by: profileId
    }
  ],
  expenses: [
    {
      id: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF",
      trip_id: tripId,
      title: "Dinner",
      amount: 60,
      currency: "JPY",
      category: "food",
      paid_by: profileId,
      split_with: [profileId],
      split_mode: "equal",
      spent_at: "2026-11-12"
    }
  ],
  guides: [
    { id: guideId, title: "Kyoto", summary: "Shrines", destination: "Kyoto, Japan", is_published: true }
  ]
};

describe("Supabase import planner", () => {
  it("normalizes UUID case, booleans and arrays", () => {
    const row = normalizeRow("places", { id: placeId, trip_id: tripId });
    expect(row.id).toBe(placeId.toLowerCase());
    expect(row.trip_id).toBe(tripId.toLowerCase());

    const expense = normalizeRow("expenses", { split_with: [profileId], amount: 12.5 });
    expect(expense.split_with).toBe(JSON.stringify([profileId.toLowerCase()]));

    expect(normalizeRow("guides", { is_published: true }).is_published).toBe(1);
  });

  it("orders parents before children", () => {
    const plan = buildPlan(tables);
    const joined = plan.statements.join("\n");
    expect(joined.indexOf("INSERT INTO profiles")).toBeLessThan(joined.indexOf("INSERT INTO trips"));
    expect(joined.indexOf("INSERT INTO trips")).toBeLessThan(joined.indexOf("INSERT INTO trip_days"));
    expect(joined.indexOf("INSERT INTO trip_days")).toBeLessThan(joined.indexOf("INSERT INTO places"));
    expect(TABLE_ORDER.indexOf("guides")).toBeLessThan(TABLE_ORDER.indexOf("guide_places"));
  });

  it("imports idempotently and keeps the original ids", async () => {
    const plan = buildPlan(tables);
    for (const statement of plan.statements) {
      if (statement.startsWith("--")) continue;
      await env.DB.prepare(statement).run();
    }

    const trip = await env.DB.prepare("SELECT * FROM trips WHERE id = ?").bind(tripId.toLowerCase()).first<any>();
    expect(trip?.title).toBe("Kyoto in autumn");
    expect(trip?.timezone).toBe("Asia/Tokyo");

    const place = await env.DB.prepare("SELECT * FROM places WHERE id = ?").bind(placeId.toLowerCase()).first<any>();
    expect(place?.name).toBe("Fushimi Inari Shrine");
    expect(place?.day_id).toBe(dayId.toLowerCase());

    const expense = await env.DB.prepare("SELECT split_with FROM expenses").first<any>();
    expect(JSON.parse(expense.split_with)).toEqual([profileId.toLowerCase()]);

    // Running the same plan again must not duplicate or fail.
    for (const statement of plan.statements) {
      if (statement.startsWith("--")) continue;
      await env.DB.prepare(statement).run();
    }
    const trips = await env.DB.prepare("SELECT COUNT(*) AS count FROM trips").first<{ count: number }>();
    expect(trips?.count).toBe(1);
    const guides = await env.DB.prepare("SELECT is_published FROM guides WHERE id = ?")
      .bind(guideId.toLowerCase())
      .first<any>();
    expect(guides.is_published).toBe(1);
  });

  it("keeps apostrophes intact", async () => {
    const plan = buildPlan({
      guides: [{ id: guideId, title: "Arul's guide", is_published: false }]
    });
    for (const statement of plan.statements) {
      if (statement.startsWith("--")) continue;
      await env.DB.prepare(statement).run();
    }
    const row = await env.DB.prepare("SELECT title FROM guides WHERE id = ?").bind(guideId.toLowerCase()).first<any>();
    expect(row.title).toBe("Arul's guide");
  });
});
