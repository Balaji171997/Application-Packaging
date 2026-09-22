# How to test this

There is no sandbox and no simulator. These are the real scripts, run against
real folders on this PC. Only two things are stand-ins for now, and both are
plain config:

| | While testing | Later |
|---|---|---|
| Drop folder | `C:\AudiSwIntegration\DropFolder` - ONE root; the window and the collector both put `<ENV>\New` etc. underneath it. Put that root as `DropFolder` in `Packager\Settings.txt` | two roots - one in the packagers' zone, one in the SCCM zone - kept in step by the sync task on the middle server |
| Middle server | not needed on one PC - the window and the collector share the root. To see the middle server work, use two roots (section A2) | the middle server's scheduled task |
| Content share | the real SCCM store, already set in every environment file. It MUST be UNC - SCCM refuses a local path | unchanged |
| Account | your own user | the gMSA (collector) and the sync account (middle server) |

**SCCM is bypassed with `-DryRun`** - on the collector (`Watch-AudiSwDropFolder.ps1
-DryRun`) or on the window (`Start-AudiSwClient.ps1 -DryRun`, which shows TEST
MODE in the header). Every step runs and reports, nothing touches a site. There
is no switch for this in the window itself: a packager's job is always real.

---

## A. The flow, end to end

You need two PowerShell windows: one for the packager, one standing in for the
Script Runner.

### Window 1 - the collector (this is the Script Runner)

```powershell
cd <tool folder>
while ($true) {
    .\SccmServer\Watch-AudiSwDropFolder.ps1 -DropFolder C:\AudiSwIntegration\DropFolder\INA -Verbose
    Start-Sleep -Seconds 5
}
```

Leave it running. This is the real collector script - the same one the scheduled
task will run on the server. `-DropFolder` is **that environment's folder** under
the root (`<root>\INA`), which is how each server's task is pointed in
production - the ICZ server watches `\ICZ`, the INA server `\INA`, and neither
can pick up the other's jobs. Pointed at the root itself it serves every
environment folder underneath, which is handy on one test PC. With `-Verbose`
it names the folders it looked in when there is nothing to collect.

