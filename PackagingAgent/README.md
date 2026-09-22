# Packaging Agent

A **standalone** AI agent for software packaging: reads an order (AO form incl. wizard screenshots, installers,
predecessor, knowledge base), says what is missing, evaluates the install on this machine (snapshot), proposes the
packaging method - and hands the result over as files. Gemini API, PowerShell 5.1 only; no Python, no modules.

It does **not** change Package Assistance. It only *loads* a Package Assistance folder as a library (its engine `.ps1`
files for source/predecessor/snapshot/knowledge base + its `settings.json` for the share paths).

## Run

| How | What |
|---|---|
| **`Run-PackagingAgent.cmd`** (double-click) | opens the agent window |
| drop an order folder onto `Run-PackagingAgent.cmd` | opens the window with that order |
| `Run-PackagingAgent.cmd /console` | text mode: pick an order, enter the key, get the summary + HTML sheet |
| `powershell -STA -ExecutionPolicy Bypass -File .\Start-PackagingAgent.ps1 [-Folder <order>] [-Tool <tool folder>] [-Console] [-NoModel]` | same, scripted |
| `Invoke-PackagingAgent.ps1 -Folder <order> -Open` / `-Newest 5` | batch intake (CLI) |
| `Test-Agent.ps1` | offline tests (fake model) - run after any change |

In the window: **Run intake** → missing items / questions or READY → **Start evaluation** (baseline snapshot → the
proposed silent install on THIS machine → after snapshot → the agent's keep/remove/disable verdicts) → **Show changes**
→ **Export for Package Assistance**.

## Files

| File | Role |
|---|---|
| `Start-PackagingAgent.ps1` / `Run-PackagingAgent.cmd` | executor: finds the tool library, loads everything, opens the window (or console mode) |
| `Agent.App.ps1` | the window (WPF): intake, evaluation state machine, export |
| `Agent.Gemini.ps1` | Gemini REST client: function calling, images/PDF parts, retries + model fallback, key handling, audit log, cost meter, offline transport double |
| `Agent.Docs.ps1` | readers for the order documents: `.docx` (tables, ☐/☒, screenshots + captions), `.xlsx`, order-folder classifier |
| `Agent.Core.ps1` | the agent: evaluation sheet, PII scrubber, facts + rule gaps, model tasks (form extraction → assessment → snapshot decision), install runner, reports |
| `Invoke-PackagingAgent.ps1` | headless intake |
| `agent.settings.json` (created from `settings.agent.example.json`) | model, cost cap, screenshots on/off, proxy - **never the key** |

## Where the tool library comes from

`Start-PackagingAgent.ps1` looks for a folder with `Core.ps1` **next to this folder** (`MTB-PackageAssistance`,
`MTB_PackageAssistance`, `GPF-…`, `PAG-…`, any `*PackageAssistance*`) or **inside** this folder, or takes `-Tool`.
So to move the agent to another environment, copy this folder plus one tool folder beside it.

## What comes out (`Export for Package Assistance`)

Under `WorkRoot\AI\<package>\` (WorkRoot from the tool's settings, default `C:\temp\PackageAssistance`):
- `evaluation-sheet.html` / `.json` - Declared / Observed / Decided, questions for the AO, ranked install candidates, verdicts
- `agent-handover.json` - install args, uninstall command, product code, detection, per-user mode, cleanup commands, notes
- `NNN-<task>.json` - every model request/response (audit; image bytes replaced by their size)

And `WorkRoot\Reports\<package>.snapshot.json` - the same file Package Assistance's own analyzer writes, so the
packager loads it there with **Analyze installer → Load report…** and applies it as usual.

## Which key / endpoint (two providers)

| Your key looks like | Provider | Endpoint URL to enter |
|---|---|---|
| `AIza…` (39 chars) | Google Gemini API directly | leave empty |
| `sk-…` | an **OpenAI-compatible gateway** (company AI platform, e.g. VW/MAN gateway serving `gemini-2.5-flash-lite`) | the base URL that came with the key, e.g. `https://gateway.company.com/v1` |

A `sk-…` key sent to Google gives `400 API key not valid` - that is the wrong endpoint, not a wrong key.

**Gateway behind an identity provider** (you also got a *client id + client secret* and a URL ending in
`…/protocol/openid-connect/token` or `…/oauth2/token`): that URL is the **token endpoint**, not the AI API. Enter it
as *Token URL* with the client id/secret; the agent fetches an access token (client credentials, cached) and sends
`Authorization: Bearer <token>` plus the `sk-` key in an extra header. Which header the gateway wants differs, so the
verifier / *Test* button tries `x-api-key`, `api-key`, token-only and key-only in turn and keeps the one that answers
(`AuthMode` / `ApiKeyHeader`). The client secret is never written anywhere.
URL, model and key are typed at runtime (key dialog in the window, or the prompts in console mode); nothing is stored
unless you tick "remember" (URL + model → `agent.settings.json`, key → Credential Manager).

**Verify from your machine first:** `powershell -ExecutionPolicy Bypass -File .\Test-AgentEndpoint.ps1` - asks URL, model
and key (hidden) and reports each step: name resolution → proxy → service reached → key accepted → model answers →
**function calling works** (the agent needs tool calls). A wrong-network case shows as DNS/503 via the proxy ("host not
allowed from this network"), a licence/tenant problem as 401/403 ("key rejected"), a wrong model name as 400/404 plus the
model names the gateway lists.

## Key and data

Key lookup: typed in the window (session only) → `GEMINI_API_KEY` → Credential Manager `PackagingAgent-Gemini` (only
if "remember" was ticked). What leaves the machine: scrubbed form text (names/phones/e-mails removed), the wizard
screenshots (optional), installer metadata, snapshot summaries. Never installer binaries.

## Rules when editing

- Save every `.ps1` as **UTF-8 with BOM** (☐/☒ in the sources; PowerShell 5.1 reads BOM-less UTF-8 as ANSI).
- Never name a parameter `$Args`; keep the state variable `$script:PkgAgent`; inside WPF handlers use functions and
  the shared `$ctx` (a `$script:` variable does not resolve there).
- Run `Test-Agent.ps1` after any change.
