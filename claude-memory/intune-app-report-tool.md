---
name: intune-app-report-tool
description: IntuneApps - WPF Win32 app inventory at Downloads\IntuneAppReport with Excel-style per-column filters; ONE Sync button; 3 files
metadata: 
  node_type: memory
  type: project
  originSessionId: ff2c8d45-834f-45da-b4b7-19b87e7366ee
  modified: 2026-07-21T12:55:03.739Z
---

`C:\Users\AW140\Downloads\IntuneAppReport` (own folder, per [[downloads-files-is-pb-only]]).
Resume note on the share: `\\mndemucfsm01\...\VWITS Team\Balaji\Claude\IntuneAppReport-PROGRESS.md`.

**Three files only** — `IntuneApps.ps1` (window + filtering + export), `lib\Intune.ps1` (Graph, audit
cache, Notes parsing, snapshots), `lib\Xlsx.ps1` (OOXML writer). Launch `Run.cmd`.

**Rebuilt three times before it landed.** What the user actually wanted, learned the hard way:
- **Excel-style filter dropdown on EVERY column header** (checkbox list + counts), filter chips you can
  remove, clickable lifecycle tiles. Not a category rail, not filter comboboxes above the grid.
- **ONE Sync button.** They pushed back hard on "why require two sync buttons" — Sync does the app pull
  AND the audit backfill (deep first run, incremental after). No separate Full sync / fetch-creators.
- **Native WPF, not a browser app** — asked directly and they chose WPF, despite being told it caps how
  modern it can look.
- Grid columns: Name/Kind/Lifecycle/Version/Created/Created by/Created via/Assigned to. They explicitly
  removed "Modified by" and "What changed" from the grid — modification detail belongs in the detail
  pane and Excel only.
- Detail pane must be **built WPF controls** (badges, provenance grid, timeline), not a monospace text
  dump — the text dump was rejected as "not much useful".

**Verification tooling built in — use it, don't guess:**
- `-SelfTest` builds the real window offscreen and runs 15 checks (columns, every filter dropdown,
  single-row filter, all 7 lifecycle stages in the detail pane, tile click, chip removal, combined
  filters, search, Excel export). All pass as of 2026-07-21.
- `-Screenshot <path>` renders the window to PNG offscreen. **This is how the layout bugs were caught**
  (truncated headers "Kir"/"Versi", horizontal scrollbar) — reading the PNG beats trusting the XAML.

**Layout gotcha:** DataGrid headers hold title + filter button, so columns need explicit `MinWidth` or
star sizing truncates the header text. Set `ScrollViewer.HorizontalScrollBarVisibility="Disabled"` so
columns fit the width. Window 1240x700 clamped to WorkArea (theirs is 1280x752).

See [[intune-notes-json-schema]] for the lifecycle/created-via data, [[ps51-list-object-wrap]] for the
single-row crash, [[ps51-comma-arg-and-alias]] for the `function H` = Get-History trap.
