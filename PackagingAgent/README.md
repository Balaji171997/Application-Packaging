# Packaging Agent

An AI packaging engineer for the team's PSADT v4 packages. The **AI is the brain**: it reads the order, finds the
previous version, chooses the route, says exactly what to install and what the test must prove, judges what the
machine showed, and checks and finishes the built package. **This agent is its hands and its training**: it
gathers everything the AI needs, runs what the AI decides on this workstation, measures, builds from the team's
template — and carries the knowledge that makes a model behave like a packager with fifteen years here.

The closest thing in our own world is SCCM: Software Center fetches, runs and reports and decides nothing; the
site server decides. When a design question comes up, ask: *is this the hands or the brain?*

**Standalone.** Everything it needs is in this folder; it never touches Package Assistance and is never integrated
into it. PowerShell 5.1 only — no Python, no modules to install.

---

## The flow

```
intake → plan → prepare → evaluate → build → verify → handover
 hands    AI     hands     hands+AI   hands    AI       hands
```

| Stage | Who | What happens |
|---|---|---|
| **intake** | hands | Copy the order locally (file dates kept), fingerprint every installer, read the form's tick boxes, look for the previous version by name, look it up in the catalogue. No judgement. |
| **plan** | AI | One job on the **dossier**: settle the predecessor, choose the route, the exact install lines with their sources, what the test must prove, what must come off this machine first, and the package itself (changes to the reused script, or extra steps for a fresh one). Questions for the owner. |
| **prepare** | hands | Hand the packager what only a person can do (record a response file, supply a licence) — exactly as the plan asked. |
| **evaluate** | hands, then AI — **your go-ahead first** | Remove what the plan said, baseline snapshot, run the plan's lines one at a time (optionally the previous version first), snapshot again. The AI judges what the installer really did. |
| **build** | hands | From the predecessor's script (the plan's changes applied as written) or fresh from the template (the plan's steps under the markers). Delivered files placed with their folder tree. |
| **verify** | AI | Reads the built script against the order, the source, the test and the predecessor; fixes it in place with `edit_script`; runs `check_package`. **Only a pass signs it off.** |
| **handover** | hands | Evaluation sheet, `agent-handover.json`, the snapshot report Package Assistance loads — and the order is added to the case library. |

When a stage fails, the AI looks first (whose fault, what next); a person is asked only when it says so. When
the packager types in the chat box, the AI answers — while a stage runs, on its next round.

## How the AI works, cheaply

- **The dossier** — everything true for the whole order, sent once as the first message: the documents **in full**
  with their screenshots, every delivered file, the previous package opened with its whole script, what is installed
  on this machine, the template's toolkit, what the team knows about these installers, and the closest past cases.
  The screenshots are dropped once the plan has been made from them.
- **Jobs, then folds** — each job (plan, judge the test, verify, …) works with its hands until it submits one
  result; then its working turns are folded into two short lines: what was asked, what was decided. Every later
  request is about the size of the dossier, not the size of everything ever said. The stable prefix (handbook +
  dossier) is what a caching gateway serves cheaply.
- **Checked once** — the hands check what they can see for certain (is the named installer really delivered, is a
  delivered transform applied, does a *pass* survive the mechanical checks) and send the answer back **once**.
  That is what keeps a cheaper model from shipping a careless answer.
- **Hands, not scaffolding** — `run_powershell`, `read_document`, `open_package`, `search_previous_packages`,
  `read_knowledge`, `take_screenshot`, `remember_this`, and on a built package `edit_script` / `check_package`.

Model: `gemini-2.5-pro` for every job (fallbacks `claude-sonnet-4.6`, `gpt-5.1`, used only when it is unavailable).
`agent.settings.json` holds only the connection (URL, token URL, client id, client secret, API key, headers), the
model, the fallbacks and `MaxCostPerPackageUSD`, which stops any order that runs away. Prices for that cap live in
the code.

**The test install is patient and honest**: an installer is started the way deployment starts it (no shell, no
security prompt; an MSI with the template's own parameters), watched while it works, and when a window sits still the
AI is shown the screen and says what it is. What the install opens afterwards is judged and closed, the uninstall is
tested the same way, and the judgement is checked against what the machine really showed.

## It keeps learning

`Knowledge\` is the training (see `Knowledge\README.md`): how to work, the installer playbook, switches measured
across 238 shipped MAN packages, diagnosed problems, what the packagers have said, research notes — and
**`Cases.json`, written automatically at every handover**. The next order of the same vendor, application or
technology starts from those worked examples, and from the ~900-package catalogue in `Engine\`.

---

## Folder layout

```
PackagingAgent\
├─ Run-PackagingAgent.cmd        double-click to start (or drop an order folder onto it)
├─ Start-PackagingAgent.ps1      the launcher: loads everything, opens the window
├─ Invoke-PackagingAgent.ps1     headless: -Folder <order> [-Stage <id>] [-Flow] / -Newest N
├─ agent.settings.json           endpoint, model, key + secret — GIT-IGNORED, never shared
├─ agent.settings.example.json   the same without secrets
├─ engine-settings.json          share paths (Incoming, live packages, work folder)
│
├─ Src\                          the agent
│   ├─ Agent.Brain.ps1           the dossier, the job runner + fold, the hands, the schemas, every AI job
│   ├─ Agent.Prompts.ps1         the handbook (system prompt) and the job briefs
│   ├─ Agent.Core.ps1            the sheet, the flow, intake, build, the install runner, the report
│   ├─ Agent.Tools.ps1           7-Zip, MSI library, autorunsc, Procmon, memory, case library, catalogue
│   ├─ Agent.Ops.ps1             run_powershell: guarded execution, activity log, transcript
│   ├─ Agent.Gemini.ps1          the gateway: token, request, retries, audit, cost (incl. cached tokens)
│   ├─ Agent.Docs.ps1            .docx / .xlsx / legacy .doc readers
│   ├─ Agent.Console.ps1         the window: the flow, the channel, the feed, the chat box, the watcher
│   └─ Agent.Ui.ps1              WPF helpers, key dialog, runspaces, the handover export
├─ Knowledge\                    the training — see Knowledge\README.md
├─ Engine\                       the agent's own library (resolver, predecessor, snapshot, builders, catalogue)
├─ Template\                     the team's PSADT template — fixed, never rewritten
├─ Tools\                        7-Zip, WiX MSI library, Sysinternals (git-ignored), endpoint check, priors builder
├─ Tests\                        offline suite (scripted model, no network) + gateway tests
└─ Docs\                         How-it-works.md (the design) · Process-record.md (decisions and lessons)
```

## Run it

| How | What happens |
|---|---|
| `Run-PackagingAgent.cmd` | the agent window opens |
| drop an order folder onto the .cmd | the window opens with that order |
| `Invoke-PackagingAgent.ps1 -Folder <order>` | runs intake, plan, prepare, then prints the flow |
| `Invoke-PackagingAgent.ps1 -Folder <order> -Flow` | where this order stands; calls nothing |
| `Invoke-PackagingAgent.ps1 -Folder <order> -Stage verify -BuiltScript <path>` | one named stage |
| `Tests\Test-Agent.ps1` | offline tests — run after every change |

## Connection (VW LLMaaS)

```
BaseUrl      https://llmapi.ai.vwgroup.com/v1
AuthMode     token+key
ApiKeyHeader X-LLM-API-CLIENT-ID     ApiKeyPrefix "Bearer "
```

Both credentials travel, in two headers: `Authorization: Bearer <access token>` and
`X-LLM-API-CLIENT-ID: Bearer <API key>`. The client secret is as necessary as the key — a missing secret shows up
as a misleading 401. Key and secret come from the window (this session), `agent.settings.json`, `GEMINI_API_KEY`,
or Credential Manager. Stages run in background runspaces that re-load the agent, so any new credential setting
must also travel in `Start-AgentRunspace`'s payload.

## What leaves the machine

| Sent to the AI | Never sent |
|---|---|
| Document text (names, phones, e-mails scrubbed) and their screenshots | installers or any binaries |
| installer metadata, snapshot summaries, script text, command output | passwords, credentials |

Every request and response is audited under `WorkRoot\AI\<package>\`.

## Rules when editing

- Save every `.ps1` as **UTF-8 with BOM**.
- The AI decides; the hands never choose a command, never tidy one the AI wrote, never rewrite the template.
- Protected, always: the network shares and the predecessor package are read-only; the built deploy script is
  edited in place, never replaced. Local disk is the AI's workshop.
- Run `Tests\Test-Agent.ps1` after every change.
