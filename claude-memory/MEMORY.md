# Memory index

- [Memory lives in the repo](memory-lives-in-repo.md) — this folder is a junction into Application-Packaging\claude-memory; on a new machine run Setup-ClaudeMemory.ps1 -WorkingDir <folder>
- [git not on PATH](git-not-on-path.md) — AW140 machine: use GitHub Desktop's bundled git.exe via full path (`$env:LOCALAPPDATA\GitHubDesktop\app-*\resources\app\git\cmd\git.exe`)

- [GPF xlsx testing fixes](gpf-xlsx-testing-fixes.md) — field-test findings; r60 did -Transforms + ProcessAsUser -Wait/-ContinueOnError drop + .NET env-var conversion; filename-swap DEFERRED by user
- [MTB reuse SoftIdent/ProcToBlock](mtb-reuse-softident-proctoblock.md) — r222: keep name-based predecessor SoftIdent (Merge-SnapshotDeltas); empty ProcToBlock stays empty on reuse
- [GPF portable deploy sync](gpf-portable-deploy-sync.md) — after ANY GPF change, also sync portable copy Application-Packaging\GPF_PackageAssistance (underscore); sidecar data like snippets.json needs copy but NO repack

- [PB agent story](pb-agent-story.md) — spec to train an AI agent on the packaging process; split sub-stories (build+param-test+disable-autoupdate / verify / deploy w/ approval gate); md in Downloads\agent-story
- [Shared-folder deployment](shared-folder-deployment.md) — v1 rollout: exe+all on a share, users get a SHORTCUT; UNC binary-module load caveat + PackageBuilder.exe.config fix
- [Docx: no Node/Python here](docx-no-node-python.md) — build Office files via hand-written OOXML + PowerShell zip; skill helper scripts can't run
- [Intune vs SCCM troubleshooting](intune-vs-sccm-troubleshooting.md) — Company Portal not Software Center; AppWorkload.log is THE Intune app log (+ IME/AgentExecutor); Win32Apps registry state
- [SharePoint migration status](sharepoint-migration-status.md) — source+predecessor DONE via SharePoint.ps1 overrides (proven); Outgoing/Snippets pending; SCCM ContentShare can NEVER move
- [SharePoint auth = PnP 1.12.0](sharepoint-auth-pnp112.md) — ONLY PnP 1.12.0 + PnP Management Shell client id works (PS 5.1); Graph CLI Tools + Intune app both blocked by tenant policy — don't retry those
- [PackageSources layout](sharepoint-packagesources-layout.md) — Vendor/App/Version_Release/{source,doc,EQS,SCCM,Intune,Order}; deterministic map from PB's package name
- [Downloads\files = PB only](downloads-files-is-pb-only.md) — don't create unrelated files there; other deliverables go in own folder outside `files`
- [SCCM2Intune migrator](sccm2intune-migrator.md) — Downloads\SCCM2IntuneMigrator: ONE script replacing the 4 old variants; brand-neutral, profiles in settings.json; UAT group MDM_MN_SWW_<vendor>_<app>_UAT
- [Multi-team brand variants](multi-team-brand-variants.md) — manager wants PB reused for other teams; separate brand copies (their PSADT template + paths + branding), user brings 5-10 samples after a meeting
- [GPF brand variant](gpf-brand-variant.md) — GPF team (3 target brands INA=Audi/VWG=Group/G1V=VW): SEPARATE tool copy at Downloads\GPF-PackageBuilder, files\ stays MTB-only; template/conversion/resolver done + ALL TESTS PASS vs real corpus; Step-1 GUI wiring pending
- [Intune Notes = JSON](intune-notes-json-schema.md) — app Notes field is JSON (lifecycle/notes/managed/status); real stages LIVE/SAT/RETIRED/UAT/FailedUAT/PreRollout; parse don't regex
- [IntuneAppReport tool](intune-app-report-tool.md) — Downloads\IntuneAppReport: WPF Sync-now tool exporting Win32 app inventory + change history (audit trail + own snapshot diffs); PB's MSAL auth, can't be scheduled
- [GPF 30-Jul findings + brand selector](gpf-30jul-findings-and-brand-selector.md) — r43/r44: 12 findings done (Test-Path dbl-guard, InstallTitle style, $flag=match-predecessor, brand rules) + Audi/VW/Group Step-1 dropdown; OPEN: #1/#2 dep-ordering, #9, #10, #3
- [GPF test-case remediation](gpf-testcases-remediation.md) — findings from GPF team's Package_BuilderTesting.docx; 3 user decisions, Freia 9.1.0 gold standard, Increment 1 DONE (wrapper fills/date/author/@()/branding-last), remaining increments mapped
- [Audi SCCM integration tool](audi-sccm-integration-tool.md) — new client: rewrite EQS-PoshGUI tool so all SCCM work runs as ONE service account; transport DECIDED = flow 2 drop folder only (don't re-propose WinRM/JEA); NO real person recorded anywhere server-side, RFC is the audit link; tool in Downloads\Application-Packaging\AudiSwIntegration
- [PPT template facts](audi-ppt-template-facts.md) — "Package Builder.pptx" = VW Group 2023 theme; colours/fonts/layouts + the dark-layout tx1=white mapping; render via PowerPoint COM to verify

- [Verify = semantic, not syntax](verify-semantic-not-syntax.md) — for Package Builder, "verify" means meaningful + matches live + review-flagged, not just parse-clean
- [Active Setup house style](activesetup-house-style.md) — team's per-user-config pattern (plain-PS stub in SupportFiles + Set-ADTActiveSetup); reference pkg on Outgoing share
- [Automations ruled out](automation-scope-not-useful.md) — firewall/services/reboot/ProgramData automations are NOT useful for Package Builder; don't re-propose
- [Snapshot froze on 10GB app](snapshot-huge-install-perf.md) — eager WPF tree + O(n²) counts; lazy children + 400 cap + memoised counts (r213/r26)
- [Screenshots: keep it simple](screenshot-keep-it-simple.md) — shortcut screenshots use fixed timing (launch→wait→shot1→15s→shot2), full-screen; NO adaptive "is it loaded" detection
- [UX declutter preference](ux-declutter-preference.md) — labeled rows not dropdowns, nothing hidden/duplicated, one accented primary per tab, snapshot installer-independent (+Admin/SYSTEM CMD), junior-friendly, conservative before go-live
- [Force-kill modal-dialog ghost](force-kill-modal-dialog-ghost.md) — force-killing an app showing a #32770 modal dialog leaves an unclearable csrss ghost window; drain dialogs (WM_CLOSE) BEFORE force-kill
- [Predecessor reuse report](predecessor-reuse-report.md) — reuse review is a two-part Done/Check report; keep Done items verified against the built script
- [Log-path format v4](log-path-format-v4.md) — team v3→v4 log modernisation: $configToolKitLogDir\$setuplogName → per-app $LogPathMain (Get-ADTConfig); ~half the live packages
- [MTB Get-ADTApp + reboot style](mtb-getadtapp-and-reboot-style.md) — MTB house style: Get-ADTApplication = -Name first + bareword -NameMatch; reuse keeps ONE POST-section Set-MTBReboot (comment-state from predecessor); r218, MTB-only

- [Never bulk-rename via shell](never-bulk-rename-via-shell.md) — quoted strings through Bash/PowerShell tool turned every `'` into `P`, corrupting 2 files; use Edit or a typed hashtable, then parse-check + count quotes
- [PS 5.1 collection & path traps](ps51-collection-and-path-traps.md) — empty collection is falsy; `if`-assignment unrolls a 1-elem array; `[]` in a positional path; GetNewClosure hides functions from handlers
- [PS 5.1 ConvertFrom-Json nesting](ps51-convertfromjson-nesting.md) — `@(Get-Content|ConvertFrom-Json)` wraps the array; .Count lies, member access enumerates. Assign then flatten
- [PS 5.1 List[object] wrap bug](ps51-list-object-wrap.md) — @()/comma on a List[object] of PSObjects throws "Argument types do not match"; use .ToArray()
- [PS 5.1 Setter enum bug](ps51-setter-enum.md) — New-Object Windows.Setter mis-binds enum values; set .Property/.Value explicitly
- [PS comma-arg & alias traps](ps51-comma-arg-and-alias.md) — `f a, b` = ONE array param not two; bare helper names collide with aliases (ni=New-Item)
- [PS/WPF closure scope](ps-wpf-closure-scope.md) — each .GetNewClosure() handler has its own scope; share dialog state via one captured hashtable, not $script: vars
- [MSI GenerateTransform read-only](msi-generatetransform-readonly.md) — COM error "GenerateTransform,ReferenceDatabase,TransformFile" = output .mst read-only/locked; write to temp then place
- [MSI cleanup keypath+reader](msi-cleanup-keypath-reader.md) — OpenView/StringData reader is non-deterministic (use Database.Export); run-key removal must be KeyPath-aware (dedicated run-key component = remove WHOLE component, not the row); 3DExperience is the test MSI
- [ConfigMgr provider -Filter trap](configmgr-provider-filter-trap.md) — under the CMSite drive, FileSystem cmdlets with -Filter/-File/-Recurse throw "provider does not support filters"; pin location to a filesystem path
- [Intune detectionRules array](intune-detectionrules-array.md) — Graph 400 "detectionRules does not match schema" = single branding-only rule unwrapped to a JSON object; force array (`return ,$x.ToArray()` / `@()`)
- [v4 Get-ADTApplication -Name positional](v4-getadtapplication-name-positional.md) — v3 name was positional; v4 -Name isn't (pos0=-FilterScript) → converter adds explicit -Name (r214/r27); Invoke-ADTAllUsersRegistryAction inline form is correct
- [MSI runas-verb launch](msi-runas-verb-launch.md) — snapshot "Run installer" fails for every MSI (.msi has no 'runas' shell verb); launch MSI/MSP via msiexec (Get-InstallerRunSpec) in Admin/SYSTEM/sandbox paths
