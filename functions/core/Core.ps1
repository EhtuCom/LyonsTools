#region Core helpers ------------------------------------------------------------

function Get-LTString {
    <#
        Returns the text for the current language ($LT.Lang: en, es or ca).
        Accepts either three strings (English, Spanish, Catalan) or one object
        with en/es/ca properties, as used in config/tools.json. Falls back to English.
    #>
    param(
        [Parameter(Position = 0)]$En,
        [Parameter(Position = 1)][string]$Es,
        [Parameter(Position = 2)][string]$Ca
    )
    if ($null -ne $En -and $En -isnot [string]) {
        $value = $En.($LT.Lang)
        if (-not $value) { $value = $En.en }
        return [string]$value
    }
    $value = switch ($LT.Lang) { 'es' { $Es } 'ca' { $Ca } default { $En } }
    if ($value) { $value } else { $En }
}

function Write-LTLog {
    <#
        Writes a line to the console, the GUI log panel (through a thread-safe queue
        drained by the UI timer) and the daily log file.
        Pass the message in English, Spanish and Catalan:  Write-LTLog "Done." "Hecho." "Fet." -Level Ok
        A single (untranslated) message is shown as is in every language.
    #>
    param(
        [Parameter(Position = 0)][AllowEmptyString()][string]$En,
        [Parameter(Position = 1)][string]$Es,
        [Parameter(Position = 2)][string]$Ca,
        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Step')][string]$Level = 'Info'
    )
    $message = Get-LTString $En $Es $Ca
    $tag = switch ($Level) {
        'Ok'    { '[OK]   ' }
        'Warn'  { Get-LTString '[WARN] ' '[AVISO]' "[AVÍS] " }
        'Error' { '[ERROR]' }
        'Step'  { '=====> ' }
        default { '       ' }
    }
    $line = '{0} {1} {2}' -f (Get-Date -Format 'HH:mm:ss'), $tag, $message

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

function Test-LTCanElevate {
    <#
        True if this user can get administrator rights through UAC (already elevated, or a
        member of Administrators running with a filtered token). Standard users - e.g. on a
        Remote Desktop / terminal server - get $false, and admin-only actions are disabled
        for them instead of showing a password prompt they cannot answer.
    #>
    if (Test-LTAdmin) { return $true }
    [bool]((whoami.exe /groups) -match 'S-1-5-32-544')
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
        Write-LTLog "The administrator permission request was cancelled." "Se ha cancelado la solicitud de permisos de administrador." "S'ha cancel·lat la sol·licitud de permisos d'administrador." -Level Warn
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
    Write-LTLog "Downloading $Url" "Descargando $Url" "Descarregant $Url"
    # WebClient streams to disk. Invoke-WebRequest in Windows PowerShell 5.1 buffers the whole file in
    # memory first, which is very slow for big installers (Adobe Reader is 800 MB).
    $wc = New-Object Net.WebClient
    try {
        $wc.Headers['User-Agent'] = $LT.UserAgent
        $wc.DownloadFile($Url, $target)
    }
    finally { $wc.Dispose() }
    if (-not (Test-Path $target) -or (Get-Item $target).Length -eq 0) { throw "empty download: $Url" }
    $size = [math]::Round((Get-Item $target).Length / 1MB, 1)
    Write-LTLog "Downloaded: $target ($size MB)" "Descargado: $target ($size MB)" "Descarregat: $target ($size MB)"
    $target
}

function Test-LTSignature {
    <#
        Checks the Authenticode signature of a downloaded installer. Returns $true if it may be run.
        -ExpectedPublisher: regex the signer's subject must match (protects against a swapped download).
        Windows reports "UnknownError" when only the *timestamp* cannot be verified (e.g. the FNMT
        Configurador is time-stamped by FNMT's own authority, which Windows does not trust). In that case
        the file hash already matched, so the signer's own certificate chain is verified here instead and
        the expected publisher is required.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ExpectedPublisher
    )
    if ($Path -notmatch '\.(exe|msi)$') { return $true }
    $sig = Get-AuthenticodeSignature -FilePath $Path
    $cert = $sig.SignerCertificate
    $signer = if ($cert) { $cert.GetNameInfo('SimpleName', $false) } else { '' }

    if ($ExpectedPublisher -and $cert -and $cert.Subject -notmatch $ExpectedPublisher) {
        Write-LTLog "The installer is signed by '$signer', not by the expected publisher. It will not be run." `
            "El instalador está firmado por '$signer', no por el editor esperado. No se ejecutará." `
            "L'instal·lador està signat per '$signer', no per l'editor esperat. No s'executarà." -Level Error
        return $false
    }
    if ($sig.Status -eq 'Valid') {
        Write-LTLog "Valid digital signature: $signer" "Firma digital válida: $signer" "Signatura digital vàlida: $signer" -Level Ok
        return $true
    }
    if ($sig.Status -eq 'UnknownError' -and $cert -and $ExpectedPublisher) {
        $chain = New-Object Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode = 'Online'
        $chain.ChainPolicy.RevocationFlag = 'ExcludeRoot'
        $ok = $chain.Build($cert)
        if (-not $ok -and ($chain.ChainStatus | Where-Object { $_.Status -match 'Revocation' }) -and -not ($chain.ChainStatus | Where-Object { $_.Status -notmatch 'Revocation' })) {
            # Revocation servers unreachable (offline / filtered network): accept the chain without it.
            $chain.ChainPolicy.RevocationMode = 'NoCheck'
            $ok = $chain.Build($cert)
        }
        if ($ok) {
            Write-LTLog "Digital signature by '$signer' verified (its timestamp could not be checked by Windows)." `
                "Firma digital de '$signer' verificada (Windows no ha podido comprobar su marca de tiempo)." `
                "Signatura digital de '$signer' verificada (Windows no ha pogut comprovar la seva marca de temps)." -Level Ok
            return $true
        }
    }
    $msg = $sig.StatusMessage
    Write-LTLog "The installer does not have a valid digital signature ($($sig.Status): $msg). It will not be run." `
        "El instalador no tiene una firma digital válida ($($sig.Status): $msg). No se ejecutará." `
        "L'instal·lador no té una signatura digital vàlida ($($sig.Status): $msg). No s'executarà." -Level Error
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
    $name = [IO.Path]::GetFileName($Path)
    Write-LTLog "Running installer: $name $Arguments" "Ejecutando instalador: $name $Arguments" "Executant l'instal·lador: $name $Arguments"
    if ($LT.IsRdsHost) {
        # Remote Desktop Session Host: software must be installed in "install mode" so that per-user
        # settings are captured for every user (change user /install ... /execute). Needs admin rights,
        # so the whole installer run goes through one elevated step.
        Write-LTLog "Terminal server detected: installing in install mode for all users." `
            "Servidor de terminales detectado: se instala en modo instalación para todos los usuarios." `
            "Servidor de terminals detectat: s'instal·la en mode instal·lació per a tots els usuaris."
        $argLine = if ($Arguments) { " -ArgumentList '$($Arguments.Replace("'", "''"))'" } else { '' }
        $script = @"
change.exe user /install | Out-Null
try { `$p = Start-Process -FilePath '$file'$argLine -Wait -PassThru } finally { change.exe user /execute | Out-Null }
exit `$p.ExitCode
"@
        $code = Invoke-LTElevated -Script $script
        if ($code -eq -1) { return $false }
    }
    else {
        try {
            $splat = @{ FilePath = $file; Wait = $true; PassThru = $true; ErrorAction = 'Stop' }
            if ($Arguments) { $splat.ArgumentList = $Arguments }
            if (-not (Test-LTAdmin)) { $splat.Verb = 'RunAs' }
            $p = Start-Process @splat
        }
        catch {
            $err = $_.Exception.Message
            Write-LTLog "The installer could not be run: $err" "No se ha podido ejecutar el instalador: $err" "No s'ha pogut executar l'instal·lador: $err" -Level Error
            return $false
        }
        $code = $p.ExitCode
    }
    switch ($code) {
        0       { Write-LTLog "Installation completed." "Instalación completada." "Instal·lació completada." -Level Ok; return $true }
        3010    { Write-LTLog "Installation completed. The computer must be restarted." "Instalación completada. Es necesario reiniciar el equipo." "Instal·lació completada. Cal reiniciar l'equip." -Level Ok; return $true }
        1602    { Write-LTLog "Installation cancelled by the user." "Instalación cancelada por el usuario." "Instal·lació cancel·lada per l'usuari." -Level Warn; return $false }
        default { Write-LTLog "The installer finished with code $code." "El instalador ha terminado con código $code." "L'instal·lador ha acabat amb el codi $code." -Level Warn; return $false }
    }
}

function Install-LTWinget {
    <# Installs a package with winget. Returns $false if winget is not available or fails. #>
    param([Parameter(Mandatory)][string]$Id)
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-LTLog "winget is not available on this computer." "winget no está disponible en este equipo." "winget no està disponible en aquest equip." -Level Warn
        return $false
    }
    Write-LTLog "Installing $Id with winget..." "Instalando $Id con winget..." "Instal·lant $Id amb winget..."
    $out = & $winget.Source install --id $Id --exact --silent --accept-source-agreements --accept-package-agreements 2>&1
    $out | Where-Object { "$_".Trim() -and "$_" -notmatch '^[\s\-\\|/]+$' -and "$_" -notmatch "[$([char]0x2580)-$([char]0x259F)]" } |
        Select-Object -Last 6 | ForEach-Object { Write-LTLog "    $_" }
    # 0 = ok, -1978335189 = already installed / no newer version
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) { return $true }
    $code = $LASTEXITCODE
    Write-LTLog "winget returned code $code." "winget ha devuelto el código $code." "winget ha retornat el codi $code." -Level Warn
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
    Write-LTLog "Opening $Url" "Abriendo $Url" "Obrint $Url"
    Start-Process $Url
}

function Invoke-LTItem {
    <# Runs one item from config/tools.json (an action or a link). #>
    param(
        [Parameter(Mandatory)]$Item,
        [int]$Minutes = 5
    )
    if ($Item.url) { Open-LTUrl -Url $Item.url; return }
    if ($Item.admin -and -not $LT.CanElevate) {
        Write-LTLog "This action requires an administrator. Ask your IT support to run it (on a terminal server it applies to all users)." `
            "Esta acción requiere un administrador. Pide a tu soporte informático que la ejecute (en un servidor de terminales se aplica a todos los usuarios)." `
            "Aquesta acció requereix un administrador. Demana al teu suport informàtic que l'executi (en un servidor de terminals s'aplica a tots els usuaris)." -Level Warn
        return
    }
    $params = @{}
    if ($Item.usesMinutes) { $params.Minutes = $Minutes }
    & $Item.action @params
}

#endregion
