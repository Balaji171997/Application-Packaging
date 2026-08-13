# Audi SCCM Integration Tool

Replaces Audi's **EQS SW Integration Tool 1.0.3**. Same job - integrate, modify
and remove software packages in ICZ, INA and PCZ - with two things changed:

1. **All SCCM and AD work is done by one shared service account**, not by each
   packager's personal administrator account.
2. **Every environment setting lives in XML.** Adding a fourth environment is one
   new file. No code change, no rebuild, no release.

| | Today | With this tool |
|---|---|---|
| Who acts in SCCM | each packager, personally | one service account |
| Packager needs the SCCM console | yes | **no** |
| Packager needs SCCM rights | yes | **no** |
| Where environment settings live | 36 XML files + ~40 values inside the script | 3 XML files + 1 defaults file |
| A step that fails | window still says `"Done."` | reports the real error and rolls back |

---

## Who does what

| Role | What they touch | What they need |
|---|---|---|
| **Packager** | the window on a file share | nothing - no console, no rights, no admin |
| **SCCM / server team** | the scheduled task and `Server\Engine\Config` | one service account, one folder |
| **AD team** | the service account, once | a standard service-account request |

Nobody edits a script to run this. The only files anyone maintains are the four
XML files in `Server\Engine\Config`.

---

## How it works

The window never connects to the SCCM server, and the server never accepts a
connection. They exchange **files on a share**.

```
packager's PC                    a plain file share                the SCCM server
┌───────────────────┐            ┌────────────────────┐           ┌──────────────────┐
│ packager window   │  writes a  │  \New              │  reads    │ scheduled task   │
│ no SCCM rights    │ ─ file ──▶ │  \Working          │ ◀──────── │ runs as the      │
│ no SCCM console   │            │  \Done  \Failed    │ ─ writes  │ service account  │
│ reads the result  │ ◀───────── │  <job>.result.xml  │  result ▶ │ does all the work│
└───────────────────┘            └────────────────────┘           └──────────────────┘
```

Four points that usually come up in review:

- **No firewall rule, no inbound port.** Both sides already reach the share.
  Nothing is opened into the secure zone.
- **No person reaches the server.** The job file carries no user name and the
  server does not work one out - it does not read the file's owner either. Every
  record on the SCCM side is keyed by **job ID** and **RFC number**. RFC to person
  is a lookup in Audi's change system, where that link belongs.
- **The RFC is mandatory.** With no name kept, it is the only route back to a
  requester, so a job without one is refused.
- **Nothing is lost if the window is closed.** The server writes its result
  whether anyone is watching or not. Reopen the tool, type the package name, and
  the result is read straight back out of the share.

A live WinRM/JEA connection was designed as the alternative and is **not** being
built. Its scripts sit under `Server\_NotUsed-LiveConnection\` so nobody installs
them by mistake.

---

## Where the files go

```
AudiSwIntegration\
│
├── Server\          →  ON the SCCM server, in the secure zone
│   ├── Engine\                        the tool itself
│   │   ├── AudiSwIntegration.ps1        entry point
│   │   ├── Src\                         Config Runtime Transport Provider Steps
│   │   │                                Inspect Preflight Orchestrator
│   │   └── Config\                      THE ONLY FILES ANYONE EDITS
│   │       ├── Environments\              ICZ.xml  INA.xml  PCZ.xml
│   │       ├── Defaults.xml               what is the same everywhere
│   │       └── Environment.xsd            what all of them are checked against
│   ├── Install-AudiSwDropWatcher.ps1    creates the scheduled task, once
│   ├── Watch-AudiSwDropFolder.ps1       collects jobs from the share
│   └── _NotUsed-LiveConnection\         the option we are NOT building
│
├── Client\          →  on a SHARE; packagers get a shortcut
│   ├── Start-AudiSwClient.ps1           the packager window
│   └── MainWindow.xaml                  its layout
│
└── Tests\           →  stays with us, never deployed
```

**Nothing about the environments sits on a packager's PC.** Site servers, share
paths, scope IDs and collection IDs are all in `Server\Engine\Config`, in the
secure zone - so a config change never means redistributing the client.

---

## Running it

```powershell
# the packager window - dry run is ON by default, nothing is changed
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Client\Start-AudiSwClient.ps1
```

```powershell
# all 419 checks - no SCCM, no network, no rights
.\Tests\Invoke-AllTests.ps1
```

```powershell
# the window's own wiring, without opening it
.\Client\Start-AudiSwClient.ps1 -SelfTest
```

On the server, once:

```powershell
.\Server\Install-AudiSwDropWatcher.ps1 -Gmsa '<account>' -DropFolder '<share>' -WhatIf
```

From the console instead of the window:

```powershell
. .\Server\Engine\AudiSwIntegration.ps1
$plan = Get-AudiIntegrationPlan -PackageName 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0003_MUL' -EnvironmentCode 'INA' -Rfc 'AES-1-000123-A'

