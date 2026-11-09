-- Wanderer initial schema
-- Postgres 15+ / Supabase

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.trip_role as enum ('owner', 'editor', 'viewer');
create type public.place_category as enum ('sight', 'food', 'lodging', 'activity', 'transport', 'shopping', 'note');
create type public.reservation_type as enum ('flight', 'lodging', 'car', 'restaurant', 'train', 'other');
create type public.expense_category as enum ('food', 'lodging', 'transport', 'activities', 'shopping', 'other');

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    email text,
    display_name text,
    avatar_url text,
    locale text not null default 'en',
    currency text not null default 'USD',
    units text not null default 'metric',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.profiles (id, email, display_name)
    values (
        new.id,
        new.email,
        coalesce(new.raw_user_meta_data ->> 'display_name', split_part(coalesce(new.email, ''), '@', 1))
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Trips
-- ---------------------------------------------------------------------------

create table public.trips (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references public.profiles (id) on delete cascade,
    title text not null,
    destination text,
    start_date date,
    end_date date,
    currency text not null default 'USD',
    cover_url text,
    cover_color text,
    notes text,
    share_token uuid not null default gen_random_uuid(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index trips_owner_idx on public.trips (owner_id);
create unique index trips_share_token_idx on public.trips (share_token);

create table public.trip_members (
    trip_id uuid not null references public.trips (id) on delete cascade,
    user_id uuid not null references public.profiles (id) on delete cascade,
    role public.trip_role not null default 'editor',
    joined_at timestamptz not null default now(),
    primary key (trip_id, user_id)
);

create index trip_members_user_idx on public.trip_members (user_id);

-- The creator becomes the owner member automatically.
create or replace function public.handle_new_trip()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.trip_members (trip_id, user_id, role)
    values (new.id, new.owner_id, 'owner')
    on conflict (trip_id, user_id) do update set role = 'owner';
    return new;
end;
$$;

create trigger on_trip_created
    after insert on public.trips
    for each row execute function public.handle_new_trip();

create table public.trip_invites (
    id uuid primary key default gen_random_uuid(),
    trip_id uuid not null references public.trips (id) on delete cascade,
    email text not null,
    role public.trip_role not null default 'editor',
    token uuid not null default gen_random_uuid(),
    expires_at timestamptz,
    accepted_at timestamptz,
    created_at timestamptz not null default now(),
    unique (trip_id, email)
);

-- ---------------------------------------------------------------------------
-- Days, places, reservations, expenses, checklist
-- ---------------------------------------------------------------------------

create table public.trip_days (
    id uuid primary key default gen_random_uuid(),
    trip_id uuid not null references public.trips (id) on delete cascade,
    day_index integer not null check (day_index >= 0),
    date date,
    title text,
    notes text,
    unique (trip_id, day_index)
);

create index trip_days_trip_idx on public.trip_days (trip_id, day_index);

create table public.places (
    id uuid primary key default gen_random_uuid(),
    trip_id uuid not null references public.trips (id) on delete cascade,
    day_id uuid references public.trip_days (id) on delete set null,
    name text not null,
    address text,
    lat double precision,
    lng double precision,
    category public.place_category not null default 'sight',
    notes text,
    website text,
    phone text,
    price_level integer check (price_level between 0 and 4),
    rating numeric(2, 1),
    photo_url text,
    start_time timestamptz,
    end_time timestamptz,
    position integer not null default 0,
    created_by uuid references public.profiles (id) on delete set null,
    created_at timestamptz not null default now()
);

create index places_trip_idx on public.places (trip_id, day_id, position);
create index places_geo_idx on public.places (lat, lng);

create table public.reservations (
    id uuid primary key default gen_random_uuid(),
    trip_id uuid not null references public.trips (id) on delete cascade,
    type public.reservation_type not null default 'other',
    title text not null,
    provider text,
    confirmation_code text,
    start_at timestamptz,
    end_at timestamptz,
    start_location text,
    end_location text,
    cost numeric(12, 2),
    currency text default 'USD',
    notes text,
    created_by uuid references public.profiles (id) on delete set null,
    created_at timestamptz not null default now()
);

create index reservations_trip_idx on public.reservations (trip_id, start_at);

create table public.expenses (
    id uuid primary key default gen_random_uuid(),
    trip_id uuid not null references public.trips (id) on delete cascade,
    title text not null,
    amount numeric(12, 2) not null check (amount >= 0),
    currency text not null default 'USD',
    category public.expense_category not null default 'other',
    paid_by uuid references public.profiles (id) on delete set null,
    split_with uuid[] not null default '{}',
    spent_at date not null default current_date,
    notes text,
    created_by uuid references public.profiles (id) on delete set null,
    created_at timestamptz not null default now()
);

create index expenses_trip_idx on public.expenses (trip_id, spent_at);

create table public.checklist_items (
    id uuid primary key default gen_random_uuid(),
    trip_id uuid not null references public.trips (id) on delete cascade,
    title text not null,
    is_checked boolean not null default false,
    position integer not null default 0,
    created_by uuid references public.profiles (id) on delete set null,
    created_at timestamptz not null default now()
);

create index checklist_trip_idx on public.checklist_items (trip_id, position);

-- ---------------------------------------------------------------------------
-- Public guides (Explore)
-- ---------------------------------------------------------------------------

create table public.guides (
    id uuid primary key default gen_random_uuid(),
    author_id uuid references public.profiles (id) on delete set null,
    title text not null,
    summary text,
    destination text,
    cover_url text,
    is_published boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index guides_published_idx on public.guides (is_published, created_at desc);

create table public.guide_places (
    id uuid primary key default gen_random_uuid(),
    guide_id uuid not null references public.guides (id) on delete cascade,
    name text not null,
    address text,
    lat double precision,
    lng double precision,
    notes text,
    photo_url text,
    position integer not null default 0
);

create index guide_places_guide_idx on public.guide_places (guide_id, position);

-- ---------------------------------------------------------------------------
-- Visited places (profile map)
-- ---------------------------------------------------------------------------

create table public.visited_places (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles (id) on delete cascade,
    country_code text not null,
    city text,
    year integer,
    created_at timestamptz not null default now(),
    unique (user_id, country_code, city, year)
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.is_trip_member(p_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.trip_members m
        where m.trip_id = p_trip_id and m.user_id = auth.uid()
    ) or exists (
        select 1 from public.trips t
        where t.id = p_trip_id and t.owner_id = auth.uid()
    );
$$;

create or replace function public.can_edit_trip(p_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.trip_members m
        where m.trip_id = p_trip_id
          and m.user_id = auth.uid()
          and m.role in ('owner', 'editor')
    ) or exists (
        select 1 from public.trips t
        where t.id = p_trip_id and t.owner_id = auth.uid()
    );
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger profiles_touch_updated_at
    before update on public.profiles
    for each row execute function public.touch_updated_at();

create trigger trips_touch_updated_at
    before update on public.trips
    for each row execute function public.touch_updated_at();

create trigger guides_touch_updated_at
    before update on public.guides
    for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.trips enable row level security;
alter table public.trip_members enable row level security;
alter table public.trip_invites enable row level security;
alter table public.trip_days enable row level security;
alter table public.places enable row level security;
alter table public.reservations enable row level security;
alter table public.expenses enable row level security;
alter table public.checklist_items enable row level security;
alter table public.guides enable row level security;
alter table public.guide_places enable row level security;
alter table public.visited_places enable row level security;

-- Profiles: signed-in users can read the small public profile surface,
-- everyone may only edit their own row.
create policy "profiles readable by authenticated"
    on public.profiles for select
    to authenticated
    using (true);

create policy "profiles self insert"
    on public.profiles for insert
    to authenticated
    with check (id = auth.uid());

create policy "profiles self update"
    on public.profiles for update
    to authenticated
    using (id = auth.uid())
    with check (id = auth.uid());

-- Trips
create policy "trips readable by members"
    on public.trips for select
    to authenticated
    using (owner_id = auth.uid() or public.is_trip_member(id));

create policy "trips insert own"
    on public.trips for insert
    to authenticated
    with check (owner_id = auth.uid());

create policy "trips update by editors"
    on public.trips for update
    to authenticated
    using (public.can_edit_trip(id))
    with check (public.can_edit_trip(id));

create policy "trips delete by owner"
    on public.trips for delete
    to authenticated
    using (owner_id = auth.uid());

-- Members
create policy "members readable by members"
    on public.trip_members for select
    to authenticated
    using (public.is_trip_member(trip_id));

create policy "members managed by editors"
    on public.trip_members for insert
    to authenticated
    with check (public.can_edit_trip(trip_id));

create policy "members update by editors"
    on public.trip_members for update
    to authenticated
    using (public.can_edit_trip(trip_id))
    with check (public.can_edit_trip(trip_id));

create policy "members removed by editors or self"
    on public.trip_members for delete
    to authenticated
    using (public.can_edit_trip(trip_id) or user_id = auth.uid());

-- Invites
create policy "invites readable by editors"
    on public.trip_invites for select
    to authenticated
    using (public.can_edit_trip(trip_id));

create policy "invites managed by editors"
    on public.trip_invites for insert
    to authenticated
    with check (public.can_edit_trip(trip_id));

create policy "invites deleted by editors"
    on public.trip_invites for delete
    to authenticated
    using (public.can_edit_trip(trip_id));

-- Trip content
create policy "days readable by members"
    on public.trip_days for select
    to authenticated
    using (public.is_trip_member(trip_id));
create policy "days written by editors"
    on public.trip_days for all
    to authenticated
    using (public.can_edit_trip(trip_id))
    with check (public.can_edit_trip(trip_id));

create policy "places readable by members"
    on public.places for select
    to authenticated
    using (public.is_trip_member(trip_id));
create policy "places written by editors"
    on public.places for all
    to authenticated
    using (public.can_edit_trip(trip_id))
    with check (public.can_edit_trip(trip_id));

create policy "reservations readable by members"
    on public.reservations for select
    to authenticated
    using (public.is_trip_member(trip_id));
create policy "reservations written by editors"
    on public.reservations for all
    to authenticated
    using (public.can_edit_trip(trip_id))
    with check (public.can_edit_trip(trip_id));

create policy "expenses readable by members"
    on public.expenses for select
    to authenticated
    using (public.is_trip_member(trip_id));
create policy "expenses written by editors"
    on public.expenses for all
    to authenticated
    using (public.can_edit_trip(trip_id))
    with check (public.can_edit_trip(trip_id));

create policy "checklist readable by members"
    on public.checklist_items for select
    to authenticated
    using (public.is_trip_member(trip_id));
create policy "checklist written by editors"
    on public.checklist_items for all
    to authenticated
    using (public.can_edit_trip(trip_id))
    with check (public.can_edit_trip(trip_id));

-- Guides
create policy "published guides are public"
    on public.guides for select
    to anon, authenticated
    using (is_published or author_id = auth.uid());

create policy "guides insert own"
    on public.guides for insert
    to authenticated
    with check (author_id = auth.uid());

create policy "guides update own"
    on public.guides for update
    to authenticated
    using (author_id = auth.uid())
    with check (author_id = auth.uid());

create policy "guides delete own"
    on public.guides for delete
    to authenticated
    using (author_id = auth.uid());

create policy "published guide places are public"
    on public.guide_places for select
    to anon, authenticated
    using (
        exists (
            select 1 from public.guides g
            where g.id = guide_id and (g.is_published or g.author_id = auth.uid())
        )
    );

create policy "guide places written by author"
    on public.guide_places for all
    to authenticated
    using (
        exists (select 1 from public.guides g where g.id = guide_id and g.author_id = auth.uid())
    )
    with check (
        exists (select 1 from public.guides g where g.id = guide_id and g.author_id = auth.uid())
    );

-- Visited places
create policy "visited places own"
    on public.visited_places for all
    to authenticated
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values
    ('avatars', 'avatars', true),
    ('trip-covers', 'trip-covers', true),
    ('place-photos', 'place-photos', true)
on conflict (id) do nothing;

create policy "public image read"
    on storage.objects for select
    to anon, authenticated
    using (bucket_id in ('avatars', 'trip-covers', 'place-photos'));

create policy "users upload to own folder"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id in ('avatars', 'trip-covers', 'place-photos')
        and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "users update own folder"
    on storage.objects for update
    to authenticated
    using (
        bucket_id in ('avatars', 'trip-covers', 'place-photos')
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id in ('avatars', 'trip-covers', 'place-photos')
        and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "users delete own folder"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id in ('avatars', 'trip-covers', 'place-photos')
        and (storage.foldername(name))[1] = auth.uid()::text
    );

-- ---------------------------------------------------------------------------
-- Realtime (collaboration)
-- ---------------------------------------------------------------------------

do $$
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
        begin
            alter publication supabase_realtime add table public.places;
        exception when duplicate_object then null;
        end;
        begin
            alter publication supabase_realtime add table public.trip_days;
        exception when duplicate_object then null;
        end;
        begin
            alter publication supabase_realtime add table public.reservations;
        exception when duplicate_object then null;
        end;
        begin
            alter publication supabase_realtime add table public.expenses;
        exception when duplicate_object then null;
        end;
        begin
            alter publication supabase_realtime add table public.checklist_items;
        exception when duplicate_object then null;
        end;
    end if;
end;
$$;
