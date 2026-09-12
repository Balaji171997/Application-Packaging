---
name: ps51-convertfromjson-nesting
description: "PS 5.1 - @(Get-Content x.json | ConvertFrom-Json) yields a NESTED array; assign first, then flatten"
metadata: 
  node_type: memory
  type: reference
  originSessionId: ff2c8d45-834f-45da-b4b7-19b87e7366ee
  modified: 2026-07-21T07:12:24.424Z
---

On Windows PowerShell 5.1, `ConvertFrom-Json` emits a JSON **array** as ONE pipeline item (it does not
enumerate). So:

```powershell
$a = @(Get-Content big.json -Raw | ConvertFrom-Json)   # WRONG: 1-element array wrapping the real one
$a.Count        # 1  (even with 801 objects inside)
$a[5]           # $null
$a | Where-Object {...}   # unrolls only ONE level -> $_ is the whole array
```

The nesting is vicious to spot: `.Count` lies, indexing silently returns `$null`, and member access on
the wrapper does **member enumeration**, so `$a.SomeIntField` comes back as an *array* — the visible
symptom is `Cannot convert "System.Object[]" to type "System.Int32"`, pointing at a line that looks fine.
Classification then computes ONCE over the whole blob and `$x | Add-Member` stamps that single wrong
value onto every element, so every row gets identical values (all "Standard", all "Retired").

**Fix — assign first, then flatten explicitly:**
```powershell
$data = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
$out  = New-Object 'System.Collections.Generic.List[object]'
foreach ($x in $data) { [void]$out.Add($x) }
return $out.ToArray()
```

`$x = <pipeline>` then `@($x)` works because assignment stores the emitted array itself; it is only
`@(<pipeline>)` that wraps. Code can appear to work by accident: a `return @(...)` inside a function
gets unrolled on output, hiding the bug until someone assigns the expression directly.

Same family as [[ps51-list-object-wrap]] and the single-element collapse in [[intune-detectionrules-array]].
Found while building [[intune-app-report-tool]] (loading an 801-app snapshot).
