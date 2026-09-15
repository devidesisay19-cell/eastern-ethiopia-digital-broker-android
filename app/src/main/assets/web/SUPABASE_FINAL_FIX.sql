-- Canonical production database patch. See SUPABASE_PRODUCTION_PATCH.sql.

-- EASTERN ETHIOPIA DIGITAL BROKER
-- Production integration patch for the supplied final application.
-- Safe/conditional: preserves existing rows and does not seed/delete locations.
-- Run once in Supabase SQL Editor before final live testing.

begin;

-- =========================================================
-- 1. ACCOUNT STATUS / ROLE SUPPORT
-- =========================================================
alter table public.profiles
  add column if not exists is_active boolean not null default true;

update public.profiles
set is_active = true
where is_active is null;

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('super_admin','admin','city_admin','owner','renter','job_seeker','employer'));

-- =========================================================
-- 2. ROLE HELPERS
-- =========================================================
create or replace function public.is_super_admin()
returns boolean
language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.profiles p
    where p.id=auth.uid() and p.role='super_admin' and p.is_active=true
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.profiles p
    where p.id=auth.uid()
      and p.role in ('super_admin','admin','city_admin')
      and p.is_active=true
  );
$$;

create or replace function public.is_city_admin()
returns boolean
language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.profiles p
    where p.id=auth.uid() and p.role='city_admin' and p.is_active=true
  );
$$;

create or replace function public.can_manage_city(target_city uuid)
returns boolean
language sql stable security definer set search_path=public as $$
  select target_city is not null and (
    public.is_super_admin()
    or exists(
      select 1 from public.profiles p
      where p.id=auth.uid() and p.role='admin' and p.is_active=true
    )
    or exists(
      select 1 from public.admin_city_assignments a
      where a.admin_id=auth.uid() and a.city_id=target_city
    )
  );
$$;

grant execute on function public.is_super_admin() to anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.is_city_admin() to anon, authenticated;
grant execute on function public.can_manage_city(uuid) to anon, authenticated;

-- =========================================================
-- 3. PROFILES RLS
-- =========================================================
drop policy if exists profiles_self_select on public.profiles;
drop policy if exists profiles_self_insert on public.profiles;
drop policy if exists profiles_super_admin_update on public.profiles;
drop policy if exists public_signup_profile_insert on public.profiles;
drop policy if exists super_admin_update_profiles on public.profiles;

create policy profiles_self_select
on public.profiles for select to authenticated
using (id=auth.uid() or public.is_admin());

create policy profiles_self_insert
on public.profiles for insert to authenticated
with check (
  id=auth.uid()
  and role in ('owner','renter','job_seeker','employer')
);

create policy profiles_super_admin_update
on public.profiles for update to authenticated
using (public.is_super_admin())
with check (
  public.is_super_admin()
  and role in ('super_admin','admin','city_admin','owner','renter','job_seeker','employer')
);

drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update
on public.profiles for update to authenticated
using (id=auth.uid() and is_active=true)
with check (id=auth.uid() and role in ('owner','renter','job_seeker','employer') and is_active=true);

-- =========================================================
-- 4. LOCATIONS RLS
-- =========================================================
-- Public sees active rows; frontend additionally removes rows whose parent chain is inactive.
drop policy if exists locations_active_select on public.locations;
drop policy if exists active_locations_public_read on public.locations;
drop policy if exists locations_super_admin_insert on public.locations;
drop policy if exists locations_super_admin_update on public.locations;
drop policy if exists locations_super_admin_delete on public.locations;

create policy locations_active_select
on public.locations for select to anon, authenticated
using (is_active=true or public.is_admin());

create policy locations_super_admin_insert
on public.locations for insert to authenticated
with check (public.is_super_admin());

create policy locations_super_admin_update
on public.locations for update to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

create policy locations_super_admin_delete
on public.locations for delete to authenticated
using (public.is_super_admin());

-- =========================================================
-- 5. CITY ADMIN ASSIGNMENTS
-- =========================================================
drop policy if exists assignments_super_admin_all on public.admin_city_assignments;
drop policy if exists assignments_city_admin_self_read on public.admin_city_assignments;
drop policy if exists super_admin_manage_city_assignments on public.admin_city_assignments;
drop policy if exists city_admin_read_own_assignment on public.admin_city_assignments;

create policy assignments_super_admin_all
on public.admin_city_assignments for all to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

create policy assignments_city_admin_self_read
on public.admin_city_assignments for select to authenticated
using (admin_id=auth.uid());

-- =========================================================
-- 6. PROPERTIES: PUBLIC STATUS + ADMIN/OWNER ACCESS
-- =========================================================
drop policy if exists properties_public_read on public.properties;
drop policy if exists properties_owner_insert on public.properties;
drop policy if exists properties_owner_update on public.properties;
drop policy if exists properties_owner_delete on public.properties;
drop policy if exists properties_admin_all on public.properties;
drop policy if exists admin_manage_properties_by_city on public.properties;

