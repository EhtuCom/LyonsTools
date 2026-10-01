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
        Write-LTLog "Download link not found on the FNMT website. Opening the downloads page." "No se ha encontrado el enlace en la web de la FNMT. Abriendo la página de descargas." "No s'ha trobat l'enllaç al web de la FNMT. Obrint la pàgina de descàrregues." -Level Warn
        Open-LTUrl $page
        return
    }
    try { $file = Save-LTFile -Url $url }
    catch { $err = $_.Exception.Message; Write-LTLog "Download error: $err" "Error al descargar: $err" "Error en descarregar: $err" -Level Error; return }
    if (-not (Test-LTSignature -Path $file -ExpectedPublisher 'Nacional de Moneda y Timbre')) { return }
    Write-LTLog "Follow the steps of the FNMT Configurator installer." "Sigue los pasos del instalador del Configurador FNMT." "Segueix els passos de l'instal·lador del Configurador FNMT."
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
                "Omitido: $fileName no es un certificado válido (la web puede haber bloqueado la descarga)." `
                "Omès: $fileName no és un certificat vàlid (el web pot haver bloquejat la descàrrega)." -Level Warn
            continue
        }
        if ($seen.ContainsKey($cert.Thumbprint)) { continue }
        $seen[$cert.Thumbprint] = $true

        $name = $cert.GetNameInfo('SimpleName', $false)
        if ($cert.NotAfter -lt (Get-Date)) { Write-LTLog "Skipped (expired): $name" "Omitido (caducado): $name" "Omès (caducat): $name"; continue }
        if ($cert.Subject -eq $cert.Issuer) {
            if (-not $TrustedRoots.ContainsKey($cert.Thumbprint)) {
                $tp = $cert.Thumbprint
                Write-LTLog "Skipped: unknown root '$name' ($tp). It does not match the official roots ($Issuer)." `
                    "Omitido: raíz desconocida '$name' ($tp). No coincide con las raíces oficiales ($Issuer)." `
                    "Omès: arrel desconeguda '$name' ($tp). No coincideix amb les arrels oficials ($Issuer)." -Level Warn
                continue
            }
            [pscustomobject]@{ File = $file; Store = 'Root'; Name = $name }
        }
        else {
            [pscustomobject]@{ File = $file; Store = 'CA'; Name = $name }
        }
    }
    $plan = @($plan)
    if (-not $plan.Count) { Write-LTLog "There are no certificates to install." "No hay certificados para instalar." "No hi ha certificats per instal·lar." -Level Error; return }
    $count = $plan.Count

    if ($LT.CanElevate) {
        $script = ($plan | ForEach-Object {
                "Import-Certificate -FilePath '$($_.File)' -CertStoreLocation 'Cert:\LocalMachine\$($_.Store)' | Out-Null"
            }) -join "`n"
        Write-LTLog "Installing $count certificates ($Issuer) for all users (administrator permission will be requested)..." `
            "Instalando $count certificados ($Issuer) para todos los usuarios (se pedirá permiso de administrador)..." `
            "Instal·lant $count certificats ($Issuer) per a tots els usuaris (es demanarà permís d'administrador)..."
        if ((Invoke-LTElevated -Script $script) -ne 0) {
            Write-LTLog "The certificates could not be installed." "No se han podido instalar los certificados." "No s'han pogut instal·lar els certificats." -Level Error
            return
        }
    }
    else {
        Write-LTLog "Installing $count certificates ($Issuer) for your user. Windows will ask you to confirm each root certificate: answer 'Yes'." `
            "Instalando $count certificados ($Issuer) para tu usuario. Windows pedirá confirmar cada certificado raíz: responde 'Sí'." `
            "Instal·lant $count certificats ($Issuer) per al teu usuari. Windows demanarà confirmar cada certificat arrel: respon 'Sí'."
        foreach ($c in $plan) {
            try { Import-Certificate -FilePath $c.File -CertStoreLocation "Cert:\CurrentUser\$($c.Store)" -ErrorAction Stop | Out-Null }
            catch {
                $n = $c.Name
                Write-LTLog "Not installed: $n" "No instalado: $n" "No instal·lat: $n" -Level Warn
                $c.Store = $null
            }
        }
    }
    foreach ($c in $plan | Where-Object Store) {
        $where = if ($c.Store -eq 'Root') {
            Get-LTString 'Trusted Root Certification Authorities' "Entidades de certificación raíz de confianza" "Entitats de certificació arrel de confiança"
        }
        else {
            Get-LTString 'Intermediate Certification Authorities' "Entidades de certificación intermedias" "Entitats de certificació intermèdies"
        }
        $n = $c.Name
        Write-LTLog "Installed: $n  ->  $where" "Instalado: $n  ->  $where" "Instal·lat: $n  ->  $where" -Level Ok
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
    catch { Write-LTLog "The FNMT page could not be read; using the known list." "No se ha podido leer la página de la FNMT, se usa la lista conocida." "No s'ha pogut llegir la pàgina de la FNMT; es fa servir la llista coneguda." -Level Warn }
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
            Write-LTLog "Downloaded the Consorci AOC public key bundle: $url" "Descargado el paquete de claves públicas del Consorci AOC: $url" "Descarregat el paquet de claus públiques del Consorci AOC: $url"
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
            "Está instalado $n. El Consorci AOC indica desinstalarlo antes (Configuración > Aplicaciones)." `
            "Hi ha instal·lat $n. El Consorci AOC indica desinstal·lar-lo abans (Configuració > Aplicacions)." -Level Warn
    }
    try { $file = Save-LTFile -Url 'https://cdn.bit4id.com/es/AOC/middleware/Bit4id_AOC_Middleware.exe' }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "Download error: $err" "Error al descargar: $err" "Error en descarregar: $err" -Level Error
        Open-LTUrl 'https://suport.aoc.cat/ca-es/article/?servei=tcat&id=KA-07251_instal-lacio-del-programari-per-a-l-us-de-la-t-cat-en-targeta'
        return
    }
    if (-not (Test-LTSignature -Path $file -ExpectedPublisher 'BIT4ID')) { return }
    Write-LTLog "Follow the installer steps. You will need a card reader connected to use the T-CAT." `
        "Sigue los pasos del instalador. Necesitarás un lector de tarjetas conectado para usar la T-CAT." `
        "Segueix els passos de l'instal·lador. Necessitaràs un lector de targetes connectat per fer servir la T-CAT."
    if (Start-LTInstaller -Path $file) {
        Write-LTLog "Manual: https://cdn.bit4id.com/es/AOC/manuals/Windows/Windows.html"
    }
}

function Get-LTPersonalCertificates {
    $certs = @(Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue | Where-Object HasPrivateKey | Sort-Object NotAfter)
    if (-not $certs.Count) {
        Write-LTLog "There are no signing certificates (with a private key) for this Windows user." `
            "No hay ningún certificado para firmar (con clave privada) en este usuario de Windows." `
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
        if ($days -lt 0) { Write-LTLog "$base (EXPIRED $ago days ago)" "$base (CADUCADO hace $ago días)" "$base (CADUCAT fa $ago dies)" -Level Error }
        elseif ($days -le 60) { Write-LTLog "$base (expires in $days days: renew it)" "$base (caduca en $days días: renuévalo)" "$base (caduca d'aquí a $days dies: renova'l)" -Level Warn }
        else { Write-LTLog "$base ($days days)" "$base ($days días)" "$base ($days dies)" -Level Ok }
    }
    if ($certs | Where-Object { $_.NotAfter -lt $now }) {
        Write-LTLog "Expired certificates can be deleted from the certificate manager." "Los certificados caducados se pueden eliminar desde el administrador de certificados." "Els certificats caducats es poden eliminar des de l'administrador de certificats."
    }
}

function Open-LTCertManager {
    Start-Process certmgr.msc
    Write-LTLog "Certificate manager opened. Your certificates are in Personal > Certificates." `
        "Abierto el administrador de certificados. Tus certificados están en Personal > Certificados." `
        "S'ha obert l'administrador de certificats. Els teus certificats són a Personal > Certificats." -Level Ok
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
            "Autofirma ya está instalado: versión $v. Se reinstalará con la última versión." `
            "Autofirma ja està instal·lat: versió $v. Es reinstal·larà amb l'última versió."
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
    if (-not $exe) { Write-LTLog "The Autofirma ZIP does not contain an installer." "El ZIP de Autofirma no contiene ningún instalador." "El ZIP d'Autofirma no conté cap instal·lador." -Level Error; return }
    if (-not (Test-LTSignature -Path $exe.FullName -ExpectedPublisher 'ADMINISTRACION DIGITAL|Gobierno de Espa|SECRETARIA GENERAL')) { return }

    # Silent mode shows a blocking dialog if the same version is already installed, so only use /S on clean machines.
    $arguments = if ($installed) { $null } else { '/S' }
    if (Start-LTInstaller -Path $exe.FullName -Arguments $arguments) {
        Write-LTLog "Autofirma installed. Restart the browser before signing." "Autofirma instalado. Reinicia el navegador antes de firmar." "Autofirma instal·lat. Reinicia el navegador abans de signar." -Level Ok
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
        if (-not (Test-LTSignature -Path $exe -ExpectedPublisher 'Consorci Administraci')) { return }
        Write-LTLog "Installing the Signador for your user only. Follow the installer steps." `
            "Instalando el Signador solo para tu usuario. Sigue los pasos del instalador." `
            "Instal·lant el Signador només per al teu usuari. Segueix els passos de l'instal·lador."
        $p = Start-Process -FilePath $exe -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            $code = $p.ExitCode
            Write-LTLog "The installer finished with code $code." "El instalador ha terminado con código $code." "L'instal·lador ha acabat amb el codi $code." -Level Warn
            return
        }
        $crt = Get-ChildItem -Path $env:LOCALAPPDATA, $env:APPDATA, $env:USERPROFILE -Filter root.crt -Recurse -Depth 6 -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'Signador|AOC' -and $_.FullName -match 'lib\\certificate' } | Select-Object -First 1
        if ($crt) {
            $thumb = ([Security.Cryptography.X509Certificates.X509Certificate2]::new($crt.FullName)).Thumbprint
            if (-not (Test-Path "Cert:\CurrentUser\Root\$thumb")) {
                Write-LTLog "Windows will ask to trust the Signador local certificate: answer 'Yes'." "Windows pedirá confiar en el certificado local del Signador: responde 'Sí'." "Windows demanarà confiar en el certificat local del Signador: respon 'Sí'."
                try { Import-Certificate -FilePath $crt.FullName -CertStoreLocation Cert:\CurrentUser\Root -ErrorAction Stop | Out-Null } catch { }
            }
        }
        Write-LTLog "Signador installed. Restart the browser before signing." "Signador instalado. Reinicia el navegador antes de firmar." "Signador instal·lat. Reinicia el navegador abans de signar." -Level Ok
        return
    }

    try { $msi = Save-LTFile -Url 'https://signador.aoc.cat/signador/getNativa?os=windows&arch=64&msi' -FileName 'AppNativaSignador-x64.msi' }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "Signador download error: $err" "Error al descargar el Signador: $err" "Error en descarregar el Signador: $err" -Level Error
        Open-LTUrl 'https://signador.aoc.cat/signador/installNativa'
        return
    }
    if (-not (Test-LTSignature -Path $msi -ExpectedPublisher 'Consorci Administraci')) { return }

    $log = Join-Path (Get-LTWorkFolder) 'signador-install.log'
    $script = @"
