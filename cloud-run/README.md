# Keening API

Fastify on Node 24 with Firebase Admin authentication and Postgres profiles.

- `GET /health`: public liveness check; does not query the database.
- `GET /whoami`: requires `Authorization: Bearer <Firebase ID token>`, verifies
  token validity/revocation, and atomically provisions or updates the user.
  Returns `{ firebaseUid, email, anonymous }`; internal UUIDs stay in the database.

## Configuration

Run `npm ci` then `npm start`. The server loads `cloud-run/.env`; existing process
environment variables take precedence. See `.env.example`. Use ADC for live
Firebase via `gcloud auth application-default login`; use the Cloud Run runtime
service identity after deployment, with Firebase Auth read permission for the
revocation/disabled-user check. No downloaded service-account key is needed.

The local scripts set a fixed browser origin on port 3000. Production requires
explicit `CORS_ORIGINS` and disallows emulator tokens. Emulator mode requires
a demo Firebase project and local Postgres, so emulator identities cannot be
written to the configured Neon database accidentally.

## Tests

`npm test` runs API/config tests. Set `TEST_DATABASE_URL` to a local database with
the schema installed to include the concurrent profile-provisioning test.
`npm run test:local` checks the running emulator stack with an anonymous account,
verifies the API response and database row, then removes its test account/row.

The scoped uuid dependency override fixes an advisory in gaxios's transitive
dependency; gaxios uses the compatible v4 API. `npm audit --omit=dev` is clean.

## Container

`Dockerfile` uses Node 24 and runs as the unprivileged node user. Environment files
are excluded from both Docker and gcloud uploads. Cloud Build successfully built
the image and deployed it to Cloud Run in `europe-west2` on 2026-09-29.

API: https://keening-api-321783087335.europe-west2.run.app

Production CORS allows only Keening's `.web.app` and `.firebaseapp.com` origins.
`DATABASE_URL` comes from Secret Manager, pinned to version 1. The runtime account
can access only that secret and perform the Firebase user lookup needed for
revocation checks. See `../docs/deployment.md` for redeployment instructions.
