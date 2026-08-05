# How to test this

Two ways, depending on what you have access to.

| | Needs | Proves |
|---|---|---|
| **A. Sandbox** | nothing at all | the window, reading a package, and the whole job round trip |
| **B. Test server (ICZ)** | the ICZ SCCM server + an account | that it really creates objects in SCCM |

Start with A. It takes one command and needs no rights, no server and no SCCM.

---

## A. Sandbox — on any Windows PC

```powershell
.\Tools\Start-AudiSwSandbox.ps1
```

That one command:

1. makes a drop folder under `%LOCALAPPDATA%\AudiSwSandbox`
2. builds a sample package to read (a real PSADT v4 script and a real `.docx`)
3. starts the collector in the background — this stands in for the scheduled task
   on the Script Runner
4. opens the packager window, pointed at that folder

The window shows an amber **SANDBOX** badge so a test can never be mistaken for a
real run.

### What to try

1. **Browse** to the sample package it printed the path of, then **Read details**.
   Everything on the left fills in, and so do the names, descriptions and the RFC
   number on the right. Hover the grey line under the left column to see which
   value came from which file.
2. Leave **Dry run** ticked and press **Integrate**. The window writes a job file,
   waits, and a few seconds later the result appears in section 4 — eight steps,
   each with what it did.
3. Press **Preview on this PC** instead. Same eight steps, but it runs locally and
   nothing is written to the drop folder at all.
4. Clear the **RFC number** and press Integrate. It refuses, and says why.
5. Look in `%LOCALAPPDATA%\AudiSwSandbox\DropFolder\Done` — the job file and the
   result file are both there.

Close the window to stop the collector. Delete `%LOCALAPPDATA%\AudiSwSandbox` to
start clean.

### Without opening the window at all

```powershell
.\Tests\Invoke-AllTests.ps1                    # 232 checks, no SCCM, no rights
.\Client\Start-AudiSwClient.ps1 -SelfTest      # drives the window's own code, no screen
```

The self test reads a real sample package and prints **every field the window
shows**, so you can see at a glance whether anything came through empty.

---

## B. Test server — ICZ

This is the part that needs someone with access. Nothing below changes any SCCM
setting; the first three steps create nothing at all.

### B1. Does it see the site?

On the machine that will act as the **Script Runner**, with the ConfigMgr console
installed:

```powershell
. .\Server\Engine\AudiSwIntegration.ps1
$plan = Get-AudiIntegrationPlan -PackageName 'ICZ_ADOBE_Acrobat_Reader_x64_2024.1_0003_MUL' -EnvironmentCode 'ICZ' -Rfc 'RFC0000001'
Connect-AudiSccm -Plan $plan
```

Expected: `Connected to ICZ on AUDIINSA1298.audi.vwg5t.`
If it fails it says why — console missing, name not resolving, or no rights.

### B2. What would it do? (still creates nothing)

```powershell
Invoke-AudiSwIntegration -Plan $plan -DryRun
```

Eight steps, all OK, against the dry-run provider.

### B3. Preflight against the real site (reads only)

```powershell
Test-AudiSwPrerequisite -Plan $plan -Provider (New-AudiSccmProvider)
```

This is the first thing that talks to SCCM for real. It only reads: does the
content path exist, is the application name free, do the limiting collections,
the distribution point group and the security scopes exist. Fix whatever it
reports before going further.

### B4. A real run

Put a real test package on the ICZ content share first, then:

```powershell
Invoke-AudiSwIntegration -Plan $plan
```

Then check in the console: 1 application, 1 deployment type, 4 collections,
4 deployments, the security scopes, the folder placement, and the AD group.

Then a **modify** — this is the one to exercise carefully, because it changes an
application that is already live:

```powershell
Invoke-AudiSwModification -Plan $plan -DryRun   # says exactly what it would change
Invoke-AudiSwModification -Plan $plan
```

Worth trying in this order:
1. Run it unchanged — it should report *"Nothing to change"* beyond refreshing the
   definition. It must **not** create a second application.
2. Delete one collection by hand, run modify — it puts that one collection and its
   deployment back, and touches nothing else.
3. Comment a collection out of `Config\Environments\ICZ.xml`, run modify — it
   retires exactly that collection. Check that a collection you made by hand,
   named after the same package, is **not** touched.
4. Bump the package revision (`0003` → `0004`) and run modify — the detection rule
   and content path update, and the content re-distributes.

And the removal:

```powershell
Invoke-AudiSwRemoval -Plan $plan
```

### B5. The collector

```powershell
.\Server\Watch-AudiSwDropFolder.ps1 -DropFolder '\\<server>\SwIntegration-Inbox$' -DryRun -Verbose
```

Runs once against the folder, without a scheduled task and without changing SCCM.
When that looks right, register the task (see `DEPLOYMENT.md` section 3.3).

---

## What a tester should check, and why

| Check | Why it matters |
|---|---|
| The application's **Owner** in SCCM reads the **service account** | this is the point of the project |
| No personal name appears in the console, the log, `job.json` or the result file | Audi's requirement |
| Every object carries the **RFC number** | with no name kept, the RFC is the only route back to a person |
| A job with no RFC is refused | otherwise a change would be untraceable |
| Point the content share at a missing path - it reports the real reason and creates nothing | the old tool always said `"Done."` |
| Stop a run halfway - what it created is rolled back | no half-integrated packages |
| A package named `ADO_ADOBE_...` keeps its name | the old tool corrupted it to `INA_INABE_...` |

---

## Known limits, so they are not reported as bugs

- **PCZ is refused for real runs.** Four of its values are copies of INA's and one
  was never set, so it is marked `verified="false"`. A dry run still works.
- **The German display entry is written but unproven.** Both languages now go
  into SCCM: English through the supported cmdlet, German through the
  application's `SDMPackageXML`, the same route the old tool used. It fails soft
  - if the German entry cannot be written the English one is already in place and
  a warning is logged, rather than the whole integration failing. **Check the
  German name in the console on the first ICZ run.**
- **The instruction-document patterns are not calibrated.** They work on the
  sample, and they are tuned for `Label: value` and `Label <tab> value`. Against a
  real GPF document some fields may come back empty until the patterns in
  `Defaults.xml` are adjusted - that is a config edit, not a code change.
- **The live SCCM and ARS calls have never run.** Everything testable without a
  site is tested; B3 onwards is the first time real calls happen.
- **On a display shorter than about 800 px the page scrolls.** Nothing is lost,
  but everything fits at once from roughly 1500 x 940 upwards.
