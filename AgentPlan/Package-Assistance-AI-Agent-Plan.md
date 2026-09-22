# Packaging Agent — process-wide plan (v2, 19 Sep 2026)

Scope: the **whole packaging lifecycle** (order → evaluation → packaging → SAT → rollout → lifecycle), all brands
(MTB first; GPF/PAG share the engine). Package Assistance is one client of the agent, not its home.
Runtime constraints: packagers work on **Citrix VDI** (no local Hyper-V/Sandbox); test machines are **vSphere VMs**;
no Python/Node on the machines; EDR quarantines fresh binaries; German client, security-sensitive.
Model: Gemini API key — use `gemini-3.5-flash-lite` (2.5 Flash-Lite is retired 16 Oct 2026).

---

## 1. The idea in one picture

The agent is a **teammate with a mailbox, a share and a test VM**, not a button in a wizard.

```
   ServiceNow / MyOrder ──RITM──▶ Incoming share  ◀── AO uploads form + sources
                                     │
                                     ▼  watcher (scheduled task on a VDI/service session)
        ┌─────────────────────────────────────────────────────────────────────────┐
        │                    PACKAGING AGENT  (headless, PowerShell)               │
        │  channels: Incoming share · SWC mailbox (Outlook) · SharePoint           │
        │            PackageSources + EQS tracker · vSphere test VMs (PowerCLI)    │
        │            SCCM prelive · Intune Graph · Knowledge Base (894 pkgs)       │
        │  brain:    Gemini function-calling loop, allow-listed tools, JSON state  │
        │  state:    Evaluation Sheet per RITM (Declared / Observed / Decided)     │
        └─────────────────────────────────────────────────────────────────────────┘
                                     │ results, drafts, questions
                                     ▼
        Package Assistance GUI = REVIEW CONSOLE (gates) ── also Teams/mail notifications
```

The human never starts from a blank form again: every RITM arrives with a filled sheet, a proposed decision list, a drafted
mail and (once the VM stage exists) a proven install/uninstall — and only **approves, corrects or sends**.

---

## 2. The lifecycle, stage by stage — what the agent does, what stays human

