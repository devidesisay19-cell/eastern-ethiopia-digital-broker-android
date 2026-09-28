-- =====================================================================
-- Eastern Ethiopia Digital Broker  -  FINAL SQL (v4)   Run ONCE, safe to re-run.
-- Supabase > SQL Editor > paste whole file > Run.
--
-- v4 ADDS (on top of v3 listing RLS + storage fix below):
--  1. Super Admin can change any user's role (RPC eedb_set_user_role) and
--     assign City Admins (RPC eedb_assign_city_admin).  RLS on profiles and
--     admin_city_assignments; a trigger stops anyone else from changing role.
--  2. Automatic post_status_history trigger on properties / marketplace_items
--     / cars -> "Sold / Rented" report works no matter who changes the status.
--  3. eedb_daily_report(date): per-city daily counts, Super Admin only.
-- First super admin: run once in SQL editor
--   update public.profiles set role='super_admin' where id='<YOUR-AUTH-UUID>';
-- =====================================================================

begin;

do $$
begin
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
-- v3: drop every existing policy on the listing tables / listing buckets
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select policyname, tablename from pg_policies
           where schemaname='public' and tablename in ('marketplace_items','cars')
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
  for r in select policyname from pg_policies
           where schemaname='storage' and tablename='objects'
             and (coalesce(qual,'') || ' ' || coalesce(with_check,'')) ~ '(marketplace-images|car-images|property-images|job-cvs)'
  loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
  end loop;
end $$;

-- v3: city check that never depends on an unknown function
create or replace function public.eedb_can_manage_city(cid uuid)
returns boolean
language plpgsql stable security definer set search_path=public
as $$
declare r text; ok boolean := false;
begin
  select p.role into r from public.profiles p
   where p.id = auth.uid() and coalesce(p.is_active,true) = true;
  if r is null or r not in ('super_admin','admin','city_admin') then return false; end if;
  if r = 'super_admin' then return true; end if;
  if to_regprocedure('public.can_manage_city(uuid)') is not null then
    begin
      execute 'select public.can_manage_city($1)' into ok using cid;
    exception when others then ok := false;
    end;
    if coalesce(ok,false) then return true; end if;
  end if;
  if cid is not null and to_regclass('public.admin_city_assignments') is not null then
    begin
      execute 'select exists (select 1 from public.admin_city_assignments a where a.admin_id = auth.uid() and a.city_id = $1)'
        into ok using cid;
    exception when others then ok := false;
    end;
    if coalesce(ok,false) then return true; end if;
  end if;
  return false;
end;
$$;

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
      where p.id = pid and public.eedb_can_manage_city(p.city_id)
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
using (public.eedb_is_listing_admin() and public.eedb_can_manage_city(city_id))
with check (public.eedb_is_listing_admin() and public.eedb_can_manage_city(city_id));

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
using (public.eedb_is_listing_admin() and public.eedb_can_manage_city(city_id))
with check (public.eedb_is_listing_admin() and public.eedb_can_manage_city(city_id));

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
  and public.eedb_can_manage_city(city_id)
);

