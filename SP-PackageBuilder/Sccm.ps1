##############################################################
# Sccm.ps1  -  SCCM Automator (Step 4 integration)
# Auto-fetches every field from the BUILT package's Invoke-AppDeployToolkit.ps1, then runs the
# team's proven create flow so the user never needs the console:
#   map S: -> copy Content to prelive -> New-CMApplication -> DE app-catalog -> move ->
#   Add-CMScriptDeploymentType (+ branding/ProductCode/uninstall detection) -> exit code 60012 ->
#   distribute -> Install/Uninstall collections -> deployments.
# Also: Update-SccmContent (recopy + redistribute) and Open-CMTrace.
# ConfigMgr cmdlets are only invoked at run time; nothing here loads at dot-source.
##############################################################

# Reference defaults (prelive). Override any via settings.json -> "Sccm": { ... }.
$script:SccmDefaults = [ordered]@{
    SiteCode           = 'G08'
    SiteServer         = 'mbdcaswvtb29843.mn-man.biz'
    ContentShare       = '\\mbddfsovpc01.mn-man.biz\SWDPreLive-Gate\CMLib_TEST\Apps'
    DPGroup            = '_ALL_DPs'
    AppFolder          = 'G08:\Application\VOLKSWAGEN\DEVELOPMENT\EQS'
    CollectionFolder   = 'G08:\DeviceCollection\DEVELOPMENT\EQS'
    TestAppFolder      = 'G08:\Application\VOLKSWAGEN\TEST'                          # Dev->Test (UAT) promotion target
    TestCollectionFolder = 'G08:\DeviceCollection\VOLKSWAGEN\SOFTWARE DISTRIBUTION\TEST'
    ClientLogShare     = 'c$\Windows\CCM\Logs'                                       # client-side CCM logs (AppDiscovery/AppEnforce)
    PsadtLogShare      = 'c$\ProgramData\VWG\Logs'                                   # PSADT app install/uninstall logs
    LimitingCollection = 'All Systems'
    ModuleRelPath      = 'ConfigurationManagerPrelive\ConfigurationManager\ConfigurationManager.psd1'
    InstallCmd         = '"Invoke-AppDeployToolkit.exe" install'
    UninstallCmd       = '"Invoke-AppDeployToolkit.exe" uninstall'
    RepairCmd          = '"Invoke-AppDeployToolkit.exe" repair'
    MaxRuntimeMins     = 180
    EstRuntimeMins     = 15
    DeferredExitCode   = 60012
    CMTracePath        = 'C:\Windows\CCM\CMTrace.exe'
    DistWaitSec        = 3600     # how long to wait for content distribution to finish (large apps need longer)
}

function Get-SccmConfig {
    $cfg = @{}; foreach ($k in $script:SccmDefaults.Keys) { $cfg[$k] = $script:SccmDefaults[$k] }
    $over = if (Get-Command Get-Setting -ErrorAction SilentlyContinue) { Get-Setting 'Sccm' } else { $null }
    if ($over) { foreach ($p in $over.PSObject.Properties) { if ($null -ne $p.Value -and "$($p.Value)" -ne '') { $cfg[$p.Name] = $p.Value } } }
    return $cfg
}

# --- Find an existing package folder by name under the Outgoing share (for publish-only use,
#     without building the package in this session). Returns the package root or $null. A valid
#     package root contains Content\Invoke-AppDeployToolkit.ps1. ----------------------------------
function Find-OutgoingPackage {
    param([Parameter(Mandatory)][string]$Name, [string]$BasePath)
    if (-not $BasePath) { $BasePath = if (Get-Command Get-Setting -ErrorAction SilentlyContinue) { Get-Setting 'OutgoingPath' } else { $null } }
    if (-not $BasePath -or -not (Test-Path $BasePath)) { Write-Log "Outgoing path not reachable: $BasePath" Warning; return $null }
    $name = $Name.Trim()
    $cands = New-Object System.Collections.Generic.List[string]
    $exact = Join-Path $BasePath $name
    if (Test-Path $exact) { $cands.Add($exact) }
    foreach ($dir in @(Get-ChildItem -LiteralPath $BasePath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $name -or $_.Name -like "*$name*" })) {
        if ($cands -notcontains $dir.FullName) { $cands.Add($dir.FullName) }
    }
    # Prefer a candidate that actually contains the PSADT script.
    foreach ($c in $cands) {
        if (Get-ChildItem -Path $c -Filter 'Invoke-AppDeployToolkit.ps1' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\Frontend\\' } | Select-Object -First 1) { return $c }
    }
    if ($cands.Count -gt 0) { return $cands[0] }
    return $null
}

# --- Fetch the English short description from the package's "Installation instructions" .docx.
#     The doc is a table: a label cell "Short description of the product in English" followed by
#     the value cell. Filename/format vary - we match on the label text, not the filename.
function Get-PackageDescription {
    param([Parameter(Mandatory)][string]$PackagePath)
    $docs = @(Get-ChildItem -Path $PackagePath -Filter *.docx -Recurse -ErrorAction SilentlyContinue)
    if ($docs.Count -eq 0) { return '' }
    $doc = ($docs | Where-Object { $_.Name -match '(?i)instruction|description|install' } | Select-Object -First 1)
    if (-not $doc) { $doc = $docs[0] }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($doc.FullName)
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'word/document.xml' }
        $sr = New-Object System.IO.StreamReader($entry.Open()); $xml = $sr.ReadToEnd(); $sr.Close(); $zip.Dispose()
    } catch { Write-Log "Description docx read failed: $($_.Exception.Message)" Warning; return '' }
    # Flatten to text: the request form separates a label from its value with a ">" marker
    # (and ends a value at the next "... description of the product" / "Dependencies" label).
    $t = $xml -replace '</w:p>', ' ' -replace '<[^>]+>', ''
    $t = [System.Net.WebUtility]::HtmlDecode($t) -replace '\s+', ' '
    foreach ($label in @('Short description of the product in English', 'Detailed description of the product in English')) {
        $m = [regex]::Match($t, [regex]::Escape($label) + '\s*>?\s*(?<v>.+?)\s*>?\s*(?:Detailed description of the product|Short description of the product|Dependencies)', 'IgnoreCase')
        if ($m.Success) {
            $val = ($m.Groups['v'].Value.Trim() -replace '\s*>\s*$', '')
            if ($val -and $val -notmatch '(?i)^\s*click here to enter text\s*$' -and $val.Length -gt 3) { return $val }
        }
    }
    return ''
}

