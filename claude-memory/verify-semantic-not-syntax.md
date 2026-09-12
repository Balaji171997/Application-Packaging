---
name: verify-semantic-not-syntax
description: "For Package Builder, \"verify\" means semantic correctness + review-flagging, not just parse/structure"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

When the user asks to verify generated PSADT packages, parse-clean / structure-complete is NOT enough. They
want **semantic** checking: is the generated `.ps1` MEANINGFUL and correct for the *new* version, does it match
what the live package does, and is everything that needs human attention actually flagged for review.

**Why:** a script can parse perfectly yet be wrong - e.g. predecessor reuse swaps the version but leaves the
predecessor's product-code GUID in the SoftIdent detection key; v4 CUSTOM-VARIABLES that read
`$adtSession.DeploymentType` are silently empty; a reused `.inf`/answer file embeds the old version. These all
parse fine and would have shipped broken.

**How to apply:** check real example packages (tool-generated vs the live one), confirm carried-over identifiers
were updated or flagged, and confirm review items are surfaced. The engine has `Get-ScriptReviewFindings`
(Build.ps1) for semantic findings, surfaced via `Get-CombinedReview` in the Step-3 review popup/button and the
Step-4 checklist. Add new semantic checks there. See [[ps51-list-object-wrap]] for a related gotcha in that code.
