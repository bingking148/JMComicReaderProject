# 🐮 JM漫画阅读器 - 飞牛OS部署指南

## 📋 概述

本指南帮助您在飞牛OS（FnOS）上使用Docker部署JM漫画阅读器。飞牛OS是基于Linux的NAS系统，完美支持Docker容器化部署。

## ✅ 兼容性说明

- ✅ **完全兼容飞牛OS**
- ✅ **支持x86_64架构**
- ✅ **支持ARM64架构**（如飞牛OS运行在ARM设备上）
- ✅ **数据持久化存储**
- ✅ **自动重启保护**

---

## 🚀 快速部署（推荐）

### 方法一：使用Docker Compose（推荐）

#### 1. 创建部署目录

通过飞牛OS的SSH或终端执行：

```bash
# 创建应用目录
mkdir -p /vol1/docker/jmcomic-reader
cd /vol1/docker/jmcomic-reader
```

#### 2. 创建docker-compose.yml

```bash
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  jmcomic-reader:
    image: bingking148/jmcomic-reader:latest
    container_name: jmcomic-reader
    ports:
      - "5000:5000"
    volumes:
      # 漫画下载目录（持久化到飞牛OS存储池）
      - /vol1/docker/jmcomic-reader/data/DownloadedComics:/app/DownloadedComics
      # 临时缓存目录
      - /vol1/docker/jmcomic-reader/data/TempCache:/app/TempCache
      # 后端数据目录（数据库和配置）
      - /vol1/docker/jmcomic-reader/data/backend:/app/backend
    environment:
      - PYTHONUNBUFFERED=1
      - FLASK_ENV=production
      - BASE_DIR=/app
      - DOWNLOAD_DIR=/app/DownloadedComics
      - TEMP_CACHE_DIR=/app/TempCache
    restart: unless-stopped
    networks:
      - jmcomic-network

networks:
  jmcomic-network:
    driver: bridge
EOF
```

#### 3. 启动容器

```bash
# 拉取镜像并启动
docker-compose up -d

# 查看日志
docker-compose logs -f
```

#### 4. 访问应用

```
http://你的飞牛OS_IP:5000
```

---

### 方法二：使用Docker命令行

#### 1. 创建数据目录

```bash
mkdir -p /vol1/docker/jmcomic-reader/data/DownloadedComics
mkdir -p /vol1/docker/jmcomic-reader/data/TempCache
mkdir -p /vol1/docker/jmcomic-reader/data/backend
```

#### 2. 运行容器

```bash
docker run -d \
  --name jmcomic-reader \
  --restart unless-stopped \
  -p 5000:5000 \
  -v /vol1/docker/jmcomic-reader/data/DownloadedComics:/app/DownloadedComics \
  -v /vol1/docker/jmcomic-reader/data/TempCache:/app/TempCache \
  -v /vol1/docker/jmcomic-reader/data/backend:/app/backend \
  -e PYTHONUNBUFFERED=1 \
  -e FLASK_ENV=production \
  bingking148/jmcomic-reader:latest
```

---

### 方法三：使用飞牛OS Docker管理界面

#### 1. 打开飞牛OS Docker应用
- 登录飞牛OS管理界面
- 进入"应用中心" → "Docker"

#### 2. 拉取镜像
- 点击"镜像" → "拉取镜像"
- 输入镜像名称：`bingking148/jmcomic-reader:latest`
- 点击"拉取"

#### 3. 创建容器
- 点击"容器" → "创建容器"
- 选择镜像：`bingking148/jmcomic-reader:latest`
- 配置如下：

**基本设置：**
- 容器名称：`jmcomic-reader`
- 自动重启：开启

**端口映射：**
- 本地端口：`5000`
- 容器端口：`5000`

**存储空间：**
- 添加三个卷映射：
  1. `/vol1/docker/jmcomic-reader/data/DownloadedComics` → `/app/DownloadedComics`
  2. `/vol1/docker/jmcomic-reader/data/TempCache` → `/app/TempCache`
  3. `/vol1/docker/jmcomic-reader/data/backend` → `/app/backend`

**环境变量：**
- `PYTHONUNBUFFERED` = `1`
- `FLASK_ENV` = `production`

#### 4. 启动容器
- 点击"创建并启动"

---

## 📁 数据存储说明

### 持久化数据位置

| 数据类型 | 飞牛OS路径 | 容器内路径 |
|---------|-----------|-----------|
| 下载的漫画 | `/vol1/docker/jmcomic-reader/data/DownloadedComics` | `/app/DownloadedComics` |
| 临时缓存 | `/vol1/docker/jmcomic-reader/data/TempCache` | `/app/TempCache` |
| 数据库和配置 | `/vol1/docker/jmcomic-reader/data/backend` | `/app/backend` |

### 备份数据

```bash
# 备份整个数据目录
cd /vol1/docker/jmcomic-reader
tar -czvf jmcomic-reader-backup-$(date +%Y%m%d).tar.gz data/

# 仅备份漫画
cd /vol1/docker/jmcomic-reader/data
tar -czvf comics-backup-$(date +%Y%m%d).tar.gz DownloadedComics/ backend/
```

### 恢复数据

```bash
# 停止容器
docker stop jmcomic-reader

# 恢复数据
cd /vol1/docker/jmcomic-reader
tar -xzvf jmcomic-reader-backup-20240101.tar.gz

# 重启容器
docker start jmcomic-reader
```

---

## 🔧 常用管理命令

### 查看容器状态

