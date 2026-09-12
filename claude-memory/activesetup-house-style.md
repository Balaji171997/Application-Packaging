---
name: activesetup-house-style
description: "Team's Active Setup pattern for per-user config in PSADT v4 packages, and where the reference example lives"
metadata: 
  node_type: memory
  type: reference
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

The team implements per-user configuration in PSADT v4 packages with **Active Setup** driving a **plain-PowerShell stub** (NOT PSADT) staged in `Content\SupportFiles`.

Reference example (real package): `\\mndemucfsm01\SEC-EQS-Lib-Gate\EQS_SEC\EQS\Packages\Outgoing\Adobe_CCDesktopApp_x86_6.9.1.1-0001_MUL\Content\`.

House structure:
- SupportFiles holds `<App>_<Version>_ActiveSetup_Install.ps1` (+ any `*_HKCU.reg`). The stub hides its console (Add-Type Hide-Console), logs to `%localappdata%\VWG\Logs\<appname>_ActiveSetup_Install.log`, and imports per-user `.reg` via `reg.exe Import` from `$ParentDirPath`.
- POST-INSTALLATION: `Copy-ADTFile` the stub (+ HKCU .reg) to a persistent dir, then `Set-ADTActiveSetup -StubExePath "...\<stub>.ps1" -Description "User_Registries" -Key $AppFullName -ExecutionPolicy "Bypass"`.
- POST-UNINSTALLATION: `Set-ADTActiveSetup -Key $AppFullName -PurgeActiveSetupKey` + `Remove-ADTFolder`.

Other per-user route: `Invoke-ADTAllUsersRegistryAction -ScriptBlock { Set-ADTRegistryKey -SID $_.SID -LiteralPath 'HKCU\...' ... }` (applies at install to all existing users + default profile). `Set-ADTActiveSetup` StubExePath validation only allows .exe/.vbs/.cmd/.bat/.ps1/.js (a .reg can't be the stub directly).

This is now codegen'd by the tool (Build.ps1 `Get-PerUserConfig` / `Get-ActiveSetupStub`, Step-2 "Per-user config" dropdown -> `State.PerUserMode`). See [[verify-semantic-not-syntax]].