### Window 2 - the packager

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Packager\Start-AudiSwClient.ps1
```

Then:

The window opens dark, on the **Integrate** page, with **no environment
chosen** - the header's ENVIRONMENT box is empty on purpose.

1. **Choose the environment** in the header: `ICZ - Test` or `INA - Production`.
   The package name does NOT decide this: the same `INA_` package goes to ICZ
   first and INA after. Nothing can be submitted until one is chosen.
2. **Browse** to a package - for example `C:\temp\INA_ETAS_INCA_x64_7.5.7-0001_MUL`.
   If the request forms are kept apart from the packages, put that root in
   **Documents location** once (remembered for you; the team default is
   `DocumentsRoot` in `Packager\Settings.txt`). It is looked at only when the package folder
   has no *Software Integration* form: the request's folder is found by the
   AES ID from the script, and the form read from its `Documentation` folder.
3. Press **Read details**. The package name and RFC land in the header; the
   parts, the branding key and the **install title** fill in from the deployment
   script (`InstallTitle`); the descriptions come from the request document. If
   the script closes processes, the description begins *"The following
   applications will be closed for installation: a,b. "* and then the short
   description; if it closes nothing, the short description stands alone. The
   **Windows versions** tick boxes follow the form's operating-system line; what
   is ticked becomes the deployment type's requirement rule, and nothing ticked
   is refused.
4. **Change anything you like.** What you leave on the screen is what the server
   uses. Section 04 shows the ONE detection rule - the branding key - and
   follows the branding key and revision as you edit them.
5. Press **Integrate** and confirm.
6. Watch window 1 pick the job up within five seconds and run it. The window
   jumps to **Jobs** as the run starts.
7. The steps appear on the Jobs page - eight of them, each saying what it did.

### What to try next

- **Clear the RFC** and press Integrate. It refuses and says why (when
  `requireRfc` is on).
- **Modify page** - after an Integrate, press *Read from SCCM*. The settings and
  collections on the site appear; change a setting or tick a collection and
  *Apply changes*. The page updates itself from the server's answer. Machines
  are not here - see the next line.
- **Members page** - press *Read from SCCM*, pick a collection. One list, three
  states: *on site*, *will be added*, *will be removed*. Paste names (one per
  line or comma-separated) and *Add*; select rows and *Remove selected* (or
  *Remove all*); *Keep selected* undoes a removal; *Apply* sends it all,
  confirmed by machine name. The list then updates itself from the server's
  answer - no second Read from SCCM. *Discard changes* forgets everything not
  yet applied.
- **Package content row** (Integrate page) - shows where the content goes:
  `<root>\<ENV>\Sources\<SCCM name>`, beside the job, and whether it is there
  already. *Copy now* puts it there without submitting; Integrate does the same
  by itself and shows "Content copy" as its first step on Jobs. The window never
  touches the SCCM store - the server copies Sources into the store as the job's
  first step, and clears Sources once the job has succeeded (a dry run leaves
  it for the real run).
- **Submit the same package twice.** Press Integrate, then - before the
  collector has picked it up - press it again (or from a second window). The
  second is refused: "A job for … is already QUEUED", and the Jobs page shows
  the one in flight. Stop the collector, drop two job files for one package by
  hand, start it: the older runs, the newer lands in `\Failed` as "Refused as
  a duplicate", naming the job it lost to.
- **Remove page** - the button stays off until you type the package name back.
  Needs only the package name and the RFC in the header. No package folder.
- **Update content** (Integrate page) - for a package already in SCCM whose
  files changed: the package folder is compared with the store file by file
  (size + content hash, never timestamps), only what differs is replaced, and
  the distribution points are told to fetch the change. Nothing else on the
  application is touched. Details, collections and machines of an existing
  application are changed on the Modify and Members pages, not here.
- Look in `C:\AudiSwIntegration\DropFolder\INA\Done` - the job file and the
  result file are both there, and neither names a person.
- **Close the window, reopen it, and type the same package name.** The Jobs page
  shows the run you just did, read straight back out of `\Done`. This is what a
  packager gets the next morning for a job that was still queued when they left.
- **Theme** - the sun/moon button at the foot of the rail. Remembered per user
  under `%LOCALAPPDATA%\AudiSwIntegration`.

### Without opening the window

```powershell
.\Tests\Invoke-AllTests.ps1                    # 826 checks, no SCCM, no rights
.\Packager\Start-AudiSwClient.ps1 -SelfTest      # drives the window's own code, no screen
```

The self test reads a real package and prints **every field the window shows**,
so you can see at a glance whether anything came through empty.

### A2. With the middle server in between

On one PC the window and the collector can share a root, and the sync task is not
needed. To see the whole production road, give them two roots and run the sync task
between them - three windows:

```powershell
# window 1 - the SCCM server, reading ITS root only
while ($true) { .\SccmServer\Watch-AudiSwDropFolder.ps1 -DropFolder C:\AudiSwIntegration\ServerDrop\INA -Verbose; Start-Sleep 5 }

# window 2 - the middle server
while ($true) { .\MiddleServer\Sync-AudiSwDropFolders.ps1 -ClientRoot C:\AudiSwIntegration\DropFolder -ServerRoot C:\AudiSwIntegration\ServerDrop -Verbose; Start-Sleep 5 }
# (in production neither script gets a path on the command line - they read Watcher-Settings.txt / Sync-Settings.txt beside them)

