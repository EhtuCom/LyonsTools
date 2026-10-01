#region Office AutoRecover ------------------------------------------------------
<#
    Two layers, so it works both for administrators and for standard users (e.g. on a
    Remote Desktop / terminal server):

    1. User preference, through Office's own object model (no admin rights needed):
         Word        Options.SaveInterval (minutes), Options.CreateBackup
         Excel       Application.AutoRecover.Enabled / .Time
         PowerPoint  HKCU\Software\Microsoft\Office\16.0\PowerPoint\Options
                       SaveAutoRecoveryInfo / FrequencyToSaveAutoRecoveryInfo (no object model;
                       these value names are the long-standing ones, not documented for 16.0)

    2. When the user can elevate, the documented Office 16.0 Group Policy values (ADMX),
       which Office cannot overwrite when it closes:
         Word        HKCU\Software\Policies\Microsoft\Office\16.0\Word\Options
                       autosaveinterval (minutes, 0 = off), keepunsavedchanges
         Excel       ...\Excel\Options       autorecovertime (minutes), keepunsavedchanges
         PowerPoint  ...\PowerPoint\Options  saveautorecoveryinfo, frequencytosaveautorecoveryinfo, keepunsavedchanges
       HKCU\Software\Policies is only writable by administrators, so the values are written
       elevated into HKEY_USERS\<SID of the signed-in user>: they land in the right profile even
       if a different admin account approves the UAC prompt.
#>

function Get-LTUserSid { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }

function Set-LTUserPolicy {
    <#
        Writes DWORD policy values for the current user in one elevated step.
        $Values: list of @{ Path = 'Word\Options'; Name = 'autosaveinterval'; Value = 5 }
        A $null Value removes the value.
    #>
    param([Parameter(Mandatory)][object[]]$Values)

    $sid = Get-LTUserSid
    $lines = foreach ($v in $Values) {
        $key = "Registry::HKEY_USERS\$sid\$($LT.OfficePolicyRoot)\$($v.Path)"
        if ($null -eq $v.Value) {
            "Remove-ItemProperty -LiteralPath '$key' -Name '$($v.Name)' -ErrorAction SilentlyContinue"
        }
        else {
            "if (-not (Test-Path -LiteralPath '$key')) { New-Item -Path '$key' -Force | Out-Null }"
            "New-ItemProperty -LiteralPath '$key' -Name '$($v.Name)' -Value $([int]$v.Value) -PropertyType DWord -Force | Out-Null"
        }
    }
    $result = Invoke-LTElevated -Script ($lines -join "`n")
    if ($result -ne 0) {
        Write-LTLog "The settings could not be locked as a policy (administrator permission is required)." `
            "No se han podido fijar los ajustes como directiva (hacen falta permisos de administrador)." `
            "No s'han pogut fixar els ajustos com a directiva (calen permisos d'administrador)." -Level Warn
        return $false
    }
    $true
}

function Set-LTOfficeUserPreference {
    <# Per-user AutoRecover settings through Office itself. Works without administrator rights. #>
    param(
        [Parameter(Mandatory)][ValidateSet('Word', 'Excel', 'PowerPoint')][string]$App,
        [Parameter(Mandatory)][int]$Minutes,
        [switch]$Backup
    )
    if ($App -eq 'PowerPoint') {
        $key = 'HKCU:\Software\Microsoft\Office\16.0\PowerPoint\Options'
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        Set-ItemProperty -Path $key -Name 'SaveAutoRecoveryInfo' -Value 1 -Type DWord
        Set-ItemProperty -Path $key -Name 'FrequencyToSaveAutoRecoveryInfo' -Value $Minutes -Type DWord
        return $true
    }
    $com = $null
    try {
        if ($App -eq 'Word') {
            $com = New-Object -ComObject Word.Application -ErrorAction Stop
            $com.Options.SaveInterval = $Minutes
            if ($Backup) { $com.Options.CreateBackup = $true }
        }
        else {
            $com = New-Object -ComObject Excel.Application -ErrorAction Stop
            $com.AutoRecover.Enabled = $true
            $com.AutoRecover.Time = $Minutes
        }
        return $true
    }
    catch {
        $err = $_.Exception.Message
        Write-LTLog "$App could not be configured: $err" "No se ha podido configurar ${App}: $err" "No s'ha pogut configurar ${App}: $err" -Level Warn
        return $false
    }
    finally {
        if ($com) {
            try { if ($App -eq 'Word') { $com.Quit([ref]0) } else { $com.Quit() } } catch { }
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($com)
        }
    }
}

function Get-LTAutoRecoverPolicyState {
    <# Returns the policy values written by Lyons Tools, or $null if none. #>
    param([ValidateSet('Word', 'Excel', 'PowerPoint')][string]$App)
    $p = Get-ItemProperty "HKCU:\$($LT.OfficePolicyRoot)\$App\Options" -ErrorAction SilentlyContinue
    $min = switch ($App) { 'Word' { $p.autosaveinterval } 'Excel' { $p.autorecovertime } 'PowerPoint' { $p.frequencytosaveautorecoveryinfo } }
    if ($null -eq $min) { return $null }
    [pscustomobject]@{ Minutes = $min; KeepLast = $p.keepunsavedchanges -eq 1 }
}

