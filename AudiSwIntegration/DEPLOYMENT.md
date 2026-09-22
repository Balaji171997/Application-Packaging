# Deployment plan — Audi SCCM Integration Tool

Everything Audi has to provide, what we install, and what the security review will
ask about.

Repeat all of it **once per environment** (ICZ, INA, PCZ). The three environments
are separate AD domains, so nothing can be shared between them.

## 0. What goes on which machine

The repository has one folder per machine. Copy that folder, run its
installer, fill in its settings file - nothing from the other two folders is
needed there.

| Machine | Copy this folder | Then | Paths live in |
|---|---|---|---|
| **Packagers' share** (packager zone) | `Packager\` | give packagers a shortcut to `Start-AudiSwClient.ps1` | `Packager\Settings.txt` – DropFolder (packager-side root), DocumentsRoot |
| **Middle server** | `MiddleServer\` | `.\Install-AudiSwDropFolderSync.ps1 -Account … -ClientRoot … -ServerRoot …` | `Sync-Settings.txt` – ClientRoot (packager side), ServerRoot (SCCM side) |
| **SCCM server** (one per environment) | `SccmServer\` | `.\Install-AudiSwDropWatcher.ps1 -Gmsa … -DropFolder <sccm-side root>\<ENV>` | `Watcher-Settings.txt` – DropFolder, retention days |

`Tests\` and `Update-PackagerLib.ps1` stay with us and are never deployed.
Every installer accepts `-WhatIf` and prints what it would do.

---

## 1. How a job reaches the server — decided

**The drop folder, with the middle zone doing every transfer.** Audi's rule:
*all transfers between the zones are handled in the middle zone.* So there are
two drop folders with the same layout - one in the packagers' zone, one in the
SCCM zone - and the only thing that ever crosses a zone boundary is the task on
the middle server:

1. The packager window writes the job file - and the package content beside it -
   into the **packager-side drop folder** (a share the packagers already reach).
2. A scheduled task on the **middle server** pulls those files across and pushes
   them into the **SCCM-side drop folder** every couple of minutes, and carries
   status and results back the other way. It reaches both drop folders and
   nothing else - **not the SCCM server itself, not the store.**
3. A scheduled task on the **SCCM server** works only inside its own zone: it
   takes the job from the SCCM-side drop folder, copies the package from there
   into the content store itself, runs the job as the service account, and
   writes the status and the result back into the same folder.

```
packager's PC        packager-side drop folder     MIDDLE SERVER        SCCM-side drop folder       the SCCM server
┌───────────────┐    ┌───────────────────┐   ┌─────────────────┐   ┌───────────────────┐   ┌────────────────────┐
│ window        │ ─▶ │ \Sources\<pkg>    │   │ sync task       │   │ \Sources\<pkg>    │   │ watcher task       │
│ no SCCM rights│ ─▶ │ \New\<pkg>\job    │ ▶ │ pulls  ▶ pushes │ ▶ │ \New\<pkg>\job    │ ▶ │ takes job+package, │
│ no store      │    │ \Working          │   │                 │   │ \Working          │   │ copies package into│
│   rights      │ ◀─ │ \Done  \Failed    │ ◀ │ pushes ◀ pulls  │ ◀ │ \Done  \Failed    │ ◀ │ the store, runs it,│
└───────────────┘    └───────────────────┘   └─────────────────┘   └───────────────────┘   │ writes status back │
                      <root>\<ENV>\...        the ONLY thing that    <root>\<ENV>\...       └────────────────────┘
                                              crosses a zone                                 never leaves its zone
