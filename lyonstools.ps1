<#
    Lyons Tools 1.3.5 - utilidades de Windows, Office, Java y firma digital
    https://github.com/EhtuCom/LyonsTools  |  https://ehtu.com

    GENERATED FILE - DO NOT EDIT. Edit the sources and run Compile.ps1.
    Built 2026-10-01 08:49
#>

<#
.SYNOPSIS
    Lyons Tools - Windows, Office, Java and digital signature utilities (ehtu.com)

.PARAMETER Run
    Runs actions without opening the window. Comma-separated IDs (see -List).
    Example: -Run office-crash-protection,java-check

.PARAMETER Minutes
    AutoRecover interval in minutes for the Office actions (1-120, default 5).

.PARAMETER Lang
    Interface language: en (English, default), es (Espa$([char]0x00F1)ol) or ca (Catal$([char]0x00E0)).
    The choice made in the window is remembered per user.

.PARAMETER List
    Lists the IDs of all available actions.

.EXAMPLE
    irm https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1 | iex

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1))) -Run office-crash-protection -Minutes 3 -Lang es
#>
param(
    [string[]]$Run,
    [ValidateRange(1, 120)][int]$Minutes = 5,
    [ValidateSet('', 'en', 'es', 'ca')][string]$Lang = '',
    [switch]$List
)

$LT = [hashtable]::Synchronized(@{})
$LT.Version = '1.3.5'
$LT.Repo = 'EhtuCom/LyonsTools'
$LT.SourceUrl = 'https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1'
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


# ---- functions\abogacia\Abogacia.ps1 ----
#region Abogac$([char]0x00ED)a ----------------------------------------------------------------

function Install-LTAcaMiddleware {
    <#
        Bit4id middleware for the ACA (Autoridad de Certificaci$([char]0x00F3)n de la Abogac$([char]0x00ED)a) card,
        from https://www.abogacia.es/site/acaplus/guias-y-software-de-instalacion/
        The "Mini Lector ACA" driver offered on that page is NOT installed: its code-signing
        certificate has been revoked, and current Windows detects the reader by itself.
    #>
    try { $file = Save-LTFile -Url 'https://www.abogacia.es/repositorio/acaplusdescarga/Bit4id_Middleware.exe' -FileName 'Bit4id_ACA_Middleware.exe' }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "Download error: $err" "Error al descargar: $err" "Error en descarregar: $err" -Level Error
        Open-LTUrl 'https://www.abogacia.es/site/acaplus/guias-y-software-de-instalacion/'
        return
    }
    if (-not (Test-LTSignature -Path $file)) { return }
    Write-LTLog "Follow the installer steps. Then connect the reader with the ACA card inserted." `
        "Sigue los pasos del instalador. Despu$([char]0x00E9)s, conecta el lector con la tarjeta ACA insertada." `
        "Segueix els passos de l'instal$([char]0x00B7)lador. Despr$([char]0x00E9)s, connecta el lector amb la targeta ACA inserida."
    if (Start-LTInstaller -Path $file) {
        Write-LTLog "If Windows does not recognise the reader, see the ACA guide: https://www.abogacia.es/site/acaplus/tarjeta-configura-dispositivos/" `
            "Si Windows no reconoce el lector, consulta la gu$([char]0x00ED)a de ACA: https://www.abogacia.es/site/acaplus/tarjeta-configura-dispositivos/" `
            "Si Windows no reconeix el lector, consulta la guia d'ACA: https://www.abogacia.es/site/acaplus/tarjeta-configura-dispositivos/"
    }
}

function Install-LTAcaRootCertificates {
    <# ACA root and subordinate CAs. The root is pinned to the SHA1 published by the Consejo General de la Abogac$([char]0x00ED)a. #>
    $trustedRoots = @{ '3A09ECCF9D8770C3D5515806A9230EC9B32659BE' = 'ACA ROOT 2' }
    $folder = New-LTCleanFolder 'aca-certs'
    Initialize-LTWeb
    $files = foreach ($name in 'ACA_ROOTCA.CER', 'ACA_SUB1CA.cer', 'ACA_SUB2CA.cer') {
        $file = Join-Path $folder $name
        try {
            Invoke-WebRequest -Uri "https://www.abogacia.es/repositorio/acaplusdescarga/$name" -OutFile $file -UseBasicParsing -UserAgent $LT.UserAgent -ErrorAction Stop
            $file
        }
        catch { Write-LTLog "Could not download $name" "No se ha podido descargar $name" "No s'ha pogut descarregar $name" -Level Warn }
    }
    Install-LTCertificateFiles -Files @($files) -TrustedRoots $trustedRoots -Issuer 'ACA'
}

#endregion

# ---- functions\core\Core.ps1 ----
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
        'Warn'  { Get-LTString '[WARN] ' '[AVISO]' "[AV$([char]0x00CD)S] " }
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
        Write-LTLog "The administrator permission request was cancelled." "Se ha cancelado la solicitud de permisos de administrador." "S'ha cancel$([char]0x00B7)lat la sol$([char]0x00B7)licitud de permisos d'administrador." -Level Warn
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
    Invoke-WebRequest -Uri $Url -OutFile $target -UseBasicParsing -UserAgent $LT.UserAgent -ErrorAction Stop
    $size = [math]::Round((Get-Item $target).Length / 1MB, 1)
    Write-LTLog "Downloaded: $target ($size MB)" "Descargado: $target ($size MB)" "Descarregat: $target ($size MB)"
    $target
}

function Test-LTSignature {
    <# Logs the Authenticode signer of a downloaded file. Returns $true if the signature is valid. #>
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -notmatch '\.(exe|msi)$') { return $true }
    $sig = Get-AuthenticodeSignature -FilePath $Path
    $signer = $sig.SignerCertificate.Subject
    if ($sig.Status -eq 'Valid') {
        Write-LTLog "Valid digital signature: $signer" "Firma digital v$([char]0x00E1)lida: $signer" "Signatura digital v$([char]0x00E0)lida: $signer" -Level Ok
        return $true
    }
    Write-LTLog "The installer does not have a valid digital signature ($($sig.Status))." `
        "El instalador no tiene una firma digital v$([char]0x00E1)lida ($($sig.Status))." `
        "L'instal$([char]0x00B7)lador no t$([char]0x00E9) una signatura digital v$([char]0x00E0)lida ($($sig.Status))." -Level Warn
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
    Write-LTLog "Running installer: $name $Arguments" "Ejecutando instalador: $name $Arguments" "Executant l'instal$([char]0x00B7)lador: $name $Arguments"
    try {
        $splat = @{ FilePath = $file; Wait = $true; PassThru = $true; ErrorAction = 'Stop' }
        if ($Arguments) { $splat.ArgumentList = $Arguments }
        if (-not (Test-LTAdmin)) { $splat.Verb = 'RunAs' }
        $p = Start-Process @splat
    }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "The installer could not be run: $err" "No se ha podido ejecutar el instalador: $err" "No s'ha pogut executar l'instal$([char]0x00B7)lador: $err" -Level Error
        return $false
    }
    $code = $p.ExitCode
    switch ($code) {
        0       { Write-LTLog "Installation completed." "Instalaci$([char]0x00F3)n completada." "Instal$([char]0x00B7)laci$([char]0x00F3) completada." -Level Ok; return $true }
        3010    { Write-LTLog "Installation completed. The computer must be restarted." "Instalaci$([char]0x00F3)n completada. Es necesario reiniciar el equipo." "Instal$([char]0x00B7)laci$([char]0x00F3) completada. Cal reiniciar l'equip." -Level Ok; return $true }
        1602    { Write-LTLog "Installation cancelled by the user." "Instalaci$([char]0x00F3)n cancelada por el usuario." "Instal$([char]0x00B7)laci$([char]0x00F3) cancel$([char]0x00B7)lada per l'usuari." -Level Warn; return $false }
        default { Write-LTLog "The installer finished with code $code." "El instalador ha terminado con c$([char]0x00F3)digo $code." "L'instal$([char]0x00B7)lador ha acabat amb el codi $code." -Level Warn; return $false }
    }
}

function Install-LTWinget {
    <# Installs a package with winget. Returns $false if winget is not available or fails. #>
    param([Parameter(Mandatory)][string]$Id)
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-LTLog "winget is not available on this computer." "winget no est$([char]0x00E1) disponible en este equipo." "winget no est$([char]0x00E0) disponible en aquest equip." -Level Warn
        return $false
    }
    Write-LTLog "Installing $Id with winget..." "Instalando $Id con winget..." "Instal$([char]0x00B7)lant $Id amb winget..."
    $out = & $winget.Source install --id $Id --exact --silent --accept-source-agreements --accept-package-agreements 2>&1
    $out | Where-Object { "$_".Trim() -and "$_" -notmatch '^[\s\-\\|/]+$' -and "$_" -notmatch "[$([char]0x2580)-$([char]0x259F)]" } |
        Select-Object -Last 6 | ForEach-Object { Write-LTLog "    $_" }
    # 0 = ok, -1978335189 = already installed / no newer version
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) { return $true }
    $code = $LASTEXITCODE
    Write-LTLog "winget returned code $code." "winget ha devuelto el c$([char]0x00F3)digo $code." "winget ha retornat el codi $code." -Level Warn
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
            "Esta acci$([char]0x00F3)n requiere un administrador. Pide a tu soporte inform$([char]0x00E1)tico que la ejecute (en un servidor de terminales se aplica a todos los usuarios)." `
            "Aquesta acci$([char]0x00F3) requereix un administrador. Demana al teu suport inform$([char]0x00E0)tic que l'executi (en un servidor de terminals s'aplica a tots els usuaris)." -Level Warn
        return
    }
    $params = @{}
    if ($Item.usesMinutes) { $params.Minutes = $Minutes }
    & $Item.action @params
}

#endregion

# ---- functions\firma\Firma.ps1 ----
#region Firma digital ------------------------------------------------------------

function Install-LTFnmtConfigurator {
    $page = 'https://www.sede.fnmt.gob.es/descargas/descarga-software'
    $url = $null
    try { $url = Find-LTWebLink -Url $page -Pattern 'descargas\.cert\.fnmt\.es/Windows/Configurador_FNMT_[\d.]+_64bits\.exe' }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "The FNMT website could not be read: $err" "No se ha podido consultar la web de la FNMT: $err" "No s'ha pogut consultar el web de la FNMT: $err" -Level Warn
    }
    if (-not $url) {
        Write-LTLog "Download link not found on the FNMT website. Opening the downloads page." "No se ha encontrado el enlace en la web de la FNMT. Abriendo la p$([char]0x00E1)gina de descargas." "No s'ha trobat l'enlla$([char]0x00E7) al web de la FNMT. Obrint la p$([char]0x00E0)gina de desc$([char]0x00E0)rregues." -Level Warn
        Open-LTUrl $page
        return
    }
    try { $file = Save-LTFile -Url $url }
    catch { $err = $_.Exception.Message; Write-LTLog "Download error: $err" "Error al descargar: $err" "Error en descarregar: $err" -Level Error; return }
    if (-not (Test-LTSignature -Path $file)) { return }
    Write-LTLog "Follow the steps of the FNMT Configurator installer." "Sigue los pasos del instalador del Configurador FNMT." "Segueix els passos de l'instal$([char]0x00B7)lador del Configurador FNMT."
    [void](Start-LTInstaller -Path $file)
}

function Install-LTCertificateFiles {
    <#
        Installs CA certificate files. Self-signed roots go to the Root store ONLY if their
        thumbprint is in $TrustedRoots; intermediate CAs go to the CA store. Expired ones are skipped.
        Administrators: LocalMachine stores (all users, one UAC prompt).
        Standard users (e.g. terminal server): CurrentUser stores; Windows asks to confirm each root.
    #>
    param(
        [Parameter(Mandatory)][string[]]$Files,
        [Parameter(Mandatory)][hashtable]$TrustedRoots,
        [Parameter(Mandatory)][string]$Issuer
    )
    $seen = @{}
    $plan = foreach ($file in $Files) {
        $fileName = [IO.Path]::GetFileName($file)
        try { $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($file) }
        catch {
            Write-LTLog "Skipped: $fileName is not a valid certificate (the website may have blocked the download)." `
                "Omitido: $fileName no es un certificado v$([char]0x00E1)lido (la web puede haber bloqueado la descarga)." `
                "Om$([char]0x00E8)s: $fileName no $([char]0x00E9)s un certificat v$([char]0x00E0)lid (el web pot haver bloquejat la desc$([char]0x00E0)rrega)." -Level Warn
            continue
        }
        if ($seen.ContainsKey($cert.Thumbprint)) { continue }
        $seen[$cert.Thumbprint] = $true

        $name = $cert.GetNameInfo('SimpleName', $false)
        if ($cert.NotAfter -lt (Get-Date)) { Write-LTLog "Skipped (expired): $name" "Omitido (caducado): $name" "Om$([char]0x00E8)s (caducat): $name"; continue }
        if ($cert.Subject -eq $cert.Issuer) {
            if (-not $TrustedRoots.ContainsKey($cert.Thumbprint)) {
                $tp = $cert.Thumbprint
                Write-LTLog "Skipped: unknown root '$name' ($tp). It does not match the official roots ($Issuer)." `
                    "Omitido: ra$([char]0x00ED)z desconocida '$name' ($tp). No coincide con las ra$([char]0x00ED)ces oficiales ($Issuer)." `
                    "Om$([char]0x00E8)s: arrel desconeguda '$name' ($tp). No coincideix amb les arrels oficials ($Issuer)." -Level Warn
                continue
            }
            [pscustomobject]@{ File = $file; Store = 'Root'; Name = $name }
        }
        else {
            [pscustomobject]@{ File = $file; Store = 'CA'; Name = $name }
        }
    }
    $plan = @($plan)
    if (-not $plan.Count) { Write-LTLog "There are no certificates to install." "No hay certificados para instalar." "No hi ha certificats per instal$([char]0x00B7)lar." -Level Error; return }
    $count = $plan.Count

    if ($LT.CanElevate) {
        $script = ($plan | ForEach-Object {
                "Import-Certificate -FilePath '$($_.File)' -CertStoreLocation 'Cert:\LocalMachine\$($_.Store)' | Out-Null"
            }) -join "`n"
        Write-LTLog "Installing $count certificates ($Issuer) for all users (administrator permission will be requested)..." `
            "Instalando $count certificados ($Issuer) para todos los usuarios (se pedir$([char]0x00E1) permiso de administrador)..." `
            "Instal$([char]0x00B7)lant $count certificats ($Issuer) per a tots els usuaris (es demanar$([char]0x00E0) perm$([char]0x00ED)s d'administrador)..."
        if ((Invoke-LTElevated -Script $script) -ne 0) {
            Write-LTLog "The certificates could not be installed." "No se han podido instalar los certificados." "No s'han pogut instal$([char]0x00B7)lar els certificats." -Level Error
            return
        }
    }
    else {
        Write-LTLog "Installing $count certificates ($Issuer) for your user. Windows will ask you to confirm each root certificate: answer 'Yes'." `
            "Instalando $count certificados ($Issuer) para tu usuario. Windows pedir$([char]0x00E1) confirmar cada certificado ra$([char]0x00ED)z: responde 'S$([char]0x00ED)'." `
            "Instal$([char]0x00B7)lant $count certificats ($Issuer) per al teu usuari. Windows demanar$([char]0x00E0) confirmar cada certificat arrel: respon 'S$([char]0x00ED)'."
        foreach ($c in $plan) {
            try { Import-Certificate -FilePath $c.File -CertStoreLocation "Cert:\CurrentUser\$($c.Store)" -ErrorAction Stop | Out-Null }
            catch {
                $n = $c.Name
                Write-LTLog "Not installed: $n" "No instalado: $n" "No instal$([char]0x00B7)lat: $n" -Level Warn
                $c.Store = $null
            }
        }
    }
    foreach ($c in $plan | Where-Object Store) {
        $where = if ($c.Store -eq 'Root') {
            Get-LTString 'Trusted Root Certification Authorities' "Entidades de certificaci$([char]0x00F3)n ra$([char]0x00ED)z de confianza" "Entitats de certificaci$([char]0x00F3) arrel de confian$([char]0x00E7)a"
        }
        else {
            Get-LTString 'Intermediate Certification Authorities' "Entidades de certificaci$([char]0x00F3)n intermedias" "Entitats de certificaci$([char]0x00F3) interm$([char]0x00E8)dies"
        }
        $n = $c.Name
        Write-LTLog "Installed: $n  ->  $where" "Instalado: $n  ->  $where" "Instal$([char]0x00B7)lat: $n  ->  $where" -Level Ok
    }
    Write-LTLog "If you use Firefox, enable 'security.enterprise_roots.enabled' or import the certificates in Firefox." `
        "Si usas Firefox, activa 'security.enterprise_roots.enabled' o importa los certificados en Firefox." `
        "Si fas servir Firefox, activa 'security.enterprise_roots.enabled' o importa els certificats al Firefox."
}

