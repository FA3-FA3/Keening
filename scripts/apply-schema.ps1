[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot '.env.local'
$schemaPath = Join-Path $projectRoot 'postgres\init\01-schema.sql'
$psql = Get-Command psql -ErrorAction Stop

if (-not (Test-Path -LiteralPath $envPath)) {
    throw 'Create .env.local with DATABASE_URL for the Keening database first.'
}

$entries = @(Get-Content -LiteralPath $envPath | Where-Object {
    $_ -match '^\s*DATABASE_URL\s*='
})
if ($entries.Count -ne 1) {
    throw '.env.local must contain exactly one DATABASE_URL entry.'
}
$databaseUrl = ($entries[0] -replace '^\s*DATABASE_URL\s*=\s*', '').Trim()
if ($databaseUrl.Length -ge 2 -and (
    ($databaseUrl.StartsWith('"') -and $databaseUrl.EndsWith('"')) -or
    ($databaseUrl.StartsWith("'") -and $databaseUrl.EndsWith("'"))
)) {
    $databaseUrl = $databaseUrl.Substring(1, $databaseUrl.Length - 2)
}
if ($databaseUrl -notmatch '^postgres(ql)?://') {
    throw 'DATABASE_URL must contain a PostgreSQL connection URI.'
}

# Keep -f BEFORE the connection URI for this machine's psql build.
# -X ignores personal psql startup files; stop immediately on SQL errors.
& $psql.Source -X -v ON_ERROR_STOP=1 -f $schemaPath $databaseUrl
if ($LASTEXITCODE -ne 0) {
    throw 'Schema application failed. Review the psql error above.'
}
Write-Output 'Keening schema applied successfully.'
