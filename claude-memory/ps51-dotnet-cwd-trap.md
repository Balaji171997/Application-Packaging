---
name: ps51-dotnet-cwd-trap
description: "Set-Location does NOT change [Environment]::CurrentDirectory, so .NET file calls resolve relative paths against the process directory - set both"
metadata:
  node_type: memory
  type: reference
  originSessionId: a96ed47a-37eb-4079-887f-9966cf709555
  modified: 2026-09-26T15:03:33.258Z
---

`Set-Location` moves **PowerShell's** location. .NET methods - `[IO.File]::ReadAllText`,
`WriteAllText`, `[IO.Path]::GetFullPath` - resolve relative paths against
**`[Environment]::CurrentDirectory`**, which `Set-Location` never touches. That stays wherever the
process started.

So in the same session, with the same relative path:

```powershell
Set-Location C:\some\folder
Get-Content 'x.ps1'                  # works   - cmdlet, uses PS location
[IO.File]::ReadAllText('x.ps1')      # FAILS   - .NET, uses process directory
```

The error names a path you never asked for (`Could not find file 'C:\where\the\process\started\x.ps1'`),
which reads like the file is missing rather than like you are in the wrong place.

**Always set both** when handing a working directory to code you did not write:

```powershell
Set-Location -LiteralPath $dir
[Environment]::CurrentDirectory = $dir
```

Cost us a whole live run (26 Sep 2026): every edit the AI attempted in `PackagingAgent` failed this way,
it spent its entire step budget retrying, and then reported a blocker it had already fixed. Fixed in
`Src\Agent.Ops.ps1`. Recorded as a case in `Knowledge\Troubleshooting.json` too, so the agent knows it.

See [[ps51-collection-and-path-traps]].
