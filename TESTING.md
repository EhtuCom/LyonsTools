# Lyons Tools – test plan for a Windows computer or server

This file is written for Claude Code (or a technician) running **on the computer under test**. It is self-contained: nothing from the development conversation is needed.

Lyons Tools is a single PowerShell script (`lyonstools.ps1`) with a window and a command-line mode. It installs and configures software for law and tax firms (Office AutoRecover, FNMT / AOC / ACA certificates, Autofirma, Signador, Java, PDF defaults, default browser). The latest version is always at:

```
https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1
```

## Ground rules for the tester

- Work in **Windows PowerShell 5.1** (`powershell.exe`), not `pwsh`. Everything below runs from a normal (non-elevated) PowerShell window; the tool asks for administrator rights itself when it needs them.
- Run each step, **record the exact log output**, and at the end write a report (see the last section). Do not stop at the first failure; collect everything.
- Some actions need a human to click something (a UAC prompt, a Windows "Open with" dialog, Settings). You cannot click. When a step says *interactive*, run it, tell the person what the tool asked them to do, wait for them to say it is done, then verify the result with the check command given.
- Do not change anything on the computer other than through Lyons Tools. Do not uninstall software.
- Logs are also written to `%LOCALAPPDATA%\LyonsTools\logs\<date>.log`. Attach that file to the report.

## 0. Download and identify the environment

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
$dir = "$env:USERPROFILE\LyonsToolsTest"; New-Item -ItemType Directory $dir -Force | Out-Null
Invoke-RestMethod 'https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1' | Set-Content "$dir\lyonstools.ps1" -Encoding UTF8
Set-Location $dir
$lt = { param([string[]]$a) & ([scriptblock]::Create((Get-Content .\lyonstools.ps1 -Raw))) @a }

