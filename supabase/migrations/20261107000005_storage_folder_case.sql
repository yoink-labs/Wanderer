-- UUIDs rendered by Swift are uppercase; make the folder-owner checks
-- case-insensitive so cover/avatar/photo uploads work regardless of casing.

drop policy if exists "users upload to own folder" on storage.objects;
create policy "users upload to own folder"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id in ('avatars', 'trip-covers', 'place-photos')
        and lower((storage.foldername(name))[1]) = auth.uid()::text
    );

drop policy if exists "users update own folder" on storage.objects;
create policy "users update own folder"
    on storage.objects for update
    to authenticated
    using (
        bucket_id in ('avatars', 'trip-covers', 'place-photos')
        and lower((storage.foldername(name))[1]) = auth.uid()::text
    )
    with check (
        bucket_id in ('avatars', 'trip-covers', 'place-photos')
        and lower((storage.foldername(name))[1]) = auth.uid()::text
    );

drop policy if exists "users delete own folder" on storage.objects;
create policy "users delete own folder"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id in ('avatars', 'trip-covers', 'place-photos')
        and lower((storage.foldername(name))[1]) = auth.uid()::text
    );
