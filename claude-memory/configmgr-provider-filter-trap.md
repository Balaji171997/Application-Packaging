---
name: configmgr-provider-filter-trap
description: "Under the CMSite drive (Push-Location G08:), Get-ChildItem -Filter/-File/-Recurse throws \"provider does not support the use of filters\""
metadata: 
  node_type: memory
  type: reference
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

In Sccm.ps1, `New-SccmApplication` wraps the whole create in `Push-Location "$($cfg.SiteCode):"` (the ConfigMgr
CMSite drive). PowerShell binds a cmdlet's **dynamic parameters from the CURRENT drive's PROVIDER**, not from the
`-Path` argument's provider. So any FileSystem cmdlet that uses `-Filter` / `-File` / `-Recurse` while the CMSite
drive is current throws **"the provider does not support the use of filters"** even if `-Path` is a real UNC/FS path.

This bit me in r73: a recursive `Get-ChildItem -Filter 'Invoke-AppDeployToolkit.ps1' -Recurse` added to
`Copy-PackageToPrelive` (which runs INSIDE that Push-Location) broke SCCM create with that exact error.

Rule: any function that does FileSystem work AND may run under the CM drive must **pin the location to a real
filesystem path** for its body: `Push-Location ($env:SystemDrive + '\')` ... `finally { Pop-Location }`. Then
-Filter/-File/-Recurse bind to FileSystem and work. (Functions that only run on the GUI thread - e.g.
Get-SccmFieldsFromPackage in Populate-Publish - are safe and need no change.) `robocopy` / external exes are
immune (they don't use the PS provider). See also [[verify-semantic-not-syntax]].
