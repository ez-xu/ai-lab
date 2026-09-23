@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
set "PS=powershell.exe -NoProfile -ExecutionPolicy Bypass"

echo.
echo   ============================================
echo     AI-Lab  Daily Two Tasks  -  Switch
echo   ============================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%scripts\toggle.ps1" -Action status

echo.
echo   [1] Enable  auto-generate every morning 07:30
echo   [2] Disable auto-generate
echo   [3] Regenerate TODAY's tasks now
echo   [0] Exit
echo.
set /p "CH=  Choose: "

if "%CH%"=="1" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%scripts\toggle.ps1" -Action on
if "%CH%"=="2" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%scripts\toggle.ps1" -Action off
if "%CH%"=="3" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%scripts\daily-generate.ps1" -Force

echo.
pause
endlocal
