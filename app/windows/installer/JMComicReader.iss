; JMComicReader 2.0 Windows installer.
; Packages the Flutter desktop build and the bundled jmengine.exe.
#ifndef AppVersion
  #define AppVersion "2.0.0"
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
; Program files live here. The page stays visible so the user can choose D: or another drive.
DisableDirPage=no
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
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
zh_cn.SelectDirDesc=选择程序安装位置
zh_cn.SelectDirLabel3=这是程序本身的位置，体积很小。默认在 Program Files，也可以改到 D: 或其他磁盘。漫画数据在下一步单独选择，不会装进这个文件夹。
zh_cn.FinishedLabel=安装完成。可以从开始菜单或桌面快捷方式打开 [name]。卸载程序不会删除漫画数据目录。

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

[Code]
var
  DataDirPage: TInputDirWizardPage;

function TrimDataDir(const Value: String): String;
begin
  Result := Trim(Value);
  while (Length(Result) > 3) and ((Result[Length(Result)] = '\') or (Result[Length(Result)] = '/')) do
    Delete(Result, Length(Result), 1);
end;

function DefaultDataDir: String;
var
  PointerFile: String;
  Lines: TArrayOfString;
begin
  Result := ExpandConstant('{userappdata}\JMComicReader\JMComicReader');
  PointerFile := ExpandConstant('{userappdata}\JMComicReader\data_root.txt');
  if FileExists(PointerFile) then
  begin
    if LoadStringsFromFile(PointerFile, Lines) then
    begin
      if (GetArrayLength(Lines) > 0) and (TrimDataDir(Lines[0]) <> '') then
        Result := TrimDataDir(Lines[0]);
    end;
  end;
end;

procedure InitializeWizard;
begin
  DataDirPage := CreateInputDirPage(wpSelectDir,
    '漫画数据目录',
    '下载的漫画、封面和书架数据库放在哪里',
    '这一步不是程序安装位置。漫画通常很大，可以放到 D: 或其他还有空间的磁盘。' + #13#10 +
    '保持默认时，数据仍在当前用户的 AppData 里。已经装过 2.0.0 且不改这里的话，原来的漫画还在原处。' + #13#10 +
    '卸载程序不会删除这个目录。',
    False, '');
  DataDirPage.Add('漫画数据目录：');
  DataDirPage.Values[0] := DefaultDataDir();
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  DataDir, AppDir: String;
begin
  Result := True;
  if DataDirPage = nil then
    Exit;
  if CurPageID = DataDirPage.ID then
  begin
    DataDir := TrimDataDir(DataDirPage.Values[0]);
    AppDir := TrimDataDir(WizardDirValue);
    DataDirPage.Values[0] := DataDir;
    if DataDir = '' then
    begin
      MsgBox('请选择漫画数据目录。', mbError, MB_OK);
      Result := False;
    end
    else if CompareText(DataDir, AppDir) = 0 then
    begin
      MsgBox('漫画数据目录不能和程序安装目录相同。请换一个文件夹。', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

procedure WritePointer(const PointerFile, DataDir: String);
begin
  ForceDirectories(ExtractFileDir(PointerFile));
  SaveStringToFile(PointerFile, DataDir + #13#10, False);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  DataDir: String;
begin
  if CurStep <> ssPostInstall then
    Exit;
  DataDir := TrimDataDir(DataDirPage.Values[0]);
  if DataDir = '' then
    Exit;
  ForceDirectories(DataDir);
  { Beside the exe, so the first launch finds it even if this step is elevated. }
  WritePointer(ExpandConstant('{app}\data_root.txt'), DataDir);
  { User-writable copy. Later changes in Settings override the file beside the exe. }
  WritePointer(ExpandConstant('{userappdata}\JMComicReader\data_root.txt'), DataDir);
end;
