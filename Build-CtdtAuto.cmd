@echo off
setlocal
title CTDT Auto - Build CtdtAuto.exe
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0updater\Build-And-Publish.ps1" -BuildOnly -Version "2026.11.22.3"
if errorlevel 1 (
    echo.
    echo Build CtdtAuto.exe that bai. Hay kiem tra thong bao o tren.
    pause
    exit /b 1
)
echo.
echo Da build CtdtAuto.exe thanh cong!
pause
