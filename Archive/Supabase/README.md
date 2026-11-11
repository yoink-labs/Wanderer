# Archived Supabase implementation

Wanderer used Supabase (Postgres, Auth, Storage) before moving to the
Cloudflare Worker + D1 + R2 with Clerk. There are no production users to
migrate, so the app no longer links Supabase at all.

These `*.swift.txt` files are frozen copies of the last Supabase-backed
implementations, kept for reference. They are **not** part of the Xcode target
and do not compile. The SQL schema and edge function remain under `supabase/`,
and the one-off importer remains at `worker/scripts/import-supabase.ts`; it is
not part of the runtime path.

The hosted Supabase project itself was left untouched.
