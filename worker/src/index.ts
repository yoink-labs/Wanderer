import { AuthError, verifyClerkJwt, type ClerkClaims } from "./auth";

export interface Env {
  DB: D1Database;
  MEDIA: R2Bucket;
  CACHE?: KVNamespace;
  ENVIRONMENT?: string;
  CLERK_ISSUER?: string;
  CLERK_JWKS_URL?: string;
  CLERK_AUTHORIZED_PARTIES?: string;
  MEDIA_SIGNING_SECRET?: string;
  RESEND_API_KEY?: string;
  RESEND_FROM_EMAIL?: string;
  APP_SHARE_BASE_URL?: string;
  /** Test-only escape hatch. Ignored unless ENVIRONMENT is exactly "test". */
  ALLOW_TEST_AUTH?: string;
}

const JSON_LIMIT_BYTES = 1_000_000;
const UPLOAD_LIMIT_BYTES = 10_000_000;
const DEFAULT_PAGE_SIZE = 500;
const MAX_PAGE_SIZE = 1000;

class ApiError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

interface User {
  id: string;
  email: string | null;
}

interface Context {
  env: Env;
  request: Request;
  url: URL;
  user: User;
  params: Record<string, string>;
}

type Handler = (context: Context) => Promise<Response>;

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function errorResponse(error: unknown): Response {
  if (error instanceof ApiError) {
    return json({ error: { code: error.code, message: error.message } }, error.status);
  }
  if (error instanceof AuthError) {
    return json({ error: { code: error.code, message: error.message } }, error.status);
  }
  console.error("unhandled", error);
  return json({ error: { code: "internal_error", message: "Something went wrong." } }, 500);
}

async function readJson<T = Record<string, unknown>>(request: Request, limit = JSON_LIMIT_BYTES): Promise<T> {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(length) && length > limit) {
    throw new ApiError(413, "payload_too_large", "That request is too large.");
  }
  const text = await request.text();
  if (text.length > limit) {
    throw new ApiError(413, "payload_too_large", "That request is too large.");
  }
  if (text.trim().length === 0) {
    throw new ApiError(400, "empty_body", "A JSON body is required.");
  }
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new ApiError(400, "invalid_json", "The request body is not valid JSON.");
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseDateOnly(value: string): Date {
  const [year, month, day] = value.split("-").map(Number);
  return new Date(Date.UTC(year, (month ?? 1) - 1, day ?? 1));
}

function dateOnly(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function assertDateOnly(value: unknown, field: string): string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new ApiError(400, "invalid_date", `"${field}" must be a yyyy-MM-dd date.`);
  }
  const parsed = Date.parse(`${value}T00:00:00Z`);
  if (!Number.isFinite(parsed)) {
    throw new ApiError(400, "invalid_date", `"${field}" is not a real date.`);
  }
  return value;
}

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

