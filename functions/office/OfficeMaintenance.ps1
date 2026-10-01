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
            '64256afe-f5d9-4f86-8936-8840a6a4f5be' { "Actual (versión preliminar)" }
            default { $c2r.Config.CDNBaseUrl }
        }
        Write-LTLog "Office: $($c2r.Config.ProductReleaseIds)"
        Write-LTLog "Versión: $($c2r.Config.VersionToReport) ($($c2r.Config.Platform))"
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
        Write-LTLog ("{0,-11} autorrecuperación {1}; conservar última versión: {2}" -f $app, $state, $(if ($s.KeepLast) { "sí" } else { "no" }))
    }
}

function Update-LTOffice {
    $c2r = Get-LTClickToRun
    if (-not $c2r.Client) {
        Write-LTLog "No se ha encontrado Office Click-to-Run. Si es una versión MSI, actualiza con Windows Update." -Level Warn
        return
    }
    Write-LTLog "Iniciando la actualización de Office (se mostrará la ventana de Office)..."
    Start-Process -FilePath $c2r.Client -ArgumentList '/update user updatepromptuser=true forceappshutdown=false displaylevel=true'
    Write-LTLog "Actualización lanzada. Office avisará si necesita cerrar algún programa." -Level Ok
}

function Repair-LTOffice {
    $c2r = Get-LTClickToRun
    if (-not $c2r.RepairExe -or -not $c2r.Config) {
        Write-LTLog "No se ha encontrado Office Click-to-Run. Usa Configuración > Aplicaciones > Office > Modificar." -Level Warn
        Start-Process 'ms-settings:appsfeatures'
        return
    }
    $platform = if ($c2r.Config.Platform -eq 'x86') { 'x86' } else { 'x64' }
    $culture = ($c2r.Config.ClientCulture, 'es-es' | Where-Object { $_ } | Select-Object -First 1)
    Write-LTLog "Lanzando la reparación rápida de Office ($platform, $culture)..."
    $script = "Start-Process -FilePath '$($c2r.RepairExe)' -ArgumentList 'scenario=Repair platform=$platform culture=$culture RepairType=QuickRepair forceappshutdown=false DisplayLevel=True'"
    if ((Invoke-LTElevated -Script $script) -eq 0) {
        Write-LTLog "Reparación lanzada. Sigue las instrucciones de la ventana de Office." -Level Ok
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
        Write-LTLog "No se han encontrado documentos recuperables en los últimos 30 días."
        Write-LTLog "Prueba también en Word/Excel: Archivo > Información > Administrar documento > Recuperar documentos no guardados."
        return
    }
    Write-LTLog "Documentos recuperables encontrados ($($files.Count)):" -Level Ok
    foreach ($f in $files | Select-Object -First 40) {
        Write-LTLog ("    {0:dd/MM/yyyy HH:mm}  {1}" -f $f.LastWriteTime, $f.FullName)
    }
    Write-LTLog "Ábrelos con Word/Excel y usa 'Guardar como' para conservarlos. Abriendo la carpeta del más reciente..."
    Start-Process explorer.exe "/select,`"$($files[0].FullName)`""
}

function Open-LTCertManager {
    Start-Process certmgr.msc
    Write-LTLog "Abierto el administrador de certificados. Tus certificados están en Personal > Certificados." -Level Ok
}

#endregion
