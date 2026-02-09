# JMComic Reader

一个现代化、轻量级的本地 JM 漫画阅读器与下载管理器。提供优雅的 Web 界面，支持搜索、下载、离线阅读以及移动端完美适配。

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Python](https://img.shields.io/badge/python-3.8+-green.svg)
![Flask](https://img.shields.io/badge/flask-3.0+-orange.svg)

## ✨ 主要功能

###  搜索与发现
- **双模式搜索**：支持通过 **关键词** 模糊搜索或直接输入 **JM号** 精准直达。
- **详细信息**：查看漫画的完整元数据，包括作者、标签、简介、章节列表等。
- **封面预览**：智能缓存封面图片，加载迅速。

### 📥 下载管理
- **多线程下载**：后台异步下载，支持断点续传（基于 `jmcomic` 库）。
- **进度监控**：实时查看下载进度和状态。
- **本地存储**：下载后的漫画存储在本地，随时随地离线阅读。

### � 阅读体验
- **Web 阅读器**：响应式设计，完美适配 **PC** 和 **手机** 浏览器。
- **移动端优化**：针对手机端优化的触摸滑动体验，支持沉浸式阅读。
- **多种模式**：支持单页/双页显示（PC端智能适配）。

### 🛠️ 系统管理
- **缓存清理**：内置缓存管理工具，一键释放磁盘空间。
- **一键启动**：提供打包好的独立运行包，无需安装 Python 环境即可运行。
- **配置灵活**：支持自定义配置文件 `jm_option.yml`。

---

## � 快速开始

### 方式一：使用一键启动包（推荐）
适用于没有 Python 环境的用户。

1. 下载项目的最新 Release 包（即 `dist/JMComicReader` 文件夹）。
2. 解压（如果是压缩包）。
3. 双击运行文件夹内的 **`start.bat`**。
4. 浏览器会自动打开 `http://localhost:5000`。
   - 如果手机想看，确保手机和电脑在同一局域网，访问 `http://电脑IP:5000`。

### 方式二：源码运行
适用于开发者或希望自定义修改的用户。

#### 环境要求
- Python 3.8+
- pip

#### 安装步骤
1. 克隆仓库：
   ```bash
   git clone https://github.com/yourusername/JMComicReader.git
   cd JMComicReader
   ```

2. 安装依赖：
   ```bash
   pip install -r requirements.txt
   # 或者运行安装脚本
   python install_deps.py
   ```

3. 启动项目：
   Windows 用户直接双击 `start.bat`，或在命令行运行：
   ```bash
   python start.py
   ```

---

## � 项目结构

```
JMComicReader/
├── backend/                # 后端源码 (Flask)
│   ├── models/             # 数据模型
│   ├── services/           # 核心服务 (爬虫、下载、管理)
│   ├── app.py              # Flask 应用入口
│   └── jm_option.yml       # 默认配置文件
├── frontend/               # 前端源码
│   ├── static/             # 静态资源 (CSS, JS)
│   └── templates/          # HTML 模板
├── data/                   # 运行时数据 (自动生成)
│   └── backend/            # 数据库等
├── DownloadedComics/       # 下载的漫画存储目录
├── TempCache/              # 临时缓存目录
├── start.py                # 启动脚本
├── start.bat               # Windows 启动批处理
└── requirements.txt        # Python 依赖
```

## ⚙️ 配置说明

在项目根目录（打包版在 `JMComicReader` 文件夹根目录）下的 `jm_option.yml` 文件可配置爬虫参数：

```yaml
client:
  domain: [...]       # JM 域名列表，自动更新
download:
  threading:
    max_workers: 5    # 下载并发数
dir_rule:
  base_dir: ...       # 下载路径配置（默认无需修改）
```

## � 移动端使用

1. 确保电脑和手机连接到同一个 WiFi。
2. 启动程序后，在控制台可以看到类似 `Running on http://0.0.0.0:5000` 的提示。
3. 在电脑上打开 CMD，输入 `ipconfig` 查看 IPv4 地址（例如 `192.168.1.5`）。
4. 在手机浏览器输入 `http://192.168.1.5:5000` 即可访问。

## ⚠️ 免责声明

本项目仅供学习交流使用，请勿用于非法用途。所有漫画资源均来自网络，本项目不存储任何漫画内容。

---

**Enjoy Reading!** 📚
