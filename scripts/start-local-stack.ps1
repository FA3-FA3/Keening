param(
  [ValidateSet('emulator','live')][string]$Mode = 'emulator',
  [switch]$BackendOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$stateDir = Join-Path $projectRoot '.local'
$stateFile = Join-Path $stateDir 'stack.json'
$pgData = Join-Path $stateDir 'postgres'
if (Test-Path -LiteralPath $stateFile) { throw 'Stack state exists. Run stop-local-stack.ps1 first.' }
$ports = if ($Mode -eq 'emulator') { @(8080,9099,4000,4400,4500,55440) } else { @(8080) }
foreach ($port in $ports) {
  if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
    throw "Port $port is already in use. Existing services were left running."
  }
}
[System.IO.Directory]::CreateDirectory($stateDir) | Out-Null
$state = @{ mode = $Mode; services = @(); postgres = $false }
function Save-State { $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile }
function Start-ServiceProcess([string]$service) {
  $runner = Join-Path $PSScriptRoot 'run-service.ps1'
  $process = Start-Process powershell.exe -WindowStyle Hidden -PassThru `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$runner`" -Service $service -Mode $Mode" `
    -RedirectStandardOutput (Join-Path $stateDir "$service.log") `
    -RedirectStandardError (Join-Path $stateDir "$service-error.log")
  $state.services += @{ pid = $process.Id; started = $process.StartTime.ToUniversalTime().ToString('o') }
  Save-State
}
function Wait-Url([string]$url) {
  $deadline = (Get-Date).AddSeconds(90)
  do {
    try { Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 2 | Out-Null; return } catch { }
    Start-Sleep -Seconds 1
  } while ((Get-Date) -lt $deadline)
  throw "Service did not become ready: $url. Check .local logs."
}
try {
  Save-State
  if ($Mode -eq 'emulator') {
    $pgBin = Split-Path (Get-Command psql.exe -ErrorAction Stop).Source
    if (-not (Test-Path -LiteralPath (Join-Path $pgData 'PG_VERSION'))) {
      & (Join-Path $pgBin 'initdb.exe') -D $pgData -U keening_local -A trust --no-locale -E UTF8
      if ($LASTEXITCODE -ne 0) { throw 'Local Postgres initialization failed' }
    }
    & (Join-Path $pgBin 'pg_ctl.exe') -D $pgData -l (Join-Path $stateDir 'postgres.log') -o '-h 127.0.0.1 -p 55440' -w start
    if ($LASTEXITCODE -ne 0) { throw 'Local Postgres failed to start' }
    $state.postgres = $true
    Save-State
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\01-schema.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Local schema application failed' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\02-usernames.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Username migration failed' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\03-gantt.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Gantt migration failed' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\04-boards.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Boards migration failed' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\05-event-task-links.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Event links migration failed' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\06-calendar.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Independent Calendar migration failed' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\07-schedule.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Schedule migration failed' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\08-profile-picture.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Profile migration failed.' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\09-calendar-sessions.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Calendar sessions migration failed' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\10-calendar-location.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Calendar location migration failed.' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\11-calendar-tags.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Calendar tags migration failed.' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\12-event-panel-links.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Panel links migration failed.' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\13-calendar-session-panel-links.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Calendar/session panel links migration failed.' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\14-pads.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Pads migration failed.' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\15-pad-descriptions.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Pad descriptions migration failed.' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\16-document-folders.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Document folders migration failed.' }
    & (Join-Path $pgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\17-attachments.sql') 'postgresql://keening_local@127.0.0.1:55440/postgres'
    if ($LASTEXITCODE -ne 0) { throw 'Attachments migration failed.' }
    Start-ServiceProcess 'auth'
    Wait-Url 'http://127.0.0.1:9099/'
  }
  Start-ServiceProcess 'api'
  Wait-Url 'http://127.0.0.1:8080/health'
  Write-Output "Keening $Mode stack ready. API: http://localhost:8080"
  $useEmulator = if ($Mode -eq 'emulator') { 'true' } else { 'false' }
  Write-Output "Start Flutter separately: flutter run -d chrome --dart-define=USE_EMULATOR=$useEmulator"
  Write-Output 'The local API accepts any localhost web port. No browser was launched.'
} catch {
  & (Join-Path $PSScriptRoot 'stop-local-stack.ps1')
  throw
}
