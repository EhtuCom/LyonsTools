#region Entry point -------------------------------------------------------------

$LT.Config = $LTConfigJson | ConvertFrom-Json
$LT.Items = @{}
foreach ($tab in $LT.Config.tabs) {
    foreach ($section in $tab.sections) {
        foreach ($item in $section.items) { $LT.Items[$item.id] = $item }
    }
}
$LT.CanElevate = Test-LTCanElevate

$logDir = Join-Path $LT.DataDir 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$LT.LogDir = $logDir
$LT.LogFile = Join-Path $logDir ("{0:yyyy-MM-dd}.log" -f (Get-Date))

if ($List) {
    $LT.Items.Values | Sort-Object id | Format-Table @{ n = 'ID'; e = { $_.id } },
    @{ n = 'Admin'; e = { if ($_.admin) { 'x' } } },
    @{ n = (Get-LTString 'Action' "Acción" "Acció"); e = { Get-LTString $_.label } } -AutoSize
    return
}

if ($Run) {
    Write-LTLog "Lyons Tools $($LT.Version) - command line mode" "Lyons Tools $($LT.Version) - modo sin interfaz" "Lyons Tools $($LT.Version) - mode sense interfície" -Level Step
    foreach ($id in ($Run -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $item = $LT.Items[$id]
        if (-not $item) { Write-LTLog "Unknown action: $id (see -List)" "Acción desconocida: $id (usa -List)" "Acció desconeguda: $id (fes servir -List)" -Level Error; continue }
        Write-LTLog (Get-LTString $item.label) -Level Step
        try { Invoke-LTItem -Item $item -Minutes $Minutes }
        catch { Write-LTLog $_.Exception.Message -Level Error }
    }
    return
}

# WPF needs an STA thread. Windows PowerShell is STA by default; pwsh may not be.
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-Host 'Restarting Lyons Tools in STA mode...'
    $langArg = if ($Lang) { " -Lang $Lang" } else { '' }
    if ($PSCommandPath) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"$langArg"
    }
    else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -Command `"& ([scriptblock]::Create((irm '$($LT.SourceUrl)')))$langArg`""
    }
    return
}

function Get-LTUiString([string]$Key) { Get-LTString $LT.Config.strings.$Key }

function Save-LTSettings {
    try {
        if (-not (Test-Path $LT.DataDir)) { New-Item -ItemType Directory -Path $LT.DataDir -Force | Out-Null }
        [pscustomobject]@{ lang = $LT.Lang } | ConvertTo-Json | Set-Content -LiteralPath $LT.SettingsFile -Encoding UTF8
    }
    catch { }
}

function Start-LTJob {
    <# Runs a list of items in a background runspace so the window never freezes. #>
    param([object[]]$Items, [int]$Minutes)

    if ($LT.Busy) { Write-LTLog "Wait for the current task to finish." "Espera a que termine la tarea en curso." "Espera que acabi la tasca en curs." -Level Warn; return }
    $LT.Busy = $true

    $iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.Variables.Add([Management.Automation.Runspaces.SessionStateVariableEntry]::new('LT', $LT, $null))
    foreach ($name in $LT.FunctionNames) {
        $iss.Commands.Add([Management.Automation.Runspaces.SessionStateFunctionEntry]::new($name, (Get-Item "function:$name").Definition))
    }
    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.ApartmentState = 'STA'   # COM (Office) and the clipboard need STA
    $rs.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
            param($Items, $Minutes)
            try {
                foreach ($item in $Items) {
                    Write-LTLog (Get-LTString $item.label) -Level Step
                    try { Invoke-LTItem -Item $item -Minutes $Minutes }
                    catch { Write-LTLog $_.Exception.Message -Level Error }
                }
                Write-LTLog "Finished." "Terminado." "Acabat." -Level Ok
            }
            finally { $LT.Busy = $false }
        }).AddArgument($Items).AddArgument($Minutes)
    $LT.Job = @{ PowerShell = $ps; Runspace = $rs; Handle = $ps.BeginInvoke() }
}

