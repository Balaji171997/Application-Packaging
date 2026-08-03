# Deployment plan — Audi SCCM Integration Tool

Everything Audi has to provide, what we install, and what the security review will
ask about.

Repeat all of it **once per environment** (ICZ, INA, PCZ). The three environments
are separate AD domains, so nothing can be shared between them.

---

## 1. How a job reaches the server — decided

**The drop folder.** The packager window writes the job as a file into a folder in
the secure zone. A scheduled task inside that zone collects it a few minutes later
and runs it as the service account, then writes a result file back.

```
packager's PC                    a plain file share                the SCCM server
┌───────────────────┐            ┌────────────────────┐           ┌──────────────────┐
│ packager window   │  writes a  │  \New              │  reads    │ scheduled task   │
│ no SCCM rights    │ ─ file ──▶ │  \Working          │ ◀──────── │ runs as the gMSA │
│ no SCCM console   │            │  \Done  \Failed    │ ─ writes  │ does all the work│
│ waits for a file  │ ◀───────── │  <job>.result.xml  │  result ▶ │                  │
└───────────────────┘            └────────────────────┘           └──────────────────┘
```

**Nothing connects inward, so no firewall change is needed.** This matches Audi's
own architecture drawing, where a barrier separates the packaging zone from the
SCCM zone and content is *copied across* rather than reached through.

The trade-off, stated honestly: the packager gets a result a few minutes later
instead of watching the work happen live.

> The live-connection alternative (a WinRM/JEA endpoint on the site server) was
> designed and costed. **Audi is not taking it.** Its scripts are parked under
> `Server\_NotUsed-LiveConnection\` and are not installed. If it is ever revived,
> only the transport changes — the engine, the config and the window are the same
> files.

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
| **Content share** | Read (Modify if the tool is later asked to copy content) | preflight checks the source exists; the deployment type points at it |
| **ARS / SPML** | Create and delete groups in the target OU only | the access group |
| **Drop folder** | Full control on all four subfolders | it claims, reads, files and answers jobs |
| **Collector host** | *Nothing.* Not a local administrator. | it only needs to be the task's RunAs identity |
| **Domain** | *Nothing.* Not a Domain Admin. | — |

**What the operator group gets: membership, and nothing else.** No SCCM rights, no
share rights, no local rights. This is the point of the design — after rollout the
packagers' personal MECM admin accounts can be withdrawn.

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
- **Create-files** rights on the drop folder's `New\` subfolder (see 3.1)
- **No** SCCM console, **no** SCCM rights, **no** local admin, **no** password, nothing installed

> **The most common support call.** Group membership is read from the Windows
> **logon token**. Someone newly added must sign out and back in, or they will be
> refused while looking at their own name in the group. Put this in the handover.

---

## 3. The drop folder

### 3.1 The folder and its rights

```
\\<server>\SwIntegration-Inbox$\
    New\        packagers create job files here
    Working\    claimed by the watcher
    Done\       finished, with a .result.xml beside it
    Failed\
```

| Principal | Share | NTFS | On which folder |
|---|---|---|---|
| Operator group | Change | **Create files / write data** only — *not* read, *not* delete | `New\` only |
| Service account | Full | Modify | all four |

Granting *create only* on `New\` means one packager cannot read, alter or delete
another's job.

**Very likely no new permission is needed.** Their existing flow already copies
content into the secure zone, so packagers have write access there today — this
may be a new folder beside one they already use.

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

**Consequence, stated plainly:** the RFC is now the *only* route back to a person,
so a job without one would be an untraceable change. The tool therefore refuses
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

The requester has to be provable, and **a file carries no guarantee on its own**:
whoever can write to the folder could put any name inside it. So
`Watch-AudiSwDropFolder.ps1` **ignores any requester written in the file** and
takes the **NTFS owner**, which Windows stamps at creation and the writer cannot
change.

The job schema goes one step further: `<Job>` has **no requester attribute at
all**, so a file carrying one is rejected outright rather than quietly ignored.
This is the single most important detail in the whole transport, and there is a
test for it (`Test-Transport.ps1`, *"a job with an extra requester attribute is
rejected by the schema"*).

### 3.3 The scheduled task

```powershell
.\Install-AudiSwDropWatcher.ps1 `
    -Gmsa       'DEAUDI005T\svc-swintegration$' `
    -DropFolder '\\audiinsv1059\SwIntegration-Inbox$' `
    -WhatIf
```

Runs as the gMSA, so **no password is stored in Task Scheduler either**. Every few
minutes it claims jobs by moving them to `Working\` — which also prevents two runs
picking up the same job — and writes a `.result.xml` back.

### 3.4 Answers for the security review

| Question | Answer |
|---|---|
| Is any port opened? | No. Nothing connects inward. |
| Can a packager run code on the server? | No. They write a data file. The watcher reads named fields only and never executes file content. |
| Can a packager impersonate another? | There is no identity to impersonate. The server never establishes who wrote the job. |
| How is a change traced to a person? | By RFC number, through Audi's change system. No name is kept on the server. |
| Can a packager see others' jobs? | Not if `New\` grants create-only, as specified. |
| What if the watcher stops? | Jobs queue in `New\`. Nothing is lost. Monitor the task like any other. |

---

## 4. The checklist Audi can sign off

| # | What | Owner | Done |
|---|---|---|---|
| 1 | Service account (gMSA) created | AD team | ☐ |
| 2 | Operator group created and populated | AD team | ☐ |
| 3 | gMSA installed on the collector host | Server team | ☐ |
| 4 | SCCM rights granted to the account | SCCM team | ☐ |
| 5 | Content share access granted to the account | Server team | ☐ |
| 6 | ARS / SPML rights granted to the account | IAM team | ☐ |
| 7 | Drop folder created, with the rights in 3.1 | Server team | ☐ |
| 8 | Engine installed on the server | Us | ☐ |
| 9 | Collector scheduled task registered | Us | ☐ |
| 10 | Client share and shortcut published | Us | ☐ |

**Not needed, and worth saying out loud:** no firewall change, no open port, no
certificate, no new server, no software on any packager's PC, and no change to any
existing SCCM setting.

---

## 5. Order of work

| # | Step | Owner |
|---|---|---|
| 1 | Confirm the PCZ values still marked `verified="false"` | Audi |
| 2 | Confirm the drop folder path per environment | Audi |
| 3 | Create the gMSA and the operator group | AD team |
| 4 | Install the gMSA on the collector host | Server team |
| 5 | Grant SCCM rights, share access and ARS rights to the account | SCCM / server / IAM |
| 6 | Create the drop folder and set its rights | Server team |
| 7 | Install the engine and register the collector task | Us |
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
