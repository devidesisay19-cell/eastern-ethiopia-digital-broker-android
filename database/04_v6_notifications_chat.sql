-- =====================================================================
-- EEDB V6 - 04 NOTIFICATIONS, PUSH DISPATCH AND CHAT  (run FOURTH, after 03)
-- In-app notifications, FCM device tokens, event triggers (new listing, payment,
-- lead, job applicant, chat), chat threads/messages/reports, realtime.
-- Push delivery uses the Edge Function in supabase/functions/send-push.
-- =====================================================================

-- ===== NOTIFICATIONS =====
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('listing','payment','lead','job','chat','system')),
  title text not null check (length(title) <= 120),
  body text check (body is null or length(body) <= 400),
  link text check (link is null or link ~ '^[a-z0-9_-]+\.html(\?[A-Za-z0-9=&_-]*)?$'),
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications(user_id, is_read, created_at desc);
alter table public.notifications enable row level security;
drop policy if exists notifications_own_select on public.notifications;
create policy notifications_own_select on public.notifications for select to authenticated using (user_id = auth.uid());
drop policy if exists notifications_own_update on public.notifications;
create policy notifications_own_update on public.notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists notifications_own_delete on public.notifications;
create policy notifications_own_delete on public.notifications for delete to authenticated using (user_id = auth.uid());
revoke update on public.notifications from authenticated, anon;
grant update (is_read) on public.notifications to authenticated;
revoke insert on public.notifications from authenticated, anon;

create table if not exists public.device_tokens (
  token text primary key check (length(token) between 20 and 4096),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default 'android',
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user_idx on public.device_tokens(user_id);
alter table public.device_tokens enable row level security;
drop policy if exists device_tokens_own_select on public.device_tokens;
create policy device_tokens_own_select on public.device_tokens for select to authenticated using (user_id = auth.uid());
drop policy if exists device_tokens_own_delete on public.device_tokens;
create policy device_tokens_own_delete on public.device_tokens for delete to authenticated using (user_id = auth.uid());

create or replace function public.eedb_register_device(p_token text) returns void
language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  insert into public.device_tokens(token, user_id) values (p_token, auth.uid())
  on conflict (token) do update set user_id = auth.uid(), updated_at = now();
end $$;
create or replace function public.eedb_unregister_device(p_token text) returns void
language sql security definer set search_path=public as $$
  delete from public.device_tokens where token = p_token and user_id = auth.uid();
$$;
revoke all on function public.eedb_register_device(text) from public, anon;
revoke all on function public.eedb_unregister_device(text) from public, anon;
grant execute on function public.eedb_register_device(text) to authenticated;
grant execute on function public.eedb_unregister_device(text) to authenticated;

-- Called right after logout so a signed-out phone stops receiving that user's pushes.
create or replace function public.eedb_forget_device(p_token text) returns void
language sql security definer set search_path=public as $$
  delete from public.device_tokens where token = p_token;
$$;
revoke all on function public.eedb_forget_device(text) from public;
grant execute on function public.eedb_forget_device(text) to anon, authenticated;

-- internal helpers (not callable from the app)
create or replace function public.eedb_notify(p_user uuid, p_kind text, p_title text, p_body text, p_link text) returns void
language plpgsql security definer set search_path=public as $$
begin
  if p_user is null then return; end if;
  insert into public.notifications(user_id, kind, title, body, link) values (p_user, p_kind, left(p_title,120), left(p_body,400), p_link);
end $$;
revoke all on function public.eedb_notify(uuid,text,text,text,text) from public, anon, authenticated;

create or replace function public.eedb_notify_city_staff(p_city uuid, p_kind text, p_title text, p_body text, p_admin_link text, p_agent_link text, p_include_agents boolean default true, p_skip uuid default null) returns void
language plpgsql security definer set search_path=public as $$
declare r record;
begin
  if p_city is null then return; end if;
  for r in select a.admin_id as uid, p.role from public.admin_city_assignments a
           join public.profiles p on p.id = a.admin_id
           where a.city_id = p_city and p.is_active and p.role in ('city_admin','agent') loop
    if r.uid is distinct from p_skip and (p_include_agents or r.role = 'city_admin') then
      perform public.eedb_notify(r.uid, p_kind, p_title, p_body, case when r.role='agent' then p_agent_link else p_admin_link end);
    end if;
  end loop;
end $$;
revoke all on function public.eedb_notify_city_staff(uuid,text,text,text,text,text,boolean,uuid) from public, anon, authenticated;

-- ===== PUSH DISPATCH (pg_net -> Edge Function send-push) =====
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.app_config (key text primary key, value text not null);
revoke all on private.app_config from public, anon, authenticated;
-- !! Replace <PROJECT-REF> with YOUR Supabase project ref (the part before .supabase.co). Until then push is simply skipped. !!
insert into private.app_config(key,value) values
  ('push_function_url','https://<PROJECT-REF>.supabase.co/functions/v1/send-push'),
  ('push_webhook_secret', encode(gen_random_bytes(24),'hex'))
on conflict (key) do nothing;

create or replace function public.eedb_push_secret() returns text
language sql stable security definer set search_path=public as $$
  select value from private.app_config where key='push_webhook_secret';
$$;
revoke all on function public.eedb_push_secret() from public, anon, authenticated;
grant execute on function public.eedb_push_secret() to service_role;

do $$ begin
  create extension if not exists pg_net with schema extensions;
exception when others then raise notice 'pg_net not installed: %', sqlerrm; end $$;

create or replace function public.eedb_push_dispatch() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_url text; v_secret text;
begin
  select value into v_url from private.app_config where key='push_function_url';
  select value into v_secret from private.app_config where key='push_webhook_secret';
  if v_url is null or v_secret is null or position('<' in v_url) > 0 then return new; end if;
  if not exists (select 1 from public.device_tokens where user_id = new.user_id) then return new; end if;
  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type','application/json','x-eedb-secret', v_secret),
    body := jsonb_build_object('user_id', new.user_id, 'title', new.title, 'body', new.body, 'link', new.link, 'notification_id', new.id));
  return new;
