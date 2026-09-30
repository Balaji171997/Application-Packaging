---
name: agent-evaluation-patience
description: "User rules for the Packaging Agent's evaluation: patient, AI classifies screenshots, test uninstall, never re-add template MSI params, predecessor's METHOD first (another only if fully proven + simpler), AI decides - no per-app recipes, full command lines run as written, always clean the machine"
metadata:
  node_type: memory
  type: feedback
  originSessionId: a96ed47a-37eb-4079-887f-9966cf709555
  modified: 2026-09-30T02:05:25.284Z
---

From the user's field tests and follow-ups (28-29 Sep 2026):
- wait/patience before judging; screenshots go to the AI, which classifies the window kind first; test the uninstall
- the PSADT template config already carries the MSI silent params - never add them again (test or package)
- **predecessor's method first**: if the predecessor extracted the MSI from the vendor EXE, do that again (catch it
  while the EXE runs if 7-Zip cannot); another method only when it passes every test case and is easier/more efficient
- **"dont hardcode the process for kistler lets Ai decide based on evaluation and predecessor best method"** - no
  application-specific recipes in code or knowledge; general rules only, the AI decides per order
- the AI must give the FULL command; the hands run exactly that and show it beside what ran
- the packagers' notes come first when sources contradict, but the AI must still read everything
- "always try to cleanup the machine to be able to test next round or next anywhere"
- the /? answer is usually a window: photograph it; give the AI full screenshots + processes + only RECENT log lines
- repair: MSI repair / EXE repair switch / else uninstall in Pre-Repair, install in Repair, post-install config in
  Post-Repair; never drop the predecessor's pre-repair; ProcToBlock must not hold processes the installer itself runs
- test the BUILT package (install/repair/uninstall, PSADT logs, screen) before handover - as a tool the AI calls;
  the PSADT toolkit log goes to the AI IN FULL; MSI logs as error lines + tail, the AI opens the full file when needed
- SILENT = nobody touches anything. Brief progress/splash is fine; ANY window that needs a click or close (error box
  "to ignore", prompt, app/console left open) = NOT silent even if the instructions say ignore - the package must
  suppress it. General rule, never phrase it as one application's case
- a predecessor MSI may be the TEAM'S CAPTURE (author "MAN Software Packaging", InstallShield) - then the method is
  "capture again" (a person's job) and everything else follows the predecessor
- MSIs can be unpacked anywhere - watch MsiInstaller events + msiexec command lines, not just temp folders
- prerequisites: copy locally then install (never from the share), in order incl. their own prerequisites
- predecessor exists and source partly matches -> first reason WHY it was packaged that way; deviate only with a reason
- "we are creating helping hands and instructions - the AI does the work; a tool only where it makes a job easier,
  and the AI keeps the freedom to do it itself"

**Why:** a 12 s "window = not silent" rule, bare-msiexec trials and a fresh rebuild lost the predecessor's config and
method on real orders.

**How to apply:** keep `Invoke-AgentInstallRun` activity-based with AI looks, `methodChoice`/`testNext`, and
`Invoke-AgentMachineCleanup` after attempts/rounds. Never write per-app instructions into Experience.json yourself.
Related: [[packaging-agent-process-record]].
