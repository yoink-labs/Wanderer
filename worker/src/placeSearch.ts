import { ApiError, json } from "./http";
/** User-triggered search only. Global one-second lease enforces OSM's ceiling. */
export async function searchPlaces(
  db: D1Database,
  query: string,
  endpoint = "https://nominatim.openstreetmap.org/search",
): Promise<Response> {
  const q = query.trim();
  if (q.length < 2 || q.length > 180)
    throw new ApiError(
      400,
      "invalid_query",
      "Enter between 2 and 180 characters.",
    );
  const key = q.toLowerCase();
  const cached = await db
    .prepare(
      "SELECT payload FROM place_search_cache WHERE query = ? AND expires_at > ?",
    )
    .bind(key, Date.now())
    .first<{ payload: string }>();
  if (cached) return json(JSON.parse(cached.payload));
  // One persistent timestamp, acquired atomically; no module-level request state.
  const now = Date.now();
  const acquired = await db
    .prepare(
      "UPDATE place_search_gate SET requested_at=? WHERE id=1 AND requested_at < ? RETURNING requested_at",
    )
    .bind(now, now - 1100)
    .first();
  if (!acquired)
    throw new ApiError(
      429,
      "search_busy",
      "Please wait a moment before searching again.",
    );
  const url = new URL(endpoint);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("q", q);
  url.searchParams.set("limit", "7");
  url.searchParams.set("extratags", "1");
  const response = await fetch(url, {
    headers: {
      "User-Agent":
        "Wanderer/1.0 (https://wanderer.yoinklabs.dev; operations@undrift.dev)",
      Accept: "application/json",
    },
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok)
    throw new ApiError(
      503,
      "search_unavailable",
      "Search is unavailable. You can enter the place by hand.",
    );
  const data = await response.json();
  await db
    .prepare(
      "INSERT INTO place_search_cache(query,payload,expires_at) VALUES (?,?,?) ON CONFLICT(query) DO UPDATE SET payload=excluded.payload,expires_at=excluded.expires_at",
    )
    .bind(key, JSON.stringify(data), now + 7 * 86400000)
    .run();
  return json(data);
}
