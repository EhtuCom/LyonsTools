<#
.SYNOPSIS
    Builds lyonstools.ps1, the single-file distributable, from the sources in this repo.

.DESCRIPTION
    Order of the generated file:
        scripts/start.ps1   (param block + shared state)
        functions/**/*.ps1  (all functions)
        config/tools.json   (embedded as $LTConfigJson)
        xaml/MainWindow.xaml (embedded as $LTXaml)
        scripts/main.ps1    (entry point)

    The output is pure ASCII so it works the same with `irm | iex`, with
    "Run with PowerShell" and with Windows PowerShell 5.1 reading it as ANSI:
      - .ps1 sources: non-ASCII characters are only allowed inside double-quoted
        strings (and comments) and are rewritten as $([char]0xNNNN).
      - JSON: non-ASCII becomes \uNNNN.
      - XAML: non-ASCII becomes &#xNNNN;

.EXAMPLE
    .\Compile.ps1           # build
    .\Compile.ps1 -Run      # build and launch the GUI
#>
[CmdletBinding()]
param(
    [string]$Output,
    [switch]$Run
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Output) { $Output = Join-Path $root 'lyonstools.ps1' }
$utf8 = [Text.UTF8Encoding]::new($false)

function Read-Source([string]$Path) { [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) }

function Test-Tokens($Tokens, [string]$File) {
    foreach ($t in $Tokens) {
        $allowed = $t.Kind -in 'StringExpandable', 'HereStringExpandable', 'Comment'
        if ($t.Text -match '[^\x00-\x7F]' -and -not $allowed) {
            throw "$File (line $($t.Extent.StartLineNumber)): non-ASCII text must be inside a double-quoted string. Token: $($t.Text)"
        }
        if ($t.NestedTokens) { Test-Tokens $t.NestedTokens $File }
    }
}

function ConvertTo-AsciiPs([string]$Code, [string]$File) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseInput($Code, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "$File (line $($errors[0].Extent.StartLineNumber)): $($errors[0].Message)" }
    Test-Tokens $tokens $File
    $sb = [Text.StringBuilder]::new($Code.Length)
    foreach ($ch in $Code.ToCharArray()) {
        if ([int]$ch -gt 127) { [void]$sb.AppendFormat('$([char]0x{0:X4})', [int]$ch) } else { [void]$sb.Append($ch) }
    }
    $sb.ToString()
}

function ConvertTo-AsciiEscaped([string]$Text, [string]$Format) {
    $sb = [Text.StringBuilder]::new($Text.Length)
    foreach ($ch in $Text.ToCharArray()) {
        if ([int]$ch -gt 127) { [void]$sb.AppendFormat($Format, [int]$ch) } else { [void]$sb.Append($ch) }
    }
    $sb.ToString()
}

# --- config ------------------------------------------------------------------
$jsonPath = Join-Path $root 'config\tools.json'
$jsonText = Read-Source $jsonPath
$config = $jsonText | ConvertFrom-Json   # validates JSON
$version = $config.app.version

$ids = @{}
foreach ($tab in $config.tabs) {
    foreach ($section in $tab.sections) {
        foreach ($item in $section.items) {
            if ($ids.ContainsKey($item.id)) { throw "Duplicate id in tools.json: $($item.id)" }
            $ids[$item.id] = $item
        }
    }
}

# --- functions -----------------------------------------------------------------
$functionFiles = Get-ChildItem -Path (Join-Path $root 'functions') -Filter *.ps1 -Recurse | Sort-Object FullName
$functionCode = foreach ($f in $functionFiles) {
    "# ---- $($f.FullName.Substring($root.Length + 1)) ----"
    ConvertTo-AsciiPs (Read-Source $f.FullName) $f.Name
}
$functionCode = $functionCode -join "`r`n"

# every action referenced in the config must exist
foreach ($item in $ids.Values) {
    if ($item.action -and $functionCode -notmatch "function\s+$([regex]::Escape($item.action))\b") {
        throw "tools.json item '$($item.id)' points to missing function '$($item.action)'"
    }
}

# --- xaml ----------------------------------------------------------------------
$xamlText = Read-Source (Join-Path $root 'xaml\MainWindow.xaml')
[void][xml]$xamlText   # validates XML
if ($xamlText -match "(?m)^'@" -or $jsonText -match "(?m)^'@") { throw "XAML/JSON cannot contain a line starting with '@" }

# --- assemble ----------------------------------------------------------------------
$start = ConvertTo-AsciiPs (Read-Source (Join-Path $root 'scripts\start.ps1')) 'start.ps1'
$main = ConvertTo-AsciiPs (Read-Source (Join-Path $root 'scripts\main.ps1')) 'main.ps1'
$start = $start.Replace('__LT_VERSION__', $version).Replace('__LT_REPO__', $config.app.repo)

$jsonCompact = ConvertTo-AsciiEscaped $jsonText '\u{0:x4}'
$xamlAscii = ConvertTo-AsciiEscaped $xamlText '&#x{0:X4};'

$header = @"
<#
    Lyons Tools $version - utilidades de Windows, Office, Java y firma digital
    https://github.com/$($config.app.repo)  |  $($config.app.publisherUrl)

    GENERATED FILE - DO NOT EDIT. Edit the sources and run Compile.ps1.
    Built $(Get-Date -Format 'yyyy-MM-dd HH:mm')
#>
"@

$out = @(
    $header
    $start
    $functionCode
    "`$LTConfigJson = @'`r`n$jsonCompact`r`n'@"
    "`$LTXaml = @'`r`n$xamlAscii`r`n'@"
    $main
) -join "`r`n`r`n"

# normalise line endings and make sure the result parses
$out = ($out -replace "`r?`n", "`r`n")
$tokens = $null; $errors = $null
[void][Management.Automation.Language.Parser]::ParseInput($out, [ref]$tokens, [ref]$errors)
if ($errors) { throw "Generated script does not parse: $($errors[0].Message) (line $($errors[0].Extent.StartLineNumber))" }
if ($out -match '[^\x00-\x7F]') { throw 'Generated script is not pure ASCII.' }

[IO.File]::WriteAllText($Output, $out, $utf8)
Write-Host "Built $Output (v$version, $($ids.Count) tools, $([math]::Round((Get-Item $Output).Length / 1KB)) KB)" -ForegroundColor Green

if ($Run) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $Output }
