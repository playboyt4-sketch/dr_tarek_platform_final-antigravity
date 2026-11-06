# Environment Secrets & Deployment Configuration

## 1. Cloud Functions Environment Variables & Secrets
Run these commands in your local terminal to configure the required secrets for Bunny CDN and PDF signing:

```bash
# Set Bunny CDN Playback Template (replace with your pull-zone hostname).
# The value MUST be the direct-play URL served by the Stream pull zone:
firebase functions:secrets:set BUNNY_PLAYBACK_URL_TEMPLATE
# Value example: https://<pull-zone-hostname>.b-cdn.net/{video_id}/playlist.m3u8
# Do NOT use https://video.bunnycdn.com/play/{video_id}?quality={quality}:
# that is the Stream management/embed host, not a playable pull-zone URL,
# and it returns 403 Forbidden when opened with a CDN token.

# Set Bunny CDN Token Authentication Secret Key.
# Use the Stream library's Token Authentication key (Security tab of the
# Stream pull zone), NOT the storage-zone password and NOT the Stream API key.
firebase functions:secrets:set BUNNY_TOKEN_KEY
# Enter your Bunny Token Key when prompted
```

Requirements on the Bunny pull zone (otherwise signed playback still fails
with `403 Forbidden`):

- Token Authentication: **Advanced (HMAC)**. Query-string/Basic mode does not
  match the directory-token URLs this backend issues.
- The key in `BUNNY_TOKEN_KEY` must be the key configured for that pull zone's
  token authentication (rotating it invalidates all live signed URLs).
- Hotlink protection may reject an EMPTY `Referer`, but must accept the fixed
  `Referer` the app sends (`bunnyPlaybackHttpHeaders` in
  `lib/core/constants/bunny_playback_headers.dart`). Do not configure a
  rule that only accepts a specific browser origin.

## 2. Deploy Firestore Indexes & Security Rules
```bash
# Deploy all 18 composite indexes
firebase deploy --only firestore:indexes

# Deploy locked-down security rules
firebase deploy --only firestore:rules
firebase deploy --only storage:rules
```

## 3. Deploy Cloud Functions
```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```

## 4. Run the Initial Seeding Script
```bash
# In the functions directory:
npx ts-node src/scripts/seed_database.ts "010XXXXXXXX"
# (Pass Dr. Tarek's registered phone number to automatically assign Teacher role)

## 5. Main Web Release — RECAPTCHA_SITE_KEY (App Check, reCAPTCHA Enterprise)

The Main Flutter Web app (Firebase App `dr_tarek_platform (web)`) refuses
to boot a release build without its own reCAPTCHA Enterprise site key
(`StateError` guard in `lib/main.dart`). Rules:

- Use ONLY the key named "Dr Tarek Platform Web" (Google Cloud Console >
  reCAPTCHA Enterprise), registered for the Main Web Firebase App in
  Firebase Console > App Check. Never substitute the Dashboard key.
- Never commit the value: not in Dart files, not in workflow files,
  not in `.env` files. `String.fromEnvironment` keeps it out of source.
- Local release build (single supported entry point):
  ```powershell
  $env:RECAPTCHA_SITE_KEY = '<site-key-from-owner-or-console>'
  .\tools\build_web_release.ps1
  ```
  The script fails fast with instructions when the variable is unset.
- CI (`web-build` job) reads the GitHub secret `RECAPTCHA_SITE_KEY`,
  which the Project Owner creates once from the same key value.
```
