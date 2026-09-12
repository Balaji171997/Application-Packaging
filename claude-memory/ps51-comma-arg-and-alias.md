---
name: ps51-comma-arg-and-alias
description: PS command-call gotchas — comma between args makes ONE array param (not two); bare helper names collide with built-in aliases (ni=New-Item)
metadata: 
  node_type: memory
  type: reference
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
  modified: 2026-07-21T10:35:49.358Z
---

Two PowerShell call-parsing traps that silently corrupt test data / scratch scripts (both bit me building Snapshot.ps1 tests):

1. **Comma between command arguments = a single array parameter, NOT separate positionals.** `MyFunc @{a}, @{b}` calls `MyFunc` ONCE with `$firstParam = @(@{a}, @{b})`. So `@( MkObj @{x}, MkObj @{y} )` collapses to ONE element (the 2nd `MkObj` runs, but the 1st `MkObj` is handed the whole `@{x}, <result>` array). Fix: parenthesize each call — `@( (MkObj @{x}), (MkObj @{y}) )`. (Spaces separate positionals; commas build arrays.)

2. **A short helper-function name can be shadowed by a built-in alias.** Command resolution order is Alias > Function > Cmdlet, so defining `function NI {...}` does NOT win — `ni` is the alias for `New-Item`, so `NI @{...}` calls New-Item and throws "positional parameter cannot be found". Avoid 2-letter helper names that are aliases (ni, gc, sc, rd, ls, cd, ft, fl, gm, ps, where, foreach...). Use a distinct name (MkI, etc.).

   **SINGLE-letter names are just as bad.** Hit again 2026-07-21 in [[intune-app-report-tool]]: a local
   `function H { param($t) ... }` for writing section headers silently resolved to `h` = **Get-History**,
   failing with *"Cannot bind parameter 'Id' ... cannot convert to System.Int64"* — an error that points
   nowhere near the real cause. Single-letter aliases that exist by default include
   **h** (Get-History), **r** (Invoke-History), and one-letter drive-ish names. Name inner helpers
   `AddLine` / `AddHead`, never `L` / `H`.

Related: [[ps51-list-object-wrap]], [[ps51-setter-enum]]. When a "list" mysteriously has the wrong count or a helper "isn't being called," check these before the logic.