Invoke-AudiSwIntegration -Plan $plan -DryRun     # preview, changes nothing
Invoke-AudiSwIntegration -Plan $plan             # real run
Invoke-AudiSwModification -Plan $plan -DryRun    # reconcile an existing app
Invoke-AudiSwRemoval      -Plan $plan -DryRun
Test-AudiSwPrerequisite   -Plan $plan -Provider (New-AudiSccmProvider)
```

**[TESTING.md](TESTING.md)** - what to click, and how to test against a real ICZ
site. **[DEPLOYMENT.md](DEPLOYMENT.md)** - accounts, permissions, the share, and
the security-review answers.

---

## What it does

| Area | Detail |
|---|---|
| Config | XSD-validated; a bad file is rejected before anything runs |
| Package reading | fills the window from the package's own PSADT script and instruction document; every value records where it came from |
| Plan | expands package + environment into the exact list of objects, contacting nothing |
| Preflight | checks source path, name clashes, limiting collections, DP group and scopes **before** creating anything |
| Engine | 8 integration, 9 modify and 4 removal operations, ordered by declared dependencies |
| Failure | reports the real error, and rolls back what it created, newest first |
| Retry | only faults listed in `TransientErrors` are retried, so a real error is never buried |
| Distribution | polls until content actually reaches the distribution points, with a timeout |
| Audit | per-job folder on the server with a log and `job.json`, keyed by job ID and RFC, naming only the service account |
| Privacy | **no person's name reaches the SCCM side** - not an object, not the log, not the job record, not the result |
| Concurrency | a package lock stops two packagers integrating the same package at once |
| Transport | job and result files, XSD-validated both ways; a half-written file can never be collected |

Two rules the design holds to:

**Nothing about ICZ, INA or PCZ appears in the code.** A fourth environment is one
new XML file.

**No rule lives in code either.** How a package name splits, how the branding key
is composed, which patterns read a PSADT script or an instruction document, how
many retries, what counts as transient, how long to wait for content - all
declared in `Defaults.xml`.

---

## Tests

`.\Tests\Invoke-AllTests.ps1` - **419 checks, none needing SCCM.** Several exist
because the tool being replaced got them wrong:

- `ADO_ADOBE_Reader_x64_...` must survive intact - the old text replacement turned
  it into `INA_INABE_Reader_x64_...`
- a product name containing the separator (`Visual_Studio_Code`) must still parse
- exactly one collection carries the `Uninstall` deployment, and it must be
  `_RemoveComputer` - the old tool paired deployments to collections by position
- no two environments may share a content share or a security scope
- a deliberately broken config file must be **rejected**
- a failed run must report failure - the old tool always showed `"Done."`
- **nothing the server writes may name a person** - checked against the real log,
  `job.json` and result file, not just the code that writes them
- a config file trying to reintroduce `{requester}` must be rejected
- a job with no RFC must be refused
- a result must still be readable after the window is closed and reopened

---

## Open items

**PCZ is `verified="false"`.** Four of its values are copies of INA's and a fifth
was never set. A real run is refused until Audi confirms them; a dry run still
works so the plan can be reviewed. Details in `Config\Environments\PCZ.xml`.

**Service accounts and groups are placeholders** in the environment files until
the AD team creates them. Testing values are set to a local folder and the
signed-in user on purpose.

**Instruction-document patterns are calibrated against one real form**
(`INA_ETAS_INCA`). A form laid out differently may leave the descriptions blank
until the patterns in `Defaults.xml` are adjusted - a config edit, not a code
change. Everything else comes from the deployment script, which does not vary.

**The live provider is unproven.** The ConfigMgr commands and the ARS SOAP calls
are written but have never touched a real site or directory. That is the ICZ run,
and it is the one thing the tests here cannot cover.
