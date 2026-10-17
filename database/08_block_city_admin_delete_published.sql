-- =====================================================================
-- 08: City admins (and other non-super admins) cannot DELETE listings that
--     are published (or active / live). Super Admin can still delete them.
--     Owners can still delete their own listings as before.
--
-- How it works:
--   A RESTRICTIVE policy is ANDed with every permissive policy, so even the
--   *_admin_all policies can no longer delete a live row for a non-super admin.
--   Owners and other users are not affected (the rule only applies when the
--   caller is a listing admin and not Super Admin).
--
-- Run once in the Supabase SQL editor. Safe to re-run.
-- =====================================================================
begin;

drop policy if exists eedb_no_delete_live_properties_by_city_admin on public.properties;
create policy eedb_no_delete_live_properties_by_city_admin on public.properties
  as restrictive for delete to authenticated
  using (
    not (public.eedb_is_listing_admin() and not public.eedb_is_super_admin()
         and status in ('published','active'))
  );

drop policy if exists eedb_no_delete_live_jobs_by_city_admin on public.jobs;
create policy eedb_no_delete_live_jobs_by_city_admin on public.jobs
  as restrictive for delete to authenticated
  using (
    not (public.eedb_is_listing_admin() and not public.eedb_is_super_admin()
         and status in ('published','active'))
  );

drop policy if exists eedb_no_delete_live_marketplace_by_city_admin on public.marketplace_items;
create policy eedb_no_delete_live_marketplace_by_city_admin on public.marketplace_items
  as restrictive for delete to authenticated
  using (
    not (public.eedb_is_listing_admin() and not public.eedb_is_super_admin()
         and status in ('published','active'))
  );

drop policy if exists eedb_no_delete_live_cars_by_city_admin on public.cars;
create policy eedb_no_delete_live_cars_by_city_admin on public.cars
  as restrictive for delete to authenticated
  using (
    not (public.eedb_is_listing_admin() and not public.eedb_is_super_admin()
         and status in ('published','active'))
  );

commit;
