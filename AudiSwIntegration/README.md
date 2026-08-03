# Audi SCCM Integration Tool

Replacement for Audi's **EQS SW Integration Tool 1.0.3**, built so that all SCCM
and Active Directory work is carried out by a **shared service account** instead
of each packager's personal administrator account.

For the full deployment detail — accounts, permissions, the drop folder, the
privacy rule and the security review answers — see **[DEPLOYMENT.md](DEPLOYMENT.md)**.

---

## Where everything lives

The folders are split by **where the files end up**.

```
AudiSwIntegration\
│
├── Server\          →  goes ON the SCCM server, in the secure zone
│   ├── Engine\                     the tool itself
│   │   ├── AudiSwIntegration.ps1     entry point
│   │   ├── Src\                      Config.ps1  Runtime.ps1  Transport.ps1  Sccm.ps1
│   │   └── Config\                   the ONLY files an admin edits
│   │       ├── Environment.xsd         schema everything is checked against
│   │       ├── Defaults.xml            what is identical in all environments
│   │       └── Environments\           ICZ.xml  INA.xml  PCZ.xml
│   │
│   ├── Install-AudiSwDropWatcher.ps1  creates the scheduled task, once
│   ├── Watch-AudiSwDropFolder.ps1     collects jobs from the drop folder
│   │
│   └── _NotUsed-LiveConnection\    the live-connection option we are NOT building
│       ├── Install-AudiSwEndpoint.ps1
│       └── Endpoint\                 .pssc / .psrc
│
├── Client\          →  goes on a SHARE, packagers get a shortcut
│   ├── Start-AudiSwClient.ps1        the packager window
│   └── MainWindow.xaml               its layout
│
└── Tests\           →  stays with US. Never deployed anywhere.
    ├── Test-Config.ps1   Test-Sccm.ps1   Test-Transport.ps1   Invoke-AllTests.ps1
```

### Server or client — the short version

| | Server | Client |
|---|---|---|
| The engine that talks to SCCM | ✔ | |
| All environment settings and secrets-adjacent values | ✔ | |
| The service account identity | ✔ | |
| The packager window | | ✔ |
| Needs the SCCM console | ✔ | ✖ |
| Needs admin rights | ✖ | ✖ |

**Nothing about the environments sits on a packager's PC.** Site servers, share
paths, scope IDs and collection IDs all live in `Server\Engine\Config`, in the
secure zone. A config change therefore never means redistributing the client.

### How the window reaches the server — the drop folder, and nothing else

Audi is going with the **drop folder**. The window never connects to the SCCM
server, and the server never accepts a connection.

```
packager's PC                    a plain file share                the SCCM server
┌───────────────────┐            ┌────────────────────┐           ┌──────────────────┐
│ packager window   │  writes a  │  \New              │  reads    │ scheduled task   │
│ no SCCM rights    │ ─ file ──▶ │  \Working          │ ◀──────── │ runs as the      │
│ no SCCM console   │            │  \Done  \Failed    │ ─ writes  │ service account  │
│ waits for a file  │ ◀───────── │  <job>.result.xml  │  result ▶ │ does all the work│
└───────────────────┘            └────────────────────┘           └──────────────────┘
```

Two consequences worth stating plainly:

- **No firewall rule and no inbound port.** Traffic goes to a file share both
  sides already reach. Nothing is opened into the secure zone.
- **No person reaches the server at all.** The job file carries no user name,
  and the server does not work one out either — it does not read the file's
  owner. Every record on the SCCM side is keyed by **job ID and RFC number**.
  The link from RFC to person lives in Audi's change system, where it belongs.

The live-connection option (a WinRM/JEA endpoint on the site server) was
designed and costed but is **not** being built. Its scripts are parked under
`Server\_NotUsed-LiveConnection\` so nobody installs them by mistake.

> **Testing without any of this:** the window's **Preview on this PC** button
> runs the whole plan locally through the dry-run provider. No server, no share,
> no rights. **Integrate** and **Remove** are the ones that use the drop folder.

---

## Running it

```powershell
# open the packager window - dry run is ON by default, nothing is changed
.\Client\Start-AudiSwClient.ps1

# if launching from a plain console, WPF needs -STA
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Client\Start-AudiSwClient.ps1

# all 185 tests - no SCCM, no network, no rights needed
.\Tests\Invoke-AllTests.ps1

