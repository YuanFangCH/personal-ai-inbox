#define MyAppName "个人 AI 收件箱"

#ifndef MyAppVersion
  #define MyAppVersion "1.1.0"
#endif

#ifndef MyAppSource
  #define MyAppSource "..\..\build\windows\x64\runner\Release"
#endif

#ifndef MyAppOutput
  #define MyAppOutput "..\..\build\github-release"
#endif

[Setup]
AppId={{8CAD6DF9-6BCF-4424-AD67-A609E43E0E7A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=YuanFangCH
AppPublisherURL=https://github.com/YuanFangCH/personal-ai-inbox
AppSupportURL=https://github.com/YuanFangCH/personal-ai-inbox/issues
AppUpdatesURL=https://github.com/YuanFangCH/personal-ai-inbox/releases
DefaultDirName={localappdata}\Programs\PersonalAIInbox
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=..\..\..\LICENSE
OutputDir={#MyAppOutput}
OutputBaseFilename=personal-ai-inbox-v{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\personal_ai_inbox.exe
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany=YuanFangCH
VersionInfoDescription={#MyAppName} 安装程序
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
Source: "{#MyAppSource}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\personal_ai_inbox.exe"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\personal_ai_inbox.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\personal_ai_inbox.exe"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
