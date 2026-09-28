-- =====================================================================
-- Eastern Ethiopia Digital Broker  -  SINGLE SCRIPT (v2, matched to app code)
-- Run ONCE in Supabase > SQL Editor.  Safe to re-run.
--
-- FIXES vs previous version
--  1. Storage upload paths: app uses  user-id/item-id/file  (2 folders).
--     Old policy demanded 3 folders -> every car/marketplace photo upload
--     was rejected. Fixed.
--  2. Public read = status 'published' only (what index.html shows).
--     Old policy also exposed 'approved'/'active' rows through the API.
--  3. Owners could self-publish through the API. Trigger now locks status:
--     owners -> only pending_review/hidden/sold/rented; admins -> anything.
--  4. property-images policies added (owner: uid/propertyId/file,
--     admin: propertyId/file) - both paths the app really uses.
--  5. job-cvs private bucket + policies added (upload own, employer signed
--     URL for own jobs' applicants, delete own).
--  6. post_status_history table + policies (admin dashboard inserts to it).
--
-- NOT touched: public.can_manage_city(uuid) and existing table policies of
-- properties / jobs / job_applications / profiles / locations etc.
-- The audit query at the bottom shows their live state.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.can_manage_city(uuid)') is null then
    raise exception 'public.can_manage_city(uuid) is missing - create it first';
  end if;
  if to_regclass('public.profiles') is null
     or to_regclass('public.properties') is null
     or to_regclass('public.jobs') is null
     or to_regclass('public.job_applications') is null then
    raise exception 'profiles / properties / jobs / job_applications must already exist';
  end if;
end $$;

create extension if not exists pgcrypto;

alter table public.profiles
  add column if not exists is_active boolean not null default true;

create table if not exists public.marketplace_items (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  posted_by uuid references auth.users(id) on delete set null,
  title text not null,
  description text,
  category text not null,
  condition text not null,
  listing_type text not null default 'sell',
  price numeric(14,2) not null default 0,
  price_unit text not null default 'total',
  region_id uuid,
  zone_id uuid,
  city_id uuid,
  woreda_id uuid,
  area_id uuid,
  contact_phone text,
  photo_urls jsonb not null default '[]'::jsonb,
  status text not null default 'pending_review',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.cars (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  posted_by uuid references auth.users(id) on delete set null,
  title text not null,
  description text,
  brand text,
  model text,
  year integer,
  mileage numeric(14,2),
  transmission text,
  fuel_type text,
  color text,
  condition text not null,
  listing_type text not null default 'sell',
  price numeric(14,2) not null default 0,
  price_unit text not null default 'total',
  region_id uuid,
  zone_id uuid,
  city_id uuid,
  woreda_id uuid,
  area_id uuid,
  contact_phone text,
  photo_urls jsonb not null default '[]'::jsonb,
  status text not null default 'pending_review',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Bring an existing compatible table up to the fields used by the app.
alter table public.marketplace_items
  add column if not exists seller_id uuid,
  add column if not exists posted_by uuid,
  add column if not exists title text,
  add column if not exists description text,
  add column if not exists category text,
  add column if not exists condition text,
  add column if not exists listing_type text default 'sell',
  add column if not exists price numeric(14,2) default 0,
  add column if not exists price_unit text default 'total',
  add column if not exists region_id uuid,
  add column if not exists zone_id uuid,
  add column if not exists city_id uuid,
  add column if not exists woreda_id uuid,
  add column if not exists area_id uuid,
  add column if not exists contact_phone text,
  add column if not exists photo_urls jsonb default '[]'::jsonb,
  add column if not exists status text default 'pending_review',
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

alter table public.cars
  add column if not exists seller_id uuid,
  add column if not exists posted_by uuid,
  add column if not exists title text,
  add column if not exists description text,
  add column if not exists brand text,
  add column if not exists model text,
  add column if not exists year integer,
  add column if not exists mileage numeric(14,2),
  add column if not exists transmission text,
  add column if not exists fuel_type text,
  add column if not exists color text,
  add column if not exists condition text,
  add column if not exists listing_type text default 'sell',
  add column if not exists price numeric(14,2) default 0,
  add column if not exists price_unit text default 'total',
  add column if not exists region_id uuid,
  add column if not exists zone_id uuid,
  add column if not exists city_id uuid,
  add column if not exists woreda_id uuid,
  add column if not exists area_id uuid,
  add column if not exists contact_phone text,
  add column if not exists photo_urls jsonb default '[]'::jsonb,
  add column if not exists status text default 'pending_review',
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

create index if not exists marketplace_items_status_created_idx
  on public.marketplace_items(status, created_at desc);
create index if not exists marketplace_items_city_idx
  on public.marketplace_items(city_id);
create index if not exists marketplace_items_seller_idx
  on public.marketplace_items(seller_id);
create index if not exists cars_status_created_idx
  on public.cars(status, created_at desc);
create index if not exists cars_city_idx on public.cars(city_id);
create index if not exists cars_seller_idx on public.cars(seller_id);


-- ---------------------------------------------------------------------
-- Helper functions
-- ---------------------------------------------------------------------
create or replace function public.eedb_is_listing_admin()
returns boolean
language sql stable security definer set search_path=public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role in ('super_admin','admin','city_admin')
      and coalesce(p.is_active, true) = true
  );
$$;

create or replace function public.eedb_safe_uuid(value text)
returns uuid
language plpgsql immutable
as $$
begin
  if value is null or value !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  return value::uuid;
exception when others then
  return null;
end;
$$;

create or replace function public.eedb_owns_property(pid uuid)
returns boolean
language sql stable security definer set search_path=public
as $$
  select pid is not null and exists (
    select 1 from public.properties p
    where p.id = pid and p.owner_id = auth.uid()
  );
$$;

create or replace function public.eedb_admin_can_manage_property(pid uuid)
returns boolean
language sql stable security definer set search_path=public
as $$
  select pid is not null
    and public.eedb_is_listing_admin()
    and exists (
      select 1 from public.properties p
      where p.id = pid and public.can_manage_city(p.city_id)
    );
$$;

create or replace function public.eedb_employer_can_read_cv(cv_path text)
returns boolean
language sql stable security definer set search_path=public
as $$
  select cv_path is not null and exists (
    select 1
    from public.job_applications a
    join public.jobs j on j.id = a.job_id
    where a.cv_url = cv_path
      and j.employer_id = auth.uid()
  );
$$;

create or replace function public.eedb_limit_listing_photos()
returns trigger
language plpgsql
as $$
begin
  if new.photo_urls is null then
    new.photo_urls := '[]'::jsonb;
  end if;
  if jsonb_typeof(new.photo_urls) <> 'array'
     or jsonb_array_length(new.photo_urls) > 5 then
    raise exception 'A listing can contain at most 5 photo URLs';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Owners cannot approve/publish their own listings through the API.
create or replace function public.eedb_lock_listing_status()
returns trigger
language plpgsql
as $$
begin
  -- SQL editor / service role (no JWT user) and admins are unrestricted.
  if auth.uid() is null or public.eedb_is_listing_admin() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.status := 'pending_review';
    return new;
  end if;

  if new.seller_id is distinct from old.seller_id then
    raise exception 'seller_id cannot be changed';
  end if;

  if new.status is distinct from old.status
     and new.status not in ('pending_review','hidden','sold','rented') then
    raise exception 'Only an admin can set status to %', new.status;
  end if;
  return new;
end;
$$;

drop trigger if exists marketplace_items_photo_limit on public.marketplace_items;
create trigger marketplace_items_photo_limit
before insert or update on public.marketplace_items
for each row execute function public.eedb_limit_listing_photos();

drop trigger if exists cars_photo_limit on public.cars;
create trigger cars_photo_limit
before insert or update on public.cars
for each row execute function public.eedb_limit_listing_photos();

drop trigger if exists marketplace_items_status_lock on public.marketplace_items;
create trigger marketplace_items_status_lock
before insert or update on public.marketplace_items
for each row execute function public.eedb_lock_listing_status();

drop trigger if exists cars_status_lock on public.cars;
create trigger cars_status_lock
before insert or update on public.cars
for each row execute function public.eedb_lock_listing_status();

-- ---------------------------------------------------------------------
-- Table RLS: marketplace_items + cars
-- ---------------------------------------------------------------------
alter table public.marketplace_items enable row level security;
alter table public.cars enable row level security;

drop policy if exists marketplace_public_read on public.marketplace_items;
drop policy if exists marketplace_owner_read on public.marketplace_items;
drop policy if exists marketplace_owner_insert on public.marketplace_items;
drop policy if exists marketplace_owner_update on public.marketplace_items;
drop policy if exists marketplace_owner_delete on public.marketplace_items;
drop policy if exists marketplace_admin_all on public.marketplace_items;

create policy marketplace_public_read on public.marketplace_items
for select to anon, authenticated
using (status = 'published');

create policy marketplace_owner_read on public.marketplace_items
for select to authenticated
using (seller_id = auth.uid());

create policy marketplace_owner_insert on public.marketplace_items
for insert to authenticated
with check (seller_id = auth.uid() and posted_by = auth.uid());

create policy marketplace_owner_update on public.marketplace_items
for update to authenticated
using (seller_id = auth.uid())
with check (seller_id = auth.uid());

create policy marketplace_owner_delete on public.marketplace_items
for delete to authenticated
using (seller_id = auth.uid());

create policy marketplace_admin_all on public.marketplace_items
for all to authenticated
using (public.eedb_is_listing_admin() and public.can_manage_city(city_id))
with check (public.eedb_is_listing_admin() and public.can_manage_city(city_id));

drop policy if exists cars_public_read on public.cars;
drop policy if exists cars_owner_read on public.cars;
drop policy if exists cars_owner_insert on public.cars;
drop policy if exists cars_owner_update on public.cars;
drop policy if exists cars_owner_delete on public.cars;
drop policy if exists cars_admin_all on public.cars;

create policy cars_public_read on public.cars
for select to anon, authenticated
using (status = 'published');

create policy cars_owner_read on public.cars
for select to authenticated
using (seller_id = auth.uid());

create policy cars_owner_insert on public.cars
for insert to authenticated
with check (seller_id = auth.uid() and posted_by = auth.uid());

create policy cars_owner_update on public.cars
for update to authenticated
using (seller_id = auth.uid())
with check (seller_id = auth.uid());

create policy cars_owner_delete on public.cars
for delete to authenticated
using (seller_id = auth.uid());

create policy cars_admin_all on public.cars
for all to authenticated
using (public.eedb_is_listing_admin() and public.can_manage_city(city_id))
with check (public.eedb_is_listing_admin() and public.can_manage_city(city_id));

-- ---------------------------------------------------------------------
-- post_status_history (admin-dashboard inserts into it)
-- ---------------------------------------------------------------------
create table if not exists public.post_status_history (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  city_id uuid,
  old_status text,
  new_status text not null,
  changed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.post_status_history enable row level security;

drop policy if exists eedb_status_history_admin_insert on public.post_status_history;
drop policy if exists eedb_status_history_admin_read on public.post_status_history;

create policy eedb_status_history_admin_insert on public.post_status_history
for insert to authenticated
with check (
  public.eedb_is_listing_admin()
  and changed_by = auth.uid()
  and public.can_manage_city(city_id)
);

create policy eedb_status_history_admin_read on public.post_status_history
for select to authenticated
using (public.eedb_is_listing_admin() and public.can_manage_city(city_id));

-- ---------------------------------------------------------------------
-- Storage buckets (names exactly as used in the app code)
--   property-images   public   uid/propertyId/file  OR  propertyId/file
--   marketplace-images public  uid/itemId/file
--   car-images        public   uid/carId/file
--   job-cvs           PRIVATE  uid/file  (signed URLs, 300 s)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values
  ('property-images',    'property-images',    true),
  ('marketplace-images', 'marketplace-images', true),
  ('car-images',         'car-images',         true),
  ('job-cvs',            'job-cvs',            false)
on conflict (id) do update set public = excluded.public;

drop policy if exists eedb_listing_images_public_read   on storage.objects;
drop policy if exists eedb_listing_images_owner_insert  on storage.objects;
drop policy if exists eedb_listing_images_owner_update  on storage.objects;
drop policy if exists eedb_listing_images_owner_delete  on storage.objects;
drop policy if exists eedb_listing_images_admin_insert  on storage.objects;
drop policy if exists eedb_listing_images_admin_update  on storage.objects;
drop policy if exists eedb_listing_images_admin_delete  on storage.objects;
drop policy if exists eedb_property_images_owner_insert on storage.objects;
drop policy if exists eedb_property_images_owner_delete on storage.objects;
drop policy if exists eedb_property_images_admin_insert on storage.objects;
drop policy if exists eedb_property_images_admin_delete on storage.objects;
drop policy if exists eedb_job_cvs_owner_insert         on storage.objects;
drop policy if exists eedb_job_cvs_read                 on storage.objects;
drop policy if exists eedb_job_cvs_owner_delete         on storage.objects;

-- Public buckets: read
create policy eedb_listing_images_public_read on storage.objects
for select to anon, authenticated
using (bucket_id in ('marketplace-images','car-images','property-images'));

-- marketplace-images / car-images : owner (path = uid/itemId/file -> 2 folders)
create policy eedb_listing_images_owner_insert on storage.objects
for insert to authenticated
with check (
  bucket_id in ('marketplace-images','car-images')
  and array_length(storage.foldername(name), 1) = 2
  and (storage.foldername(name))[1] = auth.uid()::text
  and (
    (bucket_id = 'marketplace-images' and exists (
      select 1 from public.marketplace_items x
      where x.id = public.eedb_safe_uuid((storage.foldername(name))[2])
        and x.seller_id = auth.uid()
        and jsonb_array_length(coalesce(x.photo_urls, '[]'::jsonb)) < 5
    ))
    or
    (bucket_id = 'car-images' and exists (
      select 1 from public.cars x
      where x.id = public.eedb_safe_uuid((storage.foldername(name))[2])
        and x.seller_id = auth.uid()
        and jsonb_array_length(coalesce(x.photo_urls, '[]'::jsonb)) < 5
    ))
  )
);

create policy eedb_listing_images_owner_update on storage.objects
for update to authenticated
using (
  bucket_id in ('marketplace-images','car-images')
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id in ('marketplace-images','car-images')
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy eedb_listing_images_owner_delete on storage.objects
for delete to authenticated
using (
  bucket_id in ('marketplace-images','car-images')
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- marketplace-images / car-images : admin (city-scoped, same path rule)
create policy eedb_listing_images_admin_insert on storage.objects
for insert to authenticated
with check (
  bucket_id in ('marketplace-images','car-images')
  and public.eedb_is_listing_admin()
  and array_length(storage.foldername(name), 1) = 2
  and (
    (bucket_id = 'marketplace-images' and exists (
      select 1 from public.marketplace_items x
      where x.id = public.eedb_safe_uuid((storage.foldername(name))[2])
        and public.can_manage_city(x.city_id)
        and jsonb_array_length(coalesce(x.photo_urls, '[]'::jsonb)) < 5
    ))
    or
    (bucket_id = 'car-images' and exists (
      select 1 from public.cars x
      where x.id = public.eedb_safe_uuid((storage.foldername(name))[2])
        and public.can_manage_city(x.city_id)
        and jsonb_array_length(coalesce(x.photo_urls, '[]'::jsonb)) < 5
    ))
  )
);

create policy eedb_listing_images_admin_update on storage.objects
for update to authenticated
using (
  bucket_id in ('marketplace-images','car-images')
  and public.eedb_is_listing_admin()
)
with check (
  bucket_id in ('marketplace-images','car-images')
  and public.eedb_is_listing_admin()
);

create policy eedb_listing_images_admin_delete on storage.objects
for delete to authenticated
using (
  bucket_id in ('marketplace-images','car-images')
  and public.eedb_is_listing_admin()
);

-- property-images : owner  (uid/propertyId/file)
create policy eedb_property_images_owner_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'property-images'
  and array_length(storage.foldername(name), 1) = 2
  and (storage.foldername(name))[1] = auth.uid()::text
  and public.eedb_owns_property(public.eedb_safe_uuid((storage.foldername(name))[2]))
);

-- owner delete: own uid folder, or admin-uploaded propertyId/file of own property
create policy eedb_property_images_owner_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'property-images'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.eedb_owns_property(public.eedb_safe_uuid((storage.foldername(name))[1]))
  )
);

-- property-images : admin  (propertyId/file  or  uid/propertyId/file)
create policy eedb_property_images_admin_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'property-images'
  and public.eedb_is_listing_admin()
  and (
    (array_length(storage.foldername(name), 1) = 1
      and public.eedb_admin_can_manage_property(public.eedb_safe_uuid((storage.foldername(name))[1])))
    or
    (array_length(storage.foldername(name), 1) = 2
      and public.eedb_admin_can_manage_property(public.eedb_safe_uuid((storage.foldername(name))[2])))
  )
);

create policy eedb_property_images_admin_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'property-images'
  and public.eedb_is_listing_admin()
  and (
    public.eedb_admin_can_manage_property(public.eedb_safe_uuid((storage.foldername(name))[1]))
    or public.eedb_admin_can_manage_property(public.eedb_safe_uuid((storage.foldername(name))[2]))
  )
);

