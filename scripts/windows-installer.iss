#ifndef AppVersion
#define AppVersion "0.2.0"
#endif
[Setup]
AppId={{2CB75CE1-9324-46CE-A38D-C8C9B5F9F140}
AppName=余光 Yuguang
AppVersion={#AppVersion}
AppPublisher=Yuguang
AppPublisherURL=https://github.com/Aric000/yuguang
DefaultDirName={localappdata}\Programs\Yuguang
DefaultGroupName=余光
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Yuguang-{#AppVersion}-windows-x64-setup
SetupIconFile=..\shared\assets\AppIcon.ico
UninstallDisplayIcon={app}\Yuguang.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs
[Icons]
Name: "{group}\余光"; Filename: "{app}\Yuguang.exe"
Name: "{autodesktop}\余光"; Filename: "{app}\Yuguang.exe"; Tasks: desktopicon
[Tasks]
Name: desktopicon; Description: "创建桌面快捷方式"; Flags: unchecked
[Run]
Filename: "{app}\Yuguang.exe"; Description: "启动余光"; Flags: nowait postinstall skipifsilent
