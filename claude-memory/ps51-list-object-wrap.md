---
name: ps51-list-object-wrap
description: "PowerShell 5.1 throws \"Argument types do not match\" when @()/comma-wrapping a List[object] of PSObjects"
metadata: 
  node_type: memory
  type: reference
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
  modified: 2026-07-21T10:35:36.046Z
---

On this machine (Windows PowerShell 5.1.26100), `@($list)` and `,$list` throw
`System.ArgumentException: "Argument types do not match"` when `$list` is a
`System.Collections.Generic.List[object]` containing PSCustomObjects. It is NOT property-name
related (a plain `[pscustomobject]@{A=1}` triggers it) and `List[string]` is unaffected.

**Use instead:** `$list.ToArray()`, `[object[]]$list`, or pipe-collection `@($list | % { $_ })` /
`@($list | ? {...})` — all work. This bit the Package Builder MST work (Read-MstSettings returning
`OtherItems`); the fix was `.ToArray()`. See [[ps51-setter-enum]] for the other PS 5.1 WPF gotcha found in the same round.

## The companion trap: `.ToArray()` is NOT enough on return

`return $out.ToArray()` **unwraps a ONE-element array into the bare object**, because the return
pipeline enumerates it. The caller then gets a PSCustomObject where it expected a collection:

```powershell
$rows = Get-VisibleRows          # 1 match -> $rows is a PSCustomObject, not an array
$grid.ItemsSource = $rows        # throws: cannot convert PSCustomObject to IEnumerable
$rows.Count                      # $null, not 1
```

**Always `return ,$out.ToArray()`** — the comma wraps once so the pipeline's unwrap hands back the
array itself. For a single scalar you must wrap the *array*, not the value: build a List, `.ToArray()`,
then comma it. `return ,$Value` on a bare object still yields a scalar.

Found in [[intune-app-report-tool]]: filtering to a lifecycle stage with exactly one app crashed the
WPF DataGrid every time. Any filter/search returning exactly one row hits it, so it looks intermittent.
This is the mirror image of [[ps51-convertfromjson-nesting]] — one wraps too much, this unwraps too much.