function New-LTCleanFolder([string]$Name) {
    $folder = Join-Path (Get-LTWorkFolder) $Name
    if (Test-Path $folder) { Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory $folder -Force | Out-Null
    $folder
}

function Install-LTFnmtRootCertificates {
    <# FNMT CA certificates, scraped from the FNMT website (with a known list as fallback). #>
    $trustedRoots = @{
        'EC503507B215C4956219E2A89A5B42992C4C2C20' = 'AC RAIZ FNMT-RCM'
        'A4D6B770E765A9BF17ECD7B5E03B852D612FA71D' = 'AC RAIZ FNMT-RCM G2'
        '62FFD99EC0650D03CE7593D2ED3F2D32C9E3E54A' = 'AC RAIZ FNMT-RCM SERVIDORES SEGUROS'
        '1987948DAB7D62009E2D6BBED883DC3AF56799E8' = 'AC RAIZ FNMT-RCM SERVIDORES SEGUROS G2R'
        'E90D1A8F04E0D4A131BF4E7EE2BC57AE7A8A93E4' = 'AC RAIZ FNMT-RCM TSA'
    }
    $base = 'https://www.sede.fnmt.gob.es'
    $page = "$base/descargas/certificados-raiz-de-la-fnmt"
    $known = 'AC_Raiz_FNMT-RCM_SHA256.cer', 'AC_Raiz_FNMT-RCM_G2.cer', 'AC_Raiz_FNMT-RCM-SS.cer', 'AC_FNMT_Usuarios.cer',
    'AC_Usuarios_G2.cer', 'AC_Representacion.cer', 'AC_Representacion_G2.cer', 'AC_Componentes_Informaticos_SHA256.cer',
    'AC_Sector_Publico.cer', 'AC_Sector_Publico_G2.cer' | ForEach-Object { "/documents/10445900/10526749/$_" }

    $paths = $null
    try {
        $html = (Get-LTWebPage -Url $page).Content
        $paths = @([regex]::Matches($html, '/documents/10445900/10526749/[^"''\s<>?]+\.(cer|crt)') | ForEach-Object Value | Sort-Object -Unique)
    }
    catch { Write-LTLog "The FNMT page could not be read; using the known list." "No se ha podido leer la p$([char]0x00E1)gina de la FNMT, se usa la lista conocida." "No s'ha pogut llegir la p$([char]0x00E0)gina de la FNMT; es fa servir la llista coneguda." -Level Warn }
    if (-not $paths) { $paths = $known }

    $folder = New-LTCleanFolder 'fnmt-certs'
    Initialize-LTWeb
    $files = foreach ($p in $paths) {
        $file = Join-Path $folder ([IO.Path]::GetFileName($p))
        try {
            Invoke-WebRequest -Uri "$base$p" -OutFile $file -UseBasicParsing -UserAgent $LT.UserAgent -ErrorAction Stop
            $file
        }
        catch { Write-LTLog "Could not download $p" "No se ha podido descargar $p" "No s'ha pogut descarregar $p" -Level Warn }
    }
    Install-LTCertificateFiles -Files @($files) -TrustedRoots $trustedRoots -Issuer 'FNMT'
}

function Install-LTAocRootCertificates {
    <#
        Consorci AOC (CATCert) hierarchy: needed for idCAT Certificat, T-CAT and the
        Generalitat / town hall websites. Source:
        https://suport.aoc.cat/ca-es/article/?servei=tcat&id=KA-07204_claus-publiques-del-consorci-aoc-descarrega-i-instal-lacio
    #>
    $trustedRoots = @{
        '67597EADBA82D7C7FBA591B0BB9C934220052DB7' = 'CA CONSORCI AOC (G3) ROOT-A'
        '28903A635B5280FAE6774C0B6DA7D6BAA64AF2E8' = 'EC-ACC'
    }
    $bundles = 'https://epscd.aoc.cat/assets/documents/jerarquia/arxiucp_2026.zip',
    'https://epscd.aoc.cat/assets/documents/jerarquia/arxiucp_2025.zip'
    $single = 'https://epscd.aoc.cat/descarrega/caroot-a.crt', 'https://epscd.aoc.cat/descarrega/casub-a1.crt',
    'https://epscd.aoc.cat/descarrega/casub-a2.crt', 'https://epscd.aoc.cat/assets/documents/jerarquia/clauEntitatCertificadoraCatcert.zip',
    'https://epscd.aoc.cat/assets/documents/jerarquia/ec_ciutadania.zip', 'https://epscd.aoc.cat/assets/documents/jerarquia/ec_sectorpublic.zip'

    $folder = New-LTCleanFolder 'aoc-certs'
    Initialize-LTWeb
    $got = $false
    foreach ($url in $bundles) {
        try {
            $zip = Join-Path $folder 'bundle.zip'
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -UserAgent $LT.UserAgent -ErrorAction Stop
            Expand-Archive -Path $zip -DestinationPath $folder -Force
            Write-LTLog "Downloaded the Consorci AOC public key bundle: $url" "Descargado el paquete de claves p$([char]0x00FA)blicas del Consorci AOC: $url" "Descarregat el paquet de claus p$([char]0x00FA)bliques del Consorci AOC: $url"
            $got = $true
            break
        }
        catch { }
    }
    if (-not $got) {
        foreach ($url in $single) {
            try {
                $file = Join-Path $folder ([IO.Path]::GetFileName($url))
                Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing -UserAgent $LT.UserAgent -ErrorAction Stop
                if ($file -match '\.zip$') { Expand-Archive -Path $file -DestinationPath $folder -Force }
            }
            catch { Write-LTLog "Could not download $url" "No se ha podido descargar $url" "No s'ha pogut descarregar $url" -Level Warn }
        }
    }
    $files = @(Get-ChildItem -Path $folder -Recurse -File | Where-Object Extension -in '.crt', '.cer', '.der' | ForEach-Object FullName)
    if (-not $files.Count) {
        Write-LTLog "The Consorci AOC certificates could not be downloaded." "No se han podido descargar los certificados del Consorci AOC." "No s'han pogut descarregar els certificats del Consorci AOC." -Level Error
        Open-LTUrl 'https://suport.aoc.cat/ca-es/article/?servei=tcat&id=KA-07204_claus-publiques-del-consorci-aoc-descarrega-i-instal-lacio'
        return
    }
    Install-LTCertificateFiles -Files $files -TrustedRoots $trustedRoots -Issuer 'Consorci AOC'
}

function Install-LTTcatMiddleware {
    <#
        Bit4id "PKI Manager" middleware for T-CAT smart cards issued after 13/04/2023
        (https://suport.aoc.cat/ca-es/article/?servei=tcat&id=KA-07251).
        The old SafeSign software must be removed first; older cards were revoked in October 2023.
    #>
    $old = @(Get-LTInstalledApp -Name 'SafeSign')
    if ($old.Count) {
        $n = $old[0].DisplayName
        Write-LTLog "$n is installed. The Consorci AOC says to uninstall it first (Settings > Apps)." `
            "Est$([char]0x00E1) instalado $n. El Consorci AOC indica desinstalarlo antes (Configuraci$([char]0x00F3)n > Aplicaciones)." `
            "Hi ha instal$([char]0x00B7)lat $n. El Consorci AOC indica desinstal$([char]0x00B7)lar-lo abans (Configuraci$([char]0x00F3) > Aplicacions)." -Level Warn
    }
    try { $file = Save-LTFile -Url 'https://cdn.bit4id.com/es/AOC/middleware/Bit4id_AOC_Middleware.exe' }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "Download error: $err" "Error al descargar: $err" "Error en descarregar: $err" -Level Error
        Open-LTUrl 'https://suport.aoc.cat/ca-es/article/?servei=tcat&id=KA-07251_instal-lacio-del-programari-per-a-l-us-de-la-t-cat-en-targeta'
        return
    }
    if (-not (Test-LTSignature -Path $file)) { return }
    Write-LTLog "Follow the installer steps. You will need a card reader connected to use the T-CAT." `
        "Sigue los pasos del instalador. Necesitar$([char]0x00E1)s un lector de tarjetas conectado para usar la T-CAT." `
        "Segueix els passos de l'instal$([char]0x00B7)lador. Necessitar$([char]0x00E0)s un lector de targetes connectat per fer servir la T-CAT."
    if (Start-LTInstaller -Path $file) {
        Write-LTLog "Manual: https://cdn.bit4id.com/es/AOC/manuals/Windows/Windows.html"
    }
}

function Get-LTPersonalCertificates {
    $certs = @(Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue | Where-Object HasPrivateKey | Sort-Object NotAfter)
    if (-not $certs.Count) {
        Write-LTLog "There are no signing certificates (with a private key) for this Windows user." `
            "No hay ning$([char]0x00FA)n certificado para firmar (con clave privada) en este usuario de Windows." `
            "No hi ha cap certificat per signar (amb clau privada) en aquest usuari de Windows." -Level Warn
        return
    }
    $now = Get-Date
    foreach ($c in $certs) {
        $days = [int][math]::Floor(($c.NotAfter - $now).TotalDays)
        $name = $c.GetNameInfo('SimpleName', $false)
        $issuer = $c.GetNameInfo('SimpleName', $true)
        $date = $c.NotAfter.ToString('dd/MM/yyyy')
        $base = Get-LTString "$name`n           Issuer: $issuer | expires $date" "$name`n           Emisor: $issuer | caduca el $date" "$name`n           Emissor: $issuer | caduca el $date"
        $ago = -$days
        if ($days -lt 0) { Write-LTLog "$base (EXPIRED $ago days ago)" "$base (CADUCADO hace $ago d$([char]0x00ED)as)" "$base (CADUCAT fa $ago dies)" -Level Error }
        elseif ($days -le 60) { Write-LTLog "$base (expires in $days days: renew it)" "$base (caduca en $days d$([char]0x00ED)as: renu$([char]0x00E9)valo)" "$base (caduca d'aqu$([char]0x00ED) a $days dies: renova'l)" -Level Warn }
        else { Write-LTLog "$base ($days days)" "$base ($days d$([char]0x00ED)as)" "$base ($days dies)" -Level Ok }
    }
    if ($certs | Where-Object { $_.NotAfter -lt $now }) {
        Write-LTLog "Expired certificates can be deleted from the certificate manager." "Los certificados caducados se pueden eliminar desde el administrador de certificados." "Els certificats caducats es poden eliminar des de l'administrador de certificats."
    }
}

function Open-LTCertManager {
    Start-Process certmgr.msc
    Write-LTLog "Certificate manager opened. Your certificates are in Personal > Certificates." `
        "Abierto el administrador de certificados. Tus certificados est$([char]0x00E1)n en Personal > Certificados." `
        "S'ha obert l'administrador de certificats. Els teus certificats s$([char]0x00F3)n a Personal > Certificats." -Level Ok
}

function Install-LTAutofirma {
    $page = 'https://firmaelectronica.gob.es/descargas'
    $fallback = 'https://firmaelectronica.gob.es/content/dam/firmaelectronica/descargas-software/autofirma19/Autofirma64.zip'
    $url = $null
    try { $url = Find-LTWebLink -Url $page -Pattern '/descargas-software/autofirma\d+/Autofirma64\.zip' }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "firmaelectronica.gob.es could not be read: $err" "No se ha podido consultar firmaelectronica.gob.es: $err" "No s'ha pogut consultar firmaelectronica.gob.es: $err" -Level Warn
    }
    if (-not $url) { $url = $fallback }

    $installed = Get-LTInstalledApp -Name '^Autofirma' | Select-Object -First 1
    if ($installed) {
        $v = $installed.DisplayVersion
        Write-LTLog "Autofirma is already installed: version $v. It will be reinstalled with the latest version." `
            "Autofirma ya est$([char]0x00E1) instalado: versi$([char]0x00F3)n $v. Se reinstalar$([char]0x00E1) con la $([char]0x00FA)ltima versi$([char]0x00F3)n." `
            "Autofirma ja est$([char]0x00E0) instal$([char]0x00B7)lat: versi$([char]0x00F3) $v. Es reinstal$([char]0x00B7)lar$([char]0x00E0) amb l'$([char]0x00FA)ltima versi$([char]0x00F3)."
    }

    try { $zip = Save-LTFile -Url $url -FileName 'Autofirma64.zip' }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "Autofirma download error: $err" "Error al descargar Autofirma: $err" "Error en descarregar Autofirma: $err" -Level Error
        Open-LTUrl $page
        return
    }

    $dir = New-LTCleanFolder 'Autofirma'
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    $exe = Get-ChildItem -Path $dir -Filter '*.exe' -Recurse | Select-Object -First 1
    if (-not $exe) { Write-LTLog "The Autofirma ZIP does not contain an installer." "El ZIP de Autofirma no contiene ning$([char]0x00FA)n instalador." "El ZIP d'Autofirma no cont$([char]0x00E9) cap instal$([char]0x00B7)lador." -Level Error; return }
    if (-not (Test-LTSignature -Path $exe.FullName)) { return }

    # Silent mode shows a blocking dialog if the same version is already installed, so only use /S on clean machines.
    $arguments = if ($installed) { $null } else { '/S' }
    if (Start-LTInstaller -Path $exe.FullName -Arguments $arguments) {
        Write-LTLog "Autofirma installed. Restart the browser before signing." "Autofirma instalado. Reinicia el navegador antes de firmar." "Autofirma instal$([char]0x00B7)lat. Reinicia el navegador abans de signar." -Level Ok
    }
}

function Install-LTSignador {
    <#
        Native app of the Consorci AOC "Signador".
        Administrators: MSI for all users (silent); its local certificate must then be added to the
        trusted roots (https://consorciaoc.github.io/signador/guiaUsuaris/nativaDesatesa/).
        Standard users (terminal server): the per-user EXE installer, which needs no admin rights.
    #>
    $lang = if ($LT.Lang -in 'es', 'ca') { $LT.Lang } else { 'en' }

    if (-not $LT.CanElevate) {
        try { $exe = Save-LTFile -Url 'https://signador.aoc.cat/signador/getNativa?os=windows&arch=64' -FileName 'AppNativaSignador-x64.exe' }
        catch {
            $err = $_.Exception.Message
            Write-LTLog "Signador download error: $err" "Error al descargar el Signador: $err" "Error en descarregar el Signador: $err" -Level Error
            Open-LTUrl 'https://signador.aoc.cat/signador/installNativa'
            return
        }
        if (-not (Test-LTSignature -Path $exe)) { return }
        Write-LTLog "Installing the Signador for your user only. Follow the installer steps." `
            "Instalando el Signador solo para tu usuario. Sigue los pasos del instalador." `
            "Instal$([char]0x00B7)lant el Signador nom$([char]0x00E9)s per al teu usuari. Segueix els passos de l'instal$([char]0x00B7)lador."
        $p = Start-Process -FilePath $exe -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            $code = $p.ExitCode
            Write-LTLog "The installer finished with code $code." "El instalador ha terminado con c$([char]0x00F3)digo $code." "L'instal$([char]0x00B7)lador ha acabat amb el codi $code." -Level Warn
            return
        }
        $crt = Get-ChildItem -Path $env:LOCALAPPDATA, $env:APPDATA, $env:USERPROFILE -Filter root.crt -Recurse -Depth 6 -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'Signador|AOC' -and $_.FullName -match 'lib\\certificate' } | Select-Object -First 1
        if ($crt) {
            $thumb = ([Security.Cryptography.X509Certificates.X509Certificate2]::new($crt.FullName)).Thumbprint
            if (-not (Test-Path "Cert:\CurrentUser\Root\$thumb")) {
                Write-LTLog "Windows will ask to trust the Signador local certificate: answer 'Yes'." "Windows pedir$([char]0x00E1) confiar en el certificado local del Signador: responde 'S$([char]0x00ED)'." "Windows demanar$([char]0x00E0) confiar en el certificat local del Signador: respon 'S$([char]0x00ED)'."
                try { Import-Certificate -FilePath $crt.FullName -CertStoreLocation Cert:\CurrentUser\Root -ErrorAction Stop | Out-Null } catch { }
            }
        }
        Write-LTLog "Signador installed. Restart the browser before signing." "Signador instalado. Reinicia el navegador antes de firmar." "Signador instal$([char]0x00B7)lat. Reinicia el navegador abans de signar." -Level Ok
        return
    }

    try { $msi = Save-LTFile -Url 'https://signador.aoc.cat/signador/getNativa?os=windows&arch=64&msi' -FileName 'AppNativaSignador-x64.msi' }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "Signador download error: $err" "Error al descargar el Signador: $err" "Error en descarregar el Signador: $err" -Level Error
        Open-LTUrl 'https://signador.aoc.cat/signador/installNativa'
        return
    }
    if (-not (Test-LTSignature -Path $msi)) { return }

    $log = Join-Path (Get-LTWorkFolder) 'signador-install.log'
    $script = @"
`$p = Start-Process msiexec.exe -ArgumentList '/i "$msi" /passive /norestart sys.languageId=$lang /Lp "$log"' -Wait -PassThru
if (`$p.ExitCode -notin 0, 3010) { exit `$p.ExitCode }
`$crt = Get-ChildItem -Path "`$env:ProgramFiles", "`${env:ProgramFiles(x86)}" -Filter root.crt -Recurse -Depth 5 -ErrorAction SilentlyContinue |
    Where-Object { `$_.FullName -match 'Signador|AOC' -and `$_.FullName -match 'lib\\certificate' } | Select-Object -First 1
if (`$crt) { Import-Certificate -FilePath `$crt.FullName -CertStoreLocation Cert:\LocalMachine\Root | Out-Null }
"@
    Write-LTLog "Installing the Signador native app for all users (administrator permission will be requested)..." `
        "Instalando la aplicaci$([char]0x00F3)n nativa del Signador para todos los usuarios (se pedir$([char]0x00E1) permiso de administrador)..." `
        "Instal$([char]0x00B7)lant l'aplicaci$([char]0x00F3) nativa del Signador per a tots els usuaris (es demanar$([char]0x00E0) perm$([char]0x00ED)s d'administrador)..."
    $result = Invoke-LTElevated -Script $script
    if ($result -ne 0) {
        Write-LTLog "The installation did not complete (code $result). Log: $log" "La instalaci$([char]0x00F3)n no se ha completado (c$([char]0x00F3)digo $result). Registro: $log" "La instal$([char]0x00B7)laci$([char]0x00F3) no s'ha completat (codi $result). Registre: $log" -Level Error
        return
    }
    $app = Get-LTInstalledApp -Name 'Signador' | Select-Object -First 1
    $detail = if ($app) { ": $($app.DisplayName) $($app.DisplayVersion)" } else { '' }
    Write-LTLog "Signador installed$detail." "Signador instalado$detail." "Signador instal$([char]0x00B7)lat$detail." -Level Ok
    Write-LTLog "Restart the browser before signing in Generalitat procedures." "Reinicia el navegador antes de firmar en tr$([char]0x00E1)mites de la Generalitat." "Reinicia el navegador abans de signar en tr$([char]0x00E0)mits de la Generalitat."
}

#endregion

# ---- functions\java\Java.ps1 ----
#region Java ------------------------------------------------------------------