`$p = Start-Process msiexec.exe -ArgumentList '/i "$msi" /passive /norestart sys.languageId=$lang /Lp "$log"' -Wait -PassThru
if (`$p.ExitCode -notin 0, 3010) { exit `$p.ExitCode }
`$crt = Get-ChildItem -Path "`$env:ProgramFiles", "`${env:ProgramFiles(x86)}" -Filter root.crt -Recurse -Depth 5 -ErrorAction SilentlyContinue |
    Where-Object { `$_.FullName -match 'Signador|AOC' -and `$_.FullName -match 'lib\\certificate' } | Select-Object -First 1
if (`$crt) { Import-Certificate -FilePath `$crt.FullName -CertStoreLocation Cert:\LocalMachine\Root | Out-Null }
"@
    Write-LTLog "Installing the Signador native app for all users (administrator permission will be requested)..." `
        "Instalando la aplicación nativa del Signador para todos los usuarios (se pedirá permiso de administrador)..." `
        "Instal·lant l'aplicació nativa del Signador per a tots els usuaris (es demanarà permís d'administrador)..."
    $result = Invoke-LTElevated -Script $script
    if ($result -ne 0) {
        Write-LTLog "The installation did not complete (code $result). Log: $log" "La instalación no se ha completado (código $result). Registro: $log" "La instal·lació no s'ha completat (codi $result). Registre: $log" -Level Error
        return
    }
    $app = Get-LTInstalledApp -Name 'Signador' | Select-Object -First 1
    $detail = if ($app) { ": $($app.DisplayName) $($app.DisplayVersion)" } else { '' }
    Write-LTLog "Signador installed$detail." "Signador instalado$detail." "Signador instal·lat$detail." -Level Ok
    Write-LTLog "Restart the browser before signing in Generalitat procedures." "Reinicia el navegador antes de firmar en trámites de la Generalitat." "Reinicia el navegador abans de signar en tràmits de la Generalitat."
}

#endregion
