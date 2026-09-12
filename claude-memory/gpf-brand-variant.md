---
name: gpf-brand-variant
description: "GPF team variant of Package Builder - SEPARATE tool copy at Downloads\\GPF-PackageBuilder (files\\ stays MTB-only/untouched); GPF serves 3 target brands INA=Audi, VWG=Group, G1V=VW"
metadata: 
  node_type: memory
  type: project
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

Second team = **GPF** (VW ITS GPF team, per their ModulePack Request form). NOT "the AUDI team" - GPF packages for THREE target brands: **INA=Audi, VWG=Group package, G1V=VW** (outgoing folder prefix, user-selected per package; AppFullName inside the script stays UNPREFIXED). USER RULES (2026-07-08/10): the GPF tool lives in a **SEPARATE folder** `C:\Users\AW140\Downloads\GPF-PackageBuilder\` - `Downloads\files` stays MTB-ONLY and untouched (all brand plumbing was REVERTED out of files\ back to r180 state, verified ALL TESTS PASS). Scope: predecessor reuse + fresh creation only, NO SCCM/Intune (ConfigurationManagerPrelive/MSAL/IntuneWinAppUtil deleted from the GPF copy; ~30 MB total). AES number (from `AES-1-...` Incoming ticket folder) replaces RITM -> fills OrderNumber/$VWG_OrderNumber. Predecessor ALWAYS from the request's `Predecessor\` subfolder (they have NO live share access; Outgoing fallback ok; never copied to output). Source fetching manual; package-name matching must work with or without the AES prefix.

GPF copy state (2026-07-10): **ALL TESTS PASSED** (full MTB engine suite + GPF corpus block), pak GPF-2026-07-07.r1 packed 410 KB. Contains: BrandGPF.ps1 (Find-GpfRequestFolder/Resolve-GpfRequest/Find-GpfPredecessor/Get-GpfPrefixChoices/Split-GpfRequestName), PSADT_Template_GPF (their 4.1.5 wrapper + our standard markers injected; adopted their authored deploymentType-default guard), brand-gated conversion (MtbMappings/VwgVarRename/RegWowHardcode/LogPathMain OFF via settings Brand.Convert; GPF var maps dirFiles/dirSupportFiles/scriptDirectory->adtSession.*, configToolkitLogDir->adtConfig.Toolkit.LogPath), Get-FieldLinePrefix (fills BOTH line shapes: MTB bare `Field =` and GPF `[type] $Global:VWG_Field =`), SoftIdent GPF format `[DisplayVersion]=x` bump, Set-ProcToBlockDefault generalized (GPF copy only), tab hiding (Integration/Testing/Dev->Test collapsed), prefix picker (CmbOutPrefix -> NewPkg.OutPrefix -> `<Prefix>_<FullName>` output folder), AES label. settings.json: Brand=GPF block + local OtherBrand paths. Test-Build in GPF copy sets `$script:Settings=@{Brand=@{TemplateRoot='PSADT_Template_GPF'}}` (template for fixtures, MTB-default flags) + 16 GPF corpus asserts vs the real 6-app v3->v4 pair corpus in `Downloads\OtherBrand\{Incoming,Outgoing,Wrappers}`.

Corpus facts that drive the design (all verified): Incoming = `AES-1-0XXXXX-A <identity>` (identity underscore-form or free text); subfolders vary (Sources\Files[+SupportFiles|'Support Files']| raw folder, Predecessor\ (both cases, mangled names like `2503_0002`), Icons\ or root icon.png, Docs_EQS/Documents/Mails/'Shortcut Behavior', ModulePack Request xlsx = parseable form). Their authored v4 packages KEPT the v3-style BEGIN/END markers (standard parser extracts them; MARK-set fallback exists for raw-template-authored ones). Their v4 keeps VWG_* alive as $Global: bridge; custom fns (Set/Remove-Branding, Set-Reboot, INI-*, fonts...) identical v3<->v4; $VWG_CurrentRegWow defined in their v4 ext.

**GPF PORTABLE** = `C:\Users\AW140\Downloads\GPF_PackageBuilder\` (underscore; mirrors the MTB portable Downloads\PackageBuilder): loader exe (the 55 KB one!) + GPF pak + settings/snippets/KB.Recommend + PsExec + `Lib\{AvalonEdit,ico,PSADT_Template_GPF}` (~25 MB). Launch-verified: window title "build GPF-2026-07-07.r1". TRAP: the DEV folders carry the OLD 991 KB self-contained exe (07-03, r158 baked in, IGNORES the pak) - the real team loader is the 55 KB exe from the portable/share; always ship THAT one. files\ keeps its old 991 KB exe untouched (original state).

**Step-1 wiring DONE (2026-07-10, ALL TESTS PASSED + launch-verified):** BtnFetch (Brand=GPF) -> Find-GpfRequestFolder (typed structured name matches free-text folders via Vendor+App key fallback, score>=50) -> Resolve-GpfRequest -> AES auto-fills TxtRitm (only if empty), source = Sources\ parent (pre-shaped) | PayloadRoot (raw) | request root; after Set-ResolvedSource the request's Icons\ fills empty Resolved.IconsPath and request DocItems (forms/mails/'Shortcut Behavior') MERGE into Resolved.DocItems (deduped). BtnPred (Brand=GPF) -> Get-GpfPredecessorCandidates: request Predecessor\ pinned FIRST (authoritative), then Outgoing scan tolerant of brand prefix + mangled rev via Get-GpfPredecessorPackageName ('INA_..._2503_0002_MUL' -> 'Microsoft_MECMConsole_x86_2503-0002_MUL'); candidate .Name = NORMALISED identity, .FullName = real path -> Read-PredecessorModel verified live on the 7Zip (v3 MSI 25.01) + mangled MECM (v3 EXE 2503) request predecessors. State.GpfRequest in StepOwns[1].

**Lib layout (2026-07-10, user rule):** ALL modules/templates live under lib\ in BOTH dev folders now - files\lib\{PSADT_Template, ConfigurationManagerPrelive, ...}, GPF\lib\PSADT_Template_GPF. All resolvers already supported both layouts; only Test-Build template-path lookups gained a Lib-first fallback. Both suites ALL PASS after the move.

**DEEP CORPUS VALIDATION DONE (2026-07-10, TOTAL HARD FAILS: 0 across all 6 pairs)** vs their real authored v4 golds:
identity/wrapper/custom-vars-once/conversion hygiene/swaps/template regions all pass. CORRECTION: their authored v4 use
**## MARK: style ONLY** (no BEGIN/END markers - earlier "kept standard markers" claim was a test-labelling bug; the MARK
set IS the primary reader for their authored v4). Their golds define $LogPathMain/$setuplogName as CUSTOM VARIABLES once
at top (their template evaluates customs AFTER Open-ADTSession). Fixes from the sweep: SectionVarScope Convert flag
(GPF=false - Move-V4RuntimeVars scope-fix gated OFF; their customs stay once); SoftinstTyp/Portfv/AppAddInfo01-04 added
to Extract-SessionValues + fill list; SoftIdent WOW handling brand-gated on RegWowHardcode (GPF keeps NO WoW even x86 -
all 6 golds prove it) + '\ {GUID}' space collapse; MTB-format DisplayVersion bump matches GPF wrapper lines;
**Execute-MSI -Transform -> -Transforms added to the mapping** (REAL v4 bug: leftover -Transform throws; ALSO EXISTS IN
MTB files\ mappings - port with the queued MTB items). Parity gaps that remain are authors' per-release hand-additions
(new version-checks/uninstall PCs - the uninstall-previous generator covers those when enabled) + style (quotes,
explicit dirFiles, their custom log vars) - carried-pred content is faithful.

**2026-07-10 round 2 (ALL TESTS PASSED, pak repacked + portable refreshed):** ZIPPED predecessor support in
Resolve-GpfRequest (Predecessor\*.zip -> extract once to WorkPath PredCache -> inner package dir auto-found;
functional-tested); manual predecessor prompt in BtnPred (no candidates -> Yes/No -> FolderBrowserDialog -> becomes the
single candidate, non-parsing names warned); Create's "Build the script in Step 3" message now explains the REAL reason
(generation failed - first comment line shown; historic cause was the stale MTB pak missing the GPF template, fixed).

**2026-07-10 round 3 (user-reported, fixed + verified, pak 415KB portable refreshed):**
 - Duplicate predecessors: cause #1 path-based dedupe (same pkg from request + Outgoing shown twice); cause #2 the GPF
   copy INHERITED the MTB hardcoded secondary predecessor root (live share \\MNDEMUCFS120...CMLib_LIVE\Apps) via
   Get-PredecessorRoots -> 11 old VCRedis found. USER RULE: Get-GpfPredecessorCandidates now reads the request's
   Predecessor\ folder ONLY - no Outgoing/share scan ever; manual browse popup is the sole fallback. BtnPred also
   self-locates the request (Find-GpfRequestFolder) when clicked before Fetch.
 - Create "script could not be generated / Reason: Modified by AUDI AG...": the ScriptText -like '#*' failure heuristic
   false-positived because the GPF TEMPLATE legitimately STARTS with that '#' license line. Fix: failure = starts-with-#
   AND length < 500 (generator errors are one short comment; real scripts are tens of KB). Verified on the real VCRedis
   build (23.5KB, starts with '#', genFailed=False) + a real error line (True).

**2026-07-10 round 4 - share separation + fetching rules (ALL TESTS PASS, pak 416KB, portable refreshed):**
 - NO MTB SHARES anywhere in the GPF runtime: hardcoded 2nd live repo removed from Get-PredecessorRoots (settings-only);
   Core defaults -> OtherBrand local paths; Sccm defaults -> neutral placeholders (SiteCode XXX/localhost/C:\temp\
   GPF-SccmContent - NOT '' which broke a Join-Path in tests). Test-LiveShareDuplicate rides Get-PredecessorRoots ->
   local Outgoing only. Maintainer-only scripts (Analyze-KB/Release-Check/SourceAnalyzer/Test-Corpus) keep MTB param
   defaults (never auto-run).
 - Fetching rules (user): NO predecessor documents ever; ICONS - current request wins ONLY when Icons has BOTH .ico AND
   .png, else predecessor icons fallback (brand-gated in the create block; MTB branch untouched); NESTED Files\Files ->
   descend to the INNER Files when the top has no installers (max 2 hops, note logged) so contents land directly in
   Content\Files; Vendor_Sources = payload FALLBACK when Sources has neither Files nor raw payload + ALWAYS searched
   (depth 3) for install-instruction docs (docx/doc/pdf/txt named install*instru/installation guide/how-to-install) ->
   the FILES join DocItems. All fixture-tested + real-corpus regression (7Zip no false descend).

**2026-07-10 round 5 - user's VCRedis-vs-gold findings, all fixed + verified (ALL TESTS PASS, pak 417KB, portable refreshed):**
 - UPDATED TEMPLATE adopted: user copied their latest wrapper (adds `$adtConfig  = Get-ADTConfig` after Open-ADTSession,
   L206) OVER our marker pack -> markers were WIPED; re-injected in place (scratchpad inject_gpf_markers.ps1, idempotent,
   checks '#\*=+ MAIN-INSTALLATION BEGIN' first) + portable template synced. LESSON: whenever they hand over a new
   template, run the injector - the assembler is dead without markers.
 - VWG_ProcToClose BRIDGE (`= $adtSession.AppProcessesToClose`) is now PRESERVED: fill loop writes AppProcessesToClose
   (authoritative; empty @() is valid) and only falls back to a direct ProcToClose fill when that field is absent (MTB
   template). ProcToBlock bridge (`= $VWG_ProcToClose`) also survives (Set-ProcToBlockDefault hasReal check skips it).
 - SoftIdent not-retargeted -> ALWAYS a review point now (Get-PredecessorReport): no NewPkg.ProductCode -> "carries
   PREDECESSOR PC/DisplayVersion, update after test install or snapshot"; pred PC still present despite a new PC ->
   "swap did not take".
 - Set-Reboot: Remove-GpfRebootPlaceholder (GPF-gated, end of Build-PredecessorScript) - a section carrying an ACTIVE
   `Set-Reboot` (e.g. if exit 3010 block) drops the template's commented placeholder pair ("##Handling for required
   reboot" + "#Set-Reboot") in THAT section only; sections without a handler keep the placeholder.

**2026-07-11 round 6 - SoftIdent house-syntax + snapshot version + Files\Files assembly fix (ALL TESTS PASS, pak 419KB, portable refreshed):**
 - GPF KEEPS `$($VWG_CurrentRegWOW)` in SoftIdent (their extensions define it; round-4 token-stripping REVERTED): pred
   values carried VERBATIM double-quoted; Normalize-SoftIdent = no-op when RegWowHardcode off; NEW values rendered via
   **Format-BrandSoftIdent** (GPF: token replaces any WoW/inserted after SOFTWARE\ even x64, double-quoted, no double-
   insert; MTB: single-quoted hardcoded WoW). DisplayVersion-bump + PC-swap regexes now QUOTE-AGNOSTIC.
 - Snapshot -> SoftIdent for BOTH brands, pred+fresh: Merge-SnapshotDeltas SoftIdent match uses Get-FieldLinePrefix (was
   MTB-shaped -> NEVER fired on the GPF wrapper line - the miss the user saw), isExpr ignores the GPF token, write via
   Format-BrandSoftIdent. **Full registry DisplayVersion ALWAYS wins**: snapshot dialog result + State.
   SnapshotDisplayVersion (StepOwns[2]/defaults) -> Get-AutoSoftIdent -DisplayVersion (falls back to pkg version).
 - Predecessor docs: BtnFetch drops ANY DocItems under a \Predecessor\ path (resolver doc-scan was catching the request's
   embedded Predecessor docs).
 - Files\Files DEMO FAILURE root-caused: the resolver-side descend wasn't enough - fixed at ASSEMBLY: New-Package calls
   **Invoke-NestedFilesHoist** (Assemble.ps1, tested: hoists inner Files contents into Content\Files, no-overwrite,
   removes emptied folder, idempotent, suite-covered) + Build-Step3Script strips a leading 'Files\' from installer rel
   paths so commands match the hoisted layout.
 - MTB PORT PENDING for these round-6 items: Get-AutoSoftIdent -DisplayVersion + SnapshotDisplayVersion plumbing +
   quote-agnostic bump regexes (files\ has the same code); MTB needs NO token/no hoist. Plus the 5 earlier MTB items
   (done in sources, NOT yet packed - r181 pending).

**2026-07-11 round 7 - user's live-run findings (ALL TESTS PASS, pak 420KB; portable pak AND settings refreshed):**
 - ROOT CAUSE of several "regressions": the PORTABLE's settings.json was STALE (created round 3, never re-synced -
   missing SectionVarScope:false) -> scope-move ran in their live tool. LESSON: every portable refresh must copy
   pak AND settings.json when settings changed. Belt-and-braces added: Move-V4RuntimeVars NEVER runs when Brand
   Name=GPF, regardless of the flag.
 - InstallTitle now filled as 'Vendor AppName Version' for GPF (both fresh + reuse identity blocks; MTB untouched -
   PSADT composes it at runtime there).
 - FreeSpace: engine-side carry was fine (corpus-proven '500'); live miss = stale pak. Robustness added: Extract-
   SessionValues now also captures BARE-NUMBER v3 values (FreeSpace = 500 unquoted) and quotes them.
 - [string]$VWG_SoftIdent custom-variable DROP is MTB-ONLY now (brand-gated): GPF preds legitimately redefine it with
   the runtime WoW token in CUSTOM VARIABLES - kept; the PC/version swap regexes are line-prefix based so they update
   that line too.
 - Stray "Uninstall\ {GUID}" space: collapse re-added token-safely (Extract GPF branch + Format-BrandSoftIdent).
 - SoftIdent review items now cover ALL cases: EXE w/o snapshot -> "check + correct after test install"; swap didn't
   take -> manual fix; swap DID take -> "verify PC/product NAME/DisplayVersion match the real uninstall entry".

**2026-07-11 round 8 - live VCRedis retest failures, ALL root-caused vs the REAL request predecessor (ALL TESTS PASS,
pak 421KB, portable pak+settings refreshed). SYSTEMIC LESSON: every MTB-shaped "^Field =" regex is INVISIBLE on GPF
wrapper lines - always use Get-FieldLinePrefix; and ALWAYS test against the request predecessor, not the Outgoing copy
(they differ: plain $VWG_ vars, tabs, TWO SoftIdent decls, custom token line):**
 - FreeSpace 150-overwrite: Merge-SnapshotDeltas READ was MTB-shaped -> saw 0 on the GPF wrapper line -> payload floor
   (150) "raised" over pred's 500. Read now prefix-based. Proc-union reads prefix-based too; GPF targets
   AppProcessesToClose; a bridge RHS (starts with $) is never written.
 - EXE-no-snapshot review item: Get-ScriptReviewFindings finding #1 regex was MTB-shaped (+ fresh finding #4) -> now
   prefix-based + quote-agnostic; wording says check PC/name/DisplayVersion after test install.
 - [string]$VWG_SoftIdent custom line was killed by THREE stacked causes: (1) Mappings.ps1 LAYER-1b removal (now
   brand-gated), (2) Read-PredecessorModel's unconditional Convert-VWGRegWOW body-hardcode (now gated on
   RegWowHardcode - GPF keeps the token LIVE), (3) **Set-SessionValue was a GLOBAL Replace** - the session fill
   stamped the extracted wrapper value over the SAME-NAMED custom line; now FIRST-occurrence-only ($re.Replace(...,1)).
 - Missing uninstall ending log: Strip-Boilerplate's Start/is-successful log strips are MTB-only now (GPF keeps the
   pred's own log lines verbatim - their golds carry them).
 - Fresh + reuse NewPkg.SoftIdent writes go through Format-BrandSoftIdent (GPF token syntax, double-quoted).

**2026-07-11 MTB r181 (files\) - PACKED + DEPLOYED (the earlier r180->source-only changes had NEVER been packed, so
the team's copied pak was stale = why "browse fallback not implemented"). r181 bundles ALL held MTB work: the 5 items
(manual predecessor Browse prompt, ConfigMgr import-skip when console installed, $setuplogfolder removal, screenshot
2nd-shot timing, -Transforms map), DisplayVersion-wins plumbing, AND NEW: FUZZY predecessor matching. Get-Predecessor
Candidates now scores instead of exact-prefix-only: exact vendor+app=100; vendor/name-split-differs=92; same vendor +
similar app (substring or Levenshtein>=0.60)=Close; vendor-prefix + combined Levenshtein>=0.70=Close. Get-NameSimilarity
(two-row Levenshtein - NOT 2D array, PS5.1 parser chokes on 2D indexing in method calls). Picker shows [MatchNote];
Browse dialog pre-seeds SelectedPath to the live share (UNC ok). ALL TESTS PASS incl. 7 new fuzzy asserts. LESSON:
after MTB source edits ALWAYS bump BuildStamp + Pack-Engine + refresh Downloads\PackageBuilder portable, else the team
runs stale.

**2026-07-11 MTB r183 (files\) - PSADT v3 Intune support (packed + DEPLOYED to share+portable, ALL TESTS PASS).**
Intune was v4-only. Now Intune.ps1: Resolve-IntuneContentRoot finds the PSADT launcher under Content (Deploy-
Application.exe/.ps1=v3, Invoke-AppDeployToolkit.exe/.ps1=v4) with -Recurse -Depth 3, SHALLOWEST wins - handles a
NESTED content root like Content\MUL_x64_0001 (real case: Toshiba_BDRV...\Content\MUL_x64_0001) and wraps THAT
subfolder (IntuneWinAppUtil -c points there). No launcher at all -> returns null -> caller returns Ok=$false;
NoPsadt=$true "integrate manually". v3: Initialize-IntuneV3Content copies Lib\IntuneUtilitiesForPSADTv3\* (ServiceUI.exe
+ Deploy-Application.exe + .config; skips IntuneWinAppUtil.exe defensively) INTO the content root; -s=Deploy-
Application.exe; install/uninstall = 'ServiceUI.exe -process:explorer.exe Deploy-Application.exe Install/Uninstall'
(config keys SetupFileV3/InstallCmdV3/UninstallCmdV3/V3UtilitiesPath; Fields override still wins). Both publish paths
covered: Publish-ToIntune (sets commands) + Update-IntuneContent (re-wrap only, keeps existing commands). New-
IntuneWinPackage gained -SetupFile. KEY DEPLOY NOTE: the v3 utilities live in Lib\IntuneUtilitiesForPSADTv3 on DISK
(NOT in the pak) - synced ServiceUI.exe+Deploy-Application.exe+.config to the SHARE Lib and the local portable Lib
alongside the pak. Share pak backup: PackageBuilder.bak_20260714_083924.pak.

**2026-07-11 MTB r184 (files\) - SCCM vs Intune command clarity + v3 bug fix (deployed to share+portable, ALL TESTS PASS).**
The Publish tab's install/uninstall command fields (TxtPubInstall/TxtPubUninstall) are SHARED by SCCM + Intune. For v4
both platforms use the same command; for v3 they DIFFER (SCCM = Deploy-Application.exe direct via
Get-SccmFieldsFromPackage; Intune = ServiceUI-wrapped). r183 BUG: Publish-ToIntune used `if Fields.InstallCmd {..}` so
the shared SCCM v3 field OVERRODE the ServiceUI default -> Intune got the wrong (non-ServiceUI) command. FIX: new
ConvertTo-IntuneV3Command wraps the base command with 'ServiceUI.exe -process:explorer.exe <cmd>' (no double-wrap;
preserves user switches); Publish-ToIntune now always wraps for v3. CLARITY: new GUI note LblPubCmdNote (under the
command grid) shows ONLY for v3 packages: "commands above are the SCCM form; Create in Intune auto-wraps with
ServiceUI...". Populated in Set-PublishFields from base.PsadtVersion; hidden for v4. Backup:
PackageBuilder.bak_20260714_085149.pak.

**2026-07-11 MTB r186 (files\) - keep .intunewin + prepared content locally (deployed to share+portable, ALL TESTS PASS).**
Was: New-IntuneWinPackage wrote the .intunewin to a RANDOM temp (Get-WorkPath IntuneWin\<guid>) and both Publish-ToIntune
+ Update-IntuneContent DELETED that folder after upload -> the .intunewin (and staged content) were lost. Now:
New-IntuneWinPackage output = STABLE local per-package folder Get-WorkPath 'IntuneWin\<FullName>' (only a stale
*.intunewin is cleared; folder kept). If the content root is a NETWORK path (Test-NetworkPath), it's copied local into
<out>\Content first (so IntuneWinAppUtil is reliable AND the prepared content - incl. staged v3 ServiceUI - persists).
Both callers NO LONGER delete after upload; result now carries IntuneWinPath + ".intunewin kept at: <path>" in the
Message. Verified end-to-end: real wrap lands at C:\temp\PackageBuilder\IntuneWin\<FullName>\<FullName>.intunewin and
persists. Backup: PackageBuilder.bak_20260714_101048.pak. (NOTE: a literal 'Remove-Item ... -Parent' string in a
verification -match tripped the Bash sandbox - avoid that token in checks.)

**2026-07-14 MTB r187 (files\) - ALWAYS keep the wrapped content + manifest for Intune troubleshooting (deployed, ALL TESTS PASS).**
r186 only kept content local for NETWORK sources; local builds wrapped in place so the user saw only the .intunewin.
Now New-IntuneWinPackage ALWAYS snapshots the exact content into <out>\Content (per-item -LiteralPath copy - a "\*"
LiteralPath copies NOTHING, and it's bracket-safe for package names with []), stages v3 ServiceUI into THAT COPY (source
package untouched now - was modified in place before), wraps the copy, and writes _IntuneWin-manifest.txt (package /
generation / source root / setup file / exact IntuneWinAppUtil command line / full recursive content tree = "exactly
what shipped"). Logs the full `IntuneWinAppUtil.exe -c ... -s ... -o ... -q` command + top-level file list. New-
IntuneWinPackage gained -Generation; both callers pass it and no longer stage v3 themselves. Output per package:
C:\temp\PackageBuilder\IntuneWin\<FullName>\ { <FullName>.intunewin, Content\, _IntuneWin-manifest.txt }. Backup:
PackageBuilder.bak_20260714_103953.pak.

**2026-07-14 MTB r188 (files\) - ROOT CAUSE of the user's failed v3 Intune install: ServiceUI never made it into the
.intunewin (manifest tree confirmed it missing). The self-stage's Ensure-PublishModulesStaged (Core.ps1) mirrors
ConfigMgr/MSAL/IntuneWinAppUtil share->local on first publish but NOT the new Lib\IntuneUtilitiesForPSADTv3 -> on a
run-from-share (self-staged %LOCALAPPDATA%) copy the v3 utils folder was absent -> Initialize-IntuneV3Content found no
source -> wrapped without ServiceUI -> the `.\ServiceUI.exe...` command had nothing to run -> install failed. FIX:
(1) added 'Lib\IntuneUtilitiesForPSADTv3' to the Ensure mirror list; (2) belt-and-braces share fallback in Initialize-
IntuneV3Content (Get-StageSource / $env:PB_SHAREROOT -> Join V3UtilitiesPath) so ServiceUI is found even before the
mirror runs. Both tested. Deployed r188 + re-synced share Lib\IntuneUtilitiesForPSADTv3 (has ServiceUI). Backup:
PackageBuilder.bak_20260714_104925.pak. USER ACTION: relaunch (gets r188) + REBUILD the Toshiba .intunewin (its content
tree will now include ServiceUI.exe) then re-upload. This is exactly the win the keep-content+manifest feature (r187)
was for - the manifest tree surfaced the missing file.

**2026-07-14 MTB r189 (files\) - Intune "extra shield": uninstall-detection duplicate check (deployed, ALL TESTS PASS).**
Problem: the Intune dup guard (Find-IntuneApp) only matches by branding key (...\VWG\CM\<FullName>) + name, so an app
already in Intune WITHOUT our branding key (another team / out-of-band) - or a differently-NAMED copy - escapes, incl.
same-uninstall-string cases. NEW (Intune create only): after the branding check finds nothing, Find-IntuneUninstallMatches
scans win32 apps (pre-filtered to same displayVersion) and via the PURE Test-IntuneAppMatchesUninstall compares the
UNINSTALL DETECTION - keyPath (HKLM\...\Uninstall\{GUID|name}) + check32BitOn64System (32/64-bit) + detection VERSION
value (operator >=/= ignored) + ProductCode (rule or {GUID} in keyPath). Returns ALL matches (not first-and-stop - the
user hits >2 dupes), each with Lifecycle (Get-IntuneAppLifecycle parses the app notes JSON's "lifecycle":LIVE/RETIRED)
+ Branded flag; sorted LIVE-first then non-branded-first. Publish-ToIntune warns (reusing the AlreadyExists Y/N ->
ForceCreate prompt) ONLY when >=1 NON-branded match exists (branded ones listed for context - branding logic owns them);
lists every match with AppId + lifecycle + branding-key yes/no. Get-IntuneUninstallSignature builds the identity from
Fields (UninstallKey/Is32Bit/DetectVersion/ProductCode). Purely additive - existing fuzzy name+version+branding
unchanged. 11 Test-Build asserts (match/skip-branded/version/bitness/ProductCode/EXE-name-key/lifecycle-json). SCCM-create
equivalent NOT done (offered). Backup: PackageBuilder.bak_20260714_133551.pak.

**2026-07-14 MTB r190 (files\) - branding-key dup check ALSO lists ALL copies + lifecycle (deployed, ALL TESTS PASS).**
The FIRST-logic branding dup (Find-IntuneApp) returned only the newest single match, no lifecycle. Refactored: new
Get-IntuneBrandingMatches returns ALL branding-identity matches (exact .intunewin fileName OR ...\VWG\CM\<FullName>
key; deep-check now collects all, not first-and-stop), newest first; Find-IntuneApp = First-1 of it (back-compat).
Publish-ToIntune branding branch now lists every copy with AppId + lifecycle (Get-IntuneAppLifecycle from notes JSON) +
created date. Mock-Graph verified (use [pscustomobject] mocks NOT hashtables - Sort-Object -Property + .notes member
access differ on hashtables and give false test fails). Backup: PackageBuilder.bak_20260714_134526.pak. Both dup
shields (branding + uninstall-signature r189) now list ALL matches with lifecycle.

**2026-07-14 MTB r191 (files\) - editable 32-bit-on-64-bit checkbox in the Create/Publish fields (deployed, ALL TESTS PASS).**
The Create detection fields (Uninstall key/Detect version/ProductCode/2nd-detection combo) had NO 32-bit checkbox, so
check32BitOn64System (Intune) / SCCM "key is 32-bit on 64-bit" stayed whatever Get-SccmFieldsFromPackage auto-derived
from the SoftIdent WoW6432Node/arch - not correctable when SoftIdent format is unusual. Added ChkPub32Bit next to the
2nd-detection combo; Set-PublishFields populates it from base.Is32Bit (auto), Get-PublishFields overrides
$f.Is32Bit=[bool]$ChkPub32Bit.IsChecked -> flows to Get-IntuneDetectionRules check32BitOn64System AND SCCM detection.
Offscreen-render verified + flag flows into the rule (Is32Bit true/false -> check32BitOn64System true/false). The
Modify section already had ChkMod32Bit; this adds the equivalent to the CREATE flow. Backup:
PackageBuilder.bak_20260714_134836.pak.

**2026-07-14 MTB r192 (files\) - Intune duplicate check REWRITTEN to the user's order; fileName DROPPED (deployed, ALL TESTS PASS).**
CUBISCAN_QbitDB bug: two apps with the same branding key, only the latest shown - because the branding check was
fileName-GATED (only did the branding-key deep check when the .intunewin fileName matched nothing) AND the app list
wasn't paged. fileName is unreliable (upload-name dependent) - REMOVED entirely. New order (both Intune create shields):
(1) FUZZY appname + version candidates [Get-IntuneNameKey normalize: lowercase+strip-non-alnum, substring either way];
(2) branding KEY match \VWG\CM\<FullName> - just the key segment, value/operator ignored [Get-IntuneBrandingMatches,
no fileName, no ProductCode]; (3) if branding finds nothing -> uninstall-string OR ProductCode match
[Find-IntuneUninstallMatches, candidates now fuzzy-name+version]. Uninstall/registry match = compare keyPath + valueName
+ detectionValue(version) + check32BitOn64System (EVERYTHING except operator >=/= and datatype string/version);
ProductCode/GUID = match the GUID DIRECTLY (dedicated productCode rule OR {GUID} in keyPath, the latter still gated on
version+bitness since it's a registry detection). Get-IntuneWin32Apps follows @odata.nextLink (pagination). Both shields
list ALL matches + lifecycle (LIVE/RETIRED). Get-IntuneUninstallSignature gained ValueName='DisplayVersion'. Mock-Graph
verified (2 same-branding-key copies with DIFFERENT fileNames, one on page 2 -> both found; operator-ignore + valueName-
strict + GUID-direct). CAUGHT a regression in test: GUID-in-keyPath fallback must keep the version+bitness gate (a
registry detection is not GUID-alone). Backup: PackageBuilder.bak_20260714_141927.pak.

**2026-07-14 MTB r193 (files\) - branding dup catches a RENAMED copy (deployed, ALL TESTS PASS).**
Problem: an app whose displayName was later changed but keeps the SAME branding key was missed - the candidate filter
was fuzzy-appname only. KEY INSIGHT (fast, no full scan): the branding key ...\VWG\CM\<FullName> EMBEDS the version, so
any app carrying it was created with the SAME displayVersion (which IS in the free list response). Candidate filter for
BOTH Intune shields now = (displayVersion == our version) OR (fuzzy appname) - version is APPNAME-INDEPENDENT so a rename
is caught, and it's free (no extra GET). Version parsed from the FullName via Parse-PackageName. Shield changed from
name AND version to name OR version too (catches different-name-same-uninstall). Mock-verified: a copy with a totally
different displayName but same branding key + version is found (deep-checked 2 of 3, different-version app skipped).
Backup: PackageBuilder.bak_20260714_142850.pak. Same-version-AND-name double-edit is the only residual miss (rare).

**2026-07-14 MTB r194 (files\) - readable "already exists" dialog (deployed).** The duplicate-list prompt was a
[Windows.MessageBox] (wraps/cramps a multi-app list). Added Show-ConfirmTextDialog (modeled on Show-TextDialog: wide
880px, resizable, monospace, NoWrap + horizontal scroll) with Yes/No; the AlreadyExists handler uses it instead of the
MessageBox. Low-risk (new fn + one call swapped). Backup: PackageBuilder.bak_20260714_143740.pak.
REMOTE SCREENSHOTS (Invoke-RemoteShortcutShots, Screenshots.ps1): user reports it didn't work 2 days ago (no error given).
Complex remote flow (admin$ share \\m\c$\temp\PBShots + New-CimSession + Register-ScheduledTask as the interactive user,
LogonType Interactive, poll done.flag). Likely failure points: (1) need LOCAL ADMIN on target for admin$ + Task Scheduler
remoting/WinRM/DCOM (firewall); (2) logged-on-user detection blank for RDP (Win32_ComputerSystem.UserName null; quser
fallback locale-parsed 'Active|Aktiv'); (3) capturing a DISCONNECTED RDP session -> blank/black images (Windows can't
render an unattached desktop). WORKAROUND told to user: RDP to target + use the LOCAL "screenshot this machine" button; or
stay RDP-CONNECTED (locked ok, disconnected not) during capture. NOT fixed blind - need the tool's exact error Message.

**2026-07-14 MTB r195 (files\) - v3 SoftIdent 32-bit detection: read the DOUBLE-quoted custom-vars override (deployed, ALL TESTS PASS).**
Get-SccmFieldsFromPackage (Sccm.ps1) $get reader matched SINGLE quotes only, so the v3 SECOND $VWG_SoftIdent - defined
in CUSTOM VARIABLES as DOUBLE-quoted "HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)Microsoft\...\Qbit-DB [DisplayVersion=...]" -
was NEVER read -> the $($VWG_CurrentRegWOW) 32-bit token never seen -> Is32Bit fell back to arch. v4 works because its
SoftIdent is single-quoted with a literal WoW6432Node. FIX: dedicated SoftIdent read matching BOTH quote styles, LAST
def wins ($softHadWowToken flag); token-present -> Is32Bit=TRUE; and the token-resolution TrimEnd('\') bug (produced
'WoW6432NodeMicrosoft' - missing backslash) fixed to keep/normalize the hive-segment backslash + collapse doubles.
Is32Bit = (WoW6432Node key OR token) ? true : (clean key ? false : arch x86). Feeds the ChkPub32Bit checkbox (still
user-overridable, r191). Tested: user's exact CUBISCAN_QbitDB x86 double-quoted-token case -> Is32Bit true + clean key
SOFTWARE\Microsoft\...\Qbit-DB; v4 x64 native -> false; v4 x86 literal WoW -> true. Backup: PackageBuilder.bak_20260714_144740.pak.
(remote screenshots: user said DROP for now - not touched.)

**2026-07-14 MTB r196 (files\) - field reader handles BOTH quote styles for ALL fields (deployed, ALL TESTS PASS).**
r195 fixed SoftIdent double-quote reading only; user: "our tool should handle both quotes" generally. Get-SccmFields
FromPackage $get now matches ('..'|".."), last-def-wins - so vendor/app/arch/version/rev/lang and SoftIdent all read
from either quote style (removed the separate SoftIdent-specific $sd block). Also both-quotes for the $VWG_CurrentRegWOW
definition read + the MAIN-UNINSTALLATION -ProductCode extraction. Tested: all-fields-double-quoted v3 pkg + mixed quotes
+ double-quoted -ProductCode all read correctly; token->32-bit + clean key preserved. Backup: PackageBuilder.bak_20260714_145117.pak.

**2026-07-14 MTB r197 (files\) - complete v3->v4 param renames for Execute-MSI/Process (deployed, ALL TESTS PASS).**
User found -AddParameters not converted. VERIFIED against the bundled PSADT v4 compat wrappers' [Alias()] decls
(lib\PSADT_Template\Content\PSAppDeployToolkit\Frontend\v3\AppDeployToolkit\AppDeployToolkitMain.ps1 - the authoritative
old->new map, NOT guessed). Execute-MSI->Start-ADTMsiProcess Params now: Path->FilePath, AddParameters->
AdditionalArgumentList, Parameters/Arguments->ArgumentList, SecureParameters->SecureArgumentList, Transform->Transforms,
Patch->Patches, LogName->LogFileName ([ordered] so AddParameters runs before Parameters). Execute-Process/
ProcessAsUser->Start-ADTProcess(AsUser): +Arguments->ArgumentList, +SecureParameters->SecureArgumentList. Param-apply
regex is word-boundary safe: (?<!\w)-Param(?=[\s\)\]\};,]|$) so -Parameters doesn't corrupt -AddParameters, -Patch
doesn't hit -Patches. 9 Test-Build asserts. Backup: PackageBuilder.bak_20260714_145948.pak. (LESSON: for v3->v4 param
renames, the v3 compat wrapper Alias() lines in the bundled module ARE the source of truth.)

**2026-07-14 MTB r198 (files\) - icon-readiness gate DEPLOYED (share+portable, ALL TESTS PASS). Convert-IcoToPng was
System.Drawing.Icon.ToBitmap() which CHOKES on PNG-compressed .ico frames (e.g. PackageBuilder.ico) -> gate failed;
rewrote it WPF BitmapDecoder FIRST (handles PNG+BMP frames, largest) + System.Drawing fallback - fixes the gate AND
creation-time Copy-PackageIcons. Backup: PackageBuilder.bak_20260715_065913.pak.**
**2026-07-14 MTB icon-readiness gate (files\, code done + verified; r198 PACK/DEPLOY PENDING classifier outage).**
User: icon not converted/uploaded on Intune update-content when only .ico; ALWAYS convert .ico->.png + upload; for SCCM
too error if no .ico; VERIFY before integration/update + tell user to copy an .ico first; if .ico there just convert+keep.
NEW Confirm-PackageIconReady (Assemble.ps1, after Convert-IcoToPng): png present->ready; .ico only->Convert-IcoToPng to
a PERSISTED <base>.png (so ARP/SCCM .ico + Intune .png match, and Get-IconBase64 then finds the png)->ready; neither->
Ready=$false + message "copy an .ico into <Icons>". Wired as a BLOCKING pre-check in 3 GUI handlers: BtnCreateSccm,
BtnCreateIntune, BtnIntuneUpdateContent (shows MessageBox + returns if not ready). Package path: create=$script:State.
CreatedPath, intune update=$TxtIntuneContentSrc. SCCM update-content (BtnUpdateContent) NOT gated (it mirrors content,
doesn't re-set the icon). Test-Build block added (needs Lib\PackageBuilder.ico). PENDING when classifier back: full
Test-Build + pack r198 + deploy share+portable. NOTE: creation-time snapshot/ARP icon (Copy-PackageIcons + Resolve-
ArpIcon) already exists - the "get icon from snapshot during creation" is largely there; gate covers the publish side.

QUEUED MTB CHANGES (files\ - do AFTER user confirms; port carefully, files\ is at verified r180):
 1. Manual predecessor location prompt (same as GPF BtnPred fallback) - live share not always accessible.
 2. ConfigMgr console: when the CM console/module is ALREADY loaded/installed, Import-Module errors - skip import, proceed with integration (Sccm.ps1 Import path).
 3. [string]$setuplogfolder: do NOT carry forward in conversion; remove its declarations everywhere; usages -> our $LogPathMain format (check Convert-LogPathFormat + declaration-removal regexes; verify format first).
 4. Screenshot shortcuts timing: first shot on first window change; SECOND shot needs LONGER wait - take it after a bigger window change with a ~5s timer, then close (Screenshots.ps1 fixed-timing per screenshot-keep-it-simple memory).
 5. Port: Execute-MSI '-Transform' -> '-Transforms' mapping fix (found via GPF corpus).

REMAINING for GPF v1: ModulePack xlsx parse for ProcToClose/instructions auto-fill (nice-to-have); their real share paths when provided; Documents layout extras (Logs\/Snapshots\ subfolders like their Outgoing style); live end-to-end build of one corpus package by the user. MAINTENANCE NOTE: files\ and GPF-PackageBuilder are SEPARATE codebases - engine fixes must be ported manually between them (user chose clean separation over shared profiles).