# window 3 - the packager, with DropFolder = C:\AudiSwIntegration\DropFolder in Packager\Settings.txt
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Packager\Start-AudiSwClient.ps1
```

Integrate as before and watch the files travel: `Sources\<pkg>` and the job
leave `DropFolder\INA`, the job's copy waits in `DropFolder\INA\Working` (the
window shows it pending, a second Integrate is refused), the collector runs it
from `ServerDrop\INA`, and the result comes back to `DropFolder\INA\Done`. Stop
window 2 for a minute mid-way - nothing is lost, the next pass carries it. The
sync task never opens a file; `Tests\Test-Transport.ps1` drives this same road with
the real scripts under *Through the middle server*.

---
## B. On the machine with the SCCM console - ICZ

Same window, same collector, same temporary folders. The only difference is that
you start without `-DryRun`, and then it talks to ICZ for real.

### B0. Before you start

- The **ConfigMgr console must be installed** on that machine. The tool loads its
  PowerShell module from `$env:SMS_ADMIN_UI_PATH`. No console, no integration.
- **The collector copies the package into the content share** from the drop
  folder's `Sources\` as the job's first step - so the account running window 1
  needs Modify on `Content/@share` in `ICZ.xml`. The window itself needs
  nothing on the store.
- Copy the whole tool folder across, then set the three testing values in
  `SccmServer\Engine\Config\Environments\ICZ.xml`:

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

1. **Offer II1 in the window.** The header only lists what
   `Config\Defaults.xml` names under `<ClientEnvironments>` - ICZ and INA. On
   the test rig add `<Environment code="II1" label="II1  -  Test site"/>` there
   and run `Update-PackagerLib.ps1`. Take it out again afterwards.
2. **Select II1 in the header.** The package keeps its own name - an `INA_`
   package into II1 is allowed, and nothing is renamed. Preflight only reports
   the prefix; it never refuses on it.
3. **Point the collector at `<root>\II1`** - or at the root, which serves
   every environment folder underneath it as long as the server has `II1.xml`.

One folder serves one environment. A job that lands in the wrong one is now
refused rather than run - the result says which environment it was for and which
folder it was found in.

**Delete `II1.xml` once testing moves to the real ICZ site.**

### B1. Does it reach the site? (creates nothing)

```powershell
. .\SccmServer\Engine\AudiSwIntegration.ps1
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
while ($true) { .\SccmServer\Watch-AudiSwDropFolder.ps1 -DropFolder C:\AudiSwIntegration\DropFolder\ICZ -Verbose; Start-Sleep 5 }

# window 2
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Packager\Start-AudiSwClient.ps1
```

Start the window with `-DryRun`. Browse to the package, Read details, Integrate. Eight
steps, nothing created.

### B4. The real one

Same again, started without `-DryRun`. Then check in the console:

| | Expect |
|---|---|
| Application | `ICZ_ETAS_INCA_x64_7.5.7-0001_MUL`, **Owner = the account in ICZ.xml** |
| Localised name | English **and German** both filled |
| Deployment type | `..._INSTALLCOMPUTER`, install and uninstall commands, content location |
| Detection rule | **exactly one** - `HKLM\Software\VWG\CM\ETAS_INCA_x64_7.5.7-0001_MUL` `Revision`=`0001`. Nothing on the vendor's uninstall key |
| Localised name | the **install title** from the script (`InstallTitle`), not a composed "Publisher - Product - Version" |
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

- `New-CMDetectionClauseRegistryKeyValue` - the branding-key detection rule, and replacing it on Modify
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

**The package content travels with the job.** Before Integrate or Update the
window looks for `<root>\<ENV>\Sources\<package, underscore spelling>`; when it
is not there, the confirmation says so and the package is copied there first,
with progress on the status line:

- a package shaped `Content\ Documents\ Icons\` copies **Content\ only**, so the
  script sits at the top of the folder as SCCM expects;
- a package that already IS the content (script at the top) copies as it is;
- a folder with no deployment script is refused;
- the copy goes into a `~<name>.copying` folder and is renamed into place at
  the end, so a half-copied package never appears under the real name.

The middle server carries Sources before jobs. On the SCCM server the job's first step
copies Sources into the content store under the same name (the same staging
and rename), skips it when the package is already in the store, and refuses a
real Integrate that has neither. Sources is cleared once the job has succeeded.
The server's preflight still checks the store folder is there - it is the last
line, not the first.

**Every share asks for a sign-in when it cannot be opened** - the drop folder,
the documents location, a package on a share. A small
dialog asks for user name and password, up to three times; a stale session to
the same server under another account (the "multiple connections" error) is
cleared and the attempt repeated. Three failures end it with the reason; the
next click asks again. The password lives in memory for the attempt and
nowhere else. Which account the drop folder expects is the packager's own
business - the tool never carries a stored credential.

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
  was never set, so it is marked `verified="false"`. A `-DryRun` run still works.
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