```

**Who opens what - and nothing else**

| Machine | Opens | Never opens |
|---|---|---|
| Packager PC | the packager-side drop folder | the middle server, the SCCM zone, the store |
| Middle server | both drop folders | the SCCM server itself, the store |
| SCCM server | the SCCM-side drop folder, the store (both in its own zone) | the middle server, the packager side |

**Nothing inside the SCCM zone connects outward, and nothing from the packager
zone connects inward.** Every transfer is the middle server's task, in both
directions. This matches Audi's own architecture drawing, where a barrier
separates the packaging zone from the SCCM zone and content is *copied across*
rather than reached through - the sync task is that copy, and it reads nothing
inside what it carries. The only account that ever writes into the content store
is the SCCM service account.

The trade-off, stated honestly: the packager gets a result a few minutes later
instead of watching the work happen live.

> The live-connection alternative (a WinRM/JEA endpoint on the site server) was
> designed and costed. **Audi is not taking it.** Its scripts are not part of this
> repository and are not installed. If it is ever revived, only the transport
> changes — the engine, the config and the window are the same files.

---

## 2. What is needed in every environment

### 2.1 Accounts and groups — the AD team

| Item | Example | Notes |
|---|---|---|
| Service account (gMSA) | `DEAUDI005T\svc-swintegration$` | One per environment. Password created and rotated by AD, never seen by anyone. Note the trailing `$`. |
| Servers allowed to use it | the server that runs the collector task | `PrincipalsAllowedToRetrieveManagedPassword` |
| Operator group | `DEAUDI005T\G-Audi-SwIntegration-Operators` | The packagers. **No rights of its own.** |

```powershell
# AD team, once per environment
New-ADServiceAccount -Name svc-swintegration -DNSHostName svc-swintegration.audi.vwg5t `
    -PrincipalsAllowedToRetrieveManagedPassword 'AUDIINSA1298$'
New-ADGroup -Name G-Audi-SwIntegration-Operators -GroupScope Global -Path 'OU=...'

# on the server, once
Install-ADServiceAccount -Identity svc-swintegration
Test-ADServiceAccount    -Identity svc-swintegration      # must return True
```

**Why a gMSA and not an ordinary service account.** A gMSA has no password a human
ever holds, and it rotates automatically. It also has *real* credentials, so the
session can reach onward resources — the SMS Provider, the content share, the ARS
service. A JEA *virtual account* could not: it would appear on the network as the
computer account.

If Audi refuses gMSA, the fallback is an ordinary service account stored once in
Task Scheduler on that one server. The password then exists there only — never on
a packager's PC. Everything else is unchanged.

### 2.2 Permissions for the service account

| Where | What | Why |
|---|---|---|
| **SCCM** | A security role equivalent to **Application Administrator**, limited to the security scopes and limiting collections named in the environment file | create the application, deployment type, collections, deployments, scopes, folder moves |
| **Content share** | **Modify** | the job's first step copies the package from the drop folder's `Sources\` into the store, under its SCCM name; the deployment type points at it |
| **ARS / SPML** | Create and delete groups in the target OU only | the access group |
| **Server-side drop folder** | Modify on all five state folders | it claims, reads, files and answers jobs, and clears `Sources\` once a job has succeeded |
| **Collector host** | *Nothing.* Not a local administrator. | it only needs to be the task's RunAs identity |
| **Domain** | *Nothing.* Not a Domain Admin. | — |

**What the operator group gets: membership, and nothing else.** No SCCM rights, no
store rights, no local rights. This is the point of the design — after rollout the
packagers' personal MECM admin accounts can be withdrawn.

**The sync account** (on the middle server, one per zone pair) needs exactly two
things and nothing else: **Modify** on the client-side drop folder root and
**Modify** on the server-side drop folder root. No SCCM rights, no store rights,
no environment files - it never opens the files it carries.

### 2.3 What we install on the server

```
C:\Program Files\Audi\SwIntegration\        the engine and its config
C:\ProgramData\Audi\SwIntegration\Logs\<env>\<package>\<jobId>\
                                            one folder per job: the log and job.json
