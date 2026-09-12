---
name: gpf-xlsx-testing-fixes
description: "GPF field-testing findings (C:\\temp\\Package_Assistance_Tool_Testing_Data.xlsx): which are real loopholes + the 3 conversion fixes done in r60"
metadata: 
  node_type: memory
  type: project
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
  modified: 2026-08-24T05:59:17.819Z
---

Source: `C:\temp\Package_Assistance_Tool_Testing_Data.xlsx` (GPF packager field tests, ~25 pkgs). I analysed each vs the code; user decided which to fix.

**DONE + deployed r60 (2026-08-17), Test-Build 612/0:**
- **-Transforms (Sr#1)**: the GENERATED MSI install command hardcoded `-Transform` (singular) - Build.ps1 `Get-MsiCommandSet` ~1225 -> now `-Transforms` (v4). (The v3->v4 converter already mapped it; only the fresh-generated command was wrong.)
- **ProcessAsUser drop (Sr#2)**: PSADT_V3toV4_Mappings.ps1 new LAYER 1c - strips `-Wait` and `-ContinueOnError [$true/$false]` from `Start-ADTProcessAsUser` calls (call line + backtick continuations). v4 has `-NoWait`/`-ExitOnProcessFailure`, NOT `-Wait`/`-ContinueOnError` -> they threw "parameter cannot be found". Negative-lookahead keeps `-WaitForMsiExec`/`-WaitForChildProcesses`; -Wait on other cmdlets (Start-ADTProcess/MsiProcess) untouched.
- **EnvironmentVariable (Sr#15)**: new LAYER 1d - `[Environment]::GetEnvironmentVariable("VAR","Target")` (and `[System.Environment]::`) -> `Get-ADTEnvironmentVariable -Variable "VAR" -Target <Machine|User|Process>`; 1-arg form drops -Target. (The name-map only covered the PSADT `Get-EnvironmentVariable` cmdlet, not the .NET static form.) NB: target extraction uses string-concat of the 3 alt groups, NOT `(...|Where){[0]}` (that indexes the FIRST CHAR of a single-string result -> "M").

**User EXPLICITLY DEFERRED (do NOT "fix"):** installer/zip FILENAME swap to current source (Sr#4·2/#8/#13/#14). User rule: "current source to be swapped is fine for now, no need to swap with installer itself - reuse is for SIMILAR predecessor packages, so source shouldn't have many changes."

**DONE + deployed r61-r62 (reproduced against `C:\temp\newtestcases`, Test-Build 619/0):**
- **Sr#9 ProductCode inner space (r61)**: Build.ps1 Format-OutputScript strips a stray space inside a `-ProductCode ' {GUID}'` literal (next to the existing `\Uninstall\ {GUID}` fix). GUIDs never have spaces so it's safe.
- **Sr#7·1 Documents\Documents double-nest (r61)**: BrandGpf.ps1 Resolve-GpfRequest - the request's OWN `Documents` folder was added as a DocItem, then Copy-Item -Recurse nested it. Now adds its CONTENTS (filtered: skip Complexity Matrix + `~$` lock files), so files land directly in `<pkg>\Documents`.
- **Sr#20 predecessor `_0001` (r61)**: Predecessor.ps1 Read-PredecessorModel normalises the predecessor PackageName before Parse-PackageName - accepts brand prefix (INA_/VWG_/G1V_) + `_0001` and emits canonical `-0001`. DISAMBIGUATION: only strip the prefix when the stripped name still parses (INA_Adobe_CreativeCloud... -> Adobe vendor); else keep it (VWG_ZipPred... = VWG is the real vendor). Both browse paths already normalise (BrandGpf.ps1:233 auto-match + GUI.ps1:3125 manual). User rule: accept _0001 when browsing, always emit -0001 in branding/names.
- **Sr#3/#19 ProcToClose from v4 predecessor (r62)**: Predecessor.ps1 Extract-SessionValues - a v4 predecessor stores the list in `$adtSession.AppProcessesToClose = @(...)` and the wrapper `VWG_ProcToClose = $adtSession.AppProcessesToClose` is only a reference the field-regex can't read. Added: when ProcToClose isn't a real @(...) list, pull it from `AppProcessesToClose = @(...)`. (ZEISS_INSPECT now carries.)
- **Sr#4·1 java proc-close (r62)**: Predecessor.ps1 Strip-Boilerplate stripped ALL Show-Installation(Welcome|Progress). The STANDARD welcomes sit inside the consumed `if($VWG_UseDialogs){}` block, so a Welcome reaching that strip is a CUSTOM close (e.g. java applet `Show-InstallationWelcome ... -BlockExecution` inside `if($BackTask)`). Now strips ONLY Show-InstallationProgress (Set-PredecessorProgressBar re-carries it); custom Welcomes are KEPT.

- **Sr#7·2 two consecutive -IfEmpty (r63)**: reproduced against the real Adobe predecessor - the 2nd `Remove-Folder -IfEmpty` (Acrobat) was dropped during `Convert-V3ToV4Content`'s F15 -IfEmpty rewrite (PSADT_V3toV4_Mappings.ps1 ~721). Root cause: the "other params" run `(?:\s+-\w+\s+\S+)*` used `\s` which matches NEWLINES, so the first line's match ate across the line break and swallowed the entire next `Remove-ADTFolder ... -IfEmpty` line. Fix: `\s` -> `[ \t]` throughout the regex (same-line whitespace only). Both lines now convert to their own guarded blocks. (My earlier "Format-OutputScript both survive" check was misleading - Format-OutputScript has its OWN -IfEmpty rewrite that's fine; the DROP was in the converter's F15 rewrite.)

**STILL OPEN:** Sr#20 branding key `_` (Siemens) - the Read-PredecessorModel normalise should cover it; re-verify with a Siemens repro if it recurs.
**By-design / enhancement:** Sr#3/#19 ProcToClose carry (implemented via AppProcessesToClose - verify w/ v4 predecessor); Sr#4·3 pred-of-pred kept in between-code (r58 rule); Sr#21 VW->Volkswagen is title-ONLY by design (BrandGpf.ps1:193) - extending to action logs is an enhancement; Sr#14/#21·2 metadata/MRF enhancements.
See [[gpf-30jul-findings-and-brand-selector]].
