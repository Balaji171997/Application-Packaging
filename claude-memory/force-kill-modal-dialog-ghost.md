---
name: force-kill-modal-dialog-ghost
description: Force-killing an app while it shows a modal
metadata: 
  node_type: memory
  type: reference
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

Discovered live while fixing Package Builder's shortcut screenshots on the MASTA suite (unlicensed test box).

**Fact:** If you `Stop-Process -Force` (TerminateProcess) an app while it is displaying a **modal Win32 dialog (class `#32770`)**, the dialog is left on screen as a **ghost/zombie window** whose owner becomes **csrss** (the original process is gone). That ghost is **un-removable** by WM_CLOSE, `EndTask`, or clicking — it persists until **logoff/reboot**. Killing the same app while only a plain/splash window is up leaves **no** ghost (validated repeatedly: ghost count unchanged).

**Why it matters here:** a leftover ghost dialog lingers on screen into the NEXT shortcut's full-screen capture = the "mixed up / pending to be closed" screenshots the user reported.

**The fix (Package Builder r130/r131, Screenshots.ps1 close logic):** before force-killing a shortcut's process tree, **drain dialogs first** — `WM_CLOSE` (a) every window owned by the launch's pids and (b) every `#32770` that appeared since launch (by class, since the dialog may be owned by a helper, not the app) — loop until no new dialog remains, then force-kill on a no-dialog state. Plus a title-based fallback to close windows left by untracked processes. See [[screenshot-keep-it-simple]].

**MASTA specifics:** `masta.exe` is a single WPF process (class `HwndWrapper[masta.exe;Splash Window]`); cold start ~10s, splash ~30s. Unlicensed, it shows "No Settings Found" then loops "'MASTA Core' (MCxxx) is not licensed - Open Licence Manager? Yes/No" (#32770) per module; dialog appearance timing is highly variable (~20s to >60s). The dialogs BLOCK, so an unattended run captures the splash + the blocking dialog. On a LICENSED machine MASTA opens its real window and closes cleanly. RUNNA/VPS/etc. behave the same (small loader + same licence dialog).
