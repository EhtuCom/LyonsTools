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

# Windows PowerShell 5.1 (Windows 10 / Server 2016 or later) is required: 'class ::new()' syntax, Expand-Archive...
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "Lyons Tools needs Windows PowerShell 5.1 (Windows 10, Windows Server 2016 or later). This computer has PowerShell $($PSVersionTable.PSVersion)." -ForegroundColor Red
    return
}
# TLS 1.2 for every download (older Windows 10 / Server 2016 default to TLS 1.0); TLS 1.3 when the OS supports it.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Enum]::Parse([Net.SecurityProtocolType], 'Tls13') } catch { }

# Environment: Windows 10/11 vs Windows Server, Remote Desktop Session Host, remote session, admin rights.
$LT.Build = [Environment]::OSVersion.Version.Build
$LT.IsServer = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).ProductType -ne 1
# TSAppCompat = 1 on a Remote Desktop Session Host (terminal server); installers must run in "install mode" there.
$LT.IsRdsHost = $LT.IsServer -and ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue).TSAppCompat -eq 1)
$LT.IsRemoteSession = [bool]($env:SESSIONNAME -match '^(RDP|ICA)-')
