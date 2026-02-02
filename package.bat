@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

title JM漫画阅读器 - 打包工具

echo.
echo ╔═══════════════════════════════════════════════════════════╗
echo ║          🎨 JM漫画阅读器 - 一键打包工具                 ║
echo ╚═══════════════════════════════════════════════════════════╝
echo.

cd /d "%~dp0"

set "BUILD_DIR=build"
set "DIST_DIR=dist"
set "PORTABLE_DIR=JMComicReader_Portable"
set "VERSION=1.0.0"

set "PYTHON_CMD=python"

echo [%time%] 开始打包 >> build.log

call :check_environment
if errorlevel 1 (
    echo.
    echo ❌ 环境检查失败
    pause
    exit /b 1
)

call :install_build_tools
if errorlevel 1 (
    echo.
    echo ❌ 构建工具安装失败
    pause
    exit /b 1
)

call :prepare_directories

call :build_executable
if errorlevel 1 (
    echo.
    echo ❌ 可执行文件构建失败
    pause
    exit /b 1
)

call :create_portable_package
if errorlevel 1 (
    echo.
    echo ❌ 便携包创建失败
    pause
    exit /b 1
)

echo.
echo ════════════════════════════════════════════════════════════
echo  ✅ 打包完成！
echo ════════════════════════════════════════════════════════════
echo.
echo 📦 打包位置: %DIST_DIR%\%PORTABLE_DIR%
echo.
echo 📋 打包内容:
echo    • 可执行文件: JMComicReader.exe
echo    • 启动脚本: 启动.bat
echo    • 依赖文件: requirements.txt
echo    • 说明文档: README.txt
echo.
echo 💡 使用方法:
echo    将整个 %PORTABLE_DIR% 文件夹复制到目标计算机
echo    双击 '启动.bat' 即可运行
echo.
echo [%time%] 打包完成 >> build.log

pause
exit /b 0

:check_environment
echo ✓ 检查构建环境...

"%PYTHON_CMD%" --version >nul 2>&1
if errorlevel 1 (
    echo   ✗ Python 未安装
    exit /b 1
)

for /f "tokens=2" %%i in ('%PYTHON_CMD% --version 2^>^&1') do set "PY_VER=%%i"
echo   ✓ Python 版本: %PY_VER%

exit /b 0

:install_build_tools
echo.
echo ════════════════════════════════════════════════════════════
echo  📦 安装构建工具...
echo ════════════════════════════════════════════════════════════
echo.

echo 正在安装 PyInstaller...
"%PYTHON_CMD%" -m pip install pyinstaller -i https://pypi.tuna.tsinghua.edu.cn/simple

if errorlevel 1 (
    echo ❌ PyInstaller 安装失败
    exit /b 1
)

echo ✓ PyInstaller 安装完成
exit /b 0

:prepare_directories
echo.
echo ✓ 准备构建目录...

if exist "%BUILD_DIR%\build" rmdir /s /q "%BUILD_DIR%\build"
if exist "%DIST_DIR%" rmdir /s /q "%DIST_DIR%"

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

exit /b 0

:build_executable
echo.
echo ════════════════════════════════════════════════════════════
echo  🔨 构建可执行文件...
echo ════════════════════════════════════════════════════════════
echo.

cd %BUILD_DIR%

if exist "jm_reader.spec" (
    echo 使用现有的 spec 文件...
    "%PYTHON_CMD%" -m PyInstaller --clean jm_reader.spec
) else (
    echo 使用默认配置构建...
    "%PYTHON_CMD%" -m PyInstaller --onefile --name JMComicReader --add-data "../backend;backend" --add-data "../frontend;frontend" ../start.py
)

cd ..

if not exist "%BUILD_DIR%\dist\JMComicReader.exe" (
    echo ❌ 可执行文件生成失败
    exit /b 1
)

echo ✓ 可执行文件构建完成
exit /b 0

:create_portable_package
echo.
echo ════════════════════════════════════════════════════════════
echo  📦 创建便携包...
echo ════════════════════════════════════════════════════════════
echo.

set "PORTABLE_PATH=%DIST_DIR%\%PORTABLE_DIR%"
if exist "%PORTABLE_PATH%" rmdir /s /q "%PORTABLE_PATH%"
mkdir "%PORTABLE_PATH%"

echo 复制可执行文件...
copy "%BUILD_DIR%\dist\JMComicReader.exe" "%PORTABLE_PATH%\" >nul

echo 复制启动脚本...
copy "启动.bat" "%PORTABLE_PATH%\" >nul

echo 复制依赖文件...
copy "requirements.txt" "%PORTABLE_PATH%\" >nul

echo 复制说明文档...
copy "build\PORTABLE_README.txt" "%PORTABLE_PATH%\README.txt" >nul 2>nul
if errorlevel 1 (
    echo 创建说明文档...
    (
        echo # JM漫画阅读器 一键启动包 v%VERSION%
        echo.
        echo ## 快速开始
        echo.
        echo ### Windows 用户
        echo 双击 `启动.bat` 文件即可启动应用
        echo.
        echo ## 访问地址
        echo.
        echo 启动后，在浏览器中访问:
        echo - 本地访问: http://localhost:5000
        echo - 局域网访问: http://你的IP:5000
        echo.
        echo ## 停止服务
        echo.
        echo 在运行窗口按 Ctrl+C 即可停止服务
        echo.
        echo ## 目录说明
        echo.
        echo - `JMComicReader.exe` - 主程序
        echo - `DownloadedComics/` - 已下载的漫画
        echo - `TempCache/` - 临时缓存目录
        echo.
        echo ## 注意事项
        echo.
        echo - 首次运行会自动创建必要的目录和数据库文件
        echo - 请确保端口 5000 未被占用
        echo - 需要网络连接才能下载漫画
        echo.
        echo ## 系统要求
        echo.
        echo - Windows 10/11
        echo - 网络连接
        echo - 无需预装 Python
        echo.
    ) > "%PORTABLE_PATH%\README.txt"
)

echo 创建目录结构...
mkdir "%PORTABLE_PATH%\DownloadedComics" 2>nul
mkdir "%PORTABLE_PATH%\TempCache" 2>nul
mkdir "%PORTABLE_PATH%\TempCache\downloads" 2>nul
mkdir "%PORTABLE_PATH%\backend" 2>nul

echo.
echo ✓ 便携包创建完成
exit /b 0
