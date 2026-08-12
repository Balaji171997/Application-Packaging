# Audi SW Integration - simple version

Six files. Read them top to bottom and the whole thing fits in your head.

```
   PACKAGER                        SHARE                    SCRIPT RUNNER
   Submit-AudiJob.ps1   ------>   \New\*.json   ------>   Watch-AudiDropFolder.ps1
   reads the package                                              |
   writes a job file                                              v
                                                        Invoke-AudiIntegration.ps1
                                                          connect to the site
                                                          create the application
                                                          create the collections
                                                          create the deployments
                                                          distribute the content
                                                              |
                        \Done\ or \Failed\  <-----------------+
```

| File | What it does |
|---|---|
| `Environments\<CODE>.psd1` | everything about one SCCM environment. The only file you edit |
| `Read-AudiPackage.ps1` | reads a package folder - name, deployment script, request document |
| `Submit-AudiJob.ps1` | packager side: read the package, write a job file into the drop folder |
| `Watch-AudiDropFolder.ps1` | scheduled task on the Script Runner: pick up job files, run them, write results |
| `Invoke-AudiIntegration.ps1` | the engine: everything that touches SCCM, in order |
| `Remove-AudiIntegration.ps1` | undoes an integration |

No XML schema, no provider layer, no dependency graph. A job is a JSON file, an
environment is a PowerShell hashtable, and the engine is one straight run of
ConfigMgr cmdlets.

## Try it

```powershell
# packager
.\Submit-AudiJob.ps1 -PackagePath C:\temp\II1_Lumivero_Citavi_x86_6.19.2.1-0002_MUL -Environment II1

# Script Runner - or a scheduled task running the same line every 5 minutes
.\Watch-AudiDropFolder.ps1 -Environment II1
```

Add `-WhatIf` to `Watch-AudiDropFolder.ps1` to see every step without touching
the site.

## What it creates in SCCM

For one package, in this order:

1. **Application** - `II1_Lumivero_Citavi_x86_6.19.2.1-0002_MUL`, owner = the account that ran it
2. **Deployment type** - `..._INSTALLCOMPUTER`, with **two detection rules**:
   the branding key the package writes, and the product's own uninstall entry
3. **Category** - `Development`
4. **Content distribution** - to the environment's distribution point group
5. **Collections** - one per entry in the environment file
6. **Deployments** - one per collection; `_RemoveComputer` is an Uninstall
7. **Security scopes** - attached to the application
8. **Folders** - the application and every collection moved into place

**Not done yet:** the AD access group (`G-AUDI-AG-SW-<package>`). The old tool
creates it through ARS/SPML. It is written out and commented in
`Invoke-AudiIntegration.ps1` under `# --- 9. AD GROUP`, ready to switch on.

## Things that will bite you, all learned the hard way

- **The content share must be a UNC path.** `C:\temp` is refused by SCCM, and it
  is refused *after* the application has been created. Checked up front here.
- **You must step INTO the site drive.** Creating the PSDrive is not enough;
  every ConfigMgr cmdlet refuses until the current location is `II1:`.
- **You must step back OUT before touching files.** The ConfigMgr provider does
  not support `-Filter`, `-Recurse` or `-File`.
- **Importing the console module warns** when its build differs from the site's.
  It is a warning, not a failure - do not let `-ErrorAction Stop` turn it into one.
- **`Move-CMObject` wants a provider path**, `II1:\Application\ICZ-Applications`,
  not the bare folder name shown in the console.
