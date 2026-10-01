#region Core helpers ------------------------------------------------------------

function Write-LTLog {
    <#
        Writes a line to the console, the GUI log panel (through a thread-safe queue
        drained by the UI timer) and the daily log file.
    #>
    param(
        [Parameter(Position = 0)][AllowEmptyString()][string]$Message,
        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Step')][string]$Level = 'Info'
    )
    $tag = switch ($Level) {
        'Ok'    { '[OK]   ' }
        'Warn'  { '[AVISO]' }
        'Error' { '[ERROR]' }
        'Step'  { '=====> ' }
        default { '       ' }
    }
    $line = '{0} {1} {2}' -f (Get-Date -Format 'HH:mm:ss'), $tag, $Message

    if ($LT.LogQueue) { $LT.LogQueue.Enqueue($line) }
    if (-not $LT.Gui) {
        $color = switch ($Level) { 'Ok' { 'Green' } 'Warn' { 'Yellow' } 'Error' { 'Red' } 'Step' { 'Cyan' } default { 'Gray' } }
        Write-Host $line -ForegroundColor $color
    }
    if ($LT.LogFile) {
        try { Add-Content -LiteralPath $LT.LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
    }
}

function Test-LTAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-LTElevated {
    <#
        Runs a self-contained PowerShell script with administrator rights.
        It always runs in a child powershell.exe; a UAC prompt is shown unless we are already elevated.
        The rest of Lyons Tools keeps running as the logged-on user, so HKCU tweaks
        always land in the right profile.
        Returns the exit code (or -1 if the user cancelled UAC).
    #>
    param([Parameter(Mandatory)][string]$Script)

    # Always a child process (the script may call 'exit'); only ask for UAC when needed.
    $wrapped = "`$ErrorActionPreference='Stop'`ntry {`n$Script`nexit 0`n} catch { exit 1 }"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapped))
    $splat = @{
        FilePath     = 'powershell.exe'
        ArgumentList = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
        Wait         = $true
        PassThru     = $true
        WindowStyle  = 'Hidden'
        ErrorAction  = 'Stop'
    }
    if (-not (Test-LTAdmin)) { $splat.Verb = 'RunAs' }
    try {
        $p = Start-Process @splat
        return $p.ExitCode
    }
    catch {
        Write-LTLog "Se ha cancelado la solicitud de permisos de administrador." -Level Warn
        return -1
    }
}

function Get-LTWorkFolder {
    $dir = Join-Path $env:TEMP 'LyonsTools'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dir
}

function Initialize-LTWeb {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $global:ProgressPreference = 'SilentlyContinue'
}

function Get-LTWebPage {
    param([Parameter(Mandatory)][string]$Url)
    Initialize-LTWeb
    Invoke-WebRequest -Uri $Url -UseBasicParsing -UserAgent $LT.UserAgent -ErrorAction Stop
}

function Find-LTWebLink {
    <#
        Returns the first absolute link on $Url whose href matches $Pattern.
        Used to always pick the latest installer instead of hardcoding versioned file names.
    #>
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Pattern
    )
    $page = Get-LTWebPage -Url $Url
    $hrefs = @($page.Links | ForEach-Object { $_.href }) + @([regex]::Matches($page.Content, 'https?://[^"''\s<>]+') | ForEach-Object { $_.Value })
    $match = $hrefs | Where-Object { $_ -match $Pattern } | Select-Object -First 1
    if (-not $match) { return $null }
    $match = [Net.WebUtility]::HtmlDecode($match)
    ([Uri]::new([Uri]$Url, $match)).AbsoluteUri
}

function Save-LTFile {
    <# Downloads $Url into the work folder and returns the full path. #>
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$FileName
    )
    Initialize-LTWeb
    if (-not $FileName) { $FileName = [IO.Path]::GetFileName(([Uri]$Url).LocalPath) }
    $target = Join-Path (Get-LTWorkFolder) $FileName
    Write-LTLog "Descargando $Url"
    Invoke-WebRequest -Uri $Url -OutFile $target -UseBasicParsing -UserAgent $LT.UserAgent -ErrorAction Stop
    $size = [math]::Round((Get-Item $target).Length / 1MB, 1)
    Write-LTLog "Descargado: $target ($size MB)"
    $target
}

