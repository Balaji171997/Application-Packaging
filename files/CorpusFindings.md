# Corpus study — 900 live packages (what to automate for all sources & scenarios)

Source: `\\mbddfsovpc01.mn-man.biz\SWDLive-Gate\CMLib_LIVE\Apps` (900 packages), surveyed 2026-06-28.
Method: full read of every package's PSADT script + Files folder; authored-code scanned **between the section markers only** (so template boilerplate doesn't inflate counts); plus a 250-package run through the tool's own build pipeline.

## 1. Platform & source-type distribution

| Dimension | Breakdown |
|---|---|
| PSADT version | **v3 = 793 (88%)**, v4 = 106 (12%) |
| Architecture | x64 626 (70%), x86 248 (28%), ALL 26 (3%) |
| **Source type** | multi-installer **307 (34%)**, exe-only 265 (29%), msi+mst 148 (16%), **zip 114 (13%)**, msi-only 34 (4%), few/loose/msp/msix ~30 |

Takeaways: the **v3→v4 path is the dominant one** (88%); **multi-installer is the single biggest source shape** (34%); **zip delivery is common** (13%).

## 2. Authored scenarios (real custom code, % of packages)

| Scenario | % | Tool status |
|---|---|---|
| conditional logic (if/switch/foreach) | 99% | carried verbatim ✓ |
| file globbing (Get-ChildItem/-Recurse) | 78% | carried verbatim ✓ |
| remove-file | 61% | snippet ✓ |
| reg-remove | 57% | snippet ✓ |
| **Start-Sleep / waits** | 57% | **no "wait for process/file" snippet — GAP** |
| copy-file | 49% | snippet ✓ |
| reg-write | 40% | snippet ✓ |
| per-user HKCU | 29% | auto codegen + snippet ✓ |
| kill-process | 21% | ProcToClose/Block ✓ |
| new-folder | 16% | snippet ✓ |
| **vcredist / .NET prereqs** | 9% | **no prerequisite chaining — GAP** |
| response files (.iss/.inf/.xml) | 8% | flagged in review ✓ (no "run with response file" snippet) |
| Active Setup | 7% | auto codegen + snippet ✓ |
| shortcuts | 6% | snippet ✓ |
| scheduled tasks | 4% | snippet ✓ |
| certificates | 3% | snippet ✓ |
| services | 3% | snippet ✓ |
| **drivers (pnputil)** | 1% | **no snippet — GAP** |
| **fonts** | 0.3% | **no snippet (deprecated in v4) — GAP** |

## 3. Build-pipeline health (250-package live sample through our reuse + v3→v4 pipeline)

- **250/250 build, 0 exceptions** — pipeline is robust. ✅
- Real issues (the brace-imbalance 249 and "empty-section" 121 are **metric artifacts** — GUIDs/here-strings skew the brace count; the installer-line *swap* trips the empty-section check):
  - **1 parse corruption** (`Shining3D_EXStarHub`, brace delta −3).
  - **10 v3→v4 residue** — v3 cmdlets left in v4 output (SAP, Visual Studio, Adobe, EPLAN, …).
  - **4 custom-log loss** — the boilerplate stripper deleting authored `Write-ADTLogEntry` lines (Inventor −10, VS −9).

## 4. Gaps to close, prioritized by corpus frequency

1. **Harden v3→v4** (88% of corpus) — **DONE (r133).** Investigation showed the scan's "10 residue / 4 log-loss / 1 parse" overstated it. Fixed the genuine gaps: **`Execute-MSP`** now maps to `Start-ADTMsiProcess -Action 'Patch'`; the converter now also runs on **hybrid/v4 packages with stray v3 cmdlets** (`Set-RegistryKey`, `Write-Log`, …) that the old "$isV3 only" gate skipped; **`Add-UGPermission`** handles **comma-separated path lists** (one `Set-ADTItemPermission` per path) and any unusual shape is **warning-flagged**, never silently broken. Re-scan of all 900 → residue eliminated (only unusual `Add-UGPermission` shapes remain, now flagged). The **"log-loss" was a false positive** (the scanner builds with uninstall-previous OFF, so the old-version "Uninstall X" logs are correctly excluded). The **1 parse corruption** (Shining3D) is a **malformed predecessor** (a stray `}` in its POST-INSTALL) — already surfaced by the GUI's `Test-ScriptStructure` "CORRUPT SCRIPT" warning, so it's flagged, not silently shipped. Test-Build green.
2. **ZIP source auto-extraction** (13%) — **DONE (r134).** `Resolve-Source` now detects a `.zip` payload with no loose installer beside it, extracts it to a local staging folder (read-only share safe), strips Mark-of-the-Web, and resolves the installer inside (`Expand-SourceZips`). A `.zip` next to a real installer is left as-is. Verified end-to-end; Test-Build green.
3. **Prerequisite chaining** (9%) — **DONE (r135 snippets + r136 auto-chain).** `Get-PrerequisiteSpec` recognises common runtimes by filename (VC++ redist, .NET runtime/framework, Edge WebView2, DirectX). In a multi-installer build `Get-MultiCommandSet` now **stable-sorts recognised prerequisites to the front** (install first, uninstall last), **auto-fills their silent switches** when none were set, and adds a "Prerequisite(s) install first" header; the KB recommender also suggests those switches in the GUI. Verified: a vc_redist listed *after* the main MSI is reordered to install first with `/install /quiet /norestart`. Plus the **Prerequisites** snippet category for the hand-coded case.
4. **Long-tail snippets** — **DONE (r135).** New parse-clean categories: **Processes → Wait** (wait-for-process, wait-for-file-with-timeout, run-wait-check-exit — waits are in 57% of packages), **Installers → Response file** (.iss install + how to record one), **Drivers → pnputil** (install/remove .inf), **Fonts → Install** (copy+register). snippets.json now 15 categories / 30 snippets.
5. **MSIX/MSP** (rare): MSP install now handled by the converter (`Execute-MSP` → `Start-ADTMsiProcess -Action Patch`, r133); MSIX remains known-manual.

Already well-covered (no action): multi-installer, exe, msi+mst, per-user/Active-Setup, services, scheduled tasks, certificates, shortcuts, folders, registry, branding, the new predecessor-reuse report.
