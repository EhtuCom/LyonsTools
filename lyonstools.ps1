<#
    Lyons Tools 1.1.0 - utilidades de Windows, Office, Java y firma digital
    https://github.com/EhtuCom/LyonsTools  |  https://ehtu.com

    GENERATED FILE - DO NOT EDIT. Edit the sources and run Compile.ps1.
    Built 2026-10-01 07:55
#>

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
    irm https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1 | iex

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1))) -Run office-crash-protection -Minutes 3
#>
param(
    [string[]]$Run,
    [ValidateRange(1, 120)][int]$Minutes = 5,
    [switch]$List
)

$LT = [hashtable]::Synchronized(@{})
$LT.Version = '1.1.0'
$LT.Repo = 'EhtuCom/LyonsTools'
$LT.SourceUrl = 'https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1'
$LT.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) LyonsTools/$($LT.Version)"
$LT.OfficePolicyRoot = 'Software\Policies\Microsoft\Office\16.0'
$LT.Gui = $false
$LT.Busy = $false


# ---- functions\core\Core.ps1 ----
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

# ---- functions\firma\Firma.ps1 ----
#region Firma digital ------------------------------------------------------------

function Install-LTFnmtConfigurator {
    $page = 'https://www.sede.fnmt.gob.es/descargas/descarga-software'
    $url = $null
    try { $url = Find-LTWebLink -Url $page -Pattern 'descargas\.cert\.fnmt\.es/Windows/Configurador_FNMT_[\d.]+_64bits\.exe' }
    catch { Write-LTLog "No se ha podido consultar la web de la FNMT: $($_.Exception.Message)" -Level Warn }
    if (-not $url) {
        Write-LTLog "No se ha encontrado el enlace en la web de la FNMT. Abriendo la p$([char]0x00E1)gina de descargas." -Level Warn
        Open-LTUrl $page
        return
    }
    try { $file = Save-LTFile -Url $url }
    catch { Write-LTLog "Error al descargar: $($_.Exception.Message)" -Level Error; return }
    if (-not (Test-LTSignature -Path $file)) { return }
    Write-LTLog "Sigue los pasos del instalador del Configurador FNMT."
    [void](Start-LTInstaller -Path $file)
}

function Install-LTCertificateFiles {
    <#
        Installs CA certificate files into the machine stores in one elevated step.
        Self-signed roots go to LocalMachine\Root ONLY if their thumbprint is in $TrustedRoots;
        intermediate CAs go to LocalMachine\CA. Expired certificates are skipped.
    #>
    param(
        [Parameter(Mandatory)][string[]]$Files,
        [Parameter(Mandatory)][hashtable]$TrustedRoots,
        [Parameter(Mandatory)][string]$Issuer
    )
    $seen = @{}
    $plan = foreach ($file in $Files) {
        try { $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($file) }
        catch { continue }
        if ($seen.ContainsKey($cert.Thumbprint)) { continue }
        $seen[$cert.Thumbprint] = $true

        $name = $cert.GetNameInfo('SimpleName', $false)
        if ($cert.NotAfter -lt (Get-Date)) { Write-LTLog "Omitido (caducado): $name"; continue }
        if ($cert.Subject -eq $cert.Issuer) {
            if (-not $TrustedRoots.ContainsKey($cert.Thumbprint)) {
                Write-LTLog "Omitido: ra$([char]0x00ED)z desconocida '$name' ($($cert.Thumbprint)). No coincide con las ra$([char]0x00ED)ces oficiales ($Issuer)." -Level Warn
                continue
            }
            [pscustomobject]@{ File = $file; Store = 'Root'; Name = $name }
        }
        else {
            [pscustomobject]@{ File = $file; Store = 'CA'; Name = $name }
        }
    }
    $plan = @($plan)
    if (-not $plan.Count) { Write-LTLog "No hay certificados para instalar." -Level Error; return }

    $script = ($plan | ForEach-Object {
            "Import-Certificate -FilePath '$($_.File)' -CertStoreLocation 'Cert:\LocalMachine\$($_.Store)' | Out-Null"
        }) -join "`n"
    Write-LTLog "Instalando $($plan.Count) certificados ($Issuer) (se pedir$([char]0x00E1) permiso de administrador)..."
    if ((Invoke-LTElevated -Script $script) -ne 0) {
        Write-LTLog "No se han podido instalar los certificados." -Level Error
        return
    }
    foreach ($c in $plan) {
        $where = if ($c.Store -eq 'Root') { "Entidades de certificaci$([char]0x00F3)n ra$([char]0x00ED)z de confianza" } else { "Entidades de certificaci$([char]0x00F3)n intermedias" }
        Write-LTLog "Instalado: $($c.Name)  ->  $where" -Level Ok
    }
    Write-LTLog "Si usas Firefox, activa 'security.enterprise_roots.enabled' o importa los certificados en Firefox."
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
    catch { Write-LTLog "No se ha podido leer la p$([char]0x00E1)gina de la FNMT, se usa la lista conocida." -Level Warn }
    if (-not $paths) { $paths = $known }

    $folder = New-LTCleanFolder 'fnmt-certs'
    $files = foreach ($p in $paths) {
        $file = Join-Path $folder ([IO.Path]::GetFileName($p))
        try {
            Invoke-WebRequest -Uri "$base$p" -OutFile $file -UseBasicParsing -UserAgent $LT.UserAgent -ErrorAction Stop
            $file
        }
        catch { Write-LTLog "No se ha podido descargar $p" -Level Warn }
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
            Write-LTLog "Descargado el paquete de claves p$([char]0x00FA)blicas del Consorci AOC: $url"
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
            catch { Write-LTLog "No se ha podido descargar $url" -Level Warn }
        }
    }
    $files = @(Get-ChildItem -Path $folder -Recurse -File | Where-Object Extension -in '.crt', '.cer', '.der' | ForEach-Object FullName)
    if (-not $files.Count) {
        Write-LTLog "No se han podido descargar los certificados del Consorci AOC." -Level Error
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
        Write-LTLog "Est$([char]0x00E1) instalado $($old[0].DisplayName). El Consorci AOC indica desinstalarlo antes (Configuraci$([char]0x00F3)n > Aplicaciones)." -Level Warn
    }
    try { $file = Save-LTFile -Url 'https://cdn.bit4id.com/es/AOC/middleware/Bit4id_AOC_Middleware.exe' }
    catch {
        Write-LTLog "Error al descargar: $($_.Exception.Message)" -Level Error
        Open-LTUrl 'https://suport.aoc.cat/ca-es/article/?servei=tcat&id=KA-07251_instal-lacio-del-programari-per-a-l-us-de-la-t-cat-en-targeta'
        return
    }
    if (-not (Test-LTSignature -Path $file)) { return }
    Write-LTLog "Sigue los pasos del instalador. Necesitar$([char]0x00E1)s un lector de tarjetas conectado para usar la T-CAT."
    if (Start-LTInstaller -Path $file) {
        Write-LTLog "Manual: https://cdn.bit4id.com/es/AOC/manuals/Windows/Windows.html"
    }
}

