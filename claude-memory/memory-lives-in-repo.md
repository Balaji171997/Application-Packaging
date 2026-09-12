---
name: memory-lives-in-repo
description: This memory folder is a junction into Application-Packaging\claude-memory so it travels with the git repo across machines
metadata: 
  node_type: memory
  type: project
  originSessionId: 5f8c282b-8837-49ff-ba23-d8ac148e8fa6
  modified: 2026-09-12T06:02:15.085Z
---

The profile memory path `~\.claude\projects\<key>\memory` is a **directory junction** pointing at
`Application-Packaging\claude-memory`. Every memory written lands in the repo and is tracked by git, so a machine
move never loses history (set up 2026-09-12, after a move nearly did).

**On a new machine:** copy `Application-Packaging`, then run
`Application-Packaging\Setup-ClaudeMemory.ps1 -WorkingDir <the folder you will open Claude Code in>`.
It computes the profile key from that path and recreates the junction. Anything already in the profile folder is
merged in first (newer file wins), so nothing is lost either way.

**Why a junction and not a copy:** a copy is stale the moment the next memory is written. The junction means
there is exactly one set of files, and git sees them.

**Do not** put this folder under `.claude\` inside the repo - Claude Code uses that name for project settings and
commands, and mixing them invites confusion. It is `claude-memory` at the repo root, deliberately visible.
