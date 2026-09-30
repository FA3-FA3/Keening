# Backend setup sequence

## Current authentication update (2026-09-29)

Email/password login and invite-code registration now replace the anonymous test flow described in the historical phases below. Registration collects email, unique username, password and code. Code validation happens in Cloud Run using Secret Manager; direct Firebase signup is disabled. The additive username migration is applied to Neon. See deployment.md for current settings.

## Historical implementation

All phases are complete. On 2026-09-29 the owner confirmed billing was attached
and authorized the remaining deployment and live verification steps.

## Phase 1: Firebase client authentication

- Firebase project: `keening-ece74` (created by the owner).
- FlutterFire CLI was already installed; registered the web app and generated
  `lib/firebase_options.dart` using that CLI.
- Added Firebase Core and Auth, anonymous login, guarded dashboard,
  auth-state router refresh, sign-out, and a debug-only ID-token check.
- Firebase reads in widgets/router are guarded for tests without initialization.
- Debug defaults to the isolated `demo-keening` Auth Emulator on port 9099.
  Live debug requires `--dart-define=USE_EMULATOR=false`; release always uses live auth.
- Per the updated request, anonymous sign-in replaces email/password testing.
  No pre-created user is needed; the token check verifies the anonymous provider.
- Anonymous sign-in is enabled and was verified against live Firebase in Chrome.
- Validation: static analysis, widget tests, and release web compilation pass.
  A Chrome browser smoke test verified anonymous emulator login, token checking,
  API profile provisioning, sign-out, and signed-out dashboard redirection.
  Fixed emulator initialization to create the default Firebase app explicitly.
  The production Flutter build also passed the live Firebase/Cloud Run/Neon flow.
- Tokens are checked locally; there is no need to paste credentials or tokens
  into chat or a token-decoding website.

To regenerate the Firebase config in PowerShell:

```powershell
& "$env:LOCALAPPDATA\Pub\Cache\bin\flutterfire.bat" configure --project=keening-ece74 --platforms=web --yes
```

## Phase 2: Postgres / Neon (complete)

- Prepared `postgres/init/01-schema.sql` with internal UUID, unique Firebase UID,
  nullable email for anonymous users, and creation timestamp.
- Saved the supplied Keening DATABASE_URL in ignored `.env.local` and
  `cloud-run/.env`. Public `.env.example` files contain no credentials.
- Applied the schema to `neondb` on Neon PostgreSQL 18.6 in eu-west-2 after
  explicit user authorization on 2026-09-28.
- Read-only verification confirmed all four columns, UUID/timestamp defaults,
  primary key, unique Firebase UID, and nullable email. The table has zero rows.
- `scripts/apply-schema.ps1` applied the schema, stopping on SQL errors
  and placing `-f` before the connection argument as required on this machine.
- Rotate the database password shared in chat, then update both ignored files.

## Phase 3: Cloud Run API (implemented and tested)

- Fastify/Node service in `cloud-run/` with Firebase Admin token verification,
  revocation checks, bounded Postgres pool, and atomic profile upsert by Firebase UID.
- `/health` is public; `/whoami` requires a valid token and returns Firebase UID,
  nullable email, and anonymous status. Internal UUIDs remain private.
- Ten API/config/database tests passed, including concurrent provisioning.
  Dependency audit reports zero vulnerabilities.
- ADC credentials refreshed successfully. Cloud Run uses its dedicated runtime identity.

## Phase 4: Local stack (implemented)

- Added PowerShell start/stop scripts with Git Bash `.sh` wrappers. Emulator mode
  uses isolated local Postgres; live mode uses existing Neon configuration.
- Scripts launch `npm start`, track owned processes, and stop without killing
  unrelated services. Local database files are preserved. Both launch modes and
  shutdown were exercised; ports were released successfully.
- Automated local anonymous sign-in -> Firebase Admin verification -> Postgres
  provisioning passed, including repeated requests producing only one profile.
- Flutter dashboard includes **Check API connection**; API_BASE_URL is supplied
  by dart-define, with localhost only as a debug default and HTTPS required in release.
- Flutter analysis and four tests pass. Release web build passes.
- The actual Flutter debug build also passed the complete Chrome browser flow
  against the local Auth Emulator, API, and Postgres.
- Live Firebase + Neon provisioning passed in Chrome on 2026-09-29. Repeated API
  requests created one profile. Sign-out and protected-route redirection passed.
  Temporary live test accounts and their database rows were removed afterward.

## Phase 5: Deployment (complete)

- Added Dockerfile (Node 24, non-root runtime), `.dockerignore`, and `.gcloudignore`.
  Cloud Build successfully built the container and Cloud Run started it.
- CORS requires explicit origins in production. Emulator mode is rejected in
  production and cannot target Neon.
- Billing confirmed enabled; required APIs enabled. Created separate builder and
  runtime identities. Runtime permissions are scoped to Firebase user lookup
  and the database connection secret.
- DATABASE_URL is in Secret Manager, version 1. Deployed `keening-api` in London
  with zero minimum instances and a two-instance maximum.
- Flutter is published at https://keening-ece74.web.app with the live API URL.
- Verified health, rejection of missing/invalid tokens, exact-origin CORS, and
  the complete live browser/database flow. See [deployment details](deployment.md).
