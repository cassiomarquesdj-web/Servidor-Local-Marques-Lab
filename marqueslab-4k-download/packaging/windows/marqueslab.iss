; Installer for Marques Lab 4K Download.
; Per-user install (PrivilegesRequired=lowest) so no administrator prompt is
; needed: the user double-clicks, clicks Install, and the app is in the Start
; menu. Nothing else has to be installed — Python, FFmpeg and yt-dlp all ship
; inside the program folder.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef AppName
  #define AppName "Marques Lab 4K Download"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\dist\Marques Lab 4K Download"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\release"
#endif

[Setup]
AppId={{B7E2B6F1-3C5D-4F2A-9E1C-4A8D2F6B1C90}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Marques Lab
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=MarquesLab-4K-Download-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\assets\AppIcon.ico
UninstallDisplayIcon={app}\{#AppName}.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppName}.exe"
Name: "{group}\Desinstalar {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppName}.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppName}.exe"; Description: "Abrir o {#AppName}"; Flags: nowait postinstall skipifsilent
