#define MyAppName "JMComicReader"
#define MyAppPublisher "JMComicReader"
#define MyAppURL "https://github.com/bingking148/JMComicReaderProject"
#define MyAppExeName "JMComicReader.exe"
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{A1974A2E-971C-40F0-AF2F-4820C8C25D4A}
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
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
OutputDir=dist
OutputBaseFilename=JMComicReader-Setup-v{#AppVersion}
SetupIconFile=assets\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
ShowLanguageDialog=no
MissingMessagesWarning=yes
NotRecognizedMessagesWarning=yes

[Languages]
Name: "zh_cn"; MessagesFile: "compiler:Default.isl"

[Messages]
zh_cn.SetupAppTitle=安装
zh_cn.SetupWindowTitle=安装 - %1
zh_cn.UninstallAppTitle=卸载
zh_cn.UninstallAppFullTitle=%1 卸载
zh_cn.InformationTitle=提示
zh_cn.ConfirmTitle=确认
zh_cn.ErrorTitle=错误
zh_cn.SetupLdrStartupMessage=这将安装 %1。是否继续？
zh_cn.ExitSetupTitle=退出安装
zh_cn.ExitSetupMessage=安装尚未完成。如果现在退出，程序将不会被安装。%n%n你可以稍后再次运行安装程序来完成安装。%n%n确定要退出安装吗？
zh_cn.ButtonBack=< 上一步(&B)
zh_cn.ButtonNext=下一步(&N) >
zh_cn.ButtonInstall=安装(&I)
zh_cn.ButtonOK=确定
zh_cn.ButtonCancel=取消
zh_cn.ButtonYes=是(&Y)
zh_cn.ButtonYesToAll=全部是(&A)
zh_cn.ButtonNo=否(&N)
zh_cn.ButtonNoToAll=全部否(&O)
zh_cn.ButtonFinish=完成(&F)
zh_cn.ButtonBrowse=浏览(&B)...
zh_cn.ButtonWizardBrowse=浏&览...
zh_cn.ButtonNewFolder=新建文件夹(&M)
zh_cn.BeveledLabel=简体中文
zh_cn.ClickNext=点击“下一步”继续，或点击“取消”退出安装。
zh_cn.BrowseDialogTitle=浏览文件夹
zh_cn.BrowseDialogLabel=请在下面的列表中选择一个文件夹，然后点击“确定”。
zh_cn.NewFolderName=新建文件夹
zh_cn.WelcomeLabel1=欢迎使用 [name] 安装向导
zh_cn.WelcomeLabel2=安装向导将把 [name/ver] 安装到你的电脑上。%n%n建议在继续之前先关闭其他应用程序。
zh_cn.SelectDirDesc=选择 [name] 的安装位置
zh_cn.SelectDirLabel3=安装程序将把 [name] 安装到以下文件夹中。
zh_cn.DiskSpaceMBLabel=至少需要 [mb] MB 的可用磁盘空间。
zh_cn.SelectTasksLabel2=请选择安装 [name] 时要执行的附加任务，然后点击“下一步”。
zh_cn.WizardReady=准备安装
zh_cn.ReadyLabel1=安装程序已准备好开始在你的电脑上安装 [name]。
zh_cn.ReadyLabel2a=点击“安装”继续，或点击“上一步”查看或修改安装设置。
zh_cn.ReadyLabel2b=点击“安装”继续安装。
zh_cn.ReadyMemoDir=目标位置：
zh_cn.ReadyMemoType=安装类型：
zh_cn.ReadyMemoComponents=已选组件：
zh_cn.ReadyMemoTasks=附加任务：
zh_cn.PreparingDesc=安装程序正在准备把 [name] 安装到你的电脑上。
zh_cn.InstallingLabel=请稍候，安装程序正在将 [name] 安装到你的电脑上。
zh_cn.FinishedHeadingLabel=完成 [name] 安装向导
zh_cn.FinishedLabel=安装程序已完成 [name] 的安装。你可以通过已创建的快捷方式启动应用程序。
zh_cn.FinishedLabelNoIcons=安装程序已完成 [name] 的安装。
zh_cn.StatusCreateDirs=正在创建目录...
zh_cn.StatusExtractFiles=正在解压文件...
zh_cn.StatusCreateIcons=正在创建快捷方式...
zh_cn.StatusRollback=正在回滚更改...
zh_cn.StatusUninstalling=正在卸载 %1...
zh_cn.ConfirmUninstall=确定要彻底移除 %1 及其所有组件吗？

[CustomMessages]
zh_cn.UninstallProgram=卸载 %1
zh_cn.AdditionalIcons=附加快捷方式：
zh_cn.CreateDesktopIcon=创建桌面快捷方式
zh_cn.LaunchProgram=启动 %1

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "dist\JMComicReader\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