```

Nothing else on the server is modified. No SCCM setting is changed. Removal is one
command and leaves the environment exactly as it was.

### 2.4 What the packager needs

- A domain-joined PC, signed in with their normal account
- Membership of the operator group
- A shortcut to the tool on a share
- **Modify** rights on the client-side drop folder (see 3.1) - the window
  writes the job into `New\` and the package content into `Sources\`. Where the
  share needs a different account, the window asks for it when it cannot open
  the folder, up to three times per attempt
- **No** rights on the content store - the SCCM server copies the content in
- **No** SCCM console, **no** SCCM rights, **no** local admin, **no** password, nothing installed

> **The most common support call.** Group membership is read from the Windows
> **logon token**. Someone newly added must sign out and back in, or they will be
> refused while looking at their own name in the group. Put this in the handover.

---

## 3. The drop folder

### 3.1 The folder and its rights

There are **two** drop folders with the **same layout**: the **packager-side**
one (a share in the packagers' zone) and the **SCCM-side** one (a share in the
SCCM zone - on the site server or beside it). The sync task on the middle server
keeps them in step. One environment is one subfolder under the root, on both:

```
<root>\
    INA\
        New\        the window creates job files here (packager side); the watcher reads them (SCCM side)
        Sources\    the window puts the package content here, under its SCCM name; the SCCM server copies it into the store
        Working\    packager side: the "in transit" marker while the job is away, and the heartbeat coming back
                    SCCM side: claimed by the watcher
        Done\       finished, with a .result.xml beside the archived job
        Failed\
    ICZ\  ...       created by the first job for that environment - nobody pre-creates it
```

| Principal | Where | NTFS | On which folder |
|---|---|---|---|
| Operator group | packager-side root | Modify | the environment folders (`New\` and `Sources\` are written, `Done\` `Failed\` `Working\` are read for results) |
| Sync account (middle server) | packager-side root | Modify | all |
| Sync account (middle server) | SCCM-side root | Modify | all |
| SCCM service account | SCCM-side root | Modify | all |

The packagers never see the SCCM side; the SCCM service account never sees the
packager side; the middle server sees the two drop folders and nothing else.

**Very likely no new permission is needed on the packagers' side.** Their
existing flow already copies content to a share the middle server can reach, so
packagers have write access there today — this may be a new folder beside one
they already use.

### 3.2 How identity is proven — the part that needs care

**Audi's requirement: no real person's name reaches the SCCM side at all.** Not
an SCCM object, not the tool's log on the server, not `job.json`, not the result
file. The people who package software are not to appear as having made changes on
the server.

So the tool has **one identity, not two**: the shared service account. It is what
SCCM records in the application's `Owner` field, and it is the only account named
anywhere the server writes.

#### Then how is a change traced back to a person?

**Through the RFC number**, which is written onto every object the tool creates:

```
Created by the SCCM Integration Tool | job 8f1c…-…-4b2e | RFC RFC0012345
```

An auditor takes the RFC from the console and looks it up in Audi's change
system, which already records who raised it. The link to a person still exists —
it just lives on the requesting side, not on the SCCM server.

**And on the packagers' own side** there is a second, private route: every
submission appends one line to `<packager drop folder>\Record\<yyyy-MM>.txt` –
time, account, machine, environment, package, action, RFC, job id. That folder
never leaves the packager zone (the sync carries only environment folders), so
the packaging team can always answer "who did this job" among themselves while
the SCCM side still holds no name. The job id is the key between the record and
a result; it is not shown on the page, only on the history hover text.

**Consequence, stated plainly:** on the SCCM side the RFC is the *only* route
back to a person, so a job without one would be an untraceable change there. The tool therefore refuses
it — both in the window, before the job is queued, and again on the server. If
Audi would rather allow untraceable changes, that is `requireRfc="false"` in
`Defaults.xml`, and it should be a written decision.

#### How the rule is held in place

| Where | What it does |
|---|---|
| `Get-AudiIntegrationPlan` | the plan has **no requester field at all** — there is nothing for a log line, comment or record to write |
| `Defaults.xml` | the comment template names only `{jobId}` and `{rfc}` |
| `Get-AudiDefaults` | a config that puts `{requester}` back is **rejected at load** — so the rule survives an edit made on the server after handover |
| `Read-AudiSwJobFile` | never reads the job file's owner; a file that names a requester is rejected by the schema |
| `Watch-AudiSwDropFolder.ps1` | archives the finished job by **re-writing it as the service account** and deleting the packager's original, so no person-owned file is left in the secure zone |

Tests check the **artefacts**, not just the code: the real log, `job.json` and
result file are read back and fail if any name but the service account appears.

**Why the file is not allowed to name anyone.** Whoever can write to the folder
could put any name inside a job file, so a name in the file would prove nothing
and could frame a colleague. Rather than ignore such a name, the schema makes it
impossible: `<Job>` has **no requester attribute at all**, so a file carrying one
is rejected outright. Combined with the collector never reading the file's NTFS
owner, there is no path by which a person's identity can reach the server side.
This is the single most important detail in the whole transport, and there is a
test for it (`Test-Transport.ps1`, *"a job with an extra requester attribute is
rejected by the schema"*).

### 3.3 The scheduled task

```powershell
.\SccmServer\Install-AudiSwDropWatcher.ps1 `
    -Gmsa       'DEAUDI005T\svc-swintegration$' `
    -DropFolder '\\<sccm-zone share>\SwIntegration$\ICZ' `
    -WhatIf
```

