---
name: no-heavy-runs-without-asking
description: "User's machine got stuck (30 Sep 2026) - never run the full PackagingAgent test suite or anything heavy (process-spawning tests, snapshots, corpus harvest, installs) without asking first; prefer small targeted checks"
metadata:
  node_type: memory
  type: feedback
  originSessionId: a96ed47a-37eb-4079-887f-9966cf709555
  modified: 2026-09-30T02:12:46.588Z
---

The user said "my machine got stuck yesterday please dont do anything that will make the machine stuck". A full run of
`PackagingAgent\Tests\Test-Agent.ps1` (started 30 Sep 04:11) was still hanging hours later and was killed.

**Why:** the full suite is heavy on this work laptop: it starts real stand-in processes and off-screen windows, takes
machine snapshots, runs the corpus harvester with 8 worker processes and the gateway test, and a leftover stand-in can
hold the run open indefinitely. Several runs were started back to back in the background.

**How to apply:** do not run the full suite (or harvests, installs, snapshots) without asking; one run at a time,
never in the background unattended; prefer loading the files and calling the one function being changed with a tiny
input; after any test, check no test process is left (and kill only my own). Related: [[packaging-agent-process-record]].