```bash
# 查看运行中的容器
docker ps | grep jmcomic-reader

# 查看容器日志
docker logs -f jmcomic-reader

# 查看资源使用
docker stats jmcomic-reader
```

### 重启容器

```bash
# 重启
docker restart jmcomic-reader

# 或使用docker-compose
cd /vol1/docker/jmcomic-reader
docker-compose restart
```

### 更新镜像

```bash
cd /vol1/docker/jmcomic-reader

# 拉取最新镜像
docker-compose pull

# 重新创建容器
docker-compose up -d

# 清理旧镜像
docker image prune -f
```

### 停止和删除容器

```bash
# 停止
docker stop jmcomic-reader

# 删除容器（保留数据）
docker rm jmcomic-reader

# 或使用docker-compose
cd /vol1/docker/jmcomic-reader
docker-compose down
```

### 进入容器内部

```bash
# 进入容器Shell
docker exec -it jmcomic-reader /bin/bash

# 查看文件系统
docker exec jmcomic-reader ls -la /app
```

---

## 🌐 网络访问配置

### 局域网访问

部署完成后，在同一局域网内的设备可以通过以下地址访问：

```
http://飞牛OS_IP:5000
```

### 端口转发（外网访问）

如需从外网访问，需要在路由器配置端口转发：

1. 登录路由器管理界面
2. 找到"端口转发"或"虚拟服务器"设置
3. 添加规则：
   - 外部端口：`5000`（或自定义）
   - 内部IP：飞牛OS的IP地址
   - 内部端口：`5000`

⚠️ **安全提醒**：外网访问建议配合反向代理和HTTPS使用

### 使用反向代理（推荐）

如果使用飞牛OS的Nginx Proxy Manager或其他反向代理：

```nginx
server {
    listen 80;
    server_name comics.yourdomain.com;
    
    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

## 🛠 故障排除

### 1. 容器无法启动

```bash
# 查看错误日志
docker logs jmcomic-reader

# 检查端口占用
netstat -tlnp | grep 5000

# 更换端口运行
docker run -d -p 5001:5000 ...
```

### 2. 权限问题

```bash
# 修复数据目录权限
chown -R 1000:1000 /vol1/docker/jmcomic-reader/data

# 或使用docker-compose
cd /vol1/docker/jmcomic-reader
docker-compose down
sudo chown -R $USER:$USER data/
docker-compose up -d
```

### 3. 镜像拉取失败

```bash
# 配置Docker镜像加速（飞牛OS）
cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com"
  ]
}
EOF

# 重启Docker服务
systemctl restart docker

# 重新拉取镜像
docker pull bingking148/jmcomic-reader:latest
```

### 4. 性能优化

```bash
# 限制容器资源（可选）
docker run -d \
  --memory=2g \
  --cpus=2 \
  --name jmcomic-reader \
  ...
```

---

## 📱 手机访问

部署在飞牛OS后，手机可以通过以下方式访问：

### 同一WiFi下
```
http://飞牛OS_IP:5000
```

### 外网访问（配置了端口转发后）
```
http://你的公网IP:5000
# 或
http://你的域名:5000
```

### 添加到手机主屏幕

1. 用手机浏览器访问应用
2. 点击浏览器菜单 → "添加到主屏幕"
3. 即可像原生App一样使用

---

## 🔄 自动更新脚本

创建自动更新脚本：

```bash
cat > /vol1/docker/jmcomic-reader/update.sh << 'EOF'
#!/bin/bash

cd /vol1/docker/jmcomic-reader

echo "正在检查更新..."
docker-compose pull

echo "正在重启容器..."
docker-compose up -d

echo "清理旧镜像..."
docker image prune -f

echo "更新完成！"
EOF

chmod +x /vol1/docker/jmcomic-reader/update.sh
```

添加到定时任务（每周一凌晨3点自动更新）：

```bash
crontab -e

# 添加以下行
0 3 * * 1 /vol1/docker/jmcomic-reader/update.sh >> /vol1/docker/jmcomic-reader/update.log 2>&1
```

---

## 📝 部署检查清单

- [ ] 飞牛OS已安装Docker
- [ ] 创建了部署目录 `/vol1/docker/jmcomic-reader`
- [ ] 配置了正确的端口映射（5000:5000）
- [ ] 配置了数据卷映射（3个目录）
- [ ] 容器成功启动
- [ ] 可以通过 `http://飞牛OS_IP:5000` 访问
- [ ] 测试搜索和下载功能正常
- [ ] 配置了自动重启
- [ ] （可选）配置了外网访问
- [ ] （可选）配置了反向代理

---

## 📞 技术支持

### 获取帮助

- 查看容器日志：`docker logs jmcomic-reader`
- 提交Issue：https://github.com/bingking148/JMComicReaderProject/issues
- Docker Hub：https://hub.docker.com/r/bingking148/jmcomic-reader

### 常见问题

**Q: 飞牛OS支持ARM架构吗？**
A: 支持！Docker镜像支持x86_64和ARM64架构。

**Q: 数据会丢失吗？**
A: 不会！通过卷映射，数据持久化存储在飞牛OS的硬盘上，容器删除也不会丢失。

**Q: 如何备份漫画？**
A: 直接备份 `/vol1/docker/jmcomic-reader/data/DownloadedComics` 目录即可。

**Q: 手机访问慢怎么办？**
A: 确保手机和飞牛OS在同一WiFi下，或使用5GHz WiFi频段。

---

**祝您在飞牛OS上使用愉快！🎉**
