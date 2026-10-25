@echo off
setlocal
if exist "%~dp0runtime.local.cmd" call "%~dp0runtime.local.cmd"
if defined VADER_PWSH goto run
where pwsh.exe >nul 2>&1
if not errorlevel 1 (
    set "VADER_PWSH=pwsh.exe"
    goto run
)
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set "VADER_PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
    goto run
)
echo PowerShell 7 is required. Install it or add pwsh.exe to PATH.
pause
exit /b 1
:run
"%VADER_PWSH%" -NoProfile -STA -File "%~dp0VaderMappings.ps1"
if errorlevel 1 pause
