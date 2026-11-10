; Inno Setup script for the Keening Windows app.
; Built by scripts\build-installer.ps1, which passes AppVersion and SourceDir.
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\installer-stage"
#endif

[Setup]
AppId={{6F1B7C52-3D0E-4C7A-9B64-2A8E5D1F4C90}
AppName=Keening
AppVersion={#AppVersion}
AppPublisher=Keening
DefaultDirName={autopf}\Keening
DefaultGroupName=Keening
DisableProgramGroupPage=yes
; Installs for the current user by default (no administrator needed); the
; installer offers an all-users install if it is run as administrator.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\dist
OutputBaseFilename=Keening-Setup-{#AppVersion}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\keening.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Keening"; Filename: "{app}\keening.exe"
Name: "{autodesktop}\Keening"; Filename: "{app}\keening.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\keening.exe"; Description: "Start Keening"; Flags: nowait postinstall skipifsilent
