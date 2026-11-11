@echo off
setlocal

cd /d "%~dp0"

set /p APP_VERSION=<VERSION
set "ZIP_PATH=dist\JMComicReader-win64-v%APP_VERSION%.zip"

echo Installing desktop build dependencies...
python -m pip install -r requirements.txt pyinstaller
if errorlevel 1 goto :error

echo Cleaning previous desktop build...
if exist build rmdir /s /q build
if exist dist rmdir /s /q dist

echo Building JMComicReader desktop package...
pyinstaller JMComicReader.spec --noconfirm --clean
if errorlevel 1 goto :error

echo Creating release zip...
powershell -NoProfile -Command "Compress-Archive -Path 'dist\\JMComicReader' -DestinationPath '%ZIP_PATH%' -Force"
if errorlevel 1 goto :error

echo.
echo Build finished.
echo Output: %cd%\dist\JMComicReader\JMComicReader.exe
echo Zip: %cd%\%ZIP_PATH%
goto :eof

:error
echo.
echo Build failed.
exit /b 1
