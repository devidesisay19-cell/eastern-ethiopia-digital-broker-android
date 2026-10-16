-- =====================================================================
-- EEDB V6 - 01 BASE SCHEMA  (run FIRST on a new Supabase project)
-- Core tables, helper functions, contact RPCs, property RPCs, triggers, RLS.
-- Order of the database folder:  01 -> 02 -> 03   (99 = optional cleanup)
-- =====================================================================
create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  role text,
  created_at timestamptz default now(),
  cv_url text,
  is_active boolean not null default true,
  constraint profiles_role_check check (role in ('super_admin','admin','city_admin','agent','investor','owner','renter','job_seeker','employer'))
);

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.locations(id) on delete cascade,
  name text not null,
  type text not null check (type in ('region','zone','city','woreda','area')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (parent_id, name, type)
);

create table public.admin_city_assignments (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  city_id uuid not null references public.locations(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (admin_id, city_id)
);

create table public.properties (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete cascade,
  title text not null,
  listing_type text not null check (listing_type in ('rent','sell')),
  price numeric not null check (price > 0),
  location text not null,
  bedrooms integer not null default 0 check (bedrooms >= 0),
  description text,
  status text not null default 'pending_review' check (status in ('pending_review','approved','published','sold','rented','hidden','rejected')),
  created_at timestamptz default now(),
  reviewed_by uuid,
  reviewed_at timestamptz,
  rejection_reason text,
  updated_at timestamptz default now(),
  is_featured boolean default false,
  featured_until timestamptz,
  region_id uuid references public.locations(id) on delete set null,
  zone_id uuid references public.locations(id) on delete set null,
  city_id uuid references public.locations(id) on delete set null,
  woreda_id uuid references public.locations(id) on delete set null,
  area_id uuid references public.locations(id) on delete set null
);

create table public.property_images (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null,
  display_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  employer_id uuid references auth.users(id) on delete cascade,
  title text not null,
  description text not null,
  category text,
  job_type text check (job_type is null or job_type in ('full_time','part_time','contract','temporary','internship','volunteer')),
  salary numeric,
  region_id uuid references public.locations(id) on delete set null,
  zone_id uuid references public.locations(id) on delete set null,
  city_id uuid references public.locations(id) on delete set null,
  woreda_id uuid references public.locations(id) on delete set null,
  area_id uuid references public.locations(id) on delete set null,
  company_name text,
  contact_phone text,
  contact_email text,
  application_deadline date,
  status text not null default 'pending' check (status in ('pending','published','rejected','closed','filled','expired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  posted_by uuid references auth.users(id) on delete set null,
  posting_method text default 'employer' check (posting_method in ('employer','admin'))
);

create table public.job_applications (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  applicant_id uuid not null references auth.users(id) on delete cascade,
  cover_message text,
  cv_url text,
  status text not null default 'pending' check (status in ('pending','reviewing','shortlisted','accepted','rejected','withdrawn')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (job_id, applicant_id)
);

create table public.job_saved (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (job_id, user_id)
);

create table public.job_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  application_id uuid references public.job_applications(id) on delete cascade,
  job_id uuid references public.jobs(id) on delete cascade,
  type text not null default 'application_status',
  title text not null,
  message text not null,
  old_status text,
  new_status text check (new_status is null or new_status in ('pending','reviewing','shortlisted','accepted','rejected','withdrawn')),
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  status text
);

create table public.post_status_history (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('property','job','marketplace','car')),
  entity_id uuid not null,
  city_id uuid references public.locations(id),
  old_status text,
  new_status text not null,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- ===== HELPER FUNCTIONS =====
create or replace function public.is_super_admin() returns boolean
language sql stable security definer set search_path to 'public' as $$
  select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='super_admin' and p.is_active=true);
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path to 'public' as $$
  select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('super_admin','admin','city_admin') and p.is_active=true);
$$;
create or replace function public.is_city_admin() returns boolean
language sql stable security definer set search_path to 'public' as $$
  select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='city_admin' and p.is_active=true);
$$;
create or replace function public.can_manage_city(target_city uuid) returns boolean
language sql stable security definer set search_path to 'public' as $$
  select target_city is not null and (
    public.is_super_admin()
    or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin' and p.is_active=true)
    or exists(select 1 from public.admin_city_assignments a where a.admin_id=auth.uid() and a.city_id=target_city)
  );
$$;
create or replace function public.is_assigned_city(check_city_id uuid) returns boolean
language sql stable security definer set search_path to 'public' as $$
  select exists (
    select 1 from public.admin_city_assignments aca
    join public.profiles p on p.id = aca.admin_id
    join public.locations l on l.id = aca.city_id
    where aca.admin_id = auth.uid() and p.role='city_admin'
      and aca.city_id = check_city_id and l.type='city' and l.is_active=true);