function Get-LTMinutes {
    $value = 0
    if (-not $LT.MinutesBox -or -not [int]::TryParse($LT.MinutesBox.Text.Trim(), [ref]$value) -or $value -lt 1 -or $value -gt 120) {
        return $null
    }
    $value
}

function Invoke-LTSelection {
    param([string[]]$Ids)
    $items = @($Ids | ForEach-Object { $LT.Items[$_] } | Where-Object { $_ })
    if (-not $items.Count) { Write-LTLog "No action is selected." "No hay ninguna acción seleccionada." "No hi ha cap acció seleccionada." -Level Warn; return }
    $minutes = 5
    if ($items | Where-Object usesMinutes) {
        $minutes = Get-LTMinutes
        if (-not $minutes) { Write-LTLog "Enter a number of minutes between 1 and 120." "Indica un número de minutos entre 1 y 120." "Indica un nombre de minuts entre 1 i 120." -Level Error; return }
    }
    Start-LTJob -Items $items -Minutes $minutes
}

function New-LTTextBlock([string]$Text, [string]$Style) {
    $tb = [Windows.Controls.TextBlock]::new()
    $tb.Text = $Text
    $tb.Style = $LT.Window.FindResource($Style)
    $tb
}

function Test-LTItemAllowed($Item) { -not $Item.admin -or $LT.CanElevate }

function Add-LTTabs {
    $tabs = $LT.Window.FindName('Tabs')
    $selected = [Math]::Max(0, $tabs.SelectedIndex)
    $minutes = if ($LT.MinutesBox) { $LT.MinutesBox.Text } else { $null }
    $tabs.Items.Clear()
    $LT.CheckBoxes = @{}
    $LT.ItemButtons = [Collections.Generic.List[object]]::new()
    $LT.MinutesBox = $null
    $runText = Get-LTUiString 'run'
    $openText = Get-LTUiString 'open'
    $adminText = Get-LTUiString 'requiresAdmin'
    $adminTip = Get-LTUiString 'requiresAdminTip'

    foreach ($tab in $LT.Config.tabs) {
        $panel = [Windows.Controls.StackPanel]::new()
        $panel.Margin = '16,8,16,16'

        if ($tab.intro) { [void]$panel.Children.Add((New-LTTextBlock (Get-LTString $tab.intro) 'IntroText')) }

        if ($tab.minutesInput) {
            $row = [Windows.Controls.StackPanel]::new()
            $row.Orientation = 'Horizontal'
            $row.Margin = '0,4,0,8'
            [void]$row.Children.Add((New-LTTextBlock (Get-LTUiString 'minutes') 'FieldLabel'))
            $box = [Windows.Controls.TextBox]::new()
            $box.Text = if ($minutes) { $minutes } else { [string]$tab.minutesInput }
            $box.Style = $LT.Window.FindResource('MinutesBox')
            [void]$row.Children.Add($box)
            $LT.MinutesBox = $box
            [void]$panel.Children.Add($row)
        }

        foreach ($section in $tab.sections) {
            [void]$panel.Children.Add((New-LTTextBlock (Get-LTString $section.title) 'SectionHeader'))
            foreach ($item in $section.items) {
                $allowed = Test-LTItemAllowed $item
                $card = [Windows.Controls.Border]::new()
                $card.Style = $LT.Window.FindResource('Card')
                $grid = [Windows.Controls.Grid]::new()
                $c0 = [Windows.Controls.ColumnDefinition]::new(); $c0.Width = '*'
                $c1 = [Windows.Controls.ColumnDefinition]::new(); $c1.Width = 'Auto'
                $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)

                $text = [Windows.Controls.StackPanel]::new()
                $titleRow = [Windows.Controls.WrapPanel]::new()
                [void]$titleRow.Children.Add((New-LTTextBlock (Get-LTString $item.label) 'ItemTitle'))
                if ($item.admin) {
                    $tag = [Windows.Controls.Border]::new()
                    $tag.Style = $LT.Window.FindResource('AdminTag')
                    $tag.Child = New-LTTextBlock $adminText 'AdminTagText'
                    $tag.ToolTip = $adminTip
                    [void]$titleRow.Children.Add($tag)
                }
                [void]$text.Children.Add($titleRow)
                if ($item.description) { [void]$text.Children.Add((New-LTTextBlock (Get-LTString $item.description) 'ItemDescription')) }

                if ($item.url) {
                    $text.Margin = '22,0,0,0'
                    [void]$grid.Children.Add($text)
                }
                else {
                    $cb = [Windows.Controls.CheckBox]::new()
                    $cb.Content = $text
                    $cb.Tag = $item.id
                    $cb.Style = $LT.Window.FindResource('ItemCheck')
                    $cb.IsEnabled = $allowed
                    if (-not $allowed) { $cb.ToolTip = $adminTip; [Windows.Controls.ToolTipService]::SetShowOnDisabled($cb, $true) }
                    $LT.CheckBoxes[$item.id] = $cb
                    [void]$grid.Children.Add($cb)
                }

                $btn = [Windows.Controls.Button]::new()
                $btn.Content = if ($item.url) { $openText } else { $runText }
                $btn.Tag = $item.id
                $btn.Style = $LT.Window.FindResource($(if ($item.url) { 'LinkButton' } else { 'RunButton' }))
                $btn.IsEnabled = $allowed -and -not $LT.Busy
                if (-not $allowed) { $btn.ToolTip = $adminTip; [Windows.Controls.ToolTipService]::SetShowOnDisabled($btn, $true) }
                [Windows.Controls.Grid]::SetColumn($btn, 1)
                $btn.Add_Click({ Invoke-LTSelection -Ids @($this.Tag) })
                [void]$grid.Children.Add($btn)
                $LT.ItemButtons.Add($btn)

                $card.Child = $grid
                [void]$panel.Children.Add($card)
            }
        }

        $scroll = [Windows.Controls.ScrollViewer]::new()
        $scroll.VerticalScrollBarVisibility = 'Auto'
        $scroll.Content = $panel
        $ti = [Windows.Controls.TabItem]::new()
        $ti.Header = Get-LTString $tab.title
        $ti.Content = $scroll
        [void]$tabs.Items.Add($ti)
    }
    $tabs.SelectedIndex = [Math]::Min($selected, $tabs.Items.Count - 1)
}

