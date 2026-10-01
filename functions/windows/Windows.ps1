#region Windows -----------------------------------------------------------------

function Enable-LTFileExtensions {
    # Showing extensions helps users spot "factura.pdf.exe" style phishing attachments.
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 -Type DWord
    Write-LTLog "Ahora se mostrarán las extensiones de archivo (.pdf, .docx, .exe...)." -Level Ok
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
    Write-LTLog "Caché DNS vaciada." -Level Ok
}

function Start-LTQuickAssist {
    Write-LTLog "Abriendo Asistencia rápida. Elige 'Ayudar a alguien' o introduce el código que te dé el técnico."
    try { Start-Process 'ms-quick-assist:' -ErrorAction Stop }
    catch {
        Write-LTLog "Asistencia rápida no está instalada. Abriendo Microsoft Store..." -Level Warn
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
    $lines.Add("Usuario:     $env:USERDOMAIN\$env:USERNAME (administrador: $(if (Test-LTAdmin) { "sí" } else { "no" }))")
    $lines.Add("Windows:     $($os.Caption) $display (build $($os.BuildNumber))")
    $lines.Add("Memoria:     $([math]::Round($cs.TotalPhysicalMemory / 1GB, 1)) GB")
    $lines.Add("Disco $($env:SystemDrive)    $([math]::Round($disk.FreeSpace / 1GB, 1)) GB libres de $([math]::Round($disk.Size / 1GB, 1)) GB")
    if ($c2r) { $lines.Add("Office:      $($c2r.ProductReleaseIds) $($c2r.VersionToReport) ($($c2r.Platform))") }
    else { $lines.Add("Office:      no se ha detectado Office Click-to-Run") }

    $java = Get-Command java.exe -ErrorAction SilentlyContinue
    $javaVer = if ($java) { (& cmd.exe /c "`"$($java.Source)`" -version 2>&1" | Select-Object -First 1) } else { "no está en el PATH" }
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
        Write-LTLog "Informe copiado al portapapeles. Pégalo en un correo a soporte." -Level Ok
    }
    catch {
        $file = Join-Path ([Environment]::GetFolderPath('Desktop')) "Informe-LyonsTools-$env:COMPUTERNAME.txt"
        Set-Content -Path $file -Value $text -Encoding UTF8
        Write-LTLog "Informe guardado en $file" -Level Ok
    }
}

#endregion
