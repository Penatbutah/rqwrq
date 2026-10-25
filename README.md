# QR Attendance (Flutter)

Native Android app, same features as the HTML version:
teacher + student accounts (login/registration), student list, timed sessions that
mark unscanned students absent, several sessions at once, per-session QR codes, and a
screenshot block. QR codes and passes use the same format as the HTML version, so the two
apps understand each other.

## Files
- `lib/core.dart`  pure Dart logic: SHA-256/HMAC/PBKDF2, QR text, passes, scan checking, models (tested)
- `lib/main.dart`  the screens (Flutter)
- `pubspec.yaml`   packages: shared_preferences, mobile_scanner, qr_flutter
- `.github/workflows/build-flutter-apk.yml`  builds the APK on GitHub (no installs needed)

## Build the APK with GitHub (no computer setup)
1. Make a new GitHub repo and upload everything in this folder (keep `lib` and `.github`).
2. Open the Actions tab, pick "Build Flutter APK", press Run workflow.
3. When it is green (about 8 to 12 minutes), open the run and download `qr-attendance-flutter-apk`.
4. Unzip it, install `app-release.apk` on your phone, allow camera.

## Run it yourself (optional)
Install Flutter, then in this folder:
    flutter create --org com.peanut --project-name qr_attendance --platforms=android .
    (keep our lib/ files and pubspec.yaml if it asks)
    flutter pub get
    flutter run

For the screenshot block and camera permission on a local build, copy the two steps from
the workflow file (they edit AndroidManifest.xml and MainActivity.kt).

## Notes
- Data is stored on the phone, per device, like the HTML version.
- Passes travel by copy and paste. Students enter the session code at the start of each class.
- Screenshots and screen recording are blocked in the whole app (Android FLAG_SECURE).

## Parent emails
In the Students tab, add an optional parent email for each student and tap Save. On a class (Class tab or History tab) tap "Email parents" to open your email app with a ready message such as "Maya came in class Math at 7:16 AM on Oct 25, 2026."
