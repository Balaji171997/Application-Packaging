---
name: automation-scope-not-useful
description: "Package Builder automations the user has ruled out as not useful — don't re-propose these"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

For Package Builder, the user said these snapshot-driven automation ideas are **not useful in their project** (do NOT re-suggest or build them): firewall-rule cleanup, services auto-remove on uninstall, reboot-pending detection, ProgramData machine-config note.

**Why:** their packaging workflow doesn't need them — uninstallers/standard handling already cover these, or they're irrelevant to how the team ships packages.

**How to apply:** when asked "what else can we automate," propose ideas grounded in what the team actually does (e.g. things seen in real packages on the live share), not generic Windows-packaging features. The automations that DID land and matter: snapshot-driven per-user config (HKCU values + AppData file copy via [[activesetup-house-style]]), FreeSpace, cleanups (tasks/fonts/env), KB suggestions, predecessor reuse. Reliability of the snapshot diff is the priority since the user can't verify with SysTracer.
