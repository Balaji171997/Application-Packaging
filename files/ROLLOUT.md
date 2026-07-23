# Package Builder — v1 shared-folder rollout

The whole tool lives in **one folder on a shared network location**. Users get a **shortcut** to
`PackageBuilder.exe` on that share — nothing is copied to their machine. Update the tool by replacing
`PackageBuilder.pak` on the share; everyone runs the new engine automatically.

## 1. Put the tool folder on the share
Copy the complete folder (the deployed layout) to the share, e.g. `\\<server>\<share>\PackageBuilder\`:

```
PackageBuilder.exe            launcher (built once from Loader.ps1; never rebuilt)
PackageBuilder.exe.config     lets the SCCM/Intune modules load from the share (see step 3)
PackageBuilder.pak            the engine — replace THIS file to update the tool
settings.json                 central config (share paths, G08 site) — read-only for users
snippets.json                 central snippet library
KnowledgeBase.Recommend.json  installer-args knowledge base
Lib\                          AvalonEdit, icon, ConfigurationManagerPrelive\ (SCCM),
                              PowerShell Module\ (MSAL.PS + IntuneWin32App), IntuneWinAppUtil.exe,
                              PSADT_Template\ (blank v4 template)
```

Readiness was verified: every artifact above is present and the engine round-trips. (Re-verify any time
with `Release-Check.ps1` for the build, plus the deployment manifest check.)

## 2. Give users a shortcut (not a copied exe)
Create a Windows shortcut whose **Target** is `\\<server>\<share>\PackageBuilder\PackageBuilder.exe`.
Distribute the `.lnk` (or pin it). The tool resolves everything relative to the exe's own folder, so it
must run from the share — a bare exe copied elsewhere will report "pak not found".

## 3. One-time: let the share load the binary modules
The SCCM (ConfigurationManager) and Intune (MSAL.PS) modules load **binary .NET assemblies** from the
share. If the share is treated as the *Internet* zone (common for FQDN paths like
`\\server.domain.biz\...`), .NET blocks those loads. Two ways to fix — do at least one:
- **Shipped:** `PackageBuilder.exe.config` (already beside the exe) enables `loadFromRemoteSources`.
- **Recommended also:** have IT add the share host to the **Local Intranet** zone via GPO.

## 4. Smoke-test from the share before wide rollout
Launch via the shortcut (running from the share) and confirm:
- [ ] App opens; title shows the build stamp (r140+).
- [ ] Build a package (fresh) and a predecessor-reuse package — Step 3 script + editor work.
- [ ] **SCCM publish** completes (module imports from the share, connects to G08).
- [ ] **Intune publish** completes (MSAL.PS imports; sign-in per action).
- [ ] **Dev→Test move** clears test-machine members then moves (new r140 behaviour) — verify on G08.

## Notes
- All runtime output (logs, build, temp) goes to local `C:\temp\PackageBuilder`, never the share.
- Packages are written to the Outgoing shares as today.
- Adding snippets from the GUI needs a writable `snippets.json`; on a read-only share it fails
  gracefully (warning). Snippets are maintained centrally.