create policy properties_public_read
on public.properties for select to anon, authenticated
using (
  status in ('approved','published','active')
  or owner_id=auth.uid()
  or public.is_admin()
);

create policy properties_owner_insert
on public.properties for insert to authenticated
with check (owner_id=auth.uid());

create policy properties_owner_update
on public.properties for update to authenticated
using (owner_id=auth.uid())
with check (owner_id=auth.uid());

create policy properties_owner_delete
on public.properties for delete to authenticated
using (owner_id=auth.uid());

create policy properties_admin_all
on public.properties for all to authenticated
using (public.is_admin() and public.can_manage_city(city_id))
with check (public.is_admin() and public.can_manage_city(city_id));

-- =========================================================
-- 7. PROPERTY IMAGES / LEGACY PHOTOS
-- =========================================================
drop policy if exists property_images_public_read on public.property_images;
drop policy if exists property_images_owner_insert on public.property_images;
drop policy if exists property_images_owner_delete on public.property_images;
drop policy if exists property_images_admin_all on public.property_images;

create policy property_images_public_read
on public.property_images for select to anon, authenticated
using (
  exists(
    select 1 from public.properties p
    where p.id=property_id
      and (
        p.status in ('approved','published','active')
        or p.owner_id=auth.uid()
        or public.is_admin()
      )
  )
);

create policy property_images_owner_insert
on public.property_images for insert to authenticated
with check (
  owner_id=auth.uid()
  and exists(select 1 from public.properties p where p.id=property_id and p.owner_id=auth.uid())
);

create policy property_images_owner_delete
on public.property_images for delete to authenticated
using (owner_id=auth.uid());

create policy property_images_admin_all
on public.property_images for all to authenticated
using (
  exists(select 1 from public.properties p where p.id=property_id and public.can_manage_city(p.city_id))
)
with check (
  exists(select 1 from public.properties p where p.id=property_id and public.can_manage_city(p.city_id))
);

drop policy if exists property_photos_public_read on public.property_photos;
drop policy if exists property_photos_owner_manage on public.property_photos;
drop policy if exists property_photos_admin_manage on public.property_photos;

create policy property_photos_public_read
on public.property_photos for select to anon, authenticated
using (
  exists(
    select 1 from public.properties p
    where p.id=property_id
      and (
        p.status in ('approved','published','active')
        or p.owner_id=auth.uid()
        or public.is_admin()
      )
  )
);

create policy property_photos_owner_manage
on public.property_photos for all to authenticated
using (exists(select 1 from public.properties p where p.id=property_id and p.owner_id=auth.uid()))
with check (exists(select 1 from public.properties p where p.id=property_id and p.owner_id=auth.uid()));

create policy property_photos_admin_manage
on public.property_photos for all to authenticated
using (exists(select 1 from public.properties p where p.id=property_id and public.can_manage_city(p.city_id)))
with check (exists(select 1 from public.properties p where p.id=property_id and public.can_manage_city(p.city_id)));

-- =========================================================
-- 8. JOBS: REAL LOCATION COLUMNS ONLY (NO jobs.location COLUMN)
-- =========================================================
drop policy if exists jobs_public_read on public.jobs;
drop policy if exists jobs_employer_insert on public.jobs;
drop policy if exists jobs_employer_update on public.jobs;
drop policy if exists jobs_employer_delete on public.jobs;
drop policy if exists jobs_admin_all on public.jobs;
drop policy if exists admin_manage_jobs_by_city on public.jobs;

create policy jobs_public_read
on public.jobs for select to anon, authenticated
using (
  status='published'
  or employer_id=auth.uid()
  or posted_by=auth.uid()
  or public.is_admin()
);

create policy jobs_employer_insert
on public.jobs for insert to authenticated
with check (
  employer_id=auth.uid()
  and posted_by=auth.uid()
  and posting_method='employer'
);

create policy jobs_employer_update
on public.jobs for update to authenticated
using (employer_id=auth.uid())
with check (employer_id=auth.uid());

create policy jobs_employer_delete
on public.jobs for delete to authenticated
using (employer_id=auth.uid());

create policy jobs_admin_all
on public.jobs for all to authenticated
using (public.is_admin() and public.can_manage_city(city_id))
with check (public.is_admin() and public.can_manage_city(city_id));

-- =========================================================
-- 9. APPLICATION STATUS / EMPLOYER ACCESS
-- =========================================================
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.job_applications'::regclass
      and contype='c'
      and conname='job_applications_status_production_check'
  ) then
    alter table public.job_applications
      add constraint job_applications_status_production_check
      check (status in ('pending','reviewing','shortlisted','accepted','rejected','withdrawn'));
  end if;
exception when duplicate_object then null;
end $$;

