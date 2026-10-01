#region Windows -----------------------------------------------------------------

function Enable-LTFileExtensions {
    # Showing extensions helps users spot "invoice.pdf.exe" style phishing attachments.
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 -Type DWord
    Write-LTLog "File extensions (.pdf, .docx, .exe...) will now be shown." `
        "Ahora se mostrarán las extensiones de archivo (.pdf, .docx, .exe...)." `
        "Ara es mostraran les extensions dels fitxers (.pdf, .docx, .exe...)." -Level Ok
    Restart-LTExplorer
}

function Enable-LTClipboardHistory {
    # Clipboard history exists since Windows 10 1809 / Windows Server 2019 (build 17763).
    if ($LT.Build -lt 17763) {
        Write-LTLog "Clipboard history is not available on this Windows version (it needs Windows 10 1809 / Server 2019 or later)." `
            "El historial del portapapeles no está disponible en esta versión de Windows (necesita Windows 10 1809 / Server 2019 o posterior)." `
            "L'historial del porta-retalls no està disponible en aquesta versió de Windows (necessita Windows 10 1809 / Server 2019 o posterior)." -Level Warn
        return
    }
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
        "Fitxers temporals eliminats: $freed MB alliberats (els fitxers en ús s'han deixat)." -Level Ok
}

function Clear-LTDnsCache {
    # Flushing the resolver cache requires administrator rights.
    if ((Invoke-LTElevated -Script 'ipconfig.exe /flushdns | Out-Null') -ne 0) { return }
    Write-LTLog "DNS cache flushed." "Caché DNS vaciada." "Memòria cau DNS buidada." -Level Ok
}

function Start-LTQuickAssist {
    if ($LT.IsServer) {
        Write-LTLog "Quick Assist is not available on Windows Server. Contact your support provider for remote access." `
            "Asistencia rápida no está disponible en Windows Server. Contacta con tu soporte para la conexión remota." `
            "L'Assistència ràpida no està disponible a Windows Server. Contacta amb el teu suport per a la connexió remota." -Level Warn
        return
    }
    Write-LTLog "Opening Quick Assist. Choose 'Help someone' or enter the code the technician gives you." `
        "Abriendo Asistencia rápida. Elige 'Ayudar a alguien' o introduce el código que te dé el técnico." `
        "Obrint l'Assistència ràpida. Tria 'Ajudar algú' o introdueix el codi que et doni el tècnic."
    # Store app (Windows 10 2004+ / 11), then the classic built-in quickassist.exe (older Windows 10), then the Store page.
    $classic = Join-Path $env:SystemRoot 'System32\quickassist.exe'
    try { Start-Process 'ms-quick-assist:' -ErrorAction Stop; return } catch { }
    if (Test-Path $classic) { Start-Process $classic; return }
    Write-LTLog "Quick Assist is not installed. Opening Microsoft Store..." "Asistencia rápida no está instalada. Abriendo Microsoft Store..." "L'Assistència ràpida no està instal·lada. Obrint Microsoft Store..." -Level Warn
    Start-Process 'ms-windows-store://pdp/?ProductId=9P7BP5VNWKX5'
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
    $yes = Get-LTString 'yes' "sí" "sí"
    $notInstalled = Get-LTString 'not installed' 'no instalado' "no instal·lat"
    $row = { param($label, $value) '{0,-14}{1}' -f "${label}:", $value }

    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add((Get-LTString "Lyons Tools $($LT.Version) report" "Informe Lyons Tools $($LT.Version)" "Informe Lyons Tools $($LT.Version)") + " - $(Get-Date -Format 'dd/MM/yyyy HH:mm')")
    $lines.Add((& $row (Get-LTString 'Computer' 'Equipo' 'Equip') "$env:COMPUTERNAME ($($cs.Manufacturer) $($cs.Model))"))
    $lines.Add((& $row (Get-LTString 'User' 'Usuario' 'Usuari') "$env:USERDOMAIN\$env:USERNAME (admin: $(if (Test-LTAdmin) { $yes } else { 'no' }))"))
    $lines.Add((& $row 'Windows' "$($os.Caption) $display (build $($os.BuildNumber))"))
    $lines.Add((& $row (Get-LTString 'Memory' 'Memoria' "Memòria") "$([math]::Round($cs.TotalPhysicalMemory / 1GB, 1)) GB"))
    $free = [math]::Round($disk.FreeSpace / 1GB, 1); $size = [math]::Round($disk.Size / 1GB, 1)
    $lines.Add((& $row "$(Get-LTString 'Disk' 'Disco' 'Disc') $($env:SystemDrive)" (Get-LTString "$free GB free of $size GB" "$free GB libres de $size GB" "$free GB lliures de $size GB")))
    $office = if ($c2r) { "$($c2r.ProductReleaseIds) $($c2r.VersionToReport) ($($c2r.Platform))" } else { Get-LTString 'Office Click-to-Run not detected' 'no se ha detectado Office Click-to-Run' "no s'ha detectat Office Click-to-Run" }
    $lines.Add((& $row 'Office' $office))

    $java = Get-Command java.exe -ErrorAction SilentlyContinue
    $javaVer = if ($java) { (& cmd.exe /c "`"$($java.Source)`" -version 2>&1" | Select-Object -First 1) } else { Get-LTString 'not in the PATH' "no está en el PATH" "no és al PATH" }
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
            "Informe copiado al portapapeles. Pégalo en un correo a soporte." `
            "Informe copiat al porta-retalls. Enganxa'l en un correu al suport." -Level Ok
    }
    catch {
        $file = Join-Path ([Environment]::GetFolderPath('Desktop')) "LyonsTools-$env:COMPUTERNAME.txt"
        Set-Content -Path $file -Value $text -Encoding UTF8
        Write-LTLog "Report saved to $file" "Informe guardado en $file" "Informe desat a $file" -Level Ok
    }
}

#endregion
