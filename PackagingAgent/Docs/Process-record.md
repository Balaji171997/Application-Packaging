# Packaging Agent - process record

What this is, how it is meant to work, and what has been learned building it. Written so the work can be picked up
later without the conversation that produced it.

Last updated: 29 September 2026 (first field test - the evaluation rebuilt).

---

## The governing rule

**The AI is the brain. The agent is the hands.**

The agent never decides anything. It provides information and it carries out what the AI asks for on this machine.
If the AI has not said what to install, nothing is installed - "I don't know yet" is a legitimate state and it stops
the run rather than being filled in with a default.

This is not a style preference. Every time the tool has quietly substituted a decision of its own, it has produced a
confident wrong answer that looked right:

- an engine-default switch table invented `/qn REBOOT=ReallySuppress`, so a reuse trialled a bare silent switch on
  an MSI that ships a transform. Exit 0, healthy snapshot, a product nobody is shipping.
- a search reported `sameArchAsThisOrder: false` when nobody had told it which architecture to compare against. The
  AI read that as "not a match" and rebuilt from scratch with the real predecessor sitting on the share.

A missing input must read as *unknown*, never as *no*.

## The three tiers

| tier | what it is | what it does |
|---|---|---|
| **AI** | the model, off this machine | reasons, decides, judges |
| **Agent** | this tool | executes, observes, reports. Decides nothing. |
| **Endpoint** | this workstation | where installers actually run and get measured |

Named after the SCCM model the team already thinks in: site server, client agent, device.

## The flow

`intake (hands) → plan (AI) → prepare (hands) → evaluate (gate; hands install, AI judges) → build (hands) → verify (AI) → handover (hands)`

Two routes through it: **reuse the predecessor** (the normal case, and the job is small) or **build fresh**.

## The makeover (28 Sep 2026): why the brain was rebuilt

Measured before it: ~50k input tokens on *every* call, because every round of every stage re-sent the whole
conversation, and intake + reuse alone cost $2.63 on Sonnet. Eleven separate model stages (extract, assess, reuse,
machine, instruct, classify, retry, verify ×3, troubleshoot) each re-derived what the last had worked out.

The rebuild (details in `How-it-works.md`):
- **Three kinds of AI work** where a packager's judgement is needed: *plan* (one job replacing extract, assess,
  reuse, machine prep and instruct), *judge the test*, *check and finish the build*; plus troubleshoot, retry and
  consult when they happen. Everything else is the hands.
- **The dossier** replaces the opening briefing and every per-stage "context": the documents in full, the
  predecessor opened, the machine, the toolkit, the knowledge that fits, the closest past cases — once.
- **The fold** replaces compression as the main economy: a finished job leaves only what it was asked and what it
  decided. Later requests stay near the size of the dossier.
- **Checked once**: the hands send a result back once when it contradicts what they can see for certain
  (no install line, an invented file, an unapplied transform, a pass the checks refute).
- **Better hands** so rounds are not wasted on scaffolding: `open_package`, `edit_script`, `check_package`,
  `read_knowledge` (incl. the ~900-package catalogue and the case library).
- **The plan's reuse changes are applied by the build** as exact find/replace; verify fixes the rest in place.
- **Model**: `gemini-2.5-pro` — in the 26 Sep comparison it was the only model that both found the predecessor and
  concluded troubleshooting correctly, at under half Sonnet's price. Fallbacks Sonnet 4.6, GPT-5.1. Memory sorting
  used `gemini-2.5-flash` at first; since 29 Sep every job uses the one model (simpler settings, and the notes job is tiny).
- **Learning**: every handover writes `Knowledge\Cases.json`; the next order of the same vendor, application or
  technology starts from it.

Found and fixed on the way: the gateway converter added a phantom empty tool message after every text-only
assistant turn (`@($null).Count` is 1) — strict providers reject that; transcripts were never recorded because an
empty list is falsy; the out-of-steps fallback called the model without declaring its tools.

## Learning from the whole library (28 Sep 2026)

