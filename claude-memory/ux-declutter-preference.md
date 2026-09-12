---
name: ux-declutter-preference
description: "How the user wants Package Builder UI simplified — labeled rows, nothing hidden/duplicated, one accented primary per tab, junior-friendly"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
  modified: 2026-07-21T09:17:28.127Z
---

For Package Builder UX cleanup the user's rules (2026-07-04): make it professional, smoother, junior-friendly; keep ALL functionality reachable independently; do NOT break anything.

**Specifics chosen:**
- Declutter crowded button strips by **regrouping into labeled rows** (e.g. "Report:" / "Actions:"), NOT by hiding tools behind a "More ▾" dropdown. Nothing hidden.
- **No duplicated buttons / same action in two places.**
- Button placement should be **by action, handy for juniors**; give each tab ONE **accented primary** action (theme `PbAccentButton`) so the main button is obvious.
- The snapshot/analyze flow must be **independent of the selected installer** — user may run/install manually (provide Admin + SYSTEM CMD consoles inside the snapshot dialog; SYSTEM via PsExec `-s -i`).
- Screenshots split by install context: `Screenshots\<app>\snapshot\<admin|system>` so admin-vs-system installs compare.

**Why:** the user felt the tool (esp. the snapshot window's 9-button bar) was overfilled; going live imminently so changes must be safe.

**Scope note (2026-07-21):** the "labeled rows, not dropdowns" rule is about **action buttons** in
Package Builder. It does NOT extend to **filters**: for [[intune-app-report-tool]] the user explicitly
asked for dropdowns ("use dropdown as well and make UI smarter"). Filter axes with many values belong
in comboboxes; commands stay as visible rows. Same session: they also rejected showing the same
concept in two places (Retired appearing both as a left-rail category and a lifecycle value) — the
no-duplication rule is the durable one.

**Window sizing:** their work area is **1280x752**. A 1560x840 window did not fit. Default to ~1200x700
and clamp to `[Windows.SystemParameters]::WorkArea` at runtime.

**How to apply:** prefer conservative, reversible passes (typography/hierarchy/text-trim) over structural XAML re-layout right before go-live; validate main-window XAML offscreen after edits. Do changes LOCAL-only first (`C:\Users\AW140\Downloads\PackageBuilder`), user pushes to share/repo later. See [[downloads-files-is-pb-only]], [[screenshot-keep-it-simple]].
