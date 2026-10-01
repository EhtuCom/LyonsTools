#region Office AutoRecover ------------------------------------------------------
<#
    The values are the documented Office 16.0 Group Policy settings (ADMX), which cover
    Office 2016/2019/2021/2024 and Microsoft 365:

      Word        HKCU\Software\Policies\Microsoft\Office\16.0\Word\Options
                    autosaveinterval (minutes, 0 = off), keepunsavedchanges
      Excel       HKCU\Software\Policies\Microsoft\Office\16.0\Excel\Options
                    autorecovertime (minutes), keepunsavedchanges
      PowerPoint  HKCU\Software\Policies\Microsoft\Office\16.0\PowerPoint\Options
                    saveautorecoveryinfo, frequencytosaveautorecoveryinfo (minutes), keepunsavedchanges

    Policies are used (instead of the normal preference values) because Office cannot
    overwrite them when it closes. HKCU\Software\Policies is only writable by administrators,
    so the values are written elevated into HKEY_USERS\<SID of the signed-in user>: that way
    they land in the right profile even if a different admin account approves the UAC prompt.
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
        Write-LTLog "No se han podido guardar los ajustes (hacen falta permisos de administrador)." -Level Error
        return $false
    }
    $true
}

function Get-LTAutoRecoverState {
    param([ValidateSet('Word', 'Excel', 'PowerPoint')][string]$App)
    $p = Get-ItemProperty "HKCU:\$($LT.OfficePolicyRoot)\$App\Options" -ErrorAction SilentlyContinue
    $pref = Get-ItemProperty "HKCU:\Software\Microsoft\Office\16.0\$App\Options" -ErrorAction SilentlyContinue
    switch ($App) {
        'Word' {
            $min = if ($null -ne $p.autosaveinterval) { $p.autosaveinterval } else { 10 }
            [pscustomobject]@{ Enabled = $min -gt 0; Minutes = $min; KeepLast = $p.keepunsavedchanges -ne 0 }
        }
        'Excel' {
            $min = if ($null -ne $p.autorecovertime) { $p.autorecovertime } elseif ($pref.AutoRecoverTime) { $pref.AutoRecoverTime } else { 10 }
            [pscustomobject]@{ Enabled = $true; Minutes = $min; KeepLast = $p.keepunsavedchanges -ne 0 }
        }
        'PowerPoint' {
            $min = if ($null -ne $p.frequencytosaveautorecoveryinfo) { $p.frequencytosaveautorecoveryinfo } else { 10 }
            [pscustomobject]@{ Enabled = $p.saveautorecoveryinfo -ne 0; Minutes = $min; KeepLast = $p.keepunsavedchanges -ne 0 }
        }
    }
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
    $running = Get-Process WINWORD, EXCEL, POWERPNT -ErrorAction SilentlyContinue
    if ($running) {
        $names = ($running | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
        Write-LTLog "Hay programas de Office abiertos ($names). El cambio se aplicará la próxima vez que los abras." -Level Warn
    }
}

function Set-LTOfficeAutoRecover {
    param(
        [Parameter(Mandatory)][ValidateSet('Word', 'Excel', 'PowerPoint')][string]$App,
        [ValidateRange(1, 120)][int]$Minutes = 5
    )
    if (Set-LTUserPolicy -Values @(Get-LTAutoRecoverPolicy -App $App -Minutes $Minutes)) {
        Write-LTLog "$App guardará la información de autorrecuperación cada $Minutes minutos." -Level Ok
        Write-LTOfficeRunningWarning
    }
}

function Set-LTWordAutoRecover { param([int]$Minutes = 5) Set-LTOfficeAutoRecover -App Word -Minutes $Minutes }
function Set-LTExcelAutoRecover { param([int]$Minutes = 5) Set-LTOfficeAutoRecover -App Excel -Minutes $Minutes }
function Set-LTPowerPointAutoRecover { param([int]$Minutes = 5) Set-LTOfficeAutoRecover -App PowerPoint -Minutes $Minutes }

function Enable-LTOfficeCrashProtection {
    param([ValidateRange(1, 120)][int]$Minutes = 5)

    $values = @(
        foreach ($app in 'Word', 'Excel', 'PowerPoint') {
            Get-LTAutoRecoverPolicy -App $app -Minutes $Minutes
            @{ Path = "$app\Options"; Name = 'keepunsavedchanges'; Value = 1 }
        }
    )
    if (-not (Set-LTUserPolicy -Values $values)) { return }
    Write-LTLog "Word, Excel y PowerPoint: autorrecuperación cada $Minutes minutos." -Level Ok
    Write-LTLog "Se conservará la última versión autorrecuperada si se cierra sin guardar." -Level Ok

    # "Always create backup copy" in Word: a normal user preference, set through Word itself.
    $word = $null
    try {
        $word = New-Object -ComObject Word.Application -ErrorAction Stop
        $word.Options.CreateBackup = $true
        Write-LTLog "Word creará siempre una copia de seguridad (.wbk) al guardar." -Level Ok
    }
    catch {
        Write-LTLog "No se ha podido activar la copia de seguridad de Word: $($_.Exception.Message)" -Level Warn
    }
    finally {
        if ($word) {
            try { $word.Quit([ref]0) } catch { }
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word)
        }
    }
    Write-LTOfficeRunningWarning
}

function Reset-LTOfficeAutoRecover {
    <# Removes the values written by Lyons Tools, so the user can change them again in Office. #>
    $values = @(
        @{ Path = 'Word\Options'; Name = 'autosaveinterval'; Value = $null }
        @{ Path = 'Excel\Options'; Name = 'autorecovertime'; Value = $null }
        @{ Path = 'PowerPoint\Options'; Name = 'saveautorecoveryinfo'; Value = $null }
        @{ Path = 'PowerPoint\Options'; Name = 'frequencytosaveautorecoveryinfo'; Value = $null }
        foreach ($app in 'Word', 'Excel', 'PowerPoint') { @{ Path = "$app\Options"; Name = 'keepunsavedchanges'; Value = $null } }
    )
    if (Set-LTUserPolicy -Values $values) {
        Write-LTLog "Ajustes de autoguardado eliminados. Office vuelve a usar la configuración de Archivo > Opciones > Guardar." -Level Ok
    }
}

#endregion
