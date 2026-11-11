# JMComicReader

2.0 堂堂上线。

在本机搜索、下载和阅读 JM 漫画。站点协议、下载和书架由 Go 引擎完成，界面是 Flutter。Windows 安装包和 Android APK 都自带引擎，不需要另开一台电脑上的服务。

本项目仅供学习交流，请勿用于非法用途。漫画来自网络，程序不会在自有服务器上保存内容。使用前请确认已年满 18 岁。

## 文件放在哪

Windows 安装程序默认把程序装到 `%LOCALAPPDATA%\Programs\JMComicReader`，目录里是 `JMComicReader.exe` 和旁边的 `jmengine.exe`。漫画不在这里。

封面、书架数据库和已下载的漫画在用户数据目录里，更新或重装程序不会清掉：

- Windows：`%APPDATA%\JMComicReader\JMComicReader`
- Android：应用私有目录

Windows 安装向导有两页，互不替代：程序安装位置，以及漫画数据目录。默认数据目录仍是 `%APPDATA%\JMComicReader\JMComicReader`。装好以后可以在桌面版的设置里更改，并选择是否把现有文件搬走。没有选择时，程序不会删除旧目录。卸载安装程序同样不会删除漫画数据。Android 仍使用应用自己的私有目录。

设置页顶部会显示这台机器上的实际路径。漫画文件在其中的 `comics/` 下，一本一个 `{编号}_{标题}` 文件夹。

Linux 和 macOS 可以按下面的步骤自己编译。发布页里没有这两个平台的安装包。

## 使用

- 首页有推荐关键词、分类、每日最新和收藏最多
- 用关键词搜索，或直接输入 JM 编号打开一本。搜索后可以按最新、观看、图片、收藏，以及今日、本周、本月、全部筛选
- 下载可以暂停、继续；已经下完的页会跳过
- 在书架里阅读已下载的漫画，阅读进度按本保存
- 阅读时会按页面和窗口在单页、跨页、长条之间选择，也可以自己指定。可以缩放，也可以用键盘翻页
- 设置里可以改 API 域名、图片域名和同时下载的图片数（1–16），也可以只清理封面缓存

第一次打开需要确认年龄。

## 2.2.0

Windows 安装向导可以分别选择程序目录和漫画数据目录。设置里可以更改数据目录、打开漫画目录、导入文件夹或 zip / cbz、查看占用、只清理封面缓存，以及重新扫描书架。关于页有版本和仓库链接。

首页有推荐关键词、分类、每日最新和收藏最多。搜索后可以按排序和时间筛选。

取消下载会先确认。确认后删除这次已下载的文件；点「留下」则继续。暂停保留已下的页。

会记住较快的官方线路，列表和封面可以先用缓存。设置里的 HTTP 或 HTTPS 代理默认关闭。

- [v2.2.0](https://github.com/bingking148/JMComicReaderProject/releases/tag/v2.2.0)
- [Android arm64 APK](https://github.com/bingking148/JMComicReaderProject/releases/download/v2.2.0/JMComicReader-2.2.0-arm64.apk)
- [Windows 安装程序](https://github.com/bingking148/JMComicReaderProject/releases/download/v2.2.0/JMComicReader-Setup-v2.2.0.exe)

## 2.1.0

阅读器打开后直接看页面。点页面中间或按 Esc 才显示工具条。底栏是上一话、页码滑块和下一话。适宽、底色、遮光、方向和长条滚动在阅读设置里。目录和页面缩略图可以跳转。

- [v2.1.0](https://github.com/bingking148/JMComicReaderProject/releases/tag/v2.1.0)
- [Android arm64 APK](https://github.com/bingking148/JMComicReaderProject/releases/download/v2.1.0/JMComicReader-2.1.0-arm64.apk)
- [Windows 安装程序](https://github.com/bingking148/JMComicReaderProject/releases/download/v2.1.0/JMComicReader-Setup-v2.1.0.exe)

## 从 1.x 搬过来

2.0 不读取旧的 `comics.db`，也不再生成 PDF。

如果旧下载是 `{编号}_{标题}/`，里面是章节子目录，或者图片直接铺在这一层，把这些文件夹拷进上面的 `comics/`，然后在设置里点「重新扫描书架」。也可以在设置里导入这样的文件夹，或同样结构的 zip / cbz。已经下完的书不会被导入覆盖。

`jm_option.yml` 不会导入。域名和下载并发在设置页里改。

1.x 的 Python 程序还在 [`legacy/`](legacy/)，可以照旧运行：

```bash
cd legacy
pip install -r requirements.txt
python start.py
```

`python desktop_app.py` 也行。

## 从源码构建

需要 Go 1.22 或更新版本，以及 Flutter 3.27 或更新版本。打 v2.2.0 用的是 Go 1.22.12 和 Flutter 3.47.9。编 Android 还需要 Android SDK 和 NDK。

```bash
scripts/build-engine.sh

cd app
flutter pub get
flutter test
flutter run -d linux
```

把 `linux` 换成 `windows` 或 `macos` 即可。工作目录在 `app/` 时，程序会找 `app/bin/jmengine`（Windows 是 `jmengine.exe`）。也可以用环境变量 `JM_ENGINE` 指向这个文件。

Windows 安装包在打 `v2.2.0` 标签时由 GitHub Actions 生成。本地可以这样编：

```bat
cd engine
set CGO_ENABLED=0
go build -trimpath -ldflags "-s -w" -o ../app/bin/jmengine.exe ./cmd/jmengine
cd ../app
flutter build windows
ISCC /DAppVersion=2.2.0 app\windows\installer\JMComicReader.iss
```

Linux：

```bash
scripts/build-engine.sh
cd app && flutter build linux
```

产物在 `app/build/linux/x64/release/bundle/`。

Android 只编了 arm64：

```bash
scripts/build-android-engine.sh
cd app && flutter build apk --release --target-platform android-arm64
```

`scripts/build-android-engine.sh` 会把 gomobile 固定在仍能用 Go 1.22 编译的那个修订上。

macOS 先把引擎编到 `app/bin/jmengine`，再执行 `flutter build macos`。iOS 工程在仓库里，但没有打过包。

只启动引擎、不打开界面：

```bash
cd engine && go run ./cmd/jmengine -data /tmp/jmcomic
```

正常时会打印一行 `READY`，后面是端口和令牌。

测试不访问外网：

```bash
cd engine && go test ./...
cd app && flutter test
```

## 目录

- [`engine/`](engine/)：Go 引擎。`cmd/jmengine` 是桌面进程，`jmengine/` 是嵌进 Android 的入口
- [`app/`](app/)：Flutter 界面和阅读器
- [`legacy/`](legacy/)：1.x 的 Python 程序
- [`scripts/`](scripts/)：编译引擎的脚本

## 许可

[MIT](LICENSE)。代码仓库：<https://github.com/bingking148/JMComicReaderProject>
