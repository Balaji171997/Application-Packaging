# Progress — Audi SCCM Integration Tool

Running record of what is built, what is pending, and every decision taken so
far. Update this at the end of each working session.

**Last updated: 10.08.2026** — flow 2 wired end to end; no person recorded anywhere on the SCCM side. Two detection rules (branding key + SoftIdent). The collector writes a heartbeat after every step, so the window follows a job live and picks it back up after being closed. 334 tests passing.

---

## Where we are

| Increment | State |
|---|---|
| 1. Configuration foundation | **Done** |
| 2. SCCM engine (12 operations, preflight, retry, audit) | **Done** |
| 3. Active Directory group via ARS/SPML | **Done** — written, not yet run against a real directory |
| 4. Packager window | **Done** — submits through the drop folder; Preview still runs locally |
| 4b. Modify (reconcile an existing application) | **Done** — adds what is missing, retires what the environment file no longer asks for, updates what changed |
| 4c. German display name and description in SCCM | **Written**, via SDMPackageXML like the old tool. Not yet run against a site |
| 5. Flow 2 — drop folder | **Done**, engine and window both |
| 6. Flow 1 — live connection | **Dropped.** Scripts parked in `Server\_NotUsed-LiveConnection\` |
| 7. Flow 3 — shared repository | Designed and drawn, **not built** |
| 8. ICZ proving run | **Blocked** — needs the account, the rights and the drop folder |
| 9. INA and PCZ rollout | Not started |

**Tests: 334 passing** — 120 config, 147 engine, 67 transport. None need SCCM.

```powershell
.\Tests\Invoke-AllTests.ps1
```

---

## Decisions taken (do not re-litigate)

| Decision | Why |
|---|---|
| One tool, one build; environments only in XML | Adding an environment must never mean a code change |
| One shared account **per environment** | ICZ, INA and PCZ are separate AD domains — a single central account is impossible |
| gMSA preferred, ordinary service account as plan B | No password anyone holds; it also has real credentials so onward hops work |
| **Flow 2 (drop folder) only** | Audi's decision, 01.08.2026. Matches their barrier drawing; needs no firewall change |
| Requester never trusted from client input | The NTFS file owner. `<Job>` has no requester attribute, so a file carrying one is rejected |
| **No person recorded anywhere on the SCCM side** | Audi's requirement, 01.08.2026 — not on an SCCM object, and not in the server's log, job record or result file. They do not want packagers appearing as making changes on the server |
| **The RFC is the audit link** | Follows from the above. It is written to every object; Audi's change system holds RFC → person. `requireRfc="true"`, so an untraceable change is refused |
| The plan has no Requester field | Structural, not a filter: if nothing holds a person, nothing can log one |
| Preview runs locally, Integrate/Remove go through the folder | A packager can test a package with no server, no share and no rights |
| Deployments declared on the collection | Kills the old tool's index-pairing bug |
| Package names parsed positionally, never string-replaced | `ADO_ADOBE_Reader` must not become `INA_INABE_Reader` |
| Job and result files are **XML**, not JSON | Consistent with everything else, and with Audi's own `[package].xml` |
| Parsing rules live in `Defaults.xml` | A naming or template change is a config edit |
| SCCM calls sit behind a provider | Gives a real dry-run preview and makes the engine testable without SCCM |
| Modify reconciles, never rebuilds | The application object is never replaced, so live deployments and the machines in its collections are undisturbed |
| Modify is not rolled back | Half-undoing a change to an application that is already deployed is worse than stopping and reporting |
| Retiring only ever touches this package''s own collections | A hand-made collection can never be caught by it |
| Package name prefix must match the environment | INA_ into ICZ is refused. The old tool rewrote the first three characters, which is what corrupted ADO_ADOBE_ into INA_INABE_ |
| Config is read-only to the executor | The thing that executes must not rewrite the rules it runs under |

---

## Open questions for Audi — these block progress

1. **The drop folder path per environment.** The three environment files carry
   placeholders (`\\audiinsv1059.in.audi.vwg5t\SwIntegration-Inbox$` and the INA
   and PCZ equivalents). One share per environment, with the rights in
   `DEPLOYMENT.md` 3.1.
2. **PCZ settings.** Four values are copies of INA's and one was never set:
   security scope (`INA00003`), application folder (`INA-Applications`), content
   share, AD group OU (`DC=audi,DC=vwg`), and the ARS provider URL. `PCZ.xml` is
   marked `verified="false"` and a real run against it is refused.
3. **Accounts.** One gMSA and one operators group per environment. The names in
   the environment files are placeholders.
4. **A real GPF install instruction document**, so the `<Document>` patterns in
   `Defaults.xml` can be calibrated. Until then those fields stay blank.

---

## What is NOT yet proven

- **The live SCCM calls.** `New-AudiSccmProvider` wraps supported ConfigMgr
  commands but has never touched a real site. Everything testable today runs
  through the dry-run provider.
- **The ARS/SPML calls.** Written from their `Audi-ARSSPML-*` modules, never run
  against a real directory.
- **The scheduled task.** `Install-AudiSwDropWatcher.ps1` has never been run on a
  server. The collector logic itself *is* tested, via `Test-Transport.ps1`.

---

## Next steps, in order

1. Get the real drop folder paths and the PCZ confirmations (open questions 1, 2).
2. Raise the prerequisites in `DEPLOYMENT.md` section 4 — gMSA, operator group,
   SCCM rights, drop folder. Nothing else can start until these land.
3. Install on the ICZ server, register the collector task, run the acceptance
   test in `DEPLOYMENT.md` section 6.
4. Calibrate the instruction-document patterns against a real GPF document.
5. Roll out to INA, then PCZ.
6. Withdraw the packagers' personal SCCM administrator accounts. **This is the
   point of the project** and is the step most likely to be forgotten.

If flow 3 (shared repository) is ever revisited: point `Get-AudiConfigRoot` at the
repository share and split the config and job areas into two shares. Small change
— the engine, ordering and rollback are unaffected.

---

## Bugs found in the old tool (evidence for the client)

| Defect | Consequence |
|---|---|
| Step results discarded; status always `"Done."` | A failed step looks identical to a successful one |
| `.Replace(Substring(0,3),'INA')` | `ADO_ADOBE_Reader` silently becomes `INA_INABE_Reader` |
| `$global:Credential` always `$null` | Everything runs as the person clicking, despite code that accepts a credential |
| PCZ `$ARS_Provider` never assigned | Both AD steps stall on a hidden console prompt |
| PCZ carries INA's scope, folder, share and OU | Wrong-environment objects |
| Deployments paired to collections by list position | One removed deployment shifts all the rest |
| Flat `Start-Sleep 30` per deployment on the UI thread | Up to five minutes of a frozen window on PCZ |
| Shared `C:\temp\Logs` staging | Two operators overwrite each other's logs |

---

## Traps hit while building (all commented at the point of use)

- `@()` around a generic `List[object]` of PSObjects throws *"Argument types do
  not match"* in PowerShell 5.1 — use `.ToArray()`.
- `.GetNewClosure()` gives a scriptblock its own session state, so the tool's own
  functions become invisible to it once dot-sourced into a script scope, and it
  freezes captured variables at definition time. Plain scriptblocks keep the
  defining scope and stay live.
- `[int]($i / 5)` **rounds** in PowerShell rather than flooring — use
  `[math]::Floor`.
- An empty `<OperatingSystems/>` was rejected by the schema, which would have
  broken every job submitted without OS selections. `minOccurs="0"` fixed it.
- `$args` is automatic inside a script, so a runspace variable of that name is
  silently shadowed by the (empty) argument list. The window passes `$jobArgs`.
- `Wait-AudiSwJobResult` returns a hashtable and the engine returns a
  PSCustomObject; `.PSObject.Properties[...]` only works on the second. The window
  asks through `Test-HasValue` so StrictMode does not throw on the first.

---

## Deliverables and where they are

| What | Where |
|---|---|
| Code, config, client, tests | `Downloads\Application-Packaging\AudiSwIntegration\` |
| Deployment detail (accounts, permissions, drop folder, privacy, security Q&A) | `DEPLOYMENT.md` |
| Structure and commands | `README.md` |
| Three flow diagrams (SVG + PNG) | `C:\temp\Audi-SCCM-Integration\Flows\` — **flow 2 is the one being built** |
| Client design deck | `C:\temp\Audi-SCCM-Integration\...Design and Requirements.pptx` |
| Blueprint deck (earlier, plainer) | `C:\temp\Audi-SCCM-Integration\...Blueprint.pptx` |

Reference copy of the tool being replaced: `C:\temp\EQS-PoshGUI-Tool-1.0.3`.
