# Package Builder

Wizard for building PSADT v4 software-deployment packages and publishing them to **SCCM** and **Intune**.

## Run

```
powershell -ExecutionPolicy Bypass -File PackageBuilder.ps1
```

(or run `GUI.ps1` directly with `-STA`). PowerShell 5.1, Windows.

## Folder structure

```
PackageBuilder\
├─ PackageBuilder.ps1        <- START HERE (launcher; enforces STA)
├─ GUI.ps1                   <- the WPF wizard (4 steps + Integration/Testing/Troubleshoot/Dev-Test tabs)
│
│  engine modules (dot-sourced by GUI and by background jobs):
├─ Core.ps1                  <- config (settings.json), logging, work folders, version swap
├─ Predecessor.ps1           <- predecessor package parser (v3 + v4)
├─ PSADT_V3toV4_Mappings.ps1 <- v3 -> v4 script converter
├─ Source.ps1                <- source-folder resolver (installers / docs / icons)
├─ Build.ps1                 <- script assembly (sections, uninstall-previous, swaps, commands)
├─ MstBuilder.ps1            <- MST transform builder + MSI Property-table reader
├─ Assemble.ps1              <- package writer (template + Files/Documents/Icons + MSTs)
├─ Snippets.ps1              <- Step-3 snippet panel engine
├─ Sccm.ps1                  <- SCCM automation (create/modify/test/troubleshoot/move)
├─ Intune.ps1                <- Intune automation (create/assign/update content)
│
├─ settings.json             <- ALL paths + site/tenant config (edit here, not in the tool)
├─ snippets.json             <- Step-3 code snippets
├─ Test-Build.ps1            <- offline test suite (run after any code change)
│
├─ Lib\                      <- runtime dependencies
│   ├─ ICSharpCode.AvalonEdit.dll
│   ├─ IntuneWinAppUtil.exe
│   └─ PowerShell Module\    (MSAL.PS + IntuneWin32App - nothing else needed)
├─ PSADT_Template\           <- the blank v4 package template
└─ ConfigurationManagerPrelive\ <- ConfigMgr PowerShell module (console copy)
```

All paths resolve **relative to this folder** (`Get-ToolRoot`), so the whole folder is portable -
copy it anywhere and it works. The future .exe sits in this same folder and changes nothing.

## Runtime output (never in the tool folder)

| What | Where |
|---|---|
| Built packages | `OutputBasePath` from settings.json (default `C:\temp\<PackageName>`) |
| Log | `C:\temp\PackageBuilder\Logs\PackageBuilder.log` |
| .intunewin builds, temps, fetched client logs | `C:\temp\PackageBuilder\{IntuneWin,Temp,Downloads}` |

`WorkRoot` in settings.json moves all of the above. "Open work folder" button opens it.

## settings.json quick reference

| Key | Meaning |
|---|---|
| `PredecessorPath` | live package library (predecessor search) |
| `RepositoryPath` / `OutgoingPath` | incoming sources / finished-package share |
| `OutputBasePath` | where built packages are written |
| `WorkRoot` | runtime logs/temps base |
| `Sccm.*` | site code, server, prelive content share, DP group, folders, Test folders |
| `Intune.TenantId` | tenant domain (e.g. `contoso.onmicrosoft.com`) - REQUIRED for Intune |

## Shipping to the team (maintainer only) - LOADER + PAK model (recommended)

One-time: build the loader exe (never changes again):

```
Invoke-PS2EXE -InputFile .\Loader.ps1 -OutputFile .\PackageBuilder.exe -STA -noConsole `
              -title 'Package Builder' -iconFile .\Lib\PackageBuilder.ico
```

Every release after that:

```
powershell -ExecutionPolicy Bypass -File .\Pack-Engine.ps1     # -> PackageBuilder.pak
```

and copy ONLY the new `PackageBuilder.pak` to the team folder. The team copy is:

```
PackageBuilder.exe    <- stable loader (built once)
PackageBuilder.pak    <- ALL tool logic, AES-encrypted + compressed (this is the update unit)
settings.json         <- editable
snippets.json         <- editable
Lib\                  <- ALL dependencies in ONE folder:
    ICSharpCode.AvalonEdit.dll, IntuneWinAppUtil.exe, PackageBuilder.ico,
    PowerShell Module\ (MSAL.PS + IntuneWin32App),
    PSADT_Template\ (or .zip), ConfigurationManagerPrelive\
```

No readable script ships; updating the tool = replacing one .pak file (no recompile, no ps2exe).
OPTIONAL auto-update: set `"UpdatePath": "\\\\server\\share\\PackageBuilder"` in settings.json and
keep the newest .pak there - every launch picks it up automatically.

(`Build-Exe.ps1` remains as the alternative all-in-one-exe build; the pak model supersedes it.)

## After code changes

Run `powershell -NoProfile -File Test-Build.ps1` - everything should say ALL TESTS PASSED.
`PackageCreator_Plan_and_Progress.md` is the living build log / handoff document.
