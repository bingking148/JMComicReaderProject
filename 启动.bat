@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

title JM漫画阅读器

echo.
echo ╔═══════════════════════════════════════════════════════════╗
echo ║          🎨 JM漫画阅读器 - 一键启动包 v1.0              ║
echo ║                                                           ║
echo ║           完整的JM漫画查找、下载、阅读系统               ║
echo ╚═══════════════════════════════════════════════════════════╝
echo.

cd /d "%~dp0"

set "PYTHON_CMD=python"
set "PYTHON_VERSION=3.8+"
set "APP_PORT=5000"

set "LOG_FILE=startup.log"

echo [%time%] 启动检查开始 > "%LOG_FILE%"

call :check_python
if errorlevel 1 (
    echo.
    echo ❌ 错误: 未找到 Python 或版本不符合要求
    echo.
    echo 请安装 Python %PYTHON_VERSION%:
    echo 1. 访问 https://www.python.org/downloads/
    echo 2. 下载并安装 Python 3.8 或更高版本
    echo 3. 安装时勾选 "Add Python to PATH"
    echo.
    pause
    exit /b 1
)

echo [%time%] Python 检查通过 >> "%LOG_FILE%"

call :check_dependencies
if errorlevel 1 (
    echo.
    echo ⚠ 正在安装依赖包...
    echo.
    call :install_dependencies
    if errorlevel 1 (
        echo.
        echo ❌ 依赖安装失败
        pause
        exit /b 1
    )
)

echo [%time%] 依赖检查通过 >> "%LOG_FILE%"

call :check_port
if errorlevel 1 (
    echo.
    set /p "continue=是否继续启动？(y/n): "
    if /i not "!continue!"=="y" (
        echo 已取消启动
        pause
        exit /b 0
    )
)

call :create_directories

echo.
echo ════════════════════════════════════════════════════════════
echo  🚀 正在启动 JM漫画阅读器...
echo ════════════════════════════════════════════════════════════
echo.
echo 📱 访问地址:
echo    • 本地访问: http://localhost:%APP_PORT%
echo    • 局域网: http://127.0.0.1:%APP_PORT%
echo.
echo 📂 数据目录:
echo    • 已下载漫画: "%~dp0DownloadedComics"
echo    • 临时缓存: "%~dp0TempCache"
echo.
echo ⌨️  按 Ctrl+C 可停止服务
echo.
echo ════════════════════════════════════════════════════════════
echo.

echo [%time%] 启动应用 >> "%LOG_FILE%"

set FLASK_ENV=production
python -c "from backend.app import app; app.run(host='0.0.0.0', port=%APP_PORT%, debug=False, use_reloader=False, threaded=True)"

pause
exit /b 0

:check_python
echo ✓ 检查 Python 环境...
"%PYTHON_CMD%" --version >nul 2>&1
if errorlevel 1 (
    echo   ✗ Python 未安装或未添加到 PATH
    exit /b 1
)

for /f "tokens=2" %%i in ('%PYTHON_CMD% --version 2^>^&1') do set "PY_VER=%%i"
echo   ✓ Python 版本: %PY_VER%

for /f "tokens=1,2 delims=." %%a in ("%PY_VER%") do (
    set "MAJOR=%%a"
    set "MINOR=%%b"
)

if %MAJOR% lss 3 (
    echo   ✗ Python 版本过低，需要 3.8+
    exit /b 1
)
if %MAJOR% equ 3 if %MINOR% lss 8 (
    echo   ✗ Python 版本过低，需要 3.8+
    exit /b 1
)

exit /b 0

:check_dependencies
echo ✓ 检查 Python 依赖...
"%PYTHON_CMD%" -c "import flask" 2>nul
if errorlevel 1 (
    echo   ✗ 缺少 flask
    exit /b 1
)
"%PYTHON_CMD%" -c "import flask_cors" 2>nul
if errorlevel 1 (
    echo   ✗ 缺少 flask_cors
    exit /b 1
)
"%PYTHON_CMD%" -c "import jmcomic" 2>nul
if errorlevel 1 (
    echo   ✗ 缺少 jmcomic
    exit /b 1
)

echo   ✓ 所有依赖已安装
exit /b 0

:install_dependencies
echo.
echo ════════════════════════════════════════════════════════════
echo  📦 安装依赖包中...
echo ════════════════════════════════════════════════════════════
echo.

if exist requirements.txt (
    "%PYTHON_CMD%" -m pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
) else (
    echo   安装核心依赖...
    "%PYTHON_CMD%" -m pip install flask flask-cors jmcomic requests pillow img2pdf aiofiles aiohttp -i https://pypi.tuna.tsinghua.edu.cn/simple
)

if errorlevel 1 (
    echo.
    echo ❌ 依赖安装失败
    exit /b 1
)

echo.
echo ✓ 依赖安装完成
exit /b 0

:check_port
echo ✓ 检查端口 %APP_PORT%...
netstat -ano | findstr ":%APP_PORT%" >nul 2>&1
if errorlevel 1 (
    echo   ✓ 端口 %APP_PORT% 可用
    exit /b 0
) else (
    echo   ⚠ 端口 %APP_PORT% 已被占用
    echo.
    echo   可能有其他程序正在使用此端口
    echo.
    exit /b 1
)

:create_directories
echo ✓ 创建必要目录...
if not exist "DownloadedComics" mkdir "DownloadedComics"
if not exist "TempCache" mkdir "TempCache"
if not exist "TempCache\downloads" mkdir "TempCache\downloads"
if not exist "backend" mkdir "backend"

exit /b 0
