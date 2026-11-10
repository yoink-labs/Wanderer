/**
 * Builds a D1 import from a Supabase export.
 *
 * Usage:
 *   npx tsx scripts/import-supabase.ts --dir ./export --out ./import.sql [--dry-run]
 *
 * The export directory holds one `<table>.ndjson` per table, as produced by
 * "Export data" in the Supabase table editor or a `copy (select ...) to stdout`
 * dump. Rows keep their existing UUIDs, which is what makes the copy
 * idempotent: every statement is INSERT ... ON CONFLICT (id) DO UPDATE.
 *
 * Identity: Supabase `auth.users` are not exported here. Supply
 * `identities.ndjson` with rows of `{clerk_sub, profile_id, email}` to map the
 * old profile ids to Clerk subjects. Profiles without an identity still import
 * (their trips keep working) but cannot sign in until they are mapped.
 */

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

export interface ImportOptions {
  dir: string;
  out?: string;
  dryRun?: boolean;
}

/** Foreign-key order. Parents before children. */
export const TABLE_ORDER = [
  "profiles",
  "identities",
  "trips",
  "trip_members",
  "trip_invites",
  "trip_days",
  "places",
  "reservations",
  "expenses",
  "expense_splits",
  "settlements",
  "checklist_items",
  "guides",
  "guide_places",
  "visited_places",
  "attachments"
] as const;

/** Tables whose primary key is not `id`. */
const PRIMARY_KEYS: Record<string, string[]> = {
  identities: ["clerk_sub"],
  trip_members: ["trip_id", "user_id"]
};

/** Columns that hold a single UUID and must be normalized to lowercase. */
const UUID_COLUMNS = new Set([
  "id",
  "profile_id",
  "owner_id",
  "user_id",
  "trip_id",
  "day_id",
  "created_by",
  "paid_by",
  "from_user",
  "to_user",
  "expense_id",
  "author_id",
  "guide_id",
  "reservation_id",
  "place_id"
]);

const BOOLEAN_COLUMNS = new Set(["is_checked", "is_published"]);

const UUID_PATTERN = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export interface ImportPlan {
  statements: string[];
  counts: Record<string, number>;
  skipped: Record<string, number>;
  warnings: string[];
}

type Row = Record<string, unknown>;

function sqlLiteral(value: unknown): string {
  if (value === null || value === undefined) return "NULL";
  if (typeof value === "boolean") return value ? "1" : "0";
  if (typeof value === "number") {
    if (!Number.isFinite(value)) return "NULL";
    return String(value);
  }
  if (Array.isArray(value)) return sqlLiteral(JSON.stringify(value));
  if (typeof value === "object") return sqlLiteral(JSON.stringify(value));
  return `'${String(value).replace(/'/g, "''")}'`;
}

export function normalizeRow(table: string, raw: Row): Row {
  const row: Row = {};
  for (const [key, value] of Object.entries(raw)) {
    if (value === undefined) continue;
    if (UUID_COLUMNS.has(key) && typeof value === "string" && UUID_PATTERN.test(value)) {
      row[key] = value.toLowerCase();
      continue;
    }
    if (key === "split_with") {
      row[key] = Array.isArray(value) ? JSON.stringify(value.map((item) => (typeof item === "string" ? item.toLowerCase() : item))) : value;
      continue;
    }
    if (BOOLEAN_COLUMNS.has(key) && typeof value === "boolean") {
      row[key] = value ? 1 : 0;
      continue;
    }
    row[key] = value;
  }
  return row;
}

function conflictsFor(table: string): string {
  const keys = PRIMARY_KEYS[table] ?? ["id"];
  return keys.join(", ");
}

export function buildPlan(tables: Record<string, Row[]>, warn: (message: string) => void = () => undefined): ImportPlan {
  const statements: string[] = [];
  const counts: Record<string, number> = {};
  const skipped: Record<string, number> = {};
  const warnings: string[] = [];

  for (const table of TABLE_ORDER) {
    const rows = tables[table];
    if (!rows || rows.length === 0) continue;

    const normalized = rows.map((row) => normalizeRow(table, row));
    const columns = [...new Set(normalized.flatMap((row) => Object.keys(row)))];
    if (columns.length === 0) continue;

    const target = table === "identities" ? "identities" : table;
    const conflict = conflictsFor(target);
    const updates = columns.filter((column) => !(PRIMARY_KEYS[target] ?? ["id"]).includes(column));

    statements.push(`-- ${table}: ${normalized.length} row(s)`);
    for (const row of normalized) {
      const values = columns.map((column) => sqlLiteral(row[column]));
      const updateClause = updates.length
        ? `DO UPDATE SET ${updates.map((column) => `${column} = excluded.${column}`).join(", ")}`
        : "DO NOTHING";
      statements.push(
        `INSERT INTO ${target} (${columns.join(", ")}) VALUES (${values.join(", ")}) ON CONFLICT (${conflict}) ${updateClause};`
      );
    }
    counts[table] = normalized.length;

    for (const row of normalized) {
      if (!(PRIMARY_KEYS[target] ?? ["id"]).every((key) => row[key] !== undefined && row[key] !== null)) {
        skipped[table] = (skipped[table] ?? 0) + 1;
        warn(`${table}: a row is missing its key and will fail the import`);
        warnings.push(`${table}: a row is missing its key`);
      }
    }
  }

  return { statements, counts, skipped, warnings };
}

export function loadTables(dir: string): Record<string, Row[]> {
  const tables: Record<string, Row[]> = {};
  for (const table of TABLE_ORDER) {
    const path = join(dir, `${table}.ndjson`);
    if (!existsSync(path)) continue;
    const rows = readFileSync(path, "utf8")
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line, index) => {
        try {
          return JSON.parse(line) as Row;
        } catch {
          throw new Error(`${table}.ndjson line ${index + 1} is not valid JSON`);
        }
      });
    tables[table] = rows;
  }
  return tables;
}

export function runImport(options: ImportOptions): ImportPlan {
  const tables = loadTables(options.dir);
  if (Object.keys(tables).length === 0) {
    throw new Error(`No <table>.ndjson files found in ${options.dir}`);
  }
  const plan = buildPlan(tables, (message) => console.warn(`warning: ${message}`));
  const header = [
    "-- Generated by scripts/import-supabase.ts",
    "-- Run with: npx wrangler d1 execute wanderer --remote --file import.sql",
    `PRAGMA foreign_keys = ON;`,
    ""
  ];
  const sql = [...header, ...plan.statements, ""].join("\n");

  if (options.out) writeFileSync(options.out, sql, "utf8");
  if (!options.dryRun) {
    console.log(Object.entries(plan.counts).map(([table, count]) => `${table}: ${count}`).join("\n"));
  }
  return plan;
}

if (process.argv[1]?.endsWith("import-supabase.ts")) {
  const args = process.argv.slice(2);
  const dirIndex = args.indexOf("--dir");
  const outIndex = args.indexOf("--out");
  if (dirIndex === -1) {
    console.error("usage: import-supabase.ts --dir <export> [--out <file>] [--dry-run]");
    process.exit(1);
  }
  const plan = runImport({
    dir: args[dirIndex + 1],
    out: outIndex === -1 ? undefined : args[outIndex + 1],
    dryRun: args.includes("--dry-run")
  });
  if (args.includes("--dry-run")) {
    console.log(JSON.stringify(plan.counts, null, 2));
  }
}
