@echo off
chcp 65001 >nul 2>nul
where pwsh >nul 2>nul
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0cloud.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cloud.ps1" %*
)
if "%~1"=="" pause