Runs as the gMSA, so **no password is stored in Task Scheduler either**. Every few
minutes it claims jobs by moving them to `Working\` — which also prevents two runs
picking up the same job — copies `Sources\<package>` into the content store as the
job's first step, runs the job, and writes a `.result.xml` back. `-DropFolder` is
the **SCCM-side** drop folder, the environment's subfolder of it - a share in
the SCCM zone, or a local path when the folder sits on the site server itself.

**Every path lives in a settings file, not in the task.** The installer writes
`-DropFolder` into `Watcher-Settings.txt` next to the installed script, and the
scheduled task's command line carries no path at all. To change the folder
later, edit that file - the next pass uses it; nothing is re-installed. (The
same file can be filled in beforehand, then `-DropFolder` is not needed.)

**One task per environment, each pointed at its own folder** — `<share>\ICZ` on
the ICZ server, `<share>\INA` on the INA server. The window writes every job to
`<share>\<ENV>\New\<package>\`, so a server can only ever collect the
environment it is pointed at. Pointed at the share root instead, one collector
serves every environment folder under it — useful on a single test machine.

**How many jobs at once.** One task runs the queue one job after another, oldest
first, and starts again every 3 minutes. When traffic grows, add workers:

```powershell
.\Install-AudiSwDropWatcher.ps1 -Gmsa '...' -DropFolder '\\<sccm-zone share>\SwIntegration$\INA' -Workers 3
```

That registers three tasks on the same folder, started a minute apart, so three
packages are integrated side by side. It is safe by construction: a job is
claimed by an atomic move to `Working\`, so two workers can never take the same
one; one job per package at a time still holds across workers (a newer job for a
package waits or is refused while an older one runs, never the other way round);
and the engine holds a per-package lock on the SCCM side as the last line. Every
environment has its own task(s) anyway, so ICZ and INA never wait for each other.

**Package names in SCCM carry an underscore before the revision**
(`INA_WinMerge_WinMerge_x64_2.16.58_0001_test`), whatever the packager's folder
was called; the content folder on the share must be spelled that way too. Only
the branding key keeps the hyphen, because that is what the script writes.

### 3.3a The sync task on the middle server

```powershell
.\MiddleServer\Install-AudiSwDropFolderSync.ps1 `
    -Account    'DEAUDI005T\svc-swsync$' `
    -ClientRoot '\\isnasv117\GPF-Package-Documentation\DropFolder' `
    -ServerRoot '\\<sccm-zone share>\SwIntegration$' `
    -WhatIf
