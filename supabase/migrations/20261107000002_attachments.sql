-- Attachments and extra reservation metadata.
-- Attachments are trip-scoped files stored in a private Storage bucket.

alter table public.reservations
    add column if not exists metadata jsonb not null default '{}'::jsonb;

create table if not exists public.attachments (
    id uuid primary key default gen_random_uuid(),
    trip_id uuid not null references public.trips (id) on delete cascade,
    reservation_id uuid references public.reservations (id) on delete cascade,
    place_id uuid references public.places (id) on delete cascade,
    name text not null,
    storage_path text not null,
    mime_type text,
    size_bytes bigint,
    created_by uuid references public.profiles (id) on delete set null,
    created_at timestamptz not null default now()
);

create index if not exists attachments_trip_idx on public.attachments (trip_id, created_at desc);

alter table public.attachments enable row level security;

drop policy if exists "attachments readable by members" on public.attachments;
create policy "attachments readable by members"
    on public.attachments for select
    to authenticated
    using (public.is_trip_member(trip_id));

drop policy if exists "attachments written by editors" on public.attachments;
create policy "attachments written by editors"
    on public.attachments for insert
    to authenticated
    with check (public.can_edit_trip(trip_id));

drop policy if exists "attachments deleted by editors" on public.attachments;
create policy "attachments deleted by editors"
    on public.attachments for delete
    to authenticated
    using (public.can_edit_trip(trip_id));

insert into storage.buckets (id, name, public)
values ('trip-attachments', 'trip-attachments', false)
on conflict (id) do nothing;

drop policy if exists "trip members read attachment objects" on storage.objects;
create policy "trip members read attachment objects"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'trip-attachments'
        and exists (
            select 1 from public.trip_members m
            where m.trip_id = ((storage.foldername(name))[1])::uuid
              and m.user_id = auth.uid()
        )
    );

drop policy if exists "trip editors upload attachment objects" on storage.objects;
create policy "trip editors upload attachment objects"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'trip-attachments'
        and public.can_edit_trip(((storage.foldername(name))[1])::uuid)
    );

drop policy if exists "trip editors delete attachment objects" on storage.objects;
create policy "trip editors delete attachment objects"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id = 'trip-attachments'
        and public.can_edit_trip(((storage.foldername(name))[1])::uuid)
    );
