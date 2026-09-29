# Keening

Keening Flutter web frontend with a header, footer, and home page using a
green and charcoal palette. The hero has a solid background without images
or taglines. Anonymous sign-in uses Firebase Authentication; the dashboard
requires a signed-in user. No email, password, or pre-created account is needed.
The initial users schema is applied to Neon Postgres. The Fastify API verifies
Firebase tokens and provisions profiles. The app is live at
https://keening-ece74.web.app and the API runs in Cloud Run, London.

## Structure

```text
lib/
  main.dart
  router.dart
  pages/
  widgets/
  utils/
assets/images/
test/widget/
web/
```

## Run with local authentication

Start the Auth Emulator, API, and isolated local Postgres database:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-local-stack-emulator.ps1
```

In another terminal, run the app and choose **Log In → Continue anonymously**:

```sh
flutter pub get
flutter run -d chrome --web-port=3000
```

Debug builds use the emulator at localhost:9099 by default. Demo accounts are
separate from real Firebase accounts, and are discarded when the emulator stops.
The local database is preserved between runs. Stop all services with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/stop-local-stack.ps1
```

Equivalent `.sh` wrappers are available for Git Bash on Windows. PostgreSQL
tools, Firebase CLI, Node, and Flutter must be on PATH; run `npm ci` in
`cloud-run/` once after checkout. Logs and process state are in ignored `.local/`.

## Run with live authentication

The web app is registered in Firebase project `keening-ece74`. Enable the
Anonymous provider in Firebase Authentication → Sign-in method.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-local-stack-live.ps1
flutter run -d chrome --web-port=3000 --dart-define=USE_EMULATOR=false
```

Choose **Continue anonymously**, then click **Check sign-in token** on the dashboard
in a debug build. If an earlier email session is still active, sign out first.
This retrieves the token and checks its subject and anonymous provider locally without displaying,
logging, or uploading the token. Sign out to check that the dashboard is protected.

**Check API connection** sends the signed-in user's token to `/whoami` and
provisions their profile. Emulator mode writes only to local Postgres. Live mode
uses the real Neon database. ADC credentials must be available for live mode
(`gcloud auth application-default login` if they need refreshing).

## Checks

```powershell
flutter analyze
flutter test
```

## Build

```sh
flutter build web
```

Build output is written to `build/web`.
Release builds always use live Firebase authentication, even if USE_EMULATOR=true.
Set `--dart-define=API_BASE_URL=https://<deployed-service>` when building for
deployment. An unconfigured release never falls back to localhost.

## Deploy updates

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/deploy-api.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/deploy-web.ps1
```

The web deployment script resolves the deployed API URL, builds Flutter, and
publishes only Keening's Firebase Hosting site. The API script uses the dedicated
runtime identity and the pinned DATABASE_URL secret version.

See [backend setup status](docs/backend-setup.md) and [deployment details](docs/deployment.md).
