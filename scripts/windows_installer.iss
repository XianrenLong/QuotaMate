#ifndef AppVersion
  #error AppVersion must be supplied by package_windows.ps1
#endif
#ifndef ReleaseDirectory
  #error ReleaseDirectory must be supplied by package_windows.ps1
#endif
[Setup]
AppId={{F6594A3E-1ACD-4D26-83E7-5C9A9CC42E41}
AppName=QuotaMate
AppVersion={#AppVersion}
AppPublisher=QuotaMate contributors
AppPublisherURL=https://github.com/liuzilong200049-bot/QuotaMate
DefaultDirName={localappdata}\Programs\QuotaMate
DefaultGroupName=QuotaMate
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir=..\dist\windows
OutputBaseFilename=QuotaMate-{#AppVersion}-windows-x64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\quota_mate.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Files]
Source: "{#ReleaseDirectory}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\QuotaMate"; Filename: "{app}\quota_mate.exe"
Name: "{autodesktop}\QuotaMate"; Filename: "{app}\quota_mate.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\quota_mate.exe"; Description: "Launch QuotaMate"; Flags: nowait postinstall skipifsilent
; User databases and Claude statusLine settings are deliberately left intact on uninstall.
