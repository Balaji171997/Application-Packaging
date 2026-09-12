---
name: msi-runas-verb-launch
description: "Snapshot 'Run installer' fails for every MSI because .msi has no 'runas' shell verb; launch MSI via msiexec"
metadata: 
  node_type: memory
  type: reference
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

**Symptom:** the Testing/Snapshot tab "Run installer" (install-for-capture) failed for EVERY MSI package (team-reported: Tenable/Zscaler/GlobalProtect) but worked for EXE (Gandalf).

**Cause:** `Start-Process foo.msi -Verb RunAs` THROWS - `.msi` (ProgID `Msi.Package`) has shell verbs `edit/Open/Repair/runasuser/Uninstall` but **NO `runas`** (only `.exe`/`exefile` has `runas`). PsExec can't run a raw `.msi` either (not an executable). The catch only retried on cancel/denied, so it surfaced as "install failing".

**Fix (MTB r206 / GPF r18-19):** new `Get-InstallerRunSpec -Path` (BundledMsi.ps1) → `.msi`→`@{File=msiexec.exe; Args='/i "path"'}`, `.msp`→`/p`, else the exe direct. Used by `Start-InstallerLaunch` (Admin), the SYSTEM/PsExec path (GUI.ps1), and the sandbox capture script. Verified via registry (`HKCR\Msi.Package\shell` has no `runas`). Locked by Test-Build `run-installer:` asserts.

**Also (same session):** `Get-SnapshotGuidance` (Snapshot.ps1) shows plain-language tab guidance - MSI = snapshot OPTIONAL (uninstall by product code, config via MST, extra/risky bits via PSADT); EXE = RECOMMENDED; predecessor loaded = NOT needed (reuse wins). The "risky MST change -> do it in PSADT instead" rule already existed for shared-component run-keys ([[msi-cleanup-keypath-reader]] / Add-PsadtRunKeyRemovals).
