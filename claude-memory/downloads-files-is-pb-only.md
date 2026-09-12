---
name: downloads-files-is-pb-only
description: Downloads\files folder holds Package Builder files ONLY — create other deliverables in separate folders outside it
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 007744b9-50b2-40e9-9ff8-ae40a214068a
  modified: 2026-07-27T06:37:56.502Z
---

The working directory `C:\Users\AW140\Downloads\files` contains Package Builder files only. Do not create unrelated files or package folders there.

**Why:** User corrected me when I dropped SAP deployment scripts/packages into that folder — it's reserved for the Package Builder project.

**How to apply:** Put any other deliverables (PSADT packages, one-off scripts, etc.) in their own folder outside `files`, e.g. `C:\Users\AW140\Downloads\<TaskName>\`.

**2026-07-24 RELOCATION (important):** the tool folders were MOVED out of `Downloads\` into a new parent `Downloads\Application-Packaging\`. New findings doc lives at `Downloads\SecondtestCases\New_Findings.docx` with its test packages.

**2026-07-24 GPF RENAME → "Package Assistance" (current LIVE paths):**
- MTB source `Downloads\Application-Packaging\files` (r216+), MTB portable `…\PackageBuilder` (exe/pak still named `PackageBuilder.*`; MTB keeps the "Package Builder" name), MTB team share `\\mndemucfsm01\SEC-EQS-Lib-Gate\EQS_SEC\EQS\Script Repository\VWITS Team\Balaji\PackageBuilder\PackageBuilder.pak`.
- **GPF source `…\GPF-PackageAssistance`** (was `GPF-PackageBuilder`), **GPF portable `…\GPF_PackageAssistance`** (was `GPF_PackageBuilder`). GPF artifacts RENAMED: `PackageAssistance.exe` + `PackageAssistance.exe.config` + `PackageAssistance.pak` (loader/Pack-Engine/Build-Exe updated to those names; AES key unchanged). Old proven exe kept as `PackageBuilder.exe.old` for revert. GPF has NO share — the portable IS the distribution.
Use the Application-Packaging paths for all tool edits/packs/deploys going forward.
