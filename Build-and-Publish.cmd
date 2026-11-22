@echo off
chcp 65001 >nul
setlocal
title CTDT Auto - Build va Phat Hanh GitHub Release
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Publish-NewVersion.ps1"
if errorlevel 1 (
    echo.
    echo Phat hanh len GitHub that bai. Vui long kiem tra thong bao loi o tren.
    pause
    exit /b 1
)
echo.
pause
