@echo off
rem Lyons Tools launcher - ehtu.com
rem Double-click to open Lyons Tools. Uses lyonstools.ps1 next to this file if present,
rem otherwise downloads the latest version from GitHub.
rem Extra arguments are passed through, e.g.:  LyonsTools.cmd -Run office-crash-protection -Minutes 5
setlocal
title Lyons Tools
set "LT_LOCAL=%~dp0lyonstools.ps1"
set "LT_URL=https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1"

if exist "%LT_LOCAL%" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%LT_LOCAL%" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -Command "[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; & ([scriptblock]::Create((Invoke-RestMethod '%LT_URL%'))) %*"
)
endlocal
