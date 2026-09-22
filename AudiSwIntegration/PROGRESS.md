# Progress — Audi SCCM Integration Tool

Running record of what is built, what is pending, and every decision taken so
far. Update this at the end of each working session.

**Last updated: 16.09.2026** — window v2 (see *Window v2* below): five pages on a navigation rail, dark by default with a remembered light toggle, a proper **Members** page, a typed-confirmation **Remove** page. Rules changed on Audi's word (15./16.09.2026): **detection is the branding key only** (SoftIdent removed everywhere, engine to schema to tests); **the install title comes from the script** (`InstallTitle`), never composed; **the environment is the packager's explicit choice** — an `INA_` package goes to ICZ first and INA after, so the prefix decides nothing and preflight only reports it; **underscore in SCCM, hyphen in the branding key**; **one collector task per environment**; **every Word file read in priority order** with a second **documents location** for forms kept apart from packages; **no dry-run switch in the window**. Only ICZ and INA are offered until PCZ is confirmed. **Middle server / mail man** added 16.09.2026: two drop folder roots, `Relay-AudiSwDropFolder.ps1` between them, package content travels in `Sources\` and the SCCM server copies it into the store as the first step - the window never touches the store. 690 tests passing. Everything buildable without Audi's accounts is done.

---

## Where we are

| Increment | State |
|---|---|
| 1. Configuration foundation | **Done** |
| 2. SCCM engine (12 operations, preflight, retry, audit) | **Done** |
| 3. Active Directory group via ARS/SPML | **Done** — written, not yet run against a real directory |
| 4. Packager window | **Done, v2** — rail with Integrate / Modify / Members / Remove / Jobs; header carries package, RFC, environment; dark and light |
| 4b. Modify (reconcile an existing application) | **Done** — adds what is missing, retires what the environment file no longer asks for, updates what changed |
| 4c. German display name and description in SCCM | **Written**, via SDMPackageXML like the old tool. Not yet run against a site |
| 5. Flow 2 — drop folder | **Done**, engine and window both |
| 6. Flow 1 — live connection | **Dropped.** Its scripts were not carried into this repository |
| 7. Flow 3 — shared repository | Designed and drawn, **not built** |
| 8. ICZ proving run | **Blocked** — needs the account, the rights and the drop folder |
| 9. INA and PCZ rollout | Not started |

**Tests: 826 passing** — 46 client, 263 config, 257 engine, 260 transport (including the packagers' Record file staying on their side, the store delete from a non-filesystem drive, the status files the packager reads, the content step surviving a failed site step, the exact-name lookup against a fake `Get-CMApplication`, the free-space guard, size-aware Sources retention, the drop-folder housekeeping, the incremental content update by size + SHA-256 with timestamps untouched, Find → tick → targeted removal, the content-folder guard, content refresh, the wildcard refusals, the Run again / Clean up advice, the relay round trip with the real scripts, the multi-worker race, the settings files, ten crafted job files against the schema, and a job the server died on). None need SCCM. `Start-AudiSwClient.ps1 -SelfTest` drives the window's own code without a screen.

```powershell
.\Tests\Invoke-AllTests.ps1
```

---

## Decisions taken (do not re-litigate)

| Decision | Why |
|---|---|
| One tool, one build; environments only in XML | Adding an environment must never mean a code change |
| One shared account **per environment** | ICZ, INA and PCZ are separate AD domains — a single central account is impossible |
| gMSA preferred, ordinary service account as plan B | No password anyone holds; it also has real credentials so onward hops work |
| **Flow 2 (drop folder) only** | Audi's decision, 01.08.2026. Matches their barrier drawing; needs no firewall change |
| The server never works out who wrote a job | It does not read the file's owner and the file cannot name anyone: `<Job>` has no requester attribute, so a file carrying one is rejected by the schema |
| **No person recorded anywhere on the SCCM side** | Audi's requirement, 01.08.2026 — not on an SCCM object, and not in the server's log, job record or result file. They do not want packagers appearing as making changes on the server |
| **The RFC is the audit link** | Follows from the above. It is written to every object; Audi's change system holds RFC → person. `requireRfc="true"`, so an untraceable change is refused |
| The plan has no Requester field | Structural, not a filter: if nothing holds a person, nothing can log one |
| Every action goes through the drop folder; every job is REAL | No dry-run switch in the window (Audi, 15.09.2026). `-DryRun` on the command line is for testing only and shows TEST MODE in the header. The window carries no SCCM code at all |
| **Detection = the branding key, nothing else** | Audi, 15.09.2026. A second rule on the vendor's uninstall key reads an installed package as missing when that key moves between builds. SoftIdent is gone from engine, config, schema, job file and window |
| **Install title read from the script** | Audi, 15.09.2026. `InstallTitle` (v4) / `$installTitle` or friendly name (v3) is what Software Center shows; it is never composed from the package name |
| **Environment is the packager's explicit choice** | Audi, 15.09.2026. The same `INA_` package goes to ICZ (test) then INA (production); the prefix says who it is for, not where this job goes. Nothing is preselected; only ICZ and INA are offered (`ClientEnvironments` in Defaults.xml) until PCZ is confirmed |
| **Underscore in SCCM, hyphen in the branding key** | Audi, 15.09.2026. Folder may be `..._2.16.58-0001_test`; application, deployment type, collections, AD group and the content folder are `..._2.16.58_0001_test` (`sccmNameFormat`); the branding key stays `..._2.16.58-0001_test` because the script writes it so. The window shows the SCCM spelling in the header as soon as a folder is read |
| **One collector task per environment, pointed at `<root>\<ENV>`** | Each server watches its own folder and cannot pick up another environment's jobs. Pointed at the root it serves every folder underneath (single test PC). A `<root>\<ENV>` that the window has not created yet is "nothing to collect", never an error. "Nothing to collect" lists the folders it looked in |
| **Every Word file is read, in priority order** | `Software Integration` form first, then `Install…` document, then anything else (`<NamePattern>` in Defaults.xml; among equals .docx over .doc, then newest). Each field comes from the FIRST file that has it, so the install document fills what the form left blank. Two generations of headings: "Short description…" and v4.1 "Description of the product in…" (short sentence = first line). The status line after Read details is one sentence; files read, spelling note and form extras are on its tooltip |
| **Two places for the request form** | The package folder first (script + `Documents\`, as today). When it holds no *Software Integration* form, the **documents location** (`DocumentsRoot` in `Client\Settings.txt` as the team default, editable and remembered per packager in the window): one folder per request, `<AES-ID> <Vendor> <App> <Version>\Documentation\…`, found by the AES ID from `VWG_OrderNumber`, else by product + version in the folder name (vendor optional, preferred when present; reported as a name match). Only the form comes from there; the package's own install documents still count after it |
| **A middle server carries the drop folder across — the "mail man"** | Audi, 16.09.2026 (drawing). The packagers' zone and the SCCM zone never see each other; one middle server can open both. Two drop folder roots with the SAME layout (`<root>\<ENV>\New|Working|Done|Failed|Sources`): the window writes to the client-side root exactly as before, the collector reads the server-side root exactly as before, and `Server\Relay-AudiSwDropFolder.ps1` (scheduled task on the middle server, `Install-AudiSwRelay.ps1`, every 2 min) carries Sources first, then jobs, out; heartbeats and results back. A carried job's client copy moves to client `Working\` as the "in transit" marker, so the window still shows it pending and one-job-per-package still holds. Every copy staged as `~name.relaying` and renamed. The relay reads nothing inside the files and needs only Modify on both roots |
| **"All transfers between the zones are handled in the middle zone"** | Audi's own words, 16.09.2026 (third round - final). Two drop folders, packager zone and SCCM zone; the relay task on the middle server is the ONLY thing that crosses a zone, in both directions (pulls from the packager share, pushes into the SCCM-zone share, carries status back). The SCCM watcher never leaves its zone; it copies `Sources` → store inside the zone. Only the gMSA writes into the store; the middle server has no store access. Offered and declined on the way: the "mailbox" (one share on the middle server, SCCM reaches out) and the middle server writing the store directly. **Workers:** `Install-AudiSwDropWatcher.ps1 -Workers N` (1-8) registers N staggered tasks on one folder; safe because claims are atomic moves and an older job never yields to a newer duplicate held by another worker (`Submitted -lt CreationTime`) |
| **Client's three points, 17.09.2026: drop folder ON the SCCM server, one transfer task each way, error handling after SCCM starts, input validation ("Exploits of a Mom")** | Shape: exactly the relay with `ServerRoot` = a folder on the SCCM server; the middle server keeps nothing (only `~` staging on the destination side). **Error handling** (DEPLOYMENT 3.3b): rollback on Integrate, stop-and-report on Modify, staged store copy, retry on provider errors, and NEW `StaleJobMinutes` (240): a job in `Working\` with no heartbeat movement is closed as FAILED with the last reported step and "check the site before submitting again" - never re-run automatically. **Input validation** (DEPLOYMENT 3.3c): `Environment.xsd` simpleTypes PackageName `[A-Za-z0-9._+-]`, Identifier, OptionalIdentifier (RFC), HostName, CollectionName, NamePart, DisplayName (256, no control chars), DisplayText (2048) applied to every Job attribute; watcher also refuses a file whose package name is not the folder it sits in. Nothing is ever string-built into a query or command - values are cmdlet parameters and Join-Path only |
| **Failed jobs: automatic only inside the drop folder; anything on the site needs a confirmation that names every object** | Audi, 18.09.2026 (Ewald's wildcard case). The watcher closes a job the server died on as FAILED and does NOTHING on the site; the Jobs page offers **Run again** (archived job file re-submitted with `retried`+1 after a prompt listing action/collections/machines/settings - Modify/Change/Remove are idempotent, member Remove now tolerates "already out") and **Clean up** (Integrate that created its application → Remove page, typed name). `Format-PlanEffect` makes the Integrate/Update/Remove prompt list application, deployment type, every collection with its deployment action, scopes, content path and what is NOT touched; Apply changes = one prompt with creates/removes/settings before→after; Remove page lists the exact objects. Server: `Assert-AudiExactName` + `Get-AudiCmObjectExact` - no ConfigMgr -Name wildcard ever reaches a remove; removals go by -InputObject after a whole-string, case-sensitive match; `Split-AudiPackageName` refuses `* ? [ ] \ / : " < > |`, spaces and `..`. Content copy by the SCCM server's local task confirmed by Audi ("everything is local, more reliable") |
| **Find → tick → remove; content deletion as its own question; Update content; verified copies** | Audi, 18.09.2026 (second round). New actions `Find` (pattern search, the ONE place a wildcard means a wildcard; result carries `Found` apps with collections + content path), `Remove` with `<Targets>` (exact names ticked; server `Invoke-AudiSwTargetRemoval` matches each whole, literal wildcard names looked up by enumerating and filtering, never via -Name), `RefreshContent` (client copies Sources with `-Replace`; on the SCCM side `Sync-AudiPackageContent` compares Sources with the store FILE BY FILE by size + SHA-256 — NEVER by timestamp, the user's rule: timestamps differ between machines and the tool must never rewrite one — replaces/adds/removes only what differs via `~.syncing` temp + move, keeps the Sources timestamp on replaced files, verifies the whole tree; then `Invoke-AudiSwContentRefresh` → `Update-CMDistributionPoint`; a package not yet in the store gets the full copy). Job attribute `removeContent`: the Remove page's tick + a SECOND prompt with the exact folder; server `Remove-AudiPackageContent` deletes only a folder directly under the env's store, literal path, after SCCM let go. Relay copies with **robocopy** straight share→share (staging on the destination, nothing on the middle server) and **verifies file count + bytes**; store copy verified the same way before rename. Run again prompt shows *done in the earlier attempt* vs *still to do* (`Get-RunAgainPreview`). `New-AudiSiteOnlyPlan` for jobs not about one package |
| **Sources cleared the moment the store holds a verified copy; size-aware retention; free-space guard** | User, 18.09.2026 ("not overloading the SCCM server"). Sources are a duplicate once the store has them, so they go at the end of the job whatever its outcome - a retry runs from the store ("Already in the store"), never needs a new copy from the packager. Kept only when the content step failed/never ran, or under dry run. Orphan Sources: 14 days, or `LargeSourcesRetentionDays`=2 when ≥ `LargeSourcesGB`=8. `Get-AudiFreeSpace` (GetDiskFreeSpaceEx, UNC-capable) + `Assert-AudiEnoughSpace` (2 GB margin) before the store copy; the relay checks the SCCM-side volume the same way and leaves the package on the packager side. XML footprint measured: job ≈1 KB, result ≈3 KB, Inspect ≈7 KB |
| **Drop-folder housekeeping on the SCCM side; re-copy is the workaround for a bad content copy** | User, 18.09.2026. The permanent record is the server log under ProgramData; the drop folder is tidied by the watcher every pass per `Watcher-Settings.txt`: Done → `Archive\<yyyy-MM>\<pkg>\` after 90 days, Failed after 180, Archive months deleted after 365, a `Sources\<pkg>` with no pending job deleted after 14 days (0 = keep). Sources otherwise removed on success, kept on failure. A bad copy is fixed by *Copy now* (offers "copy again, replacing") or Integrate again; the relay always replaces an existing SCCM-side Sources with the newer, verified copy. The packager side is theirs to keep or clean |
| **One folder per machine (18.09.2026)** | User: "differentiate files to 3 folders so I can use them on all 3 machines" and "relay is not a nice ring". `Client\` → `Packager\`; `Server\Engine` + watcher + `Watcher-Settings.txt` → `SccmServer\`; the relay → `MiddleServer\Sync-AudiSwDropFolders.ps1` + `Install-AudiSwDropFolderSync.ps1` + `Sync-Settings.txt` (task "Audi SW Integration - drop folder sync", install folder `DropFolderSync`); `Sync-AudiSwClient.ps1` → `Update-PackagerLib.ps1`. Older rows below still say Client/Server/relay - read them as Packager/SccmServer/sync task. DEPLOYMENT §0 is the copy-this-folder table |
| **Packager side never builds the server plan (18.09.2026 bug)** | Integrate threw "property Collections not found": the confirmation text was built from the full server plan, which a packager PC cannot build - it has no environment files. `Format-PlanEffect` now uses only what the packager side knows (SCCM name, deployment-type suffix and category from Defaults.xml, branding key, the collections the last Read from SCCM returned; otherwise "every collection the <ENV> environment file asks for, named in the result"). The Remove page's object list likewise. The self-test now renders all three prompts, so this cannot come back. Also: *Update files* → **Update content** (files + redistribute, what the name says); the Integrate page's *Update* (reconcile) button is gone - details/collections/machines of an existing application belong to the Modify and Members pages |
| **One confirmation window for every action (18.09.2026, "the prompt is too clumsy")** | `Show-Confirm`: a themed window with an accent bar, a headline ("Integrate X into INA"), one quiet lead sentence, THIS WILL as label/value rows (mono for names and paths), NOT TOUCHED as a short list, the question, and Cancel / *verb* (red for removals). Used by Integrate, Update content, Remove, Delete the files, Apply (collections + settings), Apply (machines), Remove ticked, Run again, Copy now / Copy again, Remove all. `Get-PlanEffect` gives the structured effect; `Format-PlanEffect` is only its text form for the self-test. Under `-SelfTest` the window is recorded and answered No; the self-test raises the Integrate click and checks the window titled *Integrate* appears - on the source tree AND on a packager-only install (hand-filled form) |
| **The packager is never blind (18.09.2026)** | Every sync pass writes `<packager root>\sync-status.txt` (`iso-time\|host\|OK/FAILED\|message`, also written when the SCCM side cannot be reached); every watcher pass writes `<ENV>\watcher-status.txt` in the SCCM-side folder and the sync carries it back. The Jobs page shows both under CONNECTION with a dot: green = OK, amber = no pass for 10 min ("the middle server may be down"), red = FAILED with the reason. Sync and watcher both clear a stale session (error 1219, `net use /delete`) and, when a PERSON runs them at a console, ask for a sign-in up to 3 times (`Get-Credential` + `New-PSDrive -Credential`); a scheduled task says plainly that its account needs MODIFY on the share |
| **The content step survives a failed site step (18.09.2026 bug: "Count not found", files copied but nothing recorded)** | Two fixes. Server: `Get-AudiCmObjectExact` collapsed an empty `switch` to `$null` (`$found = @(switch …)` now) - that was the "Die Eigenschaft Count wurde nicht gefunden" in preflight. Watcher: when the engine THROWS (as preflight does) the catch built a result with no steps, so the Content copy that had already put the files in the store was lost and Sources were not cleared. The content step is now put in front of the result AFTER the try/catch, Sources are cleared whenever the store holds a verified copy whatever the outcome, and the failure message says "The package files ARE in the store; Run again continues from there". Packager side: `Get-StoreContentRecord` reads the newest real result with a successful content step (cancelled by a later "Content folder: deleted"), so the Package content row says "in the SCCM store since …", Integrate copies nothing again (its confirm says so), and only Update content sends files |
| **Nothing says "check the console"; no job id on the page; who-did-it stays on the packagers' side (19.09.2026)** | User: nobody can open the SCCM console, so no message may send them there (Preflight's unreadable-distribution note and the category note reworded; result messages state facts and what the tool does next). Job ids are record keys, not reading matter: gone from the Jobs headline, the pending line, the status bar, the "already in progress" box and the all-runs list; they stay on the history hover text. **Record:** `Write-AudiSwPackagerRecord` (called by `Submit-AudiSwJob`) appends `time\|account\|machine\|env\|package\|action\|RFC\|job id` to `<packager root>\Record\<yyyy-MM>.txt`. That folder has no `New\`, so the sync never carries it; the job file still has no requester and the SCCM side still holds no person. Best effort - a record that cannot be written never stops a job |
| **Content-folder delete died with "Der Objektverweis wurde nicht auf eine Objektinstanz festgelegt" (19.09.2026, user's Remove with delete-the-files)** | Not a refusal: the engine leaves the session on the CMSite drive and the watcher ran `Test-Path`/`Remove-Item` on the UNC store path from there. Watcher now calls `Restore-AudiFileSystemLocation` right after the engine and again after the catch (before Sources is touched); `Remove-AudiPackageContent` uses `[IO.Directory]::Exists/Delete` (provider-independent), clears read-only attributes first and verifies the folder is gone |
| **Design pass (18.09.2026): layman-first pages** | Each page opens with one sentence + a numbered next-step strip (`Update-NextStep` lights the current step on Integrate); rarely-needed rows behind a `Disclosure` toggle (Integrate: documents location + files-go-to; Remove: delete-the-files + Find); plain verbs on buttons (*Integrate / Update / Update files / Remove / Find / Run again*), technical words in tooltips only; first-run status line says the three things to do. Disclosures open by themselves when they matter (no form found, Find results, Clean up) |
| **Every path in a settings file beside the script that uses it** | Audi, 16.09.2026. `Client\Settings.txt` (DropFolder, DocumentsRoot), `Server\Watcher-Settings.txt` (DropFolder, EngineRoot, MaxJobsPerRun), `Server\Relay-Settings.txt` (ClientRoot, ServerRoot, EnvironmentCode) - same `key = value` shape. The installers write the file into the install folder and register tasks with NO path on the command line; a command-line parameter still wins over the file. Changing a path = editing the file, never a re-install |
| **The package content travels with the job, via `Sources\`** | Audi, 16.09.2026. Before Integrate/Update the window checks `<root>\<ENV>\Sources\<SCCM name>`; if absent it copies the package there first (Content\ only for a `Content\ Documents\ Icons\` package, the folder as is when the script is at the top; no script = refused; staged as `~name.copying`, renamed at the end). **The window never reaches the SCCM store** — the collector copies Sources into `Content/@share` as the job's FIRST step ("Content copy"), skips it when the package is already in the store, refuses a real Integrate that has neither, and deletes Sources once the job succeeded (a dry run leaves it). Packagers need no store rights; `contentShare` is gone from `<ClientEnvironments>` |
| **Every share asks for a sign-in when it cannot be opened** | Drop folder, documents location, a package on a share: `Connect-AudiShare` tests, then prompts for user name + password (themed dialog), connects with `New-PSDrive -Credential` (no password on any command line), clears a stale session on the same server (error 1219) and retries, gives up after 3 with the reason; the next click asks again |
| **One job per package at a time** | Audi, 16.09.2026. The window refuses a submission while a job for that package is queued (`\New`) or running (`\Working`) — dialog names the job, the Jobs page shows it (a queued job now shows as QUEUED before its heartbeat exists). The collector refuses a duplicate that got past that: per pass the oldest job per package runs, later ones go to `\Failed` with "Refused as a duplicate: job X … was still queued/running"; a job being run by another collector instance blocks the same way. `Get-AudiSwPendingJob` in Transport.ps1 |
| **The Package content row on the Integrate page** | Shows `<root>\<ENV>\Sources\<SCCM name>` and whether the package is there (passive - never prompts); *Copy now* copies on its own; a copy made during Integrate appears as the first step "Content copy" on the Jobs page, before the server's own steps |
| **One settings file per install, one per packager** | `Client\Settings.txt` (DropFolder, DocumentsRoot) for the team; `%LOCALAPPDATA%\AudiSwIntegration\settings.txt` for what a packager changed in the window (DocumentsRoot, Theme). Same `key = value` shape; the packager's wins |
| Members have their own page and their own Apply | Machines are the one change that reaches real computers; they are confirmed by name and never mixed into a collection change |
| Remove sits behind a typed confirmation | The package name must be typed back before the button is live |
| Deployments declared on the collection | Kills the old tool's index-pairing bug |
| Package names parsed positionally, never string-replaced | `ADO_ADOBE_Reader` must not become `INA_INABE_Reader` |
| Job and result files are **XML**, not JSON | Consistent with everything else, and with Audi's own `[package].xml` |
| Parsing rules live in `Defaults.xml` | A naming or template change is a config edit |
| SCCM calls sit behind a provider | Gives a real dry-run preview and makes the engine testable without SCCM |
| Modify reconciles, never rebuilds | The application object is never replaced, so live deployments and the machines in its collections are undisturbed |
| Modify is not rolled back | Half-undoing a change to an application that is already deployed is worse than stopping and reporting |
| Retiring only ever touches this package's own collections | A hand-made collection can never be caught by it |
| Package names are never rewritten | The old tool rewrote the first three characters, which is what corrupted ADO_ADOBE_ into INA_INABE_. (The earlier "prefix must match the environment" refusal was dropped 15.09.2026 — see the environment decision above) |
| Config is read-only to the executor | The thing that executes must not rewrite the rules it runs under |

---

## Window v2 (15.09.2026)

Shape borrowed from the tools packagers already know — a sidebar of workflow
actions like the MECM App-Packager GUI, a pick-collection / paste-names /
confirm flow like the console's right-click *Add Devices to Collection* — and
the enterprise basics: context always visible, one primary action per page,
dark mode as the baseline.

| Page | What it does |
|---|---|
| **Integrate** | package folder (+ optional documents location) → Read details → correct → Integrate. Windows versions are visible tick boxes (from the form; become the OS requirement rule). *Update existing* re-applies the details to an application already on the site |
| **Modify** | Read from SCCM → settings in place, collections ticked → Apply changes. The page updates itself from the server's answer |
| **Members** | Read from SCCM → pick a collection → one list with three states (on site / will be added / will be removed) → *Remove selected*, *Keep selected*, *Remove all*, paste + *Add* → Apply. Confirmed by machine name; the list updates itself from the server's answer, no second read |
| **Remove** | what is removed, spelled out; the button is off until the package name is typed back |
| **Jobs** | current/last run, steps with OK / FAILED badges, *Show all runs* |

Header: package, RFC, environment. Rail foot: the theme toggle. Every colour
is a keyed brush; the script holds both palettes and `Test-Client.ps1` proves
they cover every key.

**Read from the v4.1 request form for information (WinMerge, 15.09.2026):**
predecessor package + "discontinued with this release", the SCCM sites ticked,
the software category. Shown on the status-line tooltip after Read details;
nothing acts on them yet - see *Proposed next* below.

**Proposed next, needs Audi's yes:**
1. *Sites → collections.* The form ticks IN1/NE1, GY1, SJ1, IN9, NE9 and leaves
   PI1/PN1, PG1, PJ1, PS1 unticked; the INA environment file creates a
   collection per site prefix. Carrying the ticked sites in the job (like the
   operating systems) would let the server create only the collections asked
   for, and preflight report any difference. Needs the prefix mapping confirmed
   (does "IN1/NE1" mean both `IN1-` and `NE1-`?).
2. *Category → SCCM administrative category.* Every application currently gets
   `Application/@category="Development"`; the form names "Learning &
   Collaboration". A mapping table in Defaults.xml from form category to SCCM
   category name would make it one edit - once the SCCM category names exist.
3. *Predecessor → Remove.* The window already names it; a "Remove predecessor"
   action after a successful Integrate (with its own typed confirmation) would
   close the loop the form describes.
4. *Provisioning category → ARS OU.* "Lizenzfrei" vs "Lizenzpflichtig" etc.
   maps to the AD group's OU once the ARS step is switched back on.

**Still open on the window:** `requireRfc` is `false` in `Defaults.xml` while
DEPLOYMENT.md and the decisions table say the RFC is mandatory — one of the two
has to give; the window and server both honour the switch, whichever way it
is set.

---

## Open questions for Audi — these block progress

1. **The drop folder path per environment.** The three environment files carry
   placeholders (`\\audiinsv1059.in.audi.vwg5t\SwIntegration-Inbox$` and the INA
   and PCZ equivalents). One share per environment, with the rights in
   `DEPLOYMENT.md` 3.1.
2. **PCZ settings.** Four values are copies of INA's and one was never set:
   security scope (`INA00003`), application folder (`INA-Applications`), content
   share, AD group OU (`DC=audi,DC=vwg`), and the ARS provider URL. `PCZ.xml` is
   marked `verified="false"` and a real run against it is refused.
3. **Accounts.** One gMSA and one operators group per environment. The names in
   the environment files are placeholders.
4. **A real GPF install instruction document**, so the `<Document>` patterns in
   `Defaults.xml` can be calibrated. Until then those fields stay blank.

---

## What is NOT yet proven

- **The live SCCM calls.** `New-AudiSccmProvider` wraps supported ConfigMgr
  commands but has never touched a real site. Everything testable today runs
  through the dry-run provider.
- **The ARS/SPML calls.** Written from their `Audi-ARSSPML-*` modules, never run
  against a real directory.
- **The scheduled task.** `Install-AudiSwDropWatcher.ps1` has never been run on a
  server. The collector logic itself *is* tested, via `Test-Transport.ps1`.

---

## Next steps, in order

1. Get the real drop folder paths and the PCZ confirmations (open questions 1, 2).
2. Raise the prerequisites in `DEPLOYMENT.md` section 4 — gMSA, operator group,
   SCCM rights, drop folder. Nothing else can start until these land.
3. Install on the ICZ server, register the collector task, run the acceptance
   test in `DEPLOYMENT.md` section 6.
4. Calibrate the instruction-document patterns against a real GPF document.
5. Roll out to INA, then PCZ.
6. Withdraw the packagers' personal SCCM administrator accounts. **This is the
   point of the project** and is the step most likely to be forgotten.

If flow 3 (shared repository) is ever revisited: point `Get-AudiConfigRoot` at the
repository share and split the config and job areas into two shares. Small change
— the engine, ordering and rollback are unaffected.

---

## Bugs found in the old tool (evidence for the client)

| Defect | Consequence |
|---|---|
| Step results discarded; status always `"Done."` | A failed step looks identical to a successful one |
| `.Replace(Substring(0,3),'INA')` | `ADO_ADOBE_Reader` silently becomes `INA_INABE_Reader` |
| `$global:Credential` always `$null` | Everything runs as the person clicking, despite code that accepts a credential |
| PCZ `$ARS_Provider` never assigned | Both AD steps stall on a hidden console prompt |
| PCZ carries INA's scope, folder, share and OU | Wrong-environment objects |
| Deployments paired to collections by list position | One removed deployment shifts all the rest |
| Flat `Start-Sleep 30` per deployment on the UI thread | Up to five minutes of a frozen window on PCZ |
| Shared `C:\temp\Logs` staging | Two operators overwrite each other's logs |

---

## Traps hit while building (all commented at the point of use)

- `@()` around a generic `List[object]` of PSObjects throws *"Argument types do
  not match"* in PowerShell 5.1 — use `.ToArray()`.
- `.GetNewClosure()` gives a scriptblock its own session state, so the tool's own
  functions become invisible to it once dot-sourced into a script scope, and it
  freezes captured variables at definition time. Plain scriptblocks keep the
  defining scope and stay live.
- `[int]($i / 5)` **rounds** in PowerShell rather than flooring — use
  `[math]::Floor`.
- An empty `<OperatingSystems/>` was rejected by the schema, which would have
  broken every job submitted without OS selections. `minOccurs="0"` fixed it.
- `$args` is automatic inside a script, so a runspace variable of that name is
  silently shadowed by the (empty) argument list. The window passes `$jobArgs`.
- `Wait-AudiSwJobResult` returns a hashtable and the engine returns a
  PSCustomObject; `.PSObject.Properties[...]` only works on the second. The window
  asks through `Test-HasValue` so StrictMode does not throw on the first.
- A function parameter called `$State` shadows the window's shared `$state`
  table for every helper it calls — variable names are case-insensitive.
- `$window.Resources[$key] = $brush` hands WPF a PSObject wrapper and throws
  *"Unable to cast PSObject to Brush"*; `Remove` then `Add` through the methods.
- The request form's text has `\r\n` line endings, so a regex ending in `$`
  after a literal must allow `[ \t\r]*$` — `.` swallows the `\r`, a literal
  alternation does not.
- **Never bulk-edit files through the shell tool with arrays of pairs.**
  `@(@('a','b'))` flattens to `@('a','b')`, so `$e[0]`/`$e[1]` become
  *characters* and every `w` in a file turns into `h`. Three files were lost
  that way on 16.09.2026 and rebuilt from git. Use the editor tool.
- `Get-Content -Raw` without `-Encoding UTF8` reads a BOM-less UTF-8 file as
  ANSI, and `Set-Content -Encoding UTF8` then writes the mis-read characters
  back as mojibake (`—` becomes `â€”`). Undo: re-encode the text as 1252 bytes
  and decode as UTF-8. Better: do not touch these files through the shell.

---

## Deliverables and where they are

| What | Where |
|---|---|
| Code, config, client, tests | `Application-Packaging\AudiSwIntegration\` (this repository) |
| Deployment detail (accounts, permissions, drop folder, privacy, security Q&A) | `DEPLOYMENT.md` |
| Structure and commands | `README.md` |
| Three flow diagrams (SVG + PNG) | `C:\temp\Audi-SCCM-Integration\Flows\` — **flow 2 is the one being built** |
| Client design deck | `C:\temp\Audi-SCCM-Integration\...Design and Requirements.pptx` |
| Blueprint deck (earlier, plainer) | `C:\temp\Audi-SCCM-Integration\...Blueprint.pptx` |

Reference copy of the tool being replaced was `C:\temp\EQS-PoshGUI-Tool-1.0.3`
(no longer on this machine).
