-- =====================================================================
-- 10: (a) Only Super Admin can DELETE listings (any status).
--     (b) Investors can view the daily report, same as Super Admin.
--     (c) Payment ledger accepts CBE, Chapa, E-birr in addition to
--         Telebirr and CBE Birr.
-- Run once in the Supabase SQL editor (after 01..09). Safe to re-run.
-- =====================================================================
begin;

-- ---------- (a) Delete: Super Admin only, any status ----------
drop policy if exists eedb_no_delete_live_properties on public.properties;
drop policy if exists eedb_no_delete_live_jobs on public.jobs;
drop policy if exists eedb_no_delete_live_marketplace on public.marketplace_items;
drop policy if exists eedb_no_delete_live_cars on public.cars;

drop policy if exists eedb_only_super_admin_delete_properties on public.properties;
create policy eedb_only_super_admin_delete_properties on public.properties
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin());

drop policy if exists eedb_only_super_admin_delete_jobs on public.jobs;
create policy eedb_only_super_admin_delete_jobs on public.jobs
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin());

drop policy if exists eedb_only_super_admin_delete_marketplace on public.marketplace_items;
create policy eedb_only_super_admin_delete_marketplace on public.marketplace_items
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin());

drop policy if exists eedb_only_super_admin_delete_cars on public.cars;
create policy eedb_only_super_admin_delete_cars on public.cars
  as restrictive for delete to authenticated
  using (public.eedb_is_super_admin());

-- ---------- (b) Daily report: Super Admin + Investor ----------
create or replace function public.eedb_daily_report(report_date date default null)
returns table (
  city_id uuid, city_name text,
  prop_rent int, prop_sale int, jobs int,
  mkt_sell int, mkt_rent int, car_sell int, car_rent int,
  prop_sold int, prop_rented int, mkt_sold int, mkt_rented int,
  car_sold int, car_rented int
)
language plpgsql stable security definer set search_path=public
as $$
#variable_conflict use_column
declare
  tz constant text := 'Africa/Addis_Ababa';
  d date := coalesce(report_date, (now() at time zone 'Africa/Addis_Ababa')::date);
  t0 timestamptz;
  t1 timestamptz;
begin
  if not (public.eedb_is_super_admin() or public.eedb_is_investor()) then
    raise exception 'Only Super Admin or Investor can view reports';
  end if;
  t0 := d::timestamp at time zone tz;
  t1 := (d + 1)::timestamp at time zone tz;

  return query
  with ev as (
    select p.city_id as cid,
           case when lower(coalesce(p.listing_type,'')) = 'rent' then 'prop_rent' else 'prop_sale' end as k
      from public.properties p where p.created_at >= t0 and p.created_at < t1
    union all
    select j.city_id, 'jobs'
      from public.jobs j where j.created_at >= t0 and j.created_at < t1
    union all
    select m.city_id,
           case when lower(coalesce(m.listing_type,'')) = 'rent' then 'mkt_rent' else 'mkt_sell' end
      from public.marketplace_items m where m.created_at >= t0 and m.created_at < t1
    union all
    select c.city_id,
           case when lower(coalesce(c.listing_type,'')) = 'rent' then 'car_rent' else 'car_sell' end
      from public.cars c where c.created_at >= t0 and c.created_at < t1
    union all
    select h.city_id,
           (case h.entity_type when 'property' then 'prop' when 'marketplace' then 'mkt' else 'car' end)
           || '_' || h.new_status
      from (select distinct x.entity_type, x.entity_id, x.new_status, x.city_id
              from public.post_status_history x
             where x.created_at >= t0 and x.created_at < t1
               and x.new_status in ('sold','rented')
               and x.entity_type in ('property','marketplace','car')
               -- FIX: only listings that still exist
               and (
                    (x.entity_type = 'property'    and exists (select 1 from public.properties p     where p.id = x.entity_id))
                 or (x.entity_type = 'marketplace' and exists (select 1 from public.marketplace_items m where m.id = x.entity_id))
                 or (x.entity_type = 'car'         and exists (select 1 from public.cars c            where c.id = x.entity_id))
               )) h
  ),
  cities as (
    select l.id as cid, l.name as cname from public.locations l
     where l.type = 'city' and coalesce(l.is_active, true)
    union all
    select null::uuid, '(No city selected)'
  )
  select c.cid, c.cname::text,
         (count(*) filter (where ev.k = 'prop_rent'))::int,
         (count(*) filter (where ev.k = 'prop_sale'))::int,
         (count(*) filter (where ev.k = 'jobs'))::int,
         (count(*) filter (where ev.k = 'mkt_sell'))::int,
         (count(*) filter (where ev.k = 'mkt_rent'))::int,
         (count(*) filter (where ev.k = 'car_sell'))::int,
         (count(*) filter (where ev.k = 'car_rent'))::int,
         (count(*) filter (where ev.k = 'prop_sold'))::int,
         (count(*) filter (where ev.k = 'prop_rented'))::int,
         (count(*) filter (where ev.k = 'mkt_sold'))::int,
         (count(*) filter (where ev.k = 'mkt_rented'))::int,
         (count(*) filter (where ev.k = 'car_sold'))::int,
         (count(*) filter (where ev.k = 'car_rented'))::int
    from cities c
    left join ev on ev.cid is not distinct from c.cid
   group by c.cid, c.cname
   order by (c.cid is null), c.cname;
end;
$$;

revoke all on function public.eedb_daily_report(date) from public, anon;
grant execute on function public.eedb_daily_report(date) to authenticated;

-- ---------- (c) Payment methods ----------
alter table public.payments drop constraint if exists payments_method_check;
alter table public.payments add constraint payments_method_check
  check (method in ('cash','bank_transfer','telebirr','cbe_birr','cbe','chapa','ebirr','other'));

commit;
