# Engine - the agent's own library

These files started life as copies of the packaging engine, but they are **the agent's own code now**.
There is no sync back to Package Assistance and no script that refreshes them: `Tools\Sync-Engine.ps1`
was deleted deliberately, because a sync meant any fix made here was silently overwritten the next time
somebody ran it.

**So: edit these freely.** They are part of the agent, they are versioned with it, and a change here
stays. The agent is standalone - `PackagingAgent\` runs on its own, with no Package Assistance folder
anywhere near it, which was always the point.

| File | What the agent uses from it |
|---|---|
| `Core.ps1` | settings, logging, work folders, package-name parsing |
| `Source.ps1` | installer engine fingerprint, MSI properties, source resolver, knowledge-base lookup |
| `Predecessor.ps1` | find the previous package and read its proven install/uninstall commands |
| `BundledMsi.ps1` | how to launch an installer (MSI via msiexec), local copy of a UNC installer, MSI watch dirs |
| `Snapshot.ps1` | before/after machine snapshot, diff, uninstall + cleanup derivation |
| `Screenshots.ps1` | the app's own Start-Menu shortcuts after an install |
| `MstBuilder.ps1`, `PSADT_V3toV4_Mappings.ps1` | MSI/MST work and the v3 to v4 command mapping |
| `Build.ps1` | the script builders: `Build-PredecessorScript`, `Build-FreshScript`, `Get-TemplateScript` |
| `KnowledgeBase.Recommend.json` | ~900 past packages: proven silent switches per vendor/app/engine |

## If a fix belongs in both places

A bug fixed here does not travel to Package Assistance, and one fixed there does not travel here.
That is the trade: independence over automatic updates. When a fix matters to both, apply it to both -
and remember the house rule that the agent is **never** integrated into Package Assistance.

## Where the agent's own code lives

Everything the agent itself does is under `Src\` - the pipeline, the prompts, the console, the AI
gateway, and `Agent.Tools.ps1` for the free tools it drives (7-Zip, the WiX MSI library, autorunsc,
Process Monitor). New agent behaviour normally belongs there rather than in this folder.
