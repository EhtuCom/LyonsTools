#region PDF ----------------------------------------------------------------------

function Get-LTAdobeProgId {
    <# ProgId registered by Adobe Acrobat (64-bit, "Acrobat.Document.DC") or Acrobat Reader 32-bit ("AcroExch.Document.DC"). #>
    foreach ($id in 'Acrobat.Document.DC', 'AcroExch.Document.DC') {
        if (Test-Path "Registry::HKEY_CLASSES_ROOT\$id\shell\open\command") { return $id }
    }
    $null
}

function Get-LTPdfDefault {
    (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice' -ErrorAction SilentlyContinue).ProgId
}

function Get-LTPdfAppName([string]$ProgId) {
    switch -Regex ($ProgId) {
        '^(Acrobat|AcroExch)\.' { 'Adobe Acrobat' }
        '^MSEdgePDF' { 'Microsoft Edge' }
        '^Chrome' { 'Google Chrome' }
        '^FirefoxPDF' { 'Mozilla Firefox' }
        '^$' { Get-LTString 'not set (Windows default)' 'sin definir (predeterminado de Windows)' "sense definir (predeterminat de Windows)" }
        default { $ProgId }
    }
}

function Get-LTAdobeReaderUrl {
    <#
        Current official Adobe Reader 64-bit installer (ardownload*.adobe.com), taken from the
        winget package catalogue on GitHub. Used on computers without winget (e.g. Windows Server).
    #>
    $headers = @{ 'User-Agent' = 'LyonsTools' }
    $base = 'https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/a/Adobe/Acrobat/Reader/64-bit'
    # Assigned first: in Windows PowerShell 5.1 Invoke-RestMethod does not enumerate arrays into the pipeline.
    $dirs = Invoke-RestMethod -Uri $base -UseBasicParsing -Headers $headers -ErrorAction Stop
    $latest = $dirs | Where-Object type -eq 'dir' | Sort-Object { [version]($_.name -replace '[^\d.]', '') } | Select-Object -Last 1
    $files = Invoke-RestMethod -Uri $latest.url -UseBasicParsing -Headers $headers -ErrorAction Stop
    $installer = $files | Where-Object name -like '*.installer.yaml' | Select-Object -First 1
    $yaml = (Invoke-WebRequest -Uri $installer.download_url -UseBasicParsing -ErrorAction Stop).Content
    $url = [regex]::Match($yaml, 'InstallerUrl:\s*(https://ardownload\d*\.adobe\.com/\S+\.exe)').Groups[1].Value
    if (-not $url) { throw 'Adobe installer URL not found' }
    [pscustomobject]@{ Version = $latest.name; Url = $url }
}

function Install-LTAdobeReader {
    <# Court notifications, tax forms and signed filings are PDFs whose signatures Adobe Reader can validate. #>
    if (Install-LTWinget -Id 'Adobe.Acrobat.Reader.64-bit') {
        Write-LTLog "Adobe Acrobat Reader installed or already up to date." "Adobe Acrobat Reader instalado o ya actualizado." "Adobe Acrobat Reader instal·lat o ja actualitzat." -Level Ok
        return
    }
    # No winget (Windows Server): official Adobe installer.
    try {
        $reader = Get-LTAdobeReaderUrl
        $v = $reader.Version
        Write-LTLog "Downloading Adobe Acrobat Reader $v (about 800 MB, it may take a while)..." `
            "Descargando Adobe Acrobat Reader $v (unos 800 MB, puede tardar)..." `
            "Descarregant Adobe Acrobat Reader $v (uns 800 MB, pot trigar)..."
        $file = Save-LTFile -Url $reader.Url
    }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "Adobe Reader could not be downloaded ($err). Opening the official page." `
            "No se ha podido descargar Adobe Reader ($err). Abriendo la página oficial." `
            "No s'ha pogut descarregar Adobe Reader ($err). Obrint la pàgina oficial." -Level Warn
        Open-LTUrl 'https://get.adobe.com/reader/enterprise/'
        return
    }
    if (-not (Test-LTSignature -Path $file)) { return }
    # Adobe's documented switches: progress bar only, no restart.
    [void](Start-LTInstaller -Path $file -Arguments '/sPB /rs /msi')
}