function Get-LTJavaInfo {
    Write-LTLog "Installed Java versions" "Versiones de Java instaladas" "Versions de Java instal$([char]0x00B7)lades"

    $java = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($java) {
        $path = $java.Source
        Write-LTLog "Default Java (PATH): $path" "Java por defecto (PATH): $path" "Java per defecte (PATH): $path"
        $out = & cmd.exe /c "`"$path`" -version 2>&1"
        $out | ForEach-Object { Write-LTLog "    $_" }
    }
    else {
        Write-LTLog "There is no Java in the PATH (the 'java' command does not exist)." `
            "No hay ning$([char]0x00FA)n Java en el PATH (el comando 'java' no existe)." `
            "No hi ha cap Java al PATH (l'ordre 'java' no existeix)." -Level Warn
    }

    $apps = @(Get-LTInstalledApp -Name '\bJava\b|\bJRE\b|\bJDK\b|Temurin|OpenJDK|Zulu|Corretto')
    if ($apps.Count) {
        Write-LTLog "Installed Java programs:" "Programas Java instalados:" "Programes Java instal$([char]0x00B7)lats:"
        foreach ($a in $apps) { Write-LTLog ("    {0}  [{1}]" -f $a.DisplayName, $a.DisplayVersion) }
    }
    else {
        Write-LTLog "No Java found in Installed apps." "No se ha encontrado ning$([char]0x00FA)n Java instalado en Programas y caracter$([char]0x00ED)sticas." "No s'ha trobat cap Java instal$([char]0x00B7)lat a Programes i caracter$([char]0x00ED)stiques."
    }

    foreach ($key in 'HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment', 'HKLM:\SOFTWARE\WOW6432Node\JavaSoft\Java Runtime Environment') {
        $cur = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).CurrentVersion
        if ($cur) {
            $bits = if ($key -match 'WOW6432') { '32' } else { '64' }
            Write-LTLog "Registered Oracle Java ($bits-bit): version $cur" "Java de Oracle registrado ($bits bits): versi$([char]0x00F3)n $cur" "Java d'Oracle registrat ($bits bits): versi$([char]0x00F3) $cur"
        }
    }

    try {
        $lts = (Invoke-RestMethod -Uri 'https://api.adoptium.net/v3/info/available_releases' -UseBasicParsing -ErrorAction Stop).most_recent_lts
        Write-LTLog "Latest Java LTS available: $lts (Temurin). Java 8 is still the java.com version." `
            "$([char]0x00DA)ltima versi$([char]0x00F3)n LTS de Java disponible: $lts (Temurin). Java 8 sigue siendo la versi$([char]0x00F3)n de java.com." `
            "$([char]0x00DA)ltima versi$([char]0x00F3) LTS de Java disponible: $lts (Temurin). Java 8 continua sent la versi$([char]0x00F3) de java.com." -Level Ok
    }
    catch { }
}

function Install-LTJavaTemurin {
    <# Installs the latest LTS Eclipse Temurin JRE (free OpenJDK build) from the Adoptium API. #>
    Write-LTLog "Looking for the latest Eclipse Temurin LTS..." "Buscando la $([char]0x00FA)ltima versi$([char]0x00F3)n LTS de Eclipse Temurin..." "Cercant l'$([char]0x00FA)ltima versi$([char]0x00F3) LTS d'Eclipse Temurin..."
    Initialize-LTWeb
    $lts = 25
    try {
        $lts = (Invoke-RestMethod -Uri 'https://api.adoptium.net/v3/info/available_releases' -UseBasicParsing -ErrorAction Stop).most_recent_lts
        $assetsUrl = "https://api.adoptium.net/v3/assets/latest/$lts/hotspot?architecture=x64&image_type=jre&os=windows&vendor=eclipse"
        $asset = @(Invoke-RestMethod -Uri $assetsUrl -UseBasicParsing -ErrorAction Stop)[0]
        $installer = $asset.binary.installer
        if (-not $installer.link) {
            # Some releases only ship a JRE zip; the JDK always has an MSI.
            $assetsUrl = $assetsUrl -replace 'image_type=jre', 'image_type=jdk'
            $asset = @(Invoke-RestMethod -Uri $assetsUrl -UseBasicParsing -ErrorAction Stop)[0]
            $installer = $asset.binary.installer
        }
        $release = $asset.release_name
        Write-LTLog "Version found: $release" "Versi$([char]0x00F3)n encontrada: $release" "Versi$([char]0x00F3) trobada: $release"
        $file = Save-LTFile -Url $installer.link -FileName $installer.name
    }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "Temurin could not be downloaded: $err" "No se ha podido descargar Temurin: $err" "No s'ha pogut descarregar Temurin: $err" -Level Error
        Write-LTLog "Trying winget..." "Probando con winget..." "Provant amb winget..."
        if (-not (Install-LTWinget -Id "EclipseAdoptium.Temurin.$lts.JRE")) { Open-LTUrl 'https://adoptium.net/temurin/releases/' }
        return
    }
    if (-not (Test-LTSignature -Path $file)) { return }
    # FeatureEnvironment/FeatureJavaHome set PATH and JAVA_HOME, FeatureJarFileRunWith opens .jar files,
    # FeatureOracleJavaSoft writes the HKLM\SOFTWARE\JavaSoft keys that older apps look for.
    [void](Start-LTInstaller -Path $file -Arguments 'ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome,FeatureOracleJavaSoft /passive /norestart')
}

function Install-LTJavaOracle8 {
    <# Oracle Java 8 (the one on java.com), still required by some old government applets/apps. #>
    Write-LTLog "Installing Oracle Java 8 (java.com)..." "Instalando Oracle Java 8 (java.com)..." "Instal$([char]0x00B7)lant Oracle Java 8 (java.com)..."
    if (Install-LTWinget -Id 'Oracle.JavaRuntimeEnvironment') {
        Write-LTLog "Oracle Java 8 installed or already up to date." "Oracle Java 8 instalado o ya actualizado." "Oracle Java 8 instal$([char]0x00B7)lat o ja actualitzat." -Level Ok
        return
    }
    # Fallback: offline x64 installer from java.com (the BundleId changes with every release).
    $page = 'https://www.java.com/es/download/manual.jsp'
    try {
        $link = (Get-LTWebPage -Url $page).Links |
            Where-Object { $_.href -match 'AutoDL\?BundleId=' -and $_.outerHTML -match 'Windows Fuera de l(.|&\w+;|&#\d+;)nea \(64 bits\)' } |
            Select-Object -First 1
        if (-not $link) { throw 'link not found' }
        $file = Save-LTFile -Url ([Net.WebUtility]::HtmlDecode($link.href)) -FileName 'jre8-windows-x64.exe'
        if (-not (Test-LTSignature -Path $file)) { return }
        [void](Start-LTInstaller -Path $file -Arguments '/s')
    }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "Could not download from java.com ($err). Opening the official page." `
            "No se ha podido descargar desde java.com ($err). Abriendo la p$([char]0x00E1)gina oficial." `
            "No s'ha pogut descarregar des de java.com ($err). Obrint la p$([char]0x00E0)gina oficial." -Level Warn
        Open-LTUrl "https://www.java.com/$(if ($LT.Lang -eq 'en') { 'en' } else { 'es' })/download/"
    }
}

function Clear-LTJavaCache {
    $javaws = @(
        (Get-Command javaws.exe -ErrorAction SilentlyContinue).Source,
        "$env:ProgramFiles\Java\*\bin\javaws.exe",
        "${env:ProgramFiles(x86)}\Java\*\bin\javaws.exe"
    ) | Where-Object { $_ } | ForEach-Object { Get-Item $_ -ErrorAction SilentlyContinue } | Select-Object -First 1

    if ($javaws) {
        $exe = $javaws.FullName
        Write-LTLog "Clearing the cache with $exe" "Vaciando la cach$([char]0x00E9) con $exe" "Buidant la mem$([char]0x00F2)ria cau amb $exe"
        Start-Process -FilePath $exe -ArgumentList '-uninstall', '-clearcache' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
    }
    $cache = Join-Path $env:USERPROFILE 'AppData\LocalLow\Sun\Java\Deployment\cache'
    if (Test-Path $cache) {
        Remove-Item -Path "$cache\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-LTLog "Java cache deleted: $cache" "Cach$([char]0x00E9) de Java eliminada: $cache" "Mem$([char]0x00F2)ria cau de Java eliminada: $cache" -Level Ok
    }
    elseif (-not $javaws) {
        Write-LTLog "There is no Java cache to clean." "No hay cach$([char]0x00E9) de Java que limpiar." "No hi ha mem$([char]0x00F2)ria cau de Java per netejar."
    }
    else {
        Write-LTLog "Java cache cleared." "Cach$([char]0x00E9) de Java vaciada." "Mem$([char]0x00F2)ria cau de Java buidada." -Level Ok
    }
}

#endregion

# ---- functions\office\OfficeAutoRecover.ps1 ----
#region Office AutoRecover ------------------------------------------------------
<#
    Two layers, so it works both for administrators and for standard users (e.g. on a
    Remote Desktop / terminal server):

    1. User preference, through Office's own object model (no admin rights needed):
         Word        Options.SaveInterval (minutes), Options.CreateBackup
         Excel       Application.AutoRecover.Enabled / .Time
         PowerPoint  HKCU\Software\Microsoft\Office\16.0\PowerPoint\Options
                       SaveAutoRecoveryInfo / FrequencyToSaveAutoRecoveryInfo (no object model;
                       these value names are the long-standing ones, not documented for 16.0)

    2. When the user can elevate, the documented Office 16.0 Group Policy values (ADMX),
       which Office cannot overwrite when it closes:
         Word        HKCU\Software\Policies\Microsoft\Office\16.0\Word\Options
                       autosaveinterval (minutes, 0 = off), keepunsavedchanges
         Excel       ...\Excel\Options       autorecovertime (minutes), keepunsavedchanges
         PowerPoint  ...\PowerPoint\Options  saveautorecoveryinfo, frequencytosaveautorecoveryinfo, keepunsavedchanges
       HKCU\Software\Policies is only writable by administrators, so the values are written
       elevated into HKEY_USERS\<SID of the signed-in user>: they land in the right profile even
       if a different admin account approves the UAC prompt.
#>

function Get-LTUserSid { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }

function Set-LTUserPolicy {
    <#
        Writes DWORD policy values for the current user in one elevated step.
        $Values: list of @{ Path = 'Word\Options'; Name = 'autosaveinterval'; Value = 5 }
        A $null Value removes the value.
    #>
    param([Parameter(Mandatory)][object[]]$Values)

    $sid = Get-LTUserSid
    $lines = foreach ($v in $Values) {
        $key = "Registry::HKEY_USERS\$sid\$($LT.OfficePolicyRoot)\$($v.Path)"
        if ($null -eq $v.Value) {
            "Remove-ItemProperty -LiteralPath '$key' -Name '$($v.Name)' -ErrorAction SilentlyContinue"
        }
        else {
            "if (-not (Test-Path -LiteralPath '$key')) { New-Item -Path '$key' -Force | Out-Null }"
            "New-ItemProperty -LiteralPath '$key' -Name '$($v.Name)' -Value $([int]$v.Value) -PropertyType DWord -Force | Out-Null"
        }
    }
    $result = Invoke-LTElevated -Script ($lines -join "`n")
    if ($result -ne 0) {
        Write-LTLog "The settings could not be locked as a policy (administrator permission is required)." `
            "No se han podido fijar los ajustes como directiva (hacen falta permisos de administrador)." `
            "No s'han pogut fixar els ajustos com a directiva (calen permisos d'administrador)." -Level Warn
        return $false
    }
    $true
}

function Set-LTOfficeUserPreference {
    <# Per-user AutoRecover settings through Office itself. Works without administrator rights. #>
    param(
        [Parameter(Mandatory)][ValidateSet('Word', 'Excel', 'PowerPoint')][string]$App,
        [Parameter(Mandatory)][int]$Minutes,
        [switch]$Backup
    )
    if ($App -eq 'PowerPoint') {
        $key = 'HKCU:\Software\Microsoft\Office\16.0\PowerPoint\Options'
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        Set-ItemProperty -Path $key -Name 'SaveAutoRecoveryInfo' -Value 1 -Type DWord
        Set-ItemProperty -Path $key -Name 'FrequencyToSaveAutoRecoveryInfo' -Value $Minutes -Type DWord
        return $true
    }
    $com = $null
    try {
        if ($App -eq 'Word') {
            $com = New-Object -ComObject Word.Application -ErrorAction Stop
            $com.Options.SaveInterval = $Minutes
            if ($Backup) { $com.Options.CreateBackup = $true }
        }
        else {
            $com = New-Object -ComObject Excel.Application -ErrorAction Stop
            $com.AutoRecover.Enabled = $true
            $com.AutoRecover.Time = $Minutes
        }
        return $true
    }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "$App could not be configured: $err" "No se ha podido configurar ${App}: $err" "No s'ha pogut configurar ${App}: $err" -Level Warn
        return $false
    }
    finally {
        if ($com) {
            try { if ($App -eq 'Word') { $com.Quit([ref]0) } else { $com.Quit() } } catch { }
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($com)
        }
    }
}

function Get-LTAutoRecoverPolicyState {
    <# Returns the policy values written by Lyons Tools, or $null if none. #>
    param([ValidateSet('Word', 'Excel', 'PowerPoint')][string]$App)
    $p = Get-ItemProperty "HKCU:\$($LT.OfficePolicyRoot)\$App\Options" -ErrorAction SilentlyContinue
    $min = switch ($App) { 'Word' { $p.autosaveinterval } 'Excel' { $p.autorecovertime } 'PowerPoint' { $p.frequencytosaveautorecoveryinfo } }
    if ($null -eq $min) { return $null }
    [pscustomobject]@{ Minutes = $min; KeepLast = $p.keepunsavedchanges -eq 1 }
}

function Get-LTAutoRecoverPolicy {
    param(
        [ValidateSet('Word', 'Excel', 'PowerPoint')][string]$App,
        [int]$Minutes
    )
    switch ($App) {
        'Word' { @{ Path = 'Word\Options'; Name = 'autosaveinterval'; Value = $Minutes } }
        'Excel' { @{ Path = 'Excel\Options'; Name = 'autorecovertime'; Value = $Minutes } }
        'PowerPoint' {
            @{ Path = 'PowerPoint\Options'; Name = 'saveautorecoveryinfo'; Value = 1 }
            @{ Path = 'PowerPoint\Options'; Name = 'frequencytosaveautorecoveryinfo'; Value = $Minutes }
        }
    }
}

