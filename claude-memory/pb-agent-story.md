---
name: pb-agent-story
description: Agent enablement story for turning Package Builder + packaging process into an AI agent (for the AI team)
metadata: 
  node_type: memory
  type: project
  originSessionId: c44559f7-24bd-4a86-bfcc-811c8a3625af
---

The AI team asked the user to write a "story" (agent enablement spec) to train an agent
to do the whole packaging process (Package Builder + manual steps) the way a human does.

Deliverable written 2026-07-06 at `C:\Users\AW140\Downloads\agent-story\package-builder-agent-story.md`
(kept OUT of `Downloads\files`, which is PB-only — see [[downloads-files-is-pb-only]]).

Structure agreed: split into sub-stories, not one end-to-end story. Format: markdown.
- Sub-story 1 = Build & prove: test EVERY install/uninstall param until confirmed working
  BEFORE finalizing; cross-check switches vs vendor/internet; NEW standard = detect & disable
  auto-update if present.
- Sub-story 2 = Verify against standards/reference (semantic, Done/Check report).
- Sub-story 3 = Deploy & register in ConfigMgr — HARD human-approval go-live gate.

Persona = junior/mid packaging engineer. This is the initial "main agenda" scope; to be
trained further later. Draws on team standards: [[verify-semantic-not-syntax]],
[[log-path-format-v4]], [[activesetup-house-style]], [[screenshot-keep-it-simple]],
[[force-kill-modal-dialog-ghost]], [[predecessor-reuse-report]], [[configmgr-provider-filter-trap]].
