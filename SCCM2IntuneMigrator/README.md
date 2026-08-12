# SCCM to Intune migrator

One PowerShell script that migrates SCCM applications into Intune Win32 apps: reads the app from
SCCM, builds the `.intunewin` from the real content location, creates the app, uploads the
content, works out the UAT group each app needs, and reports everything. Several applications per
run, and anything that fails is rolled back so nothing half-created is left behind.

It does **not** create groups — the UAT group name goes in the report so it can be created
afterwards. Assignments it does make are always `available`.

```
SCCM2IntuneMigrator\
  SCCM2IntuneMigrator.ps1     the tool - the ONLY script
  settings.json               every site / tenant / naming value, as named profiles
  Assets\DefaultAppIcon.png   the fallback icon (replace this one file to rebrand)
  Lib\                        ConfigurationManager, MSAL.PS, IntuneWin32App,
                              IntuneWinAppUtil.exe, MahApps assemblies, PSADT v3 utilities
  Tests\                      offline test suite (no SCCM or tenant needed)
```

Run it:

```bash
powershell -STA -ExecutionPolicy Bypass -File "SCCM2IntuneMigrator.ps1"
```

`-STA` matters — it is a WPF window.

---

## It replaces the four old scripts

The old tool had one file per situation. Those differences are now **detected per application**,
so there is one script and no more copies to keep in sync.

| Old file | What it did differently | Now |
|---|---|---|
| `..._Icon.ps1` | baseline | baseline |
| `..._Icon_newPSADT.ps1` | PSADT v4 setup file + commands, no ServiceUI | the toolkit is detected from the content on the share, per app |
| `..._Icon_NoDetection.ps1` | invented a branding key when SCCM had no detection | happens automatically when SCCM has no detection clause |
| `..._Icon_NoDetectionPreLive.ps1` | only a different site code / server | a **profile** in `settings.json` |

PreLive is deliberately still its own thing — here it is just the `PreLive` profile.

---

## What it does per application

**1. Reads SCCM** — name, publisher, version, content location, install experience, run time,
exit codes, icon, detection clauses.

**2. Description** — in this order:

1. the description held in SCCM,
2. otherwise the request form (`.docx`) found **around the content location** — see the search
   scope below. Whatever is actually filled in is taken: **English or German**, **short or
   detailed**, and both when both are there,
3. otherwise a generated sentence, so an app is never created with an empty description.

Unfilled cells (*"Click here to enter text."*, *"Klick hier um Text einzugeben."*, `n/a`, …) count
as empty. The report records which of the three it used, and which label it came from.