function Write-LTOfficeRunningWarning {
    $session = (Get-Process -Id $PID).SessionId
    $running = Get-Process WINWORD, EXCEL, POWERPNT -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session
    if ($running) {
        $names = ($running | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
        Write-LTLog "Office programs are open ($names). Close them so they do not overwrite the change; it applies the next time they are opened." `
            "Hay programas de Office abiertos ($names). Ci$([char]0x00E9)rralos para que no sobrescriban el cambio; se aplicar$([char]0x00E1) al volver a abrirlos." `
            "Hi ha programes d'Office oberts ($names). Tanca'ls perqu$([char]0x00E8) no sobreescriguin el canvi; s'aplicar$([char]0x00E0) en tornar-los a obrir." -Level Warn
    }
}

function Set-LTOfficeAutoRecoverCore {
    param(
        [Parameter(Mandatory)][string[]]$Apps,
        [ValidateRange(1, 120)][int]$Minutes = 5,
        [switch]$CrashProtection
    )
    Write-LTOfficeRunningWarning
    foreach ($app in $Apps) {
        if (Set-LTOfficeUserPreference -App $app -Minutes $Minutes -Backup:$CrashProtection) {
            Write-LTLog "${app}: AutoRecover every $Minutes minutes." "${app}: autorrecuperaci$([char]0x00F3)n cada $Minutes minutos." "${app}: recuperaci$([char]0x00F3) autom$([char]0x00E0)tica cada $Minutes minuts." -Level Ok
        }
    }
    if ($CrashProtection -and ($Apps -contains 'Word')) {
        Write-LTLog "Word will always create a backup copy (.wbk) when saving." "Word crear$([char]0x00E1) siempre una copia de seguridad (.wbk) al guardar." "El Word crear$([char]0x00E0) sempre una c$([char]0x00F2)pia de seguretat (.wbk) en desar." -Level Ok
    }

    if (-not $LT.CanElevate) {
        Write-LTLog "Saved as your personal Office setting (you can change it in File > Options > Save)." `
            "Guardado como ajuste personal de Office (se puede cambiar en Archivo > Opciones > Guardar)." `
            "Desat com a ajust personal d'Office (es pot canviar a Fitxer > Opcions > Desa)."
        return
    }
    $values = @(foreach ($app in $Apps) {
            Get-LTAutoRecoverPolicy -App $app -Minutes $Minutes
            if ($CrashProtection) { @{ Path = "$app\Options"; Name = 'keepunsavedchanges'; Value = 1 } }
        })
    if (Set-LTUserPolicy -Values $values) {
        Write-LTLog "Locked as a policy for this user: Office cannot undo it." "Fijado como directiva para este usuario: Office no lo puede deshacer." "Fixat com a directiva per a aquest usuari: Office no ho pot desfer." -Level Ok
        if ($CrashProtection) {
            Write-LTLog "The last AutoRecovered version will be kept if a file is closed without saving." `
                "Se conservar$([char]0x00E1) la $([char]0x00FA)ltima versi$([char]0x00F3)n autorrecuperada si se cierra sin guardar." `
                "Es conservar$([char]0x00E0) l'$([char]0x00FA)ltima versi$([char]0x00F3) recuperada autom$([char]0x00E0)ticament si es tanca sense desar." -Level Ok
        }
    }
}

function Set-LTWordAutoRecover { param([int]$Minutes = 5) Set-LTOfficeAutoRecoverCore -Apps Word -Minutes $Minutes }
function Set-LTExcelAutoRecover { param([int]$Minutes = 5) Set-LTOfficeAutoRecoverCore -Apps Excel -Minutes $Minutes }
function Set-LTPowerPointAutoRecover { param([int]$Minutes = 5) Set-LTOfficeAutoRecoverCore -Apps PowerPoint -Minutes $Minutes }
function Enable-LTOfficeCrashProtection { param([int]$Minutes = 5) Set-LTOfficeAutoRecoverCore -Apps Word, Excel, PowerPoint -Minutes $Minutes -CrashProtection }

function Reset-LTOfficeAutoRecover {
    <# Removes the policy values written by Lyons Tools, so the user can change them again in Office. #>
    if (-not ('Word', 'Excel', 'PowerPoint' | Where-Object { Get-LTAutoRecoverPolicyState -App $_ })) {
        Write-LTLog "There are no locked AutoRecover settings: they can already be changed in File > Options > Save." `
            "No hay ajustes de autoguardado fijados: ya se pueden cambiar en Archivo > Opciones > Guardar." `
            "No hi ha ajustos de desament fixats: ja es poden canviar a Fitxer > Opcions > Desa." -Level Ok
        return
    }
    $values = @(
        @{ Path = 'Word\Options'; Name = 'autosaveinterval'; Value = $null }
        @{ Path = 'Excel\Options'; Name = 'autorecovertime'; Value = $null }
        @{ Path = 'PowerPoint\Options'; Name = 'saveautorecoveryinfo'; Value = $null }
        @{ Path = 'PowerPoint\Options'; Name = 'frequencytosaveautorecoveryinfo'; Value = $null }
        foreach ($app in 'Word', 'Excel', 'PowerPoint') { @{ Path = "$app\Options"; Name = 'keepunsavedchanges'; Value = $null } }
    )
    if (Set-LTUserPolicy -Values $values) {
        Write-LTLog "AutoRecover policies removed. Office uses File > Options > Save again." `
            "Directivas de autoguardado eliminadas. Office vuelve a usar Archivo > Opciones > Guardar." `
            "Directives de desament eliminades. Office torna a fer servir Fitxer > Opcions > Desa." -Level Ok
    }
}

#endregion

# ---- functions\office\OfficeMaintenance.ps1 ----
#region Office maintenance -------------------------------------------------------

function Get-LTClickToRun {
    $cfg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    $exe = Join-Path $env:CommonProgramFiles 'microsoft shared\ClickToRun\OfficeC2RClient.exe'
    $repair = Join-Path $env:CommonProgramFiles 'microsoft shared\ClickToRun\OfficeClickToRun.exe'
    [pscustomobject]@{
        Config    = $cfg
        Client    = if (Test-Path $exe) { $exe } else { $null }
        RepairExe = if (Test-Path $repair) { $repair } else { $null }
    }
}

function Get-LTOfficeInfo {
    $c2r = Get-LTClickToRun
    if ($c2r.Config) {
        $channel = switch -Regex ($c2r.Config.CDNBaseUrl) {
            '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' { 'Current Channel' }
            '55336b82-a18d-4dd6-b5f6-9e5095c314a6' { 'Monthly Enterprise Channel' }
            '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' { 'Semi-Annual Enterprise Channel' }
            '64256afe-f5d9-4f86-8936-8840a6a4f5be' { 'Current Channel (Preview)' }
            default { $c2r.Config.CDNBaseUrl }
        }
        $version = "$($c2r.Config.VersionToReport) ($($c2r.Config.Platform))"
        Write-LTLog "Office: $($c2r.Config.ProductReleaseIds)"
        Write-LTLog "Version: $version" "Versi$([char]0x00F3)n: $version" "Versi$([char]0x00F3): $version"
        Write-LTLog "Channel: $channel" "Canal: $channel" "Canal: $channel"
        if ($c2r.Config.SharedComputerLicensing -eq '1') {
            Write-LTLog "Shared computer activation is on (terminal server)." "La activaci$([char]0x00F3)n de equipo compartido est$([char]0x00E1) activada (servidor de terminales)." "L'activaci$([char]0x00F3) d'equip compartit est$([char]0x00E0) activada (servidor de terminals)."
        }
    }
    else {
        $msi = Get-LTInstalledApp -Name 'Microsoft Office|Microsoft 365' | Select-Object -First 1
        if ($msi) { Write-LTLog "Office (MSI): $($msi.DisplayName) $($msi.DisplayVersion)" }
        else { Write-LTLog "Office is not installed." "No se ha encontrado Office instalado." "No s'ha trobat Office instal$([char]0x00B7)lat." -Level Warn }
    }

    foreach ($app in 'Word', 'Excel', 'PowerPoint') {
        $s = Get-LTAutoRecoverPolicyState -App $app
        if ($s) {
            $keep = if ($s.KeepLast) { Get-LTString 'yes' "s$([char]0x00ED)" "s$([char]0x00ED)" } else { 'no' }
            Write-LTLog "$($app): AutoRecover locked at $($s.Minutes) min; keep last version: $keep" `
                "$($app): autorrecuperaci$([char]0x00F3)n fijada cada $($s.Minutes) min; conservar $([char]0x00FA)ltima versi$([char]0x00F3)n: $keep" `
                "$($app): recuperaci$([char]0x00F3) autom$([char]0x00E0)tica fixada cada $($s.Minutes) min; conservar l'$([char]0x00FA)ltima versi$([char]0x00F3): $keep"
        }
        else {
            Write-LTLog "$($app): AutoRecover set in Office (File > Options > Save)." `
                "$($app): autorrecuperaci$([char]0x00F3)n seg$([char]0x00FA)n Office (Archivo > Opciones > Guardar)." `
                "$($app): recuperaci$([char]0x00F3) autom$([char]0x00E0)tica segons Office (Fitxer > Opcions > Desa)."
        }
    }
}

function Update-LTOffice {
    $c2r = Get-LTClickToRun
    if (-not $c2r.Client) {
        Write-LTLog "Office Click-to-Run not found. If it is an MSI version, update it with Windows Update." `
            "No se ha encontrado Office Click-to-Run. Si es una versi$([char]0x00F3)n MSI, actualiza con Windows Update." `
            "No s'ha trobat Office Click-to-Run. Si $([char]0x00E9)s una versi$([char]0x00F3) MSI, actualitza-la amb Windows Update." -Level Warn
        return
    }
    Write-LTLog "Starting the Office update (the Office window will appear)..." "Iniciando la actualizaci$([char]0x00F3)n de Office (se mostrar$([char]0x00E1) la ventana de Office)..." "Iniciant l'actualitzaci$([char]0x00F3) d'Office (es mostrar$([char]0x00E0) la finestra d'Office)..."
    Start-Process -FilePath $c2r.Client -ArgumentList '/update user updatepromptuser=true forceappshutdown=false displaylevel=true'
    Write-LTLog "Update started. Office will warn you if it needs to close any program." "Actualizaci$([char]0x00F3)n lanzada. Office avisar$([char]0x00E1) si necesita cerrar alg$([char]0x00FA)n programa." "Actualitzaci$([char]0x00F3) iniciada. Office avisar$([char]0x00E0) si cal tancar algun programa." -Level Ok
}

function Repair-LTOffice {
    $c2r = Get-LTClickToRun
    if (-not $c2r.RepairExe -or -not $c2r.Config) {
        Write-LTLog "Office Click-to-Run not found. Use Settings > Apps > Office > Modify." `
            "No se ha encontrado Office Click-to-Run. Usa Configuraci$([char]0x00F3)n > Aplicaciones > Office > Modificar." `
            "No s'ha trobat Office Click-to-Run. Fes servir Configuraci$([char]0x00F3) > Aplicacions > Office > Modifica." -Level Warn
        Start-Process 'ms-settings:appsfeatures'
        return
    }
    $platform = if ($c2r.Config.Platform -eq 'x86') { 'x86' } else { 'x64' }
    $culture = ($c2r.Config.ClientCulture, 'en-us' | Where-Object { $_ } | Select-Object -First 1)
    Write-LTLog "Starting Office Quick Repair ($platform, $culture)..." "Lanzando la reparaci$([char]0x00F3)n r$([char]0x00E1)pida de Office ($platform, $culture)..." "Iniciant la reparaci$([char]0x00F3) r$([char]0x00E0)pida d'Office ($platform, $culture)..."
    $script = "Start-Process -FilePath '$($c2r.RepairExe)' -ArgumentList 'scenario=Repair platform=$platform culture=$culture RepairType=QuickRepair forceappshutdown=false DisplayLevel=True'"
    if ((Invoke-LTElevated -Script $script) -eq 0) {
        Write-LTLog "Repair started. Follow the instructions in the Office window." "Reparaci$([char]0x00F3)n lanzada. Sigue las instrucciones de la ventana de Office." "Reparaci$([char]0x00F3) iniciada. Segueix les instruccions de la finestra d'Office." -Level Ok
    }
}

function Find-LTOfficeRecoverableFiles {
    $since = (Get-Date).AddDays(-30)
    $places = @(
        @{ Path = Join-Path $env:LOCALAPPDATA 'Microsoft\Office\UnsavedFiles'; Filter = '*' },
        @{ Path = Join-Path $env:APPDATA 'Microsoft\Word'; Filter = '*.asd' },
        @{ Path = Join-Path $env:APPDATA 'Microsoft\Word'; Filter = '*.wbk' },
        @{ Path = Join-Path $env:APPDATA 'Microsoft\Excel'; Filter = '*.xlsb' },
        @{ Path = Join-Path $env:APPDATA 'Microsoft\Excel'; Filter = '*.xar' },
        @{ Path = Join-Path $env:APPDATA 'Microsoft\PowerPoint'; Filter = '*.pptx' }
    )
    $files = foreach ($p in $places) {
        if (Test-Path $p.Path) {
            Get-ChildItem -Path $p.Path -Filter $p.Filter -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $since }
        }
    }
    # Word backup copies (.wbk) are saved next to the original document. Depth is limited
    # because Documents is often redirected to a network share on terminal servers.
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $files = @($files) + @(Get-ChildItem -Path $docs -Filter '*.wbk' -Recurse -Depth 4 -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $since })
    $files = @($files | Sort-Object LastWriteTime -Descending)

    if (-not $files.Count) {
        Write-LTLog "No recoverable documents found from the last 30 days." "No se han encontrado documentos recuperables en los $([char]0x00FA)ltimos 30 d$([char]0x00ED)as." "No s'han trobat documents recuperables dels $([char]0x00FA)ltims 30 dies."
        Write-LTLog "Also try in Word/Excel: File > Info > Manage Document > Recover Unsaved Documents." `
            "Prueba tambi$([char]0x00E9)n en Word/Excel: Archivo > Informaci$([char]0x00F3)n > Administrar documento > Recuperar documentos no guardados." `
            "Prova tamb$([char]0x00E9) al Word/Excel: Fitxer > Informaci$([char]0x00F3) > Gestiona el document > Recupera els documents no desats."
        return
    }
    $count = $files.Count
    Write-LTLog "Recoverable documents found ($count):" "Documentos recuperables encontrados ($count):" "Documents recuperables trobats ($count):" -Level Ok
    foreach ($f in $files | Select-Object -First 40) {
        Write-LTLog ("    {0:dd/MM/yyyy HH:mm}  {1}" -f $f.LastWriteTime, $f.FullName)
    }
    Write-LTLog "Open them with Word/Excel and use 'Save as' to keep them. Opening the folder of the most recent one..." `
        "$([char]0x00C1)brelos con Word/Excel y usa 'Guardar como' para conservarlos. Abriendo la carpeta del m$([char]0x00E1)s reciente..." `
        "Obre'ls amb el Word/Excel i fes servir 'Desa com a' per conservar-los. Obrint la carpeta del m$([char]0x00E9)s recent..."
    Start-Process explorer.exe "/select,`"$($files[0].FullName)`""
}

#endregion

# ---- functions\windows\Browser.ps1 ----
#region Default browser ------------------------------------------------------------
<#
    Windows protects the default browser choice (UserChoice hash): no tool may change it
    silently. We use each browser's own "make default" switch and, when Windows still needs
    confirmation, open Settings directly on that browser's page (Windows 11) so the user only
    has to press "Set default".
#>

function Get-LTBrowserInfo {
    param([ValidateSet('Chrome', 'Edge', 'Firefox')][string]$Browser)
    $map = @{
        Chrome  = @{ Exe = 'chrome.exe'; Reg = '^Google Chrome'; ProgId = '^ChromeHTML'; Winget = 'Google.Chrome'; Switch = '--make-default-browser' }
        Edge    = @{ Exe = 'msedge.exe'; Reg = '^Microsoft Edge$'; ProgId = '^MSEdgeHTM'; Winget = 'Microsoft.Edge'; Switch = '--make-default-browser' }
        Firefox = @{ Exe = 'firefox.exe'; Reg = '^Firefox'; ProgId = '^FirefoxURL'; Winget = 'Mozilla.Firefox'; Switch = '-setDefaultBrowser' }
    }
    $info = $map[$Browser]
    $path = $null
    foreach ($hive in 'HKCU', 'HKLM') {
        $p = (Get-ItemProperty "$($hive):\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$($info.Exe)" -ErrorAction SilentlyContinue).'(default)'
        if ($p -and (Test-Path $p.Trim('"'))) { $path = $p.Trim('"'); break }
    }
    # Name under RegisteredApplications, used by the Settings deep link.
    $registered = $null
    foreach ($hive in @(@{ Key = 'HKCU:\SOFTWARE\RegisteredApplications'; Scope = 'registeredAppUser' }, @{ Key = 'HKLM:\SOFTWARE\RegisteredApplications'; Scope = 'registeredAppMachine' })) {
        $props = Get-ItemProperty $hive.Key -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        $name = $props.PSObject.Properties.Name | Where-Object { $_ -match $info.Reg } | Select-Object -First 1
        if ($name) { $registered = @{ Name = $name; Scope = $hive.Scope }; break }
    }
    [pscustomobject]@{ Name = $Browser; Path = $path; Registered = $registered; ProgId = $info.ProgId; Winget = $info.Winget; Switch = $info.Switch }
}

function Install-LTBrowserDirect {
    <# Official enterprise MSI installers, for computers without winget (e.g. Windows Server). #>
    param([ValidateSet('Chrome', 'Edge', 'Firefox')][string]$Browser)
    $lang = switch ($LT.Lang) { 'es' { 'es-ES' } 'ca' { 'ca' } default { 'en-US' } }
    $url = switch ($Browser) {
        'Chrome' { 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' }
        'Firefox' { "https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=win64&lang=$lang" }
        'Edge' { $null }
    }
    if (-not $url) { Open-LTUrl 'https://www.microsoft.com/edge/business/download'; return $false }
    try { $msi = Save-LTFile -Url $url -FileName "$Browser-x64.msi" }
    catch { $err = $_.Exception.Message; Write-LTLog "Download error: $err" "Error al descargar: $err" "Error en descarregar: $err" -Level Error; return $false }
    if (-not (Test-LTSignature -Path $msi)) { return $false }
    Start-LTInstaller -Path $msi
}

function Test-LTDefaultBrowser {
    param([string]$ProgIdPattern)
    $current = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction SilentlyContinue).ProgId
    [bool]($current -and $current -match $ProgIdPattern)
}

function Set-LTDefaultBrowser {
    param([Parameter(Mandatory)][ValidateSet('Chrome', 'Edge', 'Firefox')][string]$Browser)

    $b = Get-LTBrowserInfo -Browser $Browser
    if (-not $b.Path) {
        if (-not $LT.CanElevate) {
            Write-LTLog "$Browser is not installed and installing it requires an administrator." `
                "$Browser no est$([char]0x00E1) instalado y para instalarlo hace falta un administrador." `
                "$Browser no est$([char]0x00E0) instal$([char]0x00B7)lat i per instal$([char]0x00B7)lar-lo cal un administrador." -Level Warn
            return
        }
        Write-LTLog "$Browser is not installed. Installing it..." "$Browser no est$([char]0x00E1) instalado. Instal$([char]0x00E1)ndolo..." "$Browser no est$([char]0x00E0) instal$([char]0x00B7)lat. Instal$([char]0x00B7)lant-lo..." -Level Warn
        if (-not (Install-LTWinget -Id $b.Winget)) {
            if (-not (Install-LTBrowserDirect -Browser $Browser)) { return }
        }
        $b = Get-LTBrowserInfo -Browser $Browser
        if (-not $b.Path) { Write-LTLog "$Browser could not be found after installing it." "No se encuentra $Browser despu$([char]0x00E9)s de instalarlo." "No es troba $Browser despr$([char]0x00E9)s d'instal$([char]0x00B7)lar-lo." -Level Error; return }
    }
    if (Test-LTDefaultBrowser $b.ProgId) {
        Write-LTLog "$Browser is already the default browser." "$Browser ya es el navegador predeterminado." "$Browser ja $([char]0x00E9)s el navegador predeterminat." -Level Ok
        return
    }

    Test-LTAssociationPolicy

    # Firefox can usually set itself as default (also on Windows 10 / Server).
    if ($Browser -eq 'Firefox') {
        Start-Process -FilePath $b.Path -ArgumentList $b.Switch -Wait -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (Test-LTDefaultBrowser $b.ProgId) {
            Write-LTLog "Done: Firefox is now the default browser." "Hecho: Firefox es ahora el navegador predeterminado." "Fet: Firefox $([char]0x00E9)s ara el navegador predeterminat." -Level Ok
            return
        }
    }

    $build = [Environment]::OSVersion.Version.Build
    if ($build -ge 22000 -and $b.Registered) {
        # Windows 11 / Server 2025: Settings opens on the browser's own page with a "Set default" button.
        $name = [Uri]::EscapeDataString($b.Registered.Name)
        Start-Process "ms-settings:defaultapps?$($b.Registered.Scope)=$name"
        Write-LTLog "Settings has opened on the $Browser page: press 'Set default' at the top." `
            "Se ha abierto Configuraci$([char]0x00F3)n en la p$([char]0x00E1)gina de ${Browser}: pulsa 'Establecer como predeterminado' arriba." `
            "S'ha obert Configuraci$([char]0x00F3) a la p$([char]0x00E0)gina de ${Browser}: prem 'Estableix com a predeterminat' a dalt." -Level Step
    }
    else {
        # Windows 10 / Server 2016-2022: the browsers' --make-default-browser switch is not reliable
        # here (Edge just opens a window), so go straight to Settings > Default apps.
        Start-Process 'ms-settings:defaultapps'
        Write-LTLog "In Settings > Default apps, click the browser under 'Web browser' and choose $Browser." `
            "En Configuraci$([char]0x00F3)n > Aplicaciones predeterminadas, pulsa el navegador que aparece en 'Explorador web' y elige $Browser." `
            "A Configuraci$([char]0x00F3) > Aplicacions predeterminades, prem el navegador que surt a 'Navegador web' i tria $Browser." -Level Step
    }

    # Wait for the user's choice and confirm it, instead of assuming it worked.
    Write-LTLog "Waiting for the change (up to 2 minutes)..." "Esperando el cambio (hasta 2 minutos)..." "Esperant el canvi (fins a 2 minuts)..."
    $deadline = (Get-Date).AddMinutes(2)
    while ((Get-Date) -lt $deadline) {
        if (Test-LTDefaultBrowser $b.ProgId) {
            Write-LTLog "Done: $Browser is now the default browser." "Hecho: $Browser es ahora el navegador predeterminado." "Fet: $Browser $([char]0x00E9)s ara el navegador predeterminat." -Level Ok
            return
        }
        Start-Sleep -Seconds 2
    }
    Write-LTLog "$Browser is not the default browser yet. Finish the choice in Settings and use the 'Test' button to check it." `
        "$Browser todav$([char]0x00ED)a no es el navegador predeterminado. Termina la elecci$([char]0x00F3)n en Configuraci$([char]0x00F3)n y usa el bot$([char]0x00F3)n 'Prueba' para comprobarlo." `
        "$Browser encara no $([char]0x00E9)s el navegador predeterminat. Acaba l'elecci$([char]0x00F3) a Configuraci$([char]0x00F3) i fes servir el bot$([char]0x00F3) 'Prova' per comprovar-ho." -Level Warn
}

function Test-LTAssociationPolicy {
    <#
        Warns if a Group Policy "default associations configuration file" is set (common on
        domain-joined terminal servers): it re-applies its browser/PDF defaults at every sign-in.
    #>
    $file = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -ErrorAction SilentlyContinue).DefaultAssociationsConfiguration
    if (-not $file) { return $false }
    Write-LTLog "A Group Policy sets the default apps on this computer ($file). Any change may be undone at the next sign-in; ask the domain administrator to change that file." `
        "Una directiva de grupo fija las aplicaciones predeterminadas en este equipo ($file). El cambio puede deshacerse al volver a iniciar sesi$([char]0x00F3)n; pide al administrador del dominio que cambie ese archivo." `
        "Una directiva de grup fixa les aplicacions predeterminades en aquest equip ($file). El canvi es pot desfer en tornar a iniciar sessi$([char]0x00F3); demana a l'administrador del domini que canvi$([char]0x00EF) aquest fitxer." -Level Warn
    $true
}

function Get-LTBrowserName([string]$ProgId) {
    switch -Regex ($ProgId) {
        '^ChromeHTML' { 'Google Chrome' }
        '^MSEdgeHTM' { 'Microsoft Edge' }
        '^FirefoxURL' { 'Mozilla Firefox' }
        '^IE\.HTTP' { 'Internet Explorer' }
        '^$' { Get-LTString 'not set (Windows default)' 'sin definir (predeterminado de Windows)' "sense definir (predeterminat de Windows)" }
        default { $ProgId }
    }
}

function Open-LTDefaultBrowserTest {
    <# Shows which browser is the default (https and http) and opens ehtu.com with it, to confirm the change worked. #>
    $base = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations'
    $https = Get-LTBrowserName (Get-ItemProperty "$base\https\UserChoice" -ErrorAction SilentlyContinue).ProgId
    $http = Get-LTBrowserName (Get-ItemProperty "$base\http\UserChoice" -ErrorAction SilentlyContinue).ProgId
    Write-LTLog "Current default browser: $https" "Navegador predeterminado actual: $https" "Navegador predeterminat actual: $https" -Level Ok
    if ($http -ne $https) {
        Write-LTLog "Note: http links open with $http (https with $https)." "Atenci$([char]0x00F3)n: los enlaces http se abren con $http (https con $https)." "Atenci$([char]0x00F3): els enlla$([char]0x00E7)os http s'obren amb $http (https amb $https)." -Level Warn
    }
    [void](Test-LTAssociationPolicy)
    $url = $LT.Config.app.publisherUrl
    Write-LTLog "Opening $url with the default browser..." "Abriendo $url con el navegador predeterminado..." "Obrint $url amb el navegador predeterminat..."
    Start-Process $url
}

function Set-LTDefaultBrowserChrome { Set-LTDefaultBrowser -Browser Chrome }
function Set-LTDefaultBrowserEdge { Set-LTDefaultBrowser -Browser Edge }
function Set-LTDefaultBrowserFirefox { Set-LTDefaultBrowser -Browser Firefox }

#endregion

# ---- functions\windows\Pdf.ps1 ----
#region PDF ----------------------------------------------------------------------

function Get-LTAdobeProgId {
    <# ProgId registered by Adobe Acrobat (64-bit, "Acrobat.Document.DC") or Acrobat Reader 32-bit ("AcroExch.Document.DC"). #>
    foreach ($id in 'Acrobat.Document.DC', 'AcroExch.Document.DC') {
        if (Test-Path "Registry::HKEY_CLASSES_ROOT\$id\shell\open\command") { return $id }
    }
    $null
}

function Get-LTPdfDefault {
    (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice' -ErrorAction SilentlyContinue).ProgId
}

function Get-LTPdfAppName([string]$ProgId) {
    switch -Regex ($ProgId) {
        '^(Acrobat|AcroExch)\.' { 'Adobe Acrobat' }
        '^MSEdgePDF' { 'Microsoft Edge' }
        '^Chrome' { 'Google Chrome' }
        '^FirefoxPDF' { 'Mozilla Firefox' }
        '^$' { Get-LTString 'not set (Windows default)' 'sin definir (predeterminado de Windows)' "sense definir (predeterminat de Windows)" }
        default { $ProgId }
    }
}

function Get-LTAdobeReaderUrl {
    <#
        Current official Adobe Reader 64-bit installer (ardownload*.adobe.com), taken from the
        winget package catalogue on GitHub. Used on computers without winget (e.g. Windows Server).
    #>
    $headers = @{ 'User-Agent' = 'LyonsTools' }
    $base = 'https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/a/Adobe/Acrobat/Reader/64-bit'
    # Assigned first: in Windows PowerShell 5.1 Invoke-RestMethod does not enumerate arrays into the pipeline.
    $dirs = Invoke-RestMethod -Uri $base -UseBasicParsing -Headers $headers -ErrorAction Stop
    $latest = $dirs | Where-Object type -eq 'dir' | Sort-Object { [version]($_.name -replace '[^\d.]', '') } | Select-Object -Last 1
    $files = Invoke-RestMethod -Uri $latest.url -UseBasicParsing -Headers $headers -ErrorAction Stop
    $installer = $files | Where-Object name -like '*.installer.yaml' | Select-Object -First 1
    $yaml = (Invoke-WebRequest -Uri $installer.download_url -UseBasicParsing -ErrorAction Stop).Content
    $url = [regex]::Match($yaml, 'InstallerUrl:\s*(https://ardownload\d*\.adobe\.com/\S+\.exe)').Groups[1].Value
    if (-not $url) { throw 'Adobe installer URL not found' }
    [pscustomobject]@{ Version = $latest.name; Url = $url }
}

function Install-LTAdobeReader {
    <# Court notifications, tax forms and signed filings are PDFs whose signatures Adobe Reader can validate. #>
    if (Install-LTWinget -Id 'Adobe.Acrobat.Reader.64-bit') {
        Write-LTLog "Adobe Acrobat Reader installed or already up to date." "Adobe Acrobat Reader instalado o ya actualizado." "Adobe Acrobat Reader instal$([char]0x00B7)lat o ja actualitzat." -Level Ok
        return
    }
    # No winget (Windows Server): official Adobe installer.
    try {
        $reader = Get-LTAdobeReaderUrl
        $v = $reader.Version
        Write-LTLog "Downloading Adobe Acrobat Reader $v (about 800 MB, it may take a while)..." `
            "Descargando Adobe Acrobat Reader $v (unos 800 MB, puede tardar)..." `
            "Descarregant Adobe Acrobat Reader $v (uns 800 MB, pot trigar)..."
        $file = Save-LTFile -Url $reader.Url
    }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "Adobe Reader could not be downloaded ($err). Opening the official page." `
            "No se ha podido descargar Adobe Reader ($err). Abriendo la p$([char]0x00E1)gina oficial." `
            "No s'ha pogut descarregar Adobe Reader ($err). Obrint la p$([char]0x00E0)gina oficial." -Level Warn
        Open-LTUrl 'https://get.adobe.com/reader/enterprise/'
        return
    }
    if (-not (Test-LTSignature -Path $file)) { return }
    # Adobe's documented switches: progress bar only, no restart.
    [void](Start-LTInstaller -Path $file -Arguments '/sPB /rs /msi')
}

function New-LTSamplePdf {
    <# Writes a small, valid one-page PDF (with a correct xref table) and returns its path. #>
    $content = "BT /F1 22 Tf 72 760 Td (Lyons Tools - PDF test) Tj 0 -34 Td /F1 12 Tf (If you can read this, PDF files open correctly. ehtu.com) Tj ET"
    $objects = @(
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
        "<< /Length $($content.Length) >>`nstream`n$content`nendstream",
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
    )
    $sb = [Text.StringBuilder]::new("%PDF-1.4`n")
    $offsets = foreach ($i in 0..($objects.Count - 1)) {
        $sb.Length
        [void]$sb.Append("$($i + 1) 0 obj`n$($objects[$i])`nendobj`n")
    }
    $xref = $sb.Length
    [void]$sb.Append("xref`n0 $($objects.Count + 1)`n0000000000 65535 f `n")
    foreach ($o in $offsets) { [void]$sb.Append(('{0:D10} 00000 n ' -f $o) + "`n") }
    [void]$sb.Append("trailer`n<< /Size $($objects.Count + 1) /Root 1 0 R >>`nstartxref`n$xref`n%%EOF`n")

    $path = Join-Path (Get-LTWorkFolder) 'LyonsTools-test.pdf'
    [IO.File]::WriteAllText($path, $sb.ToString(), [Text.Encoding]::ASCII)
    $path
}

function Show-LTOpenWithDialog {
    <#
        Shows Windows' "Open with" dialog for a file through SHOpenWithDialog and waits for it.
        OAIF_REGISTER_EXT | OAIF_EXEC | OAIF_FORCE_REGISTRATION: the app the user picks is saved
        as the default for that file type and the file is opened with it.
        Returns 'ok', 'cancelled' or the HRESULT.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not ('LTOpenWith' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LTOpenWith {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct OPENASINFO { public string pcszFile; public string pcszClass; public int oaifInFlags; }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHOpenWithDialog(IntPtr hwndParent, ref OPENASINFO info);
    public static int Show(string file, int flags) {
        OPENASINFO info = new OPENASINFO();
        info.pcszFile = file;
        info.pcszClass = null;
        info.oaifInFlags = flags;
        return SHOpenWithDialog(IntPtr.Zero, ref info);
    }
}
'@
    }
    $hr = [LTOpenWith]::Show($Path, 0x2 -bor 0x4 -bor 0x8)
    switch ($hr) {
        0 { 'ok' }
        -2147023673 { 'cancelled' }   # HRESULT_FROM_WIN32(ERROR_CANCELLED)
        default { '0x{0:X8}' -f $hr }
    }
}

