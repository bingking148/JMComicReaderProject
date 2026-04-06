@echo off
setlocal

cd /d "%~dp0"

set /p APP_VERSION=<VERSION
set "ISCC="

call build_desktop.bat
if errorlevel 1 goto :error

if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not defined ISCC for /f "delims=" %%I in ('where iscc 2^>nul') do set "ISCC=%%I"

if not defined ISCC (
    echo Inno Setup 6 is not installed.
    echo Install it first, then rerun this script.
    exit /b 1
)

echo Building Windows installer...
"%ISCC%" /DAppVersion=%APP_VERSION% "JMComicReaderInstaller.iss"
if errorlevel 1 goto :error

echo.
echo Installer finished.
echo Setup: %cd%\dist\JMComicReader-Setup-v%APP_VERSION%.exe
goto :eof

:error
echo.
echo Installer build failed.
exit /b 1
