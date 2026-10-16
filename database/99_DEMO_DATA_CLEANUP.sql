-- Removes ALL demo users and their listings/jobs/leads (cascade). Run before real launch.
delete from public.payments where note = 'DEMO data';
delete from auth.users where email like '%@demo.eedb.test';
-- Optional: remove the demo locations too (only if you will add your own):
-- delete from public.locations where name in ('Dire Dawa','Harari','Somali','Oromia')
--   and type = 'region';
