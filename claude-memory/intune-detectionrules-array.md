---
name: intune-detectionrules-array
description: "Intune create fails Graph 400 'detectionRules ... does not match schema' when ONE detection rule (branding-only) unwraps to a JSON object"
metadata: 
  node_type: memory
  type: project
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

**Symptom:** publishing to Intune fails with `Graph POST -> HTTP 400: "Property detectionRules in payload has a value that does not match schema."` ONLY when the "2nd detection = None (branding only)" is selected — with any 2nd detection (Version/String/ProductCode) it works.

**Root cause (PS 5.1):** `Get-IntuneDetectionRules` (Intune.ps1) builds a `List[object]` and did `return $rules`. With exactly ONE rule (branding-only), PowerShell UNWRAPS the single-element collection on return → the caller gets a bare **hashtable**, not an array. `Invoke-Graph` pipes the body to `ConvertTo-Json`, so `detectionRules` serialized as a JSON **object** `{ ... }` instead of an **array** `[ { ... } ]` → Graph rejects the schema. Two+ rules stay an array, so the bug is invisible until someone picks branding-only.

**Fix (final, MTB r203 + GPF r17):** function does `return $rules.ToArray()` (plain enumerable array, NO leading comma) AND the three call sites wrap `detectionRules = @(Get-IntuneDetectionRules ...)`. That yields a FLAT `[ {..},{..} ]` for 1 OR 2+ rules.

**TRAP I hit (r201/r16 was WRONG):** `return ,$rules.ToArray()` (comma idiom) TOGETHER WITH the caller's `@()` DOUBLE-wraps -> `detectionRules: [ [ {..},{..} ] ]` (nested), which ALSO 400s "does not match schema". The single-rule case rendered `[{}]` by luck so it looked fixed; 2 rules exposed `[[{},{}]]`. Pick ONE: comma-in-function + NO `@()` at caller, OR plain `.ToArray()` + `@()` at caller. NOT both. My first Test-Build assert missed it because it tested `(Get-...)` not the real `@(Get-...)` call - the corrected assert builds `@{ detectionRules = @(Get-...) } | ConvertTo-Json` and checks it is FLAT (`"detectionRules":\s*\[\s*\{` and NOT `\[\s*\[`), for both 1-rule and 2-rule.

**General rule:** an array-typed JSON payload from a List must be forced to an array so ConvertTo-Json emits `[...]` not `{...}` - but never comma-idiom AND `@()` together (double-wrap). Test the ACTUAL call-site expression, and assert flatness not just "starts with [". The branding registry rule itself was fine (keyPath/valueName='Revision'/detectionValue=Revision all populated; the G1V_ prefix and empty uninstall key were NOT the cause). See [[ps51-list-object-wrap]].