function Get-LTAutoRecoverPolicy {
    param(
        [ValidateSet('Word', 'Excel', 'PowerPoint')][string]$App,
        [int]$Minutes
    )
    switch ($App) {
        'Word' { @{ Path = 'Word\Options'; Name = 'autosaveinterval'; Value = $Minutes } }
        'Excel' { @{ Path = 'Excel\Options'; Name = 'autorecovertime'; Value = $Minutes } }
        'PowerPoint' {
            @{ Path = 'PowerPoint\Options'; Name = 'saveautorecoveryinfo'; Value = 1 }
            @{ Path = 'PowerPoint\Options'; Name = 'frequencytosaveautorecoveryinfo'; Value = $Minutes }
        }
    }
}

function Write-LTOfficeRunningWarning {
    $session = (Get-Process -Id $PID).SessionId
    $running = Get-Process WINWORD, EXCEL, POWERPNT -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session
    if ($running) {
        $names = ($running | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
        Write-LTLog "Office programs are open ($names). Close them so they do not overwrite the change; it applies the next time they are opened." `
            "Hay programas de Office abiertos ($names). Ciérralos para que no sobrescriban el cambio; se aplicará al volver a abrirlos." `
            "Hi ha programes d'Office oberts ($names). Tanca'ls perquè no sobreescriguin el canvi; s'aplicarà en tornar-los a obrir." -Level Warn
    }
}

function Set-LTOfficeAutoRecoverCore {
    param(
        [Parameter(Mandatory)][string[]]$Apps,
        [ValidateRange(1, 120)][int]$Minutes = 5,
        [switch]$CrashProtection
    )
    Write-LTOfficeRunningWarning
    foreach ($app in $Apps) {
        if (Set-LTOfficeUserPreference -App $app -Minutes $Minutes -Backup:$CrashProtection) {
            Write-LTLog "${app}: AutoRecover every $Minutes minutes." "${app}: autorrecuperación cada $Minutes minutos." "${app}: recuperació automàtica cada $Minutes minuts." -Level Ok
        }
    }
    if ($CrashProtection -and ($Apps -contains 'Word')) {
        Write-LTLog "Word will always create a backup copy (.wbk) when saving." "Word creará siempre una copia de seguridad (.wbk) al guardar." "El Word crearà sempre una còpia de seguretat (.wbk) en desar." -Level Ok
    }

    if (-not $LT.CanElevate) {
        Write-LTLog "Saved as your personal Office setting (you can change it in File > Options > Save)." `
            "Guardado como ajuste personal de Office (se puede cambiar en Archivo > Opciones > Guardar)." `
            "Desat com a ajust personal d'Office (es pot canviar a Fitxer > Opcions > Desa)."
        return
    }
    $values = @(foreach ($app in $Apps) {
            Get-LTAutoRecoverPolicy -App $app -Minutes $Minutes
            if ($CrashProtection) { @{ Path = "$app\Options"; Name = 'keepunsavedchanges'; Value = 1 } }
        })
    if (Set-LTUserPolicy -Values $values) {
        Write-LTLog "Locked as a policy for this user: Office cannot undo it." "Fijado como directiva para este usuario: Office no lo puede deshacer." "Fixat com a directiva per a aquest usuari: Office no ho pot desfer." -Level Ok
        if ($CrashProtection) {
            Write-LTLog "The last AutoRecovered version will be kept if a file is closed without saving." `
                "Se conservará la última versión autorrecuperada si se cierra sin guardar." `
                "Es conservarà l'última versió recuperada automàticament si es tanca sense desar." -Level Ok
        }
    }
}

function Set-LTWordAutoRecover { param([int]$Minutes = 5) Set-LTOfficeAutoRecoverCore -Apps Word -Minutes $Minutes }
function Set-LTExcelAutoRecover { param([int]$Minutes = 5) Set-LTOfficeAutoRecoverCore -Apps Excel -Minutes $Minutes }
function Set-LTPowerPointAutoRecover { param([int]$Minutes = 5) Set-LTOfficeAutoRecoverCore -Apps PowerPoint -Minutes $Minutes }
function Enable-LTOfficeCrashProtection { param([int]$Minutes = 5) Set-LTOfficeAutoRecoverCore -Apps Word, Excel, PowerPoint -Minutes $Minutes -CrashProtection }

function Reset-LTOfficeAutoRecover {
    <# Removes the policy values written by Lyons Tools, so the user can change them again in Office. #>
    if (-not ('Word', 'Excel', 'PowerPoint' | Where-Object { Get-LTAutoRecoverPolicyState -App $_ })) {
        Write-LTLog "There are no locked AutoRecover settings: they can already be changed in File > Options > Save." `
            "No hay ajustes de autoguardado fijados: ya se pueden cambiar en Archivo > Opciones > Guardar." `
            "No hi ha ajustos de desament fixats: ja es poden canviar a Fitxer > Opcions > Desa." -Level Ok
        return
    }
    $values = @(
        @{ Path = 'Word\Options'; Name = 'autosaveinterval'; Value = $null }
        @{ Path = 'Excel\Options'; Name = 'autorecovertime'; Value = $null }
        @{ Path = 'PowerPoint\Options'; Name = 'saveautorecoveryinfo'; Value = $null }
        @{ Path = 'PowerPoint\Options'; Name = 'frequencytosaveautorecoveryinfo'; Value = $null }
        foreach ($app in 'Word', 'Excel', 'PowerPoint') { @{ Path = "$app\Options"; Name = 'keepunsavedchanges'; Value = $null } }
    )
    if (Set-LTUserPolicy -Values $values) {
        Write-LTLog "AutoRecover policies removed. Office uses File > Options > Save again." `
            "Directivas de autoguardado eliminadas. Office vuelve a usar Archivo > Opciones > Guardar." `
            "Directives de desament eliminades. Office torna a fer servir Fitxer > Opcions > Desa." -Level Ok
    }
}

#endregion
