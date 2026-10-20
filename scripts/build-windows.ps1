# Builds the Windows desktop app (needs Visual Studio with the "Desktop development with C++" workload).
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
flutter pub get
flutter build windows --release
Write-Host "Built: build\windows\x64\runner\Release\keening.exe (ship the whole Release folder)"
