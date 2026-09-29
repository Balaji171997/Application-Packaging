# How a packager decides — the reasoning the agent has to reproduce

This is the decision process a senior packaging engineer runs, written down so the agent can follow the same one.
It is built from three things: **industry practice** (repackage-vs-wrap literature), **our own corpus** (238 shipped
packages, measured — see `Corpus-findings.md`), and the house rules in the team's template.

**The one thing that frames everything:** this team **wraps**. Every shipped package is the vendor's own installer
driven from a PSADT v4 script. Nobody repackages into a fresh MSI. So the classic "repackage or wrap?" question is
already answered, and the real question is the one below.

> **How do I drive this vendor installer silently, carrying every choice the application owner made, on a machine
> I cannot see?**

---

## Phase 1 — Understand the request before touching a file

| Question | Where the answer is | If missing |
|---|---|---|
| Which application, which version, which architecture, which language? | the package name, the AO form | **23% of order names don't parse** — read the form and the installer, never trust the name |
| Who asked, and for which environment (SCCM, Intune, both)? | the form's distribution ticks | ask |
| Is this a new application or a version bump? | the catalogue of shipped packages | decides Phase 3 entirely |
| Is there a complexity matrix / vendor documentation? | the order's `doc` folder (88% / 85% have them) | proceed, but say so |

**The decision that matters here: is there a predecessor?** Only **21%** of orders have one. When there is, most of
the thinking has already been done by whoever shipped the last version, and the job becomes *what changed*. When there
isn't — **79% of the time** — everything below applies in full.

## Phase 2 — Identify what actually arrived

Look at the payload, not the paperwork:

1. **How many installers?** One (56%), several (18%), many (13%), or **none at all (13%)**. More than one means an
   order of installation and probably prerequisites — **59% of our shipped packages run more than one installer.**
2. **What technology is each one?** MSI is deterministic. An EXE is a research problem, and **76% of our packages
   involve an EXE**. Identify it from the binary's own markers (Inno, Nullsoft, InstallShield, wixburn), from what
   `/?` prints, and from the file layout beside it (`setup.iss`, `ISSetupPrerequisites`, a `.mst`).
3. **Is there an MSI hiding inside the EXE?** If it can be extracted safely it usually makes the better package —
   but only if the extraction is trustworthy.
4. **What else is in the box?** A transform (13%), a zip to expand (18%), licence files, configuration templates,
   an icon, start pages, language packs. Each one has to end up somewhere in the package or be explicitly discarded.

## Phase 3 — Choose the route

This is the heart of it. Take the **highest** route that carries **all** of the owner's choices:

| # | Route | Choose it when |
|---|---|---|
| 1 | **MSI + transform (.mst)** | An MSI with non-default selections. The choices live in the transform, the command stays clean. |
| 2 | **MSI + public properties** | The choices are expressible as `INSTALLDIR=`, `ADDLOCAL=`, `ALLUSERS=1`, a licence property. |
| 3 | **EXE silent switch + selection switches** | A documented silent switch exists and `/COMPONENTS=`, `/TASKS=`, `/DIR=`, `/LANG=` carry the rest. |
| 4 | **EXE + recorded response file** | The selections cannot be expressed as switches. A human walks the wizard **once** (InstallShield `/r /f1`, Inno `/SAVEINF=`), the package replays it. Normal packaging, not a failure. |
| 5 | **Extracted MSI** | The EXE is a wrapper and extraction is trustworthy. |
| 6 | **Silent install + post-install configuration** | Install with defaults, then apply what no switch covers: registry values, a config file copied into place, a licence file. **Very common** — 39% of our packages write registry, 36% copy files. |
| 7 | **Loose files** | No installer at all (13% of orders): copy the payload, make the shortcut, write the ARP entry. |
| 8 | **Manual, per the owner's instructions** | Only when nothing above reproduces the required result. |