| Stage (today) | Agent does (unattended) | Human gate | ROI lever |
|---|---|---|---|
| **1 Order intake** — RITM, AO fills Software Package Request form, uploads to Incoming (layouts are inconsistent: `doc\`/`source\`, flat, nested `7.19_0001\…`) | Watches Incoming; normalises the folder; reads the form (deterministic content controls/tables + Gemini for free text + **vision on the ~10 wizard screenshots**); fingerprints installers, MSI props, zips; checks licence/dependency/minor-update flags; looks up predecessor + catalogue history + KB vendor recipe; **triage verdict**: complete / incomplete / minor-update fast lane; drafts the **first mail within minutes** (missing files, contradictions with history, path mismatches, scope) | G1: send mail | ⅔ of packages need clarification today (250 mails / 151 pkgs). One complete mail on day 0 instead of rounds over days |
| **2 Evaluation (EQS checklist, 26 steps)** — install per instructions on test machine, ARP, clean uninstall, Admin + SYSTEM, reboot, predecessor, complexity, MRF, screenshots, icons, upload EQS folder, tracker status | Reverts a **vSphere VM** to its clean snapshot, copies sources, runs the ranked switch candidates (form → predecessor → KB vendor → KB engine → engine default) until silent + ARP + clean uninstall; detects prompts/dialogs; before/after snapshot; classifies diff (**app / bundled extras / autoupdate / per-user / noise**); finds autoupdate recipe; proposes Decided rows with evidence; fills complexity matrix; shortcut screenshots; parses AO replies into the sheet; writes EQS folder on SharePoint; updates tracker status | G2: approve Decided rows | The whole manual eval afternoon → 20–60 min unattended; evidence-backed decisions instead of memory |
| **3 Packaging** — PSADT package per brand template, predecessor reuse, MST, snippets, tests | Existing deterministic pipeline builds; agent authors only the delta (config files, registry, per-user/Active Setup, autoupdate-off, shortcuts-to-delete, prerequisites, response files); semantic **reviewer** pass vs house standards; VM runs Standalone / Upgrade / Predecessor / Admin / System, logs into `Documents\Logs\…`; MRF, QA checklist, docx "packaging team" section, sheet export | G3: sign-off → Outgoing / SharePoint | First-pass package that already passes our own QA list |
| **4 SAT (22 steps)** — prelive SCCM app, Software Center install/uninstall/repair/upgrade, shortcuts, install-dir counts, logs, SysTracer, detection, Test Hive | Publishes to prelive (engine exists); on an SCCM-client VM runs the SAT list, collects logs/SysTracer/detection proof; writes SAT report | G3b: SAT accept | SAT becomes a report to read, not a day to spend |
| **5 UAT / rollout** — UAT group/collection, AO confirmation, go-live, retire predecessor | Assigns UAT (engines exist: SCCM2IntuneMigrator, Intune UAT group naming); mails AO with test instructions; **monitors install results** (Intune App Monitor / IntuneAppReport already in repo); reminds AO; prepares go-live change; updates lifecycle stage in Intune Notes JSON | **G4: go-live — never automated** | Fewer forgotten UATs, status always current |
| **6 Lifecycle** — vendor updates, retirements | **Update radar** for the top vendors (Microsoft 41, Vector 36, Autodesk 31, Adobe 22, Dassault 22, Siemens 20, Citrix 17 … ≈ 50 % of live apps): detect new versions, pre-evaluate as minor updates before the AO asks; SAP8_UpdateNotifier pattern generalised | G1 | Turns reactive updates into a queue that is already half done |
| **Cross-cutting** | Every human correction at a gate becomes a KB row / few-shot example; monthly metrics (hours per package, rounds, first-pass QA, RITM→Outgoing lead time); full audit log per RITM | – | Proves ROI to the client with numbers, not opinions |

**Fast lane**: minor update ☒ or known-vendor predecessor with "same as predecessor" → stages 1–3 run back-to-back, one combined
sign-off at G3. **Standard lane** for new products keeps G1 and G2.

---

## 3. Architecture (brand-neutral core, thin clients)

```
Application-Packaging\
├─ PackagingAgent\                 ← NEW, brand-neutral core (shipped inside each tool's pak AND runnable headless)
│   Gemini.ps1        REST client: generateContent, tools[], responseSchema, inlineData (png/pdf), retries, token+cost meter,
│                     audit log WorkRoot\AI\<RITM>\NNN-request/response.json
│   Agent.ps1         loop: goal + state → model → functionCall → dispatch → functionResponse …; step + cost budgets; resumable
│   Tools.ps1         allow-listed registry (name, JSON schema, handler, side-effect class: read / vm / draft / deliver)
│   Scrub.ps1         PII scrubber (AO/cost-centre names, e-mails, phones) before any request
│   Sheet.ps1         Evaluation Sheet v1 (from EvaluationSheet\samples): load/save/merge/diff, html + xlsx render
│   Intake.ps1        stage-1 tools: folder normaliser, AO form reader (OOXML), screenshot extractor, complexity xlsx reader
│   TestVm.ps1        vSphere driver: PowerCLI Set-VM -Snapshot ▸ wait GuestOperationsReady ▸ Copy-VMGuestFile ▸ Invoke-VMScript
│                     (Admin) ▸ PsExec -s inside the guest for SYSTEM ▸ fetch results; WinRM fallback
│   Mail.ps1          Outlook COM: read SWC mailbox, parse .msg, create DRAFTS (never sends without the gate)
│   Docs.ps1          OOXML writers: MRF.xlsm, QA checklist, docx section, complexity matrix
│   Invoke-PackagingAgent.ps1   CLI / scheduled-task entry: -Ritm <folder> -Stage intake|prove|build|docs -Brand MTB|GPF|PAG
├─ MTB-PackageAssistance\  GUI gets an "Assistant" drawer (transcript · current tool call · Approve / Edit / Reject · cost)
├─ GPF-PackageAssistance\  same drawer, brand profile from settings.json
└─ PAG-PackageAssistance\
```

Settings (`settings.json`, each brand copy):
```json
"AI": {
  "Enabled": true, "Provider": "gemini",
  "KeySource": "CredentialManager:PackagingAgent-Gemini",
  "Models": { "extract": "gemini-3.5-flash-lite", "decide": "gemini-3.5-flash-lite",
              "author": "gemini-3.5-flash-lite", "review": "gemini-3.5-flash-lite" },
  "MaxStepsPerStage": 40, "MaxCostPerPackageUSD": 5,
  "SendScreenshots": true, "GroundingSearch": false,
  "FastLane": { "MinorUpdate": true, "KnownVendorPredecessor": true },
  "TestVm": { "Type": "vSphere", "VCenter": "vcenter.example", "Vm": "PKG-TEST-MTB-01", "Snapshot": "Clean",
              "GuestCred": "CredentialManager:PackagingAgent-Guest" }
}
```
Rules: API key and guest credentials live in **Windows Credential Manager** (DPAPI), never in files. Tools with side-effect
class `vm` only run files from the RITM folder; class `deliver` (copy to Outgoing/SharePoint, publish, assign) only after a
gate. There is **no shell tool** — the model can only call what is registered. `AI.Enabled=false` = today's tool, unchanged.

Model use vs rules (unchanged principle): **facts from tools, judgement from the model, approval from the human.**
Deterministic: form fields, fingerprints, MSI props, predecessor/KB lookup, snapshot capture, package assembly, parse checks.
Gemini: free-text + screenshot reading, switch choice when the ranked list is empty/contradictory, diff classification,
delta code, semantic review, mail wording, AO-reply parsing, free-text doc cells.

---

## 4. Environment answers

| Question | Answer |
|---|---|
| Where does the headless agent run? | A scheduled task in a VDI session (or a small Windows server) that can reach Incoming, the SWC mailbox, SharePoint and vCenter. Same `.pak` code as the GUI. |
| Test machines | **vSphere VMs, one per brand** (MTB / GPF / PAG images), each with a `Clean` snapshot, VMware Tools, a local admin for guest ops, PsExec for SYSTEM context, SCCM client on the SAT VM. PowerCLI runs on PS 5.1. Nested virtualisation on Citrix VDI is not assumed. |
| Sources to the VM | `Copy-VMGuestFile` or a share the VM can read; never over the API. |
| Data leaving the network | Form text (scrubbed), screenshots (wizard UI), installer metadata, snapshot summaries, script text. Never binaries. Paid tier: no training, ≤55-day abuse-monitoring retention (ZDR on request); **grounding search off** (its prompts are retained 30 days with no opt-out). |
| Cost | Flash-Lite ≈ $0.20–0.30 per package, hard cap $5, ≤ $100/month at 50 packages. ROI is measured in hours and rounds, not tokens. |

---

## 5. Delivery — Monday first, then stages

### Monday 21 Sep — "the agent is integrated and does intake"
Demo script (10 min):
1. Pick a real Incoming folder (IrfanView = simple exe with vendor FAQ pasted in the form; TopSolid = nested multi-installer + .NET prereqs; Siemens TopStart = 1.2 GB exe) — run `Invoke-PackagingAgent -Ritm … -Stage intake`.
2. Show the audit log (every model call, tokens, cost) and the **Evaluation Sheet** (html): Declared vs Observed, conflicts, gaps, ranked switch candidates with source, predecessor/KB hits.
3. Show the **drafted clarification mail** — and beside it the mail the team actually sent for a comparable package from Outgoing (same questions on day 0 = the ROI slide).
4. Open Package Assistance → Step 1 → **Assistant** button runs the same intake on the selected source, shows the sheet, and pre-fills installer / switches / predecessor for Step 2.
5. Flip `AI.Enabled=false` → tool behaves exactly as before.

Built 19–20 Sep (all inside `MTB-PackageAssistance\`, packed into the .pak; user decisions applied: no test VM → the
Citrix VDI itself is the evaluation machine via the existing snapshot engine; key typed per session, never stored; mail
draft dropped for now):
- [x] `Agent.Gemini.ps1` - REST client, function calling, images/PDF parts, retries + model fallback, audit log, cost meter, offline transport double
- [x] `Agent.Docs.ps1` - AO form .docx reader (tables, ☐/☒, screenshots + captions) + complexity .xlsx reader + order-folder classifier
- [x] `Agent.Core.ps1` - evaluation sheet, PII scrubber, deterministic facts (fingerprint, MSI props, predecessor, KB, catalogue) + rule gaps, model tasks (form extraction → assessment → snapshot decision), install runner, html/text reports
- [x] `Agent.UI.ps1` - Assistant window: Run intake → missing/questions or READY → Start evaluation (baseline → silent install → analyze → classification → change tree) → Apply to wizard
- [x] GUI: Assistant button on Step 1; `AI.Enabled` switch; `Apply-SnapshotResult` shared with the analyzer
- [x] `Invoke-PackagingAgent.ps1` CLI (`-Folder` / `-Newest N`), `Test-Agent.ps1` offline suite (all pass), Test-Build still green, packed build smoke-tested
- [ ] Monday: enter the key → API key dialog → Test → run intake on IrfanView / TopSolid / TopStart with the model → evaluate IrfanView on the VDI

Not for Monday: mail drafting/sending, docs writers, VM proving, SCCM/Intune stages.

### After Monday
| Stage | Weeks | Depends on |
|---|---|---|
| Prove on vSphere VM (stage 2) | 4 | vCenter access, one clean VM per brand, guest admin credential |
| Build + review + VM tests (stage 3) | 3 | stage 2 |
| Docs + SharePoint EQS folder + tracker (stage 2/3 paperwork) | 2 | SharePoint write (built, untested) |
| Mailbox integration: watcher + AO reply parsing (stage 1 loop) | 1–2 | SWC mailbox access from the agent session |
| SAT on SCCM-client VM (stage 4) | 2 | prelive publish (exists), SAT VM |
| UAT/rollout monitoring + update radar (stages 5–6) | 3 | Intune App Monitor / IntuneAppReport (exist) |
| Fast lane + learning loop + metrics | 2 | – |

≈ 4 months to the full lifecycle with gates; intake is live from Monday.

---

## 6. Market position

Robopack has the closest capability (cloud VM "Analyze & Test", PSADT wrapper) but is Intune-only, catalogue apps, sources
leave the network, no AO-form/RITM/clarification process, no SCCM, no MAN/VW templates, licence per tenant. Patch My PC =
catalogue updates only. Advanced Installer / Master Packager / AdminStudio = editors. PACE = workflow shell. None of them
reads a Software Package Request form, argues with history, drives the EQS/SAT checklists or knows 894 MAN packages.
Stage 2 gives us the one thing Robopack has that we lack; everything else is already ours.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| Flash-Lite weak on authoring/review | Per-task model override; measure reviewer-disagreement rate before moving a task to `gemini-3.5-flash` |
| Prompt injection from AO forms / readmes (untrusted text) | Allow-listed tools only, no shell, `vm` tools restricted to the RITM folder, `deliver` tools behind gates |
| Hallucinated switch | Nothing is Decided until the VM proves it silent + ARP + uninstall; intake only *ranks candidates with source* |
| vSphere/guest-ops not granted | Stage 2 falls back to a dedicated test client driven over WinRM/PsExec; intake, build, docs do not need a VM |
| Data protection | Scrubber, no binaries, audit per RITM, grounding off, `AI.Enabled` off = today's tool; ZDR request to Google if the client asks |
| API outage / budget | Every stage degrades to today's manual path; sheet keeps partial results; hard cost cap |
| Wrong keep/remove slips through | G2 shows each Decided row with evidence; fast lane only for minor updates / known predecessors |

---

## 8. Needed from you

1. **API key** → store it yourself: `cmdkey /generic:PackagingAgent-Gemini /user:api /pass:<key>` (I never see it; the tool reads it via Credential Manager). Until then I develop against recorded responses.
2. OK to write the agent as a brand-neutral `PackagingAgent\` folder in the repo, packed into each tool's `.pak`?
3. Monday demo on IrfanView / TopSolid / TopStart, or name three others?
4. Mail: text draft on disk is enough for Monday? (Outlook draft needs COM in the session.)
5. For stage 2 (after Monday): vCenter address, VM names per brand, whether guest ops via VMware Tools are allowed.
