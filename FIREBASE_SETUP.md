# Push notifications (Firebase Cloud Messaging) - setup

The app, the database and the Edge Function are ready. Push needs YOUR Firebase project (free).
Until you do the steps below, notifications still work **inside the app** (bell icon) - only the
phone-level push is off. The app builds and runs without Firebase values.

## 1. Create the Firebase project and the Android app
1. https://console.firebase.google.com -> Add project.
2. Project settings -> Your apps -> Add app -> Android. Package name: `com.easterneethiopia.digitalbroker`.
3. Add your SHA-1 only if you later add Google sign-in (not needed for push).
4. From the downloaded `google-services.json` copy 4 values.

## 2. Put the values in the app
Create `app/src/main/res/values/firebase_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="google_app_id" translatable="false">1:1234567890:android:abcdef...</string>      <!-- mobilesdk_app_id -->
    <string name="google_api_key" translatable="false">AIza...</string>                           <!-- current_key -->
    <string name="gcm_defaultSenderId" translatable="false">1234567890</string>                   <!-- project_number -->
    <string name="project_id" translatable="false">your-firebase-project-id</string>              <!-- project_id -->
</resources>
```
(No Gradle plugin needed.) Rebuild the APK/AAB.

## 3. Let the server send pushes
1. Firebase console -> Project settings -> Service accounts -> **Generate new private key** (JSON file).
2. Supabase dashboard -> Edge Functions -> `send-push` -> Secrets -> add
   `FCM_SERVICE_ACCOUNT_JSON` = the full content of that JSON file.
3. Database file `database/04_v6_notifications_chat.sql`: replace `<PROJECT-REF>` with your project ref
   (already done on the current project `eedb-v5`).
4. Deploy the function from `supabase/functions/send-push/index.ts` (verify_jwt = OFF; it checks its own secret).

## 4. Test
Log in on the phone (allow notifications), then from another account create a lead or a payment for the same city.
The phone should show a push even when the app is closed. Tapping it opens the right page.

## What triggers a notification
| Event | Who receives it |
|---|---|
| New property / marketplace item / car awaiting review | City admins and agents of that city |
| Listing approved / rejected / sold / rented | The listing owner |
| New customer request (lead) | City admins and agents of that city |
| Payment recorded (pending) | City admins of that city |
| Payment confirmed / rejected | The person who recorded it (and the agent); the property owner if it features their listing |
| New job applicant / job post approved or rejected | The employer |
| New chat message or report | City team (city chats), Super Admin (super chats and reports), or the person who wrote first (replies) |
