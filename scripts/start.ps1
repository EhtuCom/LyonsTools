<#
.SYNOPSIS
    Lyons Tools - Windows, Office, Java and digital signature utilities (ehtu.com)

.PARAMETER Run
    Runs actions without opening the window. Comma-separated IDs (see -List).
    Example: -Run office-crash-protection,java-check

.PARAMETER Minutes
    AutoRecover interval in minutes for the Office actions (1-120, default 5).

.PARAMETER Lang
    Interface language: en (English, default), es (Español) or ca (Català).
    The choice made in the window is remembered per user.

.PARAMETER List
    Lists the IDs of all available actions.

.EXAMPLE
    irm https://raw.githubusercontent.com/__LT_REPO__/main/lyonstools.ps1 | iex

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/__LT_REPO__/main/lyonstools.ps1))) -Run office-crash-protection -Minutes 3 -Lang es
#>
param(
    [string[]]$Run,
    [ValidateRange(1, 120)][int]$Minutes = 5,
    [ValidateSet('', 'en', 'es', 'ca')][string]$Lang = '',
    [switch]$List
)

$LT = [hashtable]::Synchronized(@{})
$LT.Version = '__LT_VERSION__'
$LT.Repo = '__LT_REPO__'
$LT.SourceUrl = 'https://raw.githubusercontent.com/__LT_REPO__/main/lyonstools.ps1'
# A regular browser user agent: some official sites (abogacia.es) block unknown clients.
$LT.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'
$LT.OfficePolicyRoot = 'Software\Policies\Microsoft\Office\16.0'
$LT.Gui = $false
$LT.Busy = $false

# Per-user settings (language), kept in the user's profile so it also works on terminal servers.
$LT.DataDir = Join-Path $env:LOCALAPPDATA 'LyonsTools'
$LT.SettingsFile = Join-Path $LT.DataDir 'settings.json'
$LT.Settings = $null
try { $LT.Settings = Get-Content -LiteralPath $LT.SettingsFile -Raw -ErrorAction Stop | ConvertFrom-Json } catch { }
$LT.Lang = if ($Lang) { $Lang } elseif ($LT.Settings.lang -in 'en', 'es', 'ca') { $LT.Settings.lang } else { 'en' }

# Environment: Windows 10/11 vs Windows Server, terminal server session, admin rights.
$LT.IsServer = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).ProductType -ne 1
$LT.IsRemoteSession = [bool]($env:SESSIONNAME -like 'RDP-*')
