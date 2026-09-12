---
name: audi-sccm-integration-tool
description: New Audi client project - rewrite their SCCM integration tool to run under a shared service account; transport DECIDED = flow 2 drop folder only (not JEA/WinRM)
metadata: 
  node_type: memory
  type: project
  originSessionId: fd7b3460-9b55-454d-8890-76d54ccc8d20
  modified: 2026-08-01T06:54:51.494Z
---

New brand client (Audi) engagement started 2026-07-30, separate from the MTB and GPF
Package Builder variants ([[gpf-brand-variant]], [[multi-team-brand-variants]]).

**Their existing tool** (reference only, not a codebase to inherit):
`C:\temp\EQS-PoshGUI-Tool-1.0.3` — "Audi SW Integration Tool 1.0.3" by Andras Galambos
(AHA/FP-13). WPF GUI + 15 PowerShell modules. 12 operations (8 integration + 4 removal)
across 3 MECM environments: **ICZ** (test), **INA** (prod), **PCZ** (prod). The "Runbook"
naming is dead Orchestrator ceremony from before the MCB shutdown — everything runs locally
in-process.

**The requirement:** all SCCM work must run under, and be recorded as, one shared
system/service account instead of each packager's personal MECM admin account. The packager
only operates the tool.

**Decisions the user made (2026-07-30):**
- Deliverable = **SCCM integration module only** — not an Audi brand variant of Package Builder.
- **Rewrite** the engine using Package Builder patterns; their script is a requirements reference.
- **Desktop WPF now**, web-based front end presented as the phase-2 roadmap (user liked web but
  wants desktop first).
- XML holds **SCCM/environment config only** — one XML per environment so a new environment is a
  file, never a code change. This was the user's own idea and should be preserved.
- The user is **not deep in AD/SCCM** — explain identity/infrastructure options in plain language,
  no jargon (JEA/gMSA/double-hop/Kerberos land badly).

**TRANSPORT DECIDED 2026-08-01 — flow 2 (drop folder) ONLY.** The user said twice: *"flow 2
only ..first flow we ar enot following"*. Do not re-propose the live-connection / WinRM / JEA
endpoint. Its scripts are parked at `Server\_NotUsed-LiveConnection\`, not deleted.

How flow 2 works: the packager window writes a job XML into `<share>\New`, a scheduled task on
the SCCM server (running as the gMSA) claims it by moving it to `\Working`, runs it, and writes
`<job>.result.xml` into `\Done` or `\Failed`; the window polls for that file. **No firewall
change, no open port, nothing connects inward** — which is why it matches Audi's own barrier
drawing. gMSA is still the account of choice (not a JEA virtual account) because the task must
reach the content-store UNC and the ARS/SPML SOAP endpoint. Plan B if AD refuses: an ordinary
service account stored once in Task Scheduler on that one server.

**PRIVACY RULE DECIDED 2026-08-01 — no real person is recorded ANYWHERE on the SCCM side.**
User: *"dont keept real person name on sccm server logs. only integrator has that info"* /
*"they dont want to see real person doing any changes in SCCm side ..they dont want to involve
real person as well into the server"*. This is stronger than "not on SCCM objects": it covers the
tool's own log, `job.json` and the result file on the server too.

So there is now **one identity only** — the gMSA, in the SCCM `Owner` field. The plan object has
**no `Requester` field at all** (structural, so nothing can log one), `Get-AudiIntegrationPlan`
has no `-Requester` parameter, and the collector no longer reads the job file's NTFS owner.
**The RFC number is the audit link**: written to every SCCM object, and Audi's change system
holds RFC → person. `Audit/@requireRfc="true"` in Defaults.xml, so a job with no RFC is refused
by both the window and the server — otherwise a change would be untraceable.
Also: the collector **re-writes** the archived job file as the service account and deletes the
packager's original, so no person-owned file is left in the secure zone.
`<Job>` in the XSD still has no requester attribute, so a file carrying one is rejected outright.

**Tool:** `Downloads\Application-Packaging\AudiSwIntegration\` — `Server\` (engine + config +
collector), `Client\` (WPF window), `Tests\` (170 checks, none need SCCM). The window's
**Preview** button runs the plan locally through the dry-run provider (no server, no share, no
rights); **Integrate/Remove** go through the drop folder. `PROGRESS.md` in that folder is the
running record — read it first when resuming.

**Deliverables:** `C:\temp\Audi-SCCM-Integration\` — plan markdown, three flow diagrams (SVG+PNG)
and a PPTX built from the user's "Package Builder.pptx" template ([[audi-ppt-template-facts]]).
