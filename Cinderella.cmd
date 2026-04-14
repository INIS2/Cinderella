@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Cinderella.Gui.ps1" %*
