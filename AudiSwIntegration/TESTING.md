# How to test this

There is no sandbox and no simulator. These are the real scripts, run against
real folders on this PC. Only two things are stand-ins for now, and both are
plain config:

| | While testing | Later |
|---|---|---|
| Drop folder | `C:\AudiSwIntegration\DropFolder\<ENV>` | the share on the Script Runner |
| Content share | the real SCCM store, already set in every environment file. It MUST be UNC - SCCM refuses a local path | unchanged |
| Account | your own user | the gMSA |

**SCCM is bypassed by the Dry run tick**, which is on by default. Every step runs
and reports, nothing touches a site. That is how to test the whole flow without
SCCM.

---

## A. The flow, end to end

You need two PowerShell windows: one for the packager, one standing in for the
Script Runner.

### Window 1 - the collector (this is the Script Runner)

```powershell
cd <tool folder>
while ($true) {
    .\Server\Watch-AudiSwDropFolder.ps1 -DropFolder C:\AudiSwIntegration\DropFolder\INA -Verbose
    Start-Sleep -Seconds 5
}
```

Leave it running. This is the real collector script - the same one the scheduled
task will run on the server. Change `INA` to whichever environment you are
testing.

### Window 2 - the packager

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Client\Start-AudiSwClient.ps1
```

Then:

1. **Browse** to a package - for example `C:\temp\INA_ETAS_INCA_x64_7.5.7-0001_MUL`.
2. Press **Read details**. Everything fills in from the deployment script, the
   description comes from the request document, and **the Environment dropdown
   moves itself to INA** because the package name says so.
3. **Change anything you like.** Every field is editable now. Correct the
   revision, the branding key, the SoftIdent, the descriptions - whatever the
   packager needs. What you leave on the screen is what the server uses.
4. Check the **RFC number**. It is filled from `VWG_OrderNumber` in the script.
   It is required.
5. Leave **Dry run** ticked and press **Integrate**.
6. Watch window 1 pick the job up within five seconds and run it.
7. The result appears in section 4 of the window - eight steps, each saying what
   it did.

### What to try next

- **Preview on this PC** - the same eight steps, run locally, nothing written to
  the drop folder at all. Useful for checking a package before queueing it.
- **Change the Environment to the wrong one on purpose.** The strip turns amber
  and Integrate refuses: *"This package is named for INA but ICZ is selected."*
  Nothing is submitted and nothing is renamed.
- **Clear the RFC** and press Integrate. It refuses and says why.
- **Modify** - submit an Integrate first, then press Modify. It reports what it
  would add, change or retire rather than creating a second application.
- **Remove** - needs only the package name and the RFC. No package folder.
- Look in `C:\AudiSwIntegration\DropFolder\INA\Done` - the job file and the
  result file are both there, and neither names a person.
- **Close the window, reopen it, and type the same package name.** The Result tab
  shows the run you just did, read straight back out of `\Done`. This is what a
  packager gets the next morning for a job that was still queued when they left.

### Without opening the window

```powershell
.\Tests\Invoke-AllTests.ps1                    # 378 checks, no SCCM, no rights
.\Client\Start-AudiSwClient.ps1 -SelfTest      # drives the window's own code, no screen
```

The self test reads a real package and prints **every field the window shows**,
so you can see at a glance whether anything came through empty.

---
## B. On the machine with the SCCM console - ICZ

Same window, same collector, same temporary folders. The only difference is that
you untick **Dry run** at the end, and then it talks to ICZ for real.

### B0. Before you start

- The **ConfigMgr console must be installed** on that machine. The tool loads its
  PowerShell module from `$env:SMS_ADMIN_UI_PATH`. No console, no integration.
- **Copy the package to the content share yourself.** The tool never copies -
  see the note below. Put it where `ICZ.xml` says `Content share` points.
- Copy the whole tool folder across, then set the three testing values in
  `Server\Engine\Config\Environments\ICZ.xml`:

```xml
<Runner   host="<that machine>"/>
<Service  account="<your user>" allowedGroup="<your user>"/>
<Transport mode="DropFolder" dropFolder="C:\AudiSwIntegration\DropFolder\ICZ" resultTimeoutMinutes="30"/>
<Content  share="<the real ICZ content share>" distributionPointGroup="Test"/>
```

### B0a. If the test machine is a different site

The test site is not ICZ - it is site **II1** on **AUDIINSA1299.audi.vwg5t**.
That is `Config\Environments\II1.xml`: everything is ICZ's except the site code,
the server and the drop folder.

Three things follow, and getting any of them wrong is what makes a job sit there
untouched:

1. **Name the package `II1_...`** - rename the folder under the content share and
   type the matching name in the window. Packages are named for the environment
   they go into and preflight refuses a mismatch, which is what stops a package
   being built on the wrong site.
2. **Select II1 in the dropdown.** With an `II1_` package it selects itself. With
   a package still named `ICZ_` or `INA_` the dropdown will move *itself* to that
   environment when you press Read details, and the job goes to that
   environment's folder.
3. **Point the collector at II1's folder:**
   `-DropFolder C:\AudiSwIntegration\DropFolder\II1`

One folder serves one environment. A job that lands in the wrong one is now
refused rather than run - the result says which environment it was for and which
folder it was found in.

**Delete `II1.xml` once testing moves to the real ICZ site.**

### B1. Does it reach the site? (creates nothing)

```powershell
. .\Server\Engine\AudiSwIntegration.ps1
$plan = Get-AudiIntegrationPlan -PackageName 'ICZ_ETAS_INCA_x64_7.5.7-0001_MUL' -EnvironmentCode 'ICZ' -Rfc 'AES-1-020627-A'
Connect-AudiSccm -Plan $plan
```

Expect `Connected to ICZ on AUDIINSA1298.audi.vwg5t.` If it fails it says why -
console missing, name not resolving, or no rights.

### B2. Preflight against the real site (reads only)

```powershell
Test-AudiSwPrerequisite -Plan $plan -Provider (New-AudiSccmProvider) | Select-Object -ExpandProperty Findings | Format-Table Check, Ok, Message -AutoSize
```

This is the first thing that touches SCCM, and it only reads. It checks the
content path exists, the application name is free, and that the limiting
collections, the distribution point group and the security scopes are real.
**Fix everything it reports before going on.**

### B3. The full flow, still changing nothing

Two windows, exactly as in section A, but with `ICZ`:

```powershell
# window 1
while ($true) { .\Server\Watch-AudiSwDropFolder.ps1 -DropFolder C:\AudiSwIntegration\DropFolder\ICZ -Verbose; Start-Sleep 5 }

