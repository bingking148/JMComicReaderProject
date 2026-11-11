; JMComicReader 2.1 Windows installer.
; Packages the Flutter desktop build and the bundled jmengine.exe.
#ifndef AppVersion
  #define AppVersion "2.1.0"
#endif
#ifndef BundleDir
  #define BundleDir "..\..\build\windows\x64\runner\Release"
#endif

#define MyAppName "JMComicReader"
#define MyAppPublisher "JMComicReader"
#define MyAppURL "https://github.com/bingking148/JMComicReaderProject"
#define MyAppExeName "JMComicReader.exe"

[Setup]
AppId={{B7E2C1A4-6F0D-4E5A-9C31-2D8A7F0E4B19}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppVerName={#MyAppName} {#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
OutputDir=..\..\..\dist
OutputBaseFilename=JMComicReader-Setup-v{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName} {#AppVersion}
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#AppVersion}
ShowLanguageDialog=no
CloseApplications=no

[Languages]
Name: "zh_cn"; MessagesFile: "compiler:Default.isl"

[Messages]
zh_cn.SetupAppTitle=安装
zh_cn.SetupWindowTitle=安装 - %1
zh_cn.BeveledLabel=简体中文
zh_cn.WelcomeLabel1=欢迎使用 [name] 安装向导
zh_cn.WelcomeLabel2=这将安装 [name/ver]。程序在本机窗口中运行，不需要 Python，也不需要另一台电脑上的服务。%n%n建议先关闭正在运行的 JMComicReader。
zh_cn.SelectDirDesc=选择安装位置
zh_cn.SelectDirLabel3=安装程序会把 [name] 安装到下面的文件夹。下载的漫画保存在用户数据目录，更新程序不会删除它们。
zh_cn.FinishedLabel=安装完成。可以从开始菜单或桌面快捷方式打开 [name]。

[CustomMessages]
zh_cn.CreateDesktopIcon=创建桌面快捷方式
zh_cn.LaunchProgram=启动 %1

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "附加任务："; Flags: checkedonce

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
