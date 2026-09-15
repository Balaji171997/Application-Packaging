---
name: eqs-evaluation-corpus
description: "What the real MAN package corpus looks like (Outgoing + CMLib_LIVE shares), the EQS→GPF→SAT process artefacts, and the \"Evaluation Sheet\" idea the user is shaping (Sept 2026)"
metadata: 
  node_type: memory
  type: project
  originSessionId: f1cafd55-2e38-401d-a3f1-eeb2766a2dd3
  modified: 2026-09-14T11:02:54.432Z
---

User (Balaji Gurram) is on the **MAN EQS team** = evaluation side (mail signature "MAN EQS"; sends queries via SWC service.softwarecoordination@man.eu to the AO; packaging team = "Clientmanagement Packaging-Team" / GPF). Evaluation-before-packaging is THEIR job → that's why it is the pain point.

**Shares (read-only observed 2026-09-14):**
- `\\mndemucfsm01\SEC-EQS-Lib-Gate\EQS_SEC\EQS\Packages\Outgoing` — 228 pkgs, layout `Content\ | Documents\ | Icons\`
- `\\mbddfsovpc01.mn-man.biz\SWDLive-Gate\CMLib_LIVE\Apps` — 919 live apps, same layout (Documents present in ~all)

**Documents\ per package (real artefacts):**
- `Installation instructions for MAN <App> <Ver>.docx` = AO's **Software Package Request form** (v1.x / v2.0) — fixed sections + ☐/☒ checkboxes + tables + avg ~10 wizard screenshots with captions ("Click Next", "Provide the location …", "Select features as shown below"). v2.0 adds SCCM/Intune split, Package ID (RITM), Silent-Param/Responsefile/Services/Certificates/Autostart/Autoupdate table, and a "filled by packaging team" section (install/uninstall/repair cmd, anticipated detection, return codes, reboot, Active Setup, permanent cache, intentional leftovers). Shortcuts-to-delete table maps 1:1 to Remove-ADTFile lines in final scripts.
- `MAN_MRF_<pkg>.xlsm` (Module Request Form, 102/228): Meta Data, Install-Uninstall, Prerequisites, **QA Checklist (30 items install/uninstall)**, Additional Information.
- `Complexity_Matrix_*.xlsx` v2.0 (16 criteria, points → small/medium/large/highly complex; e.g. known product −8, MST +5, >3GB +2, Active Setup +2, >45 min +4).
- `EQS_Checklist_MAN.xlsx`: EVAL sheet (26 steps: install per instructions on test machine, ARP check, clean uninstall, Admin+SYSTEM context, reboot check, predecessor check, complexity, MRF, mails copied, shortcut screenshots doc, icons, upload SharePoint EQS folder, PowerApps/EQS-tracker status) + SAT sheet (22 steps: pre-live SCCM via SCCMCreationandDeploymentAutomator 4.0, Software Center install/uninstall/repair/upgrade, shortcuts, install-dir counts, logs, SysTracer, detection, Test Hive).
- `.msg` mails: 250 across 151 pkgs (⅔ of packages need ≥1 clarification round). Subjects `[PKG-Order] Query and Information - RITM… | <pkg>`, `[Query]: RITM… | <pkg>`, `Repackaging Approval …`. Typical queries: predecessor handling contradicts history, path mismatch inside the doc, scope (MSI only), incomplete predecessor list, shortcut-test limits (licence).
- Logs `Standalone\ | Upgrade\ | Predecessor\ | Admin\ | System\` (PSADT + vendor logs); `Source Validator` Install/Uninstall_report html (**Source Validation Tool 1.0** — categorised before/after diff: Run/RunOnce, Active Setup, ARP, services, ODBC, fonts, printers, drivers, env vars, tasks, branding keys, shortcuts, hosts, certs, addins, context menus, folders, misc registry; noisy with McAfee/Defender) in 154 pkgs; SysTracer `.snp` in 103.
- Content: PSADT v4 168 / v3 49; MST in 73; response files (.iss/.properties/.rsp) ~60; non-empty SupportFiles 86; 59 pkgs have Upgrade-scenario logs.
- Vendor concentration (LIVE): Microsoft 41, Vector 36, Autodesk 31, Adobe 22, Dassault 22, Siemens 20, Citrix 17, Altair 16, SAP 14, MathWorks 13 → high predecessor-reuse potential.

**Evaluation Sheet idea (user's, being shaped):** one machine-readable sheet (Declared from AO form / Observed from fingerprint+snapshot+tests / Decided via packager or AO mail) that PB builds from; tool generates clarification mail, parses replies; complexity/MRF/QA/Additional-Info auto-filled. Constraints: no Azure, no Foundry; maybe M365 Copilot Chat (free tier) for unstructured bits; Windows OCR offline for screenshots. Decision pending ("will discuss again").

**How to apply:** ground any evaluation-automation design in these artefacts (parse the docx form deterministically; Source Validator categories = Observed schema; EQS/QA checklists = test matrix). Related: [[ado-pipeline-idea-dropped]], [[pb-agent-story]], [[sharepoint-packagesources-layout]].
