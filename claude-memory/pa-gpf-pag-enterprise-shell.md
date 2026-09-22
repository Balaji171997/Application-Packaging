---
name: pa-gpf-pag-enterprise-shell
description: "20 Sep 2026 - GPF and PAG Package Assistance got MTB's enterprise shell (header, step strip, sections, dialog chrome, busy card); GUI.ps1/Theme.ps1 identical GPF=PAG; MTB untouched; smoke driver + rules"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7d55d151-f242-4450-a165-3b37421965bd
  modified: 2026-09-22T06:43:35.454Z
---

**Done 20 Sep 2026 (user: "MTB already there with the SharePoint version, so GPF + PAG").** GPF-PackageAssistance
and PAG-PackageAssistance now share one GUI.ps1 + Theme.ps1 (copy GPF -> PAG after any change; settings.json holds
the only differences). MTB-PackageAssistance was NOT changed.

What the shell is: header (PACKAGE ASSISTANCE | name | <OrderNumberLabel> value | BRAND when >1 target), step strip
of 4 pills with state lines (`Update-StepStrip` / `Get-StepState` / `Test-StepDone`), `Update-PBChrome` repaints it
(called from Populate-Step, Parse-Current, TextChanged of name/order/brand, fetch, predecessor, Populate-Publish).
Strip right end = `Source: <folder>  Predecessor: <pkg>` only - user rule: NO platform / target / Incoming-vs-
SharePoint wording for GPF/PAG, just where the files came from. Pages = titled sections (SecMsi/SecExe/SecAnalysis/
SecMulti follow Populate-Step2's visibility; all hidden while no installer). Step 4: lone tab's HEADER hidden by
collapsing the TabItem (hiding the template's HeaderPanel blanked the page - don't). `PnlPublishStatus` collapses
until it has text. Dialog chrome: `Set-PBDialogChrome -Window -Glyph` before every ShowDialog; `New-PBGlyphButton`,
`New-PBCaption`, `Show-ConfirmTextDialog`. Busy card `Start-PBBusyHost` + `Show-PBBusy`/`Hide-PBBusy` around build,
predecessor load, fetch, create. `Update-ReviewButton` edits the inner TextBlock so the glyph survives.

**22 Sep:** MTB's review acknowledgement ported too (Show-ReviewPopup with per-item "Confirmed" + "Confirm all",
Test-/Set-ReviewAck, Get-OpenReview, State.ReviewAck owned by Step 3; button / Create block / strip count OPEN
items). Also MTB's analyzer (Show-SnapshotDialog) is now verbatim in GPF/PAG (per-user dropdown in its footer).

**22 Sep (later):** full MTB polish diff walked (XAML + every shared function): Configure two-column MST grid + MTB
section order + copyable status labels, Editor toolbar/snippets, Create "Build summary" grid (Set-SummaryRows) +
amber review card, MTB dialog titles/subtitles/accent, snapshot-tree functions + Show-MstPlanDialog verbatim from
MTB (GPF's New-SnapTreeBody had LOST $fCache/$fcount/$rcount - empty counts + O(n^2); fixed by the port). Kept
GPF-only functional bits (Generate MST / Carry-forward switches, brand row, screenshot note, parameterised
Show-ConfirmTextDialog). BOM added to non-ASCII .ps1 files in all three tools (MTB GUI.ps1 had none).
Access-issue sign-in everywhere (PAG ask): `Connect-PBShare -Retry`, `Test-PBAccessError`, `Invoke-PBWithShareAccess`
wrap Fetch / Stage-SourceLocal / Predecessor / Copy to Outgoing. How to re-diff: `Get-Fn`-style AST swap scripts in
scratchpad (Port-*.ps1); Smoke-GPF.ps1 now also renders `2b-installation-msi.png` (populated Configure page).

**Rules learned:** controls that were TextBlocks and became copyable TextBoxes (PbCopyText) only support .Text /
.Foreground / .ToolTip - check member uses before converting. Never set a glyph button's `.Content` to a string.
Handlers that are `.GetNewClosure()` (Copy to Outgoing) were left alone. Text tiers: no #888/#939BA7 (tertiary
#A0A8B4). DEV mode of GUI.ps1 must dot-source BrandGpf.ps1 + Screenshots.ps1 (pak already did).

**Verify after any XAML change:** scratchpad `Smoke-GPF.ps1 [-Src <tool>] [-Tag x]` copies the tool, injects a
DispatcherTimer driver before `try { $script:Win.ShowDialog() | Out-Null }` (and the SMOKE-ERRORS line before the
shutdown block), moves the window off-screen (-4000,-4000, 1400x860) and RENDERS each page + the analyzer with
RenderTargetBitmap to shots-<tag>\*.png - no desktop capture (a full-screen grab caught the user's own desktop).
The first run per machine takes ~5 min (knowledge-base warm-up), later runs ~20 s. MTB's copy gets stuck in
Step 3 under this driver (modal prompt) - use MTB's own Smoke-GUI.ps1 from the old session if needed.
Then: Pack-Engine.ps1 in GPF and PAG, copy the GPF pak to GPF_PackageAssistance, Release-Check.ps1 both, Test-Build.