# --- Parse the built package's Invoke-AppDeployToolkit.ps1 into the SCCM field set. ----------
function Get-SccmFieldsFromPackage {
    param([Parameter(Mandatory)][string]$PackagePath)
    $cfg = Get-SccmConfig
    if (-not (Test-Path -LiteralPath $PackagePath)) { Write-Log "SCCM: package path does not exist: $PackagePath" Error; return $null }
    # Find the PSADT script: v4 'Invoke-AppDeployToolkit.ps1' OR fall back to v3 'Deploy-Application.ps1' (older /
    # other-team packages). Search the whole tree (the script may sit under \Content) but skip PSADT Frontend copies.
    $ps1 = $null
    foreach ($fn in 'Invoke-AppDeployToolkit.ps1','Deploy-Application.ps1') {
        $ps1 = Get-ChildItem -Path $PackagePath -Filter $fn -Recurse -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -notmatch '\\Frontend\\' } | Select-Object -First 1
        if ($ps1) { break }
    }
    if (-not $ps1) { Write-Log "SCCM: no PSADT script (Invoke-AppDeployToolkit.ps1 / Deploy-Application.ps1) found under $PackagePath - is this a built package folder (it should contain Content\)?" Error; return $null }
    # PSADT VERSION decides the SCCM/Intune deployment command: v3 runs Deploy-Application.exe, v4 runs
    # Invoke-AppDeployToolkit.exe. Detected from which script we found, so v3 packages integrate correctly too.
    $isV3 = ($ps1.Name -ieq 'Deploy-Application.ps1')
    $txt = if (Get-Command Read-FileSmart -ErrorAction SilentlyContinue) { Read-FileSmart -Path $ps1.FullName } else { Get-Content $ps1.FullName -Raw }

    # Field reader: matches v4 "AppVendor = '..'", v3 "[string]$appVendor = '..'" AND the v3 VWG-prefixed names
    # ($VWG_SoftIdent). A v3 variable can be defined TWICE (top + a CUSTOM VARIABLES override, e.g. the 32-bit
    # SoftIdent with the hive token) - the LAST definition is what runs, so take the LAST match.
    # Reads a field's value from EITHER quote style ('..' or "..") - v3/v4 scripts use both (e.g. the v3 custom-vars
    # SoftIdent override is double-quoted). A field can be defined twice (top + a CUSTOM VARIABLES override) - the LAST
    # definition is what runs, so take the last match.
    $get = { param($f)
        $ms = [regex]::Matches($txt, "(?im)^\s*(?:\[[^\]]+\]\s*)?\`$?(?:VWG_)?$f\s*=\s*(?:'([^']*)'|""([^""]*)"")")
        if ($ms.Count) { $m = $ms[$ms.Count-1]; if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value } } else { '' }
    }
    $vendor = & $get 'AppVendor'; $app = & $get 'AppName'; $arch = & $get 'AppArch'
    $ver    = & $get 'AppVersion'; $rev = & $get 'AppRevision'; $lang = & $get 'AppLang'
    $soft   = & $get 'SoftIdent'   # both quote styles + last-def-wins -> the v3 double-quoted custom-vars override is seen
    $softHadWowToken = ($soft -match '(?i)VWG_CurrentRegWO?W')   # v3 32-bit hive token present -> 32-bit on 64-bit
    # v3 32-bit hive token: SoftIdent may embed $($VWG_CurrentRegWOW). Resolve it to its REAL value from the token's own
    # definition in the same script (32-bit packages define it as 'WoW6432Node\'; 64-bit as ''); no definition -> by the
    # package arch. Downstream then treats it exactly like a literal WoW6432Node key: strip it + tick the 32-bit box.
    if ($soft -match '(?i)VWG_CurrentRegWO?W') {
        $dm = [regex]::Matches($txt, "(?im)^\s*(?:\[[^\]]+\]\s*)?\`$VWG_CurrentRegWO?W\s*=\s*(?:'([^']*)'|""([^""]*)"")")
        $wow = if ($dm.Count) { $lm = $dm[$dm.Count-1]; if ($lm.Groups[1].Success) { $lm.Groups[1].Value } else { $lm.Groups[2].Value } } elseif ("$arch" -match '(?i)x86') { 'WoW6432Node\' } else { '' }
        if ($wow -and $wow -notmatch '\\$') { $wow = "$wow\" }   # the token replaces the WHOLE hive segment ('SOFTWARE\<token>Microsoft') - keep the trailing backslash
        $soft = [regex]::Replace($soft, '(?i)\$\(\s*\$?VWG_CurrentRegWO?W\s*\)|\$VWG_CurrentRegWO?W', $wow)
        $soft = [regex]::Replace($soft, '(?<=[^:\\])\\{2,}', '\')   # collapse doubles (e.g. when the path had an explicit '\' after the token, or the token resolved empty)
    }

    # FullName: prefer an explicit $AppFullName / the package folder name, else reconstruct.
    $full = ([regex]::Match($txt, "(?im)AppFullName\s*=.*?""?([A-Za-z0-9]+_.+?_(?:x86|x64|ALL)_[^_\r\n""]+_[\w-]+)")).Groups[1].Value
    if (-not $full) { $full = Split-Path $PackagePath -Leaf }
    if ($full -notmatch '_') { $full = "${vendor}_${app}_${arch}_${ver}-${rev}_${lang}" }

    # ProductCode (the package's OWN): prefer the SoftIdent GUID, then the MAIN-UNINSTALLATION
    # -ProductCode, then any GUID. (A bare "first GUID" would catch a predecessor's uninstall PC.)
    $pc = ([regex]::Match($soft, '\{[0-9A-Fa-f\-]{36}\}')).Value
    if (-not $pc) { $pc = ([regex]::Match($txt, "(?is)MAIN-UNINSTALLATION BEGIN.*?-ProductCode\s*['""](\{[0-9A-Fa-f\-]{36}\})['""]")).Groups[1].Value }
    if (-not $pc) { $pc = ([regex]::Match($txt, '\{[0-9A-Fa-f\-]{36}\}')).Value }

    # Uninstall detection key + version from SoftIdent: "HKLM:\SOFTWARE\..\Uninstall\<id> [DisplayVersion = X]".
    # If the key sits under WoW6432Node we STRIP it and mark the clause 32-bit (SCCM "this key is
    # 32-bit on 64-bit Windows" / Intune Check32BitOn64System) - you never put WoW6432Node in the path.
    $uninstKey = ''; $detVer = ''
    if ($soft) {
        $m = [regex]::Match($soft, '(?i)^HKLM:\\(?<key>.+?)\s*(?:\[DisplayVersion\s*=\s*(?<v>[^\]]+)\])?\s*$')
        if ($m.Success) { $uninstKey = $m.Groups['key'].Value.Trim(); $detVer = $m.Groups['v'].Value.Trim() }
    }
    if (-not $detVer) { $detVer = $ver }
    $uninst32 = ($uninstKey -match '(?i)WoW6432Node\\')
    $uninstKey = $uninstKey -replace '(?i)WoW6432Node\\', ''
    # 32-bit-on-64-bit for the detection clause: a WoW6432Node key OR the v3 $($VWG_CurrentRegWOW) token means 32-bit;
    # a clean key present means 64-bit; no key -> fall back to the package arch. (The user can still override the box.)
    $is32 = if ($uninst32 -or $softHadWowToken) { $true } elseif ($uninstKey) { $false } else { "$arch" -match '(?i)x86' }

    # Icons folder resolved from ANY path level (root/Content/subfolder) so the SCCM app icon is found whether the
    # packager points at the package root or the Content folder (Icons sits at the ROOT - see Resolve-IconsDir).
    $iconFolder = if (Get-Command Resolve-IconsDir -ErrorAction SilentlyContinue) { Resolve-IconsDir -PackagePath $PackagePath } else { Join-Path $PackagePath 'Icons' }
    $icon = ''
    if ($iconFolder -and (Test-Path $iconFolder)) { $i = Get-ChildItem $iconFolder -Filter *.ico -File -ErrorAction SilentlyContinue | Select-Object -First 1; if ($i) { $icon = $i.FullName } }

    return @{
        FullName     = $full
        Publisher    = $vendor
        Version      = $ver
        Revision     = $rev
        ProductName  = $app
        Arch         = $arch
        Is32Bit      = $is32         # 32-bit-on-64-bit for the uninstall detection clause
        ProductCode  = $pc
        BrandingKey  = "SOFTWARE\VWG\CM\$full"
        UninstallKey = $uninstKey
        DetectVersion= $detVer
        DetectType   = 'Version'        # Version | String | ProductCode | None  (2nd detection clause)
        Description  = $($dsc = Get-PackageDescription -PackagePath $PackagePath; if ($dsc) { $dsc } else { "$vendor $app" })
        PsadtVersion = if ($isV3) { 'v3' } else { 'v4' }
        # v3 packages deploy via Deploy-Application.exe, v4 via Invoke-AppDeployToolkit.exe - BOTH with the POSITIONAL
        # deployment type (team convention: '"Deploy-Application.exe" Install', never -DeploymentType). These land in
        # the editable publish fields, so a packager can still adjust switches (e.g. add -DeployMode).
        InstallCmd   = if ($isV3) { '"Deploy-Application.exe" Install' }   else { $cfg.InstallCmd }
        UninstallCmd = if ($isV3) { '"Deploy-Application.exe" Uninstall' } else { $cfg.UninstallCmd }
        RepairCmd    = if ($isV3) { '"Deploy-Application.exe" Repair' }    else { $cfg.RepairCmd }
        IconPath     = $icon
        LocalSource  = $PackagePath
        ContentPath  = (Join-Path (Join-Path $cfg.ContentShare $full) 'Content')
    }
}

# --- Map S: and copy the package Content into the prelive content location FIRST. -----------
function Copy-PackageToPrelive {
    param([Parameter(Mandatory)][string]$LocalPackagePath, [Parameter(Mandatory)][string]$FullName)
    $cfg = Get-SccmConfig
    # This does FILESYSTEM work but is called while the current location is the CMSite drive (New-SccmApplication
    # wraps it in Push-Location G08:). PowerShell binds a cmdlet's dynamic parameters (-Filter / -File / -Recurse)
    # from the CURRENT drive's provider, and the ConfigMgr provider rejects them ("the provider does not support the
    # use of filters"). Pin the location to a real filesystem path so every cmdlet below binds to FileSystem.
    Push-Location ($env:SystemDrive + '\')
    try {
    if (-not (Get-PSDrive -Name 'S' -ErrorAction SilentlyContinue)) {
        try { New-PSDrive -Name 'S' -PSProvider FileSystem -Root $cfg.ContentShare -Persist -ErrorAction Stop | Out-Null; Write-Log "Mapped S: -> $($cfg.ContentShare)" }
        catch { Write-Log "Could not map S: ($($_.Exception.Message)) - using UNC directly." Warning }
    }
    # Find the REAL Content folder = the dir that holds Invoke-AppDeployToolkit.ps1 (NOT the PSADT Frontend copy),
    # at WHATEVER depth it sits under the given path. The fast paths (<root>\Content, then <root> itself) cover the
    # normal layout; the recursive search tolerates a manual copy that added an extra nesting level - this matches
    # Find-OutgoingPackage's own logic, so a package it accepted as "found" can never be rejected here as "not a
    # Content folder" (the "it IS the correct folder" report).
    $srcContent = $null
    foreach ($cand in @((Join-Path $LocalPackagePath 'Content'), $LocalPackagePath)) {
        if (Test-Path (Join-Path $cand 'Invoke-AppDeployToolkit.ps1')) { $srcContent = $cand; break }
    }
    if (-not $srcContent) {
        $ps1 = Get-ChildItem -Path $LocalPackagePath -Filter 'Invoke-AppDeployToolkit.ps1' -Recurse -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -notmatch '\\Frontend\\' } | Select-Object -First 1
        if ($ps1) { $srcContent = Split-Path -Parent $ps1.FullName }
    }
    # GUARD: /MIR deletes whatever is on prelive that isn't in the source. Refuse to mirror unless we located a
    # REAL package Content folder - otherwise a wrong browse/typo would wipe good content.
    if (-not $srcContent) {
        Write-Log "Refusing to copy: no Invoke-AppDeployToolkit.ps1 found under '$LocalPackagePath' (not a package Content folder). Check the content source." Error
        return $false
    }
    $destPkg = Join-Path $cfg.ContentShare $FullName
    $destContent = Join-Path $destPkg 'Content'
    if (-not (Test-Path $destContent)) { New-Item $destContent -ItemType Directory -Force | Out-Null }
    Write-Log "Copying Content to prelive: $destContent"
    # /MT:16 = 16-thread copy (big win for many files), /J = unbuffered I/O (big win for large/multi-GB files).
    # robocopy verifies each file, so this is faster but NOT lossy/corrupting.
    $rcFlags = '/MIR','/J','/MT:16','/R:2','/W:2','/NFL','/NDL','/NJH','/NJS','/NP'
    robocopy "$srcContent" "$destContent" @rcFlags | Out-Null
    # robocopy exit codes: 0-7 = success (with/without copies/extras); >=8 = at least one FAILED copy.
    if ($LASTEXITCODE -ge 8) {
        Write-Log "robocopy reported failures copying Content to prelive (exit $LASTEXITCODE) - content may be INCOMPLETE; not continuing." Error
        return $false
    }
    # docs/icons one level under the package (siblings of Content), if present locally
    foreach ($side in 'Documents','Icons') {
        $s = Join-Path $LocalPackagePath $side
        if (Test-Path $s) {
            robocopy "$s" (Join-Path $destPkg $side) @rcFlags | Out-Null
            if ($LASTEXITCODE -ge 8) { Write-Log "robocopy reported failures copying $side (exit $LASTEXITCODE) - check the share." Warning }
        }
    }
    return (Test-Path (Join-Path $destContent 'Invoke-AppDeployToolkit.ps1'))
    } finally { Pop-Location }
}

# --- Connect to the SCCM site (import module + site PSDrive). --------------------------------
# The REAL reason the last Connect-Sccm failed. Every caller used to report a flat "Could not connect to the SCCM
# site.", which is actively misleading when the actual fault was the module import (e.g. the ConfigMgr console's
# AdminUI.PS.psm1 blocked by execution policy) - the site was never even contacted. Get-SccmConnectMessage appends it.
$script:SccmConnectError = ''
function Get-SccmConnectMessage {
    if ("$script:SccmConnectError".Trim()) { return "Could not connect to the SCCM site. $script:SccmConnectError" }
    return 'Could not connect to the SCCM site.'
}
# TRUE when any ConfigMgr/AdminUI assembly is already loaded in this process. Used to decide whether falling back to the
# BUNDLED ConfigMgr module is safe: if the console's assemblies are in the AppDomain, importing a DIFFERENT build of the
# same module clashes (that clash is exactly why we prefer the installed console module in the first place).
function Test-ConfigMgrAssemblyLoaded {
    try {
        return [bool](@([AppDomain]::CurrentDomain.GetAssemblies()) | Where-Object {
            "$($_.FullName)" -match '(?i)^(AdminUI\.|Microsoft\.ConfigurationManagement)'
        } | Select-Object -First 1)
    } catch { return $false }
}
function Connect-Sccm {
    param([string]$ToolRoot)
    $cfg = Get-SccmConfig
    $script:SccmConnectError = ''
    if (-not (Get-Module ConfigurationManager)) {
        # EXECUTION POLICY (root cause of "running scripts is disabled on this system" when importing the CONSOLE's
        # module): the launcher is a 32-BIT ps2exe process, so it reads the WOW6432Node PowerShell hive - which is
        # commonly Undefined (= Restricted) even when the 64-bit LocalMachine policy is Bypass. The ConfigMgr console
        # module is a SCRIPT module (AdminUI.PS.psm1), so the import dies. Lift it for THIS PROCESS ONLY: in-memory,
        # no admin rights, no registry write, gone when the tool exits. Only a GPO-set MachinePolicy/UserPolicy can
        # block this - in that case we warn and still try (the bundled-module fallback below may carry us).
        if (Get-Command Enable-PBProcessScripts -ErrorAction SilentlyContinue) { [void](Enable-PBProcessScripts) }
        else { try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop } catch { Write-Log "Could not relax the execution policy for this process - a GPO may enforce it: $($_.Exception.Message)" Warning } }

        # A machine with the ConfigMgr CONSOLE INSTALLED already has the module on disk (SMS_ADMIN_UI_PATH) -
        # importing our bundled copy there clashes (assembly already loaded). Prefer the installed console's module.
        $installedMod = $null
        if ($env:SMS_ADMIN_UI_PATH) {
            $c = Join-Path (Split-Path $env:SMS_ADMIN_UI_PATH -Parent) 'ConfigurationManager.psd1'
            if (Test-Path $c) { $installedMod = $c; Write-Log "ConfigMgr console detected on this machine - using its module: $c" }
        }
        # ModuleRelPath is tool-relative (e.g. ConfigurationManagerPrelive\...). Resolve against the
        # passed ToolRoot, else the tool/exe folder. Absolute paths pass through. Consolidated layout:
        # if not at the root, also look under Lib\ (everything-under-Lib team copy).
        # Resolved SEPARATELY from $installedMod so it stays available as a FALLBACK when the console module fails.
        $bundledMod = if ([IO.Path]::IsPathRooted($cfg.ModuleRelPath)) { $cfg.ModuleRelPath }
                      elseif ($ToolRoot) { Join-Path $ToolRoot $cfg.ModuleRelPath }
                      else { Resolve-ToolPath $cfg.ModuleRelPath }
        if (-not (Test-Path $bundledMod) -and -not [IO.Path]::IsPathRooted($cfg.ModuleRelPath)) {
            $base = if ($ToolRoot) { $ToolRoot } else { Get-ToolRoot }
            $alt = Join-Path (Join-Path $base 'Lib') $cfg.ModuleRelPath
            if (Test-Path $alt) { $bundledMod = $alt }
        }
        # When the tool relaunched itself locally from a share (GUI.ps1), the huge ConfigMgr module was NOT mirrored -
        # it stays on the share. Fall back to $env:PB_SHAREROOT so this (now full-trust) local process imports it there.
        if (-not (Test-Path $bundledMod) -and $env:PB_SHAREROOT -and -not [IO.Path]::IsPathRooted($cfg.ModuleRelPath)) {
            foreach ($cand in @((Join-Path $env:PB_SHAREROOT $cfg.ModuleRelPath), (Join-Path (Join-Path $env:PB_SHAREROOT 'Lib') $cfg.ModuleRelPath))) {
                if (Test-Path $cand) { $bundledMod = $cand; break }
            }
        }
        $mod = if ($installedMod) { $installedMod } else { $bundledMod }
        if (-not (Test-Path $mod)) { $script:SccmConnectError = "The ConfigMgr PowerShell module was not found ($mod)."; Write-Log "ConfigMgr module not found: $mod (put ConfigurationManagerPrelive\ next to the tool or under Lib\)." Error; return $false }
        try { Import-Module $mod -ErrorAction Stop } catch {
            $firstLine = ("$($_.Exception.Message)" -split "`r?`n")[0]
            # Console-installed machines can throw here (same assemblies already loaded) although the module IS
            # usable - if it ended up loaded, SKIP the import failure and continue with the integration.
            if (Get-Module ConfigurationManager) {
                Write-Log "ConfigMgr module import reported an error but the module IS loaded (console already present) - continuing: $firstLine" Warning
            }
            # The CONSOLE's module failed (execution policy still blocked, corrupt install...). Fall back to our BUNDLED
            # copy - but ONLY when NO ConfigMgr assembly is already in this AppDomain. The whole reason we prefer the
            # console's module is that importing the bundled one alongside already-loaded console assemblies CLASHES
            # (mismatched versions of the same types). Get-Module being null is NOT proof nothing loaded: a PARTIAL
            # import (assemblies in, script fails after) leaves exactly that state - and that IS the clash case. So
            # check the AppDomain directly and refuse the fallback when console types are present; a clear error beats
            # a subtly broken session.
            elseif ($installedMod -and $bundledMod -and (Test-Path $bundledMod) -and -not (Test-ConfigMgrAssemblyLoaded)) {
                Write-Log "Console ConfigMgr module import FAILED ($firstLine) - no ConfigMgr assembly is loaded, so falling back to the bundled module: $bundledMod" Warning
                try { Import-Module $bundledMod -ErrorAction Stop; Write-Log "ConfigMgr module loaded from the bundled copy (console module was unusable)." }
                catch {
                    if (Get-Module ConfigurationManager) { Write-Log "Bundled ConfigMgr module reported an error but IS loaded - continuing: $(("$($_.Exception.Message)" -split "`r?`n")[0])" Warning }
                    else { $script:SccmConnectError = "The ConfigMgr module could not be imported (console AND bundled) - $firstLine"; Write-Log "Import ConfigMgr module failed (console AND bundled): $($_.Exception.Message)" Error; return $false }
                }
            }
            else {
                # Either the console module failed while its assemblies ARE already loaded (substituting the bundled
                # build now would clash), or there is no bundled copy. Fail cleanly with the real reason.
                $hint = if ($installedMod -and (Test-ConfigMgrAssemblyLoaded)) { ' ConfigMgr assemblies are already loaded in this process, so the bundled module cannot be substituted - restart the tool; if the console module is blocked by policy, have it allowed centrally.' } else { '' }
                $script:SccmConnectError = "The ConfigMgr module could not be imported - $firstLine$hint"; Write-Log "Import ConfigMgr module failed: $($_.Exception.Message)$hint" Error; return $false
            }
        }
    }
    if (-not (Get-PSDrive -Name $cfg.SiteCode -ErrorAction SilentlyContinue)) {
        # -Scope Global so the CMSite drive survives this function and is usable by the create flow.
        # The CMSite provider runs a console-vs-site VERSION CHECK when the drive is created. After a
        # site upgrade it emits "A new version of the console is available (x.x.x.x). Cmdlets may not
        # function as expected..." - a WARNING, not a real fault. Under -ErrorAction Stop that warning
        # was promoted to a terminating error and the tool wrongly reported "failed to connect".
        # Fix: suppress the version notice, create the drive, then VERIFY it exists. Only a genuinely
        # missing drive (wrong server / no rights) is a real failure.
        $drvErr = $null
        New-PSDrive -Name $cfg.SiteCode -PSProvider CMSite -Root $cfg.SiteServer -Description 'SCCM Site' `
            -Scope Global -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -ErrorVariable drvErr | Out-Null
        if (-not (Get-PSDrive -Name $cfg.SiteCode -ErrorAction SilentlyContinue)) {
            $why = if ($drvErr) { ($drvErr | Select-Object -First 1).ToString() } else { 'unknown error' }
            # "A non-recoverable error occurred during a database lookup" = the SMS Provider host name did not resolve /
            # was unreachable. This is a network/name-resolution/rights issue, NOT a tool bug.
            $hint = if ($why -match '(?i)database lookup|no such host|not be resolved|RPC server') {
                        " -> '$($cfg.SiteServer)' could not be resolved/reached from this machine. Check you are on the corporate network/VPN, that the name resolves (nslookup $($cfg.SiteServer)), that it is the correct SMS Provider server (settings.json -> Sccm.SiteServer), and that you have SCCM console rights."
                    } else { " -> verify the SMS Provider '$($cfg.SiteServer)' is reachable and you have SCCM console rights." }
            $script:SccmConnectError = "Site drive $($cfg.SiteCode): could not be created against '$($cfg.SiteServer)' - $why"; Write-Log "New-PSDrive $($cfg.SiteCode): failed connecting to '$($cfg.SiteServer)': $why$hint" Error; return $false
        }
        if ($drvErr) { Write-Log "SCCM connected; ignored console/site version notice: $(($drvErr | Select-Object -First 1).ToString())" Warning }
    }
    return $true
}

# Build the second detection clause: the SoftIdent/uninstall key (preferred) with the 32-bit
# flag (no -Is64Bit when the key was under WoW6432Node), else the MSI ProductCode.
function New-SccmUninstallClause {
    param([hashtable]$Fields)
    # STRICT: exactly ONE secondary clause for the selected type, never the other. ProductCode and the
    # uninstall/version key are mutually exclusive - selecting one must never also create the other.
    $type = if ($Fields.DetectType) { "$($Fields.DetectType)" } else { 'Version' }
    if ($type -eq 'None') { return $null }
    if ($type -eq 'ProductCode') {
        if ($Fields.ProductCode) { return (New-CMDetectionClauseWindowsInstaller -ProductCode $Fields.ProductCode -Existence) }
        Write-Log "SCCM: detect type 'ProductCode' but the package has no ProductCode - 2nd clause skipped (branding only)." Warning
        return $null
    }
    # Version / String -> registry DisplayVersion on the uninstall key (WoW6432Node already stripped;
    # 32-bit flag from $Fields.Is32Bit). NO fallback to ProductCode - the chosen type is honored strictly.
    if (-not $Fields.UninstallKey) {
        Write-Log "SCCM: detect type '$type' but the package has no uninstall key - 2nd clause skipped (branding only)." Warning
        return $null
    }
    $p = @{ ExpectedValue=$Fields.DetectVersion; Hive='LocalMachine'; KeyName=$Fields.UninstallKey; Value=$true; ValueName='DisplayVersion' }
    if ($type -eq 'String') { $p['PropertyType']='String'; $p['ExpressionOperator']='IsEquals' }
    else                    { $p['PropertyType']='Version'; $p['ExpressionOperator']='GreaterEquals' }
    if (-not $Fields.Is32Bit) { $p['Is64Bit'] = $true }
    return (New-CMDetectionClauseRegistryKeyValue @p)
}

# Review/update detection on an EXISTING app (branding key is always kept; re-applies the
# uninstall/ProductCode clause from the current fields). Returns @{ Ok; Message }.
# Identify the branding clause (registry key under ...\VWG\CM\...) vs the secondary clause.
function Test-SccmBrandingClause { param($Clause) return ("$($Clause.Setting.Location)" -match '(?i)\\VWG\\CM\\') }
# Pull the removal logical name off a detection clause (property name varies by CM build).
function Get-SccmClauseName {
    param($Clause)
    foreach ($p in 'SettingLogicalName','LogicalName') { if ($Clause.PSObject.Properties[$p] -and $Clause.$p) { return "$($Clause.$p)" } }
    if ($Clause.Setting) { foreach ($p in 'LogicalName','SettingLogicalName') { if ($Clause.Setting.PSObject.Properties[$p] -and $Clause.Setting.$p) { return "$($Clause.Setting.$p)" } } }
    return $null
}

# Read the existing SECONDARY detection (branding ignored) off an app so the user can edit it.
function Get-SccmDetection {
    param([Parameter(Mandatory)][string]$FullName, [string]$ToolRoot)
    $cfg = Get-SccmConfig
    if (-not (Connect-Sccm -ToolRoot $ToolRoot)) { return @{ Ok=$false; Message=(Get-SccmConnectMessage) } }
    Push-Location "$($cfg.SiteCode):"
    try {
        $dt = Get-CMDeploymentType -ApplicationName $FullName -DeploymentTypeName $FullName -ErrorAction SilentlyContinue
        if (-not $dt) { return @{ Ok=$false; Message="Application / deployment type '$FullName' not found in SCCM." } }
        $clauses = @(Get-CMDeploymentTypeDetectionClause -InputObject $dt -ErrorAction SilentlyContinue)
        $det = [ordered]@{ DetectType='None'; UninstallKey=''; DetectVersion=''; Is32Bit=$false; ProductCode='' }
        foreach ($c in $clauses) {
            if (Test-SccmBrandingClause $c) { continue }   # branding stays implicit
            $src = "$($c.Setting.SourceType)"
            if ($src -match '(?i)MSI|Installer|ProductCode') {
                $det.DetectType = 'ProductCode'; $det.ProductCode = "$($c.Setting.ProductCode)"
            } elseif ($src -match '(?i)Registry') {
                $det.UninstallKey  = "$($c.Setting.Location)"
                $det.Is32Bit       = -not [bool]$c.Setting.Is64Bit
                $det.DetectVersion = "$($c.ConstantValue)"; if (-not $det.DetectVersion) { $det.DetectVersion = "$($c.constant.Value)" }
                $det.DetectType    = if ("$($c.DataType.TypeName)" -match '(?i)String') { 'String' } else { 'Version' }
            }
        }
        Write-Log "SCCM: fetched detection for '$FullName' ($($clauses.Count) clause(s); secondary type = $($det.DetectType))."
        return @{ Ok=$true; Detection=$det; Message="Fetched detection for '$FullName' - edit below and click Update detection." }
    } catch { return @{ Ok=$false; Message="Fetch detection failed: $($_.Exception.Message)" } }
    finally { Pop-Location }
}

# Replace ONLY the secondary detection clause; the branding key is ALWAYS kept (never shown/edited).
function Update-SccmDetection {
    param([Parameter(Mandatory)][hashtable]$Fields, [string]$ToolRoot)
    $cfg = Get-SccmConfig
    Set-PbProgress -Indeterminate -Status 'Connecting to the SCCM site...'
    if (-not (Connect-Sccm -ToolRoot $ToolRoot)) { return @{ Ok=$false; Message=(Get-SccmConnectMessage) } }
    Push-Location "$($cfg.SiteCode):"
    try {
        $name = $Fields.FullName
        $dt = Get-CMDeploymentType -ApplicationName $name -DeploymentTypeName $name -ErrorAction SilentlyContinue
        if (-not $dt) { return @{ Ok=$false; Message="Application / deployment type '$name' not found." } }
        # 1. Remove ONLY the non-branding clause(s). Branding stays, so the DT is never left empty and the
        #    branding key never duplicates. (We do NOT re-add branding here.)
        Set-PbProgress -Percent 35 -Status 'Reading existing detection...'
        $clauses = @(Get-CMDeploymentTypeDetectionClause -InputObject $dt -ErrorAction SilentlyContinue)
        $secNames = @(); foreach ($c in $clauses) { if (-not (Test-SccmBrandingClause $c)) { $n = Get-SccmClauseName $c; if ($n) { $secNames += $n } } }
        Write-Log "SCCM: existing detection = $($clauses.Count) clause(s); removing $($secNames.Count) non-branding."
        Set-PbProgress -Percent 60 -Status 'Removing old secondary detection...'
        if ($secNames.Count) {
            try { Set-CMScriptDeploymentType -ApplicationName $name -DeploymentTypeName $name -RemoveDetectionClause $secNames -ErrorAction Stop | Out-Null }
            catch { Write-Log "SCCM: removing old secondary clause(s) failed: $($_.Exception.Message)" Warning }
        }
        # 2. Add the new secondary clause for the selected type (None -> branding only).
        Set-PbProgress -Percent 85 -Status 'Adding new detection...'
        $extra = New-SccmUninstallClause -Fields $Fields
        if ($extra) { Set-CMScriptDeploymentType -ApplicationName $name -DeploymentTypeName $name -AddDetectionClause $extra -ErrorAction Stop | Out-Null }
        Set-PbProgress -Percent 100 -Status 'Done.'
        $what = if ($extra) { "$(if($Fields.DetectType){$Fields.DetectType}else{'Version'})" } else { 'none (branding only)' }
        Write-Log "SCCM: detection updated on '$name' (branding kept; secondary = $what; removed $($secNames.Count))." Success
        return @{ Ok=$true; Message="Detection updated on '$name' - branding kept, secondary set to: $what (removed $($secNames.Count) old)." }
    } catch { return @{ Ok=$false; Message="Update detection failed: $($_.Exception.Message)" } }
    finally { Pop-Location }
}

# Read the RFC / order number from a BUILT package's PSADT script ($adtSession.OrderNumber = 'RFC1234'). SCCM collection
# comments must carry "RFC_<OrderNumber>", but for a LOADED package the RITM textbox is empty - so the package script is the
# source of truth. Finds Content\Invoke-AppDeployToolkit.ps1 (or a recursive fallback, skipping the Frontend copy) and
# reads the OrderNumber / VWG_OrderNumber value. Returns '' when nothing usable is found.
function Get-PackageOrderNumber {
    param([string]$PackagePath)
    if (-not $PackagePath) { return '' }
    $ps1 = $null
    foreach ($c in @((Join-Path $PackagePath 'Content\Invoke-AppDeployToolkit.ps1'),
                     (Join-Path $PackagePath 'Invoke-AppDeployToolkit.ps1'),
                     (Join-Path $PackagePath 'Content\Deploy-Application.ps1'),
                     (Join-Path $PackagePath 'Deploy-Application.ps1'))) {
        if (Test-Path -LiteralPath $c) { $ps1 = $c; break }
    }
    if (-not $ps1) {
        $ps1 = Get-ChildItem -LiteralPath $PackagePath -Recurse -Include 'Invoke-AppDeployToolkit.ps1','Deploy-Application.ps1' -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -notmatch '\\Frontend\\' } | Select-Object -First 1 | ForEach-Object { $_.FullName }
    }
    if (-not $ps1 -or -not (Test-Path -LiteralPath $ps1)) { return '' }
    $txt = Get-Content -LiteralPath $ps1 -Raw -ErrorAction SilentlyContinue
    if (-not $txt) { return '' }
    $m = [regex]::Match($txt, "(?im)^[ \t]*(?:\[[^\]]+\][ \t]*)?\`$?(?:Global:)?(?:VWG_)?OrderNumber[ \t]*=[ \t]*['`"]([^'`"\r\n]+)['`"]")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

# --- The create flow. Returns @{ Ok; Message }. -------------------------------------------
function New-SccmApplication {
    param(
        [Parameter(Mandatory)][hashtable]$Fields,
        [string]$ToolRoot,
        [string]$LocalPackagePath,
        [bool]$Distribute = $true,
        [bool]$Collections = $true,
        [bool]$Deploy = $true,
        [bool]$AllowUserInteraction = $true,
        [string]$RfcComment = ''
    )
    $cfg = Get-SccmConfig
    $name = $Fields.FullName
    # RFC/order number for the collection comments: prefer whatever was passed (the RITM the user typed), but for a LOADED
    # package that textbox is empty - fall back to the OrderNumber baked into the package's own PSADT script, so the
    # collections are always tagged "RFC_<OrderNumber>" instead of a bare "RFC_".
    if (-not "$RfcComment".Trim() -and $LocalPackagePath) {
        $fromPs1 = Get-PackageOrderNumber -PackagePath $LocalPackagePath
        if ($fromPs1) { $RfcComment = $fromPs1; Write-Log "SCCM: RFC/order number '$RfcComment' read from the package script (RITM box was empty)." }
        else { Write-Log "SCCM: no OrderNumber in the package script and no RITM entered - collections will be tagged 'RFC_' only." Warning }
    }
    try {
        # 0. Connect + "already exists" check FIRST - before the (possibly multi-GB) prelive copy,
        #    so a duplicate name fails in seconds instead of after minutes of copying.
        Set-PbProgress -Percent 3 -Status 'Connecting to the SCCM site...'
        if (-not (Connect-Sccm -ToolRoot $ToolRoot)) { return @{ Ok=$false; Message=(Get-SccmConnectMessage) } }
        Push-Location "$($cfg.SiteCode):"
        $instColl = "$name-INSTALL (TEST)"; $uninstColl = "$name-UNINSTALL (TEST)"
        $appCreated = $false; $instCollCreated = $false; $uninstCollCreated = $false
        try {
            if (Get-CMApplication -Name $name -ErrorAction SilentlyContinue) { return @{ Ok=$false; Message="Application '$name' already exists - nothing created." } }

            # 0b. Content to prelive (robocopy works on UNC paths regardless of the CMSite PSDrive CWD).
            if ($LocalPackagePath) {
                Set-PbProgress -Percent 8 -Status 'Copying content to prelive share...'
                if (-not (Copy-PackageToPrelive -LocalPackagePath $LocalPackagePath -FullName $name)) {
                    return @{ Ok=$false; Message='Content copy to prelive failed (see log - bad source folder or copy errors).' }
                }
            }

            # 1. Application
            $localized = "$($Fields.ProductName) $($Fields.Version)"
            $desc = "$($Fields.Description)"
            Set-PbProgress -Percent 40 -Status 'Creating the application...'

            # DEFAULT (en-US) icon: pass the icon path straight to -IconLocationFile. The SCCM cmdlet reads
            # the file itself (UNC \\server\share\.. works) and stores it in the right internal format. The
            # German display below then REUSES those exact stored bytes, so we don't build any icon by hand.
            if ($Fields.IconPath -and (Test-Path $Fields.IconPath)) { Write-Log "SCCM: icon -> $($Fields.IconPath)" }
            else { Write-Log "SCCM: no icon found in the package (Icons\*.ico) - app will have no custom icon." Warning }

            Write-Log "SCCM: New-CMApplication $name"
            $appParams = @{ Name=$name; Publisher=$Fields.Publisher; SoftwareVersion=$Fields.Version; AutoInstall=$true
                            LocalizedName=$localized; Keyword=$Fields.ProductName; ErrorAction='Stop' }
            if ($Fields.IconPath) { $appParams['IconLocationFile'] = $Fields.IconPath }   # proven UNC-safe default icon
            if ($desc) { $appParams['LocalizedDescription'] = $desc }
            $appRes = New-CMApplication @appParams
            if (-not $appRes.CI_UniqueID) { throw 'New-CMApplication returned no CI_UniqueID.' }
            $appCreated = $true

            # 1b. German (de) display - REUSE the exact Icon object SCCM already built for the default
            #     display from -IconLocationFile, so the icon byte FORMAT is guaranteed correct (our own
            #     .ico / ExtractAssociatedIcon bytes were the wrong format and never rendered). We add the
            #     de display straight into the application's SDMPackageXML DisplayInfo collection and persist
            #     it via WMI Put() - the same proven pattern this tool already uses for exit codes, and what
            #     the old MAN automator's (commented) code intended.
            try {
                $ser = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]
                $appObj = Get-CMApplication -Name $name
                $sx = $ser::DeserializeFromString($appObj.SDMPackageXML, $true)
                # Source icon = whichever existing (default) display already carries icon bytes.
                $srcIcon = $null
                foreach ($d in $sx.DisplayInfo) { if ($d.Icon -and $d.Icon.Data -and $d.Icon.Data.Length -gt 0) { $srcIcon = $d.Icon; break } }
                # Skip if a 'de' display already exists; else add one.
                $hasDe = $false; foreach ($d in $sx.DisplayInfo) { if ("$($d.Language)" -eq 'de') { $hasDe = $true; break } }
                if (-not $hasDe) {
                    $de = New-Object Microsoft.ConfigurationManagement.ApplicationManagement.AppDisplayInfo
                    $de.Language = 'de'; $de.Title = $localized; $de.Description = $desc
                    $de.Tags.Add($Fields.ProductName) | Out-Null
                    if ($srcIcon) { $de.Icon = $srcIcon }
                    $sx.DisplayInfo.Add($de)
                    $newXml = $ser::SerializeToString($sx, $true)
                    $wmi = Get-WmiObject -ComputerName $cfg.SiteServer -Namespace "root\SMS\site_$($cfg.SiteCode)" -Class SMS_ApplicationLatest -Filter "LocalizedDisplayName like '%$name%'"
                    $cur = [wmi]$wmi.__PATH
                    $cur.SDMPackageXML = $newXml
                    $cur.Put() | Out-Null
                    Write-Log "SCCM: added German (de) display, reusing the default icon ($(if($srcIcon){$srcIcon.Data.Length}else{0}) bytes)."
                } else { Write-Log "SCCM: German (de) display already present." }
                # Read back so the log says DEFINITIVELY whether the de icon persisted.
                $vx = $ser::DeserializeFromString((Get-CMApplication -Name $name).SDMPackageXML, $true)
                $deV = $null; foreach ($d in $vx.DisplayInfo) { if ("$($d.Language)" -eq 'de') { $deV = $d; break } }
                $deBytes = if ($deV -and $deV.Icon -and $deV.Icon.Data) { $deV.Icon.Data.Length } else { 0 }
                Write-Log "SCCM: de display persisted (icon bytes stored = $deBytes)."
            } catch { Write-Log "SCCM: DE display FAILED: $($_.Exception.Message)" Warning }
            Move-CMObject -FolderPath $cfg.AppFolder -InputObject (Get-CMApplication -Name $name) -ErrorAction SilentlyContinue | Out-Null

            # 2. Detection clauses: branding key (MANDATORY) + the chosen 2nd clause.
            $brand = New-CMDetectionClauseRegistryKeyValue -Hive LocalMachine -KeyName $Fields.BrandingKey -ValueName 'Name' -Existence -PropertyType String -Is64Bit
            $extra = New-SccmUninstallClause -Fields $Fields

            # 3. Script deployment type.
            Set-PbProgress -Percent 60 -Status 'Adding the deployment type + detection...'
            Write-Log "SCCM: Add-CMScriptDeploymentType"
            $dt = Add-CMScriptDeploymentType -AddDetectionClause $brand -ApplicationName $name -DeploymentTypeName $name `
                    -AddLanguage 'en-US','de-DE' -ContentLocation $Fields.ContentPath `
                    -InstallCommand $Fields.InstallCmd -RepairCommand $Fields.RepairCmd -UninstallCommand $Fields.UninstallCmd `
                    -InstallationBehaviorType InstallForSystem -UserInteractionMode Normal -LogonRequirementType WhereOrNotUserLoggedOn `
                    -MaximumRuntimeMins $cfg.MaxRuntimeMins -EstimatedRuntimeMins $cfg.EstRuntimeMins -ErrorAction Stop
            if (-not $dt.CI_UniqueID) { throw 'Add-CMScriptDeploymentType failed.' }
            Set-CMScriptDeploymentType -ApplicationName $name -DeploymentTypeName $name -RequireUserInteraction $AllowUserInteraction -ErrorAction SilentlyContinue | Out-Null
            if ($extra) { Set-CMScriptDeploymentType -ApplicationName $name -DeploymentTypeName $name -AddDetectionClause $extra -ErrorAction SilentlyContinue | Out-Null }

            # 3b. Exit code 60012 (deferred -> FastRetry) via SDMPackageXML. Non-fatal.
            try {
                $ec = New-Object Microsoft.ConfigurationManagement.ApplicationManagement.ExitCode
                $ec.Code = $cfg.DeferredExitCode; $ec.Name = 'Installation deferred by user'
                $ecc = New-Object Microsoft.ConfigurationManagement.ApplicationManagement.ExitCodeClass; $ecc.value__ = 2; $ec.Class = $ecc
                $wmi = Get-WmiObject -ComputerName $cfg.SiteServer -Namespace "root\SMS\site_$($cfg.SiteCode)" -Class SMS_ApplicationLatest -Filter "LocalizedDisplayName like '%$name%'"
                $cur = [wmi]$wmi.__PATH
                $xml = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::DeserializeFromString($cur.SDMPackageXML, $true)
                $xml.DeploymentTypes[0].Installer.ExitCodes.Add($ec)
                $cur.SDMPackageXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::SerializeToString($xml, $true)
                $cur.Put() | Out-Null
            } catch { Write-Log "SCCM: exit-code 60012 add skipped: $($_.Exception.Message)" Warning }

            # 4. Distribute content.
            if ($Distribute) {
                Set-PbProgress -Percent 75 -Status 'Starting content distribution...'
                Write-Log "SCCM: Start-CMContentDistribution -> $($cfg.DPGroup)"
                Start-CMContentDistribution -ApplicationName $name -DistributionPointGroupName $cfg.DPGroup -ErrorAction Stop | Out-Null
                # MONITOR distribution to completion (so testing never starts on half-distributed content).
                # Live status is shown in the tool; we wait until every targeted DP is done (success or error)
                # or DistWaitSec elapses. The DP byte-transfer itself is SCCM's (server-side) - we just watch it.
                $pkgId = (Get-CMApplication -Name $name).PackageID
                $deadline = (Get-Date).AddSeconds([int]$cfg.DistWaitSec)
                $tgt=0; $ok=0; $err=0; $prog=0
                do {
                    Start-Sleep -Seconds 8
                    $st = Get-CMDistributionStatus -Id $pkgId -ErrorAction SilentlyContinue
                    $tgt=[int]$st.Targeted; $ok=[int]$st.NumberSuccess; $err=[int]$st.NumberErrors; $prog=[int]$st.NumberInProgress
                    $pct = if ($tgt -gt 0) { [int](100*($ok+$err)/$tgt) } else { 0 }
                    Set-PbProgress -Percent ([int](75 + 0.13*$pct)) -Status ("Distributing to DPs: $ok/$tgt done$(if($prog){" ($prog in progress)"})$(if($err){" - $err error(s)"})")
                    if ($tgt -gt 0 -and ($ok + $err) -ge $tgt) { break }
                } while ((Get-Date) -lt $deadline)
                if ($tgt -gt 0 -and ($ok + $err) -lt $tgt) { Write-Log "SCCM: distribution still running after $($cfg.DistWaitSec)s ($ok/$tgt done) - check Monitoring > Content Status." Warning }
                elseif ($err -gt 0) { Write-Log "SCCM: distribution finished with $err DP error(s) of $tgt - check Content Status." Warning }
                else { Write-Log "SCCM: content distributed to all $tgt DP(s)." Success }
            }

            # 5. Collections + deployments.
            if ($Collections) {
                Set-PbProgress -Percent 90 -Status 'Creating collections + deployments...'
                $sched1 = New-CMSchedule -Start (Get-RandomStartTime) -Nonrecurring
                New-CMDeviceCollection -Name $instColl -LimitingCollectionName $cfg.LimitingCollection -RefreshSchedule $sched1 -Comment "Install | RFC_$RfcComment" -ErrorAction Stop | Out-Null
                $instCollCreated = $true
                $sched2 = New-CMSchedule -Start (Get-RandomStartTime) -Nonrecurring
                New-CMDeviceCollection -Name $uninstColl -LimitingCollectionName $cfg.LimitingCollection -RefreshSchedule $sched2 -Comment "Uninstall | RFC_$RfcComment" -ErrorAction Stop | Out-Null
                $uninstCollCreated = $true
                Move-CMObject -FolderPath $cfg.CollectionFolder -InputObject (Get-CMDeviceCollection -Name $instColl)   -ErrorAction SilentlyContinue | Out-Null
                Move-CMObject -FolderPath $cfg.CollectionFolder -InputObject (Get-CMDeviceCollection -Name $uninstColl) -ErrorAction SilentlyContinue | Out-Null
                if ($Deploy) {
                    New-CMApplicationDeployment -Name $name -CollectionName $instColl   -DeployAction Install   -DeployPurpose Required -TimeBaseOn Utc -UserNotification DisplaySoftwareCenterOnly -AllowRepairApp $true -ErrorAction Stop | Out-Null
                    New-CMApplicationDeployment -Name $name -CollectionName $uninstColl -DeployAction Uninstall -DeployPurpose Required -TimeBaseOn Utc -UserNotification DisplaySoftwareCenterOnly -ErrorAction Stop | Out-Null
                }
            }
            $app = Get-CMApplication -Name $name
            $pkgId = "$($app.PackageID)"; $ciId = "$($app.CI_UniqueID)"
            Set-PbProgress -Percent 100 -Status 'Done.'
            Write-Log "SCCM OK: '$name'  PackageID=$pkgId  CI_UniqueID=$ciId" Success
            return @{ Ok=$true; AppId=$pkgId; CIUniqueID=$ciId
                      Message="SCCM '$name' created$(if($Distribute){' + distributed'})$(if($Collections){' + collections'})$(if($Deploy){' + deployed'}).  PackageID: $pkgId   CI: $ciId" }
        } catch {
            $err = $_.Exception.Message
            # ROLL BACK what we made so nothing has to be deleted by hand in the console.
            $did = ($appCreated -or $instCollCreated -or $uninstCollCreated)
            try { if ($instCollCreated)   { Remove-CMDeviceCollection -Name $instColl   -Force -ErrorAction SilentlyContinue } } catch {}
            try { if ($uninstCollCreated) { Remove-CMDeviceCollection -Name $uninstColl -Force -ErrorAction SilentlyContinue } } catch {}
            try { if ($appCreated)        { Remove-CMApplication -Name $name -Force -ErrorAction SilentlyContinue } } catch {}  # also removes DT, deployments, content
            if ($did) { Write-Log "SCCM: rolled back partial creation of '$name'." Warning }
            return @{ Ok=$false; Message="SCCM create failed$(if($did){' (rolled back)'}): $err" }
        } finally { Pop-Location }
    } catch {
        return @{ Ok=$false; Message="SCCM create failed: $($_.Exception.Message)" }
    }
}

# --- Update content for an existing app. Two modes:
#     default      = recopy the package to prelive, THEN refresh/redistribute on the DPs.
#     -RefreshOnly = you already updated the prelive content yourself; DON'T copy, only refresh the DPs.
function Update-SccmContent {
    param([string]$LocalPackagePath, [Parameter(Mandatory)][string]$FullName, [string]$ToolRoot, [switch]$RefreshOnly)
    $cfg = Get-SccmConfig
    if ($RefreshOnly) {
        Set-PbProgress -Indeterminate -Status 'Refreshing existing prelive content on the DPs (no copy)...'
    } else {
        if (-not $LocalPackagePath) { return @{ Ok=$false; Message='No content source given (and refresh-only not set).' } }
        if (-not (Copy-PackageToPrelive -LocalPackagePath $LocalPackagePath -FullName $FullName)) { return @{ Ok=$false; Message='Content recopy failed.' } }
    }
    if (-not (Connect-Sccm -ToolRoot $ToolRoot)) { return @{ Ok=$false; Message=(Get-SccmConnectMessage) } }
    Push-Location "$($cfg.SiteCode):"
    try {
        $app = Get-CMApplication -Name $FullName -ErrorAction SilentlyContinue
        if (-not $app) { return @{ Ok=$false; Message="Application '$FullName' not found." } }
        Set-PbProgress -Percent 70 -Status 'Refreshing content on the DPs...'
        # If content is ALREADY on the DP group, REFRESH it (Update-CMDistributionPoint). Only call
        # Start-CMContentDistribution for first-time distribution - calling it again on already-distributed
        # content throws "No content destination was found / already distributed". That's the error you hit
        # when re-pushing without changes; refreshing is the correct, idempotent action.
        $pre = if ($RefreshOnly) { 'Existing prelive content' } else { 'Content recopied to prelive and' }
        $st = Get-CMDistributionStatus -Id "$($app.PackageID)" -ErrorAction SilentlyContinue
        $already = ($st -and ([int]$st.Targeted -gt 0))
        if ($already) {
            try { Update-CMDistributionPoint -ApplicationName $FullName -DeploymentTypeName $FullName -ErrorAction Stop | Out-Null
                  return @{ Ok=$true; Message="$pre refreshed on the DPs for '$FullName'." } }
            catch { Write-Log "SCCM: Update-CMDistributionPoint failed ($($_.Exception.Message)); trying a fresh distribution." Warning }
        }
        if ($RefreshOnly) {
            # Refresh-only but the app was never distributed -> there is nothing on the DPs to refresh.
            return @{ Ok=$false; Message="'$FullName' has no content on the DPs yet, so there is nothing to refresh. Distribute it first (run a normal Update content, or create the app)." }
        }
        Start-CMContentDistribution -ApplicationName $FullName -DistributionPointGroupName $cfg.DPGroup -ErrorAction Stop | Out-Null
        return @{ Ok=$true; Message="Content recopied to prelive and distributed to '$($cfg.DPGroup)' for '$FullName'.`nNOTE: SCCM updates the DPs in the BACKGROUND - this confirms the job was submitted, not finished. Use 'Content status' to see when the DPs actually have it." }
    } catch {
        $m = $_.Exception.Message
        if ($m -match 'already been distributed|No content destination') { return @{ Ok=$true; Message="$(if($RefreshOnly){'Refresh requested.'}else{'Content recopied to prelive.'}) DPs already have this content (nothing to re-send) for '$FullName'." } }
        return @{ Ok=$false; Message="Update content failed: $m" }
    }
    finally { Pop-Location }
}

# --- Content status: what the DPs ACTUALLY have. The instant success from Update content only means the
#     distribution job was SUBMITTED - SCCM pushes to the DPs in the background. This reads the site's
#     per-DP records (SMS_DistributionDPStatus): state + the REAL last-update time on every DP. -------------
function Get-SccmContentStatus {
    param([Parameter(Mandatory)][string]$FullName, [string]$ToolRoot)
    $cfg = Get-SccmConfig
    Set-PbProgress -Indeterminate -Status 'Connecting to the SCCM site...'
    if (-not (Connect-Sccm -ToolRoot $ToolRoot)) { return @{ Ok=$false; Message=(Get-SccmConnectMessage) } }
    Push-Location "$($cfg.SiteCode):"
    try {
        $app = Get-CMApplication -Name $FullName -ErrorAction SilentlyContinue
        if (-not $app) { return @{ Ok=$false; Message="Application '$FullName' not found." } }
        $pkg = "$($app.PackageID)"
        Set-PbProgress -Indeterminate -Status 'Reading per-DP distribution status...'
        $rows = @()
        try {
            $rows = @(Get-WmiObject -ComputerName $cfg.SiteServer -Namespace "root\sms\site_$($cfg.SiteCode)" `
                        -Class SMS_DistributionDPStatus -Filter "PackageID='$pkg'" -ErrorAction Stop)
        } catch { return @{ Ok=$false; Message="Could not read DP status from $($cfg.SiteServer): $($_.Exception.Message)" } }
        if (-not $rows.Count) { return @{ Ok=$false; Message="No distribution records for '$FullName' (PackageID $pkg) - the content has not been distributed yet." } }
        $lines = @(); $ok = 0; $running = 0; $bad = 0; $latest = $null
        foreach ($r in $rows) {
            $st = switch ([int]$r.MessageState) { 1 {'OK'} 2 {'IN PROGRESS'} 3 {'UNKNOWN'} 4 {'ERROR'} default {"state $($r.MessageState)"} }
            if ($st -eq 'OK') { $ok++ } elseif ($st -eq 'IN PROGRESS') { $running++ } else { $bad++ }
            $t = $null; try { if ($r.LastUpdateDate) { $t = [Management.ManagementDateTimeConverter]::ToDateTime($r.LastUpdateDate) } } catch {}
            if ($t -and (-not $latest -or $t -gt $latest)) { $latest = $t }
            $lines += ("  {0,-30} {1,-12} {2}" -f "$($r.Name)".Split('.')[0], $st, $(if ($t) { $t.ToString('yyyy-MM-dd HH:mm') } else { '-' }))
        }
        $note = if ($running) { "Distribution still RUNNING on $running DP(s) - re-check in a few minutes." }
                elseif ($bad)  { "$bad DP(s) report a problem - see Monitoring > Distribution Status in the console." }
                else           { "All DPs are up to date." }
        $when = if ($latest) { $latest.ToString('yyyy-MM-dd HH:mm') } else { 'unknown' }
        return @{ Ok=$true; Message="Content status for '$FullName' (PackageID $pkg): $ok OK, $running in progress, $bad problem(s) of $($rows.Count) DP(s).`nNewest DP update: $when. $note`n$($lines -join "`n")" }
    } finally { Pop-Location }
}

# --- Delete an app we created: deployments -> collections -> application (content/DTs go with it). ---
function Remove-SccmApplication {
    param([Parameter(Mandatory)][string]$FullName, [string]$ToolRoot)
    $cfg = Get-SccmConfig
    Set-PbProgress -Indeterminate -Status 'Connecting to the SCCM site...'
    if (-not (Connect-Sccm -ToolRoot $ToolRoot)) { return @{ Ok=$false; Message=(Get-SccmConnectMessage) } }
    Push-Location "$($cfg.SiteCode):"
    try {
        $name = $FullName
        if (-not (Get-CMApplication -Name $name -ErrorAction SilentlyContinue)) { return @{ Ok=$false; Message="Application '$name' not found - nothing to delete." } }
        $instColl = "$name-INSTALL (TEST)"; $uninstColl = "$name-UNINSTALL (TEST)"
        # 1. Remove deployments from both collections (so the collections can be deleted).
        Set-PbProgress -Percent 25 -Status 'Removing deployments...'
        foreach ($c in @($instColl, $uninstColl)) {
            try { Remove-CMApplicationDeployment -Name $name -CollectionName $c -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
        # 2. Remove the INSTALL/UNINSTALL (TEST) collections we created.
        Set-PbProgress -Percent 55 -Status 'Removing collections...'
        foreach ($c in @($instColl, $uninstColl)) {
            try { if (Get-CMDeviceCollection -Name $c -ErrorAction SilentlyContinue) { Remove-CMDeviceCollection -Name $c -Force -ErrorAction SilentlyContinue } } catch {}
        }
        # 3. Remove the application itself (this also removes its deployment types + content).
        Set-PbProgress -Percent 85 -Status 'Removing application...'
        Remove-CMApplication -Name $name -Force -ErrorAction Stop | Out-Null
        Set-PbProgress -Percent 100 -Status 'Done.'
        Write-Log "SCCM: deleted application '$name' (+ deployments + collections)." Success
        return @{ Ok=$true; Message="Deleted '$name' - application, deployment types, deployments, and the INSTALL/UNINSTALL (TEST) collections." }
    } catch { return @{ Ok=$false; Message="Delete failed: $($_.Exception.Message)" } }
    finally { Pop-Location }
}

# --- TESTING: add machine(s) to the INSTALL or UNINSTALL (TEST) collection (direct membership). ---
function Add-SccmTestMachine {
    param([Parameter(Mandatory)][string]$FullName, [ValidateSet('Install','Uninstall')][string]$Action='Install',
          [Parameter(Mandatory)][string[]]$Machines, [string]$ToolRoot)
    $cfg = Get-SccmConfig
    Set-PbProgress -Indeterminate -Status 'Connecting to the SCCM site...'
    if (-not (Connect-Sccm -ToolRoot $ToolRoot)) { return @{ Ok=$false; Message=(Get-SccmConnectMessage) } }
    Push-Location "$($cfg.SiteCode):"
    try {
        $coll = if ($Action -eq 'Install') { "$FullName-INSTALL (TEST)" } else { "$FullName-UNINSTALL (TEST)" }
        if (-not (Get-CMDeviceCollection -Name $coll -ErrorAction SilentlyContinue)) { return @{ Ok=$false; Message="Collection '$coll' not found - create the app first." } }
        $added = 0; $miss = @()
        foreach ($m in $Machines) {
            $mn = "$m".Trim(); if (-not $mn) { continue }
            $dev = Get-CMDevice -Name $mn -ErrorAction SilentlyContinue
            if ($dev -and $dev.ResourceID) {
                Add-CMDeviceCollectionDirectMembershipRule -CollectionName $coll -ResourceId $dev.ResourceID -ErrorAction SilentlyContinue | Out-Null
                Write-Log "SCCM: added '$mn' to '$coll'."; $added++
            } else { $miss += $mn; Write-Log "SCCM: device '$mn' not found in SCCM." Warning }
        }
        return @{ Ok=($added -gt 0); Message="Added $added machine(s) to '$coll'.$(if($miss){' Not found: '+($miss -join ', ')})" }
    } catch { return @{ Ok=$false; Message="Add member failed: $($_.Exception.Message)" } }
    finally { Pop-Location }
}

# --- TESTING: trigger client policy cycles on machine(s) (WMI to the client; no site connection). ---
# WMI calls with -ComputerName <SELF> route through DCOM loopback and frequently FAIL (token/UAC/RPC-to-self) even
# though local WMI works fine - that's why "run machine policy" etc. on the machine you're SITTING on can fail. So
# for the LOCAL machine we OMIT -ComputerName (hit WMI locally). Returns a splat: @{} for local, @{ComputerName=m} else.
function Get-PBMachineSplat {
    param([string]$Machine)
    $m = "$Machine".Trim()
    $short = $m.Split('.')[0]
    $isLocal = (-not $m) -or (@('.', 'localhost', '127.0.0.1', '::1') -contains $m) -or ($short -ieq "$env:COMPUTERNAME")
    if ($isLocal) { return @{} } else { return @{ ComputerName = $m } }
}

# Path to a client-side location (logs) on a target machine. LOCAL machine -> the DIRECT local path (C:\Windows\CCM\Logs,
# C:\ProgramData\VWG\Logs), which needs NO admin share and NO elevation; only a REMOTE machine uses the \\host\c$\...
# admin share (which does require admin ON that remote). So pulling logs from the box you're sitting on never needs admin.
function Get-PBClientPath {
    param([string]$Machine, [string]$ShareRel)   # e.g. 'c$\Windows\CCM\Logs' or 'c$\ProgramData\VWG\Logs'
    if ((Get-PBMachineSplat $Machine).Count -eq 0) {
        if ($ShareRel -match '^([A-Za-z])\$\\(.*)$') { return ($Matches[1] + ':\' + $Matches[2]) }   # c$\X -> C:\X
        return $ShareRel
    }
    return "\\$($Machine.Split('.')[0])\$ShareRel"
}

# Trigger the LOCAL client's policy cycles via the ConfigMgr Control Panel applet COM object (CPApplet.CPAppletMgr) -
# the SAME mechanism as the "Configuration Manager" control-panel Actions tab. Crucially this works for the INTERACTIVE
# USER WITHOUT elevation (unlike direct WMI root\ccm TriggerSchedule, which UAC-filters to admin). Returns the count of
# actions triggered, or -1 when the applet isn't usable (client not installed / COM not registered) so the caller can
# fall back to WMI. Matches Machine Policy (retrieval+evaluation) + Application Deployment Evaluation by name.
function Invoke-CmLocalClientActions {
    $cp = $null
    try { $cp = New-Object -ComObject 'CPApplet.CPAppletMgr' -ErrorAction Stop } catch { return -1 }
    try {
        $n = 0
        foreach ($a in @($cp.GetClientActions())) {
            if ("$($a.Name)" -match '(?i)machine policy|application deployment|app deployment') {
                try { [void]$a.PerformAction(); $n++ } catch { Write-Log "SCCM: local action '$($a.Name)' failed: $($_.Exception.Message)" Warning }
            }
        }
        return $n
    } catch { return -1 }
    finally { if ($cp) { try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($cp) } catch {} } }
}

function Invoke-SccmMachinePolicy {
    param([Parameter(Mandatory)][string[]]$Machines)
    # For REMOTE machines only - WMI TriggerSchedule needs rights ON the remote client.
    $cycles = @{ 'Machine Policy Retrieval'='{00000000-0000-0000-0000-000000000021}'
                 'Machine Policy Evaluation'='{00000000-0000-0000-0000-000000000022}'
                 'App Deployment Evaluation'='{00000000-0000-0000-0000-000000000121}' }
    $hit = 0
    foreach ($m in $Machines) {
        $mn = "$m".Trim(); if (-not $mn) { continue }
        $mSplat = Get-PBMachineSplat $mn
        $isLocal = ($mSplat.Count -eq 0)
        Set-PbProgress -Indeterminate -Status "Triggering policy on $mn$(if ($isLocal) { ' (local)' })..."
        $ok = $false
        if ($isLocal) {
            # LOCAL machine (where Package Builder runs): use the control-panel applet path - NO admin/elevation required.
            $n = Invoke-CmLocalClientActions
            if ($n -gt 0) { $ok = $true; Write-Log "SCCM: triggered $n local client action(s) via the Configuration Manager applet on $mn (no elevation needed)." Success }
            elseif ($n -eq 0) { Write-Log "SCCM: the Configuration Manager applet returned no matching actions on $mn - is the SCCM client installed + running?" Warning }
        }
        if (-not $ok) {
            # REMOTE (or the local applet was unavailable): direct WMI TriggerSchedule.
            $wmiOk = $true; $denied = $false
            foreach ($c in $cycles.GetEnumerator()) {
                try { Invoke-WmiMethod @mSplat -Namespace 'root\ccm' -Class 'SMS_CLIENT' -Name 'TriggerSchedule' -ArgumentList $c.Value -ErrorAction Stop | Out-Null }
                catch { $wmiOk = $false; if ("$($_.Exception.Message)" -match '(?i)denied|verweigert|0x80070005|access is denied') { $denied = $true }; Write-Log "SCCM: '$($c.Key)' on $mn failed: $($_.Exception.Message)" Warning }
            }
            if ($wmiOk) { $ok = $true; Write-Log "SCCM: policy cycles triggered on $mn." Success }
            elseif ($denied) { Write-Log "SCCM: policy trigger denied on $mn$(if ($isLocal) { ' - install/start the SCCM client (Configuration Manager applet), or run as admin as a last resort.' } else { ' - you need rights on that remote client.' })" Warning }
        }
        if ($ok) { $hit++ }
    }
    return @{ Ok=($hit -gt 0); Message="Triggered policy on $hit/$($Machines.Count) machine(s)." }
}

# --- TROUBLESHOOT: force a restart on a target machine (use when a reboot is pending). The GUI confirms
#     first (outward-facing / disruptive). Needs admin rights on the machine + RPC/WMI reachability. ----
function Restart-SccmMachine {
    param([Parameter(Mandatory)][string]$Machine)
    $m = "$Machine".Trim().Split('.')[0]
    if (-not $m) { return @{ Ok=$false; Message='Enter a machine name.' } }
    $mSplat = Get-PBMachineSplat $m   # local -> omit -ComputerName (restarts THIS machine)
    Set-PbProgress -Indeterminate -Status "Sending restart to $m..."
    try {
        Restart-Computer @mSplat -Force -ErrorAction Stop
        Write-Log "SCCM: restart command sent to $m." Warning
        return @{ Ok=$true; Message="Restart sent to $m. It is rebooting now - wait a few minutes, then Check install state again; the pending reboot should clear." }
    } catch {
        return @{ Ok=$false; Message="Could not restart ${m}: $($_.Exception.Message). Needs admin rights on the machine and it must be reachable (RPC/WMI)." }
    }
}

# --- TESTING: remove machine(s) from the INSTALL or UNINSTALL (TEST) collection (separate from Add). ---
function Remove-SccmTestMachine {
    param([Parameter(Mandatory)][string]$FullName, [ValidateSet('Install','Uninstall')][string]$Action='Install',
          [Parameter(Mandatory)][string[]]$Machines, [string]$ToolRoot)
    $cfg = Get-SccmConfig
    Set-PbProgress -Indeterminate -Status 'Connecting to the SCCM site...'
    if (-not (Connect-Sccm -ToolRoot $ToolRoot)) { return @{ Ok=$false; Message=(Get-SccmConnectMessage) } }
    Push-Location "$($cfg.SiteCode):"
    try {
        $coll = if ($Action -eq 'Install') { "$FullName-INSTALL (TEST)" } else { "$FullName-UNINSTALL (TEST)" }
        if (-not (Get-CMDeviceCollection -Name $coll -ErrorAction SilentlyContinue)) { return @{ Ok=$false; Message="Collection '$coll' not found." } }
        $removed = 0; $miss = @()
        foreach ($m in $Machines) {
            $mn = "$m".Trim(); if (-not $mn) { continue }
            $dev = Get-CMDevice -Name $mn -ErrorAction SilentlyContinue
            if ($dev -and $dev.ResourceID) {
                Remove-CMDeviceCollectionDirectMembershipRule -CollectionName $coll -ResourceId $dev.ResourceID -Force -ErrorAction SilentlyContinue | Out-Null
                Write-Log "SCCM: removed '$mn' from '$coll'."; $removed++
            } else { $miss += $mn }
        }
        return @{ Ok=$true; Message="Removed $removed machine(s) from '$coll'.$(if($miss){' Not found: '+($miss -join ', ')})" }
    } catch { return @{ Ok=$false; Message="Remove member failed: $($_.Exception.Message)" } }
    finally { Pop-Location }
}

# --- TROUBLESHOOT: list the machines currently in the INSTALL or UNINSTALL (TEST) collection. ---
function Get-SccmCollectionMembers {
    param([Parameter(Mandatory)][string]$FullName, [ValidateSet('Install','Uninstall')][string]$Action='Install', [string]$ToolRoot)
    $cfg = Get-SccmConfig
    Set-PbProgress -Indeterminate -Status 'Reading collection members...'
    if (-not (Connect-Sccm -ToolRoot $ToolRoot)) { return @{ Ok=$false; Message=(Get-SccmConnectMessage) } }
    Push-Location "$($cfg.SiteCode):"
    try {
        $coll = if ($Action -eq 'Install') { "$FullName-INSTALL (TEST)" } else { "$FullName-UNINSTALL (TEST)" }
        if (-not (Get-CMDeviceCollection -Name $coll -ErrorAction SilentlyContinue)) { return @{ Ok=$false; Message="Collection '$coll' not found." } }
        # Evaluated members (preferred); fall back to the direct membership rules we added.
        $names = @(Get-CMCollectionMember -CollectionName $coll -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)" })
        if (-not $names) { $names = @(Get-CMDeviceCollectionDirectMembershipRule -CollectionName $coll -ErrorAction SilentlyContinue | ForEach-Object { "$($_.RuleName)" }) }
        $names = @($names | Where-Object { $_ } | Sort-Object -Unique)
        return @{ Ok=$true; Members=$names; CollAction=$Action; Message="'$coll' has $($names.Count) member(s)." }
    } catch { return @{ Ok=$false; Message="Read members failed: $($_.Exception.Message)" } }
    finally { Pop-Location }
}

# --- TROUBLESHOOT: is the app installed on a machine? App-id first (SCCM client CCM_Application),
#     then branding-key fallback (HKLM\SOFTWARE\VWG\CM\<pkg> via WMI). Verdict vs the collection intent. ----
# Turn CCM_Application.EvaluationState into a CLEAR English phrase. InstallState alone is misleading -
# it reads "NotInstalled" for the WHOLE time an install is running (until post-install detection passes),
# so we describe the actual PHASE instead. Returns @{Text; InProgress; Reboot; Error} or $null (unknown).
function Get-SccmEvalPhrase {
    param([int]$State, [int]$Percent, [string]$Action)
    $verb   = if ($Action -eq 'Uninstall') { 'Uninstalling' } else { 'Installing' }
    $done   = if ($Action -eq 'Uninstall') { 'Uninstalled'  } else { 'Installed'  }
    $noun   = if ($Action -eq 'Uninstall') { 'uninstall'    } else { 'install'    }
    $pct    = if ($Percent -gt 0 -and $Percent -lt 100) { " ($Percent% done)" } else { '' }
    switch ($State) {
        0  { @{ Text='Idle (no action running)';                         InProgress=$false } }
        1  { @{ Text='Available in Software Center (not started yet)';   InProgress=$false } }
        2  { @{ Text="$verb - queued, about to start$pct";              InProgress=$true  } }
        3  { @{ Text="$verb - checking the machine$pct";                InProgress=$true  } }
        4  { @{ Text="$verb - preparing content$pct";                   InProgress=$true  } }
        5  { @{ Text="$verb - downloading content$pct";                 InProgress=$true  } }
        6  { @{ Text="$verb - waiting to start$pct";                    InProgress=$true  } }
        7  { @{ Text="$verb NOW$pct";                                    InProgress=$true  } }
        8  { @{ Text="$done - waiting for a reboot to finish";          InProgress=$false; Reboot=$true } }
        9  { @{ Text="$done - waiting for a (hard) reboot to finish";   InProgress=$false; Reboot=$true } }
        10 { @{ Text="$done - waiting for reboot";                      InProgress=$false; Reboot=$true } }
        11 { @{ Text="$verb - verifying it installed$pct";             InProgress=$true  } }
        12 { @{ Text="$done (complete)";                                 InProgress=$false } }
        13 { @{ Text="FAILED - the last $noun attempt errored"; InProgress=$false; Error=$true } }
        14 { @{ Text="$verb - waiting for a maintenance window";        InProgress=$true  } }
        15 { @{ Text="$verb - waiting for a user to log on";            InProgress=$true  } }
        16 { @{ Text="$verb - waiting for the user to log off";         InProgress=$true  } }
        17 { @{ Text="$verb - waiting for user logon";                  InProgress=$true  } }
        18 { @{ Text="$verb - waiting for the user to reconnect";       InProgress=$true  } }
        19 { @{ Text="$verb - waiting for user data";                   InProgress=$true  } }
        20 { @{ Text="$verb - waiting until no user is logged on";      InProgress=$true  } }
        21 { @{ Text="$verb - will retry shortly";                      InProgress=$true  } }
        22 { @{ Text="$verb - waiting for presentation mode to end";    InProgress=$true  } }
        23 { @{ Text="$verb - waiting for orchestration";               InProgress=$true  } }
        default { $null }
    }
}

function Get-SccmInstallState {
    param([Parameter(Mandatory)][string]$Machine, [Parameter(Mandatory)][string]$FullName, [string]$ExpectedAction)
    $m = "$Machine".Trim().Split('.')[0]
    if (-not $m) { return @{ Ok=$false; Message='Enter a machine name.' } }
    $mSplat = Get-PBMachineSplat $m   # local -> omit -ComputerName (DCOM-to-self fails)
    Set-PbProgress -Indeterminate -Status "Checking install state on $m..."
    $state = $null; $source = $null
    $prod = if ($FullName -match '_') { ($FullName -split '_')[1] } else { $FullName }
    # 1) App-id: the SCCM client's application catalog. SMART state, not just Installed/NotInstalled:
    #    EvaluationState tells whether the install/uninstall is RUNNING RIGHT NOW (with PercentComplete)
    #    or queued; DetermineIfRebootPending tells whether Software Center shows "restart required".
    $errExpl = $null; $inProgress = $false; $appErrCode = $null; $isError = $false; $pct = 0
    try {
        $apps = Get-WmiObject @mSplat -Namespace 'root\ccm\clientsdk' -Class CCM_Application -ErrorAction Stop
        $hit = $apps | Where-Object { "$($_.FullName)" -eq $FullName -or "$($_.Name)" -eq $FullName -or ($prod -and "$($_.Name)" -like "*$prod*") } | Select-Object -First 1
        if ($hit) {
            $rawInstall = "$($hit.InstallState)"   # 'Installed' / 'NotInstalled' / 'Unknown'
            $source = 'SCCM client (CCM_Application)'
            $es  = -1; try { $es = [int]$hit.EvaluationState } catch {}
            try { $pct = [int]$hit.PercentComplete } catch {}
            # Describe the actual PHASE in plain English (handles "installing" so we never show NotInstalled
            # while an install is running). If the phase is unknown/idle, fall back to the InstallState word.
            $phrase = Get-SccmEvalPhrase -State $es -Percent $pct -Action $ExpectedAction
            if ($pct -gt 0 -and $pct -lt 100 -and -not ($phrase -and $phrase.InProgress)) {
                # percent says it's mid-run even if the eval state didn't map to an active phase
                $verb = if ($ExpectedAction -eq 'Uninstall') { 'Uninstalling' } else { 'Installing' }
                $phrase = @{ Text = "$verb NOW ($pct% done)"; InProgress = $true }
            }
            if ($phrase -and $phrase.Text -and $es -notin 0,1) {
                $state = $phrase.Text
                $inProgress = [bool]$phrase.InProgress
                $isError    = [bool]$phrase.Error
            } else {
                # idle / available / unknown -> plain installed-or-not, in clear words
                $state = if ($rawInstall -match '(?i)^installed$') { 'Installed' }
                         elseif ($rawInstall -match '(?i)notinstalled') { 'Not installed' }
                         else { $rawInstall }
            }
            # SCCM-level error code on the app object (may be 0 even when the installer exit code was not).
            foreach ($p in 'ErrorCode','ReturnCode','LastInstallError') {
                if ($hit.PSObject.Properties[$p] -and "$($hit.$p)".Trim() -and "$($hit.$p)" -ne '0') { $appErrCode = $hit.$p; break }
            }
        }
    } catch {}
    # 1b) Reboot pending = what Software Center shows as "Restart required" (client-wide check). Also fetch
    #     the machine's LAST BOOT TIME so we can confirm whether a reboot actually happened: if it booted
    #     recently but a reboot is STILL flagged, the pending reboot is from another source (not our install).
    $rebootPending = $false; $bootNote = ''
    try {
        $rb = Invoke-WmiMethod @mSplat -Namespace 'root\ccm\clientsdk' -Class CCM_ClientUtilities -Name DetermineIfRebootPending -ErrorAction Stop
        $rebootPending = ([bool]$rb.RebootPending -or [bool]$rb.IsHardRebootPending)
    } catch {}
    if ($rebootPending) {
        try {
            $os = Get-WmiObject @mSplat -Class Win32_OperatingSystem -ErrorAction Stop
            $boot = $os.ConvertToDateTime($os.LastBootUpTime)
            $mins = [int]((Get-Date) - $boot).TotalMinutes
            $ago  = if ($mins -lt 60) { "$mins min ago" } elseif ($mins -lt 1440) { '{0:N1} h ago' -f ($mins/60) } else { '{0:N1} days ago' -f ($mins/1440) }
            $bootNote = "  (last booted $($boot.ToString('yyyy-MM-dd HH:mm')), $ago"
            if ($mins -lt 15) { $bootNote += " - it rebooted recently yet a reboot is STILL flagged, so this is a SEPARATE pending reboot (Windows Update / pending file rename); another reboot usually clears it)" }
            else { $bootNote += " - reboot the machine to clear it)" }
        } catch {}
    }
    # 2) Fallback: branding key via WMI StdRegProv (works even when Remote Registry service is off).
    if (-not $state) {
        try {
            $r = Invoke-WmiMethod @mSplat -Namespace 'root\default' -Class StdRegProv -Name GetStringValue `
                    -ArgumentList ([uint32]2147483650), "SOFTWARE\VWG\CM\$FullName", 'Name' -ErrorAction Stop
            $state = if ($r.ReturnValue -eq 0 -and $r.sValue) { 'Installed' } else { 'Not installed' }
            $source = 'branding key (package name)'
        } catch { return @{ Ok=$false; Message="Could not reach $m to check state ($($_.Exception.Message)). Is it online / WMI reachable?" } }
    }
    # "installed" = the success word and NOT a not-installed / in-progress / failed phrase.
    $installed = ($state -match '(?i)installed' -and $state -notmatch '(?i)not installed|notinstalled|installing|failed')
    # 3) LIVE TRUTH from AppEnforce.log. CCM_Application's WMI data is CACHED and lags reality - it can read
    #    "complete" while an install is still running (and keep a stale exit code). AppEnforce.log is
    #    append-only and real-time: a "Starting enforcement" with no matching "completed" after it = running
    #    NOW; otherwise the last "completed ... exit code N" is the real result. The log WINS over WMI.
    $enf = Get-SccmEnforceStatus -Machine $m -FullName $FullName
    if ($enf.InProgress) {
        $verb = if (($enf.Action -eq 'Uninstall') -or ($ExpectedAction -eq 'Uninstall')) { 'Uninstalling' } else { 'Installing' }
        $pctTxt = if ($pct -gt 0 -and $pct -lt 100) { " ($pct% done)" } else { '' }
        $state = "$verb NOW - in progress$pctTxt"; $source = 'AppEnforce.log (live)'
        $inProgress = $true; $isError = $false; $installed = $false
    }
    # RECONCILE the WMI verdict with the REAL exit code so the header never contradicts the explanation:
    # 3010/1641 mean the install SUCCEEDED and only a reboot is outstanding - but the client often flags the
    # app Error/NotInstalled meanwhile, because post-install detection cannot pass until after the reboot.
    # The concrete exit code wins over the client's interim verdict.
    $errExpl = $null
    if (-not $inProgress) {
        $hexCode = if ($enf.Code) { ConvertTo-Hex32 "$($enf.Code)" } else { $null }
        $appHex  = if ($appErrCode) { ConvertTo-Hex32 "$appErrCode" } else { $null }
        $word = if ($ExpectedAction -eq 'Uninstall') { 'Uninstall' } else { 'Install' }
        # DETECTION FAILED AFTER INSTALL (0x87D00324) - installer ran OK (exit 0) but the app was NOT detected,
        # i.e. the DETECTION RULE does not match what was installed. Catch this BEFORE the "exit 0 = success"
        # branch, otherwise we'd wrongly call a detection mismatch a success. Log signal wins; app code backs it.
        if ($enf.DetectionFailed -or $appHex -eq '0x87D00324') {
            $state = "$word ran OK but DETECTION FAILED - the app is not detected, so the DETECTION RULE does not match what was installed"
            if ($enf.DetectionFailed) { $source = 'AppEnforce.log (live)' }
            $installed = $false; $isError = $true
            $errExpl = Get-SccmErrorExplanation -Code '0x87D00324'
        } elseif ($hexCode -in @('0x00000BC2','0x00000669')) {
            # 3010/1641 was a SUCCESS-with-reboot. That exit code stays in AppEnforce.log forever, so only say
            # "needs a reboot" while a reboot is ACTUALLY pending. Once the machine has rebooted (no pending
            # reboot), the install is DONE - don't keep telling the user to reboot.
            $dec = if ($hexCode -eq '0x00000BC2') { '3010' } else { '1641' }
            if ($rebootPending) {
                $state = "$word finished OK - just needs a REBOOT to complete (exit $dec, not a failure)"
            } else {
                $state = "$word complete (exit $dec was a success-with-reboot; the reboot has already been done)"
            }
            $source = 'AppEnforce.log (live)'
            $installed = ($ExpectedAction -ne 'Uninstall'); $isError = $false
        } elseif ($isError -and $hexCode -eq '0x00000000') {
            # client says error but the last real enforcement succeeded -> stale client state; trust the log.
            $state = "$word finished OK (exit 0 - the client state is still catching up)"
            $source = 'AppEnforce.log (live)'
            $installed = ($ExpectedAction -ne 'Uninstall'); $isError = $false
        }
    }
    # THE REAL FAILURE REASON: the installer/MSI exit code (1, 1603, ...) is the last completed code in the
    # log. Only show it when NOT installed and NOT mid-run (so a successful retry doesn't show a stale code).
    # (Skip if a detection-failed explanation was already set above.)
    if (-not $errExpl -and -not $inProgress -and (-not $installed -or $isError)) {
        $codeToExplain = if ($enf.Code) { $enf.Code } elseif ($appErrCode) { $appErrCode } else { $null }
        # don't explain a success/zero code (0, 0x00000000) or success-with-reboot as a failure reason.
        if ($codeToExplain -and (ConvertTo-Hex32 "$codeToExplain") -notin @($null, '0x00000000', '0x00000BC2', '0x00000669')) {
            $errExpl = Get-SccmErrorExplanation -Code "$codeToExplain"
        }
    }
    # DETECTION-KEY-NOT-FOUND cross-check (independent of a fresh install). The package writes its OWN branding
    # marker (HKLM\SOFTWARE\VWG\CM\<name>) - if THAT is present but SCCM reports the app not installed / not
    # discovered, SCCM's DETECTION RULE is wrong (the key it checks doesn't match what's on disk). Also read
    # AppDiscovery.log (the dedicated detection log) for its verdict, to inform the user explicitly.
    $discNote = ''
    if (-not $inProgress -and -not $installed) {
        $branding = Test-SccmBrandingPresent -Machine $m -FullName $FullName
        $disc     = Get-SccmDiscoveryResult  -Machine $m -FullName $FullName
        if ($branding -eq $true) {
            # the app really IS installed (our marker is there) but SCCM does not detect it
            $state = 'Installed (package branding key is present) but SCCM does NOT detect it'
            $isError = $true
            if (-not $errExpl) { $errExpl = Get-SccmErrorExplanation -Code '0x87D00324' }
            $discNote = "`nDetection rule mismatch: the app is on the machine but SCCM's detection rule does not find it. Fix it in Modify > Update detection."
        } elseif ($disc -eq 'NotDiscovered') {
            $discNote = "`nAppDiscovery.log: SCCM's detection rule reports the app as NOT detected here. If it should be installed, the detection key/rule does not match (fix in Modify > Update detection); if it was never installed, this is expected."
        } elseif ($disc -eq 'Discovered') {
            $discNote = "`nAppDiscovery.log: SCCM's detection rule DID detect the app (the not-installed reading above may be stale - re-check)."
        }
    }
    if ($rebootPending) { $state += "  + REBOOT REQUIRED (Software Center shows restart pending)$bootNote" }
    $verdict = ''
    if ($ExpectedAction -and -not $inProgress) {
        $shouldBeInstalled = ($ExpectedAction -eq 'Install')
        $verdict = if ($installed -eq $shouldBeInstalled) { '  -> matches the '+$ExpectedAction+' collection (OK)' } else { '  -> MISMATCH vs the '+$ExpectedAction+' collection!' }
    } elseif ($inProgress) {
        $verdict = '  -> wait for it to finish, then re-check'
    }
    $msg = "$m : $state  [$source]$verdict"
    if ($errExpl) { $msg += "`nLast enforcement result -> $errExpl" }
    elseif (-not $installed -and -not $inProgress -and -not $discNote) { $msg += "`n(No exit code found in AppEnforce.log yet - use the Package logs button to read the install/MSI log directly.)" }
    if ($discNote) { $msg += $discNote }
    return @{ Ok=$true; State=$state; Message=$msg }
}

# Read AppEnforce.log on the machine and report, for THIS app, whether an enforcement is running RIGHT NOW
# and the last completed exit code. AppEnforce.log is append-only/real-time, so it beats the cached
# CCM_Application WMI state. Our deployment type is named = FullName, so we scope by that (or the app token).
# Returns @{ InProgress=$bool; Action='Install'|'Uninstall'|$null; Code=<string or $null>; DetectionFailed=$bool }.
function Get-SccmEnforceStatus {
    param([Parameter(Mandatory)][string]$Machine, [string]$FullName)
    $res = @{ InProgress = $false; Action = $null; Code = $null; DetectionFailed = $false }
    $cfg = Get-SccmConfig
    $src = Join-Path (Get-PBClientPath -Machine $Machine -ShareRel $cfg.ClientLogShare) 'AppEnforce.log'
    if (-not (Test-Path $src)) { return $res }
    $txt = $null; try { $txt = Get-Content $src -Raw -ErrorAction Stop } catch { return $res }
    if (-not $txt) { return $res }
    $prod = if ($FullName -match '_') { ($FullName -split '_')[1] } else { $FullName }
    $isOurs = {
        param($dt)
        ($FullName -and $dt -like "*$FullName*") -or ($prod -and $dt -like "*$prod*")
    }
    # "+++ Starting Install enforcement for App DT "<DTname>" ..."
    $lastStart = $null; $startAction = $null
    foreach ($mt in [regex]::Matches($txt, '(?i)Starting (Install|Uninstall) enforcement for App DT "([^"]+)"')) {
        if (& $isOurs $mt.Groups[2].Value) { $lastStart = $mt.Index; $startAction = $mt.Groups[1].Value }
    }
    # "App enforcement completed (N seconds) for App DT "<DTname>" ... Exit Code: 0xN" (hex) - capture pos + code
    $lastDone = $null; $doneCode = $null
    foreach ($mt in [regex]::Matches($txt, '(?i)App enforcement completed.*?for App DT "([^"]+)"[^\r\n]*')) {
        if (& $isOurs $mt.Groups[1].Value) {
            $lastDone = $mt.Index
            $c = [regex]::Match($mt.Value, '(?i)Exit Code:?\s*(0x[0-9A-Fa-f]+|\d+)')
            if ($c.Success) { $doneCode = $c.Groups[1].Value }
        }
    }
    if ($null -ne $lastStart -and ($null -eq $lastDone -or $lastStart -gt $lastDone)) {
        # an enforcement started with no completion after it = running now
        $res.InProgress = $true; $res.Action = $startAction
    } elseif ($null -ne $lastDone) {
        # OUR app completed. Prefer the code on the completion line; else fall back to the "Matched exit code
        # N" line for THIS enforcement (between our start and our completion - never another app's code).
        $code = $doneCode
        if (-not $code) {
            $lo = if ($null -ne $lastStart -and $lastStart -lt $lastDone) { $lastStart } else { 0 }
            foreach ($mt in [regex]::Matches($txt, '(?i)Matched exit code (\d+) to a')) {
                if ($mt.Index -gt $lo -and $mt.Index -lt $lastDone) { $code = $mt.Groups[1].Value }
            }
        }
        $res.Code = $code
        # DETECTION-FAILED-AFTER-INSTALL (the classic 0x87D00324): the installer matched a SUCCESS exit code,
        # yet within the SAME enforcement block the app is still "not discovered" AFTER that success. (A real
        # success ends "Application discovered".) Scope to this block (last start -> last completion).
        $lo2 = if ($null -ne $lastStart -and $lastStart -lt $lastDone) { $lastStart } else { 0 }
        $block = $txt.Substring($lo2, $lastDone - $lo2)
        $succ = [regex]::Match($block, '(?i)Matched exit code \d+ to a Success entry')
        if ($succ.Success) {
            $afterSuccess = $block.Substring($succ.Index)
            if ([regex]::IsMatch($afterSuccess, '(?i)not discovered|not detected|after.*successful install')) {
                $res.DetectionFailed = $true
            }
        }
    }
    # else: our app is not in the log at all -> leave InProgress/Code unset (nothing to report).
    return $res
}

# Read AppDiscovery.log (the DEDICATED detection log) and return the MOST RECENT detection verdict for THIS
# app: 'Discovered' / 'NotDiscovered' / $null. Each detection is preceded by "Performing detection of app
# deployment type <FriendlyName>(...)"; the result is "Application (not )discovered". We track the current
# DT and record the result only when it is ours. This catches a "detection key not found" even with NO recent
# install (a routine compliance check), which AppEnforce.log would not show.
function Get-SccmDiscoveryResult {
    param([Parameter(Mandatory)][string]$Machine, [string]$FullName)
    $cfg = Get-SccmConfig
    $src = Join-Path (Get-PBClientPath -Machine $Machine -ShareRel $cfg.ClientLogShare) 'AppDiscovery.log'
    if (-not (Test-Path $src)) { return $null }
    $txt = $null; try { $txt = Get-Content $src -Raw -ErrorAction Stop } catch { return $null }
    if (-not $txt) { return $null }
    $prod = if ($FullName -match '_') { ($FullName -split '_')[1] } else { $FullName }
    $cur = $false; $last = $null
    $rx = [regex]'(?i)(Performing detection of app deployment type (?<dt>.+?)\(|\[AppDT "(?<dt2>[^"]+)"|Application (?<not>not )?discovered)'
    foreach ($mt in $rx.Matches($txt)) {
        if ($mt.Groups['dt'].Success -or $mt.Groups['dt2'].Success) {
            $name = if ($mt.Groups['dt'].Success) { $mt.Groups['dt'].Value } else { $mt.Groups['dt2'].Value }
            $cur  = (($name -like "*$FullName*") -or ($prod -and $name -like "*$prod*"))
        } elseif ($mt.Value -match '(?i)discovered') {
            if ($cur) { $last = if ($mt.Groups['not'].Success) { 'NotDiscovered' } else { 'Discovered' } }
        }
    }
    return $last
}

# Is OUR package's branding marker present on the machine? HKLM\SOFTWARE\VWG\CM\<FullName>\Name. This is an
# INDEPENDENT "the app really is installed" signal: if it is present but SCCM still reports the app not
# installed / not discovered, then SCCM's DETECTION RULE is what's wrong (the "detection key not found" case).
# Returns $true / $false / $null (could not check).
function Test-SccmBrandingPresent {
    param([Parameter(Mandatory)][string]$Machine, [string]$FullName)
    try {
        $mSplat = Get-PBMachineSplat $Machine   # local -> omit -ComputerName (DCOM-to-self fails)
        $r = Invoke-WmiMethod @mSplat -Namespace 'root\default' -Class StdRegProv -Name GetStringValue `
                -ArgumentList ([uint32]2147483650), "SOFTWARE\VWG\CM\$FullName", 'Name' -ErrorAction Stop
        return ($r.ReturnValue -eq 0 -and [bool]$r.sValue)
    } catch { return $null }
}

# --- TROUBLESHOOT: list the PSADT/package logs on a machine (ProgramData\VWG\Logs) matching the
#     package's vendor/app tokens - install, uninstall, repair, MSI and EXE logs all included. The GUI
#     shows them in a picker (like the predecessor dialog) and fetches the chosen one. ----------------
function Get-SccmPsadtLogList {
    param([Parameter(Mandatory)][string]$Machine, [string]$FullName)
    $cfg = Get-SccmConfig
    $mn = "$Machine".Trim().Split('.')[0]
    if (-not $mn) { return @{ Ok=$false; Message='Enter a machine name.' } }
    Set-PbProgress -Indeterminate -Status "Listing package logs on $mn..."
    $base = Get-PBClientPath -Machine $mn -ShareRel $cfg.PsadtLogShare
    if (-not (Test-Path $base)) { return @{ Ok=$false; Message="Log path not reachable: $base ($(if($base -match '^\\\\'){'machine off / need admin on that remote?'}else{'is the app installed here yet?'}))." } }
    $vendor = ''; $app = ''
    if ($FullName -match '_') { $parts = $FullName -split '_'; $vendor = $parts[0]; $app = $parts[1] } else { $app = "$FullName" }
    $logs = @(Get-ChildItem -Path $base -Recurse -Filter *.log -ErrorAction SilentlyContinue)
    if ($app -or $vendor) {
        $logs = $logs | Where-Object {
            ($app    -and ($_.Name -like "*$app*"    -or $_.FullName -like "*$app*")) -or
            ($vendor -and ($_.Name -like "*$vendor*" -or $_.FullName -like "*$vendor*"))
        }
    }
    $logs = @($logs | Sort-Object LastWriteTime -Descending | Select-Object -First 50)
    if (-not $logs.Count) { return @{ Ok=$false; Message="No matching .log files under $base (filter: $vendor/$app). App never ran here?" } }
    $items = @($logs | ForEach-Object {
        [pscustomobject]@{
            Name       = $_.Name
            Modified   = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            SizeKB     = [math]::Round($_.Length / 1024)
            Folder     = ($_.DirectoryName -replace [regex]::Escape($base), '').TrimStart('\')
            RemotePath = $_.FullName
        }
    })
    return @{ Ok=$true; LogList=$items; Machine=$mn; Message="$($items.Count) log(s) found on $mn - pick one to open." }
}

# --- TROUBLESHOOT: copy ONE chosen remote log locally and open it in CMTrace. -----------------------
function Copy-SccmClientLogFile {
    param([Parameter(Mandatory)][string]$Machine, [Parameter(Mandatory)][string]$RemotePath)
    $mn = "$Machine".Trim().Split('.')[0]
    Set-PbProgress -Indeterminate -Status "Fetching $(Split-Path $RemotePath -Leaf) from $mn..."
    try {
        if (-not (Test-Path $RemotePath)) { return @{ Ok=$false; Message="Log no longer there: $RemotePath" } }
        $dest = Join-Path (Get-WorkPath 'Downloads') $mn
        if (-not (Test-Path $dest)) { New-Item $dest -ItemType Directory -Force | Out-Null }
        $local = Join-Path $dest (Split-Path $RemotePath -Leaf)
        Copy-Item -LiteralPath $RemotePath -Destination $local -Force -ErrorAction Stop
        Open-CMTrace -LogPath $local
        $known = try { Find-KnownLogErrors -Text ([IO.File]::ReadAllText($local)) } catch { $null }
        return @{ Ok=$true; Message="Opened $(Split-Path $RemotePath -Leaf) in CMTrace (copied to $dest).$(if($known){"`nKnown issue(s) found:`n$known"})" }
    } catch { return @{ Ok=$false; Message="Fetch log failed: $($_.Exception.Message)" } }
}

# --- Known Software Center / app-deployment error codes -> plain-English cause + fix. ---------------
$script:SccmErrorMap = @{
    '0x87D00324' = 'Installed OK but the app was NOT detected afterwards -> the DETECTION rule (branding / uninstall / version key) does not match what the installer actually wrote. Fix it in Modify > Update detection.'
    '0x87D00325' = 'Deployment is past due and will be retried at the next opportunity.'
    '0x87D00327' = 'No current or future maintenance/service window exists to run the deployment in.'
    '0x87D00329' = 'The install command returned a failure -> the package install itself failed. Check the Install/Uninstall (PSADT) log.'
    '0x87D0032D' = 'Application is not applicable -> requirement rules (OS / architecture / etc.) were not met.'
    '0x87D013BC' = 'Requirement rules not met (OS version, architecture, disk space, registry/file requirement).'
    '0x87D01106' = 'Failed to download content from the distribution point. Check distribution (Update content / Content Status).'
    '0x87D00267' = 'Content not found / not yet distributed to the DP the client uses.'
    '0x87D00269' = 'Waiting for user interaction or for a running process to close.'
    '0x87D0029E' = 'Detection rules evaluated but the app is reported as not installed.'
    # --- raw installer / process exit codes (AppEnforce.log "exit code N"; ConvertTo-Hex32 maps N->hex) ---
    '0x00000000' = 'Exit 0 - success.'
    '0x00000001' = 'Exit code 1 - GENERAL FAILURE returned by the installer or PSADT script, and SCCM did not detect the app afterwards. The deployment-type "success codes" do not include 1, so this counts as failed. Open the Package logs (install / MSI log) for the underlying cause - usually a failed prerequisite, a non-zero install step, or an explicit Exit-Script -ExitCode 1 in the PSADT script.'
    '0x00000002' = 'Exit code 2 - the installer/script returned 2 (general failure). Read the Package log for the failing step.'
    '0x00000003' = 'Exit code 3 - the installer/script returned 3 (general failure). Read the Package log for the failing step.'
    '0x00000642' = 'MSI 1602 - the installation was cancelled by the user.'
    '0x00000643' = 'MSI fatal error 1603 - the installation failed. Check the MSI / PSADT log for the real cause.'
    '0x00000645' = 'MSI 1605 - this action is only valid for products that are currently installed.'
    '0x00000652' = 'MSI 1618 - another installation is already in progress; it will retry.'
    '0x00000653' = 'MSI 1619 - the MSI package could not be opened (missing, locked or corrupt installer).'
    '0x00000654' = 'MSI 1620 - the MSI package could not be opened (invalid package).'
    '0x00000666' = 'MSI 1638 - another version of this product is already installed; remove it first or use the correct upgrade code.'
    '0x00000667' = 'MSI 1639 - invalid command-line argument passed to msiexec.'
    '0x00000669' = 'MSI 1641 - success; the installer initiated a reboot.'
    '0x0000066A' = 'MSI 1642 - unable to install the update patch (wrong base product / already patched).'
    '0x00000BC2' = 'Exit 3010 - success, but a REBOOT is required (soft reboot). Software Center shows "restart required" - this is normal for many installs.'
    '0x0000EA6C' = 'Exit 60012 - install deferred by the user; it is retried at the next window (expected, not a failure).'
    '0x80004005' = 'Unspecified failure (E_FAIL) - check the install / PSADT log for the underlying error.'
    '0x80070005' = 'Access denied (0x80070005) - the install needs rights it does not have, or a file/registry path is locked.'
}
function ConvertTo-Hex32 {
    param([string]$Code)
    $c = "$Code".Trim(); if (-not $c) { return $null }
    [int64]$v = 0
    try {
        if     ($c -match '^0x[0-9A-Fa-f]+$')   { $v = [Convert]::ToInt64($c.Substring(2),16) }
        elseif ($c -match '^-?\d+$')            { $v = [int64]$c }
        elseif ($c -match '^[0-9A-Fa-f]{5,8}$') { $v = [Convert]::ToInt64($c,16) }
        else { return $null }
    } catch { return $null }
    return ('0x{0:X8}' -f ([uint32]($v -band 0xFFFFFFFFL)))
}
function Get-SccmErrorExplanation {
    param([string]$Code)
    $hex = ConvertTo-Hex32 $Code
    if (-not $hex) { return $null }
    $msg = $script:SccmErrorMap[$hex]
    if ($msg) { return "$hex : $msg" }
    return "$hex : not a known code. Open the Install/Uninstall or AppEnforce log (buttons above) and read the failure line, or search this code in CMTrace."
}
# Scan a copied log's text for known error codes and return a short summary line (or $null). Catches both
# 8-hex SCCM/HRESULT codes and decimal "exit code N" lines (PSADT / AppEnforce) - the latter is how a plain
# installer failure like exit code 1 shows up.
function Find-KnownLogErrors {
    param([string]$Text)
    if (-not $Text) { return $null }
    $found = [ordered]@{}
    foreach ($m in [regex]::Matches($Text, '0x[0-9A-Fa-f]{8}')) {
        $hex = ConvertTo-Hex32 $m.Value
        if ($hex -and $script:SccmErrorMap.ContainsKey($hex) -and -not $found.Contains($hex)) { $found[$hex] = $script:SccmErrorMap[$hex] }
    }
    # decimal exit codes, e.g. "exit code [1]", "exit code 1603", "completed with exit code 3010". Skip 0.
    foreach ($m in [regex]::Matches($Text, '(?i)exit code\s*\[?(\d{1,5})\]?')) {
        $n = $m.Groups[1].Value
        if ($n -eq '0') { continue }
        $hex = ConvertTo-Hex32 $n
        if ($hex -and $script:SccmErrorMap.ContainsKey($hex) -and -not $found.Contains($hex)) { $found[$hex] = $script:SccmErrorMap[$hex] }
    }
    if ($found.Count -eq 0) { return $null }
    return (($found.Keys | ForEach-Object { "$_ -> $($found[$_])" }) -join "`n")
}

# --- TROUBLESHOOT: pull a client log from a target machine to local temp and open it in CMTrace.
#     AppDiscovery/AppEnforce = CCM client logs; Package = the PSADT install/uninstall log(s). ----
function Get-SccmClientLog {
    param([Parameter(Mandatory)][string]$Machine, [ValidateSet('AppDiscovery','AppEnforce','Package')][string]$Which,
          [string]$FullName)
    $cfg = Get-SccmConfig
    $mn = "$Machine".Trim().Split('.')[0]
    if (-not $mn) { return @{ Ok=$false; Message='Enter a machine name.' } }
    $dest = Join-Path (Get-WorkPath 'Downloads') $mn; if (-not (Test-Path $dest)) { New-Item $dest -ItemType Directory -Force | Out-Null }
    try {
        if ($Which -eq 'Package') {
            $folder = Get-PBClientPath -Machine $mn -ShareRel $cfg.PsadtLogShare
            if ($FullName) { $cand = Join-Path $folder $FullName; if (Test-Path $cand) { $folder = $cand } }
            if (-not (Test-Path $folder)) { return @{ Ok=$false; Message="PSADT log path not reachable: $folder ($(if($folder -match '^\\\\'){'machine off / need admin on that remote'}else{'app not run here yet?'}))" } }
            # newest matching log(s): filter to the package name if given, else everything under the folder.
            $logs = Get-ChildItem -Path $folder -Recurse -Filter *.log -ErrorAction SilentlyContinue
            if ($FullName) { $logs = $logs | Where-Object { $_.Name -like "*$($FullName.Split('_')[1])*" -or $_.FullName -like "*$FullName*" } }
            $logs = $logs | Sort-Object LastWriteTime -Descending | Select-Object -First 5
            if (-not $logs) { return @{ Ok=$false; Message="No PSADT .log files found under $folder." } }
            $opened = $null
            foreach ($l in $logs) { $d = Join-Path $dest $l.Name; Copy-Item $l.FullName $d -Force -ErrorAction SilentlyContinue; if (-not $opened) { $opened = $d } }
            Open-CMTrace -LogPath $opened
            $known = try { Find-KnownLogErrors -Text ([IO.File]::ReadAllText($opened)) } catch { $null }
            return @{ Ok=$true; Message="Copied $($logs.Count) PSADT log(s) to $dest and opened the newest in CMTrace.$(if($known){"`nKnown issue(s) found:`n$known"})" }
        } else {
            $name = "$Which.log"
            $src  = Join-Path (Get-PBClientPath -Machine $mn -ShareRel $cfg.ClientLogShare) $name
            if (-not (Test-Path $src)) { return @{ Ok=$false; Message="$name not reachable at $src ($(if($src -match '^\\\\'){'machine off / need admin on that remote'}else{'not present here yet'}))." } }
            $d = Join-Path $dest $name
            Copy-Item $src $d -Force -ErrorAction Stop
            Open-CMTrace -LogPath $d
            $known = try { Find-KnownLogErrors -Text ([IO.File]::ReadAllText($d)) } catch { $null }
            return @{ Ok=$true; Message="Copied $name from $mn and opened it in CMTrace ($d).$(if($known){"`nKnown issue(s) found:`n$known"})" }
        }
    } catch { return @{ Ok=$false; Message="Get log failed: $($_.Exception.Message)" } }
}

# --- Remove ALL direct-membership rules (test machines added during DEV testing via Add-SccmTestMachine) from a
#     collection, so they are not carried across a hive move. Returns the count removed. Query rules / the limiting
#     collection are untouched. Assumes the caller is already in the site PSDrive (Push-Location "<Site>:"). ---
function Clear-SccmCollectionDirectMembers {
    param([Parameter(Mandatory)][string]$CollectionName)
    $rules = @(Get-CMDeviceCollectionDirectMembershipRule -CollectionName $CollectionName -ErrorAction SilentlyContinue)
    $removed = 0
    foreach ($r in $rules) {
        try { Remove-CMDeviceCollectionDirectMembershipRule -CollectionName $CollectionName -ResourceId $r.ResourceID -Force -ErrorAction Stop | Out-Null; $removed++ }
        catch { Write-Log "SCCM: could not remove member '$($r.RuleName)' from '$CollectionName': $($_.Exception.Message)" Warning }
    }
    return $removed
}

# --- DEV<->TEST (UAT) move: move the app + its INSTALL/UNINSTALL collections to the Test (or Dev) folders. ---
# Before the move we EMPTY the INSTALL/UNINSTALL collections of any direct members (test machines added during DEV
# testing): those are environment-specific and must not be dragged into the next hive. If a collection is already empty
# we just move it. The deployments + collections themselves are kept (only the test-machine membership is cleared).
function Move-SccmDevToTest {
    param([Parameter(Mandatory)][string]$FullName, [ValidateSet('Test','Dev')][string]$Target='Test', [string]$ToolRoot)
    $cfg = Get-SccmConfig
    Set-PbProgress -Indeterminate -Status 'Connecting to the SCCM site...'
    if (-not (Connect-Sccm -ToolRoot $ToolRoot)) { return @{ Ok=$false; Message=(Get-SccmConnectMessage) } }
    Push-Location "$($cfg.SiteCode):"
    try {
        if (-not (Get-CMApplication -Name $FullName -ErrorAction SilentlyContinue)) { return @{ Ok=$false; Message="Application '$FullName' not found." } }
        $appDest  = if ($Target -eq 'Test') { $cfg.TestAppFolder } else { $cfg.AppFolder }
        $collDest = if ($Target -eq 'Test') { $cfg.TestCollectionFolder } else { $cfg.CollectionFolder }
        # Empty the collections of any leftover test machines BEFORE the move (per-environment membership is never carried).
        Set-PbProgress -Percent 25 -Status 'Checking collection members...'
        $cleared = 0
        foreach ($c in @("$FullName-INSTALL (TEST)", "$FullName-UNINSTALL (TEST)")) {
            if (Get-CMDeviceCollection -Name $c -ErrorAction SilentlyContinue) {
                $rm = Clear-SccmCollectionDirectMembers -CollectionName $c
                if ($rm -gt 0) { $cleared += $rm; Write-Log "SCCM: cleared $rm test member(s) from '$c' before the $Target move." }
            }
        }
        Set-PbProgress -Percent 45 -Status "Moving application to $Target..."
        Move-CMObject -FolderPath $appDest -InputObject (Get-CMApplication -Name $FullName) -ErrorAction Stop | Out-Null
        Set-PbProgress -Percent 80 -Status "Moving collections to $Target..."
        foreach ($c in @("$FullName-INSTALL (TEST)", "$FullName-UNINSTALL (TEST)")) {
            $obj = Get-CMDeviceCollection -Name $c -ErrorAction SilentlyContinue
            if ($obj) { Move-CMObject -FolderPath $collDest -InputObject $obj -ErrorAction SilentlyContinue | Out-Null }
        }
        Set-PbProgress -Percent 100 -Status 'Done.'
        $memNote = if ($cleared -gt 0) { "Cleared $cleared test member(s) from the collections first." } else { 'Collections had no members - moved directly.' }
        Write-Log "SCCM: moved '$FullName' + collections to $Target ($appDest). $memNote" Success
        return @{ Ok=$true; Message="Moved '$FullName' (application + collections) to $Target.`n$memNote`nApp -> $appDest`nColls -> $collDest" }
    } catch { return @{ Ok=$false; Message="Move to $Target failed: $($_.Exception.Message)" } }
    finally { Pop-Location }
}

function Get-RandomStartTime { "{0}:{1}" -f (Get-Random -Maximum 12), (Get-Random -Maximum 59) }

# --- Open a log in CMTrace (falls back to default viewer). ----------------------------------
function Open-CMTrace {
    param([Parameter(Mandatory)][string]$LogPath)
    $cfg = Get-SccmConfig
    if (-not (Test-Path $LogPath)) { Write-Log "Log not found: $LogPath" Warning; return }
    if (Test-Path $cfg.CMTracePath) { Start-Process $cfg.CMTracePath -ArgumentList "`"$LogPath`"" }
    else { Start-Process $LogPath }
}
