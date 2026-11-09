-- Splitwise-style expense splits and settlements.

do $$
begin
    create type public.expense_split_mode as enum ('equal', 'exact', 'percent', 'shares');
exception
    when duplicate_object then null;
end $$;

alter table public.expenses
    add column if not exists split_mode public.expense_split_mode not null default 'equal';

create table if not exists public.expense_splits (
    id uuid primary key default gen_random_uuid(),
    trip_id uuid not null references public.trips (id) on delete cascade,
    expense_id uuid not null references public.expenses (id) on delete cascade,
    user_id uuid not null references public.profiles (id) on delete cascade,
    amount numeric(12, 2) not null default 0,
    weight numeric(10, 2),
    created_at timestamptz not null default now(),
    unique (expense_id, user_id)
);

create index if not exists expense_splits_trip_idx on public.expense_splits (trip_id);
create index if not exists expense_splits_expense_idx on public.expense_splits (expense_id);

create table if not exists public.settlements (
    id uuid primary key default gen_random_uuid(),
    trip_id uuid not null references public.trips (id) on delete cascade,
    from_user uuid not null references public.profiles (id) on delete cascade,
    to_user uuid not null references public.profiles (id) on delete cascade,
    amount numeric(12, 2) not null check (amount > 0),
    currency text not null default 'USD',
    settled_at date not null default current_date,
    note text,
    created_by uuid references public.profiles (id) on delete set null,
    created_at timestamptz not null default now()
);

create index if not exists settlements_trip_idx on public.settlements (trip_id, settled_at desc);

alter table public.expense_splits enable row level security;
alter table public.settlements enable row level security;

drop policy if exists "splits readable by members" on public.expense_splits;
create policy "splits readable by members"
    on public.expense_splits for select
    to authenticated
    using (public.is_trip_member(trip_id));

drop policy if exists "splits written by editors" on public.expense_splits;
create policy "splits written by editors"
    on public.expense_splits for all
    to authenticated
    using (public.can_edit_trip(trip_id))
    with check (public.can_edit_trip(trip_id));

drop policy if exists "settlements readable by members" on public.settlements;
create policy "settlements readable by members"
    on public.settlements for select
    to authenticated
    using (public.is_trip_member(trip_id));

drop policy if exists "settlements written by editors" on public.settlements;
create policy "settlements written by editors"
    on public.settlements for all
    to authenticated
    using (public.can_edit_trip(trip_id))
    with check (public.can_edit_trip(trip_id));

-- Backfill splits for existing expenses that already use split_with.
insert into public.expense_splits (trip_id, expense_id, user_id, amount)
select
    e.trip_id,
    e.id,
    member.user_id,
    round(e.amount / greatest(array_length(e.split_with, 1), 1), 2)
from public.expenses e
cross join lateral unnest(e.split_with) as member(user_id)
where array_length(e.split_with, 1) > 0
  and not exists (
      select 1 from public.expense_splits s
      where s.expense_id = e.id and s.user_id = member.user_id
  );
