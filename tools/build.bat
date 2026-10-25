@echo off
rem ============================================================
rem  tools\build.bat -- launcher only.
rem
rem  All logic lives in tools\build.ps1 (UTF-8 with BOM, CRLF).
rem  THIS FILE MUST STAY PURE ASCII: cmd.exe reads a batch file
rem  and decodes it with the active code page, so a multi-byte
rem  character that straddles a read-buffer boundary shifts the
rem  parse and the tail of the line gets executed as a command
rem  ("<fragment> is not recognized as an internal or external command").
rem
rem  Usage:  tools\build.bat [-o DIR] [-n] [--no-vdf] [--workshop-id ID] [-h]
rem  Exit:   0 ok / 2 bad source / 3 bad arg or unsafe path / 4 post-check failed
rem ============================================================
setlocal

set "PS_EXE=powershell"
where pwsh.exe >nul 2>nul
if not errorlevel 1 set "PS_EXE=pwsh"

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
set "RC=%ERRORLEVEL%"

endlocal & exit /b %RC%