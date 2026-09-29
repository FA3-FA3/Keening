$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location (Join-Path $projectRoot 'cloud-run')
try {
  & gcloud.cmd run deploy keening-api --source=. --project=keening-ece74 `
    --region=europe-west2 `
    --service-account=keening-api@keening-ece74.iam.gserviceaccount.com `
    --build-service-account=projects/keening-ece74/serviceAccounts/keening-build@keening-ece74.iam.gserviceaccount.com `
    --allow-unauthenticated --set-secrets=DATABASE_URL=keening-database-url:1 `
    --env-vars-file=deploy.env.yaml --min-instances=0 --max-instances=2 `
    --concurrency=40 --memory=512Mi --cpu=1 --timeout=30 --quiet
  if ($LASTEXITCODE -ne 0) { throw 'API deployment failed.' }
} finally { Pop-Location }
