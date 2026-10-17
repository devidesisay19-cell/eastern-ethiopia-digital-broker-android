-- =====================================================================
-- 12: When a listing is deleted, its photos are deleted from storage too,
--     so the space is freed and the storage guard (11) can accept uploads
--     again.
--       * property_images rows  -> storage 'property-images' (by storage_path)
--       * marketplace_items.photo_urls / cars.photo_urls (public URLs)
--         -> 'marketplace-images' / 'car-images'
--
-- Run once in the Supabase SQL editor after 11. Safe to re-run.
-- Check after a test delete: Storage usage (eedb_storage_status) should drop.
-- =====================================================================
begin;

-- 1) Property photo rows deleted (also happens when the property is deleted, by cascade)
create or replace function public.eedb_delete_property_photo_file()
returns trigger
language plpgsql security definer set search_path=public, storage
as $$
begin
  if old.storage_path is not null then
    delete from storage.objects
     where bucket_id = 'property-images' and name = old.storage_path;
  end if;
  return old;
end;
$$;

drop trigger if exists eedb_property_photo_file_cleanup on public.property_images;
create trigger eedb_property_photo_file_cleanup
after delete on public.property_images
for each row execute function public.eedb_delete_property_photo_file();

-- 2) Marketplace / car listing deleted -> remove their photo_urls files
create or replace function public.eedb_delete_listing_photos_from_urls()
returns trigger
language plpgsql security definer set search_path=public, storage
as $$
declare
  bkt  text := tg_argv[0];
  u    text;
  pth  text;
begin
  if old.photo_urls is null then
    return old;
  end if;
  foreach u in array old.photo_urls loop
    pth := split_part(u, '/object/public/' || bkt || '/', 2);
    if pth <> '' then
      delete from storage.objects where bucket_id = bkt and name = pth;
    end if;
  end loop;
  return old;
end;
$$;

drop trigger if exists eedb_marketplace_photo_cleanup on public.marketplace_items;
create trigger eedb_marketplace_photo_cleanup
after delete on public.marketplace_items
for each row execute function public.eedb_delete_listing_photos_from_urls('marketplace-images');

drop trigger if exists eedb_car_photo_cleanup on public.cars;
create trigger eedb_car_photo_cleanup
after delete on public.cars
for each row execute function public.eedb_delete_listing_photos_from_urls('car-images');

commit;
