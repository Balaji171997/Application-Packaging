# IntuneApps

Win32 app inventory for Intune with **Excel-style filtering on every column**. Filter the grid, export
exactly what you filtered.

```
Run.cmd
```

Three files, nothing else:

```
IntuneApps.ps1     the window, filtering, export
lib\Intune.ps1     Graph auth, the app pull, audit cache, Notes parsing, snapshots
lib\Xlsx.ps1       the .xlsx writer
Data\              snapshots, AuditCache.json, ChangeLog.json, exports, log  (created on first run)
```

## Filtering

Every column header has a **▾ filter button**. Click it for a checkbox list of that column's values with
counts — tick what you want, exactly like Excel AutoFilter. The button turns blue when that column is
filtering. Filters on different columns combine, `Clear filters` resets everything, and the search box
matches across all fields at once.

The values offered in a dropdown reflect the *other* active filters, so you never tick a value that
would return nothing.

Columns: `Name · Kind · Lifecycle · Version · Created · Created by · Created via · Status · Assigned to`

## Where the data comes from

The Notes field is JSON written by your tooling, so lifecycle is read from it directly, not guessed:

```json
{ "notes": "Created by SCCM2Intune App Migration tool.",
  "managed": true, "status": "OK", "rollout": "", "pilot": "", "lifecycle": "SAT" }
```

797 of 801 apps use it. That gives three independent axes:

| Column | Source | Values in your tenant |
|---|---|---|
| **Kind** | app name / version | Standard 762, UPD 19, Test 10, Winget 10 |
| **Lifecycle** | `lifecycle` key | LIVE 525, SAT 158, RETIRED 78, UAT 24, FailedUAT 11, PreRollout 1, not recorded 4 |
| **Created via** | inner `notes` text | SCCM2Intune 298, Manual 249, Intune Win32 Automator 210, Winget Intune Manager 26, Package Builder 8, other 10 |

**"Manual (no note)"** means the inner note is empty — a human built it by hand.
**"Other (see notes)"** means there is note text that matches no known tool; the detail pane shows the
raw JSON so you can read it and, if it's a pattern worth having, add it to `CreationMethodRules`.
**Lifecycle "Not recorded"** means the Notes field is empty altogether (4 apps).

## Created by

Graph does **not** expose who created an app. The only source is the Intune audit log, so on the first
sync the tool walks back through it (default 400 days, in 30-day chunks) and caches the result in
`Data\AuditCache.json`. It saves after every chunk, so throttling or cancelling never loses collected
work; later syncs only fetch what's new.

Honest limits: **apps created before the audit retention window can never have a creator** — that data
no longer exists. `Created via` works for all 801 and is the reliable answer to "where did this come
from". Both the UPN and the raw user ID are captured; the ID is in the detail pane and the export.

## Detail pane

Full record, the **raw Notes JSON**, **version history** (real transitions only) and **modification
history** (dated note events + audit entries + our own snapshot diffs, newest first). When a section is
empty it says why, rather than showing a blank.

## Excel export

`Export to Excel` writes what the filters currently show, as three sheets: **Apps** (31 columns),
**Version history**, **Modification history**. Autofilter on, numbers as real numbers. Hand-written
OOXML — no Excel needed to produce it, no ImportExcel, no Python.

## Self-test

```
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\IntuneApps.ps1 -SelfTest
```

Builds the real window offscreen and exercises columns, every filter dropdown, single-row filtering,
combined filters, the detail pane, search and the Excel export against the last snapshot. Use it after
any edit.

## settings.json

| Key | Meaning |
|---|---|
| `TenantId` | Tenant domain or GUID. |
| `ModulePath` | Folder holding `MSAL.PS` + `IntuneWin32App` (Package Builder's `lib`). |
| `DataPath` | Blank = `.\Data`. |
| `FetchCreators` / `CreatorBackfillDays` | Audit-log creator lookup, and how far back the first run walks. |
| `TestPatterns` / `UpdPatterns` / `WingetVersionValues` | Matched against the FIRST or LAST name token only, so "Attestation Client" is never a test app. |
| `CreationMethodRules` | Ordered `{ Method, Pattern }` matched against the inner note text. |
| `LifecycleRules` | Fallback only, for the few apps whose Notes are free text. |

## Notes

- Sign-in is interactive, so this **cannot run unattended**. Unattended would need an Entra app
  registration with `DeviceManagementApps.Read.All` + `Group.Read.All`.
- `installSummary` returns HTTP 400 for every app in this tenant, so install counts are not collected.
- The window opens at 1200×700 and clamps to your desktop work area.
