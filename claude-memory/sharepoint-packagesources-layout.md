---
name: sharepoint-packagesources-layout
description: "Layout of the SWPackaging/PackageSources SharePoint library and how it maps onto PB's Vendor_App_Arch_Version-Release_Lang name"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5f8c282b-8837-49ff-ba23-d8ac148e8fa6
  modified: 2026-09-04T10:36:25.613Z
---

`PackageSources` library layout (verified 2026-09-04 against live data, ~514 vendor folders):

```
PackageSources/{Vendor}/{App}/{Version}_{Release}/
    source/     <- installer(s); may hold files directly OR one nested folder
    doc/        <- .docx instructions, sometimes install .log files
    SCCM/       <- BUILT PACKAGE lives here (folder named like the full package name)
                   -> this is where PREDECESSOR packages are read from, replacing the old
                      UNC PredecessorPath (\\mbddfsovpc01...\CMLib_LIVE\Apps)
    EQS/ Intune/ Order/         <- other build outputs, not source
    RITM*.txt   <- loose ticket-reference files at the version root
```

Predecessor discovery = list sibling version folders under the same `{Vendor}/{App}`, then read
`{Version}_{Release}/SCCM/{FullPackageName}/`. There is no flat "all packages" folder like the old share.

**Name mapping is deterministic** — PB's parser (`Vendor_App_Arch_Version-Release_Lang`) maps straight onto the path:
`3Dconnexion_3DxWare_x64_10.9.1.650-0001_MUL` → `3Dconnexion/3DxWare/10.9.1.650_0001/`
Version+Release join with an **underscore** in SharePoint where the package name uses a **hyphen**. `Arch` and `Lang` do not appear in the path at all.

**Edge cases seen in the first sample:**
- Version folder containing ONLY a `RITM*.txt`, no subfolders (stale/unstarted ticket) → must return "no source", not an error.
- Version folder with `EQS/Intune/Order/SCCM` but no `source` and no `doc`.
- `source/` containing a nested folder rather than loose installers (PB's `Resolve-Source` already recurses, so this is fine once downloaded).

**How to apply:** for SOURCE, fetch only `source` + `doc` (skip `EQS/Intune/Order`, they are unrelated outputs and can be huge). For PREDECESSOR, fetch from the sibling version's `SCCM/` folder instead. Keep all SharePoint logic in its OWN files — the user asked that PB's existing scripts not be edited in place. Related: [[sharepoint-auth-pnp112]].
