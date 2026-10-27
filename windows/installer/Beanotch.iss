; Builds Beanotch-Setup-<arch>.exe from the published app in out\Beanotch.
; iscc /DAppVersion=0.1.0 /DArch=x64 windows\installer\Beanotch.iss
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef Arch
  #define Arch "x64"
#endif

[Setup]
AppId={{6F1C2B9E-6A3D-4E0B-9C8E-2B5D7A41C3F0}
AppName=Beanotch
AppVersion={#AppVersion}
AppPublisher=Gian
AppPublisherURL=https://giankbr.github.io/beanie-notch
AppSupportURL=https://github.com/giankbr/beanie-notch/issues
; Per-user install: no admin prompt, and updates can replace it later without one.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Beanotch
DisableProgramGroupPage=yes
DisableDirPage=yes
OutputDir=..\..\out
OutputBaseFilename=Beanotch-Setup-{#Arch}
SetupIconFile=..\src\Beanotch\Assets\Beanotch.ico
UninstallDisplayIcon={app}\Beanotch.exe
UninstallDisplayName=Beanotch
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Tasks]
Name: "startup"; Description: "Open Beanotch when I sign in"

[Files]
Source: "..\..\out\Beanotch\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{userprograms}\Beanotch"; Filename: "{app}\Beanotch.exe"
Name: "{userstartup}\Beanotch"; Filename: "{app}\Beanotch.exe"; Tasks: startup

[Run]
Filename: "{app}\Beanotch.exe"; Description: "Open Beanotch"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{localappdata}\Beanotch"
