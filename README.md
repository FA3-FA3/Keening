# Keening

Keening Flutter web frontend with a header, footer, and home page using a
green and charcoal palette. The hero has a solid background without images
or taglines. Email/password sign-in uses Firebase Authentication. Choose **Log In ? Create an account** to register with email, username, password, and an invitation code. The backend validates the code; direct Firebase client signup and anonymous login are disabled.
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

The startup script does not launch Chrome. In another terminal, run `flutter run -d chrome`. The local API accepts the localhost port Flutter chooses.

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

The web app is registered in Firebase project `keening-ece74`. Email/password authentication is enabled; anonymous authentication and direct client signup are disabled.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-local-stack-live.ps1
flutter run -d chrome --dart-define=USE_EMULATOR=false
```

Create an account with your invitation code, then use **Log In** with its email and password. The debug token check verifies the password provider without displaying or logging the token.

**Check API connection** sends the signed-in user's token to `/whoami` and
provisions their profile. Emulator mode writes only to local Postgres. Live mode
uses the real Neon database. ADC credentials must be available for live mode
(`gcloud auth application-default login` if they need refreshing).

Both stack scripts start backend services only. Launch Flutter separately using the command printed by the script. Arbitrary localhost web ports are accepted only by the development API bound to loopback; production still uses exact configured origins. `-BackendOnly` remains accepted for compatibility. The optional `start-web.ps1` helper and VS Code launch configurations still use port 3000 if you prefer a fixed port.

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
runtime identity and pinned DATABASE_URL and REGISTRATION_CODE secret versions.

See [backend setup status](docs/backend-setup.md) and [deployment details](docs/deployment.md).

Registration requires REGISTRATION_CODE in the ignored cloud-run/.env for local development. Never put its value in Flutter or public configuration. Usernames use 3?30 letters, numbers or underscores and are unique without regard to case. Passwords use 8?128 characters. Run scripts/apply-schema.ps1 to apply the additive username migration to an existing database.

The Gantt workspace supports user-created calendars with saved tasks/events, date ranges, dependencies and row ordering. See [Gantt setup and behavior](docs/gantt.md).

The Boards tab adapts Sorbit tasks into private, user-created workplaces. Panels, draggable tasks, tags, completion, and archive/restore are saved in Neon. See [Boards setup and behavior](docs/boards.md).

UI convention: use `AppDropdownButton` and `AppDropdownButtonFormField` from
`lib/widgets/app_dropdown.dart` for new dropdowns. Their rounded button highlights
and menus match the app's rounded action buttons. Material dropdown and popup
menus also receive the shared shape through both application themes.
