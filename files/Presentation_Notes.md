# Package Builder — Presentation Notes

## What it is (the elevator pitch)
A single-folder Windows tool that takes a software packaging job from **"here's the installer"** to
**"deployed in SCCM and Intune, tested, and troubleshot"** — in one guided wizard.
What used to need Orca, Beyond Compare, the ConfigMgr console, the Intune portal, CMTrace, manual
robocopy and a head full of tribal knowledge is now **one exe the whole team runs by copying a folder**.

## The workflow (demo script)
**Step 1 — Info:** type the package name (`Vendor_App_Arch_Version-Release_Lang`), pick the predecessor
package from the live library, point at the source files. The tool parses everything itself.

**Step 2 — Detection:** installer type and product code are auto-detected; MSI packages get an MST
transform built in-tool (standard properties applied, desktop shortcut / Run keys stripped — Orca replaced
by a checkbox dialog showing the MSI Property table).

**Step 3 — Editor:** the deployment script is **assembled automatically** on the blank PSADT v4 template:
the predecessor's custom logic is carried over, versions swapped safely (longest-prefix rule, never touches
look-alike numbers), v3 predecessors are **converted to v4 automatically** (200+ mapping rules). A real code
editor (AvalonEdit) with snippet library for manual touches. A structure validator refuses to build a
package whose script wouldn't parse — corruption cannot ship.

**Step 4 — Create & Publish (tabs):**
- *Review & Create* — assembles the final package folder (template + script + payload + docs + icons + MSTs).
- *Integration* — one click **Create in SCCM** (prelive copy, app, deployment type with branding+chosen
  detection, distribution, collections, deployments, German display name + icon) or **Create in Intune**
  (.intunewin build, Win32 app via Graph, chunked upload with SAS renewal/resume, detection rules, icon).
  Modify section: fetch/update detection, update content (or DP-refresh only), per-DP **content status**
  with real last-update times, delete app.
- *Testing* — add/remove machine lists to TEST collections, trigger client policy remotely.
- *Troubleshoot* — live install state straight from the client (Installing NOW 45%, reboot required with
  last-boot proof, real installer exit codes dug out of AppEnforce.log and explained in plain English,
  detection-rule mismatch detection), pull any client/package log into CMTrace, remote reboot.
- *Dev→Test* — move app + collections between UAT folders.

Side-by-side **diff vs predecessor** (Beyond Compare style, whitespace-ignored) at any point.

## Architecture — what we used and why
| Piece | Choice | Why |
|---|---|---|
| Language | **PowerShell 5.1** | preinstalled on every corporate Windows machine — zero runtime to deploy |
| UI | **WPF (XAML)** | native, fast, themeable dark UI; no web stack, no extra dependencies |
| Editor | **AvalonEdit** (one DLL) | real syntax-highlighted editing inside the tool |
| Packaging std | **PSADT v4** | corporate standard; the tool fills the official blank template |
| SCCM | **ConfigMgr PowerShell module** (bundled console copy) | the supported automation surface; site drive + cmdlets |
| Intune | **Microsoft Graph (beta) called directly**, token via MSAL / "Microsoft Intune PowerShell" client | no client secret of ours, survives Conditional Access; our own uploader = chunked, resumable, SAS-renewing (more robust than the community module) |
| MSI/MST | **Windows Installer COM** | native Property-table read/write + transform generation — Orca eliminated |
| Distribution | **Loader exe + encrypted pak** | see below |
| Quality | offline **test suite + parse gates** at build AND pack time | a broken build physically cannot be packed or shipped |

## The distribution model (the part worth showing off)
- **PackageBuilder.exe** — a tiny loader, compiled once (PS2EXE), never changes. Carries the icon.
- **PackageBuilder.pak** — ALL tool logic: merged, compressed, **AES-encrypted** (~150 KB). Opaque binary —
  nobody can read or tamper with the code.
- **settings.json / snippets.json** — the only editable files (paths, site, tenant, snippets).
- **Lib\** — third-party dependencies only (AvalonEdit, IntuneWinAppUtil, MSAL+IntuneWin32App modules,
  PSADT template, ConfigMgr module).

**Updating the tool = replacing the one .pak file.** No reinstall, no recompile. Optional auto-update:
point `UpdatePath` at a share — every launch picks up the newest pak automatically. The team never
redistributes anything.

## Reliability principles baked in
- Every remote action runs on a background thread — the UI never freezes; one progress bar + copyable log.
- Everything destructive asks first; everything partial **rolls back** (SCCM and Intune creates).
- Transient failures retry themselves (Graph throttling/5xx, token expiry mid-upload, upload block failures,
  DP "already distributed", console/site version notices).
- Duplicate guards on both SCCM and Intune (Intune matched by branding key — display names lie).
- The session log records every step; client-side errors are translated to plain English with the fix named.

## Numbers
- ~510 KB of source, 10 engine modules + GUI, packs to a 150 KB encrypted pak
- One folder (~254 MB incl. ConfigMgr console module), zero installation, zero admin rights to run
- Offline test suite + multi-stage parse gates; UI changes verified by rendered screenshots during development
