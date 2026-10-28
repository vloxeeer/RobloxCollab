@echo off
title RobloxCollab Ultimate Installer
echo ------------------------------------------
echo 1. Cleaning up environment...
echo ------------------------------------------

:: Очистка кэша и старых настроек
call npm config delete proxy
call npm config delete https-proxy
call npm config set strict-ssl false
call npm config set registry https://registry.npmmirror.com

:: Настройка зеркал для Electron
set ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
set ELECTRON_CUSTOM_DIR=v28.1.0

cd app

:: Удаление node_modules если они есть (с принуждением)
if exist node_modules (
    echo Removing old node_modules...
    rd /s /q node_modules
)

echo ------------------------------------------
echo 2. Starting Installation (Network Timeout Fix)...
echo ------------------------------------------

:: Запуск установки с игнорированием ошибок Electron (мы поставим его позже если что)
call npm install --network-timeout=1000000 --no-audit --no-fund

if %errorlevel% neq 0 (
    echo ------------------------------------------
    echo ERROR: Installation failed. 
    echo Trying alternative method...
    echo ------------------------------------------
    call npm install electron@28.1.0 --save-dev --electron_mirror=https://npmmirror.com/mirrors/electron/
)

echo ------------------------------------------
echo 3. Finalizing...
echo ------------------------------------------
pause