exception when others then
  return new;   -- never block the insert because of push problems
end $$;
drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push after insert on public.notifications for each row execute function public.eedb_push_dispatch();

-- ===== EVENT TRIGGERS =====
create or replace function public.eedb_notify_listing_insert() returns trigger
language plpgsql security definer set search_path=public as $$
declare j jsonb := to_jsonb(new); owner uuid; label text;
begin
  owner := coalesce(j->>'owner_id', j->>'seller_id')::uuid;
  label := case tg_table_name when 'properties' then 'property' when 'marketplace_items' then 'marketplace item' else 'car' end;
  if new.status = 'pending_review' then
    perform public.eedb_notify_city_staff(new.city_id, 'listing', 'New ' || label || ' to review', new.title, 'admin-dashboard.html', 'agent-dashboard.html', true, owner);
  end if;
  return new;
end $$;
drop trigger if exists eedb_notify_properties_ins on public.properties;
create trigger eedb_notify_properties_ins after insert on public.properties for each row execute function public.eedb_notify_listing_insert();
drop trigger if exists eedb_notify_marketplace_ins on public.marketplace_items;
create trigger eedb_notify_marketplace_ins after insert on public.marketplace_items for each row execute function public.eedb_notify_listing_insert();
drop trigger if exists eedb_notify_cars_ins on public.cars;
create trigger eedb_notify_cars_ins after insert on public.cars for each row execute function public.eedb_notify_listing_insert();

create or replace function public.eedb_notify_listing_status() returns trigger
language plpgsql security definer set search_path=public as $$
declare j jsonb := to_jsonb(new); owner uuid; reason text;
begin
  if new.status is not distinct from old.status then return new; end if;
  owner := coalesce(j->>'owner_id', j->>'seller_id')::uuid;
  if new.status = 'published' then
    perform public.eedb_notify(owner, 'listing', 'Your listing is live', new.title, 'index.html');
  elsif new.status = 'rejected' then
    reason := j->>'rejection_reason';
    perform public.eedb_notify(owner, 'listing', 'Your listing was not approved', coalesce(reason, new.title), 'index.html');
  elsif new.status in ('sold','rented') then
    perform public.eedb_notify(owner, 'listing', 'Marked as ' || new.status, new.title, 'index.html');
  end if;
  return new;
