---
name: multi-team-brand-variants
description: "Manager wants Package Builder reused for other teams — separate brand-specific tool copies (different PSADT template + paths, same process)"
metadata: 
  node_type: memory
  type: project
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

Package Builder is going to be reused for OTHER teams (manager's ask, raised 2026-07-04). The PROCESS is the same; what differs per team/brand:
- the **PSADT template** (they'll hand over their template),
- **paths** (repos / shares / Outgoing / prelive / SCCM site etc. — in settings.json),
- **branding** (detection branding key, naming).

Plan: keep a **separate tool copy per brand** (not one tool with a switch). The user will bring their PSADT template + **5-10 sample packages** so we adapt: swap the template, update paths in settings.json, adjust brand-specific detection/naming, then validate by re-building those sample packages (reuse flow). Details (exact paths/branding) come after the user's meeting.

**How to apply:** when the template + sample packages arrive, fork the tool into a brand-specific copy, replace `PSADT_Template`, update `settings.json` paths + branding, and verify against their samples. See [[shared-folder-deployment]], [[downloads-files-is-pb-only]], [[verify-semantic-not-syntax]].
