@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
set "PS=powershell.exe -NoProfile -ExecutionPolicy Bypass"

echo.
echo   ================================================
echo     AI-Lab  Daily Four Tasks  -  Switch
echo   ================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%toggle.ps1" -Action status

echo.
echo   [1] Enable  auto-generate (Mon-Fri 07:30)
echo   [2] Disable auto-generate
echo   [3] Regenerate TODAY's tasks now (overwrite)
echo   [4] Force TODAY even on weekend/holiday
echo   [5] Show next 21 days calendar
echo   [0] Exit
echo.
set /p "CH=  Choose: "

if "%CH%"=="1" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%toggle.ps1" -Action on
if "%CH%"=="2" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%toggle.ps1" -Action off
if "%CH%"=="3" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%daily-generate.ps1" -Force
if "%CH%"=="4" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%daily-generate.ps1" -Force -IgnoreCalendar
if "%CH%"=="5" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%toggle.ps1" -Action calendar -Days 21

echo.
pause
endlocal
