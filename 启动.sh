#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_PORT=5000
LOG_FILE="startup.log"

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

check_port() {
    echo "✓ 检查端口 $APP_PORT..."
    
    if lsof -Pi :$APP_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "  ⚠ 端口 $APP_PORT 已被占用"
        echo ""
        echo "  可能有其他程序正在使用此端口"
        echo ""
        log_message "WARNING: Port $APP_PORT already in use"
        return 1
    fi
    
    echo "  ✓ 端口 $APP_PORT 可用"
    log_message "Port $APP_PORT is available"
    return 0
}

create_directories() {
    echo "✓ 创建必要目录..."
    
    mkdir -p DownloadedComics
    mkdir -p TempCache/downloads
    mkdir -p backend
    
    log_message "Directories created"
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
    log_message "Startup check started"
    
    print_header "🎨 JM漫画阅读器 - 一键启动包 v1.0"
    
    check_port || {
        echo ""
        read -p "是否继续启动？: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "已取消启动"
            log_message "Startup cancelled by user"
            exit 0
        fi
    }
    
    create_directories
    
    # 优先检查是否有打包好的可执行文件
    if [[ "$OSTYPE" == "darwin"* ]] && [ -d "JMComicReader.app" ]; then
        # macOS 应用包
        echo ""
        echo "✓ 检测到独立可执行文件（macOS 应用）"
        echo ""
        print_header "🚀 正在启动 JM漫画阅读器（独立模式）..."
        echo ""
        echo "📱 访问地址:"
        echo "   • 本地访问: http://localhost:$APP_PORT"
        
        LOCAL_IP=$(get_local_ip)
        if [ "$LOCAL_IP" != "无法获取IP地址" ]; then
            echo "   • 局域网: http://$LOCAL_IP:$APP_PORT"
        fi
        
        echo ""
        echo "📂 数据目录:"
        echo "   • 已下载漫画: \"$SCRIPT_DIR/DownloadedComics\""
        echo "   • 临时缓存: \"$SCRIPT_DIR/TempCache\""
        echo ""
        echo "⌨️  按 Ctrl+C 可停止服务"
        echo ""
        print_header "═══════════════════════════════════════════════════════════"
        echo ""
        
        log_message "Starting standalone application (macOS app)"
        
        open "JMComicReader.app"
        exit 0
        
    elif [ -f "JMComicReader" ]; then
        # Linux 可执行文件
        echo ""
        echo "✓ 检测到独立可执行文件"
        echo ""
        print_header "🚀 正在启动 JM漫画阅读器（独立模式）..."
        echo ""
        echo "📱 访问地址:"
        echo "   • 本地访问: http://localhost:$APP_PORT"
        
        LOCAL_IP=$(get_local_ip)
        if [ "$LOCAL_IP" != "无法获取IP地址" ]; then
            echo "   • 局域网: http://$LOCAL_IP:$APP_PORT"
        fi
        
        echo ""
        echo "📂 数据目录:"
        echo "   • 已下载漫画: \"$SCRIPT_DIR/DownloadedComics\""
        echo "   • 临时缓存: \"$SCRIPT_DIR/TempCache\""
        echo ""
        echo "⌨️  按 Ctrl+C 可停止服务"
        echo ""
        print_header "═══════════════════════════════════════════════════════════"
        echo ""
        
        log_message "Starting standalone application"
        
        ./JMComicReader
        exit 0
    fi
    
    # 如果没有可执行文件，检查 Python 环境
    check_python || {
        echo ""
        print_header "⚠️  未检测到独立可执行文件"
        echo ""
        echo "❌ 错误: 未找到 Python 环境"
        echo ""
        echo "请选择以下方式之一:"
        echo ""
        echo "方式一: 下载独立可执行文件（推荐）"
        echo "  从项目发布页面下载:"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "    - JMComicReader.app (macOS)"
        else
            echo "    - JMComicReader (Linux)"
        fi
        echo ""
        echo "方式二: 安装 Python 环境"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "  1. 使用 Homebrew: brew install python3"
            echo "  2. 或访问: https://www.python.org/downloads/"
        else
            echo "  Ubuntu/Debian: sudo apt-get install python3 python3-pip"
            echo "  CentOS/RHEL: sudo yum install python3 python3-pip"
            echo "  或访问: https://www.python.org/downloads/"
        fi
        echo ""
        read -p "按任意键退出..." -n1 -s
        exit 1
    }
    
    check_dependencies || {
        echo ""
        echo "⚠ 正在安装依赖包..."
        echo ""
        install_dependencies || {
            echo ""
            read -p "按任意键退出..." -n1 -s
            exit 1
        }
    }
    
    echo ""
    print_header "🚀 正在启动 JM漫画阅读器（Python 模式）..."
    echo ""
    echo "📱 访问地址:"
    echo "   • 本地访问: http://localhost:$APP_PORT"
    
    LOCAL_IP=$(get_local_ip)
    if [ "$LOCAL_IP" != "无法获取IP地址" ]; then
        echo "   • 局域网: http://$LOCAL_IP:$APP_PORT"
    fi
    
    echo ""
    echo "📂 数据目录:"
    echo "   • 已下载漫画: \"$SCRIPT_DIR/DownloadedComics\""
    echo "   • 临时缓存: \"$SCRIPT_DIR/TempCache\""
    echo ""
    echo "⌨️  按 Ctrl+C 可停止服务"
    echo ""
    print_header "═══════════════════════════════════════════════════════════"
    echo ""
    
    log_message "Starting application"
    
    export FLASK_ENV=production
    $PYTHON_CMD -c "from backend.app import app; app.run(host='0.0.0.0', port=$APP_PORT, debug=False, use_reloader=False, threaded=True)"
}

check_python() {
    echo "✓ 检查 Python 环境..."
    
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
    
    MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
    MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
    
    if [ "$MAJOR" -lt 3 ] || { [ "$MAJOR" -eq 3 ] && [ "$MINOR" -lt 8 ]; }; then
        echo "  ✗ Python 版本过低，需要 3.8+"
        log_message "ERROR: Python version too low"
        return 1
    fi
    
    return 0
}

check_dependencies() {
    echo "✓ 检查 Python 依赖..."
    
    local missing_deps=()
    
    $PYTHON_CMD -c "import flask" 2>/dev/null || missing_deps+=("flask")
    $PYTHON_CMD -c "import flask_cors" 2>/dev/null || missing_deps+=("flask-cors")
    $PYTHON_CMD -c "import jmcomic" 2>/dev/null || missing_deps+=("jmcomic")
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "  ✗ 缺少依赖: ${missing_deps[*]}"
        log_message "ERROR: Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
    
    echo "  ✓ 所有依赖已安装"
    log_message "Dependencies check passed"
    return 0
}

install_dependencies() {
    print_header "📦 安装依赖包中..."
    echo ""
    
    if [ -f "requirements.txt" ]; then
        $PYTHON_CMD -m pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
    else
        echo "  安装核心依赖..."
        $PYTHON_CMD -m pip install flask flask-cors jmcomic requests pillow img2pdf aiofiles aiohttp -i https://pypi.tuna.tsinghua.edu.cn/simple
    fi
    
    if [ $? -ne 0 ]; then
        echo ""
        echo "❌ 依赖安装失败"
        log_message "ERROR: Failed to install dependencies"
        return 1
    fi
    
    echo ""
    echo "✓ 依赖安装完成"
    log_message "Dependencies installed successfully"
    return 0
}

trap 'echo ""; echo "服务已停止"; log_message "Service stopped"; exit 0' INT TERM

main
