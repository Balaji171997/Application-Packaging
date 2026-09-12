---
name: screenshot-keep-it-simple
description: "Package Builder shortcut screenshots must use dead-simple fixed timing, not adaptive \"is it loaded\" detection"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

For Package Builder's shortcut-screenshot feature (Screenshots.ps1 `Invoke-ShortcutScreenshots`), the user wants a DEAD-SIMPLE flow and explicitly rejected clever adaptive detection: "these complicated logics are not working properly simplify."

The accepted design (r125): launch the target (or .lnk, like a normal user) → wait up to TimeoutSec(30s) for a window → take SHOT 1 → wait SecondShotSec(15s) → take SHOT 2 → close → next. Capture is FULL SCREEN (WorkingArea, excludes taskbar), not per-window cropping. Tray/background apps (no window appears): capture full screen WITH taskbar + a zoomed notification-area crop so the tray icon shows.

**Why:** Over several rounds I built increasingly clever "fully loaded" detectors (static-fraction over a sliding window, window-set quiet timer, splash→app handoff, frame signatures/dedup). They kept mis-firing — grabbed MASTA's static splash instead of its later licence dialog, froze browser/news pages at the 90s cap, etc. The user's point: a fixed 15s wait + full-screen grab is more reliable and predictable than any heuristic.

**How to apply:** Resist re-introducing adaptive timing/detection here. If the final state appears late, lengthen the fixed wait or add a third fixed shot — don't add screen-watching logic. Keep full-screen capture (it naturally includes splash+dialog together and any tray area). See [[verify-semantic-not-syntax]] for the broader "make it actually work, simply" expectation.
