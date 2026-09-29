# Keening production deployment

Deployed and verified on 2026-09-29 in Firebase/GCP project `keening-ece74`.

- Web app: https://keening-ece74.web.app
- Alternate Hosting domain: https://keening-ece74.firebaseapp.com
- API: https://keening-api-321783087335.europe-west2.run.app
- API URL reported by gcloud (used in the Flutter build): https://keening-api-7vt2rnct2a-nw.a.run.app
- Cloud Run service/region: `keening-api` / `europe-west2`.
- Initial revision: `keening-api-00001-w25`.
- Cloud Build: `5604aeb1-d6b5-428b-831e-b2970a1ee3bb` (successful Dockerfile build).
- Firebase Hosting version: `1671b56ad7345692`.

## Infrastructure and access

Billing was already linked by the owner. Enabled Cloud Run, Cloud Build,
Artifact Registry, Secret Manager, and IAM APIs.

Runtime identity: `keening-api@keening-ece74.iam.gserviceaccount.com`.
Its custom `keeningAuthReader` role contains only `firebaseauth.users.get` for
revocation/disabled-user checks. Secret accessor is granted on the
`keening-database-url` secret only. The container receives version **1** as
DATABASE_URL; credentials are excluded from source uploads and the image.

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
- Actual hosted Flutter app in headless Chrome: anonymous Firebase sign-in,
  two authenticated API requests, one matching Neon profile with nullable email,
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
