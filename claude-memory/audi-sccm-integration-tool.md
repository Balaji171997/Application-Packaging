---
name: audi-sccm-integration-tool
description: New Audi client project - rewrite their SCCM integration tool to run under a shared service account; transport DECIDED = flow 2 drop folder only (not JEA/WinRM)
metadata: 
  node_type: memory
  type: project
  originSessionId: fd7b3460-9b55-454d-8890-76d54ccc8d20
  modified: 2026-09-19T01:46:21.892Z
---

New brand client (Audi) engagement started 2026-07-30, separate from the MTB and GPF
Package Builder variants ([[gpf-brand-variant]], [[multi-team-brand-variants]]).

**Their existing tool** (reference only, not a codebase to inherit):
`C:\temp\EQS-PoshGUI-Tool-1.0.3` — "Audi SW Integration Tool 1.0.3" by Andras Galambos
(AHA/FP-13). WPF GUI + 15 PowerShell modules. 12 operations (8 integration + 4 removal)
across 3 MECM environments: **ICZ** (test), **INA** (prod), **PCZ** (prod). The "Runbook"
naming is dead Orchestrator ceremony from before the MCB shutdown — everything runs locally
in-process.

**The requirement:** all SCCM work must run under, and be recorded as, one shared
system/service account instead of each packager's personal MECM admin account. The packager
only operates the tool.

**Decisions the user made (2026-07-30):**
- Deliverable = **SCCM integration module only** — not an Audi brand variant of Package Builder.
- **Rewrite** the engine using Package Builder patterns; their script is a requirements reference.
- **Desktop WPF now**, web-based front end presented as the phase-2 roadmap (user liked web but
  wants desktop first).
- XML holds **SCCM/environment config only** — one XML per environment so a new environment is a
  file, never a code change. This was the user's own idea and should be preserved.
- The user is **not deep in AD/SCCM** — explain identity/infrastructure options in plain language,
  no jargon (JEA/gMSA/double-hop/Kerberos land badly).

