---
name: package-record-design
description: "Agreed direction (Sept 2026, parked) for ONE record per package version replacing MRF/Complexity/EQS-Checklist/Evaluation docx/mails — SharePoint list + Power Apps + PB integration; user rejected per-app \"Application Card\" (too much data) and found the Declared/Observed/Decided sample sheets confusing"
metadata: 
  node_type: memory
  type: project
  originSessionId: f1cafd55-2e38-401d-a3f1-eeb2766a2dd3
  modified: 2026-09-14T12:31:40.183Z
---

**Parked on 2026-09-14 ("leave this for now, keep it recorded").** The user asked for an enterprise-level documentation model from AO → EQS → Packager → QA without duplication. Two earlier shapes were rejected:
- Declared/Observed/Decided "Evaluation Sheet" samples (EvaluationSheet\samples\evaluation-sheets.{json,html} in the repo, artifact https://claude.ai/code/artifact/b09a1c81-32a2-4fe8-b0c6-f3befb88e425) → "literally confusing", set aside.
- One "Application Card" per app holding all versions → rejected: too much data in one doc.

**Accepted direction:** ONE record per package version, 5 sections / one owner each, one Q&A thread, files stay in the existing SharePoint `PackageSources\Vendor\App\Version_Release\{source,doc,EQS,SCCM,Intune,Order}` layout.
1. Request (AO) — imported from the tagged Word form (not retyped); Word doc stays attached as home of screenshots.
2. Evaluation (EQS) — package name, installer type, silent params + **"provided by: AO/EQS/Packager"**, ARP, path, reboot, per-user, auto-update, leftovers, predecessor check, complexity points, verdict, corrections to 1.
3. Build (Packager, written mostly by PB) — commands, detection, product code, return codes, reboot, Active Setup, permanent cache, intentional leftovers, exceptions, how-it-was-done, reused-from-predecessor, logs + shortcut screenshots.
4. QA/Integration (QA) — standalone/upgrade/repair, Admin+SYSTEM, shortcuts, detection, pre-live SCCM/Intune ids, UAT group, defects, LIVE date, RFC, sign-off.
5. Lifecycle (system) — state, release no. (-0001/-0002), created-from-predecessor, handover dates.
States: Requested → In Evaluation → Waiting for AO → Ready to Package → In Packaging → Waiting for Clarification → Package Ready → In QA → UAT → LIVE → Retired. Thread list: record, question, from, to, asked, answer, answered, status (Power Automate mails via SWC).
Tech: SharePoint list + existing Power Apps portal + Power Automate; PB reads/writes the record via PnP (already working). Script change = new release record pre-filled from previous. Kills MRF, Complexity xlsx, EQS_Checklist, Evaluation docx, Release History xlsm, mails-as-documents.

**How to apply:** when the topic returns, start from the ~40-field column list + state/permission matrix; do NOT re-propose per-app cards or the three-column sheet. Related: [[eqs-evaluation-corpus]], [[pb-agent-story]], [[sharepoint-packagesources-layout]].
