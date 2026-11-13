import { env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { call, createTrip, json, token } from "./helpers";

const HOST = "aerodatabox.p.rapidapi.com";

type Responder = (url: string) => Response | Promise<Response>;

let calls: string[] = [];
let responder: Responder = () => new Response("no route", { status: 500 });

function dateIn(days: number): string {
  const date = new Date(Date.now() + days * 86_400_000);
  return date.toISOString().slice(0, 10);
}

function sampleFlight(number: string, date: string) {
  return [
    {
      number,
      status: "Expected",
      isCargo: false,
      airline: { name: "British Airways", iata: "BA" },
      aircraft: { model: "Airbus A320" },
      departure: {
        airport: { iata: "LHR", shortName: "London Heathrow", municipalityName: "London" },
        scheduledTime: { utc: `${date}T09:00:00Z`, local: `${date}T09:00:00+00:00` },
        revisedTime: { utc: `${date}T09:25:00Z`, local: `${date}T09:25:00+00:00` },
        terminal: "5",
        gate: "A10",
      },
      arrival: {
        airport: { iata: "LIS", shortName: "Lisbon", municipalityName: "Lisbon" },
        scheduledTime: { utc: `${date}T11:35:00Z`, local: `${date}T11:35:00+00:00` },
        terminal: "1",
      },
      greatCircleDistance: { km: 1585 },
    },
  ];
}

function upstreamFlight(number: string, date: string): Responder {
  return () =>
    new Response(JSON.stringify(sampleFlight(number, date)), {
      headers: { "content-type": "application/json" },
    });
}

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM flight_cache").run();
  await env.DB.prepare("DELETE FROM flight_usage").run();
  calls = [];
  responder = () => new Response("no route", { status: 500 });
  vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
    calls.push(String(input));
    return responder(String(input));
  });
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("flight status", () => {
  it("normalizes an upstream flight and serves the next lookup from cache", async () => {
    const date = dateIn(14);
    responder = upstreamFlight("BA123", date);

    const first = await json(await call("GET", `/v1/flights/BA123/${date}`, { token: token("flyer") }));
    expect(first.cached).toBe(false);
    expect(first.flight.flight_number).toBe("BA123");
    expect(first.flight.status_label).toBe("On time");
    expect(first.flight.departure.airport).toBe("LHR");
    expect(first.flight.departure.terminal).toBe("5");
    expect(first.flight.departure.delay_minutes).toBe(25);
    expect(first.flight.arrival.airport).toBe("LIS");
    expect(first.attribution).toContain("AeroDataBox");
    expect(calls).toHaveLength(1);
    expect(calls[0]).toContain(`/flights/Number/BA123/${date}`);

    const second = await json(await call("GET", `/v1/flights/ba 123/${date}`, { token: token("flyer") }));
    expect(second.cached).toBe(true);
    expect(second.flight.flight_number).toBe("BA123");
    expect(calls).toHaveLength(1);
  });

  it("serves the last known status when a refresh fails", async () => {
    const date = dateIn(10);
    responder = upstreamFlight("TP42", date);
    await call("GET", `/v1/flights/TP42/${date}`, { token: token("flyer") });

    await env.DB.prepare("UPDATE flight_cache SET expires_at = ?")
      .bind(new Date(Date.now() - 1000).toISOString())
      .run();
    responder = () => new Response("boom", { status: 500 });

    const stale = await json(await call("GET", `/v1/flights/TP42/${date}`, { token: token("flyer") }));
    expect(stale.stale).toBe(true);
    expect(stale.flight.flight_number).toBe("TP42");
  });

  it("stops calling upstream once the monthly unit budget is spent", async () => {
    const date = dateIn(20);
    const month = new Date().toISOString().slice(0, 7);
    await env.DB.prepare("INSERT INTO flight_usage (month, units, requests) VALUES (?, 380, 200)")
      .bind(month)
      .run();

    const response = await call("GET", `/v1/flights/NOTFOUND/${date}`, { token: token("flyer") });
    expect(response.status).toBe(200);
    const body = await json(response);
    expect(body.budget_exhausted).toBe(true);
    expect(body.flight).toBeNull();
    expect(calls).toHaveLength(0);
  });

  it("rejects malformed flight numbers and dates", async () => {
    expect((await call("GET", `/v1/flights/!!!/2026-01-01`, { token: token("flyer") })).status).toBe(400);
    expect((await call("GET", `/v1/flights/BA123/not-a-date`, { token: token("flyer") })).status).toBe(400);
  });

  it("attaches statuses to a trip's flight reservations", async () => {
    const trip = await createTrip("owner");
    const date = dateIn(1);    responder = upstreamFlight("UA88", date);
    await call("POST", `/v1/trips/${trip.id}/reservations`, {
      token: token("owner"),
      body: {
        type: "flight",
        title: "UA88",
        start_at: `${date}T18:00:00Z`,
        end_at: `${date}T23:00:00Z`,
        metadata: { flight_number: "UA88", flight_date: date },
      },
    });

    const response = await call("GET", `/v1/trips/${trip.id}/flights`, { token: token("owner") });
    expect(response.status).toBe(200);
    const body = await json(response);
    const entries = Object.values(body.flights) as Array<Record<string, unknown>>;
    expect(entries).toHaveLength(1);
    expect((entries[0].flight as Record<string, unknown>).flight_number).toBe("UA88");
    expect(body.attribution).toContain("AeroDataBox");
    expect(body.budget.units_used).toBeGreaterThan(0);
  });
});

describe("CORS", () => {
  it("answers preflight for an allowed web origin", async () => {
    const response = await call("OPTIONS", "/v1/trips", {
      token: null,
      headers: {
        origin: "http://localhost:5173",
        "access-control-request-method": "POST",
      },
    });
    expect(response.status).toBe(204);
    expect(response.headers.get("access-control-allow-origin")).toBe("http://localhost:5173");
  });

  it("refuses preflight from an unknown origin", async () => {
    const response = await call("OPTIONS", "/v1/trips", {
      token: null,
      headers: { origin: "https://evil.example" },
    });
    expect(response.status).toBe(403);
  });
});
