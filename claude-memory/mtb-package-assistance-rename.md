---
name: mtb-package-assistance-rename
description: "SP-PackageCompanion is now MTB-PackageAssistance (Package Assistance, MTB prefix, same naming as GPF); loader exe must be rebuilt when the pak name changes; GUI.ps1 now ends the process on close"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7d55d151-f242-4450-a165-3b37421965bd
  modified: 2026-09-18T09:14:26.686Z
---

**18 Sep 2026:** the SharePoint-linked Package Builder variant was renamed on the user's ask
("same as the GPF one, MTB prefix"): repo folder `MTB-PackageAssistance` (was `SP-PackageCompanion`,
before that `SP-PackageBuilder`), files `PackageAssistance.exe / .exe.config / .pak / .ps1`,
`New-MTBToolRelease.ps1`, release zip `MTB_PackageAssistance-<version>.zip`, window header
"PACKAGE ASSISTANCE". Text replaced everywhere in scripts/docs/settings (not `lib\`).

**Why:** one product name across teams; "Companion" was a leftover.

**How to apply:**
- The exe is a thin ps2exe **Loader** that opens the `.pak` BY NAME - renaming the pak means
  recompiling `Loader.ps1` (`Invoke-ps2exe -InputFile .\Loader.ps1 -OutputFile .\PackageAssistance.exe
  -STA -noConsole -title 'Package Assistance'`; ps2exe module is installed CurrentUser). Never
  string-replace inside an .exe (it was done once by accident and the exe had to be rebuilt anyway).
- `Build-Exe.ps1` in that folder was corrupted in git (every `P` -> `a`); rewritten 18 Sep.
- **Lingering process bug fixed:** closing the window used to leave the exe running (busy-card WPF
  dispatcher thread + warm-up/job runspaces). GUI.ps1 of MTB-PackageAssistance, GPF-PackageAssistance
  and `files\` now shut those down and call `[Environment]::Exit(0)` after `ShowDialog` (unless
  dot-sourced in an interactive console). GPF pak repacked and copied to `GPF_PackageAssistance`.
  `files\` (MTB PackageBuilder) needs its exe rebuilt at the next release for the fix to ship.
- Smoke test that proves it: start the exe, close the main window, `Get-Process PackageAssistance`
  must be empty within seconds.
- Related: [[sharepoint-migration-status]], [[gpf-portable-deploy-sync]], [[never-bulk-rename-via-shell]].
