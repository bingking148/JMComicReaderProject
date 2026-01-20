# 删除Docker相关文件和内容的计划

## 需要删除的文件
1. **DOCKER.md** - 完整的Docker部署指南文档
2. **Dockerfile** - Docker镜像构建配置
3. **docker-compose.yml** - Docker Compose配置文件
4. **.dockerignore** - Docker排除文件配置

## 需要清理的文档内容
1. **README.md** - 删除"方式二：Docker部署"部分（第81-125行）
   - 保留"方式一：普通部署"部分
   - 保留所有API文档和功能说明
   - 保留项目结构中的普通部署说明

2. **部署说明.md** - 删除Docker相关章节
   - 保留系统要求
   - 保留项目结构
   - 保留安装步骤
   - 保留使用说明中的普通部署部分
   - 删除所有Docker相关的配置和命令说明

## 保留的核心文件（确保正常部署不受影响）
- ✅ **requirements.txt** - Python依赖包列表
- ✅ **start.py** - Linux/Mac启动脚本
- ✅ **start.bat** - Windows启动脚本
- ✅ **backend/** - 所有后端代码和配置
- ✅ **frontend/** - 所有前端代码
- ✅ **所有数据库和配置文件** - 运行时自动生成

## 影响评估
- ✅ **不影响普通部署** - 只删除Docker特定的配置文件和文档
- ✅ **不影响核心功能** - 不修改任何代码逻辑
- ✅ **不影响依赖管理** - 保留requirements.txt
- ✅ **不影响启动方式** - 保留start.py和start.bat

## 执行步骤
1. 删除4个Docker相关文件
2. 清理README.md中的Docker部署章节
3. 清理部署说明.md中的Docker相关内容
4. 验证项目结构完整性