$$;
create or replace function public.is_management() returns boolean
language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from public.profiles where id=auth.uid() and role in ('super_admin','admin','city_admin'));
$$;
create or replace function public.current_user_role() returns text
language sql stable security definer set search_path to 'public' as $$
  select role from public.profiles where id=auth.uid() limit 1;
$$;

-- ===== CONTACT RPCs =====
create or replace function public.get_property_owner_contact(p_owner_id uuid)
returns table(id uuid, full_name text, phone text, role text)
language sql stable security definer set search_path to 'public' as $$
  select p.id, p.full_name, p.phone, p.role from public.profiles p
  where p.id=p_owner_id and p.is_active=true limit 1;
$$;
create or replace function public.get_property_contacts(p_city_id uuid)
returns table(id uuid, full_name text, phone text, role text)
language sql stable security definer set search_path to 'public' as $$
  select p.id, p.full_name, p.phone, p.role from public.profiles p
  where p.is_active=true and (
    p.role in ('admin','super_admin')
    or (p.role='city_admin' and exists(select 1 from public.admin_city_assignments a where a.admin_id=p.id and a.city_id=p_city_id)))
  order by case p.role when 'super_admin' then 1 when 'admin' then 2 else 3 end, p.full_name nulls last;
$$;

-- ===== PROPERTY ADMIN RPCs =====
create or replace function public.admin_approve_property(target_property_id uuid) returns boolean
language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then raise exception 'Access denied. Administrator required.'; end if;
  update public.properties set status='published', reviewed_by=auth.uid(), reviewed_at=now(), rejection_reason=null, updated_at=now()
  where id=target_property_id and public.can_manage_city(city_id);
  if not found then raise exception 'Property not found or not in your city.'; end if;
  return true;
end $$;
create or replace function public.admin_review_property(target_property_id uuid, decision text, reject_reason text default null) returns boolean
language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then raise exception 'Access denied. Administrator required.'; end if;
  if decision not in ('approve','reject') then raise exception 'Invalid review decision.'; end if;
  if decision='reject' and (reject_reason is null or trim(reject_reason)='') then raise exception 'Rejection reason is required.'; end if;
  update public.properties set
    status = case when decision='approve' then 'published' else 'rejected' end,
    reviewed_by=auth.uid(), reviewed_at=now(),
    rejection_reason = case when decision='approve' then null else trim(reject_reason) end,
    updated_at=now()
  where id=target_property_id and public.can_manage_city(city_id);
  if not found then raise exception 'Property not found or not in your city.'; end if;
  return true;
end $$;
create or replace function public.admin_set_property_featured(target_property_id uuid, make_featured boolean, days integer default 30) returns boolean
language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then raise exception 'Access denied. Administrator required.'; end if;
  if days < 1 or days > 365 then raise exception 'Featured duration must be between 1 and 365 days.'; end if;
  update public.properties set
    is_featured = make_featured,
    featured_until = case when make_featured then now() + make_interval(days => days) else null end,
    updated_at = now()
  where id=target_property_id and public.can_manage_city(city_id);
  if not found then raise exception 'Property not found or not in your city.'; end if;
  return true;
end $$;

-- ===== TRIGGERS =====
create or replace function public.update_jobs_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
create trigger jobs_updated_at_trigger before update on public.jobs for each row execute function public.update_jobs_updated_at();

create or replace function public.update_job_applications_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
create trigger job_applications_updated_at_trigger before update on public.job_applications for each row execute function public.update_job_applications_updated_at();

create or replace function public.create_job_application_notification() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare v_job_title text; v_title text; v_message text;
begin
  if old.status is not distinct from new.status then return new; end if;
  select title into v_job_title from public.jobs where id=new.job_id;
  v_title := case new.status
    when 'pending' then 'Application Received'
    when 'reviewing' then 'Application Under Review'
    when 'shortlisted' then 'You Have Been Shortlisted'
    when 'accepted' then 'Application Accepted'
    when 'rejected' then 'Application Update'
    when 'withdrawn' then 'Application Withdrawn'
    else 'Application Status Updated' end;
  v_message := 'Your application for "' || coalesce(v_job_title,'this job') || '" is now: ' || replace(new.status,'_',' ') || '.';
  insert into public.job_notifications(user_id, application_id, job_id, type, title, message, old_status, new_status, is_read, status)
  values (new.applicant_id, new.id, new.job_id, 'application_status', v_title, v_message, old.status, new.status, false, new.status);
  return new;
end $$;
create trigger job_application_status_notification_trigger after update on public.job_applications for each row execute function public.create_job_application_notification();

