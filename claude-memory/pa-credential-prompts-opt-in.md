---
name: pa-credential-prompts-opt-in
description: Package Assistance rule - a share sign-in may only be offered by an action the packager started; passive UI paths must never prompt (Porsche 23 Sep 2026 bug)
metadata:
  node_type: memory
  type: feedback
  originSessionId: 7d55d151-f242-4450-a165-3b37421965bd
  modified: 2026-09-23T13:12:58.136Z
---

**User rule (Porsche field report, 23 Sep 2026):** "our functionality is that when they try to fetch location then
ask for credentials - but here unnecessarily... once we enter package name and going to order id it says access
denied 3 times. this is not good." A credential prompt is only ever acceptable inside a handler the packager
STARTED (Fetch source, Find predecessor, Copy to Outgoing). Anything that merely reacts to typing, repaints the
window, or runs in a worker must stay silent.

**Why it happened:** `Suggest-Predecessor` (the "a previous version exists" hint) runs on `TxtPkg` LostFocus and
called `Get-PredecessorRoots`, which offered `Connect-PBShare` for any root it could not open - modal prompt x3,
and focus never reached the Order ID box.

**How it is enforced now (GPF = PAG, MTB has none of this):**
- `Connect-PBShare -AllowPrompt` / `Invoke-PBWithShareAccess -AllowPrompt`: asking is OPT-IN; without the switch they
  only report whether the path opens. Only the three explicit handlers pass it. `$script:PBNoSharePrompt` = global
  kill switch. `Get-PredecessorRoots -AllowSignIn` (default off).
- `Connect-PBShare` probes the share first and prompts ONLY on a credentials-can-fix-this error. `Test-PBAccessError`
  is deliberately strict: access denied / Zugriff verweigert / logon failure / 1219 / 0x80070005. "Network path not
  found" / missing folder / mistyped share are logged and skipped - a credential cannot fix those.
- The hint resolves its roots once per session (`$script:PredQuietRoots`): a dead UNC root cost ~3 s of Test-Path per
  name typed (1st name 1.3 s, later names 18 ms after the fix).

**Same class, same day - the busy card (ALL 3 brands):** the progress card runs on its own STA thread with
`Topmost="True"`, so it covered the "which source?" picker and the window had to be dragged. `Suspend-PBBusy` /
`Resume-PBBusy` (counted) + `Invoke-PBWithoutBusy { }` for MessageBoxes; `Set-PBDialogChrome` suspends and hooks
`Add_Closed`, which covers EVERY in-tool dialog in one place because chrome is always applied just before
ShowDialog. `Hide-PBBusy` resets the counter so the card can never stay stuck.

**Follow-ups the same day (GPF/PAG only, MTB untouched):**
- The classification that only prompted on "access denied" was WRONG for a share in ANOTHER DOMAIN - Windows reports
  that as "network path not found". Removed: on an explicit click, a UNC that does not open simply gets the prompt,
  and the Get-Credential message says to use DOMAIN\user. `Test-PBAccessError` is broad again (used only after an
  explicit action already failed). A cancel is remembered per share until the next click (`Reset-PBShareAsk`).
- The auto "a previous version exists" hint on name LostFocus and the "View predecessor install/uninstall" button
  were REMOVED on the team's request. Typing now touches nothing (15 ms/name).
- "No predecessor found" is now a diagnosis, not silence: `Get-PredecessorSearchReport` (per location: not
  configured / cannot open + DOMAIN\user hint / nothing matching + the closest names present) shown by
  `Show-PredecessorMissingDialog` with Sign in and search again / Select the package... / Continue without.
  `Resolve-PredecessorSelection` is ONE picker for folder OR zip OR a file inside the package OR a folder of
  packages - no more "YES folder / NO zip". Tests: scratchpad `Test-PredResolve.ps1` (15 checks).

**How to apply:** when adding any new share access, ask "did the user click something for this?" - if not, no prompt
and no blocking probe on the UI thread. When anything modal appears, the busy card must not be on top of it. When
something is not found, say WHICH location was checked and WHY it failed - never just offer a browse box. The driver guard lives in scratchpad `Smoke-GPF.ps1` phase 2 (unreachable
UNC + two LostFocus events, asserts `$script:PBShareAsked` stays empty). See [[pa-gpf-pag-enterprise-shell]] and
[[pag-porsche-variant]].
