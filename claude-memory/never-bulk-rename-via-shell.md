---
name: never-bulk-rename-via-shell
description: Passing quoted replacement strings through the Bash/PowerShell tool mangled every single-quote into P and corrupted two files — use Edit or a typed hashtable
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5f8c282b-8837-49ff-ba23-d8ac148e8fa6
  modified: 2026-09-16T06:01:51.912Z
---

On 2026-09-11 a bulk find/replace run through the PowerShell tool, with replacement pairs written as
`@("'PackageBuilder'","'PackageCompanion'")`, had its quotes mangled in transit. The effect was that **every
single-quote in Core.ps1 and Screenshots.ps1 became the letter `P`** (`'WorkRoot'` → `PWorkRootP`), and a
`D:\Dist\` path became `::\:ist\`. Both files were unparseable until restored from the MTB originals.

**Why:** the string passed through a shell layer that re-interpreted the quote characters before PowerShell saw
them, so the "search" string no longer matched what I thought and a stray `'`→`P` substitution ran across the whole
file.

**How to apply:**
- For a handful of edits, use the Edit tool — it matches exact text and cannot mangle quoting.
- For a genuine bulk pass, build the map INSIDE the PowerShell tool as a typed `[ordered]@{}` with plain string
  literals (`$map['old'] = 'new'`) — never as nested arrays of quoted strings in a one-liner.
- Afterwards ALWAYS parse-check every touched file and count single-quotes before/after; a file that dropped from
  ~200 quotes to 2 is corrupted even if nothing "errored".
- A first scan for corruption falsely flagged `SharePoint.ps1` because the pattern `P…P` matched the literal
  word **PnP**. Check the hits are real before "fixing" them.

**It happened AGAIN on 2026-09-16, a different shape of the same mistake:** a hashtable of
`@(@('old','new'))` pairs run through the PowerShell tool. PowerShell 5.1 FLATTENS a one-element
array-of-arrays, so `$e` iterated over the two strings and `$e[0]`/`$e[1]` were their first two
CHARACTERS — `.Replace('w','h')` ran over Watch-AudiSwDropFolder.ps1, `'('→'`'` over PROGRESS.md,
`'│'→' '` over README.md. All three rebuilt from git HEAD plus the session's edits.
**Rule now: multi-file text edits go through the Edit tool, one file at a time. No exceptions.**

Related: [[sharepoint-migration-status]], [[audi-sccm-integration-tool]].
