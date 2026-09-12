---
name: intune-notes-json-schema
description: "The team's Intune app Notes field is JSON (lifecycle/notes/managed/status/pilot/rollout) - parse it, don't regex it"
metadata: 
  node_type: memory
  type: project
  originSessionId: ff2c8d45-834f-45da-b4b7-19b87e7366ee
  modified: 2026-07-21T09:17:41.547Z
---

In the m365.man tenant, the **Notes field of each Win32 app is a JSON document** written by the team's
tooling — not free text. 797 of 801 apps use it (4 empty, 0 plain text):

```json
{ "notes": "Created by SCCM2Intune App Migration tool.",
  "managed": true, "status": "OK", "rollout": "", "pilot": "", "lifecycle": "SAT" }
```

**`lifecycle`** is the authoritative stage — read it directly, never guess from prose. Real values
(2026-07-21, 801 apps): `LIVE` 525, `SAT` 158, `RETIRED` 78, `UAT` 24, `FailedUAT` 11, `PreRollout` 1,
not recorded 4. Note the CAPS and that **FailedUAT / PreRollout** exist — an assumed
Live/UAT/SAT/Pilot/Retired list is wrong.

**Inner `notes`** records HOW the package was created, which is a genuinely useful filter axis:
SCCM2Intune 298, blank = manual 249, Intune Win32 Automator 210, Winget Intune Manager 26,
Package Builder 8, other 10.

**`pilot` / `rollout`** are scheduled ISO timestamps (mostly blank), `managed` true 751 / false 46,
`status` almost always `OK`.

Some inner notes carry their own dated trail — `"[2025-01-30] Rollout scheduled ... Package was set to
LIVE"` (13 apps). For older apps this is the ONLY record of what happened, since Intune's audit log
does not reach back far enough.

**How to apply:** parse the JSON first and fall back to regex only for the handful of free-text notes.
This is a separate axis from name-based Kind (Test/UPD/Winget) — see [[intune-app-report-tool]].
"Created by" in the sense of *which human* is NOT in this field and NOT in Graph; it only comes from
the Intune audit log (~1yr retention), so it is blank for most of the estate.