```

`-ClientRoot` is the packager-side share; `-ServerRoot` is the SCCM-side share.
The sync account needs Modify on both and nothing else - it never opens the
SCCM server itself, and never the store. Every transfer between the two zones
is this task, in both directions; neither zone reaches into the other.

As with the watcher, **the paths live in `Sync-Settings.txt`** next to the
installed script, written by the installer; the task's command line carries
none. Edit the file to change a path; the next pass uses it.

Every two minutes it carries, per environment folder: `Sources\<package>` in
(content first, so no job ever arrives ahead of it), then the job files in, then
heartbeats and finished results back out to the packager side. The packager
side's copy of a carried job moves to its `Working\` as the "in transit" marker,
so the window still shows the job as pending and still refuses a second job for
the same package until the result is back. Every copy is staged under a `~` name
and renamed into place, so neither side can read a half-copied file or folder.

Pass `-EnvironmentCode INA` when one middle server serves one zone only; without
it the task carries every environment folder it finds.

**When a share cannot be opened.** The sync (and the watcher) first drops a
stale session to the same server under another account – Windows error 1219,
"multiple connections" – with `net use \\server\share /delete` and tries the
path again. If it still does not open and a *person* is running the script at
a console, it asks for a sign-in (up to three times, `Get-Credential` +
`New-PSDrive -Credential`, no password on any command line). The scheduled
task cannot ask, and its log says so in one line: which root, as which
account, and the reason (ACCESS DENIED / path does not exist / network) – so
the share team knows exactly what to grant.

**The packager is never blind.** Every pass leaves a one-line status file:

| File | Written by | Read by |
|---|---|---|
| `<packager root>\sync-status.txt` | the sync task, at the end of every pass – also when the SCCM side could not be reached (`FAILED` + the reason) | the window's Jobs page, *CONNECTION → Middle server* |
| `<root>\<ENV>\watcher-status.txt` | the watcher, in the SCCM-side folder, every pass | carried back by the sync; Jobs page, *CONNECTION → SCCM server* |

Format `2026-09-18T15:41:02+02:00|HOST|OK|message`. The Jobs page shows a dot:
green = passing, amber = no pass for 10 minutes ("the middle server may be
down"), red = FAILED with the reason. So "QUEUED for an hour" always comes with
its cause, and no one has to log on to either server to find it.

### 3.3b What happens when something goes wrong after the SCCM server has started

Asked by Audi: *error handling, specifically after the job has reached SCCM.*
Every row ends with a result file the packager sees on the Jobs page.

| What goes wrong | What the server does | What the packager sees | Left on the site |
|---|---|---|---|
| Package not in `Sources\` and not in the store | refuses the job before touching SCCM | FAILED – "neither in the store nor in Sources … wait for the next sync pass" | nothing |
| Store copy dies half-way (network, disk full) | the copy went to `~name.copying`; the half folder is removed on the next attempt; the job fails | FAILED at step "Content copy" with the error | nothing – no half package ever appears under the real name |
| A step fails during Integrate (collection, deployment, scope …) | **rolls back** everything it created in this run, in reverse order | FAILED – the failing step and the reason, plus "Rolled back: …" rows | nothing from this run |
| A step fails during Modify / Change | stops there, no rollback (the application is live; half-undoing is worse) | FAILED – which step, what was done before it | what the earlier steps did – reported, not hidden |
| SCCM says "already exists" | reported as that step's failure | FAILED with SCCM's own words | as before the run |
| SMS Provider unavailable / timeout | retried with back-off (`<Retry>` patterns in Defaults.xml); then fails | FAILED naming the provider error | nothing from this run |
| **The server dies mid-job** (reboot, task killed, 4-h limit) | the next pass finds a job in `Working\` with no heartbeat for `StaleJobMinutes` (240) and **closes it as FAILED** with the last step the heartbeat reported. **Nothing on the site is touched automatically** (Audi's rule: drop-folder actions yes, site actions only after a confirmation) | FAILED – "the server stopped … nothing on the site has been touched since" plus the next step: **Run again** (Modify / Change / Remove / an Integrate that never created its application – what is already done is skipped, the rest completed) or **Clean up** (an Integrate that did create its application – the Remove page, name typed back, removes exactly this package's objects) | what the finished steps did, listed in the result – the packager's Run again or Clean up settles it, with a confirmation that names every object |
| Watcher task stopped altogether | jobs wait in `New\` | QUEUED / HANDED OVER on the Jobs page, for as long as it takes | nothing |
| Sync task stopped | jobs wait on the packager side; results wait on the SCCM side | QUEUED / HANDED OVER | nothing |
| Result cannot be written back (share full, rights) | warning in the task log; the job stays in `Working\` until it can be filed | HANDED OVER, then FAILED once the stale rule closes it | as the job left it |

`Sources\<package>` is removed the moment the store holds a verified copy –
also when a later step of the same job fails, and also when the engine throws
(a preflight refusal). The result then carries *Content copy – OK* as its first
step and the message ends "The package files ARE in the store; Run again
continues from there". The window reads that: the Package content row says
*in the SCCM store since …*, Integrate copies nothing again, Run again runs
from the store. Sources stay only when the content step itself failed or never
ran – the one case a retry needs them.

**Every copy is verified.** The sync task copies with robocopy (restartable,
retries) straight from the packager share to the SCCM-side share – nothing
lands on the middle server, not even temporarily; the staging folder is on the
destination share. After the copy, file count and total bytes are compared on
both sides; a copy that does not agree is dropped and tried again on the next
pass, and the job it belongs to waits with it. The SCCM server's copy into the
store is verified the same way before the folder gets its real name. The step
messages carry the numbers ("312 files, 1,204,551,680 bytes – verified").

**Two rules from Audi, and how the tool keeps them**

1. *Automatic actions may happen inside the drop folder; anything that writes
   to or deletes from SCCM needs a confirmation.* So the server closes,
   files, re-queues and reports on its own, and never removes or re-runs
   anything on the site by itself. Run again and Clean up are buttons on the
   Jobs page; both ask first.
2. *Every removal or change says exactly what it will do, by name, before it
   is confirmed* (Ewald's wildcard case). Integrate, Update, Remove, Apply
   changes, Apply machines and Run again each open one prompt that lists the
   application, the collections, the machines and the settings by their whole
   names – and what is *not* touched. On the server, no object is ever removed
   by name: it is fetched, matched **exactly** (whole string, case-sensitive)
   and handed to the remove cmdlet as an object; a name containing `* ? [ ]`
   is refused before any cmdlet sees it, and so is a package name with a
   wildcard, a path character or a space.

**Removing, in full (18.09.2026):**

| Situation | How | What is asked |
|---|---|---|
| A package this tool integrated | Remove page, package name typed back | one prompt naming the application, its deployment type, every collection with its deployment, and what is *not* touched |
| …and its files in the store | tick *Also delete the package folder from the content store* | a second, separate question with the exact folder path; deleted only after SCCM has let go, only that one folder directly under the environment's store, by literal path |
| An application this tool did not create – legacy, hand-made, or a name with a `*` in it | *Find on the site*: type a name or pattern, the server lists every match with its collections and content folder; **tick** the ones to go; *Remove ticked* | one prompt naming every ticked application and its collections; then the content question. The pattern is a search only – what is removed is the exact names ticked, each matched whole on the site and removed as an object |
| Only the files changed (new build, same version) | Integrate page, *Update content* | one prompt: the store folder that is updated, the deployment type that is re-distributed, and everything that is not touched. On the SCCM side the package in Sources is compared with the store **file by file, by size and SHA-256 – never by timestamp**; only files that differ are replaced, new ones added, dropped ones removed, and no timestamp is ever rewritten. A one-file change to a 4 GB package writes one file, and the distribution points fetch one file |

### 3.3d Housekeeping – the drop folder over the long term

The **permanent record** of every job is the server log,
`C:\ProgramData\Audi\SwIntegration\Logs\<env>\<package>\<jobId>\` (log + job
record), on the SCCM server. The drop folder only feeds the window's Jobs page
and the sync task. So it does not have to keep things for ever, and the watcher
tidies it on every pass, by the days in `Watcher-Settings.txt` (0 = keep for
ever):

| What | After | Where it goes |
|---|---|---|
| a finished job in `Done\` (job file + result) | `DoneRetentionDays` = 90 | `Archive\<yyyy-MM>\<package>\` in the same environment folder |
| a failed job in `Failed\` | `FailedRetentionDays` = 180 | the same |
| an `Archive\<yyyy-MM>\` month | `ArchiveRetentionDays` = 365 | deleted |
| a package's `Sources\` with **no job pending for it** (a failed job nobody ran again) | `SourcesRetentionDays` = 14 | deleted – the next Integrate copies it afresh |
| …a **large** one (`LargeSourcesGB` = 8 or more) | `LargeSourcesRetentionDays` = 2 | the same, sooner |

**`Sources\<package>` is cleared the moment the store holds a verified copy** –
whatever the rest of the job then does. A job that copied its content and
then failed on a collection is run again from the store ("Already in the
store"), never from Sources, so keeping gigabytes beside the store would be
waste. Sources stay only when the content step itself failed or never ran
(the one case a retry needs them), and under a dry run.

**Room is checked before a byte moves.** The sync task refuses to carry a package
the SCCM-side volume cannot hold (with the numbers; the package waits on the
packager side, its job with it), and the store copy refuses the same way,
both keeping a 2 GB margin. A refused copy is a clear message in the result,
not a full disk on the SCCM server.

**Size of the XML side, for scale**: a job file is about 1 KB, a result about
3 KB, an Inspect answer about 7 KB. A hundred packages with five runs each is
around 2–3 MB – nothing next to the packages themselves.

The sync task carries results back to the packager side, so the packagers' copy
of `Done\` and `Failed\` is theirs to keep or clean as they like.

**When the content copy itself went wrong** (a copy that did not verify, wrong
files sent): the packager presses *Copy now* on the Integrate page – the
window says the files are already in the drop folder and offers to copy them
again, replacing what is there – or simply Integrates again. The sync task always
**replaces** a `Sources\<package>` already on the SCCM side with the newer
copy (verified by file count and bytes before the swap), so the next run sees
the fresh files. Nothing has to be deleted by hand on any server.

### 3.3c Input validation – "Exploits of a Mom"

Asked by Audi with the xkcd cartoon: a job file is written in another zone by a
packager's tool, so what stops a crafted file doing damage on the SCCM server?

1. **Nothing is ever assembled from job-file values.** No query, no command
   line, no script is built by string concatenation. Every value reaches SCCM
   as a **cmdlet parameter**, and files only through `Join-Path`. There is no
   SQL, WQL or shell for a `'); DROP TABLE` to escape into.
