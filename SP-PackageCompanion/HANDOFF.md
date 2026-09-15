# Package Companion (SharePoint edition) - handoff note

Written 2026-09-12 when moving to a new test machine. Read this first in the new session.

## Step 0 - restore Claude's memory (before anything else)

Claude Code's memory of this whole project (45 files: every gotcha, dead end and decision) now lives IN this repo at
`Application-Packaging\claude-memory`. It only works once the profile is linked to it:

```
cd <path>\Application-Packaging
.\Setup-ClaudeMemory.ps1 -WorkingDir '<the folder you open Claude Code in>'
```

Do this BEFORE the first Claude session on the new machine, or that session starts with no memory at all.
The script is safe to re-run and merges anything already in the profile.

## Do this first on the new machine

**The exe is missing on purpose.** `PackageCompanion.exe` was compiled here and then quarantined by Cortex XDR /
Trellix within minutes (fresh unsigned ps2exe binaries trip them). Nothing else is broken. Rebuild it:

```
cd <this folder>
Import-Module ps2exe
Invoke-PS2EXE -InputFile .\Loader.ps1 -OutputFile .\PackageCompanion.exe -STA -noConsole -title 'Package Companion' -iconFile .\Lib\PackageCompanion.ico
```

Then `.\Pack-Engine.ps1` and launch `PackageCompanion.exe`. If the exe vanishes again on the new machine too,
fall back to display-name-only: keep files as `PackageBuilder.*`, UI text stays "Package Companion".

The Loader is a thin 54 KB exe that reads `PackageCompanion.pak` by name. A 968 KB exe is the OLD ps2exe build
with a July engine baked in - it ignores the pak entirely. `OLD-ps2exe-build.exe.bak` is that file, kept as evidence.

## What this tool is

A separate copy of Package Builder (MTB) that reads sources and predecessors from SharePoint first, with the UNC
shares as fallback. `Application-Packaging\files` is the untouched MTB original. This folder differs only in:
`SharePoint.ps1`, `Lib\PnP.PowerShell\1.12.0\`, `settings.json`, and four wiring lines. `Sync-FromMTB.ps1` pulls MTB
fixes forward and re-applies the wiring.

Wiring lives in FOUR places (all must list `SharePoint.ps1` LAST): `Pack-Engine.ps1` (builds the shipped pak),
`Build-Exe.ps1`, GUI.ps1 dev dot-source block, and GUI.ps1 `Invoke-PBAsync` runspace loader (~L4250).

## Auth - the only thing that works in this tenant

PnP.PowerShell **1.12.0** (last PS 5.1 build) + client id `28bf2c22-437c-42e7-a4be-e8a0f44a8264` (PnP Management
Shell). Graph CLI Tools and the Intune app are both blocked by tenant policy - do not retry them. Sign-in runs at
STARTUP before the WPF window exists; running it from a button handler or a worker runspace HANGS.

`Get-PnPFile` deadlocks on the WPF UI thread - `Invoke-SPDownload` clears the SynchronizationContext around the
download for that reason. Do not add a dispatcher pump there; it deadlocks the other way.

## Renamed 2026-09-11 to "Package Companion"

Everything renamed (text, exe, pak, config, icon, work root `C:\temp\PackageCompanion`). The old
`C:\temp\PackageBuilder` was left behind deliberately. Client did not like "Builder" (it assists, it does not build).

## 2026-09-12 on the new machine (this session)

- Folder renamed `SP-PackageBuilder` -> `SP-PackageCompanion`. Exe rebuilt with ps2exe 1.0.18 (installed
  CurrentUser, PSGallery trusted) - Trellix on this machine left it alone. Git is NOT on PATH here: use
  `%LOCALAPPDATA%\GitHubDesktop\app-*\resources\app\git\cmd\git.exe`.
- ENGINE FIX (in MTB `files\` AND mirrored here, byte-identical): `SW-Source` & co. added to `$script:SourceNames`
  (Source.ps1) - without it the resolver fell to scan mode, Files\ got `SW-Source\...` whole and every license .txt
  became a "document". New `Copy-DocItems` flattens the doc folder into Documents\ (was Documents\Documents\...).
  Both copy paths (Copy-ResolvedSource, Assemble.ps1 loose path) use it. Test-Build.ps1: ALL TESTS PASSED.
  -> the MTB team copy needs this Source.ps1 + Assemble.ps1 too.
- SHELL REDESIGN (SP copy only - GUI.ps1/Theme.ps1 already diverged from MTB): left rail GONE, every step has
  the full width. Header = brand | package name (Consolas, MaxWidth 640) | `RITM <id>` right beside it (hidden
  until typed, updates live) - no user name. Under it a step strip of compact pills
  `Info | Installation | Editor | Create & Publish` (current = teal-tinted pill, done = light, pending = muted;
  NO numbers/dots/counts - the user rejected a review-count badge because it read as "things left to do") with
  `Source: ... Target: ...` at the right end. Window 1200x760 (min 1040x640), base font 13, inputs 28-30px.
  Step 1 is two columns (identity | "Source & predecessor" panel); Step 2 scrolls. Text tiers documented in
  Theme.ps1 (`#B7BEC8` secondary, `#A0A8B4` tertiary - deliberately bright for dimmed monitors; never `#888`).
  19 dynamic labels are read-only borderless TextBoxes (style `PbCopyText`, DynamicResource) so they can be
  selected + copied. Status bar is EMPTY when idle (a standing "Ready" read as a button).
