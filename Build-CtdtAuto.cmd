@echo off
chcp 65001 >nul
setlocal
title CTDT Auto - Build CtdtAuto.exe (Cuc bo)
echo Dang bien dich CtdtAuto.exe voi Icon game moi...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\Program Files (x86)\AutoIt3\Aut2Exe\Aut2exe_x64.exe' /in '%~dp0CTDT_auto_custom.au3' /out '%~dp0CtdtAuto.exe' /icon '%~dp0CtdtAuto.ico' /x64 /comp 1 /console"
if errorlevel 1 (
    echo.
    echo Bien dich that bai! Vui long kiem tra lai.
    pause
    exit /b 1
)
echo.
echo ==============================================
echo  Bien dich CtdtAuto.exe cuc bo thanh cong!
echo ==============================================
pause
