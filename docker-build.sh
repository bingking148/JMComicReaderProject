#!/bin/bash

# JM漫画阅读器 Docker构建脚本
# 用于构建并推送Docker镜像到Docker Hub

set -e

# 配置
IMAGE_NAME="bingking148/jmcomic-reader"
VERSION="1.0.0"
LATEST_TAG="latest"

echo "=================================="
echo "JM漫画阅读器 Docker构建脚本"
echo "=================================="
echo ""

# 检查Docker是否安装
if ! command -v docker &> /dev/null; then
    echo "❌ 错误: Docker未安装"
    exit 1
fi

echo "✓ Docker已安装"

# 检查是否登录Docker Hub
echo ""
echo "检查Docker Hub登录状态..."
if ! docker info | grep -q "Username"; then
    echo "⚠ 未登录Docker Hub，请先登录:"
    echo "  docker login"
    exit 1
fi

echo "✓ 已登录Docker Hub"

# 构建镜像
echo ""
echo "=================================="
echo "构建Docker镜像..."
echo "=================================="
docker build -t ${IMAGE_NAME}:${VERSION} -t ${IMAGE_NAME}:${LATEST_TAG} .

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ 镜像构建成功"
    echo "  镜像标签: ${IMAGE_NAME}:${VERSION}"
    echo "  镜像标签: ${IMAGE_NAME}:${LATEST_TAG}"
else
    echo ""
    echo "❌ 镜像构建失败"
    exit 1
fi

# 推送镜像到Docker Hub
echo ""
echo "=================================="
echo "推送镜像到Docker Hub..."
echo "=================================="

echo "推送 ${IMAGE_NAME}:${VERSION}..."
docker push ${IMAGE_NAME}:${VERSION}

echo "推送 ${IMAGE_NAME}:${LATEST_TAG}..."
docker push ${IMAGE_NAME}:${LATEST_TAG}

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ 镜像推送成功"
else
    echo ""
    echo "❌ 镜像推送失败"
    exit 1
fi

echo ""
echo "=================================="
echo "构建完成！"
echo "=================================="
echo ""
echo "镜像信息:"
echo "  仓库: ${IMAGE_NAME}"
echo "  版本: ${VERSION}"
echo "  标签: ${LATEST_TAG}"
echo ""
echo "使用方式:"
echo "  docker pull ${IMAGE_NAME}:${LATEST_TAG}"
echo ""