**TRANSPORT DECIDED 2026-08-01 — flow 2 (drop folder) ONLY.** The user said twice: *"flow 2
only ..first flow we ar enot following"*. Do not re-propose the live-connection / WinRM / JEA
endpoint. Its scripts are parked at `Server\_NotUsed-LiveConnection\`, not deleted.

How flow 2 works: the packager window writes a job XML into `<share>\New`, a scheduled task on
the SCCM server (running as the gMSA) claims it by moving it to `\Working`, runs it, and writes
`<job>.result.xml` into `\Done` or `\Failed`; the window polls for that file. **No firewall
change, no open port, nothing connects inward** — which is why it matches Audi's own barrier
drawing. gMSA is still the account of choice (not a JEA virtual account) because the task must
reach the content-store UNC and the ARS/SPML SOAP endpoint. Plan B if AD refuses: an ordinary
service account stored once in Task Scheduler on that one server.

**PRIVACY RULE DECIDED 2026-08-01 — no real person is recorded ANYWHERE on the SCCM side.**
User: *"dont keept real person name on sccm server logs. only integrator has that info"* /
*"they dont want to see real person doing any changes in SCCm side ..they dont want to involve
real person as well into the server"*. This is stronger than "not on SCCM objects": it covers the
tool's own log, `job.json` and the result file on the server too.

So there is now **one identity only** — the gMSA, in the SCCM `Owner` field. The plan object has
**no `Requester` field at all** (structural, so nothing can log one), `Get-AudiIntegrationPlan`
has no `-Requester` parameter, and the collector no longer reads the job file's NTFS owner.
**The RFC number is the audit link**: written to every SCCM object, and Audi's change system
holds RFC → person. `Audit/@requireRfc="true"` in Defaults.xml, so a job with no RFC is refused
by both the window and the server — otherwise a change would be untraceable.
Also: the collector **re-writes** the archived job file as the service account and deletes the
packager's original, so no person-owned file is left in the secure zone.
`<Job>` in the XSD still has no requester attribute, so a file carrying one is rejected outright.

**Tool:** now IN THE REPO at `Application-Packaging\AudiSwIntegration\` (moved from Downloads
~12 Sep 2026) — `Server\` (engine + config + collector), `Client\` (WPF window + Lib/Config
copies kept in step by `Sync-AudiSwClient.ps1`), `Tests\` (551 checks, none need SCCM). The
parked `_NotUsed-LiveConnection` scripts were NOT carried into the repo. **Integrate/Modify/
Remove** go through the drop folder; Dry run (on by default) rehearses without SCCM.
`PROGRESS.md` in that folder is the running record — read it first when resuming.

**Readiness (15 Sep 2026):** everything buildable without Audi is done and green (551 tests +
`-SelfTest`). Blocked ONLY on Audi: gMSA + operator group per env, SCCM/share/ARS rights, real
drop-folder UNC per env, PCZ values (`verified="false"`), a real GPF instruction doc for pattern
calibration. Live ConfigMgr/ARS calls and the scheduled task have never run against a site.

**Window v2, 15 Sep 2026 (user: "complete makeover, dark mode, don't cramp members"):** nav rail
with 5 pages (Integrate / Modify / Members / Remove / Jobs, tabs `tabIntegrate..tabJobs`,
radios `navIntegrate..navJobs`), header = package + RFC + environment, dry-run pill + theme
toggle at rail foot. DARK BY DEFAULT; both palettes live in the script (`$script:Palettes`),
every XAML colour is a `{DynamicResource}` keyed brush, swap via `Resources.Remove/Add` (the
indexer throws "Unable to cast PSObject to Brush"). Theme remembered in
`%LOCALAPPDATA%\AudiSwIntegration\client.theme`. Remove is gated by typing the package name.
Render-check XAML with XamlReader + RenderTargetBitmap (give the root Grid a Background or the
capture is transparent). XML comments must not contain `--`.

**Three rules Audi changed 15 Sep 2026 — don't reintroduce:**
- Detection = BRANDING KEY ONLY. SoftIdent removed from engine/Defaults.xml/XSD/job file/window/tests.
- Install title comes from the script (`InstallTitle`, v3 `$installTitle`/friendly name) → the
  "Install title (EN/DE)" fields; never composed "Publisher - Product - Version".
- Environment is the packager's EXPLICIT choice; the package prefix decides NOTHING (an `INA_`
  package goes to ICZ then INA). Preflight `SitePrefix` only reports. Offered list =
  `<ClientEnvironments>` in Defaults.xml = ICZ + INA only until PCZ is confirmed. Nothing preselected.
- Description format confirmed correct: "The following applications will be closed for
  installation: a,b. " + SHORT description when the script closes processes; short description
  alone otherwise (tested end-to-end through Read-AudiPackageDetail).
- The executor in result files is the live Windows identity (AW140 when run here) — user said
  that's fine because on the server it is the gMSA; don't change it.
- OPEN: `Audit/@requireRfc="false"` in Defaults.xml contradicts docs saying RFC mandatory.

**Later on 15 Sep 2026 (real package `C:\temp\INA_WinMerge_WinMerge_x64_2.16.58-0001_test`):**
- NAMING RULE: SCCM objects + content folder = underscore before revision
  (`..._2.16.58_0001_test`, `sccmNameFormat` in Defaults.xml, `Get-AudiSccmName`); browsed
  folder may be hyphen; branding key keeps hyphen. Window header shows SCCM spelling.
- COLLECTOR: one scheduled task per environment pointed at `<root>\<ENV>` is the NORMAL
  production shape (user insisted); root also works. The "nothing to collect" the user saw
  was the collector pointed at `<root>\INA` before that mode existed.
- REQUEST FORM v4.1 "…_Software Integration Level 3_request_(1).docx": chosen by
  `<NamePattern>` (Software Integration → request); headings "Description of the product in
  English/German" (no "Short"), short sentence = first line. Also reads PredecessorPackage,
  PredecessorDiscontinued, Site:* ticks, SoftwareCategory — info only on the status line.
  Regex tip: text has \r\n, so end anchors need `[ \t\r]*$`.
- Proposed (not built, needs Audi yes): sites→collections filter, form category→SCCM
  category, predecessor→Remove action, provisioning→ARS OU.
- DEMO polish (user): status line after Read details = ONE short sentence; everything else
  (files read, spelling note, predecessor/sites/category) on the tooltip. Reader now reads
  EVERY Word file in order Software Integration → Install → other, first file with a field
  wins (`Origin` = "document: <file>"). 620 tests green.
- 15 Sep later: NO dry-run switch in the window (every job real; `-DryRun` cmdline = TEST MODE
  badge, testing only). Members page = one list, states on site / will be added / will be
  removed + Remove selected / Keep selected / Remove all / Add / Discard; after Apply the list
  (and Modify page) update themselves from the result steps (Complete-MemberApply /
  Complete-ChangeApply) — no second Read. Collector: `<root>\<ENV>` missing but root reachable
  = "nothing to collect", never an error (the window creates the folder with the first job).
- 16 Sep: Windows versions = visible CheckBoxes (`pnlOperatingSystems`, built from Defaults
  OperatingSystems, ticked from the form, sent as the job's OperatingSystems; none ticked = refused).
  Reference tool `C:\temp\EQS-PoshGUI-Tool-1.0.3` is GONE from this machine — comparisons now
  rest on what was recorded in code comments/PROGRESS.
- 16 Sep: DOCUMENTS LOCATION (second root for request forms): `Read-AudiPackageDetail -DocumentRoot`
  + `Find-AudiDocumentFolder` (AES ID from VWG_OrderNumber first, else vendor+product+version fuzzy);
  used ONLY when the package has no Software Integration form. Window: `txtDocumentRoot` row in
  card 01, team default `Client\DocumentsRoot.txt`, per-user override in
  `%LOCALAPPDATA%\AudiSwIntegration\documents.root` (Save-DocumentRoot skips under -SelfTest).
- 16 Sep: ONE settings file `Client\Settings.txt` (DropFolder, DocumentsRoot; key = value) + per-user
  `%LOCALAPPDATA%\AudiSwIntegration\settings.txt` (DocumentsRoot, Theme). DropFolder.txt/DocumentsRoot.txt gone.
- 16 Sep: window copies the package via `Copy-AudiPackageContent` (`Get-AudiPackageContentRoot`:
  Content\ only for Content/Documents/Icons shape; flat = as is; staged `~name.copying`).
  `Connect-AudiShare` = themed credential dialog, New-PSDrive -Credential, 1219 stale-session
  clear, 3 attempts; used for drop folder, documents root, package path.
- 16 Sep: content copy is VISIBLE — Integrate page "Package content" row (txtContentTarget /
  txtContentState / btnCopyContent "Copy now", `Update-ContentState` passive, `Start-ContentCopy`),
  and "Content copy" as first Jobs step (`$state.CopyStep`). `Get-ContentCopyPlan` is the pre-check.
- **16 Sep — MIDDLE SERVER / "MAIL MAN" (user's drawing, confirmed):** packager zone and SCCM zone
  never see each other; a middle server can open both. TWO drop folder roots, SAME layout
  `<root>\<ENV>\New|Working|Done|Failed|Sources`. Window writes to the client root; the collector
  reads the server root; `Server\Relay-AudiSwDropFolder.ps1` (+ `Install-AudiSwRelay.ps1`, task every
  2 min, needs only Modify on both roots) carries Sources first then jobs out, heartbeats/results
  back; the carried job's client copy moves to client `Working\` as the in-transit marker (pending +
  one-job-per-package still hold). **The window NEVER touches the SCCM store**: content goes to
  `<root>\<ENV>\Sources\<SCCM name>` (client calls `Initialize-AudiDropFolder` first — Sources must
  exist before the job does); the collector copies Sources → `Content/@share` as the job's FIRST step
  "Content copy" (skips if already in store; refuses a real Integrate with neither; unverified env =
  no copy, engine refusal wins), deletes Sources after success (dry run keeps it). `contentShare`
  attr removed from ClientEnvironments/XSD. Test-Transport "Through the middle server" drives the
  real relay + collector. 690 tests green.
- **16 Sep FINAL topology (client's words: "all transfers between the zones must be handled in the
  middle zone")**: two drop folders (packager zone + SCCM zone); the relay task on the middle server is
  the ONLY thing crossing a zone, both directions; the SCCM watcher never leaves its zone and copies
  Sources → store itself; middle server has NO store access. Declined on the way: mailbox (SCCM
  reaching out to the middle share) and middle-writes-store. `-Workers N` (1-8) on the watcher
  installer = N staggered tasks; older job never yields to a newer duplicate held by another worker.
  ALL PATHS IN SETTINGS FILES beside each script (`Client\Settings.txt`, `Server\Watcher-Settings.txt`,
  `Server\Relay-Settings.txt`); tasks carry no path; CLI param wins over file. 698 tests. Client
  diagram artifact: https://claude.ai/artifact/K46ccxYbi9QYRUHwymyJLk
- **17 Sep — client's three points** (drop folder ON the SCCM server; tasks 2+3 and 6+7 combined = one
  transfer task each way on the middle server; error handling after SCCM starts; input validation, xkcd
  327): shape = relay with ServerRoot on the SCCM server, middle keeps nothing. Added `StaleJobMinutes`
  (240) stuck-job closure in the watcher (FAILED + last heartbeat step, never auto re-run); XSD
  simpleTypes PackageName/Identifier/HostName/CollectionName/NamePart/DisplayName/DisplayText on every
  Job attribute; watcher refuses name≠folder. DEPLOYMENT 3.3b (error table) + 3.3c (validation). 720
  tests. `\p{Cc}` works in .NET XSD patterns; XML attribute values normalise tab/newline to space, a
  `&#9;` char ref survives - use [char]9 to test control chars.
