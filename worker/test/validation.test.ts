import { describe, expect, it } from "vitest";
import { call, createTrip, json, token } from "./helpers";

async function firstDay(owner: string, tripId: string): Promise<string> {
  const days = await json<any[]>(await call("GET", `/v1/trips/${tripId}/days`, { token: token(owner) }));
  return days[0].id;
}

describe("fixed-choice fields", () => {
  it("rejects an unknown place category with a 400 that lists the allowed values", async () => {
    const trip = await createTrip("valid_place");
    const response = await call("POST", `/v1/trips/${trip.id}/places`, {
      token: token("valid_place"),
      body: { name: "Belém Tower", category: "landmark", day_id: await firstDay("valid_place", trip.id) },
    });
    expect(response.status).toBe(400);
    const body = await json<any>(response);
    expect(body.error.code).toBe("invalid_value");
    expect(body.error.message).toContain("sight");
  });

  it("still accepts every category the app sends", async () => {
    const trip = await createTrip("valid_ok");
    const day = await firstDay("valid_ok", trip.id);
    for (const category of ["sight", "food", "lodging", "activity", "transport", "shopping", "note"]) {
      const response = await call("POST", `/v1/trips/${trip.id}/places`, {
        token: token("valid_ok"),
        body: { name: category, category, day_id: day },
      });
      expect(response.status).toBe(201);
    }
  });

  it("checks updates, bookings and expenses too", async () => {
    const trip = await createTrip("valid_more");
    const place = await json<any>(
      await call("POST", `/v1/trips/${trip.id}/places`, { token: token("valid_more"), body: { name: "Cafe" } }),
    );
    const patch = await call("PATCH", `/v1/trips/${trip.id}/places/${place.id}`, {
      token: token("valid_more"),
      body: { category: null },
    });
    expect(patch.status).toBe(400);

    const booking = await call("POST", `/v1/trips/${trip.id}/reservations`, {
      token: token("valid_more"),
      body: { title: "Ferry", type: "boat" },
    });
    expect(booking.status).toBe(400);

    const expense = await call("POST", `/v1/trips/${trip.id}/expenses`, {
      token: token("valid_more"),
      body: { title: "Lunch", amount: 12, spent_at: "2026-11-12", split_mode: "random" },
    });
    expect(expense.status).toBe(400);
  });

  it("turns any other schema rejection into a 400, not a 500", async () => {
    const trip = await createTrip("valid_amount");
    const response = await call("POST", `/v1/trips/${trip.id}/days`, {
      token: token("valid_amount"),
      body: { day_index: -1 },
    });
    expect(response.status).toBe(400);
    expect((await json<any>(response)).error.code).toBe("invalid_value");
  });
});
