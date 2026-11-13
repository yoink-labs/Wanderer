import { describe, expect, it } from "vitest";
import { addMember, call, createTrip, json, seedProfile, token } from "./helpers";

describe("personal layer", () => {
  it("keeps private places visible only to their owner", async () => {
    const owner = await createTrip("owner");
    const otherSub = `other-${crypto.randomUUID()}`;
    const other = await seedProfile(otherSub);
    await addMember(owner.id, other, "editor");

    const created = await call("POST", `/v1/trips/${owner.id}/personal/places`, {
      token: token("owner"),
      body: {
        name: "My quiet morning cafe",
        category: "food",
        lat: 38.71,
        lng: -9.14,
      },
    });
    expect(created.status).toBe(201);
    const place = await json(created);
    expect(place.name).toBe("My quiet morning cafe");

    const mine = await json(await call("GET", `/v1/trips/${owner.id}/personal`, { token: token("owner") }));
    expect(mine.private_places).toHaveLength(1);

    const theirs = await json(await call("GET", `/v1/trips/${owner.id}/personal`, { token: token(otherSub) }));
    expect(theirs.private_places).toHaveLength(0);

    const patch = await call("PATCH", `/v1/trips/${owner.id}/personal/places/${place.id}`, {
      token: token("owner"),
      body: { name: "Renamed cafe" },
    });
    expect(patch.status).toBe(200);
    expect((await json(patch)).name).toBe("Renamed cafe");

    // Another member cannot edit or delete it even with the id.
    const forbidden = await call("DELETE", `/v1/trips/${owner.id}/personal/places/${place.id}`, {
      token: token(otherSub),
    });
    expect(forbidden.status).toBe(404);

    const removed = await call("DELETE", `/v1/trips/${owner.id}/personal/places/${place.id}`, {
      token: token("owner"),
    });
    expect(removed.status).toBe(200);
  });

  it("hides and replaces a shared place for one member only", async () => {
    const owner = await createTrip("owner");
    const otherSub = `other-${crypto.randomUUID()}`;
    const other = await seedProfile(otherSub);
    await addMember(owner.id, other, "editor");

    const placeResponse = await call("POST", `/v1/trips/${owner.id}/places`, {
      token: token("owner"),
      body: { name: "Group dinner", category: "food" },
    });
    const place = await json(placeResponse);

    const override = await call("PUT", `/v1/trips/${owner.id}/personal/overrides/place/${place.id}`, {
      token: token(otherSub),
      body: { hidden: true, data: { name: "Dinner on my own" } },
    });
    expect(override.status).toBe(200);
    const saved = await json(override);
    expect(saved.hidden).toBe(true);
    expect(saved.data.name).toBe("Dinner on my own");

    // The shared row is untouched.
    const shared = await json(await call("GET", `/v1/trips/${owner.id}/places`, { token: token("owner") }));
    expect(shared[0].name).toBe("Group dinner");

    const mine = await json(await call("GET", `/v1/trips/${owner.id}/personal`, { token: token(otherSub) }));
    expect(mine.overrides).toHaveLength(1);
    const theirs = await json(await call("GET", `/v1/trips/${owner.id}/personal`, { token: token("owner") }));
    expect(theirs.overrides).toHaveLength(0);

    // Clearing an override deletes it.
    const cleared = await call("PUT", `/v1/trips/${owner.id}/personal/overrides/place/${place.id}`, {
      token: token(otherSub),
      body: { hidden: false, data: {} },
    });
    expect((await json(cleared)).deleted).toBe(true);
    expect(
      (await json(await call("GET", `/v1/trips/${owner.id}/personal`, { token: token(otherSub) }))).overrides,
    ).toHaveLength(0);
  });

  it("rejects unknown override fields and item types", async () => {
    const trip = await createTrip("owner");
    const badField = await call("PUT", `/v1/trips/${trip.id}/personal/overrides/place/abc`, {
      token: token("owner"),
      body: { hidden: true, data: { sneaky: true } },
    });
    expect(badField.status).toBe(400);

    const badType = await call("PUT", `/v1/trips/${trip.id}/personal/overrides/expense/abc`, {
      token: token("owner"),
      body: { hidden: true },
    });
    expect(badType.status).toBe(400);
  });

  it("returns the whole trip in one bundle with the caller's personal layer", async () => {
    const trip = await createTrip("owner");
    await call("POST", `/v1/trips/${trip.id}/places`, {
      token: token("owner"),
      body: { name: "Belem Tower", category: "sight" },
    });
    await call("POST", `/v1/trips/${trip.id}/personal/places`, {
      token: token("owner"),
      body: { name: "Only mine" },
    });

    const response = await call("GET", `/v1/trips/${trip.id}/bundle`, { token: token("owner") });
    expect(response.status).toBe(200);
    const bundle = await json(response);
    expect(bundle.trip.id).toBe(trip.id);
    expect(bundle.days).toHaveLength(5);
    expect(bundle.places).toHaveLength(1);
    expect(bundle.personal.private_places).toHaveLength(1);
  });
});