end $$;
drop trigger if exists eedb_notify_properties_upd on public.properties;
create trigger eedb_notify_properties_upd after update of status on public.properties for each row execute function public.eedb_notify_listing_status();
drop trigger if exists eedb_notify_marketplace_upd on public.marketplace_items;
create trigger eedb_notify_marketplace_upd after update of status on public.marketplace_items for each row execute function public.eedb_notify_listing_status();
drop trigger if exists eedb_notify_cars_upd on public.cars;
create trigger eedb_notify_cars_upd after update of status on public.cars for each row execute function public.eedb_notify_listing_status();

create or replace function public.eedb_notify_lead() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  perform public.eedb_notify_city_staff(new.city_id, 'lead', 'New customer request', new.customer_name || ' - ' || new.customer_phone, 'agents-leads.html', 'agent-dashboard.html');
  return new;
end $$;
drop trigger if exists eedb_notify_lead_ins on public.leads;
create trigger eedb_notify_lead_ins after insert on public.leads for each row execute function public.eedb_notify_lead();

create or replace function public.eedb_notify_payment() returns trigger
language plpgsql security definer set search_path=public as $$
declare amt text := 'ETB ' || to_char(new.amount, 'FM999,999,999,990'); owner uuid;
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    perform public.eedb_notify_city_staff(new.city_id, 'payment', 'Payment awaiting confirmation', amt || ' - ' || new.kind, 'payments.html', 'payments.html', false, new.recorded_by);
  end if;
  if new.status = 'confirmed' and (tg_op = 'INSERT' or old.status is distinct from 'confirmed') then
    perform public.eedb_notify(new.recorded_by, 'payment', 'Payment confirmed', amt, 'payments.html');
    if new.agent_id is not null and new.agent_id is distinct from new.recorded_by then
      perform public.eedb_notify(new.agent_id, 'payment', 'Payment confirmed', amt, 'payments.html');
    end if;
    if new.kind = 'featured_listing' and new.listing_kind = 'property' and new.listing_id is not null then
      select owner_id into owner from public.properties where id = new.listing_id;
      perform public.eedb_notify(owner, 'payment', 'Your listing is now featured', amt || ' received', 'index.html');
    end if;
  elsif new.status = 'rejected' and tg_op = 'UPDATE' and old.status is distinct from 'rejected' then
    perform public.eedb_notify(new.recorded_by, 'payment', 'Payment rejected', amt, 'payments.html');
  end if;
  return new;
end $$;
drop trigger if exists eedb_notify_payment_trg on public.payments;
create trigger eedb_notify_payment_trg after insert or update of status on public.payments for each row execute function public.eedb_notify_payment();

create or replace function public.eedb_notify_application() returns trigger
language plpgsql security definer set search_path=public as $$
declare emp uuid; ttl text;
begin
  select employer_id, title into emp, ttl from public.jobs where id = new.job_id;
  perform public.eedb_notify(emp, 'job', 'New job applicant', ttl, 'employer-applications.html');
  return new;
end $$;
drop trigger if exists eedb_notify_application_ins on public.job_applications;
create trigger eedb_notify_application_ins after insert on public.job_applications for each row execute function public.eedb_notify_application();

create or replace function public.eedb_notify_job_status() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.status is distinct from old.status and new.status in ('published','rejected') then
    perform public.eedb_notify(new.employer_id, 'job', case when new.status='published' then 'Your job post is live' else 'Your job post was not approved' end, new.title, 'employer-job-dashboard.html');
  end if;
  return new;
end $$;
drop trigger if exists eedb_notify_job_upd on public.jobs;
create trigger eedb_notify_job_upd after update of status on public.jobs for each row execute function public.eedb_notify_job_status();

