# Package Builder — Rebuild Plan & Handoff

Single source of truth. Hand to Claude Code/Cowork: "Continue building from this plan."
Goal: a simple, smart, smooth tool to build daily PSADT v4 packages with minimal clicks —
strong predecessor reuse, reliable version/RITM/ProductCode handling, an AvalonEdit editor,
flexible source handling, and a portable launcher the team runs by copying one folder.
Name everywhere: **Package Builder**.

## 0. Current status
DONE & validated:
- Core.ps1 — logging, Parse-PackageName, §1 version swap, safe config loader.
- Predecessor.ps1 — clean model, UTF-16/BOM reading, boilerplate strip (validated on real v3+v4).
- Build.ps1 — §2 uninstall block (both cases), installer/PC swap, MST wrapper.
- Source.ps1 — flexible resolver (validated on 5 messy layouts).
- Editor.ps1 — standalone AvalonEdit editor (confirmed good).
- Tests/Test-Build.ps1 — green.
- v3→v4: Get-InstalledApplication→Get-ADTApplication; Convert-HKCUAllUsers.
- GUI.ps1 — Step 1 + Step 2 live (info, RITM, fetch, detection, ProductCode auto-fill,
  MST checkboxes, ISO warn-and-stop, multi-installer picker).
NOT done (next, in order): SCCM integration, Intune integration, then portable exe (built LAST),
golden tests. Step 4 (Review & Create / assembler) is DONE — see sessions 4-5 and §9.
PARTIAL: Step 3 editor embedded (AvalonEdit in main GUI: highlighting, jump-to-section, snippet
insert, find; edits persist to $State.ScriptText). Builds onto the REAL blank v4 template now
(Get-TemplateScript loads PSADT_Template\ folder, or PSADT_Template.zip when present). Predecessor
fills the $adtSession block (Get/Set-AdtSessionBlock) + authored code; identity retargeted to the new
package (Set-SessionField); fresh-fill path (Build-FreshScript) when no predecessor. Snippets still
inline (plan §6 wants real snippets.json).

PACKAGING DECISION (2026-06-06): template ships as PSADT_Template.zip (NOT base64 - base64 bloats
~33% and parses slowly on every launch). Portable layout: PackageBuilder.exe (PS2EXE from the .ps1
sources) + PSADT_Template.zip + Lib\AvalonEdit.dll + EXTERNAL snippets.json + EXTERNAL settings.json
(team edits snippets/settings; sources embedded in exe, not casually editable). Maintainer keeps .ps1
to rebuild. Loader already supports both an extracted folder (dev) and the zip (distribution).
DONE 2026-06-06: §7 wizard backbone — central $State rehydration on every Back/Next (no
close/reopen), per-step Reset + Reset-all, downstream invalidation on upstream change
(pkg name, source, predecessor, RITM, ProductCode, MST flags). Fixes stale-installer bug.
Env: AvalonEdit 6.3.1.120 (.NET Framework) in Lib\; load via unblock + load-from-bytes.

DONE 2026-06-06 (session 2 — branding / commands / formatting):
- Branding (uninstall-previous block): Remove-MTBDetectionKey verbose form (-InstanceName/-AdditionalRegPaths)
  collapsed to positional `Remove-MTBDetectionKey "<name>"` (Simplify-RemoveDetectionKey). A BARE
  Remove-MTBDetectionKey in a GENERATED block is pinned to the PREDECESSOR full name (would otherwise
  default to $AppFullName = the new pkg). `## Branding Uninstall` stays at the end of the uninstall-prev
  block but is STRIPPED from the new pkg POST-UNINSTALLATION (Remove-SectionBrandingUninstall; template
  owns `## Removing Branding Detection Key` there). POST-REPAIR now OWNS `## Branding Detection Registry
  Key` / Set-MTBDetectionKey (template edit, mirrors POST-INSTALLATION).
- Accumulate (UPDATED): keep EVERY existing predecessor uninstall block VERBATIM (Split-ExistingUninstallBlocks,
  absorbs the leading `#Upgrade` comment), in order, under one corrected header `## Uninstallation of
  predecessor package`; then append the generated immediate block. Generation rule: predecessor HAS
  existing block(s) -> auto-generate immediate; predecessor has NONE -> user opt-in (AddUninstallPrevious),
  GUI asks, never silent.
- SoftIdent bitness (Normalize-SoftIdent): hive WoW6432Node segment forced by NEW pkg arch (x86 -> add,
  x64 -> remove even if predecessor wrongly had it); $($VWG_CurrentRegWOW) token resolved; legacy
  [string]$VWG_SoftIdent custom variable removed (SoftIdent lives only in $adtSession). Applied to both
  predecessor + fresh paths.
- Repair MSI: `-RepairMode 'Repair'` added to any Start-ADTMsiProcess -Action 'Repair' missing it.
- Fresh-package standard commands (§5/§9): New-StandardCommands + Add-StandardCommands port the reference
  CommandBuilder -> SingleMSI / SingleEXE / LooseFiles / Multiple, injected into MAIN-INSTALL/UNINSTALL/
  REPAIR + PRE-REPAIR. MSI uses DirFiles path + -Transform; EXE Repair=reinstall, PreRepair=uninstall;
  Multiple installs in order / uninstalls reversed; each installer referenced as $($adtSession.DirFiles)\<name>
  (all chosen installers copied flat into Files\ by Copy-ResolvedSource).
- Loose files (§4/§7): user option in the installer picker ("Treat as loose files"); LooseFiles command
  set = Copy-ADTFile payload -> $envProgramFiles[X86]\Vendor\App, optional desktop shortcut(s) per chosen
  target exe (New-ADTShortcut, multiple allowed), optional ARP entry (Set/Remove-MTBApplicationWizardEntry).
  Icon resolution helper (Source.ps1 Resolve-ArpIcon / Save-ArpIcon): Icons folder -> a target exe ->
  exe matching app/vendor name -> none; Save-ArpIcon writes SupportFiles\Icon.ico (extracts from exe).
  NOTE: actual Icon.ico placement runs in Step 4 assembler (not built yet).
- Output formatting (§6 adjunct): Format-OutputScript now runs Invoke-Formatter (PSScriptAnalyzer,
  PSUseConsistentIndentation + Whitespace, brace style untouched) with a regex-only fallback; strips a
  stray leading BOM, normalises CRLF, trims trailing whitespace per-line (the old "[ \t]+$" missed it
  before CRLF), collapses blank runs. Requires PSScriptAnalyzer on the build box (bundle for portable exe).
- GUI: EXE install/uninstall arg boxes (Step 2, blank => TODO); loose-files options (ARP / shortcut /
  target exes) in Step 2; installer-type-change vs predecessor now a popup (MessageBox); editor jump-to
  panel narrowed 200->150 to give the editor more width. Predecessor reuse path UNCHANGED by these.
PENDING: per-installer EXE args in Multiple mode (currently TODO); Step 4 assembler (incl. Icon.ico copy,
MST build, source copy, save); optional MSI-from-loose (<2GB) — deferred, ARP chosen instead.

DONE 2026-06-06 (session 3 — loose=zip, repair semantics, FreeSpace, GUI fixes):
- Loose files now use ZIP, not copy: script runs Expand-MTBZipFile -Path "$($adtSession.DirFiles)\<FullName>.zip"
  -Destination <installpath> -Override. Step 4 must ZIP the loose payload into Files\<FullName>.zip (if the
  source is already a zip, reuse it; else zip the loose files). Shortcuts now land in the START MENU
  ($envCommonStartMenuPrograms), not the desktop.
- MSI creation from loose files: DECLINED (needs WiX/COM authoring, fragile, toolchain may be absent) -
  zip-extraction + optional ARP entry chosen instead.
- Repair semantics: Multiple-installer repair = uninstall everything (reverse order) then install again
  (PreRepair = uninstall sequence, MainRepair = install sequence). Loose repair = re-extract (PreRepair just
  Remove-ADTFolder). PRE-REPAIR never carries branding/reboot: Remove-PreRepairNoise strips
  Remove-MTBDetectionKey + Set-MTBReboot (and their comments) from the predecessor's Pre-Repair body.
- FreeSpace auto-fill (fresh): Get-PayloadSizeMB (Source.ps1) sums chosen installers + their non-doc/icon
  payload -> MB; Build-FreshScript writes $adtSession.FreeSpace. (Predecessor path keeps the predecessor's value.)
- GUI fixes: installer picker enlarged (680x470, min sizes) with the "loose files" checkbox on its own row
  (was cut off on small screens) and reworded (zip payload, extract at install); loose files can proceed with
  NO installer selected (whole payload used); Step 2 now shows type 'LooseFiles' and hides EXE/MST controls
  when loose (no more EXE+loose mixing).
DONE 2026-06-06 (session 4 — Step 4 assembler):
- Assemble.ps1 New-Package: lays down a real PSADT v4 package at <OutputBasePath>\<FullName>:
  (1) copy blank template (Content/ + Documents/ + Icons/); (2) write the Step-3 ScriptText over
  Content\Invoke-AppDeployToolkit.ps1 (UTF-8 BOM); (3) source -> Content\Files\ (Copy-ResolvedSource for
  installers+payload, OR New-PayloadZip -> Files\<FullName>.zip for loose: reuse a single source zip else
  stage non-doc/icon files and Compress-Archive); (4) docs -> Documents\, icons -> Icons\; (5) ARP icon ->
  Content\SupportFiles\Icon.ico via Resolve-ArpIcon/Save-ArpIcon when CreateArp; (6) MST via New-PackageMst
  (merges vendor MST + Step-2 remove-shortcut/run-key flags); (7) Unblock-File the whole package.
  Validated end-to-end on a synthetic loose source (template + script + zip + docs landed).
- MstBuilder.ps1 ported from the reference (Build-Mst / Remove-MsiTableRows / Get-StandardMstProperties),
  adapted to this tool's Get-Setting + injected -Logger; Get-MsiProductCode reused from Predecessor.ps1.
DONE 2026-06-06 (session 5 — Step 4 GUI wired + multi-install/MST/repair fixes):
- Step 4 GUI: GUI.ps1 now dot-sources MstBuilder.ps1 + Assemble.ps1; P4 is a Review panel (package/output/
  mode/source/MST flags/loose+ARP/script status via Populate-Step4); the final "Create" button calls
  New-Package with $State (LooseFiles, ARP, shortcut targets, MST flags) and offers "open folder".
- Manual installer selection: "Add installers (manual)..." button (Step 1) opens a multiselect file dialog
  defaulting to settings RepositoryPath; pick one-by-one (re-click to add more). Sets a manual Resolved
  (Mode='manual', Manual=$true) so Copy-ResolvedSource copies ONLY the picked files (no payload-tree sweep,
  no auto docs/icons) - for sources scattered across subfolders we can't uniquely resolve.
- MST for EVERY MSI: assembler builds an MST per *.msi in Files\ (merging each one's vendor MST + Step-2
  flags); Get-MsiCommandSet now always emits -Transform <msi>.mst (we always create one).
- Loose Pre-Repair fixed: now the FULL uninstall (remove shortcut(s) + ARP entry + folder); only
  Remove-MTBDetectionKey / Set-MTBReboot stay out of Pre-Repair. Loose shortcut control relabelled to
  "Create Start Menu shortcut(s)" (it was already targeting $envCommonStartMenuPrograms).
- Multiple uninstall/repair (confirmed matches reference): uninstall all in REVERSE one-by-one; repair =
  uninstall-all then install-all. User trims in the Step-3 editor.
Known minor: Resolve-Source DocItems can list both a Documents folder AND its files -> a nested
Documents\Documents on copy (pre-existing; dedupe later).
PENDING: portable launcher/exe; golden tests on real packages; SCCM/Intune (end).

## 1. Version swap (LOCKED)
Predecessor→new version, one-dot prefix, longest-first. 1.2.3.4→1.5.6.7 swaps 1.2.3.4→1.5.6.7,
1.2.3→1.5.6, 1.2→1.5. Stop at two components. Boundaries leave 11.2 / 1.2.3.4.5 / bare years
untouched. Catches version-named folders. Applies to authored code, SoftIdent, AppVersion.
2025.1 works (won't reduce to 2025).

## 2. Uninstall-previous block (UPDATED 2026-06-06 — accumulate, pinned to predecessor)
In PreInstall; removes a predecessor. The new package keeps up to TWO predecessor blocks so it
cleans up whichever of the last two versions is found in the field (mirrors real packages, e.g.
Synera, which stacks two blocks). Every block stays pinned to the version it removes and is
injected AFTER the global version swap, so it is NEVER bumped to the new version.

Two blocks, oldest first:
- Older block = the predecessor's OWN existing uninstall block, kept VERBATIM (it already removes
  the older version and is already v3→v4-converted). Do not retarget or version-swap it.
- Newer block = remove THIS predecessor. Generated from the predecessor's identity the SAME way we
  generate one when none exists: detection = (Get-ADTApplication -ProductCode "{predPC}", or
  -Name "<AppName>" if EXE) -and (Test-Path "HKLM:\SOFTWARE\VWG\CM\<predecessor FullPackageName>");
  body = predecessor Pre+Main+Post uninstall, taken wholesale (never parse the multiple
  ProductCodes inside).

If the predecessor has NO existing block, only the newer (immediate) block is generated, gated by
the user opt-in (AddUninstallPrevious).
Detection ALWAYS identifies the PREDECESSOR being removed (its branding key + its ProductCode/Name),
never the new package. Predecessor ProductCode source = {GUID} in predecessor MAIN-UNINSTALL section.
Branding root: HKLM:\SOFTWARE\VWG\CM\ + predecessor full package name (constant).
Quote/paren-aware block finder: close the If(...) condition by paren-matching BEFORE brace-walking
the body, so a '{GUID}' ProductCode brace is never mistaken for the body's opening brace.
Known follow-up: generated EXE detection uses the package AppName for -Name, which may differ from
the installed ARP DisplayName — source it from SoftIdent / the old block if it misses on a real EXE.

## 2b. Predecessor selection (UPDATED 2026-06-06)
The package is NEVER its own predecessor (exact FullName excluded). Find returns ALL Vendor_App
candidates sorted newest-first; the user PICKS one (picker when >1, auto when exactly 1). Same-version
candidates (different revision) are shown and flagged "(same version)" — that's the valid predecessor
for a revision bump (e.g. build -0002 from -0001: immediate uninstall block removes the same version,
branding-key Test-Path = predecessor full name, body = predecessor uninstall; predecessor's own older
blocks kept as-is). Default selection = newest candidate strictly older than the new version.
Author = DISPLAY NAME (Get-AuthorName: settings.DefaultAuthor -> AD/local display name -> username),
never the login id.

## 2c. Template injection + conversion fixes (2026-06-06 r7)
NEVER modify the template. Set-SectionBody now INSERTS the (stripped) predecessor body into the
section marker and PRESERVES all template lines - including the template's own Write-ADTLogEntry
"Start.."/"..successful" lines (body goes between them; pristine template section if body empty).
Uninstall-previous blocks are always FIRST after "## <Perform Pre-Installation tasks here>".
v3->v4: Execute-MSI -Path "{GUID}" now converts to Start-ADTMsiProcess -ProductCode (not -FilePath);
leftover [string]$VWG_SoftIdent declaration removed. Uninstall-previous block drops the reboot
scaffold (##Handling for required reboot / #Set-MTBReboot). SoftIdent autopopulates from predecessor,
version bumped by global swap, ProductCode swapped old->new on the SoftIdent line only. Author =
display name with trailing "(...)" domain stripped.

## 2d. Session population from v3/v4 predecessor (2026-06-06 r8)
The blank template's $adtSession is empty; we fill its MTB fields from the predecessor.
- v4 predecessor: Get-AdtSessionBlock swaps the whole block in.
- v3 predecessor (no block): Extract-SessionValues (Predecessor.ps1) reads $VWG_ProcToClose /
  $VWG_FreeSpace / $VWG_SoftIdent etc. from the PRE-conversion text, normalises comma-strings to
  @('a','b') arrays, resolves $($VWG_CurrentRegWOW) in SoftIdent to "WoW6432Node\" for x86, and
  Set-SessionValue writes each into the template field. SoftIdent then gets version bump (global
  swap) + ProductCode swap (old->new).
Duplicate branding/reboot fix: the fresh template OWNS Set-MTBDetectionKey + reboot handling in
POST sections, so the predecessor's Set-MTBDetectionKey / Set-Branding / Set-MTBReboot and their
"## Branding.." / "##Handling for required reboot" comments are now stripped (Remove-* kept for the
uninstall-previous block). Output passes through Format-OutputScript (trim trailing ws, collapse 3+
blank lines to one).

## 3. Field population (LOCKED)
Keep current (never overwritten): new version, new MSI ProductCode (auto-read), RITM id,
new installer filename, new MST name.
Auto from predecessor: vendor, app, arch, lang, params, processes, SoftIdent base (then bumped),
MST/standard properties, all authored code, docs/icons.
Swaps on reuse: version (§1), RITM (old→new), installer filename + ProductCode (old→new) ONLY
when new source type matches predecessor type; if not, carry verbatim + WARN user (Step 1 after
fetch + Step 3 header). Same old/new version = no-op version swap; only RITM+PC swap.
MST (vendor-provided, LOCKED): if the new MSI ships a vendor/client .mst (sibling with the same base
name, else the only .mst in the folder — Find-VendorMst in Source.ps1), that MST is the BASE. Build
the package MST by MODIFYING it (apply standard properties + the Step-2 checkbox flags via
New-PackageMst -ExistingMst), NEVER regenerate from scratch — regenerating discards the vendor's
customizations. Only when no vendor MST exists do we create one from defaults.

## 4. Source resolution (LOCKED)
Order: structured 'source' folder (deep descent through vendor/version/single-subfolder chains;
recognizes 'vendor source') → recursive scan → loose-payload fallback (any non-doc/non-icon file)
→ picker if >1. One payload auto-takes; multiple → picker with Up/Down install order.
Docs always one level under package (Documents); any doc/documents folder anywhere pulled in.
Copy the WHOLE payload tree from the chosen installer's folder into the package Files\ (recursively,
incl. subfolders) EXCEPT documents/icons/other installers — vendor support files (.mst, .varfile,
.ini, .dll, payload subdirs) must ALL land in Files\ (Copy-PayloadTree). Applies in BOTH the
structured case AND the picker/fallback case (non-document files always copied alongside the
installer, not just the installer itself). ISO = warn-and-stop (mount, copy files, re-fetch; no
Next). Block Next on Step 1 until a valid non-ISO payload is detected.

## 5. v3→v4 (LOCKED additions)
Get-InstalledApplication→Get-ADTApplication. Convert-HKCUAllUsers (near end of Convert-V3ToV4Content):
inline [ScriptBlock]$X used by Invoke-HKCURegistrySettingsForAllUsers -RegistrySettings $X →
Invoke-ADTAllUsersRegistryAction -ScriptBlock {...}; remove orphaned defs; $UserProfile.SID→$_.SID.

## 6. Editor (LOCKED: AvalonEdit)
Lib\ICSharpCode.AvalonEdit.dll (6.3.1.120). Unblock + load-from-bytes. PowerShell highlighting,
line numbers, current-line highlight, Ctrl+F/Ctrl+H, 4-space tabs, jump-to-section, snippet
insert from real snippets.json. Confirmed good.

## 7. Wizard UX (TO BUILD — FIRST)
Reset per step (clears that step + downstream) + "Reset all". Every panel re-populates from
central $State on navigation (Back/Forward reflect truth — fixes stale-installer bug). Upstream
change invalidates downstream so Step 3 rebuilds. Never close/reopen for mid-flow changes.

## 8. File layout (simple)
PackageBuilder.ps1 (entry+stamp) | Core.ps1 | Predecessor.ps1 | Build.ps1 | Source.ps1 |
GUI.ps1 (inline XAML) | Lib\ICSharpCode.AvalonEdit.dll | Tests\Test-Build.ps1 | goldens\ |
settings.json, snippets.json, PSADT_V3toV4_Mappings.ps1

## 9. Build order (remaining) — REORDERED 2026-06-06
DONE: 1. Wizard UX (Section 7) · 2. Step 3 editor · 3. Step 4 Review & Create (assembler + MST + zip +
ARP icon + save + unblock). See sessions 1-5 above.

NEXT (in this order — launcher/exe is LAST so we don't re-extract on every change while still iterating):
4. SCCM + Intune integrations — BOTH live in STEP 4 (user's plan 2026-06-08). Studied the team's reference
   tools (MANSCCMCreationandDeploymentAutomator 4.2; MAN_SCCM2IntuneMigrationTool; PSADT-Migration-Orchestrator).

   SCCM AUTOMATOR (Sccm.ps1) — replicate the reference create flow, but AUTO-FETCH everything from the built
   package's Invoke-AppDeployToolkit.ps1 (parse $adtSession) and SHOW for optional user edit, then create.
   The user should never need the console. Sequence (mirrors ref):
   - Map S: drive (-Persist) to the prelive content share, then COPY the package\Content to
     \\...\CMLib_TEST\Apps\<FullName>\Content FIRST (content location is prelive - must be there before DT).
   - Import ConfigurationManagerPrelive\ConfigurationManager.psd1; New-PSDrive <SiteCode>:; Set-Location.
   - New-CMApplication (Publisher=Vendor, SoftwareVersion=Version, LocalizedName="<App> <Ver>", Keyword=App,
     Icon) -> add DE App-Catalog display -> Move-CMObject to app folder.
   - Detection: (1) MANDATORY branding key New-CMDetectionClauseRegistryKeyValue Hive=LM
     KeyName="SOFTWARE\VWG\CM\<FullName>" ValueName=Name -Existence -Is64Bit; (2) optional uninstall key
     DisplayVersion >= Version (Is64Bit unless x86); (3) optional ProductCode WindowsInstaller.
   - Add-CMScriptDeploymentType (detection, ContentLocation, Install/Repair/Uninstall = "Invoke-AppDeployToolkit.exe"
     install/repair/uninstall, InstallForSystem, 180/15 min) -> add 2nd detection -> exit code 60012 (deferred,
     FastRetry) via SDMPackageXML/WMI.
   - Start-CMContentDistribution to DP _ALL_DPs; poll Get-CMDistributionStatus.
   - New-CMDeviceCollection <FullName>-INSTALL/-UNINSTALL (TEST), Limiting=All Systems, random schedule, RFC
     comment -> Move to collection folder -> New-CMApplicationDeployment Install(Required)/Uninstall(Required).
   - Extra tabs (later): UPDATE CONTENT (recopy + redistribute), add devices to collection, download package
     logs and OPEN them in CMTrace.
   Config (settings.json overridable; ref defaults): SiteCode=G08, Server=mbdcaswvtb29843.mn-man.biz,
   ContentShare=\\mbddfsovpc01.mn-man.biz\SWDPreLive-Gate\CMLib_TEST\Apps, DP=_ALL_DPs,
   AppFolder=G08:\Application\VOLKSWAGEN\DEVELOPMENT\EQS, CollFolder=G08:\DeviceCollection\DEVELOPMENT\EQS.

   INTUNE AUTOMATOR (Intune.ps1) — CREATE the Win32 app only (NO group assignment per user). Auth = DELEGATED
   (interactive sign-in, NO client id/secret). AVOID the module's fragility (407 proxy + large-file failures):
   use RAW Graph (graph.microsoft.com/beta) with a ROBUST uploader - chunked Azure-blob block upload, system
   proxy + DefaultNetworkCredentials (kills 407), SAS-URI renewal on long uploads, retry/backoff, resumable.
   Steps: IntuneWinAppUtil -> .intunewin (SetupFile=Invoke-AppDeployToolkit.exe); parse detection.xml
   (encryption info) from the .intunewin; create win32LobApp; content version+file; upload encrypted blob in
   blocks; commit w/ encryptionInfo; patch committedContentVersion. Detection = branding key
   (registry, ValueName=Revision == <rev>) + ProductCode (MSI) when present; requirement = Arch + W10_1607;
   icon = package Icons png/ico (base64). If BOTH SCCM+Intune chosen, Intune takes its fields FROM the SCCM
   tab (edited) and shows for confirm.
   Placement: Step 4 gets a "Publish" area with SCCM and Intune sections; both prefilled from the package,
   editable, one-click create, live log + CMTrace for SCCM logs.

   SCCM REFINEMENTS (2026-06-08, in Sccm.ps1 - DONE, engine only):
   - Detection 2nd clause = the SoftIdent/uninstall key (preferred over ProductCode). WoW6432Node is STRIPPED
     from the key path and the clause is marked 32-bit (no -Is64Bit) - never put WoW6432Node in the KeyName.
     Branding key clause (SOFTWARE\VWG\CM\<FullName>, Is64Bit) is ALWAYS kept (mandatory). Validated.
   - Update-SccmDetection: re-apply detection on an existing app (keeps branding + uninstall clause) for the
     "review/update after creation" need.
   - Description: Get-PackageDescription reads the package's "Installation instructions" .docx (Documents\)
     and pulls the "Short description of the product in English" value (falls back to Detailed). Validated on
     the Adobe doc. Wired into New-CMApplication (-LocalizedDescription) + the DE app-catalog display. User
     can still edit it in the Step-4 form.
   INTUNE detection must MIRROR this: same uninstall key, but strip WoW6432Node and set Check32BitOn64System=
     $true (the module/Graph equivalent of the 32-bit checkbox); branding key (ValueName Revision) kept;
     description from the same docx OR user. Post-create: update content / icon / detection from the tool.

   INTUNE AUTOMATOR (Intune.ps1 - DONE, engine only). CREATE Win32 app only, NO group assignment.
   - Auth: Connect-Intune = delegated interactive Connect-MgGraph (Microsoft.Graph.Authentication), NO client
     id/secret; sets DefaultWebProxy = DefaultNetworkCredentials (kills 407). Graph calls via Invoke-MgGraphRequest.
   - Package: New-IntuneWinPackage runs IntuneWinAppUtil (-c Content -s Invoke-AppDeployToolkit.exe -o ... -q)
     -> <FullName>.intunewin; Get-IntuneWinMetadata reads Detection.xml (encryption info + sizes).
   - ROBUST UPLOAD (Send-IntuneBlob): chunked block PUT to the Azure SAS with -ProxyUseDefaultCredentials +
     per-block retry/backoff + SAS RENEWAL (renewUpload + azureStorageUriRenewal) every ~40 min -> avoids the
     module's 407 / large-file failures. Set-IntuneAppContent does content version -> file -> blob -> commit
     (fileEncryptionInfo) -> wait -> PATCH committedContentVersion.
   - New-IntuneApp: POST win32LobApp (displayName, description, publisher, install/uninstall cmd, setupFilePath,
     applicableArchitectures, minimumSupportedWindowsRelease=1607, returnCodes incl 60012=retry, detectionRules
     = Get-IntuneDetectionRules (mirror SCCM), largeIcon=package png base64) then upload content. Validated the
     offline pieces (detection rules, icon base64, description default "Vendor App").
   - Post-create: Update-IntuneContent / Update-IntuneIcon / Update-IntuneDetection (PATCH).
   Settings.json -> "Intune": { TenantId; IntuneWinAppUtil }.

   STEP-4 PUBLISH GUI - DONE (2026-06-08). GUI.ps1 dot-sources Sccm.ps1 + Intune.ps1. P4 now has a Review
   section + a "Publish to SCCM / Intune" section (in a ScrollViewer). After Create succeeds, $State.CreatedPath
   is set and Populate-Publish auto-fetches fields (Get-SccmFieldsFromPackage) into editable boxes: Publisher,
   Version, ProductCode, Branding key, Uninstall key, Detect version, Description. Buttons: "Create in SCCM"
   (with Distribute/Collections/Deploy toggles -> New-SccmApplication), "Create in Intune" (-> New-IntuneApp),
   "Open log (CMTrace)". Get-PublishFields merges the edited form over the auto-fetched base so BOTH targets use
   the SAME edited fields (Intune inherits SCCM). Revisiting Step 4 re-enables the form. Parse-clean; live
   SCCM/Graph paths only run on a connected box.
   PUBLISH IS NOW INDEPENDENT (2026-06-08): you can publish an existing package WITHOUT building. Settings
   OutgoingPath (default \\mndemucfsm01\SEC-EQS-Lib-Gate\EQS_SEC\EQS\Packages\Outgoing). Find-OutgoingPackage
   (Sccm.ps1) resolves a package folder by name (exact then partial; prefers the one with Invoke-AppDeployToolkit.ps1).
   Step-4 Publish got a "Package name + Load from Outgoing + Browse..." row (always enabled), and the step rail
   (1-4) is now CLICKABLE - open the tool, click "4", type a name, Load, then Create in SCCM/Intune. Validated
   Find-OutgoingPackage; GUI parse-clean.
   FIXES 2026-06-08 (from first live test):
   - settings.json now controls EVERYTHING: rewritten with all paths + nested "Sccm" {SiteCode/SiteServer/
     ContentShare/DPGroup/AppFolder/CollectionFolder/LimitingCollection/ModuleRelPath/CMTracePath} and "Intune"
     {TenantId/IntuneWinAppUtil}. Initialize-Config carries those defaults and WRITES a starter settings.json
     when none exists. Root cause of "Invalid JSON primitive: ." = the file's UTF-8 BOM: Read-FileSmart kept the
     leading U+FEFF char -> ConvertFrom-Json choked. Read-FileSmart now TrimStart's the BOM (also helps any
     downstream parse). Verified config loads with the Sccm section.
   - SCCM "drive G08 does not exist": Connect-Sccm created the CMSite PSDrive inside the function scope, so it
     was gone by the time New-SccmApplication did Push-Location G08:. Now New-PSDrive ... -Scope Global.
   - Intune "Microsoft.Graph.Authentication not available": removed the module dependency entirely. Connect-Intune
     is now a self-contained DEVICE-CODE flow against the well-known public "Microsoft Graph PowerShell" client
     (no client id/secret of ours) + token refresh; Invoke-Graph uses Invoke-RestMethod with the bearer token +
     retry; proxy 407 handled by Set-IntuneProxyCreds (DefaultWebProxy.Credentials = DefaultNetworkCredentials).
     NOTE: device-code polling briefly blocks the WPF thread while the user signs in (one-time).
   REFINEMENTS 2026-06-08 (2nd live test):
   - Branding-only detection works (no uninstall key/ProductCode -> only the mandatory branding clause). Confirmed.
   - Detection 2nd clause is now a CHOICE: $Fields.DetectType in { Version (default), String, ProductCode, None }.
     SCCM New-SccmUninstallClause + Intune Get-IntuneDetectionRules both honour it (Version=GreaterEquals/version,
     String=IsEquals/string). Engine + offline test done. GUI dropdown (CmbDetectType) still to add (GUI was locked).
     [Idea for later: File / Custom-script detection types when no version/string is possible.]
   - SCCM language: German (de) app-catalog display is now ROBUST - the icon is optional and no longer skips the
     de display on icon failure (root cause of English-only); errors are logged, not swallowed. DT keeps
     -AddLanguage en-US,de-DE.
   - SCCM "Allow users to view and interact": default ON now (New-SccmApplication -AllowUserInteraction $true,
     applied via Set-CMScriptDeploymentType -RequireUserInteraction always). GUI checkbox to add (locked).
   - INTUNE auth: the device-code error ("You cannot access this right now ... restricted by your admin") = a
     Conditional Access block on device-code flow. Switched Connect-Intune to INTERACTIVE auth-code + PKCE with a
     one-shot localhost listener (browser sign-in) - no module, no client id/secret, CA-friendly. NO MODULES NEEDED.
   REFINEMENTS 2026-06-08 (3rd live test):
   - German app-catalog display now ALWAYS gets the icon (same as English) - loaded robustly (New Icon($ico)
     first, ExtractAssociatedIcon fallback); only logs a warning if the file truly won't load.
   - ROLLBACK ON FAILURE (no manual console cleanup): New-SccmApplication tracks app/collection creation and, on
     any error, removes the install/uninstall collections + Remove-CMApplication (which also drops DT, deployments,
     content). New-IntuneApp tracks the created app id and DELETEs the app shell if a later step fails.
   - APP ID returned + surfaced: SCCM result has @{AppId=PackageID; CIUniqueID} and logs "PackageID=.. CI=..";
     Intune result has @{AppId}. Both put the id in the publish-log message, the tool log, AND copy it to the
     CLIPBOARD on success.
   - GUI Publish form completed: "2nd detection" dropdown (Version/String/ProductCode/None) -> $Fields.DetectType;
     "Allow user to view/interact (SCCM)" checkbox (default ON) -> -AllowUserInteraction.
   REFINEMENTS 2026-06-08 (4th live test):
   - German icon FIX (was failing on a UNC path): ExtractAssociatedIcon/Icon() don't accept UNC + some PNG-framed
     .ico. Now copy the .ico to a LOCAL temp first, then load (New Icon -> ExtractAssociatedIcon -> Bitmap.GetHicon
     fallbacks). German display always gets the icon, same as English.
   - INTUNE AUTH switched to the working client: device-code AND the Graph CLI client (14d82eec) are blocked by
     the tenant CA for this ext user (AADSTS50105). Connect-Intune now uses the IntuneWin32App module's
     Connect-MSIntuneGraph (MSAL.PS) = the "Microsoft Intune PowerShell" SP (6beebafa-...), which the tenant
     permits (same as the SCCM2Intune tool). We use the module ONLY for the token; the .intunewin upload stays our
     robust uploader. settings Intune.ModulePath (default C:\temp\SCCM2Intune Migration Tool\PowerShell Module);
     set Intune.TenantId too. NO client id of ours, no secret.
   - PROGRESS BAR: SCCM/Intune publish now runs on a BACKGROUND runspace (Start-PublishJob) with an indeterminate
     ProgressBar + DispatcherTimer poll -> window stays responsive, bar animates, result + clipboard on completion.
   PORTABILITY 2026-06-08 (everything tool-relative for the future exe - nothing hard-coded to C:\):
   - Core.ps1 Get-ToolRoot (= $PSScriptRoot as scripts, the .exe folder once packaged) + Resolve-ToolPath
     (relative -> toolroot, absolute passes through).
   - Intune: ModulePath default 'Lib' (tool-relative); Connect-Intune searches resolved ModulePath, then Lib\,
     then the tool root (recursive) for MSAL.PS.psd1 + IntuneWin32App.psd1. IntuneWinAppUtil resolved tool-relative
     and auto-found under the tool root if not set. So drop MSAL.PS + IntuneWin32App (only those two) +
     IntuneWinAppUtil.exe under Lib\.
   - SCCM: Connect-Sccm resolves ModuleRelPath (ConfigurationManagerPrelive\...) tool-relative.
   WHAT TO SHIP (all beside the exe / tool root): the .ps1 files + settings.json + snippets.json; Lib\ICSharpCode.
   AvalonEdit.dll; Lib\MSAL.PS\ + Lib\IntuneWin32App\ + Lib\IntuneWinAppUtil.exe; PSADT_Template\ (or .zip);
   ConfigurationManagerPrelive\. (NOT needed: Microsoft.Graph.Groups, microsoft.graph.authentication.)
   2026-06-08 cleanup + real progress:
   - Removed dead files: Editor.ps1 (only a comment referenced it; the editor lives inside GUI.ps1) and
     "New Text Document.txt" (stray PSADT template copy). Active set = Core/Predecessor/Build/Source/
     MstBuilder/Assemble/Snippets/Sccm/Intune/PSADT_V3toV4_Mappings/GUI .ps1 + settings.json + snippets.json
     (+ Test-Build.ps1 dev harness).
   - SCCM German icon FINAL fix: ConfigMgr Icon.Data is System.Byte[] (verified by reflection on the DLL),
     NOT System.Drawing.Icon. Assigning an Icon object coerced to a 766-byte junk blob -> no icon. Now
     $ico.Data = [IO.File]::ReadAllBytes(IconPath) (full ~86KB icon; ReadAllBytes is UNC/mapped/local safe).
   - Intune: util resolver accepts exe path OR folder ("Lib") OR empty -> searches for the .exe (folder no
     longer run as a command). Connect requires real Intune.TenantId (no 'common'); surfaces the module's
     swallowed warnings. Block-list commit sends UTF-8 bytes + retry; catch logs the real error before rollback.
   - REAL progress (no marquee): Core.Set-PbProgress -> $Global:PBProgress (synchronized hashtable via jobArgs);
     GUI DispatcherTimer drives a determinate 0-100% bar + % overlay (LblPbPct) + live step line (LblPubStatus).
     Intune upload reports 15..90% per block; SCCM per-step %. LblPublishLog now a read-only TextBox (copyable).
     Verified: parse-clean, Test-Build PASSED, XAML loads with the 4 new/updated controls.
   2026-06-09 Intune metadata + large-file + icon:
   - Intune commitFileFailed ROOT CAUSE: PS 5.1 corrupts a raw byte[] body. Send-IntuneBlob now matches the
     proven IntuneWin32App module: chunk bytes -> ISO-8859-1 string, content-type text/plain;charset=iso-8859-1,
     Invoke-WebRequest -UseBasicParsing; '0000' ASCII block ids; BinaryReader chunk reads. (verified byte-exact.)
   - Intune app body fixes: displayName = ProductName (not the full package name; migrator differentiates by
     version); displayVersion = Version (was missing); isFeatured = $true; applicableArchitectures = 'x86,x64'
     (= "All / allow on all systems", matching migrator's -Architecture All).
   - SCCM icon: resolve ONE non-UNC $iconLocal (mapped S: copy, else local temp copy of the UNC source) and use
     it for BOTH -IconLocationFile (default icon) AND the de display's ExtractAssociatedIcon. Likely the real
     fix - IconLocationFile/ExtractAssociatedIcon are both flaky on UNC. Added a read-back that logs the de
     icon byte count actually persisted, to settle whether remaining "no de icon" is a viewing-locale thing.
   2026-06-09 German icon FINAL approach (after many failed byte attempts):
   - Root cause: ConfigMgr stores the display icon in a specific internal format. Our hand-built bytes (raw
     .ico = 86KB, ExtractAssociatedIcon Icon-object coerced = 766B) were the WRONG format -> never rendered,
     even though they "persisted". Both -IconLocationFile (default/en-US) and the cmdlet store the CORRECT
     format themselves.
   - Final fix (Sccm.ps1 step 1b): after New-CMApplication creates the default icon via -IconLocationFile,
     deserialize the app SDMPackageXML, grab the Icon object off the default DisplayInfo (correct bytes), build
     a 'de' AppDisplayInfo, set .Icon = that SAME object, $sx.DisplayInfo.Add($de), reserialize, and persist
     via WMI [wmi]$SMS_ApplicationLatest.__PATH .Put() (the proven pattern already used for exit code 60012;
     also what the old automator's commented code intended). Reflection-confirmed: DisplayInfo is
     LocalizedDataSet<AppDisplayInfo> with .Add(AppDisplayInfo); AppDisplayInfo.Icon:Icon; Icon.Data:byte[].
   - Read-back logs "de display persisted (icon bytes stored = N)" to confirm. Default icon reverted to the
     plain UNC $Fields.IconPath on -IconLocationFile (rerouting it had broken the EnglishE icon). isFeatured back
     to $false per user. Removed dead $iconLocal/$iconTmp.
   2026-06-09 Manage-existing-app (phase A+B + update content):
   - New Sccm.ps1 Remove-SccmApplication: deployments -> INSTALL/UNINSTALL (TEST) collections -> Remove-CMApplication
     (DTs/content go with it), with Set-PbProgress steps. Update-SccmDetection + Update-SccmContent already existed.
   - GUI Step 4: new "Manage existing SCCM application" row under the Create row - buttons BtnUpdateDetection,
     BtnUpdateContent, BtnDeleteApp (delete has a Yes/No confirm). New Start-SccmManageJob runs the chosen engine
     on the background runspace (same progress bar/result UX as Start-PublishJob); Test-ManageReady guards that a
     package is loaded (needs the exact FullName). All act on the app named in the loaded/built package.
     Verified: parse-clean, XAML loads the 3 buttons, Test-Build PASSED.
   2026-06-09 detection clause fixes:
   - STRICT single secondary clause on CREATE (both SCCM New-SccmUninstallClause + Intune Get-IntuneDetectionRules):
     removed the cross-fallback so ProductCode and the uninstall/version key are mutually exclusive - selecting one
     never also creates the other. Missing field -> branding only (logged), not a silent switch to the other type.
   - Update-SccmDetection now REPLACES instead of appending (was -AddDetectionClause only -> duplicates / "total 3").
     Order: capture old clause SettingLogicalNames (Get-CMDeploymentTypeDetectionClause) -> add branding + selected
     -> Set-CMScriptDeploymentType -RemoveDetectionClause $oldNames. DT never left with 0 clauses. The DetectType
     dropdown is the "what to update" control: pick a type+Update = branding+that; pick None+Update = branding only;
     change type+Update again = remove old & set new.
   2026-06-09 detection rework (replace bug + fetch-edit + hide branding):
   - Earlier replace bug: -RemoveDetectionClause got $_.SettingLogicalName (null on this build) AND I re-added
     branding -> duplicates of BOTH. Fix: Update-SccmDetection now KEEPS branding (never re-adds/shows it) and
     replaces ONLY the secondary: find non-branding clauses (Test-SccmBrandingClause = Setting.Location matches
     \VWG\CM\), remove them (Get-SccmClauseName tries SettingLogicalName/LogicalName/Setting.LogicalName defensively),
     then add the new secondary. Logs "existing detection = N; removing M non-branding" so we can see if M>0.
   - New Get-SccmDetection: reads the app's current secondary clause by name -> @{DetectType;UninstallKey;
     DetectVersion;Is32Bit;ProductCode} (best-effort property reads).
   - GUI: "Fetch detection" button (BtnFetchDetection) -> populates the editable fields from SCCM; branding key
     field hidden (row collapsed, control kept so create still computes it). Update detection then replaces only
     the 2nd clause with the edited values. Verified parse/XAML/Test-Build.
   - CONFIRMED live: detection remove works (user saw it after a console REFRESH - external cmdlet edits need the
     open console to refresh; normal, not a bug).
   2026-06-09 Intune 400 + upload speed:
   - 400 on create = applicableArchitectures order. Graph wants the module's exact 'x64,x86' (I had 'x86,x64'). Fixed.
     Invoke-Graph now surfaces the Graph error body (ErrorDetails.Message / response stream) for future 4xx.
   - Upload speed: replaced Invoke-WebRequest-per-block (reconnects each call + ISO-8859-1 string) with one reused
     System.Net.Http.HttpClient sending RAW bytes (ByteArrayContent + HttpRequestMessage; x-ms-blob-type as request
     header). Verified byte-exact 0..255 round-trip + header + 201 via local HttpListener. Proxy creds on handler,
     per-block retry, SAS renewal kept. BlockSizeMB 6 -> 10. Per-request overhead gone; now bandwidth-bound.
   2026-06-09 SCCM distribution speed:
   - Real cause of "slow distribution" = the 5-min BLOCKING poll loop (30x10s waiting for NumberSuccess>=1).
     Removed it: Start-CMContentDistribution -ErrorAction Stop already throws if it can't START, so we kick off
     and continue - SCCM copies to DPs server-side/async; the tool no longer sits idle. (DP transfer time itself
     is SCCM's, not ours to speed.)
   - robocopy to prelive now /J (unbuffered I/O, large files) + /MT:16 (16-thread, many files) - faster, still
     verified/non-corrupting.
   2026-06-09 distribution monitoring restored + Modify UI:
   - User: must SEE distribution finish in-tool (don't continue on incomplete content). Restored the wait but now
     it MONITORS live: polls Get-CMDistributionStatus, shows "Distributing to DPs: ok/tgt done (in progress) (errors)"
     in the progress bar, waits until every targeted DP is done (success or error) or DistWaitSec (new config,
     default 3600). Logs success / partial / DP errors.
   - Clear Modify UI: replaced the cramped manage-buttons row with a self-contained "Modify an existing SCCM
     application" section that has its OWN fields (TxtModAppName + CmbModDetectType + ChkMod32Bit + TxtModUninstallKey
     + TxtModDetectVersion + TxtModProductCode), separate from the Create fields. Get-ModifyFields builds from those
     (branding derived from the name). Fetch populates them; Update detection/content/Delete act on the typed name.
     Moved Modify + progress OUTSIDE PnlPublish so they work WITHOUT a loaded package (modify any app by name).
     Update content auto-finds the package by name in Outgoing if not loaded. PnlPublish (Create) still gated on a
     loaded/built package. Verified parse/XAML(balanced)/Test-Build.
   2026-06-09 Step-4 tabbed (Integration) + Testing/Troubleshoot/Dev-Test built in one go:
   - Step 4 ScrollViewer -> TabControl: [Review & Create] [Integration] [Testing] [Troubleshoot] [Dev -> Test],
     with ONE shared progress bar + status + copyable log (PbPublish/LblPbPct/LblPubStatus/LblPublishLog) in
     P4 Grid.Row=1 below the tabs, so every tab's op reports there. Integration tab = the publish (create
     SCCM/Intune) + the self-contained Modify section. Wizard nav unchanged (still 4 steps).
   - New Sccm.ps1 engines: Add-SccmTestMachine (Get-CMDevice -> Add-CMDeviceCollectionDirectMembershipRule to
     <app>-INSTALL/UNINSTALL (TEST)); Invoke-SccmMachinePolicy (WMI TriggerSchedule {021}{022}{121} to clients);
     Get-SccmClientLog (AppDiscovery/AppEnforce from \\m\c$\Windows\CCM\Logs; Package = PSADT install/uninstall
     log from \\m\c$\ProgramData\VWG\Logs\<app> -> copy to %TEMP%\SCCM_Logs_<m> -> Open-CMTrace);
     Move-SccmDevToTest (Move-CMObject app -> TestAppFolder + colls -> TestCollectionFolder, or back to Dev).
     New config: TestAppFolder, TestCollectionFolder, ClientLogShare, PsadtLogShare.
   - Start-SccmManageJob generalized (-Op hashtable; actions addmachine/machinepolicy/getlog/move); handlers for
     all new buttons; app-name pre-filled across Modify/Testing/Troubleshoot/Dev-Test on package load.
   - The PREVIOUSLY-MISSED bit is in: Troubleshoot "Install/Uninstall log" = the app's PSADT log (alongside
     AppDiscovery + AppEnforce), all opened in CMTrace - matches the old automator's Package Log.
   Verified: 3 files parse clean, XAML balanced, all new controls present, Test-Build PASSED.
   2026-06-09 testing/troubleshoot smarts + Intune assignment:
   - Testing: separate Remove-SccmTestMachine ("Remove from collection") - Add/Remove are independent direct-
     membership actions (adding to Uninstall does NOT clear Install). Answer to user's Q: no auto-clear.
   - Troubleshoot: Get-SccmCollectionMembers ("Show members" -> LstTsMembers; click a row -> fills machine box) +
     Get-SccmInstallState ("Check install state"): app-id FIRST (SCCM client root\ccm\clientsdk CCM_Application
     .InstallState), branding-key FALLBACK (HKLM\SOFTWARE\VWG\CM\<pkg> via WMI StdRegProv - works w/o Remote
     Registry svc). Verdict vs the chosen collection (Install->should be installed / Uninstall->should be gone).
   - Intune (Testing tab): Add/Remove-IntuneGroupAssignment - ISOLATED: POST one mobileAppAssignment
     (intent=available, groupAssignmentTarget by group Object ID/GUID) / DELETE the single matching assignment.
     Never touches the app or other assignments (checks for an existing identical assignment first). Find-IntuneApp
     made robust (product displayName or full package name; newest match) so it still resolves after the
     displayName=ProductName change.
   - Start-SccmManageJob extended (removemachine/members/checkstate/intuneassign/intuneunassign); members fill the
     ListBox via the completion handler; app names pre-filled across all tabs on package load. All additive - no
     existing path changed. Verified: 3 files parse clean, XAML balanced, all controls present, Test-Build PASSED.
   2026-06-09 Intune assign by app-id/branding + Software Center error decoder:
   - Intune assignment app resolution is INTUNE-ONLY (no SCCM): Find-IntuneApp now takes -AppId (GUID -> direct
     GET, top priority); else matches the BRANDING KEY identity = the package FullName embedded in the .intunewin
     fileName ("<FullName>.intunewin") and in the detection keyPath ..\VWG\CM\<FullName> (same marker the
     migration tool used); else product displayName. GUI Intune section: "App ID (preferred)" + "App name
     (fallback)" + group. Add/Remove-IntuneGroupAssignment pass -AppId through.
   - Software Center error decoder: $script:SccmErrorMap (0x87D00324 detection-not-detected, 1603/1618/3010/60012,
     0x87D013BC requirements, 0x87D01106 content, access-denied, etc.) + ConvertTo-Hex32 (hex / negative decimal /
     exit code -> 0xXXXXXXXX; uses 0xFFFFFFFFL int64 mask) + Get-SccmErrorExplanation. Troubleshoot tab: "Explain"
     box (instant, UI thread). Get-SccmClientLog auto-scans fetched AppEnforce/PSADT logs (Find-KnownLogErrors)
     and appends "Known issue(s) found". Verified -2016410844 == 0x87D00324, 1603, 3010 map correctly.
   All additive. Verified: 3 files parse clean, XAML balanced, all controls present, Test-Build PASSED.
   2026-06-09 Intune safety + group-by-name + Intune update content + content-source selection:
   - Group: TxtIntuneGroupId now takes a NAME or Object ID. Resolve-IntuneGroupId (GUID -> as-is; name -> Graph
     /groups displayName lookup; if >1 or no group-read -> clear "use Object ID" message).
   - SAFER app resolution (Intune is sensitive): Find-IntuneApp dropped the display-name fallback. App id -> direct;
     else branding-key identity (fileName "<FullName>.intunewin" / detection keyPath ..\VWG\CM\<FullName>); else
     $null -> callers return "Application not found. Nothing changed." (never guesses by name).
   - Intune Update content: new BtnIntuneUpdateContent + content-source field/Browse. Update-IntuneContent rewritten
     (param AppName/AppId/LocalPackagePath): uploads a new content version AND RE-APPLIES the icon (Get-IconBase64 ->
     PATCH largeIcon) because Intune drops the icon on a content update. Settings/assignments untouched.
   - Content source selection for BOTH (SCCM Modify + Intune): TxtModContentSrc/BtnModBrowseSrc + TxtIntuneContentSrc/
     BtnIntuneBrowseSrc (FolderBrowserDialog defaulting to Outgoing). SCCM 'content' source priority: field ->
     loaded package -> find by name in Outgoing. Pre-filled with CreatedPath on load. (SCCM & Intune sources can differ.)
   - New actions: intunecontent; intuneassign/unassign now pass -Group (name|id). All additive.
   Verified: 3 parse clean, engines load, XAML balanced, all controls present, Test-Build PASSED.
   2026-06-09 Integrate-tab editability + UX:
   - Editable Product name (TxtPubProductName -> Intune displayName + SCCM localized name/keyword) and editable
     Commands section: Install/Uninstall/Repair (TxtPubInstall/Uninstall/Repair). One shared commands block;
     SCCM uses all three, Intune uses Install+Uninstall (New-IntuneApp now reads $Fields.InstallCmd/UninstallCmd,
     falling back to cfg). Get-PublishFields + Populate-Publish updated.
   - Removed the Distribute/Collections/Deploy checkboxes - Start-PublishJob now always passes distribute/
     collections/deploy = $true. (Allow user view/interact checkbox kept, moved to the buttons row.)
   - Tab UX: TabControl x:Name=TabsP4 with a proper TabItem style (rounded headers, hover #3E3E42, selected
     #0E639C/white/semibold). On tab switch (TabsP4.SelectionChanged, only real TabItem changes) the Integrate
     app name (PublishBase.FullName) + content path (CreatedPath) flow into the Modify/Testing/Troubleshoot/
     Dev-Test/Intune fields when those are blank.
   Verified: 3 parse clean, XAML balanced, new fields present, old checkboxes gone, Test-Build PASSED.
   2026-06-09 fixes + consolidation:
   - Update-SccmContent: was re-running Start-CMContentDistribution on already-distributed content -> "No content
     destination". Now: if already on DPs -> Update-CMDistributionPoint (refresh, idempotent); else first-time
     Start-CMContentDistribution; "already distributed" treated as OK. Works even with no content change.
   - Find-IntuneApp: EXACT-only (app id, or exact .intunewin fileName / exact ..\VWG\CM\<FullName> detection).
     Dropped the partial '*name*' and product-display-name fallbacks - same-named apps no longer risk a wrong match;
     no match -> "Application not found. Nothing changed."
   - Check install state now ALSO fetches the Software Center error code from the client (CCM_Application
     ErrorCode/ReturnCode) and appends Get-SccmErrorExplanation. Removed the separate "Explain error code" box.
   - Intune App ID from create is remembered ($script:State.IntuneAppId) -> pre-filled into TxtIntuneAppId and
     re-applied on tab switch (until the user edits). Tab switch keeps reflecting Integrate app name + content path.
   - FOLDER CONSOLIDATION: Core Get-WorkRoot/Get-WorkPath; WorkRoot (settings, default C:\temp\PackageBuilder) with
     subfolders Logs / IntuneWin / Downloads / Build / Temp. Routed: log (Logs\PackageBuilder.log), .intunewin
     (IntuneWin\), encrypted payload + build temps PBtpl*/PBzip*/PkgBuilder.msi (Temp\), fetched client logs
     (Downloads\<machine>\), LocalWorkingDir default (Build\). GUI Open-log + messages use Get-LogPath.
   Verified: all .ps1 parse clean, settings valid, XAML balanced, Test-Build PASSED. (exe NOT built - per user.)
   2026-06-09 final polish (user decisions):
   - Intune upload RESUME: on a block exhausting retries (usually expired SAS on large uploads) -> renew SAS +
     retry the same block (up to 3 rounds); already-uploaded blocks persist so it resumes, not restarts.
   - "Open work folder" button (BtnOpenWork) -> opens WorkRoot (Logs/IntuneWin/Downloads/Build/Temp). NOTE: the
     finished PACKAGE still goes to OutputBasePath (deliverable), deliberately separate from WorkRoot runtime junk.
   - Declined per user: in-tool Settings UI (settings.json stays backend-only), group-name-resolution extra work
     (field already accepts name or id), auto member status, pre-create summaries, de-DE default language.
   Verified again: 4 files parse clean, XAML balanced (BtnOpenWork present), Test-Build PASSED.
   NEXT: live-test on the connected box; then DISCUSS further improvements (user wants to). exe still NOT built.
   2026-06-09 improvement round 1 (user-picked: machines list, MSI prop editor, predecessor diff):
   - Testing machines LIST: TxtTestMachine + BtnTestAddList -> LstTestMachines (dedup, uppercased) +
     Remove selected/Clear list. Get-TestMachines = list items, else the typed box (one-offs still work).
     Add/Remove collection + Run machine policy all act on EVERY listed machine.
   - MSI property editor (in-tool Orca replacement): MstBuilder Get-MsiProperties (COM, read-only Property
     table). GUI Show-MsiPropertiesDialog: DataGrid (Set?/Property/Value, filter box, Add property), typed
     MsiPropRow class for reliable WPF binding. Ticked rows -> "KEY=VALUE" lines -> existing MsiProps[fn]
     plumbing -> merged into the MST at build. Buttons: BtnMsiPropsView (single-MSI panel) + per-MSI
     "View MSI properties..." in the multi-installer rows. VERIFIED on real AdobeDesktopApp.msi: 98 props
     incl. AgreeToLicense=No (the exact IAGREE/AGREETOLICENSE use case).
   - Diff vs predecessor: BtnDiffPred (Step-3 toolbar) -> Show-PredecessorDiff: Compare-Object on
     PredecessorModel.RawV4Content vs current editor text; two copyable panes (red = removed from
     predecessor, green = added in current) with counts.
   - Deferred per user: version-swap preview (last priority), silent-switch autodetect (dropped for now).
   Verified: parse clean, XAML balanced (6 new controls), real-MSI property read OK, Test-Build PASSED.
   2026-06-09 v3->v4 $UserProfile.SID fix (user-reported): TWO stacked bugs in PSADT_V3toV4_Mappings.ps1:
   (1) Convert-V3ToV4Content called Convert-HKCUAllUsers on the STALE $content var and returned $result ->
   the whole HKCU/SID conversion was computed on the wrong text and discarded. Now: $result =
   Convert-HKCUAllUsers -Content $result. (2) the replacement string '$_.SID' - in .NET regex substitution
   '$_' is a token for THE ENTIRE INPUT STRING (would inject the whole script); must be '$$_.SID'.
   Verified end-to-end: v3 [ScriptBlock]+Invoke-HKCURegistrySettingsForAllUsers snippet -> clean
   Invoke-ADTAllUsersRegistryAction -ScriptBlock { Set-ADTRegistryKey ... -SID $_.SID }; Test-Build PASSED.
   2026-06-10 full-tool review -> minor hardening round (user-approved):
   FIXED:
   - Log truncation: background jobs no longer call Initialize-Log (it TRUNCATED the session log on every
     publish/manage action); jobs append via lazy Get-LogPath. Only GUI startup truncates.
   - Single-job gate: $script:ActionButtons (all 19 action buttons) + Set-ActionButtons used by BOTH
     Start-PublishJob and Start-SccmManageJob - no more concurrent jobs fighting over the shared progress
     bar/status/log. + Window Closing handler warns if a job is still running ($script:JobRunning).
   - robocopy exit check in Copy-PackageToPrelive: >=8 on Content copy = FAIL (no silent partial content);
     side-folder (Documents/Icons) failures log a warning.
   - /MIR guard: Copy-PackageToPrelive refuses to mirror unless the source contains Invoke-AppDeployToolkit.ps1
     (a wrong browse/typo can no longer wipe good prelive content).
   - Exists-check BEFORE the prelive copy in New-SccmApplication (connect -> check duplicate -> THEN copy);
     duplicate names now fail in seconds, not after a multi-GB copy.
   DECIDED / WON'T FIX (user):
   - Intune sign-in per action: KEEP - fresh token each action avoids expiry errors on long sessions.
   - .intunewin leftovers on failed uploads: KEEP - user can upload them manually.
   - Prelive folder not deleted on app delete: KEEP - recopy replaces it; current exists/replace behavior fine.
   DEFERRED (documented, not implemented): cancel button for running jobs (DistWaitSec cap is the guard);
   per-job CCM_Application WMI timeout; Find-OutgoingPackage wildcard fallback tightening; instance mutex /
   shared-log contention; state autosave across restarts; Sccm/Intune golden tests; Graph beta->v1.0 migration;
   WATCH: Microsoft deprecating the "Microsoft Intune PowerShell" first-party app (client 6beebafa) - if the
   tenant flips that, Connect-MSIntuneGraph breaks and the sign-in client must change.
   Verified: 4 files parse clean, no stale refs, XAML balanced, Test-Build PASSED.
   2026-06-10 Pre-Install corruption fix (user-reported via Ps1.txt - Wireshark v3 predecessor):
   ROOT CAUSE: Convert-HKCUAllUsers used NON-GREEDY regex brace matching ('\{(.*?)\}') for
   [ScriptBlock]$X = { ... } capture/removal - a v3 scriptblock containing nested If { } blocks (Wireshark's
   $CAPextension code) got TRUNCATED at the first inner '}', and the def-removal left orphaned tail braces ->
   unbalanced braces -> Build.ps1's (correct, depth-aware) block excision then latched onto wrong braces ->
   empty predecessor-uninstall If blocks + body dumped dedented after a stray '}' (exactly the user's symptom).
   FIX: new Find-ClosingBrace (quote-aware depth counter) + Convert-HKCUAllUsers rewritten: balanced capture of
   each def (span incl. trailing newline), defs removed FIRST by exact span (descending), invoke-by-name inlines
   the FULL body, inline-{...} shape rewrapped via depth matching. ALSO added missing v3 mapping
   Convert-RegistryPath -> Convert-ADTRegistryPath (was left unconverted in the output).
   VERIFIED on a replica of the Wireshark pattern (nested-brace + simple scriptblocks, two invokes): braces
   balanced 4/4, nested Ifs preserved inside Invoke-ADTAllUsersRegistryAction, defs removed, SID swapped,
   converted output PARSES with 0 errors; Test-Build PASSED. (User: re-open Step 3 'Rebuild from inputs'.)
   2026-06-10 FULL PIPELINE AUDIT (user asked: no more corruption-class bugs). Traced predecessor read ->
   v3->v4 conversion -> section extraction/stripping -> assembly -> swaps -> format. FIXED 4 + 1 net:
   - Converter Layer-2 case mismatch: gate was case-insensitive (-match) but inner [regex]::Match was
     case-SENSITIVE -> mixed-case v3 vars ($AppName/$InstallPhase) silently left unconverted. Pattern now (?i).
     VERIFIED: "$AppName"/"$appVersion" both -> $($adtSession.*) incl. inside double-quoted strings.
   - Converter Layer-1 param renames now follow BACKTICK CONTINUATION lines (v3 Execute-MSI calls split with `
     left -Path etc. unconverted on continuation lines -> invalid v4 param). Also (?=\s|$) so a param ending
     the line converts. VERIFIED with a split Execute-MSI -> -FilePath on the continuation line.
   - Converter Layer-3 warning insertion at line 0: $lines[0..(-1)] WRAPS in PS (first+last) -> scrambled
     script when a deprecated call was on the first line. Guarded ($i=0 -> prepend). (Note: path is currently
     near-dead since all deprecated funcs get renamed in Layer 1 first, but the trap is real.)
   - Strip-Boilerplate brace counting now ignores braces inside quoted strings (Get-LineBraceDelta) - a
     '{'/'}' in a string inside a dialog block would have desynced block-skipping and eaten/kept wrong lines.
     VERIFIED with a brace-in-string dialog block.
   - SAFETY NET (the big one): Test-ScriptStructure (real PS parser on the generated script). Surfaced as a
     red "CORRUPT SCRIPT: ..." header in Step 3 AND a Yes/No gate at Create ("does NOT parse - create anyway?").
     ANY future corruption-class bug (unbalanced braces, broken blocks) is now caught before a package builds.
   Audited-and-OK (reasoned, no change): Get-SectionBody non-greedy is correct (markers never nest);
   Invoke-VersionSwap anchored longest-first (golden-tested); Swap-InstallerRefs literal Replace; session-block
   regex matches team template shape; Set-SectionBody insertion anchors; Find-ExistingUninstallBlock is
   depth+quote aware; Format-OutputScript falls back safely when Invoke-Formatter rejects input.
   Verified: 3 edited files parse clean, slice fix proven, XAML balanced, Test-Build PASSED.
   2026-06-10 SECOND-PASS audit (real-scenario contract walk, final-stage): traced MSI/EXE/loose/multi +
   v3/v4-predecessor + fresh builds end-to-end across component contracts. 2 NEW real issues fixed:
   - STALE PUBLISH TARGETS: StepOwns[4] was empty -> CreatedPath/PublishBase survived upstream changes;
     after renaming/rebuilding, Step 4 could publish the PREVIOUS package as if it were the new one.
     Now 4 = @('CreatedPath','PublishBase') - any upstream change disables Publish until rebuilt/reloaded.
   - STALE REBUILD OUTPUT: New-Package overlaid an existing output folder -> old version-named MSI/EXE/zip
     + MSTs survived into the new package content (and step 5 built MSTs for stale MSIs). Now cleans the
     folder first, GUARDED: only when it contains Content\Invoke-AppDeployToolkit.ps1 (clearly our previous
     build) or is empty; refuses to touch anything else.
   Contracts verified OK (no change): New-PackageMst HAS -Properties (extras merge into MST); MST filename
   (<msi>.mst beside the MSI) matches the script's ChangeExtension default; all Assemble helpers exist
   (Find-VendorMst/Resolve-ArpIcon/Save-ArpIcon/Copy-ResolvedSource/...); Get-SccmFieldsFromPackage regexes
   match generated-script shapes (single-quoted session fields, SoftIdent '...' normalised by
   Extract-SessionValues, MAIN-UNINSTALL ProductCode preferred over first-GUID); same-version rebuild =
   version-swap no-op (identical pairs dropped); loose zip/shortcut/ARP path goldens green; icons pipeline
   (copy -> ico->png -> exe-extract fallback); Unblock-File pass on output; publish guards (PublishBase gate,
   ManageReady gate). Final state: 12/12 files parse clean, XAML balanced, ALL TESTS PASSED.
   2026-06-10 scenario-gap pass + Package Builder structure:
   - GAP FIXED: .msp/.iso are selectable installers ($script:InstallerExts) but only MSI/EXE have command
     sets - a single .msp silently produced an EXE-style Start-ADTProcess line. Get-SourceWarning now flags
     unsupported extensions (works with OR without a predecessor; loose-files mode exempt) -> red Step-3
     header "No standard command set for .msp - author commands manually".
   - Clean structure: PackageBuilder.ps1 launcher (STA enforce -> GUI.ps1); README.md (folder map, run cmd,
     settings reference, runtime-output table); BuildStamp -> 2026-06-10.r9; deleted stray Ps1.txt debug file.
     Physical subfolder reorg deliberately NOT done (would touch every dot-source path at final stage; the
     flat engine-module layout is documented in README instead). Window title already "Package Builder".
   - KNOWN LIMITS (documented, accepted): same-FILENAME MSIs in different subfolders share per-MSI props/flags
     (keyed by name at create); here-strings containing unbalanced braces inside v3 HKCU scriptblocks would
     still confuse depth counting (parse-net catches it); paths >260 chars depend on robocopy/long-path policy;
     single quotes inside EXE args would break the quoted -ArgumentList.
   Verified: parse clean (incl. new launcher), ALL TESTS PASSED.
   2026-06-10 MSI-dialog visibility fix (user-reported) + file hiding:
   - Show-MsiPropertiesDialog grid had Foreground #1E1E1E (near-black) on dark rows -> properties invisible
     until clicked. Fixed: Foreground #D4D4D4, dark ColumnHeaderStyle (#2D2D30 bg / #9CDCFE text), grid-line
     brushes, and an EditingElementStyle (dark bg / white text) so IN-EDIT cells are readable too. THIS TIME
     VERIFIED VISUALLY: rendered the exact grid (RenderTargetBitmap -> PNG, real AdobeDesktopApp.msi rows incl.
     AgreeToLicense) and inspected the image - fully readable. Lesson recorded: UI changes need a visual check,
     parse/logic checks don't catch styling.
   - Set-ToolVisibility.ps1 (deploy-time): -Hide sets Hidden attr on all top-level items EXCEPT settings.json,
     snippets.json and PackageBuilder.exe (or the .ps1 launcher until the exe exists); -Show reverts. Hidden
     files still load (explicit paths) - sandbox-verified all three states incl. hidden-folder enumeration.
     NOT run on the dev folder (keeps dev/searches normal); run it on the TEAM copy after the exe build.
     Note for user: Hidden attribute deters casual browsing; it is NOT security (show-hidden-files reveals).
   Verified: parse clean, ALL TESTS PASSED.
   2026-06-10 EMBEDDED-ENGINE exe model (user rejected attribute-hiding - everyone has show-hidden on):
   - Real answer: ship NO .ps1 at all. Build-Exe.ps1 (maintainer-only) concatenates the 10 engine modules
     (BOM-stripped), base64-embeds them as $script:PBEngineSource, appends GUI.ps1 verbatim ->
     PackageBuilder_merged.ps1 -> parse-gate -> Invoke-PS2EXE (-STA -noConsole) -> PackageBuilder.exe;
     merged file deleted after compile. TEAM SHIP LIST: exe + settings.json + snippets.json + Lib\ +
     PSADT_Template\ + ConfigurationManagerPrelive\ (deps only - none of OUR logic readable).
   - GUI.ps1 made DUAL-MODE: header skips file dot-sourcing when $script:PBEngineSource is set (root =
     Get-ToolRoot = exe folder); BOTH job runners pass engine=$script:PBEngineSource and runspaces load via
     . ([scriptblock]::Create($a.engine)) instead of file dot-source when set. Dev mode unchanged (files).
   - VERIFIED: merged 439KB parses clean; engine decodes (230KB); all engine fns define from the string in
     main scope; RUNSPACE job path proven (Parse-PackageName/Invoke-VersionSwap/Get-StandardMstProperties/
     Get-WorkRoot all work from embedded engine in a background runspace). Test-Build PASSED (dev intact).
   - Honest caveat for user: ps2exe embeds the script; a determined person can extract it (ps2exe -extract).
     It fully stops casual viewing/editing/copying - real hard protection would need a different platform.
   - Set-ToolVisibility.ps1 kept as optional extra; superseded by the embedded model for the main goal.
   NEXT: when live testing done -> Install-Module ps2exe -> run Build-Exe.ps1 -> test exe -> ship.
   2026-06-10 rail clip fix + window icon (both VISUALLY verified via RenderTargetBitmap):
   - Step-rail "4  Review and Create" was clipped (rail 132px). Rail -> 152px; N4 renamed "4  Create & Publish"
     (truer name - the step holds Review&Create/Integration/Testing/Troubleshoot/Dev-Test tabs). Render
     confirmed: full label visible, tabs clean.
   - Window/taskbar icon: GUI loads Lib\PackageBuilder.ico onto $Win.Icon when present (defensive, logs on
     failure); Build-Exe.ps1 already uses the SAME file for the exe icon. USER ACTION: drop the .ico as
     Lib\PackageBuilder.ico - both the window and the future exe pick it up automatically.
   2026-06-10 LOADER + PAK architecture (user: embedded exe = hard to update; wants portable/flexible/advanced):
   - SPLIT protection from code: Pack-Engine.ps1 (maintainer) merges all .ps1 (same proven model) -> parse-gate
     -> Deflate compress -> AES-256 encrypt -> PackageBuilder.pak (441KB source -> 128KB opaque binary).
     Loader.ps1 (compile ONCE with ps2exe -> PackageBuilder.exe, never changes): finds pak beside itself,
     decrypts+decompresses IN MEMORY, executes. UPDATE = re-run Pack-Engine + replace ONE .pak file - no
     recompile, no ps2exe, exe untouched forever.
   - AUTO-UPDATE built into the loader: settings.json "UpdatePath" -> newer pak on the share is copied local
     before launch (best-effort, never blocks). Team always current without redistribution.
   - DEPS CONSOLIDATED under ONE Lib\: added Lib\PSADT_Template(.zip) candidates (Build.ps1 Get-TemplateScript +
     Assemble.ps1 Get-TemplateRoot) and Lib\<ModuleRelPath> fallback (Connect-Sccm). Team root = exe + pak +
     settings.json + snippets.json + Lib\ (5 items). Root-level layouts still work (fallbacks, dev unchanged).
   - VERIFIED end-to-end: pak built; decrypt round-trip = exact source; parses clean (0 errors); engine from
     inside the pak runs in a background runspace; pak unreadable as text. All files parse; Test-Build PASSED.
   - Honest note: AES key lives in the loader exe = obfuscation-grade (like ps2exe), not cryptographic-grade
     vs a determined insider; fully stops casual reading/editing/copying.
   SHIP FLOW: [once] Invoke-PS2EXE Loader.ps1 -> exe; [each release] Pack-Engine.ps1 -> copy pak.
   2026-06-10 *** FINAL BUILD SHIPPED ***
   - ps2exe installed (PSGallery). PackageBuilder.pak built (441KB -> 128KB). PackageBuilder.exe compiled
     (134KB; -STA -noConsole, title 'Package Builder', icon Lib\PackageBuilder.ico - user provided the ico,
     product/company/version metadata set).
   - SMOKE-TESTED TWICE: (1) exe in dev folder - GUI up, engine initialized, config+snippets loaded;
     (2) exe in the SHIP folder - loads config from ITS OWN folder (portability proven), AvalonEdit from
     Lib\ beside the exe, process stable, clean shutdown.
   - TEAM FOLDER built at C:\Users\AW140\Downloads\PackageBuilder (253.8 MB, 1112 files, 5 root items):
     PackageBuilder.exe + PackageBuilder.pak + settings.json + snippets.json + Lib\ (AvalonEdit dll,
     IntuneWinAppUtil.exe, PackageBuilder.ico, PowerShell Module\{MSAL.PS,IntuneWin32App},
     PSADT_Template\, ConfigurationManagerPrelive\).
   - Dev folder unchanged (all .ps1 + exe + pak build artifacts stay with maintainer).
   - NOT yet exercised from ship copy (live-test next): Step-4 template pickup from Lib\PSADT_Template and
     Connect-Sccm Lib\ fallback (code paths added + parse-verified; first live build/publish confirms).
   UPDATE FLOW from now on: edit dev .ps1 -> Pack-Engine.ps1 -> copy new .pak to the team folder (or the
   UpdatePath share). The exe never changes.
   2026-06-10 startup popups fix (user-reported): ps2exe -noConsole reroutes EVERY Write-Host to a blocking
   MessageBox -> "Config loaded"/"Snippets loaded" OK-boxes at exe startup. Write-Log now echoes to console
   ONLY when $Host.Name -eq 'ConsoleHost' (dev unchanged; exe silent - log file is the record). Only runtime
   Write-Host in shipped code was Core's Write-Log (grep-verified; maintainer scripts keep theirs).
   SHIPPED AS A PAK UPDATE - first real use of the update flow: Pack-Engine -> copy pak -> done, exe untouched.
   VERIFIED: ship exe MainWindowTitle = 'Package Builder' within 12s (window straight up, no blocking boxes);
   Test-Build PASSED.
   2026-06-11 round 7a - reboot confirmation + reboot-from-tool (user: "after reboot it still says pending; how
   do you confirm reboot done? better to reboot from the tool"):
   - CONFIRM reboot done: Get-SccmInstallState now fetches Win32_OperatingSystem.LastBootUpTime whenever a
     reboot is pending and appends "(last booted <time>, N ago - ...)". If booted <15 min ago yet still
     flagged -> message says it's a SEPARATE pending reboot (Windows Update / pending file rename) and another
     reboot usually clears it; else "reboot the machine to clear it". So the user can see if a reboot happened.
   - REBOOT FROM TOOL: new Restart-SccmMachine (Restart-Computer -ComputerName -Force). GUI: "Reboot machine"
     button (red) next to Check install state in Troubleshoot; CONFIRM dialog first (outward-facing/disruptive
     - "anyone signed in will be logged off"); runs as job action 'reboot'; added to ActionButtons (job gate).
     Needs admin rights + RPC/WMI on the target. Parse fix: "${m}:" (was "$m:" = scope-ref parse error).
   - Shipped pak (478KB->140KB). Test-Build PASSED.
   2026-06-11 round 7c - clarified: it's the bottom PACKAGE "Create" button (BtnNext relabelled 'Create' on
   Step 4) that showed on ALL Step-4 sub-tabs; should only show on Review & Create. FIX: in Show-Step and the
   TabsP4 SelectionChanged, set BtnNext.Visibility = Visible only when the active Step-4 tab header -like
   'Review*', else Collapsed; steps 1-3 always Visible. Render-verified: Create shown on Review & Create,
   hidden on Testing/Integration/Troubleshoot/Dev-Test (bottom bar shows only Back/Reset). (round 7b's
   CreatePanel = the SCCM/Intune create buttons; this 7c = the package-assembly Create button - both done.)
   Parse clean, Test-Build PASSED, pak shipped (484KB->142KB).
   2026-06-11 round 7b - Create buttons hidden during modify (user chose "smaller change, no tab move"):
   - Wrapped the create-only controls (ChkPubAllowInteract + Create in SCCM + Create in Intune) in a named
     <StackPanel x:Name="CreatePanel" Visibility="Collapsed">. It is shown ONLY when a package is loaded for
     creation: Populate-Publish sets CreatePanel.Visibility='Visible'; the two disable paths (Show-Review else,
     Populate-Publish early-return) set 'Collapsed'. So when only modifying an existing app (no package loaded)
     the Create buttons are hidden; Open log / Open work folder stay visible always. Load-from-Outgoing and
     Browse both set CreatedPath then Populate-Publish, so loading a package reveals the buttons.
   - Render-verified the Integration tab XAML loads + CreatePanel toggles cleanly. Parse clean, Test-Build
     PASSED. Shipped pak (478KB->140KB).
   2026-06-11 round 8 - detection-key-not-found via AppDiscovery.log + branding cross-check (user asked which
   part informs them; round 6 only covered detection-fail AFTER a fresh install):
   - GAP: round 6 used AppEnforce.log (post-install not-discovered) + CCM_Application.ErrorCode 0x87D00324.
     Both need a RECENT install enforcement. A standalone "detection rule doesn't match" (app installed earlier,
     rule wrong) had no signal -> just read "Not installed".
   - ADDED Get-SccmDiscoveryResult: reads AppDiscovery.log (the dedicated detection log), tracks the current DT
     via "Performing detection of app deployment type X(" / inline [AppDT "X"], records the LAST 'Discovered'/
     'NotDiscovered' for OUR app. ADDED Test-SccmBrandingPresent: independent check of HKLM\SOFTWARE\VWG\CM\
     <name>\Name (the package's own marker = "the app really is installed").
   - Get-SccmInstallState cross-check (when not in-progress and not installed): branding present but SCCM not
     detecting -> "Installed (package branding key present) but SCCM does NOT detect it" + 0x87D00324 fix note
     (definitive detection-key-wrong). Else AppDiscovery NotDiscovered -> neutral note (rule mismatch if it
     should be installed, else expected). Else Discovered -> note the not-installed reading may be stale.
   - VERIFIED offline (4 cases): ours NotDiscovered/Discovered, other-then-ours (Discovered, no leak), only-other
     (null). Parse clean, Test-Build PASSED. Shipped pak (484KB->142KB).
   2026-06-11 round 6 - detection-failed-after-install (user asked: does the tool capture it? - it did NOT, and
   WORSE my round-4/5 "exit 0 = client catching up" branch would have MASKED it as success):
   - Scenario: installer exits 0 but SCCM's detection rule doesn't match what was written -> app shows failed
     (classic 0x87D00324). Since the installer code is 0, the stale-client branch wrongly called it success.
   - FIX: Get-SccmEnforceStatus now also returns DetectionFailed - within the last enforcement block it sees a
     "Matched exit code N to a Success entry" but still "not discovered"/"not detected" AFTER that success (a
     real success ends "Application discovered"). In Get-SccmInstallState the detection check runs FIRST in
     reconciliation (before the 3010 and exit-0 branches); triggers on the log flag OR appErrCode 0x87D00324.
     Message: "<Install|Uninstall> ran OK but DETECTION FAILED - the app is not detected, so the DETECTION RULE
     does not match what was installed" + the 0x87D00324 explanation (fix via Modify > Update detection),
     installed=false, isError=true (so verdict shows MISMATCH correctly).
   - VERIFIED offline (3 cases): detection-fail block -> flagged + correct message; CLEAN success (ends
     "Application discovered") NOT misflagged; detection-fail signalled by WMI appErrCode 0x87D00324 alone also
     caught. Parse clean, Test-Build PASSED. Shipped pak (474KB->139KB).
   2026-06-13 round 25 - KNOWLEDGE BASE foundation (user vision: KB-driven autonomous packaging). Built
   Analyze-KnowledgeBase.ps1 - READ-ONLY miner of the 922-package live share (\\...\CMLib_LIVE\Apps).
   Per package extracts: identity, template v3/v4, installer type, EXE engine (NSIS/Inno/InstallShield/
   Mozilla/vendor-custom from silent-switch fingerprint), install+uninstall arg strings, auto-update
   suppression recipes (scheduled-task / vendor-updater / policy-config / disable-service), detection facts
   (branding key / uninstall-key ref / WOW6432 / product code), notable cmdlet frequencies. Aggregates
   per-vendor recommendation tables + global stats -> KnowledgeBase.json + _Summary.md. Backtick line-
   continuation joined; trailing escaped-quote backtick trimmed. BUG fixed: param named $Args never bound
   ($Args is a reserved automatic var) -> renamed $Switches + call site. LIVE-TESTED on 25 pkgs: 25 read in
   ~2.5s (=> ~3 min for 922), engines correctly classified (NSIS/Inno/vendor-custom), v3-heavy (~84%).
   Residual gap (acceptable v1): args passed via a $variable aren't resolved (shown empty). This JSON is the
   data layer for the planned recommendation + sandbox-discovery engines; NOT packed into the pak (maintainer
   analysis tool, like Build-Exe/Pack-Engine). Tool runtime unaffected: Test-Build PASSED.
   NEXT (user to trigger): run full 922 -> review findings -> decide which recommendations to wire into the GUI.
   2026-06-13 round 26 - SourceAnalyzer.ps1 (Phase-1 vertical slice of the autonomous-assist packager) + MEASURED it:
   - Built: Get-InstallerEngine (fingerprints NSIS/Inno/InstallShield/WiX-Burn/7z-SFX/WinRAR/Wise/MSIX/MSI-as-OLE
     by scanning the binary's OWN first-6MB bytes - NO external tool, works everywhere), Get-EnginePlan (engine
     -> silent-switch family + confidence), Get-InnerMsi (7-Zip static peek for bundled MSI; msiexec /a fallback;
     7z absent on dev box, present on packaging boxes), Get-SourceAnalysis (folder -> topology {SingleMSI/SingleEXE/
     WrapperMSI/Multiple} + plan), and a -Measure harness scoring engine->switch vs the KB's recorded reality.
   - MEASURED on real EXE packages (n=44): engine identified from bytes 28/44 = 64%; engine-derived switch matched
     the recorded switch only 11/24 = 46% of judgeable. HONEST CONCLUSION (validates the user's instinct): the
     silent switch is NOT purely determined by the engine - vendors layer CUSTOM switches on a standard engine
     (Ansys WiX-Burn uses '-Silent' not /quiet; Vector uses '/noGui /noReboot'; InstallShield apps add '-remove';
     Inno via '/LOADINF=' answer file; some args are $variable-based = KB extraction gap).
   - ARCHITECTURE REFINED BY DATA: engine-fingerprint ALONE is a fallback (46%), not the decider. The reliable
     path = (1) KB EXACT switch for vendor+app when the app was packaged before = the common repackage case,
     effectively the recorded working switch; (2) engine fingerprint as the fallback for brand-new apps;
     (3) sandbox VERIFY either. Same $Args-reserved-variable trap recurred in Test-SwitchMatchesEngine -> fixed
     ($Sw). Tools are maintainer/analysis only (not packed). Tool runtime: Test-Build PASSED.
   2026-06-13 round 27 - KB RECOMMENDATION wired into the GUI (shipped):
   - Analyze-KnowledgeBase.ps1 now also emits KnowledgeBase.Recommend.json (slim 638KB): byVendorApp (newest
     pkg's exact switches = high conf) + byVendor (most-common = medium). Regenerated over all 920 (664 app
     keys, 397 vendor keys).
   - Source.ps1 (packed runtime) gained: Get-InstallerEngine (byte fingerprint, mirrors SourceAnalyzer),
     Get-EngineSwitch (engine->default switch), Get-KBRecommendation (lazy-loads the index from Get-ToolRoot;
     tiers: exact vendor+app=high -> vendor=medium -> engine guess=low -> null). All 3 tiers + live fingerprint
     TESTED (Vector/LicenseClient->'/noGui /noReboot' high; Adobe/<new>->'-p -i -f' medium; new+Inno->/VERYSILENT
     low; GIMP exe->InnoSetup).
   - GUI Step 2: PnlKbHint advisory under the EXE-params - "KB [<engine>] suggests install args: <switch>
     (<conf> - <source>)" + a "Use" button that fills Install args. Non-intrusive, read-only, never auto-fills
     the build. Render-verified. KnowledgeBase.Recommend.json shipped next to the exe (degrades silently if absent).
   - Build stamp -> 2026-06-13.r26 (window title). Parse clean, Test-Build PASSED, pak shipped (156KB),
     ship-exe smoke OK.
   2026-06-13 round 28 - CORPUS CORRUPTION SCANNER + crash fix (user: "find vulnerabilities, prevent corrupted
   packages, smartly ask for manual"):
   - Built Test-CorpusConversion.ps1: runs the tool's OWN pipeline (Read-PredecessorModel -> v3->v4 convert ->
     strip -> Build-PredecessorScript w/ version bump) against real packages, AST-parses the BUILT script, and
     flags parse errors / v3 residue / custom-log loss / build exceptions. A permanent mass-regression/vuln tool.
   - FOUND + FIXED (critical): Convert-HKCUAllUsers CRASHED the whole build on ~2.5% of packages (Adobe Acrobat,
     microTool, ...) - String.Remove overran the string on NESTED/overlapping [ScriptBlock] spans. Fix: drop
     contained spans + clamp removal. Build EXCEPTIONS 17->0 across the corpus.
   - Find-ClosingBrace rewritten to use the PowerShell TOKENIZER (correctly ignores braces in comments / here-
     strings / escaped quotes) - strictly more correct than the old hand counter.
   - Convert-HKCUAllUsers rewritten to POSITIONAL PAIRING (def + its immediate invoke -> one replacement,
     backwards) instead of a name->body hashtable that collided on DUPLICATE var names (corpus showed 8x
     "$HKCURegistrySettings" in one script). custom-log loss -> 0.
   - REGRESSION-checked: Mozilla (user's real workflow) still builds 0 parse errors, custom Taskschedule logs
     intact. Corpus parse-error rate ~10-12% of v3 (was ~12%+crashes).
   - HONEST REMAINING GAP: ~10% of v3 packages with MULTIPLE same-named HKCU scriptblocks in the multi-line
     "= \n {" form still mis-splice (e.g. "$UserProfile" -> "$UserP"+insert). Layered edge cases; needs a
     dedicated careful rewrite (the corpus scan is the test harness). NOT silently shippable: VERIFIED the
     Test-ScriptStructure SAFETY NET flags every corrupted build ("script has N parse error(s) - first at line
     X...") -> red CORRUPT banner + Create gate. So corruption is CAUGHT, never shipped = the "smartly ask for
     manual" guarantee holds.
   - Build stamp -> r28. Test-Build PASSED, pak shipped (157KB).
   2026-06-13 round 29 - HKCU conversion SPLICE FIXED -> v3 parse errors 0 (corruption class eliminated):
   - Replaced the precompute-all-pairs + backward-replace approach (which overlapped on duplicate var names and
     spliced mid-token, "$UserProfile"->"$UserP"+insert) with INCREMENTAL rebuild: find one def, balance-match,
     pair with its immediate invoke, splice out, continue scanning from AFTER the replacement (guard 1000). No
     multi-edit index staleness possible.
   - VERIFIED: Wireshark 4.2.4 (was 3 err+splice) -> 0 err no splice; ITSolution (1 err+splice) -> 0; Mozilla
     stays 0. CORPUS SCAN 150 random: PARSE ERRORS 16->0, build exceptions 0, custom-log loss ~0. The
     v3-conversion corruption class is effectively eliminated.
   - Build stamp r29. Test-Build PASSED, pak shipped (157KB).
   2026-06-13 round 30 - KB suggestion UI overhaul + fixes (user: cramped UI, Wireshark showed nothing, -f file,
   multi-installer EXE suggestions):
   - WIRESHARK FIX: Get-KBRecommendation returned a HIGH-confidence but EMPTY install (exact match recorded
     install='' because the switch was variable-based) and the UI hid it. Now empty exact/vendor matches FALL
     THROUGH to the engine default (Wireshark exe -> NSIS -> '/S'). (Wireshark also has 2 installers: Npcap.msi
     + Wireshark.exe -> previously multi-mode hid the single-EXE hint entirely; now multi rows show per-EXE.)
   - ANSWER-FILE NOTE (the '-f' question): Test-NeedsAnswerFile flags switches that point at a response/answer
     file (-f / /f1 / .iss / -inputFile / /LOADINF). The panel shows a yellow note: the file path is package-
     specific (KB stores the switch pattern, not the old path) -> supply it from THIS source or capture via
     sandbox later. Answer: yes, the file is determined from the source/instructions/sandbox, not the KB.
   - UI OVERHAUL: replaced the one-line cramped hint with a spacious bordered CARD - title, color-coded
     [engine] + confidence, install args in a dark monospace box, "Use these args" button, answer-file note,
     source line. Render-verified.
   - MULTI-INSTALLER: each EXE row in Multiple mode now shows its own "KB [engine]: <args>" + Use button
     (MSI rows unchanged - /qn+MST). Per-installer fingerprint + lookup.
   - Build stamp r30. Parse clean, Test-Build PASSED, pak shipped (158KB), ship-exe title confirms r30.
   2026-06-13 round 31 - per-installer EXE args in the KB (user: Wireshark suggested only "/S" but the package
   used "/NCRC /S /desktopicon=no /quicklaunchicon=no"):
   - Analyzer now captures EXE args SEPARATELY (ExeArgs) and the index stores exeInstall/exeEngine per app, so
     a multi-installer package's EXE switches aren't lost when an MSI is also present (Wireshark = Npcap.msi +
     Wireshark.exe was classified MSI -> EXE args dropped). Get-KBRecommendation prefers exeInstall when the
     selected installer fingerprints as an EXE engine. Also: pick the EXE call whose FILENAME matches the APP
     name (not the first exe = often a prerequisite like Npcap with bare /S), preferring calls that have args.
   - RESULT: Vector now correctly suggests '/noGui /noReboot /userSettings'. BUT Wireshark still shows '/S':
     its newest folder (4.6.5) has NO parseable install command (skeleton), and the older Wireshark command
     form stores the rich args via a variable/splat the regex can't follow. HONEST LIMIT: the KB hint is
     mechanically-extracted and imperfect for variable/splat/multi-line command forms - it's a STARTING POINT.
   - KEY (told user): in the predecessor-REUSE flow the build carries the predecessor's ACTUAL command VERBATIM
     (installer-swap preserves the full args) - the KB hint does NOT replace it. So a reused Wireshark KEEPS
     '/NCRC /S /desktopicon=no /quicklaunchicon=no' regardless of the hint. The hint is advisory, most useful
     for brand-NEW apps. (Deeper fix later: follow $variable/@splat arg definitions in the analyzer.)
   - Build stamp r31. Test-Build PASSED, pak + refreshed index (750KB) shipped.
   2026-06-13 round 32 - SAME-INSTALLER matching + variable-resolved args ("almost perfect" for known installers):
   - EXTRACTION: Resolve-ArgString now follows a $variable arg ("$p = '/NCRC /S ...'" then "-ArgumentList $p")
     to its literal assignment - recovers FULL commands the literal-only regex missed (the real reason Wireshark
     stored "/S"). Applied to MSI + EXE arg capture.
   - NEW TIER-0 MATCH: byInstaller index keyed by FUZZY installer filename (Get-InstKey: version-stripped,
     separators collapsed -> "Wireshark-4.6.5-x64.exe" & "Wireshark-4.4.7-x64.exe" both = "wiresharkx64").
     Stores the newest package's recorded command per key. Get-KBRecommendation now: TIER0 same-installer
     (high) -> exact vendor+app -> vendor -> engine default. GUI passes the selected installer's Name (single +
     multi rows). Identical Get-InstKey in analyzer + Source.ps1 so keys line up.
   - VERIFIED: selecting Wireshark-4.6.5-x64.exe now returns "/NCRC /S /desktopicon=no /quicklaunchicon=no"
     (high, "same installer: Wireshark-4.2.4-x64.exe") - the full real command, recovered via var-resolution +
     fuzzy match. 321 installer keys. Re-mining adds new packages/keys automatically (user's extensibility ask).
   - Index built from 882/920 this run (38 transient network read timeouts, not a code bug - data sane); re-run
     -All on a stable share to capture all. Build stamp r32. Test-Build PASSED, pak+index (920KB) shipped.
   2026-06-13 round 33 - installer-name robustness (user: "installer names will be different - how handled?"):
   - Explained tiering: filename match is TIER 0; a RENAMED installer (same app) misses it and falls back to
     Vendor+App (keyed on the package FOLDER name, not the installer file) -> still gets a command; then engine.
   - Fixed the CONVERSE risk it exposed: generic installer names (setup.exe/install.exe) keyed purely on
     filename would cross-match BETWEEN vendors at high confidence (false positive). Now byInstaller keys are
     VENDOR-SCOPED "<vendor>::<key>"; the bare "<key>" is stored ONLY for SPECIFIC (non-generic, len>=5,
     not in {setup,install,...}) names. Get-KBRecommendation tier-0 tries "<vendor>::<key>" first, then the
     bare key only for specific names. byInstaller entries now carry vendor/app.
   - VERIFIED: Wireshark specific name -> full '/NCRC /S /desktopicon=no /quicklaunchicon=no' (high); renamed
     Wireshark file -> vendor+app fallback (high); generic setup.exe for unknown vendor -> engine default /S
     (NO cross-vendor command); bare 'setup' key not stored. 706 keys (396 scoped + 310 specific-bare).
   - Build stamp r33. Test-Build PASSED, pak+index (1346KB) shipped.
   2026-06-14 round 46 - network-drive launch fix + nested-setup awareness (user: "manual Run won't launch - UAC
     prompt then nothing; the EXE sometimes extracts ANOTHER setup; SentinelOne runs from a network drive").
   - ROOT CAUSE: a network/UNC path is invisible to an ELEVATED process (separate logon session) + many wrappers
     refuse to extract beside a read-only/UNC path -> "approve UAC, nothing happens". FIX: Copy-InstallerLocal
     copies the installer (+ small siblings) to a LOCAL folder; the manual Run now does that then Start-Process
     -Verb RunAs -WorkingDirectory <local>; the SANDBOX Capture.ps1 copies the read-only-mapped installer to
     C:\inst before running. NESTED SETUP: Get-NewSetupsSince/Get-SetupSnapshot - the Scan now reports extracted
     setup*.exe ("no MSI yet, but it extracted setup.exe - let it run further"). Tested: local-copy + capture OK.
     Build stamp r46.
   2026-06-14 round 52 - SNAPSHOT engine (Phase 2 of the "what did the installer do" plan). Sandbox-INDEPENDENT:
     runs on the current machine, user manually triggers the install between two snapshots; sandbox automation is
     a later layer. (user: "uninstall written automatically from snapshot; works with or without sandbox; manual
     trigger now, auto via sandbox later - correct".)
   - New Snapshot.ps1: Get-MachineSnapshot captures 9 categories fast (~13s): Programs (Uninstall entries -
     detection + UNINSTALL come from here), Services (+image path), Scheduled Tasks, Run keys, Shortcuts,
     Certificates, Drivers (DriverStore packages), Printers/print-drivers, Program folders. Compare-MachineSnapshot
     diffs before/after into per-category ADDED vs background NOISE. Test-IsSnapshotNoise is CONTEXT-AWARE: a
     noise token (microsoft/edge/mcafee/citrix/vmware/sccm/defender/redist...) is filtered ONLY when it doesn't
     match the app's own vendor/name - so a Citrix app shows Citrix changes, a McAfee app shows McAfee. Nothing
     deleted (noise just collapses). Get-UninstallFromSnapshotDiff picks the app's new Uninstall entry and derives
     DisplayName/Version/ProductCode + the (Quiet)UninstallString -> for auto-writing the ps1 uninstall + detection.
   - VERIFIED with a synthetic install: counts populated (Programs 185/Services 339/Drivers 765/...); MyTestApp +
     its update service + shortcut detected as ADDED; Edge Update filtered as NOISE; ProductCode + quiet
     uninstall derived; context test - Citrix kept when app=Citrix, filtered otherwise (after adding 'citrix' to
     the noise list). Snapshot.ps1 added to GUI dot-source + Pack-Engine + Test-Build. (Perf: ~13s/snapshot - fine
     for one-time; could trim DriverStore/Tasks later.)
   - Build stamp r52. Test-Build PASSED, pak shipped (201KB, now includes Snapshot.ps1).
   2026-06-15 round 52b - SNAPSHOT GUI integration (Phase 3). New "Analyze installer (snapshot)..." button in its
     own Step-2 panel (PnlSnapshot), shown for ANY real installer (lone EXE, MSI, or multiple - not loose files),
     so it covers the multi-installer cases (Avigilon EXE->EXE->MSI, Citrix VDA) too. Show-SnapshotDialog: baseline
     auto-captured on open (Dispatcher Background so the window paints first), "Run installer (manual)" reuses
     Copy-InstallerLocal+RunAs, then "Analyze" takes the after-snapshot, diffs, and renders a SIMPLE categorised
     report (Programs/Services/Tasks/Autostart/Shortcuts/Certs/Drivers/Printers/Program folders) with each
     category's background NOISE collapsed to one grey italic line. New Get-SnapshotCleanups derives tick-to-apply
     cleanups (auto-update service/task -> ticked; desktop shortcut -> ticked; plain service/run-key -> unticked;
     start-menu shortcut ignored). On Apply: a real MSI ProductCode is written to the field (drives the build's
     uninstall + detection AUTOMATICALLY); the captured uninstall command + every ticked cleanup become Review
     items (SnapshotNotes -> Get-CombinedReview). EXE uninstall strings are surfaced as ready-to-paste review notes
     (path is machine-specific, not injected blindly). New state: SnapshotNotes, SnapshotUninstall (owned by Step 2,
     cleared on upstream change). VERIFIED: cleanup logic + uninstall derivation unit test ALL PASSED; offscreen STA
     render of the dialog controls OK (FontStyle/dynamic-children/checkboxes all valid); GUI.ps1+Snapshot.ps1 parse
     clean; merged pak passed the parse gate; Test-Build PASSED. Pak shipped (206KB).
   2026-06-15 round 53 - live-test bug fixes (SentinelOne + JMatPro).
   - BUG (snapshot won't analyze - "baseline pending even though done"): each {..}.GetNewClosure() WPF handler has
     its OWN scope, so $script:SnapBefore written in the Loaded handler's async dispatcher action was invisible to
     the Analyze handler (the button enabled fine - a shared object ref - but the scalar didn't cross). FIX: one
     shared reference hashtable $ctx (Before/Result/DiffUninstall/Cleanups) captured by every closure; mutate
     fields, never reassign. Saved as memory [[ps-wpf-closure-scope]]. Applies to all Show-*Dialog functions.
   - BUG (SentinelOne KB hint showed common params, NOT "previously packaged as MSI+MST"): the PackagedAsMsi signal
     only lived in the byVendorApp tier, but Tier-0 (same-installer fingerprint) returns FIRST and masked it. FIX:
     an $annotate scriptblock now runs on EVERY tier's result - if the source is an EXE ($wantExe) and the
     recommended install command is an MSI command (Start-ADTMsiProcess/msiexec/.msi), it sets PackagedAsMsi+Type=
     MSI and appends "(previously packaged as MSI+MST)". VERIFIED with a fake-KB integration test (Tier-0 hit ->
     PackagedAsMsi True, Type MSI, uninstall preserved).
   - BUG (SentinelOne "invalid image" on launch + a McAfee DLL error popup): re-running an EDR/AV installer on a
     protected endpoint that already has it is blocked by tamper protection / the resident agent. New
     Test-IsSecurityProduct (sentinel/crowdstrike/mcafee/defender/cortex/xdr/edr/symantec/sophos/eset/...) gates
     BOTH "Run installer" buttons (MSI-capture + snapshot) with a strong warning that steers to 'Check for bundled
     MSI' (no execution) or a sandbox. Does not block - just warns + lets the user bail.
   - Build stamp r53. Test-Build PASSED, all unit/integration tests PASSED, pak shipped (208KB).
   2026-06-15 round 54 - live-test round 2 (SentinelOne / JMatPro / Kistler).
   - SentinelOne KB STILL not showing "MSI+MST" after r53: real cause was in Update-KbHint, not the recommender.
     Get-KBRecommendation DOES return PackagedAsMsi for SentinelOne (byVendorApp type=MSI), but its Install is
     EMPTY (MSI installs via the MST, no params) and the hint's guard `-not $rec.Install.Trim()` treated that as
     "no match" and fell to the engine default BEFORE the PackagedAsMsi block. Fixed: guard now also checks
     `-and -not $rec.PackagedAsMsi`. (Confirmed the KB has SentinelOne|SentinelAgent type=MSI, install empty.)
   - "Check for bundled MSI" failed for SentinelOne: 7-Zip wasn't installed at the time (Get-ArchiveTool returned
     null), and the static byte-scan gives a FALSE "no MSI / custom installer" because SentinelInstaller.msi
     (70MB) is stored in a PE RESOURCE the scan can't see. With 7-Zip present, Find/Expand-BundledMsi extract it
     correctly (VERIFIED: 0.9s, valid MSI ProductCode {7CCB2DE9-...}). Added a clear message when 7-Zip is missing
     ("limited static check can't see a resource-stored MSI - install 7-Zip and retry").
   - Kistler launch "UAC declined / operation cancelled, nothing changed": forced RunAs + the installer's OWN
     manifest elevation conflict. New Start-InstallerLaunch tries RunAs, and on cancel/1223 falls back to a normal
     launch (lets the manifest self-elevate). Both Run buttons use it; clearer failure text.
   - SNAPSHOT thoroughness (the headline): the old scan only captured targeted surfaces + top-level dirs and
     "missed too many things". Added DEEP capture - Get-PathSet (full recursive FILE tree under ProgramFiles/x86/
     ProgramData/AppData + Windows\drivers\Fonts\Installer\Tasks, cache dirs pruned) and Get-RegKeySet (full
     recursive HKLM/HKCU SOFTWARE + Services + Installer\Products; the giant SOFTWARE\Classes COM store is pruned
     - it was 100k+ keys, dominated time AND hit the cap, TRUNCATING the diff = the "missing things"). Diff via
     Get-SnapshotRawDiff + Group-SnapshotPaths (grouped by folder/key with counts). ~22-38s/capture, RELIABLE (no
     truncation). VERIFIED: 5 synthetic files + 3 reg keys detected exactly. Report now shows "Files created (N)"
     and "Registry keys created (N)" grouped sections. Status text warns the window may be unresponsive ~30-60s.
   - Certificates section now shows the thumbprint + a one-shot "Open certmgr" button; Drivers section a "Open
     DriverStore folder" button (per category, not per item) - user request.
   - Unknown EXE (no KB + no engine switch): new "Probe installer for /? help" button -> Get-InstallerHelp runs
     /? /help --help -h NON-elevated, captures console output, shows it in a new Show-TextDialog. VERIFIED it
     captured 1668 chars from where.exe /?.
   - Build stamp r54. Test-Build PASSED; parse + probe + launch + deep-capture + render tests PASSED; pak 215KB.
   2026-06-15 round 55 - WHOLE-SYSTEM snapshot (user: "widen through system, dont want to miss anything even if it
     takes time"). Replaced the scoped deep scan with a full-machine differ:
   - FILES: Get-PathMap walks EVERY fixed drive in full (DirectoryInfo enumeration = size+mtime for free), storing
     path -> "len|mtimeTicks", so the diff catches NEW *and* MODIFIED files (not just new). Only $Recycle.Bin /
     System Volume Information / recovery dirs are skipped at capture. Measured: ~24s warm / ~74s cold, 298k files,
     ~35MB.
   - REGISTRY: Get-RegMap walks HKLM\SOFTWARE (incl the Classes/COM store), HKLM\SYSTEM\CurrentControlSet, HKCU\
     SOFTWARE, HKCU\Environment, storing keypath -> value-signature, so the diff catches NEW keys AND value changes
     (PATH/env/config). Values are read everywhere EXCEPT under Classes/COM (key-presence only there - reading every
     COM value was prohibitively slow; a probe that did never finished). Measured: ~92s, 533k keys. (HKCR dropped -
     it's a merged view of SOFTWARE\Classes we already cover, was double-walking.)
   - ENV VARS: Get-EnvSnapshot + Get-EnvDiff surface added/changed machine+user variables (PATH is the canonical
     value change a key-only diff would miss in plain text).
   - Diff (Get-SnapshotRawDiff) now returns {Path;Change=new|modified} + Modified/Deleted/Noise counts. OS churn is
     routed to a collapsed NOISE count (never dropped) via a broad path/key noise regex. Report shows "Files - N
     new/changed (M modified)", "Registry keys/values - ...", and an "Environment variables" section.
   - PERF/UX: a full capture is ~2-3 min, so it now runs on a BACKGROUND runspace (Start-SnapshotJob, mirrors
     Start-PublishJob) with an indeterminate ProgressBar - the window stays responsive (no more "Not Responding").
   - VERIFIED (fastdiff, tiny roots): 3 new files + 1 MODIFIED file, new reg subkey + CHANGED reg value, env
     added + env changed all detected exactly; Temp-path files correctly routed to noise. Timing measured on real
     C:\ + registry. Test-Build PASSED, pak 218KB shipped (r55).
   - NOTE: still NOT captured: registry VALUES under the COM/Classes store (keys only there), and file CONTENT
     (size+mtime is the modify signal). Everything else under all fixed drives + the main hives IS diffed.
   2026-06-15 round 56 - SentinelOne KB hint + elevation-aware probe.
   - ROOT CAUSE of "still no MSI+MST hint": the SentinelOne EXE fingerprints as ENGINE='unknown', so $wantExe was
     FALSE, and the byVendorApp "previously packaged as MSI+MST" branch (and the annotator) were gated behind
     $wantExe - so they never fired for an unidentifiable EXE. The MSI+MST hint should depend on "the current
     source is NOT itself an MSI", not on a KNOWN engine. Added $srcNotMsi = Engine notin MSI/MSI-as-OLE/MSIX, and
     switched the type=MSI byVendorApp branch + the annotator to use $srcNotMsi. VERIFIED against the real KB: with
     package SentinelOne_SentinelAgent + the unknown-engine exe, rec now = PackagedAsMsi True, Type MSI,
     "(previously packaged as MSI+MST)". (Combined with r54's Update-KbHint guard fix, the hint now shows.)
   - Probe /? failed with "requires elevation" for SentinelOne (manifest forces elevation; UseShellExecute=$false
     can't elevate). Get-InstallerHelp now detects the 740/elevation error and retries ONCE elevated, redirecting
     the installer's output to a temp file via `cmd /c "exe" /? > tmp 2>&1` (Start-Process -Verb RunAs, one UAC
     prompt), bounded by WaitForExit so a GUI installer can't hang the UI. Reads + returns the captured text;
     notes if the elevated run produced no console text (GUI help). Probe button confirm text updated to mention
     the possible UAC prompt. (Non-elevated path unchanged + still verified on where.exe.)
   - Build stamp r56. kbtest + fixtest PASSED, Test-Build PASSED, pak 219KB shipped.
   2026-06-15 round 57 - baseline capture "runs forever" fix. The whole-drive file walk followed REPARSE POINTS
     (junctions/symlinks). Windows has self-referential junctions (C:\ProgramData\Application Data -> C:\ProgramData,
     C:\Users\All Users -> ProgramData, the per-user Application Data/Local Settings junctions) that make a naive
     recursive walk LOOP FOREVER - that was the "baseline still running so long" (and likely the error). Fix:
     Get-PathMap now SKIPS any directory with the ReparsePoint attribute, and both Get-PathMap (300s) and Get-RegMap
     (240s) have a wall-clock cap as a final safety net so capture ALWAYS terminates. VERIFIED: whole C:\ now 296,038
     files (vs 298,166 before = only the ~2k junction-dup entries dropped, no real content lost), completes in ~61s.
     Build r57, Test-Build PASSED, pak 219KB shipped.
   2026-06-15 round 58 - snapshot: fix runtime closure error + make it FAST (user: "property X cannot be found"
     during baseline + "taking >2.5 min, reduce time, cover MAIN things, ignore junk").
   - BUG ("the property Visibility/Before/Text/IsEnabled cannot be found"): the Start-SnapshotJob -OnDone callback
     is a NESTED closure (created inside the already-closured add_Loaded/add_Click handler). A scriptblock created
     inside a closure does NOT inherit the handler's CAPTURED (module-scope) vars - so $pb/$ctx/$lblStat/$bAnalyze
     were $null in the callback. Reproduced + proved in isolation: $script: is ALSO isolated per-closure (fails);
     $global: and a same-name LOCAL RE-BIND both work. Fix: re-bind the needed vars to true locals at the top of
     each handler ($pb=$pb; $ctx=$ctx; ...) before creating the -OnDone closure, so it captures them. Extended
     memory [[ps-wpf-closure-scope]].
   - SPEED: reverted the whole-system scan to FOCUSED MAIN locations. Files: ProgramFiles/x86/ProgramData/AppData
     (Roaming+Local) + Windows\{drivers,SysWOW64\drivers,Fonts,Installer,Tasks,spool\drivers} - NOT all of C:\ (which
     spent its time in WinSxS/OS junk). Cache/Temp dirs are pruned DURING the walk now. Registry: the SOFTWARE\
     Classes COM/file-association store is PRUNED ENTIRELY (was ~380k of the 533k keys + most of the 92s); value-
     change detection kept for the rest. Services still captured via CIM regardless. Reparse-skip + time caps from
     r57 retained. VERIFIED: fastdiff correctness still PASSES (new/modified files, new/changed reg, env). Test-
     Build PASSED, pak 220KB shipped (r58). Capture target ~1 min instead of ~2.5-5.
   2026-06-15 round 59 - snapshot SPEED (cont). Measured the split: FILES (focused roots) 3.7s/78k warm; REGISTRY
     with per-key VALUE reads 52s/167k; registry KEY-PRESENCE-ONLY 14s. The value-reads were ~the entire cost.
     Switched Get-RegMap to key-presence by default (new -ValuesToo switch kept for a future deep mode), dropped
     HKLM\SYSTEM\CurrentControlSet (device-Enum noise; services via CIM). Full capture now ~18s warm / ~35s cold
     (was ~65-153s). Trade: generic value-change in arbitrary reg keys no longer flagged - the value changes that
     matter are still shown via the Services (CIM) / Autostart (Run) / Environment (PATH) sections. fastdiff still
     PASSES (new+modified files, new reg key, env add/change). Report registry note updated. r59 shipped, 220KB.
   2026-06-15 round 60 - snapshot: fix Analyze crash + replicate proper repackager methodology (less junk + app
     surfaced). User: "property text cannot be found at analyze; data is junk + actual application not shown; check
     online how snapshots are done properly".
   - CRASH: the Analyze -OnDone callback used $lblSummary but it was MISSING from the re-bind list (only $pb/$ctx/
     $lblStat/$bAnalyze/$bApply/$rep/$AppVendor/$AppName were rebound) -> $lblSummary $null -> "property Text cannot
     be found", which threw mid-render (hence the half/junk report). Added $lblSummary to the rebind. Lesson added
     to memory [[ps-wpf-closure-scope]]: EVERY control the nested callback touches must be rebound.
   - METHODOLOGY (WebSearch'd AdminStudio/Advanced Installer/Master Packager): the two pillars are (1) a CLEAN
     machine image and (2) a custom EXCLUSION LIST. Replicated: (a) Test-IsVendorNoise + $SnapshotBgVendors - a
     context-aware exclusion list (microsoft/windows/mcafee/sentinel/crowdstrike/google/intel/teams/office/citrix/
     vmware/ccm/... + OS churn) applied to the file AND registry diffs, so background-agent noise on a production
     box is filtered UNLESS the app being packaged IS that vendor; (b) Test-IsAppItem tags items matching the app
     vendor/name; Get-SnapshotRawDiff now takes -AppTokens, tags New items .IsApp, and routes vendor/OS noise to
     the collapsed count. (c) New "* APPLICATION DETECTED" section at the TOP of the report: DisplayName/Version/
     Publisher + ProductCode + uninstall (from Get-UninstallFromSnapshotDiff) + the app's own install folder(s)
     (IsApp file groups) - so the actual app is front-and-centre, not buried. (d) Hint now recommends a clean VM +
     closing other apps for the cleanest capture. VERIFIED (vendortest): JMatPro files kept+flagged IsApp; McAfee/
     Microsoft/Google filtered as noise; unknown 3rd-party kept. fastdiff + Test-Build PASSED. r60 shipped, 221KB.
   2026-06-16 round 61 - snapshot report REDESIGN (user: "show clearly what was created for the app; junk just
     hidden; must be able to COPY; organize properly").
   - New engine fn Get-SnapshotReportText builds ONE organized, plain-text report: (1) APPLICATION (name/version/
     publisher/ProductCode/uninstall + install location(s)); (2) CREATED BY THE APP - only app-matching items per
     category (programs/services/tasks/run/shortcuts/certs/drivers/printers) + app registry keys + env changes;
     (3) OTHER NEW ITEMS (non-app, non-vendor - possible prerequisites); (4) a single "(N background/OS/vendor
     items hidden as noise)" line - junk is HIDDEN, not listed. VERIFIED (reporttest): app surfaced, McAfee/OS
     hidden, prereq in Other, counts right.
   - UI: the report row is now a read-only, SELECTABLE/COPYABLE Consolas TextBox (not a StackPanel of TextBlocks);
     added a "Copy report" button (-> clipboard) + certmgr/DriverStore buttons in the bottom bar; the recommended-
     cleanup checkboxes moved to a compact scroll area below. Dialog grid went 4->5 rows. Removed the old rich
     category/deep/env rendering entirely.
   - Also fixed the lingering Analyze crash root cause from r60 testing surfaced again here ($lblSummary rebind was
     already added r60; this round removed the code paths that referenced unbound controls).
   - VERIFIED: report generator test + vendor/fastdiff tests pass; offscreen render of the new 5-row layout OK;
     Test-Build PASSED. r61 shipped, 222KB.
   2026-06-16 round 62 - generated EXE -ArgumentList quoting. User wants the ps1's -ArgumentList in DOUBLE quotes
     with any inner double-quote backtick-escaped. Fixed in Get-ExeCommandSet (Build.ps1, the single source for
     both single + multi-installer EXE commands): $eaI/$eaU = params with `"` -> "`"" (-replace '"','`"'), emitted
     as -ArgumentList "$eaI". e.g. /S -> -ArgumentList "/S"; /S /v"qn" -> -ArgumentList "/S /v`"qn`"". Test-Build
     assertion updated + a new escaping assertion; both PASS. r62 shipped, 222KB.
   2026-06-16 round 63 - snapshot: SysTracer-style report (full paths) + write the captured uninstall into the ps1.
   - (a) UNINSTALL NOW WRITTEN TO PS1: new Convert-RawUninstallToPsadt (Build.ps1) turns a captured Add/Remove
     uninstall string into a PSADT line - MsiExec /X{GUID} -> Start-ADTMsiProcess -Action 'Uninstall' -ProductCode
     '{GUID}'; "C:\..\unins000.exe" /SILENT -> Start-ADTProcess -FilePath '...' -ArgumentList "/SILENT" (+ a
     REVIEW note that the path is capture-derived). Get-ExeCommandSet takes -UninstallCommand (priority over the
     installer-exe+args fallback); New-StandardCommands passes NewPkg.UninstallCommand; the Step-3 builder sets
     NewPkg.UninstallCommand = State.SnapshotUninstall for a lone EXE. Test-Build verifies both forms land in the
     ps1.
   - (b) FULL PATHS, no "..." (user: "data incomplete, cant we get full path"): researched SysTracer (full-path
     tree, +/~/- markers, organized by category, show-only-differences). Get-SnapshotReportText rewritten to list
     EVERY file/registry path IN FULL (no Group-SnapshotPaths collapsing), each marked [+] added / [~] modified /
     [-] deleted, sorted, capped at 5000/section ("Copy report" gets all). Get-SnapshotRawDiff now also returns a
     Deleted list (app/non-noise) so deletions show too. Organized: APPLICATION header, CREATED BY THE APP (Files/
     Registry/Services/Tasks/Shortcuts/Certs/Drivers/Printers/Env), OTHER NEW ITEMS, hidden-noise count.
   - VERIFIED: reporttest (full paths + markers, app-first, junk hidden) + Test-Build (uninstall written) PASS.
     r63 shipped, 223KB.
   2026-06-16 round 64 - SysTracer-style THOROUGH scan + write cleanups into the ps1.
   - SCANNING now SysTracer-grade: re-enabled registry VALUE capture (Get-MachineSnapshot calls Get-RegMap
     -ValuesToo), so the diff catches registry value CHANGES (not just new keys), matching SysTracer's keys+values
     capture. Files already carry size+mtime (modified detection). ~1 min/capture (the speed tradeoff the user
     accepts for completeness).
   - CLEANUPS now WRITTEN INTO THE PS1 (user: "runkey and desktop shortcut should be removed in ps1 file"):
     Get-SnapshotCleanups now emits a real .Command per cleanup (Service -> Stop/Set-Service Disabled; Task ->
     Disable-ScheduledTask; RunKey -> Remove-ADTRegistryKey; Desktop shortcut -> Remove-ADTFile). The dialog Apply
     collects TICKED cleanups' commands into result.CleanupCommands -> State.SnapshotCleanupCommands; the Step-3
     builder sets NewPkg.PostInstallExtra; New-StandardCommands adds $cmds.PostInstall; Add-StandardCommands now
     injects it into the POST-INSTALLATION section. Run-key + desktop-shortcut cleanups default to TICKED. Verified
     (Test-Build): cleanup commands generated + written into POST-INSTALLATION; uninstall (MSI/EXE) written.
   - UNINSTALL reaffirmed: r63's Convert-RawUninstallToPsadt + UninstallCommand wiring confirmed (MSI->ProductCode,
     EXE->path+args). Report stays category-organized with full paths + +/~/- markers.
   - r64 shipped, 224KB. Test-Build + report tests PASS.
   2026-06-16 round 65 - fix "argument types" crash + AdminStudio/SysTracer category report + open-specific-cert.
   - CRASH FIX (user: "argument type not found during baseline AND analyze"): Get-SnapshotRawDiff returned New /
     Deleted as List[object] of PSObjects; the report's @($FileDiff.New) wrapping threw the PS 5.1 "Argument types
     do not match" ([[ps51-list-object-wrap]]). Fixed: return .ToArray(). Reproduced the WHOLE pipeline clean
     afterwards (repro.ps1 - every stage OK; value-change detection [~] confirmed).
   - REPORT REORGANISED by CATEGORY (user: "Files and under it only files... registry drivers certificates
     services shortcuts"): APPLICATION header -> CHANGES BY CATEGORY summary counts -> a section per category
     (FILES & FOLDERS [app + other/prereq, full paths], REGISTRY, SERVICES, DRIVERS, CERTIFICATES, SHORTCUTS,
     SCHEDULED TASKS, AUTOSTART, PRINTERS, PROGRAMS, ENVIRONMENT) each with +/~/- markers. Small categories now show
     ALL their Added items (noise already filtered by Compare) instead of app-token-filtered, so drivers/certs/
     services always appear. Fixed a `.Add("...-f a,b")` trap (comma went to .Add) by parenthesising the -f.
   - CERT VALIDATOR: new Open-CapturedCertificate (exports the cert by thumbprint to a temp .cer + launches the
     Windows cert viewer) + Show-CertPickerDialog; the bottom-bar button is now "Open certificate..." -> pick which
     captured cert and view it DIRECTLY (not just certmgr). Certs stored in $ctx.Certs at analyze; thumbprint shown
     in the report.
   - SCAN already SysTracer-grade (r64 registry values). VERIFIED: report + Test-Build + repro all PASS. r65, 225KB.
   - STILL OPEN (user "replicate AdminStudio Repackager... exclude=remove, include=default remaining, add custom per
     category"): an INTERACTIVE per-category include/exclude tree (+ add-custom) is the next big build. NOTE the
     architecture: our tool WRAPS the vendor installer via PSADT (it doesn't rebuild an MSI from the capture like
     AdminStudio), so include/exclude here = curating which captured changes become package customizations
     (cleanups/uninstall/notes), not packaging captured files. Needs a design decision with the user.
   2026-06-16 round 66 - EXCLUSIONS (the AdminStudio piece, scoped). User decision: "only exclusions, wrapped into
     PSADT; inclusions = current logic, no change." So NOT a full repackager - we keep wrapping the vendor installer
     and only EXCLUDE (remove) chosen items. Auto-suggested exclusions (shortcut/Run-key/service/task) already wrap
     into POST-INSTALLATION (r64). Added "add custom exclusion": new Get-ExclusionCommand turns a typed file /
     folder / registry key / shortcut into the right PSADT removal (Remove-ADTFile / Remove-ADTFolder /
     Remove-ADTRegistryKey, with HKLM\ -> HKLM:\ normalisation). New "Exclude item..." button + Show-InputDialog in
     the snapshot dialog -> adds a ticked checkbox -> flows through $ctx.Cleanups -> State.SnapshotCleanupCommands ->
     POST-INSTALL (existing wiring). Cleanups header relabelled "Exclusions to apply". Inclusions untouched.
     VERIFIED: Get-ExclusionCommand outputs (file/folder/regkey/shortcut) correct; GUI parses; Test-Build PASS.
     r66 shipped, 226KB.
   2026-06-16 round 67 - PERSIST the snapshot report + exclusions (user: "if I close the window the report is gone;
     let me save it + come back from the ps1 to add more exclusions; keep until Reset").
   - State now persists SnapshotReport (text) + SnapshotExclusions (master list of {Label;Command;Checked}), both
     Step-2-owned (survive closing the dialog AND going to Step 3 and back; cleared only by Reset / a Step-1 source
     change). Show-SnapshotDialog gained -ExistingReport/-ExistingExclusions: re-opening "Analyze installer" now
     RELOADS the saved report + its exclusion checkboxes (editable) WITHOUT forcing a new capture (it still grabs a
     fresh baseline in the background so a brand-new Analyze still works). Apply returns the FULL exclusion list
     (ticked + unticked, with state) + ReportText; the BtnSnapshot handler stores them back into State.
   - New "Save report..." button (System.Windows.Forms.SaveFileDialog -> .txt). Fixed a DockPanel ordering bug
     ($bSave was added after the fill child) by moving it into the bottom-bar construction. Cleanups relabelled
     "Exclusions to apply". GUI parses, Test-Build PASS. r67, 227KB.
   2026-06-16 round 68 - VALIDATOR CHECKS BUNDLE (user picked this + "package configuration options"). New
     Get-InstallerValidation (Source.ps1) runs on the chosen installer(s) and adds review items:
     - Digital SIGNATURE / publisher (Get-AuthenticodeSignature): signed-by-<CN> (valid) / NOT signed / bad status.
     - VERSION cross-check: installer's real version (MSI ProductVersion via Get-MsiProperty COM; EXE
       FileVersionInfo.ProductVersion/FileVersion) vs the package-name version -> warn on mismatch.
     - ARCHITECTURE cross-check: EXE PE machine (Get-PeArch: 0x14C=x86 / 0x8664=x64 / 0xAA64=ARM64) or MSI
       SummaryInformation Template (Get-MsiTemplateArch) vs the package-name Arch -> warn on mismatch.
     Wired into Get-CombinedReview (cached by path+size so signature/COM reads don't repeat). VERIFIED on real
     installers: SentinelOne x64 signed by "SentinelOne Inc."; JMatPro x86 signed by "Sente Software Ltd"; forced
     wrong version/arch correctly produced the mismatch warnings. Test-Build PASS. r68, 230KB.
   - STILL OPEN (user also picked): PACKAGE CONFIGURATION OPTIONS - detection-method picker (ProductCode / file+
     version / registry / script), install context (system vs user), reboot behaviour, custom pre/post actions,
     prerequisite chaining. Bigger Step-2 UI build - NEXT.
   2026-06-16 round 69 - snapshot UX fixes (paused new features per user).
   - DESKTOP SHORTCUT now captured: the Shortcuts category used %USERPROFILE%\Desktop, which misses a OneDrive/
     Known-Folder REDIRECTED desktop. Now uses [Environment]::GetFolderPath(Desktop/CommonDesktopDirectory/
     StartMenu/CommonStartMenu/Programs/CommonPrograms) + $env:OneDrive\Desktop + the old paths. VERIFIED: a test
     .lnk on the (redirected) desktop is now captured=True.
   - ADDED/MODIFIED/DELETED differentiation now CLEAR: report tags each line with the explicit words ADDED /
     MODIFIED / DELETED (was [+]/[~]/[-]) and sorts within a section so added/modified/deleted group together.
   - MANUAL baseline (auto was risky): removed the auto-capture-on-open. New "1. Take baseline" button starts the
     BEFORE capture when the user is ready; "2. Run installer"; "3. Analyze". On RE-OPEN, the saved report +
     exclusions load WITHOUT any scan (nothing runs until Take baseline) - fixes the "baseline loads again".
   - UI clean-up (user: "clean like the snippets model, clear fields"): the report sits under a bold 'SNAPSHOT
     REPORT' section header and the exclusions under a bold 'EXCLUSIONS (ticked = removed in POST-INSTALLATION)'
     header. Render-tested OK. r69, 230KB. Test-Build + report tests PASS.
   2026-06-19 round 70 - KB/validator data not clearing for the PREVIOUS app (user bug). Two causes: (1) the
     validator cache $script:InstallerValCache was keyed by path+size only (ignored the package name) and lived
     outside $script:State, so a name change / Reset never refreshed it -> previous app's signature/version/arch
     findings stuck. Fix: key includes $Parsed.FullName; and Invalidate-From (n<=2) now clears $InstallerValCache +
     $KbHintSwitch/$KbHintInstaller + $ReviewAutoShown and collapses PnlKbHint. Name change / source change / Reset
     all flow through Invalidate-From, so the previous application's KB suggestion + validator findings clear. r70.
   2026-06-19 round 71 - PACKAGE CONFIG (1/n): CUSTOM ACTIONS. New Show-CustomActionsDialog (3 multiline boxes:
     PRE-INSTALL / POST-INSTALL / PRE-UNINSTALL) + "Custom actions..." button (Step 2). State.PreInstallActions /
     PostInstallActions / PreUninstallActions (Step-2 owned). New-StandardCommands now emits cmds.PreInstall /
     PostInstall / PreUninstall; Add-StandardCommands injects PreInstallCode / PostInstallCode / PreUninstallCode.
     Step-3 build COMBINES snapshot cleanups + the packager's PostInstallActions into POST-INSTALL, and sets PRE-
     INSTALL / PRE-UNINSTALL. (Fresh-build path, like snapshot cleanups - predecessor reuse carries its own.)
     VERIFIED (Test-Build): custom commands land in PRE-INSTALLATION + PRE-UNINSTALLATION. r71, 232KB.
   2026-06-19 round 72 - REMOVED the custom-actions UI + made the snapshot GUI "pro". User: "the customactions box
     is useless anyway we can open script editor and fill there." Removed Show-CustomActionsDialog, the "Custom
     actions..." button, and State.PreInstallActions/PostInstallActions/PreUninstallActions. KEPT the Build.ps1 wiring
     (New-StandardCommands PreInstall/PostInstall/PreUninstall + Add-StandardCommands injection) - harmless, snapshot
     cleanups still flow through PostInstallExtra, and Test-Build's PRE-INSTALL/PRE-UNINSTALL assertions (which call
     Build-FreshScript with NewPkg.PreInstallExtra directly) still pass. SNAPSHOT GUI PRO: live FILTER toolbar in the
     report area (row between header + textbox): a search TextBox (case-insensitive substring; sections with no match
     disappear) + a category ComboBox (All / Files / Registry / Services / Drivers / Certs / Shortcuts / Tasks /
     Autostart / Printers / Programs / Environment) + Clear button + filter-state label. Get-SnapshotReportText gained
     -Search/-OnlyCat (structure-aware: _hit per-item filter + _showCat per-section gate; APPLICATION header + summary
     always shown). $ctx now keeps the raw diff (Diff/FileDiff/RegDiff/EnvChanges/Un/AppTokens) so the filter
     re-renders WITHOUT re-scanning, via the new module function Update-SnapshotReportView (a real function, not a
     closure, to dodge the per-closure scope traps; falls back to a plain line-filter when only a SAVED report is
     re-loaded with no diff in memory). Copy/Save now use the VISIBLE (filtered) text; Apply still persists the FULL
     report. VERIFIED: parse-clean (all 6 modules + merged pak), Test-Build green (incl. custom-action build wiring),
     runtime filter test (search hides non-matching sections; OnlyCat shows one category; APPLICATION always shown).
     r72, 233KB.
   2026-06-19 round 73 - MULTI-MSI BUNDLES + 3 live-test bugs from a Mozilla predecessor run (user: "i don't want
     broken structure like this in future"). Diagnosed from the log; NONE were caused by the r72 snapshot/picker work.
     (1) BUNDLED MULTI-MSI: the wrapper handler kept only the LARGEST extracted MSI (Select -First 1) but pointed the
     payload root at the extraction folder - so Copy-PayloadTree shipped ALL extracted MSIs + an MST each, while the
     install command referenced only one (the "multiple msi/mst" the user saw on Woelfel_Immi). The ENGINE already
     supports ordered chaining (New-StandardCommands 'Multiple' -> Get-MultiCommandSet: install in order, uninstall
     reverse, repair=reinstall; assembler builds an MST per MSI). Added Show-BundledMsiPickerDialog (checkbox list +
     Up/Down ordering, reads ProductName/Version/Code via Get-MsiProperty, shows paired vendor MST, unticks likely
     prerequisites by name); the handler now uses it for >1 MSI, PRUNES unticked MSIs from the extract folder (so they
     don't leak), and Add-ManualInstallers in PICKED ORDER -> Multiple mode. Single-MSI path unchanged.
     (2) MST BUILD FAILED "GenerateTransform,ReferenceDatabase,TransformFile": REPRODUCED - GenerateTransform throws
     when $OutputMst is READ-ONLY. In predecessor reuse the vendor MST is copied from the read-only LIVE share into
     Files\ with the MSI's base name, so it IS $OutputMst and read-only. Fix (Build-Mst): GenerateTransform writes to
     a FRESH temp .mst, COM dbs are released, THEN the transform is placed at $OutputMst (clear read-only + remove
     stale target first; create the dir if missing). Also: if there are no differences, inject a benign MTBTRANSFORM
     marker so a valid .mst always exists (the install -Transform must resolve). [no-diff returns False, not an error.]
     (3) SCCM "is not a package Content folder" though it WAS correct: Find-OutgoingPackage locates the package by a
     RECURSIVE search for Invoke-AppDeployToolkit.ps1 (Frontend excluded), but Copy-PackageToPrelive only checked
     <path>\Content or <path>. Made Copy-PackageToPrelive use the SAME recursive locate, so any extra nesting from a
     manual copy is tolerated and a package Find accepted can't be rejected here.
     Also: icon CROSS-PACKAGE contamination (a Firefox build copied the ISDOCReader package's Icons) - the icon
     fallback climbed to the PARENT (a multi-package share) with MaxDepth 2 and grabbed a sibling package's Icons. Fix:
     new Get-PackageRootFolder (walks up to the ancestor whose name parses as a valid package name) bounds the
     Icons/Documents fallback to INSIDE the package; returns $null on a bare share so we never grab a sibling. Applied
     in Resolve-Source AND Copy-PackageIcons. VERIFIED: Test-Build green + 6 NEW assertions (multi-MSI order/reverse/
     per-MST/repair; pkg-root nested + null-on-share); reproduced & re-tested the read-only-vendor-MST MST build.
     r73, 236KB.
   2026-06-19 round 74 - SCCM "provider does not support the use of filters" (regression from r73) + predecessor
     icon reuse. (1) The r73 recursive content-folder search I added to Copy-PackageToPrelive used Get-ChildItem
     -Filter -Recurse, but that function is called INSIDE New-SccmApplication's `Push-Location G08:` (the CMSite
     drive). PowerShell binds a cmdlet's dynamic params (-Filter/-File/-Recurse) from the CURRENT drive's PROVIDER,
     and the ConfigMgr provider rejects filters -> the create threw. Fix: pin Copy-PackageToPrelive to a filesystem
     location for its whole body (`Push-Location $env:SystemDrive\` ... finally Pop-Location) so every cmdlet binds
     to FileSystem. (Get-SccmFieldsFromPackage's -Filter at L98/135 is SAFE - it runs in Populate-Publish on the GUI
     thread, never under the CM drive.) (2) PREDECESSOR ICON REUSE: for a predecessor build, icons now come from the
     PREDECESSOR's own package folder on the live share (new Get-PredecessorIconsPath: <pred>\Icons, else any Icons
     under it). At the assemble call the Resolved is CLONED with IconsPath=predecessor icons and RootPath=predecessor
     path, so if the predecessor has no Icons the fallback stays INSIDE the predecessor and Icons are left EMPTY -
     never borrowing another package's (pairs with the r73 cross-package fix). Fresh packages keep the new-source
     icons (package-root scoped) else empty. VERIFIED: all modules parse-clean, Test-Build green (44 incl. r73's 6),
     Get-PredecessorIconsPath returns the folder / blank correctly. r74, 237KB.
   2026-06-19 round 75 - FULL-PIPELINE AUDIT (user: "run audit on everything... do everything"). Read-only audit of
     detection -> KB -> validator -> build (fresh + predecessor) -> MST -> assemble -> SCCM (all 10 CMSite-drive
     Push-Location blocks) -> Intune -> bundled-MSI. Confirmed the r72-74 fixes have NO siblings (only
     Copy-PackageToPrelive ran a filesystem -Filter under the CM drive; Intune is REST/Graph so the provider trap
     doesn't apply; the only share-sourced write besides the MST is Unblock-File, already in try/catch). Then fixed
     the residual risks found: (1) Find-VendorMst's "single .mst in folder -> use it" fallback applied a stray
     transform to EVERY MSI in a MULTI-MSI bundle folder (exposure I added with the r73 picker) - now the fallback
     is gated to a single-MSI folder; multi-MSI requires an exact <base>.mst name. (2) FRESH-package detection
     warning: Get-ScriptReviewFindings (non-predecessor branch) now flags a SoftIdent that is empty / still a
     placeholder / an MSI package whose key doesn't use the ProductCode / a subkey equal to the bare app name -
     i.e. the classic SCCM 0x87D00324 "installed but not detected" before deploy. (3) Expand-BundledMsi now passes
     7-Zip -aou (auto-rename on clash) so two bundled MSIs with the same leaf name both survive (App.msi/App_1.msi)
     instead of one silently overwriting the other. (#4 persistent S: drive + #5 inline-SQL property name were
     reviewed and are already safe - S: failure is non-fatal and falls back to the UNC; property names are
     hardcoded constants.) VERIFIED: all modules parse-clean, Test-Build green = 50 tests incl. 6 NEW (Find-VendorMst
     multi-MSI no-false-pair / exact-name wins / single-MSI fallback kept; fresh-detection warning fires for guessed
     SoftIdent, NOT for predecessor builds, NOT when the ProductCode is used). r75, 239KB.
   - HONEST LIMIT (recorded): all verification here is parse + local unit tests. The live SCCM site, the read-only
     shares, and real installer registry/detection can only be proven on the user's next real run - state that
     explicitly instead of claiming "it works".
   2026-06-19 round 76 - ASK-BEFORE-REPLACE on outward copies (user: "before replacing anything just ask user").
     (1) PRELIVE: SCCM create MIRRORS Content to prelive via robocopy /MIR (replaces + prunes) with no prompt. Added
     a UI-thread confirmation in $BtnCreateSccm.add_Click BEFORE Start-PublishJob: if <ContentShare>\<FullName>\Content
     already exists, MessageBox YesNo "Prelive content already exists ... MIRROR (replace) it?"; No aborts. (Had to
     be up front because Copy-PackageToPrelive runs in a background runspace where a dialog can't be shown. The
     deliberate "Update content" action is unchanged - that one is meant to re-copy.) (2) NEW "Copy package to
     Outgoing share..." button on the Review & Create tab (BtnCopyOutgoing): copies the created package
     (State.CreatedPath, e.g. c:\temp\<FullName>) to Get-Setting OutgoingPath\<FullName> at any time; if it already
     exists there it ASKS YesNo before mirroring; guards same-folder (already the Outgoing copy) and unreachable
     paths; robocopy /MIR with exit-code check; status in LblCreateResult. Registered BtnCopyOutgoing in the FindName
     list. VERIFIED: GUI parses, XAML loads with the new button, Test-Build still 50/50. r76, 239KB.
   2026-06-19 round 78 - KB & MULTI-SOURCE EXE (plan Part A). (A1) KB hint panel now shows BOTH install AND
     uninstall, each with a 'Use' button (LblKbUninst/BtnKbUseUninst -> TxtUninstArgs). (A2) Get-KBRecommendation
     gained an ENGINE-TYPE tier: from the existing KnowledgeBase.Recommend.json (each byInstaller entry has
     engine+install+uninstall) it builds an in-memory byEngine index (Get-KbEngineIndex; one vote per package per
     engine) and, with no vendor/app match, suggests the most-common CLEAN install+uninstall for that engine
     (Test-CleanSwitch filters path/answer-file/ACL/log noise; min 2 votes for known engines, 3 for catch-all, so
     no garbage like an icacls line). Runtime->analyzer engine map ($EngineRuntimeToKb). (A3) Get-EngineUninstallSwitch
     gives a per-engine default uninstall arg. (A4) MULTI-SOURCE full per-EXE tooling: refactored the bundled-MSI /
     run-capture / probe handlers into Invoke-BundledMsiCheck/Invoke-RunCapture/Invoke-ProbeHelp (take an $Exe;
     -ReplaceInChain swaps just that installer via new Replace-InstallerInChain + the extracted Update-ChosenResolved);
     Build-MultiArgRows now gives each EXE row install+uninstall KB (with Use) AND a [Check bundled MSI][Run & capture]
     [Probe /?] strip. VERIFIED: parse + XAML load + Test-Build (56 incl. 6 new KB asserts) + live engine-tier check
     on real KB. r78, 243KB.
   2026-06-19 round 79 - LAUNCH & SCREENSHOT validation (plan Part B). New engine module Screenshots.ps1:
     Resolve-ShortcutTarget (WScript.Shell), Get-AppStartMenuShortcuts ([-Diff]|[-Live]; keeps Start-Menu .exe
     shortcuts, drops Desktop + uninstall/update/help, dedupes true dupes by name+target+args, prefers app tokens but
     doesn't require them), Invoke-ShortcutScreenshots (launch .lnk -> wait for MainWindow -> screenshot the window
     rect via Win32 GetWindowRect + System.Drawing CopyFromScreen, full-screen fallback -> close; refuses
     Test-IsSecurityProduct targets; bounded timeouts; best-effort), Compare-ShortcutSets (Added/Gone/Same; keyed by
     name+target; tolerates empty reference). Integration-tab button "Validate: screenshot app shortcuts" (BtnShotValidate)
     -> Start-ScreenshotJob (background runspace) LIVE-enumerates the installed shortcuts (authority), screenshots to
     C:\temp\PackageBuilder\Screenshots\<pkg>\integration\<timestamp>, and diffs vs the OPTIONAL snapshot reference
     (State.SnapshotShortcuts, stored by the snapshot dialog's $res.Shortcuts). Works standalone with no snapshot.
     Added Screenshots.ps1 to Pack-Engine engineFiles. VERIFIED: parse all + merged pak parse-gate + Test-Build (60,
     incl. 4 new shortcut asserts: keeps real/drops uninstall+desktop, diff Added, empty-ref tolerated). NOTE/LIMIT:
     the actual launch+screen-capture path (Win32/CopyFromScreen) could NOT be live-exercised here (the safety
     classifier was intermittently unavailable for process-launch commands) - logic around it is unit-tested; the
     real capture is standard Win32 + best-effort by design and needs the user's live confirmation. r79, 249KB.
   2026-06-19 round 80 - SCREENSHOT validation, the testing-tab + smart version (user: put it in the Testing tab,
     differentiate by install TIMESTAMP not name, one-click, and make clear which screenshot is which). Rewrote
     Screenshots.ps1: Get-AppInstallInfo (ARP lookup -> install folder + time); Get-AppStartMenuShortcuts now LAYERS
     the live differentiation - (1) snapshot ref target exe/folder, (2) install dir, (3) .lnk newer than install
     time, (4) name tokens - and NEVER falls back to "launch everything" (returns nothing if no signal). PNGs are
     CAPTIONED (Save-CaptionedPng draws a name+target+time strip under each shot) and an index.html contact sheet is
     written (Write-ScreenshotIndex; no System.Web dependency) so "which screenshot is which" is obvious. New
     Troubleshoot-tab button BtnTsShots "Screenshot app shortcuts (this machine)" next to the log buttons; shared
     Invoke-ShortcutValidation + Get-ValidationTokens drive both it and the Integration BtnShotValidate.
     Start-ScreenshotJob now resolves install info in-runspace and passes install dir/time + ref. LIVE-TESTED the
     capture this time (notepad via a .lnk): launches the TARGET exe directly (with the shortcut's args+workdir) so
     the process is reliably closeable, hardened the MainWindowHandle type check (a shell-launched .lnk handed back
     an empty value that mis-coerced vs [IntPtr]::Zero -> SetForegroundWindow("") crash; now guarded with -is
     [IntPtr]), full-screen fallback guards a null PrimaryScreen. Verified: PNG written + captioned, process closed,
     index.html written with the shortcut name; Test-Build 60 green; pack parse-gate. (Window-rect capture only
     fell back to full-screen here because the agent session is non-interactive; a real desktop captures the window.)
     r80, 253KB. NEXT (user, after this): KB uninstall suggestion should also name the uninstall EXE (uninstall exe
     differs from install exe - unins000.exe / Uninstall.exe / msiexec /x) - analyzer captures install/uninstall
     ARGS only (byInstaller has 'installer' = install exe, no uninstaller); plan to add uninstaller exe to the
     analyzer + a per-engine uninstaller-exe hint.
   2026-06-19 round 81 - KB UNINSTALLER EXE (user: "uninstall exe differs from install exe - the KB should be
     capable"). (1) Analyzer (Analyze-KnowledgeBase.ps1) now captures the uninstaller EXE/command alongside the
     uninstall args: $uninExe = 'msiexec /x {ProductCode}' for MSI, else the EXE uninstaller's name (unins000.exe /
     Uninstall_<app>.exe), stored as a new `uninstaller` field in byInstaller/byVendorApp/byVendor + a UninstallExe
     fact. (2) Get-EngineUninstaller (Source.ps1) gives the typical uninstaller exe per engine (Inno unins000.exe,
     NSIS Uninstall.exe, MSI msiexec /x {ProductCode}, ...) - immediate value with no regen. (3) Get-KBRecommendation
     returns UninstallExe (KB `uninstaller` when present, else the engine default via $annotate); the KB hint shows
     uninstall as EXE + args (the 'Use' button still applies only the ARGS to the uninstall box), in the single-EXE
     panel AND the multi-source per-EXE rows (label shows "(uninstaller exe)"). (4) REGENERATED the production KB
     from the live share (923 packages, ~2.7 min, read-only) so existing entries are backfilled - 454/731 byInstaller
     entries now carry the real uninstaller exe (e.g. Uninstall_Pulse2025.1.exe vs install AltairPulse2025.1_win64.exe;
     MathWorksProductUninstaller.exe vs setup.exe); copied KnowledgeBase.Recommend.json to the team folder next to
     the pak. VERIFIED: parse all, Test-Build 63 green (incl. 3 new uninstaller asserts), analyzer validated on 25
     then full 923, real-app lookups return the recorded uninstaller exe. r81, 254KB pak + 1631KB KB.
   2026-06-19 round 82 - PREDECESSOR REUSE: NO Detection step (user). The forward Next already skipped Detection
     (Step 1 -> Show-Step 3, running Populate-Step 2 silently for the ProductCode) and the editor already auto-builds
     (Populate-Step3 -> Build-Step3Script), but the step RAIL still showed "2 Detection". Added Update-StepRail
     (called from Show-Step + when a predecessor is chosen/cleared): for predecessor reuse it COLLAPSES N2 and
     renumbers the visible rail Info(1) -> Editor(2) -> Create & Publish(3); a normal build shows all four. Panel
     indices / Show-Step numbers are unchanged - only the rail labels differ, so the clickable rail + skip logic
     still work. MSI: the standard defaults (remove desktop shortcut + Run keys) already match typical predecessor
     behaviour and the predecessor's own commands/settings are carried by Build-PredecessorScript; a source change
     is still surfaced in Review (Get-SourceWarning). VERIFIED: parse + XAML load + render-check on the real N1-N4
     controls (Detection collapses, Editor renumbers to 2) + Test-Build 63 green. r82, 254KB.
   2026-06-19 round 83 - REVERTED r82 (user reconsidered: KEEP Detection for predecessor reuse - the snapshot +
     shortcut + bundled + MST-match features live there and are useful). Removed Update-StepRail (+ its Show-Step
     call + the two handler calls), the BtnNext predecessor forward-skip (1->3), and the BtnBack predecessor
     back-skip (3->1). Predecessor reuse is now the normal 4-step flow with Detection visible/usable; the editor
     still auto-builds from the predecessor (Populate-Step3). Predecessor logic UNCHANGED per user (verbatim carry +
     the swaps: version, installer filename, MSI ProductCode - solves most automation). INSTEAD, made the tool
     INFORM clearly when the source differs: Get-SourceWarning now states predecessor X vs your Y + how to align for
     EVERY mismatch - loose files, MULTIPLE installers (the gap the bundled-MSI picker can open), and type change
     (was only first-ext type before). The structured-fetch popup now fires for 'Source TYPE|STRUCTURE' (not just
     'TYPE changed'); the warning also shows in the editor header (red) + is reviewable. VERIFIED: parse + rail
     render-check (back to Info/Detection/Editor/Create) + Test-Build 63 green. r83, 254KB.
   2026-06-19 round 84 - MULTI-COMPONENT predecessor: SHOW the full install + uninstall sequence (user). Read-
     PredecessorModel only captured the FIRST installer; now it also parses the ORDERED sequences via new engine
     Get-PredecessorCommandSeq (per MSI/EXE line: Kind/Action/Name/Mst/ProductCode/Args/Display; skips schtasks/reg/
     cmd/powershell/msiexec helpers; unwraps backtick continuations). Model gains InstallSeq/UninstallSeq/
     InstallCount/IsMulti (single-installer fields kept for the swap). Format-PredecessorSeq renders "INSTALL (N, in
     order)" + "UNINSTALL (M, reverse)". GUI: picking a predecessor now appends a summary to LblPred ("MULTI-
     COMPONENT: installs N in order, uninstalls M in reverse"), sets the full sequence as the label TOOLTIP, and
     shows a new "View predecessor install / uninstall..." button (BtnPredCmds -> Show-TextDialog with the full
     sequence + a note that reuse swaps only the primary installer). Get-SourceWarning now detects a MULTI-COMPONENT
     predecessor and says so (installs N / uninstalls M, your source has K - verify each command), and the
     source-differs popup fires for it too. Honest: predecessor reuse still SWAPS only the primary installer/
     ProductCode (per the user's "keep predecessor logic + swaps") - the multi-component awareness is transparency +
     guidance so the packager verifies each command; auto-mapping every component of a multi-installer predecessor
     to a multi-installer new source is a possible NEXT step. VERIFIED: parse all + XAML (BtnPredCmds) + Test-Build
     67 green (4 new pred-seq asserts) + live parser test (3 installs incl MST/args, uninstall-by-ProductCode). r84, 257KB.
   2026-06-19 round 85 - SCREENSHOTS: initial validation at SNAPSHOT time + package-log timestamp for troubleshoot
     (user pointed out both gaps). (1) The snapshot dialog (Detection page) only stored the shortcut LIST; now it has
     a 'Launch + screenshot shortcuts' button (enabled after Analyze when shortcuts were captured) that screenshots
     the EXACT shortcuts the diff found - no guessing, app freshly installed - to Screenshots\<app>\snapshot\<ts>.
     These are the reference the Troubleshoot validation diffs against. (2) Get-AppInstallInfo now prefers the
     PACKAGE INSTALL LOG timestamp as the install marker (new Get-AppInstallLogTime: ProgramData\VWG\Logs\<app>\
     *install*.log creation time) over the ARP folder/InstallDate, and reports which via Info.TimeSource; the
     validation result now says "(shortcuts identified by package install log / ARP install folder/date)". So the
     Troubleshoot screenshots are tied to when the package actually installed (timestamp-based shortcut detection ->
     launch -> snip), exactly as expected. VERIFIED: parse + XAML + Test-Build 67 green + helper null-safety. r85, 258KB.
   2026-06-19 round 86 - SMARTER shortcut differentiation (user: "app names don't always match the install folder/
     ARP - detect the INSTALL TIME and screenshot shortcuts created then; stop thinking app-name = X"). DROPPED the
     name-based layers (ARP install-folder match + app-name token match) from the LIVE differentiation entirely.
     Replaced Get-AppInstallInfo/Get-AppInstallLogTime with Get-AppInstallWindow: from the package's OWN PSADT install
     log (ProgramData\VWG\Logs\<package>\*install*.log - the tool's convention, reliable + name-independent) it
     returns @{Start=log creation; End=log last-write; Source}. Get-AppStartMenuShortcuts -Live now uses ONLY: (1)
     snapshot reference (exact target exe), then (2) the INSTALL WINDOW - shortcuts CREATED in [Start-2m, End+10m] are
     this install's, whatever the app/exe/folder is named; with neither it returns NOTHING and the UI says to run a
     snapshot or ensure the install log exists (never guesses by name, never launches the whole Start Menu).
     Start-ScreenshotJob feeds SinceTime/UntilTime from the window; result reports "matched by package install log
     (<file>)" / "snapshot reference". VERIFIED: parse + no stale refs + Test-Build 67 green + window helper null-safe.
     r86, 257KB.
   2026-06-22 round 87 - SNAPSHOT now SysTracer-COMPLETE without the speed/junk cost (user: "make it like systracer
     catches everything even though it takes time ... for faster find another alternative ... cannot miss anything ...
     junk type data shouldnt be stored be smarter"). Root cause of "misses things": the FILE scan used a narrow root
     list (Program Files/ProgramData/AppData + a few Windows subdirs), so a custom install dir anywhere (D:\Apps,
     C:\Tools, a DLL dropped in System32) was invisible. FIX - the smart fast+complete design: $SnapshotFileRoots now
     enumerates EVERY fixed drive from its ROOT ([IO.DriveInfo] Fixed+IsReady; fallback %SystemDrive%\). Speed does NOT
     come from a narrow root list - it comes from PRUNING the OS-churn megafolders installers never touch (added to
     Get-PathMap $skipDir: WinSxS, servicing, SoftwareDistribution, DriverStore, CbsTemp, Panther, LiveKernelReports,
     Minidump, $Windows.~BT/~WS, $GetCurrent, Downloaded Program Files - on top of the existing cache/temp names).
     The before/after DIFF + noise filter then store ONLY real changes - junk is never persisted. MEASURED on this
     box: whole C:\ = 124,103 files in 10.7s (was missing System32's 21,432 files entirely; WinSxS/SoftwareDistribution
     pruned to 0). Registry value-scan unchanged (HKLM/HKCU SOFTWARE, Classes pruned) = 171,587 keys in 54.7s -> a
     full before+after deep pair ~2-2.5 min ("takes time is fine"). RELIABILITY: both Get-PathMap and Get-RegMap now
     LOG A LOUD WARNING if a scan stops at its cap with work still queued (a truncated map would diff as false
     add/delete) - caps raised generously (file MaxSeconds 300->900, reg 240->600) so it never trips in practice but
     is never silent if it does. $SnapshotFileNoiseRe extended (WinSxS/servicing/SoftwareDistribution/DriverStore/
     Panther/assembly NativeImages/$Windows.~BT/pagefile|hiberfil|swapfile.sys) as a belt-and-suspenders net.
     KNOWN/BY-DESIGN gap, offered as a future toggle: HKLM\SOFTWARE\Classes (COM/shell-ext) + HKLM\SYSTEM\
     CurrentControlSet stay out of the registry value-scan (huge + churny; services/drivers/tasks/certs/env are each
     captured by dedicated collectors) - add a "deep registry" mode only if a shell-extension/COM-heavy app needs it.
     VERIFIED: Snapshot.ps1 parse OK + Test-Build 72 green (5 new: roots include drive root; wide scan keeps a real
     nested file, prunes WinSxS + Temp folders; WinSxS path + pagefile.sys are file-noise) + live timing above + pack
     parse-gate. r87, 259KB.
   2026-06-22 round 88 - UNBLOCK (Mark-of-the-Web) on EVERY copy/extract (user: "during copy locally and run installer
     it takes too much time to launch exe ... exe is blocked while copy ... everytime we do any copy or download it
     should unblock files"). Root cause: files copied from the LIVE network share carry a Zone.Identifier ADS (MOTW),
     so running a copied installer trips the "Open File - Security Warning" dialog / SmartScreen = the multi-second
     launch stall. FIX - one shared helper Unblock-PBPath (Core.ps1): strips Zone.Identifier via Unblock-File, file OR
     whole folder (recurse), best-effort (never throws/blocks, no-op when no stream). Wired in at every copy/extract:
     Copy-InstallerLocal (BundledMsi - the run-local + run-&-capture path the user hit; all run paths funnel here incl.
     Show-MsiCaptureDialog), Copy-ResolvedSource (Source - the package source copy off the share), Expand-BundledMsi
     (BundledMsi - extracted-from-wrapper files). Assemble.ps1's existing inline final-package unblock REFACTORED to
     call the same helper (one implementation, DRY). SCCM prelive/Outgoing copies need no unblock - they push the
     already-unblocked built package. VERIFIED: parse (5 files) + Test-Build 76 green (4 new: stamp a real
     Zone.Identifier then confirm Unblock-PBPath removes it from a file, recurses into subfolders, and is safe on a
     missing path) + pack parse-gate. r88, 259KB (265,584 bytes deployed).
   2026-06-22 round 89 - SHORTCUT SCREENSHOT: fixed "property Text cannot be found" crash + smarter capture (user:
     "property text cannot be found error when i click launch and take screenshot of shortcut ... should minimize
     everything and launch each shortcut and take screenshot after atleast 10 seconds .. some shortcuts take time to
     launch ... clear screenshot of that specific app ... before every launch just minimize everything"). CRASH ROOT
     CAUSE: in Show-SnapshotDialog the $bShots.add_Click handler referenced $lblSummary, but $lblSummary was created
     AFTER the handler - so .GetNewClosure() captured it as $null and "$null.Text =" threw. FIX: create $lblSummary
     BEFORE the handler, and run capture in the BACKGROUND (Start-ScreenshotJob gained -ExactShortcuts so the snapshot
     dialog screenshots its precise $ctx.Shortcuts off-thread) so the new >=10s waits never freeze the GUI; nested
     OnDone re-binds true locals (ps-wpf-closure-scope). CAPTURE REWRITE (Invoke-ShortcutScreenshots): (1) MINIMIZE
     EVERYTHING via Shell.Application.MinimizeAll() before EACH launch -> the app comes up on an empty desktop = a
     clean, unambiguous shot; UndoMinimizeALL() restores at the end (finally). (2) Wait up to -TimeoutSec=30s for the
     window AND guarantee >=-MinVisibleSec=10s since launch before capturing (slow apps / late-drawing content). (3)
     DELEGATING-LAUNCHER ROBUSTNESS: if $proc shows no window (it exited fast, e.g. Win11 System32\notepad.exe hands
     off to the Store app), adopt the FOREGROUND window on the cleared desktop for BOTH capture and close - guarded so
     it never adopts/closes our own window, Explorer, dwm, or powershell. Added GetForegroundWindow +
     GetWindowThreadProcessId to PBScreen. VERIFIED: parse (GUI+Screenshots) + Test-Build 76 green + LIVE smoke
     (launched notepad: now captures the real WINDOW - note empty, not full-screen fallback - and the process is
     CLOSED afterwards). r89, 262KB (267,872 bytes deployed).
   2026-06-22 round 90 - Publish-tab bug fixes + auto cert/driver cleanup + removed Diff-vs-predecessor (user: browse
     package -> "Could not read package fields" (Dell_Latitude 7230 RE BIOS Update...); "cannot bind argument" on the
     publish tab; confirm snapshot removes desktop/uninstall shortcut + run key; auto-remove certs/drivers on uninstall;
     "diff vs predecessor ... not proper ... style i did not like remove it"). FIXES: (1) Get-SccmFieldsFromPackage
     only looked for the v4 'Invoke-AppDeployToolkit.ps1' -> a v3 / other-team package (Deploy-Application.ps1) or a
     differently-built Dell package returned $null = "Could not read package fields". Now it falls back to
     Deploy-Application.ps1 AND the field-reader regex matches BOTH v4 "AppVendor = '..'" and v3 "[string]$appVendor =
     '..'" (optional [type]+$ prefix); Test-Path guard up front. (2) Populate-Publish now SURFACES the real exception
     (was swallowed to a generic message - that hid the "cannot bind argument"); the not-found message tells the user
     exactly which script files are needed and to pick the package ROOT/Content. (3) REMOVED "Diff vs predecessor"
     entirely (BtnDiffPred + Show-PredecessorDiff + PBDiff/PBDiffRow Add-Type + handler + control-name) per the user -
     the install/uninstall SEQUENCE view (BtnPredCmds / Format-PredecessorSeq) is KEPT. CUSTOMIZATIONS (Get-Snapshot
     Cleanups): now also flags the Start-Menu UNINSTALL shortcut for removal (POST-INSTALL, default on - users
     shouldn't run the vendor uninstaller; SCCM/Intune owns removal). NEW auto POST-UNINSTALL cleanups, tagged
     '# [post-uninstall]' so the build routes them to POST-UNINSTALLATION (NOT post-install - removing a cert/driver at
     install would break the app): CERTIFICATES auto-removed by thumbprint (Remove-Item Cert:\LocalMachine\<store>\
     <thumb>, default ON); DRIVERS off-by-default with a locale-INDEPENDENT command (Get-WindowsDriver -Online matched
     by OriginalFileName, then pnputil /delete-driver - NOT pnputil text parsing, which is German on this estate) + a
     "VERIFY this is your driver" note. PLUMBING: GUI Build-NewPkg splits SnapshotCleanupCommands by the tag into
     PostInstallExtra / PostUninstallExtra; New-StandardCommands + Add-StandardCommands gained a PostUninstallCode path;
     Set-SectionBody INSERTS after the "<Perform Post-UnInstallation tasks here>" marker so the template's
     Remove-MTBDetectionKey branding removal is preserved (cleanup runs BEFORE it). VERIFIED: parse (5 files) +
     Test-Build 84 green (8 new: cert post-uninstall tag+default, uninstall-shortcut flagged, normal shortcut not
     flagged, driver default-off+tag, post-uninstall inserted, branding kept, cleanup-before-branding) + pack
     parse-gate (GUI incl.). r90, 260KB (266,160 bytes deployed).
   2026-06-22 round 91 - PSADT v3 INTEGRATION (user: "for psadt v3 also we have to handle integration sometimes").
     Get-SccmFieldsFromPackage now detects the PSADT VERSION from which script it found (Deploy-Application.ps1 = v3,
     Invoke-AppDeployToolkit.ps1 = v4) and returns the matching SCCM/Intune deployment commands: v3 ->
     "Deploy-Application.exe" -DeploymentType "Install"/"Uninstall"/"Repair"; v4 -> the existing
     "Invoke-AppDeployToolkit.exe" install/uninstall/repair. Adds a PsadtVersion field. The commands land in the
     EDITABLE publish fields so a packager can still add e.g. -DeployMode "Silent". (Builds on r90's v3 field-reader +
     Deploy-Application.ps1 fallback.) NOTE - driver custom function: the user asked to use "our custom driver function
     in the template extensions", but NEITHER the v4 PSAppDeployToolkit.Extensions.psm1 (has Set-MTBReboot,
     Expand-MTBZipFile, Set/Remove-MTBDetectionKey, Remove-MTBFonts, Set/Remove-MTBApplicationWizardEntry) NOR the v3
     AppDeployToolkitExtensions.ps1 (empty template) in THIS repo copy contains a driver function. Driver cleanup still
     uses the locale-independent Get-WindowsDriver + pnputil command (default OFF). PENDING: user to share the real
     driver function name/params (likely lives in the LIVE template) so the driver cleanup command can call it. Sccm.ps1
     parse OK + pack parse-gate; live field-extraction re-verify deferred (transient safety-classifier outage). r91.
   2026-06-22 round 92 - DRIVER cleanup now calls the team's custom helper (user replaced the template extensions).
     Found it: the driver functions live in the DEPLOYED template (Downloads\PackageBuilder\Lib\PSADT_Template\...\
     PSAppDeployToolkit.Extensions.psm1, a clean SUPERSET = the same 8 MTB funcs + Add-WindowsDriverOnline +
     Remove-PnPDrivers) - NOT in the source repo copy (Downloads\files\PSADT_Template\..., still the 8-func June-2
     version). So production builds (deployed exe -> Lib template) already ship Remove-PnPDrivers. Get-SnapshotCleanups
     driver command now: `if (Get-Command Remove-PnPDrivers) { Remove-PnPDrivers -Delinflist '<infbase-no-ext>' } else
     { <generic Get-WindowsDriver/pnputil fallback> }` (still '# [post-uninstall]' tagged -> POST-UNINSTALLATION).
     Remove-PnPDrivers signature: -Delinflist "name1;name2" (original INF base names WITHOUT .inf; semicolon list),
     locale-safe (.cat match in %WinDir%\inf, ordinal/invariant) + Intune-safe (reboot codes 3010/1641 logged, not
     propagated). Driver cleanup DEFAULT now ON (was off) since it uses the vetted helper; infName extracted as
     '<folder>' minus '.inf_<arch>_<hash>'. KNOWN GAP (flagged to user, not auto-changed - template is theirs): the
     SOURCE repo template copy lacks the driver funcs, so source/dev builds use the fallback; offered to sync it.
     VERIFIED: parse + Test-Build 84 green (driver test updated: calls Remove-PnPDrivers -Delinflist 'heci', default on,
     post-uninstall tag) + pack parse-gate. r92, 260KB (266,480 bytes deployed).
   2026-06-22 round 93 - driver cleanup simplified to call the helper DIRECTLY (user: "why this if else ... i want to
     use just the function ... everything handled in function itself ... and now under files also i have updated the
     template so it will be there"). Confirmed the SOURCE template (files\PSADT_Template\...\PSAppDeployToolkit.
     Extensions.psm1) now carries Add-WindowsDriverOnline + Remove-PnPDrivers, so the r92 Get-Command/else fallback is
     unnecessary. Driver command is now simply: `Remove-PnPDrivers -Delinflist '<infbase-no-ext>'   # [post-uninstall]
     remove driver '<inf>'` (still POST-UNINSTALLATION, default ON). VERIFIED: parse + Test-Build 84 green (driver test
     tightened: asserts the command is the helper ONLY - no Get-WindowsDriver/no 'if (Get-Command') + pack parse-gate.
     r93, 260KB (266,352 bytes deployed).
   2026-06-22 SNIPPETS - imported the team's script library (\\mndemucfsm01\...\VWITS Team\Gajendra\Scripts) into
     snippets.json. FIRST verified batch = 19 snippets across 11 categories (Shortcuts/Certificates/Uninstall/Folders/
     Registry/Services/Scheduled Tasks/DLL Registration/Branding/Cleanup/Examples). Each v3->v4 converted using the
     authoritative v4 cmdlet list (New-Shortcut->New-ADTShortcut, Get-UserProfiles->Get-ADTUserProfiles, Remove-File->
     Remove-ADTFile, New-Folder->New-ADTFolder, Get/Set/Remove-RegistryKey->*-ADTRegistryKey, Get-InstalledApplication
     -Exact -> Get-ADTApplication -NameMatch Exact, Execute-MSI -Path <GUID> -> Start-ADTMsiProcess -ProductCode,
     Execute-Process -Path/-Parameters -> Start-ADTProcess -FilePath/-ArgumentList, Write-Log -> Write-ADTLogEntry
     (drop v3 -Source $deployAppScriptFriendlyName), $dirFiles/$dirSupportFiles -> $adtSession.DirFiles/DirSupportFiles,
     Remove-Branding -> team Remove-MTBDetectionKey). JUDGMENT CALLS: custom Import-Certificates/Remove-Certificate ->
     native Import-Certificate / Remove-Item Cert:\; Stop-ServiceAndDependencies (no v4 equiv) -> native Stop-Service.
     App-specific names genericized to <placeholders> (<Vendor>/<AppName>/<MainExe>/<Thumbprint>/<GUIDn>/<ServiceName>
     /<TaskName>/etc.). VERIFIED: JSON valid + tool's Initialize-Snippets loads all 19 + every code block parses clean
     (0 failures) + deployed to PackageBuilder\snippets.json. The big Deploy-Application.ps1 files on the share are full
     v3 PACKAGES (not snippets) - skipped. ~55 more .txt snippets remain to import the same way (pending user go-ahead).
   2026-06-22 r94 SNIPPETS "easy add" (user: "any easy way to store snippets? difficult to write manually ... remove
     the example test snippets"). NO MORE hand-editing JSON: added an in-app workflow. Snippets.ps1 +Save-Snippet
     (-Name -Category -Subcategory -Code -> loads/creates category+subcategory, add-or-replace by name, ConvertTo-Json
     with <>&' un-escaped for readability, UTF8 no-BOM, reloads), +Remove-Snippet (by name, prunes empty subs/cats),
     +Convert-V3ToV4Snippet (cmdlet map of ~45 v3->v4 renames + -Parameters->-ArgumentList + same-line -Path->-FilePath
     for Start-ADTProcess/Msi + $dirFiles/$dirSupportFiles->$adtSession.* + drop -Source $deployAppScriptFriendlyName),
     +Save-SnippetsModel, and Initialize-Snippets remembers $script:SnippetsPath. GUI: Step-3 Snippets drawer gained
     "Add..." + "Delete" buttons; Show-AddSnippetDialog (Name / editable Category combo / Subcategory / Code paste box /
     "Convert v3->v4 on save" checkbox); "Add..." also pre-fills with the editor SELECTION (= save-selection-as-snippet);
     Refresh-SnippetUi rebuilds the category dropdown after add/delete. Removed the "Examples / Log a test message" test
     category from snippets.json (now 10 cats / 18 snippets). HIT the cat-alias trap again (helper func 'Cat' resolved
     to Get-Content) - renamed builder helpers PBCat/PBSub/PBSnip (see memory ps51-comma-arg-and-alias). VERIFIED:
     parse (Snippets+GUI) + live Save/Remove round-trip on a temp copy + Convert sample correct + real snippets.json
     valid (10 cats) + Add-dialog XAML loads offscreen + pack parse-gate. Deployed r94 pak + snippets.json.
   2026-06-22 r95 SNIPPETS: $VWG_CurrentRegWOW hardcode + SHARED library (merge). (1) User: "$($VWG_CurrentRegWOW) is
     not available in new psadt ... hardcode it with wow6432node directly". Convert-V3ToV4Snippet now replaces
     $($VWG_CurrentRegWOW)/$VWG_CurrentRegWOW -> 'Wow6432Node\' and $($VWG_CurrentSysWOW)/$VWG_CurrentSysWOW ->
     'SysWOW64'; fixed the two existing snippets (Registry Values + ARP) to literal Wow6432Node\ with a "drop for
     64-bit" note. (2) User: per-person local snippet files would be chaotic - how does it merge? FIX: snippets.json is
     now SHAREABLE - settings.json 'SnippetsPath' points every tool at ONE file on the team share; if set-but-missing
     the tool SEEDS it from the local copy. Save/Remove already RE-READ the file before writing (so different people's
     additions accumulate/merge, not clobber); Save-SnippetsModel now writes temp-then-atomic-Replace with 5x retry +
     Copy fallback so a file briefly locked by another concurrent user never corrupts/loses the write. VERIFIED: parse
     (Core/Snippets/GUI) + converter VWG->Wow6432Node/SysWOW64 + snippets.json 0 VWG refs & valid + atomic Save lands on
     disk (18->19, no temp leftovers) + pack parse-gate. Deployed r95 pak + snippets.json.
   2026-06-22 r96 - $VWG_CurrentRegWOW now hardcoded during PREDECESSOR REUSE too (user: "during predecessor reuse
     conversion should work for $($VWG_CurrentRegWOW) ... if somewhere in script we have it it is not converting to
     Wow6432Node"). Root cause: the predecessor pipeline uses Convert-V3ToV4Content (PSADT_V3toV4_Mappings.ps1), which
     had no VWG handling - AND it only runs when the predecessor is detected v3, so a v4 predecessor still referencing
     $VWG_CurrentRegWOW skipped it. FIX: new shared Convert-VWGRegWOW (PSADT_V3toV4_Mappings.ps1) hardcodes
     $($VWG_CurrentRegWOW)/$VWG_CurrentRegWOW -> 'Wow6432Node\' and $($VWG_CurrentSysWOW)/$VWG_CurrentSysWOW ->
     'SysWOW64' ($(...) form first so the bare pass doesn't mangle the inner name). Called inside Convert-V3ToV4Content
     (after the $VWG_SoftIdent strip) AND UNCONDITIONALLY in Read-PredecessorModel on the BODY $Content (so v4
     predecessors get it; $rawContent keeps originals for SoftIdent/session extraction). VERIFIED: parse + live (direct
     + via full converter: Set-RegistryKey...$($VWG_CurrentRegWOW)App_is1 -> Set-ADTRegistryKey...Wow6432Node\App_is1)
     + Test-Build 89 green (5 new VWG asserts; Test-Build now sources PSADT_V3toV4_Mappings.ps1) + pack parse-gate.
     r96. NOTE to user on SnippetsPath: empty default ALREADY = the local snippets.json next to the exe (= "current
     file location") - no change needed now; set it to a share path later to enable team sync.
   2026-06-22 r97 SNIPPETS: EDIT button + module-correct branding + removed leftover examples (user: "give edit option
     ... for removing branding key -instancename is not require now ... check our modules in template while converting
     ... remove unnecessary previously-existing snippets ... keep detailed explanations"). (1) EDIT: new "Edit..."
     button in the Snippets drawer; Show-AddSnippetDialog gained -Original (pre-fills name/cat/sub/code, title "Edit
     snippet", convert OFF); on save it replaces, and if the identity changed it removes the OLD entry SCOPED by
     name+category+SUBcategory (Remove-Snippet gained -Subcategory) so a same-named snippet in another subcat is never
     touched. (2) BRANDING per the REAL module fn Remove-MTBDetectionKey (param is -Name [positional, string[]], NOT
     -InstanceName; no -AdditionalRegPaths, no wildcards - exact HKLM\SOFTWARE\VWG\CM\<Name> match): mapper now renames
     Remove-Branding/Set-Branding -InstanceName -> -Name + new Layer-1c strips -AdditionalRegPaths "..","..";  fixed the
     "Remove branding detection key" snippet to Remove-MTBDetectionKey [-Name ...] with a detailed explanation. (3)
     REMOVED the 2 leftover starter examples (Clean Firefox user profiles, generic Remove-registry-key-tree) ->
     snippets.json now 9 cats / 16 real snippets. VERIFIED: parse (Snippets/GUI/Mappings) + JSON valid + branding
     v3->v4 (Remove-Branding -InstanceName+-AdditionalRegPaths -> Remove-MTBDetectionKey -Name) + edit-rename scoped
     delete (renamed updated, same-name in other subcat preserved) + Test-Build 92 green (3 new branding) + pack
     parse-gate. r97. PENDING: convert the remaining ~55 .txt snippets from the share (module-aware, detailed
     explanations) - next batch.
   2026-06-22 r98 AUDIT (user: "scan for duplicates/unnecessary, issues in predecessor reuse + fresh script, folder
     fetches, corruption/unknown errors"). FINDINGS+FIXES: (1) NO duplicate function definitions across all 292 funcs
     in the 14 packed modules + GUI (AST scan) - no silent-override corruption. (2) MAJOR: the v3->v4 mapper
     (PSADT_V3toV4_Mappings.ps1) had 9 TARGETS that DON'T EXIST in PSADT v4 -> predecessor reuse would emit calls to
     non-existent cmdlets. Cross-checked every NewName against the live PSAppDeployToolkit.psd1 FunctionsToExport +
     the team MTB extension funcs. Fixed: Remove-MSIApplications->Uninstall-ADTApplication (was Remove-ADTMsiApplications),
     Remove-Shortcut->Remove-ADTFile (no Remove-ADTShortcut), Show-BalloonTip->Show-ADTBalloonTip (was
     Show-ADTBalloonNotification), Get-DesktopShortcut->Get-ADTShortcut (was Get-ADTDesktopShortcut),
     Invoke-RegisterOrUnregisterDLL->Invoke-ADTRegSvr32 + -DLLAction->-Action; and MOVED Install-Font/Uninstall-Font/
     Set-PinnedApplication/Set-PowerPlan to V3DeprecatedFunctions (no v4 equivalent -> manual-review warning instead of
     a broken rename). (3) NEW REGRESSION GUARD test: asserts EVERY mapper target is a real v4 function (reads the live
     .psd1 export list via Import-PowerShellDataFile + the extensions module funcs) - catches this class forever. (4)
     DUPLICATE removed: Convert-V3ToV4Snippet (snippet Add dialog) had its own ~45-entry map; now DELEGATES to the
     authoritative Convert-V3ToV4Content (inline map kept only as fallback) so the Add dialog gets the SAME validated
     mapping incl. branding -Name fix + -AdditionalRegPaths strip + shape rewrites. (5) SourceAnalyzer.ps1 = standalone
     maintainer CLI (logic already in Source.ps1 for runtime), not in the pak - fine, not dead runtime code.
     VERIFIED: parse + Test-Build 93 green (mapper-target guard PASSES after the 9 fixes; live: snippet converter now
     does branding fix) + pack parse-gate. r98.
   2026-06-23 r99/r100 LIVE-TEST FIXES (user testing on a VWG box). (1) MULTI-INSTALLER predecessor reuse now swaps
     EVERY component (was: only primary; multi even fell through to no-swap because NewPkg.MsiFileName is empty for
     multi). Build-PredecessorScript: new MULTI branch pairs $Model.InstallSeq with $NewPkg.Installers BY ORDER and
     swaps each filename+MST+ProductCode; SINGLE branch unchanged; count-mismatch -> verbatim+warn. Test-Build +5
     (multi-pred: both PCs swapped in install AND uninstall, old dropped, both filenames). (2) DOC FOLDER not copied
     when MIXING a MANUAL pick + a FETCHED installer: Update-ChosenResolved searched for \doc only under the
     installers' common parent (\source); \doc is a SIBLING. Now climbs to Get-PackageRootFolder like Resolve-Source.
     (3) SHORTCUT/LOG detection (Get-AppInstallWindow) rewritten: scans *.log FILES recursively (logs are FILES named
     e.g. Mozilla_FirefoxESRMAN_140.12.0_x86_MUL_0001_PSAppDeployToolkit_Install.log - NOT per-package folders),
     matches by app TOKENS in filename+subpath (prefers ALL-tokens, falls back to ANY), prefers NEWEST INSTALL log
     (else newest matching); added -LogRoot so a caller can point at a remote machine (\\host\C$\ProgramData\VWG\Logs).
     Fixes "fails even locally" + the format mismatch. (4) LOCAL-MACHINE SCCM actions failed: Invoke-WmiMethod
     -ComputerName <SELF> routes through DCOM loopback and fails - new Get-PBMachineSplat returns @{} for the local
     machine (short/FQDN/localhost) so machine-policy, install-state, reboot-pending, OS/boot, branding reg-read, and
     restart all hit LOCAL WMI directly. VERIFIED: parse + Test-Build 98 green + Get-AppInstallWindow live on the real
     log name + Get-PBMachineSplat local/remote + pack parse-gate. Deployed r100. PENDING (answered, not yet built):
     remote LAUNCH+SCREENSHOT not feasible from the tool's machine (no remote desktop capture - must run on that box;
     remote LOG/shortcut READ is feasible via -LogRoot/UNC); copy source+doc locally at Step-1; KB suggest ALL
     predecessor installers' params + exe match; snapshot place ALL applicable uninstall strings.
   2026-06-23 r101 - the 3 "to do" items, done one by one. (1) STAGE SOURCE LOCAL: Set-ResolvedSource now calls new
     Stage-SourceLocal - a UNC/network source folder is copied ONCE to <WorkRoot>\Source\<leaf> (refreshing any stale
     copy, + Unblock-PBPath) and all later work (re-resolve, Icons/Docs detect, build copy) reads LOCAL; local sources
     pass through; opt out via settings 'StageSourceLocal'=$false. (2) KB EXE-MATCH: new Test-SwitchMatchesEngine
     (NSIS=/S|/D=, Inno=/(VERY)SILENT.., IShield=/s|/f1, Burn=/quiet.., MSI=/qn..); the loose byVendor tier no longer
     returns a switch that's wrong for THIS exe's engine - it falls through to the engine tier instead. (Param named
     $Sw not $Switch - $Switch collides with the keyword and binds $null; cost me a debug cycle - see
     ps51-comma-arg-and-alias.) (3) SNAPSHOT ALL UNINSTALLS: Get-UninstallFromSnapshotDiff now returns AllUninstalls +
     UninstallCount and builds the Uninstall block from EVERY applicable new ARP entry (Added - shared runtimes are in
     Noise) GUID or string, uninstall-REVERSE order; Convert-RawUninstallToPsadt made multi-line-aware (a v4 command
     per line); GUI note lists all detected entries when >1. (.ToArray() not @() on the List - ps51-list-object-wrap.)
     VERIFIED: parse (5 files) + Test-Build 105 green (engine-match x4, multi-uninstall convert x2, snapshot-all x2) +
     live + pack parse-gate. Deployed r101.
   2026-06-23 r102/r103 - snapshot-driven smart automations (user batch). (#1) Snapshot was detecting only ONE ARP
     entry (MASTA) - the 2nd (Sentinel HASP runtime) was filtered by the 'sentinel' noise token meant for the
     SentinelOne EDR. FIX: Compare-MachineSnapshot no longer vendor-noise-filters the PROGRAMS category - EVERY new
     ARP entry is shown (it's the install's own footprint); auto-UNINSTALL still excludes shared MS runtimes
     (VC++/.NET/webview2/SQL/DirectX via $sharedRe in Get-UninstallFromSnapshotDiff). (#2) FILES report now GROUPS by
     folder ("<folder>\ (N files)"); folders with <=3 files are expanded - no more 800 individual lines (new
     _emitFolders). (#3) ProcToClose + ProcToBlock auto-filled (fresh) from the app's OWN exes = the Start-Menu
     shortcut TARGETS the snapshot captured (Build-FreshScript writes them as @('a','b') array literals via
     Set-SessionValue). (#4) single MSI -> SoftIdent = its ProductCode; (#5) EXE that wraps an MSI -> the GUID from
     its captured uninstall -> both via new Get-AutoSoftIdent (fresh only; HKLM\..\Uninstall\{GUID} [DisplayVersion=
     ..], Normalize-SoftIdent fixes bitness) - kills the 0x87D00324 guesswork. (#6) CONFIRMED: scheduled tasks ARE
     handled - Get-SnapshotCleanups DISABLES new tasks (Disable-ScheduledTask; default-on for auto-update tasks) -
     disable, not delete (safer; can switch to remove on request). VERIFIED: parse + Test-Build 116 green (auto-
     softident x3, ProcToClose x3, show-all-ARP + shared-runtime-exclude x3, folder-report x3) + live folder report +
     pack parse-gate. Deployed r103.
   2026-06-24 r104 - cleanup automation + FreeSpace + KB parity + sibling-docs (user batch). (#1) Snapshot cleanups
     now UNREGISTER (not disable) scheduled tasks (Unregister-ScheduledTask -TaskName -TaskPath -Confirm:$false), and
     ADD two new cleanup kinds: FONTS dropped under \Fonts\ -> Remove-MTBFonts -FontName '...'  # [post-uninstall], and
     ENV VARS added (machine/user, PATH skipped) -> Remove-ADTEnvironmentVariable -Variable -Target  # [post-uninstall]
     (Get-SnapshotCleanups now takes -FileDiff + -EnvChanges). (#2) FREESPACE fixed: Get-PayloadSizeMB now returns
     max(installer-payload, measured INSTALLED footprint, 150 MB floor). Installed footprint = sum of the app's new
     FILE bytes from the snapshot (Get-SnapshotRawDiff now sums size from each _FileMap 'size|mtime' value, returns
     .InstalledBytes) -> surfaced as result.InstalledMB -> State.SnapshotInstalledMB -> passed to Get-PayloadSizeMB
     -InstalledMB. So a tiny installer that expands to GBs still reserves enough disk; never lowers the value (0 when
     no snapshot). (#3) HID 'Check bundled MSI' + 'Run & capture MSI' (single-EXE PnlBundled forced Collapsed; the
     multi-source per-EXE strip now shows only 'Probe /?'). Snapshot analyzer covers capture without running the
     installer on this machine; handlers kept wired for easy re-enable. (#4) MULTI-SOURCE KB PARITY with single-EXE:
     each EXE row's install suggestion now falls back to Get-EngineSwitch when the KB has no match (was blank ->
     "not shown like single exe"); uninstall already fell back to Get-EngineUninstallSwitch. PackagedAsMsi recs no
     longer offered as EXE install args. CACHE/RESET fix: Build-MultiArgRows prunes State.InstallerArgs entries for
     installers no longer in the set, so a prior source's typed args can't bleed into a new package. (#5) SIBLING-DOCS:
     when a manual installer is picked from a real layout (<Pkg>\source\setup.exe) and no Documentation folder is
     auto-found, new Get-SiblingDocItems carries the SIBLINGS of the 'source' folder into Documents (DocItems). A
     GENERIC/temp parent (temp\setup.exe) or generic grandparent (Downloads\source) harvests NOTHING - the exe alone
     goes into Files (new $script:GenericFolderNames list; stray installers among siblings are excluded). VERIFIED:
     parse all 4 files + Test-Build green (cleanup task/font/env x4, FreeSpace floor/footprint x4, sibling-docs x5) +
     decrypt-and-load smoke of the deployed pak (all new functions resolve, BuildStamp r104). Deployed r104.
   2026-06-24 r105 - PER-USER CONFIG auto-codegen + smarter Files/Documents split (user batch). (#1) PER-USER CONFIG:
     new Step-2 dropdown "Per-user config" (None / All-users registry / Active Setup) -> State.PerUserMode -> the tool
     auto-writes the correct PSADT v4 code so packagers don't hand-write it. AllUsersReg -> POST-INSTALL block
     "Invoke-ADTAllUsersRegistryAction -ScriptBlock { Set-ADTRegistryKey -SID $_.SID -LiteralPath 'HKCU\Software\
     <Vendor>\<App>' ... }". ActiveSetup -> replicates the TEAM HOUSE STRUCTURE found on the Outgoing share
     (Adobe_CCDesktopApp): a PLAIN-PowerShell stub "<App>_<Version>_ActiveSetup_Install.ps1" staged in SupportFiles
     (hides console, logs to %localappdata%\VWG\Logs, imports HKCU via reg.exe) + POST-INSTALL copies it to
     $envProgramData\VWG\<App>\ActiveSetup and registers Set-ADTActiveSetup -StubExePath ... -Description 'User_
     Registries' -Key $AppFullName -ExecutionPolicy 'Bypass' + POST-UNINSTALL purge (PurgeActiveSetupKey +
     Remove-ADTFolder). New funcs in Build.ps1: Get-PerUserConfig / Get-ActiveSetupStub / Get-ActiveSetupStubName;
     New-Package writes the stub into SupportFiles; both FRESH (via New-StandardCommands) AND PREDECESSOR get the POST
     extras - the predecessor builder previously injected NEITHER snapshot-cleanups NOR per-user extras, now does
     (additive Set-SectionBody before Format-OutputScript), so this also FIXED snapshot cleanups never reaching a
     predecessor-reuse script. Vendor/App/Version pre-filled; only <ValueName>/<Data>/reg names stay as placeholders.
     (#2) FILES vs DOCUMENTS split on manual add (Update-ChosenResolved): three cases. (A) installer in a \source
     subfolder -> everything under source -> Files, \doc sibling -> Documents (unchanged). (B) FLAT folder (installer +
     docs MIXED, no subfolder) -> new Get-LooseDocFiles routes ROOT-level files by EXTENSION ($DocExts) to Documents;
     installers + support files (.dll/.inf/.cfg/.ini) stay in Files; SUBFOLDERS (e.g. Firefox payload tree) stay in
     Files untouched. Copy-PayloadTree gained -ExcludeFiles so reclassified docs are NOT duplicated into Files;
     Copy-ResolvedSource computes the exclusion from DocItems that are files under PayloadRoot. (C) generic/temp parent
     (temp\setup.exe) -> nothing extra harvested, exe alone -> Files (guarded by $GenericFolderNames). VERIFIED: parse
     all files + Test-Build green (per-user codegen x8 incl. fresh+predecessor injection + stub parses; flat-folder
     split x6 incl. end-to-end Copy-ResolvedSource) + offscreen XAML render of the new ComboBox + decrypt-and-load
     smoke of the deployed pak (Get-PerUserConfig etc. resolve, BuildStamp r105). Deployed r105.
   2026-06-24 r106 - per-user refinements per user feedback. (#1) REVERTED the r105 predecessor injection: predecessor
     reuse now carries the predecessor's OWN code verbatim again - we do NOT auto-inject per-user config OR snapshot
     cleanups into a predecessor script (user: "if predecessor already has the codes why inject again? add extra from
     snippets"). Build-Step3Script forces PerUserMode='None' when a PredecessorModel is loaded; Build-PredecessorScript
     no longer appends PostInstall/PostUninstall extras. Fresh builds still auto-codegen via New-StandardCommands.
     (#2) SNIPPETS: added a "Per-user configuration" category to snippets.json, generated from the SAME functions as
     the codegen (so they match): "All users (registry)" -> the Invoke-ADTAllUsersRegistryAction block; "Active Setup"
     -> install+uninstall wiring snippet + the plain-PS stub snippet (clean <Vendor>/<App>/<Version> placeholders).
     Also refreshed the stale "Scheduled Tasks / Remove a scheduled task" snippet from schtasks /delete to the
     Unregister-ScheduledTask syntax the tool now emits. This is the path for adding per-user code to a PREDECESSOR
     reuse build. (#3) MULTI-SOURCE merge confirmed + locked with tests: Get-MultiCommandSet builds each installer's
     OWN command (per-EXE InstallParams/UninstallParams from State.InstallerArgs[fullname], per-MSI ProductCode+MST),
     install IN ORDER + uninstall in REVERSE, all merged into the one ps1 - added multi-EXE (distinct per-exe args) and
     mixed MSI+EXE tests. VERIFIED: parse all + Test-Build green (multi-EXE x3, multi-mix x2, predecessor-not-injected,
     per-user codegen x8) + every per-user snippet parses as valid PS + decrypt-load smoke (r106) + snippets.json
     deployed alongside the pak (SnippetsPath empty -> local file next to the exe). Deployed r106 (pak + snippets.json).
   2026-06-24 r107 - per-user config is now SNAPSHOT-DRIVEN (user: "it should auto take info from snapshot and apply,
     not just syntax"). New Get-SnapshotHkcuValues (Snapshot.ps1) reads the app's OWN new HKCU\SOFTWARE values (live,
     typed Name/Value/Kind) from the registry diff after Analyze -> stored in State.SnapshotHkcu (Step-2 owned/reset).
     Get-PerUserConfig + Get-ActiveSetupStub gained -HkcuItems: when present, the generated code is auto-filled with
     the REAL detected values (Get-PBHkcuLines + Get-PBRegValueLiteral handle String/ExpandString/DWord/QWord/
     MultiString/Binary) - All-users-reg emits 'Set-ADTRegistryKey -SID $_.SID -LiteralPath HKCU\... -Name -Value
     -Type' per value; the Active Setup stub emits 'New-Item' + 'New-ItemProperty' per value in the user context. Empty
     (no snapshot) -> the ready-to-edit placeholder scaffold as before. Build-Step3Script passes
     -HkcuItems State.SnapshotHkcu (FRESH only); New-Package bakes them into the staged stub. The snapshot 'Done'
     status now reports "N per-user (HKCU) value(s) detected - pick a Per-user config option to auto-apply them", tying
     the analyzer to the dropdown. (Predecessor reuse still untouched; snippets stay placeholder for manual use.)
     VERIFIED: parse all + Test-Build green (auto-fill reg+stub, stub still parses, Get-SnapshotHkcuValues reads live
     String+DWord and ignores non-app/non-HKCU) + decrypt-load smoke (r107). Deployed r107.
   2026-06-24 r108 - per-user FILE auto-copy + SNAPSHOT RELIABILITY hardening (user: "do the autocopy... and make our
     snapshot difference reliable - that's what the auto-codes rely on; user can't use SysTracer to confirm").
     (#1) PER-USER FILE AUTO-COPY (snapshot-driven, mirrors the team house pattern - AnalogDevices_LTSpice): new
     Get-SnapshotUserFiles (Snapshot.ps1) picks the install's new files under the packager's profile (AppData
     Roaming/Local/LocalLow) from the file diff (bounded: <=200 files, <=200MB each); stored in State.SnapshotUserFiles.
     New Get-PerUserFileCopy (Build.ps1) emits the 'Get-ADTUserProfiles | foreach { Copy-ADTFile ... }' loop into
     POST-INSTALL (covers existing + Default profile so new users inherit) + matching Remove-ADTFile loop into
     POST-UNINSTALL, and a Staged list. New-Package copies each detected file into SupportFiles\UserProfile\<Scope>\...
     so the loop finds them. Wired into Build-Step3Script (FRESH + PerUserMode != None, alongside the HKCU registry
     code); predecessor reuse untouched. (#2) RELIABILITY: Get-PathMap/Get-RegMap now set $script:SnapshotIncomplete
     on a cap hit; Get-MachineSnapshot stores $s._Incomplete. The Analyze 'Done' line now turns RED and warns when the
     scan was INCOMPLETE (cap hit -> false add/delete possible) OR when NO app change was detected (installer not run /
     Analyze clicked too early) - the two failure modes the user couldn't otherwise catch. (#3) Get-SnapshotHkcuValues
     relaxed: it no longer requires a name (IsApp) match - every NEW/MODIFIED HKCU key in the (already noise-filtered)
     diff is taken, so per-user settings under a codename key are not silently missed. VERIFIED: parse all +
     Test-Build green (per-user files codegen x6 incl. staging map + Get-SnapshotUserFiles classification; HKCU relax
     x2) + decrypt-load smoke (r108). Deployed r108.
   2026-06-24 r109 - "open ignored in CMTrace" + retain noise + confirm no app-name hardcoding (user batch).
     (#1) Get-SnapshotRawDiff now RETAINS the filtered items (NoiseItems, capped 5000) instead of only counting them -
     so the user can SEE what was filtered (and later promote items). (#2) Get-SnapshotReportText gained -IncludeNoise,
     which appends an "IGNORED (filtered as OS/vendor/churn noise)" section (files grouped by folder, registry paths,
     per-category). (#3) The snapshot dialog's "Copy report" button is REPLACED by "Open full report (CMTrace)": it
     writes the FULL report (app changes + ignored items) to <WorkRoot>\Logs\snapshot_<ts>.log and opens it via
     Open-CMTrace (CMTracePath from settings; falls back to the default opener). 'Save report...' kept (txt for
     tickets). (#4) CONFIRMED no app-name hardcoding in the auto-codes: HKCU values + per-user files + uninstall +
     ProcToClose/SoftIdent all come from the ACTUAL machine diff (r108 relaxed HKCU to not need a name match); the
     vendor/app name is only used to AVOID filtering the app's own changes as noise and to pre-fill placeholders when
     no snapshot ran. VERIFIED: parse all + Test-Build green (noise retained in NoiseItems, not in New; -IncludeNoise
     adds the IGNORED section; default report omits it) + decrypt-load smoke (r109). Deployed r109.
     PENDING/OFFERED (user asked "will it be possible?"): an in-dialog selector to tick/untick detected per-user items
     and PROMOTE an ignored item into the new logics - feasible now that noise is retained; awaiting user go-ahead
     (today they can already trim via the Step-3 editor + 'Exclude item...' for removals).
   2026-06-24 r110 - live-test fixes (user). (#1) RUN INSTALLER no longer copies a LOCAL source again: Copy-InstallerLocal
     returns the path unchanged unless it's UNC (the source is already staged locally in step 1) - the "copying locally"
     stall/message is gone for local sources; the snapshot Run-installer warning/status are now conditional on UNC.
     (#2) CMTrace button is now "View ignored OS junk (CMTrace)" and opens ONLY the ignored/noise items (new -NoiseOnly
     on Get-SnapshotReportText) - the app changes stay in the dialog + Save report. (#3) SHORTCUT SCREENSHOTS: the TOOL
     window (and the snapshot dialog) are now MINIMIZED from the UI thread before the background capture job (the job
     can't touch WPF windows and Shell.MinimizeAll didn't reliably catch our own window) and restored after - fixes
     "tool stays full screen / looks stuck / captured instead of the app". Window acquisition is more robust for SLOW /
     delegating apps: polls BOTH the launched process's MainWindowHandle AND the foreground app window (excluding
     tool+shell) up to 45s (was 30), settles >=10s, then re-acquires the foreground once more. The launch prompt now
     explains the count (e.g. "4 of 7 - uninstall/update/help/desktop shortcuts are skipped"). (#4) Smoother: the
     run-installer no longer blocks the UI copying a local source; screenshots already run in a background runspace.
     VERIFIED: parse all + Test-Build green (NoiseOnly app-sections-absent; Copy-InstallerLocal local-in-place) +
     decrypt-load. Deployed r110.
   2026-06-24 r111 - live-test fixes from a real MASTA package (user). (#1) FILES with the app name no longer fall to
     NOISE: new Get-AppMatchTokens (Snapshot.ps1) returns the vendor + AppName AND each significant WORD of them
     (>=3 chars; version/arch/lang dropped), used for both appTokens sites. So a file deep under
     "...\SMT\MASTA 15.1.8 RLM\...\google\protobuf\x.pyi" still matches 'masta'/'smt'/'rlm' and is kept as APP - the
     bundled-Python \google\ segment no longer mis-files it as 3rd-party vendor noise. (User's rule: anything carrying
     the app name is always a real change.) (#2) SHORTCUT FILTER no longer drops real tools: ShortcutExcludeRe gained
     negative lookaheads so "Licence/License Manager|Server|Console", "Support Tool|Console", "Update Manager" are KEPT
     (only doc/agreement/uninstall/help entries are dropped) - fixes the MASTA "4 of 7" (Licence Manager was wrongly
     excluded; now 5 launch, only Help + Release Notes skipped). (#3) Every skipped shortcut is now LOGGED with its
     reason ("[shortcut] SKIP '<name>' - ...") so "what got ignored and why" is answerable from the log. (#4) MINIMIZE
     fixed: new Set-PBWindowState force-minimizes via Win32 ShowWindow (SW_FORCEMINIMIZE for the main window, which WPF
     would NOT minimize as the modal dialog's owner - that's why the tool stayed full-screen) + SW_RESTORE after. Both
     the snapshot-dialog and integration capture now truly hide all tool windows. VERIFIED: parse all + Test-Build
     green (app-token words + vendor-noise override on the google-nested path; shortcut filter keeps Licence Manager /
     drops Help+Release Notes+License Agreement) + decrypt-load. Deployed r111.
   2026-06-24 r112 - more live-test fixes (user, MASTA). (#1) App-name match is now learned FROM THE SNAPSHOT: new
     Get-SnapshotAppTokens = package-name words + the folders the install CREATED (ProgramDirs.Added) + the app's ARP
     DisplayName (Programs.Added). The Analyze callback computes $diff first, then tokens, so a file under the app's own
     install folder (e.g. ...\SMT\MASTA 15.1.8 RLM\...\google\protobuf\) is ALWAYS app/never noise even when the package
     name (Contoso/Widget) doesn't match the install folder. (#2) Analyze-dialog BUTTON SIZING fixed: the bottom bar is
     a DockPanel(LastChildFill) - docked buttons stretch perpendicular, so when the status label wrapped tall after
     Analyze the buttons ballooned ("bar chart" look) in a non-maximized window; now every button is pinned
     VerticalAlignment=Center. (#3) MINIMIZE finally fixed: Set-PBWindowState now does WindowState AND Win32
     ShowWindow(SW_FORCEMINIMIZE) with EnsureHandle, and the snapshot dialog minimizes the modal DIALOG FIRST then the
     OWNER (minimizing the owner while the modal child is up was being reverted - that's why the main window stayed
     full-screen). (#4) SCREENSHOT CAPTURE waits for a STABLE window: per shortcut it polls the launched proc + any
     same-named proc started after launch, picks the LARGEST reasonably-sized window (tiny splash ignored), and
     requires that handle to persist >=3s AND >=MinVisibleSec since launch - so a SPLASH/loading screen that hands off
     to the main window is never the thing captured. VERIFIED: parse all + Test-Build green (snapshot tokens from
     created-folder+ARP; file under created folder is APP despite pkg mismatch) + PB.Win Add-Type compiles +
     decrypt-load. Deployed r112.
   2026-06-24 r113 - root-cause fixes (user: "check WHY the window is like this, not more minimize options"). (#1)
     ANALYZE DIALOG was near-blank at normal size (report height-starved once the exclusions panel appeared) - it now
     opens MAXIMIZED with MinWidth/Height + a 1040x720 restore size. (#2) MINIMIZE root cause = the dialog is MODAL and
     Windows reactivates the visible OWNER of a modal dialog, so it could never stay minimized. Fix: HIDE the main
     window outright (works with a modal child) + force-minimize the dialog; Show() restores. (#3) CAPTURE no longer
     depends on the tool being hidden at all: new PBScreen.ForceForeground (AttachThreadInput + SetWindowPos HWND_TOP +
     BringWindowToTop + SetForegroundWindow) raises EACH app window to the top and we capture only ITS rectangle
     (clamped to the virtual screen). If no app window resolves, we now record a MISS with the reason instead of
     full-screen-capturing the tool/desktop (that was the "wrong screenshot"). Combined with r112's stable-window wait,
     a slow app like MASTA gets its real window captured, not a splash or the tool. VERIFIED: PBScreen C# compiles,
     parse all + Test-Build green, decrypt-load. Deployed r113.
   2026-06-24 r114 - fix the r113 regressions (user). (#1) "Analyze shows detection window" was caused by opening the
     dialog MAXIMIZED (r113) - REVERTED to a normal 1040x760 window (MinW/H 820/600) and instead gave the report
     TextBox MinHeight=240 so it's never starved by the exclusions panel (the original blank-report complaint). (#2)
     SCREENSHOTS said "no app window" for every shortcut even though the windows were visible: the r112/r113 detection
     matched by PROCESS NAME / foreground, but a Java app (MASTA) opens its window under a CHILD process (javaw.exe),
     so MainWindowHandle/name never matched. REWRITTEN to enumerate ALL visible top-level windows via Win32 EnumWindows
     (new PBScreen.GetAppWindows -> visible, titled, >=200x150, not WS_EX_TOOLWINDOW, not our PID) and pick the LARGEST
     window that is NEW since launch (snapshot the window set right before launching each shortcut), regardless of
     owning process; falls back to the largest visible app window. Still waits for it to be STABLE >=3s and
     >=MinVisibleSec since launch, then ForceForeground + capture its rect. VERIFIED: EnumWindows C# compiles + runs,
     parse all + Test-Build green, decrypt-load. Deployed r114.
   2026-06-24 r115 - screenshots: simplest reliable model + diagnostics (user: "wait fixed 10s, and first check WHY no
     screenshot captured"). PROVED the capture pipeline works in the job's STA runspace (end-to-end test: launched
     notepad, GetAppWindows found it, ForceForeground + CopyFromScreen saved a 75KB PNG) - so the r114 STABILITY loop
     (needed the same handle 3x consecutively) was the suspect for never settling. REPLACED it with the user's model: a
     FIXED MinVisibleSec (10s) wait after launch, THEN find the window (largest NEW visible top-level window via
     EnumWindows, any owning process; else largest visible app window), re-checking every 2s up to TimeoutSec for slow
     apps. Added a DIAGNOSTIC log line per shortcut: "saw N candidate window(s); capturing '<title>' (pid X)" or "NONE
     matched - recording a miss", written to PackageBuilder.log so a miss is explainable. VERIFIED: end-to-end runspace
     capture test saves a PNG, parse + Test-Build green, decrypt-load. Deployed r115.
   2026-06-24 r116 - analyze layout (robust) + post-window LOAD wait (user). (#1) Analyze report STILL blank at normal
     size: now the dialog opens LARGE by default (90% of the work area, capped 1500x1000, CenterScreen) so the report
     shows without maximizing, AND the report ROW gets a hard RowDefinitions[2].MinHeight=320 so the exclusions panel
     can never squeeze it to nothing. (NOT maximized - that misbehaved in r113.) (#2) SCREENSHOTS: after the window is
     found, ADD a post-window LOAD wait (user: "wait additional 10-15s; some apps show full behaviour after loading
     internally"). New params PostWindowMin=12 / PostWindowSec=22. "Fully launched" is detected by CPU going IDLE: we
     sample the window's process TotalProcessorTime each second and capture once it's been <80ms/s (idle) for 3s in a
     row - but never before PostWindowMin and never after PostWindowSec. So a splash->blank->populated app is captured
     populated. Logs "waited Ns post-window for load to settle (CPU-idle: yes/no)". Re-raises ForceForeground right
     before the shot. (Answered the user's question: CPU-idle is how we detect "completely launched" beyond just the
     window existing.) VERIFIED: parse all + pack parse-gate; the capture pipeline itself was already proven end-to-end
     (notepad PNG) in r115's test - r116 only adds a wait before it. Deployed r116.
   2026-06-24 r117 - DIAGNOSED the empty-screenshots via the log (the diagnostics paid off). The log showed: the tool
     DOES find each window ("capturing 'MASTA' (pid 2264)", "capturing 'MASTA licence not found (Process ID 21744)'"),
     but after the 12-22s post-window wait -> "no app window ... nothing captured". TWO root causes: (a) MASTA can't
     run on this machine - it shows a "MASTA licence not found" dialog and EXITS (no licence/dongle), so there's no
     working app to shoot; (b) the post-window wait was LOSING the window - it found it, waited, and by capture time
     the (error) window had already closed. FIX: capture the window the MOMENT it's found (initial shot), THEN do the
     load wait, THEN re-capture the loaded view if the window is still alive (overwrites). So an app that errors/closes
     during the wait is still captured (you at least see the licence-error dialog), and a real app gets the loaded
     view. The wait also now breaks early if the process HasExited. Refactored the capture into a reusable $doCapture
     scriptblock. VERIFIED: parse + pack parse-gate. Deployed r117. NOTE TO USER: MASTA needs its licence on the test
     box to actually run - the screenshots will show the licence-error windows until it's licensed there.
   2026-06-24 r118 - THE screenshot bug found + human-like observe-capture (user). Rebuilt capture as the user's model:
     launch -> WATCH the window, snap when the picture STOPS CHANGING (= fully loaded), keeping the last frame so a
     window that closes mid-load is still captured; ALSO save the loading screen if it lingers past 4s (multiple PNGs
     per shortcut, named "<NN>_<name>_loading_<sec>s.png" + the final "<NN>_<name>.png"; index.html shows all). Stability
     = tiny 16x16 downscaled-hash compare across ~1.5s polls; observe >=5s, give up at 30s. THE ROOT-CAUSE BUG behind
     EVERY empty screenshot: the capture clamped the window rect to VirtualScreen, which produced a NEGATIVE height for
     windows positioned outside it (off-screen / multi-monitor / DPI) -> the grab returned null -> nothing captured.
     FIX: use the window's ACTUAL rect (CopyFromScreen handles off-screen edges), guard size only. PROVEN end-to-end in
     the job's STA runspace: full Invoke-ShortcutScreenshots on a Notepad shortcut now saves 01_Notepad.png (1.3MB).
     Also: analyze dialog opens at 90% work-area + report-row MinHeight 320 (visible without maximizing). Deployed r118.
   2026-06-24 r119 - capture TITLELESS dialogs (user's MASTA doc compared vs tool output). r118 captured 4/5 (RUNNA/
     Duty/VPS = the "MASTA licence not found" dialogs - correct; MASTA = splash). Shortcut 2 (MASTA Licence Manager)
     produced NO png: its first window is the "No Settings Found For This Version" dialog which has NO title-bar text,
     and GetAppWindows excluded titleless windows. FIX: dropped the GetWindowTextLength==0 exclusion (size + tool-window
     + not-ours filters are enough; title shown as "(no title)" in logs), lowered the min height 150->130. So titleless
     app dialogs are now captured. (Known remaining: apps that gate on a dialog needing a CLICK - e.g. MASTA's OK -> No,
     Licence Manager's OK - the tool captures the dialog state but does not click through; that's the licence env, not a
     tool bug.) VERIFIED: pack parse-gate; r118 already proved capture end-to-end (Notepad PNG); this only relaxes a
     filter. Deployed r119.
   2026-06-24 r120 - shortcut-2 miss diagnosis. r119 log showed Licence Manager STILL "saw 0 candidate window(s)" for
     the full 45s, and the user's doc shows that dialog HAS a title bar - so the r119 title-relax was NOT the cause and
     I was guessing. Added PBScreen.GetAllWindowsDebug() (every visible top-level window with size/pid/TOPMOST/
     toolwindow/rect/title) and the capture now DUMPS that list to the log on a miss, so the next run shows exactly what
     the Licence Manager actually put on screen (titleless? topmost? tool-window? off-screen rect? or no window at
     all?). Also widened GetAppWindows min size 200x130 -> 160x110. NOTE: the user's "can't snip over the window" clue
     is the Snipping Tool overlay vs a TOPMOST window - the tool's CopyFromScreen grabs the screen buffer regardless of
     topmost (RUNNA/Duty/VPS captured fine), so topmost is not why shortcut 2 misses; the dump will reveal the real
     reason. VERIFIED: GetAllWindowsDebug compiles + runs; pack parse-gate. Deployed r120. NEXT: read the log after the
     user re-runs to see the window dump for Licence Manager.
   2026-06-24 r121 - shortcut-2 SOLVED + dedup. The r120 window-dump nailed it: the Licence Manager dialog is
     "766x376 ... topmost=True tool=True 'No Settings Found...'" - it sets WS_EX_TOOLWINDOW, and GetAppWindows EXCLUDED
     tool windows (RUNNA/Duty/VPS dialogs are tool=False, hence found). FIX: GetAppWindows no longer excludes tool
     windows; instead it excludes the real desktop/taskbar/system shell by CLASS NAME (new GetClassName: Progman/
     WorkerW/Shell_TrayWnd/...) + off-screen windows (Left/Top <= -30000, e.g. Citrix at -32768). So titleless AND
     tool-window app dialogs are now captured. (2) DEDUP (user: "1st one - don't keep the same loading screen multiple
     times"): replaced the exact 16x16 MD5 with a TOLERANT 12x12 greyscale signature (per-cell tol 22, >8/144 cells =
     real change) - minor splash animation is ignored so (a) an animating splash counts as settled and (b) near-
     identical loading frames are NOT saved; if the FINAL frame equals the last loading frame, that loading png is
     deleted. VERIFIED end-to-end in the runspace: Notepad -> saw 6 candidates, picked 'Notepad', saved a loading frame
     then deduped it against the final -> only 01_Notepad.png remains. Deployed r121.
   2026-06-24 r122 - "wait until it FULLY loads" via screen-change settling (user: 1st/3rd still show loading, not the
     final; don't rely on CPU - watch the screen). Replaced the "stable for 2 polls" check with a SETTLE TIMER: any
     MEANINGFUL screen change (>10/144 tolerant cells) resets a timer; we capture only once the screen has had NO
     meaningful change for SettleSec (=8s) - i.e. the animating/cycling MASTA splash keeps resetting the timer and is
     NOT captured as final; when it finally goes static (the loaded app, or the licence/"No Settings" dialog) the timer
     runs out and THAT is captured. Observation cap raised 30s -> 90s ("whatever the time may be"); min 8s. Distinct
     loading frames still saved (deduped). Logs "screen SETTLED (no change for 8s) at Ns - fully loaded" or "hit the 90s
     cap (still changing)". VERIFIED end-to-end: a static Notepad settles in ~5s and yields one PNG; the loading frame
     is deduped. Deployed r122. (Answer to "how long does it wait": until the screen is unchanged for 8s = loaded, max
     90s/shortcut.)
   2026-06-24 r123 - "fully loaded" detection made TRULY human-like (user: a loading screen can have a CHANGING image
     above it, and a finished browser page has live news that keeps changing - magnitude of change alone can't tell
     loading from loaded; "think like a human, consider all possibilities"). Replaced the r122 "no major change for Ns"
     timer with TWO human cues combined:
       (1) STATIC FRACTION over a sliding window of recent frames - a cell constant across the WHOLE window is static
           structure; one that changes anywhere in it is "live" (news tile / video / spinner). We settle when >=72% of
           the screen has been static across a ~SettleSec window. So a loaded page whose news region churns is still
           "static enough" -> captured; a splash whose WHOLE content repaints is not -> keep waiting. (Unit-tested:
           loaded+live ring ~83% static -> settle; full-repaint ring ~16% -> wait; static dialog 100% -> settle.)
       (2) "Is this the real app window?" gate - GetAppWindows now also returns GWL_STYLE; we only declare LOADED on a
           window with a caption / a title / >=40% of screen (not a borderless splash). Only a splash up -> wait; a small
           titleless tool still settles after a longer grace so it isn't penalised.
       (3) SPLASH->APP HANDOFF - re-resolve the best window every poll; when a splash closes and the real (captioned/
           bigger) window appears we follow it, keep the splash as a loading frame, and re-observe the app. So "an image
           changing above a loading screen" is handled: that splash is followed to the real window, not mistaken for final.
       Cap still 90s backstop; distinct loading stages still saved + deduped. Renamed $pick height key H->Ht (collided
       with the handle key H). VERIFIED: parse + staticFrac unit + live Notepad e2e. Deployed r123.
   2026-06-24 r124 - shortcut capture made FACT-BASED on the window LIFECYCLE, not pixel-guessing (user: r123 didn't wait
     for MASTA - it grabbed the static splash; the real 'No Settings'/'licence not found' popup appears AFTER the splash;
     RUNNA likewise showed only the loading window. "see actual facts instead of guessing... refer how it behaves front
     and back end"). The decisive fact: the FINAL behaviour is a SEPARATE WINDOW that opens after the splash. So:
       (1) WINDOW-SET QUIET gate - each poll we enumerate the app's NEW-since-launch top-level windows and build a
           presence signature (handles + sizes). A new/closed window resets a "quiet" timer; we only finalise once the
           app has STOPPED opening/closing windows for SettleSec. So MASTA's licence dialog (which pops late) resets the
           timer when it appears and we settle on IT, not the splash. (GetAppWindows now also returns GWL_STYLE so we can
           tell a real interactive window - has WS_SYSMENU/close box or fills >=45% screen - from a chrome-less splash.)
       (2) CAPTURE THE LATEST window - the resolver follows the FOREGROUND window, else the NEWEST-appeared (tracked via a
           first-seen poll index), so a small late dialog on top of a big splash is the one captured. The superseded splash
           is kept as a loading_<sec>s frame.
       (3) Still require static-fraction >=72% over the settle window (so a finished news/video page settles while a full
           repaint waits) AND a real interactive window AND elapsed>=PostWindowMin; 90s cap is the backstop.
       Replaced the r123 splash->app single-handoff with this multi-window lifecycle model ($resolve + $evolveAt/$prevSet).
       VERIFIED: parse + staticFrac unit + live Notepad e2e (window set quiet, captured final, deduped loading). Deployed
       r124. NOTE for the user: this needs the app to actually create its windows; MASTA still needs its licence on the
       box, but now we WAIT for and capture its licence dialog instead of the splash.
   2026-06-24 r125 - SHORTCUT CAPTURE RADICALLY SIMPLIFIED (user: "these complicated logics are not working properly
     simplify"). Threw out the whole observe loop (static-fraction, window-set quiet timer, splash handoff, signatures,
     dedup) and did exactly what a normal user does:
       launch the target (fallback .lnk) -> WAIT up to TimeoutSec(30s) for a window to appear -> take SHOT 1 ->
       wait SecondShotSec(15s) -> take SHOT 2 -> close -> next shortcut.
     Capture is now FULL SCREEN (no per-window cropping): WorkingArea, which EXCLUDES the taskbar ("take the screenshot
     fully without taskbar"). Files: NN_<name>_shot1.png, NN_<name>_shot2.png. Re-foregrounds before shot 2 so a dialog
     that popped during the 15s (e.g. MASTA's licence popup) is on top and in frame.
     TRAY/BACKGROUND apps (the one extra rule the user wanted): if NO window appears within TimeoutSec, the app went to
     the system tray / runs hidden -> we still capture it: full screen WITH the taskbar (Bounds) so the tray area shows,
     PLUS a 2.4x ZOOM of the bottom-right notification area (NN_<name>_tray.png + _tray_zoom.png + _tray_zoom2.png after
     a delay, since the icon can appear late) so the tray icon is recognisable.
     Params trimmed to (TimeoutSec=30, SecondShotSec=15); removed MinVisibleSec/PostWindowMin/PostWindowSec/SettleSec.
     Only caller (GUI.ps1:3703) passes just -Shortcuts/-OutDir/-Title so nothing breaks. $pick kept only to detect "a
     window came up" + foreground it; $grab/$sigOf/$sigDiff/$saveFrame/$staticFrac/$resolve all deleted (C#
     GetAllWindowsDebug left in, now unused, harmless). VERIFIED: parse + live Notepad e2e -> shot1 + shot2 saved.
     Deployed r125.
   2026-06-24 r126 - SHORTCUT CAPTURE rebuilt as a fact-based DECISION TREE (user: "think like a 10-year packaging
     engineer; engineer except for very rare cases shouldn't have to do the job manually"; and for tray: "check whether
     it really opened there, don't just blind-capture"). Per shortcut, after launch:
       1) A WINDOW appeared (process-agnostic) -> shot1; wait SecondShotSec; keep shot2 ONLY if the screen changed
          (24x24 sameness check). Then CLASSIFY the window title and flag it: 'app window opened' (ok/green) vs
          'opened a prompt/dialog' (licence/login/first-run -> attention/amber) vs 'opened an ERROR/problem window'
          (error/failed/not found/no settings/crash, EN+DE -> attention). So the engineer sees WHAT opened at a glance.
       2) NO window but the app ADDED ITS OWN tray icon -> VERIFIED by a before/after tray-name diff (UIA enumerates
          Shell_TrayWnd + the opened overflow flyout; one-time hidden-icon baseline at run start; per-shortcut $trayBefore
          pre-launch). Only on a confirmed NEW icon do we open the flyout and screenshot it, naming the icon. (ok/green)
       3) NO window, no new icon, process ALIVE -> 'runs in the background, service-style, no UI' (info/grey, no shot).
       4) NO window, no icon, process EXITED -> 'launched then exited (stub/handoff or failed) - manual check' (attention).
       5) Launch threw -> 'did not start' (fail/red).
     Result objects now carry Outcome + Status; Write-ScreenshotIndex colour-codes the contact sheet by Status
     (ok=green, attention=amber, fail=red, info=grey) and shows the outcome text per shortcut. New C# in PBScreen:
     FindWindow, ClickAt (SetCursorPos+mouse_event), PressEsc (keybd_event), FindOverflowWindow (the hidden-icons flyout
     window). New helpers: $openTray (UIA Invoke the chevron, click fallback), $trayNames (filtered notification-icon
     names), $sig/$differ (sameness check), $grabWindow (capture one window scaled). Verify script adds a live tray
     ENUMERATION probe that dumps the chevron name + icon names found on the box. Pending deploy as r126 (blocked by a
     prolonged shell-classifier outage at write time; code complete + staged). See [[screenshot-keep-it-simple]].
   2026-06-24 r127 - LAUNCH RELIABILITY + count-based tray (user on r125 still: shortcuts didn't launch 1st time / worked
     2nd; tool went to tray even when app didn't open there; hidden icons not captured). Fixes, informed by a LIVE tray
     probe on the box:
       - LAUNCH like a user: Start-Process the .LNK (shell - honours target/args/workdir/run-as/associations), fall back
         to the target exe. Plus RELAUNCH ONCE if no window appears within TimeoutSec (the "worked the second time" case).
       - TRAY VERIFICATION switched from NAME-diff to COUNT-diff. The live probe showed real tray names are volatile on
         this machine ("Task Manager CPU 27%", "Unplugged: 42%", "File Explorer - 4 running windows") - a name diff sees
         every %/count tick as a "new icon" -> false tray captures. COUNT is immune: probe proved count1=15==count2=15
         stable over 2.5s while names churned. So: one-time baseline count (flyout open, taskbar app-buttons + chevron +
         shell nav excluded); in the no-window branch, count again - capture the flyout ONLY if count went UP. Else
         background (alive) / launched-then-exited. Chevron resolves as 'Show Hidden Icons' (EN); flyout opens (fly!=0).
       Removed $trayNames/$trayBefore/$hiddenBaseline; added $countTray. VERIFIED: parse + Notepad e2e (launch via .lnk,
       1 shot, outcome classified) + tray-count stability probe. Deployed r127. (Live shortcut run next, with the user.)
   2026-06-24 r128-r131 - PROCESS-AWARE capture + GHOST-SAFE close, driven by a LIVE drive-the-machine session on the
     real MASTA shortcuts (user: shortcuts launched late/mixed; "monitor task manager"; "only our launched process should
     be closed"; "close by title" fallback; "clear window for next shortcut").
     r128: launch the .LNK like a user; WAIT process-aware - snapshot pids before launch, track NEW pids (incl. children
       like javaw), and capture ONLY a window OWNED by one of THIS shortcut's pids ($pickOur) so a different slow
       shortcut's late window is never grabbed (the "mixed up" bug). Removed the relaunch-once (it made duplicates).
       Timeout 30->45s for slow cold starts (MASTA splash appears ~10s, runs ~30s).
     r129: CLOSE only the launch's OWN process tree (Win32_Process parent/child), excluding SERVICES (Win32_Service
       ProcessId) even if same-named, + core shell; per-process errors logged+skipped.
     r130: graceful WM_CLOSE drain before force-kill; prefer the FOREGROUND window in $pickOur (the licence DIALOG over
       the bigger splash); TITLE fallback (close leftover windows by matching title + kill non-service owner).
     r131 + LIVE ROOT CAUSE: the "MASTA not licensed" window that lingered into the next shortcut is a Windows GHOST -
       force-killing masta.exe while its modal #32770 dialog was up orphans the dialog to csrss; it is UN-removable
       (WM_CLOSE/EndTask/click all fail; clears only on logoff). Killing on the plain splash leaves NO ghost (validated
       3x). FIX: before force-kill, DRAIN dialogs - WM_CLOSE the launch's pid windows AND any #32770 that appeared since
       launch (by class, since the dialog may be owned by a helper not the app), loop until none remain, then kill on a
       no-dialog state. See [[force-kill-modal-dialog-ghost]]. Live findings: masta.exe is a single WPF process; dialog
       timing is highly variable (~20s to >60s); on a LICENSED box MASTA opens its real window and closes cleanly.
       VERIFIED each round: parse + Notepad e2e + tray-count probe; deployed through r131. (A stuck ghost remains on the
       test box from the investigation - needs a logoff to clear.)
   2026-06-24 r132 - PREDECESSOR REUSE REPORT (user: as a 20-yr packaging engineer, make reuse near-fully automatic and
     give an easy, layman-clear REVIEW so the engineer trusts the automation and only fills the few unknowns). The reuse
     LOGIC was already mature (installer/MST/ProductCode swap, version swap, v3->v4, uninstall-previous accumulation, v4
     scope fixes); the gap was that the review was a FLAT "things to fix" list that never showed what was DONE for you.
     Added Get-PredecessorReport (Build.ps1): returns @{Done; Check}. DONE = what was changed automatically, each line
     VERIFIED against the built script (never claims a swap not visible in the output) - reuse, identity, version-swap
     (with count), installer/MST/ProductCode swaps, carried session settings, kept custom code sections, uninstall-prev,
     v4 scope fix. CHECK = the unknowns (Get-ScriptReviewFindings + Get-SourceWarning) in plain language with WHY. Plus
     Format-PredecessorReportText and ...Html (presentable standalone export). GUI: Show-ReviewPopup became a two-part
     REPORT for reuse builds - green "Done automatically (N)" over amber "Please check / fill (M)" - the toolbar button
     reads "Reuse report (N)", it auto-opens on the first reuse build, and a "Save report (HTML)" button exports it as
     evidence. State.ReusePkg stores the built new-package facts (set in Build-Step3Script; cleared on Step-1 reset).
     VERIFIED: parse (Build/GUI/Predecessor) + Test-Build (added report asserts: Done lists version/installer swaps +
     uninstall-prev, clean swap -> no leftover Check, text+html well-formed) + offscreen WPF construct smoke. Deployed
     r132. See [[predecessor-reuse-report]].
   2026-06-28 CORPUS STUDY (user: study all 900 live packages, find what logic to keep so most tasks auto-handle for all
     source types + scenarios). Surveyed all 900 (\\mbddfsovpc01...\CMLib_LIVE\Apps): full read of each PSADT script +
     Files folder; authored code scanned BETWEEN section markers only (so template boilerplate doesn't inflate); + a
     250-pkg run through our build pipeline. Findings (written up presentably in files\CorpusFindings.md):
       - Platform: PSADT v3=793(88%), v4=106(12%); x64 70%, x86 28%. v3->v4 is THE dominant path.
       - Source shape: multi-installer 307(34%) is the biggest, exe-only 265(29%), msi+mst 148(16%), ZIP 114(13%),
         msi-only 34. ZIP delivery is common and Source.ps1 has NO zip extraction = top source gap.
       - Authored scenarios: conditional 99%, file-glob 78%, remove-file 61%, reg-remove 57%, Start-Sleep/WAITS 57%,
         copy 49%, reg-write 40%, per-user 29%, kill-proc 21%, new-folder 16%, vcredist/.NET PREREQS 9%, response-file
         8%, Active Setup 7%, shortcut 6%, sched-task 4%, cert 3%, service 3%, driver 1%, font 0.3%.
       - Pipeline health (250 sample): 250/250 build, 0 exceptions. Real issues: 1 parse corruption (Shining3D), 10
         v3->v4 residue (SAP/VS/Adobe/EPLAN), 4 custom-log-loss (Inventor -10, VS -9). (brace-imbalance 249 + empty-
         section 121 are METRIC ARTIFACTS: GUIDs/here-strings skew brace count; installer-line swap trips empty check.)
     PRIORITIZED GAPS to implement: (1) harden v3->v4 (fix the parse corruption + 10 residue + 4 log-loss; re-scan 900),
     (2) ZIP source auto-extract (13%), (3) prerequisite chaining (9%), (4) long-tail snippets: wait-for-process/file,
     run-with-response-file, drivers(pnputil), fonts. Implementation queued; was pinpointing exact residue cmdlets when
     a prolonged shell-classifier outage hit. Tools: corpus_survey.ps1 / corpus_authored.ps1 (scratchpad), existing
     Test-CorpusConversion.ps1 is the corruption scanner.
   2026-06-24 r133 - v3->v4 HARDENING (corpus gap #1), driven by a build-pipeline scan of all 900. The scanner's "10
     residue / 4 log-loss / 1 parse" OVERSTATED it (Get-ScheduledTask is a real v4 cmdlet, Refresh-Desktop is kept by
     design). The genuine gaps, all fixed + verified:
       - Execute-MSP was UNMAPPED -> added to the converter as Start-ADTMsiProcess -Action 'Patch' -FilePath (-Path) (EPLAN
         had 2; now 0). Verified rebuild: 0 Execute-MSP, 2 Patch calls, parse-clean.
       - HYBRID/v4 packages with stray v3 cmdlets (Set-RegistryKey, Write-Log) weren't converted: the old gate ran the
         converter only when "$isV3 AND no $adtSession". Now Read-PredecessorModel also runs it whenever ANY v3-only
         syntax is present ($hasV3Syntax incl. Write-Log) - safe on v4 (the v3 tables only match v3 names). Residue of
         Set-RegistryKey/Write-Log -> 0.
       - Add-UGPermission now handles a COMMA-SEPARATED PATH LIST (-Path "a","b" -> one Set-ADTItemPermission per path),
         both param orders; any leftover unusual shape gets a "# WARNING: convert manually" comment (never silently
         broken). Unit-tested all four cases.
     Re-scan of all 900: v3 residue eliminated (only unusual Add-UGPermission shapes remain, now flagged). FALSE ALARMS
     confirmed: "log-loss" = the scanner builds with uninstall-previous OFF so old-version "Uninstall X" logs are
     correctly excluded (Inventor: with uninstall-prev ON the 36 logs return); the 1 parse corruption (Shining3D) is a
     MALFORMED PREDECESSOR (stray '}' in its POST-INSTALL, braceDelta -1) already surfaced by Test-ScriptStructure
     "CORRUPT SCRIPT". Files: PSADT_V3toV4_Mappings.ps1 (Execute-MSP + Add-UGPermission), Predecessor.ps1 (trigger).
     Test-Build green. Deployed r133. Remaining corpus gaps (CorpusFindings.md): ZIP source auto-extract (13%),
     prerequisite chaining (9%), long-tail snippets (wait-for-proc/file, response-file, drivers, fonts).
   2026-06-24 r134 - ZIP SOURCE AUTO-EXTRACT (corpus gap #2, 13% of packages ship a .zip). Source.ps1: new
     Expand-SourceZips extracts every .zip to a LOCAL staging folder (Get-WorkPath Temp\zipsrc_*, each zip its own
     subfolder; share is read-only so never extract in place), strips MOTW. Resolve-Source computes $effRoot: if the
     tree has .zip(s) but NO loose installer beside them, extract and resolve the installer from the staging folder
     (icons/docs still resolved from the original RootPath; payloadRoot -> staging so Files\ ships extracted content).
     A .zip next to an .exe/.msi is left as-is (supplementary). VERIFIED end-to-end (zip-wrapped MSI -> Installer.msi
     resolved, Valid=True) + Test-Build green. Deployed r134.
   2026-06-24 r135 - LONG-TAIL SNIPPETS (corpus gaps #3+#4) via Save-Snippet (handles escaping/persist). Added 5
     categories / 10 snippets, all parse-clean: Processes>Wait (wait-for-process, wait-for-file w/ timeout, run-wait-
     check-exitcode - waits in 57% of corpus), Prerequisites>Runtimes (VC++ redist, .NET; -IgnoreExitCodes 3010/1638),
     Drivers>pnputil (install/remove .inf), Installers>Response file (.iss silent + how to record), Fonts>Install
     (copy+register). snippets.json now 15 cats / 30 snippets (was 10/20). Deployed r135.
   2026-06-24 r136 - PREREQUISITE AUTO-CHAINING (corpus gap #3, full version). Source.ps1 Get-PrerequisiteSpec
     recognises common runtimes by FILENAME (VC++ redist, .NET runtime/framework, Edge WebView2, DirectX; rules kept
     tight so a main app isn't mis-tagged). Build.ps1 Get-MultiCommandSet now STABLE-SORTS recognised prerequisites to
     the FRONT of a multi-installer build (install first; uninstall is the exact reverse = app first, prereq last),
     AUTO-FILLS a prereq EXE's silent switches when none were set, and prepends "## Prerequisite(s) install first: ...".
     Get-KBRecommendation gained a top "TIER -1" so the GUI also suggests the prereq switches. VERIFIED: a vc_redist
     listed AFTER the main MSI is reordered to install first with /install /quiet /norestart (unit) + Test-Build green.
     Deployed r136. ALL 4 corpus gaps now FULLY addressed. Corpus study COMPLETE - see CorpusFindings.md.
   2026-06-24 r137 - REUSE PRODUCTCODE REPLACEMENT, found + fixed by VERIFYING reuse across the corpus (user: "not
     assumption but it will work, PC replaced wherever required like SoftIdent + sections"). Verification of single-MSI
     predecessors revealed a REAL gap: an MSI installed BY FILE (Start-ADTMsiProcess -FilePath x.msi) has NO ProductCode
     on the install line, so the build's swapMap (which used Model.Installer.ProductCode = the INSTALL code) never picked
     it up -> the MAIN-UNINSTALL kept the predecessor's ProductCode (would uninstall the OLD version). FIX (Build.ps1):
     in the single-installer branch, ALSO add Get-PredecessorUninstallPC -> NewPkg.ProductCode to the swap map; and add
     PreRepairCode to the Swap-InstallerRefs sections (repair = uninstall-then-reinstall of the CURRENT package, must use
     the new code). For the genuinely AMBIGUOUS case (old PC in POST-INSTALL/CUSTOM-VARS - e.g. a DisplayIcon registry
     write under the uninstall key vs an intentional remove-old-version), Get-PredecessorReport now adds a CHECK item
     instead of auto-swapping. EVIDENCE (97 single-MSI built): MAIN-UNINSTALL new PC 97/97, SoftIdent new PC 92/92, 0
     parse errors, all 7 residual old codes report-flagged. Multi-component still swaps per-component by order; type/
     structure mismatch still warns via Get-SourceWarning. Test-Build green. Deployed r137. See [[predecessor-reuse-report]].
   2026-06-30 r138 - PROCTOBLOCK DEFAULTS TO PROCTOCLOSE in BOTH fresh + predecessor-reuse builds (user: "while
     predecessor reuse proctoblock should get what proctoclose is there by default" + "even in fresh package time it
     should get what proctoclose gets"). Rationale: the apps you CLOSE before install are the same ones to BLOCK during
     it (template gates blocking on `if ($adtSession.ProcToBlock)` then blocks `-CloseProcesses $adtSession.ProcToClose`).
     New Build.ps1 Set-ProcToBlockDefault runs on the final script in both paths (before Format-OutputScript), IDEMPOTENT
     per the user's exact rule ("if already there skip it; if that already-there is $adtSession.ProcToClose template one
     or old psadtv3 $vwg_proctoclose then it should replace... but if really process are there then can skip"):
       REPLACE ProcToBlock with ProcToClose's value when ProcToBlock has NO real (quoted) process name yet - i.e. empty
         (@() / '' / ""), a REFERENCE ($adtSession.ProcToClose / $VWG_ProcToClose / $ProcToClose), or a <placeholder>;
       SKIP (never clobber) when ProcToBlock already lists real quoted processes (legitimately authored differently);
       no mirror when ProcToClose itself is empty. "Has a real process" = contains a quoted NON-empty literal; guards a
       multi-line/unbalanced array literal (skips rather than risk corruption). EVIDENCE (250 live predecessors built):
       ProcToClose had real procs in 211 -> ProcToBlock==ProcToClose 206, own authored list kept 5, 0 mismatches; 39
       had empty ProcToClose (correctly no mirror). 6 new Test-Build asserts (mirror empty/$adtSession/$VWG_, skip
       authored, skip empty-close, fresh-default mirror) - all green. Deployed r138. See [[predecessor-reuse-report]].
   2026-06-30 r139 - SNAPSHOT-ASSISTED PREDECESSOR REUSE (user: "how we can use snapshot info for predecessor reuse?
     without breaking predecessor logic"; chose "merge net-new only" + "freespace softident should get changed from
     snapshot info" + "if already similar there then not needed"). New Build.ps1 Merge-SnapshotDeltas runs at the END of
     Build-PredecessorScript (after all predecessor logic, before Set-ProcToBlockDefault) - ADDITIVE / value-refresh ONLY,
     never touches the predecessor's install/uninstall/repair command bodies:
       FreeSpace -> RAISED to the new version's measured footprint when bigger (max, never lowered).
       SoftIdent -> refreshed from the new version's detection ($NewPkg.SnapshotSoftIdent, e.g. a wrapped-EXE's real MSI
         GUID) ONLY when the predecessor's is empty/<placeholder>/single plain ProductCode; a MULTI-GUID or EXPRESSION
         detection ($/double-quote/-and/-or/Test-Path/Get-ItemProperty) is left intact. Tagged '# [snapshot-detection]'.
       ProcToClose/Block -> UNION in new-version app exes the predecessor didn't list (additive; ProcToBlock then mirrors
         via r138 Set-ProcToBlockDefault when it was empty).
       Cleanups -> each snapshot cleanup whose distinctive target (Get-CleanupTarget: -Name/leaf/longest literal) is NOT
         already in the script is appended to POST-INSTALL/UNINSTALL via Append-ToSection, tagged '# [snapshot-added]';
         a target the predecessor already handles is SKIPPED (no duplication - the user's "if already similar not needed").
     Plumbing: GUI Build-Step3Script now ALWAYS computes the snapshot detection + procs but in REUSE stashes them as
     $newPkg.SnapshotSoftIdent / SnapshotProcs (NOT SoftIdent/ProcToClose - those would clobber via the existing line-1218
     override / session-carry); cleanups already flowed via PostInstall/UninstallExtra. Per-user config STAYS out of reuse
     (PerUserMode forced 'None' at the GUI when a predecessor is loaded) - add per-user via snippets. Get-PredecessorReport
     surfaces both tags (Done + Check). 14 new Test-Build asserts (raise/not-lower FreeSpace, refresh vs multi-GUID-intact
     SoftIdent, proc union, dedup skip, net-new tag, POST-UNINSTALL routing, report Done/Check) - all green. Fresh path
     unchanged (still auto-injects via New-StandardCommands). Deployed r139. See [[predecessor-reuse-report]].
   2026-06-30 r140 - SCCM DEV->TEST HIVE MOVE now EMPTIES the collections of test machines first (user: "keep a check if
     install uninstall collections any members were added remove them and then move to test hive if nothing there then can
     directly move"). Test machines are added as DIRECT membership rules during DEV testing (Add-SccmTestMachine); those are
     per-environment and must not ride along to the next hive. New Sccm.ps1 Clear-SccmCollectionDirectMembers removes ALL
     direct-membership rules from a collection (query rules / limiting coll untouched) and returns the count; Move-SccmDevToTest
     now clears the INSTALL/UNINSTALL (TEST) collections BEFORE the Move-CMObject, logs "cleared N test member(s)" (or "no
     members - moved directly"), and reports it. Mockable Test-Build asserts added (loads Sccm.ps1; stubs Get-/Remove-
     CMDeviceCollectionDirectMembershipRule): removes-all/count, called-per-member, empty->0.
     VERSION 1 RELEASE CHECK (release_check.ps1): ALL shipped modules parse (Core/Theme/Predecessor/Build/Source/MstBuilder/
     BundledMsi/Snapshot/Screenshots/Assemble/Snippets/Sccm/Intune/PSADTv3v4/GUI/Loader/Pack-Engine); settings/snippets/
     KnowledgeBase JSON valid; FRESH 100/100 + REUSE 100/100 corpus builds parse-clean; pak round-trip (AES-256 decrypt ->
     Deflate -> parse) = 0 errors on the DEPLOYED artifact. Test-Build green. Deployed r140. NEXT: plan portable/lightweight
     user rollout. (Live SCCM member-clear path to be confirmed against the real G08 site on the next on-site test.)
   2026-07-01 r141 - THREE fixes from the user's on-share full-functionality test:
     (1) PREDECESSOR UNINSTALL OPT-OUT BUG: unchecking "add uninstall previous" was DELETING the predecessor's OWN existing
         uninstall block(s), not just skipping the generated one. Fix (Build.ps1 Build-PredecessorScript): the existing
         blocks are AUTHORED code - always extracted (to shield from the version swap) then re-inserted verbatim REGARDLESS
         of the checkbox; the checkbox now gates ONLY New-UninstallPreviousBlock (the generated immediate-predecessor block).
         3 Test-Build asserts (opt-out keeps {1111} existing block, adds no generated {2222}, exactly one block).
     (2) INTUNE "Cannot add type. Compilation errors occurred." when run from the UNC share: MSAL.PS compiles internal C#
         referencing its own DLLs and the CLR/csc won't load them from a remote path. Fix (Intune.ps1): new
         Get-LocalModuleManifest stages a UNC module folder to a LOCAL cache (Get-WorkPath 'modules', MOTW-stripped, freshness
         check) and imports from there; MSAL.PS before IntuneWin32App. Local paths pass through unchanged (2 asserts). ConfigMgr
         is NOT staged (huge; it imported fine - its error was environmental, below).
     (3) SCCM "New-PSDrive G08: A non-recoverable error occurred during a database lookup" = the SMS Provider host
         (mbdcaswvtb29843.mn-man.biz) did not RESOLVE/reach from the test machine - a network/DNS/VPN/rights issue, NOT a tool
         bug (the ConfigMgr module imported fine from the share, got as far as New-PSDrive). Improved Connect-Sccm error to name
         the server + say to check name resolution / VPN / settings.json Sccm.SiteServer / SCCM rights.
     Test-Build green. Packed r141; deployed pak + PackageBuilder.exe.config to BOTH the local folder AND the user's share
     (\\mndemucfsm01\...\Balaji\PackageBuilder). User to re-test Intune publish (now staged locally) + SCCM (after confirming
     the site server resolves).
   2026-07-01 r142 - three more from the on-share test:
     (1) INTEGRATION TAB package-name field was empty after a build. GUI.ps1 Populate-Publish now also sets
         $TxtPubPkgName.Text = $base.FullName (it filled every OTHER field but skipped the name box).
     (2) INTUNE "no token after sign-in - Error creating the Web Proxy specified in the 'system.net/defaultProxy'
         configuration section": a machine.config defaultProxy that THROWS on proxy creation (WPAD/script) - the getter
         [WebRequest]::DefaultWebProxy threw, MSAL got no token. Fix (Intune.ps1 Set-IntuneProxyCreds): resolve the system
         (WinINET) proxy DIRECTLY via GetSystemWebProxy() - which does NOT go through that config section - attach default
         creds, pin as DefaultWebProxy; on failure fall back to a direct (null-proxy) connection. Never throws (asserted).
         (Module STAGING from r141 already worked - both modules staged + imported from the local cache.)
     (3) LONG PATH hardening: PackageBuilder.exe.config gains AppContextSwitchOverrides
         (Switch.System.IO.UseLegacyPathHandling=false;Switch.System.IO.BlockLongPaths=false) so System.IO tolerates
         >260-char paths on OSes with long paths enabled. Note: full >260 support also needs the OS LongPathsEnabled
         policy (IT). The Intune local cache (C:\temp\PackageBuilder\modules) is SHORT, which itself reduces path length.
     SCCM "database lookup" is unchanged = the SMS Provider FQDN not resolving from the machine (network/DNS/VPN), NOT a
     tool bug. Test-Build green. Packed r142; pak + exe.config redeployed to local + the user's share.
   2026-07-01 r143 - ROOT CAUSE of "works when copied local, FAILS from the share shortcut" (user tested both on the same
     machine, has SCCM rights + console works): launching the exe from a UNC share puts .NET in the RESTRICTED NETWORK
     ZONE, which CAS-sandboxes arbitrary NETWORK operations - so SCCM (WMI + DNS to the site server -> "database lookup" /
     Winsock WSANO_RECOVERY) and Intune (HTTPS to Microsoft + GetSystemWebProxy -> "invalid argument" -> "error sending
     request") FAIL, while local (MyComputer/full-trust) works. FILE I/O still worked from the share (package creation,
     module staging), so it is the network-permission subset that is blocked. FIX shipped: GUI.ps1 detects a UNC $root and
     MIRRORS the tool to %LOCALAPPDATA%\PackageBuilder (robocopy /MIR /MT:16, EXCLUDING the huge ConfigMgr module + *.pdb,
     120s cap) then RELAUNCHES the local exe (full trust) and [Environment]::Exit(0)s the share instance; sets
     $env:PB_SHAREROOT so the local process still imports the not-mirrored ConfigMgr module from the share (Connect-Sccm
     fallback added). Guarded: only in the packed exe + UNC + not already local (PB_LOCALRUN) + settings.json
     "LocalRelaunch" != false; ANY failure falls through to running from the share (unchanged). Users still hold only a
     shortcut. NOTE: if the share instance is TOO restricted to even Start-Process, the relaunch can't fire - then the
     DEFINITIVE fix is adding the share host to the LOCAL INTRANET zone (GPO "Site to Zone Assignment List" ->
     file://mndemucfsm01 = zone 1, or reg HKCU\...\Internet Settings\ZoneMap\Domains\mndemucfsm01 file=DWORD 1), which
     makes the share full-trust like local. Test-Build green. Packed r143; deployed pak + exe.config to local + share.
   2026-07-01 r143 - SHARE-RUN NETWORK FAILURE root-caused. User proved: whole folder COPIED LOCAL = SCCM+Intune work;
     run from the SHARE via shortcut = both fail (SCCM "database lookup" DNS; Intune GetSystemWebProxy "invalid argument"
     + token "error sending request"). Same across machines. NOT the exe.config (SCCM failed from the share BEFORE the
     exe.config existed too). => the UNC EXECUTION CONTEXT breaks the network stack (WMI + WinHTTP/DNS). ZERO-COPY attempt
     (r143): a process launched from a UNC share has its CURRENT DIRECTORY on the network path, a known trigger for exactly
     these WMI/WinHTTP failures. GUI.ps1 now pins [Environment]::CurrentDirectory (+ Set-Location) to a LOCAL folder
     ($env:TEMP) at startup, BEFORE any network op, while still running from the share. Tool resolves all its own files by
     ABSOLUTE path (Get-ToolRoot), so CWD move is safe. IF this fixes it -> true zero-copy portability from the share. IF
     NOT -> the only robust path is auto-stage-local (loader mirrors the folder to %LOCALAPPDATA% once + on update, reruns
     local; user still only uses a shortcut, no manual copy) - offered, not yet built. Test-Build green; deployed r143 to
     local + share. AWAITING user's from-share retest.
   2026-07-01 r144 - SELF-STAGE with DEFERRED publish modules (user's final portability design). Shortcut -> SHARE exe;
     on a network launch the tool mirrors the CORE (exe, pak, 3 JSONs, AvalonEdit, icon, PSADT template) to
     %LOCALAPPDATA%\PackageBuilder and RE-LAUNCHES locally (network ops need a local process). The HEAVY SCCM/Intune
     modules are NOT copied at launch - they are staged locally ON DEMAND the first time the user publishes (or opens
     the Integration tab, which warms them in the background). Core.ps1: Test-NetworkPath, Get-LocalStageRoot,
     Copy-IfNewer (newer-only), Copy-TreeNewer (robocopy /XO), Invoke-SelfStage (core mirror + writes a .source marker),
     Get-StageSource (marker or $env:PB_SHAREROOT), Ensure-PublishModulesStaged (mirror ConfigMgr + MSAL.PS/IntuneWin32App
     + IntuneWinAppUtil.exe share->local Lib, idempotent). GUI.ps1: replaced the old /MIR-everything-except-ConfigMgr
     relaunch with Invoke-SelfStage (core-only); Ensure-PublishModulesStaged called at the top of BOTH publish jobs
     (create + ops) so modules are present before Connect-Sccm/Connect-Intune; a background warmer kicks on first
     Integration-tab open. UPDATES: maintainer replaces the SHARE pak -> each launch Copy-IfNewer pulls the newer pak to
     the local cache before relaunch, so users auto-get updates (modules refresh newer-only on next publish). Settings
     switch "LocalRelaunch": false disables it. Full-local-copy still works (no network -> no relaunch, no .source -> no
     module staging). Removed the hidden/read-only lock from the local folder + exe.config from share+local (user: not
     needed now). 15 new self-stage Test-Build asserts (core copied, ConfigMgr/MSAL deferred, on-demand staged, newer-only,
     network detect, PB_SHAREROOT fallback) - all green. Deployed r144 to share (master) + local. See [[shared-folder-deployment]].
   2026-07-01 r145 - three from the user's big feedback batch:
     (1) PRODUCT-CODE-FROM-SNAPSHOT correctness (reuse): GUI.ps1 now only sets $newPkg.SnapshotSoftIdent (which drives the
         reuse detection refresh) when the snapshot resolves to a SINGLE product code. If the snapshot shows MULTIPLE
         ProductCodes (multi-component installer), it does NOT swap - keeps the predecessor's detection (a one-code swap
         would be wrong). Counts distinct GUIDs in $State.SnapshotUninstall.
     (2) SCCM 'run policy' access-denied: Invoke-SccmMachinePolicy now detects denied/verweigert/0x80070005 and says to run
         Package Builder AS ADMINISTRATOR (triggering CCM client policy needs local admin) - environmental, not a bug.
     (3) SHORTCUT-SCREENSHOT button consolidated: removed the duplicate on the Integration tab (BtnShotValidate); kept the
         ONE on the Troubleshoot tab (BtnTsShots). Both called the same Invoke-ShortcutValidation (install-timestamp/folder/
         snapshot detection - not name guessing), so no logic lost. Main XAML re-validated. Test-Build green. Deployed r145.
     STILL QUEUED from the batch (bigger, next): UNINSTALL SNAPSHOT + smart leftover cleanup (before/after user-run uninstall
     -> diff leftovers app-related only by name/ARP/install-dir/vendor+app, remove now-empty folders, PSADT v4/PS, ref live
     packages); LOAD a saved snapshot report to re-apply actions; skip re-copying a source already on a LOCAL drive; keep the
     screenshot button enabled until close/reset.
   2026-07-01 r146 - POLICY-TRIGGER fix (I was WRONG in r145 that it needs elevation - user corrected). Running client
     policy on the LOCAL machine should NOT need admin. Fix (Sccm.ps1): new Invoke-CmLocalClientActions uses the ConfigMgr
     Control Panel applet COM object 'CPApplet.CPAppletMgr' -> GetClientActions() -> PerformAction() for actions matching
     'machine policy'/'application deployment' - the SAME path as the Configuration Manager control-panel Actions tab, which
     the INTERACTIVE USER runs WITHOUT elevation. Invoke-SccmMachinePolicy now: LOCAL -> CPApplet (no admin); REMOTE (or
     applet unavailable) -> the old WMI root\ccm TriggerSchedule (needs rights on the remote). Reverted the bogus "run as
     admin" message. ALSO (same r146) NON-ADMIN LOCAL LOG FETCH: new Get-PBClientPath - for the LOCAL machine it returns the
     DIRECT path (c$\Windows\CCM\Logs -> C:\Windows\CCM\Logs, c$\ProgramData\VWG\Logs -> C:\...), avoiding the c$ ADMIN SHARE
     (which needs admin even on your own box); REMOTE still uses \\host\c$\... (inherently needs admin on the remote). Wired
     into Get-SccmEnforceStatus, Get-SccmDiscoveryResult, Get-SccmPsadtLogList, and Get-SccmLog (both PSADT + AppEnforce/
     Discovery). 3 Test-Build asserts. AUDIT for "run on same machine, RDP, no admin": LOCAL is now admin-free for policy +
     logs + WMI(clientsdk read)/registry(HKLM read); only REBOOT (Restart-Computer) inherently needs admin; REMOTE machine
     actions (c$ logs, remote WMI, reboot) inherently need rights on that remote. Site ops need SCCM rights (not machine
     admin); Intune all non-admin. Deployed r146 to LOCAL ONLY - user froze the share and will push it manually.
   2026-07-02 r147 - V3 SCCM-PUBLISH FETCH fixes (user found live: Altair Pulse v3 gave an EMPTY uninstall key). Root
     causes in Get-SccmFieldsFromPackage: (a) the field reader didn't match the v3 VWG_ prefix ($VWG_SoftIdent) -> $get now
     allows (?:VWG_)? AND takes the LAST definition (v3 defines SoftIdent twice - top + CUSTOM VARIABLES 32-bit override -
     and the LAST is what runs); (b) the v3 hive token $($VWG_CurrentRegWOW) embedded in SoftIdent is now RESOLVED from the
     token's own definition in the same script ('WoW6432Node\' on 32-bit / '' on 64-bit; no def -> by AppArch), then the
     existing downstream strips WoW6432Node + ticks the 32-bit box - key box stays clean, checkbox carries bitness (user's
     rule); (c) [DisplayVersion = X] with SPACES already parsed (verified by test); (d) v3 commands now POSITIONAL:
     '"Deploy-Application.exe" Install' (no -DeploymentType, team convention); v4 re-verified w/ test (WoW strip + 32-bit +
     PC/version from SoftIdent). 8 new Test-Build asserts (Altair Pulse fixture verbatim). Also fixed Test-Build leaking
     robocopy's exit code 1 (explicit exit 0). Intune sign-in + policy trigger CONFIRMED WORKING live by user (r146).
     Deployed r147 LOCAL ONLY. Tool goes LIVE today EOD.
   2026-07-02 r148 - REMOTE SCREENSHOTS (plan item C) + UI SMOOTHNESS + snapshot-dialog flexibility. Deployed to LOCAL
     AND SHARE (user unfroze the share). Tool goes LIVE today.
     (1) REMOTE SMOKE-TEST SCREENSHOTS: Testing tab gains 'Remote screenshots' (BtnRemoteShots, acts on the machines list
         like Run machine policy). Screenshots.ps1: New-PBShotsAgentScript generates a SELF-CONTAINED agent (tokens +
         snapshot reference shortcut names baked in; single-quoted template with __PB_*__ placeholder replace); agent
         discovers Start-Menu .lnk (ref names win over fuzzy tokens; uninstall/help excluded), launches each, captures via
         PrintWindow(PW_RENDERFULLCONTENT) = WORKS ON A LOCKED RDP SESSION (with a black-frame check -> CopyFromScreen
         fallback for GPU apps), closes apps, writes PNGs + index.html + done.flag. Invoke-RemoteShortcutShots stages to
         \\m\c$\temp\PBShots (C:\temp NOT Windows\Temp - ACLs, user's call), finds the logged-on user (Win32_ComputerSystem
         -> quser fallback), Register-ScheduledTask via CIM with New-ScheduledTaskPrincipal -LogonType Interactive (runs in
         THEIR session, NO password, works locked), polls done.flag (420s cap), pulls the report to Screenshots\<pkg>\
         remote\<machine>\, cleans task+temp in finally. Local-machine guard -> points to the Troubleshoot local button.
         'remoteshots' case in Start-SccmManageJob (background; opens the pulled folder).
     (2) SMOOTHNESS - "(Not Responding)" killers: new Invoke-PBAsync (background runspace w/ engine + Done on UI thread via
         DispatcherTimer). Rewired the three sync share-walkers: BtnPred (STAGE 1 candidates + STAGE 2 Read-PredecessorModel
         both async; UI continuation extracted to Set-PredecessorUi), BtnFetch (Find-SourceFolder async), BtnLoadOutgoing
         (Find-OutgoingPackage async). Buttons disable + status shows 'window stays responsive' during each.
     (3) Snapshot dialog: 'Launch + screenshot shortcuts' now ENABLED whenever State.SnapshotShortcuts persist (reopened
         dialog / earlier analyze) with click fallback to the persisted list - part of plan item B flexibility.
     9 new remote-agent asserts (parses, tokens quote-escaped, refs baked, PrintWindow, excludes, done.flag/index, C:\temp,
     local-guard) - ALL TESTS PASSED; main XAML re-validated. REUSE RELIABILITY AUDIT (user asked): corpus 80-100/100
     parse-clean fresh+reuse (multiple runs), PC swap verified 97/97 single-MSI + multi-component per-component, opt-out
     keeps authored blocks, snapshot-merge inert w/o snapshot + multi-PC guard - solid; known judgment points stay flagged
     in the reuse report (type mismatch verbatim carry, old-PC-in-POST-INSTALL ambiguity).
   2026-07-02 r149 - PLAN A + B COMPLETE (user: finish before go-live, be efficient). Deployed local + share.
     (A) UNINSTALL LEFTOVER CHECK - the SMART design: NOT a second snapshot pair. The install snapshot already knows
         exactly what was created, so after the user MANUALLY uninstalls, a LIVE Test-Path over those known items finds
         precisely what the uninstaller left behind - zero noise, zero re-scan, app-related only (user's requirement).
         Snapshot.ps1: Get-LeftoverCandidates (compact JSON-safe lists: app files/dirs incl. file-parents, IsApp reg keys,
         shortcut .lnks - persisted with the report); ConvertTo-PBRegForms (any hive spelling -> Registry:: for Test-Path
         + HKLM:\ drive form for the command); Get-UninstallLeftovers (live check; top-most leftover FOLDER swallows its
         files/subdirs, top-most reg key swallows subkeys; EMPTY folders flagged; commands = Remove-ADTFolder /
         Remove-ADTFile / Remove-ADTRegistryKey -Recurse, all tagged '# [post-uninstall]' -> the EXISTING Apply pipe routes
         them into POST-UNINSTALLATION; 60-item cap). Dialog gains '4. Leftover check (after uninstall)' (enabled after
         Analyze, on reopen w/ persisted state, or after Load report); results append to the report + ticked checkboxes.
     (B) SAVE/LOAD REPORT - Apply now AUTO-SAVES the full re-loadable report (Save-SnapshotState JSON: report text,
         exclusions+tick states, shortcuts, HKCU/user files, footprint, uninstall/PC/detection, leftover candidates) to
         WorkRoot\Reports\<pkg>.snapshot.json. New 'Load report...' dialog button (Read-SnapshotState) restores ALL of it -
         re-apply actions, screenshot shortcuts, or run the leftover check across sessions/restarts, no re-install needed.
         State.SnapshotLeftoverCandidates added (init + StepOwns[2] + reset defaults); ctx.LeftoverCandidates; Apply result
         + caller persist it; reopen-rehydrate also restores candidates + shortcuts.
     11 new asserts (folder-swallow, EMPTY flag, gone-not-listed, reg top-key + drive-form + -Recurse, post-uninstall tags,
     save/read round-trip incl. candidates/shortcuts/footprint) - ALL TESTS PASSED. Whole pending plan (A, B, C) now DONE.
   2026-07-02 r150 - RUNTIME DATA sweep added to the leftover check (user asked how in-between testing junk is handled;
     this closed the one real gap). The candidate-based design already IGNORES unrelated junk created between Analyze and
     uninstall (only install-created items are ever checked) and SWALLOWS the app's own runtime junk inside install-created
     folders (folder-level Remove-ADTFolder removes contents too). GAP: data the app created at FIRST RUN in locations the
     installer never touched (ProgramData\<vendor>, %APPDATA%\<app>...). NOW: Get-UninstallLeftovers step 5 sweeps the
     standard data roots (ProgramData, APPDATA, LOCALAPPDATA, ProgramFiles x64+x86 - injectable -DataRoots for tests) +
     HKCU/HKLM Software for top-level folders/keys named EXACTLY like the App or Vendor (>=3 chars, exact match only - no
     fuzzy). SAFETY POLICY: APP-named -> ticked by default; VENDOR-named -> reported UNTICKED with a '[VENDOR - may be
     SHARED with other <vendor> products]' warning (removing a shared vendor dir could break sibling products - a human
     decides). Get-LeftoverCandidates now persists Vendor/App; GUI passes them + checkbox honors the Default flag; report
     lines show [x]/[ ] tick state. 3 new asserts. ALL TESTS PASSED. Deployed r150 to local + share.
   2026-07-02 r151 - FIVE fixes from the user's live testing (deployed local + share):
     (1) UNINSTALL DERIVATION (Snapshot.ps1 Get-UninstallFromSnapshotDiff): an ARP entry whose "UninstallString" is a
         NORMAL app exe (launcher/updater registers these) is SKIPPED with a log line - a real uninstall is msiexec / a
         GUID / an uninstall-looking exe (unins|uninstal|remove). BEST-match scoring replaces first-match (exact=3,
         contains=2, +1 for GUID key); SoftIdent ProductCode now comes from the MOST-matched GUID entry even when the
         primary ARP key isn't a GUID (EXE-type installs). All real uninstall entries still all used (uninstall-reverse).
     (2) PSADT ENV VARS (new Format-PBPathArg): generated cleanup/leftover/exclusion paths no longer hardcode
         C:\Program Files etc. - longest-prefix mapping to $envCommonDesktopDirectory/$envCommonStartMenuPrograms/
         $envProgramFilesX86/$envProgramFiles/$envProgramData/$envLocalAppData/$envAppData/$envWinDir; DOUBLE-quoted arg
         when substituted (must expand), single-quoted literal otherwise. Applied in Get-UninstallLeftovers (files/
         folders/lnk/runtime sweep) + Get-ExclusionCommand.
     (3) CLEANUP TIMING (user rule): install-snapshot Apply writes ONLY the uninstall command + POST-INSTALL exclusions;
         '# [post-uninstall]'-tagged items are DEFERRED (kept ticked, noted) until '4. Leftover check (after uninstall)'
         has RUN (ctx.LeftoverChecked; persisted as State.SnapshotLeftoverChecked + in the saved JSON; restored on
         reopen/Load). After the check (even a CLEAN result), Apply writes them + the real leftovers to POST-UNINSTALL.
     (4) DOCS ONE LEVEL UP (Source.ps1 Get-SiblingDocItems new branch): installer in a BUILD folder whose parent is a
         VERSION_REV-named package folder (^\d+(\.\d+)*[_-]\d+$, e.g. 26.0.0.0_0001) -> that folder's DOC FILES (install
         instructions .docx, complexity sheet .xlsx - DocExts) + doc-NAMED folders go to Documents; other folders are
         LOGGED as not-auto-included (no junk hoovering). Existing source-named/sibling/flat logic untouched.
     (5) ICONS matched pair (Assemble.ps1 Copy-PackageIcons + Intune.ps1 Get-IconBase64): whenever an .ico exists, a
         SAME-BASENAME .png is generated FROM it (even if a stray png exists); Intune now PREFERS the png that has a
         matching .ico sibling -> ARP/SCCM (.ico) and Intune (.png) always show the SAME image; predecessor ico-only
         Icons get their png generated. ALSO fixed my r148 closure bug the user hit ("property CreatedPath cannot be
         found" on Load from Outgoing): $script:State is NULL inside .GetNewClosure() callbacks - all async Done handlers
         (BtnLoadOutgoing, BtnPred both stages) + dialog handlers (bShots fallback, bLeftover, rehydrate) now use a
         captured $stateRef (per ps-wpf-closure-scope). 13 new asserts - ALL TESTS PASSED.
   2026-07-02 r152 - FULL CLOSURE-SCOPE AUDIT (user asked "any errors now? check thoroughly"). Built an AST analyzer
     (scratchpad closure_audit.ps1): finds every $script:/$global: reference inside any .GetNewClosure() block in GUI.ps1
     (53 blocks) - the "property CreatedPath cannot be found" bug class (writes throw; reads silently return $null).
     FOUND 11 (all PRE-EXISTING, not from the recent async work): 3 REAL broken features - (a) 'Run & capture MSI' Use
     button ALWAYS returned nothing ($script:CaptureResult write lost in the closure's scope; body read real scope's
     $null) -> fixed with a shared $capRef hashtable; (b) 'Copy to Outgoing' always said "No created package yet"
     ($script:State.CreatedPath read null) -> (Get-PBState).CreatedPath; (c) reuse-report Save-HTML wrote empty
     Model/NewPkg + generic filename -> Get-PBState. Plus 6 cosmetic $script:Win no-ops (window not hidden/restored
     around screenshot flows, render flushes) -> (Get-PBMainWindow). FIX PATTERN: new closure-safe accessors
     Get-PBState / Get-PBMainWindow (FUNCTIONS execute in their DEFINITION scope, so closures reach the real objects
     through them). Audit re-run: CLEAN - 0 references in all 53 blocks. ALL TESTS PASSED. Deployed r152 local + share.
   2026-07-02 r153 - FETCH = MANUAL parity (user: "fetch button should have same logic as manual installer fetching")
     + full small-things sweep. Resolve-Source now runs a MANUAL-PARITY doc harvest when the resolver found NO docs
     inside the root and installers exist: Get-SiblingDocItems on the first installer's parent - covering source-named
     siblings AND the VERSION_REV one-level-up docs (which can sit OUTSIDE the fetched root, e.g. Find-SourceFolder
     landing directly on the build folder). Fires ONLY when docs are otherwise empty - structured/scan results never
     disturbed. 3 new asserts (resolver on the nCode build-root fixture finds setup.exe + harvests the one-level-up
     instructions/complexity docs + still excludes OtherPayload). SNIPPETS TAB audited end-to-end: add/edit dialog
     validation, edit-rename = save-then-remove-old (failure-safe), v3->v4 convert toggle, insert-at-caret w/ TextChanged
     state sync, preview, category refresh, shared-file save w/ atomic temp+retries + graceful read-only failure - all
     correct; its closures were covered by the r152 AST audit (clean). ALL TESTS PASSED. Deployed r153 local + share.
   2026-07-03 r154 - "NO PREDECESSOR" BUG (user's live case HBM_nCodeGlyphworks_x64_26.0.0.0: predecessor 24.1.0 exists
     on the live share but Find predecessor said none). ROOT CAUSE: my r148 async rewrite runs Get-PredecessorCandidates /
     Find-SourceFolder inside Invoke-PBAsync BACKGROUND runspaces, which load the ENGINE modules only ($p.engine =
     PBEngineSource = engineFiles; GUI.ps1 is NOT in it) - both functions lived in GUI.ps1, so the background call died
     with CommandNotFound, was caught, and surfaced as "no results". 'Fetch source' had the SAME latent break. FIX: moved
     Get-PredecessorCandidates -> Predecessor.ps1 and Find-SourceFolder -> Source.ps1 (pure engine logic; GUI keeps a
     pointer comment). RULE (memory-worthy): any function called inside Invoke-PBAsync -Work MUST live in an ENGINE module.
     Also: a FAILED background search now shows "search FAILED: <error>" on the label instead of masquerading as
     "No predecessor found" / "not found" (that masking is what hid this bug). LIVE-PROVEN: engine-only session finds
     exactly HBM_nCodeGlyphworks_x64_24.1.0-0001_en-US for the user's package. 7 new asserts (4 async-visible source-file
     checks incl. Find-OutgoingPackage/Read-PredecessorModel, 3 candidate-logic: finds 24.1.0 / never self / not other
     apps). ALL TESTS PASSED. Deployed r154 local + share.
   2026-07-03 r155/r156 - DEMO-CRITICAL: the async predecessor flow (my r148 experiment) kept breaking via closure/
     runspace scope traps (r148 CreatedPath, r154 engine-visibility, r155 nested-closure -> user got NO predecessor
     popup). DECISION: REVERTED BtnPred / BtnFetch / BtnLoadOutgoing to SYNCHRONOUS (plain add_Click, direct
     $script:State + direct function calls - the pre-async pattern that worked). A 2-3s pause on the share walk is
     acceptable; a working popup is not negotiable. Invoke-PBAsync remains defined but unused. Proven: scope_probe.ps1
     showed BOTH captured-local AND accessor-fn are unreachable from a nested .GetNewClosure() in child scope - so sync
     is the only reliable path here.
   2026-07-03 r156 - VERSION/SoftIdent fixes on the live HBM_nCodeGlyphworks 24.1.0 -> 26.0.0.0 reuse (user demo pkg):
     (1) Get-VersionPrefixPairs now pads OLD up to NEW's length -> a 3-part name-version (24.1.0) swaps a 4-part
         DisplayVersion (24.1.0.0 -> 26.0.0.0). Fixes "SoftIdent not replacing version".
     (2) YEAR-FORM swap: vendors like nCode name folders/keys "20YY.M" (nCode 2024.1 64-bit, 2024.1.lnk). When major is
         a 2-digit year suffix, also swap 20<oldMaj>.<oldMin> -> 20<newMaj>.<newMin> (2024.1 -> 2026.0). Anchored +
         requires .minor, so bare years / dates / copyrights (C) 2023 / 10/24/2024 are untouched.
     (3) PRED-OF-PRESSOR bump (Get-PredecessorOfPredecessorVersion + Build.ps1 3b): the predecessor's INLINE previous-
         version checks (nCode "backup registries if 2023.1 installed" + uninstall licensing conditionals) move up ONE
         step 23.1->24.1, so the new pkg's "previous version" = the immediate predecessor, not two-old. Detected from
         VWG\CM detection keys carrying a version < predecessor. Applied to the main body AND the preserved (extracted)
         blocks so no stale 2023.1 survives (checked + unchecked). SoftIdent/main/post = 2026, preinstall pred-of-pred =
         2024, exactly as the user specified. Built script parses clean (checked + unchecked).
     DEFERRED (told user): #5 installer-swap-from-source (prefer a source file matching the predecessor's installer
     name over the user's pick) - needs careful source-resolution integration + tests; not risking it pre-demo.
   2026-07-03 r157 - Tested predecessor reuse on 3 more live pkgs (all build + parse clean): Firefox ESR 140.11->140.12
     (MSI), beA Client Security 4.4.3.598->4.4.4.604 (EXE), Citrix VDA 2402.0.2150.2566->2507.0.1100.167 (v3 EXE, 3
     candidates -> newest, pred-of-pred bump fired on 2402.0.100.629). NEW: ACTIVE SETUP CARRY-FORWARD for reuse
     (Assemble.ps1 Copy-PredecessorActiveSetup + New-Package -PredecessorPath/-PredVersion, wired from the Create button).
     The predecessor's packager-authored *ActiveSetup*.ps1 lives ONLY in its SupportFiles (not vendor source), so a reuse
     build referencing "SupportFiles\<App>_<newver>_ActiveSetup_Install.ps1" would ship a BROKEN ref. Now each such .ps1
     is copied with FILENAME + CONTENT version-swapped (pred->new + the pred-of-pred bump), so it matches the reused
     script's Copy-ADTFile/Set-ADTActiveSetup reference. VERIFIED on the REAL nCode file:
     nCodeGlyphworks_24.1.0_ActiveSetup_Install.ps1 -> _26.0.0_ (content $appname="nCodeGlyphworks_26.0.0", 0 stale refs,
     parses). 7 new asserts. ALL TESTS PASSED. Deployed r157 local + share. (v3-only NOTE: still deferred #5 installer-
     swap-from-source.)
   2026-07-03 r158 - TWO corrections from user testing:
     (1) PRED-OF-PRED bump is now CHECKBOX-GATED (user clarified): it must fire ONLY when uninstall-previous is
         UNCHECKED. CHECKED = STANDARD behaviour restored (keep the predecessor's own block verbatim + add our generated
         "remove predecessor" block; the predecessor's 2023.1 previous-version refs stay pinned - two stacked blocks =
         multi-version coverage). UNCHECKED = no generated block, so bump the kept logic up one step (23.1 -> 24.1) so it
         targets the immediate predecessor. The CURRENT-version swap (24->26, incl. 4-part DisplayVersion + year-form) is
         UNCHANGED and ALWAYS runs - it is independent of the checkbox. Detection moved to run AFTER block injection (on
         the complete $out) so it finds the ref whether inline or in an extracted-then-reinjected block. Also removed the
         pred-of-pred bump from the Active Setup carry-forward (main version swap only; keeps it checkbox-independent,
         Active Setup stubs ~never carry a two-versions-back ref - acceptable exception).
     (2) PREDECESSOR PICKER now ALWAYS shows (removed the cands.Count==1 silent auto-pick) - the packager SEES which
         predecessor is used and can choose a DIFFERENT one even when only one candidate exists (default pre-selected).
     VERIFIED live (nCode): CHECKED keeps 2023.1, UNCHECKED bumps to 2024.1, current version -> 2026.0 in both; both
     parse. New/updated asserts (gated CHECKED vs UNCHECKED, picker-always-shows). ALL TESTS PASSED. Deployed r158.
   2026-07-03 FINAL PRE-DEMO FUNCTIONAL SWEEP (r158, no code change needed): built a FUNCTIONAL harness (scratchpad
     functional.ps1) that EXERCISES each capability end-to-end and checks REAL output, not just parse. 35/35 GREEN:
     name parse (valid+invalid); source resolution (structured/flat-docs/version-folder); FRESH MSI package built to disk
     WITH a real MST (WindowsInstaller COM on C:\Windows\Installer\f3762.msi); FRESH EXE package; nCode REUSE full build
     incl. ActiveSetup .ps1 carried+renamed+version-swapped, script references match; Firefox/beA/Citrix reuse build+
     parse+version; LOOSE zip payload; machine snapshot capture + leftover check (live Test-Path, folder swallow, post-
     uninstall tag) + report save/load; standalone MST; icon ico/png pairing; SNIPPETS add/edit/delete round-trip on a
     shared file; SCCM field fetch v3+v4; remote-screenshot agent gen+parse; self-stage UNC detection.
     USER FINDINGS this round, both investigated + explained (NOT bugs): (a) "Mozilla SoftIdent product code not swapped"
     - Firefox has NO ProductCode anywhere: installs the MSI BY FILE, UNINSTALLS via helper.exe /S, SoftIdent is
       name+version based ("Mozilla Firefox 140.11.0 ESR"). The VERSION swapped correctly 140.11->140.12; there is simply
       no GUID to swap. Correct behaviour. (b) Copy-Item "PSAppDeployToolkit.Extensions.psd1 not found" during New-Package
       was a TEST-ONLY MAX_PATH(260) artifact from the long scratchpad output path (262 chars); real packages go to
       C:\temp\<pkg> (~150 chars) and copy fine - confirmed the template file exists.
   2026-07-03 r159 - FIVE user asks (all built + tested, deployed local+share):
     (1) SNIPPET OWNER GATING: Add/Edit/Delete snippet buttons hidden for non-owners. Core.ps1 $script:SnippetOwners=@('AW140')
         (baked into the ENCRYPTED pak so users can't edit it, unlike settings.json) + Test-IsSnippetOwner (matches $env:USERNAME);
         GUI hides the 3 write buttons when not owner. To add an owner: edit the list + repack.
     (2) LOAD/SAVE SCRIPT in the editor: BtnLoadScript (OpenFileDialog -> editor) + BtnSaveScript (writes back to the loaded
         path, UTF-8 BOM; parse-warns first). Save is IsEnabled=False until a file is Loaded (so we only overwrite the file the
         user explicitly opened); Rebuild-from-inputs clears loaded mode. Lets the packager tweak a tested .ps1 without opening it externally.
     (3) LOG-PATH FORMAT modernisation (Convert-LogPathFormat, ~HALF of live v3 packages use it): old flat
         "$configToolKitLogDir\$setuplogName" -> new per-app v4 log dir. Drops [string]$setuplogName* decls; rewrites the simple
         "$configToolKitLogDir\$setuplogName" -> $LogPathMain; nested "$configToolKitLogDir\$logfolder\$setuplogName" keeps the
         subfolder and gets a real v4 filename ($($adtSession.AppName)_$($adtSession.AppVersion)_$($adtSession.DeploymentType).log,
         NOT a doubled dir); injects "$adtConfig=Get-ADTConfig / New-ADTFolder / $LogPathMain=..." at the top of each section that
         logs. Verified on live CarlZeiss (simple, 1 block) + GIMP (nested, 5 blocks) - both parse clean, no old vars left.
     (4) CASE-INSENSITIVE cmdlet rename fix (PSADT_V3toV4_Mappings.ps1): the func-rename Replace was case-SENSITIVE, so
         'New-folder'/'copy-file' were detected but left unconverted (seen live in GIMP). Added (?i). Corpus reuse builds still green.
     (5) LOCAL TEST CONSOLES: BtnAdminCmd (Start-Process cmd -Verb RunAs at the package Content dir) + BtnSystemCmd (PsExec
         -accepteula -s -i cmd via RunAs; Find-PsExec looks next to the exe / PsExec\ / Lib\ / Tools\). For testing
         install/uninstall/repair at admin AND SYSTEM level. User keeps PsExec.exe alongside PackageBuilder.
     PREDECESSOR "only one" - INVESTIGATED, NOT a bug: Get-PredecessorCandidates returns ALL live predecessors (Firefox/beA=1,
     Citrix=3, nCode=1) - most apps just have one older version live on the share. Picker already shows all (r158). All tests +
     demo-proof green on r159.
   2026-07-03 r160 - Screenshot UI reorg + VWG_app* mapping:
     (1) SCREENSHOT REORG (user): LOCAL "Screenshot shortcuts (this machine)" (BtnTsShots) moved from Troubleshoot -> the
         Review & Create tab, next to Admin/SYSTEM CMD (test the package you just built, right after installing it locally).
         Its handler now takes the name from the built package (State.Parsed.FullName / CreatedPath leaf) + reports on
         LblCreateResult. REMOTE screenshots (BtnRemoteShots) moved from Testing -> Troubleshoot; handler now reads the
         Troubleshoot Machine name (TxtTsMachine, comma/space-sep for several) + Application name (TxtTsAppName). Testing tab
         keeps only collection mgmt + Intune (no screenshot feature).
     (2) v3->v4 $VWG_app* aliases (user): $VWG_appFullName -> $AppFullName (the v4 template's concatenated variable);
         $VWG_appName/Vendor/Version/Arch/Lang/Revision -> $adtSession.App* (canonical, same as plain $appName). Added to the
         V3ToV4Variables table so the context-aware renamer handles string ($(...)) vs standalone. Fixes $VWG_appFullName
         previously surviving un-converted (e.g. Set-ActiveSetup -Key $VWG_appFullName in the nCode build). Verified live +
         6 new asserts. ALL TESTS PASSED. Deployed r160.
   2026-07-03 r161 - Local-test overhaul on Review & Create (user):
     (1) LOADED-.ps1 IS A TEST TARGET: Get-CreatedContentDir now prefers $script:LoadedScriptPath's folder (that IS a
         package Content dir), so after Load .ps1 + Save the Admin/SYSTEM buttons work - fixes "no created package" when
         a .ps1 was loaded. Falls back to State.CreatedPath\Content. BtnTsShots derives the app name from the loaded
         package folder too.
     (2) INSTALL / UNINSTALL / REPAIR buttons under Admin AND SYSTEM (replaces the two bare CMD-only buttons; CMD kept):
         Invoke-LocalDeploy finds the entry exe (Invoke-AppDeployToolkit.exe v4 / Deploy-Application.exe v3) and runs the
         SAME positional command Integration uses - "<exe> install|uninstall|repair" - Admin via Start-Process -Verb RunAs
         (working dir = Content), SYSTEM via PsExec "-accepteula -s -i -w <dir> <exe> <type>". 6 new buttons
         (BtnAdmin/Sys Install/Uninstall/Repair) + the 2 CMD buttons. New asserts; ALL TESTS PASSED. Deployed r161.
   2026-07-03 r162 - three fixes:
     (1) v3->v4 -Exact/-WildCard/-RegEx SWITCHES -> v4 -NameMatch VALUE ('Exact'/'WildCard'/'Regex') on Get-ADTApplication +
         Uninstall-ADTApplication (v4 has no -Exact switch -> "parameter cannot be found"). ALSO broadened the param-rename
         lookahead from (?=\s|$) to (?=[\s\)\]\};,]|$) so a switch at the end of a call ("...-Exact)") is caught.
     (2) EMPTY editor no longer flags "SoftIdent empty" - Get-CombinedReview returns @() when ScriptText is blank.
     (3) SELF-STAGE now mirrors PsExec*.exe + a Tools\ / PsExec\ folder from the share to the local copy (extra tools were
         being left on the share); Find-PsExec also falls back to the share source + RepositoryPath, so PsExec is found
         wherever it was dropped. ALL TESTS PASSED. Deployed r162.
   2026-07-03 r163 - SNAPSHOT TREE VIEW (SysTracer-style) built + deployed. User approved the mockup; chose NO filter bar
     (app-relevant default + collapsed folders + an "Ignored" node). Added a "Tree view" button to the snapshot dialog's
     toolbar -> Show-SnapshotTreeView opens a WPF TreeView: Files & Registry as the real system HIERARCHY (built from the
     diff paths); the rest (Shortcuts/Services/Tasks/Drivers/Certs/RunKeys/Printers/Programs/Env) as colour-coded lists;
     an "Ignored - OS/vendor noise (N)" node at the bottom (capped sample). COLOUR RULE (one, everywhere): green=added,
     amber=modified, red=removed; scaffolding folders/keys stay NEUTRAL and carry a "+added ~modified -removed" count badge
     (honest - we track files/keys, not folder creation); only real changed LEAVES are coloured. A changed REGISTRY key
     expands to its LIVE values (name/type/data; new-key values are green). Pure tree logic (Add-SnapshotTreePath /
     Get-SnapshotTreeCounts) moved to Snapshot.ps1 + unit-tested; the WPF builders verified via an STA smoke test
     (tree_smoke.ps1 - all build w/o exceptions, live values read). Additive (separate button/window) so it can't break the
     existing text report/Apply. ALL TESTS PASSED. Deployed r163. NOTE (Phase 2, not done): per-value OLD->NEW for MODIFIED
     registry keys needs the snapshot to store actual before-values (currently only a hash) - today a modified key shows
     its CURRENT values. Suggest to user for after the demo.
   2026-07-04 r164 - three small changes + snapshot-view overhaul:
     (1) Add installer dialog defaults to C:\temp (fallback Incoming repo).
     (2) SECOND live predecessor repo: Get-PredecessorRoots searches BOTH \\mbddfsovpc01...\SWDLive-Gate\CMLib_LIVE\Apps
         AND \\MNDEMUCFS120.mn-man.biz\SWDistribution-Gate\CMLib_LIVE\Apps (+ optional settings 'PredecessorPaths' array),
         deduped (primary wins). Wired into Get-PredecessorCandidates, Test-LiveShareDuplicate, and the predecessor auto-hint.
     (3) SNAPSHOT TREE VIEW rebuilt as CUSTOM nested rows (the raw WPF TreeView looked wrong): chevron + coloured left-accent
         + badge + collapsible children; single $this.Tag toggle handler (no per-node closures); hover; scaffolding neutral
         w/ +add ~mod -del count badges; only changed LEAVES coloured. NEW ChangeSet model (Snapshot.ps1
         New-SnapshotChangeSet) captures file size/date + registry VALUES at build time, so the report is SELF-CONTAINED.
         Files show size·date; registry keys expand to captured values (name [type] = data). COPY (text), EXPORT
         (HTML colour-coded / TXT / JSON), IMPORT (JSON -> re-view the tree, no live machine) via
         Format-SnapshotChangeSetText/Html + ConvertTo-PBHashtable. Pure engine funcs unit-tested (14 asserts); WPF builders
         STA-smoke-tested. Still additive (Tree view button); plain text report + Apply flow untouched. ALL TESTS PASSED.
         Deployed r164. (Per-value old->new for MODIFIED reg keys still needs storing before-values - deferred.)
   2026-07-04 r165 - snapshot report clarity + registry old->new + screenshots:
     (1) REGISTRY OLD->NEW: Get-RegMap now stores the ACTUAL values (name<SOH>type<SOH>value<STX>..., capped 60 vals /
         400 chars / 6KB per key) instead of a hash; Get-SnapshotRawDiff attaches a per-VALUE diff (ConvertFrom-RegValueString
         + Compare-RegValueStrings) so a MODIFIED key shows added/removed/CHANGED with old->new. Tree renders changed
         values amber (old struck red -> new green), added green, removed red.
     (2) TREE-EMPTY-ON-LOAD FIXED: Analyze now builds a self-contained ChangeSet (New-SnapshotChangeSet: files+size/date,
         registry+values, lists, env, noise) stored on ctx.ChangeSet AND saved with the report; loaded reports restore it
         (ConvertTo-PBHashtable) so the Tree view works on a LOADED report, not just a fresh analyze.
     (3) Tree footer: removed JSON Import (report save/load already exists); Export now offers HTML / TXT / .REG
         (Format-SnapshotChangeSetReg -> a real Windows .reg file: added/changed keys w/ values, [-KEY] for deleted,
         "name"=- for removed values, string+dword encoded). Copy (report text) kept.
     (4) SCREENSHOTS: Create-tab button already log-time-based (Get-AppInstallWindow + -SinceTime; "install first" if no
         log/snapshot) - confirmed, one button covers created + loaded pkg. Troubleshoot "Remote screenshots" now runs
         LOCALLY (Invoke-ShortcutValidation) when the only target is THIS machine (COMPUTERNAME/./localhost). Admin/SYSTEM
         install buttons + timestamped screenshot folders support the two-machine admin-vs-system compare workflow.
     16 new asserts (regval diff, .reg export, changeset). ALL TESTS PASSED. Deployed r165.
   2026-07-04 r166 - snapshot window UX + installer-independent + tabs polish (LOCAL-ONLY; user pushes to repo later):
     (1) LOADED-REPORT TREE FIXED (real root cause): the auto-save in BtnSnapshot built its OWN Data hashtable and
         OMITTED ChangeSet, so EVERY loaded report (not just old ones) came up with an empty Tree. Now saves
         ChangeSet=$res.ChangeSet. Plus New-SnapshotChangeSetFromState (Snapshot.ps1) rebuilds a STRUCTURAL tree (files
         /reg keys parsed from the LeftoverCandidates removal-commands + Shortcuts) for pre-r166 reports that never
         stored a ChangeSet; Load + same-session re-open both use it. old->new reg values verified through save/load.
     (2) SNAPSHOT INSTALLER-INDEPENDENT: Show-SnapshotDialog -ExePath is now optional; BtnSnapshot opens it in MANUAL
         mode with no source selected. 'Run installer' disables when there's nothing to auto-run.
     (3) ADMIN/SYSTEM in the snapshot: 'Step 2 - install as: Admin|SYSTEM' selector + 'Open CMD (Admin)' / 'Open CMD
         (SYSTEM, PsExec -s -i)' consoles so the user installs by hand at either level (works with no installer). 'Run
         installer' honors the mode (SYSTEM via PsExec -s -i -d). 'Launch + screenshot' -> Screenshots\<app>\snapshot\
         <admin|system> so the two install contexts compare side by side. Reuses Find-PsExec (no new PsExec logic).
     (4) SNAPSHOT BOTTOM BAR regrouped from one 9-button strip into labeled rows: 'Report:' (Save / Load / View-ignored)
         and 'Actions:' (Launch+screenshot / Exclude / Open certificate / DriverStore), then commit (Apply / Cancel).
         Nothing hidden, nothing duplicated.
     (5) TABS polish (conservative, no structural re-layout - go-live safety): each Step-4 tab gets ONE accented PRIMARY
         action (Create in SCCM/Intune, Add to collection, Move to TEST) for junior-clear hierarchy; verbose helper
         paragraphs trimmed; muted helper text standardized to #888. Main-window XAML re-validated offscreen.
     +5 asserts (old-report rebuild, save-carries-ChangeSet). Test-Build green, tree_smoke OK, DEMO-PROOF r166 PASSED.
     Deployed to LOCAL ref only (C:\Users\AW140\Downloads\PackageBuilder). SHARE/REPO deferred per user.
   2026-07-04 r167 - noise filter overhaul + inline tree + snapshot/tab polish (LOCAL-ONLY):
     (1) NOISE FILTER (biggest win): a real avasign report showed 2375/2485 "files" were pure churn. ROOT: a MODIFIED
         (not newly-created) FILE outside the app is background churn - installers ADD their files. Get-SnapshotRawDiff
         now routes modified-non-app FILES to noise (kept viewable in NoiseItems). Regex also gains \!!!!!\d+ reparse
         farms (Cortex/Traps), catroot2, wbem\Repository, appcompat, AppData\Local\Packages (UWP churn); BgVendors gains
         cyvera/traps/paloalto. Report + tree now show only the real app footprint (+ADDED prerequisites). 6 asserts.
     (2) INLINE CHANGE TREE replaces the plain-text report: New-SnapTreeBody (extracted, shared with the standalone
         window) hosted in the dialog; category BUTTONS (All/Files/Registry/Shortcuts/Services/...) via Get-SnapTreeCategories
         drive it in place. REMOVED: plain-text pane, search box, category dropdown (was dead), 'Tree view' + 'Clear'
         buttons. $txtReport kept as an off-screen buffer so Save/Copy/leftover-append still work. Exclusions moved into
         their own collapsible Expander (auto-opens when there are any). Refresh state shared via $ctx (closure-safe).
     (3) SNAPSHOT CONSOLES: Admin/SYSTEM CMD now open at the DEFAULT dir (System32), not the installer folder. All
         'PsExec not found' MODAL warnings -> quiet status lines (PsExec is the owner's to stage; not a user warning).
     (4) TESTING TAB: machines ListBox shrunk (300x112) with the collection action buttons stacked BESIDE it (was a full
         -width box + a separate button row) - compact + tidy.
     (5) TOOLTIPS/HELP: trimmed the long always-visible helper paragraphs + the longest button tooltips (Integration/
         Testing/Troubleshoot/Dev->Test) to short one-liners; details stay in per-button tooltips.
     Parse OK, main XAML re-validated offscreen, inline-tree STA smoke OK, Test-Build green, DEMO-PROOF r167 PASSED.
     Deployed to LOCAL ref only. SHARE/REPO deferred per user.
   2026-07-04 r168 - analyze in background + category buttons fixed + polish (LOCAL-ONLY):
     (1) ANALYZE NO LONGER FREEZES: the whole heavy diff (compare + raw diffs + report + change set + shortcuts +
         leftovers + cleanups) was running in the Analyze OnDone ON THE UI THREAD. New Start-SnapshotAnalyzeJob runs it
         all in a background runspace (every function is engine-visible); the callback only assigns + renders (fast).
     (2) CATEGORY BUTTONS FIXED: the inline tree's category buttons threw "object not found" - caused by a stored
         self-invoking $ctx.RefreshTree CLOSURE (the exact ps-wpf-closure-scope trap). Replaced with a SCRIPT FUNCTION
         Update-SnapInlineTree -Ctx $ctx that all callers (buttons, Analyze, Load, re-open) invoke. STA-tested by
         actually RaiseEvent-ing a category button's Click -> switches category, no error.
     (3) 'IGNORED' dropped from the tree categories (the "View ignored OS junk (CMTrace)" button already covers it).
         Confirmed Autostart (Run keys) + Scheduled tasks + Services + Drivers + Certificates ARE separate categories -
         they only appear when the app actually created them (content-gated), which is why avasign showed only a few.
     (4) SPACE: snapshot dialog hint shortened to one line, category buttons made compact, outer margin trimmed.
     (5) CMD consoles already open at System32 (r167); confirmed.
     Parse OK, XAML OK, category-button STA smoke OK, Test-Build green, DEMO-PROOF r168 PASSED (248 cmds, 0 unresolved).
     Deployed to LOCAL ref only.
   2026-07-04 r169 - tree design overhaul + leftover-check visibility (LOCAL-ONLY):
     (1) TREE CONTRAST BUG: reg-value NAME + list-leaf KEY Runs had no Foreground -> WPF default BLACK -> invisible on the
         #0C0C0C row. Set explicit light (#E7E9ED). (This was "some registry names I can't see".)
     (2) TREE REDESIGN (master-detail): categories moved to a LEFT sidebar (full-width buttons WITH per-category counts,
         Get-SnapCategoryCount) + the selected category's tree on the RIGHT - uses horizontal space, no top button-wrap row.
         ROOT nodes (drive C:\, hives HKLM/HKCU) now render with a distinct raised teal bar + SemiBold teal text
         (New-SnapRowBorder -Root) so system roots stand out from plain folders. Row padding/indent tightened (less waste).
     (3) LEFTOVER CHECK now SHOWS its result: it used to write only to the off-screen report + the collapsed exclusions
         panel, so nothing appeared. Now it renders the leftovers as amber rows in the tree pane (with a 'Change tree' button
         to go back) AND auto-expands the Exclusions section. Clean-uninstall shows a green "nothing left behind" message.
     (4) \Recent\ (Windows MRU) is never a leftover/cleanup candidate now (Get-UninstallLeftovers filters it). +2 asserts.
     (5) Create tab / snapshot dialog spacing tightened.
     Parse OK, XAML OK, tree-redesign STA smoke OK, Test-Build green, DEMO-PROOF r169 PASSED (249 cmds, 0 unresolved).
     Deployed to LOCAL ref only. (Open item: user to point at the exact "info page" that still feels spacious.)
   2026-07-04 r170 - tree usability (copy/exclude/perf) + capture accuracy + leftover clarity (LOCAL-ONLY):
     (1) TREE PERF: category + 'Change tree' clicks felt slow/unresponsive - Update-SnapInlineTree rebuilt EVERYTHING each
         click. Split into Show-SnapCategory (swaps only the right pane, CACHES per-category panels in $ctx.TreePanels ->
         instant re-clicks) + build-buttons-once. Data-changing callers (Analyze/Load) reset the cache.
     (2) TREE COPY + EXCLUDE (right-click menu): every file/registry/shortcut row now has a ContextMenu - 'Copy path'
         (exact path/key to clipboard) + 'Exclude - remove POST-INSTALL' / 'POST-UNINSTALL' (Add-SnapExclusion builds the
         Remove-ADT* command + a ticked checkbox, de-dupes). Solves can't-copy, can't-exclude-easily, and post-uninstall
         exclude. Manual excludes are tagged 'manual-exclude' and are NOT deferred by Apply (only leftover-check items are).
     (3) SHORTCUT TARGET shown inline (-> target) on the row; run-key command too (New-SnapListLeafUI -Detail).
     (4) CAPTURE ACCURACY (VC++ 'quality miss'): an ADDED file is real footprint even under a Microsoft/vendor path, so it
         is no longer vendor-filtered - a bundled prerequisite (VC++/.NET/WebView2/UCRT via Test-IsPrereqFile) now SHOWS.
         Narrow allowlist so a browser/AV auto-update (msedge.dll) stays noise. New ARP entries already show (Programs cat).
     (5) LEFTOVER clarity: header now reports "uninstaller REMOVED ~X of N install items; Y LEFT BEHIND"; heading no longer
         mislabels post-uninstall cleanup as POST-INSTALLATION (Exclusions & cleanup, each item tagged). Independent (no-
         installer) snapshot still auto-writes uninstall/detection/exclusions into the package (Apply is source-agnostic).
     (6) Step-1 (source) tab margin 22->16 tightened.
     +4 asserts (prereq kept / cache / Recent / leftover). Test-Build green, tree STA smokes OK, DEMO-PROOF r170 PASSED
     (253 cmds, 0 unresolved). Deployed to LOCAL ref only.
   2026-07-04 r171 - reliability: replaced-component capture + real after-uninstall diff + timing override (LOCAL-ONLY):
     (1) REPLACED-COMPONENT CAPTURE (Get-SnapshotRawDiff): a component being replaced (VC++ etc.) removes old / adds new /
         bumps ARP - now shown even without an app name. ADDED registry KEYS are kept under vendor paths (a Chrome/Edge
         policy key, a new component key); ALL REMOVED files/keys are kept (only OS/MRU churn hides a removal); a MODIFIED
         ARP (\Uninstall\) key is kept and shows DisplayVersion old->new. Non-ARP modified vendor values stay noise.
     (2) AFTER-UNINSTALL = REAL DIFF (New-UninstallChangeSet): the leftover check now renders a proper before(install)/after
         diff with the SAME tree as the install - red = REMOVED by uninstaller, amber = LEFT BEHIND (tick to clean), green =
         ADDED (new files under the app dirs). Built live from the install candidates + Test-Path, so it works same-session
         AND on a loaded report. Left-behind items still become ticked post-uninstall cleanup rows.
     (3) POST-INSTALL/POST-UNINSTALL TIMING is now USER-CHANGEABLE: every exclusion/cleanup row (Add-ExclusionRow) has a
         timing combo; changing it rewrites the command tag on that entry (Apply uses the new timing). All 5 exclusion
         sources (analyze / leftover / right-click / load / re-open) route through it. Manual excludes are never deferred.
     +7 asserts (reg added/ARP/vendor-value, uninstall diff present/removed/added). Test-Build green, tree STA smokes OK,
     DEMO-PROOF r171 PASSED (255 cmds, 0 unresolved). Deployed to LOCAL ref only.
   2026-07-04 r172/r173 - FINALIZE this version: discoverability + richer capture + prereqs-in-uninstall-diff (LOCAL-ONLY):
     r172: tree header now says "right-click a row to Copy path or Exclude" (the menu was undiscoverable). Deployed.
     r173: (1) AFTER-UNINSTALL diff now covers the FULL install footprint incl. PREREQUISITES (Get-LeftoverCandidates adds
         AllFiles/AllReg = all New paths; New-UninstallChangeSet diffs those) - so VC++/.NET show removed/left too. The
         actionable CLEANUP stays app-only (Files/Dirs/Reg/Lnk) - never offers to remove a shared runtime.
         (2) RICHER CAPTURE (Get-MachineSnapshot): Services += State/Account/Type/Description; Scheduled tasks += Action
         (Execute+Args)/Triggers/Author/State; Certificates += Thumbprint/Issuer/Expires/FriendlyName; Shortcuts now
         RESOLVE Target+Arguments (fixes the r170 'target' that had nothing to show); Drivers += Inf/Added-date. ChangeSet
         label falls back to FriendlyName/Subject (certs) and the inline row detail prefers Action/Path/Subject/Inf.
     +3 asserts (prereq-in-uninstall-diff, cert-Subject-label). Enrichment snippets verified live. Test-Build green,
     DEMO-PROOF r173 PASSED (255 cmds, 0 unresolved). Deployed to LOCAL ref. THIS VERSION IS FINALIZED (r173).
     KNOWN TRADE-OFF (by design, for scan speed): HKCR\Classes is pruned -> file associations + COM/CLSID registrations
     are NOT captured; firewall rules also not captured. Add later if a real package needs them.
   2026-07-04 r174 - SMART MSI Run-key removal (component-aware) + object-not-found sweep (LOCAL-ONLY):
     AUDIT (user: "check object-not-found errors everywhere, this happened before"): AST scan of ALL 11 modules for the
     ps-wpf-closure-scope trap ($script:State/$script:Win inside a .GetNewClosure()) = 0 found / CLEAN. All-categories tree
     render (enriched services/tasks/certs/drivers/shortcuts) = no property errors. StrictMode is NOT on in the tool's own
     code (only in the PSADT template), so unguarded null-property reads return $null (don't throw). demo_proof 255 cmds 0
     unresolved. Confirmed service 'what it runs' (image path) shows inline.
     SMART RUN-KEY REMOVAL (user's design): when removing a Run key from an MSI, look at ITS component -
       - component DEDICATED to the Run key (no other registry, no files) -> delete the Registry row in the MST (as before).
       - component SHARED with other files/registry -> KEEP it in the MSI (deleting it would drop the other resources / orphan
         the KeyPath, and MSI RemoveRegistry can't suppress a value the same MSI writes) -> remove just the VALUE via PSADT
         Remove-ADTRegistryKey in POST-INSTALLATION, auto-injected into the package ps1.
       Impl: Resolve-RunKeyPlan (pure, unit-tested) + Get-MsiRunKeyPlan (reads Registry+File tables) in MstBuilder; Build-Mst
       returns the deferred keys; New-PackageMst -DeferredRunKeys sink; Assemble collects across MSIs + Add-PsadtRunKeyRemovals
       (Build.ps1) injects via Append-ToSection into POST-INSTALLATION. This also explains the user's MSI-2715 (File-table
       break from deleting a component). +8 asserts (plan 32/64/dedicated/shared/deferred + ps1 injection). Test-Build green,
       DEMO-PROOF r174 PASSED. Deployed LOCAL ref.
   2026-07-04 r175/r176 - team-reported reuse fixes (LOCAL-ONLY):
     r175 SOFTIDENT DISPLAYVERSION (team: predecessor reuse left detection at old ver): on reuse WITHOUT a new-version
       snapshot, the SoftIdent's embedded [DisplayVersion=...] is now set to the NEW version DETERMINISTICALLY. The generic
       version swap missed it because the predecessor's REAL DisplayVersion (Inno 4-part 3.5.17129.17210) differs from the
       predecessor PACKAGE version used as the swap token. Only-when-predecessor-carried (snapshot detection wins if present);
       a SoftIdent w/o DisplayVersion untouched. Verified in the live nCode reuse (logs the bump; demo_proof shows ->26.0.0.0).
     r176 LOG FILE SYNTAX (team: "$LogPathMain only makes a folder, no setup log file"): Convert-LogPathFormat now emits a
       real .log FILE. $LogPathMain = the log FOLDER (New-ADTFolder); NEW $LogFileMain = "$LogPathMain\<vendor_app_ver_arch_
       lang_rev>_<PHASE>.log" where PHASE is the SECTION (PreInstall/Install/PostInstall/Uninstall/Repair...). Rule 2a (old
       flat "$configToolKitLogDir\$setuplogName" file path) -> $LogFileMain (was $LogPathMain, a DIR -> only a folder got made
       = the bug); 2b bare dir -> $LogPathMain; 2c bare filename literal (nested paths). This also DIFFERENTIATES the
       predecessor-uninstall log (pre-install phase) from the main-install log automatically. +6 asserts (existing 2
       updated). Test-Build green, DEMO-PROOF r176 PASSED (255 cmds).
   2026-07-06 r178 - team-reported Get-RegistryKey v3->v4 param + DEPLOYED TO SHARE (team testing):
     Get-RegistryKey mapping renamed the FUNCTION but not the -Value param. v3 Get-RegistryKey -Value = the value NAME;
     v4 Get-ADTRegistryKey uses -Name and has NO -Value (a leftover -Value throws "parameter cannot be found"). FIX:
     PSADT_V3toV4_Mappings.ps1 Get-RegistryKey -> Params @{ '-Value'='-Name' }. The param rename is SCOPED to
     Get-ADTRegistryKey call lines (via $isCallLine), so Set-ADTRegistryKey's -Value (the DATA, correct in both v3/v4) is
     UNTOUCHED. Verified in template (Get-ADTRegistryKey has -Name/-LiteralPath[alias Key], no -Value). +3 asserts
     (Get -Value->-Name, no leftover -Value, Set -Value untouched). Test-Build green, DEMO-PROOF r178 PASSED.
     *** DEPLOYED TO THE TEAM SHARE (user authorized - team is testing): pak + snippets.json copied to
     \\mndemucfsm01\SEC-EQS-Lib-Gate\EQS_SEC\EQS\Script Repository\VWITS Team\Balaji\PackageBuilder\ (byte-verified;
     share pak 398,528/7-4 -> 402,624 r178; users self-stage the newer pak on next launch). NOTE: share snippets.json was
     24,408/6-24 vs dev 34,859 - overwrote with dev (superset by size); flagged to user to confirm no share-only snippets lost.
   2026-07-06 r179 - log-block de-dup + ActiveSetup ExecutionPolicy on conversion (LOCAL-staged; SHARE push held for consent):
     (a) Convert-LogPathFormat: Pre/Main/Post of one deployment run share the SAME function scope (Install/Uninstall/
         Repair-ADTDeployment), so the scaffold ($adtConfig=Get-ADTConfig / $LogPathMain / New-ADTFolder) is now emitted
         ONCE per Install/Uninstall/Repair GROUP (first logging section); later sections in the group only re-set the
         phase-specific $LogFileMain (reusing $LogPathMain). Uninstall/Repair are separate functions -> own scaffold. Was
         redefining the whole block per section (user flagged the redundancy). +5 asserts (scaffold 1x/group, New-ADTFolder
         1x, LogFileMain 2x, PreInstall phase, main-install reuses LogPathMain w/ no 2nd scaffold).
     (b) PSADT_V3toV4_Mappings LAYER 1d: a converted predecessor Set-ADTActiveSetup line with a .ps1 stub gets
         -ExecutionPolicy 'Bypass' appended (v3 Set-ActiveSetup wrapper has NO -ExecutionPolicy -> v4 falls back to
         (Get-ExecutionPolicy), blocking the stub on locked-down machines). Scoped: .ps1 only, skips .exe/purge/already-set/
         backtick-continued. Fresh generator already emitted it. +functional test (ps1 gets 1x, exe none, preset no dup).
     ActiveSetup CreateProcessWithToken "handle invalid" (nCode, user report): DIAGNOSED, no tool change (user declined
       -NoExecuteForCurrentUser). Root cause = elevated-INTERACTIVE test hits the non-SYSTEM else-branch (psm1:15529)
       Start-ADTProcess -UseUnelevatedToken; the session has no usable un-elevated linked token (built-in Admin / UAC off /
       RDP-service) -> 0x80004005. SCCM/SYSTEM takes the working branch (15485) or cleanly skips (Session 0). Test as SYSTEM
       (PsExec -s) or normal-admin+UAC. Bundled PSADT is 4.1.8 (user was on 4.1.6); same 4.1-line path -> likely same in 4.1.6.
     Test-Build ALL PASS; DEMO-PROOF r179 PASS (pak engine visible, GUI 0/255 unresolved, live nCode reuse, exe r179).
     Local dev + Downloads\PackageBuilder ref updated to r179 (403,536 bytes). SHARE NOT pushed (classifier held it - awaiting
     explicit user OK for the team share).
   2026-07-06 r180 - MST cleanup RELIABILITY OVERHAUL + autostart/stray toggles + predecessor replicate (LOCAL; SHARE held):
     ROOT CAUSE (found via user's DassaultSystems_3DExperience/3DEXPERIENCELauncher.msi): the MSI OpenView/Fetch/StringData
     reader is NON-DETERMINISTIC (same SELECT gave 10 rows one run, 12 w/ 2 blank another; WHERE=3 vs client-read=1). This
     mis-counted component footprints -> wrong run-key decisions. 3DExperience C_RegSystray = DEDICATED (1 reg=the run key,
     0 files, Attr=260, KeyPath=the run row); old logic deleted the ROW and left the component => DANGLING KEYPATH (real
     install/repair risk - user's "chance of MST error" concern was RIGHT).
     FIX (MstBuilder.ps1, all proven live on 3DExperience, integrity CLEAN):
      - Export-MsiTable: read tables via Database.Export->IDT (deterministic). Remove-MsiRowsByPk: delete by exact PK.
      - Resolve-MsiCleanupPlan (PURE, unit-tested) + Get-MsiCleanupPlan (IO): KEYPATH-AWARE run keys - dedicated -> remove
        WHOLE component (Registry+Shortcut+File+FeatureComponents+Component); shared+not-keypath -> delete row;
        shared+keypath -> reassign KeyPath to a file/other reg then delete, else PSADT (DeferPsadt).
      - Shortcuts categorised via Directory-tree walk (Resolve-DirCategory): Desktop / Startup(autostart, catches WiX
        WIX_DIR_COMMON_ALTSTARTUP) / SendTo / Stray / Other(keep). Shortcuts are never keypaths -> always safe to delete.
      - Test-MstIntegrity: apply finished MST to a copy, refuse to ship if any dangling keypath / orphaned ref. Build-Mst
        throws; New-PackageMst re-throws integrity failures (never ship broken silently).
      - Read-MstSettings + ApplyExtras rebuilt on Export (predecessor MST replication is now reliable + categorised).
     GUI: 4 toggles (Keep desktop / Keep Startup-autostart / Keep SendTo-stray / Keep Run key) global + per-MSI (MsiFlags),
       threaded New-Package->New-PackageMst->Build-Mst. Match-predecessor dialog shows all 4 (defaulted from predecessor),
       user override wins. USER-WINS is structural: run/shortcut removals ONLY via toggles; Read-MstSettings excludes them
       from the auto-replicate OtherItems -> a user "keep" is never overridden by the predecessor.
     Fixed 3 PS5.1 traps: @() on List[object] (use .Count/.ToArray), ApplyTransform emits $null into pipeline ([void] it),
       return ,$list returns the List not elements (return $list.ToArray()). Memory: [[msi-cleanup-keypath-reader]].
     Test-Build ALL PASS (+14 new: 11 cleanup planner incl. user-wins, 3 real-MSI 3DX incl. integrity CLEAN); DEMO-PROOF
     r180 PASS (pak engine, GUI 0/255 unresolved, live nCode reuse, exe r180). Local dev + Downloads\PackageBuilder ref on
     r180 (409,424 bytes). SHARE NOT pushed - awaiting explicit user OK.
   2026-07-07 AUDI BRAND VARIANT - FOUNDATION (round 1 of ~3; see memory audi-brand-variant.md for the full analysis):
     Scope: portable brand copy for the AUDI GroupWrapper team - predecessor reuse + fresh creation w/ source/docs/icons/
     MSI-MST/KB, NO SCCM/Intune. User rules: prefix selection (INA=Audi, VWG=Group package, G1V=VW); AES number
     (AES-1-... from the Incoming request folder) replaces RITM -> $VWG_OrderNumber; predecessor STRICTLY from the
     request's Predecessor\ folder (no live access; Outgoing fallback ok; never copied to output); package-name matching
     must work with or without the AES prefix; source fetching manual for now.
     DONE THIS ROUND (Test-Build ALL PASS, zero MTB regression):
      (a) Brand profile plumbing: settings.json Brand block (Name/TemplateRoot/OrderNumberLabel/OutgoingPrefix/
          Features.Sccm|Intune|Publish/Convert.MtbMappings|VwgVarRename|RegWowHardcode|LogPathMain|SoftIdentFormat)
          + Core.ps1 helpers Get-PBMember/Get-PBBrand(dot-path)/Test-PBFeature/Test-PBConvertFlag. MTB defaults = zero change.
      (b) AUDI template pack: PSADT_Template_AUDI\Content built from Wrappers\Final_GroupWrapper_v4.1.5 with our standard
          #*====X BEGIN/END==== markers injected into all 9 phases + CUSTOM VARIABLES/FUNCTIONS (comments only; parses;
          all 10 SectionMarkers verified). Adopted their authored deploymentType-default guard before LogName (their raw
          template bug, fixed in practice by their packagers). Builder: scratchpad\build_audi_template.ps1 (re-runnable).
      (c) Predecessor.ps1: $script:SectionMarkersAudiV4 (## MARK: fence extraction, Pre=$false everywhere - their authors
          write code ABOVE the "## <Perform" line) + Get-PBMarkerSet auto-detect per FILE + wired into Read-PredecessorModel.
          KEY FINDING: their AUTHORED v4 packages (7Zip/Python verified) KEPT the v3-style BEGIN/END markers - the STANDARD
          set extracts them perfectly (7Zip: version-check/40 old-ver uninstalls/process-kill kept; dialogs/reboot/phase-set
          stripped). MARK set = safety net for raw-template-authored packages.
      (d) Strip-Boilerplate additions: brand-neutral $adtSession.InstallPhase= / $Global:SessionDeploymentType= strips;
          AUDI-gated (Get-PBBrand Name -eq AUDI) bare Set/Remove-Branding + commented #Set-Reboot + "## Branding Uninstall".
      (e) BrandAudi.ps1 (NEW engine module, registered in Pack-Engine engineFiles): Get-AudiNameKey (normalise for match),
          Split-AudiRequestName (AES ticket + identity), Find-AudiRequestFolder (by package name w/ or w/o AES prefix,
          scored match), Resolve-AudiRequest (harvest: Files/SupportFiles/'Support Files'/raw payload root, icons incl
          root icon.png, Docs_EQS/Documents/Mails/'Shortcut Behavior' + root xlsx/docx/msg -> DocItems, Predecessor\
          both cases, Notes), Find-AudiPredecessor (request FIRST -> Outgoing fallback, brand-prefix + mangled-rev
          tolerant e.g. INA_..._2503_0002), Get-AudiPrefixChoices (from Brand.OutgoingPrefix).
          ALL RESOLVER TESTS PASSED against the real 6-request corpus (every shape verified). PS5.1 trap fixed: Notes
          was @() (fixed array) -> List + .ToArray() out.
   2026-07-07 AUDI round 2 (tasks #37-38 built; VERIFICATION PARTIALLY PENDING - classifier outage blocked the final
     Test-Build/XAML run; conversion+fill suite DID pass in full before the outage):
     ENGINE (verified green via scratchpad test_audi_convert.ps1 - ALL CONVERSION TESTS PASSED):
      - PSADT_V3toV4_Mappings: brand gates in Convert-V3ToV4Content ($flagMtb/$flagVar/$flagWow from Test-PBConvertFlag,
        default true): MtbOnlyFunctions=@(Set-Branding,Set-Reboot,Remove-Branding) skipped when MtbMappings off;
        -AdditionalRegPaths strip + Convert-VWGRegWOW gated; LAYER 2 uses $script:V3ToV4VariablesAudi when VwgVarRename
        off (dirFiles/dirSupportFiles/scriptDirectory->adtSession.*, configToolkitLogDir->adtConfig.Toolkit.LogPath).
      - Build.ps1: Get-FieldLinePrefix generalises Set-SessionField/Set-SessionValue to BOTH line shapes (MTB bare
        'Field =' AND AUDI '[type] $Global:VWG_Field ='); AppProcessesToClose mirror fill (no-op on MTB); SoftIdent
        dual-format DisplayVersion bump (MTB '[DisplayVersion = x]' + AUDI '[DisplayVersion]=x'); PC-swap + WOW
        normalize use the generalised prefix; Convert-LogPathFormat gated on LogPathMain flag; Get-TemplateScript
        prefers Brand.TemplateRoot folder. Assemble.ps1: Get-TemplateRoot prefers Brand.TemplateRoot; New-Package
        prefixes the OUTPUT FOLDER with NewPkg.OutPrefix (INA_/VWG_/G1V_; in-script AppFullName stays bare).
     GUI (edits done; XAML render check PENDING): LblRitmCaption named (startup sets '<Brand.OrderNumberLabel> number');
      TabIntegration/TabTesting/TabDevTest named + collapsed when Test-PBFeature Publish/Sccm false; PnlOutPrefix+
      CmbOutPrefix picker on Review&Create (populated from Get-AudiPrefixChoices, hidden when brand has none);
      $newPkg.OutPrefix from the picker ('INA - Audi' -> 'INA'); new controls registered in the FindName list.
     TESTS: Test-Build gained the AUDI corpus block (guarded on Downloads\OtherBrand): resolver (AES parse, mangled pred,
      find w/o prefix, raw Sources, Outgoing-prefix fallback), conversion profile on REAL MECM v3, template pack
      (markers, Get-TemplateScript pick-up, field fill, [DisplayVersion]=x bump), authored-v4 extraction (7Zip). Test-Build
      also now loads BrandAudi.ps1. Settings saved/restored around the block.
     NEXT VERIFY (single batch when classifier recovers): parse GUI/Assemble/Build/Test-Build + offscreen XAML render of
      the 6 new controls + FULL Test-Build (MTB regression + AUDI corpus). THEN: Step-1 AUDI resolver GUI wiring (browse
      AES request -> auto-harvest source/icons/docs/pred/AES) + bump BuildStamp + pack + AUDI portable folder assembly.
     REMAINING (tasks #37-38):
      #37 conversion profile wiring: gate MTB mappings/VWG var rename/RegWOW hardcode/LogPathMain in
          Convert-V3ToV4Content+Build.ps1 via Test-PBConvertFlag; add AUDI var maps ($dirFiles->$($adtSession.dirFiles),
          $dirSupportFiles->$($adtSession.DirSupportFiles), $configToolkitLogDir->$($adtConfig.Toolkit.LogPath));
          SoftIdent '[DisplayVersion]=x' format (parse + bump + generate); template root from Brand.TemplateRoot
          (PSADT_Template_AUDI); output folder <Prefix>_<AppFullName> + prefix picker (never offer the package itself
          in Outgoing fallback - reuse Get-PredecessorCandidates rule); Documents\Logs+Snapshots layout; no Intunewin.
          GUI: hide SCCM/Intune tabs/buttons when Test-PBFeature false; RITM label -> Brand.OrderNumberLabel ('AES');
          auto-fill AES from request folder; wire Find-AudiRequestFolder/Resolve-AudiRequest into Step 1 when Brand=AUDI.
      #38 gold-standard corpus tests: 6 v3->v4 pairs in Downloads\OtherBrand (guard w/ Test-Path).
     THEN: pack with a Brand=AUDI settings.json into a separate portable folder (no share needed - they have no live access).
   ===== THIS IS THE GPF-PackageBuilder COPY (split from Downloads\files 2026-07-10; entries above are shared MTB
   history up to the split - MTB work continues in Downloads\files, GPF work logs HERE) =====
   2026-07-10 GPF STEP-1 WIRING + LIB LAYOUT + PORTABLE (ALL TESTS PASSED; portable launch-verified GPF-2026-07-07.r1):
     - BtnFetch (Brand=GPF): Find-GpfRequestFolder (structured typed name matches free-text AES folders via Vendor+App
       key fallback) -> Resolve-GpfRequest -> AES auto-fills the order-number box (only when empty), source = Sources\
       parent (pre-shaped Files[+SupportFiles]) | raw PayloadRoot | request root; request Icons\ fills an empty
       Resolved.IconsPath; request DocItems (forms/mails/'Shortcut Behavior') merged into Resolved.DocItems (deduped).
     - BtnPred (Brand=GPF): Get-GpfPredecessorCandidates - the request's Predecessor\ pinned FIRST (authoritative, no
       live access), then Outgoing scan tolerant of the brand prefix + mangled revision via
       Get-GpfPredecessorPackageName ('INA_..._2503_0002_MUL' -> 'Microsoft_MECMConsole_x86_2503-0002_MUL');
       candidate .Name = normalised identity, .FullName = real path. VERIFIED live: 7Zip request pred loads
       [v3, MSI v25.01]; mangled MECM pred loads [v3, EXE v2503]; self never offered. State.GpfRequest in StepOwns[1].
     - Lib layout: lib\PSADT_Template_GPF (user rule); Test-Build template lookups Lib-first. Set-ProcToBlockDefault +
       ProcToClose asserts generalised to the GPF wrapper line shape (GPF copy only).
     - Portable: Downloads\GPF_PackageBuilder (loader exe 55KB + pak 412KB + settings/snippets/KB + PsExec +
       Lib\{AvalonEdit,ico,PSADT_Template_GPF}). TRAP fixed: the 991KB dev exe is the OLD self-contained r158 build
       that IGNORES the pak - always ship the 55KB loader.
     REMAINING for v1: ModulePack xlsx auto-fill (ProcToClose/instructions), real GPF share paths, Documents
     Logs\/Snapshots\ extras, live end-to-end user test of one corpus package.
   ===== PENDING PLAN (agreed with user 2026-07-01; NOT yet built; ALL builds LOCAL-ONLY, user pushes to share manually) =====
   The user paused here ("keep the plan updated, will get back later"). Resume with these, as a package engineer, refer live
   packages, local-only deploys each round:
   A. UNINSTALL SNAPSHOT + SMART LEFTOVER CLEANUP (biggest): mirror the install-snapshot flow for UNINSTALL - snapshot BEFORE
      uninstall (app installed) -> USER manually runs the uninstall -> snapshot AFTER. Diff = items present in BOTH (the
      uninstaller LEFT them) -> keep only APP-RELATED (vendor+app tokens / ARP DisplayName / install-dir name, cross-ref the
      INSTALL snapshot's created items) -> generate PSADT v4 POST-UNINSTALL cleanup (Remove-ADTFile/Remove-ADTFolder/
      Remove-ADTRegistryKey) + remove now-EMPTY folders (real emptiness check). SMART, not "keep everything". Build on
      Snapshot.ps1 (Get-MachineSnapshot / Compare-MachineSnapshot / Get-SnapshotRawDiff / Get-SnapshotCleanups).
   B. LOAD a SAVED report -> re-apply its actions (flexibility). AND shortcut-screenshot validation must be available on a
      LOADED report too (its snapshot shortcut list comes back with the report). Keep the screenshot button ENABLED until the
      tool is closed or reset (not one-shot).
   C. REMOTE shortcut-screenshot agent (user idea): a STANDALONE PBShots.ps1 (not full PB) copied to \\remote\c$\Windows\Temp\
      (works non-elevated w/ the user's remote-admin token) -> triggered via a SCHEDULED TASK in the LOGGED-ON user's session
      (runs even when the RDP session is LOCKED - locked != logged off) -> writes report + index.html + PNGs + done.flag ->
      tool polls, pulls the report back via c$, cleans up the remote task+temp. CAPTURE MUST USE PrintWindow(hwnd,hdc,
      PW_RENDERFULLCONTENT=0x2) NOT Graphics.CopyFromScreen - PrintWindow renders the window itself so it WORKS on a
      LOCKED/disconnected session (CopyFromScreen grabs the lock screen). Fallback to CopyFromScreen for GPU/Chromium apps that
      PrintWindow renders blank. ALSO switch the LOCAL capture to PrintWindow (then no need to minimize the tool / foreground
      apps). Screenshots.ps1 currently uses CopyFromScreen (lines ~484/494/538).
   Also revisit: "see anywhere we can update any logics" (general smartness pass).
   =========================================================================================================================
   2026-06-19 round 77 - UPDATE CONTENT now also asks before replacing prelive (user). $BtnUpdateContent.add_Click
     now, when NOT 'refresh only', checks <ContentShare>\<FullName>\Content and shows "This will MIRROR (REPLACE)
     the prelive content ... Really replace it?" (YesNo) on the UI thread BEFORE Start-SccmManageJob -Action content;
     No aborts, nothing copied. 'Refresh only' skips the prompt (it copies nothing - just refreshes the DPs). AUDITED
     the update-content flow and confirmed it is proper: $src priority = ContentSrc field -> loaded package (leaf ==
     FullName) -> Find-OutgoingPackage, Test-Path guarded; Update-SccmContent calls the (provider-safe, recursive-
     content-detect) Copy-PackageToPrelive BEFORE Push-Location G08:, then idempotently refreshes
     (Update-CMDistributionPoint when already distributed) else Start-CMContentDistribution. VERIFIED: GUI parses,
     Test-Build 50/50. LIVE caveat unchanged (prelive copy/DP refresh only provable on the real site). r77, 240KB.
   - PACKAGE CONFIG remaining (user also wanted): detection-method picker (ProductCode/file+version/registry/
     script), install context (system/user), reboot behaviour, prerequisite chaining. NEXT.
   - NEXT (Phase 4/5 - LAST per user): sandbox-automated capture (before/after INSIDE a throwaway VM).
   - NEXT (Phase 4/5): drive the snapshot from a sandbox automatically (before/after INSIDE the VM); verify the
     install AND uninstall with a second snapshot; feed the captured facts (uninstall string, services, dirs) back
     into the KB. Also: extend Analyze-KnowledgeBase to capture same-exe uninstalls (Citrix VDA /removeall) so the
     hint shows uninstall for that pattern. Optional: enable snapshot for MSI-only via the MSI tables too.
   2026-06-14 round 51 - proactive predecessor suggestion + uninstall shown in KB hint (user: "Citrix shows full
     install+uninstall from KB? suggest predecessor reuse when same app exists at another version").
   - PROACTIVE PREDECESSOR (issue 3): Suggest-Predecessor scans the live share (server-side -Filter
     "Vendor_App_*", fast; cached per app; skipped once a predecessor is chosen) on TxtPkg LostFocus; if other
     versions exist it sets LblPred to "a previous version is already in the live share (versions: ...) - click
     Find predecessor to REUSE (carries old commands, skips Detection)". Verified: hypothetical Citrix VDA 2508 ->
     finds 2203/2402x2/2507. TextChanged resets the scan cache so edits re-suggest.
   - UNINSTALL IN HINT: Update-KbHint now shows "Uninstall (from KB): <cmd>" when the recommendation carries one
     (MSI product code, or a dedicated uninstall.exe like GammaTech). NOTE: installers whose uninstall reuses the
     SAME setup exe with a flag (Citrix VDA = VDAWorkstationSetup.exe /removeall) aren't captured as a separate
     uninstall yet -> empty in the hint, but predecessor reuse carries the full uninstall section verbatim.
     (Future: analyzer could capture same-exe /removeall|/uninstall|-x uninstalls.)
   - Build stamp r51. Test-Build PASSED, pak shipped (197KB).
   2026-06-14 round 50 - small fixes from the user's list: predecessor-reuse SKIPS Detection; Avigilon "packaged
     as MSI+MST" hint; Citrix VDA clarified.
   - PREDECESSOR REUSE -> SKIP DETECTION (Citrix 6b): Next from Step 1 in predecessor reuse now runs detection
     SILENTLY (so a single-MSI predecessor still captures the new ProductCode for the swap) then jumps straight
     to the Editor (Step 3); Back from Editor returns to Info (Step 1). Step 2 stays clickable on the rail for
     MST matching. Honors the user's repeated "predecessor reuse = use same as predecessor, skip detection".
   - AVIGILON MSI+MST HINT (issues 1/4): Get-KBRecommendation - for an EXE source whose vendor/app was previously
     packaged as MSI (type=MSI, even with empty install args, since MSIs often install via the MST), returns
     PackagedAsMsi + the MSI install/uninstall. Update-KbHint shows "previously packaged as MSI+MST - extract/
     capture the MSI" + the previous uninstall, instead of a useless EXE-args guess. Verified: Avigilon_ACCClient
     -> PackagedAsMsi=True.
   - CITRIX VDA 6a clarified: not a bug - its install is `$returnCode = Start-ADTProcess VDAWorkstationSetup.exe`
     + exit-code handling (Citrix returns 3 = reboot). Predecessor reuse carries it verbatim; the skip now lands
     the user in the editor with the correct commands. (My earlier "0 commands" was a test-regex artifact - it
     only matched line-leading Start-ADT, not the assigned form.)
   - ISSUE 2 (same version): NOT skipped - the byInstaller tier matches the installer name regardless of version,
     so an exact/same-version package still gets the recommendation.
   - STILL OPEN (small): issue 3 - proactively suggest predecessor reuse when the same app exists at another
     version. NEXT: the big snapshot-capture plan (see below / discussed with user).
   - Build stamp r50. Test-Build PASSED, pak shipped (197KB).
   2026-06-14 round 49 - MSI capture finds the REAL msi, not the runtime one (user: "Avigilon EXE caches the MSI
     in C:\ProgramData\Package Cache\{GUID}vX - capture only looked at C:\Windows\Installer and showed the wrong
     runtime msi; just find any real msi created other than the runtime installer one").
   - Get-MsiWatchDirs now includes C:\ProgramData\Package Cache (where WiX/Burn bundles cache the REAL app MSI);
     Windows\Installer is kept but ranked LAST. New Test-RuntimeCacheMsi flags the \Windows\Installer\ runtime
     copy. Get-NewMsisSince now sorts REAL extracted MSIs (temp / Package Cache) ahead of the runtime cache, then
     by size - so the actual app MSI is at the top of the capture list, not the renamed install DB. Sandbox
     Capture.ps1 dir list also gained Package Cache. Verified: watch dirs include Package Cache; classifier
     correct; new-MSI diff works. (Reading Package Cache may need the tool elevated - best-effort.)
   - STILL OPEN from the user's list (next): (1/4) KB hint should say "this app was previously packaged as
     MSI+MST (extracted from the EXE)" + show uninstall/product code when an EXE source matches a vendor/app that
     was MSI-packaged; (2) confirm same-version isn't skipped; (3) proactively suggest predecessor-reuse when the
     same app exists at another version; (6) Citrix VDA multi-installer: main-installer params not suggested +
     predecessor reuse still showed the detection tab (EQS_Citrix_VirtualDeliveryAgent_x64_2507.0.1100.167).
   - Build stamp r49. Test-Build PASSED, pak shipped (196KB).
   2026-06-14 round 48c - DEEP AUDIT pass (user: "scan deeper for scenarios to improve / bugs / predictable
     failures"). Scanned the known bug classes + risky recent code; two real fixes, rest noted as low-risk.
   - FIXED (semantic, parse-clean-but-broken class): Move-V4RuntimeVars could move a variable definition out of
     the CUSTOM-VARIABLES block while a NON-assignment there (a helper function / bare statement) still referenced
     it -> dangling reference at runtime. Added a guard: if anything KEPT still references a would-be-moved var,
     back off entirely (leave it for the manual-review finding). Verified: Scania still auto-moves; a synthetic
     function-uses-var case now backs off (moved=0); control (no ref) still moves (moved=1).
   - FIXED (noise): the INF/ISS review finding matched ANY .inf/.iss anywhere (comments, log names). Tightened to
     only fire when the file is in an install command / argument context. Scania's Setupins.inf still detected.
   - REVIEWED + clean: List[object] @()/comma-wrap (all returns use .ToArray()/pipe-collect/List[string] - safe);
     [version]/[int] casts (try/catch guarded); 256/$max icon scale (guarded by >256); percent math
     ([Math]::Max(1,..)); Substring offsets (from regex indices, length-guarded).
   - NOTED (low-risk, not changed): sandbox Start-Process may meet a UAC prompt with no interactive approver -
     but the .wsb LogonCommand runs elevated so the installer inherits elevation (untestable here, no Sandbox);
     Move-V4 doesn't reach a PRE-section whose marker is absent in a converted script (template has all);
     review popup auto-shows once/session (button shows live count after); Copy-InstallerLocal copies EXE-only
     when the source folder >1200MB (rare, could miss siblings); multi-repo array needs direct/call-operator
     invocation (documented).
   - Build stamp r48. Test-Build PASSED, pak shipped (195KB).
   2026-06-14 round 48b - KB identity from the PS1, not the folder (user: "target the ps1 file mostly; even if
     the folder name isn't ours we can get vendor/app from inside the ps1; fuzzy match should work").
   - Analyze-KnowledgeBase.ps1: Parse-Name now returns Matched=$true/$false. New Get-ScriptIdentity reads
     Vendor/App/Version/Arch/Lang straight from the script ($adtSession AppVendor/AppName/... on v4, $appVendor/
     $appName/... on v3). Get-PackageFacts: when the FOLDER name doesn't follow our convention (another repo's
     naming), it takes identity from the SCRIPT (folder fills any gaps) - so the KB records the right vendor/app/
     version regardless of folder naming. Verified: GammaTech(v4)->GammaTechnologies/GTSuite/2026.1.0000,
     Inkscape(v3)->Inkscape/Inkscape/1.4.0; a non-convention folder -> Matched=False -> script identity used.
     (Fuzzy installer-name matching already exists via byInstaller's version-stripped key + the vendor/app/engine
     tier fallback; this makes the vendor/app it keys on reliable for any repo.) Analyzer re-shipped.
   2026-06-14 round 48 - KB EXPANSION: merge + multi-repo (user: "accumulate over time - combine our repo with
     other brands' repos when available and store them, so we have one huge KB usable anywhere").
   - Analyze-KnowledgeBase.ps1: -RepoPath is now [string[]] (mine ONE or MANY repos in a run; unreachable repos
     are skipped, not fatal - so it works "when those are available"); new -Merge switch folds the new repo's
     packages into the EXISTING KnowledgeBase.json (freshly-mined records win per package name, all other prior
     packages carried forward) so the KB GROWS instead of being replaced - a newer app VERSION (different package
     name) is just added and the newest-version aggregation picks it. The recommendation index is re-aggregated
     from the COMBINED record set each time. Cmdlets aggregation made robust to JSON-loaded (PSCustomObject)
     records as well as freshly-mined (hashtable). recFile now derives from -OutFile (KnowledgeBase.Recommend.json
     for the default; a custom -OutFile gets its own index and never clobbers the production one).
   - VERIFIED: base mine 12 -> -Merge another repo -> 13 with the prior live package retained; multi-repo run
     (-RepoPath @(live,eqs)) aggregates both. NOTE: multi-repo must be invoked directly/with the call operator,
     NOT powershell.exe -File (arrays don't bind through -File); the -Merge sequential path is the robust
     alternative. The standalone analyzer is now copied to the ship folder so the KB can be expanded anywhere.
   - (No pak change - the analyzer is a standalone mining script, not an engine module; still r47 runtime.)
   2026-06-14 round 47 - KB arg-extraction fixes (GammaTechnologies) + full engine PARAMETER reference + capture
     order (user: "got only --mode unattended but many params exist - it's under $parameters; the install engine
     should find ALL params not just silent; suggest first-time from the installer file; multiple bundled
     installers -> order via event viewer").
   - KB BUG (Resolve-ArgString in Analyze-KnowledgeBase.ps1): (1) the install used -ArgumentList "$Parameters"
     (var INSIDE quotes) but the resolver only matched a bare $Var, so it never followed it; (2) [^'"]* truncated
     at the first backtick-escaped quote (`"$env...`"). Rewrote to handle quoted var refs + backtick-escaped
     quotes (Unwrap-ArgToken). (3) AGGREGATION bug: the install-EXE picker matched the app name, but
     "Uninstall_GT-SUITE.exe" also contains "gtsuite" so the UNINSTALLER won -> recorded its "--mode unattended"
     as install. Now uninstaller EXEs (uninstall|unins\d|uninst) are split out of the install candidates AND used
     for the uninstall args. RE-MINED 920 packages -> GammaTech now returns the full 12-arg command for both
     setup-windows.exe and setup-windows-x64.exe. KnowledgeBase.Recommend.json (1469KB) copied next to the exe.
   - ENGINE PARAMETER REFERENCE (Source.ps1 Get-EngineParameterHelp): full switch set per engine (MSI / Inno /
     NSIS / InstallShield / WiX-Burn / 7z-SFX / WinRAR-SFX / InstallAware / Wise / MSIX / custom), not just the
     silent switch. Wired into Update-KbHint: when there's NO KB match, the hint now falls back to the installer's
     ENGINE - suggests its default silent switch (usable) AND lists every parameter the engine supports, so a
     brand-new installer gets a useful first-time suggestion straight from the file's fingerprint. (For MSI the
     real per-MSI properties stay available via 'View MSI properties'.)
   - CAPTURE ORDER: multi-installer capture now sorts the picked MSIs by appearance time (= the order the wrapper
     extracted/installed them = the package's install order; uninstall is the reverse) before handing them to
     Add-ManualInstallers as ordered multi-installers. (Event-log exact sequence is a future refinement; file
     write-time is the proxy.)
   - Build stamp r47. Test-Build PASSED, pak shipped (195KB) + KB JSON in ship folder.
   2026-06-14 round 45 - AUTOMATIC capture via Windows Sandbox (user: "if sandbox is available then this process
     should be automatic"). Safe + self-cleaning: the installer runs in a throwaway VM, never touches the host.
   - BundledMsi.ps1: Test-SandboxAvailable (WindowsSandbox.exe present); $script:SandboxCaptureScript = a self-
     contained Capture.ps1 that runs INSIDE the sandbox (no tool modules there) - snapshots temp/system MSIs,
     runs the installer, and copies every NEW .msi (>=100KB, + sibling cabs/mst) it drops to the mapped out
     folder AS IT APPEARS (catches a transient temp MSI even if the installer deletes it), then writes _done.txt;
     Start-SandboxCapture writes the .wsb (maps installer dir read-only -> C:\src, work dir read-write -> C:\work)
     + Capture.ps1, launches WindowsSandbox.exe, returns the host out-folder path (non-blocking).
   - Show-MsiCaptureDialog: new accent "Run in Sandbox (auto)" button (disabled with an explanatory tooltip when
     Sandbox isn't enabled). On click it launches the sandbox and a DispatcherTimer polls the out folder, filling
     the MSI list as captures appear and showing status until _done.txt (or an 8-min deadline). Then the existing
     Use-selected flow switches the source to MSI+MST. Manual Run/Scan stays as the fallback.
   - VERIFIED: the in-sandbox Capture.ps1 logic tested locally against a FAKE installer (a .cmd that drops a real
     MSI into a temp folder) -> captured the MSI + wrote _done.txt; fixed Start-Process empty-ArgumentList +
     self-detection of the out folder. Dialog renders correctly. Sandbox NOT enabled on this box (Win11 Ent +
     hypervisor present, feature off) so the live end-to-end sandbox run is untested here; availability gating +
     manual fallback are tested. Cleanup is automatic (sandbox is disposable) - this is the safe path the user
     wanted for EDR/agent installers like SentinelOne.
   - NEXT (sandbox-only, logged): after capture, also derive UNINSTALL + verify install/uninstall via snapshot
     diff inside the sandbox (the user's full vision); needs the sandbox enabled to build+test.
   - Build stamp r45. Test-Build PASSED, pak shipped (191KB).
   2026-06-14 round 44 - RUN & CAPTURE the runtime-extracted MSI (user: "ask user to run the installer (even for
     multiple); for EXEs that extract the MSI at runtime, enable a button, check event log + temp/system folders
     after the run, grab the MSI - whole folder if it has cabs, else just the MSI - then make the MST. Sandbox not
     available so rely on manual trigger; you don't have to finish installing to get the MSI").
   - BundledMsi.ps1 capture engine (all read-only except the user-triggered Run): Get-MsiWatchDirs (TEMP /
     Windows\Temp / Windows\Installer), Get-MsiSnapshot (baseline of existing .msi), Get-NewMsisSince (new/fresh
     .msi >= MinKB since the baseline, recurse depth 4), Get-RecentInstallerMsiFromEventLog (MsiInstaller
     Application-log products, read-only), Copy-CapturedMsi (brings sibling cabs/transforms when the folder looks
     DEDICATED - few files + >1 cab/msi/mst - else just the MSI, per the user's rule).
   - Show-MsiCaptureDialog (Step-2 "Run & capture MSI..." button, lone EXE): snapshots on open; [Run installer]
     launches the EXE after a hard YesNo warning (it actually installs on THIS box); [Scan for new MSI] lists what
     the run dropped (name/size/folder); [Use selected] copies via Copy-CapturedMsi and switches the source to
     MSI+MST (Add-ManualInstallers) with a SourceNotes review line ("CAPTURED from a run of '<exe>' - wrapper may
     do more; TEST; clean up the test install"). Supports multiple MSIs. The tool NEVER auto-runs the installer.
   - VERIFIED: engine tested with a synthetic temp extraction (App.msi + data1.cab in a dedicated folder) ->
     detected the new MSI + captured the cab too; event-log read clean; dialog renders correctly (offscreen).
     The actual installer run + real capture is user-driven (can't be unit-tested without running an installer).
   - HONEST: cleanup/uninstall of the test install + the snapshot-diff approach is the user's job for now (no
     sandbox); the SourceNotes line reminds them. Auto cleanup/uninstall is a sandbox-only future step.
   - Build stamp r44. Test-Build PASSED, pak shipped (188KB).
   2026-06-14 round 43 - PSADT v4 variable-scope AUTO-FIX + bundled-MSI extraction (user: "auto-move Deployment
     Type/$env* custom vars to install/uninstall/repair pre-sections (manual otherwise); scan KB for these vars;
     can the tool extract a bundled MSI + make the MST itself?").
   - KB SCAN (custom-variables): 70/120 packages have a CUSTOM VARIABLES block; 46 reference ADT runtime vars
     that are EMPTY there on v4 (the block runs BEFORE Import-Module/Open-ADTSession). Found: $adtSession.
     DeploymentType x59 (+DirFiles/DirSupportFiles), and ADT $env* - $envSystem32Directory x45, $envPublic,
     $envProgramFiles, $envProgramData, $envSystemRoot, $envTemp - and $configToolkitLogDir. (Identity fields
     AppName/AppVersion/AppVendor/AppArch/AppLang ARE in the literal $adtSession and stay.)
   - AUTO-MOVE (Build.ps1 Move-V4RuntimeVars, applied in Build-PredecessorScript): relocates CUSTOM-VARIABLES
     assignment lines that read DeploymentType / ADT $env* / $config* (and anything that depends on them) into
     each action's PRE-INSTALLATION / PRE-UNINSTALLATION / PRE-REPAIR section, where the session+env are live.
     Skips multi-line/here-string assignments (left for manual). Corpus SAFETY: 100 packages, 39 moved, 0 parse
     breaks introduced. Marker comment "[Package Builder] moved from the variables block" -> Get-ScriptReview
     Findings reports "AUTO-MOVED... verify" (transparent); a still-unmoved DeploymentType line is flagged to
     move manually. VERIFIED on Scania_XCOM: moved 11 lines, 0 DeploymentType left in var block, parse-clean.
   - BUNDLED-MSI (BundledMsi.ps1, Step-2 "Check for bundled MSI..." button for a lone EXE): Test-ExeBundlesMsi
     statically scans the EXE (no install run) for an OLE/MSI header + wrapper signatures and gives an honest
     verdict; Find/Expand-BundledMsi use 7-Zip (Lib\7za.exe / installed / PATH) to LIST/EXTRACT the embedded
     MSI; on extract the source switches to MSI+MST (Add-ManualInstallers) with a SourceNotes review line
     ("extracted from wrapper '<exe>' - the wrapper may also install prereqs/registry the bare MSI won't; TEST").
     PROBED the real SentinelOne 72MB EXE: no OLE/MSI header (custom installer builds/decrypts the MSI at
     runtime) -> correctly reports "not statically extractable". Tested positive (stub+f3752.msi -> detected) +
     negatives. NOTE: 7-Zip not on this box, so live extraction is untested here; the no-tool/custom paths are
     graceful + tested. Running the EXE to capture the MSI (SentinelOne) intentionally NOT automated (installing
     an EDR agent on the packaging box is unsafe/irreversible) - left to the user with guidance.
   - Build stamp r43. Test-Build PASSED, pak shipped (184KB, now includes BundledMsi.ps1).
   2026-06-14 round 42 - SEMANTIC review findings (user: "are you just checking syntax? I want the package to be
     MEANINGFUL + matching live + things needing attention properly kept for review"). User-found real gaps:
     SentinelOne EXE showed no KB suggestion; predecessor reuse kept the PREDECESSOR's product-code GUID in
     SoftIdent (version swapped, GUID not) with no review flag; CUSTOM VARIABLES that read $adtSession.DeploymentType
     are EMPTY on v4; predecessor INF/answer file reused but user not told to regenerate.
   - NEW Get-ScriptReviewFindings (Build.ps1): inspects the BUILT script (not just '## REVIEW' markers) and returns
     clear messages for: (1) SoftIdent/detection carrying a predecessor product-code GUID ({GUID} or {GUID}_is1)
     -> verify/replace for the new version; (2) CUSTOM VARIABLES block referencing $adtSession.DeploymentType
     (empty there on v4 -> move into Install/Uninstall/Repair function); (3) predecessor .inf/.iss answer file
     reused -> regenerate for the new version. Predecessor-only checks gated on IsPredecessor.
   - Wired into Get-CombinedReview (Step-3 popup + "Review (N)" button) AND Populate-Step4 now uses the same
     unified Get-CombinedReview (script markers + semantic findings + MST notes), so the editor popup, the toolbar
     button and the Step-4 checklist all show identical, complete review lists.
   - VERIFIED on the user's real packages: SentinelOne (MSI reuse) -> flags SoftIdent {7CCB2DE9...}; Scania_XCOM
     (v3 Inno reuse) -> flags {E2F216BE...}_is1 + $adtSession.DeploymentType in the var block + Setupins.inf.
     FRESH build -> 0 findings (no false positives; SoftIdent is the AppName/version from the r41 fix).
   - KB EMPTY-STATE (SentinelOne "no suggestion"): Update-KbHint no longer HIDES the card when the KB has no match;
     it now shows "[engine] no known args" + guidance (check vendor instructions/docs; common silent patterns per
     engine) and hides the "Use these args" button. The empty box still flags "no silent switches" for review.
     (SentinelOne's live package is actually an MSI extracted from the vendor EXE; the vendor EXE is a custom
     unknown engine with no KB data, so "no args" is correct - now it's explained, not silent.)
   - HONEST scope: these are flagged for REVIEW, not auto-fixed. Auto-swapping the SoftIdent GUID to the new MSI's
     ProductCode (readable silently even though the detection window is skipped on reuse) is a logged future step;
     moving the DeploymentType line into the function is left to the packager (auto-move is risky).
   - Build stamp r42. Test-Build PASSED, pak shipped (179KB).
   2026-06-13 round 41 - FULL-ps1 verification (found+fixed a real fresh-build bug) + palette repaint + two UI
     visibility-bug fixes + Review-items popup in the editor (user: "test ALL ps1 generated properly not just
     install/uninstall/repair, for all cases; change colour combination (your pick - professional/unique/smooth);
     EXE-not-MSI not visible; snippets dropdown not visible; review items as a first-time popup in the editor +
     a button to reopen with updated info"):
   - FULL-SCRIPT VERIFY (new check beyond command lines): for 100 random live packages, built BOTH predecessor-
     reuse (version-bumped) AND fresh, and checked the WHOLE script: parse, $adtSession present, all 10 section
     markers present, identity fields (AppVendor/AppName/AppArch/AppVersion/AppScriptAuthor) populated AND
     matching, no unresolved <token>, not truncated, no v3 residue. Result after fix: PRED 100/100, FRESH 100/100.
   - REAL BUG FOUND + FIXED: fresh builds shipped a LITERAL placeholder in the detection key -
     SoftIdent = '...\Uninstall\<Appname> [DisplayVersion = <version>]' (the blank template default). Build-
     FreshScript only replaced SoftIdent when NewPkg.SoftIdent was supplied, and neither the corpus harness NOR
     the GUI's Build-Step3Script supplies it -> EVERY fresh package carried '<Appname>'. Predecessor reuse never
     showed it (it overwrites SoftIdent from the predecessor). Fix: Build-FreshScript now always resolves the
     <Appname>/<version> tokens to the real AppName/Version inside the SoftIdent regex callback ($-escaped),
     then Normalize-SoftIdent for the hive. Fresh went 0/100 -> 100/100 clean.
   - UI BUG 1 (EXE/short textboxes clipped): theme TextBox Padding 6,3 was too tall for the Height=24/26 boxes,
     so "EXE" / "(not an MSI)" were vertically cut. Fixed: Padding 8,2 + VerticalContentAlignment honoured by the
     PART_ContentHost (padding on the Border, ScrollViewer fills) -> no clipping.
   - UI BUG 2 (snippets dropdown invisible): partial ComboBox style (colours, no template) hid the selected text.
     Fixed: full dark ComboBox ControlTemplate (rounded toggle, chevron, themed Popup) + ComboBoxItem style
     (accent hover). Selected text + drop-down list now clearly readable.
   - PALETTE REPAINT (Theme.ps1 + harmonised GUI.ps1 hardcodes): "professional, unique, smooth" - layered
     graphite (#181A1F/#21242B/#2A2E36) + soft low-contrast borders + ONE refined teal-cyan accent (#2BA6B8)
     used sparingly (CTA / focus / selection / active step). Global replace in GUI.ps1: bg #1E1E1E->#181A1F,
     #252526->#21242B, #2D2D30->#2A2E36, text #D4D4D4->#E7E9ED, header accent #9CDCFE->#56C8D6; active nav step
     now teal. Semantic status colours (green/amber/red/orange) kept. Verified by offscreen renders (steps 1/2/3
     + popups all cohesive). NOTE: native [Windows.MessageBox] Yes/No stays OS-light (custom would be needed).
   - REVIEW POPUP IN EDITOR: new Get-CombinedReview (## REVIEW markers + MstReviewNotes, live re-scan),
     Update-ReviewButton (toolbar "Review (N)" amber when items / "Review" green when clear), Show-ReviewPopup
     (themed modal, numbered accent-bar cards, OK). Auto-shows ONCE on first editor entry with items
     ($script:ReviewAutoShown); the "Review" toolbar button reopens the up-to-date list anytime; refreshed on
     Rebuild. (Step-4 review block kept as the final checklist.)
   - Build stamp r41. Test-Build PASSED, pak shipped (177KB).
   2026-06-13 round 40 - live verification (predecessor reuse + fresh vs shipped) + MODERN UI THEME everywhere
     (user: "verify with live packages the ps1 generates as expected vs already available + cover all scenarios;
     and make the UI professional/neat/modern like a real vendor tool, easy on eyes, every window/button/popup"):
   - LIVE VERIFY (corpus 60/60 built, 0 PARSE ERRORS, 0 exceptions; + concrete shipped-vs-generated examples):
     * UiPath (v4 MSI): predecessor reuse reproduced the shipped install line VERBATIM incl. custom
       ADDLOCAL="Studio,Robot,EdgeExtension" EDGE_INSTALL_TYPE=POLICYONLINE. parseErr=0.
     * IPETRONIK IPEmotion (v3, 24-MSI monster): every Execute-MSI -> Start-ADTMsiProcess with all
       BINFOLDER/APPDATAFOLDER args preserved, redist EXEs + product-code uninstalls intact. parseErr=0, v3residue=0.
     * Adobe AcrobatPro (v3 EXE): custom uninstall/repair logic converted clean. Fresh builds parse-clean.
     * Corpus "brace imbalance 60 / empty main section 29" are METRIC FALSE POSITIVES (crude quote-strip; and the
       empty-section check does a verbatim match of the v3 predecessor's first line against the v4-converted
       build, which renames Execute-MSI->Start-ADTMsiProcess so it never matches). Parse=0 proves integrity.
     * NOT-A-BUG: the test/corpus harness calls Read-PredecessorModel WITHOUT -PackageName, so model.Identity is
       empty (version-swap dormant in the test). The real GUI passes -PackageName at BOTH call sites
       (GUI.ps1:1719, 1928) so Identity/version-swap ARE live in production. Verified by code inspection.
     * Genuine minor items (logged, not corruption): 4/60 v3-residue (SAP/UiPath/Adobe/VS2026), 1 custom-log
       loss (VS Professional 2026 -9 lines). Both parse fine; future polish.
   - MODERN UI THEME: new Theme.ps1 = one shared dark ResourceDictionary (Apply-PbTheme merges it into a Window's
     resources -> implicit styles cascade to ALL Buttons/TextBoxes/CheckBoxes/ComboBoxes/ListBoxItems with no
     per-control edits). Calm low-strain palette (bg #1B1D23, surface #23262E, accent #4C8DF6). Rounded buttons
     with clear hover, keyed PbAccentButton for the Next/Create CTA, rounded accent-focus textboxes, custom
     rounded accent checkboxes, calm (not bright-blue) list selection. Apply-PbTheme wired into the main window
     + EVERY dialog (predecessor/installer pickers, MSI props, log picker, predecessor diff, MST plan). Dot-
     sourced in GUI dev path, added to Pack-Engine engineFiles (2nd, after Core) and Test-Build load order.
     VERIFIED by offscreen render: main window steps 1/2/4 + predecessor-picker popup all look consistent/clean.
     NOTE: native [Windows.MessageBox] Yes/No confirmations stay OS-themed (light) - theming those needs custom
     dialogs (out of scope); all of the tool's OWN windows/popups are themed.
   - Build stamp r40. Test-Build PASSED, pak shipped (174KB, now includes Theme.ps1).
   2026-06-13 round 39 - MST plan CONFIRMATION dialog + opt-in replication of extra removals (user: "safe ones
     will be decided by user to apply ... default ones show as will-be-applied and extra whatever you select
     will be applied. if user confirms then only everything starts applying"):
   - NEW Show-MstPlanDialog (GUI.ps1): "Match predecessor MST" no longer silently mutates the toggles. It now
     opens a confirmation dialog showing (a) WILL BE APPLIED (standard): desktop-shortcut / Run-key removal
     pre-ticked from what the predecessor did + the properties to set; (b) EXTRA CHANGES the predecessor MST
     also made, as a DataGrid - safe REMOVALS are opt-in "Apply" checkboxes, additions/changes are "manual
     only" (Apply box disabled via IsEnabled-bound-to-CanApply). NOTHING changes until "Apply plan"; Cancel =
     no-op. On confirm: writes the standard toggles to State.MsiFlags DIRECTLY (add_Click does NOT fire on a
     programmatic IsChecked set), sets State.MstApplyExtras = selected removals, State.MstReviewNotes = the
     report-only items (surfaced in Step-4 review block).
   - Read-MstSettings now returns OtherItems = structured objects {Category,Action,Table,PkCol,Keys,CanApply,
     Label,Note}; removals (LaunchCondition / non-desktop Shortcut / extra Registry key / Environment) carry
     the base PKs and CanApply=$true; adds/changes are CanApply=$false (re-inserting a row that references a
     component maybe-absent from the new MSI could corrupt it -> manual). Get-MstTableSig rewritten to take the
     column count from _Columns (Record.FieldCount returns 0 with this installer provider, which had truncated
     the signature to the PK and hidden value CHANGES).
   - Build-Mst / New-PackageMst / New-Package(Assemble) gained -ApplyExtras/-MstApplyExtras: each selected
     removal deletes rows by PK on the NEW MSI via Remove-MsiTableRows - a safe no-op if the key is gone, so it
     can never corrupt the package. GUI create call threads @($script:State.MstApplyExtras).
   - VERIFIED on C:\Windows\Installer\f3752.msi: full round-trip - detection (lcDetected=True, keyMatch=True,
     canApply=True) -> feed item back to Build-Mst -> the LaunchCondition is actually removed (rows=0); no-op
     with a bogus key throws no error and leaves the table intact; dialog renders correctly (offscreen).
   - BUGS fixed en route (both new permanent gotchas): (1) Windows PowerShell 5.1.26100 throws
     System.ArgumentException "Argument types do not match" when @()/comma-wrapping a List[object] that holds
     PSCustomObjects -> use .ToArray() / [object[]] / pipe-collection instead. (2) New-Object Windows.Setter
     (prop,enumValue) mis-binds ENUM values (stored as the literal expression string) -> build the Setter with
     explicit .Property/.Value assignment. Both caught by the offscreen render + corpus-style tests.
   - Build stamp r39. Test-Build PASSED, pak shipped (171KB).
   2026-06-13 round 38 - MST predecessor reuse: detect + REPORT other transform changes (user: "how far will MST
     changes be applied? any other changes also can be carry forwarded?" -> chose "detect + report the gaps"):
   - CONTEXT: predecessor-reuse "Match predecessor MST" auto-replicates only 3 intent categories (desktop
     shortcut removal, Run-key removal, Property adds/changes). It re-DERIVES intent (rebuilds a fresh MST vs
     the NEW MSI) rather than applying the old MST verbatim, because the old MST's row keys are tied to the OLD
     MSI and would be fragile across a version bump. (Verbatim path still exists separately: Find-VendorMst ->
     Build-Mst -ExistingMst applies a vendor .mst shipped next to the new MSI, 100%.)
   - ADDED (report-only, NO risky auto-apply): MstBuilder.ps1 Get-MstTableSig (generic full-row signature map,
     PK -> all-cols joined char31, FieldCount-driven). Read-MstSettings now diffs base-vs-transformed for
     Registry / Shortcut(non-desktop) / RemoveFile / LaunchCondition / Feature / Environment, EXCLUDING the
     desktop-shortcut + Run-key PKs already handled (no double-report), and returns OtherChanges = string notes
     (e.g. "Registry: 1 added / 0 changed / 0 removed (beyond the Run key)").
   - SURFACED clearly: handler persists notes to State.MstReviewNotes and appends them (amber) to the match
     line; Populate-Step4 folds them into the numbered ">> N ITEM(S) NEED YOUR REVIEW" block with guidance
     ("MST items: the predecessor's transform changed more than the Step-2 toggles capture; confirm the new
     version needs the same, adjust Step-2 properties/toggles if so"). Aligns with round-37 review surfacing.
   - VERIFIED: live share stores NO standalone .mst (these PSADT packages don't ship transforms), so built a
     SYNTHETIC MST off C:\Windows\Installer\f3752.msi (INSERT Registry row + DELETE LaunchCondition) ->
     Read-MstSettings reported OTHER=2 exactly: "Registry: 1 added" + "LaunchCondition: 1 removed/bypassed",
     with 0 false positives on the untouched categories. Both files parse clean.
   - Build stamp r38. Test-Build PASSED, pak shipped (167KB).
   2026-06-13 round 37 - corpus re-scan + clearer review items + calmer diff colors (user: "check logic against
     live packages... whether we give todo kind of things which user need to look or review - those should be
     clear to user not just typing todo. and diff vs predecessor is colorful and not good to watch"):
   - CORPUS RE-SCAN: full build pipeline on 150 live packages = 150/150 built, 0 parse errors, 0 exceptions,
     0 log-loss, 4 v3-residue (cmdlets that PARSE on v4 but map 1:1 later - logged, not corruption). No
     situation produced a corrupt/non-parsing package; the Test-ScriptStructure red-banner gate still backstops.
   - REVIEW ITEMS (replaces silent "# TODO"): Build.ps1 Get-ExeCommandSet now prepends actionable
     "## REVIEW:" markers (e.g. "no SILENT INSTALL switches found for '<exe>' - add them or the install may
     prompt"; "no UNINSTALL command for '<exe>'"). New Get-ReviewItems(ScriptText) scrapes them; Populate-Step4
     surfaces a numbered, AMBER block in LblReview: ">> N ITEM(S) NEED YOUR REVIEW before this package is
     complete: 1. ... (fix in Step 3, then Rebuild)". So the user SEES exactly what to check, not a buried TODO.
   - DIFF COLORS: Show-PredecessorDiff DataTriggers softened from bright fills to low-saturation dark tints
     (mod #1B2430/del #241A1A/add #19231B) + a thin 3px colored LEFT accent bar (blue/maroon/green) and muted
     foregrounds; equal rows stay plain. Verified by offscreen render - calm, readable, accent-only.
   - Build stamp r37. Test-Build PASSED, pak shipped (164KB).
   2026-06-13 round 36 - MST replication for MSI predecessor reuse + live-share popup on Find-predecessor (user):
   - POPUP: factored Test-LiveShareDuplicate (checks PredecessorPath for the EXACT FullName = vendor+app+arch+
     version+release; once per name); called from BOTH Find-predecessor AND Step-1 Next. So clicking Find
     predecessor warns if that exact package already exists in the live share.
   - MST REPLICATION (Read-MstSettings in MstBuilder.ps1): applies the predecessor's MST to its base MSI (temp
     copy, ApplyTransform flag 31 = lenient) and diffs base-vs-transformed -> RemovedShortcut / RemovedRunKey /
     ExtraProps. "Match predecessor MST" button in Step 2 (MSI + predecessor reuse only) reads it and sets the
     Keep-shortcut/Keep-Run-key toggles + extra-properties box to replicate it; best-effort, degrades to a
     message + standard defaults if unreadable. VERIFIED 8/8 real MSI+MST pairs (Adobe Acrobat rmShortcut=True
     +8 props; 7-Zip ARPNOMODIFY/REMOVE; etc.). BUGS fixed en route: invalid .NET variable-length lookbehind
     regex for 64-bit Run (-> single Run filter), strict ApplyTransform(0) threw on real MSTs (-> 31), and COM
     method returns (Execute/Close/ApplyTransform) polluted function output making results an Object[] (->
     piped every COM call to Out-Null; helpers return List via ,$ idiom).
   - Build stamp r36. Test-Build PASSED, pak shipped (163KB).
   2026-06-13 round 35 - live-share exists popup at NAME ENTRY + swap-logic verification (user):
   - POPUP MOVED/ADDED: when the user commits a package name leaving Step 1 (Next), check the LIVE SHARE
     (PredecessorPath) for that EXACT FullName; if the folder exists -> YesNo "already exists in the live share
     ... Create it again?". Asked ONCE per distinct name ($script:LiveCheckedName) to avoid nagging. (The
     round-34 output/Outgoing check at Create stays too.)
   - SWAP-LOGIC VERIFICATION (user: "make sure product code swap & all logics are good, no corruption"):
     * STRUCTURAL: corpus scan = 0 parse errors; targeted test on 46 real scripts that CONTAIN a product-code
       GUID -> 46/46 built scripts PARSE. No corruption from version+PC swap.
     * FINDING: Model.Installer.ProductCode is captured in only ~1/46 (it's extracted from the INSTALL command,
       where MSI uses the .msi filename, not a GUID). So the PC swap rarely fires - and that's mostly CORRECT:
       the GUIDs in scripts are usually uninstall-previous refs (must KEEP, to remove the OLD version), and the
       build deliberately does NOT blindly swap all GUIDs (that would corrupt prerequisites/uninstall-previous).
       The package's REAL detection product code comes from Step 2 (Get-MsiProductCode on the NEW msi) =
       authoritative, independent of the script.
     * HONEST residual (low-freq, NOT corruption): a predecessor that hardcodes its OWN product code in an
       in-script self-detection/uninstall (rare; usually filename/branding) wouldn't be swapped. Targeted
       future improvement: also scan the uninstall command for the product code. Script stays valid regardless.
   - Build stamp r35. Test-Build PASSED, pak shipped (160KB).
   2026-06-13 round 34 - "already exists" popup at Create (user request): BtnNext Create flow, after the
   parse-gate and before build, checks if a package with the EXACT FullName already exists in the OutputBasePath
   or the Outgoing share (Find-OutgoingPackage). If so -> YesNo popup "A package named 'X' already exists: <where>.
   Create it again?" - No aborts. (SCCM/Intune already had their own exists guards; this is the build-time one.)
   Build stamp r34. Parse clean, Test-Build PASSED, pak shipped (160KB).
   NEXT (optional): byApp.exeInstall could prefer the RICHEST command across versions (so a renamed installer
   gets the full args, not just the newest's /S); follow @splat args; v3-residue mappings; version-flag.
   OUTSTANDING (user raised): version-swap leaves UNRELATED version numbers untouched (folder versions / bundled
   component versions like gimp-help-2.10.34 vs app 2.10.38) - by-design-safe (we only swap the known app
   version) but it leaves stale refs the packager must catch. NEXT: add a "stale version-like token" FLAGGER to
   the Step-3 build (surface unswapped version tokens for review; never auto-change - that risks corruption).
   Longer-term the sandbox/snapshot gives the REAL installed paths/versions.
   2026-06-13 round 25b - fix: `-File` launch threw "Split-Path ... Path is null" - $MyInvocation.MyCommand.Path
   is $null when evaluating a PARAM DEFAULT under -File. Moved $OutFile default into the body using
   $PSScriptRoot (fallback Get-Location). Verified with the user's exact command (-File, no args): outputs land
   next to the script. Parse clean.
   2026-06-12 round 24 - the REAL "diff button not visible" cause (user clarified: button GONE when installer
   changed): Step-3 toolbar DockPanel had LblScriptHdr FIRST (takes full desired width) and the buttons docked
   right AFTER - when Get-SourceWarning produced its long "Installer changed: predecessor used 'X', new is 'Y'"
   header, the text consumed the whole row and CLIPPED the Diff/Rebuild buttons out of view. (This also explains
   the earlier "it just shows installer names of predecessor and current" report - that WAS the warning text.)
   FIX: buttons are now allocated FIRST (DockPanel child order, docked right), the header is the fill child with
   TextTrimming=CharacterEllipsis + full text as ToolTip (set in Populate-Step3). RENDER-VERIFIED with an
   extra-long installer warning: text trims with '...', both buttons fully visible. Parse clean, Test-Build
   PASSED, pak shipped (153KB, build stamp r23 unchanged in title).
   2026-06-12 round 23 - diff NOISE (user: "is it even in the pak? exe just shows installer names"):
   - VERIFIED FIRST: ship pak DID contain all round-18..22 diff code (decrypted + grepped: engine, similarity,
     XAML, picker all present) and the user's launch log proved they ran the ship folder. The real problem was
     diff QUALITY, found by dumping the actual Mozilla rebuild diff: 70 changed rows, MOSTLY FORMATTER NOISE -
     the build pipeline re-spaces carried code ("If(" -> "If (", "a,b" -> "a, b", alignment columns), and the
     collapse-runs normalization still saw those as differences. Real changes (installer/version) drowned.
   - FIXES: (1) comparison key now strips ALL whitespace (Norm = remove \s entirely; trade-off documented:
     in-string spacing differences compare equal - acceptable lens). (2) template-FURNITURE rows dropped from
     the view ('## <Perform ... tasks here>', '## MARK:', '##===='/banner lines - stripped from predecessor +
     re-added by template = not real changes). (3) "Show only differences" now defaults OFF - full side-by-side
     scripts by default (the user's original BC-style ask); checkbox filters on demand.
   - RESULT on the real Mozilla rebuild: 70 -> 18 changed rows, formatting-noise rows = 0, every remaining row
     a REAL change (version/date/author/RITM/installer/log-scaffolding swap/Import-Module footer).
   - BUILD STAMP IN TITLE: Core BuildStamp -> '2026-06-12.r23'; window title = "Package Builder - build <stamp>"
     so "is my exe on the latest pak?" is answerable at a glance. Smoke-verified: ship exe title shows the stamp.
   Parse clean, Test-Build PASSED, pak shipped (153KB).
   2026-06-12 round 22 - diff availability + similarity pairing (user: diff "not available" after installer
   change during reuse; pairing confusing - "spaces showing as difference, text missing per line number"):
   - AVAILABILITY: Show-PredecessorDiff no longer dead-ends. LEFT side: in-memory model -> RE-READ from
     State.PredecessorPath (fresh Read-PredecessorModel) -> OpenFileDialog to pick ANY .ps1 to compare
     against (covers reuse/changed-installer flows where the model is gone). RIGHT side: editor text ->
     State.ScriptText -> the CREATED package's Content\Invoke-AppDeployToolkit.ps1 on disk. Window title
     names both sources.
   - PAIRING: 'mod' rows were paired by POSITION within a hunk, so UNRELATED del/add lines landed side by
     side (read as fake near-matches = the user's confusion). Now pairing is SIMILARITY-GATED (>=50%
     char-LCS on normalized text, like Beyond Compare): similar lines pair on one blue row; dissimilar
     stay separate red del / green add rows. VERIFIED: changed-version line -> mod; unrelated replacement
     -> separate del+add; eq untouched.
   Parse clean, Test-Build PASSED, pak shipped (518KB->153KB).
   2026-06-12 round 21 - DOUBLE-SUCCESS logic (user: predecessor has conditional success/else messaging; keeping
   it + template's unconditional trailing success = success logged TWICE on the happy path):
   - POLICY (now implemented): a success log INSIDE an if/else is LOGIC, not scaffolding.
     (1) Strip-Boilerplate is now BRACE-DEPTH-AWARE: "X of ... is successful" stripped ONLY at depth 0
         (top level); inside a conditional it survives verbatim (with its else "not found" branch).
         "Start Installation|Uninstallation|Repair" stripped at ANY depth (the template announces the start
         unconditionally; an inner copy is duplicate scaffolding - confirmed in the real Mozilla If-block).
     (2) Set-SectionBody DOUBLE-SUCCESS GUARD: when the injected body still owns an action-success log,
         the template's unconditional trailing success line is REMOVED for that section (body owns the
         outcome); otherwise the template line stays. Template Start line always stays.
   - VERIFIED on the real Mozilla build: Uninstall = 1 Start (template) + 1 conditional success (version-
     swapped, inside If) + 1 else not-found + Close-ADTSession kept; Install/Repair = 1 Start + 1 success
     (template; predecessor's top-level copies stripped). Custom Taskschedule logs intact, installer swap
     clean, script parses.
   - RISK SCAN (user asked re other packages) - 4 pattern cases all end with EXACTLY ONE action-success:
     (A) early-exit style (if !found -> log+Close-ADTSession; success at top level) -> top-level success
         stripped, template used; semantics identical. (B) Mozilla if/else -> conditional kept, template
         suppressed. (C) CUSTOM-WORDED success inside if (doesn't match the anchored form) -> kept as a
         detail line, template success stays (1 action-success + custom detail; acceptable). (D) no logging
         in body -> template scaffolding only. Residual risk documented: custom wordings are treated as
         detail lines, never as the action-success - predictable, never double.
   Parse clean, Test-Build PASSED, pak shipped (515KB->152KB).
   2026-06-12 round 20 - CRITICAL: installer swap broken for filenames WITH SPACES (user: "during installer
   changed the difference between predecessor is not showing"):
   - REPRODUCED with the real Mozilla predecessor + a changed installer: the built script contained
     "Firefox Setup Firefox Setup 140.11.0esr.msi" (DOUBLED prefix). ROOT CAUSE (Predecessor.ps1:244): the
     extraction regex [^\s"']+\.msi STOPS AT SPACES -> 'Firefox Setup 140.10.2esr_en-us.msi' extracted as
     '140.10.2esr_en-us.msi' -> the literal swap key matched only the tail (doubling the prefix), or - when
     the version pass had rewritten the digits inside the name first - matched NOTHING (silent no-swap, OLD
     installer left in the new script => the diff shows no change where the installer changed = the user's
     report).
   - FIX 1 (extraction): prefer the QUOTED filename (spaces included) for .msi/.exe/.mst, fall back to the
     bare token. Verified: extracts 'Firefox Setup 140.10.2esr_en-us.msi' in full.
   - FIX 2 (safety net, Build.ps1 swap map): also map the VERSION-SWAPPED variant of every old name to the
     same new value, so the literal swap can never be defeated by the version pass ordering.
   - VERIFIED end-to-end on the real predecessor: doubled prefix 0, old-name remnants 0, new name present
     2x (install+repair), built script parses, and the DIFF now shows the installer change as a clean mod
     row (old left / new right). USER ACTION: rebuild packages where the installer changed.
   Parse clean, Test-Build PASSED, pak shipped (512KB->151KB).
   2026-06-12 round 19 - CRITICAL: custom Write-ADTLogEntry lines were being DELETED (user found via the new
   diff on the Mozilla FirefoxESRMAN build - "we are corrupting predecessor"):
   - ROOT CAUSE (Predecessor.ps1 Strip-Boilerplate): the scaffolding-strip pattern matched ANY log line
     containing 'Start |successful' ANYWHERE. The custom line "Taskschedule Firefox Default Browser Agent ...
     is successfullY deleted" matched 'successful' -> stripped from Install AND Repair sections (verified by
     diffing the user's real files: old had 22 log lines, built had 20; the surviving If-block lost only its
     log line).
   - FIX: anchor to how the TEMPLATE's scaffolding MESSAGES BEGIN: quote followed by "Start (Installation|
     Uninstallation|Repair)" or "(Installation|Uninstallation|Repair) of ... is successful". VERIFIED on the
     targeted snippet (custom kept x3, scaffolding stripped x3) AND end-to-end on the real Mozilla predecessor:
     Taskschedule line survives x2 (install+repair), 15 custom lines survive = exact expected count
     (22 - 6 scaffolding - 1 in the template catch block), scaffolding still stripped.
   - Also fixed: BLANK lines showing RED in the diff (whitespace is supposed to be ignored): post-Align
     cleanup drops blank-only del/add rows and reclassifies mod-with-one-blank-side to add/del; verified -
     zero colored blank rows remain.
   - USER ACTION: REBUILD any package created while the bug was live (the Mozilla FirefoxESRMAN one) - the
     fix changes what the builder PRODUCES, it cannot repair already-built output.
   Parse clean, Test-Build PASSED, pak shipped (511KB->150KB).
   2026-06-12 round 18 - REAL side-by-side diff + FINAL pre-presentation verification:
   - DIFF REWRITE (user: want Beyond Compare style, ws-insensitive; old one just dumped removed-left/added-
     right via Compare-Object). New: C# LCS (Add-Type, PBDiff.Align, guard >30M cells) aligning predecessor
     LEFT / current RIGHT with per-side line numbers; del+add runs PAIRED into 'mod' rows (old+new on the
     same line); comparison key = trim + collapse \s+ so WHITESPACE-ONLY changes show as unchanged; dialog
     from XAML (no programmatic setters - the proven trap), DataTriggers: blue=changed red=removed
     green=added; "Show only differences (with context)" checkbox (default ON, 2 context lines, '...'
     separators). VERIFIED: engine on a 13/14-line replica (mod/add/eq + ws-only->eq all correct) AND
     rendered the dialog to PNG - visually confirmed alignment/colors/legend.
   - FINAL SWEEP (presentation tomorrow): all 17 .ps1 parse clean; Test-Build ALL PASSED; pak rebuilt
     (509KB->150KB) and round-trip-verified (decrypts byte-perfect, parses clean, contains engine+GUI+new
     diff); ship-folder integrity 11/11 critical items OK; ship exe smoke test alive with 'Package Builder'
     window; log proves engine initialized from the ship folder. Presentation_Notes.md written (what/why/
     architecture/distribution model/reliability/numbers) for the user's demo.
   2026-06-11 round 17 - SCCM content-update CONFIRMATION (user: instant success but DPs lag; when did content
   ACTUALLY update?): new Get-SccmContentStatus reads the site's per-DP records (WMI SMS_DistributionDPStatus,
   root\sms\site_<code> on the SiteServer, filtered by the app's PackageID): per-DP MessageState (1 OK /
   2 IN PROGRESS / 3 UNKNOWN / 4 ERROR, defensive default) + LastUpdateDate (WMI date converted) -> message
   shows "N OK, N in progress, N problem(s)", the NEWEST DP update time, per-DP table, and a verdict line
   (still running - re-check / problems - see console Monitoring / all up to date). New "Content status" button
   in Modify (job action 'contentstatus', in ActionButtons). Update content success message now states it only
   SUBMITS ("DPs update in the BACKGROUND - use Content status"). Live caveat: MessageState mapping confirmed on
   first real use. Parse clean, Test-Build PASSED, pak shipped (504KB->148KB).
   2026-06-11 round 16 - already-exists AppId made copyable (user): the AlreadyExists branch now ALSO copies the
   existing app's id to the clipboard (like the success path) and appends "(existing app id copied to clipboard)"
   to the label; the id was already filled into the Intune tab's App ID box (selectable) and the result label is
   a read-only TextBox (selectable). Pak shipped (147KB).
   2026-06-11 round 15 - "property IntuneAppId cannot be found" popup AFTER successful upload (user) - the
   GetNewClosure SCOPE TRAP:
   - CAUSE: round-12's `$script:State.IntuneAppId = ...` sits INSIDE the publish timer-tick .GetNewClosure()
     handler. A GetNewClosure block runs in its own dynamic-module scope: $script:State there is $null when the
     closure is created INSIDE A FUNCTION (only the function's locals are captured), and setting a property on
     $null throws exactly "The property 'IntuneAppId' cannot be found on this object". REPRODUCED offline with
     the same function-made-closure shape (exact message); top-level closures don't show it (script vars get
     captured), which is why a naive repro passes.
   - FIX: functions execute in their DEFINITION scope, so closures must mutate state via main-scope helpers.
     Added Set-IntuneAppIdUi (sets State.IntuneAppId + TxtIntuneAppId), Get-/Set-MsiPropsFor; replaced the two
     completion-handler sites AND the latent 2nd instance found by audit: the "View MSI properties..." click
     handler (its SAVE path indexed $null.MsiProps -> would error + lose edits in the exe). Audited ALL 9
     GetNewClosure blocks - the rest only use their own captured locals (safe). SCOPE RULE documented in code.
   - VERIFIED: repro errors direct / works via helper / main scope receives the value. Parse clean, Test-Build
     PASSED, pak shipped (499KB->147KB).
   2026-06-11 round 14 - Find-IntuneApp SPEED (user: exists-check too slow): the deep branding-key scan did ONE
   Graph GET PER APP across the whole tenant. Now FUZZY-PREFILTERS by display name first (apps whose name
   contains the product token - our apps are always named after the product), and only those few candidates get
   the per-app detection-rule GET. The EXACT branding key still DECIDES the match (name only narrows the search,
   correctness unchanged). fileName exact match (step 2a, list-only, no extra GETs) still runs first. Benefits
   the duplicate guard AND assignment/update-content resolution. Trade-off accepted: an app whose display name
   doesn't contain the product token would be missed by the deep scan - cannot happen for apps created by this
   tool or the migrator (both name by product). Parse clean, Test-Build PASSED, pak shipped (498KB->147KB).
   2026-06-11 round 13 - INTUNE FULL HARDENING PASS (user: "no errors should come; all errors handled"). Kept
   the proven mechanics (per user: Intune is sensitive); hardened EVERY stage surgically:
   (1) Invoke-Graph: 401 mid-flight -> re-auth ONCE (Connect-Intune) + refresh header + retry (long uploads
       outliving the token); 429 -> honor Graph's Retry-After header (cap 60s) instead of blind backoff.
       (4x retry on 5xx/429/network was already there.)
   (2) Wait-IntuneFileState + (3) Wait-IntuneCommittable: a transient Graph/network blip during status POLLING
       no longer kills the stage - logged as a warning, polling continues until the deadline.
   (4) Send-IntuneBlob scheduled SAS renewal wrapped in try/catch - a failed SCHEDULED renewal continues; the
       per-block resume renews on actual block failure anyway.
   (5) New-IntuneWinPackage failure now surfaces WHY: IntuneWinAppUtil exit code + last 4 output lines.
   (6) New-IntuneApp catch: rollback delete failure now SURFACED ("partial app id X may remain in the portal,
       delete before retrying") instead of silently swallowed; failure message includes the KEPT .intunewin
       path for manual upload (per design); "(rolled back - retry is safe, it will create fresh)" wording.
       $iw initialized so the catch never references an undefined var.
   Already-armored from earlier rounds: block upload (4x/block + 3x SAS-renew-resume), commit race (committable
   wait + 6x retry on the settling 400), icon .ico->PNG conversion (never fatal), duplicate guard (branding-key
   match + popup), rollback keeps .intunewin. Parse clean, Test-Build PASSED, pak shipped (497KB->146KB).
   2026-06-11 round 12 - Intune duplicate guard + stale-AppId fix (user: misleading "appid doesn't exist" then
   success; wants exists-popup BEFORE create, matched by branding key):
   (A) STALE APP ID: on create success the GUI only filled TxtIntuneAppId IF EMPTY -> a dead id from an earlier
       rolled-back attempt lingered; any action against it said "doesn't exist" while the retry create had
       actually SUCCEEDED (the misleading sequence). FIX: success now ALWAYS overwrites TxtIntuneAppId +
       State.IntuneAppId with the new id.
   (B) DUPLICATE GUARD: New-IntuneApp (unless Fields.ForceCreate) calls Find-IntuneApp BEFORE creating -
       matched ONLY by branding identity (fileName '<FullName>.intunewin' / detection keyPath \VWG\CM\<FullName>;
       never display name - Intune allows parallel same-name apps). If found -> returns AlreadyExists+AppId,
       nothing created. GUI shows a YesNo popup ("already exists ... Create ANOTHER copy anyway?"); Yes re-runs
       with ForceCreate=$true; either way the existing AppId is filled into the Intune tab. SCCM unaffected
       (AlreadyExists only set by the Intune path; SCCM already had its own exists-check).
   Parse clean, Test-Build PASSED, pak shipped (494KB->145KB).
   2026-06-11 round 11 - Intune icon + SAS-renewal commit race (user hit both; wants robust, limited-access):
   (A) ICON: Get-IconBase64 sent RAW .ico bytes labelled image/png when no .png existed -> Graph rejected the
       icon. FIX: convert .ico -> real PNG. WPF BitmapDecoder (handles BMP *and* PNG-compressed .ico frames,
       picks the largest), System.Drawing Bitmap(path) fallback; if both fail, create app WITHOUT icon (not
       fatal). VERIFIED 3 methods on the all-PNG-frame PackageBuilder.ico: Icon.ToBitmap() FAILS (range error),
       Image.FromFile/Bitmap(path) OK, WPF decoder OK + largest (256px). So now any .ico just works; PNG still
       used directly if present.
   (B) SAS-RENEWAL COMMIT RACE: after a SAS renewal during upload, the Graph /commit fired before the renewal
       settled -> HTTP 400 "File commit can not be started until status for SAS request or renewal has
       transitioned to 'Success'" -> whole create rolled back. FIX: new Wait-IntuneCommittable polls until
       uploadState in {azureStorageUriRequestSuccess, azureStorageUriRenewalSuccess} before commit; commit now
       wrapped in a 6x retry that re-waits + sleeps 10s ONLY on that transient 400 (other errors still throw).
       Surgical - did not touch the working block-upload/renewal loop.
   - Note for user: the retry "intuneappid does not exist then it created" = the first failed attempt ROLLED
     BACK (deleted the half-made app), so the retry correctly found nothing and created fresh - expected, not a
     bug. Parse clean, Test-Build PASSED, pak shipped (492KB->144KB).
   2026-06-11 round 10 - Reset didn't clear the Troubleshoot tab (user). CAUSE: Reset-Step/Invalidate-From only
   reset $script:State keys; the Step-4 tabs (Integration publish form, Modify, Testing, Troubleshoot, Intune,
   Dev-Test) hold MANUAL WPF control values not in State, so they were never cleared. FIX: new Clear-Step4Fields
   empties all those textboxes/lists/checkboxes/combos (TxtTsMachine, TxtTsAppName, LstTsMembers, LstTestMachines,
   ChkMod*, CmbTsColl, pub form, etc.), resets State.IntuneAppId, disables PnlPublish + collapses CreatePanel;
   called from Reset-Step (Step 4 is always downstream) so both Reset step and Reset all clear the tabs. Verified
   offline against the real XAML controls (populated then cleared -> PASS). Parse clean, Test-Build PASSED,
   pak shipped (487KB->143KB).
   2026-06-11 round 9 - 3010 "needs reboot" persisted AFTER reboot (user rebooted twice, still saw "just needs
   a REBOOT to complete"): the 3010/1641 exit code lives in AppEnforce.log forever, so the round-5 branch said
   "needs reboot" unconditionally. The user's message had NO "+ REBOOT REQUIRED" suffix => DetermineIfReboot
   Pending = FALSE (reboot done). FIX: gate the 3010/1641 wording on $rebootPending - pending -> "needs a REBOOT
   to complete"; NOT pending -> "$word complete (exit 3010 was a success-with-reboot; the reboot has already
   been done)". installed=true either way. Verified offline (pending true/false, 3010 + 1641). Parse clean,
   Test-Build PASSED, pak shipped (485KB->142KB).
   2026-06-11 round 5 - 3010 contradiction fix (user: header said "FAILED ... + REBOOT REQUIRED" while the
   explanation said "Exit 3010 - success, but reboot required" - confusing):
   - CAUSE: exit 3010 = SUCCESS-with-reboot, but the client flags the app Error (EvaluationState 13) until
     post-reboot detection passes. We showed the WMI verdict (FAILED) AND the log explanation (success) side
     by side without reconciling.
   - FIX: the concrete exit code WINS over the client's interim verdict. After the in-progress check:
     log code 3010/1641 -> state = "<Install|Uninstall> finished OK - just needs a REBOOT to complete (exit
     3010, not a failure)" [source AppEnforce.log (live)], installed=true (Install; false for Uninstall),
     no MISMATCH, NO error line (3010/1641/0 excluded from the failure explanation). Also: client-says-error
     but log exit 0 -> "finished OK (exit 0 - client state still catching up)".
   - VERIFIED offline (5 cases): user's exact case -> clean "finished OK - needs REBOOT" + matches-OK;
     stale-error+exit0 -> OK; real exit 1 STILL shows FAILED + explanation; clean install untouched;
     uninstall+3010 phrased with Uninstall verb. Parse clean, Test-Build PASSED. Shipped pak (472KB->138KB).
   2026-06-11 round 4 - WMI staleness fix (user: showed "Installed (complete)" + stale exit 1 while STILL installing):
   - ROOT CAUSE: CCM_Application WMI data is CACHED/lags - it read EvaluationState=12 (complete) while the
     retry install was actually still running, and kept the previous attempt's ErrorCode=1. So the tool
     wrongly said "Installed (complete)" AND dragged the stale exit 1 onto it.
   - FIX: AppEnforce.log (append-only, real-time) is now the AUTHORITY. New Get-SccmEnforceStatus parses it,
     app-scoped by DT name (=FullName, or product token): a "Starting <Install|Uninstall> enforcement for App
     DT "<ours>"" with NO matching "App enforcement completed" after it => InProgress (running NOW); else the
     last completion's "Exit Code: 0xN" (or the scoped "Matched exit code N" fallback for older log formats)
     is the real result. In Get-SccmInstallState the log OVERRIDES the WMI phrase: if log says in-progress ->
     "Installing/Uninstalling NOW - in progress (n% done)" [source: AppEnforce.log (live)], installed=false,
     no error shown. Error code is explained ONLY when not-installed AND not-in-progress (kills the stale-
     code-on-installed bug), and a success/zero code (0x00000000) is never shown as a failure.
   - Replaced Get-SccmLastEnforceCode with Get-SccmEnforceStatus. VERIFIED offline on 5 constructed AppEnforce
     logs: (1) failed->retry-running=InProgress True; (2) failed->succeeded=code 0 (no error, installed);
     (3) only-failed=0x1; (4) completion line w/o numeric code -> scoped "Matched exit code"=1; (5) a DIFFERENT
     app's lines never leak a code to ours. Parse clean, Test-Build PASSED. Shipped pak (470KB->138KB).
   2026-06-11 round 3 - install-state clarity + real failure reason (user-reported):
   - Two problems: (a) exit code 1 (0x1) failure was NOT surfaced; (b) it showed "NotInstalled" WHILE installing.
   - (a) CAUSE: the installer/MSI exit code (1, 1603, ...) is NOT a CCM_Application property - it lives in
     AppEnforce.log ("...with exit code 1"). FIX: new Get-SccmLastEnforceCode reads \\m\c$\Windows\CCM\Logs\
     AppEnforce.log and returns the LAST "exit code N" (or trailing 8-hex). Get-SccmInstallState now digs this
     whenever the app isn't cleanly installed/not mid-run and explains it (prefers it over the SCCM app code).
     Added raw exit codes to SccmErrorMap: 0x1 (exit 1 = general failure, full guidance), 2,3, 1602,1605,
     1619,1620,1638,1639,1641,1642 (1603/1618/3010/60012 already present; ConvertTo-Hex32 maps decimal->hex).
     Find-KnownLogErrors now also matches decimal "exit code [N]" (was hex-only) so the Package-logs button
     surfaces exit 1 too. VERIFIED offline: code 1/1603/3010/1618/1641 all explain; scanner + last-match work.
   - (b) CAUSE: CCM_Application.InstallState stays "NotInstalled" the ENTIRE install until post-install
     detection passes - so showing it verbatim read "NotInstalled" mid-install. FIX: new Get-SccmEvalPhrase
     maps the full EvaluationState enum (0-23) to CLEAR English: 2-7,11,14-23 = "Installing - <phase> (n% done)"
     / "Installing NOW"; 8-10 = "Installed - waiting for reboot"; 12 = "Installed (complete)"; 13 = "FAILED -
     the last install attempt errored"; 0/1/unknown -> fall back to plain "Installed"/"Not installed".
     PercentComplete 1-99 also forces an "Installing NOW" phrase. (My earlier 3/4-as-running guess was wrong;
     now the documented enum is used.) $installed excludes installing/failed; in-progress suppresses MISMATCH.
     VERIFIED offline across states 0,1,2,3,5,7,8,12,13,21,99 + Uninstall verb. Parse clean, Test-Build PASSED.
   Shipped as pak update (467KB->136KB).
   2026-06-11 round 2 (3 user-reported items):
   (A) Package-logs picker GUI crash: "ShowDialog ... [Windows.Media.Brushes]::White is not a valid value
       for TextElement.Foreground property on a setter". CAUSE: Show-LogPicker built the ListViewItem
       selection style PROGRAMMATICALLY and used the STATIC frozen [Windows.Media.Brushes]::White as a
       Setter value - rejected by WPF value-validation in the packed exe. (Show-MsiPropertiesDialog never
       hit this because it news up a fresh SolidColorBrush for every value.) FIX: rewrote Show-LogPicker to
       build from a XAML string via XamlReader (same mechanism as the main window) - declarative brush
       strings (#0E639C / White) are parsed by the XAML reader and never touch .NET Setter validation.
       Render-verified offline: selected row = white-on-blue readable, others light-on-dark. Audited the
       whole GUI: confirmed ZERO remaining [..Brushes]:: setter values; MSI dialog left as-is (already safe).
   (B) Update content with EMPTY content box still said "copied content": by design, blank box ->
       auto-find the package by name in Outgoing (or the just-built package) -> robocopy /MIR to prelive ->
       refresh DPs. So it really WAS copying (truthful message), just from an auto-resolved source. User
       sometimes updates prelive by hand and only wants a DP refresh. FIX: added ChkModRefreshOnly
       ("Content already in prelive - just refresh the DPs (don't copy)"). When ticked, the job calls
       Update-SccmContent -RefreshOnly (LocalPackagePath now optional) which SKIPS Copy-PackageToPrelive and
       only Update-CMDistributionPoint; if the app was never distributed it returns a clear "nothing to
       refresh - distribute first" instead of silently copying. Messages no longer claim "recopied" in
       refresh mode. Help text + checkbox tooltip explain both paths.
   (C) Audit of similar broken cases: the New-PSDrive bug was one instance of "-ErrorAction Stop promotes a
       benign warning to fatal". Reviewed ALL -ErrorAction Stop in Sccm.ps1 - every other one wraps a GENUINE
       operation (create/deploy/distribute/copy/WMI) with its own try/catch + clear message or fallback, so
       no other false-fatal cases. Intune is Graph-HTTP (no console-version warnings); not affected.
   Shipped as pak update (456KB->133KB). Parse clean, Test-Build PASSED.
   2026-06-11 "failed to connect to SCCM site" on Show members (user-reported) - ROOT CAUSE NOT connectivity:
   - Log showed: New-PSDrive G08 failed: "A new version of the console is available (5.2509.1036.1200).
     Cmdlets may not function... may corrupt your site's configuration if a different version than your site."
     The CMSite provider runs a console-vs-site VERSION CHECK on drive creation; after a site upgrade it
     emits this WARNING, and our New-PSDrive used -ErrorAction Stop -> warning promoted to terminating error
     -> Connect-Sccm returned $false -> every SCCM action reported "failed to connect". (Connection is NOT
     creation-dependent - each action connects fresh; this hit ALL actions equally.)
   - FIX (Connect-Sccm): create the drive with -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
     -ErrorVariable, then VERIFY via Get-PSDrive; only a genuinely-missing drive (wrong server/no rights) is
     a real failure (its actual error surfaced). Benign version notice logged as a Warning and ignored.
     Bundled console module manifest = 5.2509.1036.1200 (matches the notice) - mismatch is a minor build/rev;
     refresh the bundled ConfigurationManagerPrelive console copy from a current admin console when convenient.
   - Shipped as pak update (454KB->132KB). Parse clean, Test-Build PASSED. Needs the user's live re-test of
     Show members to confirm the drive now mounts past the warning.
   2026-06-10 Troubleshoot upgrades (user ideas - both were NOT yet handled, now built):
   - PACKAGE-LOG PICKER: BtnLogPackage ("Package logs...") -> Get-SccmPsadtLogList enumerates
     \\machine\c$\ProgramData\VWG\Logs recursively, filtered by the package's VENDOR or APP token (covers
     PSADT install/uninstall/repair + MSI + EXE logs), newest-first top 50 -> Show-LogPicker dialog
     (ListView: Log file/Modified/KB/Subfolder, dark theme, double-click=open, selection style fixed -
     default highlight was light-on-light, VISUALLY render-verified) -> Copy-SccmClientLogFile fetches the
     chosen log to WorkRoot\Downloads\<machine> and opens in CMTrace (+ known-error auto-scan appended).
     New job actions loglist/getlogfile; completion handler chains picker -> fetch.
   - SMART INSTALL STATE: Get-SccmInstallState now reads CCM_Application.EvaluationState + PercentComplete:
     ES 4 (or 0<pct<100) -> "INSTALLING/UNINSTALLING NOW (n% complete)" (verb follows the chosen collection);
     ES 3 -> "enforcement PENDING in Software Center (queued)"; in-progress suppresses the MISMATCH verdict
     ("wait for it to finish, then re-check"). REBOOT: CCM_ClientUtilities.DetermineIfRebootPending
     (client-wide = what Software Center shows as Restart required) -> appends "+ REBOOT REQUIRED".
     Repair reflects install-state as before. ErrorCode explanation kept.
   - Shipped as pak update #2 (452KB merged -> 131KB pak); ship exe re-smoke-tested OK. Live caveats: the
     EvaluationState mapping (3=pending/4=running) and DetermineIfRebootPending shape need one live check.
   2026-06-10 custom icon: generated programmatically (GDI+ -> multi-res PNG-compressed .ico 16/24/32/48/64/
   128/256): dark rounded square, isometric blue package cube, white up-arrow (deploy) on the right face,
   checklist bars on the left face; small sizes simplify to the plain cube. VISUALLY verified via preview
   sheet. User's original icon kept as Lib\PackageBuilder.user.ico. Exe RECOMPILED with the new icon (icon
   bakes at compile time), ship copy updated (exe+ico), ship exe re-smoke-tested OK. (Gotcha hit: 'LP' as a
   function name collides with the lp->Out-Printer alias.)
   NEXT (per user plan): move SCCM create+manage to a dedicated step; then C Testing (add machines to INSTALL/UNINSTALL
   colls + run machine policy), D Troubleshoot (pull AppDiscovery/AppEnforce logs -> CMTrace), E Dev->Test/UAT move.
   STILL OPEN (user testing): confirm de icon now renders; large-file Intune upload end-to-end.
   REMAINING (later): SCCM other tabs (add devices to a collection; download package logs -> CMTrace); Intune
   update content/icon/detection buttons (functions exist); portable launcher.
6. Portable launcher: thin PackageBuilder.exe (PS2EXE/WinForms shim) dot-sources + starts tool;
   team copies one folder + Lib\ and double-clicks; scripts stay editable for maintainer; unblock-load so
   copied DLLs work. BUILD LAST — once features are stable (avoids re-extracting the exe per change).
7. Golden tests — add real-package goldens (MSI, EXE, loose, 3-part version).

DONE 2026-06-06 (session 6 — source dump, multi-args, icons, snippets):
- Source copy = DUMP AS-IS: Copy-PayloadTree now copies the whole source folder verbatim (structure
  preserved), filtering by FOLDER name only (skip Documents/Icons folders) - no longer by file type, so
  license/info .txt, .ini, .varfile etc. all land in Files\ (fixed the "licenseinfo folder missing" bug).
  Manual mode copies ONLY the picked files.
- Multiple installers categorised correctly: Step 2 shows type 'Multiple' (not the first ext) for >1
  installers incl. manual selection; per-installer arg rows (Build-MultiArgRows) - each EXE gets install/
  uninstall arg boxes persisted to $State.InstallerArgs (by full path), MSIs show "uses its MST". Wired
  into Build-Step3Script Multiple branch (EXE args flow into the generated commands).
- Icons more robust: Resolve-Source also checks a sibling Icons folder and falls back to any *.ico under
  the root; the assembler extracts an icon from an EXE in Files\ if the Icons folder is still empty.
- Snippets now file-driven: snippets.json copied into the tool; Snippets.ps1 loads it (categories ->
  subcategories -> snippets). Step-3 LEFT panel rebuilt: JUMP TO SECTION (top) + SNIPPETS (category combo
  + list + Insert; double-click inserts). Inline snippet hashtable removed. Step rail shrunk (190->132,
  two-line title) to give the editor more width.
DONE 2026-06-06 (session 7 — snippet drawer, MSI props/MST, ico->png):
- Snippets un-compressed: a collapsible "Snippets" DRAWER below the editor (Expander) with a category
  dropdown + search box + list (left) and a monospace PREVIEW pane (right) + Insert button - matches the
  reference layout. Jump-to-section restored to its own comfortable left panel (170). Snippets still load
  from snippets.json (Snippets.ps1; search wired).
- MSI properties / MST: the remove-shortcut/Run-key checkboxes are HIDDEN and now default ON - the MST
  strips desktop shortcut / Run keys for EVERY MSI WHEN PRESENT (Remove-MsiTableRows only acts if the rows
  exist). Added a per-MSI "Extra MSI properties" box (KEY=VALUE; ... ) for single AND multiple installers
  (like the EXE args box); ConvertTo-MsiPropHashtable parses it, merged over Get-StandardMstProperties and
  fed to Build-Mst per MSI (New-Package -MsiPropsMap). MST is thus enabled for multiple too.
  *** Default: desktop shortcut + Run keys are REMOVED. Two independent Step-2 toggles let the user KEEP
  them per package: "Keep desktop shortcut" and "Keep Run key (32 and 64-bit)" (shown whenever the package
  has any MSI; unchecked = remove). Run32/Run64 move together via the single Run-key toggle. ***
- Icons robust + ico->png: Copy-PackageIcons copies .ico/.png from the source Icons folder (found via
  IconsPath, a sibling Icons, or any *.ico), generates a .png from any lone .ico (Convert-IcoToPng, medium
  quality - closest 256 frame, longest side capped 256, HighQualityBicubic), and falls back to extracting
  from an EXE in Files\. Validated: ico-only source -> package Icons\ has both app.ico + app.png.
DONE 2026-06-06 (session 8 — copy model + relative paths + UI wording):
- Files now MIRRORS the source: Resolve-Source exposes PayloadRoot (deepest installer folder for structured,
  else scanned root). Copy-ResolvedSource dumps PayloadRoot into Files\ preserving structure - structured
  source = copy EVERYTHING (Copy-PayloadTree -ExcludeDocIcon:$false); scan/loose = differentiation (skip only
  Documents/Icons folders). license/info .txt + nested folders are kept. Manual mode still copies only the
  picked files (flat).
- Install-command paths now reflect the ACTUAL location: Get-RelativePath makes each installer path relative
  to PayloadRoot, so an MSI/EXE in a subfolder renders as $($adtSession.DirFiles)\sub\App.msi with a matching
  -Transform $($adtSession.DirFiles)\sub\App.mst (Get-MsiCommandSet defaults MST via ChangeExtension, keeping
  the subfolder). The assembler builds each MSI's MST in its own subfolder (recursive). Manual = flat names.
- MST flags: the two Keep toggles (desktop shortcut / Run key) are ONE choice applied to ALL MSIs in the
  package (labels clarified). Extra-MSI-properties box reworded to "one per line, e.g. ALLUSERS=1" and made
  multi-line (single + per-MSI in Multiple).
- Icons: a .png is only generated from a .ico when NO .png already exists (existing png left as-is).
DONE 2026-06-06 (session 9 - per-MSI flags, predecessor opt-out, fuzzy compare, single source button):
- Predecessor uninstall block is a FULL user choice. Build-PredecessorScript: $AddUninstallPrevious=$false ->
  NOTHING inserted (no preserved blocks, no generated one, no header). GUI Step-1 checkbox "Add predecessor
  uninstall block" (shown only with a predecessor); its DEFAULT = whether the predecessor ALREADY has an
  uninstall block (Find-ExistingUninstallBlock on the predecessor PreInstall) - ON if present, OFF (ask) if not.
  Passed into the build; Invalidate-From 3 on change. (Param default stays $true for non-GUI callers/tests.)
- Per-MSI MST cleanup: Keep desktop shortcut / Keep Run key are now PER MSI (single MSI = its own pair in
  Step 2; each MSI row in Multiple has its own pair). $State.MsiFlags[FullName] -> Create builds
  MsiFlagsMap[name]=@{Shortcut=-not KeepShortcut; Run=-not KeepRunKey} -> New-Package -MsiFlagsMap applies
  each MSI's own flags in the MST loop (falls back to package defaults).
- Get-SourceWarning: compares AFTER version-bumping the predecessor name, then FUZZY (letters-only,
  substring-tolerant) - a pure version change never warns; a genuinely different name/type does.
- Source buttons consolidated: "Browse source" removed; Step 1 = "Find predecessor" + "Fetch source" +
  "Add installer(s) / source". Add-ManualInstallers now treats the installer's PARENT folder as the source
  (PayloadRoot=common parent), dumps that folder into Files\ (structure preserved, Documents/Icons folders
  skipped), detects Icons/Docs under it, and makes install paths relative to it. Validated end-to-end.
FIXES 2026-06-06 (session 9b):
- DeployAppScriptVersion (toolkit version, e.g. 4.1.8) is preserved from OUR template during predecessor
  reuse - the predecessor's older value (4.1.7) no longer leaks in via the $adtSession block swap. Captured
  from $Template before the swap and restored with Set-SessionField. Validated 4.1.7 pred -> 4.1.8 out.
- Predecessor-uninstall checkbox now refreshes immediately on predecessor selection (BtnPred sets its
  Visibility + IsChecked directly; hidden again when no predecessor found) - previously only updated on
  Step-1 re-navigation, so it appeared missing.
- Confirmed (no change needed): a vendor/existing MST is MERGED (ApplyTransform then property merge in
  Build-Mst via -ExistingMst from Find-VendorMst), never regenerated defaults-only.
Cleanup backlog: dedupe Resolve-Source DocItems (nested Documents\Documents); real-MSI end-to-end validation;
verify GUI dynamic per-MSI rows + predecessor checkbox + single source button on a real run.

## 10. Principles
Surgical over rewrites; working over polished; play back bug understanding before fixing; ask
before guessing. No global version bump without boundaries; uninstall block in its own lane;
never parse multiple ProductCodes in an uninstall body. Validate on real v3/v4. Keep maintainer
access open; hide complexity from the team via the exe, not obfuscation.