- **18 Sep — Audi's two rules for failed jobs / any site change:** (1) automatic actions only inside the
  drop folder; anything writing/deleting in SCCM or the store needs a confirmation; (2) every removal or
  modification must name EXACTLY what it does (Ewald: a wildcard in a package name could remove many).
  Built: watcher closes a died job as FAILED and touches nothing on the site; Jobs page **Run again**
  (re-submits archived job file, `retried`+1, idempotent Modify/Change/Remove) and **Clean up** (Integrate
  that created its app → Remove page, typed name); `Format-PlanEffect` = smart prompt listing every
  object by name + what is NOT touched; Apply changes one consolidated prompt; server
  `Assert-AudiExactName`/`Get-AudiCmObjectExact`, removals by -InputObject after exact match;
  `Split-AudiPackageName` refuses wildcard/path chars/spaces. Content copy stays with the SCCM server's
  local task (Audi: "everything is local, more reliable"). NEVER re-propose automatic rollback/re-run.
  731 tests. Client diagram artifact republish failed once (proxy) - retry from the same file.
- **18 Sep, round 2 (user):** Run again must show done vs remaining (`Get-RunAgainPreview`); Clean up /
  Remove must ASK separately about deleting the store folder (`removeContent` attr, `Remove-AudiPackageContent`
  guarded: directly under env store, literal path, after SCCM let go); "Update content" = `RefreshContent`
  action (replace store folder from Sources + `Update-CMDistributionPoint`); Ewald's literal-wildcard apps
  = `Find` action (pattern search → `Found` list) → tick → `Remove` with `<Targets>` exact names
  (`Invoke-AudiSwTargetRemoval`, literal names enumerated+filtered, never -Name). Middle server stores
  NOTHING even temporarily (staging on destination share); relay uses robocopy + file-count/bytes
  verification; store copy verified before rename. 773 tests. Client\Lib has no Steps.ps1 - step lists
  for previews are inline in the client.
