# Lyons Tools

Windows, Office, Java, PDF and digital signature utilities for law and tax firms in Catalonia (Spain), maintained by [ehtu.com](https://ehtu.com).

A single PowerShell script with a graphical interface, nothing to install. The interface is available in **English** (default), **Español** and **Català**. The language is chosen in the window and remembered per user.

## How to open it

Open **PowerShell** (Start menu, type `powershell`) and paste:

```powershell
irm https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1 | iex
```

Or download [`LyonsTools.cmd`](LyonsTools.cmd) and double-click it.

PowerShell does not need to be opened as administrator. Lyons Tools runs as your user and only asks for administrator permission for the actions that need it. This way per-user settings always land in your profile, even when another account approves the prompt.

## Supported systems

- Windows 10 and Windows 11
- Windows Server 2016 / 2019 / 2022 / 2025, including **Remote Desktop / terminal servers** with standard (non-admin) users

Actions marked **Administrator** are disabled for standard users, who never see a password prompt they cannot answer. On a terminal server the administrator runs those once (installers, root certificates, browser policies) and they apply to every user. Everything else works per user:

| For standard users | How |
|---|---|
| Office AutoRecover | Saved through Office itself as the user's preference. Admins also get it locked as a policy. |
| Root certificates (FNMT, AOC, ACA) | Installed in the user's own certificate store. Windows asks the user to confirm each root. |
| Signador (AOC) | Uses the per-user installer. |
| Default PDF app / default browser | Always per user. Windows requires the user to confirm the choice. |
| Restart Explorer | Only restarts the current session, never other users' sessions. |

What changes on Windows Server:

- **No winget:** Chrome, Edge, Firefox, Adobe Reader, Java (Temurin and Oracle 8) are downloaded from their official enterprise installers instead.
- **Remote Desktop Session Host:** installers run in *install mode* (`change user /install` … `/execute`), as Microsoft recommends, so they are set up for every user.
- **Server Core** has no desktop, so only the command line mode works there (`-Run`).
- **Quick Assist** does not exist on Windows Server; the action says so.

Every installer's digital signature is verified and must belong to the expected publisher (FNMT, Autofirma, Consorci AOC, Bit4id, Adobe, Google, Microsoft, Mozilla, Eclipse, Oracle). A download from the wrong publisher is never run.

Requirements: Windows PowerShell 5.1, which is built into Windows 10, Windows 11 and Windows Server 2016 or later. Windows Server 2012 R2 and older are not supported. On an old, unpatched Windows 10 / Server 2016 where `irm` fails with a TLS error, use `LyonsTools.cmd` instead: it forces TLS 1.2 before downloading.

## What it includes

### Office
- **AutoRecover every N minutes** in Word, Excel and PowerPoint.
- **Full crash protection:** AutoRecover, keeps the last version if a file is closed without saving, and Word backup copies (`.wbk`).
- **Find recoverable documents** (`.asd`, `.wbk`, `.xar`, unsaved documents from the last 30 days).
- **Remove the locked AutoRecover settings.**
- Show the Office version, update Office, Quick Repair.

### Digital signature
- **FNMT Configurator** (latest version from the FNMT website).
- **Root certificates** for FNMT and Consorci AOC (idCAT, T-CAT). Roots are only installed if their fingerprint matches the official ones.
- **My certificates:** lists signing certificates and warns about those expiring within 60 days.
- **Autofirma**, the **Signador** native app (AOC) and the **T-CAT** card software (Bit4id).
- **Check that it works:**
  - The official Signador test page (AOC).
  - A test signature and certificate validation on VALIDe.
  - The FNMT certificate status check.
- Links: FNMT, AEAT, ATC, VALIDe, idCAT Mòbil, e-NOTUM, AOC support.

### Legal (Abogacía / Advocacia)
- **ACA card software (Bit4id)** and **ACA root certificates** (ACA ROOT 2 checked against its official fingerprint).
- Links: LexNET, e-justícia.cat, the Seu judicial, a Signador test, ACA Plus, DNIe software.
- The "Mini Lector ACA" driver from abogacia.es is deliberately **not** installed: its code signature has been revoked, and Windows recognises the reader without it.

### Java
Check the installed version, install the latest LTS Java (Eclipse Temurin) or Oracle Java 8, clear the Java cache.

### Windows
- **Settings:** show file extensions, clipboard history (Win+V).
- **PDF:**
  - Install Adobe Acrobat Reader.
  - Make Adobe the default PDF app, using the right method for each Windows version, then confirm the change.
  - Test: open a PDF with the default app.
  - Make Edge, Chrome and Firefox **download PDFs and open them in Adobe** instead of their built-in viewer (`AlwaysOpenPdfExternally`, Firefox `DisableBuiltinPDFViewer`). There is also an action to undo this.
- **Default browser:** Chrome, Edge or Firefox.
- **Utilities:** support report, Quick Assist, clean temporary files, flush DNS, restart Explorer, Windows Update.

Windows protects the default PDF app and default browser choices. Since Windows 10, no tool may change them silently on computers that are not in a domain. Lyons Tools opens the exact Windows dialog or Settings page so the user only has to confirm. Firefox can usually set itself as the default.

All downloads come from the official websites at the time of use, so the latest version is always installed. The digital signature of every installer is checked before it runs.

## Command line (deployment and remote support)

```powershell
# List the available IDs ("x" = requires administrator)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1))) -List

# Run specific actions, in Spanish
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/EhtuCom/LyonsTools/main/lyonstools.ps1))) -Run office-crash-protection,fnmt-root-certs -Minutes 5 -Lang es
```

Logs are kept in `%LOCALAPPDATA%\LyonsTools\logs`. The language setting is in `%LOCALAPPDATA%\LyonsTools\settings.json`.

## Development

```
config/tools.json       Tabs, sections, actions and every interface text in en/es/ca
functions/<area>/*.ps1  One function per action (Verb-LTName)
scripts/start.ps1       Parameters and shared state
scripts/main.ps1        Entry point and WPF interface
xaml/MainWindow.xaml    Window layout
Compile.ps1             Builds lyonstools.ps1 (single file)
```

To add a utility:
1. Write the function in `functions/`. Log messages take the three languages:
   ```powershell
   Write-LTLog "Done." "Hecho." "Fet." -Level Ok
   ```
2. Add an entry to `config/tools.json` with `"action": "FunctionName"`, a `label` and a `description` in `en`, `es` and `ca`, plus `"admin": true` if it needs administrator rights.
3. Run `.\Compile.ps1` (or `.\Compile.ps1 -Run` to try it) and commit the generated `lyonstools.ps1`.

The compiler rejects missing translations. It also converts accents so the generated script is pure ASCII and works the same with `irm | iex` and with Windows PowerShell 5.1. In `.ps1` files, accented text must be inside double quotes.

## License

MIT. Use at your own risk.