-- job-cvs (private): applicant uploads/deletes own file; applicant or the
-- job's employer can read (createSignedUrl needs SELECT).
create policy eedb_job_cvs_owner_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'job-cvs'
  and array_length(storage.foldername(name), 1) = 1
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy eedb_job_cvs_read on storage.objects
for select to authenticated
using (
  bucket_id = 'job-cvs'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.eedb_employer_can_read_cv(name)
  )
);

create policy eedb_job_cvs_owner_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'job-cvs'
  and (storage.foldername(name))[1] = auth.uid()::text
);

commit;

-- =====================================================================
-- AUDIT (one result table). Look for:  RLS OFF  /  policies=0  /  MISSING
-- and any job-cvs bucket with public=true.
-- =====================================================================
select 'table_rls' as check_type, c.relname::text as item,
       (case when c.relrowsecurity then 'RLS ON' else 'RLS OFF  <-- FIX' end)
       || ', policies=' ||
       (select count(*) from pg_policies p
         where p.schemaname = 'public' and p.tablename = c.relname)::text as result
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
  and c.relname in ('profiles','jobs','properties','property_images','locations',
                    'marketplace_items','cars','job_applications','job_saved',
                    'job_notifications','admin_city_assignments','post_status_history')
union all
select 'bucket', id::text, 'public=' || public::text
from storage.buckets
where id in ('property-images','marketplace-images','car-images','job-cvs')
union all
select 'storage_policy', policyname::text, cmd::text
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
union all
select 'function', 'can_manage_city(uuid)',
       case when to_regprocedure('public.can_manage_city(uuid)') is null
            then 'MISSING' else 'ok' end
union all
select 'table_missing', t.name, 'MISSING <-- app uses it'
from (values ('profiles'),('jobs'),('properties'),('property_images'),('locations'),
             ('marketplace_items'),('cars'),('job_applications'),('job_saved'),
             ('job_notifications'),('admin_city_assignments'),('post_status_history')) as t(name)
where to_regclass('public.' || t.name) is null
order by 1, 2;