- 18 Sep: UPDATE CONTENT is INCREMENTAL (`Sync-AudiPackageContent`): SCCM side compares Sources vs store
  by size + SHA-256, NEVER timestamps (user: timestamps differ between systems; the tool must never
  rewrite a content timestamp); only differing files replaced/added/removed; whole tree verified. 783
  tests. Client page v4 published with Run again/Clean up, four removal ways, incremental update.
  User's standing ask: tool must be "advanced, logical, flexible, layman-understandable, attractive
  design without too much info" - keep UI text short, one primary action per page.
- 18 Sep: design pass done (NextStep strip + `Disclosure` ToggleButton style + BoolToVis; rarely-needed
  rows hidden; plain verbs). Housekeeping in the watcher: Done→Archive\yyyy-MM after 90d, Failed 180d,
  Archive 365d, orphan Sources 14d (Watcher-Settings.txt; 0 = keep). Copy now offers "copy again,
  replacing"; relay replaces SCCM-side Sources with the newer verified copy. 792 tests. Render check:
  scratchpad Render2.ps1 -Tab tabX (static XAML only - script-driven text not shown).
- 18 Sep: Sources cleared once the store holds a verified copy regardless of job outcome (retry runs
  from the store - user worried about re-copying from the packager: not needed); LargeSourcesGB=8 →
  2-day retention; free-space guard (GetDiskFreeSpaceEx P/Invoke, 2 GB margin) in engine copy + relay.
  XML sizes: job 1 KB, result 3 KB, inspect 7 KB. 797 tests.