function New-LTSamplePdf {
    <# Writes a small, valid one-page PDF (with a correct xref table) and returns its path. #>
    $content = "BT /F1 22 Tf 72 760 Td (Lyons Tools - PDF test) Tj 0 -34 Td /F1 12 Tf (If you can read this, PDF files open correctly. ehtu.com) Tj ET"
    $objects = @(
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
        "<< /Length $($content.Length) >>`nstream`n$content`nendstream",
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
    )
    $sb = [Text.StringBuilder]::new("%PDF-1.4`n")
    $offsets = foreach ($i in 0..($objects.Count - 1)) {
        $sb.Length
        [void]$sb.Append("$($i + 1) 0 obj`n$($objects[$i])`nendobj`n")
    }
    $xref = $sb.Length
    [void]$sb.Append("xref`n0 $($objects.Count + 1)`n0000000000 65535 f `n")
    foreach ($o in $offsets) { [void]$sb.Append(('{0:D10} 00000 n ' -f $o) + "`n") }
    [void]$sb.Append("trailer`n<< /Size $($objects.Count + 1) /Root 1 0 R >>`nstartxref`n$xref`n%%EOF`n")

    $path = Join-Path (Get-LTWorkFolder) 'LyonsTools-test.pdf'
    [IO.File]::WriteAllText($path, $sb.ToString(), [Text.Encoding]::ASCII)
    $path
}

function Show-LTOpenWithDialog {
    <#
        Shows Windows' "Open with" dialog for a file through SHOpenWithDialog and waits for it.
        OAIF_REGISTER_EXT | OAIF_EXEC | OAIF_FORCE_REGISTRATION: the app the user picks is saved
        as the default for that file type and the file is opened with it.
        Returns 'ok', 'cancelled' or the HRESULT.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not ('LTOpenWith' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LTOpenWith {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct OPENASINFO { public string pcszFile; public string pcszClass; public int oaifInFlags; }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHOpenWithDialog(IntPtr hwndParent, ref OPENASINFO info);
    public static int Show(string file, int flags) {
        OPENASINFO info = new OPENASINFO();
        info.pcszFile = file;
        info.pcszClass = null;
        info.oaifInFlags = flags;
        return SHOpenWithDialog(IntPtr.Zero, ref info);
    }
}
'@
    }
    $hr = [LTOpenWith]::Show($Path, 0x2 -bor 0x4 -bor 0x8)
    switch ($hr) {
        0 { 'ok' }
        -2147023673 { 'cancelled' }   # HRESULT_FROM_WIN32(ERROR_CANCELLED)
        default { '0x{0:X8}' -f $hr }
    }
}

