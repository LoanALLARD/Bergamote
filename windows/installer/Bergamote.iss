; Programme d'installation de Bergamote pour Windows (Inno Setup 6).
;
;   dotnet publish windows/Bergamote.Windows -c Release -r win-x64 --self-contained ... -o windows/publish
;   iscc /DAppVersion=0.1.0 windows\installer\Bergamote.iss      -> windows\publish\Bergamote-Setup-0.1.0.exe
;
; Installation pour l'utilisateur courant, sans droits d'administrateur : l'app va dans
; %LOCALAPPDATA%\Programs\Bergamote, avec un raccourci dans le menu Démarrer.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6E1B0C0E-3B5A-4E0B-9C52-BE26A307E001}
AppName=Bergamote
AppVersion={#AppVersion}
AppPublisher=Loan Allard
AppPublisherURL=https://loanallard.github.io/Bergamote/
AppSupportURL=https://github.com/LoanALLARD/Bergamote/issues
DefaultDirName={autopf}\Bergamote
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=..\publish
OutputBaseFilename=Bergamote-Setup-{#AppVersion}
SetupIconFile=..\Bergamote.Windows\Bergamote.ico
UninstallDisplayIcon={app}\Bergamote.exe
UninstallDisplayName=Bergamote
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; Une version déjà lancée est fermée avant d'être remplacée.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"

[Files]
Source: "..\publish\Bergamote.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Bergamote"; Filename: "{app}\Bergamote.exe"

[Run]
Filename: "{app}\Bergamote.exe"; Description: "{cm:LaunchProgram,Bergamote}"; Flags: nowait postinstall skipifsilent

[Registry]
; Le réglage « lancer à l'ouverture de session » de l'app : retiré avec elle.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "Bergamote"; ValueType: none; Flags: uninsdeletevalue dontcreatekey

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /IM Bergamote.exe /F"; Flags: runhidden; RunOnceId: "StopBergamote"