function Get-LTPersonalCertificates {
    $certs = @(Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue | Where-Object HasPrivateKey | Sort-Object NotAfter)
    if (-not $certs.Count) {
        Write-LTLog "No hay ning$([char]0x00FA)n certificado para firmar (con clave privada) en este usuario de Windows." -Level Warn
        return
    }
    $now = Get-Date
    foreach ($c in $certs) {
        $days = [int][math]::Floor(($c.NotAfter - $now).TotalDays)
        $name = $c.GetNameInfo('SimpleName', $false)
        $issuer = $c.GetNameInfo('SimpleName', $true)
        $msg = "{0}`n           Emisor: {1} | caduca el {2:dd/MM/yyyy}" -f $name, $issuer, $c.NotAfter
        if ($days -lt 0) { Write-LTLog "$msg (CADUCADO hace $(-$days) d$([char]0x00ED)as)" -Level Error }
        elseif ($days -le 60) { Write-LTLog "$msg (caduca en $days d$([char]0x00ED)as: renu$([char]0x00E9)valo)" -Level Warn }
        else { Write-LTLog "$msg ($days d$([char]0x00ED)as)" -Level Ok }
    }
    if ($certs | Where-Object { $_.NotAfter -lt $now }) {
        Write-LTLog "Los certificados caducados se pueden eliminar desde el administrador de certificados."
    }
}

function Install-LTAutofirma {
    $page = 'https://firmaelectronica.gob.es/descargas'
    $fallback = 'https://firmaelectronica.gob.es/content/dam/firmaelectronica/descargas-software/autofirma19/Autofirma64.zip'
    $url = $null
    try { $url = Find-LTWebLink -Url $page -Pattern '/descargas-software/autofirma\d+/Autofirma64\.zip' }
    catch { Write-LTLog "No se ha podido consultar firmaelectronica.gob.es: $($_.Exception.Message)" -Level Warn }
    if (-not $url) { $url = $fallback }

    $installed = Get-LTInstalledApp -Name '^Autofirma' | Select-Object -First 1
    if ($installed) { Write-LTLog "Autofirma ya est$([char]0x00E1) instalado: versi$([char]0x00F3)n $($installed.DisplayVersion). Se reinstalar$([char]0x00E1) con la $([char]0x00FA)ltima versi$([char]0x00F3)n." }

    try { $zip = Save-LTFile -Url $url -FileName 'Autofirma64.zip' }
    catch { Write-LTLog "Error al descargar Autofirma: $($_.Exception.Message)" -Level Error; Open-LTUrl $page; return }

    $dir = Join-Path (Get-LTWorkFolder) 'Autofirma'
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    $exe = Get-ChildItem -Path $dir -Filter '*.exe' -Recurse | Select-Object -First 1
    if (-not $exe) { Write-LTLog "El ZIP de Autofirma no contiene ning$([char]0x00FA)n instalador." -Level Error; return }
    if (-not (Test-LTSignature -Path $exe.FullName)) { return }

    # Silent mode shows a blocking dialog if the same version is already installed, so only use /S on clean machines.
    $arguments = if ($installed) { $null } else { '/S' }
    if (Start-LTInstaller -Path $exe.FullName -Arguments $arguments) {
        Write-LTLog "Autofirma instalado. Reinicia el navegador antes de firmar." -Level Ok
    }
}

