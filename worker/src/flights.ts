/**
 * Flight status through AeroDataBox's RapidAPI marketplace listing.
 *
 * The free plan is small (400 API units and 1,600 requests per month), so this
 * module is built around a shared cache rather than per-user calls:
 *
 * - one cache row per flight number + date serves every member who tracks it;
 * - a refresh is only attempted when the cached copy has expired;
 * - a monthly budget guard refuses upstream calls before they are made and
 *   serves the last known status instead;
 * - completed flights are cached for the seven days the terms allow and never
 *   refreshed.
 *
 * Attribution is required by AeroDataBox's terms; every payload carries
 * `attribution` and the app renders it beside the status.
 */

import { ApiError } from "./http";

export const FLIGHT_ATTRIBUTION = "Flight data by AeroDataBox";

/** Free-plan limits from the RapidAPI Basic plan. Overridable for tests. */
const MONTHLY_UNIT_CAP = 380;
const MONTHLY_REQUEST_CAP = 1_500;
/** Flight-status lookups are a Tier 2 endpoint on the Basic plan. */
const REQUEST_UNITS = 2;
/** Never let one page load fan out into a burst of paid calls. */
const MAX_REFRESHES_PER_REQUEST = 3;

export interface FlightEnv {
  DB: D1Database;
  RAPIDAPI_KEY?: string;
  RAPIDAPI_HOST?: string;
  FLIGHT_MONTHLY_UNIT_CAP?: string;
  FLIGHT_MONTHLY_REQUEST_CAP?: string;
}

export interface NormalizedFlight {
  flight_number: string;
  date: string;
  status: string;
  status_label: string;
  airline: { name: string | null; iata: string | null } | null;
  aircraft: string | null;
  departure: FlightEnd;
  arrival: FlightEnd;
  great_circle_km: number | null;
  updated_at: string;
  source: "AeroDataBox";
  attribution: string;
}

export interface FlightEnd {
  airport: string | null;
  airport_name: string | null;
  city: string | null;
  terminal: string | null;
  gate: string | null;
  scheduled: string | null;
  estimated: string | null;
  actual: string | null;
  delay_minutes: number | null;
}

export interface FlightLookup {
  flight: NormalizedFlight | null;
  cached: boolean;
  stale: boolean;
  fetched_at: string | null;
  attribution: string;
  /** True when the cache was empty and the free-plan budget said no. */
  budget_exhausted: boolean;
}

interface CacheRow {
  cache_key: string;
  payload: string;
  fetched_at: string;
  expires_at: string;
}

function nowIso(): string {
  return new Date().toISOString();
}

function monthKey(date = new Date()): string {
  return date.toISOString().slice(0, 7);
}

export function normalizeFlightNumber(raw: string): string {
  return raw.toUpperCase().replace(/[\s-]/g, "").slice(0, 10);
}

