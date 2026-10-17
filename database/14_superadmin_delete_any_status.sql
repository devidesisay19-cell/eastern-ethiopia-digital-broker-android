-- =====================================================================
-- 14: Only Super Admin can delete listings (property, job, marketplace,
--     car) - ANY status. Deleting also frees their photos from storage
--     (migration 12) and removes the database rows.
--     Owners, agents, employers and city admins cannot delete.
-- Run once in the Supabase SQL editor after 01..13. Safe to re-run.
-- =====================================================================
begin;

drop policy if exists eedb_superadmin_delete_sold_rented_properties on public.properties;
drop policy if exists eedb_only_super_admin_delete_properties on public.properties;
create policy eedb_only_super_admin_delete_properties on public.properties
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin());

drop policy if exists eedb_superadmin_delete_sold_rented_marketplace on public.marketplace_items;
drop policy if exists eedb_only_super_admin_delete_marketplace on public.marketplace_items;
create policy eedb_only_super_admin_delete_marketplace on public.marketplace_items
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin());

drop policy if exists eedb_superadmin_delete_sold_rented_cars on public.cars;
drop policy if exists eedb_only_super_admin_delete_cars on public.cars;
create policy eedb_only_super_admin_delete_cars on public.cars
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin());

drop policy if exists eedb_only_super_admin_delete_jobs on public.jobs;
create policy eedb_only_super_admin_delete_jobs on public.jobs
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin());

commit;
