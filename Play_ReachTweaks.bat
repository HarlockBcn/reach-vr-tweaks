@echo off
title ReachTweaks
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launcher\ReachTweaks.ps1" %*
if errorlevel 1 pause
timeout /t 5 >nul