function Set-LTAdobeDefaultPdf {
    <#
        Windows requires the user to confirm the default PDF app. Depending on the OS we open:
          Windows 11 / Server 2025         : Settings on Adobe's page ("Set default")
          Windows 10 / Server 2016-2022    : the "Open with" dialog for a sample PDF ("Always use this app")
        and then wait up to 2 minutes to confirm the change.
    #>
    $progId = Get-LTAdobeProgId
    if (-not $progId) {
        if (-not $LT.CanElevate) {
            Write-LTLog "Adobe Acrobat Reader is not installed and installing it requires an administrator." `
                "Adobe Acrobat Reader no est$([char]0x00E1) instalado y para instalarlo hace falta un administrador." `
                "Adobe Acrobat Reader no est$([char]0x00E0) instal$([char]0x00B7)lat i per instal$([char]0x00B7)lar-lo cal un administrador." -Level Warn
            return
        }
        Write-LTLog "Adobe Acrobat Reader is not installed. Installing it first..." "Adobe Acrobat Reader no est$([char]0x00E1) instalado. Se instala primero..." "Adobe Acrobat Reader no est$([char]0x00E0) instal$([char]0x00B7)lat. S'instal$([char]0x00B7)la primer..." -Level Warn
        Install-LTAdobeReader
        $progId = Get-LTAdobeProgId
        if (-not $progId) { return }
    }

    $current = Get-LTPdfDefault
    if ($current -match '^(Acrobat|AcroExch)\.') {
        Write-LTLog "Adobe Acrobat is already the default app for PDF files." "Adobe Acrobat ya es la aplicaci$([char]0x00F3)n predeterminada para los PDF." "Adobe Acrobat ja $([char]0x00E9)s l'aplicaci$([char]0x00F3) predeterminada per als PDF." -Level Ok
        return
    }
    $now = Get-LTPdfAppName $current
    Write-LTLog "PDF files currently open with: $now" "Los PDF se abren ahora con: $now" "Els PDF s'obren ara amb: $now"
    [void](Test-LTAssociationPolicy)

    $build = [Environment]::OSVersion.Version.Build
    $registered = $null
    $props = Get-ItemProperty 'HKLM:\SOFTWARE\RegisteredApplications' -ErrorAction SilentlyContinue
    if ($props) { $registered = $props.PSObject.Properties.Name | Where-Object { $_ -match '^Adobe Acrobat' } | Select-Object -First 1 }

    if ($build -ge 22000 -and $registered) {
        Start-Process "ms-settings:defaultapps?registeredAppMachine=$([Uri]::EscapeDataString($registered))"
        Write-LTLog "Settings has opened on the Adobe Acrobat page: press 'Set default' at the top." `
            "Se ha abierto Configuraci$([char]0x00F3)n en la p$([char]0x00E1)gina de Adobe Acrobat: pulsa 'Establecer como predeterminado' arriba." `
            "S'ha obert Configuraci$([char]0x00F3) a la p$([char]0x00E0)gina d'Adobe Acrobat: prem 'Estableix com a predeterminat' a dalt." -Level Step
    }
    else {
        # Windows' own "Open with" dialog, asked to save the choice as the default for .pdf.
        # (rundll32 OpenAs_RunDLL shows the same list but without the "always use this app" option.)
        Write-LTLog "In the 'How do you want to open this file?' window choose 'Adobe Acrobat' and press OK: it will become the default for PDF files." `
            "En la ventana '$([char]0x00BF)C$([char]0x00F3)mo quieres abrir este archivo?' elige 'Adobe Acrobat' y pulsa Aceptar: quedar$([char]0x00E1) como predeterminada para los PDF." `
            "A la finestra 'Com vols obrir aquest fitxer?' tria 'Adobe Acrobat' i prem D'acord: quedar$([char]0x00E0) com a predeterminada per als PDF." -Level Step
        $result = Show-LTOpenWithDialog -Path (New-LTSamplePdf)
        if ((Get-LTPdfDefault) -match '^(Acrobat|AcroExch)\.') {
            Write-LTLog "Done: PDF files will open with Adobe Acrobat." "Hecho: los PDF se abrir$([char]0x00E1)n con Adobe Acrobat." "Fet: els PDF s'obriran amb Adobe Acrobat." -Level Ok
            return
        }
        # Backup: the Settings page, where the user picks Adobe for .pdf.
        Start-Process 'ms-settings:defaultapps'
        Write-LTLog "Not changed yet ($result). In Settings > Default apps > Choose default apps by file type, set '.pdf' to Adobe Acrobat." `
            "Todav$([char]0x00ED)a no ha cambiado ($result). En Configuraci$([char]0x00F3)n > Aplicaciones predeterminadas > Elegir aplicaciones predeterminadas por tipo de archivo, pon '.pdf' con Adobe Acrobat." `
            "Encara no ha canviat ($result). A Configuraci$([char]0x00F3) > Aplicacions predeterminades > Tria les aplicacions predeterminades per tipus de fitxer, posa '.pdf' amb Adobe Acrobat." -Level Step
    }

    Write-LTLog "Waiting for the change (up to 2 minutes)..." "Esperando el cambio (hasta 2 minutos)..." "Esperant el canvi (fins a 2 minuts)..."
    $deadline = (Get-Date).AddMinutes(2)
    while ((Get-Date) -lt $deadline) {
        if ((Get-LTPdfDefault) -match '^(Acrobat|AcroExch)\.') {
            Write-LTLog "Done: PDF files will open with Adobe Acrobat." "Hecho: los PDF se abrir$([char]0x00E1)n con Adobe Acrobat." "Fet: els PDF s'obriran amb Adobe Acrobat." -Level Ok
            return
        }
        Start-Sleep -Seconds 2
    }
    Write-LTLog "Adobe is not the default yet. You can also change it in Settings > Apps > Default apps > Choose default apps by file type > .pdf, then use the PDF 'Test' button." `
        "Adobe todav$([char]0x00ED)a no es la predeterminada. Tambi$([char]0x00E9)n se puede cambiar en Configuraci$([char]0x00F3)n > Aplicaciones > Aplicaciones predeterminadas > Elegir aplicaciones predeterminadas por tipo de archivo > .pdf, y despu$([char]0x00E9)s usar el bot$([char]0x00F3)n 'Prueba' de PDF." `
        "Adobe encara no $([char]0x00E9)s la predeterminada. Tamb$([char]0x00E9) es pot canviar a Configuraci$([char]0x00F3) > Aplicacions > Aplicacions predeterminades > Tria les aplicacions predeterminades per tipus de fitxer > .pdf, i despr$([char]0x00E9)s fer servir el bot$([char]0x00F3) 'Prova' de PDF." -Level Warn
}

function Open-LTPdfTest {
    <# Shows which app opens PDF files and opens a test PDF with it. #>
    $name = Get-LTPdfAppName (Get-LTPdfDefault)
    Write-LTLog "PDF files open with: $name" "Los PDF se abren con: $name" "Els PDF s'obren amb: $name" -Level Ok
    [void](Test-LTAssociationPolicy)
    $sample = New-LTSamplePdf
    Write-LTLog "Opening a test PDF with the default app..." "Abriendo un PDF de prueba con la aplicaci$([char]0x00F3)n predeterminada..." "Obrint un PDF de prova amb l'aplicaci$([char]0x00F3) predeterminada..."
    Start-Process $sample
}

