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
        Write-LTLog "No hay ningún Java en el PATH (el comando 'java' no existe)." -Level Warn
    }

    $apps = @(Get-LTInstalledApp -Name '\bJava\b|\bJRE\b|\bJDK\b|Temurin|OpenJDK|Zulu|Corretto')
    if ($apps.Count) {
        Write-LTLog "Programas Java instalados:"
        foreach ($a in $apps) { Write-LTLog ("    {0}  [{1}]" -f $a.DisplayName, $a.DisplayVersion) }
    }
    else {
        Write-LTLog "No se ha encontrado ningún Java instalado en Programas y características."
    }

    foreach ($key in 'HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment', 'HKLM:\SOFTWARE\WOW6432Node\JavaSoft\Java Runtime Environment') {
        $cur = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).CurrentVersion
        if ($cur) {
            $bits = if ($key -match 'WOW6432') { '32 bits' } else { '64 bits' }
            Write-LTLog "Java de Oracle registrado ($bits): versión $cur"
        }
    }

    try {
        $latest = Invoke-RestMethod -Uri 'https://api.adoptium.net/v3/info/available_releases' -UseBasicParsing -ErrorAction Stop
        Write-LTLog "Última versión LTS de Java disponible: $($latest.most_recent_lts) (Temurin). Java 8 sigue siendo la versión de java.com." -Level Ok
    }
    catch { }
}

function Install-LTJavaTemurin {
    <# Installs the latest LTS Eclipse Temurin JRE (free OpenJDK build) from the Adoptium API. #>
    Write-LTLog "Buscando la última versión LTS de Eclipse Temurin..."
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
        Write-LTLog "Versión encontrada: $($asset.release_name)"
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
        Write-LTLog "No se ha podido descargar desde java.com ($($_.Exception.Message)). Abriendo la página oficial." -Level Warn
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
        Write-LTLog "Vaciando la caché con $($javaws.FullName)"
        Start-Process -FilePath $javaws.FullName -ArgumentList '-uninstall', '-clearcache' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
    }
    $cache = Join-Path $env:USERPROFILE 'AppData\LocalLow\Sun\Java\Deployment\cache'
    if (Test-Path $cache) {
        Remove-Item -Path "$cache\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-LTLog "Caché de Java eliminada: $cache" -Level Ok
    }
    elseif (-not $javaws) {
        Write-LTLog "No hay caché de Java que limpiar."
    }
    else {
        Write-LTLog "Caché de Java vaciada." -Level Ok
    }
}

#endregion
