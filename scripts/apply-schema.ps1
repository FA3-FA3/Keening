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
& $psql.Source -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\02-usernames.sql') $databaseUrl
if ($LASTEXITCODE -ne 0) { throw 'Username migration failed.' }
& $psql.Source -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\03-gantt.sql') $databaseUrl
if ($LASTEXITCODE -ne 0) { throw 'Gantt migration failed.' }
& $psql.Source -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\04-boards.sql') $databaseUrl
if ($LASTEXITCODE -ne 0) { throw 'Boards migration failed.' }
& $psql.Source -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\05-event-task-links.sql') $databaseUrl
if ($LASTEXITCODE -ne 0) { throw 'Event links migration failed.' }
& $psql.Source -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\06-calendar.sql') $databaseUrl
if ($LASTEXITCODE -ne 0) { throw 'Independent Calendar migration failed.' }
& $psql.Source -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\07-schedule.sql') $databaseUrl
if ($LASTEXITCODE -ne 0) { throw 'Schedule migration failed.' }
& $psql.Source -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\08-profile-picture.sql') $databaseUrl
if ($LASTEXITCODE -ne 0) { throw 'Profile picture migration failed.' }
& $psql.Source -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\09-calendar-sessions.sql') $databaseUrl
if ($LASTEXITCODE -ne 0) { throw 'Calendar sessions migration failed.' }
& $psql.Source -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\10-calendar-location.sql') $databaseUrl
if ($LASTEXITCODE -ne 0) { throw 'Calendar location migration failed.' }
& $psql.Source -X -v ON_ERROR_STOP=1 -f (Join-Path $projectRoot 'postgres\init\11-calendar-tags.sql') $databaseUrl
    if ($LASTEXITCODE -ne 0) { throw 'Calendar tags migration failed.' }
Write-Output 'Keening schema applied successfully.'