- **18 Sep LAYOUT: one folder per machine** - `Packager\` (was Client), `MiddleServer\`
  (`Sync-AudiSwDropFolders.ps1`, `Install-AudiSwDropFolderSync.ps1`, `Sync-Settings.txt`; task "Audi SW
  Integration - drop folder sync"; user disliked "relay"), `SccmServer\` (Engine, watcher,
  Watcher-Settings.txt). Dev helper `Update-PackagerLib.ps1` (was Sync-AudiSwClient.ps1). Moves staged
  in git (22 renames), not committed. Older memory lines saying Client/Server/relay = these.
- **RULE (bug 18 Sep): the packager side has NO environment files** - never call
  `Get-AudiIntegrationPlan` in client UI paths; `New-PlanFromForm` returns only PackageName/Environment/Rfc.
  `Format-PlanEffect` builds prompts from Defaults.xml + form + last SiteState. Self-test renders all prompts.
  Integrate page buttons now: *Update content* (files+redistribute) + *Integrate*; the reconcile "Update"
  button was removed (Modify/Members pages own existing apps). `DocumentsRoot` already in Packager\Settings.txt.
- 18 Sep round 2 of that bug: `$script:SiteState` read under StrictMode before any assignment → window died.
  All `$script:` vars now initialised at top level; Test-Client enforces "every $script: var has a
  top-level assignment". All dialogs go through `Show-Box (text,title,buttons,icon)` (array-arg wrapper;
  under -SelfTest records + answers No/OK) and every button through `Invoke-Guarded` (error → status +
  box, window stays up). Self-test now RAISES the Integrate click and proves the Confirm box is reached;
  also verified from a packager-only tree (Packager\ + Tests\New-AudiSwSamplePackage.ps1, no SccmServer).
  USER RULE: "everything has to work independently on its part and connect only via the data
  transferred" - never let the client depend on server-side files.
- **18 Sep round 3** ("prompt too clumsy" / "packager will be blind" / "Count" error): ONE themed
  `Show-Confirm` window (headline, lead, THIS WILL rows, NOT TOUCHED, question, Cancel/<verb>, red for
  removals; `Get-PlanEffect` = structured effect) for EVERY confirm - Integrate/Update/Remove/Delete the
  files/Apply/Members/Remove ticked/Run again/Copy. Under -SelfTest it records Title=verb (the click check
  looks for 'Integrate'); self-test raises the click on the source tree AND on a packager-only install
  (hand-filled form + minimal package). Status files: sync writes `<packager root>\sync-status.txt`
  (`iso|host|OK/FAILED|msg`, also on unreachable SCCM side), watcher writes `<ENV>\watcher-status.txt`,
  sync carries it back; Jobs page CONNECTION rows (`Update-ConnectionHealth`, amber >10 min, red FAILED).
  Sync + watcher clear 1219 and Get-Credential ×3 when interactive. Provider bug: `$found = @(switch
  ...)` (empty switch → $null → ".Count not found" in preflight). Watcher bug: engine THROW dropped the
  already-done Content copy step + skipped Sources clearing → content step now prepended after try/catch,
  Sources cleared whenever store verified, message "files ARE in the store". Client `Get-StoreContentRecord`
  reads history → "in the SCCM store since …", Integrate copies nothing again. Test-Client accepts script
  PARAMS as top-level `$script:` inits. 819 tests. Renders: scratchpad Render-Confirm.ps1 (extracts
  Show-Confirm via AST; paint `$d.Content.Background` before RenderTargetBitmap).
- **19 Sep (user: "good for now, leave Audi")**: NO message may say "check in the console" (nobody can open
  it); job IDs removed from every visible line (kept on history hover + record); WHO-DID-IT record =
  `Write-AudiSwPackagerRecord` in Transport (called by Submit-AudiSwJob) → `<packager root>\Record\yyyy-MM.txt`
  `time|account|machine|env|package|action|RFC|jobId` - sync never carries it (no New\ inside), SCCM side still
  nameless (result `executor` = service account by design; test checks job files only). Bug: content-folder
  delete threw "Objektverweis nicht … festgelegt" = watcher ran file cmdlets while session sat on the CMSite
  drive → `Restore-AudiFileSystemLocation` right after the engine + after the catch; `Remove-AudiPackageContent`
  now .NET Directory.Exists/Delete + clears read-only. 826 tests. AUDI PARKED here; next = GPF/PAG UI.
- Shell trap 16 Sep: `Get-Content -Raw` (no -Encoding) + `Set-Content -Encoding UTF8` turned every
  `—` in PROGRESS.md into `â€”`; undone by re-encoding 1252→UTF8. Edit docs with the Edit tool only.
- 16 Sep: ONE JOB PER PACKAGE — `Get-AudiSwPendingJob` (Transport; New=Queued, Working=Running; use
  GetAttribute not dotted access under StrictMode); window `Test-PackageJobPending` before any submit;
  collector decides duplicates over the whole queue up front (`$olderInQueue`) → Failed "Refused as a
  duplicate". Test-Transport's orphan job must be removed after the timeout test or it blocks later ones.
- Server UNC failure ("cannot be opened") = that PowerShell session can't open the share
  (elevated window / other account / cross-domain), not a layout issue; watcher now prints
  reason + account + elevation hint. Fix is on the access side.

**Deliverables:** `C:\temp\Audi-SCCM-Integration\` — plan markdown, three flow diagrams (SVG+PNG)
and a PPTX built from the user's "Package Builder.pptx" template ([[audi-ppt-template-facts]]).
