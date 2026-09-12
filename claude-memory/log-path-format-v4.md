---
name: log-path-format-v4
description: "Team's v3->v4 log-path modernisation - old $configToolKitLogDir\\$setuplogName becomes per-app $LogPathMain (Get-ADTConfig)"
metadata: 
  node_type: memory
  type: reference
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

Team convention discovered from live packages (~HALF of the ~896 live v3 Deploy-Application.ps1 use it). Package Builder's `Convert-LogPathFormat` (Build.ps1, runs in Build-PredecessorScript) implements the v3->v4 transform.

**OLD (v3):** flat toolkit log dir + per-purpose log FILE names —
`[string]$setuplogName = $VWG_appFullName + "_" + "Setup" + "_" + $deploymentType + ".log"` (many variants: `_Re`, `_preun`, `_de`, `1`, ...), used as `"$configToolKitLogDir\$setuplogName"` (note the capital-K `configToolKitLogDir`) in `Execute-Process /log ...` and `Copy-File -Destination`.

**NEW (v4):** a per-app log DIRECTORY, defined in EACH section that logs, referenced as `$LogPathMain`:
```
$adtConfig = Get-ADTConfig
New-ADTFolder -Path "$($adtConfig.Toolkit.LogPath)\$($adtSession.AppVendor)\$($adtSession.AppName)_$($adtSession.AppVersion)\$($adtSession.DeploymentType)"
$LogPathMain = "$($adtConfig.Toolkit.LogPath)\$($adtSession.AppVendor)\$($adtSession.AppName)_$($adtSession.AppVersion)\$($adtSession.DeploymentType)"
```
Transform: drop the `[string]$setuplogName*` decls; a NESTED `$configToolKitLogDir\$logfolder\$setuplogName` keeps its subfolder and the trailing filename becomes `$($adtSession.AppName)_$($adtSession.AppVersion)_$($adtSession.DeploymentType).log` (NOT a doubled `$LogPathMain`); inject the block at the top of each section that logs.

**r176/r177 FIX (team-reported "only a folder gets made, no setup log file"):** the old flat `$configToolKitLogDir\$setuplogName` was a FULL FILE PATH but the transform mapped it to `$LogPathMain` (a DIRECTORY) -> an installer's `-Log`/`-LogFileName` pointed at a folder -> no log file. FINAL v4 form (per the user, r177) - injected PER SECTION that logs:
```
$adtConfig   = Get-ADTConfig
$LogPathMain = "$($adtConfig.Toolkit.LogPath)\$($adtSession.AppVendor)\$($adtSession.AppName)_$($adtSession.AppVersion)\$($adtSession.DeploymentType)"
New-ADTFolder -Path $LogPathMain
$LogFileMain = "$LogPathMain\$($AppFullName)_Setup_<PHASE>.log"
```
- REUSE the template's `$AppFullName` (defined at template L137 = Vendor_App_Arch_Version-Rev_Lang) - do NOT rebuild the identity.
- `<PHASE>` = the SECTION: PRE-INSTALLATION->`PreInstall`, MAIN-INSTALLATION->`Install`, PostInstall/PreUninstall/Uninstall/PostUninstall/Repair... So the predecessor-uninstall log (`..._Setup_PreInstall.log`) and the main-install log (`..._Setup_Install.log`) are DIFFERENT files; the FOLDER auto-detects DeploymentType.
- Rule 2a (flat file path `$configToolKitLogDir\$setuplogName`) -> `$LogFileMain`; 2b (bare `$configToolKitLogDir`) -> `$LogPathMain` (dir); 2c (bare `$setuplogName` in a nested path) -> a filename literal (NOT $LogFileMain - would double the dir).
- Scope: EXE-type predecessor REUSE only (transform only fires when the v3 log tokens are present); FRESH packages get the same block as a SNIPPET (Logging > "Per-section setup log file (v4)") for manual insertion. Verified live on CarlZeiss (simple) + GIMP (nested).

Related: PSADT v3->v4 mapper func-rename is now case-insensitive (`New-folder`/`copy-file` were being missed). See [[ps-wpf-closure-scope]] for the GUI side.
