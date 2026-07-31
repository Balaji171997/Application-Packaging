# Audi SCCM Integration Tool

Replacement for Audi's **EQS SW Integration Tool 1.0.3**, built so that all SCCM
and Active Directory work is carried out by a **shared service account** instead
of each packager's personal administrator account.

For the full deployment detail — firewall, registration, permissions and the
security review answers — see **[DEPLOYMENT.md](DEPLOYMENT.md)**.

---

## Where everything lives

The folders are split by **where the files end up**.

```
AudiSwIntegration\
│
├── Server\          →  goes ON the SCCM server, in the secure zone
│   ├── Engine\                     the tool itself
│   │   ├── AudiSwIntegration.ps1     entry point
│   │   ├── Src\                      Config.ps1  Runtime.ps1  Sccm.ps1
│   │   └── Config\                   the ONLY files an admin edits
│   │       ├── Environment.xsd         schema everything is checked against
│   │       ├── Defaults.xml            what is identical in all environments
│   │       └── Environments\           ICZ.xml  INA.xml  PCZ.xml
│   │
│   ├── Endpoint\                   definition of the "counter"   (option A)
│   │   ├── AudiSwIntegration.pssc    who may connect, who does the work
│   │   └── AudiSwIntegration.psrc    the only commands that exist
│   │
│   ├── Install-AudiSwEndpoint.ps1     registers the counter      (option A)
│   ├── Install-AudiSwDropWatcher.ps1  creates the scheduled task (option B)
│   └── Watch-AudiSwDropFolder.ps1     collects jobs from the folder (option B)
│
├── Client\          →  goes on a SHARE, packagers get a shortcut
│   ├── Start-AudiSwClient.ps1        the packager window
│   └── MainWindow.xaml               its layout
│
└── Tests\           →  stays with US. Never deployed anywhere.
    ├── Test-Config.ps1   Test-Sccm.ps1   Invoke-AllTests.ps1
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

> **While testing:** the window currently loads the engine directly so it can run
> against the dry-run provider with no server at all. Once the endpoint exists it
> calls the server instead — the window itself does not change.

---

## Running it

```powershell
# open the packager window - dry run is ON by default, nothing is changed
.\Client\Start-AudiSwClient.ps1

# if launching from a plain console, WPF needs -STA
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Client\Start-AudiSwClient.ps1

# all 132 tests - no SCCM, no network, no rights needed
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
.\Server\Install-AudiSwEndpoint.ps1    -Gmsa '...' -OperatorGroup '...' -WhatIf   # option A
.\Server\Install-AudiSwDropWatcher.ps1 -Gmsa '...' -DropFolder '...'    -WhatIf   # option B
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
| Audit | per-job folder with a log and `job.json` naming **requester** and **executor** |
| Concurrency | a package lock stops two operators integrating the same package at once |

## Tests

`.\Tests\Invoke-AllTests.ps1` — 132 checks, none needing SCCM. Several guard
against defects in the tool being replaced:

- `ADO_ADOBE_Reader_x64_...` must survive intact — the old text replacement turned
  it into `INA_INABE_Reader_x64_...`
- a product name containing the separator (`Visual_Studio_Code`) must still parse
- exactly one collection carries the `Uninstall` deployment, and it must be
  `_RemoveComputer`; the old tool paired deployments to collections by position
- no two environments may share a content share or a security scope
- a deliberately broken config file must be **rejected**
- a failed run must report failure — the old tool always showed `"Done."`

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
