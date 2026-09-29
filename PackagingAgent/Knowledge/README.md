# Knowledge — what the agent knows, and how it keeps learning

The AI is the packaging engineer; this folder is its training. Every order's dossier carries the part of it that
fits the order, and the AI can pull the rest on demand with `read_knowledge`. Nothing here is code — it is
evidence, written so that a person can read and correct it. **It is all local**: the agent never reads the package
shares for knowledge at runtime, so it works on any machine, for any brand, after any move.

## The team's own practice — `Corpus\`

Built by `Tools\Build-CorpusKnowledge.ps1` from the whole shipped library (both live repositories + Outgoing,
~3,400 packages), read once, read-only. Not a switch table: **how this team packages, evaluates and fixes**.

| File | What it is |
|---|---|
| `Corpus\Index.json` | every shipped package on one line — vendor, app, version, arch, PSADT v3/v4, MSI/EXE, multi-installer — to find the right ones fast |
| `Corpus\Packages\<vendor>.json` | one profile per package: files and SupportFiles, transform and response files, install/uninstall sequence, what each phase does (pre-install, post-install, pre/post-uninstall, repair — command and line), how the previous version is removed (generic / version-pinned), per-user method (Active Setup / all-users registry), updater, shortcut and reboot handling, detection, ProcToClose, **the author's own notes**, and **what evaluation left behind**: the evaluation document and the owner's form (the packaging team's section: commands, detection, return codes, reboot, Active Setup, intentional leftovers), MRF, complexity matrix, validation reports, test logs (Standalone / Upgrade / Admin / System), and the query mails to the owner |
| `Corpus\Patterns.json` | the whole library measured: what each phase does and how often, with real examples; how updaters, shortcuts and reboots were handled; detection shapes; how often each evaluation artefact exists |
| `Corpus\Vendors.json` | per vendor: its applications, installer types, how old versions are removed, per-user practice, the usual post-install work, updater handling, author notes |
| `Corpus\Lessons.json` | what package authors wrote down when something needed explaining — "because", "workaround", "do not", "must" — with the package it came from |

Scrubbed on the way in: e-mail addresses, phone numbers, names in contact tables. Product codes are kept.

## The rest of the training

| File | What it is | Where it comes from | Who changes it |
|---|---|---|---|
| `Method.json` | **How to work**: how to read a script, verify, troubleshoot, and stay honest | lessons paid for by real defects | the team, by hand |
| `InstallerPlaybook.json` | **Installer technologies**: how to recognise each one, what to try, the eight parameter intents, the reboot policy, how to discover an unknown EXE | vendor documentation, packaging research, cross-checked against our corpus | the team, by hand |
| `SwitchPriors.json` | **Silent-switch families** counted across 238 shipped packages (674 installer launches) | `Tools\Build-SwitchPriors.ps1` | re-run the tool |
| `Troubleshooting.json` | **Problems already diagnosed**: what it looked like, what it really was, how to tell, what to do | real runs that went wrong | the team, when a new one is understood |
| `Experience.json` | **What the packagers told the agent**: house rules, vendor facts, corrections — scoped global / vendor / package / technology | the packager (chat, notes, after testing) and the AI's own `remember_this` | automatically; edit by hand to correct |
| `Cases.json` | **Every order the agent finished**: the line the machine *proved*, what failed first, the updater and how it was switched off, what verification fixed, what the packager said after testing | written automatically at every handover | automatically |
| `Research\` | **Research**: what the MAN corpus shows, and the decision method a senior packager follows (the human-readable source of the handbook) | corpus analysis and packaging research | the team, by hand |
| `..\Engine\KnowledgeBase.Recommend.json` | the older switch catalogue (install/uninstall lines per installer) | the Package Assistance knowledge base | regenerate with the engine |

## How a new order uses it

1. **The dossier** carries: `howThisTeamPackages` (the library's practice, compact), the playbook entries for the
   installer technologies actually delivered, universal rules, parameter intents, reboot policy, switch priors, the
   diagnosed troubleshooting cases, the packagers' notes — and under *what this team did before*: the **shipped
   packages most like this order** (same vendor and application first — usually the predecessor's family), **this
   vendor's profile**, **what authors wrote down** for it, and **the orders this agent finished**.
2. **During any job** the AI can ask for more: `packages:<words>`, `vendor:<name>`, `lessons:<words>`, `patterns`,
   `cases:<words>`, `playbook:<name>`, `priors`, `troubleshooting`, `method`, `memory`, `template`, `toolkit`.
3. The AI is told to **learn the practice, not copy lines** — paths, versions, brands and machines change; the
   reasoning carries over — and to say which package or case it learned from.

## How it keeps learning

- **Every handover** writes the order into `Cases.json`; what the packager writes after testing is kept on that case
  word for word and sorted into `Experience.json`.
- **While working**, the AI records what it learns with `remember_this`.
- **When the library grows** (new packages shipped by anyone, with or without the agent), re-run
  `Tools\Build-CorpusKnowledge.ps1` — it caches per package, so a refresh only reads what is new.
- **Another brand's library** can be added with `-From <share>`; the practice is learned the same way.
- **When a new kind of failure is understood**, add it to `Troubleshooting.json`.

## Rules for editing by hand

- Keep every entry **a fact with its source**, not an opinion.
- Correct, don't pile up: a wrong note is taught to every future run.
- JSON must stay valid (`Tests\Test-Agent.ps1` checks it).
