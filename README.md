# JMComicReader

本地 JM 漫画阅读器。2.0 起，搜索、详情、下载、缓存、书架和配置都由一个 **Go 引擎**完成；桌面和手机上的界面是 **Flutter**。手机应用自己带这份引擎，不需要电脑开着，也不用连同一 Wi-Fi。

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)

## 能做什么

- 关键词搜索，以及用 JM 号直接打开
- 详情、标签、章节
- 封面缓存
- 并发下载、断点续传、进度
- 书架：列表、删除、占用空间、重新扫描旧目录
- 阅读进度按本保存，更新应用不会清掉下载
- 可配置 API / 图片域名和下载并发（对应旧版 `jm_option.yml`）
- 阅读器会按页面比例和窗口自己选择：适宽单页、跨页、长条连续滚动；也支持捏合、双击缩放、点击翻页、键盘

旧的 Python / Flask / pywebview 程序在 [`legacy/`](legacy/)。

## 架构

```
JMComicReaderProject/
├── engine/                 Go 引擎（协议、下载、书架、配置）
│   ├── cmd/jmengine/       桌面可执行文件，只监听 127.0.0.1
│   └── jmengine/           gomobile 入口，嵌进 Android / iOS 进程
├── app/                    Flutter 界面与阅读器
├── scripts/                构建引擎
└── legacy/                 1.x Python 应用
```

Flutter 不实现站点协议。它只做界面，通过本机回环地址访问引擎：

- **桌面**：启动同目录或 `app/bin/` 里的 `jmengine`
- **Android**：`gomobile` 把引擎编进 APK，由 `MainActivity` 在进程内 `Start`
- **iOS**：工程和 MethodChannel 已留好。把 gomobile 的 xcframework 接上 `jmengine.Start` 之后就能编，步骤见下方

数据放在系统给应用的支持目录里（桌面大约是 `~/.local/share/app.jmcomic.reader.jm_comic_reader`，Android 在应用私有目录）。封面缓存、书架数据库和漫画正文都在这里，升级安装不会清掉。

## 环境

- Go 1.22+
- Flutter 3.27+（本仓库用 3.47 验证）
- 桌面 Linux：`clang`、`cmake`、`ninja`、`pkg-config`、GTK 3
- Android：Android SDK、NDK，以及 `gomobile`

```bash
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
gomobile init
```

## 开发运行

```bash
# 引擎测试
cd engine && go test ./...

# 桌面引擎二进制
scripts/build-engine.sh

# 界面
cd app
flutter pub get
flutter test
flutter run -d linux          # 或 windows / macos
flutter run -d android
```

`flutter run` 时当前目录是 `app/`，它会找到 `app/bin/jmengine`。安装包会把这个二进制放在可执行文件旁边。

只想看引擎是否在线：

```bash
cd engine && go run ./cmd/jmengine -data /tmp/jmcomic
# 输出 READY <port> <token>
```

## 构建

**Linux 桌面**

```bash
scripts/build-engine.sh
cd app && flutter build linux
```

产物在 `app/build/linux/x64/release/bundle/`。

**Windows**

在 Windows 上：

```bash
cd engine
set CGO_ENABLED=0
go build -trimpath -ldflags "-s -w" -o ../app/bin/jmengine.exe ./cmd/jmengine
cd ../app && flutter build windows
```

**macOS**

同样先 `go build -o app/bin/jmengine ./cmd/jmengine`，再 `flutter build macos`。运行时也会查找可执行文件旁边的 `jmengine`。

**Android**

```bash
scripts/build-android-engine.sh
cd app && flutter build apk
```

`app/android` 的 `preBuild` 会调用上面的脚本。AAR 打进 APK 后，手机上的搜索和下载不再经过电脑。

**iOS（尚未在本环境编过包）**

```bash
cd engine
gomobile bind -target=ios -o Jmengine.xcframework ./jmengine
```

把 `Jmengine.xcframework` 加进 `app/ios/Runner`，然后在 `AppDelegate.swift` 的 `jmcomic/engine` 通道里调用 `JmengineStart(dataDir)`，返回端口。令牌写在数据目录的 `engine.token`。

## 从 1.x 迁移

1.x 是 Python 3.8 + Flask + pywebview，手机只能打开电脑上的网页。那套代码在 `legacy/`，仍可按原来的方式运行：

```bash
cd legacy
pip install -r requirements.txt
python start.py          # 或 python desktop_app.py
```

2.0 不读取旧的 `comics.db`。旧下载目录的形状还认：`{编号}_{标题}/` 下面要么是章节子目录，要么是平铺的图片。把这些文件夹放进新的数据目录下的 `comics/`，然后在设置里点「重新扫描书架」。

旧的 `jm_option.yml` 不会自动导入。域名和并发改在设置页里。应用默认会向发布列表要当前 API 域名，也可以自己填。

2.0 不再生成 PDF。阅读用的是解码后的图片。

## 配置

设置页可以改：

- API 域名、图片域名
- 是否在启动时刷新 API 域名
- 同时下载的图片数（1–16）
- 清理封面缓存
- 重新扫描 `comics/`

阅读偏好（自适应 / 单页 / 跨页 / 长条、适宽 / 完整、从左或从右）会记在同一份配置里。

## 测试

```bash
cd engine && go test ./...
cd app && flutter test
```

Go 测试覆盖加解密、切图、搜索解析，以及「下载 → 书架 → 阅读」这条本地路径。不依赖外网。

## 免责声明

本项目仅供学习交流，请勿用于非法用途。漫画资源来自网络，本程序不会在自有服务器上保存内容。使用前请确认已年满 18 岁。

## 许可

[MIT](LICENSE)
