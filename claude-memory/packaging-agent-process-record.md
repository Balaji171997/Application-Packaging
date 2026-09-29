---
name: packaging-agent-process-record
description: "PackagingAgent\\Docs\\Process-record.md + How-it-works.md are the durable record of the agent (28 Sep makeover; 29 Sep evaluation rebuilt after the first field test: patient runner, AI looks at still windows, uninstall test, decision check, parameter check) - read first when resuming"
metadata:
  node_type: memory
  type: project
  originSessionId: a96ed47a-37eb-4079-887f-9966cf709555
  modified: 2026-09-29T01:43:38.945Z
---

`PackagingAgent\Docs\Process-record.md` (decisions, defect log) and `Docs\How-it-works.md` (the design) are the
handover for the Packaging Agent. Read them before resuming.

The 28 Sep 2026 makeover: flow `intake → plan(AI) → prepare → evaluate(AI judges) → build → verify(AI) → handover`;
all AI work in `Src\Agent.Brain.ps1`; dossier sent once; jobs fold; `-Check` sends a result back once; hands
`open_package`/`edit_script`/`check_package`/`read_knowledge`; `Knowledge\Cases.json` + `Knowledge\Corpus`.

29 Sep 2026, after the user's first field test (Firefox MSI reuse, Kistler Inno EXE), the EVALUATION was rebuilt
(user: "concentrate on evaluation", patience, read the screenshots, check the uninstall):
- `Invoke-AgentInstallRun` (Agent.Core): direct CreateProcess when elevated (no shell -> no UAC / Run-Cancel
  prompt), Zone.Identifier removed from local copies, MSI gets the template's `config.psd1` params + log
  (`Get-AgentTemplateMsiDefaults`), activity-based patience over the whole process family, still window ->
  screenshot -> AI `watch` job (`submit_look`: wait/close/stop/ask), settle after exit, cleanup incl. Windows
  Terminal-hosted consoles.
- Uninstall test after the judgement (`Invoke-AgentUninstallTest` + `submit_uninstall_review`, merged into decision).
- `Test-AgentDecision` check; `Test-AgentScriptCommands` validates every parameter (aliases too; `-ContinueOnError`,
  `-ArgumentList /qn` on Start-ADTMsiProcess); retry-loop bug fixed (`-not $trial` stopped after round 1).
- Packager notes = dossier section 0 "STANDING ORDERS"; settings file slimmed (prices in code, one model for all jobs).
- Log appends every run (was wiped at start - run 2's "could not fetch source" failure could not be diagnosed).
- Offline suite ~395 tests incl. real-runner tests on off-screen stand-in forms.

**Why:** the user tests live; every defect above came from a real run. Never re-introduce "a window = not silent".

**How to apply:** still open = live re-test by the user (Kistler + Firefox again), corpus testLogs undercounted for
zips with backslash paths (fix applies on the next full re-harvest). See [[ai-agent-integration-plan]],
[[packaging-agent-architecture]], [[agent-knowledge-is-practice-not-switches]].