function Install-LTSignador {
    <#
        Native app of the Consorci AOC "Signador". The MSI installs for all users; after a
        silent install its local certificate must be added to the trusted roots manually
        (https://consorciaoc.github.io/signador/guiaUsuaris/nativaDesatesa/).
    #>
    $url = 'https://signador.aoc.cat/signador/getNativa?os=windows&arch=64&msi'
    try { $msi = Save-LTFile -Url $url -FileName 'AppNativaSignador-x64.msi' }
    catch {
        Write-LTLog "Error al descargar el Signador: $($_.Exception.Message)" -Level Error
        Open-LTUrl 'https://signador.aoc.cat/signador/installNativa'
        return
    }
    if (-not (Test-LTSignature -Path $msi)) { return }

    $log = Join-Path (Get-LTWorkFolder) 'signador-install.log'
    $script = @"
`$p = Start-Process msiexec.exe -ArgumentList '/i "$msi" /passive /norestart sys.languageId=es /Lp "$log"' -Wait -PassThru
if (`$p.ExitCode -notin 0, 3010) { exit `$p.ExitCode }
`$crt = Get-ChildItem -Path "`$env:ProgramFiles", "`${env:ProgramFiles(x86)}" -Filter root.crt -Recurse -Depth 5 -ErrorAction SilentlyContinue |
    Where-Object { `$_.FullName -match 'Signador|AOC' -and `$_.FullName -match 'lib\\certificate' } | Select-Object -First 1
if (`$crt) { Import-Certificate -FilePath `$crt.FullName -CertStoreLocation Cert:\LocalMachine\Root | Out-Null }
"@
    Write-LTLog "Instalando la aplicaci$([char]0x00F3)n nativa del Signador (se pedir$([char]0x00E1) permiso de administrador)..."
    $result = Invoke-LTElevated -Script $script
    if ($result -ne 0) {
        Write-LTLog "La instalaci$([char]0x00F3)n no se ha completado (c$([char]0x00F3)digo $result). Registro: $log" -Level Error
        return
    }
    $app = Get-LTInstalledApp -Name 'Signador' | Select-Object -First 1
    Write-LTLog "Signador instalado$(if ($app) { ": $($app.DisplayName) $($app.DisplayVersion)" })." -Level Ok
    Write-LTLog "Reinicia el navegador antes de firmar en tr$([char]0x00E1)mites de la Generalitat."
}

#endregion

# ---- functions\java\Java.ps1 ----
#region Java ------------------------------------------------------------------

function Get-LTJavaInfo {
    Write-LTLog "Versiones de Java instaladas"

    $java = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($java) {
        Write-LTLog "Java por defecto (PATH): $($java.Source)"
        $out = & cmd.exe /c "`"$($java.Source)`" -version 2>&1"
        $out | ForEach-Object { Write-LTLog "    $_" }
    }
    else {
        Write-LTLog "No hay ning$([char]0x00FA)n Java en el PATH (el comando 'java' no existe)." -Level Warn
    }

    $apps = @(Get-LTInstalledApp -Name '\bJava\b|\bJRE\b|\bJDK\b|Temurin|OpenJDK|Zulu|Corretto')
    if ($apps.Count) {
        Write-LTLog "Programas Java instalados:"
        foreach ($a in $apps) { Write-LTLog ("    {0}  [{1}]" -f $a.DisplayName, $a.DisplayVersion) }
    }
    else {
        Write-LTLog "No se ha encontrado ning$([char]0x00FA)n Java instalado en Programas y caracter$([char]0x00ED)sticas."
    }

    foreach ($key in 'HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment', 'HKLM:\SOFTWARE\WOW6432Node\JavaSoft\Java Runtime Environment') {
        $cur = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).CurrentVersion
        if ($cur) {
            $bits = if ($key -match 'WOW6432') { '32 bits' } else { '64 bits' }
            Write-LTLog "Java de Oracle registrado ($bits): versi$([char]0x00F3)n $cur"
        }
    }

    try {
        $latest = Invoke-RestMethod -Uri 'https://api.adoptium.net/v3/info/available_releases' -UseBasicParsing -ErrorAction Stop
        Write-LTLog "$([char]0x00DA)ltima versi$([char]0x00F3)n LTS de Java disponible: $($latest.most_recent_lts) (Temurin). Java 8 sigue siendo la versi$([char]0x00F3)n de java.com." -Level Ok
    }
    catch { }
}

function Install-LTJavaTemurin {
    <# Installs the latest LTS Eclipse Temurin JRE (free OpenJDK build) from the Adoptium API. #>
    Write-LTLog "Buscando la $([char]0x00FA)ltima versi$([char]0x00F3)n LTS de Eclipse Temurin..."
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
        Write-LTLog "Versi$([char]0x00F3)n encontrada: $($asset.release_name)"
        $file = Save-LTFile -Url $installer.link -FileName $installer.name
    }
    catch {
        Write-LTLog "No se ha podido descargar Temurin: $($_.Exception.Message)" -Level Error
        Write-LTLog "Probando con winget..."
        if (-not (Install-LTWinget -Id "EclipseAdoptium.Temurin.$lts.JRE")) { Open-LTUrl 'https://adoptium.net/es/temurin/releases/' }
        return
    }
    if (-not (Test-LTSignature -Path $file)) { return }
    # FeatureEnvironment/FeatureJavaHome set PATH and JAVA_HOME, FeatureJarFileRunWith opens .jar files,
    # FeatureOracleJavaSoft writes the HKLM\SOFTWARE\JavaSoft keys that older apps look for.
    [void](Start-LTInstaller -Path $file -Arguments 'ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome,FeatureOracleJavaSoft /passive /norestart')
}

function Install-LTJavaOracle8 {
    <# Oracle Java 8 (the one on java.com), still required by some old government applets/apps. #>
    Write-LTLog "Instalando Oracle Java 8 (java.com)..."
    if (Install-LTWinget -Id 'Oracle.JavaRuntimeEnvironment') {
        Write-LTLog "Oracle Java 8 instalado o ya actualizado." -Level Ok
        return
    }
    # Fallback: offline x64 installer from java.com (the BundleId changes with every release).
    $page = 'https://www.java.com/es/download/manual.jsp'
    try {
        $link = (Get-LTWebPage -Url $page).Links |
            Where-Object { $_.href -match 'AutoDL\?BundleId=' -and $_.outerHTML -match 'Windows Fuera de l(.|&\w+;|&#\d+;)nea \(64 bits\)' } |
            Select-Object -First 1
        if (-not $link) { throw 'enlace no encontrado' }
        $file = Save-LTFile -Url ([Net.WebUtility]::HtmlDecode($link.href)) -FileName 'jre8-windows-x64.exe'
        if (-not (Test-LTSignature -Path $file)) { return }
        [void](Start-LTInstaller -Path $file -Arguments '/s')
    }
    catch {
        Write-LTLog "No se ha podido descargar desde java.com ($($_.Exception.Message)). Abriendo la p$([char]0x00E1)gina oficial." -Level Warn
        Open-LTUrl 'https://www.java.com/es/download/'
    }
}

function Clear-LTJavaCache {
    $javaws = @(
        (Get-Command javaws.exe -ErrorAction SilentlyContinue).Source,
        "$env:ProgramFiles\Java\*\bin\javaws.exe",
        "${env:ProgramFiles(x86)}\Java\*\bin\javaws.exe"
    ) | Where-Object { $_ } | ForEach-Object { Get-Item $_ -ErrorAction SilentlyContinue } | Select-Object -First 1

    if ($javaws) {
        Write-LTLog "Vaciando la cach$([char]0x00E9) con $($javaws.FullName)"
        Start-Process -FilePath $javaws.FullName -ArgumentList '-uninstall', '-clearcache' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
    }
    $cache = Join-Path $env:USERPROFILE 'AppData\LocalLow\Sun\Java\Deployment\cache'
    if (Test-Path $cache) {
        Remove-Item -Path "$cache\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-LTLog "Cach$([char]0x00E9) de Java eliminada: $cache" -Level Ok
    }
    elseif (-not $javaws) {
        Write-LTLog "No hay cach$([char]0x00E9) de Java que limpiar."
    }
    else {
        Write-LTLog "Cach$([char]0x00E9) de Java vaciada." -Level Ok
    }
}

#endregion

# ---- functions\office\OfficeAutoRecover.ps1 ----
#region Office AutoRecover ------------------------------------------------------
<#
    The values are the documented Office 16.0 Group Policy settings (ADMX), which cover
    Office 2016/2019/2021/2024 and Microsoft 365:

      Word        HKCU\Software\Policies\Microsoft\Office\16.0\Word\Options
                    autosaveinterval (minutes, 0 = off), keepunsavedchanges
      Excel       HKCU\Software\Policies\Microsoft\Office\16.0\Excel\Options
                    autorecovertime (minutes), keepunsavedchanges
      PowerPoint  HKCU\Software\Policies\Microsoft\Office\16.0\PowerPoint\Options
                    saveautorecoveryinfo, frequencytosaveautorecoveryinfo (minutes), keepunsavedchanges

    Policies are used (instead of the normal preference values) because Office cannot
    overwrite them when it closes. HKCU\Software\Policies is only writable by administrators,
    so the values are written elevated into HKEY_USERS\<SID of the signed-in user>: that way
    they land in the right profile even if a different admin account approves the UAC prompt.
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
        Write-LTLog "No se han podido guardar los ajustes (hacen falta permisos de administrador)." -Level Error
        return $false
    }
    $true
}

function Get-LTAutoRecoverState {
    param([ValidateSet('Word', 'Excel', 'PowerPoint')][string]$App)
    $p = Get-ItemProperty "HKCU:\$($LT.OfficePolicyRoot)\$App\Options" -ErrorAction SilentlyContinue
    $pref = Get-ItemProperty "HKCU:\Software\Microsoft\Office\16.0\$App\Options" -ErrorAction SilentlyContinue
    switch ($App) {
        'Word' {
            $min = if ($null -ne $p.autosaveinterval) { $p.autosaveinterval } else { 10 }
            [pscustomobject]@{ Enabled = $min -gt 0; Minutes = $min; KeepLast = $p.keepunsavedchanges -ne 0 }
        }
        'Excel' {
            $min = if ($null -ne $p.autorecovertime) { $p.autorecovertime } elseif ($pref.AutoRecoverTime) { $pref.AutoRecoverTime } else { 10 }
            [pscustomobject]@{ Enabled = $true; Minutes = $min; KeepLast = $p.keepunsavedchanges -ne 0 }
        }
        'PowerPoint' {
            $min = if ($null -ne $p.frequencytosaveautorecoveryinfo) { $p.frequencytosaveautorecoveryinfo } else { 10 }
            [pscustomobject]@{ Enabled = $p.saveautorecoveryinfo -ne 0; Minutes = $min; KeepLast = $p.keepunsavedchanges -ne 0 }
        }
    }
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
    $running = Get-Process WINWORD, EXCEL, POWERPNT -ErrorAction SilentlyContinue
    if ($running) {
        $names = ($running | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
        Write-LTLog "Hay programas de Office abiertos ($names). El cambio se aplicar$([char]0x00E1) la pr$([char]0x00F3)xima vez que los abras." -Level Warn
    }
}

function Set-LTOfficeAutoRecover {
    param(
        [Parameter(Mandatory)][ValidateSet('Word', 'Excel', 'PowerPoint')][string]$App,
        [ValidateRange(1, 120)][int]$Minutes = 5
    )
    if (Set-LTUserPolicy -Values @(Get-LTAutoRecoverPolicy -App $App -Minutes $Minutes)) {
        Write-LTLog "$App guardar$([char]0x00E1) la informaci$([char]0x00F3)n de autorrecuperaci$([char]0x00F3)n cada $Minutes minutos." -Level Ok
        Write-LTOfficeRunningWarning
    }
}

function Set-LTWordAutoRecover { param([int]$Minutes = 5) Set-LTOfficeAutoRecover -App Word -Minutes $Minutes }
function Set-LTExcelAutoRecover { param([int]$Minutes = 5) Set-LTOfficeAutoRecover -App Excel -Minutes $Minutes }
function Set-LTPowerPointAutoRecover { param([int]$Minutes = 5) Set-LTOfficeAutoRecover -App PowerPoint -Minutes $Minutes }

function Enable-LTOfficeCrashProtection {
    param([ValidateRange(1, 120)][int]$Minutes = 5)

    $values = @(
        foreach ($app in 'Word', 'Excel', 'PowerPoint') {
            Get-LTAutoRecoverPolicy -App $app -Minutes $Minutes
            @{ Path = "$app\Options"; Name = 'keepunsavedchanges'; Value = 1 }
        }
    )
    if (-not (Set-LTUserPolicy -Values $values)) { return }
    Write-LTLog "Word, Excel y PowerPoint: autorrecuperaci$([char]0x00F3)n cada $Minutes minutos." -Level Ok
    Write-LTLog "Se conservar$([char]0x00E1) la $([char]0x00FA)ltima versi$([char]0x00F3)n autorrecuperada si se cierra sin guardar." -Level Ok

    # "Always create backup copy" in Word: a normal user preference, set through Word itself.
    $word = $null
    try {
        $word = New-Object -ComObject Word.Application -ErrorAction Stop
        $word.Options.CreateBackup = $true
        Write-LTLog "Word crear$([char]0x00E1) siempre una copia de seguridad (.wbk) al guardar." -Level Ok
    }
    catch {
        Write-LTLog "No se ha podido activar la copia de seguridad de Word: $($_.Exception.Message)" -Level Warn
    }
    finally {
        if ($word) {
            try { $word.Quit([ref]0) } catch { }
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word)
        }
    }
    Write-LTOfficeRunningWarning
}

function Reset-LTOfficeAutoRecover {
    <# Removes the values written by Lyons Tools, so the user can change them again in Office. #>
    $values = @(
        @{ Path = 'Word\Options'; Name = 'autosaveinterval'; Value = $null }
        @{ Path = 'Excel\Options'; Name = 'autorecovertime'; Value = $null }
        @{ Path = 'PowerPoint\Options'; Name = 'saveautorecoveryinfo'; Value = $null }
        @{ Path = 'PowerPoint\Options'; Name = 'frequencytosaveautorecoveryinfo'; Value = $null }
        foreach ($app in 'Word', 'Excel', 'PowerPoint') { @{ Path = "$app\Options"; Name = 'keepunsavedchanges'; Value = $null } }
    )
    if (Set-LTUserPolicy -Values $values) {
        Write-LTLog "Ajustes de autoguardado eliminados. Office vuelve a usar la configuraci$([char]0x00F3)n de Archivo > Opciones > Guardar." -Level Ok
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
            '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' { 'Actual (Current Channel)' }
            '55336b82-a18d-4dd6-b5f6-9e5095c314a6' { 'Empresa mensual (Monthly Enterprise)' }
            '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' { 'Empresa semestral (Semi-Annual)' }
            '64256afe-f5d9-4f86-8936-8840a6a4f5be' { "Actual (versi$([char]0x00F3)n preliminar)" }
            default { $c2r.Config.CDNBaseUrl }
        }
        Write-LTLog "Office: $($c2r.Config.ProductReleaseIds)"
        Write-LTLog "Versi$([char]0x00F3)n: $($c2r.Config.VersionToReport) ($($c2r.Config.Platform))"
        Write-LTLog "Canal: $channel"
    }
    else {
        $msi = Get-LTInstalledApp -Name 'Microsoft Office|Microsoft 365' | Select-Object -First 1
        if ($msi) { Write-LTLog "Office (MSI): $($msi.DisplayName) $($msi.DisplayVersion)" }
        else { Write-LTLog "No se ha encontrado Office instalado." -Level Warn }
    }

    foreach ($app in 'Word', 'Excel', 'PowerPoint') {
        $s = Get-LTAutoRecoverState -App $app
        if ($null -eq $s) { continue }
        $state = if ($s.Enabled) { "activada cada $($s.Minutes) min" } else { 'desactivada' }
        Write-LTLog ("{0,-11} autorrecuperaci$([char]0x00F3)n {1}; conservar $([char]0x00FA)ltima versi$([char]0x00F3)n: {2}" -f $app, $state, $(if ($s.KeepLast) { "s$([char]0x00ED)" } else { "no" }))
    }
}

function Update-LTOffice {
    $c2r = Get-LTClickToRun
    if (-not $c2r.Client) {
        Write-LTLog "No se ha encontrado Office Click-to-Run. Si es una versi$([char]0x00F3)n MSI, actualiza con Windows Update." -Level Warn
        return
    }
    Write-LTLog "Iniciando la actualizaci$([char]0x00F3)n de Office (se mostrar$([char]0x00E1) la ventana de Office)..."
    Start-Process -FilePath $c2r.Client -ArgumentList '/update user updatepromptuser=true forceappshutdown=false displaylevel=true'
    Write-LTLog "Actualizaci$([char]0x00F3)n lanzada. Office avisar$([char]0x00E1) si necesita cerrar alg$([char]0x00FA)n programa." -Level Ok
}

function Repair-LTOffice {
    $c2r = Get-LTClickToRun
    if (-not $c2r.RepairExe -or -not $c2r.Config) {
        Write-LTLog "No se ha encontrado Office Click-to-Run. Usa Configuraci$([char]0x00F3)n > Aplicaciones > Office > Modificar." -Level Warn
        Start-Process 'ms-settings:appsfeatures'
        return
    }
    $platform = if ($c2r.Config.Platform -eq 'x86') { 'x86' } else { 'x64' }
    $culture = ($c2r.Config.ClientCulture, 'es-es' | Where-Object { $_ } | Select-Object -First 1)
    Write-LTLog "Lanzando la reparaci$([char]0x00F3)n r$([char]0x00E1)pida de Office ($platform, $culture)..."
    $script = "Start-Process -FilePath '$($c2r.RepairExe)' -ArgumentList 'scenario=Repair platform=$platform culture=$culture RepairType=QuickRepair forceappshutdown=false DisplayLevel=True'"
    if ((Invoke-LTElevated -Script $script) -eq 0) {
        Write-LTLog "Reparaci$([char]0x00F3)n lanzada. Sigue las instrucciones de la ventana de Office." -Level Ok
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
    # Word backup copies (.wbk) are saved next to the original document.
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $files = @($files) + @(Get-ChildItem -Path $docs -Filter '*.wbk' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $since })
    $files = @($files | Sort-Object LastWriteTime -Descending)

    if (-not $files.Count) {
        Write-LTLog "No se han encontrado documentos recuperables en los $([char]0x00FA)ltimos 30 d$([char]0x00ED)as."
        Write-LTLog "Prueba tambi$([char]0x00E9)n en Word/Excel: Archivo > Informaci$([char]0x00F3)n > Administrar documento > Recuperar documentos no guardados."
        return
    }
    Write-LTLog "Documentos recuperables encontrados ($($files.Count)):" -Level Ok
    foreach ($f in $files | Select-Object -First 40) {
        Write-LTLog ("    {0:dd/MM/yyyy HH:mm}  {1}" -f $f.LastWriteTime, $f.FullName)
    }
    Write-LTLog "$([char]0x00C1)brelos con Word/Excel y usa 'Guardar como' para conservarlos. Abriendo la carpeta del m$([char]0x00E1)s reciente..."
    Start-Process explorer.exe "/select,`"$($files[0].FullName)`""
}

function Open-LTCertManager {
    Start-Process certmgr.msc
    Write-LTLog "Abierto el administrador de certificados. Tus certificados est$([char]0x00E1)n en Personal > Certificados." -Level Ok
}

#endregion

# ---- functions\windows\Windows.ps1 ----
#region Windows -----------------------------------------------------------------

function Enable-LTFileExtensions {
    # Showing extensions helps users spot "factura.pdf.exe" style phishing attachments.
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 -Type DWord
    Write-LTLog "Ahora se mostrar$([char]0x00E1)n las extensiones de archivo (.pdf, .docx, .exe...)." -Level Ok
    Restart-LTExplorer
}

function Enable-LTClipboardHistory {
    $key = 'HKCU:\Software\Microsoft\Clipboard'
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    Set-ItemProperty -Path $key -Name 'EnableClipboardHistory' -Value 1 -Type DWord
    Write-LTLog "Historial del portapapeles activado. Pulsa Windows + V para ver lo que has copiado." -Level Ok
}

function Restart-LTExplorer {
    Write-LTLog "Reiniciando el Explorador de Windows..."
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Write-LTLog "Explorador reiniciado." -Level Ok
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
    Write-LTLog "Archivos temporales eliminados: $freed MB liberados (los archivos en uso se han dejado)." -Level Ok
}

function Clear-LTDnsCache {
    ipconfig.exe /flushdns | Out-Null
    Write-LTLog "Cach$([char]0x00E9) DNS vaciada." -Level Ok
}

function Start-LTQuickAssist {
    Write-LTLog "Abriendo Asistencia r$([char]0x00E1)pida. Elige 'Ayudar a alguien' o introduce el c$([char]0x00F3)digo que te d$([char]0x00E9) el t$([char]0x00E9)cnico."
    try { Start-Process 'ms-quick-assist:' -ErrorAction Stop }
    catch {
        Write-LTLog "Asistencia r$([char]0x00E1)pida no est$([char]0x00E1) instalada. Abriendo Microsoft Store..." -Level Warn
        Start-Process 'ms-windows-store://pdp/?ProductId=9P7BP5VNWKX5'
    }
}

function Open-LTWindowsUpdate {
    Start-Process 'ms-settings:windowsupdate'
    Write-LTLog "Abierto Windows Update." -Level Ok
}

function Get-LTSystemReport {
    <# Builds a support report (Windows, Office, Java, signing apps, certificates) and copies it to the clipboard. #>
    Write-LTLog "Generando informe del equipo..."
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    $c2r = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    $display = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion

    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("Informe Lyons Tools $($LT.Version) - $(Get-Date -Format 'dd/MM/yyyy HH:mm')")
    $lines.Add("Equipo:      $env:COMPUTERNAME ($($cs.Manufacturer) $($cs.Model))")
    $lines.Add("Usuario:     $env:USERDOMAIN\$env:USERNAME (administrador: $(if (Test-LTAdmin) { "s$([char]0x00ED)" } else { "no" }))")
    $lines.Add("Windows:     $($os.Caption) $display (build $($os.BuildNumber))")
    $lines.Add("Memoria:     $([math]::Round($cs.TotalPhysicalMemory / 1GB, 1)) GB")
    $lines.Add("Disco $($env:SystemDrive)    $([math]::Round($disk.FreeSpace / 1GB, 1)) GB libres de $([math]::Round($disk.Size / 1GB, 1)) GB")
    if ($c2r) { $lines.Add("Office:      $($c2r.ProductReleaseIds) $($c2r.VersionToReport) ($($c2r.Platform))") }
    else { $lines.Add("Office:      no se ha detectado Office Click-to-Run") }

    $java = Get-Command java.exe -ErrorAction SilentlyContinue
    $javaVer = if ($java) { (& cmd.exe /c "`"$($java.Source)`" -version 2>&1" | Select-Object -First 1) } else { "no est$([char]0x00E1) en el PATH" }
    $lines.Add("Java:        $javaVer")

    foreach ($app in @(
            @{ Label = 'Autofirma:   '; Pattern = 'Autofirma' },
            @{ Label = 'Configurador:'; Pattern = 'Configurador FNMT' },
            @{ Label = 'Signador:    '; Pattern = 'Signador|AOC' })) {
        $found = Get-LTInstalledApp -Name $app.Pattern | Select-Object -First 1
        $lines.Add("$($app.Label) $(if ($found) { "$($found.DisplayName) $($found.DisplayVersion)" } else { 'no instalado' })")
    }

    $certs = @(Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue | Where-Object HasPrivateKey)
    $lines.Add("Certificados personales con clave privada: $($certs.Count)")
    foreach ($c in $certs | Sort-Object NotAfter) {
        $lines.Add("    - $($c.GetNameInfo('SimpleName', $false)) | caduca $($c.NotAfter.ToString('dd/MM/yyyy'))")
    }

    $text = $lines -join [Environment]::NewLine
    $lines | ForEach-Object { Write-LTLog $_ }
    try {
        Set-Clipboard -Value $text -ErrorAction Stop
        Write-LTLog "Informe copiado al portapapeles. P$([char]0x00E9)galo en un correo a soporte." -Level Ok
    }
    catch {
        $file = Join-Path ([Environment]::GetFolderPath('Desktop')) "Informe-LyonsTools-$env:COMPUTERNAME.txt"
        Set-Content -Path $file -Value $text -Encoding UTF8
        Write-LTLog "Informe guardado en $file" -Level Ok
    }
}

#endregion


$LTConfigJson = @'
{
  "app": {
    "name": "Lyons Tools",
    "version": "1.1.0",
    "repo": "EhtuCom/LyonsTools",
    "publisher": "ehtu.com",
    "publisherUrl": "https://ehtu.com"
  },
  "tabs": [
    {
      "title": "Office",
      "intro": "Los ajustes de autoguardado se aplican como directiva para tu usuario (Windows pedir\u00e1 permiso de administrador una vez) y Office no los puede deshacer. Se activan al volver a abrir Word, Excel o PowerPoint.",
      "minutesInput": 5,
      "sections": [
        {
          "title": "Autoguardado y recuperaci\u00f3n",
          "items": [
            {
              "id": "word-autorecover",
              "label": "Autoguardado en Word cada N minutos",
              "description": "Activa la Autorrecuperaci\u00f3n de Word y guarda la informaci\u00f3n cada N minutos (Archivo > Opciones > Guardar).",
              "action": "Set-LTWordAutoRecover",
              "usesMinutes": true
            },
            {
              "id": "excel-autorecover",
              "label": "Autoguardado en Excel cada N minutos",
              "description": "Activa la Autorrecuperaci\u00f3n de Excel y guarda la informaci\u00f3n cada N minutos.",
              "action": "Set-LTExcelAutoRecover",
              "usesMinutes": true
            },
            {
              "id": "powerpoint-autorecover",
              "label": "Autoguardado en PowerPoint cada N minutos",
              "description": "Activa la Autorrecuperaci\u00f3n de PowerPoint y guarda la informaci\u00f3n cada N minutos.",
              "action": "Set-LTPowerPointAutoRecover",
              "usesMinutes": true
            },
            {
              "id": "office-crash-protection",
              "label": "Protecci\u00f3n completa contra cierres inesperados",
              "description": "Word, Excel y PowerPoint: autorrecuperaci\u00f3n cada N minutos, conservar la \u00faltima versi\u00f3n si se cierra sin guardar, y copia de seguridad autom\u00e1tica (.wbk) de cada documento de Word.",
              "action": "Enable-LTOfficeCrashProtection",
              "usesMinutes": true
            },
            {
              "id": "office-find-recoverable",
              "label": "Buscar documentos recuperables",
              "description": "Busca archivos de autorrecuperaci\u00f3n, copias de seguridad y documentos sin guardar de los \u00faltimos 30 d\u00edas y abre la carpeta.",
              "action": "Find-LTOfficeRecoverableFiles"
            },
            {
              "id": "office-autorecover-reset",
              "label": "Quitar los ajustes de autoguardado de Lyons Tools",
              "description": "Devuelve el control a Archivo > Opciones > Guardar (los ajustes anteriores quedan fijados y no se pueden cambiar desde Office).",
              "action": "Reset-LTOfficeAutoRecover"
            }
          ]
        },
        {
          "title": "Mantenimiento",
          "items": [
            {
              "id": "office-info",
              "label": "Ver versi\u00f3n de Office y ajustes de autoguardado",
              "description": "Muestra la versi\u00f3n, el canal de actualizaci\u00f3n y la configuraci\u00f3n actual de autorrecuperaci\u00f3n.",
              "action": "Get-LTOfficeInfo"
            },
            {
              "id": "office-update",
              "label": "Actualizar Office ahora",
              "description": "Busca e instala las actualizaciones de Microsoft 365 / Office.",
              "action": "Update-LTOffice"
            },
            {
              "id": "office-repair",
              "label": "Reparaci\u00f3n r\u00e1pida de Office",
              "description": "Repara Office sin conexi\u00f3n a Internet. \u00datil si Word o Excel se cierran solos o fallan al abrir. Cierra todos los programas de Office antes.",
              "action": "Repair-LTOffice"
            }
          ]
        }
      ]
    },
    {
      "title": "Firma digital",
      "intro": "Herramientas para certificados digitales de la FNMT y del Consorci AOC (idCAT, T-CAT), Autofirma y el Signador.",
      "sections": [
        {
          "title": "Certificados",
          "items": [
            {
              "id": "fnmt-configurador",
              "label": "Descargar e instalar el Configurador FNMT",
              "description": "Necesario para solicitar y descargar el certificado de persona f\u00edsica o de representante de la FNMT.",
              "action": "Install-LTFnmtConfigurator"
            },
            {
              "id": "fnmt-root-certs",
              "label": "Instalar certificados ra\u00edz de la FNMT",
              "description": "Instala la AC Ra\u00edz FNMT-RCM y las autoridades intermedias en el almac\u00e9n de Windows (lo usan Edge, Chrome y Office).",
              "action": "Install-LTFnmtRootCertificates"
            },
            {
              "id": "aoc-root-certs",
              "label": "Instalar certificados ra\u00edz del Consorci AOC (idCAT, T-CAT)",
              "description": "Instala la jerarqu\u00eda del Consorci AOC (CA CONSORCI AOC G3, EC-ACC, EC-Ciutadania...) necesaria para el idCAT Certificat, la T-CAT y las webs de la Generalitat y los ayuntamientos.",
              "action": "Install-LTAocRootCertificates"
            },
            {
              "id": "certs-list",
              "label": "Ver mis certificados digitales y su caducidad",
              "description": "Lista los certificados personales instalados y avisa de los que caducan en menos de 60 d\u00edas.",
              "action": "Get-LTPersonalCertificates"
            },
            {
              "id": "certs-manager",
              "label": "Abrir el administrador de certificados de Windows",
              "description": "Para exportar, importar o eliminar certificados (certmgr.msc).",
              "action": "Open-LTCertManager"
            }
          ]
        },
        {
          "title": "Aplicaciones de firma",
          "items": [
            {
              "id": "autofirma",
              "label": "Descargar e instalar Autofirma",
              "description": "Aplicaci\u00f3n del Gobierno de Espa\u00f1a para firmar en sedes electr\u00f3nicas (AEAT, Seguridad Social, Justicia...).",
              "action": "Install-LTAutofirma"
            },
            {
              "id": "signador",
              "label": "Instalar la aplicaci\u00f3n nativa del Signador (AOC)",
              "description": "Aplicaci\u00f3n del Consorci AOC para firmar en tr\u00e1mites de la Generalitat de Catalunya y ayuntamientos catalanes.",
              "action": "Install-LTSignador"
            },
            {
              "id": "tcat-middleware",
              "label": "Instalar el software de la tarjeta T-CAT (Bit4id PKI Manager)",
              "description": "Controlador para usar la T-CAT en tarjeta con un lector (tarjetas emitidas desde el 13/04/2023). Sustituye al antiguo SafeSign.",
              "action": "Install-LTTcatMiddleware"
            }
          ]
        },
        {
          "title": "Enlaces \u00fatiles",
          "items": [
            { "id": "link-fnmt", "label": "Sede FNMT - Obtener certificado de persona f\u00edsica", "url": "https://www.sede.fnmt.gob.es/certificados/persona-fisica" },
            { "id": "link-aeat", "label": "Sede electr\u00f3nica de la Agencia Tributaria (AEAT)", "url": "https://sede.agenciatributaria.gob.es/" },
            { "id": "link-atc", "label": "Ag\u00e8ncia Tribut\u00e0ria de Catalunya (ATC)", "url": "https://atc.gencat.cat/" },
            { "id": "link-lexnet", "label": "LexNET (Justicia)", "url": "https://lexnet.justicia.es/" },
            { "id": "link-valide", "label": "VALIDe - Validar certificados y firmas", "url": "https://valide.redsara.es/" },
            { "id": "link-idcat-mobil", "label": "idCAT M\u00f2bil - Darse de alta o gestionar", "url": "https://idcatmobil.seu.cat/" },
            { "id": "link-enotum", "label": "e-NOTUM - Notificaciones electr\u00f3nicas de las administraciones catalanas", "url": "https://www.aoc.cat/es/serveis-aoc/e-notum/" },
            { "id": "link-aoc-support", "label": "Soporte del Consorci AOC (idCAT, T-CAT, Signador)", "url": "https://suport.aoc.cat/" }
          ]
        }
      ]
    },
    {
      "title": "Java",
      "sections": [
        {
          "title": "Java",
          "items": [
            {
              "id": "java-check",
              "label": "Comprobar la versi\u00f3n de Java",
              "description": "Muestra el Java que usa el sistema, todas las versiones instaladas y la \u00faltima versi\u00f3n disponible.",
              "action": "Get-LTJavaInfo"
            },
            {
              "id": "java-install-temurin",
              "label": "Descargar e instalar la \u00faltima versi\u00f3n LTS de Java (Temurin)",
              "description": "Java gratuito y actualizado (OpenJDK de Eclipse Adoptium). Configura JAVA_HOME y abre los archivos .jar.",
              "action": "Install-LTJavaTemurin"
            },
            {
              "id": "java-install-oracle8",
              "label": "Descargar e instalar Java 8 de Oracle (java.com)",
              "description": "Solo para aplicaciones antiguas que piden espec\u00edficamente Java de Oracle.",
              "action": "Install-LTJavaOracle8"
            },
            {
              "id": "java-clear-cache",
              "label": "Vaciar la cach\u00e9 de Java",
              "description": "Soluciona errores de aplicaciones Java descargadas que no arrancan o usan una versi\u00f3n antigua.",
              "action": "Clear-LTJavaCache"
            }
          ]
        }
      ]
    },
    {
      "title": "Windows",
      "sections": [
        {
          "title": "Ajustes",
          "items": [
            {
              "id": "win-file-extensions",
              "label": "Mostrar las extensiones de archivo",
              "description": "Muestra .pdf, .docx, .exe... Ayuda a detectar adjuntos falsos como \"factura.pdf.exe\". Reinicia el Explorador.",
              "action": "Enable-LTFileExtensions"
            },
            {
              "id": "win-clipboard-history",
              "label": "Activar el historial del portapapeles (Windows + V)",
              "description": "Permite pegar cualquiera de los \u00faltimos textos o im\u00e1genes copiados.",
              "action": "Enable-LTClipboardHistory"
            }
          ]
        },
        {
          "title": "Utilidades",
          "items": [
            {
              "id": "win-report",
              "label": "Informe del equipo para soporte",
              "description": "Recoge Windows, Office, Java, aplicaciones de firma y certificados, y lo copia al portapapeles para enviarlo a ehtu.com.",
              "action": "Get-LTSystemReport"
            },
            {
              "id": "win-quick-assist",
              "label": "Asistencia remota (Asistencia r\u00e1pida de Windows)",
              "description": "Abre Asistencia r\u00e1pida para que el t\u00e9cnico de soporte se conecte a tu equipo.",
              "action": "Start-LTQuickAssist"
            },
            {
              "id": "win-clean-temp",
              "label": "Limpiar archivos temporales",
              "description": "Elimina archivos temporales del usuario y la cach\u00e9 de Internet.",
              "action": "Clear-LTTempFiles"
            },
            {
              "id": "win-flush-dns",
              "label": "Vaciar la cach\u00e9 DNS",
              "description": "\u00datil cuando una web o sede electr\u00f3nica no carga y en otros equipos s\u00ed.",
              "action": "Clear-LTDnsCache"
            },
            {
              "id": "win-restart-explorer",
              "label": "Reiniciar el Explorador de Windows",
              "description": "Soluciona la barra de tareas o el escritorio bloqueados.",
              "action": "Restart-LTExplorer"
            },
            {
              "id": "win-update",
              "label": "Abrir Windows Update",
              "description": "Abre la configuraci\u00f3n de actualizaciones de Windows.",
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
                    <Border Background="#33FFFFFF" CornerRadius="10" Padding="10,3" Margin="0,0,10,0">
                        <TextBlock x:Name="AdminBadge" Foreground="White" FontSize="12"/>
                    </Border>
                    <Button x:Name="Website" Content="ehtu.com" Style="{StaticResource GhostButton}" Foreground="White"/>
                </StackPanel>
                <StackPanel>
                    <TextBlock Text="Lyons Tools" Foreground="White" FontSize="22" FontWeight="Bold"/>
                    <TextBlock Text="Ajustes y utilidades para despachos: Windows, Office, Java y firma digital" Foreground="#D6E4F0"/>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- Tabs (filled from config/tools.json) -->
        <TabControl x:Name="Tabs" Grid.Row="1" Background="Transparent" BorderThickness="0,1,0,0"
                    BorderBrush="{StaticResource Line}" Padding="0" Margin="12,8,12,0"/>

        <!-- Action bar -->
        <Border Grid.Row="2" Background="White" BorderBrush="{StaticResource Line}" BorderThickness="0,1" Padding="16,8">
            <DockPanel>
                <Button x:Name="RunSelected" DockPanel.Dock="Right" Content="Ejecutar seleccionadas" Style="{StaticResource BaseButton}"/>
                <Button x:Name="ClearSelection" DockPanel.Dock="Right" Content="Desmarcar todo" Style="{StaticResource GhostButton}" Margin="0,0,8,0"/>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <ProgressBar x:Name="BusyBar" Width="90" Height="6" IsIndeterminate="True" Visibility="Collapsed" Margin="0,0,10,0"/>
                    <TextBlock x:Name="StatusText" Text="Listo." Foreground="{StaticResource Muted}" VerticalAlignment="Center"/>
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
                    <Button x:Name="CopyLog" Content="Copiar registro" Style="{StaticResource GhostButton}" Foreground="#9FB3C8"/>
                    <Button x:Name="OpenLogs" Content="Carpeta de registros" Style="{StaticResource GhostButton}" Foreground="#9FB3C8"/>
                </StackPanel>
                <TextBlock Text="Lyons Tools __LT_VERSION__ &#x00B7; soporte: ehtu.com" Foreground="#6B7C8F" FontSize="11" VerticalAlignment="Center"/>
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

$logDir = Join-Path $env:LOCALAPPDATA 'LyonsTools\logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$LT.LogDir = $logDir
$LT.LogFile = Join-Path $logDir ("{0:yyyy-MM-dd}.log" -f (Get-Date))

if ($List) {
    $LT.Items.Values | Sort-Object id | Format-Table @{ n = 'ID'; e = { $_.id } }, @{ n = "Acci$([char]0x00F3)n"; e = { $_.label } } -AutoSize
    return
}

if ($Run) {
    Write-LTLog "Lyons Tools $($LT.Version) - modo sin interfaz" -Level Step
    foreach ($id in ($Run -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $item = $LT.Items[$id]
        if (-not $item) { Write-LTLog "Acci$([char]0x00F3)n desconocida: $id (usa -List)" -Level Error; continue }
        Write-LTLog $item.label -Level Step
        try { Invoke-LTItem -Item $item -Minutes $Minutes }
        catch { Write-LTLog $_.Exception.Message -Level Error }
    }
    return
}

# WPF needs an STA thread. Windows PowerShell is STA by default; pwsh may not be.
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-Host 'Reiniciando Lyons Tools en modo STA...'
    if ($PSCommandPath) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    }
    else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -Command `"irm '$($LT.SourceUrl)' | iex`""
    }
    return
}

function Start-LTJob {
    <# Runs a list of items in a background runspace so the window never freezes. #>
    param([object[]]$Items, [int]$Minutes)

    if ($LT.Busy) { Write-LTLog "Espera a que termine la tarea en curso." -Level Warn; return }
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
                    Write-LTLog $item.label -Level Step
                    try { Invoke-LTItem -Item $item -Minutes $Minutes }
                    catch { Write-LTLog $_.Exception.Message -Level Error }
                }
                Write-LTLog "Terminado." -Level Ok
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
    if (-not $items.Count) { Write-LTLog "No hay ninguna acci$([char]0x00F3)n seleccionada." -Level Warn; return }
    $minutes = 5
    if ($items | Where-Object usesMinutes) {
        $minutes = Get-LTMinutes
        if (-not $minutes) { Write-LTLog "Indica un n$([char]0x00FA)mero de minutos entre 1 y 120." -Level Error; return }
    }
    Start-LTJob -Items $items -Minutes $minutes
}

function New-LTTextBlock([string]$Text, [string]$Style) {
    $tb = [Windows.Controls.TextBlock]::new()
    $tb.Text = $Text
    $tb.Style = $LT.Window.FindResource($Style)
    $tb
}

function Add-LTTabs {
    $tabs = $LT.Window.FindName('Tabs')
    $LT.CheckBoxes = @{}

    foreach ($tab in $LT.Config.tabs) {
        $panel = [Windows.Controls.StackPanel]::new()
        $panel.Margin = '16,8,16,16'

        if ($tab.intro) { [void]$panel.Children.Add((New-LTTextBlock $tab.intro 'IntroText')) }

        if ($tab.minutesInput) {
            $row = [Windows.Controls.StackPanel]::new()
            $row.Orientation = 'Horizontal'
            $row.Margin = '0,4,0,8'
            [void]$row.Children.Add((New-LTTextBlock "Intervalo de autoguardado (minutos):" 'FieldLabel'))
            $box = [Windows.Controls.TextBox]::new()
            $box.Text = [string]$tab.minutesInput
            $box.Style = $LT.Window.FindResource('MinutesBox')
            [void]$row.Children.Add($box)
            $LT.MinutesBox = $box
            [void]$panel.Children.Add($row)
        }

        foreach ($section in $tab.sections) {
            [void]$panel.Children.Add((New-LTTextBlock $section.title 'SectionHeader'))
            foreach ($item in $section.items) {
                $card = [Windows.Controls.Border]::new()
                $card.Style = $LT.Window.FindResource('Card')
                $grid = [Windows.Controls.Grid]::new()
                $c0 = [Windows.Controls.ColumnDefinition]::new(); $c0.Width = '*'
                $c1 = [Windows.Controls.ColumnDefinition]::new(); $c1.Width = 'Auto'
                $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)

                $text = [Windows.Controls.StackPanel]::new()
                [void]$text.Children.Add((New-LTTextBlock $item.label 'ItemTitle'))
                if ($item.description) { [void]$text.Children.Add((New-LTTextBlock $item.description 'ItemDescription')) }

                if ($item.url) {
                    $text.Margin = '22,0,0,0'
                    [void]$grid.Children.Add($text)
                }
                else {
                    $cb = [Windows.Controls.CheckBox]::new()
                    $cb.Content = $text
                    $cb.Tag = $item.id
                    $cb.Style = $LT.Window.FindResource('ItemCheck')
                    $LT.CheckBoxes[$item.id] = $cb
                    [void]$grid.Children.Add($cb)
                }

                $btn = [Windows.Controls.Button]::new()
                $btn.Content = if ($item.url) { 'Abrir' } else { 'Ejecutar' }
                $btn.Tag = $item.id
                $btn.Style = $LT.Window.FindResource($(if ($item.url) { 'LinkButton' } else { 'RunButton' }))
                [Windows.Controls.Grid]::SetColumn($btn, 1)
                $btn.Add_Click({ Invoke-LTSelection -Ids @($this.Tag) })
                [void]$grid.Children.Add($btn)
                $LT.Buttons.Add($btn)

                $card.Child = $grid
                [void]$panel.Children.Add($card)
            }
        }

        $scroll = [Windows.Controls.ScrollViewer]::new()
        $scroll.VerticalScrollBarVisibility = 'Auto'
        $scroll.Content = $panel
        $ti = [Windows.Controls.TabItem]::new()
        $ti.Header = $tab.title
        $ti.Content = $scroll
        [void]$tabs.Items.Add($ti)
    }
}

function Show-LTWindow {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xaml = $LTXaml.Replace('__LT_VERSION__', $LT.Version)
    $window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new([xml]$xaml))
    $LT.Window = $window
    $LT.Gui = $true
    $LT.LogQueue = [Collections.Concurrent.ConcurrentQueue[string]]::new()
    $LT.Buttons = [Collections.Generic.List[object]]::new()
    $LT.FunctionNames = @(Get-ChildItem function: | Where-Object { $_.Name -match '^[A-Za-z]+-LT' } | ForEach-Object Name)

    $LT.LogBox = $window.FindName('LogBox')
    $busyBar = $window.FindName('BusyBar')
    $status = $window.FindName('StatusText')
    $runSelected = $window.FindName('RunSelected')
    $LT.Buttons.Add($runSelected)

    $window.FindName('AdminBadge').Text = if (Test-LTAdmin) { 'Administrador' } else { "Usuario: $env:USERNAME" }

    Add-LTTabs

    $runSelected.Add_Click({
            $ids = @($LT.CheckBoxes.Values | Where-Object IsChecked | ForEach-Object Tag)
            Invoke-LTSelection -Ids $ids
        })
    $window.FindName('ClearSelection').Add_Click({ $LT.CheckBoxes.Values | ForEach-Object { $_.IsChecked = $false } })
    $window.FindName('CopyLog').Add_Click({
            if ($LT.LogBox.Text) { [Windows.Clipboard]::SetText($LT.LogBox.Text); Write-LTLog "Registro copiado al portapapeles." -Level Ok }
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
                foreach ($b in $LT.Buttons) { $b.IsEnabled = -not $busy }
                $busyBar.Visibility = if ($busy) { 'Visible' } else { 'Collapsed' }
                $status.Text = if ($busy) { 'Trabajando... puedes seguir mirando, no cierres la ventana.' } else { 'Listo.' }
                if (-not $busy -and $LT.Job) {
                    try { $LT.Job.PowerShell.EndInvoke($LT.Job.Handle) } catch { }
                    $LT.Job.PowerShell.Dispose(); $LT.Job.Runspace.Dispose()
                    $LT.Job = $null
                }
            }
        }.GetNewClosure())
    $timer.Start()

    $window.Add_Closing({
            if ($LT.Job) { try { $LT.Job.PowerShell.Stop() } catch { } }
        })

    Write-LTLog "Lyons Tools $($LT.Version) - marca las acciones y pulsa 'Ejecutar seleccionadas', o usa el bot$([char]0x00F3)n de cada fila."
    [void]$window.ShowDialog()
    $timer.Stop()
}

Show-LTWindow

#endregion
