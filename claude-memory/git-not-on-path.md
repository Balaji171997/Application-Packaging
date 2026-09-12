---
name: git-not-on-path
description: On this machine (AW140) git.exe is NOT on PATH; use the GitHub Desktop bundled copy via full path
metadata: 
  node_type: memory
  type: project
  originSessionId: 325ebea4-b654-4c60-a751-2fa1c1b03027
  modified: 2026-09-12T06:39:36.094Z
---

On the current machine (user AW140, Windows 11) `git` is not on PATH. The only git.exe is the one bundled with GitHub Desktop:

`C:\Users\AW140\AppData\Local\GitHubDesktop\app-3.6.5\resources\app\git\cmd\git.exe`

(The `app-3.6.5` segment changes when GitHub Desktop updates — glob `app-*` if the path stops resolving.)

**Why:** Verified 2026-09-12 while checking the memory migration; plain `git ...` in the PowerShell tool fails with "not recognized". Memory lives in the repo ([[memory-lives-in-repo]]), so git checks come up often.

**How to apply:** Call it via `& "$git" -C <repo> ...` with the full path, or `$git = (Get-Item "$env:LOCALAPPDATA\GitHubDesktop\app-*\resources\app\git\cmd\git.exe" | Select-Object -Last 1).FullName`. Don't assume `git` resolves. If the user later adds it to PATH, delete this memory.
