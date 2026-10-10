# Upgrade your EXISTING (V4.4) Supabase project to V6

You do this once, in the Supabase dashboard of the project that already holds your real data
(`ubkfrpkapqnlaiscrxim`). The scripts only ADD tables, functions, policies and triggers. They do not delete or edit
any existing row (new CHECK rules apply to new rows only), and each file runs as one transaction: if anything fails,
nothing is changed. Both files are safe to re-run.

## Before you start
- Do NOT run `01_base_schema.sql` or `02_SUPABASE_FINAL_V4.sql` - your project already has them.
- Take a safety copy of what matters (SQL Editor): `select * from public.profiles;` -> Export CSV (and the same for
  `locations`, `properties`, `marketplace_items`, `cars`, `jobs`). Supabase Pro also has daily backups.

## Steps
1. Dashboard -> **SQL Editor** -> New query -> paste the whole of `database/03_v6_business.sql` -> **Run**.
   It starts with a check; if it says "Missing table/function ... run 01/02 first", send me the message.
2. New query -> paste the whole of `database/04_v6_notifications_chat.sql` -> **Run**.
   (Push is skipped until you replace `<PROJECT-REF>` in that file with `ubkfrpkapqnlaiscrxim` AND finish
   `FIREBASE_SETUP.md`. In-app notifications and chat work without it.)
3. Check:
```sql
select (select count(*) from public.leads) leads,
       (select count(*) from public.payments) payments,
       (select count(*) from public.notifications) notifications,
       (select count(*) from public.chat_threads) chats;
```
   It must return a row of zeros (no error).
4. Authentication -> Providers -> Email: sign-up now works with "Confirm email" ON or OFF.
5. Build the new APK and test: login with your old super admin, then check the list in `README.md` ("Test checklist").

## Test checklist (real phone)
Location cascade and city list - old logins (super admin, city admin, owner) - owner sign-up for a new account -
published property / marketplace / car / job visible on Home and in Admin dashboard - city-admin contacts on
"View details" - lead form - agent - payment - bell notification - chat.
