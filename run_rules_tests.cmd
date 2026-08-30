@echo off
cd /d "%~dp0security-tests"
firebase emulators:exec --only firestore,storage --project dr-tarek-platform-emulator "npm test"
