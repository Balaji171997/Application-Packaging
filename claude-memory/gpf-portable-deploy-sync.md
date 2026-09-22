---
name: gpf-portable-deploy-sync
description: Team copies of ALL THREE Package Assistance brands live in repo\PackageAssistance-Teams\ (GPF_/PAG_/MTB_PackageAssistance); after ANY source change run PackageAssistance-Teams\Update-Teams.ps1 (packs + copies pak/sidecars + mirrors Lib)
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 7d55d151-f242-4450-a165-3b37421965bd
  modified: 2026-09-20T12:27:37.079Z
---

Whenever I change a Package Assistance source folder, the user wants the team copy updated too — a source-only
change never reaches the packagers.

**Since 20 Sep 2026** the three team copies sit together in `Application-Packaging\PackageAssistance-Teams\`:
`GPF_PackageAssistance`, `PAG_PackageAssistance`, `MTB_PackageAssistance` (underscore = team copy; the hyphen
folders `GPF-PackageAssistance` etc. are the source). User: "keep all three in one folder so I know where to
look; every time we change the source, update the pak inside that folder."

**How to apply:** `.\PackageAssistance-Teams\Update-Teams.ps1` (optionally `-Brand GPF` / `-NoPack`). It runs
each brand's Pack-Engine.ps1, copies PackageAssistance.pak + settings.json + snippets.json +
KnowledgeBase.Recommend.json and mirrors Lib\ (GPF/PAG: PSADT_Template_GPF; MTB: 338 MB of SCCM/Intune/PnP
modules + template). Sidecar data files are not compiled into the pak (no repack needed for them), but they must
be copied - the script does. The loader exe is never rebuilt; all copies are byte-identical (12 Sep 2026 build).

**Why:** the exe reads `PackageAssistance.pak` by name from its own folder; the team runs the exe from a share
via a shortcut, so replacing the pak updates everyone. See [[shared-folder-deployment]], [[pa-gpf-pag-enterprise-shell]].
