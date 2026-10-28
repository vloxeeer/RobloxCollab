@echo off
chcp 65001 >nul
echo.
echo  ╔══════════════════════════════════════════╗
echo  ║       RobloxCollab — Установка           ║
echo  ╚══════════════════════════════════════════╝
echo.

echo [1/2] Проверяю Node.js...
node --version >nul 2>&1
if errorlevel 1 (
    echo.
    echo  ОШИБКА: Node.js не найден!
    echo  Скачай с https://nodejs.org и установи
    echo  Потом запусти install.bat снова
    echo.
    pause
    exit
)
echo  ✓ Node.js найден

echo.
echo [2/2] Устанавливаю зависимости...
cd app
call npm install
cd ..

echo.
echo  ╔══════════════════════════════════════════╗
echo  ║       Установка завершена!               ║
echo  ║       Запусти start.bat                  ║
echo  ╚══════════════════════════════════════════╝
echo.
pause