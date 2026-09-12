---
name: snapshot-huge-install-perf
description: "Snapshot Analyze froze on a 10 GB app - eager WPF tree build + O(n^2) counts; fixed with lazy children, child cap, memoised counts"
metadata: 
  node_type: memory
  type: project
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
  modified: 2026-07-20T13:08:29.412Z
---

**Symptom (2026-07-20, MTB r212, reported on a user machine; same code in GPF):** snapshot **Analyze** hung / "not responding" for an app whose install is ~10 GB. Nothing to do with the capture — `Get-PathMap` is already capped (5M files / 900 s) and the heavy diff already runs OFF the UI thread. The freeze was **rendering the change tree**.

**Two root causes, both measured (not guessed):**
1. **Eager visual-tree build.** `New-SnapNodeUI` (GUI.ps1) recursed into EVERY child up front even though children start `Collapsed`, creating a WPF `Border`+`StackPanel`+`TextBlock`(+badge) per changed item. Measured in STA: **2 000 nodes = 2.4 s, 24 000 nodes = 20.6 s** of pure construction on the UI thread. A 10 GB app is easily 100k+ files → minutes.
2. **O(n²) counts.** `Get-SnapshotTreeCounts` is recursive and the UI called it for EVERY node it rendered, so each call re-walked that node's whole subtree. Measured on a 24k-file tree: **9.7 s → 4.2 s (2.3x)** once memoised (the win grows with depth).

**Fixes (both tools; behaviour deliberately unchanged — every node still starts collapsed, so the visible result is identical):**
- `Get-SnapshotTreeCounts` gained an optional `-Cache` hashtable, memoised on `$Node.f`. No cache = old behaviour exactly (tests call it that way). GUI passes ONE shared cache per tree (`$fCache` / `$rCache`) and threads it into `New-SnapNodeUI -CountCache`.
- **Lazy children**: `New-SnapNodeUI` builds an EMPTY kids panel plus a `$build` scriptblock stashed in the row's `Tag.Build`; `$script:SnapToggle` runs it on FIRST expand then nulls it (so re-expand can't duplicate). Initial render is now just the root rows.
- **Per-node child cap** `$script:SnapTreeChildCap = 400`, then a "… +N more (use 'Open full report (CMTrace)')" row — bounds a single pathological folder (installers do drop 20k+ files in one dir).

**TRAP hit while doing this (cost a debug cycle):** inside the `.GetNewClosure()` builder, `$script:SnapTreeChildCap` resolved to **$null**, so `$i -ge $null` was true on the first child and every folder collapsed to one "+1000 more" row. Fix: read the cap into a LOCAL (`$cap = [int]$script:SnapTreeChildCap; if ($cap -le 0) { $cap = 400 }`) BEFORE `.GetNewClosure()` so it is baked in. Same family as [[ps-wpf-closure-scope]] — never reference `$script:` vars from inside a closure; capture locals.

**Verification:** offscreen STA render test (scratchpad `render_lazy.ps1`) — 13 assertions: children not built until expand, Build cleared after first expand, cap = 400 + 1 overflow row, "+600 more" text, re-expand does not duplicate, nested branches build, and a SMALL folder still renders ALL 12 children (cap must not change normal cases). Test-Build gained 4 count-cache asserts each: MTB 482/0, GPF 544/0.

**Shipped:** MTB `2026-07-20.r213` (source + local portable + team share), GPF `GPF-2026-07-20.r26` (source + portable). See [[shared-folder-deployment]] for the deploy procedure and the two-GPF-folders gotcha.
