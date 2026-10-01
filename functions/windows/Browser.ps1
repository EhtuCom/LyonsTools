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
                "$Browser no está instalado y para instalarlo hace falta un administrador." `
                "$Browser no està instal·lat i per instal·lar-lo cal un administrador." -Level Warn
            return
        }
        Write-LTLog "$Browser is not installed. Installing it..." "$Browser no está instalado. Instalándolo..." "$Browser no està instal·lat. Instal·lant-lo..." -Level Warn
        if (-not (Install-LTWinget -Id $b.Winget)) {
            if (-not (Install-LTBrowserDirect -Browser $Browser)) { return }
        }
        $b = Get-LTBrowserInfo -Browser $Browser
        if (-not $b.Path) { Write-LTLog "$Browser could not be found after installing it." "No se encuentra $Browser después de instalarlo." "No es troba $Browser després d'instal·lar-lo." -Level Error; return }
    }
    if (Test-LTDefaultBrowser $b.ProgId) {
        Write-LTLog "$Browser is already the default browser." "$Browser ya es el navegador predeterminado." "$Browser ja és el navegador predeterminat." -Level Ok
        return
    }

    Test-LTAssociationPolicy

    # Firefox can usually set itself as default (also on Windows 10 / Server).
    if ($Browser -eq 'Firefox') {
        Start-Process -FilePath $b.Path -ArgumentList $b.Switch -Wait -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (Test-LTDefaultBrowser $b.ProgId) {
            Write-LTLog "Done: Firefox is now the default browser." "Hecho: Firefox es ahora el navegador predeterminado." "Fet: Firefox és ara el navegador predeterminat." -Level Ok
            return
        }
    }

    $build = [Environment]::OSVersion.Version.Build
    if ($build -ge 22000 -and $b.Registered) {
        # Windows 11 / Server 2025: Settings opens on the browser's own page with a "Set default" button.
        $name = [Uri]::EscapeDataString($b.Registered.Name)
        Start-Process "ms-settings:defaultapps?$($b.Registered.Scope)=$name"
        Write-LTLog "Settings has opened on the $Browser page: press 'Set default' at the top." `
            "Se ha abierto Configuración en la página de ${Browser}: pulsa 'Establecer como predeterminado' arriba." `
            "S'ha obert Configuració a la pàgina de ${Browser}: prem 'Estableix com a predeterminat' a dalt." -Level Step
    }
    else {
        # Windows 10 / Server 2016-2022: the browsers' --make-default-browser switch is not reliable
        # here (Edge just opens a window), so go straight to Settings > Default apps.
        Start-Process 'ms-settings:defaultapps'
        Write-LTLog "In Settings > Default apps, click the browser under 'Web browser' and choose $Browser." `
            "En Configuración > Aplicaciones predeterminadas, pulsa el navegador que aparece en 'Explorador web' y elige $Browser." `
            "A Configuració > Aplicacions predeterminades, prem el navegador que surt a 'Navegador web' i tria $Browser." -Level Step
    }

    # Wait for the user's choice and confirm it, instead of assuming it worked.
    Write-LTLog "Waiting for the change (up to 2 minutes)..." "Esperando el cambio (hasta 2 minutos)..." "Esperant el canvi (fins a 2 minuts)..."
    $deadline = (Get-Date).AddMinutes(2)
    while ((Get-Date) -lt $deadline) {
        if (Test-LTDefaultBrowser $b.ProgId) {
            Write-LTLog "Done: $Browser is now the default browser." "Hecho: $Browser es ahora el navegador predeterminado." "Fet: $Browser és ara el navegador predeterminat." -Level Ok
            return
        }
        Start-Sleep -Seconds 2
    }
    Write-LTLog "$Browser is not the default browser yet. Finish the choice in Settings and use the 'Test' button to check it." `
        "$Browser todavía no es el navegador predeterminado. Termina la elección en Configuración y usa el botón 'Prueba' para comprobarlo." `
        "$Browser encara no és el navegador predeterminat. Acaba l'elecció a Configuració i fes servir el botó 'Prova' per comprovar-ho." -Level Warn
}

function Test-LTAssociationPolicy {
    <#
        Warns if a Group Policy "default associations configuration file" is set (common on
        domain-joined terminal servers): it re-applies its browser/PDF defaults at every sign-in.
    #>
    $file = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -ErrorAction SilentlyContinue).DefaultAssociationsConfiguration
    if (-not $file) { return $false }
    Write-LTLog "A Group Policy sets the default apps on this computer ($file). Any change may be undone at the next sign-in; ask the domain administrator to change that file." `
        "Una directiva de grupo fija las aplicaciones predeterminadas en este equipo ($file). El cambio puede deshacerse al volver a iniciar sesión; pide al administrador del dominio que cambie ese archivo." `
        "Una directiva de grup fixa les aplicacions predeterminades en aquest equip ($file). El canvi es pot desfer en tornar a iniciar sessió; demana a l'administrador del domini que canviï aquest fitxer." -Level Warn
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
        Write-LTLog "Note: http links open with $http (https with $https)." "Atención: los enlaces http se abren con $http (https con $https)." "Atenció: els enllaços http s'obren amb $http (https amb $https)." -Level Warn
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
