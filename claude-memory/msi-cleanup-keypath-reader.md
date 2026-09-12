---
name: msi-cleanup-keypath-reader
description: "MST cleanup - the MSI OpenView/StringData reader is non-deterministic; use Database.Export; run-key removal must be KeyPath-aware (dedicated run-key component = remove WHOLE component)"
metadata:
  node_type: memory
  type: reference
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

Package Builder MST cleanup (MstBuilder.ps1). Two hard-won facts, both proven live on **DassaultSystems 3DEXPERIENCELauncher.msi** (the canonical test MSI, at `C:\temp\DassaultSystems_3DExperience_x64_26.10.632-0001_en-US\Content\Files\`):

**1. The `$db.OpenView(...)/$rec.Fetch()/$rec.StringData(i)` reader is UNRELIABLE on real MSIs.** Same `SELECT` returned 10 rows one run, 12 (2 blank) another; `WHERE Component_='X'` said 3 while a client-side column read said 1. This mis-counted component footprints and drove wrong decisions. **FIX: read tables via `Database.Export(table, folder, "table.idt")` + parse the tab-delimited IDT (skip 3 header lines).** Deterministic. Implemented as `Export-MsiTable`. DELETE by exact PK via `WHERE pk='val'` + `View.Modify(6,rec)` (`Remove-MsiRowsByPk`) - never re-read columns to decide.

**2. Run-key removal must be KEYPATH-aware, not footprint-count.** A **dedicated** run-key component (the run key is its ONLY resource) has that run registry row AS its `Component.KeyPath` (Attributes band 4 = registry keypath). Deleting just the row leaves a **dangling keypath** -> install/repair error. The 3DExperience bug: `C_RegSystray` = dedicated (1 reg, 0 files, Attr=260, KeyPath=the run row); old logic deleted the row and left the component. **CORRECT rule** (`Resolve-MsiCleanupPlan`):
- dedicated -> remove the WHOLE component: Registry + Shortcut + File + **FeatureComponents** + Component rows (else orphaned refs).
- shared, run row NOT the keypath -> delete just the registry row.
- shared, run row IS the keypath -> reassign KeyPath to a File/other reg in the component (clear bit 4 if -> file), THEN delete; no target -> keep row, remove value via PSADT post-install (`DeferPsadt`).

**Shortcuts** are categorised by walking the Directory parent chain (`Resolve-DirCategory` -> Desktop/Startup/SendTo/Stray/Other) - Startup catches WiX `WIX_DIR_COMMON_ALTSTARTUP` (autostart, NOT desktop). Shortcuts are NEVER a component keypath -> deleting a shortcut row is always safe.

**Validation gate** (`Test-MstIntegrity`): apply the finished MST to a copy, refuse to ship if any dangling keypath or orphaned Registry/File/Shortcut/FeatureComponents -> missing component. Build-Mst throws on failure; New-PackageMst re-throws integrity failures (never ship a broken MST silently).

PS 5.1 traps hit here: `@()` on a `List[object]` of PSObjects throws (use `.Count`/`.ToArray()`) - see [[ps51-list-object-wrap]]; a void COM call like `ApplyTransform` emits `$null` into the pipeline (`[void]` it) and `return ,$list` returns the List object not its elements (`return $list.ToArray()`).

Toggles: Desktop / Startup(autostart) / SendTo+Stray / RunKey - each a Keep flag (per-MSI MsiFlags + global). Predecessor reuse replicates the predecessor MST (Read-MstSettings, Export-based, categorised) but the user's explicit Keep/Remove selection ALWAYS overrides. See [[log-path-format-v4]] for the sibling v3->v4 work.
