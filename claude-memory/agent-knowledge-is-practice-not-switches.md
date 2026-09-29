---
name: agent-knowledge-is-practice-not-switches
description: "User rule for the Packaging Agent's knowledge: learn HOW the team packages/evaluates/handles issues from the whole shipped library, consolidated into Knowledge\\Corpus that travels with the tool - never a switch table, never live-share lookups at runtime"
metadata:
  node_type: memory
  type: feedback
  originSessionId: a96ed47a-37eb-4079-887f-9966cf709555
  modified: 2026-09-28T13:05:50.268Z
---

The agent's knowledge base must teach the AI **the team's practice** — how packages are laid out, how old versions
are removed, how updaters/shortcuts/per-user/reboots are handled, how issues were worked around, what evaluation
recorded (evaluation doc, owner form's packaging section, MRF, query mails, test logs) — learned from ALL shipped
packages and consolidated into files the tool carries (`Knowledge\Corpus\`, built by
`Tools\Build-CorpusKnowledge.ps1`). Not a list of switches for the AI to copy, and the AI must not consult the live
catalogue/shares for knowledge at runtime.

**Why:** fixed instructions break as soon as the machine or the brand changes; understanding the method carries
over. The user also wants it to keep learning every time (cases at handover, re-harvest as the library grows) and to
work well even with cheaper models.

**How to apply:** when adding knowledge, add evidence of practice with its source package, consolidated (patterns,
vendor profiles, lessons), and tell the AI to learn the practice and apply it to this order — never "use this
line". Keep the knowledge map `Knowledge\README.md` current. Related: [[packaging-agent-process-record]],
[[eqs-evaluation-corpus]].
