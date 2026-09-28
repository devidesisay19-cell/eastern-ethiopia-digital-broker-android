# Eastern Ethiopia Digital Broker — Android Source

This is the complete Android Studio/Gradle source project for the Eastern
Ethiopia Digital Broker. It packages the existing web application in an
AndroidX WebView using `WebViewAssetLoader`.

## Build later in Termux or Android Studio

- Package: `com.easterneethiopia.digitalbroker`
- `compileSdk`: 36
- `targetSdk`: 36
- `minSdk`: 24
- Java/Kotlin toolchain: JDK 17
- Supabase JS: `@supabase/supabase-js@2.116.0`

This source package was intentionally not built in Replit. Build an APK/AAB
later in your Android/Termux environment with the Android SDK installed.

## Supabase setup

Run **`SUPABASE_FINAL_V4.sql`** (the only SQL file to run; it supersedes the
older canonical/v3 scripts) in the live Supabase SQL editor. The script creates or extends the
`marketplace_items` and `cars` tables, enables owner/admin RLS, creates the
`marketplace-images` and `car-images` public buckets, adds storage policies,
and includes audit queries.

The script deliberately does **not** replace `public.can_manage_city(uuid)`.
That existing helper must remain present and must continue to represent the
project's city-aware authorization rules. The existing `property-images`
bucket and Property/Job tables are not replaced by this script.

The browser app uses only the Supabase publishable key in
`app/src/main/assets/web/supabase.js`; no service-role key belongs in this
package.

## Included application features

- Property and Job browsing, details, authentication, and existing dashboards
- Marketplace listings with owner/admin create, edit, moderation, and up to
  five photos
- Car listings with owner/admin create, edit, moderation, and up to five photos
- Location hierarchy reused for Marketplace and Cars
- City-aware admin access through the existing `can_manage_city` helper
- Safe storage paths:
  - `user-id/marketplace-id/filename`
  - `user-id/car-id/filename`

Historical backups, nested duplicate Android projects, generated build
directories, `.git`, `local.properties`, signing properties, APKs, and AABs
were intentionally excluded.

## Storage buckets and paths (matched to code)

| Bucket | Access | Upload path |
|---|---|---|
| `property-images` | public | `user-id/property-id/file` (owner) or `property-id/file` (admin) |
| `marketplace-images` | public | `user-id/item-id/file` |
| `car-images` | public | `user-id/car-id/file` |
| `job-cvs` | private | `user-id/file` (signed URLs for employers) |

`SUPABASE_FINAL_V4.sql` creates all four buckets and their policies.
Run its audit query (last statement) after applying it.

## v4: Super Admin features
- **Change role**: Users -> Change Role (RPC `eedb_set_user_role`).
- **Assign City Admin**: City Admins tab (RPC `eedb_assign_city_admin`).
- **Daily reports**: Reports tab (Super Admin only) -> pick date -> pick city
  (RPC `eedb_daily_report`, Africa/Addis_Ababa day, no row limit).
- Sold/Rented history is written by DB triggers on properties,
  marketplace_items and cars. Only new status changes after running the SQL are counted.
- First Super Admin (SQL editor, once):
  `update public.profiles set role='super_admin' where id='<AUTH-UUID>';`

## v4.2 fixes
- Run **`FIX_V4_2.sql`** once in Supabase (after `SUPABASE_FINAL_V4.sql` and `FIX_V4_1.sql`):
  removes the old `marketplace_category_check` (and other old checks) and adds
  `get_listing_contacts(city_id)` for the detail pages.
- Photo picker (native `MainActivity.kt` + web pages) rewritten so photo selection works for
  admin Property / Marketplace / Car and owner Marketplace / Car. Photos are resized to JPEG.
- Admin Marketplace category is now a dropdown (same list as owner). Admin-created listings are published immediately.
- Home page (`index.html`): Marketplace and Cars cards have **View Details** -> `listing-details.html`,
  which shows the gallery, info and the City Admin (assigned to the item's city) + Super Admin phone / WhatsApp.
