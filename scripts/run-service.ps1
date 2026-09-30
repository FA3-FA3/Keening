param(
  [ValidateSet('api','auth')][string]$Service,
  [ValidateSet('emulator','live')][string]$Mode
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$env:NODE_ENV = 'development'
Remove-Item Env:\K_SERVICE -ErrorAction SilentlyContinue
if ($Service -eq 'auth') {
  Set-Location -LiteralPath $projectRoot
  & firebase.cmd emulators:start --only auth --project demo-keening
} else {
  $env:PORT = '8080'
  $env:HOST = '127.0.0.1'
  $env:CORS_ORIGINS = 'http://localhost:3000,http://127.0.0.1:3000'
  if ($Mode -eq 'emulator') {
    $env:FIREBASE_PROJECT_ID = 'demo-keening'
    $env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
    $env:DATABASE_URL = 'postgresql://keening_local@127.0.0.1:55440/postgres'
  } else {
    $env:FIREBASE_PROJECT_ID = 'keening-ece74'
    # User ADC needs a quota project for Firebase Auth admin requests.
    $env:GOOGLE_CLOUD_QUOTA_PROJECT = 'keening-ece74'
    Remove-Item Env:\FIREBASE_AUTH_EMULATOR_HOST -ErrorAction SilentlyContinue
    # Load Keening's own .env via server.js, ignoring inherited database URLs.
    Remove-Item Env:\DATABASE_URL -ErrorAction SilentlyContinue
  }
  Set-Location -LiteralPath (Join-Path $projectRoot 'cloud-run')
  & npm.cmd start
}
exit $LASTEXITCODE
