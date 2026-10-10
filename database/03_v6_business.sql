-- =====================================================================
-- EEDB V6 - 03 BUSINESS LAYER  (run THIRD, after 01 and 02)
-- Agents, customer leads, manual payments ledger, investor role + overview,
-- listing constraints, contacts incl. agents.
-- =====================================================================

-- =====================================================================
-- Safe to run on a NEW project (after 01 and 02) and on an EXISTING V4 database:
-- it only ADDS things, never deletes or changes existing rows, and can be re-run.
-- Run the whole file at once: if anything fails, nothing is changed.
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['profiles','locations','admin_city_assignments','properties','jobs','job_applications','marketplace_items','cars','post_status_history'] loop
    if to_regclass('public.'||t) is null then
      raise exception 'Missing table public.% - run 01 and 02 first (or this is not an EEDB database)', t;
    end if;
  end loop;
  foreach t in array array['eedb_is_super_admin','eedb_is_listing_admin','eedb_can_manage_city','is_city_admin','is_assigned_city'] loop
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=t) then
      raise exception 'Missing function public.% - run 02 (SUPABASE_FINAL_V4.sql) first', t;
    end if;
  end loop;
end $$;

-- ===== ROLES =====
-- drop every old CHECK on profiles.role (whatever its name) and add the new list
do $$
declare c record;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.profiles'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%role%' loop
    execute format('alter table public.profiles drop constraint %I', c.conname);
  end loop;
end $$;
alter table public.profiles add constraint profiles_role_check
  check (role in ('super_admin','admin','city_admin','agent','investor','owner','renter','job_seeker','employer'));

create or replace function public.eedb_guard_profile()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or public.eedb_is_super_admin()
     or coalesce(current_setting('eedb.allow_role_change', true),'') = '1' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.role is null or new.role not in ('owner','renter','job_seeker','employer') then
      raise exception 'This account type cannot be created from sign-up';
    end if;
    new.is_active := true;
    return new;
  end if;
  if new.role is distinct from old.role then raise exception 'Only Super Admin can change roles'; end if;
  if new.is_active is distinct from old.is_active then raise exception 'Only Super Admin can activate or deactivate accounts'; end if;
  return new;
end;
$$;

create or replace function public.eedb_is_agent() returns boolean
language sql stable security definer set search_path=public as $$
  select exists (select 1 from public.profiles p where p.id=auth.uid() and p.role='agent' and coalesce(p.is_active,true));
$$;
create or replace function public.eedb_is_investor() returns boolean
language sql stable security definer set search_path=public as $$
  select exists (select 1 from public.profiles p where p.id=auth.uid() and p.role='investor' and coalesce(p.is_active,true));
