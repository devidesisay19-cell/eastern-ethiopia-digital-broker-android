# Eastern Ethiopia Digital Broker — Android

Android Studio project that packages the supplied Eastern Ethiopia Digital Broker web application into a native Android WebView shell.

## Open and run

1. Open this folder in Android Studio.
2. Let Gradle sync.
3. Use JDK 17 for the Gradle/Android toolchain.
4. Install Android SDK Platform 36.
5. Run the `app` configuration on an emulator or device.

The project uses a standard Android app module structure (`app/src/main/AndroidManifest.xml`, `java`, `res`, and `assets/web`).

## Architecture

The original HTML/JS pages are retained under `app/src/main/assets/web/`. `MainActivity` serves them through AndroidX WebView's `WebViewAssetLoader`, which provides an HTTPS-style local origin. External Supabase API calls remain HTTPS.

The Supabase browser SDK is pinned to `@supabase/supabase-js@2.116.0` instead of the original floating `@2` URL.

## Backend

The supplied app already contains its Supabase project URL and publishable key in `app/src/main/assets/web/supabase.js`. Do not replace the publishable key with a Supabase service-role key.

Run the supplied SQL migrations/patches in Supabase according to the project's deployment notes before production release.

## GitHub

Recommended repository name: `eastern-ethiopia-digital-broker-android`.

```bash
git init
git add .
git commit -m "Create Android Studio project for Eastern Ethiopia Digital Broker"
git branch -M main
git remote add origin <YOUR_GITHUB_REPOSITORY_URL>
git push -u origin main
```

## Production signing

Configure a release keystore and signing settings in your private CI/release environment. Never commit keystore files or passwords.
