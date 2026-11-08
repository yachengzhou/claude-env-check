@echo off
start "" /min powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0tun-agent.ps1"
exit /b
