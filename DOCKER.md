# Docker 部署指南

本项目支持使用 Docker 和 Docker Compose 进行快速部署。

## 前置要求

- Docker (20.10+)
- Docker Compose (2.0+)

## 快速开始

### 方法一：使用 Docker Compose（推荐）

1. **克隆项目**

```bash
git clone <repository-url>
cd JMComicReaderProject-GitHub
```

2. **一键启动**

```bash
docker-compose up -d
```

3. **访问应用**

在浏览器中打开：`http://localhost:5000`

### 方法二：使用 Docker 命令

1. **构建镜像**

```bash
docker build -t jmcomic-reader .
```

2. **运行容器**

```bash
docker run -d \
  --name jmcomic-reader \
  -p 5000:5000 \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/data/cache:/app/data/cache \
  -v $(pwd)/data/downloads:/app/data/downloads \
  -e TEMP_CACHE_DIR=/app/data/cache \
  -e DOWNLOAD_DIR=/app/data/downloads \
  --restart unless-stopped \
  jmcomic-reader
```

3. **访问应用**

在浏览器中打开：`http://localhost:5000`

## 数据持久化

默认情况下，数据会存储在 `./data` 目录下，包含：
- `./data/cache` - 缓存目录（封面等）
- `./data/downloads` - 下载的漫画

如果需要修改数据存储位置，可以在 `docker-compose.yml` 中修改 volumes 配置。

## 常用命令

### 查看日志

```bash
docker-compose logs -f
```

### 停止服务

```bash
docker-compose stop
```

### 重启服务

```bash
docker-compose restart
```

### 删除容器和数据

```bash
docker-compose down -v
```

### 查看容器状态

```bash
docker-compose ps
```

## 环境变量

可以通过修改 `docker-compose.yml` 中的 `environment` 部分来配置环境变量：

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `TEMP_CACHE_DIR` | `/app/data/cache` | 缓存目录路径 |
| `DOWNLOAD_DIR` | `/app/data/downloads` | 下载目录路径 |

## 自定义端口

如果需要修改端口，在 `docker-compose.yml` 中修改 `ports` 配置：

```yaml
ports:
  - "8080:5000"  # 使用 8080 端口访问
```

## 故障排查

### 容器无法启动

1. 查看日志：`docker-compose logs`
2. 检查端口是否被占用：`netstat -ano | findstr :5000`
3. 确保数据目录有写入权限

### 缓存清理失败

检查 `./data/cache` 目录的权限设置。

## 生产环境建议

1. **设置资源限制**：在 `docker-compose.yml` 中添加资源限制
2. **使用 HTTPS**：配置反向代理（如 Nginx）
3. **定期备份**：定期备份 `./data` 目录
4. **日志管理**：配置日志轮转策略

### 资源限制示例

```yaml
services:
  jmcomic-reader:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M
```

## 更新应用

```bash
# 停止并删除旧容器
docker-compose down

# 拉取最新代码
git pull

# 重新构建并启动
docker-compose up -d --build
```

## 注意事项

- 首次启动时，容器会自动创建所需目录
- 确保宿主机的 `./data` 目录有足够的磁盘空间
- 建议定期清理缓存以释放磁盘空间
- 容器会自动重启（除非手动停止）
