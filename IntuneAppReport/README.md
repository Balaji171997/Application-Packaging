# Intune App Monitor

Win32 app reporting for Intune. Dark, six pages, one Sync button.

## Team folder

```
Intune App Monitor\
  IntuneAppMonitor.exe    double-click - no PowerShell window, no scripts
  settings.json           tenant + options
  lib\PowerShell Module\  MSAL.PS + IntuneWin32App (sign-in and Graph)
  Data\                   the history record - AuditCache.json, ActivityFeed.json, people.json, ChangeLog.json, Snapshots\
```

Copy the whole folder to local disk. **Launch asks for an Intune sign-in first** and then checks that the account
can actually read Intune apps; without both the tool closes, so nobody without Intune access can browse the
record. After that, loading the record takes about a minute. The signed-in account is shown in the rail. Built by `Build-Team.ps1` (below) into `Application-Packaging\Intune App Monitor`, next to this source folder.

## Source folder (this one - IntuneAppReport)

```
IntuneAppReport.ps1  the window: Overview · Apps · App page · Activity · People · Insights, filtering, exports
lib\Intune.ps1       Graph auth, the app pull, audit cache, history translator, snapshots
lib\Xlsx.ps1         the .xlsx writer
Data\                AuditCache.json (the long-term record), ActivityFeed.json, people.json, Snapshots\, ChangeLog.json, exports, log
Run.cmd              run from source (also -SelfTest, -Screenshot, -NoGui)
Build-Team.ps1       compiles the three scripts into ONE IntuneAppMonitor.exe (ps2exe, STA, no console) and lays out the team folder
```

Updating the team = run `Build-Team.ps1` again and replace their `IntuneAppMonitor.exe`. `-NoGui` / `-SelfTest` are
for the source copy (the exe has no console).

## Pages

| Page | What it answers |
|---|---|
| **Overview** | How many apps, by lifecycle (tiles + donut) and by kind (Standard / UPD / Test / Winget, plus how they were created); apps created and changes made per month; four *Needs attention* cards; the latest activity. Every tile and bar is a click into the filtered Apps list. |
| **Apps** | Every Win32 app. **Excel-style filter on every column** (checkbox list with counts, search inside the list), removable filter chips, clickable lifecycle tiles, free-text filter. Click a row for its page. Export writes exactly the list you see. |
| **App page** | *Overview* (summary, package, deployment, detection, recent history) · *All settings* (identity, lifecycle from the Notes JSON, program, requirements, detection, content, metadata, raw Notes) · *Assignments* (current + assignment history) · *History* (every change, day-grouped, old → new pills, filter by kind and person). Export = a per-app workbook. |
| **Activity** | Every change in the tenant, newest first. Period presets — Today, Yesterday, Last 7 / 30 / 90 days, This month, Last month, This year, All time, **Custom range** with from/to date pickers — plus kind, person and text. Click an app name to open it. |
| **People** | Who does what: **apps created** (creations only — the productivity number), changes, apps touched, what they mostly do, last active. Click a person to see their activity. Export = the table + an *Apps created* sheet, one row per app per creator (incl. apps deleted since). |
| **Insights** | Built-in checks: Failed UAT · in UAT > 30 days · LIVE but unassigned · RETIRED but still assigned · Test apps present · superseded but LIVE · same name in several versions · no change for over a year · no detection rules · created by hand. |

### Columns never get cramped

The Apps grid measures each header's full text at start-up and uses that as the column minimum. Columns
are shown in priority order — Name, Lifecycle, Kind, Version, Last change, Assignments, Created, Created by,
Last changed by, Created via, Publisher — and only as many as fit at their minimum; the rest are hidden and
named in the footer. **Columns** brings any of them back (the grid then scrolls sideways). A header is never
truncated. On the team's 1280 × 752 screens the window opens maximised and shows nine columns; at 1290 px of
grid width all eleven fit.

## History: what a change looks like

```
Version changed          Version: 140.14.0  ->  140.15.0
                         Content version: 3  ->  4  (new package content)
Lifecycle changed        Lifecycle: UAT  ->  FailedUAT                  (from the Notes JSON, key by key)
Assignment added         Required  ->  group MDM_MN_SWW_Autodesk_AutoCADLTDEU_INSTALL
Dependency added         this app depends on InventorPro 30.0.17501.0005 (auto-install)
App edited               Detection rule 1 added: Registry HKLM\SOFTWARE\VWG\CM\… [exists]
                         Return codes: 0 Success, 3010 SoftReboot  ->  0 Success, 1707 Success, 3010 SoftReboot
```

Rendered as *key · old (red) → new (green)*; every row says **who** (display name, sign-in name on hover),
**when**, and a colour dot for the kind (lifecycle, assignment, version, content, created, supersedence, other).

