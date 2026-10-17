-- =====================================================================
-- 09: Nobody except Super Admin can DELETE a published / active listing
--     (property, job, marketplace item, car). This includes owners,
--     sellers, employers and city admins. Owners can still delete their
--     listings while they are pending_review, rejected, hidden, sold or
--     rented, as before.
--
-- Replaces the rule in 08 with a single restrictive policy per table.
-- Run once in the Supabase SQL editor. Safe to re-run.
-- =====================================================================
begin;

drop policy if exists eedb_no_delete_live_properties_by_city_admin on public.properties;
drop policy if exists eedb_no_delete_live_jobs_by_city_admin on public.jobs;
drop policy if exists eedb_no_delete_live_marketplace_by_city_admin on public.marketplace_items;
drop policy if exists eedb_no_delete_live_cars_by_city_admin on public.cars;

drop policy if exists eedb_no_delete_live_properties on public.properties;
create policy eedb_no_delete_live_properties on public.properties
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin() or status not in ('published','active'));

drop policy if exists eedb_no_delete_live_jobs on public.jobs;
create policy eedb_no_delete_live_jobs on public.jobs
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin() or status not in ('published','active'));

drop policy if exists eedb_no_delete_live_marketplace on public.marketplace_items;
create policy eedb_no_delete_live_marketplace on public.marketplace_items
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin() or status not in ('published','active'));

drop policy if exists eedb_no_delete_live_cars on public.cars;
create policy eedb_no_delete_live_cars on public.cars
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin() or status not in ('published','active'));

commit;
