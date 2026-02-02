#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_DIR="build"
DIST_DIR="dist"
PORTABLE_DIR="JMComicReader_Portable"
VERSION="1.0.0"
PYTHON_CMD="python3"
LOG_FILE="build.log"

log_message() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

print_header() {
    local message="$1"
    local width=60
    echo ""
    echo "╔$(printf '═%.0s' $(seq 1 $width))╗"
    printf "║%-$((width-2))s║\n" "  $message  "
    echo "╚$(printf '═%.0s' $(seq 1 $width))╝"
    echo ""
}

check_environment() {
    echo "✓ 检查构建环境..."
    
    if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
        echo "  ✗ Python 未安装"
        log_message "ERROR: Python not found"
        return 1
    fi
    
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    else
        PYTHON_CMD="python"
    fi
    
    PYTHON_VERSION=$($PYTHON_CMD --version 2>&1 | awk '{print $2}')
    echo "  ✓ Python 版本: $PYTHON_VERSION"
    log_message "Python version: $PYTHON_VERSION"
    
    MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
    MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
    
    if [ "$MAJOR" -lt 3 ] || { [ "$MAJOR" -eq 3 ] && [ "$MINOR" -lt 8 ]; }; then
        echo "  ✗ Python 版本过低，需要 3.8+"
        log_message "ERROR: Python version too low"
        return 1
    fi
    
    return 0
}

install_build_tools() {
    print_header "📦 安装构建工具"
    
    echo "正在安装 PyInstaller..."
    $PYTHON_CMD -m pip install pyinstaller -i https://pypi.tuna.tsinghua.edu.cn/simple
    
    if [ $? -ne 0 ]; then
        echo "❌ PyInstaller 安装失败"
        log_message "ERROR: Failed to install PyInstaller"
        return 1
    fi
    
    echo "✓ PyInstaller 安装完成"
    log_message "PyInstaller installed successfully"
    return 0
}

prepare_directories() {
    echo "✓ 准备构建目录..."
    
    [ -d "$BUILD_DIR/build" ] && rm -rf "$BUILD_DIR/build"
    [ -d "$DIST_DIR" ] && rm -rf "$DIST_DIR"
    
    mkdir -p "$BUILD_DIR"
    mkdir -p "$DIST_DIR"
    
    log_message "Directories prepared"
}

build_executable() {
    print_header "🔨 构建独立可执行文件"
    
    echo "这可能需要几分钟时间，请耐心等待..."
    echo ""
    
    cd "$BUILD_DIR"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 构建
        if [ -f "jm_reader.spec" ]; then
            echo "使用 spec 文件构建..."
            $PYTHON_CMD -m PyInstaller --clean --noconfirm jm_reader.spec
        else
            echo "使用默认配置构建（单文件模式）..."
            $PYTHON_CMD -m PyInstaller --onefile --noconfirm \
                --name JMComicReader \
                --add-data "../backend:backend" \
                --add-data "../frontend:frontend" \
                --hidden-import flask \
                --hidden-import flask_cors \
                --hidden-import jmcomic \
                --hidden-import aiohttp \
                --hidden-import aiofiles \
                --hidden-import requests \
                --hidden-import pillow \
                --hidden-import img2pdf \
                --hidden-import sqlite3 \
                ../start.py
        fi
        
        cd ..
        
        if [ ! -f "$BUILD_DIR/dist/JMComicReader" ]; then
            echo "❌ 可执行文件生成失败"
            echo ""
            echo "请检查："
            echo "  1. 是否有足够的磁盘空间"
            echo "  2. 是否有写入权限"
            echo "  3. 查看上方错误信息"
            log_message "ERROR: Failed to build executable"
            return 1
        fi
        
    else
        # Linux 构建
        if [ -f "jm_reader.spec" ]; then
            echo "使用 spec 文件构建..."
            $PYTHON_CMD -m PyInstaller --clean --noconfirm jm_reader.spec
        else
            echo "使用默认配置构建（单文件模式）..."
            $PYTHON_CMD -m PyInstaller --onefile --noconfirm \
                --name JMComicReader \
                --add-data "../backend:backend" \
                --add-data "../frontend:frontend" \
                --hidden-import flask \
                --hidden-import flask_cors \
                --hidden-import jmcomic \
                --hidden-import aiohttp \
                --hidden-import aiofiles \
                --hidden-import requests \
                --hidden-import pillow \
                --hidden-import img2pdf \
                --hidden-import sqlite3 \
                ../start.py
        fi
        
        cd ..
        
        if [ ! -f "$BUILD_DIR/dist/JMComicReader" ]; then
            echo "❌ 可执行文件生成失败"
            echo ""
            echo "请检查："
            echo "  1. 是否有足够的磁盘空间"
            echo "  2. 是否有写入权限"
            echo "  3. 查看上方错误信息"
            log_message "ERROR: Failed to build executable"
            return 1
        fi
    fi
    
    echo ""
    echo "✓ 可执行文件构建完成"
    log_message "Executable built successfully"
    return 0
}