-- ===== RLS =====
alter table public.profiles enable row level security;
alter table public.locations enable row level security;
alter table public.admin_city_assignments enable row level security;
alter table public.properties enable row level security;
alter table public.property_images enable row level security;
alter table public.jobs enable row level security;
alter table public.job_applications enable row level security;
alter table public.job_saved enable row level security;
alter table public.job_notifications enable row level security;
alter table public.post_status_history enable row level security;

create policy locations_active_select on public.locations for select using (is_active = true or public.is_admin());
create policy locations_super_admin_insert on public.locations for insert with check (public.is_super_admin());
create policy locations_super_admin_update on public.locations for update using (public.is_super_admin()) with check (public.is_super_admin());
create policy locations_super_admin_delete on public.locations for delete using (public.is_super_admin());

create policy profiles_self_select on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy profiles_self_insert on public.profiles for insert with check (id = auth.uid() and role in ('owner','renter','job_seeker','employer'));
-- role / is_active are protected by the eedb_profiles_guard trigger (file 02), so users may edit name/phone/cv
create policy profiles_self_update on public.profiles for update using (id = auth.uid() and is_active = true) with check (id = auth.uid() and is_active = true);
create policy profiles_super_admin_update on public.profiles for update using (public.is_super_admin()) with check (public.is_super_admin());

create policy properties_public_read on public.properties for select using (status in ('approved','published','active') or owner_id = auth.uid() or public.is_admin());
create policy properties_owner_insert on public.properties for insert with check (owner_id = auth.uid());
create policy properties_owner_update on public.properties for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy properties_owner_delete on public.properties for delete using (owner_id = auth.uid());
create policy properties_admin_all on public.properties for all using (public.is_admin() and public.can_manage_city(city_id)) with check (public.is_admin() and public.can_manage_city(city_id));

create policy property_images_public_read on public.property_images for select using (exists (select 1 from public.properties p where p.id=property_images.property_id and (p.status in ('approved','published','active') or p.owner_id=auth.uid() or public.is_admin())));
create policy property_images_owner_insert on public.property_images for insert with check (owner_id=auth.uid() and exists (select 1 from public.properties p where p.id=property_images.property_id and p.owner_id=auth.uid()));
create policy property_images_owner_delete on public.property_images for delete using (owner_id = auth.uid());
create policy property_images_admin_all on public.property_images for all using (exists (select 1 from public.properties p where p.id=property_images.property_id and public.can_manage_city(p.city_id))) with check (exists (select 1 from public.properties p where p.id=property_images.property_id and public.can_manage_city(p.city_id)));

create policy jobs_public_read on public.jobs for select using (status='published' or employer_id=auth.uid() or posted_by=auth.uid() or public.is_admin());
create policy jobs_employer_insert on public.jobs for insert with check (employer_id=auth.uid() and posted_by=auth.uid() and posting_method='employer');
create policy jobs_employer_update on public.jobs for update using (employer_id=auth.uid()) with check (employer_id=auth.uid());
create policy jobs_employer_delete on public.jobs for delete using (employer_id=auth.uid());
create policy jobs_admin_all on public.jobs for all using (public.is_admin() and public.can_manage_city(city_id)) with check (public.is_admin() and public.can_manage_city(city_id));

create policy applications_applicant_read on public.job_applications for select using (applicant_id=auth.uid() or public.is_admin());
create policy applications_applicant_insert on public.job_applications for insert with check (applicant_id=auth.uid() and exists (select 1 from public.jobs j where j.id=job_applications.job_id and j.status='published'));
create policy applications_applicant_update on public.job_applications for update using (applicant_id=auth.uid()) with check (applicant_id=auth.uid());
create policy applications_applicant_delete on public.job_applications for delete using (applicant_id=auth.uid());
create policy applications_employer_read on public.job_applications for select using (exists (select 1 from public.jobs j where j.id=job_applications.job_id and j.employer_id=auth.uid()));
create policy applications_employer_update on public.job_applications for update using (exists (select 1 from public.jobs j where j.id=job_applications.job_id and j.employer_id=auth.uid())) with check (exists (select 1 from public.jobs j where j.id=job_applications.job_id and j.employer_id=auth.uid()));
create policy applications_admin_all on public.job_applications for all using (public.is_admin()) with check (public.is_admin());

create policy saved_self_all on public.job_saved for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy notifications_self_read on public.job_notifications for select using (user_id=auth.uid() or public.is_admin());
create policy notifications_self_update on public.job_notifications for update using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy notifications_self_delete on public.job_notifications for delete using (user_id=auth.uid());
create policy notifications_admin_insert on public.job_notifications for insert with check (public.is_admin());

create policy status_history_admin_read on public.post_status_history for select using (public.is_admin() and public.can_manage_city(city_id));
create policy status_history_admin_insert on public.post_status_history for insert with check (public.is_admin() and public.can_manage_city(city_id));
