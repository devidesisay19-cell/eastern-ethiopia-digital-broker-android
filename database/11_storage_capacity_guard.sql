-- =====================================================================
-- 11: Storage capacity guard.
--     When storage usage reaches the configured limit:
--       * new photo uploads are refused (storage.objects insert)
--       * listings cannot be moved to 'published' (approve / publish)
--     Super Admin can see the usage and change the limit.
--
-- Limit default: 900 MB (Supabase Free storage is 1 GB; keep a margin).
-- Change it with:  update public.eedb_settings set value='<bytes>' where key='storage_limit_bytes';
-- Run once in the Supabase SQL editor. Safe to re-run.
-- =====================================================================
begin;

create table if not exists public.eedb_settings (
  key   text primary key,
  value text not null
);
alter table public.eedb_settings enable row level security;  -- no policies: only security definer functions read it

insert into public.eedb_settings (key, value)
values ('storage_limit_bytes', '900000000')
on conflict (key) do nothing;

-- Current usage of all storage buckets, in bytes
create or replace function public.eedb_storage_used_bytes()
returns bigint
language sql stable security definer set search_path=public, storage
as $$
  select coalesce(sum((metadata->>'size')::bigint), 0)::bigint from storage.objects;
$$;

create or replace function public.eedb_storage_limit_bytes()
returns bigint
language sql stable security definer set search_path=public
as $$
  select coalesce((select value::bigint from public.eedb_settings where key='storage_limit_bytes'), 900000000);
$$;

-- Super Admin / Investor dashboard figures
create or replace function public.eedb_storage_status()
returns json
language plpgsql stable security definer set search_path=public, storage
as $$
declare used bigint; lim bigint;
begin
  if not (public.eedb_is_super_admin() or public.eedb_is_investor()) then
    raise exception 'Only Super Admin or Investor can view storage status';
  end if;
  used := public.eedb_storage_used_bytes();
  lim  := public.eedb_storage_limit_bytes();
  return json_build_object(
    'used_bytes', used,
    'limit_bytes', lim,
    'percent', round(100.0 * used / nullif(lim,0), 1),
    'full', used >= lim
  );
end;
$$;
revoke all on function public.eedb_storage_status() from public, anon;
grant execute on function public.eedb_storage_status() to authenticated;

-- 1) Block photo uploads when storage is full
create or replace function public.eedb_block_upload_when_full()
returns trigger
language plpgsql security definer set search_path=public, storage
as $$
declare added bigint;
begin
  added := coalesce((new.metadata->>'size')::bigint, 0);
  if public.eedb_storage_used_bytes() + added > public.eedb_storage_limit_bytes() then
    raise exception 'Storage is full. Photo upload is not possible right now. Please contact the Super Admin.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists eedb_storage_full_guard on storage.objects;
create trigger eedb_storage_full_guard
before insert on storage.objects
for each row execute function public.eedb_block_upload_when_full();

-- 2) Block publishing a listing when storage is full
create or replace function public.eedb_block_publish_when_full()
returns trigger
language plpgsql security definer set search_path=public
as $$
begin
  if new.status = 'published' and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    if public.eedb_storage_used_bytes() >= public.eedb_storage_limit_bytes() then
      raise exception 'Storage is full. Listings cannot be published right now. Please contact the Super Admin.'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists eedb_properties_publish_guard on public.properties;
create trigger eedb_properties_publish_guard before insert or update on public.properties
for each row execute function public.eedb_block_publish_when_full();

drop trigger if exists eedb_marketplace_publish_guard on public.marketplace_items;
create trigger eedb_marketplace_publish_guard before insert or update on public.marketplace_items
for each row execute function public.eedb_block_publish_when_full();

drop trigger if exists eedb_cars_publish_guard on public.cars;
create trigger eedb_cars_publish_guard before insert or update on public.cars
for each row execute function public.eedb_block_publish_when_full();

drop trigger if exists eedb_jobs_publish_guard on public.jobs;
create trigger eedb_jobs_publish_guard before insert or update on public.jobs
for each row execute function public.eedb_block_publish_when_full();

commit;
