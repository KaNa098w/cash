#define MyAppName "Leemon"
#define MyAppPublisher "Your Company"
#define MyAppExeName "Leemon.exe"
#define MyUpdaterExeName "Leemon.Updater.exe"
#define MyAppId "{{D8A1C2E4-1234-4ABC-9F12-1234567890AB}"

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#ifndef OutputBaseFilename
  #define OutputBaseFilename "Leemon_Setup_1.0.0"
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=D:\Programs\pos_cash\cash\dist_installer
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
UninstallDisplayIcon={app}\{#MyAppExeName}
PrivilegesRequired=lowest

; Allow silent updates to replace the running app cleanly.
CloseApplications=yes
CloseApplicationsFilter={#MyAppExeName}
RestartApplications=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительные задачи:"; Flags: unchecked

[Files]
; Берем ВСЕ файлы из Flutter Release
Source: "D:\Programs\pos_cash\cash\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "D:\Programs\pos_cash\cash\updater\bin\Release\net8.0-windows\win-x64\publish\*"; DestDir: "{app}\updater"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; For regular installs show the checkbox, for silent updates rely on RestartApplications.
Filename: "{app}\{#MyAppExeName}"; Description: "Запустить {#MyAppName}"; Flags: nowait postinstall skipifsilent
