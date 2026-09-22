---
name: pag-porsche-variant
description: "Porsche (PAG) Package Assistance = GPF code + settings.json (Family GPF, single target PAG, Order ID instead of AES); brand targets/order number are now settings-driven in the GPF code"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7d55d151-f242-4450-a165-3b37421965bd
  modified: 2026-09-22T05:38:38.639Z
---

**18 Sep 2026:** user asked for a Porsche variant "similar to GPF, only the package prefix (PAG) and Order ID
instead of AES, no brand dropdown, no VW/Group title rules, same GPF template". Built as
`PAG-PackageAssistance\` = copy of `GPF-PackageAssistance\` with its own `settings.json`
(`Brand.Name=PAG, Family=GPF, OrderNumberLabel="Order ID", OrderNumberPattern=[A-Za-z0-9][A-Za-z0-9._/-]*,
OutgoingPrefix={PAG:Porsche}`) and `$script:BuildStamp='PAG-2026-09-18.r1'`. Paths are placeholders under
`Downloads\Porsche\` until Porsche's real Incoming/Outgoing are known. No portable folder yet (user: first
MTB has to prove itself, then create `MTB_PackageAssistance` and `PAG_PackageAssistance`).

**Why:** one code base for the GPF family; a sister brand must be a settings file, not a fork.

**How to apply:**
- GPF code now reads brand targets from `Brand.OutgoingPrefix` keys (`Get-GpfTargetTags`,
  `Get-GpfDefaultTargetTag`, `Get-GpfTargetTagPattern`), the order-number shape from
  `Brand.OrderNumberPattern` / label (`Get-GpfOrderNumberPattern`, default AES when nothing loaded), and the
  GPF conventions in Build/GUI/Predecessor/Source/Mappings via `Test-PBGpfFamily` (`Brand.Family` else Name).
  The Step-1 brand combo is filled at startup and HIDDEN when there is one target. Brand rules stay keyed by
  tag (VWG/G1V/INA) - PAG matches none = defaults.
- Keep GPF and PAG code identical; edit GPF, copy the .ps1 files over PAG (not settings.json / BuildStamp).
- GPF harness fixes: `Test-CorpusConversion.ps1` and `Release-Check.ps1` now dot-source `BrandGpf.ps1`
  (they had silently failed every build with "Get-GpfTargetBrand not recognized"); Release-Check looks for
  `PackageAssistance.pak` (was PackageBuilder.pak). Corpus scan (random 120 sample from the live share) has
  pre-existing weaknesses: some v3 packages give brace imbalance / parse errors / "empty main section" -
  not from the brand change.
- Related: [[gpf-brand-variant]], [[mtb-package-assistance-rename]], [[gpf-portable-deploy-sync]].

**22 Sep 2026 - Porsche team review** (they had tested the OLD GPF copy). Already in place: Order ID free text
(all brands since 20.09, `Test-OrderNumberGate` always passes), PAG-only prefix, reuse+snapshot crash fix,
unblock after create (Assemble.ps1 last step), template change (config/icons/comments = no effect).
Added, all SETTINGS-driven so GPF is untouched (its settings.json has neither key):
- `Brand.AuthorOrder = "FirstLast"` -> `Format-AuthorName` swaps the directory's "Last, First" to "First Last"
  (GPF default LastFirst = "Prajapati Sunil"). No comma in the name = left as is.
- `Brand.NameLengthLimit = 34` -> `Update-NameLengthCounter` (GUI.ps1): text under the name box, LIVE on
  TextChanged FROM THE FIRST CHARACTER (partial name counted without '_', arch token, -0001; exact
  Get-GpfVwgNameLength once complete). GREEN up to 34, RED over: "N of 34 characters used (Manufacturer +
  Product + Version + Language) - K over the limit; consider a shorter name". Never a popup, never a block.
  34 = the same count as GPF's VWG hard stop; GPF keeps the hard stop and shows no counter.
- `Brand.NameAllowSpecialChars = true` -> Parse-Current refuses only folder-illegal chars (\ / : * ? " < > |),
  everything else is accepted and carried into the package name as typed; the space-next-to-underscore rule
  stays. GPF unchanged (letters/digits/. - _ space only).
- Predecessor location with OTHER credentials: `Get-PredecessorRoots` hands an unopenable root to the window's
  `Connect-PBShare` (1219 clear, Get-Credential x3, New-PSDrive -Credential, once per server per session);
  headless runs skip. Search order unchanged: request's own Predecessor\ -> settings PredecessorPath -> the
  "browse folder / pick .zip" prompt.
Team copy now at `PackageAssistance-Teams\PAG_PackageAssistance` (refresh: `Update-Teams.ps1 -Brand PAG`).
Porsche's real Incoming/Outgoing/Predecessor paths are STILL placeholders.
