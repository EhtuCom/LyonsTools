#region Entry point -------------------------------------------------------------

$LT.Config = $LTConfigJson | ConvertFrom-Json
$LT.Items = @{}
foreach ($tab in $LT.Config.tabs) {
    foreach ($section in $tab.sections) {
        foreach ($item in $section.items) { $LT.Items[$item.id] = $item }
    }
}

$logDir = Join-Path $env:LOCALAPPDATA 'LyonsTools\logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$LT.LogDir = $logDir
$LT.LogFile = Join-Path $logDir ("{0:yyyy-MM-dd}.log" -f (Get-Date))

if ($List) {
    $LT.Items.Values | Sort-Object id | Format-Table @{ n = 'ID'; e = { $_.id } }, @{ n = "Acción"; e = { $_.label } } -AutoSize
    return
}

if ($Run) {
    Write-LTLog "Lyons Tools $($LT.Version) - modo sin interfaz" -Level Step
    foreach ($id in ($Run -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $item = $LT.Items[$id]
        if (-not $item) { Write-LTLog "Acción desconocida: $id (usa -List)" -Level Error; continue }
        Write-LTLog $item.label -Level Step
        try { Invoke-LTItem -Item $item -Minutes $Minutes }
        catch { Write-LTLog $_.Exception.Message -Level Error }
    }
    return
}

# WPF needs an STA thread. Windows PowerShell is STA by default; pwsh may not be.
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-Host 'Reiniciando Lyons Tools en modo STA...'
    if ($PSCommandPath) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    }
    else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -Command `"irm '$($LT.SourceUrl)' | iex`""
    }
    return
}

function Start-LTJob {
    <# Runs a list of items in a background runspace so the window never freezes. #>
    param([object[]]$Items, [int]$Minutes)

    if ($LT.Busy) { Write-LTLog "Espera a que termine la tarea en curso." -Level Warn; return }
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
                    Write-LTLog $item.label -Level Step
                    try { Invoke-LTItem -Item $item -Minutes $Minutes }
                    catch { Write-LTLog $_.Exception.Message -Level Error }
                }
                Write-LTLog "Terminado." -Level Ok
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
    if (-not $items.Count) { Write-LTLog "No hay ninguna acción seleccionada." -Level Warn; return }
    $minutes = 5
    if ($items | Where-Object usesMinutes) {
        $minutes = Get-LTMinutes
        if (-not $minutes) { Write-LTLog "Indica un número de minutos entre 1 y 120." -Level Error; return }
    }
    Start-LTJob -Items $items -Minutes $minutes
}

function New-LTTextBlock([string]$Text, [string]$Style) {
    $tb = [Windows.Controls.TextBlock]::new()
    $tb.Text = $Text
    $tb.Style = $LT.Window.FindResource($Style)
    $tb
}