- **Copy to SharePoint BUILT, NOT live-tested**: `Copy-SPPackage` (SharePoint.ps1) uploads the created package to
  `{Vendor}/{App}/{Version}_{Release}/SCCM/{Name}/`, reusing existing folder spellings, creating SCCM if missing,
  asking before replace, verifying every file by name+size afterwards (incomplete = red, names the files). Never
  signs in from the button (startup only). Button `BtnCopySharePoint` on Review & Create; `Update-DeliveryButtons`
  shows SharePoint when the source was staged from SharePoint (Outgoing hidden), both when SP is on but the
  source was manual. Dry-run with stubbed PnP: 16/16. **Test it against a DUMMY vendor/app first** - a real
  name would replace the live package in SCCM/.

- LATER THE SAME DAY: busy card on its OWN UI thread (`Start-PBBusyHost`, synchronized hashtable, timer on the
  busy thread - never cross-thread delegates; `DisableProcessWindowsGhosting`) wired into every blocking op;
  Step 4 async jobs use a thin progress line. Installation page = titled sections (Installer / MST cleanup and
  properties / Silent switches / Per-installer args / Analysis / Loose files) + Segoe MDL2 glyphs everywhere
  (`New-PBGlyphButton`, `New-PBCaption`, theme styles PbGlyph/PbSectionTitle/PbSectionDesc/PbSectionRule). KB card
  is EXE-only (user: nothing for MSI). Per-user config MOVED into the analyzer window (footer row); analyzer got a
  header + 4 captioned phases (Before / Install / After install / Uninstall = Run uninstall + Leftover check).
  Build summary = label/value grid + amber review block; last package remembered (`last-session.json` in the work
  root, Reset all forgets); empty-state sentences on Info. "View predecessor install/uninstall" button REMOVED;
  installer SIGNATURE review item REMOVED from `Get-InstallerValidation` (MTB `files\` + mirror).
  **Step 4 = left sub-navigation**: `Initialize-Step4Nav` lifts the page contents out of the XAML tab controls at
  startup and re-hosts them (Package: Review & Create, Publish | SCCM: Application, Collections, Diagnostics,
  Promote | Intune: Assignments & Content, Diagnostics); `Select-P4Page`, `Invoke-P4PageEntered` (the old
  SelectionChanged body), `Set-P4GroupVisibility` (Direct Intune hides the SCCM group). `$host` is a RESERVED
  variable - it cost one startup crash. Smoke test: `scratchpad\Smoke-GUI.ps1` copies the tool, disables
  SharePoint, drives the real GUI with a DispatcherTimer and screenshots each page - use it after any XAML change.

- STRIP OPTION A built: a state line under each pill (Get-StepState: 'source fetched · predecessor 128.14.0-0002',
  'MSI + MST · 2 properties', '3 to review' / 'reviewed', 'created'). REVIEW ACKNOWLEDGEMENT: State.ReviewAck (key =
  item text; Test-/Set-ReviewAck, Get-OpenReview) - the popup shows only open items with a 'Confirmed' tick per item +
  'Confirm all'; the reuse 'done automatically' list is a collapsed expander. Confirmed items leave the amber count
  everywhere (button, Step 4 block, strip). Option B (single band) was shown and NOT chosen.

- RESUME SESSION (full): Save-LastSession serialises a whitelist of State ($script:SessionKeys, FileInfo as
  {__file}, hashtables/arrays recursed; ConvertTo-/ConvertFrom-SessionSafe) + step + Step-4 page on close;
  Restore-LastSession puts it all back, rebuilds the predecessor model from its folder, drops what is gone
  (with a note in the status line). Reset all deletes the file AT ONCE and clears the status. SCCM pages renamed
  Modify / Assignments. Analyzer = data first: title only (description in tooltip), 4 phases on one row, report +
  action buttons moved onto the tree header row, footer = one row (per-user dropdown · summary · Apply/Cancel),
  tree header shows counts only (legend in tooltip). Smoke driver lessons: [Windows.Application]::Current is
  $null in a PS host (use $Win.OwnedWindows), timer vars must be $script:, no duplicate switch cases.

- REVIEW CHECKBOX BUG (user saw a 'script' error): the tick handler was a .GetNewClosure() -> 'Set-ReviewAck is not
  recognized' - closures cannot see the script's functions (the BtnPred comment says so). FIXED by making the four
  function-calling handlers PLAIN scriptblocks (review tick, Confirm all, analyzer Run uninstall, per-user dropdown).
  Second bug found by the same driver: [Windows.TextDecorations]::Strikethrough unrolls to a bare TextDecoration in
  PS 5.1 - build a TextDecorationCollection. scratchpad\Smoke-Review.ps1 drives the real popup (RaiseEvent Click)
  and logs to shots\review.log - rerun it after touching Show-ReviewPopup. RULE: any handler that calls a script
  function must NOT be a closure; share locals dynamically (modal dialogs) or via a hashtable.

- EDITOR STEP chrome restyled (toolbar on the strip surface, glyph + filename header, 'SECTIONS' caption, snippets
  drawer header with glyph). ALL DIALOGS get the shell header band via Set-PBDialogChrome -Window -Glyph -Title
  -Subtitle -PrimaryName (re-parents the existing content under a band; fixed-height windows grow 42px) - 13
  call sites, right before each ShowDialog. Trap hit: an [ordered] hashtable indexed with an INT key returns the
  POSITION, not the value - use a plain @{} when keys are numbers. Drivers: Smoke-Dialogs.ps1 (predecessor picker,
  text, input, editor page).

- FINAL PASS: every Step 4 page has the section header (Publish / Modify / Assignments / Diagnostics / Promote /
  Intune Assignments / Intune Diagnostics); MSI-properties + MST-plan dialog bodies on the palette (grid headers,
  borders, accent primary, glyph buttons). SHARED SNIPPETS ON SHAREPOINT: settings.json -> SharePoint.SnippetsFile
  (site-relative path, EMPTY = off, shipped empty). Startup: Sync-SPSnippetsDown fetches it to the work root
  (snippets.shared.json) and the tool uses that copy; nothing there yet -> an OWNER's local file seeds it, a
  non-owner just falls back. Owner Add/Edit/Delete -> Publish-SnippetsIfShared -> Sync-SPSnippetsUp. PnP calls
  run under Invoke-SPWithoutUiContext. Dry-run 10/10 (Test-SPSnippets.ps1). To switch it on: create the folder
  in the library, set SnippetsFile, start the tool as an owner once.

- Publish page = two columns (identity | detection), fits without scrolling incl. Description + Create buttons.
  Every 'Content\' hint reworded to 'the package folder (the folder that holds the Content folder), not the
  Content folder' - the trailing backslash made people paste the Content path. THEN simplified again (user): 'The
  package folder, e.g. C:\temp\<name>' - the tool finds Invoke-AppDeployToolkit.ps1 under it (Content or root both
  work: Get-SccmFieldsFromPackage / Copy-PackageToPrelive). All Step 4 pages capped MaxWidth 960 (Publish 1000),
  left-aligned - no more full-width text boxes on wide screens.

- PUBLISH DETECTION redesigned (user): choose the METHOD first (Registry value - version | Registry value - string
  | MSI product code | None), only that method's inputs show (Update-PublishDetectionRows; grid rows collapse to
  0). Registry methods = key + VALUE NAME (new, default DisplayVersion) + version/text; the engines honour
  Fields.DetectValueName (Sccm.ps1 New-SccmUninstallClause + Get-SccmDetection reads it back; Intune.ps1
  Get-IntuneDetectionRules + signature). Same on the SCCM Modify page (Update-ModifyDetectionRows,
  TxtModDetectValueName). Combo is INDEX-based now (labels are prose). Box widths sized to content: names 360,
  commands 560, registry key wide, product code 420, description full. Fits a 768-px screen in every mode.

- PUBLISH PREVIEW FROM THE EDITOR: Populate-PublishFromScript writes the Editor's script into
  Temp\publish-preview\<FullName>\Content\ and runs the same field reader (Get-SccmFieldsFromPackage), so Publish
  is pre-filled before any package exists; re-derived on each visit while $script:PublishSource -eq 'script'. A
  created / Load-from-Outgoing / Browse package sets PublishSource='package' and is never overridden. Create buttons
  stay hidden until a real package exists. Clear-Step4Fields resets the source. Publish rows 34px (no overlap).
  Driver: Smoke-Publish.ps1. NOTE: the user runs the real exe alongside - kill only processes started by the driver.

- RESUME-LAST-SESSION REMOVED on request (Save/Restore-LastSession, ConvertTo/From-SessionSafe all deleted; Reset
  all just clears the status line). PUBLISH LAYOUT v3: left = identity + detection (boxes sized to content, 32-bit
  tick beside Method), right = tall Description with a source note (LblPubDescSrc); commands below. The editor
  preview reads the DESCRIPTION from the fetched source documents (Resolved.DocItems -> Get-PackageDescription:
  'Short/Detailed description of the product' fields in the Installation Instructions .docx) - verified on the
  real Firefox document. Built/loaded packages read their own Documents folder as before.

- PUBLISH FORM FINAL (user: 'won't ask again'): label column 118, EVERY input 440 wide on one right edge (package name
  too), registry key is a two-line box (row 54, Height 50, wrap) at the SAME 440 edge, rows 32, 32-bit tick beside
  Method, description tall on the right, commands 440 below. Do not change these widths without a request.

- SAME 440 RULE ON THE OTHER PAGES (user asked for it "but not looking too odd"): every single-line input on
  Modify / Assignments / Diagnostics / Promote / Intune Assignments & Content / Intune Diagnostics, plus the product
  code on Installation, is Width=440 HorizontalAlignment=Left. Grids that carry a trailing button (Modify app name,
  Modify content source, Intune assignments) use an Auto middle column so the button follows the box instead of
  hugging the right margin. Modify registry key is the same two-line 440 box as Publish (RowModKey 54 / 32 in
  Update-ModifyDetectionRows); Modify content-source row + hint + refresh tick use the page's 140 label column.
  Packed after this change.

## Design work - where it stands

Done: DPI awareness, graceful no-access messages on every share, Step 4 nested as
`Review & Create | Publish | SCCM (Application, Collections, Diagnostics, Promote) | Intune (Assignments & Content,
Diagnostics)`, Direct Intune mode, Intune Diagnostics local-only, collections add auto-removes from the opposite
collection, hints trimmed, and the shell redesign above.

Still open, in this order:
0. **NEXT BIG ITEM (user, 12 Sep): SharePoint becomes the ONLY place the tool reads, browses and updates
   packages from; Outgoing is a BACKUP only.** Every read that still goes to the Outgoing share - Load from
   Outgoing on Publish, Browse/Load package, Modify content source, "read the package back" paths - must go to
   the SharePoint package folder (`{Vendor}/{App}/{Ver}_{Rel}/SCCM/{Name}/`) first. Copy to SharePoint is the
   write half (built, untested); this is the read half.
1. Live-test Copy to SharePoint on a dummy package (see above).
2. Thin progress line under the content + plain sentence in the bottom strip, replacing the chunky ProgressBar
   (`PbPublish`, Step 4).
3. Replace the "review summary" on Review & Create with a **build summary**.
4. Remember the last package on reopen.
5. Snippets library on SharePoint (Outgoing is superseded by Copy to SharePoint).

## Gotchas learned the hard way

- Seven windowless orphan `PackageBuilder` processes were found holding the exe locked - leftovers from the hangs.
  If a rebuild says "access denied", check Task Manager for windowless copies before assuming a permissions issue.
- Never rename by piping quoted strings through the Bash tool - it replaced every `'` with `P` in two files.
  Use the Edit tool or a properly-typed hashtable in the PowerShell tool.
- `Test-Path` on an unreachable UNC blocks 30-90s. Use `Test-SPUncUsable` (bounded, cached) instead.
- The git repo is at `Application-Packaging` root. Today's work was uncommitted at handoff.

## Client presentation: 30 Sept 2026

German client; cares about security and flexibility. Tool only READS from live, so no live-touch concern.