create_portable_package() {
    print_header "📦 创建便携包"
    
    local portable_path="$DIST_DIR/$PORTABLE_DIR"
    rm -rf "$portable_path"
    mkdir -p "$portable_path"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 便携包
        echo "复制可执行文件..."
        cp "$BUILD_DIR/dist/JMComicReader" "$portable_path/"
        
        echo "创建 macOS 应用包..."
        local app_path="$portable_path/JMComicReader.app"
        mkdir -p "$app_path/Contents/MacOS"
        mkdir -p "$app_path/Contents/Resources"
        
        cp "$BUILD_DIR/dist/JMComicReader" "$app_path/Contents/MacOS/"
        
        cat > "$app_path/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>JMComicReader</string>
    <key>CFBundleIdentifier</key>
    <string>com.jmcomicreader.app</string>
    <key>CFBundleName</key>
    <string>JM漫画阅读器</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
</dict>
</plist>
EOF
        
        chmod +x "$app_path/Contents/MacOS/JMComicReader"
        EXE_NAME="JMComicReader.app"
        
    else
        # Linux 便携包
        echo "复制可执行文件..."
        cp "$BUILD_DIR/dist/JMComicReader" "$portable_path/"
        chmod +x "$portable_path/JMComicReader"
        EXE_NAME="JMComicReader"
    fi
    
    echo "复制启动脚本..."
    cp "启动.sh" "$portable_path/"
    
    echo "复制依赖文件..."
    cp "requirements.txt" "$portable_path/"
    
    echo "复制说明文档..."
    if [ -f "build/PORTABLE_README.txt" ]; then
        cp "build/PORTABLE_README.txt" "$portable_path/README.txt"
    else
        create_readme "$portable_path/README.txt"
    fi
    
    echo "创建目录结构..."
    mkdir -p "$portable_path/DownloadedComics"
    mkdir -p "$portable_path/TempCache"
    mkdir -p "$portable_path/TempCache/downloads"
    mkdir -p "$portable_path/backend"
    
    echo "✓ 便携包创建完成"
    log_message "Portable package created"
}

create_readme() {
    local readme_file="$1"
    
    cat > "$readme_file" << EOF
# JM漫画阅读器 一键启动包 v$VERSION

## 快速开始

### macOS 用户

**无需安装 Python！** 

1. 双击 \`JMComicReader.app\` 启动应用
2. 或在终端运行: \`./启动.sh\`
3. 访问 http://localhost:5000

### Linux 用户

**无需安装 Python！**

1. 运行: \`./启动.sh\`
2. 访问 http://localhost:5000

## 访问地址

启动后，在浏览器中访问:
- 本地访问: http://localhost:5000
- 局域网访问: http://你的IP:5000

## 停止服务

在终端窗口按 Ctrl+C 即可停止服务

## 目录说明

- \`JMComicReader.app\` / \`JMComicReader\` - 主程序（包含完整 Python 运行时）
- \`DownloadedComics/\` - 已下载的漫画
- \`TempCache/\` - 临时缓存目录

## 注意事项

- 首次运行会自动创建必要的目录和数据库文件
- 请确保端口 5000 未被占用
- 需要网络连接才能下载漫画
- 本程序已包含所有依赖，无需额外安装

## 系统要求

### macOS
- macOS Monterey (12.0) 或更高版本
- 网络连接
- **无需 Python**

### Linux
- Ubuntu 20.04 LTS 或更高版本
- 其他主流 Linux 发行版
- 网络连接
- **无需 Python**

## 故障排除

### macOS 无法打开应用
1. 右键点击应用，选择"打开"
2. 在安全提示中点击"打开"
3. 或在系统设置中允许来自未知开发者的应用

### Linux 权限问题
\`\`\`bash
chmod +x JMComicReader
\`\`\`

### 端口被占用
\`\`\`bash
lsof -i :5000
kill -9 <进程ID>
\`\`\`

## 技术支持

- 查看日志: startup.log
- 提交问题: https://github.com/bingking148/JMComicReaderProject/issues
EOF
}

get_local_ip() {
    if command -v ip &> /dev/null; then
        ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n 1
    elif command -v ifconfig &> /dev/null; then
        ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1
    else
        echo "无法获取IP地址"
    fi
}

main() {
    print_header "🎨 JM漫画阅读器 - 一键打包工具"
    
    echo "操作系统: $(uname -s) $(uname -r)"
    echo "架构: $(uname -m)"
    echo ""
    
    log_message "Starting packaging process"
    
    check_environment || exit 1
    install_build_tools || exit 1
    prepare_directories
    build_executable || exit 1
    create_portable_package
    
    print_header "✅ 打包完成！"
    
    echo "📦 打包位置: $DIST_DIR/$PORTABLE_DIR"
    echo ""
    echo "📋 打包内容:"
    echo "   • 可执行文件: $EXE_NAME (包含完整 Python 运行时)"
    echo "   • 启动脚本: 启动.sh"
    echo "   • 依赖文件: requirements.txt (备用)"
    echo "   • 说明文档: README.txt"
    echo ""
    echo "💡 使用方法:"
    echo "   将整个 $PORTABLE_DIR 文件夹复制到目标计算机"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "   双击 JMComicReader.app 或运行 ./启动.sh"
    else
        echo "   运行 ./启动.sh"
    fi
    echo ""
    echo "   **无需安装 Python！**"
    echo ""
    
    log_message "Packaging completed successfully"
}

main
