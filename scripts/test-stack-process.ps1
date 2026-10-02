$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'stack-process.ps1')
$script:fakeProcess = $null
$script:fakeCim = $null
function Get-Process { param($Id,$ErrorAction) return $script:fakeProcess }
function Get-CimInstance { param($ClassName,$Filter,$ErrorAction) return $script:fakeCim }
$stamp = [datetime]::Parse('2026-09-30T21:49:54.9354049Z').ToUniversalTime()
function Assert-Identity($expected, $label) {
  $actual = Test-StackProcessIdentity 123 ($stamp.ToString('o'))
  if ($actual -ne $expected) { throw "Failed: $label" }
  Write-Output "PASS: $label"
}
Assert-Identity $false 'exited process'
$script:fakeProcess = [pscustomobject]@{ StartTime=$stamp }
Assert-Identity $true 'matching process'
$script:fakeProcess = [pscustomobject]@{ StartTime=$stamp.AddMinutes(1) }
Assert-Identity $false 'reused PID'
$script:fakeProcess = [pscustomobject]@{ StartTime=$null }
$script:fakeCim = [pscustomobject]@{ CreationDate=$stamp.AddMinutes(1) }
Assert-Identity $false 'missing StartTime with reused PID'
$script:fakeCim = [pscustomobject]@{ CreationDate=$stamp.AddTicks(-9) }
Assert-Identity $true 'CIM microsecond precision'
$script:fakeCim = $null
Assert-Identity $false 'process exited during lookup'
$script:fakeCim = [pscustomobject]@{ CreationDate=$null }
$failed = $false
try { Test-StackProcessIdentity 123 ($stamp.ToString('o')) | Out-Null } catch { $failed = $true }
if (-not $failed) { throw 'Unverifiable ownership must retain state.' }
Write-Output 'PASS: unverifiable ownership fails safely'
