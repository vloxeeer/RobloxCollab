@echo off
title RobloxCollab Installer
echo ------------------------------------------
echo RobloxCollab: Cleaning old files...
echo ------------------------------------------

cd app
:: Удаляем сломанные папки если они есть
if exist node_modules ( rd /s /q node_modules )
if exist package-lock.json ( del /q package-lock.json )

echo ------------------------------------------
echo RobloxCollab: Installing (Using Mirror)...
echo ------------------------------------------

:: Установка переменной для обхода таймаутов Electron
set ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/

call npm install --network-timeout=100000

if %errorlevel% neq 0 (
    echo.
    echo ------------------------------------------
    echo ERROR: Installation failed! 
    echo Please check your internet or use a VPN.
    echo ------------------------------------------
    pause
    exit
)

echo ------------------------------------------
echo SUCCESS: Installation complete!
echo ------------------------------------------
pause