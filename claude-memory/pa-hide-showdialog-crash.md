---
name: pa-hide-showdialog-crash
description: "Package Assistance (GPF/PAG/MTB) \"tool closes on Apply after snapshot screenshots\" = WPF Window.Hide() on the ShowDialog main window; fixed 19 Sep 2026 with Win32 SW_HIDE; plus log-converter guard fix + pre-existing BTC v3 finding"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7d55d151-f242-4450-a165-3b37421965bd
  modified: 2026-09-19T02:54:22.006Z
---

**Bug (19 Sep 2026, all three brands):** predecessor reuse + MSI snapshot + "Launch + screenshot shortcuts" +
"Apply to package" → tool closed with no error. Cause: the screenshot handler called `(Get-PBMainWindow).Hide()`;
the main window is shown with `ShowDialog()`, and WPF's `Window.Hide()` on a modal window ENDS that ShowDialog.
Nothing visible until the snapshot dialog closed on Apply → main loop already gone → script ran off its end →
`[Environment]::Exit(0)` (the 18 Sep shutdown block). Same root cause as the invisible lingering
PackageCompanion.exe processes found on 18 Sep.

**Fix:** `Hide-PBMainWindow` / `Show-PBMainWindow` (Win32 `ShowWindow` SW_HIDE=0 / SW_SHOW=5 on the HWND, WPF never
notices), snapshot dialog `Add_Closed` restores the main window, and the main `ShowDialog()` is wrapped in
try/catch → crash log `<work>\Logs\PackageAssistance-crash.log` + MessageBox, so "closed without error" cannot
recur. GUI.ps1 identical in GPF and PAG (copy GPF→PAG); MTB edited by hand at the same three places.

**Also fixed (all three `Build.ps1`, `Convert-LogPathFormat` guard):** only convert the OLD flat format
(`$configToolKitLogDir` or `[string]$setuplogName =` decl; MTB also `$setuplogfolder`). A v4 predecessor that owns a
variable called `$setuplogName`/`$setuplog` (KNIME 5.8.2, Sphera, 13 more in CMLib_LIVE) was mangled into parse
errors / a doubled `$LogPathMain` scaffold. Proven over all 917 live packages: 903-904 byte-identical, the rest =
old broken → new untouched. User rule: NEVER change working GPF behaviour without such a proof — GPF has no
packages on this machine; its corpus tests run against the MAN share.

**Pre-existing, NOT fixed (user said leave GPF alone):** `BTCEmbeddedSys_TRATONeese_x64_4.0.0.52` reuse build has 6
parse errors in GPF — v3 predecessor in the `} elseif ($deploymentType -ieq 'Uninstall') {` layout leaks its brace
lines into the v4 template. Same with old and new code.

**How to verify:** `Release-Check.ps1` in each brand (random 100 sample → a failure may be a new package, compare old
vs new before blaming a change); scratchpad `Compare-LogConv2.ps1` pattern = swap ONLY the changed line back and
diff outputs over the corpus.

**Precedence on reuse + analyzer (asked 19 Sep):** predecessor keeps install/uninstall/repair; analyzer is ADDITIVE:
ProcToClose union, exclusions appended `# [snapshot-added]` if target not already handled, SoftIdent refreshed only
if predecessor's is empty/placeholder/single GUID and snapshot has one product code, FreeSpace raised only, no
per-user config on reuse (`Merge-SnapshotDeltas` in Build.ps1).
