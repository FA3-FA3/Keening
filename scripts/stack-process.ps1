function Test-StackProcessIdentity([int]$processId, [string]$recordedStart) {
  # Get-Process may return an object whose StartTime is inaccessible or null.
  # Never infer ownership from a PID alone: Windows reuses process IDs.
  $candidate = Get-Process -Id $processId -ErrorAction SilentlyContinue
  if ($null -eq $candidate) { return $false }
  $actualStart = $null
  try { $actualStart = $candidate.StartTime } catch { }
  $usingCim = $false
  if ($null -eq $actualStart) {
    $record = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction Stop
    if ($null -eq $record) { return $false } # Exited during the lookup.
    $actualStart = $record.CreationDate
    $usingCim = $true
  }
  if ($null -eq $actualStart -or [string]::IsNullOrWhiteSpace($recordedStart)) {
    throw "Cannot verify ownership of process $processId; leaving it running and retaining stack state."
  }
  $expected = [DateTimeOffset]::Parse($recordedStart, [Globalization.CultureInfo]::InvariantCulture)
  $actualUtc = ([datetime]$actualStart).ToUniversalTime()
  if ($usingCim) {
    # CIM timestamps have microsecond precision, versus .NET's 100ns ticks.
    return [Math]::Abs(($actualUtc - $expected.UtcDateTime).Ticks) -lt 10
  }
  return $actualUtc.Ticks -eq $expected.UtcDateTime.Ticks
}
