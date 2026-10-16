-- =====================================================================
-- 07 FIX: Daily report must not count listings that were deleted.
--
-- Problem:
--   post_status_history has no foreign key to properties / marketplace_items /
--   cars, so when a listing that was Sold/Rented is deleted its history rows
--   stay behind and eedb_daily_report() kept counting them.
--
-- Fix:
--   1. When a listing is deleted, its status-history rows are deleted too.
--   2. eedb_daily_report() only counts Sold/Rented history for listings that
--      still exist.
--   3. One-time cleanup of orphan history rows left from earlier deletes.
--
-- Run this once in Supabase SQL editor (after 02 / 05). Safe to re-run.
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 1. Remove history rows when the listing itself is deleted
-- ---------------------------------------------------------------------
create or replace function public.eedb_cleanup_status_history()
returns trigger
language plpgsql security definer set search_path=public
as $$
begin
  delete from public.post_status_history
   where entity_id = old.id
     and entity_type = case tg_table_name
                         when 'properties' then 'property'
                         when 'marketplace_items' then 'marketplace'
                         else 'car' end;
  return old;
end;
$$;

drop trigger if exists eedb_properties_history_cleanup on public.properties;
create trigger eedb_properties_history_cleanup
after delete on public.properties
for each row execute function public.eedb_cleanup_status_history();

drop trigger if exists eedb_marketplace_history_cleanup on public.marketplace_items;
create trigger eedb_marketplace_history_cleanup
after delete on public.marketplace_items
for each row execute function public.eedb_cleanup_status_history();

drop trigger if exists eedb_cars_history_cleanup on public.cars;
create trigger eedb_cars_history_cleanup
after delete on public.cars
for each row execute function public.eedb_cleanup_status_history();

-- ---------------------------------------------------------------------
-- 2. One-time cleanup of orphan history rows (listing already deleted)
-- ---------------------------------------------------------------------
delete from public.post_status_history h
 where (h.entity_type = 'property'    and not exists (select 1 from public.properties p     where p.id = h.entity_id))
    or (h.entity_type = 'marketplace' and not exists (select 1 from public.marketplace_items m where m.id = h.entity_id))
    or (h.entity_type = 'car'         and not exists (select 1 from public.cars c            where c.id = h.entity_id));

-- ---------------------------------------------------------------------
-- 3. Daily report: count Sold/Rented only for listings that still exist
-- ---------------------------------------------------------------------
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
  if not public.eedb_is_super_admin() then
    raise exception 'Only Super Admin can view reports';
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

commit;
