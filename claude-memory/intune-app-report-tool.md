---
name: intune-app-report-tool
description: IntuneApps - dark six-page WPF Win32 app reporting tool (repo\IntuneAppReport); measured/priority column fit; audit history translator; ONE Sync button; 3 files
metadata: 
  node_type: memory
  type: project
  originSessionId: ff2c8d45-834f-45da-b4b7-19b87e7366ee
  modified: 2026-09-15T12:17:48.861Z
---

Now lives in the repo: `Application-Packaging\IntuneAppReport` (Downloads copy is gone).
Resume note on the share: `\\mndemucfsm01\...\VWITS Team\Balaji\Claude\IntuneAppReport-PROGRESS.md`.

**2026-09-14 — history redesign (user: "human-readable change history from audit logs: who, what, old→new, when; current app info; drop the rest").**
- Root cause of unreadable history: `AsArray $x | ForEach-Object` — AsArray returns `,$arr`, a bare pipe hands the WHOLE array over as one item → property names/values were space-joined into one string in AuditCache v1. Same trap broke `AssignmentSummary` ("uninstall available: G1 G2"). Always write `(AsArray $x) | …` or foreach.
- **AuditCache format 2**: `Changes = @(@{N;O;V})` per event, `Groups` id→name map, `Format=2`; v1 loads as Legacy (who/when only, "Fields touched: …"), `BackfilledFromUtc` reset so the next Sync re-reads the audit log (~400 days, 30-day chunks). CreatedBy now only from `Create MobileApp` (v1 took any Create incl. assignments).
- **Translator** (`Get-ChangeHistory` / `ConvertTo-HistoryEntry` in lib\Intune.ps1): Notes JSON diffed key-by-key (Lifecycle: SAT → LIVE), `$Collection.X.Prop[i]` rebuilt per index (rules, return codes, scope tags), assignments with group names, supersedence/dependency sentences, `DeviceManagementAPIVersion` dropped. **Intune Patch quirk**: unchanged collections come back with old filled + new EMPTY = re-saved, not cleared → hidden unless Operation is Delete. Events grouped per (second, actor). Snapshot-diff entries only where the audit has no matching field|new.
- Detail pane = header badges → **Current app** facts → **Change history** cards (first 40 + "Show older" button) → raw Notes in a collapsed Expander. Export sheets: Apps + Change history (one row per line).
- `.ps1` files MUST be saved UTF-8 **with BOM** (PS 5.1 reads BOM-less as ANSI → "·" renders "Â·").
- `-Screenshot out.png -SelectApp 'Name*'` renders with that app selected and the pane scrolled to the history. SelfTest has 17 checks incl. a synthetic-event translator test.
- `[ordered]@{}` indexed with an [int] reads by POSITION → use a plain hashtable for int keys.

**2026-09-14 later — "make it a real enterprise reporting tool" round (user rejected incremental tweaks):**
- **Audit resource structure (the real reason assignments had no group):** one audit event has several `resources[]` — the app (no properties) + the assignment (`<appId>_0_0` in older events, its OWN guid in newer ones, with Intent/Target.GroupId) or `<source>_<target>` for relationships. Cache **format 3** folds all resources into the app(s) (type-based: resource `auditResourceType/type` not matching Assignment|Relationship|… = app); v2 files migrate in place (`Merge-CompositeKeys`) and `Repair-DetachedDetails` re-attaches detail by exact (When|What|Who). Real tenant: 3,076 assignment events have NO properties at all in Graph (bulk `assign` by M365EndpointAutomation) — unrecoverable; sync-to-sync diff now says "Added: required -> MDM_X".
- **Names:** `Resolve-UserNames` via `directoryObjects/getByIds` types user+servicePrincipal → cache `Users`; `Get-UnresolvedIds` sweeps the whole cache every sync; `Format-Who -WhoId` uses `$script:UserMap`; grid column is `CreatedByName`.
- **Sync speed:** audit query now `category eq 'Application' and activityDateTime …` + `$select` (falls back if rejected); ETA in progress. Not yet measured live.
- **Activity view** (second tab): tenant-wide feed, Period/Kind/Who/Search, double-click opens app, own Excel export. Feed persisted per app in `Data\ActivityFeed.json` with a stamp (`FeedVersion` bump forces rebuild): first build ~2 min for 13k entries, reload 4 s.
- Sync-diff entries are deduped against audit events in the same sync window (`$auditCovers`); "First seen by this tool" hidden when audit history exists.
- User's cache state on 14 Sep: 943 apps, 19,467 changes, history from 16 Jun 2025 (legacy v1 summaries before 10 Aug 2025), 1,328 groups named, people resolve on next Sync.
- Edit gotcha: files written by the Write tool use LF; PowerShell `.Replace()` with CRLF here-strings silently misses multi-line anchors → use the Edit tool for multi-line changes.

