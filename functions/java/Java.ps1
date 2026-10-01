#region Java ------------------------------------------------------------------

function Get-LTJavaInfo {
    Write-LTLog "Installed Java versions" "Versiones de Java instaladas" "Versions de Java instal·lades"

    $java = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($java) {
        $path = $java.Source
        Write-LTLog "Default Java (PATH): $path" "Java por defecto (PATH): $path" "Java per defecte (PATH): $path"
        $out = & cmd.exe /c "`"$path`" -version 2>&1"
        $out | ForEach-Object { Write-LTLog "    $_" }
    }
    else {
        Write-LTLog "There is no Java in the PATH (the 'java' command does not exist)." `
            "No hay ningún Java en el PATH (el comando 'java' no existe)." `
            "No hi ha cap Java al PATH (l'ordre 'java' no existeix)." -Level Warn
    }

    $apps = @(Get-LTInstalledApp -Name '\bJava\b|\bJRE\b|\bJDK\b|Temurin|OpenJDK|Zulu|Corretto')
    if ($apps.Count) {
        Write-LTLog "Installed Java programs:" "Programas Java instalados:" "Programes Java instal·lats:"
        foreach ($a in $apps) { Write-LTLog ("    {0}  [{1}]" -f $a.DisplayName, $a.DisplayVersion) }
    }
    else {
        Write-LTLog "No Java found in Installed apps." "No se ha encontrado ningún Java instalado en Programas y características." "No s'ha trobat cap Java instal·lat a Programes i característiques."
    }

    foreach ($key in 'HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment', 'HKLM:\SOFTWARE\WOW6432Node\JavaSoft\Java Runtime Environment') {
        $cur = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).CurrentVersion
        if ($cur) {
            $bits = if ($key -match 'WOW6432') { '32' } else { '64' }
            Write-LTLog "Registered Oracle Java ($bits-bit): version $cur" "Java de Oracle registrado ($bits bits): versión $cur" "Java d'Oracle registrat ($bits bits): versió $cur"
        }
    }

    try {
        $lts = (Invoke-RestMethod -Uri 'https://api.adoptium.net/v3/info/available_releases' -UseBasicParsing -ErrorAction Stop).most_recent_lts
        Write-LTLog "Latest Java LTS available: $lts (Temurin). Java 8 is still the java.com version." `
            "Última versión LTS de Java disponible: $lts (Temurin). Java 8 sigue siendo la versión de java.com." `
            "Última versió LTS de Java disponible: $lts (Temurin). Java 8 continua sent la versió de java.com." -Level Ok
    }
    catch { }
}

function Install-LTJavaTemurin {
    <# Installs the latest LTS Eclipse Temurin JRE (free OpenJDK build) from the Adoptium API. #>
    Write-LTLog "Looking for the latest Eclipse Temurin LTS..." "Buscando la última versión LTS de Eclipse Temurin..." "Cercant l'última versió LTS d'Eclipse Temurin..."
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
        Write-LTLog "Version found: $release" "Versión encontrada: $release" "Versió trobada: $release"
        $file = Save-LTFile -Url $installer.link -FileName $installer.name
    }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "Temurin could not be downloaded: $err" "No se ha podido descargar Temurin: $err" "No s'ha pogut descarregar Temurin: $err" -Level Error
        Write-LTLog "Trying winget..." "Probando con winget..." "Provant amb winget..."
        if (-not (Install-LTWinget -Id "EclipseAdoptium.Temurin.$lts.JRE")) { Open-LTUrl 'https://adoptium.net/temurin/releases/' }
        return
    }
    if (-not (Test-LTSignature -Path $file -ExpectedPublisher 'Eclipse')) { return }
    # FeatureEnvironment/FeatureJavaHome set PATH and JAVA_HOME, FeatureJarFileRunWith opens .jar files,
    # FeatureOracleJavaSoft writes the HKLM\SOFTWARE\JavaSoft keys that older apps look for.
    [void](Start-LTInstaller -Path $file -Arguments 'ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome,FeatureOracleJavaSoft /passive /norestart')
}

function Install-LTJavaOracle8 {
    <# Oracle Java 8 (the one on java.com), still required by some old government applets/apps. #>
    Write-LTLog "Installing Oracle Java 8 (java.com)..." "Instalando Oracle Java 8 (java.com)..." "Instal·lant Oracle Java 8 (java.com)..."
    if (Install-LTWinget -Id 'Oracle.JavaRuntimeEnvironment') {
        Write-LTLog "Oracle Java 8 installed or already up to date." "Oracle Java 8 instalado o ya actualizado." "Oracle Java 8 instal·lat o ja actualitzat." -Level Ok
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
        if (-not (Test-LTSignature -Path $file -ExpectedPublisher 'Oracle')) { return }
        [void](Start-LTInstaller -Path $file -Arguments '/s')
    }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "Could not download from java.com ($err). Opening the official page." `
            "No se ha podido descargar desde java.com ($err). Abriendo la página oficial." `
            "No s'ha pogut descarregar des de java.com ($err). Obrint la pàgina oficial." -Level Warn
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
        Write-LTLog "Clearing the cache with $exe" "Vaciando la caché con $exe" "Buidant la memòria cau amb $exe"
        Start-Process -FilePath $exe -ArgumentList '-uninstall', '-clearcache' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
    }
    $cache = Join-Path $env:USERPROFILE 'AppData\LocalLow\Sun\Java\Deployment\cache'
    if (Test-Path $cache) {
        Remove-Item -Path "$cache\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-LTLog "Java cache deleted: $cache" "Caché de Java eliminada: $cache" "Memòria cau de Java eliminada: $cache" -Level Ok
    }
    elseif (-not $javaws) {
        Write-LTLog "There is no Java cache to clean." "No hay caché de Java que limpiar." "No hi ha memòria cau de Java per netejar."
    }
    else {
        Write-LTLog "Java cache cleared." "Caché de Java vaciada." "Memòria cau de Java buidada." -Level Ok
    }
}

#endregion
