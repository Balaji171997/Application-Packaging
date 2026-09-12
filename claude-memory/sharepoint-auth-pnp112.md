---
name: sharepoint-auth-pnp112
description: SharePoint Online auth from PS 5.1 — only PnP.PowerShell 1.12.0 + PnP Management Shell client id works in this tenant; Graph first-party apps are blocked
metadata: 
  node_type: memory
  type: project
  originSessionId: 5f8c282b-8837-49ff-ba23-d8ac148e8fa6
  modified: 2026-09-04T10:33:54.338Z
---

Connecting to `https://manonlineservices.sharepoint.com/sites/SWPackaging` (library `PackageSources`) from Windows PowerShell 5.1 works with **exactly one** combination:

```powershell
Import-Module ...\PnP.PowerShell\1.12.0\PnP.PowerShell.psd1
Connect-PnPOnline -Url "https://manonlineservices.sharepoint.com/sites/SWPackaging" `
                  -ClientId "28bf2c22-437c-42e7-a4be-e8a0f44a8264" -Interactive
Get-PnPFolderItem -FolderSiteRelativeUrl "PackageSources"
```

- PnP.PowerShell **1.12.0 is the last PS 5.1-compatible version** (2.0+ requires PS 7). PB is PS 5.1, so pin 1.12.0.
- `28bf2c22-437c-42e7-a4be-e8a0f44a8264` = **PnP Management Shell**, already assigned/consented in this tenant.

**Dead ends already burned (do NOT re-propose):**
- `14d82eec-204b-4c2f-b7e8-296a70dab67e` (Microsoft Graph Command Line Tools) → **AADSTS50105**: tenant requires explicit user assignment on that enterprise app.
- `6beebafa-4759-41cf-8c61-34735059ad62` (Microsoft Intune PowerShell — the app PB's `Connect-MSIntuneGraph` uses) → needs `-RedirectUri 'urn:ietf:wg:oauth:2.0:oob'` to get past AADSTS900971, but then hits **"needs admin approval"** for `Sites.Read.All`: tenant blocks user self-consent for any new scope.
- WebDAV / UNC mapping / `New-PSDrive` against the SharePoint URL — dead for SharePoint Online (legacy auth, breaks under MFA/CA).
- Raw Graph REST via MSAL.PS — same consent wall as above; not an app-choice problem.

**Why:** the tenant blocks user self-consent, so any *new* scope on any app needs an admin. PnP Management Shell sidesteps this because it is already consented tenant-wide.

**How to apply:** for any SharePoint access from PB or its variants, use PnP 1.12.0 + that client id. Related: [[sharepoint-packagesources-layout]], [[downloads-files-is-pb-only]].
