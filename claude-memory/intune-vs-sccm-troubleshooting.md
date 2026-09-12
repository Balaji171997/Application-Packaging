---
name: intune-vs-sccm-troubleshooting
description: "Intune troubleshooting is a different toolset from SCCM — Company Portal not Software Center, IME logs not CCM logs"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 5f8c282b-8837-49ff-ba23-d8ac148e8fa6
  modified: 2026-09-11T05:15:29.326Z
---

Intune troubleshooting is NOT "the SCCM tab with bits greyed out" — different client app, different logs, different state.

| | SCCM | Intune |
|---|---|---|
| Client UI | Software Center | **Company Portal** |
| Install / enforcement | `CCM\Logs\AppEnforce.log` | **`AppWorkload.log`** |
| Detection | `CCM\Logs\AppDiscovery.log` | `AppWorkload.log` + `AgentExecutor.log` |
| Agent activity | `CCM\Logs\PolicyAgent.log` | `IntuneManagementExtension.log` |
| Targeting | device collections | Azure AD groups |
| Policy refresh | Machine Policy Retrieval cycle | IME sync / Company Portal sync |

**Intune logs** live in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`:
- **`AppWorkload.log`** — Win32 app detection, requirement rules, install decisions. THE one for app problems
  (app workload logging split out of IntuneManagementExtension.log in newer IME builds).
- `IntuneManagementExtension.log` — IME policy retrieval / general agent
- `AgentExecutor.log` — PowerShell detection + requirement script execution and their output
- `ClientHealth.log` — IME health / check-in

**Beyond log files:**
- Win32App state: `HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\<GRS>\<appId>`
- Company Portal (user context): `%LOCALAPPDATA%\Packages\Microsoft.CompanyPortal_*\LocalState\DiagnosticLogs`
- Event log: `DeviceManagement-Enterprise-Diagnostics-Provider/Admin`
- The PSADT package's own install/uninstall logs are the SAME for both (it is our script).

**How to apply:** in Package Builder's Step 4, Troubleshoot must be split per target — the SCCM tab's CMTrace/CCM
log buttons are meaningless for an Intune-only package. Related: [[sharepoint-migration-status]].