2. **Every value is still limited by the schema before any code sees it**
   (`Environment.xsd`, section *Input validation*): package name
   `[A-Za-z0-9._+-]` only – no slash, backslash, space or quote, so it can
   never leave the folder it is joined to; job id, RFC, setting and OS keys
   the same class; machine names what NetBIOS/DNS allow; collection names
   letters, digits, space, `._+-`; display names and descriptions no control
   characters and no longer than SCCM accepts. A file that breaks a rule is
   **rejected by the schema**, filed to `Failed\` with the reason, and never
   runs.
3. **The name in the file must be the folder it sits in**, or the job is
   refused – a file cannot run under one name and file under another.
4. **The engine trusts the file only for *what*, never for *whether*.** A
   collection named in a Change must be one of *this package's* collections; a
   setting key must be in the server's catalogue and marked editable; an action
   must be one of the five the schema lists. Anything else is refused by the
   server, whatever the window sent.
5. **The file is data, never code.** The watcher reads named fields; it never
   executes file content and never runs anything found in `Sources\`.

The tests drive ten crafted files (path in the name, quote in a machine name,
`DROP TABLE` in an RFC, control characters, over-length text …) through the
schema and check each is refused – `Tests\Test-Transport.ps1`, *Input validation*.

### 3.4 Answers for the security review

| Question | Answer |
|---|---|
| Who crosses the zone boundary? | Only the middle server's task, in both directions. The SCCM server never leaves its zone; the packager PC never leaves its own. |
| Does the middle server reach the SCCM server or the store? | No. It reaches the two drop folder shares and nothing else. |
| Who writes into the content store? | Only the SCCM service account, from the SCCM-side `Sources\`. Packagers and the middle server have no store access. |
| Can a packager run code on the server? | No. They write a data file. The watcher reads named fields only and never executes file content. |
| Can a packager impersonate another? | There is no identity to impersonate. The server never establishes who wrote the job. |
| How is a change traced to a person? | By RFC number, through Audi's change system. No name is kept on the server. |
| Can a packager see others' jobs? | Only on the packager side, where their team already works together; nothing of the middle server or the SCCM zone is visible to them. |
| What if the watcher stops? | Jobs queue in the middle server's `New\`. Nothing is lost. Monitor the task like any other. |
| What if the sync task stops? | Jobs wait in the packager-side `New\`, results wait in the middle server's `Done\`. Nothing is lost; the next pass carries everything. |
| Does the middle server run anything from the files? | No. The sync task copies and renames; it never opens a job file or runs anything in `Sources\`. |
| Can two jobs collide? | No. One job per package at a time, enforced in the window, in the watcher and by a lock in the engine. Different packages can run side by side (`-Workers`). |

---

## 4. The checklist Audi can sign off

| # | What | Owner | Done |
|---|---|---|---|
| 1 | Service account (gMSA) created | AD team | ☐ |
| 2 | Operator group created and populated | AD team | ☐ |
| 3 | gMSA installed on the collector host | Server team | ☐ |
| 4 | SCCM rights granted to the account | SCCM team | ☐ |
| 5 | Content share **Modify** granted to the account | Server team | ☐ |
| 6 | ARS / SPML rights granted to the account | IAM team | ☐ |
| 7 | Both drop folders created (packager zone, SCCM zone), with the rights in 3.1 | Server team | ☐ |
| 8 | Sync account created, Modify on both drop folder roots | AD / server team | ☐ |
| 9 | Engine installed on the SCCM server | Us | ☐ |
| 10 | Watcher scheduled task registered on the SCCM server (one per environment, pointed at the SCCM-side folder) | Us | ☐ |
| 11 | Drop folder sync task registered on the middle server | Us | ☐ |
| 12 | Packager share and shortcut published, `Packager\Settings.txt` pointed at the packager-side root | Us | ☐ |

**Not needed, and worth saying out loud:** no firewall change, no open port, no
certificate, no software on any packager's PC, and no change to any existing
SCCM setting. The middle server is one Audi already has - it gets one scheduled
task and one script.

---

## 5. Order of work

| # | Step | Owner |
|---|---|---|
| 1 | Confirm the PCZ values still marked `verified="false"` | Audi |
| 2 | Confirm the two drop folder roots (client side, server side) and the middle server | Audi |
| 3 | Create the gMSA, the sync account and the operator group | AD team |
| 4 | Install the gMSA on the collector host | Server team |
| 5 | Grant SCCM rights, store access and ARS rights to the account | SCCM / server / IAM |
| 6 | Create both drop folders and set their rights | Server team |
| 7 | Install the engine and register the collector task; register the sync task on the middle server | Us |
| 8 | Verify on **ICZ** with a real package | Us + Audi |
| 9 | Roll out to INA, then PCZ | Us + Audi |
| 10 | Withdraw the packagers' personal MECM admin accounts | Audi |

Step 10 is the point of the project — worth stating in the plan so it is not
forgotten once the tool works.

---

## 6. Acceptance test

On a PC with **no SCCM console**, signed in as an account with **no SCCM rights**:

1. Integrate a real test package on ICZ — it succeeds.
2. The application's **Owner** in SCCM reads the **service account**.
3. The log, `job.json` and the result file name **only the service account** — no
   personal name appears anywhere on the server.
4. Point the content share at a missing path — the tool reports the real reason
   and creates nothing.
4a. Check the store after 1 — the content is there under the SCCM name (underscore
    before the revision), the job's first step reads "Content copy", and
    `Sources\<package>` is gone from both drop folders.
4b. Stop the sync task, Integrate, watch the window — the job stays "pending",
    a second Integrate of the same package is refused; restart the sync task — the
    job runs and the result comes back.
5. Stop a run halfway — what it created is rolled back.
6. Remove someone from the operator group — their next attempt is refused.
7. Stop the collector task, submit a job, restart it — the job runs, nothing lost.
8. Hand-edit a job file to add a requester — the server **rejects** it.
9. Submit without an RFC — the window refuses before it queues anything.
10. Check `\Done` — the archived job file is owned by the **service account**, not
    by the packager who wrote it.

Passing 1–3 proves the whole design: the shared account really does the work, and
the packager really no longer needs privileges. 3, 8 and 10 together prove the
privacy requirement — no person is recorded anywhere on the SCCM side.