function Update-LTTexts {
    <# Static texts of the window in the current language. #>
    $w = $LT.Window
    $w.FindName('Subtitle').Text = Get-LTUiString 'subtitle'
    $w.FindName('RunSelected').Content = Get-LTUiString 'runSelected'
    $w.FindName('ClearSelection').Content = Get-LTUiString 'clearSelection'
    $w.FindName('CopyLog').Content = Get-LTUiString 'copyLog'
    $w.FindName('OpenLogs').Content = Get-LTUiString 'openLogs'
    $w.FindName('LangLabel').Text = Get-LTUiString 'language'
    $w.FindName('FooterText').Text = "Lyons Tools $($LT.Version) $([char]0x00B7) $(Get-LTUiString 'support'): ehtu.com"
    $w.FindName('StatusText').Text = if ($LT.Busy) { Get-LTUiString 'busy' } else { Get-LTUiString 'ready' }

    $badge = if (Test-LTAdmin) { Get-LTUiString 'admin' } else { "$(Get-LTUiString 'user'): $env:USERNAME" }
    if ($LT.IsRemoteSession) { $badge += " $([char]0x00B7) RDP" }
    elseif ($LT.IsServer) { $badge += " $([char]0x00B7) Server" }
    $w.FindName('AdminBadge').Text = $badge
}

