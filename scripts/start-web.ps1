param([ValidateSet('emulator','live')][string]$Mode = 'emulator')
$ErrorActionPreference = 'Stop'
if (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue) {
  throw 'Port 3000 is already in use. Stop the existing web app first.'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$useEmulator = if ($Mode -eq 'emulator') { 'true' } else { 'false' }
Push-Location -LiteralPath $projectRoot
try {
  & flutter.bat run -d chrome --web-hostname=localhost --web-port=3000 "--dart-define=USE_EMULATOR=$useEmulator" --dart-define=API_BASE_URL=http://localhost:8080
  if ($LASTEXITCODE -ne 0) { throw 'Keening web app failed to start.' }
} finally { Pop-Location }
