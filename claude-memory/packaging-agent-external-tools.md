---
name: packaging-agent-external-tools
description: "PackagingAgent\\Tools holds 7-Zip + WiX DTF (committed, redistributable) and Procmon64/autorunsc (gitignored, Sysinternals licence forbids redistribution); measured numbers and the Unblock-File trap"
metadata:
  node_type: memory
  type: project
  originSessionId: a96ed47a-37eb-4079-887f-9966cf709555
  modified: 2026-09-26T10:36:00.275Z
---

Sept 2026: the agent now drives four free tools from PowerShell, in `PackagingAgent\Tools\`.
The user obtained them; they are all genuine and were tested on this machine.

| tool | version | licence | committed? |
|---|---|---|---|
| `7z.exe` + `7z.dll` | 7-Zip 26.03 | LGPL-2.1+, `License.txt` beside it | YES |
| `Microsoft.Deployment.WindowsInstaller.dll` | WiX 3.14.1.8722 | MS-RL, .NET Foundation signed | YES |
| `Procmon.exe` / `Procmon64.exe` | Sysinternals | free to use, **redistribution forbidden** | NO - gitignored |
| `autorunsc.exe` | Autoruns 14.3 | same | NO - gitignored |

Agent-owned code lives in `Src\Agent.Tools.ps1`. **The Engine sync is GONE** (26 Sep, user's call):
`Tools\Sync-Engine.ps1` was deleted, so `PackagingAgent\Engine\` is now the agent's OWN code and may be
edited freely - a fix there no longer gets overwritten, and it does not travel to/from Package Assistance.
New agent behaviour still belongs in `Src\`.

**Reuse seam:** the engine caches its archive tool in `$script:ArchiveTool`, so `Initialize-AgentTools`
sets it and `Get-ArchiveTool` / `Find-BundledMsi` / `Expand-BundledMsi` light up with no Engine edits.

## Measured, so don't re-litigate

- The old static byte scan for a bundled MSI: 8 real deliveries of 1.8-3.9 GB, **86-113 s each, 0 hits in
  all 8**. Removed. 7-Zip reads headers instead: **0.4-63 s**, and it found 3 MSIs inside
  `RevitCoreEngine_2026.exe` that the scan missed.
- 7-Zip 26.03 has **no handler for Inno Setup, Wise or InstallShield** - those read as a bare `PE`.
  For those the answer is to run the installer and watch (MSI watch + Procmon), not to extract.
  So innounp was considered and **not** worth getting.
- `autorunsc`: 190 scheduled tasks in 2.3 s, 811 services in 7.5 s, 50 run keys in 0.6 s, **unelevated**.
  Parse its `-c` output with `ConvertFrom-Csv`, NOT `-split ','` - service descriptions contain commas and
  every column after one shifts. Read it with `Get-Content` (BOM-aware); decoding by hand broke the CSV.
- **Procmon PROVEN elevated** (26 Sep): 15 s capture = **459 MB / 1.1M events / ~30 MB per second**, and
  6 child processes came out with full command lines (`Operation = 'Process Create'`, command line in
  `Detail`). So: AI must request it, refuse under 12 GB free, delete the capture after extracting facts.
  Chain is `/AcceptEula /Quiet /Minimized /BackingFile x.pml` → `/Terminate` → `/OpenLog x.pml /SaveAs x.csv`.

## Traps

- A DLL copied or downloaded carries Zone.Identifier and `Add-Type` fails with
  **`0x80131515 Operation is not supported`**. `Initialize-AgentTools` runs `Unblock-File` on the folder.
- `[Parameter(Mandatory)][string[]]` + an empty array = PowerShell treats it as missing and **prompts**,
  which hangs a background runspace. Use a default of `@()` and guard inside.
- Route 5 trap proven on a real delivery: Revit's three MSIs are `SqlLocalDB.msi`
  (Microsoft SQL Server 2019 LocalDB - a prerequisite, NOT the app) and two Autodesk component MSIs.
  Manufacturer vs order vendor is the discriminator. Also check the MSI's `Media` table: a cabinet name
  not starting with `#` is external, so that MSI **cannot** be packaged on its own.

See [[ai-agent-integration-plan]]; secrets and the Sysinternals exes are covered by
`PackagingAgent\.gitignore` (the repo previously had none anywhere - `agent.settings.json` was untracked
only by luck; history was scanned and no secret was ever committed).