## Where the history comes from, and how far back it goes

| Source | Knows | Limit |
|---|---|---|
| **Intune audit log** | who, what, old → new, when | Intune keeps it ~1 year; the tool keeps forever what it has read |
| **App notes** | dated lines like `[2025-01-30] set to LIVE` | only what someone wrote |
| **This tool's own syncs** | every field diff between two syncs, incl. assignment targets | from the first sync onward; no author |

The rail footer states the coverage: *history on record since 16 Jun 2025 · 19,499 changes · 1,328 groups
named*. Nothing older than the audit retention can be recovered from Intune — from now on the cache is the
long-term record, so sync regularly (weekly is enough; the audit read is incremental).

**Assignments made through the bulk `assign` action** (the automation account does this) are logged by
Intune *without* a target. Those show as "Assignment added / removed (Intune recorded no detail)". The
target still appears in the next sync's own diff: *Assignments changed — Added: required -> MDM_X*.

## Sync

One button. It pulls the apps, reads the **app category only** of the audit log (`category eq 'Application'`
+ `$select`), resolves group ids and actor ids to names, snapshots, and translates new history. First run
reads a year back in 30-day windows (progress with ETA, saves after every window, Cancel keeps what it has);
later runs read only since the last sync.

**People names.** Group names resolve fine. User lookups (`directoryObjects/getByIds`, `/users/{id}`) are
denied for the Intune PowerShell client in this tenant — launching as admin does not change that; an admin
consenting `User.ReadBasic.All` for the client would. Until then `Data\people.json` lists every sign-in name
seen (e.g. `bn220@azure.man`) with an empty value: fill in the display names once and they are used everywhere.

### Cache format 3 (automatic migration)

- v1 flattened property lists into one string — unrecoverable; such entries show "Fields touched: …" and a
  full re-read replaces whatever Intune still retains.
- v2 keyed events by Intune's resource id. An assignment event has two resources (the app with no properties,
  the assignment with the detail), a relationship has `<source>_<target>` — so the app's history was missing
  its detail. v3 folds every resource into the app(s) it belongs to; an existing v2 file is **migrated in place
  on load** (no re-download) and detail filed under assignment guids is re-attached by exact timestamp.

## Excel export

The Export button follows the page: Apps → **Apps** (33 columns) + **Change history** for those apps;
Activity → **Activity** as filtered; App page → **Settings** + **Assignments** + **History** for that app;
People → **People**. Hand-written OOXML — no Excel needed, no ImportExcel, no Python.

## Self-test and screenshots

```
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\IntuneAppReport.ps1 -SelfTest
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\IntuneAppReport.ps1 -Screenshot out.png -Page apps
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\IntuneAppReport.ps1 -Screenshot out.png -SelectApp 'Revit*' -Tab history
```

The self-test builds the real window offscreen and runs 22 checks: overview, measured header widths and the
responsive column count, every filter dropdown, single-row filtering, all four app-page tabs, every lifecycle
stage, the activity presets / kind / person / search / custom range, people, insights, all three exports, and
a synthetic-event translator test (version, lifecycle, assignment, supersedence, rules, legacy entry,
actor-id-to-name, pill rendering). Use it after any edit. `-Screenshot` renders any page to PNG at the
work-area size — that is how cramped columns are caught.

## settings.json

| Key | Meaning |
|---|---|
| `TenantId` | Tenant domain or GUID. |
| `ModulePath` | Folder holding `MSAL.PS` + `IntuneWin32App` (the tool ships its own under `lib\`). |
| `DataPath` | Blank = `.\Data`. |
| `FetchCreators` / `CreatorBackfillDays` | Audit-log read, and how far back the first run walks (400 covers Intune's retention). |
| `StaleAfterDays` | Insights: "no change for over N days" (default 365). |
| `TestPatterns` / `UpdPatterns` / `WingetVersionValues` | Matched against the FIRST or LAST name token only, so "Attestation Client" is never a test app. |
| `CreationMethodRules` | Ordered `{ Method, Pattern }` matched against the inner note text. |
| `LifecycleRules` | Fallback only, for the few apps whose Notes are free text. |

## Notes

- Sign-in is interactive, so this **cannot run unattended**. Unattended would need an Entra app registration
  with `DeviceManagementApps.Read.All` + `Group.Read.All` + `User.ReadBasic.All`.
- `installSummary` returns HTTP 400 for every app in this tenant, so install counts are not collected.
- Scripts are saved UTF-8 **with BOM** on purpose: Windows PowerShell 5.1 reads a BOM-less file as ANSI and
  the `·` separators turn into `Â·`.
