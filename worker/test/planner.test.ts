import { describe, it, expect, vi } from "vitest";
import { env } from "cloudflare:test";
import { call, createTrip, json, token } from "./helpers";
describe("planner place details", () => {
  it("round trips optional source details and preserves membership privacy", async () => {
    const trip = await createTrip("details-owner");
    const result = await call("POST", `/v1/trips/${trip.id}/places`, {
      token: token("details-owner"),
      body: {
        name: "Garden",
        description: "Public garden",
        opening_hours: "Mo-Fr 09:00-17:00",
      },
    });
    expect(result.status).toBe(201);
    const place = await json(result);
    const bundle = await json(
      await call("GET", `/v1/trips/${trip.id}/bundle`, {
        token: token("details-owner"),
      }),
    );
    expect(
      bundle.places.find((p: { id: string }) => p.id === place.id),
    ).toMatchObject({
      description: "Public garden",
      opening_hours: "Mo-Fr 09:00-17:00",
    });
    expect(
      (
        await call("GET", `/v1/trips/${trip.id}/places`, {
          token: token("details-outsider"),
        })
      ).status,
    ).toBe(404);
  });
  it("serves cached explicit searches without an upstream request", async () => {
    await env.DB.prepare(
      "INSERT INTO place_search_cache(query,payload,expires_at) VALUES (?,?,?)",
    )
      .bind("test garden", '[{"name":"Garden"}]', Date.now() + 60000)
      .run();
    const response = await call("GET", "/v1/places/search?q=Test%20Garden", {
      token: null,
    });
    expect(response.status).toBe(200);
    expect(await json(response)).toEqual([{ name: "Garden" }]);
  });
  it("rejects invalid queries and enforces a shared upstream lease", async () => {
    expect((await call("GET", "/v1/places/search?q=a")).status).toBe(400);
    await env.DB.prepare(
      "UPDATE place_search_gate SET requested_at=? WHERE id=1",
    )
      .bind(Date.now())
      .run();
    expect(
      (await call("GET", "/v1/places/search?q=uncached-lease")).status,
    ).toBe(429);
  });
});
