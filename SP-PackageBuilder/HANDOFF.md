# Package Companion (SharePoint edition) - handoff note

Written 2026-09-12 when moving to a new test machine. Read this first in the new session.

## Step 0 - restore Claude's memory (before anything else)

Claude Code's memory of this whole project (45 files: every gotcha, dead end and decision) now lives IN this repo at
`Application-Packaging\claude-memory`. It only works once the profile is linked to it:

```
cd <path>\Application-Packaging
.\Setup-ClaudeMemory.ps1 -WorkingDir '<the folder you open Claude Code in>'
```

Do this BEFORE the first Claude session on the new machine, or that session starts with no memory at all.
The script is safe to re-run and merges anything already in the profile.

## Do this first on the new machine

**The exe is missing on purpose.** `PackageCompanion.exe` was compiled here and then quarantined by Cortex XDR /
Trellix within minutes (fresh unsigned ps2exe binaries trip them). Nothing else is broken. Rebuild it:

```
cd <this folder>
Import-Module ps2exe
Invoke-PS2EXE -InputFile .\Loader.ps1 -OutputFile .\PackageCompanion.exe -STA -noConsole -title 'Package Companion' -iconFile .\Lib\PackageCompanion.ico
```

Then `.\Pack-Engine.ps1` and launch `PackageCompanion.exe`. If the exe vanishes again on the new machine too,
fall back to display-name-only: keep files as `PackageBuilder.*`, UI text stays "Package Companion".

The Loader is a thin 54 KB exe that reads `PackageCompanion.pak` by name. A 968 KB exe is the OLD ps2exe build
with a July engine baked in - it ignores the pak entirely. `OLD-ps2exe-build.exe.bak` is that file, kept as evidence.

## What this tool is

A separate copy of Package Builder (MTB) that reads sources and predecessors from SharePoint first, with the UNC
shares as fallback. `Application-Packaging\files` is the untouched MTB original. This folder differs only in:
`SharePoint.ps1`, `Lib\PnP.PowerShell\1.12.0\`, `settings.json`, and four wiring lines. `Sync-FromMTB.ps1` pulls MTB
fixes forward and re-applies the wiring.

Wiring lives in FOUR places (all must list `SharePoint.ps1` LAST): `Pack-Engine.ps1` (builds the shipped pak),
`Build-Exe.ps1`, GUI.ps1 dev dot-source block, and GUI.ps1 `Invoke-PBAsync` runspace loader (~L4250).

## Auth - the only thing that works in this tenant

PnP.PowerShell **1.12.0** (last PS 5.1 build) + client id `28bf2c22-437c-42e7-a4be-e8a0f44a8264` (PnP Management
Shell). Graph CLI Tools and the Intune app are both blocked by tenant policy - do not retry them. Sign-in runs at
STARTUP before the WPF window exists; running it from a button handler or a worker runspace HANGS.

`Get-PnPFile` deadlocks on the WPF UI thread - `Invoke-SPDownload` clears the SynchronizationContext around the
download for that reason. Do not add a dispatcher pump there; it deadlocks the other way.

## Renamed 2026-09-11 to "Package Companion"

Everything renamed (text, exe, pak, config, icon, work root `C:\temp\PackageCompanion`). The old
`C:\temp\PackageBuilder` was left behind deliberately. Client did not like "Builder" (it assists, it does not build).

## Design work - where it stopped

Done: DPI awareness (fixes the crumbled sign-in window), header bar (package + RITM + user), rail footer
(Source/Target as quiet text), graceful no-access messages on every share, Step 4 nested as
`Review & Create | Publish | SCCM (Application, Collections, Diagnostics, Promote) | Intune (Assignments & Content,
Diagnostics)`, Direct Intune mode (hides the SCCM parent, leaves Repair empty), Intune Diagnostics local-only,
collections add auto-removes from the opposite collection, hints trimmed to one line each.

Agreed and NOT yet built, in this order:
1. Step rail with state dots (done / current / pending) and an amber review-item count badge on the step that
   produced them (`Get-ReviewItems` already exists; count is the new bit). Make the badge clickable.
2. Thin progress line under the content + plain sentence in the bottom strip, replacing the chunky ProgressBar.
3. **Copy to SharePoint** after Create: upload the built package to `{Vendor}/{App}/{Version}_{Release}/SCCM/{Name}/`,
   creating `SCCM` if missing. Show that button OR "Copy to Outgoing" depending on where the source came from.
   This is a WRITE to SharePoint - verify every file landed before reporting success.
4. Replace the "review summary" on Review & Create with a **build summary**.
5. Remember the last package on reopen.

## Gotchas learned the hard way

- Seven windowless orphan `PackageBuilder` processes were found holding the exe locked - leftovers from the hangs.
  If a rebuild says "access denied", check Task Manager for windowless copies before assuming a permissions issue.
- Never rename by piping quoted strings through the Bash tool - it replaced every `'` with `P` in two files.
  Use the Edit tool or a properly-typed hashtable in the PowerShell tool.
- `Test-Path` on an unreachable UNC blocks 30-90s. Use `Test-SPUncUsable` (bounded, cached) instead.
- The git repo is at `Application-Packaging` root. Today's work was uncommitted at handoff.

## Client presentation: 30 Sept 2026

German client; cares about security and flexibility. Tool only READS from live, so no live-touch concern.
