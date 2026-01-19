# 变更日志

本项目的所有重要更改都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
并且本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

## [1.0.0] - 2025-01-19

### 新增
- ✨ JM号精准搜索功能
- ✨ 关键词模糊搜索功能
- ✨ 异步下载漫画功能
- ✨ 进度实时显示
- ✨ 在线阅读器
  - 支持图片缩放
  - 支持上一页/下一页
  - 键盘快捷键支持
  - 全屏模式
- ✨ 多章节漫画支持
- ✨ 章节自动排序（从JM网站获取）
- ✨ 章节切换功能
- ✨ 封面懒加载
- ✨ 漫画管理功能
  - 已下载漫画列表
  - 删除漫画
  - 文件大小统计
- ✨ 缓存管理
- ✨ 响应式界面设计
- ✨ 深色主题

### 修复
- 🐛 修复章节显示名称问题（使用章节索引而非ID）
- 🐛 修复章节切换JavaScript错误
- 🐛 修复章节索引初始化问题
- 🐛 修复多章节漫画排序问题（动态获取正确顺序）

### 优化
- ⚡ 优化章节顺序获取逻辑
- ⚡ 改进错误处理和重试机制
- ⚡ 优化前端加载速度
- ⚡ 改进用户体验和界面交互

### 文档
- 📝 完善README文档
- 📝 添加API文档
- 📝 添加部署说明
- 📝 添加贡献指南
- 📝 添加变更日志

## [0.1.0] - 2025-01-18

### 新增
- ✨ 项目初始化
- ✨ 基础搜索功能
- ✨ 基础下载功能
- ✨ 基础阅读功能

---

[未发布]: https://github.com/yourusername/JMComicReaderProject/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yourusername/JMComicReaderProject/releases/tag/v1.0.0
[0.1.0]: https://github.com/yourusername/JMComicReaderProject/releases/tag/v0.1.0
