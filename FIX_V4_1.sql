-- =====================================================================
-- FIX V4.1  (run once in Supabase SQL Editor)
-- 1) "function jsonb_typeof(text[]) does not exist"  -> photo_urls was text[]
-- 2) 'violates check constraint "cars_condition_check"'
-- =====================================================================

-- 1) Make photo_urls jsonb on both tables (drops/recreates photo triggers)
do $$
declare t text;
begin
  foreach t in array array['cars','marketplace_items'] loop
    if (select data_type from information_schema.columns
        where table_schema='public' and table_name=t and column_name='photo_urls') = 'ARRAY' then
      execute format('drop trigger if exists %I_photo_limit on public.%I', t, t);
      execute format('alter table public.%I alter column photo_urls drop default', t);
      execute format('alter table public.%I alter column photo_urls type jsonb using to_jsonb(photo_urls)', t);
      execute format('alter table public.%I alter column photo_urls set default %L::jsonb', t, '[]');
    end if;
  end loop;
end $$;

-- Type-safe trigger function
create or replace function public.eedb_limit_listing_photos()
returns trigger language plpgsql as $$
begin
  if new.photo_urls is null then
    new.photo_urls := '[]'::jsonb;
  end if;
  if jsonb_typeof(to_jsonb(new.photo_urls)) <> 'array'
     or jsonb_array_length(to_jsonb(new.photo_urls)) > 5 then
    raise exception 'A listing can contain at most 5 photo URLs';
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists marketplace_items_photo_limit on public.marketplace_items;
create trigger marketplace_items_photo_limit before insert or update on public.marketplace_items
for each row execute function public.eedb_limit_listing_photos();
drop trigger if exists cars_photo_limit on public.cars;
create trigger cars_photo_limit before insert or update on public.cars
for each row execute function public.eedb_limit_listing_photos();

-- 2) Replace old condition check constraints with one that accepts the app's values
do $$
declare r record;
begin
  for r in
    select conrelid::regclass as tbl, conname
    from pg_constraint
    where contype='c'
      and conrelid in ('public.cars'::regclass,'public.marketplace_items'::regclass)
      and pg_get_constraintdef(oid) ilike '%condition%'
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
  end loop;
end $$;

-- Normalise old capitalised values, then add permissive constraint
update public.cars set condition = case lower(condition) when 'like new' then 'excellent' else lower(condition) end;
update public.marketplace_items set condition = case lower(condition) when 'like new' then 'excellent' else lower(condition) end;

alter table public.cars add constraint cars_condition_check
  check (condition in ('new','used','excellent','good','fair'));
alter table public.marketplace_items add constraint marketplace_items_condition_check
  check (condition in ('new','used','excellent','good','fair'));
