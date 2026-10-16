-- =====================================================================
-- FIX V4.2  (run once in Supabase SQL Editor, after SUPABASE_FINAL_V4.sql
--            and FIX_V4_1.sql)
--
--  1) new row for relation "marketplace_items" violates check constraint
--     "marketplace_category_check"
--     -> an OLD check constraint (from an earlier table version) only allows
--        a fixed list of category values. The app now sends:
--        Phone, TV, Fridge, Sofa, Furniture, Laptop, Household Equipment,
--        Work Equipment, Other.
--  2) Same protection for other old check constraints on cars / marketplace
--     (category, listing_type, status, price_unit, transmission, fuel_type).
-- =====================================================================

-- 1) Drop every OLD check constraint on these columns
do $$
declare r record;
begin
  for r in
    select conrelid::regclass as tbl, conname, pg_get_constraintdef(oid) as def
    from pg_constraint
    where contype = 'c'
      and conrelid in ('public.marketplace_items'::regclass, 'public.cars'::regclass)
      and (
           pg_get_constraintdef(oid) ~* '\mcategory\M'
        or pg_get_constraintdef(oid) ~* '\mlisting_type\M'
        or pg_get_constraintdef(oid) ~* '\mstatus\M'
        or pg_get_constraintdef(oid) ~* '\mprice_unit\M'
        or pg_get_constraintdef(oid) ~* '\mtransmission\M'
        or pg_get_constraintdef(oid) ~* '\mfuel_type\M'
      )
  loop
    raise notice 'Dropping % on %: %', r.conname, r.tbl, r.def;
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
  end loop;
end $$;

-- 2) Normalise legacy values
update public.marketplace_items set listing_type = 'sell' where lower(listing_type) in ('sale','sold');
update public.cars              set listing_type = 'sell' where lower(listing_type) in ('sale','sold');
update public.marketplace_items set listing_type = lower(listing_type);
update public.cars              set listing_type = lower(listing_type);

-- 3) Add permissive constraints that match what the app really sends
--    (NOT VALID = do not re-check old rows, only new/edited rows)
alter table public.marketplace_items
  add constraint marketplace_category_check
  check (length(btrim(category)) > 0) not valid;

alter table public.marketplace_items
  add constraint marketplace_listing_type_check
  check (listing_type in ('sell','rent')) not valid;

alter table public.cars
  add constraint cars_listing_type_check
  check (listing_type in ('sell','rent')) not valid;

alter table public.marketplace_items
  add constraint marketplace_status_check
  check (status in ('pending_review','approved','published','sold','rented','hidden','rejected')) not valid;

alter table public.cars
  add constraint cars_status_check
  check (status in ('pending_review','approved','published','sold','rented','hidden','rejected')) not valid;

-- 4) Public contact function for Marketplace / Car detail pages:
--    returns the City Admin(s) assigned to the item's city and the
--    Super Admin(s), with name + phone only (no other profile data).
create or replace function public.get_listing_contacts(p_city_id uuid)
returns table(role text, full_name text, phone text)
language sql
stable
security definer
set search_path = public
as $$
  select 'city_admin'::text, coalesce(p.full_name, 'City Admin'), p.phone
  from public.admin_city_assignments a
  join public.profiles p on p.id = a.admin_id
  where a.city_id = p_city_id
    and lower(coalesce(p.role,'')) in ('city_admin','admin')
    and coalesce(p.is_active, true)
    and coalesce(p.phone,'') <> ''
  union all
  select 'super_admin'::text, coalesce(p.full_name, 'Super Admin'), p.phone
  from public.profiles p
  where lower(coalesce(p.role,'')) = 'super_admin'
    and coalesce(p.is_active, true)
    and coalesce(p.phone,'') <> '';
$$;

revoke all on function public.get_listing_contacts(uuid) from public;
grant execute on function public.get_listing_contacts(uuid) to anon, authenticated;

-- 5) Audit: constraints that remain on the two tables
select conrelid::regclass as table_name, conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where contype = 'c'
  and conrelid in ('public.marketplace_items'::regclass, 'public.cars'::regclass)
order by 1, 2;