function Set-LTBrowserPdfDownload {
    <#
        Browser policies so PDFs are downloaded and opened with the default PDF app
        (Adobe) instead of the built-in viewers of Edge, Chrome and Firefox:
          Edge / Chrome : AlwaysOpenPdfExternally = 1
          Firefox       : DisableBuiltinPDFViewer = 1 and Handlers -> application/pdf useSystemDefault
        Browsers will show "Managed by your organization".
    #>
    param([switch]$Undo)

    $handlers = '{"mimeTypes":{"application/pdf":{"action":"useSystemDefault","ask":false}},"extensions":{"pdf":{"action":"useSystemDefault","ask":false}}}'
    if ($Undo) {
        $script = @"
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name AlwaysOpenPdfExternally -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name AlwaysOpenPdfExternally -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' -Name DisableBuiltinPDFViewer, Handlers -ErrorAction SilentlyContinue
"@
    }
    else {
        $script = @"
foreach (`$k in 'HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox') {
    if (-not (Test-Path `$k)) { New-Item -Path `$k -Force | Out-Null }
}
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name AlwaysOpenPdfExternally -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name AlwaysOpenPdfExternally -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' -Name DisableBuiltinPDFViewer -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' -Name Handlers -Value '$handlers' -PropertyType String -Force | Out-Null
"@
    }
    if ((Invoke-LTElevated -Script $script) -ne 0) {
        Write-LTLog "The browser settings could not be changed." "No se han podido cambiar los ajustes de los navegadores." "No s'han pogut canviar els ajustos dels navegadors." -Level Error
        return
    }
    if ($Undo) {
        Write-LTLog "Edge, Chrome and Firefox will open PDFs in the browser again." "Edge, Chrome y Firefox vuelven a abrir los PDF en el navegador." "Edge, Chrome i Firefox tornen a obrir els PDF al navegador." -Level Ok
    }
    else {
        Write-LTLog "Edge, Chrome and Firefox will download PDFs and open them with the default PDF app." `
            "Edge, Chrome y Firefox descargar$([char]0x00E1)n los PDF y los abrir$([char]0x00E1)n con la aplicaci$([char]0x00F3)n de PDF predeterminada." `
            "Edge, Chrome i Firefox descarregaran els PDF i els obriran amb l'aplicaci$([char]0x00F3) de PDF predeterminada." -Level Ok
        Write-LTLog "Restart the browsers to apply it. They will show 'Managed by your organization'." `
            "Reinicia los navegadores para aplicarlo. Mostrar$([char]0x00E1)n 'Administrado por tu organizaci$([char]0x00F3)n'." `
            "Reinicia els navegadors per aplicar-ho. Mostraran 'Gestionat per la teva organitzaci$([char]0x00F3)'."
        $current = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice' -ErrorAction SilentlyContinue).ProgId
        if ($current -notmatch '^(Acrobat|AcroExch)\.') {
            Write-LTLog "Tip: also run 'Make Adobe Reader the default PDF app', otherwise downloaded PDFs may still open in Edge." `
                "Consejo: ejecuta tambi$([char]0x00E9)n 'Hacer Adobe Reader la aplicaci$([char]0x00F3)n predeterminada', si no los PDF descargados pueden seguir abri$([char]0x00E9)ndose en Edge." `
                "Consell: executa tamb$([char]0x00E9) 'Fes d'Adobe Reader l'aplicaci$([char]0x00F3) predeterminada', si no els PDF descarregats es poden continuar obrint a Edge." -Level Warn
        }
    }
}

function Reset-LTBrowserPdfDownload { Set-LTBrowserPdfDownload -Undo }

#endregion

# ---- functions\windows\Windows.ps1 ----
#region Windows -----------------------------------------------------------------

function Enable-LTFileExtensions {
    # Showing extensions helps users spot "invoice.pdf.exe" style phishing attachments.
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 -Type DWord
    Write-LTLog "File extensions (.pdf, .docx, .exe...) will now be shown." `
        "Ahora se mostrar$([char]0x00E1)n las extensiones de archivo (.pdf, .docx, .exe...)." `
        "Ara es mostraran les extensions dels fitxers (.pdf, .docx, .exe...)." -Level Ok
    Restart-LTExplorer
}

function Enable-LTClipboardHistory {
    $key = 'HKCU:\Software\Microsoft\Clipboard'
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    Set-ItemProperty -Path $key -Name 'EnableClipboardHistory' -Value 1 -Type DWord
    Write-LTLog "Clipboard history turned on. Press Windows + V to see what you have copied." `
        "Historial del portapapeles activado. Pulsa Windows + V para ver lo que has copiado." `
        "Historial del porta-retalls activat. Prem Windows + V per veure el que has copiat." -Level Ok
}

function Restart-LTExplorer {
    Write-LTLog "Restarting Windows Explorer..." "Reiniciando el Explorador de Windows..." "Reiniciant l'Explorador de Windows..."
    # Only this session's Explorer: on a terminal server, other users' sessions must not be touched.
    $session = (Get-Process -Id $PID).SessionId
    Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session)) { Start-Process explorer.exe }
    Write-LTLog "Explorer restarted." "Explorador reiniciado." "Explorador reiniciat." -Level Ok
}

function Clear-LTTempFiles {
    $targets = @($env:TEMP, (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache')) | Where-Object { Test-Path $_ }
    $before = 0; $after = 0
    foreach ($t in $targets) {
        $files = Get-ChildItem -Path $t -Recurse -Force -File -ErrorAction SilentlyContinue
        $before += ($files | Measure-Object Length -Sum).Sum
        Get-ChildItem -Path $t -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne (Get-LTWorkFolder) } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $after += (Get-ChildItem -Path $t -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    }
    $freed = [math]::Round(($before - $after) / 1MB, 0)
    Write-LTLog "Temporary files deleted: $freed MB freed (files in use were left)." `
        "Archivos temporales eliminados: $freed MB liberados (los archivos en uso se han dejado)." `
        "Fitxers temporals eliminats: $freed MB alliberats (els fitxers en $([char]0x00FA)s s'han deixat)." -Level Ok
}

function Clear-LTDnsCache {
    # Flushing the resolver cache requires administrator rights.
    if ((Invoke-LTElevated -Script 'ipconfig.exe /flushdns | Out-Null') -ne 0) { return }
    Write-LTLog "DNS cache flushed." "Cach$([char]0x00E9) DNS vaciada." "Mem$([char]0x00F2)ria cau DNS buidada." -Level Ok
}

function Start-LTQuickAssist {
    if ($LT.IsServer) {
        Write-LTLog "Quick Assist is not available on Windows Server. Contact your support provider for remote access." `
            "Asistencia r$([char]0x00E1)pida no est$([char]0x00E1) disponible en Windows Server. Contacta con tu soporte para la conexi$([char]0x00F3)n remota." `
            "L'Assist$([char]0x00E8)ncia r$([char]0x00E0)pida no est$([char]0x00E0) disponible a Windows Server. Contacta amb el teu suport per a la connexi$([char]0x00F3) remota." -Level Warn
        return
    }
    Write-LTLog "Opening Quick Assist. Choose 'Help someone' or enter the code the technician gives you." `
        "Abriendo Asistencia r$([char]0x00E1)pida. Elige 'Ayudar a alguien' o introduce el c$([char]0x00F3)digo que te d$([char]0x00E9) el t$([char]0x00E9)cnico." `
        "Obrint l'Assist$([char]0x00E8)ncia r$([char]0x00E0)pida. Tria 'Ajudar alg$([char]0x00FA)' o introdueix el codi que et doni el t$([char]0x00E8)cnic."
    try { Start-Process 'ms-quick-assist:' -ErrorAction Stop }
    catch {
        Write-LTLog "Quick Assist is not installed. Opening Microsoft Store..." "Asistencia r$([char]0x00E1)pida no est$([char]0x00E1) instalada. Abriendo Microsoft Store..." "L'Assist$([char]0x00E8)ncia r$([char]0x00E0)pida no est$([char]0x00E0) instal$([char]0x00B7)lada. Obrint Microsoft Store..." -Level Warn
        Start-Process 'ms-windows-store://pdp/?ProductId=9P7BP5VNWKX5'
    }
}

function Open-LTWindowsUpdate {
    Start-Process 'ms-settings:windowsupdate'
    Write-LTLog "Windows Update opened." "Abierto Windows Update." "S'ha obert Windows Update." -Level Ok
}

function Get-LTSystemReport {
    <# Builds a support report (Windows, Office, Java, signing apps, certificates) and copies it to the clipboard. #>
    Write-LTLog "Building the computer report..." "Generando informe del equipo..." "Generant l'informe de l'equip..."
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    $c2r = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    $display = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion
    $yes = Get-LTString 'yes' "s$([char]0x00ED)" "s$([char]0x00ED)"
    $notInstalled = Get-LTString 'not installed' 'no instalado' "no instal$([char]0x00B7)lat"
    $row = { param($label, $value) '{0,-14}{1}' -f "${label}:", $value }

    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add((Get-LTString "Lyons Tools $($LT.Version) report" "Informe Lyons Tools $($LT.Version)" "Informe Lyons Tools $($LT.Version)") + " - $(Get-Date -Format 'dd/MM/yyyy HH:mm')")
    $lines.Add((& $row (Get-LTString 'Computer' 'Equipo' 'Equip') "$env:COMPUTERNAME ($($cs.Manufacturer) $($cs.Model))"))
    $lines.Add((& $row (Get-LTString 'User' 'Usuario' 'Usuari') "$env:USERDOMAIN\$env:USERNAME (admin: $(if (Test-LTAdmin) { $yes } else { 'no' }))"))
    $lines.Add((& $row 'Windows' "$($os.Caption) $display (build $($os.BuildNumber))"))
    $lines.Add((& $row (Get-LTString 'Memory' 'Memoria' "Mem$([char]0x00F2)ria") "$([math]::Round($cs.TotalPhysicalMemory / 1GB, 1)) GB"))
    $free = [math]::Round($disk.FreeSpace / 1GB, 1); $size = [math]::Round($disk.Size / 1GB, 1)
    $lines.Add((& $row "$(Get-LTString 'Disk' 'Disco' 'Disc') $($env:SystemDrive)" (Get-LTString "$free GB free of $size GB" "$free GB libres de $size GB" "$free GB lliures de $size GB")))
    $office = if ($c2r) { "$($c2r.ProductReleaseIds) $($c2r.VersionToReport) ($($c2r.Platform))" } else { Get-LTString 'Office Click-to-Run not detected' 'no se ha detectado Office Click-to-Run' "no s'ha detectat Office Click-to-Run" }
    $lines.Add((& $row 'Office' $office))

    $java = Get-Command java.exe -ErrorAction SilentlyContinue
    $javaVer = if ($java) { (& cmd.exe /c "`"$($java.Source)`" -version 2>&1" | Select-Object -First 1) } else { Get-LTString 'not in the PATH' "no est$([char]0x00E1) en el PATH" "no $([char]0x00E9)s al PATH" }
    $lines.Add((& $row 'Java' $javaVer))

    foreach ($app in @(
            @{ Label = 'Autofirma'; Pattern = 'Autofirma' },
            @{ Label = 'Configurador'; Pattern = 'Configurador FNMT' },
            @{ Label = 'Signador'; Pattern = 'Signador|AOC' },
            @{ Label = 'Bit4id'; Pattern = 'Bit4id|Universal MW' })) {
        $found = Get-LTInstalledApp -Name $app.Pattern | Select-Object -First 1
        $lines.Add((& $row $app.Label $(if ($found) { "$($found.DisplayName) $($found.DisplayVersion)" } else { $notInstalled })))
    }

    $certs = @(Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue | Where-Object HasPrivateKey)
    $lines.Add((Get-LTString 'Signing certificates' 'Certificados de firma' 'Certificats de signatura') + ": $($certs.Count)")
    $expires = Get-LTString 'expires' 'caduca' 'caduca'
    foreach ($c in $certs | Sort-Object NotAfter) {
        $lines.Add("    - $($c.GetNameInfo('SimpleName', $false)) | $expires $($c.NotAfter.ToString('dd/MM/yyyy'))")
    }

    $text = $lines -join [Environment]::NewLine
    $lines | ForEach-Object { Write-LTLog $_ }
    try {
        Set-Clipboard -Value $text -ErrorAction Stop
        Write-LTLog "Report copied to the clipboard. Paste it into an email to support." `
            "Informe copiado al portapapeles. P$([char]0x00E9)galo en un correo a soporte." `
            "Informe copiat al porta-retalls. Enganxa'l en un correu al suport." -Level Ok
    }
    catch {
        $file = Join-Path ([Environment]::GetFolderPath('Desktop')) "LyonsTools-$env:COMPUTERNAME.txt"
        Set-Content -Path $file -Value $text -Encoding UTF8
        Write-LTLog "Report saved to $file" "Informe guardado en $file" "Informe desat a $file" -Level Ok
    }
}

#endregion


$LTConfigJson = @'
{
  "app": {
    "name": "Lyons Tools",
    "version": "1.3.5",
    "repo": "EhtuCom/LyonsTools",
    "publisher": "ehtu.com",
    "publisherUrl": "https://ehtu.com",
    "defaultLanguage": "en"
  },
  "languages": [
    { "code": "en", "name": "English" },
    { "code": "es", "name": "Espa\u00f1ol" },
    { "code": "ca", "name": "Catal\u00e0" }
  ],
  "strings": {
    "subtitle": {
      "en": "Settings and utilities for law and tax firms: Windows, Office, Java and digital signature",
      "es": "Ajustes y utilidades para despachos: Windows, Office, Java y firma digital",
      "ca": "Ajustos i utilitats per a despatxos: Windows, Office, Java i signatura digital"
    },
    "minutes": { "en": "AutoRecover interval (minutes):", "es": "Intervalo de autoguardado (minutos):", "ca": "Interval de desament autom\u00e0tic (minuts):" },
    "run": { "en": "Run", "es": "Ejecutar", "ca": "Executa" },
    "open": { "en": "Open", "es": "Abrir", "ca": "Obre" },
    "runSelected": { "en": "Run selected", "es": "Ejecutar seleccionadas", "ca": "Executa les seleccionades" },
    "clearSelection": { "en": "Clear selection", "es": "Desmarcar todo", "ca": "Desmarca-ho tot" },
    "copyLog": { "en": "Copy log", "es": "Copiar registro", "ca": "Copia el registre" },
    "openLogs": { "en": "Log folder", "es": "Carpeta de registros", "ca": "Carpeta de registres" },
    "ready": { "en": "Ready.", "es": "Listo.", "ca": "Llest." },
    "busy": {
      "en": "Working... you can keep browsing, do not close the window.",
      "es": "Trabajando... puedes seguir mirando, no cierres la ventana.",
      "ca": "Treballant... pots continuar mirant, no tanquis la finestra."
    },
    "admin": { "en": "Administrator", "es": "Administrador", "ca": "Administrador" },
    "user": { "en": "User", "es": "Usuario", "ca": "Usuari" },
    "language": { "en": "Language", "es": "Idioma", "ca": "Idioma" },
    "requiresAdmin": { "en": "Administrator", "es": "Administrador", "ca": "Administrador" },
    "requiresAdminTip": {
      "en": "Requires an administrator. On a terminal server, the administrator runs it once for all users.",
      "es": "Requiere un administrador. En un servidor de terminales, el administrador lo ejecuta una vez para todos los usuarios.",
      "ca": "Requereix un administrador. En un servidor de terminals, l'administrador ho executa un cop per a tots els usuaris."
    },
    "support": { "en": "support", "es": "soporte", "ca": "suport" },
    "welcome": {
      "en": "Tick the actions and press 'Run selected', or use the button on each row.",
      "es": "Marca las acciones y pulsa 'Ejecutar seleccionadas', o usa el bot\u00f3n de cada fila.",
      "ca": "Marca les accions i prem 'Executa les seleccionades', o fes servir el bot\u00f3 de cada fila."
    }
  },
  "tabs": [
    {
      "title": { "en": "Office", "es": "Office", "ca": "Office" },
      "intro": {
        "en": "AutoRecover settings are saved for your user. If you have administrator rights they are also locked as a policy, so Office cannot undo them. Close Word, Excel and PowerPoint first; the settings apply the next time they are opened.",
        "es": "Los ajustes de autoguardado se guardan para tu usuario. Si tienes permisos de administrador, adem\u00e1s se fijan como directiva y Office no los puede deshacer. Cierra antes Word, Excel y PowerPoint; se aplican al volver a abrirlos.",
        "ca": "Els ajustos de desament autom\u00e0tic es desen per al teu usuari. Si tens permisos d'administrador, a m\u00e9s es fixen com a directiva i Office no els pot desfer. Tanca abans el Word, l'Excel i el PowerPoint; s'apliquen en tornar-los a obrir."
      },
      "minutesInput": 5,
      "sections": [
        {
          "title": { "en": "AutoSave and recovery", "es": "Autoguardado y recuperaci\u00f3n", "ca": "Desament autom\u00e0tic i recuperaci\u00f3" },
          "items": [
            {
              "id": "word-autorecover",
              "label": { "en": "Word AutoRecover every N minutes", "es": "Autoguardado en Word cada N minutos", "ca": "Desament autom\u00e0tic al Word cada N minuts" },
              "description": {
                "en": "Turns on Word AutoRecover and saves the recovery information every N minutes (File > Options > Save).",
                "es": "Activa la Autorrecuperaci\u00f3n de Word y guarda la informaci\u00f3n cada N minutos (Archivo > Opciones > Guardar).",
                "ca": "Activa la Recuperaci\u00f3 autom\u00e0tica del Word i en desa la informaci\u00f3 cada N minuts (Fitxer > Opcions > Desa)."
              },
              "action": "Set-LTWordAutoRecover",
              "usesMinutes": true
            },
            {
              "id": "excel-autorecover",
              "label": { "en": "Excel AutoRecover every N minutes", "es": "Autoguardado en Excel cada N minutos", "ca": "Desament autom\u00e0tic a l'Excel cada N minuts" },
              "description": {
                "en": "Turns on Excel AutoRecover and saves the recovery information every N minutes.",
                "es": "Activa la Autorrecuperaci\u00f3n de Excel y guarda la informaci\u00f3n cada N minutos.",
                "ca": "Activa la Recuperaci\u00f3 autom\u00e0tica de l'Excel i en desa la informaci\u00f3 cada N minuts."
              },
              "action": "Set-LTExcelAutoRecover",
              "usesMinutes": true
            },
            {
              "id": "powerpoint-autorecover",
              "label": { "en": "PowerPoint AutoRecover every N minutes", "es": "Autoguardado en PowerPoint cada N minutos", "ca": "Desament autom\u00e0tic al PowerPoint cada N minuts" },
              "description": {
                "en": "Turns on PowerPoint AutoRecover and saves the recovery information every N minutes.",
                "es": "Activa la Autorrecuperaci\u00f3n de PowerPoint y guarda la informaci\u00f3n cada N minutos.",
                "ca": "Activa la Recuperaci\u00f3 autom\u00e0tica del PowerPoint i en desa la informaci\u00f3 cada N minuts."
              },
              "action": "Set-LTPowerPointAutoRecover",
              "usesMinutes": true
            },
            {
              "id": "office-crash-protection",
              "label": { "en": "Full protection against crashes", "es": "Protecci\u00f3n completa contra cierres inesperados", "ca": "Protecci\u00f3 completa contra tancaments inesperats" },
              "description": {
                "en": "Word, Excel and PowerPoint: AutoRecover every N minutes, keep the last version if closed without saving, and an automatic backup copy (.wbk) of every Word document.",
                "es": "Word, Excel y PowerPoint: autorrecuperaci\u00f3n cada N minutos, conservar la \u00faltima versi\u00f3n si se cierra sin guardar, y copia de seguridad autom\u00e1tica (.wbk) de cada documento de Word.",
                "ca": "Word, Excel i PowerPoint: recuperaci\u00f3 autom\u00e0tica cada N minuts, conservar l'\u00faltima versi\u00f3 si es tanca sense desar, i c\u00f2pia de seguretat autom\u00e0tica (.wbk) de cada document del Word."
              },
              "action": "Enable-LTOfficeCrashProtection",
              "usesMinutes": true
            },
            {
              "id": "office-find-recoverable",
              "label": { "en": "Find recoverable documents", "es": "Buscar documentos recuperables", "ca": "Cerca documents recuperables" },
              "description": {
                "en": "Looks for AutoRecover files, backup copies and unsaved documents from the last 30 days and opens the folder.",
                "es": "Busca archivos de autorrecuperaci\u00f3n, copias de seguridad y documentos sin guardar de los \u00faltimos 30 d\u00edas y abre la carpeta.",
                "ca": "Cerca fitxers de recuperaci\u00f3 autom\u00e0tica, c\u00f2pies de seguretat i documents sense desar dels \u00faltims 30 dies i n'obre la carpeta."
              },
              "action": "Find-LTOfficeRecoverableFiles"
            },
            {
              "id": "office-autorecover-reset",
              "admin": true,
              "label": { "en": "Remove the Lyons Tools AutoRecover settings", "es": "Quitar los ajustes de autoguardado de Lyons Tools", "ca": "Treu els ajustos de desament autom\u00e0tic de Lyons Tools" },
              "description": {
                "en": "Gives control back to File > Options > Save (the settings above are locked and cannot be changed from Office).",
                "es": "Devuelve el control a Archivo > Opciones > Guardar (los ajustes anteriores quedan fijados y no se pueden cambiar desde Office).",
                "ca": "Torna el control a Fitxer > Opcions > Desa (els ajustos anteriors queden fixats i no es poden canviar des d'Office)."
              },
              "action": "Reset-LTOfficeAutoRecover"
            }
          ]
        },
        {
          "title": { "en": "Maintenance", "es": "Mantenimiento", "ca": "Manteniment" },
          "items": [
            {
              "id": "office-info",
              "label": { "en": "Show Office version and AutoRecover settings", "es": "Ver versi\u00f3n de Office y ajustes de autoguardado", "ca": "Mostra la versi\u00f3 d'Office i els ajustos de desament" },
              "description": {
                "en": "Shows the version, the update channel and the current AutoRecover configuration.",
                "es": "Muestra la versi\u00f3n, el canal de actualizaci\u00f3n y la configuraci\u00f3n actual de autorrecuperaci\u00f3n.",
                "ca": "Mostra la versi\u00f3, el canal d'actualitzaci\u00f3 i la configuraci\u00f3 actual de recuperaci\u00f3 autom\u00e0tica."
              },
              "action": "Get-LTOfficeInfo"
            },
            {
              "id": "office-update",
              "admin": true,
              "label": { "en": "Update Office now", "es": "Actualizar Office ahora", "ca": "Actualitza Office ara" },
              "description": {
                "en": "Checks for and installs Microsoft 365 / Office updates.",
                "es": "Busca e instala las actualizaciones de Microsoft 365 / Office.",
                "ca": "Cerca i instal\u00b7la les actualitzacions de Microsoft 365 / Office."
              },
              "action": "Update-LTOffice"
            },
            {
              "id": "office-repair",
              "admin": true,
              "label": { "en": "Office Quick Repair", "es": "Reparaci\u00f3n r\u00e1pida de Office", "ca": "Reparaci\u00f3 r\u00e0pida d'Office" },
              "description": {
                "en": "Repairs Office without an Internet connection. Useful if Word or Excel close by themselves or fail to open. Close all Office programs first.",
                "es": "Repara Office sin conexi\u00f3n a Internet. \u00datil si Word o Excel se cierran solos o fallan al abrir. Cierra todos los programas de Office antes.",
                "ca": "Repara Office sense connexi\u00f3 a Internet. \u00datil si el Word o l'Excel es tanquen sols o no s'obren. Tanca tots els programes d'Office abans."
              },
              "action": "Repair-LTOffice"
            }
          ]
        }
      ]
    },
    {
      "title": { "en": "Digital signature", "es": "Firma digital", "ca": "Signatura digital" },
      "intro": {
        "en": "Tools for FNMT and Consorci AOC digital certificates (idCAT, T-CAT), Autofirma and the Signador.",
        "es": "Herramientas para certificados digitales de la FNMT y del Consorci AOC (idCAT, T-CAT), Autofirma y el Signador.",
        "ca": "Eines per a certificats digitals de la FNMT i del Consorci AOC (idCAT, T-CAT), Autofirma i el Signador."
      },
      "sections": [
        {
          "title": { "en": "Certificates", "es": "Certificados", "ca": "Certificats" },
          "items": [
            {
              "id": "fnmt-configurador",
              "admin": true,
              "label": { "en": "Download and install the FNMT Configurator", "es": "Descargar e instalar el Configurador FNMT", "ca": "Descarrega i instal\u00b7la el Configurador FNMT" },
              "description": {
                "en": "Required to request and download the FNMT individual or representative certificate.",
                "es": "Necesario para solicitar y descargar el certificado de persona f\u00edsica o de representante de la FNMT.",
                "ca": "Necessari per sol\u00b7licitar i descarregar el certificat de persona f\u00edsica o de representant de la FNMT."
              },
              "action": "Install-LTFnmtConfigurator"
            },
            {
              "id": "fnmt-root-certs",
              "label": { "en": "Install FNMT root certificates", "es": "Instalar certificados ra\u00edz de la FNMT", "ca": "Instal\u00b7la els certificats arrel de la FNMT" },
              "description": {
                "en": "Installs the AC Ra\u00edz FNMT-RCM and its intermediate authorities in the Windows store (used by Edge, Chrome and Office).",
                "es": "Instala la AC Ra\u00edz FNMT-RCM y las autoridades intermedias en el almac\u00e9n de Windows (lo usan Edge, Chrome y Office).",
                "ca": "Instal\u00b7la l'AC Ra\u00edz FNMT-RCM i les autoritats interm\u00e8dies al magatzem de Windows (el fan servir Edge, Chrome i Office)."
              },
              "action": "Install-LTFnmtRootCertificates"
            },
            {
              "id": "aoc-root-certs",
              "label": { "en": "Install Consorci AOC root certificates (idCAT, T-CAT)", "es": "Instalar certificados ra\u00edz del Consorci AOC (idCAT, T-CAT)", "ca": "Instal\u00b7la els certificats arrel del Consorci AOC (idCAT, T-CAT)" },
              "description": {
                "en": "Installs the Consorci AOC hierarchy (CA CONSORCI AOC G3, EC-ACC, EC-Ciutadania...) needed for idCAT Certificat, T-CAT and the Generalitat and town hall websites.",
                "es": "Instala la jerarqu\u00eda del Consorci AOC (CA CONSORCI AOC G3, EC-ACC, EC-Ciutadania...) necesaria para el idCAT Certificat, la T-CAT y las webs de la Generalitat y los ayuntamientos.",
                "ca": "Instal\u00b7la la jerarquia del Consorci AOC (CA CONSORCI AOC G3, EC-ACC, EC-Ciutadania...) necess\u00e0ria per a l'idCAT Certificat, la T-CAT i els webs de la Generalitat i dels ajuntaments."
              },
              "action": "Install-LTAocRootCertificates"
            },
            {
              "id": "certs-list",
              "label": { "en": "Show my digital certificates and their expiry", "es": "Ver mis certificados digitales y su caducidad", "ca": "Mostra els meus certificats digitals i la seva caducitat" },
              "description": {
                "en": "Lists the installed signing certificates and warns about those expiring within 60 days.",
                "es": "Lista los certificados personales instalados y avisa de los que caducan en menos de 60 d\u00edas.",
                "ca": "Llista els certificats personals instal\u00b7lats i avisa dels que caduquen en menys de 60 dies."
              },
              "action": "Get-LTPersonalCertificates"
            },
            {
              "id": "certs-manager",
              "label": { "en": "Open the Windows certificate manager", "es": "Abrir el administrador de certificados de Windows", "ca": "Obre l'administrador de certificats de Windows" },
              "description": {
                "en": "To export, import or delete certificates (certmgr.msc).",
                "es": "Para exportar, importar o eliminar certificados (certmgr.msc).",
                "ca": "Per exportar, importar o eliminar certificats (certmgr.msc)."
              },
              "action": "Open-LTCertManager"
            }
          ]
        },
        {
          "title": { "en": "Signing applications", "es": "Aplicaciones de firma", "ca": "Aplicacions de signatura" },
          "items": [
            {
              "id": "autofirma",
              "admin": true,
              "label": { "en": "Download and install Autofirma", "es": "Descargar e instalar Autofirma", "ca": "Descarrega i instal\u00b7la Autofirma" },
              "description": {
                "en": "Spanish Government app for signing on e-government sites (AEAT, Social Security, Justice...).",
                "es": "Aplicaci\u00f3n del Gobierno de Espa\u00f1a para firmar en sedes electr\u00f3nicas (AEAT, Seguridad Social, Justicia...).",
                "ca": "Aplicaci\u00f3 del Govern d'Espanya per signar a les seus electr\u00f2niques (AEAT, Seguretat Social, Just\u00edcia...)."
              },
              "action": "Install-LTAutofirma"
            },
            {
              "id": "signador",
              "label": { "en": "Install the Signador native app (AOC)", "es": "Instalar la aplicaci\u00f3n nativa del Signador (AOC)", "ca": "Instal\u00b7la l'aplicaci\u00f3 nativa del Signador (AOC)" },
              "description": {
                "en": "Consorci AOC app for signing in Generalitat de Catalunya and Catalan town hall procedures, and e-just\u00edcia.cat.",
                "es": "Aplicaci\u00f3n del Consorci AOC para firmar en tr\u00e1mites de la Generalitat de Catalunya, ayuntamientos catalanes y e-just\u00edcia.cat.",
                "ca": "Aplicaci\u00f3 del Consorci AOC per signar en tr\u00e0mits de la Generalitat de Catalunya, ajuntaments catalans i e-just\u00edcia.cat."
              },
              "action": "Install-LTSignador"
            },
            {
              "id": "tcat-middleware",
              "admin": true,
              "label": { "en": "Install the T-CAT card software (Bit4id PKI Manager)", "es": "Instalar el software de la tarjeta T-CAT (Bit4id PKI Manager)", "ca": "Instal\u00b7la el programari de la targeta T-CAT (Bit4id PKI Manager)" },
              "description": {
                "en": "Driver for using the T-CAT smart card with a reader (cards issued since 13/04/2023). Replaces the old SafeSign.",
                "es": "Controlador para usar la T-CAT en tarjeta con un lector (tarjetas emitidas desde el 13/04/2023). Sustituye al antiguo SafeSign.",
                "ca": "Controlador per fer servir la T-CAT en targeta amb un lector (targetes emeses des del 13/04/2023). Substitueix l'antic SafeSign."
              },
              "action": "Install-LTTcatMiddleware"
            }
          ]
        },
        {
          "title": { "en": "Check that it works", "es": "Comprobar que funciona", "ca": "Comprova que funciona" },
          "items": [
            {
              "id": "test-signador",
              "label": { "en": "Test the Signador (Consorci AOC)", "es": "Probar el Signador (Consorci AOC)", "ca": "Prova el Signador (Consorci AOC)" },
              "description": {
                "en": "Official AOC test page: checks that the Signador native app is installed and can sign with your certificate.",
                "es": "P\u00e1gina de prueba oficial del AOC: comprueba que la aplicaci\u00f3n nativa del Signador est\u00e1 instalada y puede firmar con tu certificado.",
                "ca": "P\u00e0gina de prova oficial de l'AOC: comprova que l'aplicaci\u00f3 nativa del Signador est\u00e0 instal\u00b7lada i pot signar amb el teu certificat."
              },
              "url": "https://signador.aoc.cat/signador/testNativa"
            },
            {
              "id": "test-autofirma",
              "label": { "en": "Make a test signature (VALIDe)", "es": "Hacer una firma de prueba (VALIDe)", "ca": "Fes una signatura de prova (VALIDe)" },
              "description": {
                "en": "Spanish Government service: sign any document with your certificate to check that the signing client (Autofirma) works.",
                "es": "Servicio del Gobierno de Espa\u00f1a: firma cualquier documento con tu certificado para comprobar que el cliente de firma (Autofirma) funciona.",
                "ca": "Servei del Govern d'Espanya: signa qualsevol document amb el teu certificat per comprovar que el client de signatura (Autofirma) funciona."
              },
              "url": "https://valide.redsara.es/valide/firmar/ejecutar.html"
            },
            {
              "id": "test-certificate",
              "label": { "en": "Check that my certificate is valid (VALIDe)", "es": "Comprobar que mi certificado es v\u00e1lido (VALIDe)", "ca": "Comprova que el meu certificat \u00e9s v\u00e0lid (VALIDe)" },
              "description": {
                "en": "Validates any certificate (FNMT, idCAT, ACA, DNIe...): not expired, not revoked and issued by a recognised authority.",
                "es": "Valida cualquier certificado (FNMT, idCAT, ACA, DNIe...): que no est\u00e9 caducado ni revocado y que lo emita una autoridad reconocida.",
                "ca": "Valida qualsevol certificat (FNMT, idCAT, ACA, DNIe...): que no estigui caducat ni revocat i que l'emeti una autoritat reconeguda."
              },
              "url": "https://valide.redsara.es/valide/validarCertificado/ejecutar.html"
            },
            {
              "id": "test-fnmt",
              "label": { "en": "Check the status of my FNMT certificate", "es": "Verificar el estado de mi certificado FNMT", "ca": "Verifica l'estat del meu certificat FNMT" },
              "description": {
                "en": "FNMT page to check whether your FNMT individual certificate is valid, revoked or suspended.",
                "es": "P\u00e1gina de la FNMT para comprobar si tu certificado de persona f\u00edsica est\u00e1 vigente, revocado o suspendido.",
                "ca": "P\u00e0gina de la FNMT per comprovar si el teu certificat de persona f\u00edsica \u00e9s vigent, revocat o susp\u00e8s."
              },
              "url": "https://www.sede.fnmt.gob.es/certificados/persona-fisica/verificar-estado"
            }
          ]
        },
        {
          "title": { "en": "Useful links", "es": "Enlaces \u00fatiles", "ca": "Enlla\u00e7os \u00fatils" },
          "items": [
            { "id": "link-fnmt", "label": { "en": "FNMT - Get an individual certificate", "es": "Sede FNMT - Obtener certificado de persona f\u00edsica", "ca": "Seu FNMT - Obtenir el certificat de persona f\u00edsica" }, "url": "https://www.sede.fnmt.gob.es/certificados/persona-fisica" },
            { "id": "link-aeat", "label": { "en": "Spanish Tax Agency e-office (AEAT)", "es": "Sede electr\u00f3nica de la Agencia Tributaria (AEAT)", "ca": "Seu electr\u00f2nica de l'Ag\u00e8ncia Tribut\u00e0ria (AEAT)" }, "url": "https://sede.agenciatributaria.gob.es/" },
            { "id": "link-atc", "label": { "en": "Catalan Tax Agency (ATC)", "es": "Ag\u00e8ncia Tribut\u00e0ria de Catalunya (ATC)", "ca": "Ag\u00e8ncia Tribut\u00e0ria de Catalunya (ATC)" }, "url": "https://atc.gencat.cat/" },
            { "id": "link-valide", "label": { "en": "VALIDe - Validate certificates and signatures", "es": "VALIDe - Validar certificados y firmas", "ca": "VALIDe - Validar certificats i signatures" }, "url": "https://valide.redsara.es/" },
            { "id": "link-idcat-mobil", "label": { "en": "idCAT M\u00f2bil - Sign up or manage", "es": "idCAT M\u00f2bil - Darse de alta o gestionar", "ca": "idCAT M\u00f2bil - Alta i gesti\u00f3" }, "url": "https://idcatmobil.seu.cat/" },
            { "id": "link-enotum", "label": { "en": "e-NOTUM - Electronic notifications from Catalan administrations", "es": "e-NOTUM - Notificaciones electr\u00f3nicas de las administraciones catalanas", "ca": "e-NOTUM - Notificacions electr\u00f2niques de les administracions catalanes" }, "url": "https://www.aoc.cat/es/serveis-aoc/e-notum/" },
            { "id": "link-aoc-support", "label": { "en": "Consorci AOC support (idCAT, T-CAT, Signador)", "es": "Soporte del Consorci AOC (idCAT, T-CAT, Signador)", "ca": "Suport del Consorci AOC (idCAT, T-CAT, Signador)" }, "url": "https://suport.aoc.cat/" }
          ]
        }
      ]
    },
    {
      "title": { "en": "Legal", "es": "Abogac\u00eda", "ca": "Advocacia" },
      "intro": {
        "en": "LexNET and e-just\u00edcia.cat require a smart card certificate (ACA, DNIe, FNMT or idCAT/T-CAT), Autofirma (LexNET) and the Consorci AOC Signador (e-just\u00edcia.cat). Autofirma and the Signador are in the Digital signature tab.",
        "es": "Para LexNET y e-just\u00edcia.cat hace falta un certificado en tarjeta (ACA, DNIe, FNMT o idCAT/T-CAT), Autofirma (LexNET) y el Signador del Consorci AOC (e-just\u00edcia.cat). Autofirma y el Signador est\u00e1n en la pesta\u00f1a Firma digital.",
        "ca": "Per a LexNET i e-just\u00edcia.cat cal un certificat en targeta (ACA, DNIe, FNMT o idCAT/T-CAT), Autofirma (LexNET) i el Signador del Consorci AOC (e-just\u00edcia.cat). Autofirma i el Signador s\u00f3n a la pestanya Signatura digital."
      },
      "sections": [
        {
          "title": { "en": "ACA certificate (Spanish Bar)", "es": "Certificado ACA (Abogac\u00eda)", "ca": "Certificat ACA (Advocacia)" },
          "items": [
            {
              "id": "aca-middleware",
              "admin": true,
              "label": { "en": "Install the ACA card software (Bit4id)", "es": "Instalar el software de la tarjeta ACA (Bit4id)", "ca": "Instal\u00b7la el programari de la targeta ACA (Bit4id)" },
              "description": {
                "en": "Official software from the Consejo General de la Abogac\u00eda to use the bar card with the ACA certificate in a card reader.",
                "es": "Software oficial del Consejo General de la Abogac\u00eda para usar el carn\u00e9 colegial con certificado ACA en un lector de tarjetas.",
                "ca": "Programari oficial del Consejo General de la Abogac\u00eda per fer servir el carnet col\u00b7legial amb certificat ACA en un lector de targetes."
              },
              "action": "Install-LTAcaMiddleware"
            },
            {
              "id": "aca-root-certs",
              "label": { "en": "Install ACA root certificates", "es": "Instalar certificados ra\u00edz de la ACA", "ca": "Instal\u00b7la els certificats arrel de l'ACA" },
              "description": {
                "en": "Installs ACA ROOT 2 and the ACA 1 and ACA 2 subordinates so Windows and the court websites recognise the lawyer certificate.",
                "es": "Instala ACA ROOT 2 y las subordinadas ACA 1 y ACA 2 para que Windows y las sedes judiciales reconozcan el certificado de abogado.",
                "ca": "Instal\u00b7la ACA ROOT 2 i les subordinades ACA 1 i ACA 2 perqu\u00e8 Windows i les seus judicials reconeguin el certificat d'advocat."
              },
              "action": "Install-LTAcaRootCertificates"
            }
          ]
        },
        {
          "title": { "en": "Justice", "es": "Justicia", "ca": "Just\u00edcia" },
          "items": [
            { "id": "link-lexnet", "label": { "en": "LexNET (Justice)", "es": "LexNET (Justicia)", "ca": "LexNET (Just\u00edcia)" }, "url": "https://lexnet.justicia.es/" },
            { "id": "link-ejcat", "label": { "en": "e-just\u00edcia.cat - Professional extranet", "es": "e-just\u00edcia.cat - Extranet del profesional", "ca": "e-just\u00edcia.cat - Extranet del professional" }, "url": "https://ejcat.justicia.gencat.cat/IAP/" },
            { "id": "link-seujudicial", "label": { "en": "Catalan judicial e-office - Professionals", "es": "Seu judicial electr\u00f2nica de Catalunya - Profesionales", "ca": "Seu judicial electr\u00f2nica de Catalunya - Professionals" }, "url": "https://seujudicial.gencat.cat/ca/que_cal_fer/Soc-un-professional-del-dret/ejusticia/" },
            { "id": "link-signador-test", "label": { "en": "Check that the Signador works", "es": "Comprobar que el Signador funciona", "ca": "Comprova que el Signador funciona" }, "url": "https://signador.aoc.cat/signador/testNativa" },
            { "id": "link-acaplus", "label": { "en": "ACA Plus - Spanish Bar certificates", "es": "ACA Plus - Certificados de la Abogac\u00eda", "ca": "ACA Plus - Certificats de l'Advocacia" }, "url": "https://www.abogacia.es/site/acaplus/" },
            { "id": "link-dnie", "label": { "en": "Electronic ID card (DNIe) - Software and drivers", "es": "DNI electr\u00f3nico - Software y controladores", "ca": "DNI electr\u00f2nic - Programari i controladors" }, "url": "https://www.dnielectronico.es/PortalDNIe/PRF1_Cons02.action?pag=REF_1101" }
          ]
        }
      ]
    },
    {
      "title": { "en": "Java", "es": "Java", "ca": "Java" },
      "sections": [
        {
          "title": { "en": "Java", "es": "Java", "ca": "Java" },
          "items": [
            {
              "id": "java-check",
              "label": { "en": "Check the Java version", "es": "Comprobar la versi\u00f3n de Java", "ca": "Comprova la versi\u00f3 de Java" },
              "description": {
                "en": "Shows the Java used by the system, every installed version and the latest available version.",
                "es": "Muestra el Java que usa el sistema, todas las versiones instaladas y la \u00faltima versi\u00f3n disponible.",
                "ca": "Mostra el Java que fa servir el sistema, totes les versions instal\u00b7lades i l'\u00faltima versi\u00f3 disponible."
              },
              "action": "Get-LTJavaInfo"
            },
            {
              "id": "java-install-temurin",
              "admin": true,
              "label": { "en": "Download and install the latest LTS Java (Temurin)", "es": "Descargar e instalar la \u00faltima versi\u00f3n LTS de Java (Temurin)", "ca": "Descarrega i instal\u00b7la l'\u00faltima versi\u00f3 LTS de Java (Temurin)" },
              "description": {
                "en": "Free, up-to-date Java (Eclipse Adoptium OpenJDK). Sets JAVA_HOME and opens .jar files.",
                "es": "Java gratuito y actualizado (OpenJDK de Eclipse Adoptium). Configura JAVA_HOME y abre los archivos .jar.",
                "ca": "Java gratu\u00eft i actualitzat (OpenJDK d'Eclipse Adoptium). Configura JAVA_HOME i obre els fitxers .jar."
              },
              "action": "Install-LTJavaTemurin"
            },
            {
              "id": "java-install-oracle8",
              "admin": true,
              "label": { "en": "Download and install Oracle Java 8 (java.com)", "es": "Descargar e instalar Java 8 de Oracle (java.com)", "ca": "Descarrega i instal\u00b7la Java 8 d'Oracle (java.com)" },
              "description": {
                "en": "Only for older applications that specifically require Oracle Java.",
                "es": "Solo para aplicaciones antiguas que piden espec\u00edficamente Java de Oracle.",
                "ca": "Nom\u00e9s per a aplicacions antigues que demanen espec\u00edficament el Java d'Oracle."
              },
              "action": "Install-LTJavaOracle8"
            },
            {
              "id": "java-clear-cache",
              "label": { "en": "Clear the Java cache", "es": "Vaciar la cach\u00e9 de Java", "ca": "Buida la mem\u00f2ria cau de Java" },
              "description": {
                "en": "Fixes downloaded Java applications that do not start or use an old version.",
                "es": "Soluciona errores de aplicaciones Java descargadas que no arrancan o usan una versi\u00f3n antigua.",
                "ca": "Soluciona errors d'aplicacions Java descarregades que no arrenquen o fan servir una versi\u00f3 antiga."
              },
              "action": "Clear-LTJavaCache"
            }
          ]
        }
      ]
    },
    {
      "title": { "en": "Windows", "es": "Windows", "ca": "Windows" },
      "sections": [
        {
          "title": { "en": "Settings", "es": "Ajustes", "ca": "Ajustos" },
          "items": [
            {
              "id": "win-file-extensions",
              "label": { "en": "Show file extensions", "es": "Mostrar las extensiones de archivo", "ca": "Mostra les extensions dels fitxers" },
              "description": {
                "en": "Shows .pdf, .docx, .exe... Helps spot fake attachments such as \"invoice.pdf.exe\". Restarts Explorer.",
                "es": "Muestra .pdf, .docx, .exe... Ayuda a detectar adjuntos falsos como \"factura.pdf.exe\". Reinicia el Explorador.",
                "ca": "Mostra .pdf, .docx, .exe... Ajuda a detectar adjunts falsos com \"factura.pdf.exe\". Reinicia l'Explorador."
              },
              "action": "Enable-LTFileExtensions"
            },
            {
              "id": "win-clipboard-history",
              "label": { "en": "Turn on clipboard history (Windows + V)", "es": "Activar el historial del portapapeles (Windows + V)", "ca": "Activa l'historial del porta-retalls (Windows + V)" },
              "description": {
                "en": "Lets you paste any of the most recently copied texts or images.",
                "es": "Permite pegar cualquiera de los \u00faltimos textos o im\u00e1genes copiados.",
                "ca": "Permet enganxar qualsevol dels \u00faltims textos o imatges copiats."
              },
              "action": "Enable-LTClipboardHistory"
            }
          ]
        },
        {
          "title": { "en": "PDF", "es": "PDF", "ca": "PDF" },
          "items": [
            {
              "id": "adobe-reader",
              "admin": true,
              "label": { "en": "Install Adobe Acrobat Reader", "es": "Instalar Adobe Acrobat Reader", "ca": "Instal\u00b7la Adobe Acrobat Reader" },
              "description": {
                "en": "To open court notifications, tax forms and signed documents and validate their signatures.",
                "es": "Para abrir notificaciones, modelos tributarios y documentos firmados y validar sus firmas.",
                "ca": "Per obrir notificacions, models tributaris i documents signats i validar-ne les signatures."
              },
              "action": "Install-LTAdobeReader"
            },
            {
              "id": "pdf-default-adobe",
              "label": { "en": "Make Adobe Reader the default PDF app", "es": "Hacer Adobe Reader la aplicaci\u00f3n predeterminada para PDF", "ca": "Fes d'Adobe Reader l'aplicaci\u00f3 predeterminada per als PDF" },
              "description": {
                "en": "Opens Windows' 'Open with' window: choose Adobe Acrobat and press OK, and it becomes the default for PDF files. Per user.",
                "es": "Abre la ventana 'Abrir con' de Windows: elige Adobe Acrobat y pulsa Aceptar, y queda como predeterminada para los PDF. Por usuario.",
                "ca": "Obre la finestra 'Obre amb' de Windows: tria Adobe Acrobat i prem D'acord, i queda com a predeterminada per als PDF. Per usuari."
              },
              "action": "Set-LTAdobeDefaultPdf"
            },
            {
              "id": "pdf-test",
              "label": { "en": "Test: open a PDF with the default app", "es": "Prueba: abrir un PDF con la aplicaci\u00f3n predeterminada", "ca": "Prova: obre un PDF amb l'aplicaci\u00f3 predeterminada" },
              "description": {
                "en": "Shows which app opens PDF files and opens a test PDF with it.",
                "es": "Muestra qu\u00e9 aplicaci\u00f3n abre los PDF y abre un PDF de prueba con ella.",
                "ca": "Mostra quina aplicaci\u00f3 obre els PDF i hi obre un PDF de prova."
              },
              "action": "Open-LTPdfTest"
            },
            {
              "id": "pdf-browser-download",
              "admin": true,
              "label": { "en": "Download PDFs instead of opening them in Edge, Chrome or Firefox", "es": "Descargar los PDF en lugar de abrirlos en Edge, Chrome o Firefox", "ca": "Descarrega els PDF en lloc d'obrir-los a Edge, Chrome o Firefox" },
              "description": {
                "en": "Turns off the browsers' built-in PDF viewer: PDFs are downloaded and opened with the default PDF app. For all users of the computer.",
                "es": "Desactiva el visor de PDF de los navegadores: los PDF se descargan y se abren con la aplicaci\u00f3n de PDF predeterminada. Para todos los usuarios del equipo.",
                "ca": "Desactiva el visor de PDF dels navegadors: els PDF es descarreguen i s'obren amb l'aplicaci\u00f3 de PDF predeterminada. Per a tots els usuaris de l'equip."
              },
              "action": "Set-LTBrowserPdfDownload"
            },
            {
              "id": "pdf-browser-reset",
              "admin": true,
              "label": { "en": "Let browsers open PDFs again", "es": "Volver a abrir los PDF en el navegador", "ca": "Torna a obrir els PDF al navegador" },
              "description": {
                "en": "Undoes the previous action.",
                "es": "Deshace la acci\u00f3n anterior.",
                "ca": "Desf\u00e0 l'acci\u00f3 anterior."
              },
              "action": "Reset-LTBrowserPdfDownload"
            }
          ]
        },
        {
          "title": { "en": "Default browser", "es": "Navegador predeterminado", "ca": "Navegador predeterminat" },
          "items": [
            {
              "id": "browser-default-chrome",
              "label": { "en": "Make Google Chrome the default browser", "es": "Hacer Google Chrome el navegador predeterminado", "ca": "Fes de Google Chrome el navegador predeterminat" },
              "description": {
                "en": "Installs Chrome if needed (administrator). Opens Windows Settings to confirm the choice and checks that it changed. Per user.",
                "es": "Instala Chrome si hace falta (administrador). Abre Configuraci\u00f3n de Windows para confirmar la elecci\u00f3n y comprueba que ha cambiado. Por usuario.",
                "ca": "Instal\u00b7la Chrome si cal (administrador). Obre Configuraci\u00f3 de Windows per confirmar l'elecci\u00f3 i comprova que ha canviat. Per usuari."
              },
              "action": "Set-LTDefaultBrowserChrome"
            },
            {
              "id": "browser-default-edge",
              "label": { "en": "Make Microsoft Edge the default browser", "es": "Hacer Microsoft Edge el navegador predeterminado", "ca": "Fes de Microsoft Edge el navegador predeterminat" },
              "description": {
                "en": "Opens Windows Settings to confirm the choice and checks that it changed. Per user.",
                "es": "Abre Configuraci\u00f3n de Windows para confirmar la elecci\u00f3n y comprueba que ha cambiado. Por usuario.",
                "ca": "Obre Configuraci\u00f3 de Windows per confirmar l'elecci\u00f3 i comprova que ha canviat. Per usuari."
              },
              "action": "Set-LTDefaultBrowserEdge"
            },
            {
              "id": "browser-default-firefox",
              "label": { "en": "Make Mozilla Firefox the default browser", "es": "Hacer Mozilla Firefox el navegador predeterminado", "ca": "Fes de Mozilla Firefox el navegador predeterminat" },
              "description": {
                "en": "Installs Firefox if needed (administrator). Firefox usually sets itself; otherwise Windows asks you to confirm. Per user.",
                "es": "Instala Firefox si hace falta (administrador). Firefox normalmente se configura solo; si no, Windows pide confirmarlo. Por usuario.",
                "ca": "Instal\u00b7la Firefox si cal (administrador). Firefox normalment es configura sol; si no, Windows demana confirmar-ho. Per usuari."
              },
              "action": "Set-LTDefaultBrowserFirefox"
            },
            {
              "id": "browser-default-test",
              "label": { "en": "Test: open ehtu.com in the default browser", "es": "Prueba: abrir ehtu.com con el navegador predeterminado", "ca": "Prova: obre ehtu.com amb el navegador predeterminat" },
              "description": {
                "en": "Shows which browser is the default and opens the ehtu.com website with it.",
                "es": "Muestra cu\u00e1l es el navegador predeterminado y abre la web de ehtu.com con \u00e9l.",
                "ca": "Mostra quin \u00e9s el navegador predeterminat i hi obre el web d'ehtu.com."
              },
              "action": "Open-LTDefaultBrowserTest"
            }
          ]
        },
        {
          "title": { "en": "Utilities", "es": "Utilidades", "ca": "Utilitats" },
          "items": [
            {
              "id": "win-report",
              "label": { "en": "Computer report for support", "es": "Informe del equipo para soporte", "ca": "Informe de l'equip per al suport" },
              "description": {
                "en": "Collects Windows, Office, Java, signing apps and certificates, and copies it to the clipboard to send to ehtu.com.",
                "es": "Recoge Windows, Office, Java, aplicaciones de firma y certificados, y lo copia al portapapeles para enviarlo a ehtu.com.",
                "ca": "Recull Windows, Office, Java, aplicacions de signatura i certificats, i ho copia al porta-retalls per enviar-ho a ehtu.com."
              },
              "action": "Get-LTSystemReport"
            },
            {
              "id": "win-quick-assist",
              "label": { "en": "Remote support (Windows Quick Assist)", "es": "Asistencia remota (Asistencia r\u00e1pida de Windows)", "ca": "Assist\u00e8ncia remota (Assist\u00e8ncia r\u00e0pida de Windows)" },
              "description": {
                "en": "Opens Quick Assist so the support technician can connect to your computer.",
                "es": "Abre Asistencia r\u00e1pida para que el t\u00e9cnico de soporte se conecte a tu equipo.",
                "ca": "Obre l'Assist\u00e8ncia r\u00e0pida perqu\u00e8 el t\u00e8cnic de suport es connecti al teu equip."
              },
              "action": "Start-LTQuickAssist"
            },
            {
              "id": "win-clean-temp",
              "label": { "en": "Clean temporary files", "es": "Limpiar archivos temporales", "ca": "Neteja els fitxers temporals" },
              "description": {
                "en": "Deletes the user's temporary files and the Internet cache.",
                "es": "Elimina archivos temporales del usuario y la cach\u00e9 de Internet.",
                "ca": "Elimina els fitxers temporals de l'usuari i la mem\u00f2ria cau d'Internet."
              },
              "action": "Clear-LTTempFiles"
            },
            {
              "id": "win-flush-dns",
              "admin": true,
              "label": { "en": "Flush the DNS cache", "es": "Vaciar la cach\u00e9 DNS", "ca": "Buida la mem\u00f2ria cau DNS" },
              "description": {
                "en": "Useful when a website or e-office does not load here but works on other computers.",
                "es": "\u00datil cuando una web o sede electr\u00f3nica no carga y en otros equipos s\u00ed.",
                "ca": "\u00datil quan un web o una seu electr\u00f2nica no carrega i en altres equips s\u00ed."
              },
              "action": "Clear-LTDnsCache"
            },
            {
              "id": "win-restart-explorer",
              "label": { "en": "Restart Windows Explorer", "es": "Reiniciar el Explorador de Windows", "ca": "Reinicia l'Explorador de Windows" },
              "description": {
                "en": "Fixes a frozen taskbar or desktop.",
                "es": "Soluciona la barra de tareas o el escritorio bloqueados.",
                "ca": "Soluciona la barra de tasques o l'escriptori bloquejats."
              },
              "action": "Restart-LTExplorer"
            },
            {
              "id": "win-update",
              "label": { "en": "Open Windows Update", "es": "Abrir Windows Update", "ca": "Obre Windows Update" },
              "description": {
                "en": "Opens the Windows update settings.",
                "es": "Abre la configuraci\u00f3n de actualizaciones de Windows.",
                "ca": "Obre la configuraci\u00f3 d'actualitzacions de Windows."
              },
              "action": "Open-LTWindowsUpdate"
            }
          ]
        }
      ]
    }
  ]
}

'@

$LTXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Lyons Tools __LT_VERSION__ &#x00B7; ehtu.com"
        Width="980" Height="760" MinWidth="720" MinHeight="520"
        WindowStartupLocation="CenterScreen"
        Background="#F4F6F9" FontFamily="Segoe UI" FontSize="13">
    <Window.Resources>
        <SolidColorBrush x:Key="Accent" Color="#1F4E79"/>
        <SolidColorBrush x:Key="AccentHover" Color="#2E6AA3"/>
        <SolidColorBrush x:Key="Ink" Color="#1B2430"/>
        <SolidColorBrush x:Key="Muted" Color="#5B6675"/>
        <SolidColorBrush x:Key="Line" Color="#DDE3EA"/>

        <Style x:Key="BaseButton" TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="{StaticResource Accent}"/>
            <Setter Property="Padding" Value="16,7"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="5"
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.88"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="RunButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
            <Setter Property="MinWidth" Value="96"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="12,0,0,0"/>
        </Style>
        <Style x:Key="LinkButton" TargetType="Button" BasedOn="{StaticResource RunButton}">
            <Setter Property="Background" Value="White"/>
            <Setter Property="Foreground" Value="{StaticResource Accent}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style x:Key="GhostButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource Accent}"/>
            <Setter Property="FontWeight" Value="Normal"/>
            <Setter Property="Padding" Value="10,7"/>
        </Style>

        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="Padding" Value="14,10"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
        </Style>
        <Style x:Key="SectionHeader" TargetType="TextBlock">
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{StaticResource Accent}"/>
            <Setter Property="Margin" Value="0,14,0,8"/>
        </Style>
        <Style x:Key="IntroText" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource Muted}"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
            <Setter Property="Margin" Value="0,4,0,4"/>
        </Style>
        <Style x:Key="FieldLabel" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource Ink}"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="0,0,10,0"/>
        </Style>
        <Style x:Key="MinutesBox" TargetType="TextBox">
            <Setter Property="Width" Value="56"/>
            <Setter Property="Padding" Value="6,4"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
            <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
        </Style>
        <Style x:Key="ItemTitle" TargetType="TextBlock">
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{StaticResource Ink}"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
        </Style>
        <Style x:Key="ItemDescription" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource Muted}"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
            <Setter Property="Margin" Value="0,2,0,0"/>
        </Style>
        <Style x:Key="AdminTag" TargetType="Border">
            <Setter Property="Background" Value="#FFF4E5"/>
            <Setter Property="BorderBrush" Value="#E8B86D"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="7,0"/>
            <Setter Property="Margin" Value="8,1,0,0"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
        </Style>
        <Style x:Key="AdminTagText" TargetType="TextBlock">
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Foreground" Value="#8A5A00"/>
        </Style>
        <Style x:Key="ItemCheck" TargetType="CheckBox">
            <Setter Property="VerticalContentAlignment" Value="Top"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <Style TargetType="TabItem">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="Bd" Padding="18,10" Margin="0,0,2,0" Background="Transparent"
                                BorderThickness="0,0,0,3" BorderBrush="Transparent" Cursor="Hand">
                            <ContentPresenter ContentSource="Header" TextElement.FontSize="14"
                                              TextElement.Foreground="{StaticResource Muted}" x:Name="Hd"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/>
                                <Setter TargetName="Hd" Property="TextElement.Foreground" Value="{StaticResource Accent}"/>
                                <Setter TargetName="Hd" Property="TextElement.FontWeight" Value="SemiBold"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#E8EEF5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="150"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="{StaticResource Accent}" Padding="20,14">
            <DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock x:Name="LangLabel" Foreground="#D6E4F0" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <ComboBox x:Name="LangBox" Width="96" Margin="0,0,14,0" VerticalAlignment="Center"/>
                    <Border Background="#33FFFFFF" CornerRadius="10" Padding="10,3" Margin="0,0,10,0">
                        <TextBlock x:Name="AdminBadge" Foreground="White" FontSize="12"/>
                    </Border>
                    <Button x:Name="Website" Content="ehtu.com" Style="{StaticResource GhostButton}" Foreground="White"/>
                </StackPanel>
                <StackPanel>
                    <TextBlock Text="Lyons Tools" Foreground="White" FontSize="22" FontWeight="Bold"/>
                    <TextBlock x:Name="Subtitle" Foreground="#D6E4F0" TextWrapping="Wrap"/>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- Tabs (filled from config/tools.json) -->
        <TabControl x:Name="Tabs" Grid.Row="1" Background="Transparent" BorderThickness="0,1,0,0"
                    BorderBrush="{StaticResource Line}" Padding="0" Margin="12,8,12,0"/>

        <!-- Action bar -->
        <Border Grid.Row="2" Background="White" BorderBrush="{StaticResource Line}" BorderThickness="0,1" Padding="16,8">
            <DockPanel>
                <Button x:Name="RunSelected" DockPanel.Dock="Right" Style="{StaticResource BaseButton}"/>
                <Button x:Name="ClearSelection" DockPanel.Dock="Right" Style="{StaticResource GhostButton}" Margin="0,0,8,0"/>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <ProgressBar x:Name="BusyBar" Width="90" Height="6" IsIndeterminate="True" Visibility="Collapsed" Margin="0,0,10,0"/>
                    <TextBlock x:Name="StatusText" Foreground="{StaticResource Muted}" VerticalAlignment="Center"/>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- Log -->
        <TextBox x:Name="LogBox" Grid.Row="3" IsReadOnly="True" TextWrapping="NoWrap"
                 VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                 FontFamily="Consolas" FontSize="12" Background="#0F1720" Foreground="#D7DEE7"
                 BorderThickness="0" Padding="10,6"/>

        <!-- Footer -->
        <Border Grid.Row="4" Background="#0F1720" Padding="12,2,12,6">
            <DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                    <Button x:Name="CopyLog" Style="{StaticResource GhostButton}" Foreground="#9FB3C8"/>
                    <Button x:Name="OpenLogs" Style="{StaticResource GhostButton}" Foreground="#9FB3C8"/>
                </StackPanel>
                <TextBlock x:Name="FooterText" Foreground="#6B7C8F" FontSize="11" VerticalAlignment="Center"/>
            </DockPanel>
        </Border>
    </Grid>
