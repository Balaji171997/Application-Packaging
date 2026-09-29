# Package Assistance - Porsche (PAG)

**This is the GPF tool with a Porsche settings file.** Created 18.09.2026 as a copy of
`GPF-PackageAssistance`; the only intended differences are in `settings.json`:

| | GPF | Porsche (PAG) |
|---|---|---|
| `Brand.Name` / `Family` | GPF | **PAG** / family GPF - every GPF convention (template `PSADT_Template_GPF`, log style, request folders) applies unchanged |
| Target brands (Step 1 dropdown) | Audi (INA) / VW (G1V) / Group (VWG) | **PAG only** - the dropdown is hidden, the outgoing folder gets `PAG_` |
| Brand rules | Audi silent close, VW "Volkswagen" title, Group 34-char name | **none** - default rules |
| Order number | AES label | **Order ID** label - free text in both brands since 20.09.2026 (no format, not required) |
| Package name format | strict `Vendor_App_Arch_Version-Release_Lang`; letters, digits, `. - _` and spaces only | the same shape, but **special characters allowed** and carried into the package as typed (`Brand.NameAllowSpecialChars = true`); only folder-illegal `\ / : * ? " < > \|` are refused; no space next to `_` in either brand. Hyphens are fine anywhere (vendor, app, even inside the version: `1.0-beta`). A wildcard version must be written `1.x` - `*` cannot be part of a Windows folder name, and the name IS the package folder |
| Name length (Manufacturer+Product+Version+Language, prefix not counted) | Group (VWG): hard stop over 34 | **soft counter** under the name box, live from the first character: green "28 of 34 characters used", red "- N over the limit; consider a shorter name" - never a popup, never a block (`Brand.NameLengthLimit = 34`) |
| Author in the script | "Last First" (`Prajapati Sunil`) | **"First Last"** (`Sunil Prajapati`) - `Brand.AuthorOrder = "FirstLast"`; swaps on the comma the directory gives ("Last, First") |
| Share needing other credentials | - | **sign-in prompt, but only on an action you started** (22.09, corrected 23.09): Fetch source, Find predecessor and Copy to Outgoing may ask; nothing else can. Typing a package name never produces a prompt - the predecessor hint skips a location it cannot open and stays silent. A prompt appears only for a real access failure (access denied / logon failure / 1219); a missing or unreachable path is logged, not asked about. Stale session cleared, up to 3 tries, `New-PSDrive -Credential`. Same code in GPF - it simply never triggers when access is fine |
| Incoming request folder | `AES-1-020436-A <identity>` | `<Order ID> <identity>` |

Porsche team review, 22.09.2026 - checked against the tool: Order ID free text, PAG-only prefix, the
reuse+snapshot crash (fixed 19.09), unblocking after package creation (`Assemble.ps1` strips
Zone.Identifier from everything it writes) and the template change (config / icons / header comments;
the tool reads markers and the variable block only) were already in place; the three rows marked
above were added the same day. Team copy: `..\PackageAssistance-Teams\PAG_PackageAssistance\`,
refreshed with `..\PackageAssistance-Teams\Update-Teams.ps1 -Brand PAG`.

Paths in `settings.json` (`RepositoryPath` = Incoming, `OutgoingPath`, `PredecessorPath`) are
placeholders under `Downloads\Porsche\` until Porsche's real locations are known.

**Keep the code identical to GPF.** A fix in one belongs in the other; only `settings.json` and
`$script:BuildStamp` in `Core.ps1` differ. Ship = `Pack-Engine.ps1` (pak) + the loader exe, like GPF.

---

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
