#region Abogacía ----------------------------------------------------------------

function Install-LTAcaMiddleware {
    <#
        Bit4id middleware for the ACA (Autoridad de Certificación de la Abogacía) card,
        from https://www.abogacia.es/site/acaplus/guias-y-software-de-instalacion/
        The "Mini Lector ACA" driver offered on that page is NOT installed: its code-signing
        certificate has been revoked, and current Windows detects the reader by itself.
    #>
    try { $file = Save-LTFile -Url 'https://www.abogacia.es/repositorio/acaplusdescarga/Bit4id_Middleware.exe' -FileName 'Bit4id_ACA_Middleware.exe' }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "Download error: $err" "Error al descargar: $err" "Error en descarregar: $err" -Level Error
        Open-LTUrl 'https://www.abogacia.es/site/acaplus/guias-y-software-de-instalacion/'
        return
    }
    if (-not (Test-LTSignature -Path $file)) { return }
    Write-LTLog "Follow the installer steps. Then connect the reader with the ACA card inserted." `
        "Sigue los pasos del instalador. Después, conecta el lector con la tarjeta ACA insertada." `
        "Segueix els passos de l'instal·lador. Després, connecta el lector amb la targeta ACA inserida."
    if (Start-LTInstaller -Path $file) {
        Write-LTLog "If Windows does not recognise the reader, see the ACA guide: https://www.abogacia.es/site/acaplus/tarjeta-configura-dispositivos/" `
            "Si Windows no reconoce el lector, consulta la guía de ACA: https://www.abogacia.es/site/acaplus/tarjeta-configura-dispositivos/" `
            "Si Windows no reconeix el lector, consulta la guia d'ACA: https://www.abogacia.es/site/acaplus/tarjeta-configura-dispositivos/"
    }
}

function Install-LTAcaRootCertificates {
    <# ACA root and subordinate CAs. The root is pinned to the SHA1 published by the Consejo General de la Abogacía. #>
    $trustedRoots = @{ '3A09ECCF9D8770C3D5515806A9230EC9B32659BE' = 'ACA ROOT 2' }
    $folder = New-LTCleanFolder 'aca-certs'
    Initialize-LTWeb
    $files = foreach ($name in 'ACA_ROOTCA.CER', 'ACA_SUB1CA.cer', 'ACA_SUB2CA.cer') {
        $file = Join-Path $folder $name
        try {
            Invoke-WebRequest -Uri "https://www.abogacia.es/repositorio/acaplusdescarga/$name" -OutFile $file -UseBasicParsing -UserAgent $LT.UserAgent -ErrorAction Stop
            $file
        }
        catch { Write-LTLog "Could not download $name" "No se ha podido descargar $name" "No s'ha pogut descarregar $name" -Level Warn }
    }
    Install-LTCertificateFiles -Files @($files) -TrustedRoots $trustedRoots -Issuer 'ACA'
}

#endregion