# Environment facts for the report
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, ProductType
(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server').TSAppCompat   # 1 = Remote Desktop Session Host
whoami; whoami /groups | Select-String 'S-1-5-32-544'   # non-empty = member of Administrators
$env:SESSIONNAME
Get-Command winget -ErrorAction SilentlyContinue | Select-Object Source
```

Record: Windows edition and build, whether it is a terminal server (`TSAppCompat = 1`), whether the current user is an administrator, whether winget exists.

Then:

```powershell
& $lt -List
& $lt -List -Lang es
```

Expected: a table of ~57 action IDs, with an `x` in the Admin column for admin-only ones; the second call shows Spanish labels.

## 1. Read-only actions (safe, run first, as any user)

```powershell
& $lt -Run java-check,office-info,certs-list,win-report
```

Expected: no `[ERROR]` lines. `office-info` shows the Office product and version. `win-report` ends with "Report copied to the clipboard". Record the full output.

```powershell
& $lt -Run browser-default-test
& $lt -Run pdf-test
```

Expected: the log names the current default browser and PDF app, then ehtu.com opens in that browser and a one-page test PDF opens in that PDF app. Ask the person which browser/app actually opened and record it.

## 2. Window (GUI) check

Only on a computer with a desktop (not Server Core). Run:

```powershell
Start-Process powershell.exe -ArgumentList "-NoProfile -STA -Command `"& ([scriptblock]::Create((Get-Content '$dir\lyonstools.ps1' -Raw)))`""
```

Ask the person to confirm: the window opens; the header shows the user name (plus "RDP" or "Server" where applicable); the Language selector switches the whole window to Español and Català; on a standard (non-admin) account the actions tagged "Administrator" are greyed out and the log shows a warning saying so; the "Run" buttons on the Java tab work and the log fills in. Then close it.

## 3. Office AutoRecover (per user; safe, reversible)

Close Word, Excel and PowerPoint first.

```powershell
& $lt -Run word-autorecover -Minutes 7
& $lt -Run office-crash-protection -Minutes 5
& $lt -Run office-info
```

Expected: each app reports "AutoRecover every N minutes". If the user can elevate, a UAC prompt appears (*interactive*: the person accepts it) and the log adds "Locked as a policy for this user". `office-info` afterwards shows either "locked at 5 min" (admin) or "set in Office" (standard user).

Verify independently, then ask the person to open Word > File > Options > Save and confirm the interval shows 5 minutes and "Always create backup copy" is ticked:

```powershell
Get-ItemProperty 'HKCU:\Software\Policies\Microsoft\Office\16.0\Word\Options' -ErrorAction SilentlyContinue | Select-Object autosaveinterval, keepunsavedchanges
Get-ItemProperty 'HKCU:\Software\Microsoft\Office\16.0\PowerPoint\Options' -ErrorAction SilentlyContinue | Select-Object SaveAutoRecoveryInfo, FrequencyToSaveAutoRecoveryInfo
```

Undo (admin only): `& $lt -Run office-autorecover-reset` – expected "AutoRecover policies removed".

```powershell
& $lt -Run office-find-recoverable
```

Expected: a list of recoverable files or "No recoverable documents found" – never an error.

## 4. Root certificates (admin: machine store with one UAC prompt; standard user: user store with a Windows confirmation per root)

```powershell
& $lt -Run fnmt-root-certs
& $lt -Run aoc-root-certs
& $lt -Run aca-root-certs
```

*Interactive*: admin accepts one UAC prompt per action; a standard user answers "Yes" to each "install this root certificate?" dialog. Expected log: "Installed: <name> -> Trusted Root ..." or "... Intermediate ..." lines, expired ones "Skipped (expired)", no unknown-root warnings. Verify:

```powershell
$store = if ((whoami /groups) -match 'S-1-5-32-544') { 'LocalMachine' } else { 'CurrentUser' }
Get-ChildItem "Cert:\$store\Root" | Where-Object Subject -match 'FNMT-RCM|CONSORCI AOC|EC-ACC|ACA ROOT' | Select-Object Subject, Thumbprint, NotAfter
Get-ChildItem "Cert:\$store\CA"   | Where-Object Subject -match 'FNMT|AOC|CIUTADANIA|Ciutadania|ACA ' | Select-Object Subject | Sort-Object Subject
```

Expected roots: AC RAIZ FNMT-RCM, AC RAIZ FNMT-RCM G2, AC RAIZ FNMT-RCM SERVIDORES SEGUROS (and G2R), AC RAIZ FNMT-RCM TSA, CA CONSORCI AOC (G3) ROOT-A, EC-ACC, ACA ROOT 2.

## 5. Installers (admin only; each one downloads from the official site and checks the digital signature)

Run one at a time. Each is *interactive* (UAC and/or an installer wizard). After each, confirm the program appears in Installed apps:

```powershell
& $lt -Run autofirma         # expected signer: Secretaría General de Administración Digital; "Autofirma installed"
& $lt -Run signador          # Consorci AOC; admin: silent MSI for all users; standard user: per-user installer
& $lt -Run fnmt-configurador # FNMT; wizard. The log must say the signature was verified (its timestamp cannot be checked by Windows – that is expected)
& $lt -Run tcat-middleware   # Bit4id PKI Manager; wizard
& $lt -Run aca-middleware    # Bit4id (Abogacía); wizard
& $lt -Run java-install-temurin   # Eclipse Temurin JRE, passive install; then java-check must show it
& $lt -Run adobe-reader      # winget if present, otherwise the 800 MB official installer with a progress bar
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' | Where-Object DisplayName -match 'Autofirma|Signador|Configurador|Bit4id|Universal MW|Temurin|Acrobat' | Select-Object DisplayName, DisplayVersion
```

On a terminal server the log must show "Terminal server detected: installing in install mode for all users" before each installer. Then, as a **different, standard user** in another session, open the installed app once and run `& $lt -Run certs-list` to confirm the certificate chain is seen there too.

Only on a test machine, if the person agrees: `& $lt -Run java-install-oracle8`.

## 6a. PRIORITY – diagnose "Make Adobe Reader the default PDF app"

This action has been reported as not working on a Windows Server 2022 terminal server. Run this section first and report every value; the developer needs them to fix it.

```powershell
"Build: $([Environment]::OSVersion.Version)  Server: $((Get-CimInstance Win32_OperatingSystem).ProductType -ne 1)"
"Adobe ProgIds registered: " + (('Acrobat.Document.DC','AcroExch.Document.DC') | Where-Object { Test-Path "Registry::HKEY_CLASSES_ROOT\$_\shell\open\command" })
"Adobe in RegisteredApplications: " + ((Get-ItemProperty 'HKLM:\SOFTWARE\RegisteredApplications').PSObject.Properties.Name | Where-Object { $_ -match 'Adobe' })
"Adobe capability for .pdf: " + (Get-ItemProperty 'HKLM:\SOFTWARE\Adobe\Acrobat Reader\DC\Capabilities\FileAssociations','HKLM:\SOFTWARE\Adobe\Adobe Acrobat\DC\Capabilities\FileAssociations' -ErrorAction SilentlyContinue).'.pdf'
"UserChoice BEFORE: " + ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice' -ErrorAction SilentlyContinue) | Select-Object ProgId, Hash | Out-String).Trim()
"Group Policy default associations file: " + (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -ErrorAction SilentlyContinue).DefaultAssociationsConfiguration
"UCPD driver: " + (Get-Service UCPD -ErrorAction SilentlyContinue).Status
Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf' -ErrorAction SilentlyContinue | Select-Object PSChildName
```

Now run the action and have the person describe precisely what appears:

```powershell
& $lt -Run pdf-default-adobe
```

Ask and record:
1. Which window appeared? ("How do you want to open this file?" list / Settings page / nothing). Did it have a tick box or text about "always" using the app? Was Adobe Acrobat in the list?
2. What did the person click, and what happened next (the PDF opened in Adobe? in Edge? nothing)?
3. Copy the **complete** log output of the action, including the "Not changed yet (...)" line if present – the value in brackets is the dialog's result code and is important.

Then:

```powershell
"UserChoice AFTER: " + ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice' -ErrorAction SilentlyContinue) | Select-Object ProgId, Hash | Out-String).Trim()
& $lt -Run pdf-test     # which program opened the test PDF?
```

Finally, as a control, have the person set it by hand: Settings > Apps > Default apps > Choose default apps by file type > .pdf > Adobe Acrobat (on Windows 11: Default apps > Adobe Acrobat > Set default). Then run the two commands above again and record whether *manual* setting works. If even the manual way does not stick, the computer is managed by a policy or a profile tool and the developer needs to know that.

## 6. PDF and browser defaults (per user; Windows requires a human click)

```powershell
& $lt -Run pdf-browser-download     # admin: Edge/Chrome/Firefox policies; log says "will download PDFs"
& $lt -Run pdf-default-adobe        # interactive
```

`pdf-default-adobe`: on Windows 10 / Server 2016-2022 a "How do you want to open this file?" window appears – the person chooses Adobe Acrobat and presses OK. On Windows 11 / Server 2025, Settings opens on Adobe's page – the person presses "Set default". The log must end with "Done: PDF files will open with Adobe Acrobat" within 2 minutes. Verify:

```powershell
(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice').ProgId   # Acrobat.Document.DC or AcroExch.Document.DC
& $lt -Run pdf-test   # must open in Adobe
```

Then, in Edge or Chrome, open any PDF link on the web and confirm it downloads and opens in Adobe instead of inside the browser. Undo with `& $lt -Run pdf-browser-reset`.

```powershell
& $lt -Run browser-default-edge     # interactive; then browser-default-test must say Microsoft Edge and open ehtu.com in Edge
& $lt -Run browser-default-chrome   # interactive; same check for Chrome
& $lt -Run browser-default-firefox  # Firefox usually sets itself without clicks
(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice').ProgId
```

Set the browser back to what it was at the end.

## 7. Remaining Windows actions

```powershell
& $lt -Run win-clipboard-history   # on Server 2016 / Win10 < 1809: a warning that it is unavailable, no error
& $lt -Run win-file-extensions     # restarts Explorer in this session only; other users' sessions must not blink
& $lt -Run win-clean-temp
& $lt -Run win-flush-dns           # admin; UAC
& $lt -Run win-restart-explorer
& $lt -Run win-quick-assist        # on Windows Server: warning "not available"; on Windows 10/11: Quick Assist opens
& $lt -Run win-update              # Windows Update settings page opens
& $lt -Run java-clear-cache
```

## 8. Report

Produce a table: **action ID | Windows edition | user type (admin / standard) | result (OK / FAIL / NOT TESTED) | what the log said | what the person saw**. Below it, list every `[ERROR]` and `[WARN]` line verbatim, and attach `%LOCALAPPDATA%\LyonsTools\logs\<today>.log`. Note which steps needed a human click and whether the instruction in the log was accurate for this Windows version.