# window 2
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Client\Start-AudiSwClient.ps1
```

Browse to the package, Read details, leave **Dry run ticked**, Integrate. Eight
steps, nothing created.

### B4. The real one

Same again with **Dry run unticked**. Then check in the console:

| | Expect |
|---|---|
| Application | `ICZ_ETAS_INCA_x64_7.5.7-0001_MUL`, **Owner = the account in ICZ.xml** |
| Localised name | English **and German** both filled |
| Deployment type | `..._INSTALLCOMPUTER`, install and uninstall commands, content location |
| Detection rules | **two, both required** - `HKLM\Software\VWG\CM\ETAS_INCA_x64_7.5.7-0001_MUL` `Revision`=`0001`, and `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\INCA7.5.7` `DisplayVersion`=`7.5.7` |
| Requirements | Windows 10 and Windows 11 |
| Deployment type settings | Hidden, Install for system, Whether or not a user is logged on, 120 min, download on slow network, no branch cache, fallback allowed, not 32-bit |
| Category | Development |
| Content | distributed to the `Test` DP group |
| Collections | 4, each under its limiting collection, commented with the job ID and RFC |
| Deployments | 4 - three Available, `_RemoveComputer` **Uninstall** |
| Security scopes | ICZ00001, ICZ00002, ICZ00005, ICZ00006 |
| Folders | app in `\Software Library\...\Applications\ICZ-Applications`; collections in `\Assets and Compliance\...\Device Collections\II1-Site\` and `\SCCM-Manager\`. Missing folders are created |
| AD group | **none** - the step reports SKIPPED. Switched off in `Defaults.xml` (`Steps/@createArsGroup`) until the ARS attributes are agreed |

Then **Modify** (change the revision first and watch the detection rule follow),
and finally **Remove** to put ICZ back as you found it.

### B5. Things that will only show up here

These have never run against a site. If something breaks, it will be one of
these, and the message will say which step:

- `New-CMDetectionClauseRegistryKeyValue` - the two detection rules, and replacing them on Modify
- `New-CMRequirementRuleOperatingSystemValue` - the OS requirements
- the German display entry, written through `SDMPackageXML`
- the ARS/SPML call that creates the AD group - SWITCHED OFF, it fails with "malformedRequest: some of the specified attributes for the group object class are not defined in the schema"
- `Move-CMObject` and `New-CMFolder` - filing into the console folders, and creating any that are missing
- everything else on the site, in fact: no ConfigMgr cmdlet runs unless the
  current location IS the `<SITE>:` drive. The tool steps into it on connect and
  back onto the filesystem before it touches a file

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

## Two things to know before the real run

**The tool never copies content.** It only checks that the package is already on
the content share, and refuses to create anything if it is not:

> The package source was not found at `<share>\<package>`. Copy the package to
> the content share first.

That matches the tool being replaced, which also expected the content to be in
place. Copying it there stays a manual step - say the word if it should become
part of the job.

**The window will not always get an immediate result.** On this PC the collector
runs every five seconds, so the answer comes straight back. On the real Script
Runner the scheduled task runs every few minutes, so the window waits - the
progress bar goes indeterminate and the step line counts the minutes against
`resultTimeoutMinutes` (30 by default, in the environment file).

If the packager closes the window before the result arrives, **the job still
runs** and the result file is still written to `\Done` or `\Failed`. Reopen the
tool, type or browse to the same package, and the **Result** tab fills itself in
from the drop folder: the *Earlier run* strip gives the date, the outcome and the
message, the grid below gives the steps, and the strip's tooltip lists every
earlier run of that package. So fire and forget works - submit, close the window,
come back tomorrow and ask again.

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
- **The document patterns are calibrated against one real form** (INA_ETAS_INCA).
  A form laid out differently may leave the descriptions blank until the patterns
  in `Defaults.xml` are adjusted - a config edit, not a code change. Everything
  else comes from the deployment script, which does not vary.
- **The live SCCM and ARS calls have never run.** Everything testable without a
  site is tested; B3 onwards is the first time real calls happen.
- **On a display shorter than about 800 px the page scrolls.** Nothing is lost,
  but everything fits at once from roughly 1500 x 940 upwards.
