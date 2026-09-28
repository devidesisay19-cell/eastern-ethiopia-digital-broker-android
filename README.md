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

Run `SUPABASE_CANONICAL_FINAL.sql` in the live Supabase SQL editor after
reviewing the existing schema. The script creates or extends the
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

`SUPABASE_CANONICAL_FINAL.sql` creates all four buckets and their policies.
Run its audit query (last statement) after applying it.
