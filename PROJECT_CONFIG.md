# Which Supabase project does the app use?

| Project | URL | Use |
|---|---|---|
| **Production (your existing one, with all real data)** | `https://ubkfrpkapqnlaiscrxim.supabase.co` | **This source is set to it** - same accounts, location cascade, listings, photos, contacts as APK V4.4 |
| Test / demo (`eedb-v5`) | `https://lgslntahenhbuzcrkjuo.supabase.co` | empty demo data only (4 cities, demo listings) - for investor demos and experiments |

The V4.4 APK used the production project. The first V6 debug build used the empty test project, which is why the
location cascade, city-admin contacts, owner / super-admin logins and published listings looked "missing":
they live in the production project.

## Switch project
`python3 tools/set_supabase_project.py <URL> <PUBLISHABLE-KEY>`  (or Find-and-Replace in Android Studio).
Test project key: `sb_publishable_JWiUFQ4niDgwGCxx78nYRA_OYDUGxh_`
Production key:  `sb_publishable_5EokG_AyxU4BvcMiq1zyqg_B-NIMoeE`  (publishable keys are public by design; security = RLS)

## Production project must be upgraded once
See `database/UPGRADE_EXISTING_DATABASE.md` (agents, leads, payments, investor, notifications, chat, sign-up trigger).
