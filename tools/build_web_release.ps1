#Requires -Version 5.1
<#
.SYNOPSIS
  Release build of the Main Flutter Web app with the App Check
  reCAPTCHA Enterprise site key injected via --dart-define.

.DESCRIPTION
  lib/main.dart refuses to boot a release web build when
  RECAPTCHA_SITE_KEY is empty (StateError guard). This script is the
  single supported local entry point for that build: it reads the key
  from the process environment (never from a file, never committed)
  and passes it to `flutter build web --release`.

  Key source of truth: the reCAPTCHA Enterprise key named
  "Dr Tarek Platform Web" (Google Cloud Console), registered for the
  Main Web Firebase App (see env_secrets_guide.md section 5).
  Do NOT substitute the Dashboard key — each Firebase Web App has
  its own App Check configuration.

.EXAMPLE
  $env:RECAPTCHA_SITE_KEY = '<site-key-from-owner-or-console>'
  .\tools\build_web_release.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$siteKey = $env:RECAPTCHA_SITE_KEY
if ([string]::IsNullOrWhiteSpace($siteKey)) {
    Write-Error @'
RECAPTCHA_SITE_KEY is not set in this session.

  $env:RECAPTCHA_SITE_KEY = '<Main-Web site key>'
  .\tools\build_web_release.ps1

Obtain the value (once) from the Project Owner or from
Google Cloud Console > reCAPTCHA Enterprise > key "Dr Tarek Platform Web".
Never commit the value to git, never paste it into source files.
See env_secrets_guide.md section 5.
'@
    exit 1
}

& flutter build web --release --dart-define=RECAPTCHA_SITE_KEY=$siteKey
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build web --release failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}

Write-Output 'Main Web release build completed (build/web).'
