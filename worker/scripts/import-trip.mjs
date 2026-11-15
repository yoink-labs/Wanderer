#!/usr/bin/env node
/** Import a private JSON trip without checking its data into the repository.
 * Usage: ade secrets exec --env CLOUDFLARE_API_TOKEN -- node scripts/import-trip.mjs /path/to/trip.json [--remote]
 * Default only writes a reviewable SQL file under .ade/imports in this lane.
 * Stable UUIDs and INSERT OR IGNORE make retries additive: user edits survive.
 */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { createHash, randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
const root = fileURLToPath(new URL("../../", import.meta.url));
const input = process.argv[2];
if (!input)
  throw new Error("Pass a private JSON data file; see scripts/import-trip.md.");
const data = JSON.parse(readFileSync(input, "utf8"));
const worker = path.join(root, "worker");
const wrangler = path.join(worker, "node_modules/wrangler/bin/wrangler.js");
const uuid = (key) => {
  const h = createHash("sha256")
    .update(data.source_key + ":" + key)
    .digest("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-a${h.slice(17, 20)}-${h.slice(20, 32)}`;
};
function query(sql) {
  return JSON.parse(
    execFileSync(
      process.execPath,
      [
        wrangler,
        "d1",
        "execute",
        "wanderer",
        "--remote",
        "--command",
        sql,
        "--json",
      ],
      { cwd: worker, encoding: "utf8" },
    ),
  )[0].results;
}
const quote = (v) =>
  v == null
    ? "NULL"
    : typeof v === "number"
      ? String(v)
      : "'" + String(v).replaceAll("'", "''") + "'";
if (
  !data.owner_email ||
  !data.owner_clerk_sub ||
  !data.source_key ||
  !data.trip?.title
)
  throw new Error("Missing verified owner or trip identity.");
const owners = query(
  `SELECT p.id,p.email,i.clerk_sub FROM profiles p JOIN identities i ON i.profile_id=p.id WHERE lower(p.email)=lower(${quote(data.owner_email)}) AND i.clerk_sub=${quote(data.owner_clerk_sub)}`,
);
if (owners.length !== 1)
  throw new Error("Cannot uniquely identify owner; nothing written.");
const owner = owners[0].id;
const tripId = uuid("trip");
const same = query(
  `SELECT id FROM trips WHERE owner_id=${quote(owner)} AND title=${quote(data.trip.title)}`,
);
if (same.some((t) => t.id !== tripId))
  throw new Error(
    "A different trip with this name already exists. Review it before importing.",
  );
const statements = [];
function insert(table, row) {
  statements.push(
    `INSERT OR IGNORE INTO ${table} (${Object.keys(row).join(",")}) VALUES (${Object.values(row).map(quote).join(",")});`,
  );
}
insert("trips", {
  id: tripId,
  owner_id: owner,
  share_token: randomUUID(),
  currency: "USD",
  timezone: "UTC",
  ...data.trip,
});
insert("trip_members", { trip_id: tripId, user_id: owner, role: "owner" });
const dates = [];
for (
  let t = Date.parse(data.trip.start_date + "T00:00:00Z");
  t <= Date.parse(data.trip.end_date + "T00:00:00Z");
  t += 86400000
)
  dates.push(new Date(t).toISOString().slice(0, 10));
if (!dates.length || dates.length > 366) throw new Error("Invalid trip dates");
for (const [day_index, date] of dates.entries())
  insert("trip_days", {
    id: uuid("day:" + date),
    trip_id: tripId,
    day_index,
    date,
    ...(data.days?.[date] ?? {}),
  });
for (const [position, list] of (data.lists ?? []).entries())
  insert("trip_lists", {
    id: uuid("list:" + list.key),
    trip_id: tripId,
    title: list.title,
    position,
  });
for (const [position, place] of (data.places ?? []).entries()) {
  const { key, date, list_key, ...fields } = place;
  if (date && !dates.includes(date)) throw new Error("Place date outside trip");
  insert("places", {
    id: uuid("place:" + key),
    trip_id: tripId,
    day_id: date ? uuid("day:" + date) : null,
    list_id: list_key ? uuid("list:" + list_key) : null,
    position,
    created_by: owner,
    ...fields,
  });
}
for (const reservation of data.reservations ?? []) {
  const { key, metadata, ...fields } = reservation;
  insert("reservations", {
    id: uuid("reservation:" + key),
    trip_id: tripId,
    created_by: owner,
    ...fields,
    metadata: JSON.stringify(metadata ?? {}),
  });
}
const out = path.join(root, ".ade/imports");
mkdirSync(out, { recursive: true });
const sqlFile = path.join(out, tripId + ".sql");
writeFileSync(sqlFile, statements.join("\n"));
if (process.argv.includes("--remote")) {
  execFileSync(
    process.execPath,
    [
      wrangler,
      "d1",
      "execute",
      "wanderer",
      "--remote",
      "--file",
      sqlFile,
      "--json",
    ],
    { cwd: worker, stdio: "pipe" },
  );
  const counts = query(
    `SELECT (SELECT count(*) FROM trip_days WHERE trip_id=${quote(tripId)}) days,(SELECT count(*) FROM places WHERE trip_id=${quote(tripId)}) places,(SELECT count(*) FROM reservations WHERE trip_id=${quote(tripId)} AND type='flight') flights,(SELECT count(*) FROM reservations WHERE trip_id=${quote(tripId)} AND type='lodging') stays,(SELECT count(*) FROM trip_members WHERE trip_id=${quote(tripId)}) members`,
  );
  console.log(
    JSON.stringify({ trip_id: tripId, ...counts[0], imported: true }),
  );
} else
  console.log(
    JSON.stringify({
      trip_id: tripId,
      sqlFile,
      statements: statements.length,
      imported: false,
    }),
  );
