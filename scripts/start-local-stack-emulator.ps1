param([switch]$BackendOnly)
& (Join-Path $PSScriptRoot 'start-local-stack.ps1') -Mode emulator -BackendOnly:$BackendOnly