</Window>

'@

#region Entry point -------------------------------------------------------------

$LT.Config = $LTConfigJson | ConvertFrom-Json
$LT.Items = @{}
foreach ($tab in $LT.Config.tabs) {
    foreach ($section in $tab.sections) {
        foreach ($item in $section.items) { $LT.Items[$item.id] = $item }
    }
}
$LT.CanElevate = Test-LTCanElevate

$logDir = Join-Path $LT.DataDir 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$LT.LogDir = $logDir
$LT.LogFile = Join-Path $logDir ("{0:yyyy-MM-dd}.log" -f (Get-Date))

if ($List) {
    $LT.Items.Values | Sort-Object id | Format-Table @{ n = 'ID'; e = { $_.id } },
    @{ n = 'Admin'; e = { if ($_.admin) { 'x' } } },
    @{ n = (Get-LTString 'Action' "Acci$([char]0x00F3)n" "Acci$([char]0x00F3)"); e = { Get-LTString $_.label } } -AutoSize
    return
}

if ($Run) {
    Write-LTLog "Lyons Tools $($LT.Version) - command line mode" "Lyons Tools $($LT.Version) - modo sin interfaz" "Lyons Tools $($LT.Version) - mode sense interf$([char]0x00ED)cie" -Level Step
    foreach ($id in ($Run -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $item = $LT.Items[$id]
        if (-not $item) { Write-LTLog "Unknown action: $id (see -List)" "Acci$([char]0x00F3)n desconocida: $id (usa -List)" "Acci$([char]0x00F3) desconeguda: $id (fes servir -List)" -Level Error; continue }
        Write-LTLog (Get-LTString $item.label) -Level Step
        try { Invoke-LTItem -Item $item -Minutes $Minutes }
        catch { Write-LTLog $_.Exception.Message -Level Error }
    }
    return
}

# WPF needs an STA thread. Windows PowerShell is STA by default; pwsh may not be.
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-Host 'Restarting Lyons Tools in STA mode...'
    $langArg = if ($Lang) { " -Lang $Lang" } else { '' }
    if ($PSCommandPath) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"$langArg"
    }
    else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -Command `"& ([scriptblock]::Create((irm '$($LT.SourceUrl)')))$langArg`""
    }
    return
}

