-- Tighten profile visibility: a signed-in user can read their own profile and
-- the profiles of people who share a trip with them. Nothing else.

create or replace function public.shares_trip_with(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.trip_members mine
        join public.trip_members theirs on mine.trip_id = theirs.trip_id
        where mine.user_id = auth.uid()
          and theirs.user_id = p_user_id
    );
$$;

drop policy if exists "profiles readable by authenticated" on public.profiles;

create policy "profiles self or trip-mate read"
    on public.profiles for select
    to authenticated
    using (id = auth.uid() or public.shares_trip_with(id));