**The test for "did I choose right":** walk the wizard screenshots one screen at a time and point at where each
choice is carried. A choice with nowhere to go is a question for the owner — never a silent omission.

## Phase 4 — Prove it on a machine

Nothing above is believed until it runs:

1. Snapshot the machine.
2. Try the candidate commands **one at a time**, best first.
3. Watch what happens. A window that waits for a click is not silent. **An exit code of 0 is not proof** — NSIS
   returns 0 for doing nothing. The snapshot is the proof.
4. Snapshot again and diff.

When every candidate fails, the failures themselves are the evidence: a window title names the technology, an exit
code is a fact (1603 failed, 1618 another install running, 1619 bad path, 3010 success-needs-reboot). Read them, then
either try a different *technology* — not a different spelling of the same switch — or conclude that this installer
needs something a switch cannot give, and say what.

## Phase 5 — Decide what the package does

From the diff, decide every meaningful change:

- **the application itself** → keep
- **bundled extras and runtimes** → keep only if the app needs them
- **auto-update** (scheduled task, service, run key, updater exe, config flag) → **disable, always.** This is the
  single most-missed item in a hurried package.
- **per-user settings** → `None` / `AllUsersReg` / `ActiveSetup`. Note that **70% of our packages need nothing here** —
  don't invent per-user work.
- **desktop shortcuts** → remove; Start-Menu stays
- **uninstall** → derive from the ARP entry actually observed, not from the vendor's documentation
- **detection, reboot handling, processes to close** → the template's job, but adjust them when the app demands it

## Phase 6 — Build, then review as a stranger

The tool builds — the team's template, the team's builders. Then read the result as if someone else wrote it:

- **Reuse:** only the retarget should differ — version, dates, author, detection key, installer and transform names,
  the log name, and a new uninstall-previous block **only if** the predecessor pinned a version. **81% of our
  packages remove the old version generically**, and adding a pinned block to those duplicates work already done.
- **Fresh:** walk the template section by section. A section the order and the snapshot say nothing about is
  correctly empty.
- **Both:** every command must exist in the toolkit or the team's extensions (**24% of the corpus is still v3**, so a
  reused predecessor may hand you `Execute-MSI`), the template's own lines must be intact, and the folder tree must
  match what the script reads.

## Phase 7 — Hand over with the evidence

The package, plus what was tried, what was observed, what was decided and why, and what a human still has to check.
A package nobody can audit is a package nobody should ship.

---

## Where a human is genuinely needed

Not a failure — part of the craft. The agent should ask early, precisely, and with the exact command to run:

- recording a response file (somebody has to walk the wizard once)
- a licence server, key, certificate or account — **48% of our packages mention licensing**
- a selection the screenshots don't show and the form doesn't state
- an installer that only installs per-user and cannot be made machine-wide
- anything where the order and the machine disagree and the evidence can't settle it

---

## Sources

- [Repackaging versus wrapping — Advanced Installer](https://www.advancedinstaller.com/repackaging-versus-wrapping.html)
- [Wrapping vs repackaging best practices — Advanced Installer](https://www.advancedinstaller.com/user-guide/wrapping-vs-repackaging.html)
- [When and why should you repackage an EXE to an MSI — Master Packager](https://www.masterpackager.com/blog/when-and-why-should-you-repackage-an-exe-to-an-msi)
- [Repackaging vs legacy installation — Apptimized](https://apptimized.com/en/news/repackaging-vs-legacy-installation-dont-break-what-already-works/)
- [Silent install switches cheat sheet](https://github.com/offlineinstallersetup/silent-install-cheatsheet)
- [Creating the response file — Revenera/InstallShield docs](https://docs.revenera.com/installshield24helplib/helplibrary/CreatetheResponseFile.htm)
- [Performing silent installations and uninstallations — Flexera](https://resources.flexera.com/web/media/documents/silent_installs.pdf)
- our own corpus: `Corpus-findings.md` (beside this file), `Knowledge\SwitchPriors.json`, `Knowledge\Cases.json`
