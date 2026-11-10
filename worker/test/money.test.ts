import { describe, expect, it } from "vitest";
import { addMember, call, createTrip, json, seedProfile, token } from "./helpers";

describe("expenses and splits", () => {
  it("stores an expense with its splits and returns arrays as arrays", async () => {
    const trip = await createTrip("owner_money");
    const mateId = await seedProfile("mate_money");
    await addMember(trip.id, mateId);
    const mate = await json(await call("GET", "/v1/me", { token: token("mate_money") }));
    const me = await json(await call("GET", "/v1/me", { token: token("owner_money") }));

    const response = await call("POST", `/v1/trips/${trip.id}/expenses`, {
      token: token("owner_money"),
      body: {
        title: "Dinner",
        amount: 60,
        currency: "EUR",
        category: "food",
        paid_by: me.id,
        split_with: [me.id, mate.id],
        split_mode: "equal",
        spent_at: "2026-11-12",
        splits: [
          { user_id: me.id, amount: 30 },
          { user_id: mate.id, amount: 30 },
        ],
      },
    });
    expect(response.status).toBe(201);
    const expense = await json(response);
    expect(expense.split_with).toEqual([me.id, mate.id]);
    expect(expense.created_by).toBe(me.id);

    const splits = await json(
      await call("GET", `/v1/trips/${trip.id}/expense-splits`, { token: token("owner_money") }),
    );
    expect(splits).toHaveLength(2);
    expect(splits.reduce((sum: number, row: any) => sum + row.amount, 0)).toBeCloseTo(60);

    // The other member can read the split too.
    const mateView = await json(
      await call("GET", `/v1/trips/${trip.id}/expenses`, { token: token("mate_money") }),
    );
    expect(mateView[0].title).toBe("Dinner");
  });

  it("rejects negative amounts", async () => {
    const trip = await createTrip("owner_negative");
    const response = await call("POST", `/v1/trips/${trip.id}/expenses`, {
      token: token("owner_negative"),
      body: { title: "Refund?", amount: -10, spent_at: "2026-11-12" },
    });
    expect(response.status).toBe(400);
  });

  it("records settlements", async () => {
    const trip = await createTrip("owner_settle");
    const a = await json(await call("GET", "/v1/me", { token: token("owner_settle") }));
    const b = await json(await call("GET", "/v1/me", { token: token("settle_mate") }));
    await addMember(trip.id, b.id);

    const response = await call("POST", `/v1/trips/${trip.id}/settlements`, {
      token: token("owner_settle"),
      body: {
        from_user: b.id,
        to_user: a.id,
        amount: 15,
        currency: "EUR",
        settled_at: "2026-11-14",
      },
    });
    expect(response.status).toBe(201);
    const rows = await json(
      await call("GET", `/v1/trips/${trip.id}/settlements`, { token: token("settle_mate") }),
    );
    expect(rows).toHaveLength(1);
  });
});

describe("checklist", () => {
  it("round-trips booleans as JSON booleans", async () => {
    const trip = await createTrip("owner_check");
    const created = await json(
      await call("POST", `/v1/trips/${trip.id}/checklist`, {
        token: token("owner_check"),
        body: { title: "Passport", position: 0 },
      }),
    );
    expect(created.is_checked).toBe(false);

    const toggled = await json(
      await call("PATCH", `/v1/trips/${trip.id}/checklist/${created.id}`, {
        token: token("owner_check"),
        body: { is_checked: true },
      }),
    );
    expect(toggled.is_checked).toBe(true);
  });
});

describe("invites", () => {
  it("creates an invite and lets the matching email accept it", async () => {
    const trip = await createTrip("owner_invite");
    const inviteeId = await seedProfile("invitee_sub", "friend@example.com");

    const invite = await json(
      await call("POST", `/v1/trips/${trip.id}/invites`, {
        token: token("owner_invite"),
        body: { email: "Friend@Example.com", role: "editor" },
      }),
    );
    expect(invite.email).toBe("friend@example.com");
    expect(invite.email_delivered).toBe(false);

    const accepted = await call("POST", `/v1/invites/${invite.token}/accept`, {
      token: token("invitee_sub"),
    });
    expect(accepted.status).toBe(200);

    const tripView = await call("GET", `/v1/trips/${trip.id}`, { token: token("invitee_sub") });
    expect(tripView.status).toBe(200);
    expect(inviteeId).toBeTruthy();

    // A used invite cannot be accepted twice.
    const reused = await call("POST", `/v1/invites/${invite.token}/accept`, {
      token: token("invitee_sub"),
    });
    expect(reused.status).toBe(409);
  });

  it("refuses an invite addressed to another email", async () => {
    const trip = await createTrip("owner_invite_b");
    await seedProfile("other_sub", "other@example.com");
    const invite = await json(
      await call("POST", `/v1/trips/${trip.id}/invites`, {
        token: token("owner_invite_b"),
        body: { email: "intended@example.com" },
      }),
    );
    const response = await call("POST", `/v1/invites/${invite.token}/accept`, {
      token: token("other_sub"),
    });
    expect(response.status).toBe(403);
    expect((await json(response)).error.code).toBe("invite_email_mismatch");
  });

  it("validates email addresses", async () => {
    const trip = await createTrip("owner_invite_c");
    const response = await call("POST", `/v1/trips/${trip.id}/invites`, {
      token: token("owner_invite_c"),
      body: { email: "not-an-email" },
    });
    expect(response.status).toBe(400);
  });

  it("rate limits invite email bursts", async () => {
    const trip = await createTrip("owner_invite_rate");
    let limited = 0;
    for (let index = 0; index < 12; index += 1) {
      const response = await call("POST", `/v1/trips/${trip.id}/invites`, {
        token: token("owner_invite_rate"),
        body: { email: `person${index}@example.com` },
      });
      if (response.status === 429) limited += 1;
    }
    expect(limited).toBeGreaterThan(0);
  });
});