function Show-LTWindow {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xaml = $LTXaml.Replace('__LT_VERSION__', $LT.Version)
    $window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new([xml]$xaml))
    $LT.Window = $window
    $LT.Gui = $true
    $LT.LogQueue = [Collections.Concurrent.ConcurrentQueue[string]]::new()
    $LT.FunctionNames = @(Get-ChildItem function: | Where-Object { $_.Name -match '^[A-Za-z]+-LT' } | ForEach-Object Name)

    $LT.LogBox = $window.FindName('LogBox')
    # Kept in $LT so event handlers never depend on PowerShell scoping.
    $LT.BusyBar = $window.FindName('BusyBar')
    $LT.StatusText = $window.FindName('StatusText')
    $LT.RunSelected = $window.FindName('RunSelected')
    $runSelected = $LT.RunSelected

    # Language selector
    $langBox = $window.FindName('LangBox')
    $LT.LangBox = $langBox
    foreach ($l in $LT.Config.languages) {
        $entry = [Windows.Controls.ComboBoxItem]::new()
        $entry.Content = $l.name
        $entry.Tag = $l.code
        [void]$langBox.Items.Add($entry)
        if ($l.code -eq $LT.Lang) { $langBox.SelectedItem = $entry }
    }
    $langBox.Add_SelectionChanged({
            $code = $this.SelectedItem.Tag
            if (-not $code -or $code -eq $LT.Lang) { return }
            $LT.Lang = $code
            Save-LTSettings
            Update-LTTexts
            Add-LTTabs
        })

    Update-LTTexts
    Add-LTTabs

    $runSelected.Add_Click({
            $ids = @($LT.CheckBoxes.Values | Where-Object { $_.IsChecked -and $_.IsEnabled } | ForEach-Object Tag)
            Invoke-LTSelection -Ids $ids
        })
    $window.FindName('ClearSelection').Add_Click({ $LT.CheckBoxes.Values | ForEach-Object { $_.IsChecked = $false } })
    $window.FindName('CopyLog').Add_Click({
            if ($LT.LogBox.Text) {
                [Windows.Clipboard]::SetText($LT.LogBox.Text)
                Write-LTLog "Log copied to the clipboard." "Registro copiado al portapapeles." "Registre copiat al porta-retalls." -Level Ok
            }
        })
    $window.FindName('OpenLogs').Add_Click({ Start-Process explorer.exe $LT.LogDir })
    $window.FindName('Website').Add_Click({ Start-Process $LT.Config.app.publisherUrl })

    # The UI thread drains the log queue and reflects the busy state.
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({
            $line = $null
            $wrote = $false
            while ($LT.LogQueue.TryDequeue([ref]$line)) { $LT.LogBox.AppendText($line + "`r`n"); $wrote = $true }
            if ($wrote) { $LT.LogBox.ScrollToEnd() }

            $busy = [bool]$LT.Busy
            if ($busy -ne [bool]$LT.UiBusy) {
                $LT.UiBusy = $busy
                foreach ($b in $LT.ItemButtons) { $b.IsEnabled = (-not $busy) -and (Test-LTItemAllowed $LT.Items[$b.Tag]) }
                $LT.RunSelected.IsEnabled = -not $busy
                $LT.LangBox.IsEnabled = -not $busy
                $LT.BusyBar.Visibility = if ($busy) { 'Visible' } else { 'Collapsed' }
                $LT.StatusText.Text = if ($busy) { Get-LTUiString 'busy' } else { Get-LTUiString 'ready' }
                if (-not $busy -and $LT.Job) {
                    try { $LT.Job.PowerShell.EndInvoke($LT.Job.Handle) } catch { }
                    $LT.Job.PowerShell.Dispose(); $LT.Job.Runspace.Dispose()
                    $LT.Job = $null
                }
            }
        })
    $timer.Start()

    $window.Add_Closing({
            if ($LT.Job) { try { $LT.Job.PowerShell.Stop() } catch { } }
        })

    Write-LTLog "Lyons Tools $($LT.Version) - $(Get-LTUiString 'welcome')"
    if (-not $LT.CanElevate) {
        Write-LTLog "You are using a standard account: actions marked 'Administrator' are disabled." `
            "Estás usando una cuenta estándar: las acciones marcadas como 'Administrador' están desactivadas." `
            "Estàs fent servir un compte estàndard: les accions marcades com a 'Administrador' estan desactivades." -Level Warn
    }
    [void]$window.ShowDialog()
    $timer.Stop()
}

Show-LTWindow

#endregion