async function authenticate(request: Request, env: Env): Promise<User | null> {
  const header = request.headers.get("authorization") ?? "";
  const token = header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : "";
  if (!token) return null;

  // Test-only: never reachable in production because the environment check
  // must be exactly "test" and the flag must be set on that environment.
  if (env.ENVIRONMENT === "test" && env.ALLOW_TEST_AUTH === "true" && token.startsWith("test:")) {
    const sub = token.slice("test:".length);
    if (!sub) throw new AuthError("missing_subject", "The test token has no subject.");
    return resolveProfile(env, { sub });
  }

  const config = {
    jwksUrl: env.CLERK_JWKS_URL ?? "",
    issuer: env.CLERK_ISSUER ?? "",
    authorizedParties: (env.CLERK_AUTHORIZED_PARTIES ?? "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
  };
  if (!config.jwksUrl) {
    throw new ApiError(503, "auth_not_configured", "Sign-in is not configured on this server.");
  }
  const claims = await verifyClerkJwt(token, config);
  return resolveProfile(env, claims);
}

async function resolveProfile(env: Env, claims: ClerkClaims): Promise<User> {
  const existing = await env.DB.prepare("SELECT profile_id, email FROM identities WHERE clerk_sub = ?")
    .bind(claims.sub)
    .first<{ profile_id: string; email: string | null }>();

  if (existing) {
    await env.DB.prepare("UPDATE identities SET last_seen_at = ? WHERE clerk_sub = ?")
      .bind(new Date().toISOString(), claims.sub)
      .run()
      .catch(() => undefined);
    return { id: existing.profile_id, email: existing.email };
  }

  const email = typeof claims.email === "string" ? claims.email : null;
  const profileId = crypto.randomUUID();
  const displayName =
    (typeof claims.name === "string" && claims.name.trim()) ||
    (email ? email.split("@")[0] : "Traveler");

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO profiles (id, email, display_name) VALUES (?, ?, ?)
       ON CONFLICT (id) DO NOTHING`,
    ).bind(profileId, email, displayName),
    env.DB.prepare(
      `INSERT INTO identities (clerk_sub, profile_id, email, last_seen_at) VALUES (?, ?, ?, ?)
       ON CONFLICT (clerk_sub) DO NOTHING`,
    ).bind(claims.sub, profileId, email, new Date().toISOString()),
  ]);

  const created = await env.DB.prepare("SELECT profile_id FROM identities WHERE clerk_sub = ?")
    .bind(claims.sub)
    .first<{ profile_id: string }>();
  if (!created) {
    throw new ApiError(500, "identity_failed", "Could not create the account.");
  }
  return { id: created.profile_id, email };
}

// ---------------------------------------------------------------------------
// Trip authorization
// ---------------------------------------------------------------------------

type TripAccess = { tripId: string; role: "owner" | "editor" | "viewer"; ownerId: string };

async function tripAccess(env: Env, userId: string, tripId: string): Promise<TripAccess | null> {
  const row = await env.DB.prepare(
    `SELECT t.owner_id, m.role
       FROM trips t
       LEFT JOIN trip_members m ON m.trip_id = t.id AND m.user_id = ?
      WHERE t.id = ?`,
  )
    .bind(userId, tripId)
    .first<{ owner_id: string; role: string | null }>();
  if (!row) return null;
  if (row.owner_id === userId) return { tripId, role: "owner", ownerId: row.owner_id };
  if (!row.role) return null;
  return { tripId, role: row.role as TripAccess["role"], ownerId: row.owner_id };
}

async function requireTrip(
  env: Env,
  userId: string,
  tripId: string,
  mode: "read" | "write",
): Promise<TripAccess> {
  const access = await tripAccess(env, userId, tripId);
  if (!access) {
    // Same answer for "missing" and "not yours": nothing leaks.
    throw new ApiError(404, "trip_not_found", "That trip was not found.");
  }
  if (mode === "write" && access.role === "viewer") {
    throw new ApiError(403, "read_only", "You have view-only access to this trip.");
  }
  return access;
}

// ---------------------------------------------------------------------------
// Resource plumbing
// ---------------------------------------------------------------------------

interface ResourceSpec {
  table: string;
  /** Columns a client may write. Everything else is server-owned. */
  writable: string[];
  required?: string[];
  orderBy: string;
  orderDir?: "asc" | "desc";
  /** Column stamped with the authenticated profile id on insert. */
  createdBy?: string;
  transform?: (row: Record<string, unknown>) => Record<string, unknown>;
  /** Coerce a validated client body before binding (booleans, arrays). */
  prepare?: (values: Record<string, unknown>) => void;
  /** Extra work after the row is inserted, inside the same batch when possible. */
  afterCreate?: (
    env: Env,
    ctx: Context,
    row: Record<string, unknown>,
    body: Record<string, unknown>,
  ) => Promise<void>;
}

function pickWritable(
  spec: ResourceSpec,
  body: Record<string, unknown>,
  mode: "create" | "update" = "create",
): Record<string, unknown> {
  const values: Record<string, unknown> = {};
  const unknown: string[] = [];
  for (const [key, value] of Object.entries(body)) {
    if (key === "id" || key === "trip_id") continue;
    if (key === "splits") continue;
    if (!spec.writable.includes(key)) {
      unknown.push(key);
      continue;
    }
    values[key] = value;
  }
  if (unknown.length > 0) {
    throw new ApiError(400, "unknown_fields", `Unknown field(s): ${unknown.join(", ")}`);
  }
  if (mode === "create") {
    for (const field of spec.required ?? []) {
      if (values[field] === undefined || values[field] === null || values[field] === "") {
        throw new ApiError(400, "missing_field", `"${field}" is required.`);
      }
    }
  }
  spec.prepare?.(values);
  return values;
}

async function insertRow(
  env: Env,
  table: string,
  values: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const id = crypto.randomUUID();
  const row: Record<string, unknown> = { id, ...values };
  const keys = Object.keys(row);
  const statement = env.DB.prepare(
    `INSERT INTO ${table} (${keys.join(", ")}) VALUES (${keys.map(() => "?").join(", ")}) RETURNING *`,
  ).bind(...keys.map((key) => row[key] ?? null));
  const result = await statement.first<Record<string, unknown>>();
  if (!result) throw new ApiError(500, "insert_failed", "Could not save that record.");
  return result;
}

function listQuery(spec: ResourceSpec, url: URL): { sql: string; binds: unknown[] } {
  const limit = Math.min(MAX_PAGE_SIZE, Math.max(1, Number(url.searchParams.get("limit") ?? DEFAULT_PAGE_SIZE)));
  const offset = Math.max(0, Number(url.searchParams.get("offset") ?? 0));
  const order = url.searchParams.get("order") ?? spec.orderBy;
  const safeOrder = /^[a-z_]+$/.test(order) ? order : spec.orderBy;
  const dir = (url.searchParams.get("dir") ?? spec.orderDir ?? "asc").toLowerCase() === "desc" ? "DESC" : "ASC";
  return {
    sql: `SELECT * FROM ${spec.table} WHERE trip_id = ? ORDER BY ${safeOrder} ${dir} LIMIT ? OFFSET ?`,
    binds: [limit, offset],
  };
}

function registerTripResource(routes: Route[], name: string, spec: ResourceSpec): void {
  const base = `/v1/trips/:tripId/${name}`;
  routes.push({
    method: "GET",
    pattern: base,
    handler: async ({ env, url, user, params }) => {
      await requireTrip(env, user.id, params.tripId, "read");
      const query = listQuery(spec, url);
      const rows = await env.DB.prepare(query.sql)
        .bind(params.tripId, ...query.binds)
        .all<Record<string, unknown>>();
      return json((rows.results ?? []).map((row) => (spec.transform ? spec.transform(row) : row)));
    },
  });

  routes.push({
    method: "POST",
    pattern: base,
    handler: async (context) => {
      const { env, request, user, params } = context;
      await requireTrip(env, user.id, params.tripId, "write");
      const body = await readJson<Record<string, unknown>>(request);
      const payload = Array.isArray(body) ? body : [body];
      const created: Record<string, unknown>[] = [];
      for (const item of payload) {
        if (!isRecord(item)) throw new ApiError(400, "invalid_body", "Each record must be an object.");
        const values = pickWritable(spec, item);
        values.trip_id = params.tripId;
        if (spec.createdBy) values[spec.createdBy] = user.id;
        const row = await insertRow(env, spec.table, values);
        created.push(spec.transform ? spec.transform(row) : row);
        if (spec.afterCreate) await spec.afterCreate(env, context, row, item);
      }
      return json(Array.isArray(body) ? created : created[0], 201);
    },
  });

  routes.push({
    method: "PATCH",
    pattern: `${base}/:id`,
    handler: async ({ env, request, user, params }) => {
      await requireTrip(env, user.id, params.tripId, "write");
      const body = await readJson<Record<string, unknown>>(request);
      const values = pickWritable(spec, body, "update");
      const keys = Object.keys(values);
      if (keys.length === 0) throw new ApiError(400, "empty_update", "Nothing to update.");
      const row = await env.DB.prepare(
        `UPDATE ${spec.table}
            SET ${keys.map((key) => `${key} = ?`).join(", ")}
          WHERE id = ? AND trip_id = ?
      RETURNING *`,
      )
        .bind(...keys.map((key) => values[key] ?? null), params.id, params.tripId)
        .first<Record<string, unknown>>();
      if (!row) throw new ApiError(404, "not_found", "That record was not found.");
      return json(spec.transform ? spec.transform(row) : row);
    },
  });

  routes.push({
    method: "DELETE",
    pattern: `${base}/:id`,
    handler: async ({ env, user, params }) => {
      await requireTrip(env, user.id, params.tripId, "write");
      const result = await env.DB.prepare(`DELETE FROM ${spec.table} WHERE id = ? AND trip_id = ?`)
        .bind(params.id, params.tripId)
        .run();
      if (!result.meta.changes) throw new ApiError(404, "not_found", "That record was not found.");
      return json({ deleted: true });
    },
  });
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

interface Route {
  method: string;
  pattern: string;
  handler: Handler;
}

const routes: Route[] = [];

function on(method: string, pattern: string, handler: Handler): void {
  routes.push({ method, pattern, handler });
}

/**
 * Swift renders UUIDs in uppercase while D1 stores the lowercase ids we
 * generate, and SQLite compares text case-sensitively. Normalize UUID-shaped
 * path segments so both spellings address the same row.
 */
function normalizeId(value: string): string {
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(value)
    ? value.toLowerCase()
    : value;
}

function matchPattern(pattern: string, pathname: string): Record<string, string> | null {
  const patternParts = pattern.split("/").filter(Boolean);
  const pathParts = pathname.split("/").filter(Boolean);
  if (patternParts.length !== pathParts.length) return null;
  const params: Record<string, string> = {};
  for (let index = 0; index < patternParts.length; index += 1) {
    const expected = patternParts[index];
    const actual = pathParts[index];
    if (expected.startsWith(":")) {
      params[expected.slice(1)] = normalizeId(decodeURIComponent(actual));
    } else if (expected !== actual) {
      return null;
    }
  }
  return params;
}

// --- health ----------------------------------------------------------------

// --- profile ---------------------------------------------------------------

const profileColumns = ["email", "display_name", "avatar_url", "locale", "currency", "units"];

on("GET", "/v1/me", async ({ env, user }) => {
  const row = await env.DB.prepare(
    `SELECT id, email, display_name, avatar_url, locale, currency, units FROM profiles WHERE id = ?`,
  )
    .bind(user.id)
    .first();
  if (!row) throw new ApiError(404, "not_found", "Profile not found.");
  return json(row);
});

on("PATCH", "/v1/me", async ({ env, request, user }) => {
  const body = await readJson<Record<string, unknown>>(request);
  const values: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(body)) {
    if (!profileColumns.includes(key)) {
      throw new ApiError(400, "unknown_fields", `Unknown field: ${key}`);
    }
    values[key] = value;
  }
  const keys = Object.keys(values);
  if (keys.length === 0) throw new ApiError(400, "empty_update", "Nothing to update.");
  const row = await env.DB.prepare(
    `UPDATE profiles SET ${keys.map((key) => `${key} = ?`).join(", ")}, updated_at = ?
      WHERE id = ? RETURNING id, email, display_name, avatar_url, locale, currency, units`,
  )
    .bind(...keys.map((key) => values[key] ?? null), new Date().toISOString(), user.id)
    .first();
  return json(row);
});

on("DELETE", "/v1/me", async ({ env, request, user }) => {
  // A body confirmation keeps an accidental DELETE (or a retried proxy call)
  // from wiping an account.
  const body = await readJson<Record<string, unknown>>(request).catch(() => ({}) as Record<string, unknown>);
  if (body.confirm !== "delete") {
    throw new ApiError(400, "confirmation_required", 'Send {"confirm":"delete"} to delete the account.');
  }

  const trips = await env.DB.prepare("SELECT id FROM trips WHERE owner_id = ?")
    .bind(user.id)
    .all<{ id: string }>();
  for (const trip of trips.results ?? []) {
    // Best effort: media is not transactional with D1.
    const prefix = `trips/${trip.id}/`;
    const objects = await env.MEDIA.list({ prefix }).catch(() => null);
    for (const object of objects?.objects ?? []) {
      await env.MEDIA.delete(object.key).catch(() => undefined);
    }
    const covers = await env.MEDIA.list({ prefix: `public/covers/${trip.id}/` }).catch(() => null);
    for (const object of covers?.objects ?? []) {
      await env.MEDIA.delete(object.key).catch(() => undefined);
    }
  }

  // Cascades remove trips (owner), memberships, content, invites, visited
  // places and the identity row.
  await env.DB.prepare("DELETE FROM profiles WHERE id = ?").bind(user.id).run();
  return json({ deleted: true });
});

on("POST", "/v1/me/avatar", async ({ env, request, user }) => {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.startsWith("image/")) {
    throw new ApiError(415, "unsupported_media", "Upload a JPEG or PNG image.");
  }
  const bytes = await readBytes(request, UPLOAD_LIMIT_BYTES);
  const key = `public/avatars/${user.id}/${crypto.randomUUID()}.jpg`;
  await env.MEDIA.put(key, bytes, { httpMetadata: { contentType } });
  const url = mediaUrl(key, new URL(request.url).origin);
  const row = await env.DB.prepare(
    "UPDATE profiles SET avatar_url = ?, updated_at = ? WHERE id = ? RETURNING id, email, display_name, avatar_url, locale, currency, units",
  )
    .bind(url, new Date().toISOString(), user.id)
    .first();
  return json(row);
});

// --- trips -----------------------------------------------------------------

function tripTransform(row: Record<string, unknown>): Record<string, unknown> {
  return row;
}

on("GET", "/v1/trips", async ({ env, user }) => {
  const rows = await env.DB.prepare(
    `SELECT t.*, (SELECT COUNT(*) FROM places p WHERE p.trip_id = t.id) AS place_count
       FROM trips t
      WHERE t.owner_id = ?
         OR EXISTS (SELECT 1 FROM trip_members m WHERE m.trip_id = t.id AND m.user_id = ?)
      ORDER BY t.created_at DESC`,
  )
    .bind(user.id, user.id)
    .all<Record<string, unknown>>();
  return json((rows.results ?? []).map(tripTransform));
});

const tripWritable = [
  "title",
  "destination",
  "start_date",
  "end_date",
  "currency",
  "cover_color",
  "notes",
  "timezone",
];

on("POST", "/v1/trips", async ({ env, request, user }) => {
  const body = await readJson<Record<string, unknown>>(request);
  const values: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(body)) {
    if (key === "days" || key === "day_count") continue;
    if (!tripWritable.includes(key)) {
      throw new ApiError(400, "unknown_fields", `Unknown field: ${key}`);
    }
    values[key] = value;
  }
  if (typeof values.title !== "string" || values.title.trim().length === 0) {
    throw new ApiError(400, "missing_field", "A trip title is required.");
  }
  if (values.start_date !== undefined && values.start_date !== null) {
    values.start_date = assertDateOnly(values.start_date, "start_date");
  }
  if (values.end_date !== undefined && values.end_date !== null) {
    values.end_date = assertDateOnly(values.end_date, "end_date");
  }
  if (
    typeof values.start_date === "string" &&
    typeof values.end_date === "string" &&
    values.end_date < values.start_date
  ) {
    throw new ApiError(400, "invalid_range", "The end date cannot be before the start date.");
  }
  if (values.currency === undefined) values.currency = "USD";
  if (values.timezone === undefined) values.timezone = "UTC";

  const trip = await insertRow(env, "trips", { owner_id: user.id, share_token: crypto.randomUUID(), ...values });
  await env.DB.prepare("INSERT INTO trip_members (trip_id, user_id, role) VALUES (?, ?, 'owner')")
    .bind(trip.id, user.id)
    .run();

  const dayCount = numberOfDays(body, values);
  if (dayCount > 0) await createDays(env, String(trip.id), String(values.start_date), dayCount);

  return json(trip, 201);
});

function numberOfDays(body: Record<string, unknown>, values: Record<string, unknown>): number {
  const explicit = Number(body.days ?? body.day_count ?? 0);
  if (Number.isFinite(explicit) && explicit > 0) return Math.min(366, Math.floor(explicit));
  const start = values.start_date;
  const end = values.end_date;
  if (typeof start === "string" && typeof end === "string") {
    const days = Math.round((parseDateOnly(end).getTime() - parseDateOnly(start).getTime()) / 86_400_000) + 1;
    return Math.min(366, Math.max(0, days));
  }
  return 0;
}

async function createDays(env: Env, tripId: string, start: string, count: number): Promise<void> {
  const statements = [];
  for (let index = 0; index < count; index += 1) {
    const date = dateOnly(new Date(parseDateOnly(start).getTime() + index * 86_400_000));
    statements.push(
      env.DB.prepare(
        "INSERT INTO trip_days (id, trip_id, day_index, date) VALUES (?, ?, ?, ?) ON CONFLICT (trip_id, day_index) DO UPDATE SET date = excluded.date",
      ).bind(crypto.randomUUID(), tripId, index, date),
    );
  }
  if (statements.length > 0) await env.DB.batch(statements);
}

on("GET", "/v1/trips/:tripId", async ({ env, user, params }) => {
  await requireTrip(env, user.id, params.tripId, "read");
  const row = await env.DB.prepare(
    `SELECT t.*, (SELECT COUNT(*) FROM places p WHERE p.trip_id = t.id) AS place_count
       FROM trips t WHERE t.id = ?`,
  )
    .bind(params.tripId)
    .first();
  if (!row) throw new ApiError(404, "not_found", "That trip was not found.");
  return json(row);
});

on("PATCH", "/v1/trips/:tripId", async ({ env, request, user, params }) => {
  const access = await requireTrip(env, user.id, params.tripId, "write");
  const body = await readJson<Record<string, unknown>>(request);
  const values: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(body)) {
    if (!tripWritable.includes(key)) {
      throw new ApiError(400, "unknown_fields", `Unknown field: ${key}`);
    }
    values[key] = value;
  }
  if (values.start_date !== undefined && values.start_date !== null) {
    values.start_date = assertDateOnly(values.start_date, "start_date");
  }
  if (values.end_date !== undefined && values.end_date !== null) {
    values.end_date = assertDateOnly(values.end_date, "end_date");
  }
  const keys = Object.keys(values);
  if (keys.length === 0) throw new ApiError(400, "empty_update", "Nothing to update.");

  const row = await env.DB.prepare(
    `UPDATE trips SET ${keys.map((key) => `${key} = ?`).join(", ")}, updated_at = ?
      WHERE id = ? RETURNING *`,
  )
    .bind(...keys.map((key) => values[key] ?? null), new Date().toISOString(), access.tripId)
    .first<Record<string, unknown>>();
  if (!row) throw new ApiError(404, "not_found", "That trip was not found.");

  if (typeof values.start_date === "string" && typeof values.end_date === "string") {
    const count = numberOfDays({}, values);
    await syncDays(env, access.tripId, values.start_date, count);
  }
  return json(row);
});

async function syncDays(env: Env, tripId: string, start: string, count: number): Promise<void> {
  await createDays(env, tripId, start, count);
  await env.DB.prepare("DELETE FROM trip_days WHERE trip_id = ? AND day_index >= ?")
    .bind(tripId, count)
    .run();
}

on("DELETE", "/v1/trips/:tripId", async ({ env, user, params }) => {
  const access = await requireTrip(env, user.id, params.tripId, "write");
  if (access.role !== "owner") {
    throw new ApiError(403, "owner_only", "Only the trip owner can delete it.");
  }
  await env.DB.prepare("DELETE FROM trips WHERE id = ? AND owner_id = ?")
    .bind(params.tripId, user.id)
    .run();
  return json({ deleted: true });
});

on("POST", "/v1/trips/:tripId/cover", async ({ env, request, user, params }) => {
  await requireTrip(env, user.id, params.tripId, "write");
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.startsWith("image/")) {
    throw new ApiError(415, "unsupported_media", "Upload a JPEG or PNG image.");
  }
  const bytes = await readBytes(request, UPLOAD_LIMIT_BYTES);
  const key = `public/covers/${params.tripId}/${crypto.randomUUID()}.jpg`;
  await env.MEDIA.put(key, bytes, { httpMetadata: { contentType } });
  const row = await env.DB.prepare("UPDATE trips SET cover_url = ?, updated_at = ? WHERE id = ? RETURNING *")
    .bind(mediaUrl(key, new URL(request.url).origin), new Date().toISOString(), params.tripId)
    .first();
  return json(row);
});

// --- days / places / bookings / money / checklist ---------------------------

registerTripResource(routes, "days", {
  table: "trip_days",
  writable: ["day_index", "date", "title", "notes"],
  required: ["day_index"],
  orderBy: "day_index",
});

registerTripResource(routes, "places", {
  table: "places",
  writable: [
    "day_id",
    "name",
    "address",
    "lat",
    "lng",
    "category",
    "notes",
    "website",
    "phone",
    "price_level",
    "rating",
    "photo_url",
    "start_time",
    "end_time",
    "position",
  ],
  required: ["name"],
  orderBy: "position",
  createdBy: "created_by",
});

registerTripResource(routes, "reservations", {
  table: "reservations",
  writable: [
    "type",
    "title",
    "provider",
    "confirmation_code",
    "start_at",
    "end_at",
    "start_location",
    "end_location",
    "cost",
    "currency",
    "notes",
    "metadata",
  ],
  required: ["title"],
  orderBy: "start_at",
  createdBy: "created_by",
});

registerTripResource(routes, "checklist", {
  table: "checklist_items",
  writable: ["title", "is_checked", "position"],
  required: ["title"],
  orderBy: "position",
  createdBy: "created_by",
  prepare: (values) => {
    if (typeof values.is_checked === "boolean") values.is_checked = values.is_checked ? 1 : 0;
  },
  transform: (row) => ({ ...row, is_checked: row.is_checked === 1 || row.is_checked === true }),
});

registerTripResource(routes, "settlements", {
  table: "settlements",
  writable: ["from_user", "to_user", "amount", "currency", "settled_at", "note"],
  required: ["from_user", "to_user", "amount"],
  orderBy: "settled_at",
  orderDir: "desc",
  createdBy: "created_by",
});

// Expenses need their splits written in one request.
registerTripResource(routes, "expenses", {
  table: "expenses",
  writable: [
    "title",
    "amount",
    "currency",
    "category",
    "paid_by",
    "split_with",
    "split_mode",
    "spent_at",
    "notes",
  ],
  required: ["title", "amount"],
  orderBy: "spent_at",
  orderDir: "desc",
  createdBy: "created_by",
  prepare: (values) => {
    if (Array.isArray(values.split_with)) values.split_with = JSON.stringify(values.split_with);
    if (values.amount !== undefined) {
      const amount = Number(values.amount);
      if (!Number.isFinite(amount) || amount < 0) {
        throw new ApiError(400, "invalid_amount", "The amount must be zero or more.");
      }
      values.amount = amount;
    }
    if (values.split_mode !== undefined && !["equal", "exact", "percent", "shares"].includes(String(values.split_mode))) {
      throw new ApiError(400, "invalid_split_mode", "Unknown split mode.");
    }
  },
  transform: (row) => {
    let splitWith: unknown = row.split_with;
    if (typeof splitWith === "string") {
      try {
        splitWith = JSON.parse(splitWith);
      } catch {
        splitWith = [];
      }
    }
    return { ...row, split_with: Array.isArray(splitWith) ? splitWith : [] };
  },
  afterCreate: async (env, _ctx, row, body) => {
    const splits = Array.isArray(body.splits) ? body.splits : [];
    const statements = [];
    for (const split of splits) {
      if (!isRecord(split) || typeof split.user_id !== "string") continue;
      statements.push(
        env.DB.prepare(
          "INSERT INTO expense_splits (id, trip_id, expense_id, user_id, amount, weight) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT (expense_id, user_id) DO UPDATE SET amount = excluded.amount, weight = excluded.weight",
        ).bind(
          crypto.randomUUID(),
          row.trip_id,
          row.id,
          split.user_id,
          Number(split.amount ?? 0),
          split.weight === undefined || split.weight === null ? null : Number(split.weight),
        ),
      );
    }
    if (statements.length > 0) await env.DB.batch(statements);
  },
});

on("GET", "/v1/trips/:tripId/expense-splits", async ({ env, user, params }) => {
  await requireTrip(env, user.id, params.tripId, "read");
  const rows = await env.DB.prepare("SELECT * FROM expense_splits WHERE trip_id = ?")
    .bind(params.tripId)
    .all();
  return json(rows.results ?? []);
});

// --- members ---------------------------------------------------------------

on("GET", "/v1/trips/:tripId/members", async ({ env, user, params }) => {
  await requireTrip(env, user.id, params.tripId, "read");
  const rows = await env.DB.prepare(
    `SELECT m.trip_id, m.user_id, m.role, m.joined_at,
            p.id AS profile_id, p.display_name, p.email
       FROM trip_members m
       JOIN profiles p ON p.id = m.user_id
      WHERE m.trip_id = ?
      ORDER BY m.joined_at ASC`,
  )
    .bind(params.tripId)
    .all<Record<string, unknown>>();
  return json(
    (rows.results ?? []).map((row) => ({
      trip_id: row.trip_id,
      user_id: row.user_id,
      role: row.role,
      joined_at: row.joined_at,
      profiles: {
        id: row.profile_id,
        display_name: row.display_name,
        email: row.email,
      },
    })),
  );
});

// --- invites ---------------------------------------------------------------

on("GET", "/v1/trips/:tripId/invites", async ({ env, user, params }) => {
  await requireTrip(env, user.id, params.tripId, "read");
  const rows = await env.DB.prepare(
    "SELECT id, trip_id, email, role, expires_at, accepted_at, created_at FROM trip_invites WHERE trip_id = ? ORDER BY created_at DESC",
  )
    .bind(params.tripId)
    .all();
  return json(rows.results ?? []);
});

on("POST", "/v1/trips/:tripId/invites", async ({ env, request, user, params }) => {
  await requireTrip(env, user.id, params.tripId, "write");
  const body = await readJson<Record<string, unknown>>(request);
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw new ApiError(400, "invalid_email", "Enter a valid email address.");
  }
  const role = body.role === "viewer" ? "viewer" : "editor";

  await enforceRateLimit(env, `invite:${user.id}`, 10, 60);

  const trip = await env.DB.prepare("SELECT title FROM trips WHERE id = ?")
    .bind(params.tripId)
    .first<{ title: string }>();
  const inviteId = crypto.randomUUID();
  const token = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + 7 * 86_400_000).toISOString();
  const row = await env.DB.prepare(
    `INSERT INTO trip_invites (id, trip_id, email, role, token, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT (trip_id, email) DO UPDATE SET role = excluded.role, token = excluded.token, expires_at = excluded.expires_at, accepted_at = NULL
     RETURNING id, trip_id, email, role, token, expires_at, accepted_at`,
  )
    .bind(inviteId, params.tripId, email, role, token, expiresAt)
    .first<Record<string, unknown>>();

  const link = `${env.APP_SHARE_BASE_URL ?? "https://wanderer.app"}/invite/${token}`;
  const delivered = await sendInviteEmail(env, {
    to: email,
    tripTitle: trip?.title ?? "a trip",
    link,
    inviterEmail: user.email,
  });

  return json({ ...row, email_delivered: delivered }, 201);
});

on("DELETE", "/v1/trips/:tripId/invites/:id", async ({ env, user, params }) => {
  await requireTrip(env, user.id, params.tripId, "write");
  await env.DB.prepare("DELETE FROM trip_invites WHERE id = ? AND trip_id = ?")
    .bind(params.id, params.tripId)
    .run();
  return json({ deleted: true });
});

on("POST", "/v1/invites/:token/accept", async ({ env, user, params }) => {
  const invite = await env.DB.prepare(
    "SELECT id, trip_id, email, role, expires_at, accepted_at FROM trip_invites WHERE token = ?",
  )
    .bind(params.token)
    .first<{ id: string; trip_id: string; email: string; role: string; expires_at: string | null; accepted_at: string | null }>();
  if (!invite) throw new ApiError(404, "invite_not_found", "That invite is not valid.");
  if (invite.accepted_at) throw new ApiError(409, "invite_used", "That invite was already used.");
  if (invite.expires_at && Date.parse(invite.expires_at) < Date.now()) {
    throw new ApiError(410, "invite_expired", "That invite has expired.");
  }
  const profile = await env.DB.prepare("SELECT email FROM profiles WHERE id = ?")
    .bind(user.id)
    .first<{ email: string | null }>();
  const email = (profile?.email ?? user.email ?? "").toLowerCase();
  if (!email) {
    throw new ApiError(409, "email_required", "Add an email to your profile before accepting an invite.");
  }
  if (email !== invite.email.toLowerCase()) {
    throw new ApiError(403, "invite_email_mismatch", "This invite was sent to a different email address.");
  }
  await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO trip_members (trip_id, user_id, role) VALUES (?, ?, ?) ON CONFLICT (trip_id, user_id) DO UPDATE SET role = excluded.role",
    ).bind(invite.trip_id, user.id, invite.role),
    env.DB.prepare("UPDATE trip_invites SET accepted_at = ? WHERE id = ?").bind(new Date().toISOString(), invite.id),
  ]);
  return json({ trip_id: invite.trip_id, role: invite.role });
});

// --- attachments -----------------------------------------------------------

on("GET", "/v1/trips/:tripId/attachments", async ({ env, user, params }) => {
  await requireTrip(env, user.id, params.tripId, "read");
  const rows = await env.DB.prepare(
    "SELECT id, trip_id, reservation_id, place_id, name, storage_path, mime_type, size_bytes, created_at FROM attachments WHERE trip_id = ? ORDER BY created_at DESC",
  )
    .bind(params.tripId)
    .all();
  return json(rows.results ?? []);
});

on("POST", "/v1/trips/:tripId/attachments", async ({ env, request, user, params }) => {
  await requireTrip(env, user.id, params.tripId, "write");
  const fileName = (request.headers.get("x-file-name") ?? "").trim();
  if (!fileName) throw new ApiError(400, "missing_file_name", "A file name is required.");
  const contentType = request.headers.get("content-type") ?? "application/octet-stream";
  await enforceRateLimit(env, `upload:${user.id}`, 30, 60);
  const bytes = await readBytes(request, UPLOAD_LIMIT_BYTES);
  const safeName = fileName.replace(/[\\/]/g, "-").slice(0, 180);
  const key = `trips/${params.tripId}/${crypto.randomUUID()}-${safeName}`;
  await env.MEDIA.put(key, bytes, { httpMetadata: { contentType } });
  const row = await insertRow(env, "attachments", {
    trip_id: params.tripId,
    name: fileName,
    storage_path: key,
    mime_type: contentType,
    size_bytes: bytes.byteLength,
    created_by: user.id,
  });
  return json(row, 201);
});

on("GET", "/v1/trips/:tripId/attachments/:id/url", async ({ env, request, user, params }) => {
  await requireTrip(env, user.id, params.tripId, "read");
  const row = await env.DB.prepare("SELECT storage_path FROM attachments WHERE id = ? AND trip_id = ?")
    .bind(params.id, params.tripId)
    .first<{ storage_path: string }>();
  if (!row) throw new ApiError(404, "not_found", "That file was not found.");
  const expires = Math.floor(Date.now() / 1000) + 3600;
  const signature = await signMedia(env, row.storage_path, expires);
  return json({ url: `${mediaUrl(row.storage_path, new URL(request.url).origin)}?exp=${expires}&sig=${signature}` });
});

on("DELETE", "/v1/trips/:tripId/attachments/:id", async ({ env, user, params }) => {
  await requireTrip(env, user.id, params.tripId, "write");
  const row = await env.DB.prepare("SELECT storage_path FROM attachments WHERE id = ? AND trip_id = ?")
    .bind(params.id, params.tripId)
    .first<{ storage_path: string }>();
  if (!row) throw new ApiError(404, "not_found", "That file was not found.");
  await env.MEDIA.delete(row.storage_path).catch(() => undefined);
  await env.DB.prepare("DELETE FROM attachments WHERE id = ? AND trip_id = ?").bind(params.id, params.tripId).run();
  return json({ deleted: true });
});

// --- guides (public) -------------------------------------------------------

on("GET", "/v1/guides", async ({ env, url }) => {
  const search = (url.searchParams.get("q") ?? "").trim();
  const like = `%${search.replace(/[%_]/g, "")}%`;
  const rows = search
    ? await env.DB.prepare(
        `SELECT * FROM guides WHERE is_published = 1 AND (title LIKE ? OR summary LIKE ? OR destination LIKE ?) ORDER BY title ASC`,
      )
        .bind(like, like, like)
        .all()
    : await env.DB.prepare("SELECT * FROM guides WHERE is_published = 1 ORDER BY title ASC").all();
  return json((rows.results ?? []).map((row) => ({ ...row, is_published: row.is_published === 1 })));
});

on("GET", "/v1/guides/:guideId", async ({ env, params }) => {
  const row = await env.DB.prepare("SELECT * FROM guides WHERE id = ? AND is_published = 1")
    .bind(params.guideId)
    .first<Record<string, unknown>>();
  if (!row) throw new ApiError(404, "not_found", "That guide was not found.");
  return json({ ...row, is_published: true });
});

on("GET", "/v1/guides/:guideId/places", async ({ env, params }) => {
  const guide = await env.DB.prepare("SELECT id FROM guides WHERE id = ? AND is_published = 1")
    .bind(params.guideId)
    .first();
  if (!guide) throw new ApiError(404, "not_found", "That guide was not found.");
  const rows = await env.DB.prepare("SELECT * FROM guide_places WHERE guide_id = ? ORDER BY position ASC")
    .bind(params.guideId)
    .all();
  return json(rows.results ?? []);
});

// --- visited places --------------------------------------------------------

on("GET", "/v1/visited", async ({ env, user }) => {
  const rows = await env.DB.prepare(
    "SELECT * FROM visited_places WHERE user_id = ? ORDER BY country_code ASC",
  )
    .bind(user.id)
    .all();
  return json(rows.results ?? []);
});

on("POST", "/v1/visited", async ({ env, request, user }) => {
  const body = await readJson<Record<string, unknown>>(request);
  const countryCode = typeof body.country_code === "string" ? body.country_code.trim().toUpperCase() : "";
  if (!/^[A-Z]{2}$/.test(countryCode)) {
    throw new ApiError(400, "invalid_country", "Use a two-letter country code.");
  }
  const city = typeof body.city === "string" && body.city.trim() ? body.city.trim() : null;
  const year = Number.isFinite(Number(body.year)) && body.year !== null ? Number(body.year) : null;
  const existing = await env.DB.prepare(
    "SELECT id FROM visited_places WHERE user_id = ? AND country_code = ? AND COALESCE(city, '') = COALESCE(?, '') AND COALESCE(year, -1) = COALESCE(?, -1)",
  )
    .bind(user.id, countryCode, city, year)
    .first();
  if (existing) {
    const row = await env.DB.prepare("SELECT * FROM visited_places WHERE id = ?").bind(existing.id ?? "").first();
    return json(row);
  }
  const row = await insertRow(env, "visited_places", {
    user_id: user.id,
    country_code: countryCode,
    city,
    year,
  });
  return json(row, 201);
});

on("DELETE", "/v1/visited/:id", async ({ env, user, params }) => {
  const result = await env.DB.prepare("DELETE FROM visited_places WHERE id = ? AND user_id = ?")
    .bind(params.id, user.id)
    .run();
  if (!result.meta.changes) throw new ApiError(404, "not_found", "That place was not found.");
  return json({ deleted: true });
});

// --- media -----------------------------------------------------------------

function mediaUrl(key: string, origin: string): string {
  return `${origin}/media/${key.split("/").map(encodeURIComponent).join("/")}`;
}

async function signMedia(env: Env, key: string, expires: number): Promise<string> {
  const secret = env.MEDIA_SIGNING_SECRET ?? "";
  if (!secret) {
    throw new ApiError(503, "media_not_configured", "File downloads are not configured.");
  }
  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    keyMaterial,
    new TextEncoder().encode(`${key}:${expires}`),
  );
  return [...new Uint8Array(signature)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function verifyMediaSignature(env: Env, key: string, expires: number, signature: string): Promise<boolean> {
  const expected = await signMedia(env, key, expires);
  if (expected.length !== signature.length) return false;
  let different = 0;
  for (let index = 0; index < expected.length; index += 1) {
    different |= expected.charCodeAt(index) ^ signature.charCodeAt(index);
  }
  return different === 0;
}

async function serveMedia(env: Env, url: URL): Promise<Response> {
  const key = decodeURIComponent(url.pathname.replace(/^\/media\//, ""));
  if (!key || key.includes("..")) throw new ApiError(404, "not_found", "Not found.");

  if (!key.startsWith("public/")) {
    const expires = Number(url.searchParams.get("exp") ?? "0");
    const signature = url.searchParams.get("sig") ?? "";
    if (!Number.isFinite(expires) || expires * 1000 < Date.now()) {
      throw new ApiError(403, "link_expired", "That link has expired.");
    }
    const valid = await verifyMediaSignature(env, key, expires, signature);
    if (!valid) throw new ApiError(403, "bad_signature", "That link is not valid.");
  }

  const object = await env.MEDIA.get(key);
  if (!object) throw new ApiError(404, "not_found", "Not found.");
  return new Response(object.body, {
    headers: {
      "content-type": object.httpMetadata?.contentType ?? "application/octet-stream",
      "cache-control": key.startsWith("public/") ? "public, max-age=31536000, immutable" : "private, max-age=3600",
      "x-content-type-options": "nosniff",
    },
  });
}

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

async function readBytes(request: Request, limit: number): Promise<Uint8Array> {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(length) && length > limit) {
    throw new ApiError(413, "payload_too_large", "That file is too large.");
  }
  const buffer = await request.arrayBuffer();
  if (buffer.byteLength > limit) {
    throw new ApiError(413, "payload_too_large", "That file is too large.");
  }
  if (buffer.byteLength === 0) {
    throw new ApiError(400, "empty_file", "The file is empty.");
  }
  return new Uint8Array(buffer);
}

async function enforceRateLimit(env: Env, bucket: string, max: number, windowSeconds: number): Promise<void> {
  const windowStart = Math.floor(Date.now() / 1000 / windowSeconds);
  await env.DB.prepare(
    "INSERT INTO rate_limits (bucket, window_start, count) VALUES (?, ?, 1) ON CONFLICT (bucket, window_start) DO UPDATE SET count = count + 1",
  )
    .bind(bucket, windowStart)
    .run();
  if (Math.random() < 0.02) {
    await env.DB.prepare("DELETE FROM rate_limits WHERE window_start < ?")
      .bind(windowStart - 10)
      .run()
      .catch(() => undefined);
  }
  const row = await env.DB.prepare("SELECT count FROM rate_limits WHERE bucket = ? AND window_start = ?")
    .bind(bucket, windowStart)
    .first<{ count: number }>();
  if ((row?.count ?? 0) > max) {
    throw new ApiError(429, "rate_limited", "Too many requests. Try again shortly.");
  }
}

async function sendInviteEmail(
  env: Env,
  params: { to: string; tripTitle: string; link: string; inviterEmail: string | null },
): Promise<boolean> {
  if (!env.RESEND_API_KEY || !env.RESEND_FROM_EMAIL) return false;
  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        authorization: `Bearer ${env.RESEND_API_KEY}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        from: env.RESEND_FROM_EMAIL,
        to: [params.to],
        subject: `You're invited to ${params.tripTitle} on Wanderer`,
        text: [
          `${params.inviterEmail ?? "Someone"} invited you to plan ${params.tripTitle} on Wanderer.`,
          "",
          params.link,
          "",
          "If you weren't expecting this, you can ignore this email.",
        ].join("\n"),
      }),
    });
    return response.ok;
  } catch {
    // The invite row is still saved; the app falls back to the Mail sheet.
    return false;
  }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    try {
      if (request.method === "GET" && url.pathname === "/health") {
        const row = await env.DB.prepare("SELECT 1 AS ok").first<{ ok: number }>();
        return json({ ok: row?.ok === 1, service: "wanderer-api" });
      }

      if (request.method === "GET" && url.pathname.startsWith("/media/")) {
        return await serveMedia(env, url);
      }

      let matched: { route: Route; params: Record<string, string> } | null = null;
      for (const route of routes) {
        if (route.method !== request.method) continue;
        const params = matchPattern(route.pattern, url.pathname);
        if (params) {
          matched = { route, params };
          break;
        }
      }
      if (!matched) {
        return json({ error: { code: "not_found", message: "No such route." } }, 404);
      }

      // Public routes: guides and media only.
      const publicRoute =
        url.pathname.startsWith("/v1/guides") || url.pathname.startsWith("/media/");
      let user: User = { id: "", email: null };
      if (!publicRoute) {
        const authenticated = await authenticate(request, env);
        if (!authenticated) {
          throw new ApiError(401, "not_authenticated", "Sign in to continue.");
        }
        user = authenticated;
      }

      const context: Context = { env, request, url, user, params: matched.params };
      const idempotencyKey = request.headers.get("idempotency-key");
      if (request.method === "POST" && idempotencyKey) {
        const replay = await replayIdempotent(env, user.id, idempotencyKey, request.method, url.pathname);
        if (replay) return replay;
        const response = await matched.route.handler(context);
        await storeIdempotent(env, user.id, idempotencyKey, request.method, url.pathname, response.clone());
        return response;
      }

      return await matched.route.handler(context);
    } catch (error) {
      return errorResponse(error);
    }
  },
} satisfies ExportedHandler<Env>;