function Set-LTAdobeDefaultPdf {
    <#
        Windows requires the user to confirm the default PDF app. Depending on the OS we open:
          Windows 11 / Server 2025         : Settings on Adobe's page ("Set default")
          Windows 10 / Server 2016-2022    : the "Open with" dialog for a sample PDF ("Always use this app")
        and then wait up to 2 minutes to confirm the change.
    #>
    $progId = Get-LTAdobeProgId
    if (-not $progId) {
        if (-not $LT.CanElevate) {
            Write-LTLog "Adobe Acrobat Reader is not installed and installing it requires an administrator." `
                "Adobe Acrobat Reader no está instalado y para instalarlo hace falta un administrador." `
                "Adobe Acrobat Reader no està instal·lat i per instal·lar-lo cal un administrador." -Level Warn
            return
        }
        Write-LTLog "Adobe Acrobat Reader is not installed. Installing it first..." "Adobe Acrobat Reader no está instalado. Se instala primero..." "Adobe Acrobat Reader no està instal·lat. S'instal·la primer..." -Level Warn
        Install-LTAdobeReader
        $progId = Get-LTAdobeProgId
        if (-not $progId) { return }
    }

    $current = Get-LTPdfDefault
    if ($current -match '^(Acrobat|AcroExch)\.') {
        Write-LTLog "Adobe Acrobat is already the default app for PDF files." "Adobe Acrobat ya es la aplicación predeterminada para los PDF." "Adobe Acrobat ja és l'aplicació predeterminada per als PDF." -Level Ok
        return
    }
    $now = Get-LTPdfAppName $current
    Write-LTLog "PDF files currently open with: $now" "Los PDF se abren ahora con: $now" "Els PDF s'obren ara amb: $now"
    [void](Test-LTAssociationPolicy)

    $build = [Environment]::OSVersion.Version.Build
    $registered = $null
    $props = Get-ItemProperty 'HKLM:\SOFTWARE\RegisteredApplications' -ErrorAction SilentlyContinue
    if ($props) { $registered = $props.PSObject.Properties.Name | Where-Object { $_ -match '^Adobe Acrobat' } | Select-Object -First 1 }

    if ($build -ge 22000 -and $registered) {
        Start-Process "ms-settings:defaultapps?registeredAppMachine=$([Uri]::EscapeDataString($registered))"
        Write-LTLog "Settings has opened on the Adobe Acrobat page: press 'Set default' at the top." `
            "Se ha abierto Configuración en la página de Adobe Acrobat: pulsa 'Establecer como predeterminado' arriba." `
            "S'ha obert Configuració a la pàgina d'Adobe Acrobat: prem 'Estableix com a predeterminat' a dalt." -Level Step
    }
    else {
        # Windows' own "Open with" dialog, asked to save the choice as the default for .pdf.
        # (rundll32 OpenAs_RunDLL shows the same list but without the "always use this app" option.)
        Write-LTLog "In the 'How do you want to open this file?' window choose 'Adobe Acrobat' and press OK: it will become the default for PDF files." `
            "En la ventana '¿Cómo quieres abrir este archivo?' elige 'Adobe Acrobat' y pulsa Aceptar: quedará como predeterminada para los PDF." `
            "A la finestra 'Com vols obrir aquest fitxer?' tria 'Adobe Acrobat' i prem D'acord: quedarà com a predeterminada per als PDF." -Level Step
        $result = Show-LTOpenWithDialog -Path (New-LTSamplePdf)
        if ((Get-LTPdfDefault) -match '^(Acrobat|AcroExch)\.') {
            Write-LTLog "Done: PDF files will open with Adobe Acrobat." "Hecho: los PDF se abrirán con Adobe Acrobat." "Fet: els PDF s'obriran amb Adobe Acrobat." -Level Ok
            return
        }
        # Backup: the Settings page, where the user picks Adobe for .pdf.
        Start-Process 'ms-settings:defaultapps'
        Write-LTLog "Not changed yet ($result). In Settings > Default apps > Choose default apps by file type, set '.pdf' to Adobe Acrobat." `
            "Todavía no ha cambiado ($result). En Configuración > Aplicaciones predeterminadas > Elegir aplicaciones predeterminadas por tipo de archivo, pon '.pdf' con Adobe Acrobat." `
            "Encara no ha canviat ($result). A Configuració > Aplicacions predeterminades > Tria les aplicacions predeterminades per tipus de fitxer, posa '.pdf' amb Adobe Acrobat." -Level Step
    }

    Write-LTLog "Waiting for the change (up to 2 minutes)..." "Esperando el cambio (hasta 2 minutos)..." "Esperant el canvi (fins a 2 minuts)..."
    $deadline = (Get-Date).AddMinutes(2)
    while ((Get-Date) -lt $deadline) {
        if ((Get-LTPdfDefault) -match '^(Acrobat|AcroExch)\.') {
            Write-LTLog "Done: PDF files will open with Adobe Acrobat." "Hecho: los PDF se abrirán con Adobe Acrobat." "Fet: els PDF s'obriran amb Adobe Acrobat." -Level Ok
            return
        }
        Start-Sleep -Seconds 2
    }
    Write-LTLog "Adobe is not the default yet. You can also change it in Settings > Apps > Default apps > Choose default apps by file type > .pdf, then use the PDF 'Test' button." `
        "Adobe todavía no es la predeterminada. También se puede cambiar en Configuración > Aplicaciones > Aplicaciones predeterminadas > Elegir aplicaciones predeterminadas por tipo de archivo > .pdf, y después usar el botón 'Prueba' de PDF." `
        "Adobe encara no és la predeterminada. També es pot canviar a Configuració > Aplicacions > Aplicacions predeterminades > Tria les aplicacions predeterminades per tipus de fitxer > .pdf, i després fer servir el botó 'Prova' de PDF." -Level Warn
}

