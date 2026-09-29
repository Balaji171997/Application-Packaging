# How the Packaging Agent works

## The idea

A packaging engineer who is not at the machine (the AI) and an admin who is (the agent). The engineer reads,
decides and judges; the admin fetches, runs, measures, builds and reports — and never decides. The admin also
carries the team's training, so the engineer behaves like one who has worked here for years.

Three tiers, named after the SCCM model the team already thinks in:

| tier | is | does |
|---|---|---|
| **AI** | the model, off this machine | reasons, decides, judges |
| **Agent** | this tool | gathers, executes, observes, reports, builds — decides nothing |
| **Endpoint** | this workstation | where installers really run and get measured |

## One order, one conversation, few jobs

```
turn 0          THE DOSSIER  (everything true for the whole order, sent once)
job: plan       working turns ... submit_plan          -> folded to: "asked: plan" / "decided: {...}"
job: evaluated  working turns ... submit_decision      -> folded
job: built      working turns ... submit_verification  -> folded
(+ install_failed, stage_failed, consult whenever they happen)
```

The **system prompt** is the handbook (`Get-AgentSystemPrompt`) — identical on every request of every order. The
**dossier** is the first user turn and does not change after the plan (except that its screenshots are dropped
once planned from). Together they are a stable prefix, which is what a caching gateway serves at a fraction of
the price; `Add-AgentUsage` prices cached tokens at 25%.

**The fold** (`Close-AgentJob`) is what keeps the conversation affordable without losing the thread: when a job
submits, its working turns — every command, every output, every picture — are removed, and two turns replace them:
what was asked (with a one-line list of the hands it used and anything the packager said meanwhile) and the full
result it submitted. The next job knows every decision ever made on the order and carries none of the scaffolding.
Inside a job, old tool output is only shortened once the job's own turns pass ~90k characters, so the cache prefix
is not broken on every round; only the newest picture is kept.

A resumed order starts a new conversation (the conversation is never saved), seeded with the dossier plus the
decisions already on the sheet.

## The dossier (`New-AgentDossier`)

1. **The order** — package, RITM, the parsed name (with a warning that it is positional and often wrong), what the
   rules noticed, the form's tick boxes.
2. **What was delivered** — every file by name; installers with engine, architecture, version, MSI properties,
   7-Zip header listing; transforms; documents.
3. **The documents, in full** — instructions first (they outrank the form), then the form, other Word/Excel/text,
   with the embedded screenshots and their captions. PDFs and mails are named and flagged as unreadable here.
4. **The previous version** — when found by name: opened (`Open-AgentPackage`): whole deploy script, tree,
   configuration it ships where it differs from our template, what its Files folder installed. When not: the
   name-search candidates and a share search by what the files *are*, with the instruction that finding it is the
   AI's job.
5. **This machine** — related software already installed (so the plan can say what must come off), elevation,
   which evidence tools exist.