create policy eedb_status_history_admin_read on public.post_status_history
for select to authenticated
using (public.eedb_is_listing_admin() and public.eedb_can_manage_city(city_id));

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
    ))
    or
    (bucket_id = 'car-images' and exists (
      select 1 from public.cars x
      where x.id = public.eedb_safe_uuid((storage.foldername(name))[2])
        and x.seller_id = auth.uid()
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
        and public.eedb_can_manage_city(x.city_id)
    ))
    or
    (bucket_id = 'car-images' and exists (
      select 1 from public.cars x
      where x.id = public.eedb_safe_uuid((storage.foldername(name))[2])
        and public.eedb_can_manage_city(x.city_id)
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


-- =====================================================================
-- v4 PART 1: roles, super-admin powers, city-admin assignments
-- =====================================================================

create or replace function public.eedb_is_super_admin()
returns boolean
language sql stable security definer set search_path=public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role = 'super_admin'
      and coalesce(p.is_active, true) = true
  );
$$;

-- Old CHECK constraints on profiles.role often reject 'city_admin'/'super_admin'.
-- Drop them, then re-add a correct one only if every existing row conforms.
do $$
declare c record;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.profiles'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%role%'
  loop
    execute format('alter table public.profiles drop constraint %I', c.conname);
  end loop;
  if not exists (select 1 from public.profiles
                 where role is null or role not in
                 ('super_admin','admin','city_admin','owner','renter','job_seeker','employer')) then
    alter table public.profiles add constraint profiles_role_check
      check (role in ('super_admin','admin','city_admin','owner','renter','job_seeker','employer'));
  else
    raise notice 'profiles.role has legacy values; role CHECK constraint not re-added. Review profiles.role.';
  end if;
end $$;

-- Nobody except a Super Admin (or the SQL editor) can change role / is_active,
-- and public sign-up can only create the 4 self-service roles.
create or replace function public.eedb_guard_profile()
returns trigger
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or public.eedb_is_super_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.role is null or new.role not in ('owner','renter','job_seeker','employer') then
      raise exception 'This account type cannot be created from sign-up';
    end if;
    new.is_active := true;
    return new;
  end if;
  if new.role is distinct from old.role then
    raise exception 'Only Super Admin can change roles';
  end if;
  if new.is_active is distinct from old.is_active then
    raise exception 'Only Super Admin can activate or deactivate accounts';
  end if;
  return new;
end;
$$;

drop trigger if exists eedb_profiles_guard on public.profiles;
create trigger eedb_profiles_guard
before insert or update on public.profiles
for each row execute function public.eedb_guard_profile();

-- ADDITIVE policies on profiles (existing read policies used by other pages stay).
drop policy if exists eedb_profiles_super_admin_all on public.profiles;
create policy eedb_profiles_super_admin_all on public.profiles
for all to authenticated
using (public.eedb_is_super_admin())
with check (public.eedb_is_super_admin());

drop policy if exists eedb_profiles_admin_read on public.profiles;
create policy eedb_profiles_admin_read on public.profiles
for select to authenticated
using (public.eedb_is_listing_admin());

drop policy if exists eedb_profiles_self_read on public.profiles;
create policy eedb_profiles_self_read on public.profiles
for select to authenticated using (id = auth.uid());

drop policy if exists eedb_profiles_self_insert on public.profiles;
create policy eedb_profiles_self_insert on public.profiles
for insert to authenticated with check (id = auth.uid());

drop policy if exists eedb_profiles_self_update on public.profiles;
create policy eedb_profiles_self_update on public.profiles
for update to authenticated
using (id = auth.uid()) with check (id = auth.uid());

-- admin_city_assignments
create table if not exists public.admin_city_assignments (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references auth.users(id) on delete cascade,
  city_id uuid not null,
  created_at timestamptz not null default now()
);
alter table public.admin_city_assignments
  add column if not exists created_at timestamptz not null default now();

delete from public.admin_city_assignments a
using public.admin_city_assignments b
where a.admin_id = b.admin_id and a.city_id = b.city_id and a.ctid > b.ctid;

create unique index if not exists admin_city_assignments_uniq
  on public.admin_city_assignments(admin_id, city_id);

alter table public.admin_city_assignments enable row level security;

do $$
declare r record;
begin
  for r in select policyname from pg_policies
           where schemaname='public' and tablename='admin_city_assignments'
  loop
    execute format('drop policy if exists %I on public.admin_city_assignments', r.policyname);
  end loop;
end $$;

-- job-details.html shows the city admin's contact, so any signed-in user may read.
create policy eedb_assignments_read on public.admin_city_assignments
for select to authenticated using (true);

create policy eedb_assignments_super_admin_write on public.admin_city_assignments
for all to authenticated
using (public.eedb_is_super_admin())
with check (public.eedb_is_super_admin());

-- Super Admin actions as RPCs (no silent "0 rows updated" under RLS).
create or replace function public.eedb_set_user_role(target uuid, new_role text)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if not public.eedb_is_super_admin() then
    raise exception 'Only Super Admin can change roles';
  end if;
  if target is null or target = auth.uid() then
    raise exception 'You cannot change your own role';
  end if;
  if new_role is null or new_role not in
     ('super_admin','admin','city_admin','owner','renter','job_seeker','employer') then
    raise exception 'Invalid role: %', new_role;
  end if;
  update public.profiles set role = new_role where id = target;
  if not found then raise exception 'User not found'; end if;
  if new_role <> 'city_admin' then
    delete from public.admin_city_assignments where admin_id = target;
  end if;
end;
$$;

create or replace function public.eedb_assign_city_admin(target uuid, city uuid)
returns void
language plpgsql security definer set search_path=public
as $$
declare cur text;
begin
  if not public.eedb_is_super_admin() then
    raise exception 'Only Super Admin can assign city admins';
  end if;
  select role into cur from public.profiles where id = target;
  if cur is null then raise exception 'User not found'; end if;
  if cur = 'super_admin' then raise exception 'Super Admin does not need a city assignment'; end if;
  if not exists (select 1 from public.locations where id = city) then
    raise exception 'City not found';
  end if;
  update public.profiles set role = 'city_admin' where id = target;
  insert into public.admin_city_assignments(admin_id, city_id)
  values (target, city) on conflict (admin_id, city_id) do nothing;
end;
$$;

revoke all on function public.eedb_set_user_role(uuid,text) from public, anon;
revoke all on function public.eedb_assign_city_admin(uuid,uuid) from public, anon;
grant execute on function public.eedb_set_user_role(uuid,text) to authenticated;
grant execute on function public.eedb_assign_city_admin(uuid,uuid) to authenticated;

-- =====================================================================
-- v4 PART 2: automatic status history (feeds the Sold / Rented report)
-- =====================================================================
alter table public.post_status_history
  add column if not exists city_id uuid,
  add column if not exists old_status text,
  add column if not exists changed_by uuid,
  add column if not exists created_at timestamptz not null default now();

create index if not exists post_status_history_report_idx
  on public.post_status_history(created_at, new_status, entity_type);

create or replace function public.eedb_log_status_change()
returns trigger
language plpgsql security definer set search_path=public
as $$
declare et text;
begin
  if new.status is distinct from old.status then
    et := case tg_table_name
            when 'properties' then 'property'
            when 'marketplace_items' then 'marketplace'
            else 'car' end;
    insert into public.post_status_history
      (entity_type, entity_id, city_id, old_status, new_status, changed_by)
    values (et, new.id, new.city_id, old.status, new.status, auth.uid());
  end if;
  return new;
end;
$$;

drop trigger if exists eedb_properties_status_history on public.properties;
create trigger eedb_properties_status_history
after update on public.properties
for each row execute function public.eedb_log_status_change();

drop trigger if exists eedb_marketplace_status_history on public.marketplace_items;
create trigger eedb_marketplace_status_history
after update on public.marketplace_items
for each row execute function public.eedb_log_status_change();

drop trigger if exists eedb_cars_status_history on public.cars;
create trigger eedb_cars_status_history
after update on public.cars
for each row execute function public.eedb_log_status_change();

-- =====================================================================
-- v4 PART 3: Super Admin daily report  (Reports -> Date -> City)
-- Day boundaries use Africa/Addis_Ababa. Counts are aggregates, so there is
-- no row limit (100+ posts in a city are all counted).
-- =====================================================================
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
               and x.entity_type in ('property','marketplace','car')) h
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