export function isFlightDate(raw: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return false;
  const time = Date.parse(`${raw}T00:00:00Z`);
  return Number.isFinite(time);
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function pickString(source: Record<string, unknown> | null, ...keys: string[]): string | null {
  if (!source) return null;
  for (const key of keys) {
    const value = source[key];
    if (typeof value === "string" && value.trim().length > 0) return value;
    if (typeof value === "number") return String(value);
  }
  return null;
}

function timeValue(source: Record<string, unknown> | null, key: string): string | null {
  const time = asRecord(source?.[key]);
  return pickString(time, "utc", "local");
}

function delayMinutes(end: FlightEnd): number | null {
  if (!end.scheduled) return null;
  const revised = end.actual ?? end.estimated;
  if (!revised) return null;
  const scheduled = Date.parse(end.scheduled);
  const actual = Date.parse(revised);
  if (!Number.isFinite(scheduled) || !Number.isFinite(actual)) return null;
  return Math.round((actual - scheduled) / 60_000);
}

function normalizeEnd(raw: Record<string, unknown> | null): FlightEnd {
  const airport = asRecord(raw?.airport);
  const end: FlightEnd = {
    airport: pickString(airport, "iata", "icao"),
    airport_name: pickString(airport, "shortName", "name"),
    city: pickString(airport, "municipalityName"),
    terminal: pickString(raw, "terminal"),
    gate: pickString(raw, "gate"),
    scheduled: timeValue(raw, "scheduledTime"),
    // AeroDataBox has one "revised" time (actual or estimated) plus the
    // runway time, which is actual once the aircraft has moved.
    estimated: timeValue(raw, "revisedTime"),
    actual: timeValue(raw, "runwayTime"),
    delay_minutes: null,
  };
  end.delay_minutes = delayMinutes(end);
  return end;
}

/** Statuses AeroDataBox uses; a stable label keeps the UI copy consistent. */
const STATUS_LABELS: Record<string, string> = {
  Unknown: "Unknown",
  Expected: "On time",
  CheckIn: "Check-in",
  Boarding: "Boarding",
  GateClosed: "Gate closed",
  Departed: "In the air",
  EnRoute: "In the air",
  Approaching: "Landing soon",
  Arrived: "Landed",
  Delayed: "Delayed",
  Diverted: "Diverted",
  Canceled: "Cancelled",
  CanceledUncertain: "Possibly cancelled",
};

const TERMINAL_STATUSES = new Set(["Arrived", "Canceled", "Diverted"]);

export function normalizeFlight(raw: Record<string, unknown>, fallbackNumber: string, fallbackDate: string): NormalizedFlight {
  const status = pickString(raw, "status") ?? "Unknown";
  const airline = asRecord(raw.airline);
  const aircraft = asRecord(raw.aircraft);
  const departure = normalizeEnd(asRecord(raw.departure));
  const arrival = normalizeEnd(asRecord(raw.arrival));
  const distance = asRecord(raw.greatCircleDistance);
  const number = pickString(raw, "number", "callSign") ?? fallbackNumber;

  return {
    flight_number: number,
    date: fallbackDate,
    status,
    status_label: STATUS_LABELS[status] ?? status,
    airline: airline
      ? { name: pickString(airline, "name"), iata: pickString(airline, "iata") }
      : null,
    aircraft: pickString(aircraft, "model", "reg"),
    departure,
    arrival,
    great_circle_km: distance && typeof distance.km === "number" ? distance.km : null,
    updated_at: pickString(raw, "lastUpdatedUtc") ?? nowIso(),
    source: "AeroDataBox",
    attribution: FLIGHT_ATTRIBUTION,
  };
}

/**
 * How long a cached status stays fresh. Near departure the status changes
 * often; far out, a schedule is stable. Completed flights never refresh.
 */
export function cacheSeconds(flight: NormalizedFlight, now = Date.now()): number {
  if (TERMINAL_STATUSES.has(flight.status)) return 7 * 24 * 3600;
  const departure = Date.parse(flight.departure.scheduled ?? `${flight.date}T00:00:00Z`);
  if (!Number.isFinite(departure)) return 12 * 3600;
  const away = departure - now;
  if (away < 0) return 30 * 60; // should have left; check again in half an hour
  if (away < 12 * 3600 * 1000) return 20 * 60;
  if (away < 72 * 3600 * 1000) return 2 * 3600;
  return 12 * 3600;
}

function quota(name: string | undefined, fallback: number): number {
  const value = Number(name);
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
}

/** Reserve units before an upstream call. Returns false when the budget is spent. */
async function reserveBudget(env: FlightEnv, units: number): Promise<boolean> {
  const month = monthKey();
  const unitCap = quota(env.FLIGHT_MONTHLY_UNIT_CAP, MONTHLY_UNIT_CAP);
  const requestCap = quota(env.FLIGHT_MONTHLY_REQUEST_CAP, MONTHLY_REQUEST_CAP);
  const stamp = nowIso();

  const updated = await env.DB.prepare(
    `UPDATE flight_usage
        SET units = units + ?, requests = requests + 1, updated_at = ?
      WHERE month = ?
        AND units + ? <= ?
        AND requests + 1 <= ?`,
  )
    .bind(units, stamp, month, units, unitCap, requestCap)
    .run();
  if (updated.meta.changes) return true;

  // No row yet: create it if the first call fits.
  const exists = await env.DB.prepare("SELECT month FROM flight_usage WHERE month = ?")
    .bind(month)
    .first<{ month: string }>();
  if (exists) return false;

  const inserted = await env.DB.prepare(
    `INSERT INTO flight_usage (month, units, requests, updated_at)
     VALUES (?, ?, 1, ?)
     ON CONFLICT (month) DO NOTHING`,
  )
    .bind(month, units, stamp)
    .run();
  return Boolean(inserted.meta.changes);
}

async function readCache(env: FlightEnv, key: string): Promise<CacheRow | null> {
  return await env.DB.prepare(
    "SELECT cache_key, payload, fetched_at, expires_at FROM flight_cache WHERE cache_key = ?",
  )
    .bind(key)
    .first<CacheRow>();
}

async function writeCache(env: FlightEnv, key: string, number: string, date: string, flight: NormalizedFlight): Promise<void> {
  const stamp = nowIso();
  const expires = new Date(Date.now() + cacheSeconds(flight) * 1000).toISOString();
  await env.DB.prepare(
    `INSERT INTO flight_cache (cache_key, flight_number, flight_date, payload, fetched_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT (cache_key) DO UPDATE SET
       payload = excluded.payload,
       fetched_at = excluded.fetched_at,
       expires_at = excluded.expires_at`,
  )
    .bind(key, number, date, JSON.stringify(flight), stamp, expires)
    .run();
}

async function callAeroDataBox(
  env: FlightEnv,
  number: string,
  date: string,
): Promise<NormalizedFlight> {
  if (!env.RAPIDAPI_KEY) {
    throw new ApiError(503, "flights_not_configured", "Live flight status is not configured.");
  }
  const host = env.RAPIDAPI_HOST || "aerodatabox.p.rapidapi.com";
  const endpoint =
    `https://${host}/flights/Number/${encodeURIComponent(number)}/${encodeURIComponent(date)}` +
    `?dateLocalRole=Departure&withAircraftImage=false&withLocation=false`;

  let response: Response;
  try {
    response = await fetch(endpoint, {
      headers: {
        "x-rapidapi-key": env.RAPIDAPI_KEY,
        "x-rapidapi-host": host,
        accept: "application/json",
      },
      signal: AbortSignal.timeout(9_000),
    });
  } catch {
    throw new ApiError(504, "flight_lookup_timeout", "Flight status did not respond.");
  }

  if (response.status === 204) {
    throw new ApiError(404, "flight_not_found", "No flight matched that number and date.");
  }
  if (response.status === 429) {
    throw new ApiError(429, "flight_rate_limited", "Flight lookups are busy. Try again shortly.");
  }
  if (response.status === 401 || response.status === 403) {
    throw new ApiError(502, "flight_lookup_rejected", "Flight status could not be read.");
  }
  if (!response.ok) {
    throw new ApiError(502, "flight_lookup_failed", "Flight status could not be read.");
  }

  const body = await response.json<unknown>();
  const list = Array.isArray(body) ? body : [body];
  const first = list.map(asRecord).find((entry) => entry && !entry.isCargo) ?? asRecord(list[0]);
  if (!first) {
    throw new ApiError(404, "flight_not_found", "No flight matched that number and date.");
  }
  return normalizeFlight(first, number, date);
}

function parseCached(row: CacheRow): NormalizedFlight | null {
  try {
    return JSON.parse(row.payload) as NormalizedFlight;
  } catch {
    return null;
  }
}

/**
 * Look up one flight, using and refreshing the shared cache.
 *
 * `allowRefresh: false` is used for background lists so a screen refresh does
 * not spend the month's units; the cached copy is returned instead.
 */
export async function fetchFlightStatus(
  env: FlightEnv,
  rawNumber: string,
  date: string,
  options: { allowRefresh?: boolean; force?: boolean } = {},
): Promise<FlightLookup> {
  const number = normalizeFlightNumber(rawNumber);
  if (!/^[A-Z0-9]{2,8}$/.test(number)) {
    throw new ApiError(400, "invalid_flight_number", "Enter a flight number like BA123.");
  }
  if (!isFlightDate(date)) {
    throw new ApiError(400, "invalid_flight_date", "Use a yyyy-MM-dd date.");
  }

  const key = `${number}:${date}`;
  const row = await readCache(env, key);
  const cached = row ? parseCached(row) : null;
  const fresh = row ? Date.parse(row.expires_at) > Date.now() : false;

  if (row && cached && fresh && !options.force) {
    return {
      flight: cached,
      cached: true,
      stale: false,
      fetched_at: row.fetched_at,
      attribution: FLIGHT_ATTRIBUTION,
      budget_exhausted: false,
    };
  }

  if (options.allowRefresh === false) {
    return {
      flight: cached,
      cached: Boolean(row),
      stale: Boolean(row),
      fetched_at: row?.fetched_at ?? null,
      attribution: FLIGHT_ATTRIBUTION,
      budget_exhausted: false,
    };
  }

  if (!(await reserveBudget(env, REQUEST_UNITS))) {
    return {
      flight: cached,
      cached: Boolean(row),
      stale: Boolean(row),
      fetched_at: row?.fetched_at ?? null,
      attribution: FLIGHT_ATTRIBUTION,
      budget_exhausted: true,
    };
  }

  try {
    const flight = await callAeroDataBox(env, number, date);
    await writeCache(env, key, number, date, flight);
    return {
      flight,
      cached: false,
      stale: false,
      fetched_at: nowIso(),
      attribution: FLIGHT_ATTRIBUTION,
      budget_exhausted: false,
    };
  } catch (error) {
    // A failed refresh must not throw away usable data.
    if (cached) {
      return {
        flight: cached,
        cached: true,
        stale: true,
        fetched_at: row?.fetched_at ?? null,
        attribution: FLIGHT_ATTRIBUTION,
        budget_exhausted: false,
      };
    }
    throw error;
  }
}

interface ReservationLike {
  id: string;
  type?: string | null;
  title?: string | null;
  start_at?: string | null;
  metadata?: unknown;
}

interface FlightReference {
  number: string;
  date: string;
}

/** Reads the flight reference from a reservation's metadata JSON. */
export function flightReference(reservation: ReservationLike): FlightReference | null {
  if (reservation.type && reservation.type !== "flight") return null;
  let metadata: Record<string, unknown> | null = null;
  if (typeof reservation.metadata === "string") {
    try {
      metadata = asRecord(JSON.parse(reservation.metadata));
    } catch {
      metadata = null;
    }
  } else {
    metadata = asRecord(reservation.metadata);
  }
  const rawNumber =
    pickString(metadata, "flight_number", "flightNumber") ??
    (typeof reservation.title === "string" && /^[A-Z]{2}\s?\d{1,4}$/i.test(reservation.title.trim())
      ? reservation.title.trim()
      : null);
  if (!rawNumber) return null;

  const rawDate =
    pickString(metadata, "flight_date", "flightDate") ??
    (typeof reservation.start_at === "string" ? reservation.start_at.slice(0, 10) : null);
  if (!rawDate || !isFlightDate(rawDate)) return null;

  return { number: normalizeFlightNumber(rawNumber), date: rawDate };
}

/**
 * Statuses for a trip's flight reservations. Only flights within three days
 * of departure may trigger an upstream refresh, and at most three do per call.
 */
export async function flightsForReservations(
  env: FlightEnv,
  reservations: ReservationLike[],
): Promise<{ flights: Record<string, FlightLookup>; refreshed: number }> {
  const flights: Record<string, FlightLookup> = {};
  let refreshesLeft = MAX_REFRESHES_PER_REQUEST;
  const now = Date.now();

  await Promise.all(
    reservations.map(async (reservation) => {
      const reference = flightReference(reservation);
      if (!reference) return;
      const key = `${reference.number}:${reference.date}`;
      const row = await readCache(env, key);
      const fresh = row ? Date.parse(row.expires_at) > now : false;
      const departure = Date.parse(`${reference.date}T00:00:00Z`);
      const soon =
        Number.isFinite(departure) &&
        departure - now < 72 * 3600 * 1000 &&
        departure - now > -24 * 3600 * 1000;
      const allowRefresh = !fresh && soon && refreshesLeft > 0;
      if (allowRefresh) refreshesLeft -= 1;

      try {
        flights[reservation.id] = await fetchFlightStatus(env, reference.number, reference.date, {
          allowRefresh,
        });
      } catch (error) {
        // A single bad flight should not fail the whole trip view.
        const cached = row ? parseCached(row) : null;
        flights[reservation.id] = {
          flight: cached,
          cached: Boolean(row),
          stale: Boolean(row),
          fetched_at: row?.fetched_at ?? null,
          attribution: FLIGHT_ATTRIBUTION,
          budget_exhausted: error instanceof ApiError && error.code === "flight_rate_limited",
        };
      }
    }),
  );

  return { flights, refreshed: MAX_REFRESHES_PER_REQUEST - refreshesLeft };
}
