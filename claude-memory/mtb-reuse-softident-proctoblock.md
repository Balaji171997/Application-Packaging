---
name: mtb-reuse-softident-proctoblock
description: "MTB predecessor-reuse: keep the predecessor's name-based SoftIdent (don't overwrite with the new MSI ProductCode); empty ProcToBlock stays empty (no mirror)"
metadata: 
  node_type: memory
  type: project
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
  modified: 2026-08-07T04:18:06.677Z
---

MTB Package Builder (`Downloads\Application-Packaging\files`), predecessor-reuse path `Build-PredecessorScript` (Build.ps1). Two reuse bugs fixed **r221 (2026-08-04)**:

1. **SoftIdent** - REAL culprit was **`Merge-SnapshotDeltas`** (Build.ps1 ~1336), NOT the `$NewPkg.SoftIdent` line. On reuse of an MSI source, `Get-AutoSoftIdent` (GUI.ps1 ~1960) derives a ProductCode key from the MSI **read directly** (NO real snapshot needed) and stores it as `$newPkg.SnapshotSoftIdent`. `Merge-SnapshotDeltas` then judged the predecessor's carried key "simple = safe to replace" and overwrote a NAME-based key (`...\Uninstall\Mozilla Firefox 128.10.0`) with that ProductCode, tagging it `# [snapshot-detection]`. Its `$simple` test used `@($curGuids).Count -le 1` which is TRUE for a name key (0 GUIDs). Fix: added `$curIsNameKey` (regex the subkey after `\Uninstall\`; a non-`{GUID}` subkey = real ARP DisplayName) and require `-not $curIsNameKey` in `$simple` - so a name key is KEPT (name preserved, version swapped by the global pass; `[DisplayVersion=]` bumped). Empty/`<placeholder>`/single-`{GUID}` keys still refresh. Also hardened the `$NewPkg.SoftIdent` overwrite at ~1652 (`-and -not $carriedSI`) defensively, but on reuse `$newPkg.SoftIdent` is empty anyway (auto key goes to SnapshotSoftIdent). Rule: reuse = keep predecessor SoftIdent; GUID subkey -> swap ProductCode; name subkey -> keep name + version-swap.

2. **ProcToBlock** (Build.ps1 ~1755): `Set-ProcToBlockDefault` (mirrors ProcToClose into an empty ProcToBlock) was called on REUSE, so an EMPTY predecessor ProcToBlock got filled with ProcToClose values. Fix: removed that call from `Build-PredecessorScript` - on reuse the predecessor already decided ProcToBlock (empty stays empty; a non-empty list is carried as-is). `Set-ProcToBlockDefault` still runs for FRESH packages (Build-FreshScript), where mirroring is the sensible default. (`Merge-SnapshotDeltas` already skips empty ProcToBlock.)

Both are FRESH-package behaviors that were wrongly applied on reuse. Test-Build 529/0 with 4 new asserts (name SoftIdent kept + version-swapped, empty ProcToBlock stays empty, ProcToClose carried). MTB is a SEPARATE codebase from GPF - do not cross-edit. See [[mtb-getadtapp-and-reboot-style]], [[v4-getadtapplication-name-positional]].
