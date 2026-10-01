@echo off
rem Lyons Tools launcher - ehtu.com
rem Double-click to open Lyons Tools. Uses lyonstools.ps1 next to this file if present,
rem otherwise downloads the latest version from GitHub.
rem Extra arguments are passed through, e.g.:  LyonsTools.cmd -Run office-crash-protection -Minutes 5
rem The script is loaded as a command (not with -File), so it also runs where a Group Policy
rem execution policy blocks unsigned script files. TLS 1.2 is forced for old Windows 10 / Server 2016.
setlocal
title Lyons Tools
set "LT_LOCAL=%~dp0lyonstools.ps1"
set "LT_URL=https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1"

if exist "%LT_LOCAL%" (
    powershell.exe -NoProfile -STA -Command "& ([scriptblock]::Create((Get-Content -LiteralPath '%LT_LOCAL%' -Raw))) %*"
) else (
    powershell.exe -NoProfile -STA -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; & ([scriptblock]::Create((Invoke-RestMethod '%LT_URL%'))) %*"
)
endlocal
