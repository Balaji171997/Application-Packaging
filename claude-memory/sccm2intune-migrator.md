---
name: sccm2intune-migrator
description: Downloads\SCCM2IntuneMigrator - one script replacing the 4 MAN_SCCM2IntuneMgrationTool variants; brand-neutral profiles in settings.json
metadata: 
  node_type: memory
  type: project
  originSessionId: 17ecde68-9c5a-4b15-9bb0-b493baf39602
  modified: 2026-08-13T13:39:15.710Z
---

Built 2026-08-07. `C:\Users\AW140\Downloads\SCCM2IntuneMigrator\SCCM2IntuneMigrator.ps1` — ONE
script replacing the four `MAN_SCCM2IntuneMgrationTool_*.ps1` variants in
`Downloads\SCCM2Intune Migration Tool` (that old folder is the reference, left untouched).
PreLive is NOT a separate script — it is a profile.

What used to be a separate FILE is now detected per application: PSADT v3-vs-v4 from the launcher
on the share (v3 → stage ServiceUI + Deploy-Application into the LOCAL copy, never the source),
branding-key synthesis when SCCM has no detection clause, icon fallback chain, description chain.

**Hard requirements the user stated** (don't re-litigate):
- UAT group format `MDM_MN_SWW_<vendor>_<appname>_UAT`, no spaces or special characters → every
  token stripped to `[A-Za-z0-9]`. **The tool must NOT create the group** — just put the name in
  the report; assign only if that group already exists.
- **Assignment intent is ALWAYS `available`** — no dropdown, no setting to choose.
- Don't put fixed decisions (intent, group mode, group pattern) in the UI at all.
- The UI must NOT copy the old tool's layout. Current: dark header + status pill, connection card
  that collapses after Connect, ONE grid with tick boxes + live Status/Result columns (MigAppRow
  C# class with INotifyPropertyChanged), collapsible activity log, single accented Migrate button.
- No `_TemplateForAnotherBrand` block — a team just adds a normal profile.
- Another team may use a **different deployment toolkit** → `Launchers` list in settings.json
  (Marker / SetupFile / InstallCmd / UninstallCmd / StageUtilities). No PSADT knowledge in code.

**The THREE content scenarios** (user spelled these out; the .intunewin is always built from the
folder holding the launcher/executable):
1. `Invoke-AppDeployToolkit.exe` → wrap directly, copy NOTHING in.
2. `Deploy-Application.exe` → copy/REPLACE ServiceUI.exe + Deploy-Application.exe + .exe.config.
3. Neither (plain setup.exe/.msi) → wrap the folder holding the file **SCCM's own install command
   runs**, copy ONLY ServiceUI.exe. Never drop a toolkit exe into a non-toolkit package.
   Unknown case → fail that app with a plain reason.

**Commands come from SCCM for ALL THREE**, not from config — the deployment type is the record of
how the app really installs. Config commands are only a fallback when SCCM has none. Cases 2 and 3
get the Package Builder ServiceUI wrap verbatim: unquote a leading `"X.exe"`, prefix
`.\ServiceUI.exe -process:explorer.exe ` (see PB's `ConvertTo-IntuneV3Command`). Launcher flag
`WrapServiceUI` (defaults to `StageUtilities`) controls it; v4 = no wrap.

**Icon/description search scope**: SCCM content path points at/near the EXECUTABLE; `Icons\` and
the request .docx sit at the PACKAGE root 1-2 levels up. Climb at most IconSearchUpLevels /
DocSearchUpLevels (2) and STOP at the folder named after the package — never leave the package.
No package name known → don't climb at all. Description accepts English OR German, short OR
detailed, whatever is filled (German placeholders like "Klick hier um Text einzugeben" rejected).

PreLive needs NO separate ConfigMgr module — user confirmed site code + server is enough (unlike
Package Builder, which ships ConfigurationManagerPrelive).
- Must be reusable for **another brand** and the script must **not name any brand**. All
  org-specific values (site code/server, tenant, BrandingKeyRoot, name format, group pattern) live
  in `settings.json` as named profiles (`ActiveProfile` / `Common` / `Profiles`), resolution
  defaults ← Common ← profile. Rebrand = new profile + swap `Assets\DefaultAppIcon.png`.
- Flexible package-name format via `PackageNameRegex` (named groups Vendor/AppName/Arch/Version/
  Revision/Lang), falling back to the underscore split.
- The 30 GB abort is GONE — reuses Package Builder's chunked Azure block upload with SAS renewal
  and per-block resume (see [[intune-detectionrules-array]] for the sibling Graph gotcha).
- Rollback per failed app (assignment → app → group, group only if THIS run created it);
  `RollbackScope` also offers FailedAppAndStop / WholeBatch.

**Duplicate / version handling** (mirrors Package Builder's "ask the user", but batch-friendly):
a PRE-FLIGHT runs before anything is created and finds ANY version already in Intune, then ONE
review dialog lets the operator decide per app — same version → skip (default) or duplicate;
older version → migrate + **supersede** (default, `POST mobileApps/{new}/updateRelationships`,
`mobileAppSupersedence`/`update`) or skip; newer version → skip (default) or migrate. Lifecycle
shown from the existing app's Notes JSON. Cancel = tenant untouched.

**WORDING MATTERS to the user**: never a bare "already in Intune". Situation reads
`SAME|HIGHER|LOWER version (vX) already in Intune`, exactly TWO choices per case
(`Skip - do not migrate` / `Continue - migrate anyway`, or `Add supersedence - …` / `Skip - …`),
and that same sentence becomes the note in the report AND the tool's Result column
(`Skipped - HIGHER version (v2.0.0) already in Intune.`). Row-building and decision-mapping are
`New-MigReviewRows` / `Get-MigReviewDecision` — kept OUT of the dialog so they're testable.
The "What to do" column is a DataGridTemplateColumn (a DataGridComboBoxColumn looks like flat
text until the cell enters edit mode).

**PB parity**: every function of PB's Intune.ps1 is covered EXCEPT Update-IntuneContent/Icon/
Detection and Remove-IntuneGroupAssignment (post-create edits — not a migrator's job). The
uninstall-signature shield (Get/Test/Find-MigUninstallMatches) IS ported: matches the same product
already in Intune under another team's name via uninstall key+version+hive or ProductCode; a
NON-branded match stops that app. Runs just before create; apps already decided in the review
dialog are exempt. `UninstallSignatureShield: false` disables.

**Another brand with no lifecycle**: `Get-MigAppLifecycle` → 'unknown', review dialog then shows
`v4.1.0` with NO bracket and the footer says so. All decisions are version-based, not
lifecycle-based, so nothing breaks. `NotesFormat: 'Text'` writes plain-sentence notes instead of
JSON for brands that don't use the lifecycle schema. UAT group format is just
`UatGroupNamePattern` per profile — README has a full "onboarding another brand" table.

**Report is HTML ONLY** (no CSV/JSON — user asked). Columns: Application, Status, Intune app
(+portal link), UAT group, Install case, Icon, Description, Size, one short Note. Failures first.
No publisher/version, no detection column, no "TO CREATE" warning. Verbose detail lives in the
per-app log. Double-click a row in the tool to open that app in Intune.

Tool now lives at `Downloads\Application-Packaging\SCCM2IntuneMigrator` (user moved it).

**Duplicate-guard bug (fixed, don't reintroduce)**: `Start-MigrationRun` used to set a RUN-WIDE
`DuplicateAction='Create'` "because the review dialog already decided". That neutered the per-app
safety net, so migrating the same app a second time created a duplicate with only a log warning.
The decision must be PER APP, driven by `$script:ReviewedApps` — create a second copy only if that
app actually appeared in the review dialog and the operator chose Continue; otherwise SKIP.

Also: the window now has a `$Win.Dispatcher.Add_UnhandledException` net — a handler/timer error
used to escape the pump, surface as `Exception calling "ShowDialog"` and kill the window, losing
the reason. It now logs the real exception and keeps the window open.

Tests: `Tests\Run-Tests.ps1` (`-STA`), 410 offline checks, SCCM + Graph stubbed, nothing created
anywhere. Run it after any change. `Tests\Render-Ui`-style RenderTargetBitmap screenshots are the
way to actually LOOK at the window without a human — do that before claiming a UI is good.

Module discovery bug worth remembering: `Resolve-MigPath 'a', (Resolve-MigPath 'b')` passes ONE
array as a single parameter, so the search silently looked nowhere and reported "MSAL.PS and
IntuneWin32App were not found" while they sat in `Lib\PowerShell Module`. See
[[ps51-collection-and-path-traps]].
