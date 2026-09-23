# Environment Secrets & Deployment Configuration

## 1. Cloud Functions Environment Variables & Secrets
Run these commands in your local terminal to configure the required secrets for Bunny CDN and PDF signing:

```bash
# Set Bunny CDN Playback Template (replace with your pull zone hostname)
firebase functions:secrets:set BUNNY_PLAYBACK_URL_TEMPLATE
# Value example: https://video.bunnycdn.com/play/{video_id}?quality={quality}

# Set Bunny CDN Token Authentication Secret Key
firebase functions:secrets:set BUNNY_TOKEN_KEY
# Enter your Bunny Token Key when prompted
```

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
