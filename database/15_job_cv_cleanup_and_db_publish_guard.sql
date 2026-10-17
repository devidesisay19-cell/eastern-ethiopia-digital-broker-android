-- =====================================================================
-- 15: (a) Deleting a job (Super Admin) also deletes its applicants' CV
--         files from storage ('job-cvs'). Job applications are removed by
--         cascade, so storage and database are both freed.
--     (b) Publishing is blocked when the DATABASE is near its limit as well
--         as when STORAGE is full (migration 11).
--         Free plan: DB 500 MB. Pro plan: DB 8 GB -> update db_limit_bytes
--         after upgrading:
--         update public.eedb_settings set value='8000000000' where key='db_limit_bytes';
-- Run once in the Supabase SQL editor after 01..14. Safe to re-run.
-- =====================================================================
begin;

-- (a) CV files cleanup
create or replace function public.eedb_delete_job_cv_file()
returns trigger
language plpgsql security definer set search_path=public, storage
as $$
begin
  if old.cv_url is not null then
    delete from storage.objects
     where bucket_id = 'job-cvs' and name = old.cv_url;
  end if;
  return old;
end;
$$;

drop trigger if exists eedb_job_cv_file_cleanup on public.job_applications;
create trigger eedb_job_cv_file_cleanup
after delete on public.job_applications
for each row execute function public.eedb_delete_job_cv_file();

-- (b) DB size limit setting + publish guard covering storage AND database
insert into public.eedb_settings (key, value)
values ('db_limit_bytes', '450000000')
on conflict (key) do nothing;

create or replace function public.eedb_database_used_bytes()
returns bigint
language sql stable security definer set search_path=public
as $$
  select pg_database_size(current_database())::bigint;
$$;

create or replace function public.eedb_block_publish_when_full()
returns trigger
language plpgsql security definer set search_path=public, storage
as $$
declare db_lim bigint;
begin
  if new.status = 'published' and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    db_lim := coalesce((select value::bigint from public.eedb_settings where key='db_limit_bytes'), 450000000);
    if public.eedb_storage_used_bytes() >= public.eedb_storage_limit_bytes() then
      raise exception 'Storage is full. Listings cannot be published right now. Please contact the Super Admin.'
        using errcode = 'P0001';
    end if;
    if public.eedb_database_used_bytes() >= db_lim then
      raise exception 'Database is full. Listings cannot be published right now. Please contact the Super Admin.'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

-- Jobs also get the publish guard (migration 11 attached it already; re-attach to be sure)
drop trigger if exists eedb_jobs_publish_guard on public.jobs;
create trigger eedb_jobs_publish_guard before insert or update on public.jobs
for each row execute function public.eedb_block_publish_when_full();

commit;
