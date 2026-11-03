@echo off
chcp 65001 >nul 2>nul
setlocal
set "PS1=%~dp0gki.ps1"
if not exist "%PS1%" (
  echo [X] gki.ps1 missing
  pause
  exit /b 1
)
where pwsh >nul 2>nul
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
)
set "RC=%errorlevel%"
if "%~1"=="" pause
exit /b %RC%