async function replayIdempotent(
  env: Env,
  userId: string,
  key: string,
  method: string,
  path: string,
): Promise<Response | null> {
  const row = await env.DB.prepare(
    "SELECT status, body FROM idempotency_keys WHERE user_id = ? AND key = ? AND method = ? AND path = ?",
  )
    .bind(userId, key, method, path)
    .first<{ status: number; body: string }>();
  if (!row) return null;
  return new Response(row.body, {
    status: row.status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "idempotent-replay": "true" },
  });
}

async function storeIdempotent(
  env: Env,
  userId: string,
  key: string,
  method: string,
  path: string,
  response: Response,
): Promise<void> {
  if (response.status >= 500) return;
  if (key.length > 200) return;
  const body = await response.text();
  if (Math.random() < 0.02) {
    const cutoff = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
    await env.DB.prepare("DELETE FROM idempotency_keys WHERE created_at < ?")
      .bind(cutoff)
      .run()
      .catch(() => undefined);
  }
  await env.DB.prepare(
    "INSERT INTO idempotency_keys (user_id, key, method, path, status, body) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT (user_id, key) DO NOTHING",
  )
    .bind(userId, key, method, path, response.status, body)
    .run()
    .catch(() => undefined);
}

export { ApiError, tripAccess, authenticate };
