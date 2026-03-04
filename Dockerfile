# JM漫画阅读器 Docker镜像
# 基于Python 3.11的轻量级镜像
FROM python:3.11-slim

# 设置工作目录
WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    gcc \
    libffi-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# 复制依赖文件
COPY requirements.txt .

# 安装Python依赖
RUN pip install --no-cache-dir -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple

# 复制项目文件
COPY backend/ ./backend/
COPY frontend/ ./frontend/
COPY start.py .

# 创建数据目录
RUN mkdir -p /app/DownloadedComics /app/TempCache /app/backend

# 设置环境变量
ENV PYTHONUNBUFFERED=1
ENV FLASK_ENV=production
ENV BASE_DIR=/app
ENV DOWNLOAD_DIR=/app/DownloadedComics
ENV TEMP_CACHE_DIR=/app/TempCache

# 暴露端口
EXPOSE 5000

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000')" || exit 1

# 启动命令
CMD ["python", "start.py"]
