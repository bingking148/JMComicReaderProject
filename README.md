# 🎨 JM漫画阅读器

一个完整的JM漫画查找、展示、下载、阅读和管理系统，支持多章节漫画阅读、章节切换和在线预览。

本项目旨在解决在想看JM本子的时候，由于网络波动而导致加载困难的问题。通过本地下载和缓存机制，让用户即使在不稳定的网络环境下也能流畅阅读漫画，提供稳定、快速的阅读体验。

![Python](https://img.shields.io/badge/Python-3.8%2B-blue)
![Flask](https://img.shields.io/badge/Flask-3.0%2B-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

## ✨ 功能特性

### 📚 核心功能
- **🔍 JM号精准查找** - 输入JM号快速定位漫画
- **🔎 关键词模糊搜索** - 支持关键词搜索和排序
- **📥 异步下载** - 支持进度反馈的异步下载功能
- **📖 在线阅读** - 支持缩放、翻页、键盘快捷键的阅读器
- **📑 多章节支持** - 自动识别多章节漫画，支持章节切换
- **📋 漫画管理** - 已下载漫画列表、删除、文件大小统计
- **📱 响应式设计** - 完美适配桌面和移动设备

### 🎯 特色功能
- **⚡ 智能章节排序** - 从JM网站自动获取正确章节顺序
- **🖼️ 封面懒加载** - 高效的封面加载机制
- **💾 缓存优化** - 智能缓存管理，提升访问速度
- **🔄 自动重试** - 网络异常自动重试机制
- **🎨 美观界面** - 现代化深色主题设计

## 🛠 技术栈

### 后端
- **Python 3.8+** - 核心语言
- **Flask** - Web框架
- **JMComic-Crawler-Python** - JM漫画爬虫
- **SQLite** - 轻量级数据库
- **aiohttp** - 异步HTTP请求

### 前端
- **HTML5** - 页面结构
- **CSS3** - 样式设计
- **JavaScript (ES6+)** - 交互逻辑
- **响应式设计** - 适配多种设备

## 📦 安装步骤

### 1. 克隆项目

```bash
git clone https://github.com/yourusername/JMComicReaderProject.git
cd JMComicReaderProject
```

### 2. 创建虚拟环境（推荐）

```bash
python -m venv venv
# Windows
venv\Scripts\activate
# Linux/Mac
source venv/bin/activate
```

### 3. 安装依赖

```bash
pip install -r requirements.txt
```

### 4. 初始化数据库

```bash
python backend/app.py
```

首次运行会自动创建数据库。

## 🚀 使用说明

### 启动服务器

#### Windows
```bash
start.bat
```

#### Linux/Mac
```bash
python start.py
```

或者直接运行：
```bash
python backend/app.py
```

### 访问应用

打开浏览器访问：
- **本地访问**: http://localhost:5000
- **局域网访问**: http://你的IP:5000

### 功能使用

#### 1. 搜索漫画
- **JM号搜索**: 在首页输入JM号进行精准搜索
- **关键词搜索**: 点击"关键词搜索"，输入关键词进行模糊搜索

#### 2. 下载漫画
- 搜索到漫画后，点击"下载"按钮
- 查看下载进度，等待下载完成

#### 3. 阅读漫画
- 点击"阅读"按钮进入阅读界面
- 支持缩放、翻页、键盘快捷键操作
- 多章节漫画可以切换章节

#### 4. 管理已下载漫画
- 在"已下载"页面查看所有已下载的漫画
- 可以删除不需要的漫画
- 查看文件大小和下载时间

## 📁 项目结构

```
JMComicReaderProject/
├── backend/                   # 后端代码
│   ├── app.py                # Flask主应用
│   ├── jm_option.yml         # JM爬虫配置
│   ├── comics.db             # SQLite数据库（首次运行自动生成）
│   └── services/             # 业务逻辑
│       ├── jm_crawler.py     # JM漫画爬虫
│       ├── download_manager.py # 下载管理器
│       └── comic_manager.py  # 漫画管理器
├── frontend/                  # 前端代码
│   ├── static/               # 静态资源
│   │   ├── css/             # 样式文件
│   │   └── js/              # JavaScript文件
│   │       └── app.js       # 前端核心逻辑
│   └── templates/            # HTML模板
│       ├── index.html       # 首页
│       ├── search.html      # 搜索页
│       ├── detail.html      # 详情页
│       ├── downloaded.html  # 已下载页
│       └── reader.html      # 阅读页
├── DownloadedComics/         # 已下载漫画存储（自动生成）
├── TempCache/               # 临时缓存（自动生成）
├── logs/                    # 日志文件（自动生成）
├── requirements.txt         # Python依赖
├── start.py                # 启动脚本（Linux/Mac）
├── start.bat               # 启动脚本（Windows）
└── README.md              # 项目说明
```

## 📚 API文档

### 搜索相关
- `GET /api/search/jm/<int:jm_id>` - JM号搜索
- `GET /api/search/keyword?keyword=<关键词>` - 关键词搜索
- `GET /api/cover/<int:jm_id>` - 获取封面

### 下载相关
- `POST /api/download/<int:jm_id>` - 下载漫画
- `GET /api/download/progress/<download_id>` - 获取下载进度

### 阅读相关
- `GET /api/read/<int:jm_id>` - 获取章节信息
- `GET /api/read/<int:jm_id>/chapter/<chapter_id>` - 获取指定章节
- `GET /api/comic/<int:jm_id>/page/<page_num>?chapter=<chapter_id>` - 获取页面图片

### 管理相关
- `GET /api/downloaded` - 获取已下载漫画列表
- `DELETE /api/delete/<int:jm_id>` - 删除漫画
- `GET /api/cache/status` - 获取缓存状态
- `POST /api/cache/clear` - 清理缓存

## 🎮 阅读器快捷键

| 按键 | 功能 |
|------|------|
| ← / → | 上一页 / 下一页 |
| + / - | 放大 / 缩小 |
| F | 全屏 |
| ESC | 返回 / 退出全屏 |

## 🖼️ 界面展示

### 首页
现代化设计的首页，支持JM号和关键词搜索。

### 搜索结果
清晰的搜索结果展示，支持排序。

### 详情页
完整的漫画信息展示，包括封面、标签、简介等。

### 阅读器
功能完善的在线阅读器，支持缩放、翻页、章节切换。

## ⚙️ 配置说明

### JM域名配置
在 `backend/jm_option.yml` 中配置JM域名：

```yaml
client:
  domain:
    - "www.cdnhth.club"
    - "www.cdngwc.cc"
    - "www.cdngwc.net"
    # 更多域名...
```

### 端口配置
在 `backend/app.py` 中修改端口：

```python
app.run(debug=True, host="0.0.0.0", port=5000)
```

## 🐛 常见问题

### 1. 下载失败
- 检查网络连接
- 查看日志文件 `logs/app.log`
- 尝试更换JM域名

### 2. 章节显示不正确
- 确保漫画已完全下载
- 清除缓存并重启服务器
- 检查是否有网络连接（章节顺序需要从JM获取）

### 3. 阅读器加载慢
- 清理缓存
- 检查网络连接
- 确保图片文件完整

## 📝 开发计划

- [ ] 用户系统（收藏、阅读历史）
- [ ] 漫画推荐
- [ ] 批量下载
- [ ] 离线阅读
- [ ] 移动端APP

## 🤝 贡献指南

欢迎贡献代码！请遵循以下步骤：

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## ⚠️ 注意事项

本项目仅供学习研究使用，请遵守相关法律法规：
- 请勿用于商业用途
- 请尊重原作者版权
- 请合理使用各项功能
- 下载的内容请勿用于非法传播

## 📧 联系方式

如有问题或建议，请通过以下方式联系：
- 提交 Issue
- 发送邮件: your-email@example.com

## 🙏 致谢

- [JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python) - 提供JM漫画爬虫支持
- [Flask](https://flask.palletsprojects.com/) - Web框架
- 所有贡献者

---

**⭐ 如果这个项目对你有帮助，请给它一个星标！**