drop policy if exists applications_applicant_read on public.job_applications;
drop policy if exists applications_applicant_insert on public.job_applications;
drop policy if exists applications_applicant_update on public.job_applications;
drop policy if exists applications_applicant_delete on public.job_applications;
drop policy if exists applications_admin_update on public.job_applications;
drop policy if exists admin_manage_applications on public.job_applications;
drop policy if exists admin_update_applications on public.job_applications;

create policy applications_applicant_read
on public.job_applications for select to authenticated
using (applicant_id=auth.uid() or public.is_admin());

create policy applications_applicant_insert
on public.job_applications for insert to authenticated
with check (
  applicant_id=auth.uid()
  and exists(select 1 from public.jobs j where j.id=job_id and j.status='published')
);

create policy applications_applicant_update
on public.job_applications for update to authenticated
using (applicant_id=auth.uid())
with check (applicant_id=auth.uid());

create policy applications_applicant_delete
on public.job_applications for delete to authenticated
using (applicant_id=auth.uid());

create policy applications_employer_read
on public.job_applications for select to authenticated
using (exists(select 1 from public.jobs j where j.id=job_id and j.employer_id=auth.uid()));

create policy applications_employer_update
on public.job_applications for update to authenticated
using (exists(select 1 from public.jobs j where j.id=job_id and j.employer_id=auth.uid()))
with check (exists(select 1 from public.jobs j where j.id=job_id and j.employer_id=auth.uid()));

create policy applications_admin_all
on public.job_applications for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- =========================================================
-- 10. JOB NOTIFICATIONS: COMPATIBLE COLUMNS + TRIGGER
-- =========================================================
alter table public.job_notifications add column if not exists user_id uuid;
alter table public.job_notifications add column if not exists job_id uuid;
alter table public.job_notifications add column if not exists application_id uuid;
alter table public.job_notifications add column if not exists title text;
alter table public.job_notifications add column if not exists message text;
alter table public.job_notifications add column if not exists status text;
alter table public.job_notifications add column if not exists is_read boolean not null default false;
alter table public.job_notifications add column if not exists created_at timestamptz not null default now();

alter table public.job_notifications enable row level security;
drop policy if exists notifications_self_read on public.job_notifications;
drop policy if exists notifications_self_update on public.job_notifications;
drop policy if exists notifications_admin_insert on public.job_notifications;
drop policy if exists notifications_self_delete on public.job_notifications;

create policy notifications_self_read
on public.job_notifications for select to authenticated
using (user_id=auth.uid() or public.is_admin());

create policy notifications_self_update
on public.job_notifications for update to authenticated
using (user_id=auth.uid())
with check (user_id=auth.uid());

create policy notifications_self_delete
on public.job_notifications for delete to authenticated
using (user_id=auth.uid());

create policy notifications_admin_insert
on public.job_notifications for insert to authenticated
with check (public.is_admin());

create or replace function public.notify_application_status_change()
returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.status is distinct from old.status and new.applicant_id is not null then
    insert into public.job_notifications(user_id,job_id,application_id,title,message,status,is_read,created_at)
    values(
      new.applicant_id,
      new.job_id,
      new.id,
      'Application status updated',
      'Your application status is now: ' || replace(coalesce(new.status,'pending'),'_',' '),
      new.status,
      false,
      now()
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_application_status_notification on public.job_applications;
create trigger trg_application_status_notification
after update of status on public.job_applications
for each row execute function public.notify_application_status_change();

-- =========================================================
-- 11. PUBLIC PROPERTY CONTACT RPCS
-- =========================================================
drop function if exists public.get_property_contacts(uuid);

create or replace function public.get_property_contacts(p_city_id uuid)
returns table(id uuid, full_name text, phone text, role text)
language sql stable security definer set search_path=public as $$
  select p.id,p.full_name,p.phone,p.role
  from public.profiles p
  where p.is_active=true
    and (
      p.role in ('admin','super_admin')
      or (p.role='city_admin' and exists(
        select 1 from public.admin_city_assignments a
        where a.admin_id=p.id and a.city_id=p_city_id
      ))
    )
  order by case p.role when 'super_admin' then 1 when 'admin' then 2 else 3 end, p.full_name nulls last;
$$;

grant execute on function public.get_property_contacts(uuid) to anon, authenticated;

create or replace function public.get_property_owner_contact(p_owner_id uuid)
returns table(id uuid, full_name text, phone text, role text)
language sql stable security definer set search_path=public as $$
  select p.id,p.full_name,p.phone,p.role
  from public.profiles p
  where p.id=p_owner_id and p.is_active=true
  limit 1;
$$;

grant execute on function public.get_property_owner_contact(uuid) to anon, authenticated;

commit;

-- Diagnostics for the final integrated test:
select column_name,data_type from information_schema.columns
where table_schema='public' and table_name in ('profiles','jobs','job_applications','job_notifications')
order by table_name,ordinal_position;

select role,count(*) as users from public.profiles group by role order by role;
select status,count(*) as public_properties from public.properties where status in ('approved','published','active') group by status;
select status,count(*) as jobs_by_status from public.jobs group by status order by status;
