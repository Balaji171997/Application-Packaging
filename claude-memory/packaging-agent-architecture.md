---
name: packaging-agent-architecture
description: "THE governing rule for PackagingAgent - the AI is the brain, the agent is the hands (Software Center analogy); the tool never decides, never edits AI commands, never rewrites the template"
metadata:
  node_type: memory
  type: project
  originSessionId: a96ed47a-37eb-4079-887f-9966cf709555
  modified: 2026-09-26T13:03:17.469Z
---

**The AI is the brain. The agent is the hands.** The user's own analogy (26 Sep 2026): SCCM's Software
Center sits on the machine, connects, syncs, fetches and pushes - and decides nothing; the site server
decides. This agent is Software Center, the AI is the site server. Use it to settle design questions.

The goal: an agent that packages like an engineer with 10-15 years in THIS team, needing little effort
from the packager, and that talks to a human when it genuinely must. Best-in-market is the stated bar.

## The agent's four jobs, and no others
1. **Give the AI information** it cannot see from where it sits.
2. **Act on the machine for it** - installs, snapshots, extraction, MSI reads, traces, `run_powershell`.
3. **Train it** - playbook, corpus priors, parameter intents, reboot rule, house style, AND a description
   of the tool itself, sent with every call.
4. **Talk to the packager** - show progress, ask only what needs a person.

## Never
- **Decide.** The tool measures ON REQUEST and reports; meaning is the AI's. Checks are exposed as
  CALLABLE TOOLS (`check_script_parses`, `compare_section_sizes`), not pre-computed facts pushed at it.
- **Edit what the AI wrote.** Run the command as given, or refuse it and say why. No silent "repair"
  (a `Repair-AgentEscapedCommand` was built and then deliberately removed for this reason).
- **Rewrite the template.** Fixed; only the injected sections change.

## The 3 house rules the tool DOES enforce (user's explicit instructions)
1. On a reuse the **predecessor's source file is kept** - only the install instructions doc can change it.
2. A **reused predecessor script is never written over**; changes apply in place, uncovered findings are
   reported to the packager.
3. **Only a pass completes** - `fix_needed` stamps verify as failed, never done.

Full write-up: `PackagingAgent\Docs\What-this-is.md`. See [[ai-agent-integration-plan]] and
[[packaging-agent-external-tools]].