function Open-LTPdfTest {
    <# Shows which app opens PDF files and opens a test PDF with it. #>
    $name = Get-LTPdfAppName (Get-LTPdfDefault)
    Write-LTLog "PDF files open with: $name" "Los PDF se abren con: $name" "Els PDF s'obren amb: $name" -Level Ok
    [void](Test-LTAssociationPolicy)
    $sample = New-LTSamplePdf
    Write-LTLog "Opening a test PDF with the default app..." "Abriendo un PDF de prueba con la aplicación predeterminada..." "Obrint un PDF de prova amb l'aplicació predeterminada..."
    Start-Process $sample
}

function Set-LTBrowserPdfDownload {
    <#
        Browser policies so PDFs are downloaded and opened with the default PDF app
        (Adobe) instead of the built-in viewers of Edge, Chrome and Firefox:
          Edge / Chrome : AlwaysOpenPdfExternally = 1
          Firefox       : DisableBuiltinPDFViewer = 1 and Handlers -> application/pdf useSystemDefault
        Browsers will show "Managed by your organization".
    #>
    param([switch]$Undo)

    $handlers = '{"mimeTypes":{"application/pdf":{"action":"useSystemDefault","ask":false}},"extensions":{"pdf":{"action":"useSystemDefault","ask":false}}}'
    if ($Undo) {
        $script = @"
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name AlwaysOpenPdfExternally -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name AlwaysOpenPdfExternally -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' -Name DisableBuiltinPDFViewer, Handlers -ErrorAction SilentlyContinue
"@
    }
    else {
        $script = @"
foreach (`$k in 'HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox') {
    if (-not (Test-Path `$k)) { New-Item -Path `$k -Force | Out-Null }
}
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name AlwaysOpenPdfExternally -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name AlwaysOpenPdfExternally -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' -Name DisableBuiltinPDFViewer -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' -Name Handlers -Value '$handlers' -PropertyType String -Force | Out-Null
"@
    }
    if ((Invoke-LTElevated -Script $script) -ne 0) {
        Write-LTLog "The browser settings could not be changed." "No se han podido cambiar los ajustes de los navegadores." "No s'han pogut canviar els ajustos dels navegadors." -Level Error
        return
    }
    if ($Undo) {
        Write-LTLog "Edge, Chrome and Firefox will open PDFs in the browser again." "Edge, Chrome y Firefox vuelven a abrir los PDF en el navegador." "Edge, Chrome i Firefox tornen a obrir els PDF al navegador." -Level Ok
    }
    else {
        Write-LTLog "Edge, Chrome and Firefox will download PDFs and open them with the default PDF app." `
            "Edge, Chrome y Firefox descargarán los PDF y los abrirán con la aplicación de PDF predeterminada." `
            "Edge, Chrome i Firefox descarregaran els PDF i els obriran amb l'aplicació de PDF predeterminada." -Level Ok
        Write-LTLog "Restart the browsers to apply it. They will show 'Managed by your organization'." `
            "Reinicia los navegadores para aplicarlo. Mostrarán 'Administrado por tu organización'." `
            "Reinicia els navegadors per aplicar-ho. Mostraran 'Gestionat per la teva organització'."
        $current = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice' -ErrorAction SilentlyContinue).ProgId
        if ($current -notmatch '^(Acrobat|AcroExch)\.') {
            Write-LTLog "Tip: also run 'Make Adobe Reader the default PDF app', otherwise downloaded PDFs may still open in Edge." `
                "Consejo: ejecuta también 'Hacer Adobe Reader la aplicación predeterminada', si no los PDF descargados pueden seguir abriéndose en Edge." `
                "Consell: executa també 'Fes d'Adobe Reader l'aplicació predeterminada', si no els PDF descarregats es poden continuar obrint a Edge." -Level Warn
        }
    }
}

function Reset-LTBrowserPdfDownload { Set-LTBrowserPdfDownload -Undo }

#endregion
