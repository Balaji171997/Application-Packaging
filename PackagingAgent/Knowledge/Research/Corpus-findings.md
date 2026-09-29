# What the corpus actually says

Measured on the live shares, 25 September 2026 — **238 shipped packages** (Outgoing) and **136 open orders**
(Incoming). Everything below is counted, not assumed. It is the basis for what the agent has to be able to do.

---

## 1. The number that decides the design

| | |
|---|---|
| Orders with a shipped predecessor (same vendor + app + arch) | **29 (21%)** |
| Orders with **nothing to lean on** | **107 (79%)** |

**Four out of five orders are fresh.** The predecessor path — the one the tool already does well, and the one the
agent was being optimised for — is the *minority* case. The fresh path is the product.

---

## 2. What we actually package

From the 236 shipped scripts that could be read:

| Pattern | Share |
|---|---|
| EXE involved | **76%** |
| MSI involved | 57% |
| Both in one package | 35% |
| **More than one install call** | **59%** |
| MSI with a transform | 38% |
| Still PSADT v3 syntax | 24% |

Two consequences:

- **EXE is the norm, not the exception.** Silent-switch discovery is the single most valuable capability the agent
  can gain. An MSI is deterministic (`/qn REBOOT=ReallySuppress`); an EXE is a research problem.
- **A "package" is usually several installers**, in a deliberate order, with prerequisites. A design that assumes one
  installer fits only 41% of the corpus.

## 3. What the scripts do

| | Share | |
|---|---|---|
| Reboot handling (`Set-MTBReboot`) | 76% | near-universal, tool already does it |
| Branding detection key | 76% | near-universal, tool already does it |
| `ProcToClose` filled | 69% | comes from the app's own executables |
| Mentions licence / serial / activation | **48%** | a major recurring theme |
| Shortcut work | 47% | |
| Registry writes | 39% | |
| Copies files into place | 36% | |
| Kills processes explicitly | 25% | |
| **Version-pinned predecessor uninstall** | **19%** | so 81% remove the old version generically |
| Per-user: AllUsersRegistryAction | 22% | |
| Per-user: Active Setup | 8% | |
| **No per-user work at all** | **70%** | do not over-engineer this |
| Zip payload to expand | 11% | |
| Drivers | 9% | |
| Answer / response file | 8% | |
| Scheduled task / service / run key | 7-8% each | the auto-update surfaces |

Script size: **median 615 lines, p90 924, max 1857.** These are substantial scripts, not snippets.

---

## 4. What arrives in an order

| | Share |
|---|---|
| Complexity matrix (.xlsx) | 88% |
| Application owner's form (.docx) | 85% |
| A `source`-like folder | 55% |
| A `doc`-like folder | 40% |
| Zip payload | 18% |
| Vendor PDF | 14% |
| Transform (.mst) delivered | 13% |

**Installers delivered:** one 56%, two-to-five 18%, more than five 13%, **none at all 13%**.

**The folder layout is not standardised.** The eight most common shapes:

```
EQS_Docs, Icons, Source          51      (flat - no folders)              17
Docs_EQS, Icons, Vendor source   15      doc, source                      13
Docs_EQS, Icon, Vendor Source     8      Docs_EQS, Icons, Source           5
Content, Documents, Icons         2      Icons, Vendor Source              2
```

And **23% of order folder names do not parse** as `Vendor_App_Arch_Version-Release_Lang`.

**Order size: median 261 MB, p90 3.7 GB, max 36 GB.**

---

## 5. What this means for the agent

1. **Build for fresh, not for reuse.** 79% of orders have no predecessor. Reuse is a well-served special case.
2. **EXE silent-switch discovery is the highest-value capability.** 76% of packages involve an EXE, and this is
   exactly where the agent is weakest today.
3. **Multi-installer is normal (59%).** Install order, prerequisites and per-installer switches are core, not an edge.
4. **Never trust the folder shape.** The resolver must cope with at least eight layouts and with a flat folder, and
   the package name may not parse. Facts must be derived from content, not from naming.
5. **Licensing appears in half the corpus.** Recognising "this needs a licence server / key / activation" and asking
   the human is a first-class outcome, not a failure.
6. **Per-user config is the exception (30%).** Handle it, don't centre the design on it.
7. **The near-universal mechanics — reboot, detection key, ProcToClose — are already the tool's job** and are done
   well. The agent should not touch them.
8. **A quarter of shipped scripts are still v3.** Any predecessor the agent reads may be v3, so the conversion path
   and the command check matter as much as the build.
