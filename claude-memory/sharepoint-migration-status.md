---
name: sharepoint-migration-status
description: "Status of migrating Package Builder off the UNC shares onto SharePoint — what is done, what is left, and what can never move"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5f8c282b-8837-49ff-ba23-d8ac148e8fa6
  modified: 2026-09-12T14:45:01.196Z
---

Migrating PB from UNC shares to SharePoint (`SWPackaging/PackageSources`). Work lives in
`Downloads\Application-Packaging\SharePointTest\` — deliberately OUTSIDE `files\`, which is still untouched.

**Design:** PB works on LOCAL paths, so everything resolves a package to a SharePoint folder, downloads what PB
actually reads into local staging, and returns that path. `SharePoint.ps1` loads AFTER Source.ps1/Predecessor.ps1,
captures their originals via `(Get-Command X).ScriptBlock`, then overrides three functions. With
`SharePoint.Enabled=false` the originals run verbatim — the file is inert. Verified: 9/9 OFF-mode checks pass.

| UNC consumer | Setting | Status |
|---|---|---|
| Source (Incoming) | `RepositoryPath` | DONE — `Find-SourceFolder` override |
| Predecessor | `PredecessorPath` | DONE — `Get-PredecessorCandidates` + lazy `Read-PredecessorModel` |
| Built package out | `OutgoingPath` | NOT STARTED (write path; async-upload risk) |
| Shared snippets | `SnippetsPath` | NOT STARTED (read-merge-write, conflict-prone) |
| SCCM content | `Sccm.ContentShare` | **CANNOT MOVE** — ConfigMgr needs a UNC/local content source; not a SharePoint URL |

**Proven end-to-end (2026-09-05):** source staged 260 MB → PB's real `Resolve-Source` returns
`Valid=True, Mode=structured`; predecessor list is lazy (0 downloads), selection fetches ~101 KB (skipping 481
payload files) → real `Read-PredecessorModel` returns `v3, MULTI: 2 installs / 1 uninstalls`.

**Predecessor fetch is an ALLOWLIST** — PB only reads the toolkit script, `SupportFiles\*ActiveSetup*.ps1`,
`*.mst`, and `Icons\`. Payload extensions are excluded wherever they hide (one real package parks a 190 MB
installer inside `Content\SupportFiles`). `-Full` overrides.

**Open risks / decisions:**
- `Get-PredecessorRoots` (Predecessor.ps1:352) also searches a HARDCODED 2nd live repo
  `\\MNDEMUCFS120.mn-man.biz\SWDistribution-Gate\CMLib_LIVE\Apps`. The override drops it — check nothing lives
  only there.
- SharePoint `SCCM/` = "last BUILT"; `CMLib_LIVE` = "last LIVE". These can diverge.
- Predecessor matching is now app-scoped (Vendor/App path) instead of fuzzy across all packages.
- PnP is a BINARY module — loading from the UNC share may need the same `.exe.config` trust fix as PB's other
  binary modules. Untested from the share. See [[shared-folder-deployment]].

**SEPARATE TOOL (user's decision, 2026-09-05):** the SharePoint version is its own copy at
`Application-Packaging\SP-PackageCompanion` (repo root is now `Documents\GitHub\Application-Packaging`; folder
renamed from `SP-PackageBuilder` on 2026-09-12) — `files\` must stay untouched. It is a DEPLOYMENT VARIANT,
not a fork: every engine file is byte-identical to MTB. Only 4 things are its own — `SharePoint.ps1`,
`lib\PnP.PowerShell\1.12.0\`, `settings.json` (has the `SharePoint` block, `Enabled=true`), and 3 wiring lines.
`Sync-FromMTB.ps1` pulls MTB fixes forward and re-applies the wiring automatically.

**RENAMED 2026-09-11 → "Package Companion"** (client disliked "Builder" — it assists, it does not build).
Everything renamed: text, `PackageCompanion.exe/.pak/.exe.config/.ps1`, `Lib\PackageCompanion.ico`, work root
`C:\temp\PackageCompanion` (old folder left behind on purpose). The loader was recompiled with ps2exe.

**MACHINE MOVE 2026-09-12:** the freshly compiled `PackageCompanion.exe` was QUARANTINED by Cortex XDR / Trellix
(fresh unsigned ps2exe binaries trip them; Defender is off, so `Get-MpThreatDetection` shows nothing). User moved
to a new test machine, copying `Application-Packaging` whole (git repo at its root, today's work uncommitted).
**`SP-PackageCompanion\HANDOFF.md` carries the full state and the recompile command** — memory does NOT travel
with a folder copy. If the exe is eaten again, fall back to display-name-only (files stay `PackageBuilder.*`).

**2026-09-12 (new machine):** exe rebuilt fine (ps2exe 1.0.18, Trellix quiet). Shell REDESIGNED in the SP copy:
no rail, step-pill strip `Info|Installation|Editor|Create & Publish` (user REJECTED dots/numbers/review-count
badges - a count reads as "things left to do"), header = name + `RITM <id>` beside it, no user name,
Source/Target at strip's right, 19 result labels selectable (PbCopyText). `SW-Source` resolver fix + doc-folder
flattening went into MTB `files\` too (byte-identical mirror). **Copy to SharePoint BUILT (Copy-SPPackage +
BtnCopySharePoint, verify-by-size, dry-run 16/16) but NOT live-tested - test on a DUMMY vendor/app only.**
Full state in `SP-PackageCompanion\HANDOFF.md`.

**NEXT DIRECTION (user, 2026-09-12): SharePoint is the ONLY read/browse/update source - Outgoing becomes a
BACKUP.** Everything the tool currently fetches from the Outgoing share (Load from Outgoing on Publish, the
Browse/Load package paths, Modify content source, predecessor lookups, anything that "reads a package back")
must read from the SharePoint package folder (`{Vendor}/{App}/{Ver}_{Rel}/SCCM/{Name}/`) first; Outgoing is a
write-only mirror kept for safety, never the place the tool browses or updates from. Do this before adding any
new Outgoing-based feature. Copy to SharePoint (built, untested) is the write half of this; the read half is
the open work.

**Older list (superseded by the above):** rail state dots + amber review-count badge (clickable);
thin progress line replacing the chunky ProgressBar; **Copy to SharePoint** after Create (upload to
`{Vendor}/{App}/{Ver}_{Rel}/SCCM/{Name}/`, create `SCCM` if missing, show that button OR Copy-to-Outgoing by
where the source came from — a WRITE, verify every file landed); build summary replacing review summary;
remember last package on reopen.

**Seven windowless orphan processes** were holding the exe locked — leftovers from the sign-in and Get-PnPFile
hangs. Check Task Manager for windowless copies before assuming a permissions problem.

**TRAP 1 — THE EXE MUST BE THE THIN LOADER (~54 KB).** `files\` (and therefore any copy of it) carries an OLD
`PackageBuilder.exe` of ~968 KB built by `Build-Exe.ps1`/ps2exe with the engine **baked inside it** — it contains
`PBEngineSource`, never references `.pak`, and IGNORES every repack. Symptom: the tool behaves like the old
UNC-only build no matter what you change. The correct exe is the ~54 KB Loader (`Loader.ps1`) that reads
`PackageBuilder.pak` next to itself. Two releases shipped the wrong one before this was caught;
`New-SPToolRelease.ps1` now hard-fails if the exe does not reference `PackageBuilder.pak`.

**TRAP 2 — INTERACTIVE SIGN-IN CANNOT HAPPEN IN A BACKGROUND RUNSPACE.** `Find-SourceFolder` /
`Get-PredecessorCandidates` run inside `Invoke-PBAsync`'s runspace. `Connect-PnPOnline -Interactive` there HANGS
forever (no UI thread for the auth window), and a PnP connection does not cross runspaces either. Fix in place:
`Get-SPWorkerToken` signs in on the UI thread inside `Invoke-PBAsync`, the token rides in the payload as
`sptoken`, and the worker calls `Set-SPAccessToken` then connects with `-AccessToken`. Never prompt in a worker.

**WIRING GOTCHA — there are FOUR lists, not one:**
- `Pack-Engine.ps1` `$engineFiles` ← **this builds the SHIPPED .pak**; miss it and the release silently runs
  UNC-only with no error
- `Build-Exe.ps1` `$enginiFiles` (legacy ps2exe path)
- `GUI.ps1` dev-mode dot-source block
- **`GUI.ps1` `Invoke-PBAsync` runspace loader (~L4220)** — the easiest to miss, and the one that actually runs
  `Find-SourceFolder` / `Get-PredecessorCandidates`. Missing it = tool ignores SharePoint entirely in dev mode.
  (The two publish runspaces at ~L4257/L4342 deliberately do NOT load it — they never call those functions, and
  loading it there would risk a sign-in prompt on a background thread.)
`SharePoint.ps1` must be **LAST** in each — it captures the originals it overrides. `Sync-FromMTB.ps1`
re-applies all of these automatically after a sync.

**UNC IS SECONDARY (user's decision):** SharePoint is primary for both source and predecessor; UNC repos are
merged in as EXTRA predecessors only if reachable, deduped by name with SharePoint winning. Two users already
have no read access to any share. `Test-SPUncUsable` probes port 445 with a 1.5s bounded wait and caches per
session — without it a plain `Test-Path` on an unreachable UNC blocks 30-90s and looks like a frozen tool.

**DISTRIBUTION = manual ZIP from SharePoint (user's decision).** NO Intune — the Intune-managed machines are a
separate estate, so packagers would never receive an Intune-delivered app. `New-SPToolRelease.ps1` builds it;
`-NoSccm` drops the 227 MB ConfigMgr module (~343 MB → ~116 MB) for users who cannot reach UNC and therefore
cannot publish to SCCM anyway. **Mark-of-the-Web is the main hazard**: users MUST unblock the .zip BEFORE
extracting or the DLLs (AvalonEdit, PnP) fail to load; `Unblock-Tool.cmd` ships as the fallback.

Related: [[sharepoint-auth-pnp112]], [[sharepoint-packagesources-layout]], [[shared-folder-deployment]].
