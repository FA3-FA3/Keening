# Keening production deployment

Deployed and verified on 2026-09-29 in Firebase/GCP project `keening-ece74`.

- Web app: https://keening-ece74.web.app
- Alternate Hosting domain: https://keening-ece74.firebaseapp.com
- API: https://keening-api-321783087335.europe-west2.run.app
- API URL reported by gcloud (used in the Flutter build): https://keening-api-7vt2rnct2a-nw.a.run.app
- Cloud Run service/region: `keening-api` / `europe-west2`.
- Current revision: `keening-api-00002-2pb` (email/password and invite registration).
- Cloud Build: `5604aeb1-d6b5-428b-831e-b2970a1ee3bb` (successful Dockerfile build).
- Firebase Hosting version: `c2dc8999ca5d458a`.

## Infrastructure and access

Billing was already linked by the owner. Enabled Cloud Run, Cloud Build,
Artifact Registry, Secret Manager, and IAM APIs.

Runtime identity: `keening-api@keening-ece74.iam.gserviceaccount.com`.
Its custom `keeningAuthReader` role grants Firebase user get/create/update/delete for verification and invite registration. Secret accessor is scoped to `keening-database-url` and `keening-registration-code`, both pinned at version 1 as DATABASE_URL and REGISTRATION_CODE; credentials are excluded from source uploads and the image.

Build identity: `keening-build@keening-ece74.iam.gserviceaccount.com`, with the
Cloud Run Builder role. No service-account keys were downloaded.

The Node 24 image runs as the unprivileged node user. Cloud Run uses one CPU,
512 MiB memory, concurrency 40, a 30-second request timeout, zero minimum
instances, and a maximum of two instances.

Cloud Run invocation is public intentionally: `/health` is public, while
`/whoami` requires Firebase ID-token validation and revocation checks. Internal
UUIDs are never returned. Production CORS allows only the two Hosting origins
above, not localhost or arbitrary origins. Emulator mode is rejected in production.

## Verified

- Cloud Build container build, successful startup, and revision serving traffic.
- `/health` returns 200; missing or invalid authentication returns 401.
- CORS permits Keening's origin and excludes an unrelated origin.
- Actual hosted Flutter app in headless Chrome: email/password sign-in,
  authenticated API requests, one matching Neon profile,
  sign-out, and signed-out dashboard redirection.
- Temporary test accounts and their matching rows were deleted after verification.

## Deploy updates

From the project root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/deploy-api.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/deploy-web.ps1
```

The API script builds from `cloud-run/` with `deploy.env.yaml` and the pinned
secret version. The web script resolves the service URL, supplies API_BASE_URL
at build time, and deploys only Hosting. Release builds always use live Firebase.

When rotating database credentials, update the ignored local environment files,
add a new Secret Manager version, update the pinned version in `deploy-api.ps1`,
and redeploy. Never put credentials in the public YAML or Flutter configuration.

Source deployment reference:
https://cloud.google.com/run/docs/deploying-source-code

## Invite registration

POST /register validates the server-side secret before creating a disabled Firebase account, inserting its username profile, and enabling sign-in. Failures compensate newly created accounts. Usernames have a case-insensitive unique index (`postgres/init/02-usernames.sql`). Registration is limited to 10 requests per minute per observed IP per container; this is an in-memory throttle, not a distributed quota.

Firebase client.permissions.disabledUserSignup is true, email/password is enabled, and anonymous login is disabled. Admin creation is permitted. Existing anonymous tokens are rejected by the API. No password or registration code is stored in Postgres or compiled into Flutter.

Reference: https://docs.cloud.google.com/identity-platform/docs/reference/rest/v2/Config

Verified after deployment: wrong code rejected with no profile, successful registration and automatic email sign-in, repeated /whoami returns the same username profile, case-insensitive duplicate username rejected, direct Firebase signup returns ADMIN_ONLY_OPERATION, email re-login, logout and signed-out dashboard redirect. Temporary live fixture removed. All 17 backend tests (including local Postgres concurrency), local registration integration, 5 Flutter tests, static analysis and release build pass.
