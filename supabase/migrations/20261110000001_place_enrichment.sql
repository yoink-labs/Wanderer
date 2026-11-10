-- Per-place status and cost (mirrors the D1 migration).

alter table public.places
    add column if not exists visited_at timestamptz;

alter table public.expenses
    add column if not exists place_id uuid references public.places (id) on delete set null;

create index if not exists expenses_place_idx on public.expenses (place_id);
