---
name: msi-generatetransform-readonly
description: "MSI COM error \"GenerateTransform,ReferenceDatabase,TransformFile\" = output .mst is read-only/locked, not a no-diff"
metadata: 
  node_type: memory
  type: reference
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

WindowsInstaller COM `Database.GenerateTransform($refDb, $outMst)` quirks (PS 5.1, MstBuilder.ps1 Build-Mst):

- It THROWS `MethodInvocationException` whose `.Message` is just the comma-joined method+param names
  ("GenerateTransform,ReferenceDatabase,TransformFile") when it **cannot write $outMst** — i.e. the target
  path is **read-only** or **locked**. It is NOT a no-difference error and NOT a COM-binding bug.
- The real trigger in this tool: in predecessor reuse the vendor MST is copied from the **read-only LIVE share**
  into `Content\Files\` with the MSI's base name, so `$OutputMst == that read-only file`. Also if the vendor MST
  was just `ApplyTransform`-ed, the COM db still holds a handle to it.
- No-difference case returns **$false** (no file written), it does NOT throw. So if you then call
  `CreateTransformSummaryInfo($refDb, $outMst, ...)` it fails because $outMst doesn't exist.

Fix pattern (robust): GenerateTransform to a FRESH temp .mst → release all COM objects → THEN place the file at
$OutputMst (clear read-only attr + remove stale target + create dir first). If no diff, inject a benign marker
property (MTBTRANSFORM=1) and regenerate so a valid .mst always exists (the install `-Transform` must resolve).
Related: [[ps51-list-object-wrap]], [[verify-semantic-not-syntax]].
