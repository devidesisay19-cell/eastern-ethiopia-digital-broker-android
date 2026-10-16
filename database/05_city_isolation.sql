-- =====================================================================
-- EEDB V6 - 05 CITY ISOLATION  (run after 03 and 04; safe to re-run)
-- A City Admin sees and manages ONLY the data of the cities assigned to him/her.
-- Super Admin and the global "admin" role keep the full view.
-- Anonymous visitors and normal users see exactly what they saw before.
-- =====================================================================

-- ---- 1. who may see which profile -----------------------------------
create or replace function public.eedb_profile_visible(pid uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select pid = auth.uid()
    or public.eedb_is_super_admin()
    or exists (select 1 from public.profiles me where me.id = auth.uid() and me.role = 'admin' and me.is_active)
    or (public.eedb_is_listing_admin() and (
         exists (select 1 from public.admin_city_assignments a where a.admin_id = pid and public.eedb_can_manage_city(a.city_id))
      or exists (select 1 from public.properties x where x.owner_id = pid and public.eedb_can_manage_city(x.city_id))
      or exists (select 1 from public.marketplace_items x where x.seller_id = pid and public.eedb_can_manage_city(x.city_id))
      or exists (select 1 from public.cars x where x.seller_id = pid and public.eedb_can_manage_city(x.city_id))
      or exists (select 1 from public.jobs x where x.employer_id = pid and public.eedb_can_manage_city(x.city_id))
      or exists (select 1 from public.job_applications ap join public.jobs j on j.id = ap.job_id
                 where ap.applicant_id = pid and public.eedb_can_manage_city(j.city_id))
      or exists (select 1 from public.chat_threads t where t.created_by = pid and t.audience = 'city' and public.eedb_can_manage_city(t.city_id))
    ));
$$;
revoke all on function public.eedb_profile_visible(uuid) from public, anon;
grant execute on function public.eedb_profile_visible(uuid) to authenticated;

drop policy if exists profiles_self_select on public.profiles;
create policy profiles_self_select on public.profiles for select using (public.eedb_profile_visible(id));
drop policy if exists eedb_profiles_admin_read on public.profiles;   -- was: every admin could read every profile

-- ---- 2. find a registered user to make him/her an agent (limited search) ----
create or replace function public.eedb_find_user_for_agent(q text)
returns table(id uuid, full_name text, phone text, role text)
language plpgsql stable security definer set search_path=public as $$
declare t text := trim(coalesce(q, '')); d text := right(regexp_replace(coalesce(q, ''), '\D', '', 'g'), 9);
begin
  if not (public.eedb_is_super_admin() or public.is_city_admin()
          or exists (select 1 from public.profiles me where me.id = auth.uid() and me.role = 'admin' and me.is_active)) then
    raise exception 'Not allowed';
  end if;
  if length(t) < 3 then return; end if;
  return query
    select p.id, p.full_name, p.phone, p.role from public.profiles p
    where p.is_active and p.role in ('owner','renter','job_seeker','employer')
      and ((length(d) >= 6 and p.phone like '%' || d || '%')
           or p.full_name ilike '%' || replace(replace(t, '%', ''), '_', '') || '%')
    order by p.full_name limit 8;
end $$;
revoke all on function public.eedb_find_user_for_agent(text) from public, anon;
grant execute on function public.eedb_find_user_for_agent(text) to authenticated;

-- ---- 3. listings and jobs: admins see other statuses only inside their own cities ----
-- (the *_admin_all policies already grant that; the "or is_admin()" shortcut is removed)
drop policy if exists properties_public_read on public.properties;
create policy properties_public_read on public.properties for select
  using (status in ('approved','published','active') or owner_id = auth.uid());

drop policy if exists property_images_public_read on public.property_images;
create policy property_images_public_read on public.property_images for select
  using (exists (select 1 from public.properties p where p.id = property_images.property_id
                 and (p.status in ('approved','published','active') or p.owner_id = auth.uid())));

drop policy if exists property_images_admin_all on public.property_images;
create policy property_images_admin_all on public.property_images for all
  using (public.is_admin() and exists (select 1 from public.properties p where p.id = property_images.property_id and public.can_manage_city(p.city_id)))
  with check (public.is_admin() and exists (select 1 from public.properties p where p.id = property_images.property_id and public.can_manage_city(p.city_id)));

drop policy if exists jobs_public_read on public.jobs;
create policy jobs_public_read on public.jobs for select
  using (status = 'published' or employer_id = auth.uid() or posted_by = auth.uid());

-- ---- 4. job applications and job notifications ----
drop policy if exists applications_applicant_read on public.job_applications;
create policy applications_applicant_read on public.job_applications for select using (applicant_id = auth.uid());

drop policy if exists applications_admin_all on public.job_applications;
create policy applications_admin_all on public.job_applications for all to authenticated
  using (public.eedb_is_super_admin() or (public.eedb_is_listing_admin() and exists
        (select 1 from public.jobs j where j.id = job_applications.job_id and public.eedb_can_manage_city(j.city_id))))
  with check (public.eedb_is_super_admin() or (public.eedb_is_listing_admin() and exists
        (select 1 from public.jobs j where j.id = job_applications.job_id and public.eedb_can_manage_city(j.city_id))));

drop policy if exists notifications_self_read on public.job_notifications;
create policy notifications_self_read on public.job_notifications for select using (user_id = auth.uid());
