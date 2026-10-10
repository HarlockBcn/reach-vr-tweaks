@echo off
title ReachTweaks - Uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launcher\ReachTweaks.ps1" -Uninstall
pause