**Late 14 Sep — UI direction reset.** User rejected: (1) card-timeline detail pane, (2) light table-first "Change Report" mock with facets/KPI/histogram, (3) dark search-first "changelog" mock. Feedback: tool is an **all-round Win32 app reporting tool** (inventory by lifecycle, Test/UPD/Winget kinds, per-app full current settings + full history, "not cramped"), **dark theme**, no random period pills ("30 days 10 days… unprofessional"), "best in the market, advanced". User APPROVED the dark **6-page mockup** (artifact 2b6446bf-133c-4126-8d3c-2f6cdf1fc951) with one caveat: Apps column headers were cramped/half shown.

**15 Sep 2026 — WPF rebuilt to the approved design (current state).** `IntuneApps.ps1` = dark six pages: Overview (tiles, donut, kind bars, created/changes per month, Needs attention, recent activity) · Apps (grid, Excel-style header filters, chips, tiles, Columns chooser) · App page (tabs Overview / All settings / Assignments / History, old→new pills) · Activity (Period combo incl. Custom range with DatePickers, Kind, By, search) · People (click → Activity) · Insights (10 checks, two columns). Export button follows the page (apps / activity / app report / people). SelfTest 22 checks pass; `-Screenshot x.png -Page apps|activity|people|insights` or `-SelectApp 'X*' -Tab history` renders at work-area size.
- **Column-fit solution:** header min width is MEASURED at start-up (`Measure-Header` via FormattedText, Segoe UI 11.5 SemiBold + 48 px for padding/filter button); columns are in PRIORITY order and `Update-ColumnLayout` (on Grid SizeChanged) hides those that do not fit at their minimum and names them in the footer; `Columns` popup forces them on (then horizontal scroll). H-scrollbar is Disabled when everything fits (otherwise WPF shows a phantom scrollbar). User's screen = 1280×752 logical → window opens Maximized, 9 of 11 columns show (Created via, Publisher hidden). Kind/Lifecycle mins 88/104 for the chips.
- WPF-in-PS gotchas hit this round: `UniformGrid` is `Windows.Controls.Primitives.UniformGrid`; an implicit `TextBlock` style with Foreground leaks into Button/RadioButton content — don't define one; event handlers must not capture loop variables — put data in `.Tag` and read `$s.Tag`; row click = `PreviewMouseLeftButtonUp` + walk the visual tree to `DataGridRow` (`Find-Row`), skipping header/scrollbar/button sources; `@($null) + $a` in a group-by makes every bucket count 2 (use a List); bar-chart labels only on the peak + last bar (12 labels overlap in a 240-px card).
- Known gaps: people names still need `people.json` or admin consent; the DatePicker calendar popup is light (default template).