-- ===== CHAT =====
create table if not exists public.chat_threads (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade default auth.uid(),
  audience text not null check (audience in ('city','super')),
  kind text not null default 'chat' check (kind in ('chat','report')),
  city_id uuid references public.locations(id) on delete set null,
  subject text not null check (length(trim(subject)) between 2 and 120),
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  check (audience <> 'city' or city_id is not null)
);
create index if not exists chat_threads_city_idx on public.chat_threads(city_id, last_message_at desc);
create index if not exists chat_threads_creator_idx on public.chat_threads(created_by, last_message_at desc);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.chat_threads(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  body text not null check (length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_thread_idx on public.chat_messages(thread_id, created_at);

alter table public.chat_threads enable row level security;
alter table public.chat_messages enable row level security;

create or replace function public.eedb_is_staff_user() returns boolean
language sql stable security definer set search_path=public as $$
  select exists (select 1 from public.profiles p where p.id=auth.uid() and coalesce(p.is_active,true) and p.role in ('super_admin','admin','city_admin','agent'));
$$;

create or replace function public.eedb_chat_can_see(tid uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists (
    select 1 from public.chat_threads t where t.id = tid and (
      t.created_by = auth.uid()
      or public.eedb_is_super_admin()
      or (t.audience = 'city' and (
            (public.eedb_is_listing_admin() and public.eedb_can_manage_city(t.city_id))
            or public.eedb_agent_in_city(t.city_id))))
  );
$$;

-- created_by check first: the helper cannot see a row inserted by the same statement
drop policy if exists chat_threads_select on public.chat_threads;
create policy chat_threads_select on public.chat_threads for select to authenticated
  using (created_by = auth.uid() or public.eedb_chat_can_see(id));
drop policy if exists chat_threads_insert on public.chat_threads;
create policy chat_threads_insert on public.chat_threads for insert to authenticated
  with check (created_by = auth.uid() and (kind = 'chat' or public.eedb_is_staff_user()));
drop policy if exists chat_threads_update on public.chat_threads;
create policy chat_threads_update on public.chat_threads for update to authenticated
  using (public.eedb_chat_can_see(id)) with check (public.eedb_chat_can_see(id));
revoke update on public.chat_threads from authenticated, anon;
grant update (status) on public.chat_threads to authenticated;

drop policy if exists chat_messages_select on public.chat_messages;
create policy chat_messages_select on public.chat_messages for select to authenticated using (public.eedb_chat_can_see(thread_id));
drop policy if exists chat_messages_insert on public.chat_messages;
create policy chat_messages_insert on public.chat_messages for insert to authenticated
  with check (sender_id = auth.uid() and public.eedb_chat_can_see(thread_id)
              and exists (select 1 from public.chat_threads t where t.id = thread_id and t.status = 'open'));

create or replace function public.eedb_chat_after_message() returns trigger
language plpgsql security definer set search_path=public as $$
declare t public.chat_threads; r record; txt text;
begin
  select * into t from public.chat_threads where id = new.thread_id;
  update public.chat_threads set last_message_at = now() where id = new.thread_id;
  txt := left(new.body, 100);
  if new.sender_id = t.created_by then
    if t.audience = 'city' then
      perform public.eedb_notify_city_staff(t.city_id, 'chat', 'New message: ' || t.subject, txt, 'chat.html?t=' || t.id, 'chat.html?t=' || t.id, true, new.sender_id);
    end if;
    for r in select id from public.profiles where role = 'super_admin' and is_active and id is distinct from new.sender_id
             and (t.audience = 'super' or t.kind = 'report') loop
      perform public.eedb_notify(r.id, 'chat', 'New message: ' || t.subject, txt, 'chat.html?t=' || t.id);
    end loop;
  else
    perform public.eedb_notify(t.created_by, 'chat', 'Reply: ' || t.subject, txt, 'chat.html?t=' || t.id);
  end if;
  return new;
end $$;
drop trigger if exists chat_messages_after on public.chat_messages;
create trigger chat_messages_after after insert on public.chat_messages for each row execute function public.eedb_chat_after_message();

-- ===== REALTIME =====
do $$ begin
  alter publication supabase_realtime add table public.notifications;
exception when others then raise notice 'realtime notifications: %', sqlerrm; end $$;
do $$ begin
  alter publication supabase_realtime add table public.chat_messages;
exception when others then raise notice 'realtime chat: %', sqlerrm; end $$;