function Test-LTSignature {
    <# Logs the Authenticode signer of a downloaded file. Returns $true if the signature is valid. #>
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -notmatch '\.(exe|msi)$') { return $true }
    $sig = Get-AuthenticodeSignature -FilePath $Path
    if ($sig.Status -eq 'Valid') {
        Write-LTLog "Firma digital v$([char]0x00E1)lida: $($sig.SignerCertificate.Subject)" -Level Ok
        return $true
    }
    Write-LTLog "El instalador no tiene una firma digital v$([char]0x00E1)lida ($($sig.Status))." -Level Warn
    return $false
}

function Start-LTInstaller {
    <#
        Runs an .exe or .msi installer elevated and waits for it.
        MSI files get /passive (progress bar, no questions) unless $Arguments is given.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Arguments
    )
    if ($Path -match '\.msi$') {
        $file = 'msiexec.exe'
        if (-not $Arguments) { $Arguments = '/passive /norestart' }
        $Arguments = "/i `"$Path`" $Arguments"
    }
    else {
        $file = $Path
    }
    Write-LTLog "Ejecutando instalador: $([IO.Path]::GetFileName($Path)) $Arguments"
    try {
        $splat = @{ FilePath = $file; Wait = $true; PassThru = $true; ErrorAction = 'Stop' }
        if ($Arguments) { $splat.ArgumentList = $Arguments }
        if (-not (Test-LTAdmin)) { $splat.Verb = 'RunAs' }
        $p = Start-Process @splat
    }
    catch {
        Write-LTLog "No se ha podido ejecutar el instalador: $($_.Exception.Message)" -Level Error
        return $false
    }
    switch ($p.ExitCode) {
        0       { Write-LTLog "Instalaci$([char]0x00F3)n completada." -Level Ok; return $true }
        3010    { Write-LTLog "Instalaci$([char]0x00F3)n completada. Es necesario reiniciar el equipo." -Level Ok; return $true }
        1602    { Write-LTLog "Instalaci$([char]0x00F3)n cancelada por el usuario." -Level Warn; return $false }
        default { Write-LTLog "El instalador ha terminado con c$([char]0x00F3)digo $($p.ExitCode)." -Level Warn; return $false }
    }
}

function Install-LTWinget {
    <# Installs a package with winget. Returns $false if winget is not available or fails. #>
    param([Parameter(Mandatory)][string]$Id)
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-LTLog "winget no est$([char]0x00E1) disponible en este equipo." -Level Warn
        return $false
    }
    Write-LTLog "Instalando $Id con winget..."
    $out = & $winget.Source install --id $Id --exact --silent --accept-source-agreements --accept-package-agreements 2>&1
    $out | Where-Object { "$_".Trim() -and "$_" -notmatch '^[\s\-\\|/]+$' -and "$_" -notmatch "[$([char]0x2580)-$([char]0x259F)]" } |
        Select-Object -Last 6 | ForEach-Object { Write-LTLog "    $_" }
    # 0 = ok, -1978335189 = already installed / no newer version
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) { return $true }
    Write-LTLog "winget ha devuelto el c$([char]0x00F3)digo $LASTEXITCODE." -Level Warn
    return $false
}

function Get-LTInstalledApp {
    <# Searches the Uninstall registry keys (machine + user, 32 and 64 bit) by display name regex. #>
    param([Parameter(Mandatory)][string]$Name)
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName -match $Name } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation |
        Sort-Object DisplayName -Unique
}

function Open-LTUrl {
    param([Parameter(Mandatory)][string]$Url)
    Write-LTLog "Abriendo $Url"
    Start-Process $Url
}

function Invoke-LTItem {
    <# Runs one item from config/tools.json (an action or a link). #>
    param(
        [Parameter(Mandatory)]$Item,
        [int]$Minutes = 5
    )
    if ($Item.url) { Open-LTUrl -Url $Item.url; return }
    $params = @{}
    if ($Item.usesMinutes) { $params.Minutes = $Minutes }
    & $Item.action @params
}

#endregion
