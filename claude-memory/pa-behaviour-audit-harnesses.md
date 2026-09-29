---
name: pa-behaviour-audit-harnesses
description: Two harnesses that audit Package Assistance behaviour across MTB/GPF/PAG (static AST rules + a runtime control sweep with an out-of-process dialog watchdog) - what they check and what they found on 24 Sep 2026
metadata:
  node_type: memory
  type: project
  originSessionId: 7d55d151-f242-4450-a165-3b37421965bd
  modified: 2026-09-24T04:13:05.648Z
---

**Built 24 Sep 2026** after the user asked to stop fixing reported bugs one by one and instead "check every
functionality and every possible scenario ... like a real enterprise tool". Both live in the session scratchpad
(`Audit-Behaviour.ps1`, `Sweep-Controls.ps1`) - copy them forward when the scratchpad rotates.

**Static (`Audit-Behaviour.ps1`)** - AST over every .ps1 of all three brands. Rules worth keeping: busy card shown
but never hidden; hide not in a `finally`; a raw modal between `Show-PBBusy` and its `Hide` (offset-aware, or every
dialog looks like a hit); IO or a dialog from a PASSIVE handler (TextChanged/LostFocus/SelectionChanged);
`Hide-PBMainWindow` with no guaranteed show; a click handler with slow IO but no card and no button lock; an empty
`catch {}` around a whole click handler. 20 findings -> 2 false positives.

**Runtime (`Sweep-Controls.ps1`)** - drives the REAL window off-screen, walks every step + Step-4 tab, clicks every
VISIBLE ENABLED Button/CheckBox/ComboBox in two scenarios (empty form, name-only) and records exception / did the UI
say anything / how long the UI thread blocked. Destructive controls are in a $SKIP list.
Two traps learned the hard way:
- a modal BLOCKS the tool's UI thread, so the dismisser must be a SEPARATE PROCESS (Start-Job + EnumWindows +
  WM_CLOSE). It must close only windows of the process it launched - my first version targeted every window on the
  desktop and closed the user's ISE. Scope by "powershell.exe PIDs that did not exist before the sweep".
- WPF dialogs are not `#32770`; match class `HwndWrapper*` and exclude the main window by title.

**What it caught (all fixed):** MTB's *Copy package to Outgoing* was dead - `.GetNewClosure()` handlers cannot see
script functions, so `Get-PBState` threw on every click (see [[ps-wpf-closure-scope]]); the prelive mirror guard
failed OPEN in all three brands (`try/catch{}` around the "does content exist?" check, then `/MIR` anyway) - now
`Confirm-PreliveMirror`, which asks when it cannot check; three buttons that did nothing on an empty form; a
multi-minute robocopy on the UI thread with no card; a swallowed predecessor-MST read failure.

**How to apply:** after any GUI change, run both harnesses for all three brands before Test-Build. See
[[pa-credential-prompts-opt-in]] for the rule about which paths may prompt.
