# Google Play checklist - Eastern Ethiopia Digital Broker (V6)

## Before upload
- [ ] Create a permanent signing key once (keep the .jks file and passwords safe, in two places).
- [ ] Add GitHub secrets KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD, then run Actions -> Android Build -> release.
- [ ] Upload the `.aab` file to Play Console (Production or Internal testing first).
- [ ] Fill the [SQUARE BRACKET] items in `privacy.html` and `terms.html`, host both on a public web page
      (Play requires a public Privacy Policy URL) - e.g. GitHub Pages - and paste that URL in Play Console.
- [ ] Remove demo data: run `DEMO_DATA_CLEANUP.sql`.
- [ ] Supabase: Confirm email OFF (or add email-confirmation flow), set a real Super Admin account.
- [ ] Supabase: enable Point-in-time/daily backups (Pro plan) before real customers arrive.

## Store listing text (edit freely)
- App name: Eastern Ethiopia Digital Broker
- Short description (80): Buy, sell, rent and find jobs in Dire Dawa, Harar, Jigjiga and Haramaya.
- Full description: Eastern Ethiopia Digital Broker connects people and trusted local brokers. Browse houses,
  cars, goods and jobs in your city, send a call-back request, and deal with verified brokers.
  Owners and employers can post listings and jobs; city administrators review posts so the marketplace stays reliable.
- Category: House & Home (or Business). Contact email + privacy policy URL required.

## Graphics needed
- App icon 512x512 PNG, feature graphic 1024x500, at least 2 phone screenshots (take 6-8: home, property details,
  marketplace, cars, jobs, agent dashboard, investor overview).

## Data safety form (answers that match this app)
- Collects: name, email, phone number, photos, files (CV), user-generated content, app activity (contact requests).
- Purpose: app functionality, account management. Not used for ads. Not sold.
- Data encrypted in transit: Yes (HTTPS). Users can request data deletion: Yes (via support email; add a delete-account flow for best compliance).
- No location permission, no camera permission, no contacts access.

## Content rating
- Questionnaire: user-generated content (listings/jobs), no violence, no gambling. Expect "Everyone"/"3+".

## Requirements to keep in mind
- Target API level: this project targets Android 16 (API 36). Google raises the minimum every year, update `targetSdk` then.
- Test on 2-3 real phones (small screen, Android 8, Android 14) before submitting.
