import { describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import { addMember, call, createTrip, json, seedProfile, token } from "./helpers";

describe("health", () => {
  it("reports ready", async () => {
    const response = await call("GET", "/health", { token: null });
    expect(response.status).toBe(200);
    expect(await json(response)).toMatchObject({ ok: true });
  });
});

describe("authentication boundary", () => {
  it("rejects unauthenticated reads", async () => {
    const response = await call("GET", "/v1/trips", { token: null });
    expect(response.status).toBe(401);
  });

  it("rejects a malformed bearer token", async () => {
    const response = await call("GET", "/v1/trips", { token: "not-a-jwt" });
    expect(response.status).toBe(401);
  });

  it("creates a profile on first sign-in and returns it", async () => {
    const response = await call("GET", "/v1/me", { token: token("fresh_user") });
    expect(response.status).toBe(200);
    const profile = await json(response);
    expect(profile.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(profile.currency).toBe("USD");
    // Same Clerk subject resolves to the same internal id.
    const again = await json(await call("GET", "/v1/me", { token: token("fresh_user") }));
    expect(again.id).toBe(profile.id);
  });
});

describe("trips", () => {
  it("creates a trip with owner membership and days", async () => {
    const trip = await createTrip("owner_days");
    expect(trip.title).toBe("Lisbon in November");
    expect(trip.timezone).toBe("Europe/Lisbon");

    const days = await json(await call("GET", `/v1/trips/${trip.id}/days`, { token: token("owner_days") }));
    expect(days).toHaveLength(5);
    expect(days[0].date).toBe("2026-11-12");
    expect(days[4].date).toBe("2026-11-16");

    const members = await json(
      await call("GET", `/v1/trips/${trip.id}/members`, { token: token("owner_days") }),
    );
    expect(members[0].role).toBe("owner");
  });

  it("keeps trips private to owners and members", async () => {
    const trip = await createTrip("owner_private");
    const outsider = await call("GET", `/v1/trips/${trip.id}`, { token: token("outsider") });
    expect(outsider.status).toBe(404);

    const patch = await call("PATCH", `/v1/trips/${trip.id}`, {
      token: token("outsider"),
      body: { title: "Hijacked" },
    });
    expect(patch.status).toBe(404);

    const remove = await call("DELETE", `/v1/trips/${trip.id}`, { token: token("outsider") });
    expect(remove.status).toBe(404);
  });

  it("scopes child records to their trip", async () => {
    const a = await createTrip("owner_scope_a");
    const b = await createTrip("owner_scope_b");

    const place = await json(
      await call("POST", `/v1/trips/${a.id}/places`, {
        token: token("owner_scope_a"),
        body: { name: "Time Out Market", position: 0 },
      }),
    );

    // Same user, wrong trip id: must not leak or mutate.
    const patched = await call("PATCH", `/v1/trips/${b.id}/places/${place.id}`, {
      token: token("owner_scope_a"),
      body: { name: "Moved" },
    });
    expect(patched.status).toBe(404);

    const otherTripRead = await call("GET", `/v1/trips/${b.id}/places`, {
      token: token("owner_scope_a"),
    });
    expect(otherTripRead.status).toBe(404);
  });

  it("lets viewers read but not write", async () => {
    const trip = await createTrip("owner_viewer");
    const viewerId = await seedProfile("viewer_sub");
    await addMember(trip.id, viewerId, "viewer");

    const read = await call("GET", `/v1/trips/${trip.id}`, { token: token("viewer_sub") });
    expect(read.status).toBe(200);

    const write = await call("PATCH", `/v1/trips/${trip.id}`, {
      token: token("viewer_sub"),
      body: { title: "Viewer edit" },
    });
    expect(write.status).toBe(403);
    expect((await json(write)).error.code).toBe("read_only");
  });

  it("only lets the owner delete a trip", async () => {
    const trip = await createTrip("owner_delete");
    const editorId = await seedProfile("editor_sub");
    await addMember(trip.id, editorId, "editor");

    const editorDelete = await call("DELETE", `/v1/trips/${trip.id}`, { token: token("editor_sub") });
    expect(editorDelete.status).toBe(403);

    const ownerDelete = await call("DELETE", `/v1/trips/${trip.id}`, { token: token("owner_delete") });
    expect(ownerDelete.status).toBe(200);
    expect((await call("GET", `/v1/trips/${trip.id}`, { token: token("owner_delete") })).status).toBe(404);
  });

  it("resyncs days when the date range changes", async () => {
    const trip = await createTrip("owner_dates");
    const updated = await call("PATCH", `/v1/trips/${trip.id}`, {
      token: token("owner_dates"),
      body: { start_date: "2026-12-01", end_date: "2026-12-03" },
    });
    expect(updated.status).toBe(200);
    const days = await json(
      await call("GET", `/v1/trips/${trip.id}/days`, { token: token("owner_dates") }),
    );
    expect(days).toHaveLength(3);
    expect(days[2].date).toBe("2026-12-03");
  });

  it("preserves rows across an equivalent date update (no duplicate days)", async () => {
    const trip = await createTrip("owner_idempotent_days");
    for (let index = 0; index < 3; index += 1) {
      await call("PATCH", `/v1/trips/${trip.id}`, {
        token: token("owner_idempotent_days"),
        body: { start_date: "2026-11-12", end_date: "2026-11-16" },
      });
    }
    const days = await json(
      await call("GET", `/v1/trips/${trip.id}/days`, { token: token("owner_idempotent_days") }),
    );
    expect(days).toHaveLength(5);
  });

  it("rejects unknown fields instead of guessing", async () => {
    const response = await call("POST", "/v1/trips", {
      token: token("owner_unknown"),
      body: { title: "Trip", owner_id: "someone-else" },
    });
    expect(response.status).toBe(400);
    expect((await json(response)).error.code).toBe("unknown_fields");
  });
});

describe("idempotency", () => {
  it("replays a POST with the same key", async () => {
    const key = "idem-1";
    const body = { title: "Replay trip", start_date: "2026-11-12", end_date: "2026-11-13" };
    const first = await call("POST", "/v1/trips", {
      token: token("owner_idem"),
      body,
      headers: { "idempotency-key": key },
    });
    const second = await call("POST", "/v1/trips", {
      token: token("owner_idem"),
      body,
      headers: { "idempotency-key": key },
    });
    expect(first.status).toBe(201);
    expect(second.status).toBe(201);
    expect(second.headers.get("idempotent-replay")).toBe("true");
    expect((await json(second)).id).toBe((await json(first)).id);

    const trips = await json(await call("GET", "/v1/trips", { token: token("owner_idem") }));
    expect(trips).toHaveLength(1);
  });

  it("scopes idempotency keys per user", async () => {
    const key = "shared-key";
    const body = { title: "Mine" };
    const mine = await call("POST", "/v1/trips", {
      token: token("owner_idem_a"),
      body,
      headers: { "idempotency-key": key },
    });
    const theirs = await call("POST", "/v1/trips", {
      token: token("owner_idem_b"),
      body,
      headers: { "idempotency-key": key },
    });
    expect((await json(mine)).id).not.toBe((await json(theirs)).id);
  });
});