**15 Sep 2026 — DELIVERED to the team as ONE exe (user: "perfect").** User REJECTED the PB-style pak + loader + dist + zip + UpdatePath set-up as "messy / complicated" — wants: source folder stays clean, ONE separate team folder, an exe to launch, no .ps1 visible. **Naming (user chose after a long round): product = "Intune App Monitor".** Source folder/script stay `IntuneAppReport` / `IntuneAppReport.ps1` (user: "for source folder it is fine"). Rejected on the way: the "Companion" family (their own PB brand - "i dont like it"), Pack- family (Packlens/Packsmith), Convoy/Manifest, Chronicle, myth family (Argus/Vulcan/Olympus), aviation (Flightdeck), AppTrail/AppAtlas/AppLedger, IntuneLens/IntuneTrail/IntuneLedger. What landed: "Intune + App + role", plain words. Community collisions checked: IntuneAtlas exists (GitHub), "Radar" is Robopack's, "Scope" = MS scope tags. User still wants a distinct brand for the other tools too (PB/GPF) - open. Exe `IntuneAppMonitor.exe`, window/rail "Intune App Monitor", log `IntuneAppMonitor.log`, exports `IntuneAppMonitor-Apps|Activity|People|<app>-<date>.xlsx`, icon `lib\IntuneAppMonitor.ico`. Team folder location = **inside the repo**: `Application-Packaging\Intune App Monitor\` (user: "keeping this in application-packaging folder only, don't change locations"; NOT Downloads). Final: `Build-Team.ps1` (only extra file in the source folder) merges IntuneAppReport.ps1 + lib\Intune.ps1 + lib\Xlsx.ps1 (libs base64-embedded right after the `param()` line, `$script:PackedLibs`, `$script:BuildStamp`) and compiles the merged script straight into `IntuneAppMonitor.exe` with ps2exe 1.0.18 (`-STA -noConsole -x64`); lays out the team folder = `IntuneAppMonitor.exe` (296 KB) + `settings.json` + `lib\PowerShell Module\` + `Data\` record (AuditCache, ActivityFeed, people, ChangeLog, latest snapshot; NOT ModuleCache/log/xlsx). Update = rebuild, replace the exe. The script is build-aware: `$script:Root` = `$script:ToolRoot` → `$PSScriptRoot` → exe folder (`MainModule.FileName`); libs dot-sourced only when `$script:PackedLibs` is unset; no Write-Host on GUI paths (noConsole turns it into message boxes). Verified: exe opens "Intune Win32 apps" from a foreign CWD in ~60 s (record load) and closes cleanly.
- **Sign-in gate (15 Sep, user: "one needs to sign in at launch, otherwise someone without access can look at past data"):** `Invoke-SignInGate` runs BEFORE any Data is loaded - `Connect-Intune` (interactive MSAL) + `Test-IntuneAccess` (one authorised GET `mobileApps?$top=1`; 403 = signed in but no Intune role) - refuses with a message box and exits otherwise; `$script:SignedInAs` (`Get-SignedInAccount` = `$Global:AccessToken.Account.Username`) shown in the rail footer; Sync reuses the session. Always on in the exe (`$script:PackedLibs`); from source skipped only for -SelfTest/-Screenshot. Self-test stubs Connect-Intune/Test-IntuneAccess (closed/closed/open). Data\ JSON stays plain-readable with Notepad - the gate protects the tool, not the files. Also confirmed for the user: Data\ holds nothing user-bound (no on-disk token cache; ModuleCache = UNC module staging only); another account's Sync just continues the record (needs an Intune role that reads apps + audit); admin sign-in does NOT resolve azure.man ids (app consent, not user rights) - user has FILLED people.json.
- **Activity performance (15 Sep, user: "hangs on selections / typing")**: cause = per-keystroke full rebuild (regex + AsArray per entry over 12.7k, DateTime.Parse per row for day counts, 200 heavy PS-built rows). Fix: `Build-FeedIndex` once per feed load (lower-case haystack, day label, kind group, When, WhoText, minor flag, people counts as parallel arrays) → `Get-ActivityRows` is array-only (~0 s); search boxes debounced with DispatcherTimer (350/300 ms); list painted via state-based `New-FeedState/Add-FeedRows/Add-FeedChunk` - 20 rows sync then background chunks (`Dispatcher.BeginInvoke` + generation token), 100 per page; brushes frozen+cached, FontFamily/Link style cached. Self-test guards each op < 2 s (now ~0.3 s). Gotcha: replacing `$win.FindResource('Link')` globally also replaced the cache DEFINITION line → links rendered as grey buttons; check the definition after bulk replaces.
- **People page**: "Apps created" column = distinct AppIds with a `create` entry per person (796 on record); export = People + "Apps created" sheet (per app per creator, LifecycleNow/deleted). Resolve-names button and Azure-portal links were added then REMOVED at user request (they fill people.json by hand; all 37 filled on 15 Sep → 27 people rows). Build-Team never overwrites team Data\ (program only; people.json merged both ways; -RefreshData to copy record); parks exe as .exe.new when the tool is running.
- Gotcha: a RUNNING instance of the .ps1 locks the script file (Edit fails with EPERM) — ask the user to close the tool before editing.
- People 403: `directoryObjects/getByIds` for users denied for the Intune PowerShell client — not fixable by launching as admin; needs admin consent `User.ReadBasic.All` or `Data\people.json` (auto-listed sign-in names, fill once). Empty lookups are no longer stored.

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
