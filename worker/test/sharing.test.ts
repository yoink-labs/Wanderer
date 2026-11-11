import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { call, createTrip, json, token } from "./helpers";

async function addStop(owner: string, tripId: string, name: string, extra: Record<string, unknown> = {}) {
  const days = await json<any[]>(await call("GET", `/v1/trips/${tripId}/days`, { token: token(owner) }));
  const response = await call("POST", `/v1/trips/${tripId}/places`, {
    token: token(owner),
    body: { name, day_id: days[0].id, category: "food", address: "Rua Augusta 1", notes: "PRIVATE NOTE", ...extra },
  });
  expect(response.status).toBe(201);
}

describe("public shared trip page", () => {
  it("shows the itinerary but never people, notes or costs", async () => {
    const trip = await createTrip("share_owner");
    await addStop("share_owner", trip.id, "Time Out Market");
    await call("POST", `/v1/trips/${trip.id}/expenses`, {
      token: token("share_owner"),
      body: { title: "Secret dinner", amount: 999, spent_at: "2026-11-12" },
    });

    const response = await call("GET", `/s/${trip.share_token}`, { token: null });
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/html");
    expect(response.headers.get("x-robots-tag")).toContain("noindex");
    expect(response.headers.get("content-security-policy")).toContain("default-src 'none'");
    const html = await response.text();
    expect(html).toContain("Lisbon in November");
    expect(html).toContain("Time Out Market");
    expect(html).not.toContain("PRIVATE NOTE");
    expect(html).not.toContain("Secret dinner");
    expect(html).not.toContain("share_owner");
  });

  it("escapes HTML in trip content", async () => {
    const trip = await createTrip("share_xss");
    await addStop("share_xss", trip.id, "<script>alert(1)</script>");
    const html = await (await call("GET", `/s/${trip.share_token}`, { token: null })).text();
    expect(html).not.toContain("<script>alert(1)</script>");
    expect(html).toContain("&lt;script&gt;");
  });

  it("returns a friendly 404 for unknown or malformed tokens", async () => {
    expect((await call("GET", `/s/${crypto.randomUUID()}`, { token: null })).status).toBe(404);
    expect((await call("GET", "/s/not-a-token", { token: null })).status).toBe(404);
  });

  it("turns the old link off when the owner makes a new one", async () => {
    const trip = await createTrip("share_rotate");
    const rotated = await call("POST", `/v1/trips/${trip.id}/share-link`, { token: token("share_rotate") });
    expect(rotated.status).toBe(200);
    const { share_token } = await json<{ share_token: string }>(rotated);
    expect(share_token).not.toBe(trip.share_token);
    expect((await call("GET", `/s/${trip.share_token}`, { token: null })).status).toBe(404);
    expect((await call("GET", `/s/${share_token}`, { token: null })).status).toBe(200);
  });

  it("only lets the owner change the link", async () => {
    const trip = await createTrip("share_owner2");
    const editorMe = await json<{ id: string }>(await call("GET", "/v1/me", { token: token("share_editor") }));
    await env.DB.prepare("INSERT INTO trip_members (trip_id, user_id, role) VALUES (?, ?, 'editor')").bind(trip.id, editorMe.id).run();
    const response = await call("POST", `/v1/trips/${trip.id}/share-link`, { token: token("share_editor") });
    expect(response.status).toBe(403);
  });
});

describe("invites", () => {
  it("claims pending invites for the signed-in email and shows a landing page", async () => {
    const trip = await createTrip("inv_owner");
    const created = await call("POST", `/v1/trips/${trip.id}/invites`, {
      token: token("inv_owner"),
      body: { email: "Friend@Example.com", role: "editor" },
    });
    expect(created.status).toBe(201);
    const invite = await json<{ token: string }>(created);

    const page = await call("GET", `/invite/${invite.token}`, { token: null });
    expect(page.status).toBe(200);
    const html = await page.text();
    expect(html).toContain("Lisbon in November");
    expect(html).not.toContain("friend@example.com");

    // Someone else signing in claims nothing.
    const stranger = await json<{ claimed: string[] }>(
      await call("POST", "/v1/invites/claim", { token: token("inv_stranger|stranger@example.com") }),
    );
    expect(stranger.claimed).toEqual([]);

    // The invited person (email casing differs) gets the trip once.
    const first = await json<{ claimed: string[] }>(
      await call("POST", "/v1/invites/claim", { token: token("inv_friend|friend@example.com") }),
    );
    expect(first.claimed).toEqual([trip.id]);
    const again = await json<{ claimed: string[] }>(
      await call("POST", "/v1/invites/claim", { token: token("inv_friend|friend@example.com") }),
    );
    expect(again.claimed).toEqual([]);
    const trips = await json<any[]>(await call("GET", "/v1/trips", { token: token("inv_friend|friend@example.com") }));
    expect(trips.map((t) => t.id)).toContain(trip.id);
  });

  it("does not claim expired invites", async () => {
    const trip = await createTrip("inv_owner2");
    await env.DB.prepare(
      "INSERT INTO trip_invites (id, trip_id, email, role, token, expires_at) VALUES (?, ?, 'late@example.com', 'editor', ?, '2000-01-01T00:00:00Z')",
    ).bind(crypto.randomUUID(), trip.id, crypto.randomUUID()).run();
    const result = await json<{ claimed: string[] }>(
      await call("POST", "/v1/invites/claim", { token: token("inv_late|late@example.com") }),
    );
    expect(result.claimed).toEqual([]);
  });

  it("fills in a missing profile email once the token carries one", async () => {
    await call("GET", "/v1/me", { token: token("inv_noemail") });
    const before = await env.DB.prepare("SELECT email FROM identities WHERE clerk_sub = 'inv_noemail'").first<{ email: string | null }>();
    expect(before?.email).toBeNull();
    await call("GET", "/v1/me", { token: token("inv_noemail|Later@Example.com") });
    const after = await env.DB.prepare("SELECT email FROM identities WHERE clerk_sub = 'inv_noemail'").first<{ email: string | null }>();
    expect(after?.email).toBe("later@example.com");
  });
});
