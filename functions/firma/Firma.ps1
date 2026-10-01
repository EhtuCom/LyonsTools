#region Firma digital ------------------------------------------------------------

function Install-LTFnmtConfigurator {
    $page = 'https://www.sede.fnmt.gob.es/descargas/descarga-software'
    $url = $null
    try { $url = Find-LTWebLink -Url $page -Pattern 'descargas\.cert\.fnmt\.es/Windows/Configurador_FNMT_[\d.]+_64bits\.exe' }
    catch { Write-LTLog "No se ha podido consultar la web de la FNMT: $($_.Exception.Message)" -Level Warn }
    if (-not $url) {
        Write-LTLog "No se ha encontrado el enlace en la web de la FNMT. Abriendo la página de descargas." -Level Warn
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
        catch { Write-LTLog "Omitido: $([IO.Path]::GetFileName($file)) no es un certificado válido (la web puede haber bloqueado la descarga)." -Level Warn; continue }
        if ($seen.ContainsKey($cert.Thumbprint)) { continue }
        $seen[$cert.Thumbprint] = $true

        $name = $cert.GetNameInfo('SimpleName', $false)
        if ($cert.NotAfter -lt (Get-Date)) { Write-LTLog "Omitido (caducado): $name"; continue }
        if ($cert.Subject -eq $cert.Issuer) {
            if (-not $TrustedRoots.ContainsKey($cert.Thumbprint)) {
                Write-LTLog "Omitido: raíz desconocida '$name' ($($cert.Thumbprint)). No coincide con las raíces oficiales ($Issuer)." -Level Warn
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
    Write-LTLog "Instalando $($plan.Count) certificados ($Issuer) (se pedirá permiso de administrador)..."
    if ((Invoke-LTElevated -Script $script) -ne 0) {
        Write-LTLog "No se han podido instalar los certificados." -Level Error
        return
    }
    foreach ($c in $plan) {
        $where = if ($c.Store -eq 'Root') { "Entidades de certificación raíz de confianza" } else { "Entidades de certificación intermedias" }
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
    catch { Write-LTLog "No se ha podido leer la página de la FNMT, se usa la lista conocida." -Level Warn }
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
            Write-LTLog "Descargado el paquete de claves públicas del Consorci AOC: $url"
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
        Write-LTLog "Está instalado $($old[0].DisplayName). El Consorci AOC indica desinstalarlo antes (Configuración > Aplicaciones)." -Level Warn
    }
    try { $file = Save-LTFile -Url 'https://cdn.bit4id.com/es/AOC/middleware/Bit4id_AOC_Middleware.exe' }
    catch {
        Write-LTLog "Error al descargar: $($_.Exception.Message)" -Level Error
        Open-LTUrl 'https://suport.aoc.cat/ca-es/article/?servei=tcat&id=KA-07251_instal-lacio-del-programari-per-a-l-us-de-la-t-cat-en-targeta'
        return
    }
    if (-not (Test-LTSignature -Path $file)) { return }
    Write-LTLog "Sigue los pasos del instalador. Necesitarás un lector de tarjetas conectado para usar la T-CAT."
    if (Start-LTInstaller -Path $file) {
        Write-LTLog "Manual: https://cdn.bit4id.com/es/AOC/manuals/Windows/Windows.html"
    }
}

function Get-LTPersonalCertificates {
    $certs = @(Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue | Where-Object HasPrivateKey | Sort-Object NotAfter)
    if (-not $certs.Count) {
        Write-LTLog "No hay ningún certificado para firmar (con clave privada) en este usuario de Windows." -Level Warn
        return
    }
    $now = Get-Date
    foreach ($c in $certs) {
        $days = [int][math]::Floor(($c.NotAfter - $now).TotalDays)
        $name = $c.GetNameInfo('SimpleName', $false)
        $issuer = $c.GetNameInfo('SimpleName', $true)
        $msg = "{0}`n           Emisor: {1} | caduca el {2:dd/MM/yyyy}" -f $name, $issuer, $c.NotAfter
        if ($days -lt 0) { Write-LTLog "$msg (CADUCADO hace $(-$days) días)" -Level Error }
        elseif ($days -le 60) { Write-LTLog "$msg (caduca en $days días: renuévalo)" -Level Warn }
        else { Write-LTLog "$msg ($days días)" -Level Ok }
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
    if ($installed) { Write-LTLog "Autofirma ya está instalado: versión $($installed.DisplayVersion). Se reinstalará con la última versión." }

    try { $zip = Save-LTFile -Url $url -FileName 'Autofirma64.zip' }
    catch { Write-LTLog "Error al descargar Autofirma: $($_.Exception.Message)" -Level Error; Open-LTUrl $page; return }

    $dir = Join-Path (Get-LTWorkFolder) 'Autofirma'
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    $exe = Get-ChildItem -Path $dir -Filter '*.exe' -Recurse | Select-Object -First 1
    if (-not $exe) { Write-LTLog "El ZIP de Autofirma no contiene ningún instalador." -Level Error; return }
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
    Write-LTLog "Instalando la aplicación nativa del Signador (se pedirá permiso de administrador)..."
    $result = Invoke-LTElevated -Script $script
    if ($result -ne 0) {
        Write-LTLog "La instalación no se ha completado (código $result). Registro: $log" -Level Error
        return
    }
    $app = Get-LTInstalledApp -Name 'Signador' | Select-Object -First 1
    Write-LTLog "Signador instalado$(if ($app) { ": $($app.DisplayName) $($app.DisplayVersion)" })." -Level Ok
    Write-LTLog "Reinicia el navegador antes de firmar en trámites de la Generalitat."
}

#endregion