6. **Our template and its toolkit** — section markers, how a package is built, every function with its parameters.
7. **What the team knows** — `howThisTeamPackages` (the whole shipped library measured, from `Knowledge\Corpus\`),
   the playbook entries for the technologies actually delivered, universal rules, parameter intents, reboot policy,
   matching switch priors, diagnosed troubleshooting cases, packager memory.
8. **What the team did before** — the shipped packages most like this order (how each was built, what its evaluation
   recorded, what queries went to the owner, what its author worked around), this vendor's profile, the authors'
   lessons, and the orders this agent finished (`Knowledge\Cases.json`). The AI is told to learn the practice and
   apply it to this order's files and machine — never to copy a line blindly.

## The corpus (`Tools\Build-CorpusKnowledge.ps1` → `Knowledge\Corpus\`)

The shipped library (both live repositories + Outgoing, ~3,400 packages) read once, read-only, and consolidated:
an index, one profile per package (per-vendor files), the library's patterns, vendor profiles, and the authors'
lessons. Each profile is built with the engine's own reader (`Read-PredecessorModel`, which also converts v3
commands to v4 so both generations compare): layout, install/uninstall sequence, the operations of every phase, how
the previous version is removed, per-user, updater, shortcut and reboot handling, detection, the author's comments,
and the evaluation artefacts (the evaluation document's packaging-team section, the owner's form, MRF, complexity
matrix, validation reports, test logs, query-mail subjects — read from `Documents\` and from zips inside it).
Personal data is scrubbed; product codes are kept. It caches per package, so a refresh reads only what is new. At
runtime the agent reads only these local files — the knowledge travels with the tool.

## The jobs (`Invoke-AgentJob`)

| job | brief | result | hands | rounds |
|---|---|---|---|---|
| plan | `plan` | `submit_plan` | run_powershell, read_document, open_package, search_previous_packages, read_knowledge, remember_this | 14 |
| look at the screen (during a test) | `watch` | `submit_look` | none - the picture comes with the brief | 2 |
| judge the test | `evaluated` | `submit_decision` | run_powershell, take_screenshot, read_knowledge, remember_this | 10 |
| judge the uninstall test | `uninstalled` | `submit_uninstall_review` | run_powershell, take_screenshot, read_knowledge | 5 |
| nothing installed silently | `install_failed` | `submit_retry` | run_powershell, take_screenshot, read_knowledge | 6 |
| a stage failed | `stage_failed` | `submit_troubleshoot` | + read_document, search, open_package | 8 |
| check, test and finish | `built` | `submit_verification` | test_package, edit_script, check_package, run_powershell, take_screenshot, read_knowledge, remember_this | 16 |
| the packager speaks | `consult` | `submit_consult` | run_powershell, screenshot, documents, search, open_package, remember_this | 8 |
| sort what testing taught | `experience` | `submit_experience` | none (standalone) | 3 |

The runner: the packager's messages are delivered on the next round; a model that answers in prose is nudged once,
then asked for the same object as JSON (tools still declared, or strict providers refuse the request); a job that
runs out of rounds is asked to say so and summarise; the cost cap stops a runaway order; a failed job is folded too.

**Checked once** (`-Check`): the hands look at the result for what they can see for certain and, if something does
not add up, send it back once with the reason. The plan is checked for: no install line (unless loose files or
blocked), an installer that is not in the delivery, a delivered transform that neither the install line nor the
delivered-files list mentions, "no predecessor" with candidates on the table and no reason, a reuse without a
predecessor. A verification *pass* is checked against `Invoke-AgentPackageChecks` on the file as it is now.

## What the hands do with the decisions

- **Run proposal** (`Get-AgentRunProposal`) — the plan's first line and alternatives, reduced to arguments; several
  steps become a sequence. No plan → nothing runs, and the tool never invents a switch.
- **Machine prep** — removes exactly what the plan's `removeFirst` names; anything else related is left and reported.
- **Evaluate** — optional comparison run (install previous, snapshot, uninstall, snapshot), baseline, the trial or
  the sequence, MSI watch, autostart delta, Procmon trace and first-run look when the plan asked, after snapshot, the
  judgement, then **the uninstall test** (`Invoke-AgentUninstallTest`: the line the AI named, watched the same way,
  then the machine compared with the baseline) and its review, whose result goes into the decision the build reads.
  The decision is checked once (`Test-AgentDecision`) against what the attempts really showed.
- **Build** — `New-AgentNewPkg` from the plan (+ what the test changed, `Get-AgentPackageSpec`); reuse →
  `Build-PredecessorScript`, then the plan's `find/replaceWith` changes applied exactly (`Invoke-AgentPlannedChanges`,
  each must occur once and keep the script parsing; what cannot land is reported); fresh → `Build-FreshScript`, then
  the extra section steps under the markers (a step that does not parse is left out and reported).
- **Verify hands** — `edit_script` (exact, unique find/replace; refuses a change that would break parsing; keeps
  encoding and line endings; reads the change back) and `check_package` (parse, file consistency incl. unapplied
  transforms, command inventory incl. v3 names, template integrity, planned changes present, review markers,
  placement failures, section sizes versus the predecessor).

## How a line is run and watched (`Invoke-AgentInstallRun`)

- **Launched the way deployment launches it**: this session is elevated, so the process is created directly - no
  shell, no UAC, no "Open File - Security Warning". The download mark (Zone.Identifier) is removed from local copies.
  An MSI gets the template's own parameters and a verbose log (`Get-AgentTemplateMsiDefaults` reads
  `Config\config.psd1`; recorded as `templateDefaultsAdded`, `msiLog`), exactly what `Start-ADTMsiProcess` will add.
- **Watched patiently**: the family is what was started, what it started at any depth, anything new named after the
  installer, and Windows Installer's processes. While any of them uses CPU or disk, it is working. A window alone
  decides nothing.
- **Looked at when still**: a window with nothing moving for 45 s is photographed and the AI judges it (`watch` job):
  wait, close it, stop (not silent), or ask the packager. With no AI, the rule: two still periods = waiting.
- **Settled after the installer ends**: what it started gets time to finish; what it leaves on screen (the application
  finishing its settings, a console - on Windows 11 often in Windows Terminal, not a child of the installer) is
  photographed, judged, then closed. Everything still running from the install is closed at the end.

- **The AI's whole command** (`commandLine`) is parsed and run as written; the feed shows it beside what ran, and an
  MSI's verbose log says whether the package opened and the transform applied (`msiLogFacts`).
- **MSIs caught while it runs** (`-CaptureMsiTo`): new MSIs in %TEMP%/Package Cache are copied out (with their
  .cab/.mst) before the installer deletes them - the "extract the MSI from the EXE" the team does by hand.
- **The machine is given back** (`Invoke-AgentMachineCleanup`) before each further attempt and at the end of every
  test round: what the test added since the baseline is removed, what could not be is reported.

**Method and test rounds.** The plan states the predecessor's method (`install.method`). The judgement compares it with
what was proven (`methodChoice`: another method only when fully proven and simpler) and may ask for a second round
(`testNext`) - typically the predecessor's MSIs, caught in round 1 - which the hands run on the cleaned machine and the
AI judges again; the build uses the chosen round's `provenSteps`, placing files the order did not deliver from the
extraction, the catch or the previous package.

Verdicts: `silent`, `progress` (windows came and went, it finished on its own), `interactive` (a still window the
look said waits for an answer), `failed` (bad exit code, or could not start), `hung`, `stopped-by-the-packager`.
Silence alone is never success - the snapshot proves the install, and the AI checks each `mustProve` item, where
`seen` means observed here (`howSeen`), never "the package will do it".

## Learning

Every handover writes the order into `Knowledge\Cases.json` (`Save-AgentCase`); what the packager writes after
testing is kept on that case word for word and sorted into `Experience.json`. The next order of the same vendor,
application or technology gets those cases in its dossier. See `Knowledge\README.md`.