**Search scope for both.** The SCCM content location points at (or just below) the executable,
while `Icons\` and the request form normally sit at the **package root** a level or two above it.
So the search starts at the content folder and climbs at most `IconSearchUpLevels` /
`DocSearchUpLevels` (default 2) parents — and stops the moment a folder is named after the
package, because that is the package root. It never leaves the package, so a neighbouring
package's icon or form can never be picked up by mistake. With no package name known it does not
climb at all.

**3. Icon** — in this order:

1. the icon stored in SCCM — decoded, checked that it really is an image, and **converted to PNG**
   if it is not one already (SCCM usually holds `.ico`),
2. otherwise an icon found **around the content location** — see the search scope below (`Icons\`
   first, a `.png` with a matching `.ico` preferred, then `.ico`, then anything else), converted
   to PNG,
3. otherwise `Assets\DefaultAppIcon.png`, and the report says so.

Everything is normalised to a square 256x256 PNG, keeping the aspect ratio and padding
transparent (`NormalizeIconTo256: false` turns that off). PSADT toolkit artwork is skipped — that
is the toolkit's picture, not the product's.

**4. How does this package install?** Three cases, decided per application. The `.intunewin` is
always built from **the folder that holds the launcher or the executable**, never from a level
above it. Whatever gets copied in is copied into the tool's **local copy** — the source share is
never written to. The log states which case it took and why.

| # | What is in the content | `.intunewin` built from | Copied in | ServiceUI wrap |
|---|---|---|---|---|
| 1 | `Invoke-AppDeployToolkit.exe/.ps1` | the folder holding it | **nothing** | no — this toolkit runs directly |
| 2 | `Deploy-Application.exe/.ps1` | the folder holding it | `ServiceUI.exe` + `Deploy-Application.exe` + `.exe.config` (**replaced** with the tool's copies) | yes |
| 3 | neither — a plain `setup.exe` / `.msi` / script | the folder holding the file **SCCM's own install command runs** | `ServiceUI.exe` only | yes |

**The install and uninstall commands come from SCCM in every case.** The deployment type is the
record of how the application is really installed — switches and all — so that is what moves to
Intune. Where the package needs ServiceUI (cases 2 and 3) the command gets exactly the wrap the
packaging tool uses: a leading `"Something.exe"` is unquoted and `.\ServiceUI.exe
-process:explorer.exe ` is prefixed, so a migrated app and a freshly packaged one end up with the
same command line. An already-wrapped command is left alone. Only if the deployment type has no
command at all does the launcher's configured default step in — and the log says so.

```
SCCM:   "Deploy-Application.exe" Install -DeployMode Silent
Intune: .\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Install -DeployMode Silent
```

A toolkit exe is never dropped into a package that does not use one.

**Anything else** — no launcher *and* no usable SCCM command, or a command naming a file that is
not in the content — fails that application with a plain statement of which of those it was.

**A team on a different toolkit adds their own entry** to `Launchers` — marker, setup file,
commands, and whether to stage `UtilitiesPath`. No code change. Before wrapping, every `.exe`
named in the install command is checked to be inside the package, so a missing helper is caught
here rather than on the device.

**5. Detection** — SCCM clauses are mapped to their Graph equivalents: registry (value compare and
key-exists, with the 32/64-bit hive inverted correctly), MSI product code, file/folder existence
and version, and custom scripts. When SCCM has **no** detection clause at all, the branding key
`<BrandingKeyRoot>\<FullName>` `[Revision]` is synthesised and the report flags it. If nothing can
be built the app **fails**, rather than being created undetectable.

**6. Large content** — the old 30 GB abort is gone. The upload is our own chunked Azure block
upload with mid-upload SAS renewal and per-block resume, so a multi-GB app uploads instead of
failing. Above `WarnContentSizeGB` you get a warning, not a stop; `MaxContentSizeGB: 0` = no limit.

**7. UAT group — reported, never created.** The tool works out the name each app should get from
`UatGroupNamePattern` (default `MDM_MN_SWW_{Vendor}_{AppName}_UAT`) and puts it in the report.
Every token is reduced to letters and digits, so the name never contains a space or a special
character (`Contoso G.m.b.H` -> `ContosoGmbH`). It also looks the name up read-only, so the report
carries the object id when the group already exists. It never writes to the directory.

**8. Assignment** — Intune assignments from this tool are **always `available`**; there is nothing
to choose. An app is assigned only when its UAT group already exists. Otherwise the report says
`pending - create <group> and assign`. A failed assignment does **not** bin an app that was
created and uploaded successfully - it is reported as a warning.

---

## Rollback

If an application fails at any point, everything **that application** created is undone in reverse
order: the assignment, then the app. The report then says either *"rolled back, retrying is safe"*
or, when the cleanup itself failed, exactly which object IDs need removing by hand.

`RollbackScope` in `settings.json`:

| Value | Behaviour |
|---|---|
| `FailedAppOnly` *(default)* | roll back the failed app, keep the rest, carry on |
| `FailedAppAndStop` | roll back the failed app, keep earlier successes, stop the batch |
| `WholeBatch` | any failure removes every app this run created |

Groups are never part of a rollback - the tool does not create them, so it has nothing to take back.

### Two duplicate checks

1. **Branding key** — the package this team already migrated (`<BrandingKeyRoot>\<FullName>`).
2. **Uninstall signature** — the same *product* already in Intune under **someone else's name**:
   the same uninstall detection (key path including the 32/64-bit hive, plus the version) or the
   same MSI ProductCode. This is what an out-of-band or another team's copy shares even when the
   display name and branding key are completely different. It runs just before the app is created;
   a match that carries **no** branding key stops that application with the existing app named in
   the report. `UninstallSignatureShield: false` turns it off.

An application you already decided on in the review dialog is not stopped again by check 2 — you
have seen it and chosen.

---

## Several sites and several brands

Nothing organisation-specific is in the `.ps1`. Sites, tenants, key roots, naming formats and
group patterns are **profiles** in `settings.json`:

```json
"ActiveProfile": "Production",
"Common":   { "...shared by every profile..." },
"Profiles": {
  "Production": { "SiteCode": "G1K", "SiteServer": "...", "TenantId": "...",
                  "BrandingKeyRoot": "...", "UatGroupNamePattern": "MDM_MN_SWW_{Vendor}_{AppName}_UAT" },
  "PreLive":    { "SiteCode": "G08", "..." }
}
```

Resolution order: built-in defaults <- `Common` <- the selected profile. Pick the profile in the
dropdown, or run with `-ProfileName <name>`.

### Onboarding another brand — the complete list

Add a block under `Profiles` and set what that team does differently. **Nothing else changes.**

| They do this differently | Set this | Example |
|---|---|---|
| different SCCM site | `SiteCode`, `SiteServer` | `"G09"`, `"srv.corp.local"` |
| different tenant | `TenantId` | `"othertenant.onmicrosoft.com"` |
| **different UAT group format** | `UatGroupNamePattern` | `"GRP-{Vendor}-{AppName}-UAT"` → `GRP-Acme-Widget-UAT` |
| different package-name format | `PackageNameRegex` | named groups `Vendor`/`AppName`/`Version`/… |
| different branding registry key | `BrandingKeyRoot` | `"Software\\Acme\\Apps"` |
| **no branding key at all** | `BrandingKeyRoot: ""` + `SynthesizeBrandingWhenMissing: false` | detection then comes only from SCCM |
| different deployment toolkit | `Launchers` entry | marker + setup file + commands + `StageUtilities` / `WrapServiceUI` |
| **no lifecycle in Notes** | `NotesFormat: "Text"` | writes a plain sentence instead of JSON |
| different fallback icon | replace `Assets\DefaultAppIcon.png` | — |

Group-name tokens are reduced to letters and digits, so any pattern is safe: `GRP-{Vendor}-…`,
`{AppName}_UAT`, `SW_{Vendor}{AppName}_TEST` all work.

**If a brand does not record a lifecycle**, nothing breaks. `Get-MigAppLifecycle` returns
`unknown`, and the review dialog then simply shows the version without a bracket — `v4.1.0`
instead of `v4.1.0 [LIVE]` — and says so underneath. Every other decision (same / older / newer
version, supersedence) is based on the **version**, not the lifecycle, so it all still works. The
lifecycle is extra context when it happens to be there.

If a package name does not follow `<Vendor>_<App>_<Arch>_<Version>-<Rev>_<Lang>`, set
`PackageNameRegex` with named groups `Vendor` / `AppName` / `Arch` / `Version` / `Revision` /
`Lang`. A name matching nothing is reported, not crashed on.

Group-name tokens: `{Vendor}` `{AppName}` `{Arch}` `{Version}` `{Revision}` `{Lang}` `{FullName}`.

---

## Already in Intune, and older / newer versions

Before anything is created, the tool checks every ticked application against Intune and finds
**any version** of it — the same one, an older one, or a newer one. Find nothing and the run just
starts. Find something and **one** dialog opens listing each affected application with the version
that is already there and its lifecycle, and you choose per application:

| Situation shown | Your two choices | Default |
|---|---|---|
| `SAME version (v1.0) already in Intune` | *Skip - do not migrate* / *Continue - migrate anyway* | skip |
| `HIGHER version (v2.0.0) already in Intune` | *Skip - do not migrate* / *Continue - migrate anyway* | skip |
| `LOWER version (v4.1.0) already in Intune` | *Add supersedence - migrate and supersede v4.1.0* / *Skip - do not migrate* | supersede |

The Situation column always **names which case it is** - never a bare "already in Intune" - and
that exact sentence becomes the note in the report AND in the tool's Result column, so a skip
reads `Skipped - HIGHER version (v2.0.0) already in Intune.` rather than something generic.

Nothing has been created at that point, so *Cancel the whole run* leaves the tenant untouched, and
skipping one application does not affect the others. Choosing supersedence makes the new app
supersede the older one as an **update**. If supersedence cannot be set afterwards the app itself
is still fine — that is reported as a warning, not a failure.

Lifecycle (LIVE / UAT / RETIRED …) is read from each existing app's Notes field, so you can see
what you would be displacing.

A dry run skips this check entirely — it creates nothing, so there is nothing to decide.

---

## Reports and evidence

Everything lands under `<ReportRoot>\Run_<timestamp>\`:

```
MigrationReport.html      the report - one row per application
_Batch.log                the whole run
<App>\<App>.log           that application only
<App>\StagedContent\      exactly what was wrapped
<App>\Output\*.intunewin  the built package (kept, so a failed upload can be retried by hand)
<App>\_IntuneWin-manifest.txt
```

The report is deliberately short: **Application, Status, Intune app** (with a link straight to it
in the portal), **UAT group, Install case, Icon, Description, Size**, and one **Note** - the note
being the one thing worth acting on (the failure reason, `already in Intune`, or nothing at all
when it simply worked). Failures are listed first. Everything verbose - publisher, revision,
detection rules, the full messages - stays in the per-application log beside it.

Double-clicking a migrated row **in the tool** opens that app in the Intune portal too.

The app's Notes field is written as JSON including `"lifecycle": "UAT"`, so reporting tools read
the stage instead of showing `unknown`.

---

## Unattended

```bash
powershell -STA -ExecutionPolicy Bypass -File "SCCM2IntuneMigrator.ps1" -NoGui -ProfileName Production -Application "Vendor_App_x64_1.0-0001_MUL"
```

Add `-WhatIfMigration` to read SCCM and build the `.intunewin` while creating **nothing** in
Intune. The window has the same thing as the *Dry run* checkbox.

---

## Permissions

The sign-in needs `DeviceManagementApps.ReadWrite.All`. `Group.Read.All` is used to look a UAT
group up so its object id can go in the report - if it is not granted, the group NAME is still
reported and the run carries on. The tool never writes to the directory: no group is ever created,
renamed or deleted.

The helper modules (MSAL.PS, IntuneWin32App) are searched under `ModulePath`, then
`Lib\PowerShell Module`, `Lib`, `Modules`, the tool root, and finally the modules installed on the
machine. A module on a UNC share is staged to a local cache first, because MSAL.PS compiles C# at
import time and that fails from a remote path.

---

## Tests

`Tests\` runs fully offline — no SCCM, no tenant, nothing created anywhere:

```bash
powershell -STA -ExecutionPolicy Bypass -File "Tests\Run-Tests.ps1"
```

377 checks covering profile resolution, name parsing, group naming, description and icon
fallbacks, all three install cases and where their commands come from, real `.intunewin` builds,
the window and every one of its handlers (ticking, filtering, live status), every rollback path,
and a full multi-application batch — all with SCCM and Graph stubbed.

**Multi-application runs** get their own suite (`Test-MultiApp.ps1`), which proves on an 8-app
batch that applications are processed strictly one at a time in the order ticked; each gets its
own work folder, log, `.intunewin` and App ID; no log leaks another application's name; two
failures in the middle are each rolled back while the other six keep their apps; a cancel stops
cleanly with the rest marked *Not started*; and two SCCM names that sanitise to the same folder
name still get separate folders.

---

## Assumptions worth confirming

Sensible defaults were chosen for these; all three are `settings.json` values you can change.

- **A failure rolls back only that application** (`RollbackScope: FailedAppOnly`); the rest of the
  batch continues.
- **An app is assigned when its UAT group already exists** (`AssignIfGroupExists: true`). Set it
  to `false` to report the group name and never assign.
- **Icons are normalised to 256x256.** The supplied default icon is 2430x1368 — the original
  hard-coded image from the old tool — which renders letterboxed in Intune at its native size.
  Set `NormalizeIconTo256: false` to send images through untouched.
