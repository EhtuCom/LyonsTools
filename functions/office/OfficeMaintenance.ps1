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
        Write-LTLog "Version: $version" "Versión: $version" "Versió: $version"
        Write-LTLog "Channel: $channel" "Canal: $channel" "Canal: $channel"
        if ($c2r.Config.SharedComputerLicensing -eq '1') {
            Write-LTLog "Shared computer activation is on (terminal server)." "La activación de equipo compartido está activada (servidor de terminales)." "L'activació d'equip compartit està activada (servidor de terminals)."
        }
    }
    else {
        $msi = Get-LTInstalledApp -Name 'Microsoft Office|Microsoft 365' | Select-Object -First 1
        if ($msi) { Write-LTLog "Office (MSI): $($msi.DisplayName) $($msi.DisplayVersion)" }
        else { Write-LTLog "Office is not installed." "No se ha encontrado Office instalado." "No s'ha trobat Office instal·lat." -Level Warn }
    }

    foreach ($app in 'Word', 'Excel', 'PowerPoint') {
        $s = Get-LTAutoRecoverPolicyState -App $app
        if ($s) {
            $keep = if ($s.KeepLast) { Get-LTString 'yes' "sí" "sí" } else { 'no' }
            Write-LTLog "$($app): AutoRecover locked at $($s.Minutes) min; keep last version: $keep" `
                "$($app): autorrecuperación fijada cada $($s.Minutes) min; conservar última versión: $keep" `
                "$($app): recuperació automàtica fixada cada $($s.Minutes) min; conservar l'última versió: $keep"
        }
        else {
            Write-LTLog "$($app): AutoRecover set in Office (File > Options > Save)." `
                "$($app): autorrecuperación según Office (Archivo > Opciones > Guardar)." `
                "$($app): recuperació automàtica segons Office (Fitxer > Opcions > Desa)."
        }
    }
}

function Update-LTOffice {
    $c2r = Get-LTClickToRun
    if (-not $c2r.Client) {
        Write-LTLog "Office Click-to-Run not found. If it is an MSI version, update it with Windows Update." `
            "No se ha encontrado Office Click-to-Run. Si es una versión MSI, actualiza con Windows Update." `
            "No s'ha trobat Office Click-to-Run. Si és una versió MSI, actualitza-la amb Windows Update." -Level Warn
        return
    }
    Write-LTLog "Starting the Office update (the Office window will appear)..." "Iniciando la actualización de Office (se mostrará la ventana de Office)..." "Iniciant l'actualització d'Office (es mostrarà la finestra d'Office)..."
    Start-Process -FilePath $c2r.Client -ArgumentList '/update user updatepromptuser=true forceappshutdown=false displaylevel=true'
    Write-LTLog "Update started. Office will warn you if it needs to close any program." "Actualización lanzada. Office avisará si necesita cerrar algún programa." "Actualització iniciada. Office avisarà si cal tancar algun programa." -Level Ok
}

function Repair-LTOffice {
    $c2r = Get-LTClickToRun
    if (-not $c2r.RepairExe -or -not $c2r.Config) {
        Write-LTLog "Office Click-to-Run not found. Use Settings > Apps > Office > Modify." `
            "No se ha encontrado Office Click-to-Run. Usa Configuración > Aplicaciones > Office > Modificar." `
            "No s'ha trobat Office Click-to-Run. Fes servir Configuració > Aplicacions > Office > Modifica." -Level Warn
        Start-Process 'ms-settings:appsfeatures'
        return
    }
    $platform = if ($c2r.Config.Platform -eq 'x86') { 'x86' } else { 'x64' }
    $culture = ($c2r.Config.ClientCulture, 'en-us' | Where-Object { $_ } | Select-Object -First 1)
    Write-LTLog "Starting Office Quick Repair ($platform, $culture)..." "Lanzando la reparación rápida de Office ($platform, $culture)..." "Iniciant la reparació ràpida d'Office ($platform, $culture)..."
    $script = "Start-Process -FilePath '$($c2r.RepairExe)' -ArgumentList 'scenario=Repair platform=$platform culture=$culture RepairType=QuickRepair forceappshutdown=false DisplayLevel=True'"
    if ((Invoke-LTElevated -Script $script) -eq 0) {
        Write-LTLog "Repair started. Follow the instructions in the Office window." "Reparación lanzada. Sigue las instrucciones de la ventana de Office." "Reparació iniciada. Segueix les instruccions de la finestra d'Office." -Level Ok
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
        Write-LTLog "No recoverable documents found from the last 30 days." "No se han encontrado documentos recuperables en los últimos 30 días." "No s'han trobat documents recuperables dels últims 30 dies."
        Write-LTLog "Also try in Word/Excel: File > Info > Manage Document > Recover Unsaved Documents." `
            "Prueba también en Word/Excel: Archivo > Información > Administrar documento > Recuperar documentos no guardados." `
            "Prova també al Word/Excel: Fitxer > Informació > Gestiona el document > Recupera els documents no desats."
        return
    }
    $count = $files.Count
    Write-LTLog "Recoverable documents found ($count):" "Documentos recuperables encontrados ($count):" "Documents recuperables trobats ($count):" -Level Ok
    foreach ($f in $files | Select-Object -First 40) {
        Write-LTLog ("    {0:dd/MM/yyyy HH:mm}  {1}" -f $f.LastWriteTime, $f.FullName)
    }
    Write-LTLog "Open them with Word/Excel and use 'Save as' to keep them. Opening the folder of the most recent one..." `
        "Ábrelos con Word/Excel y usa 'Guardar como' para conservarlos. Abriendo la carpeta del más reciente..." `
        "Obre'ls amb el Word/Excel i fes servir 'Desa com a' per conservar-los. Obrint la carpeta del més recent..."
    Start-Process explorer.exe "/select,`"$($files[0].FullName)`""
}

#endregion
