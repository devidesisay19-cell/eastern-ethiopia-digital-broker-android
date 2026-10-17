-- =====================================================================
-- 13: (a) Only Super Admin can delete listings, and ONLY when they are
--         sold or rented (property, marketplace item, car).
--         Jobs: only Super Admin can delete (no sold/rented status for jobs).
--         Deleting a listing also removes its photos from storage (see 12),
--         so storage and database are both freed.
--     (b) Storage limit set to Pro plan size (100 GB = 107374182400 bytes).
--         IMPORTANT: run (b) only AFTER the project is upgraded to Pro,
--         otherwise Supabase (1 GB on Free) refuses uploads before this guard.
-- Run once in the Supabase SQL editor after 01..12. Safe to re-run.
-- =====================================================================
begin;

-- (a) Delete rules
drop policy if exists eedb_only_super_admin_delete_properties on public.properties;
drop policy if exists eedb_superadmin_delete_sold_rented_properties on public.properties;
create policy eedb_superadmin_delete_sold_rented_properties on public.properties
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin() and status in ('sold','rented'));

drop policy if exists eedb_only_super_admin_delete_marketplace on public.marketplace_items;
drop policy if exists eedb_superadmin_delete_sold_rented_marketplace on public.marketplace_items;
create policy eedb_superadmin_delete_sold_rented_marketplace on public.marketplace_items
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin() and status in ('sold','rented'));

drop policy if exists eedb_only_super_admin_delete_cars on public.cars;
drop policy if exists eedb_superadmin_delete_sold_rented_cars on public.cars;
create policy eedb_superadmin_delete_sold_rented_cars on public.cars
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin() and status in ('sold','rented'));

-- jobs: Super Admin only (any status)
drop policy if exists eedb_only_super_admin_delete_jobs on public.jobs;
create policy eedb_only_super_admin_delete_jobs on public.jobs
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin());

-- (b) Storage limit = Pro plan (100 GB)
update public.eedb_settings set value = '107374182400' where key = 'storage_limit_bytes';

commit;
