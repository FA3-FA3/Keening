# Builds the Windows app and packs it into an installer: dist\Keening-Setup-<version>.exe
# Needs Visual Studio (Desktop development with C++) and Inno Setup 6
# (winget install JRSoftware.InnoSetup).
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value)

if (-not $env:SKIP_BUILD) {
    flutter pub get
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
}

$release = Join-Path $root 'build\windows\x64\runner\Release'
$stage = Join-Path $root 'build\installer-stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory $stage | Out-Null
Copy-Item "$release\*" $stage -Recurse

# The Visual C++ runtime, shipped beside the app so it starts on a computer that
# does not have it installed.
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    Copy-Item (Join-Path $env:WINDIR "System32\$dll") $stage -Force
}

$iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 was not found. Install it with: winget install JRSoftware.InnoSetup' }

& $iscc "/DAppVersion=$version" "/DSourceDir=$stage" 'scripts\installer\keening.iss'
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
Write-Host "Built: dist\Keening-Setup-$version.exe"