function Add-LTTabs {
    $tabs = $LT.Window.FindName('Tabs')
    $LT.CheckBoxes = @{}

    foreach ($tab in $LT.Config.tabs) {
        $panel = [Windows.Controls.StackPanel]::new()
        $panel.Margin = '16,8,16,16'

        if ($tab.intro) { [void]$panel.Children.Add((New-LTTextBlock $tab.intro 'IntroText')) }

        if ($tab.minutesInput) {
            $row = [Windows.Controls.StackPanel]::new()
            $row.Orientation = 'Horizontal'
            $row.Margin = '0,4,0,8'
            [void]$row.Children.Add((New-LTTextBlock "Intervalo de autoguardado (minutos):" 'FieldLabel'))
            $box = [Windows.Controls.TextBox]::new()
            $box.Text = [string]$tab.minutesInput
            $box.Style = $LT.Window.FindResource('MinutesBox')
            [void]$row.Children.Add($box)
            $LT.MinutesBox = $box
            [void]$panel.Children.Add($row)
        }

        foreach ($section in $tab.sections) {
            [void]$panel.Children.Add((New-LTTextBlock $section.title 'SectionHeader'))
            foreach ($item in $section.items) {
                $card = [Windows.Controls.Border]::new()
                $card.Style = $LT.Window.FindResource('Card')
                $grid = [Windows.Controls.Grid]::new()
                $c0 = [Windows.Controls.ColumnDefinition]::new(); $c0.Width = '*'
                $c1 = [Windows.Controls.ColumnDefinition]::new(); $c1.Width = 'Auto'
                $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1)

                $text = [Windows.Controls.StackPanel]::new()
                [void]$text.Children.Add((New-LTTextBlock $item.label 'ItemTitle'))
                if ($item.description) { [void]$text.Children.Add((New-LTTextBlock $item.description 'ItemDescription')) }

                if ($item.url) {
                    $text.Margin = '22,0,0,0'
                    [void]$grid.Children.Add($text)
                }
                else {
                    $cb = [Windows.Controls.CheckBox]::new()
                    $cb.Content = $text
                    $cb.Tag = $item.id
                    $cb.Style = $LT.Window.FindResource('ItemCheck')
                    $LT.CheckBoxes[$item.id] = $cb
                    [void]$grid.Children.Add($cb)
                }

                $btn = [Windows.Controls.Button]::new()
                $btn.Content = if ($item.url) { 'Abrir' } else { 'Ejecutar' }
                $btn.Tag = $item.id
                $btn.Style = $LT.Window.FindResource($(if ($item.url) { 'LinkButton' } else { 'RunButton' }))
                [Windows.Controls.Grid]::SetColumn($btn, 1)
                $btn.Add_Click({ Invoke-LTSelection -Ids @($this.Tag) })
                [void]$grid.Children.Add($btn)
                $LT.Buttons.Add($btn)

                $card.Child = $grid
                [void]$panel.Children.Add($card)
            }
        }

        $scroll = [Windows.Controls.ScrollViewer]::new()
        $scroll.VerticalScrollBarVisibility = 'Auto'
        $scroll.Content = $panel
        $ti = [Windows.Controls.TabItem]::new()
        $ti.Header = $tab.title
        $ti.Content = $scroll
        [void]$tabs.Items.Add($ti)
    }
}

function Show-LTWindow {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xaml = $LTXaml.Replace('__LT_VERSION__', $LT.Version)
    $window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new([xml]$xaml))
    $LT.Window = $window
    $LT.Gui = $true
    $LT.LogQueue = [Collections.Concurrent.ConcurrentQueue[string]]::new()
    $LT.Buttons = [Collections.Generic.List[object]]::new()
    $LT.FunctionNames = @(Get-ChildItem function: | Where-Object { $_.Name -match '^[A-Za-z]+-LT' } | ForEach-Object Name)

    $LT.LogBox = $window.FindName('LogBox')
    $busyBar = $window.FindName('BusyBar')
    $status = $window.FindName('StatusText')
    $runSelected = $window.FindName('RunSelected')
    $LT.Buttons.Add($runSelected)

    $window.FindName('AdminBadge').Text = if (Test-LTAdmin) { 'Administrador' } else { "Usuario: $env:USERNAME" }

    Add-LTTabs

    $runSelected.Add_Click({
            $ids = @($LT.CheckBoxes.Values | Where-Object IsChecked | ForEach-Object Tag)
            Invoke-LTSelection -Ids $ids
        })
    $window.FindName('ClearSelection').Add_Click({ $LT.CheckBoxes.Values | ForEach-Object { $_.IsChecked = $false } })
    $window.FindName('CopyLog').Add_Click({
            if ($LT.LogBox.Text) { [Windows.Clipboard]::SetText($LT.LogBox.Text); Write-LTLog "Registro copiado al portapapeles." -Level Ok }
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
                foreach ($b in $LT.Buttons) { $b.IsEnabled = -not $busy }
                $busyBar.Visibility = if ($busy) { 'Visible' } else { 'Collapsed' }
                $status.Text = if ($busy) { 'Trabajando... puedes seguir mirando, no cierres la ventana.' } else { 'Listo.' }
                if (-not $busy -and $LT.Job) {
                    try { $LT.Job.PowerShell.EndInvoke($LT.Job.Handle) } catch { }
                    $LT.Job.PowerShell.Dispose(); $LT.Job.Runspace.Dispose()
                    $LT.Job = $null
                }
            }
        }.GetNewClosure())
    $timer.Start()

    $window.Add_Closing({
            if ($LT.Job) { try { $LT.Job.PowerShell.Stop() } catch { } }
        })

    Write-LTLog "Lyons Tools $($LT.Version) - marca las acciones y pulsa 'Ejecutar seleccionadas', o usa el botón de cada fila."
    [void]$window.ShowDialog()
    $timer.Stop()
}

Show-LTWindow

#endregion
