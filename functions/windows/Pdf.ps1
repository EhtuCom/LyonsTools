#region PDF ----------------------------------------------------------------------

function Get-LTAdobeProgId {
    <# ProgId registered by Adobe Acrobat (64-bit, "Acrobat.Document.DC") or Acrobat Reader 32-bit ("AcroExch.Document.DC"). #>
    foreach ($id in 'Acrobat.Document.DC', 'AcroExch.Document.DC') {
        if (Test-Path "Registry::HKEY_CLASSES_ROOT\$id\shell\open\command") { return $id }
    }
    $null
}

function Install-LTAdobeReader {
    <# Court notifications, tax forms and signed filings are PDFs whose signatures Adobe Reader can validate. #>
    if (Install-LTWinget -Id 'Adobe.Acrobat.Reader.64-bit') {
        Write-LTLog "Adobe Acrobat Reader installed or already up to date." "Adobe Acrobat Reader instalado o ya actualizado." "Adobe Acrobat Reader instal·lat o ja actualitzat." -Level Ok
        return
    }
    Open-LTUrl 'https://get.adobe.com/reader/'
}

function Set-LTAdobeDefaultPdf {
    <#
        Windows protects file associations (UserChoice hash), so no tool may set the default app
        silently on non-domain computers. We check the current choice and, if needed, open the
        Windows "Open with" dialog on a sample PDF so the user picks Adobe Acrobat + "Always".
    #>
    $progId = Get-LTAdobeProgId
    if (-not $progId) {
        Write-LTLog "Adobe Acrobat Reader is not installed. Installing it first..." "Adobe Acrobat Reader no está instalado. Se instala primero..." "Adobe Acrobat Reader no està instal·lat. S'instal·la primer..." -Level Warn
        Install-LTAdobeReader
        $progId = Get-LTAdobeProgId
        if (-not $progId) { return }
    }

    $current = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice' -ErrorAction SilentlyContinue).ProgId
    if ($current -match '^(Acrobat|AcroExch)\.') {
        Write-LTLog "Adobe Acrobat is already the default app for PDF files." "Adobe Acrobat ya es la aplicación predeterminada para los PDF." "Adobe Acrobat ja és l'aplicació predeterminada per als PDF." -Level Ok
        return
    }
    if ($current) {
        Write-LTLog "PDF files currently open with: $current" "Los PDF se abren ahora con: $current" "Els PDF s'obren ara amb: $current"
    }

    # Smallest valid PDF, just so Windows shows the "Open with" dialog for .pdf
    $sample = Join-Path (Get-LTWorkFolder) 'LyonsTools.pdf'
    $pdf = "%PDF-1.4`n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj`n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj`n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj`ntrailer<</Root 1 0 R>>`n%%EOF"
    [IO.File]::WriteAllText($sample, $pdf, [Text.Encoding]::ASCII)

    Write-LTLog "In the window that opens choose 'Adobe Acrobat' and press 'Always' (or tick 'Always use this app')." `
        "En la ventana que se abre elige 'Adobe Acrobat' y pulsa 'Siempre' (o marca 'Usar siempre esta aplicación')." `
        "A la finestra que s'obre tria 'Adobe Acrobat' i prem 'Sempre' (o marca 'Utilitza sempre aquesta aplicació')." -Level Step
    Start-Process rundll32.exe -ArgumentList "shell32.dll,OpenAs_RunDLL $sample" -Wait
    Start-Sleep -Seconds 1

    $current = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice' -ErrorAction SilentlyContinue).ProgId
    if ($current -match '^(Acrobat|AcroExch)\.') {
        Write-LTLog "Done: PDF files will open with Adobe Acrobat." "Hecho: los PDF se abrirán con Adobe Acrobat." "Fet: els PDF s'obriran amb Adobe Acrobat." -Level Ok
    }
    else {
        Write-LTLog "Adobe is not the default yet. You can also change it in Settings > Apps > Default apps > .pdf." `
            "Adobe todavía no es la predeterminada. También se puede cambiar en Configuración > Aplicaciones > Aplicaciones predeterminadas > .pdf." `
            "Adobe encara no és la predeterminada. També es pot canviar a Configuració > Aplicacions > Aplicacions predeterminades > .pdf." -Level Warn
    }
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
