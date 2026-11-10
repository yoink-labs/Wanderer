-- Named lists (mirrors the D1 migration).

create table if not exists public.trip_lists (
    id uuid primary key default gen_random_uuid(),
    trip_id uuid not null references public.trips (id) on delete cascade,
    title text not null,
    position integer not null default 0,
    created_at timestamptz not null default now()
);

create index if not exists trip_lists_trip_idx on public.trip_lists (trip_id, position);

alter table public.places
    add column if not exists list_id uuid references public.trip_lists (id) on delete set null;

create index if not exists places_list_idx on public.places (trip_id, list_id);

alter table public.trip_lists enable row level security;

drop policy if exists "lists readable by members" on public.trip_lists;
create policy "lists readable by members"
    on public.trip_lists for select
    to authenticated
    using (public.is_trip_member(trip_id));

drop policy if exists "lists written by editors" on public.trip_lists;
create policy "lists written by editors"
    on public.trip_lists for all
    to authenticated
    using (public.can_edit_trip(trip_id))
    with check (public.can_edit_trip(trip_id));
