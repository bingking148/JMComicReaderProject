# JMComicReader

一个现代化、轻量级的本地 JM 漫画阅读器与下载管理器。提供优雅的 Web 界面，支持搜索、下载、离线阅读以及移动端完美适配。

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Python](https://img.shields.io/badge/python-3.8+-green.svg)
![Version](https://img.shields.io/badge/version-1.2.0-blue.svg)

---

## 功能特性

**搜索与发现**
- 关键词模糊搜索 + JM号精准直达
- 漫画详细信息、标签、章节列表
- 封面智能缓存，加载迅速

**下载管理**
- 多线程异步下载，支持断点续传
- 实时下载进度监控
- 本地存储，随时随地离线阅读

**阅读体验**
- 响应式 Web 阅读器，适配 PC 和手机浏览器
- 移动端触摸滑动优化，支持沉浸式阅读
- 单页/双页显示模式

**桌面版**
- 基于 pywebview 的原生桌面窗口
- 用户数据自动存储到系统用户目录，更新不丢失
- 提供 Inno Setup 安装包

---

## 快速开始

### 方式一：安装包运行（推荐）

1. 下载 `dist/JMComicReader-Setup-v1.2.0.exe` 并安装
2. 启动 JMComicReader，桌面窗口会自动打开

### 方式二：源码运行

**环境要求：** Python 3.8+

```bash
git clone https://github.com/yourusername/JMComicReaderProject.git
cd JMComicReaderProject

pip install -r requirements.txt
python start.py
```

启动后浏览器访问 `http://localhost:5000`。

Windows 用户也可以直接双击 `start.bat`。

---

## 移动端使用

1. 确保手机和电脑连接同一 WiFi
2. 在电脑 CMD 中输入 `ipconfig` 查看本机 IP（如 `192.168.1.5`）
3. 手机浏览器访问 `http://192.168.1.5:5000`

---

## 项目结构

```
JMComicReaderProject/
├── backend/                     # 后端 (Flask)
│   ├── models/
│   │   └── database.py          # 数据模型
│   ├── services/
│   │   ├── jm_crawler.py        # JM 漫画爬虫
│   │   ├── download_manager.py  # 下载管理
│   │   ├── comic_manager.py     # 漫画管理
│   │   └── cover_cache.py       # 封面缓存
│   ├── app.py                   # Flask 入口
│   └── jm_option.yml            # 爬虫配置
├── frontend/                    # 前端
│   ├── static/css/              # 样式
│   ├── static/js/               # 脚本
│   └── templates/               # HTML 模板
├── assets/                      # 应用图标
├── desktop_app.py               # 桌面版入口
├── start.py                     # Web 模式入口
├── start.bat                    # Windows 启动脚本
├── build_desktop.bat            # 构建桌面包
├── build_installer.bat          # 构建安装包
├── JMComicReader.spec           # PyInstaller 配置
├── JMComicReaderInstaller.iss   # Inno Setup 配置
├── requirements.txt             # Python 依赖
└── VERSION                      # 版本号
```

---

## 配置说明

编辑 `backend/jm_option.yml` 可自定义爬虫参数：

```yaml
client:
  domain: [...]           # JM 域名列表
download:
  threading:
    max_workers: 5        # 下载并发数
dir_rule:
  base_dir: ...           # 下载路径（默认无需修改）
```

---

## 从源码构建安装包

需要安装 [Inno Setup 6](https://jrsoftware.org/isinfo.php)。

```bash
# 构建桌面版 exe
build_desktop.bat

# 构建安装包（包含上一步）
build_installer.bat
```

产物输出到 `dist/` 目录。

---

## 免责声明

本项目仅供学习交流使用，请勿用于非法用途。所有漫画资源均来自网络，本项目不存储任何漫画内容。
