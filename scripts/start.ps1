<#
.SYNOPSIS
    Lyons Tools - utilidades para Windows, Office, Java y firma digital (ehtu.com)

.PARAMETER Run
    Ejecuta acciones sin abrir la interfaz. IDs separados por comas (ver -List).
    Ejemplo: -Run office-crash-protection,java-check

.PARAMETER Minutes
    Intervalo de autoguardado en minutos para las acciones de Office (1-120, por defecto 5).

.PARAMETER List
    Muestra los IDs de todas las acciones disponibles.

.EXAMPLE
    irm https://raw.githubusercontent.com/__LT_REPO__/main/lyonstools.ps1 | iex

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/__LT_REPO__/main/lyonstools.ps1))) -Run office-crash-protection -Minutes 3
#>
param(
    [string[]]$Run,
    [ValidateRange(1, 120)][int]$Minutes = 5,
    [switch]$List
)

$LT = [hashtable]::Synchronized(@{})
$LT.Version = '__LT_VERSION__'
$LT.Repo = '__LT_REPO__'
$LT.SourceUrl = 'https://raw.githubusercontent.com/__LT_REPO__/main/lyonstools.ps1'
$LT.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) LyonsTools/$($LT.Version)"
$LT.OfficePolicyRoot = 'Software\Policies\Microsoft\Office\16.0'
$LT.Gui = $false
$LT.Busy = $false
