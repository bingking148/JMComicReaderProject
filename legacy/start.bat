@echo off
chcp 65001 >nul
echo ========================================
echo JMComicReader 项目启动器
echo ========================================
echo.

cd /d "%~dp0"

echo 正在检查端口 5000...
netstat -ano | findstr :5000 >nul
if %errorlevel% equ 0 (
    echo 警告：端口 5000 已被占用！
    echo 可能已经有实例在运行。
    echo.
    set /p choice="是否继续启动？(y/n) "
    if not "%choice%"=="y" (
        echo 已取消启动。
        exit /b 1
    )
)

echo.
echo 正在启动 Flask 应用（关闭自动重载模式）...
echo ========================================
echo 访问地址：
echo   - 本地: http://localhost:5000
echo   - 局域网: http://%computername%:5000
echo.
echo 按 Ctrl+C 停止服务
echo ========================================
echo.

REM 启动 Flask，禁用自动重载和调试模式
set FLASK_ENV=production
python -c "from backend.app import app; app.run(host='0.0.0.0', port=5000, debug=False, use_reloader=False)"