$$;
create or replace function public.eedb_agent_in_city(cid uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select cid is not null and public.eedb_is_agent() and exists (
    select 1 from public.admin_city_assignments a where a.admin_id=auth.uid() and a.city_id=cid);
$$;

create or replace function public.eedb_set_user_role(target uuid, new_role text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.eedb_is_super_admin() then raise exception 'Only Super Admin can change roles'; end if;
  if target is null or target = auth.uid() then raise exception 'You cannot change your own role'; end if;
  if new_role is null or new_role not in ('super_admin','admin','city_admin','agent','investor','owner','renter','job_seeker','employer') then
    raise exception 'Invalid role: %', new_role;
  end if;
  update public.profiles set role = new_role where id = target;
  if not found then raise exception 'User not found'; end if;
  if new_role not in ('city_admin','agent') then
    delete from public.admin_city_assignments where admin_id = target;
  end if;
end;
$$;

create or replace function public.eedb_make_agent(target uuid, city uuid)
returns void language plpgsql security definer set search_path=public as $$
declare cur text;
begin
  if not (public.eedb_is_super_admin() or (public.is_city_admin() and public.is_assigned_city(city))) then
    raise exception 'Only Super Admin or this city''s City Admin can assign agents';
  end if;
  if not exists (select 1 from public.locations where id = city and type = 'city') then raise exception 'City not found'; end if;
  select role into cur from public.profiles where id = target;
  if cur is null then raise exception 'User not found'; end if;
  if cur in ('super_admin','admin','city_admin') then raise exception 'This user already has an admin role'; end if;
  perform set_config('eedb.allow_role_change','1', true);
  update public.profiles set role = 'agent' where id = target;
  insert into public.admin_city_assignments(admin_id, city_id) values (target, city) on conflict (admin_id, city_id) do nothing;
end;
$$;

create or replace function public.eedb_remove_agent(target uuid, city uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not (public.eedb_is_super_admin() or (public.is_city_admin() and public.is_assigned_city(city))) then
    raise exception 'Only Super Admin or this city''s City Admin can remove agents';
  end if;
  delete from public.admin_city_assignments where admin_id = target and city_id = city;
  if not exists (select 1 from public.admin_city_assignments where admin_id = target) then
    perform set_config('eedb.allow_role_change','1', true);
    update public.profiles set role = 'owner' where id = target and role = 'agent';
  end if;
end;
$$;
revoke all on function public.eedb_make_agent(uuid,uuid) from public, anon;
revoke all on function public.eedb_remove_agent(uuid,uuid) from public, anon;
grant execute on function public.eedb_make_agent(uuid,uuid) to authenticated;
grant execute on function public.eedb_remove_agent(uuid,uuid) to authenticated;

-- ===== LEADS =====
create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  listing_kind text not null check (listing_kind in ('property','marketplace','car','job')),
  listing_id uuid not null,
  city_id uuid references public.locations(id) on delete set null,
  customer_name text not null check (length(trim(customer_name)) between 2 and 120),
  customer_phone text not null check (length(trim(customer_phone)) between 6 and 30),
  message text check (message is null or length(message) <= 1000),
  status text not null default 'new' check (status in ('new','contacted','viewing','closed_won','closed_lost')),
  assigned_agent_id uuid references public.profiles(id) on delete set null,
  note text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists leads_city_status_idx on public.leads(city_id, status, created_at desc);
create index if not exists leads_agent_idx on public.leads(assigned_agent_id);
alter table public.leads enable row level security;

drop policy if exists leads_public_insert on public.leads;
create policy leads_public_insert on public.leads for insert to anon, authenticated
  with check (status = 'new' and assigned_agent_id is null and note is null);
drop policy if exists leads_super_admin_all on public.leads;
create policy leads_super_admin_all on public.leads for all to authenticated
  using (public.eedb_is_super_admin()) with check (public.eedb_is_super_admin());
drop policy if exists leads_city_admin_all on public.leads;
create policy leads_city_admin_all on public.leads for all to authenticated
  using (public.eedb_is_listing_admin() and public.eedb_can_manage_city(city_id))
  with check (public.eedb_is_listing_admin() and public.eedb_can_manage_city(city_id));
drop policy if exists leads_agent_read on public.leads;
create policy leads_agent_read on public.leads for select to authenticated
  using (public.eedb_agent_in_city(city_id) and (assigned_agent_id is null or assigned_agent_id = auth.uid()));
drop policy if exists leads_agent_update on public.leads;
create policy leads_agent_update on public.leads for update to authenticated
  using (public.eedb_agent_in_city(city_id) and (assigned_agent_id is null or assigned_agent_id = auth.uid()))
  with check (public.eedb_agent_in_city(city_id) and assigned_agent_id = auth.uid());

create or replace function public.eedb_leads_touch() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists leads_touch on public.leads;
create trigger leads_touch before update on public.leads for each row execute function public.eedb_leads_touch();

create or replace function public.eedb_agent_report()
returns table(agent_id uuid, agent_name text, phone text, city_name text, leads_total bigint, leads_won bigint, listings_total bigint)
language sql stable security definer set search_path=public as $$
  select p.id, p.full_name, p.phone, l.name,
    (select count(*) from public.leads x where x.assigned_agent_id = p.id),
    (select count(*) from public.leads x where x.assigned_agent_id = p.id and x.status = 'closed_won'),
    (select count(*) from public.properties x where x.owner_id = p.id)
    + (select count(*) from public.marketplace_items x where x.seller_id = p.id)
    + (select count(*) from public.cars x where x.seller_id = p.id)
  from public.profiles p
  join public.admin_city_assignments a on a.admin_id = p.id
  join public.locations l on l.id = a.city_id
  where p.role = 'agent'
    and (public.eedb_is_super_admin() or (public.eedb_is_listing_admin() and public.eedb_can_manage_city(a.city_id)))
  order by l.name, p.full_name;
$$;
revoke all on function public.eedb_agent_report() from public, anon;
grant execute on function public.eedb_agent_report() to authenticated;

-- ===== CONTACTS (city admins + agents + super admin) =====
create or replace function public.get_listing_contacts(p_city_id uuid)
returns table(role text, full_name text, phone text)
language sql stable security definer set search_path to 'public' as $$
  select 'city_admin'::text, p.full_name, p.phone
  from public.admin_city_assignments a join public.profiles p on p.id=a.admin_id
  where a.city_id=p_city_id and lower(p.role) in ('city_admin','admin') and p.is_active and length(trim(both from p.phone))>0
  union all
  select 'agent'::text, p.full_name, p.phone
  from public.admin_city_assignments a join public.profiles p on p.id=a.admin_id
  where a.city_id=p_city_id and lower(p.role)='agent' and p.is_active and length(trim(both from p.phone))>0
  union all
  select 'super_admin'::text, p.full_name, p.phone
  from public.profiles p where lower(p.role)='super_admin' and p.is_active and length(trim(both from p.phone))>0;
$$;
grant execute on function public.get_listing_contacts(uuid) to anon, authenticated;
grant execute on function public.get_property_contacts(uuid) to anon, authenticated;
grant execute on function public.get_property_owner_contact(uuid) to anon, authenticated;

-- ===== LISTING CONSTRAINTS (enforced for new rows; existing rows are not re-checked) =====
do $$
declare s text;
begin
  foreach s in array array[
    $q$marketplace_items|marketplace_price_check|check (price > 0)$q$,
    $q$marketplace_items|marketplace_price_unit_check|check (price_unit in ('total','day','week','month'))$q$,
    $q$marketplace_items|marketplace_items_condition_check|check (condition in ('new','used','excellent','good','fair'))$q$,
    $q$marketplace_items|marketplace_category_check|check (length(btrim(category)) > 0)$q$,
    $q$marketplace_items|marketplace_listing_type_check|check (listing_type in ('sell','rent'))$q$,
    $q$marketplace_items|marketplace_status_check|check (status in ('pending_review','approved','published','sold','rented','hidden','rejected'))$q$,
    $q$cars|cars_price_check|check (price > 0)$q$,
    $q$cars|cars_price_unit_check|check (price_unit in ('total','day','week','month'))$q$,
    $q$cars|cars_condition_check|check (condition in ('new','used','excellent','good','fair'))$q$,
    $q$cars|cars_year_check|check (year is null or (year >= 1950 and year <= 2100))$q$,
    $q$cars|cars_mileage_check|check (mileage is null or mileage >= 0)$q$,
    $q$cars|cars_transmission_check|check (transmission is null or transmission in ('Manual','Automatic','Semi-Automatic','Other'))$q$,
    $q$cars|cars_fuel_type_check|check (fuel_type is null or fuel_type in ('Petrol','Diesel','Hybrid','Electric','Other'))$q$,
    $q$cars|cars_listing_type_check|check (listing_type in ('sell','rent'))$q$,
    $q$cars|cars_status_check|check (status in ('pending_review','approved','published','sold','rented','hidden','rejected'))$q$
  ] loop
    execute format('alter table public.%I drop constraint if exists %I', split_part(s,'|',1), split_part(s,'|',2));
    execute format('alter table public.%I add constraint %I %s not valid', split_part(s,'|',1), split_part(s,'|',2), split_part(s,'|',3));
  end loop;
end $$;

-- ===== PAYMENTS LEDGER (manual) =====
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  city_id uuid not null references public.locations(id) on delete restrict,
  kind text not null check (kind in ('featured_listing','listing_fee','commission','subscription','other')),
  amount numeric(14,2) not null check (amount > 0 and amount < 1000000000),
  currency text not null default 'ETB' check (currency = 'ETB'),
  method text not null check (method in ('cash','bank_transfer','telebirr','cbe_birr','other')),
  reference text check (reference is null or length(reference) <= 80),
  payer_name text check (payer_name is null or length(payer_name) <= 120),
  payer_phone text check (payer_phone is null or length(payer_phone) <= 30),
  listing_kind text check (listing_kind is null or listing_kind in ('property','marketplace','car','job')),
  listing_id uuid,
  featured_days integer check (featured_days is null or featured_days between 1 and 365),
  agent_id uuid references public.profiles(id) on delete set null,
  agent_pct numeric(5,2) not null default 0 check (agent_pct between 0 and 100),
  status text not null default 'pending' check (status in ('pending','confirmed','rejected')),
  note text check (note is null or length(note) <= 500),
  recorded_by uuid references auth.users(id) on delete set null default auth.uid(),
  confirmed_by uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists payments_city_status_idx on public.payments(city_id, status, created_at desc);
create index if not exists payments_agent_idx on public.payments(agent_id);
alter table public.payments enable row level security;

create or replace function public.eedb_payment_admin(cid uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select public.eedb_is_super_admin() or (public.eedb_is_listing_admin() and public.eedb_can_manage_city(cid));
$$;
drop policy if exists payments_admin_all on public.payments;
create policy payments_admin_all on public.payments for all to authenticated
  using (public.eedb_payment_admin(city_id)) with check (public.eedb_payment_admin(city_id));
drop policy if exists payments_agent_insert on public.payments;
create policy payments_agent_insert on public.payments for insert to authenticated
  with check (public.eedb_agent_in_city(city_id) and recorded_by = auth.uid());
drop policy if exists payments_agent_read on public.payments;
create policy payments_agent_read on public.payments for select to authenticated
  using (public.eedb_is_agent() and (recorded_by = auth.uid() or agent_id = auth.uid()));

create or replace function public.eedb_payment_guard() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and not public.eedb_payment_admin(new.city_id) then
      new.status := 'pending'; new.confirmed_by := null; new.confirmed_at := null;
      new.recorded_by := auth.uid();
      new.agent_id := auth.uid();
    elsif new.status = 'confirmed' then
      new.confirmed_by := coalesce(new.confirmed_by, auth.uid()); new.confirmed_at := coalesce(new.confirmed_at, now());
    end if;
    return new;
  end if;
  if old.status = 'confirmed' and auth.uid() is not null and not public.eedb_is_super_admin() then
    raise exception 'A confirmed payment can only be changed by Super Admin';
  end if;
  if old.status = 'confirmed' and (new.amount is distinct from old.amount or new.city_id is distinct from old.city_id or new.kind is distinct from old.kind) and auth.uid() is not null then
    raise exception 'Amount, city and type of a confirmed payment cannot be changed';
  end if;
  if new.status is distinct from old.status then
    new.confirmed_by := auth.uid(); new.confirmed_at := now();
  end if;
  return new;
end $$;
drop trigger if exists payments_guard on public.payments;
create trigger payments_guard before insert or update on public.payments for each row execute function public.eedb_payment_guard();

create or replace function public.eedb_payment_apply() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.status = 'confirmed' and (tg_op = 'INSERT' or old.status is distinct from 'confirmed')
     and new.kind = 'featured_listing' and new.listing_kind = 'property' and new.listing_id is not null then
    update public.properties
       set is_featured = true,
           featured_until = greatest(coalesce(featured_until, now()), now()) + make_interval(days => coalesce(new.featured_days, 30)),
           updated_at = now()
     where id = new.listing_id and city_id = new.city_id;
  end if;
  return new;
end $$;
drop trigger if exists payments_apply on public.payments;
create trigger payments_apply after insert or update on public.payments for each row execute function public.eedb_payment_apply();

create or replace function public.eedb_payment_summary(p_city uuid default null)
returns table(city_id uuid, city_name text, confirmed_total numeric, pending_total numeric, month_total numeric, today_total numeric, agent_share_total numeric)
language sql stable security definer set search_path=public as $$
  select l.id, l.name,
    coalesce(sum(p.amount) filter (where p.status='confirmed'),0),
    coalesce(sum(p.amount) filter (where p.status='pending'),0),
    coalesce(sum(p.amount) filter (where p.status='confirmed' and p.confirmed_at >= date_trunc('month', now() at time zone 'Africa/Addis_Ababa') at time zone 'Africa/Addis_Ababa'),0),
    coalesce(sum(p.amount) filter (where p.status='confirmed' and (p.confirmed_at at time zone 'Africa/Addis_Ababa')::date = (now() at time zone 'Africa/Addis_Ababa')::date),0),
    coalesce(sum(p.amount * p.agent_pct / 100) filter (where p.status='confirmed'),0)
  from public.locations l
  left join public.payments p on p.city_id = l.id
  where l.type='city' and (p_city is null or l.id = p_city) and public.eedb_payment_admin(l.id)
  group by l.id, l.name order by l.name;
$$;
revoke all on function public.eedb_payment_summary(uuid) from public, anon;
grant execute on function public.eedb_payment_summary(uuid) to authenticated;

-- ===== INVESTOR OVERVIEW (Super Admin or Investor; aggregated numbers only) =====
create or replace function public.eedb_investor_overview()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  tz constant text := 'Africa/Addis_Ababa';
  d0 date := (now() at time zone 'Africa/Addis_Ababa')::date - 13;
  live text[] := array['published','approved'];
begin
  if not (public.eedb_is_super_admin() or public.eedb_is_investor()) then
    raise exception 'Only Super Admin or Investor can view the investor overview';
  end if;
  return jsonb_build_object(
    'generated_at', now(),
    'totals', jsonb_build_object(
      'users', (select count(*) from public.profiles),
      'agents', (select count(*) from public.profiles where role='agent'),
      'city_admins', (select count(*) from public.profiles where role='city_admin'),
      'cities', (select count(*) from public.locations where type='city' and is_active),
      'properties_live', (select count(*) from public.properties where status = any(live)),
      'marketplace_live', (select count(*) from public.marketplace_items where status = any(live)),
      'cars_live', (select count(*) from public.cars where status = any(live)),
      'jobs_live', (select count(*) from public.jobs where status='published'),
      'listings_total', (select count(*) from public.properties) + (select count(*) from public.marketplace_items) + (select count(*) from public.cars),
      'closed_deals', (select count(*) from public.properties where status in ('sold','rented'))
                    + (select count(*) from public.marketplace_items where status in ('sold','rented'))
                    + (select count(*) from public.cars where status in ('sold','rented')),
      'leads_total', (select count(*) from public.leads),
      'revenue_total', (select coalesce(sum(amount),0) from public.payments where status='confirmed'),
      'revenue_30d', (select coalesce(sum(amount),0) from public.payments where status='confirmed' and confirmed_at >= now() - interval '30 days'),
      'payments_pending', (select count(*) from public.payments where status='pending'),
      'featured_active', (select count(*) from public.properties where is_featured and (featured_until is null or featured_until > now())),
      'leads_new', (select count(*) from public.leads where status='new'),
      'leads_won', (select count(*) from public.leads where status='closed_won'),
      'applications', (select count(*) from public.job_applications),
      'new_users_7d', (select count(*) from public.profiles where created_at >= now() - interval '7 days'),
      'new_listings_7d',
          (select count(*) from public.properties where created_at >= now() - interval '7 days')
        + (select count(*) from public.marketplace_items where created_at >= now() - interval '7 days')
        + (select count(*) from public.cars where created_at >= now() - interval '7 days')
    ),
    'by_city', coalesce((
      select jsonb_agg(jsonb_build_object(
        'city_id', l.id, 'city', l.name,
        'properties', (select count(*) from public.properties x where x.city_id=l.id and x.status = any(live)),
        'marketplace', (select count(*) from public.marketplace_items x where x.city_id=l.id and x.status = any(live)),
        'cars', (select count(*) from public.cars x where x.city_id=l.id and x.status = any(live)),
        'jobs', (select count(*) from public.jobs x where x.city_id=l.id and x.status='published'),
        'agents', (select count(*) from public.admin_city_assignments a join public.profiles p on p.id=a.admin_id where a.city_id=l.id and p.role='agent'),
        'leads', (select count(*) from public.leads x where x.city_id=l.id),
        'leads_won', (select count(*) from public.leads x where x.city_id=l.id and x.status='closed_won'),
        'revenue', (select coalesce(sum(amount),0) from public.payments x where x.city_id=l.id and x.status='confirmed')
      ) order by l.name)
      from public.locations l where l.type='city' and l.is_active), '[]'::jsonb),
    'daily', (
      select jsonb_agg(jsonb_build_object(
        'date', g.d,
        'listings',
            (select count(*) from public.properties x where (x.created_at at time zone tz)::date = g.d)
          + (select count(*) from public.marketplace_items x where (x.created_at at time zone tz)::date = g.d)
          + (select count(*) from public.cars x where (x.created_at at time zone tz)::date = g.d),
        'leads', (select count(*) from public.leads x where (x.created_at at time zone tz)::date = g.d),
        'users', (select count(*) from public.profiles x where (x.created_at at time zone tz)::date = g.d)
      ) order by g.d)
      from generate_series(d0, d0 + 13, interval '1 day') as gs(ts), lateral (select gs.ts::date as d) g)
  );
end $$;
revoke all on function public.eedb_investor_overview() from public, anon;
grant execute on function public.eedb_investor_overview() to authenticated;

-- ===== SIGN-UP: create the profile from the sign-up data (works with "Confirm email" ON) =====
create or replace function public.eedb_handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb); r text; n text;
begin
  n := nullif(trim(coalesce(m->>'full_name','')), '');
  if n is null then return new; end if;            -- old app versions: the app inserts the profile itself
  r := coalesce(m->>'role', 'owner');
  if r not in ('owner','renter','job_seeker','employer') then r := 'owner'; end if;
  insert into public.profiles(id, full_name, phone, role, is_active)
  values (new.id, n, nullif(trim(m->>'phone'), ''), r, true)
  on conflict (id) do nothing;
  return new;
exception when others then
  return new;                                      -- never block sign-up
end $$;
drop trigger if exists eedb_on_auth_user_created on auth.users;
create trigger eedb_on_auth_user_created after insert on auth.users
  for each row execute function public.eedb_handle_new_user();