# check the window's wiring without opening it
.\Client\Start-AudiSwClient.ps1 -SelfTest
```

From the console instead of the window:

```powershell
. .\Server\Engine\AudiSwIntegration.ps1

$plan = Get-AudiIntegrationPlan -PackageName 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0003_MUL' -EnvironmentCode 'INA'
Invoke-AudiSwIntegration -Plan $plan -DryRun     # preview, changes nothing
Invoke-AudiSwIntegration -Plan $plan             # real run
Invoke-AudiSwRemoval     -Plan $plan -DryRun

Read-AudiPackageDetail   -PackagePath 'D:\Packages\INA_ADOBE_...'
Test-AudiSwPrerequisite  -Plan $plan -Provider (New-AudiSccmProvider)
```

On the server, once (see DEPLOYMENT.md for the parameters):

```powershell
.\Server\Install-AudiSwDropWatcher.ps1 -Gmsa '...' -DropFolder '\\server\SwIntegration-Inbox$' -WhatIf
```

To see what the collector would do — no scheduled task, no SCCM, nothing changed:

```powershell
.\Server\Watch-AudiSwDropFolder.ps1 -DropFolder '\\server\SwIntegration-Inbox$' -DryRun -Verbose
```

---

## The two rules the design holds to

**One tool, one build.** Nothing about ICZ, INA or PCZ appears anywhere in the
code. Adding a fourth environment is one new XML file — no rebuild, no release.

**No rule lives in code either.** How a package name splits, how the branding key
is composed, which patterns read a PSADT script or an instruction document, how
many times to retry, what counts as a transient fault, how long to wait for
content distribution — all declared in `Defaults.xml`.

## What it does

| Area | Detail |
|---|---|
| Config | XSD-validated; a bad file is rejected before anything runs |
| Package reading | fills the window from the package's own PSADT script and instruction document; each value records where it came from |
| Plan | expands package + environment into the exact list of objects, contacting nothing |
| Preflight | verifies source path, name clashes, limiting collections, DP group and scopes **before** creating anything |
| Engine | eight integration and four removal operations, order enforced by declared dependencies |
| Failure | the real error is reported; a failed run rolls back what it created, newest first |
| Retry | only faults matching `TransientErrors` are retried, so a real error is not buried |
| Distribution | polls until content actually reaches the distribution points, with a timeout |
| Audit | per-job folder on the server with a log and `job.json`, keyed by **job ID** and **RFC**, naming only the service account |
| Privacy | **no real person's name reaches the SCCM side** — not an SCCM object, not the log, not the job record, not the result file |
| RFC | required by default, because with no name kept it is the only route back to the requester |
| Concurrency | a package lock stops two operators integrating the same package at once |
| Transport | job and result files, XSD-validated both ways; a half-written file can never be collected |
| Identity | one identity only: the shared service account. The plan has no requester field for anything to log |

## Tests

`.\Tests\Invoke-AllTests.ps1` — 185 checks, none needing SCCM. Several guard
against defects in the tool being replaced:

- `ADO_ADOBE_Reader_x64_...` must survive intact — the old text replacement turned
  it into `INA_INABE_Reader_x64_...`
- a product name containing the separator (`Visual_Studio_Code`) must still parse
- exactly one collection carries the `Uninstall` deployment, and it must be
  `_RemoveComputer`; the old tool paired deployments to collections by position
- no two environments may share a content share or a security scope
- a deliberately broken config file must be **rejected**
- a failed run must report failure — the old tool always showed `"Done."`
- **nothing the server writes may name a person** — checked on the real log,
  `job.json` and result file, not just on the code that writes them
- a config file that tries to reintroduce `{requester}` must be rejected
- a job with no RFC must be refused, since the RFC is the only audit link left

## Open items

**PCZ is `verified="false"`.** Four of its values are copies of INA's and a fifth
was never set. A real run is refused until Audi confirms them; a dry run still
works so the plan can be reviewed. Details in `Config\Environments\PCZ.xml`.

**Service accounts and groups are placeholders** in the environment files until
the AD team creates them.

**Instruction document patterns are not calibrated.** Audi uses the same format as
the GPF packages, so the `<Document>` patterns in `Defaults.xml` are to be tuned
against a real GPF instruction document.

**The live provider is unproven.** The ConfigMgr commands and the ARS SOAP calls
are written but have never touched a real site or directory — that is the ICZ run,
and it is the only part a test here cannot cover.
