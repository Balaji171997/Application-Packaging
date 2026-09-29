# Third-party tools the agent uses

The agent controls these from PowerShell and hands their output to the AI as facts.
Every one of them is optional: if a file is missing, the agent says so in the feed and
carries on with less evidence rather than failing.

| File | Version | Licence | In the repo? |
|---|---|---|---|
| `7z.exe`, `7z.dll` | 7-Zip 26.03 | LGPL-2.1-or-later (unRAR restriction on part of the code) - see `License.txt` | Yes. LGPL permits redistribution as long as the licence text travels with it. |
| `Microsoft.Deployment.WindowsInstaller.dll` | WiX 3.14.1.8722 | MS-RL (Microsoft Reciprocal License), .NET Foundation | Yes. Open source, redistribution permitted. |
| `Procmon.exe` | Sysinternals 3.20 | Sysinternals Software License Terms | **No - git-ignored.** Free to use, but the licence does not permit redistribution. Download per machine from https://learn.microsoft.com/sysinternals/downloads/procmon |
| `autorunsc.exe` | Sysinternals Autoruns 14.3 | Sysinternals Software License Terms | **No - git-ignored.** Same reason. https://learn.microsoft.com/sysinternals/downloads/autoruns |

## Signing

`7z.exe` and `7z.dll` are not code-signed - that is normal for the 7-Zip console
binaries, and authenticity is established by the version resource plus `License.txt`.
The other three are signed (Microsoft Corporation, and WiX Toolset / .NET Foundation).
Somewhere with AppLocker or WDAC, the 7-Zip pair is the one that needs allowing.

## Copied from another machine?

Files downloaded with a browser carry a Zone.Identifier stream, and .NET refuses to
load a DLL that has one - it fails with `0x80131515 Operation is not supported`.
The agent calls `Unblock-File` on this folder before loading anything, so this is
handled, but it is the first thing to check if a tool mysteriously will not load.

## What each one is for

- **7-Zip** - names the installer technology from the file itself and extracts without
  running anything. Measured against eight real deliveries (1.8-3.9 GB): 0.4-63 s each,
  versus 86-113 s for the byte scan it replaces, and it found three MSIs inside
  `RevitCoreEngine_2026.exe` where the byte scan found none.
  It has **no handler for Inno Setup, Wise or InstallShield** - those show up as bare
  `PE`, and the answer for them is to run the installer and watch (see Process Monitor).
- **WiX DTF** - reliable MSI/MST/MSP work: property and table reads, transform
  generation, and proving a transform actually applies to this MSI before handover.
  Replaces the `WindowsInstaller.Installer` COM API, whose `OpenView`/`StringData`
  reader is not deterministic.
- **Process Monitor** - what the installer really did, including the child processes it
  launched and their command lines. That is how the extracted MSI and the switches a
  vendor wrapper passes to it are found - and for InstallShield and Wise suites, where no
  extractor works, it is the only route. Needs elevation.
  Measured: fifteen seconds of capture on an idle machine produced **459 MB** (~30 MB per
  second) and 1.1 million events, out of which 6 child processes were extracted with their
  full command lines. So a trace is requested by the AI rather than taken by default, the
  agent refuses to start one with less than 12 GB free, and the capture is deleted as soon
  as the facts are out of it.
- **Autoruns (console)** - every autostart point: services, scheduled tasks, Run keys.
  Measured 190 tasks in 2.3 s, 811 services in 7.5 s, 50 run keys in 0.6 s, unelevated.
  This is how the auto-update mechanism gets found instead of hunted for by hand.
