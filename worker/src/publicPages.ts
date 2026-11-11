/**
 * Public, read-only pages that a shared link or an invite email opens.
 *
 * They are plain HTML from the Worker (no app, no JavaScript), marked
 * noindex, and show only what the owner chose to share by sending the link:
 * the trip's title, destination, dates and each day's stops. They never
 * include people (names, emails), notes, costs, bookings or files.
 */

export interface PublicEnv {
  DB: D1Database;
}

type TripRow = {
  id: string;
  title: string;
  destination: string | null;
  start_date: string | null;
  end_date: string | null;
};

type DayRow = { id: string; day_index: number; date: string | null; title: string | null };
type PlaceRow = {
  day_id: string | null;
  name: string;
  address: string | null;
  category: string | null;
  position: number;
};

const TOKEN = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function formatDay(date: string | null, index: number): string {
  if (!date) return `Day ${index + 1}`;
  const parsed = new Date(`${date}T12:00:00Z`);
  if (Number.isNaN(parsed.getTime())) return `Day ${index + 1}`;
  const label = parsed.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", timeZone: "UTC" });
  return `Day ${index + 1}, ${label}`;
}

function formatRange(start: string | null, end: string | null): string {
  if (!start) return "";
  const options: Intl.DateTimeFormatOptions = { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" };
  const a = new Date(`${start}T12:00:00Z`).toLocaleDateString("en-US", options);
  if (!end || end === start) return a;
  const b = new Date(`${end}T12:00:00Z`).toLocaleDateString("en-US", options);
  return `${a} – ${b}`;
}

function page(title: string, body: string, status = 200): Response {
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>${escapeHtml(title)}</title>
<style>
:root { color-scheme: light dark; --paper:#EEF2F3; --card:#fff; --ink:#10283A; --muted:#56697A; --route:#F2A922; --line:#D3DBD8; }
@media (prefers-color-scheme: dark) { :root { --paper:#0B151C; --card:#13212A; --ink:#E8EEF1; --muted:#93A6B3; --route:#FFC14D; --line:#22323C; } }
* { box-sizing: border-box; }
body { margin:0; background:var(--paper); color:var(--ink); font:17px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
main { max-width: 640px; margin: 0 auto; padding: 32px 20px 64px; }
h1 { font-size: 34px; line-height: 1.1; margin: 0 0 6px; font-weight: 900; font-stretch: expanded; letter-spacing: -0.01em; }
.meta { color: var(--muted); margin: 0 0 28px; }
.day { background: var(--card); border: 1px solid var(--line); border-radius: 18px; padding: 18px 18px 6px; margin-bottom: 14px; }
.day h2 { font-size: 17px; margin: 0 0 12px; }
ol { list-style: none; margin: 0; padding: 0; }
li { position: relative; padding: 0 0 14px 40px; }
li::before { content: counter(stop); counter-increment: stop; position: absolute; left: 0; top: 0; width: 26px; height: 26px; border-radius: 50%; background: var(--route); color: #10283A; font-weight: 800; font-size: 14px; display: grid; place-items: center; }
li:not(:last-child)::after { content: ""; position: absolute; left: 11.5px; top: 26px; bottom: 0; width: 3px; background: var(--route); }
ol { counter-reset: stop; }
.name { font-weight: 600; }
.sub { color: var(--muted); font-size: 15px; }
.empty { color: var(--muted); padding-bottom: 12px; }
.foot { color: var(--muted); font-size: 14px; margin-top: 28px; }
</style>
</head>
<body><main>${body}</main></body>
</html>`;
  return new Response(html, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "private, max-age=60",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer",
      "x-robots-tag": "noindex, nofollow",
    },
  });
}

function notFound(): Response {
  return page(
    "Link not available",
    `<h1>This link isn't available</h1><p class="meta">The trip owner may have turned off link sharing. Ask them for a new link.</p>`,
    404,
  );
}

export async function serveSharedTrip(env: PublicEnv, token: string): Promise<Response> {
  if (!TOKEN.test(token)) return notFound();
  const trip = await env.DB.prepare(
    "SELECT id, title, destination, start_date, end_date FROM trips WHERE share_token = ?",
  )
    .bind(token.toLowerCase())
    .first<TripRow>();
  if (!trip) return notFound();

  const days = (
    await env.DB.prepare("SELECT id, day_index, date, title FROM trip_days WHERE trip_id = ? ORDER BY day_index")
      .bind(trip.id)
      .all<DayRow>()
  ).results ?? [];
  const places = (
    await env.DB.prepare(
      "SELECT day_id, name, address, category, position FROM places WHERE trip_id = ? AND day_id IS NOT NULL ORDER BY position",
    )
      .bind(trip.id)
      .all<PlaceRow>()
  ).results ?? [];

  const dayBlocks = days
    .map((day) => {
      const stops = places.filter((place) => place.day_id === day.id);
      const list = stops.length
        ? `<ol>${stops
            .map((stop) => {
              const sub = [stop.category ? stop.category[0].toUpperCase() + stop.category.slice(1) : null, stop.address]
                .filter(Boolean)
                .join(", ");
              return `<li><div class="name">${escapeHtml(stop.name)}</div>${sub ? `<div class="sub">${escapeHtml(sub)}</div>` : ""}</li>`;
            })
            .join("")}</ol>`
        : `<p class="empty">Nothing planned yet.</p>`;
      const heading = day.title ? `${formatDay(day.date, day.day_index)}: ${day.title}` : formatDay(day.date, day.day_index);
      return `<section class="day"><h2>${escapeHtml(heading)}</h2>${list}</section>`;
    })
    .join("");

  const meta = [trip.destination, formatRange(trip.start_date, trip.end_date)].filter(Boolean).join(" · ");
  return page(
    `${trip.title} – Wanderer`,
    `<h1>${escapeHtml(trip.title)}</h1>${meta ? `<p class="meta">${escapeHtml(meta)}</p>` : ""}${dayBlocks}
<p class="foot">A read-only itinerary shared from Wanderer by Yoink Labs.</p>`,
  );
}

export async function serveInvitePage(env: PublicEnv, token: string): Promise<Response> {
  if (!TOKEN.test(token)) return notFound();
  const invite = await env.DB.prepare(
    `SELECT trips.title AS title, trip_invites.expires_at AS expires_at, trip_invites.accepted_at AS accepted_at
     FROM trip_invites JOIN trips ON trips.id = trip_invites.trip_id WHERE trip_invites.token = ?`,
  )
    .bind(token.toLowerCase())
    .first<{ title: string; expires_at: string | null; accepted_at: string | null }>();
  if (!invite) return notFound();
  const expired = invite.expires_at !== null && Date.parse(invite.expires_at) < Date.now();
  if (expired) {
    return page(
      "Invite expired",
      `<h1>This invite has expired</h1><p class="meta">Ask the trip owner to send a new one.</p>`,
      410,
    );
  }
  return page(
    `Join ${invite.title} – Wanderer`,
    `<h1>You're invited to ${escapeHtml(invite.title)}</h1>
<p class="meta">Open Wanderer on your iPhone and sign in with the email address this invite was sent to. The trip appears in your Trips list.</p>
<p class="foot">Wanderer is a trip planner by Yoink Labs. One Yoink Labs account works in the app and on yoinklabs.dev.</p>`,
  );
}
