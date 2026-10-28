@echo off
title RobloxCollab Installer
echo ------------------------------------------
echo RobloxCollab: Installing...
echo ------------------------------------------

:: Проверка Node.js
node -v >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Node.js not found! Please install it from https://nodejs.org
    pause
    exit
)

cd app
call npm install
echo ------------------------------------------
echo SUCCESS: Installation complete!
echo ------------------------------------------
pause