User: the catalogue must not be a table of switches the AI copies ("then if machine changes, brand changes, it
fails") — the way the team packages, evaluates and handles issues has to be learned from the packages we have, and
consolidated into a knowledge base the tool carries. So `Tools\Build-CorpusKnowledge.ps1` reads the shipped library
once (both live repos + Outgoing: 3,460 package folders) and writes `Knowledge\Corpus\` (index, per-vendor profiles,
patterns, vendor profiles, author lessons). The dossier carries the practice and the most similar packages; the AI
is told to learn the practice, not copy lines. Nothing reads the shares for knowledge at runtime.
Found on the way: the privacy scrubber turned digit runs inside GUIDs into `[phone]`, destroying product codes in
documents the AI read — GUIDs are now set aside before scrubbing.

## First field test, and the evaluation rebuilt (28-29 Sep 2026)

The packager ran two real orders (Firefox ESR 140.16 MSI+MST reuse; Kistler CEUS 8.6.6.16, Inno EXE) and reported:
evaluation must be patient, look at the screenshots properly, check the uninstall; `/qn` was added although the
template supplies it; the Run/Cancel prompt needed clicking; windows were left open; the Kistler package lost most of
the predecessor's configuration; a note written after the first run was not acted on. What was found:

| what happened | why | fixed by |
|---|---|---|
| Firefox MSI "not silent", then `/qn REBOOT=ReallySuppress` written into the package | the trial ran bare `msiexec /i x.msi TRANSFORMS=` - the template's `SilentParams` were never added, so the wizard showed | trial adds the template's MSI parameters + a log exactly as `Start-ADTMsiProcess` does; dossier states what the toolkit adds; `check_package` flags `-ArgumentList /qn` (it REPLACES the defaults); playbook no longer says `/qn` |
| Inno `/SILENT` killed after 12 s | "a window for 12 s = not silent" - but `/SILENT` shows a progress bar | activity-based patience; a still window is photographed and judged by the AI (`submit_look`) |
| Run/Cancel prompt on every attempt, one Cancel failed an attempt | `Start-Process -Verb RunAs` goes through the shell; the files carried ZoneId=3 from a downloaded zip | elevated session starts the process directly; download mark removed from local copies |
| CEUS window and a cmd window left open | cleanup only knew the installer's own children; the console was hosted by Windows Terminal | the family is everything started since go; after the installer ends, leftovers are photographed, judged, closed |
| the AI's retry lines were never run | loop condition `-not $trial` is false after round one | `$ranSequence` flag; a retry that needs a person stops the trial |
| decision claimed a response-file install that never happened, "seen" for steps only the package does | nothing checked a decision against the attempts | `Test-AgentDecision` (-Check): silent without a silent attempt, a file nobody made, seen-without-observation, proven line vs package line |
| Kistler built fresh: lost FreeSpace, ProcToBlock, driver removal, SID permissions, repair steps; `-ContinueOnError` on v4 functions | technology change (MSI -> EXE) taken as a reason to start again; parameters never checked | handbook: a new technology is still a reuse; `check_package` validates every parameter against the toolkit (incl. aliases) |
| the packager's note was not acted on | it sat 135,000 characters into the dossier | packager notes are the dossier's first section, "standing orders" |
| run 2 could not be diagnosed | the log was emptied at every start | the log appends every run (rolled at 5 MB) |

Then the packager's follow-up (29 Sep): **the predecessor's method first** - if it extracted the MSI from the vendor
EXE, do that again; another method (the EXE) only when it passes every test and is simpler - **decided by the AI from
the predecessor and the evaluation, never a per-application recipe**; the AI writes **full commands** and they must run
as written; the packagers' notes come first when sources contradict, but everything is read; and **the machine is
always given back** so the next round or test can run. So:
- `install.steps[].commandLine` (whole command) - the hands parse it (`ConvertFrom-AgentCommandLine`), the plan check
  sends back a line whose arguments disagree, the feed shows "AI's command / ran", and an MSI's log is read
  (`Test-AgentMsiLog`: package opened, transform applied or NOT, outcome). Instruction-document paths that do not exist
  here (`C:\SW-Source\x.mst`) resolve to the delivered file.
- MSIs a vendor EXE unpacks while it runs are **caught** (copied out of %TEMP% while they exist - 7-Zip cannot read
  Inno/InstallShield); prepare does 7-Zip extraction when the plan asks. `Get-AgentInstallerRoots`: order, extracted,
  caught, the previous package (its transforms may be reused).
- `methodChoice` (checked: leaving the predecessor's method needs a silent, proven install) and `testNext`: a **second
  test round** of another method on the cleaned machine, judged again; `buildFromTestRound` picks the lines the build
  uses (`provenSteps`); the skeleton places caught/extracted/predecessor files the order did not deliver.
- `Invoke-AgentMachineCleanup` before every further attempt and at the end of every round: new programs removed
  silently (entry's quiet line, MSI product code, Inno's documented switches - nothing else), their folders, shortcuts
  and the tasks/services/run entries pointing into them; the rest reported.
- Precedence written into the handbook (WHOSE WORD WINS): live packager > standing orders > owner's documents on WHAT /
  predecessor + practice on HOW > knowledge > reasoning; contradictions named.

Second Kistler field test (29 Sep, Firefox passed) - what went wrong, and the fixes:

| what happened | why | fixed by |
|---|---|---|
| three "Setup" windows in the taskbar, agent says nothing is open | the installer-help probe (`/?`, `/help`, ...) killed only `Ceus82.exe` after 10 s; its `Ceus82.tmp` stayed on its wizard. And `Get-Process` sees one window per process: Inno's wizard (`TWizardForm` "Setup - CEUS 8.2") is NOT the process's main window, so it was invisible | the probe ends everything it started and is skipped for documented technologies (Inno, NSIS, InstallShield, Burn); windows are listed with `EnumWindows` (every visible top-level window, owner, class) and closed by handle; stale copies of the installer are closed before an attempt |
| every job took 3 model calls; the AI's screen judgement lost ("Invalid JSON primitive: My.") | the fold wrote each finished job as a MODEL turn "My result (submit_x): {json}", and the model copied that shape instead of calling the function | the record now sits in the user turn; a result written as JSON text with all required fields is accepted (`ConvertFrom-AgentLooseJson`) |
| "stuck while loading processes" | Process Monitor recorded the whole trial (retries, AI waits) - gigabytes - then its export and `Import-Csv` took many minutes | recording stops after the plan's own attempts; export limited to 240 s; the CSV is read as a stream, only the rows used |
| the app and its bundled runtimes were left installed | the run never reached the end-of-round cleanup | the fixes above; cleanup runs before every further attempt and at the end of every round |

Packager, same day: the /? answer is usually a WINDOW - photograph it; send the AI the full screenshot, processes and
only RECENT log lines; repair = MSI repair / EXE repair switch / otherwise uninstall in Pre-Repair + install + post-install
config (pre-repair was being dropped); ProcToBlock held a process the new EXE runs itself, so the package failed; test
the built package before handover; and "we are creating helping hands and instructions - the AI does the work, a tool
only where it makes a job easier, with the AI free to do it itself". So:
- `Get-AgentInstallerHelpLook`: each help switch - console text or the window (screenshot + its words read via
  `PA.Win.Texts`); everything it started is closed. The picture goes to the retry and judgement jobs.
- `Get-AgentRecentEvidence -Since`: processes started since, every window now, logs written since (error lines + tail;
  the toolkit's `LogPath` from config.psd1, MSI logs, %TEMP%), MsiInstaller/application-error events. Given to screen
  looks, the judgement, the retry, troubleshooting and consult.
- `Get-AgentScriptPhases`: nine phases for v4 template regions, plain v4 functions and v3 `$installPhase`; check_package
  fails on `droppedFromPredecessor` (it found the dropped post-install, post-uninstall and post-repair on the real
  Kistler build) and reports processes in ProcToClose/ProcToBlock that the test install started itself.
- `test_package` (a hand in verify): `Invoke-AppDeployToolkit.exe -DeploymentType Install|Repair|Uninstall -DeployMode
  Silent`, watched; exit code meaning, windows + pictures, machine vs before, recent toolkit/MSI log lines. A pass goes
  back once if the package was never run, was edited after its last run, or the last run was not clean. Cleanup after.
- Handbook: REPAIR and process-list rules; "your hands are helpers, not a script you follow".

Then: the toolkit log of a package test goes to the AI in full (`Get-AgentToolkitLogs`, CMTrace markup stripped); MSI
logs stay as error lines + tail with their path, and the AI opens the whole file when troubleshooting. And **silent
means nobody touches anything**: any window the hands had to close - an error box the instructions call harmless, a
prompt, an application or console left open - is recorded in `neededIntervention` and makes the attempt, the uninstall
test or the package test NOT silent; the package has to suppress it. A progress window that goes by itself is fine.

Next run: the plan asked the PACKAGER to extract a delivered driver zip, with a wrong path in the command. Why: the
delivery listing showed only the first 150 files (the zip, three folders down, was not among them) and zips by name
only, so the AI never saw where the zip was or what was in it; and nothing stopped a plan from handing a person work
the hands can do. Now: `sources.keyFiles` (every archive/installer/driver/config file with its path, up to 400),
`sources.zipContents` (each zip's entries, read without extracting), `sources.folders` (every folder with counts and
kinds); prepare expands every delivered zip into the work folder (`expandedZips`, also searched for installers);
run_powershell states where the AI may write; the plan check sends back a humanNeeded that asks for listing,
extracting or copying; the handbook: never ask a person for what the hands can do.

Third Kistler field test (29 Sep, afternoon). What happened and what was changed (all general, no application named):
- The predecessor's main MSI was a CAPTURE (author "MAN Software Packaging", InstallShield); the vendor EXE never had one.
  The AI looked for an MSI to extract and concluded "the vendor no longer ships it". Now every MSI read gets
  `whoBuiltIt` (summary info: author, comments, creating tool - `Get-AgentMsiAuthorship`); the predecessor payload flags
  `capturedByAPackagingTeam`; the plan check sends back a plan that ignores it; the handbook: a captured predecessor
  means "capture the new version the same way" (a person's job - say so), everything else from the predecessor.
- The error dialog came from a MISSING PREREQUISITE (the instructions require a database client). The retry diagnosed
  it but asked the packager. Now `evaluate.prerequisitePackages` / retry `installPrerequisitePackages`: the hands
  install the team's package of it from the share (new baseline afterwards), and remove it after the package tests.
- 0 of 13 planned changes landed: finds copied from the v3 predecessor, the build converts to v4. The dossier now shows
  a v3 predecessor CONVERTED; the build retries a failed find converted, then ignoring indentation (`Edit-AgentScriptTrimmed`).
- Verify ran out of 16 rounds: now the configured 30.
- The uninstall test only ran for a "silent" install: now whenever the install left an ARP entry.
- Cleanup left the drivers the setup added: `Remove-AgentAddedDrivers` (pnputil, only when no copy existed before);
  whatever a cleanup cannot remove is recorded (`machine-leftovers.json`) and removed before the next evaluation
  (`Clear-AgentEarlierLeftovers`); folders the predecessor script names that already exist are shown to the plan, and
  removeFirst may remove a folder.
- MSI catching: also every MSI named on a new msiexec command line, copied the moment the process appears; scans every
  1.5 s. A child a setup starts just as it ends is found in a last look for descendants and closed.

Then (packager): an MSI can be unpacked anywhere, not only in the temp folders - watch the event log too; prerequisites
are never installed from a share, and a prerequisite can have its own; and when a predecessor exists and the source
matches even partly, first reason why it was packaged that way, and only deviate with a good reason. So:
- the runner reads the MsiInstaller events while it runs ("Beginning a Windows Installer transaction: <path>") and the
  msiexec command lines, and copies every MSI they name the moment it is named; the events are kept on the attempt
  (`msiEvents`) even when the file was already gone.
- prerequisite packages carry an install order (their own prerequisites first, read from each package's script and
  documents), are installed from a LOCAL copy one by one, the chain stops at the first failure with that package's own
  toolkit log, and they are removed in reverse order after the tests.
- plan: `predecessorUnderstanding` (how it was packaged, why, what is different now, each deviation with its reason);
  the plan check sends back a plan without it when a predecessor exists, and a fresh build without reasons.

Then (30 Sep, Kistler again): the plan set readiness `blocked` because the Oracle Client package was not found; the
packager put it in C:\temp, the AI answered "okay, proceeding with the evaluation" - and nothing moved, because the
consult answer had no field for the packages and no way to lift the block. And the AI read the product code of last
version's MSI straight off the live library. So:
- **nothing is done on a share.** A share is listed or copied from, nothing else. `Use-LocalCopy` (Engine\Core) copies
  a file into `<work>\FromShares`, works on the copy and removes it; every MSI reader (product code, properties,
  authorship, arch, identity), 7-Zip listing/extraction, the transform check and the /? probe go through it. The runner
  refuses an installer or transform on a share. `run_powershell` refuses any command that does more than list/copy on
  a share path (`Test-AgentOpShareUse`, AST-based, follows variables and pipelines). `FromShares` is cleared at
  handover and when the window closes. The predecessor payload now carries each MSI's product code, read from a copy.
- **blocked means nothing can be run.** A plan with runnable steps and readiness blocked goes back (and is read as
  ask_ao if the check is ignored). A missing prerequisite is asked for and the test goes ahead - an error shows it is
  needed. A capture a person must make (`humanNeeded.beforeTheTest` false, or a capture/prerequisite request) no longer
  stops prepare: it goes to the handover, and the test, the build from the predecessor and the handover go on.
- **the consult answer acts.** `submit_consult` gained `prerequisitePackages` (replaces the plan's list, in order) and
  `unblock`; `Set-AgentConsultChanges` writes them to the sheet and the console carries on to the evaluation approval.

The uninstall is now tested after the judgement (`Invoke-AgentUninstallTest` + `submit_uninstall_review`); what it
settles goes into the decision the build reads. `agent.settings.json` is now only the connection, the model, the
fallbacks and the cost cap - prices live in code (they only serve the cap).

## One conversation per order

One conversation, held on the sheet (`Get-AgentConversation`) and never saved: the dossier, then two folded turns
per finished job. A resumed order starts again from the dossier plus the decisions saved on the sheet.

## Talking to it while it works

A chat box at the bottom of the window, always available.

- while a stage is running, the message is queued and picked up on the model's **next round**
- **during a long install**, the trial's wait loop drains it every 1.5s, stops the attempt, and records
  `stopped-by-the-packager` as the verdict
- when **nothing is running**, the message wakes a `consult` turn - same conversation, same tools - whose job is to
  answer, look first if looking helps, and say what changes

## Testing on the machine

The rules, all of which were paid for by a real run going wrong:

- **The machine is borrowed. Give it back.** Anything installed is uninstalled; anything started is stopped.
- **Run a package the way a package is run** - `Invoke-AppDeployToolkit.exe`, not the `.ps1` by hand. The `.exe`
  picks the host and architecture and sets the toolkit up first. Driving the `.ps1` tests a path nobody deploys.
- **Run an installer the way deployment runs it** - as a process, elevated, not through the Windows shell (no UAC, no
  "Open File - Security Warning"), the download mark removed from local copies, and an MSI with the template's own
  parameters (`Start-ADTMsiProcess` adds `REBOOT=ReallySuppress /QN` + logging from `Config\config.psd1`).
- **A window is not a verdict. Be patient.** Watch the whole process family (and Windows Installer); while anything
  uses CPU or disk it is working. Only a window with nothing moving is a question - photograph it and let the AI say
  what it is (progress / waiting for a click / the app or a console the install opened / a security prompt).
- **What the install opens after it ends** (the application finishing its settings, a console checking drivers - often
  hosted by Windows Terminal, which is not a child of the installer) is waited for, judged, and closed.
- **Test the uninstall too**, the same way, and compare the machine with the baseline.
- **One candidate at a time, never twice.**
- **An exit code is not a result.** Check what you predicted would appear.
- **When the packager speaks, they win.** They can see the screen; you cannot.
- **If you are stuck, say so.** Stuck and quiet is the one thing that wastes the whole afternoon.

### The comparison run, and what a diff cannot see

When the predecessor is installed first, the sequence is: clean snapshot → install predecessor → snapshot
(`predecessorFootprint`) → **uninstall it** → snapshot (`predecessorLeftovers`) → install the new version.

This matters because a package installs shared runtimes and its uninstall deliberately leaves them (removing a
shared runtime breaks whatever else depends on it). So after the predecessor is removed those pieces remain, the new
version finds them and **skips** them, and they never appear in its diff - making the package look like it does not
need them.

`predecessorLeftovers` is therefore **part of what the package installs**, even though the diff does not show it.
Whether to remove them is a question for the packager, not a decision for the agent.

### Observing, not inferring

A silent install and a stuck install are identical from a process handle. Three ways to actually see:

- `take_screenshot` - what is on screen. Settles "working or waiting?". Taken automatically after 60s of silence.
- `run_powershell` - what is running, with command lines. Finds the `.tmp` an Inno EXE extracted, the `msiexec` a
  wrapper spawned.
- `traceTheInstall` (Process Monitor) - what it did, step by step. The only way to see a wrapper's inner switches.

## Finding the predecessor

The folder name is the **weakest** evidence in the order - the parser is positional, so `EQS_Kistler_Ceus_x86_...`
reads its vendor as "EQS" and matches nothing. "No predecessor found by name" is a question, not an answer.

Order of work: the order folder itself → fuzzy on vendor and application → what the **files** say (installer name,
ProductName, manufacturer) → narrow by architecture and version. Two equally likely: **ask**.

## Defect log - the ones worth remembering

Each of these passed every check in place at the time.

| what happened | why | the lesson |
|---|---|---|
| version replacement missing, verification passed | `Get-AgentCheckTools` is a *simple* function; the caller's `-Version` landed in `$args` and vanished. The check skips the comparison when given a blank. | a check with a missing input returns a confident meaningless answer |
| a delivered transform never applied | only checked "files the script names exist", never the inverse | check both directions of every check |
| the window hung on troubleshoot | `New-AgentRunspaceArg` was **called but never defined** - it threw before the runspace started, so `Done` was never set | sweep for called-but-undefined functions |
| the whole window died | handler faults surface against `ShowDialog`; a timer stored in a dead local threw on `.Stop()` | handlers outlive the scope that made them - keep state on `$ctx` |
| three installer dialogs left on screen | cleanup looked for `Ceus82`; the process was `Ceus82.tmp`, and an elevated re-launch is not a child of what we started | look for what *appeared*, not only what you launched |
| chat box delivered nothing | drain only happened between model rounds; the run had failed, so nothing was looping | a queue nobody reads is worse than no queue |
| the conversation silently reset each stage | `return $list` **enumerates** - an empty `List[object]` returns `$null` | `return ,$list` |
| every call built a new inbox | `-not $emptyCollection` is `$true` in PowerShell | use `$null -eq`, not `-not` |

## Knowledge files

`Knowledge/` is the training, and where new lessons go — mapped in `Knowledge\README.md`: Method, InstallerPlaybook,
SwitchPriors (238 MAN packages), Troubleshooting, Experience (packager memory), **Cases** (every finished order,
written automatically), `Research\` (corpus findings, how a packager decides), plus the ~900-package catalogue in
`Engine\KnowledgeBase.Recommend.json`.

## Open

- **Live validation.** The rebuilt brain (dossier, plan/judge/verify jobs, fold, checks, case library) has passed the
  offline suite with a scripted model, but has not met the live model end to end. The packager tests it next.
- **Fluent icons.** The tier icons are hand-drawn vector paths. Needs `ic_fluent_brain_circuit_24_regular.svg`,
  `ic_fluent_person_24_regular.svg`, `ic_fluent_desktop_24_regular.svg` from microsoft/fluentui-system-icons (MIT).
