---
name: gpf-portable-deploy-sync
description: "GPF deploy rule: after ANY GPF tool change, sync the portable/deploy copy at Application-Packaging\\GPF_PackageAssistance (pak + changed sidecar data files)"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
  modified: 2026-08-24T06:31:10.748Z
---

Whenever I change the GPF "Package Assistance" tool, the user wants the portable/deploy copy updated too — not just the source.

- **Source (edit here):** `C:\Users\AW140\Downloads\Application-Packaging\GPF-PackageAssistance` (hyphen)
- **Portable/deploy (must be synced):** `C:\Users\AW140\Downloads\Application-Packaging\GPF_PackageAssistance` (underscore) — this is the real run target: `PackageAssistance.exe` + `PackageAssistance.pak` + sidecar data files (`snippets.json`, `settings.json`, `KnowledgeBase.Recommend.json`, `Lib\`, `PsExec.exe`).

**Why:** users run the portable copy; a source-only change never reaches them.

**How to apply:**
- Code changes (in the `.ps1` files) → bump `$script:BuildStamp` (Core.ps1 line 7), repack to `PackageAssistance.pak` via Pack-Engine, then copy the pak into the portable folder.
- **Sidecar data files** (e.g. `snippets.json`) are NOT compiled into the pak — they're read from disk next to the exe. So editing one needs **no repack**, but the file must still be copied into `GPF_PackageAssistance`. Verify with `cmp -s` (byte-for-byte identical).

MTB "Package Builder" has the analogous portable copy — this rule is GPF-specific. See [[shared-folder-deployment]], [[downloads-files-is-pb-only]].
