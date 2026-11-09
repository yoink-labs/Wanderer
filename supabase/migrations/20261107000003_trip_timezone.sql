alter table public.trips
    add column if not exists timezone text not null default 'UTC';

update public.trips set timezone = 'Asia/Tokyo' where title = 'Kyoto in autumn';
