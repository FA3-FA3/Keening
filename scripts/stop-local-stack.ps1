$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$stateFile = Join-Path $projectRoot '.local\stack.json'
if (-not (Test-Path -LiteralPath $stateFile)) { Write-Output 'No Keening stack is recorded.'; return }
$state = Get-Content -Raw -LiteralPath $stateFile | ConvertFrom-Json
function Stop-ProcessTree([int]$processId) {
  $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$processId")
  foreach ($child in $children) { Stop-ProcessTree $child.ProcessId }
  Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
}
foreach ($service in $state.services) {
  $process = Get-Process -Id $service.pid -ErrorAction SilentlyContinue
  if ($process -and $process.StartTime.ToUniversalTime().ToString('o') -eq $service.started) {
    Stop-ProcessTree $service.pid
  }
}
if ($state.postgres) {
  $pgBin = Split-Path (Get-Command psql.exe).Source
  $pgData = Join-Path $projectRoot '.local\postgres'
  & (Join-Path $pgBin 'pg_ctl.exe') -D $pgData status | Out-Null
  if ($LASTEXITCODE -eq 0) {
    & (Join-Path $pgBin 'pg_ctl.exe') -D $pgData -m fast -w stop
    if ($LASTEXITCODE -ne 0) { throw 'Postgres shutdown failed; retaining stack state.' }
  }
}
Remove-Item -LiteralPath $stateFile
Write-Output 'Keening stack stopped. Local database files are preserved.'