function Get-LTUiString([string]$Key) { Get-LTString $LT.Config.strings.$Key }

function Save-LTSettings {
    try {
        if (-not (Test-Path $LT.DataDir)) { New-Item -ItemType Directory -Path $LT.DataDir -Force | Out-Null }
        [pscustomobject]@{ lang = $LT.Lang } | ConvertTo-Json | Set-Content -LiteralPath $LT.SettingsFile -Encoding UTF8
    }
    catch { }
}

function Start-LTJob {
    <# Runs a list of items in a background runspace so the window never freezes. #>
    param([object[]]$Items, [int]$Minutes)

    if ($LT.Busy) { Write-LTLog "Wait for the current task to finish." "Espera a que termine la tarea en curso." "Espera que acabi la tasca en curs." -Level Warn; return }
    $LT.Busy = $true

    $iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.Variables.Add([Management.Automation.Runspaces.SessionStateVariableEntry]::new('LT', $LT, $null))
    foreach ($name in $LT.FunctionNames) {
        $iss.Commands.Add([Management.Automation.Runspaces.SessionStateFunctionEntry]::new($name, (Get-Item "function:$name").Definition))
    }
    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.ApartmentState = 'STA'   # COM (Office) and the clipboard need STA
    $rs.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
            param($Items, $Minutes)
            try {
                foreach ($item in $Items) {
                    Write-LTLog (Get-LTString $item.label) -Level Step
                    try { Invoke-LTItem -Item $item -Minutes $Minutes }
                    catch { Write-LTLog $_.Exception.Message -Level Error }
                }
                Write-LTLog "Finished." "Terminado." "Acabat." -Level Ok
            }
            finally { $LT.Busy = $false }
        }).AddArgument($Items).AddArgument($Minutes)
    $LT.Job = @{ PowerShell = $ps; Runspace = $rs; Handle = $ps.BeginInvoke() }
}

function Get-LTMinutes {
    $value = 0
    if (-not $LT.MinutesBox -or -not [int]::TryParse($LT.MinutesBox.Text.Trim(), [ref]$value) -or $value -lt 1 -or $value -gt 120) {
        return $null
    }
    $value
}

function Invoke-LTSelection {
    param([string[]]$Ids)
    $items = @($Ids | ForEach-Object { $LT.Items[$_] } | Where-Object { $_ })
    if (-not $items.Count) { Write-LTLog "No action is selected." "No hay ninguna acci$([char]0x00F3)n seleccionada." "No hi ha cap acci$([char]0x00F3) seleccionada." -Level Warn; return }
    $minutes = 5
    if ($items | Where-Object usesMinutes) {
        $minutes = Get-LTMinutes
        if (-not $minutes) { Write-LTLog "Enter a number of minutes between 1 and 120." "Indica un n$([char]0x00FA)mero de minutos entre 1 y 120." "Indica un nombre de minuts entre 1 i 120." -Level Error; return }
    }
    Start-LTJob -Items $items -Minutes $minutes
}

function New-LTTextBlock([string]$Text, [string]$Style) {
    $tb = [Windows.Controls.TextBlock]::new()
    $tb.Text = $Text
    $tb.Style = $LT.Window.FindResource($Style)
    $tb
}

function Test-LTItemAllowed($Item) { -not $Item.admin -or $LT.CanElevate }

function Add-LTTabs {
    $tabs = $LT.Window.FindName('Tabs')
    $selected = [Math]::Max(0, $tabs.SelectedIndex)
    $minutes = if ($LT.MinutesBox) { $LT.MinutesBox.Text } else { $null }
    $tabs.Items.Clear()
    $LT.CheckBoxes = @{}
    $LT.ItemButtons = [Collections.Generic.List[object]]::new()
    $LT.MinutesBox = $null
    $runText = Get-LTUiString 'run'
    $openText = Get-LTUiString 'open'
    $adminText = Get-LTUiString 'requiresAdmin'
    $adminTip = Get-LTUiString 'requiresAdminTip'

    foreach ($tab in $LT.Config.tabs) {
        $panel = [Windows.Controls.StackPanel]::new()
        $panel.Margin = '16,8,16,16'

        if ($tab.intro) { [void]$panel.Children.Add((New-LTTextBlock (Get-LTString $tab.intro) 'IntroText')) }

        if ($tab.minutesInput) {
            $row = [Windows.Controls.StackPanel]::new()
            $row.Orientation = 'Horizontal'
            $row.Margin = '0,4,0,8'
            [void]$row.Children.Add((New-LTTextBlock (Get-LTUiString 'minutes') 'FieldLabel'))
            $box = [Windows.Controls.TextBox]::new()
            $box.Text = if ($minutes) { $minutes } else { [string]$tab.minutesInput }
            $box.Style = $LT.Window.FindResource('MinutesBox')
            [void]$row.Children.Add($box)
            $LT.MinutesBox = $box
            [void]$panel.Children.Add($row)
        }

        foreach ($section in $tab.sections) {
            [void]$panel.Children.Add((New-LTTextBlock (Get-LTString $section.title) 'SectionHeader'))
            foreach ($item in $section.items) {
                $allowed = Test-LTItemAllowed $item
                $card = [Windows.Controls.Border]::new()
                $card.Style = $LT.Window.FindResource('Card')
                $grid = [Windows.Controls.Grid]::new()
                $c0 = [Windows.Controls.ColumnDefinition]::new(); $c0.Width = '*'
                $c1 = [Windows.Controls.ColumnDefinition]::new(); $c1.Width = 'Auto'
                $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)

                $text = [Windows.Controls.StackPanel]::new()
                $titleRow = [Windows.Controls.WrapPanel]::new()
                [void]$titleRow.Children.Add((New-LTTextBlock (Get-LTString $item.label) 'ItemTitle'))
                if ($item.admin) {
                    $tag = [Windows.Controls.Border]::new()
                    $tag.Style = $LT.Window.FindResource('AdminTag')
                    $tag.Child = New-LTTextBlock $adminText 'AdminTagText'
                    $tag.ToolTip = $adminTip
                    [void]$titleRow.Children.Add($tag)
                }
                [void]$text.Children.Add($titleRow)
                if ($item.description) { [void]$text.Children.Add((New-LTTextBlock (Get-LTString $item.description) 'ItemDescription')) }

                if ($item.url) {
                    $text.Margin = '22,0,0,0'
                    [void]$grid.Children.Add($text)
                }
                else {
                    $cb = [Windows.Controls.CheckBox]::new()
                    $cb.Content = $text
                    $cb.Tag = $item.id
                    $cb.Style = $LT.Window.FindResource('ItemCheck')
                    $cb.IsEnabled = $allowed
                    if (-not $allowed) { $cb.ToolTip = $adminTip; [Windows.Controls.ToolTipService]::SetShowOnDisabled($cb, $true) }
                    $LT.CheckBoxes[$item.id] = $cb
                    [void]$grid.Children.Add($cb)
                }

                $btn = [Windows.Controls.Button]::new()
                $btn.Content = if ($item.url) { $openText } else { $runText }
                $btn.Tag = $item.id
                $btn.Style = $LT.Window.FindResource($(if ($item.url) { 'LinkButton' } else { 'RunButton' }))
                $btn.IsEnabled = $allowed -and -not $LT.Busy
                if (-not $allowed) { $btn.ToolTip = $adminTip; [Windows.Controls.ToolTipService]::SetShowOnDisabled($btn, $true) }
                [Windows.Controls.Grid]::SetColumn($btn, 1)
                $btn.Add_Click({ Invoke-LTSelection -Ids @($this.Tag) })
                [void]$grid.Children.Add($btn)
                $LT.ItemButtons.Add($btn)

                $card.Child = $grid
                [void]$panel.Children.Add($card)
            }
        }

        $scroll = [Windows.Controls.ScrollViewer]::new()
        $scroll.VerticalScrollBarVisibility = 'Auto'
        $scroll.Content = $panel
        $ti = [Windows.Controls.TabItem]::new()
        $ti.Header = Get-LTString $tab.title
        $ti.Content = $scroll
        [void]$tabs.Items.Add($ti)
    }
    $tabs.SelectedIndex = [Math]::Min($selected, $tabs.Items.Count - 1)
}

function Update-LTTexts {
    <# Static texts of the window in the current language. #>
    $w = $LT.Window
    $w.FindName('Subtitle').Text = Get-LTUiString 'subtitle'
    $w.FindName('RunSelected').Content = Get-LTUiString 'runSelected'
    $w.FindName('ClearSelection').Content = Get-LTUiString 'clearSelection'
    $w.FindName('CopyLog').Content = Get-LTUiString 'copyLog'
    $w.FindName('OpenLogs').Content = Get-LTUiString 'openLogs'
    $w.FindName('LangLabel').Text = Get-LTUiString 'language'
    $w.FindName('FooterText').Text = "Lyons Tools $($LT.Version) $([char]0x00B7) $(Get-LTUiString 'support'): ehtu.com"
    $w.FindName('StatusText').Text = if ($LT.Busy) { Get-LTUiString 'busy' } else { Get-LTUiString 'ready' }

    $badge = if (Test-LTAdmin) { Get-LTUiString 'admin' } else { "$(Get-LTUiString 'user'): $env:USERNAME" }
    if ($LT.IsRemoteSession) { $badge += " $([char]0x00B7) RDP" }
    elseif ($LT.IsServer) { $badge += " $([char]0x00B7) Server" }
    $w.FindName('AdminBadge').Text = $badge
}

function Show-LTWindow {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xaml = $LTXaml.Replace('__LT_VERSION__', $LT.Version)
    $window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new([xml]$xaml))
    $LT.Window = $window
    $LT.Gui = $true
    $LT.LogQueue = [Collections.Concurrent.ConcurrentQueue[string]]::new()
    $LT.FunctionNames = @(Get-ChildItem function: | Where-Object { $_.Name -match '^[A-Za-z]+-LT' } | ForEach-Object Name)

    $LT.LogBox = $window.FindName('LogBox')
    # Kept in $LT so event handlers never depend on PowerShell scoping.
    $LT.BusyBar = $window.FindName('BusyBar')
    $LT.StatusText = $window.FindName('StatusText')
    $LT.RunSelected = $window.FindName('RunSelected')
    $runSelected = $LT.RunSelected

    # Language selector
    $langBox = $window.FindName('LangBox')
    $LT.LangBox = $langBox
    foreach ($l in $LT.Config.languages) {
        $entry = [Windows.Controls.ComboBoxItem]::new()
        $entry.Content = $l.name
        $entry.Tag = $l.code
        [void]$langBox.Items.Add($entry)
        if ($l.code -eq $LT.Lang) { $langBox.SelectedItem = $entry }
    }
    $langBox.Add_SelectionChanged({
            $code = $this.SelectedItem.Tag
            if (-not $code -or $code -eq $LT.Lang) { return }
            $LT.Lang = $code
            Save-LTSettings
            Update-LTTexts
            Add-LTTabs
        })

    Update-LTTexts
    Add-LTTabs

    $runSelected.Add_Click({
            $ids = @($LT.CheckBoxes.Values | Where-Object { $_.IsChecked -and $_.IsEnabled } | ForEach-Object Tag)
            Invoke-LTSelection -Ids $ids
        })
    $window.FindName('ClearSelection').Add_Click({ $LT.CheckBoxes.Values | ForEach-Object { $_.IsChecked = $false } })
    $window.FindName('CopyLog').Add_Click({
            if ($LT.LogBox.Text) {
                [Windows.Clipboard]::SetText($LT.LogBox.Text)
                Write-LTLog "Log copied to the clipboard." "Registro copiado al portapapeles." "Registre copiat al porta-retalls." -Level Ok
            }
        })
    $window.FindName('OpenLogs').Add_Click({ Start-Process explorer.exe $LT.LogDir })
    $window.FindName('Website').Add_Click({ Start-Process $LT.Config.app.publisherUrl })

    # The UI thread drains the log queue and reflects the busy state.
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({
            $line = $null
            $wrote = $false
            while ($LT.LogQueue.TryDequeue([ref]$line)) { $LT.LogBox.AppendText($line + "`r`n"); $wrote = $true }
            if ($wrote) { $LT.LogBox.ScrollToEnd() }

            $busy = [bool]$LT.Busy
            if ($busy -ne [bool]$LT.UiBusy) {
                $LT.UiBusy = $busy
                foreach ($b in $LT.ItemButtons) { $b.IsEnabled = (-not $busy) -and (Test-LTItemAllowed $LT.Items[$b.Tag]) }
                $LT.RunSelected.IsEnabled = -not $busy
                $LT.LangBox.IsEnabled = -not $busy
                $LT.BusyBar.Visibility = if ($busy) { 'Visible' } else { 'Collapsed' }
                $LT.StatusText.Text = if ($busy) { Get-LTUiString 'busy' } else { Get-LTUiString 'ready' }
                if (-not $busy -and $LT.Job) {
                    try { $LT.Job.PowerShell.EndInvoke($LT.Job.Handle) } catch { }
                    $LT.Job.PowerShell.Dispose(); $LT.Job.Runspace.Dispose()
                    $LT.Job = $null
                }
            }
        })
    $timer.Start()

    $window.Add_Closing({
            if ($LT.Job) { try { $LT.Job.PowerShell.Stop() } catch { } }
        })

    Write-LTLog "Lyons Tools $($LT.Version) - $(Get-LTUiString 'welcome')"
    if (-not $LT.CanElevate) {
        Write-LTLog "You are using a standard account: actions marked 'Administrator' are disabled." `
            "Est$([char]0x00E1)s usando una cuenta est$([char]0x00E1)ndar: las acciones marcadas como 'Administrador' est$([char]0x00E1)n desactivadas." `
            "Est$([char]0x00E0)s fent servir un compte est$([char]0x00E0)ndard: les accions marcades com a 'Administrador' estan desactivades." -Level Warn
    }
    [void]$window.ShowDialog()
    $timer.Stop()
}

Show-LTWindow

#endregion
