##############################################################
# Intune.ps1  -  Intune Automator (Step 4 integration). CREATE the Win32 app only (no group
# assignment). Built to AVOID the IntuneWin32App module's 407 / large-file failures:
#   - Graph auth = DELEGATED interactive (Connect-MgGraph, no client id/secret); Graph calls via
#     Invoke-MgGraphRequest.
#   - The fragile part - the Azure-blob upload of the encrypted payload - is OUR OWN robust uploader:
#     system proxy + DefaultNetworkCredentials (kills 407), chunked block upload, SAS-URI RENEWAL
#     mid-upload (large files), and per-block retry/backoff.
# Detection MIRRORS SCCM: branding key (Revision == <rev>) + the SoftIdent/uninstall key (DisplayVersion
# >= ver, WoW6432Node stripped -> Check32BitOn64System=$true). Reuses Sccm.ps1's field parser + description.
##############################################################

$script:IntuneDefaults = [ordered]@{
    GraphBase         = 'https://graph.microsoft.com/beta'
    Scopes            = 'DeviceManagementApps.ReadWrite.All'
    IntuneWinAppUtil  = ''        # IntuneWinAppUtil.exe - relative to the tool folder, or auto-found under Lib\
    TenantId          = ''
    ModulePath        = 'Lib'     # relative to the tool folder; holds MSAL.PS + IntuneWin32App (also auto-found)
    MinWindowsRelease = '1607'
    BlockSizeMB       = 10       # bigger blocks = fewer round-trips on large (multi-GB) apps; 4..50 sensible
    SetupFile         = 'Invoke-AppDeployToolkit.exe'
    InstallCmd        = 'Invoke-AppDeployToolkit.exe install'
    UninstallCmd      = 'Invoke-AppDeployToolkit.exe uninstall'
    # PSADT v3 (Deploy-Application.exe): Intune runs it in the USER session via ServiceUI so the UI shows. The v3
    # utilities (ServiceUI.exe + Deploy-Application.exe + .config) are staged into the content root before wrapping.
    SetupFileV3       = 'Deploy-Application.exe'
    InstallCmdV3      = '.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Install'
    UninstallCmdV3    = '.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Uninstall'
    V3UtilitiesPath   = 'Lib\IntuneUtilitiesForPSADTv3'   # folder next to the tool; copied into the content root for v3
    RenewMinutes      = 40
}
function Get-IntuneConfig {
    $cfg = @{}; foreach ($k in $script:IntuneDefaults.Keys) { $cfg[$k] = $script:IntuneDefaults[$k] }
    $over = if (Get-Command Get-Setting -ErrorAction SilentlyContinue) { Get-Setting 'Intune' } else { $null }
    if ($over) { foreach ($p in $over.PSObject.Properties) { if ($null -ne $p.Value -and "$($p.Value)" -ne '') { $cfg[$p.Name] = $p.Value } } }
    return $cfg
}

# Make Invoke-RestMethod use the corporate proxy with the logged-on creds (kills 407 on the blob upload).
function Set-IntuneProxyCreds {
    # Some corporate machines have a machine.config <system.net><defaultProxy> that THROWS when .NET tries to CREATE the
    # proxy from config (WPAD / proxy-script failure). MSAL then dies with "Error creating the Web Proxy specified in the
    # 'system.net/defaultProxy' configuration section" -> "no token after sign-in". Fix: resolve the system (WinINET/IE)
    # proxy DIRECTLY - GetSystemWebProxy() does NOT go through that config section - carry the user's default credentials,
    # and pin it as DefaultWebProxy so MSAL reads a valid proxy instead of re-hitting the broken config path.
    try {
        $sys = [System.Net.WebRequest]::GetSystemWebProxy()
        if ($sys) {
            try { $sys.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials } catch {}
            [System.Net.WebRequest]::DefaultWebProxy = $sys
        }
    } catch {
        # Last resort: go direct (no proxy) rather than let the broken config proxy crash the token call.
        try { [System.Net.WebRequest]::DefaultWebProxy = $null } catch {}
        Write-Log "Intune: could not resolve the system proxy ($($_.Exception.Message)); trying a direct connection." Warning
    }
}

# Auth via the IntuneWin32App module's Connect-MSIntuneGraph (MSAL.PS) - it uses the "Microsoft Intune
# PowerShell" service principal (6beebafa-...), which tenants commonly permit even when the generic Graph
# CLI client (14d82eec) is blocked by Conditional Access (your AADSTS50105). We use the module ONLY for
# the token; the .intunewin content upload stays OUR robust uploader. No client id/secret of ours.
# When a PowerShell module lives on a NETWORK SHARE (portable tool run from a UNC path), importing it can fail with
# "Cannot add type. Compilation errors occurred." - MSAL.PS compiles internal C# that references its own DLLs, and the
# CLR/csc will not load/reference those from a remote path. Fix: copy the module's whole folder to a LOCAL cache once and
# import from there. Local (non-UNC) module folders pass straight through unchanged.
function Get-LocalModuleManifest {
    param([string]$ManifestPath)
    if (-not $ManifestPath -or ($ManifestPath -notmatch '^\\\\')) { return $ManifestPath }   # only stage UNC paths
    try {
        $srcDir = Split-Path -Parent $ManifestPath
        $name   = Split-Path -Leaf $srcDir
        $cache  = Join-Path (Get-WorkPath 'modules') $name
        $dstManifest = Join-Path $cache (Split-Path -Leaf $ManifestPath)
        $fresh = (Test-Path $dstManifest) -and ((Get-Item $dstManifest).LastWriteTimeUtc -ge (Get-Item $ManifestPath).LastWriteTimeUtc)
        if (-not $fresh) {
            if (Test-Path $cache) { Remove-Item $cache -Recurse -Force -ErrorAction SilentlyContinue }
            Copy-Item -LiteralPath $srcDir -Destination $cache -Recurse -Force -ErrorAction Stop
            Unblock-PBPath -Path $cache   # strip Mark-of-the-Web on the copied files
            Write-Log "Intune: staged module '$name' from the share to a local cache ($cache) for import."
        }
        if (Test-Path $dstManifest) { return $dstManifest }
    } catch { Write-Log "Intune: could not stage module locally ($ManifestPath): $($_.Exception.Message). Importing from the share." Warning }
    return $ManifestPath
}

function Connect-Intune {
    $cfg = Get-IntuneConfig
    Set-IntuneProxyCreds
    if (-not (Get-Command Connect-MSIntuneGraph -ErrorAction SilentlyContinue)) {
        # Search the tool folder (resolved ModulePath, then Lib\, then the whole tool root) for the two
        # modules we need. All tool-relative so the portable exe works wherever it's copied.
        $dirs = @()
        if ($cfg.ModulePath) { $dirs += (Resolve-ToolPath $cfg.ModulePath) }
        $dirs += (Join-Path (Get-ToolRoot) 'Lib'); $dirs += (Get-ToolRoot)
        $msal = $null; $iwa = $null
        foreach ($dir in ($dirs | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)) {
            if (-not $msal) { $msal = Get-ChildItem -Path $dir -Recurse -Filter 'MSAL.PS.psd1'       -ErrorAction SilentlyContinue | Select-Object -First 1 }
            if (-not $iwa)  { $iwa  = Get-ChildItem -Path $dir -Recurse -Filter 'IntuneWin32App.psd1' -ErrorAction SilentlyContinue | Select-Object -First 1 }
        }
        if (-not $msal -or -not $iwa) { Write-Log "Intune modules not found (need MSAL.PS + IntuneWin32App under the tool's Lib\ or Intune.ModulePath)." Error; return $false }
        # EXECUTION POLICY: MSAL.PS + IntuneWin32App are SCRIPT modules, so on a machine whose (often 32-bit WOW6432Node)
        # policy is Restricted/Undefined the import dies with "running scripts is disabled on this system" (same root cause
        # as the ConfigMgr console module). Lift it for THIS PROCESS ONLY before importing - identical to the SCCM path.
        if (Get-Command Enable-PBProcessScripts -ErrorAction SilentlyContinue) { [void](Enable-PBProcessScripts) }
        # Stage from the share to a local cache first (avoids the UNC "Cannot add type" compile failure). MSAL.PS BEFORE
        # IntuneWin32App (the latter depends on it).
        $msalPath = Get-LocalModuleManifest $msal.FullName
        $iwaPath  = Get-LocalModuleManifest $iwa.FullName
        try { Import-Module $msalPath -ErrorAction Stop; Import-Module $iwaPath -ErrorAction Stop }
        catch {
            $msg = "$($_.Exception.Message)"
            $hint = if ($msg -match '(?i)running scripts is disabled|execution of scripts is disabled|UnauthorizedAccess') {
                ' The execution policy is blocking the script module import - it is enforced by a GPO (MachinePolicy/UserPolicy) that a per-process Bypass cannot override; have "PowerShell script execution" allowed centrally for this machine.'
            } else { '' }
            Write-Log "Importing Intune modules failed: $msg.$hint" Error; return $false
        }
    }
    # Must be the real tenant (e.g. contoso.onmicrosoft.com or the tenant GUID) - exactly like the
    # working migrator tool. 'common' misroutes an external/guest (ext id) sign-in to the home tenant.
    $tenant = "$($cfg.TenantId)".Trim()
    if (-not $tenant) {
        Write-Log "Intune: no tenant set. Put your tenant domain (e.g. contoso.onmicrosoft.com) in settings.json -> Intune.TenantId, then retry." Error
        return $false
    }
    try {
        # Connect-MSIntuneGraph swallows its own failures as warnings and only sets the globals on
        # success, so capture the warning stream and surface it (CA / AADSTS reasons land there).
        $warns = $null
        Connect-MSIntuneGraph -TenantID $tenant -WarningVariable warns -WarningAction SilentlyContinue | Out-Null
        if (-not $Global:AuthenticationHeader -and -not $Global:AccessToken) {
            $why = if ($warns) { ($warns | ForEach-Object { "$_" }) -join ' | ' } else { 'sign-in returned no token (cancelled, or blocked by Conditional Access).' }
            Write-Log "Intune: no token after sign-in - $why" Error
            return $false
        }
        Write-Log "Intune connected to '$tenant' (Microsoft Intune PowerShell client)." Success
        return $true
    } catch { Write-Log "Intune connect failed: $($_.Exception.Message)" Error; return $false }
}

# Bearer header (just Authorization, to avoid Content-Type/ExpiresOn clashes); silent refresh near expiry.
function Get-IntuneAuthHeader {
    if ($Global:AccessToken -and $Global:AccessToken.ExpiresOn) {
        $exp = try { $Global:AccessToken.ExpiresOn.LocalDateTime } catch { $null }
        if ($exp -and (Get-Date) -ge $exp.AddMinutes(-5)) {
            try { Connect-MSIntuneGraph -TenantID $Global:AccessTokenTenantID -Refresh -ErrorAction Stop | Out-Null } catch {}
        }
    }
    if ($Global:AuthenticationHeader -and $Global:AuthenticationHeader.Authorization) { return @{ Authorization = "$($Global:AuthenticationHeader.Authorization)" } }
    if ($Global:AccessToken) { return @{ Authorization = "Bearer $($Global:AccessToken.AccessToken)" } }
    return $null
}

function Invoke-Graph {
    param([string]$Method, [string]$Uri, $Body)
    $hdr = Get-IntuneAuthHeader
    if (-not $hdr) { throw 'Not connected to Intune.' }
    $p = @{ Method=$Method; Uri=$Uri; Headers=$hdr; ErrorAction='Stop' }
    if ($Body) {
        $json = if ($Body -is [string]) { "$Body" } else { $Body | ConvertTo-Json -Depth 20 -Compress }
        # Send the JSON as explicit UTF-8 BYTES (not a string): Windows PowerShell 5.1's Invoke-RestMethod encodes a
        # STRING body as ASCII, which mangles any non-ASCII character (®/™/accents/NBSP - common in a vendor's
        # description/publisher) into invalid bytes, so Graph rejects the payload with HTTP 400 "Unable to read JSON
        # request payload." Bytes + an explicit charset make the body byte-exact and parseable.
        $p['Body'] = [Text.Encoding]::UTF8.GetBytes($json)
        $p['ContentType'] = 'application/json; charset=utf-8'
    }
    $reauthed = $false
    for ($try=1; $try -le 4; $try++) {
        try { return Invoke-RestMethod @p }
        catch {
            $sc = $null; try { $sc = [int]$_.Exception.Response.StatusCode } catch {}
            # Graph puts the real reason in the response body - surface it (Invoke-RestMethod fills ErrorDetails).
            $detail = "$($_.ErrorDetails.Message)"
            if (-not $detail) { try { $rs=$_.Exception.Response.GetResponseStream(); $sr=New-Object IO.StreamReader($rs); $detail=$sr.ReadToEnd(); $sr.Close() } catch {} }
            # TOKEN EXPIRED mid-flight (long uploads): re-auth ONCE, refresh the header, retry the call.
            if ($sc -eq 401 -and -not $reauthed) {
                $reauthed = $true
                Write-Log 'Intune: token expired mid-operation - signing in again and retrying...' Warning
                try { if (Connect-Intune) { $p['Headers'] = Get-IntuneAuthHeader; continue } } catch {}
            }
            if ($try -ge 4 -or ($sc -and $sc -lt 500 -and $sc -ne 429)) {
                if ($detail) { $detail = ($detail -replace '\s+',' ').Trim(); if ($detail.Length -gt 600) { $detail = $detail.Substring(0,600) } }
                # DIAGNOSTIC for the "unable to read JSON request payload" 400: log exactly what we sent (Content-Type +
                # body byte length + a head/tail snippet) so a repeat failure shows the real cause instead of guessing.
                if ($sc -eq 400 -and $detail -match '(?i)payload|Content-Type' -and $p.ContainsKey('Body')) {
                    $bb = $p['Body']; $len = if ($bb -is [byte[]]) { $bb.Length } else { "$bb".Length }
                    $snip = try { $s = if ($bb -is [byte[]]) { [Text.Encoding]::UTF8.GetString($bb) } else { "$bb" }; if ($s.Length -gt 300) { $s.Substring(0,200) + ' … ' + $s.Substring($s.Length-80) } else { $s } } catch { '<unreadable>' }
                    Write-Log "Intune Graph 400 payload diag: ContentType='$($p.ContentType)' BodyBytes=$len BodyType=$($bb.GetType().Name) Snippet=$snip" Warning
                }
                throw "Graph $Method -> HTTP $sc$(if($detail){": $detail"})"
            }
            # 429 throttling: honor Graph's Retry-After when present; otherwise backoff.
            $wait = [Math]::Min(20, 3*$try)
            if ($sc -eq 429) { try { $ra = [int]"$($_.Exception.Response.Headers['Retry-After'])"; if ($ra -gt 0) { $wait = [Math]::Min(60, $ra) } } catch {} }
            Start-Sleep -Seconds $wait
        }
    }
}

# Find the REAL content root to wrap + which PSADT generation it is. The launcher (Deploy-Application / Invoke-
# AppDeployToolkit) is usually in Content directly, but some packages nest it in a subfolder (e.g.
# Content\MUL_x64_0001\Deploy-Application.exe). IntuneWinAppUtil must be pointed at THAT folder - the one holding the
# launcher - because at deploy time Intune extracts and runs the setup file from the package root. Returns
# @{ Root; Generation('v3'|'v4'); SetupFile } for the SHALLOWEST launcher found, or $null when there is no PSADT
# launcher at all (a bare setup .exe -> caller tells the user to integrate manually).
function Resolve-IntuneContentRoot {
    param([Parameter(Mandatory)][string]$ContentFolder)
    if (-not (Test-Path -LiteralPath $ContentFolder)) { return $null }
    # v4 markers first (a v4 package never carries a top-level Deploy-Application; v3 never carries Invoke-AppDeployToolkit)
    $markers = @(
        @{ File='Invoke-AppDeployToolkit.exe'; Gen='v4'; Setup='Invoke-AppDeployToolkit.exe' }
        @{ File='Invoke-AppDeployToolkit.ps1'; Gen='v4'; Setup='Invoke-AppDeployToolkit.exe' }
        @{ File='Deploy-Application.exe';       Gen='v3'; Setup='Deploy-Application.exe' }
        @{ File='Deploy-Application.ps1';       Gen='v3'; Setup='Deploy-Application.exe' }
    )
    foreach ($m in $markers) {
        $found = Get-ChildItem -LiteralPath $ContentFolder -Filter $m.File -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                 Sort-Object { ($_.FullName -split '[\\/]').Count } | Select-Object -First 1
        if ($found) { return @{ Root=$found.DirectoryName; Generation=$m.Gen; SetupFile=$m.Setup } }
    }
    return $null
}

# A v3 package must launch Deploy-Application via ServiceUI under Intune so the UI shows in the user session. Wrap the
# given command (the SCCM/base form, e.g. '"Deploy-Application.exe" Install') with ServiceUI - unless it already is one.
# Any switches the packager added to the base command are preserved inside the wrap.
function ConvertTo-IntuneV3Command {
    param([string]$Command)
    $c = "$Command".Trim()
    if (-not $c) { return $c }
    if ($c -match '(?i)\bServiceUI(\.exe)?\b') { return $c }
    $c = $c -replace '^"([^"]+\.exe)"', '$1'   # unquote a leading "Deploy-Application.exe" so the form matches exactly
    return ".\ServiceUI.exe -process:explorer.exe $c"
}

# v3 Intune prep: copy the staged utilities (ServiceUI.exe + Deploy-Application.exe + .config) INTO the content root
# (next to the launcher) so the ServiceUI install/uninstall commands work once Intune extracts the package. The
# packager exe (IntuneWinAppUtil.exe) is never shipped inside a package.
function Initialize-IntuneV3Content {
    param([Parameter(Mandatory)][string]$ContentRoot)
    $cfg = Get-IntuneConfig
    $src = if (Get-Command Resolve-ToolPath -ErrorAction SilentlyContinue) { Resolve-ToolPath $cfg.V3UtilitiesPath } else { $cfg.V3UtilitiesPath }
    # A self-staged LOCAL copy (run-from-share) may not have this folder yet - fall back to the recorded share source
    # / $env:PB_SHAREROOT (same pattern as the ConfigMgr module) so ServiceUI is always found.
    if (-not $src -or -not (Test-Path $src -PathType Container)) {
        $bases = @()
        try { if (Get-Command Get-StageSource -ErrorAction SilentlyContinue) { $bases += (Get-StageSource -ToolRoot (Get-ToolRoot)) } } catch {}
        if ($env:PB_SHAREROOT) { $bases += $env:PB_SHAREROOT }
        foreach ($b in ($bases | Where-Object { $_ })) {
            $cand = Join-Path $b $cfg.V3UtilitiesPath
            if (Test-Path $cand -PathType Container) { $src = $cand; Write-Log "Intune v3: using utilities from the share source: $cand"; break }
        }
    }
    if (-not $src -or -not (Test-Path $src -PathType Container)) {
        Write-Log "Intune v3: utilities folder not found ($($cfg.V3UtilitiesPath)) - ServiceUI.exe + Deploy-Application.exe must already be in the content root." Warning
    } else {
        $copied = @()
        foreach ($f in (Get-ChildItem -LiteralPath $src -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -ieq 'IntuneWinAppUtil.exe') { continue }   # the packager - never ship it inside a package
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $ContentRoot $f.Name) -Force
            $copied += $f.Name
        }
        Write-Log "Intune v3: staged into '$ContentRoot': $($copied -join ', ')"
    }
    if (-not (Test-Path (Join-Path $ContentRoot 'ServiceUI.exe'))) {
        Write-Log "Intune v3: ServiceUI.exe is NOT in the content root - the install/uninstall commands will FAIL. Put ServiceUI.exe in $($cfg.V3UtilitiesPath)." Error
    }
}

# --- Package the Content folder into <FullName>.intunewin via IntuneWinAppUtil. ---------------
function New-IntuneWinPackage {
    param([Parameter(Mandatory)][string]$ContentFolder, [Parameter(Mandatory)][string]$FullName, [string]$OutputFolder, [string]$SetupFile, [string]$Generation)
    $cfg = Get-IntuneConfig
    if (-not "$SetupFile".Trim()) { $SetupFile = $cfg.SetupFile }
    # Resolve IntuneWinAppUtil.exe. The configured value may be the exe itself, a FOLDER (e.g. "Lib"),
    # or empty - in the last two cases we SEARCH for the .exe, so a folder value is never run as a command
    # (that caused the "...\lib is not recognized as a cmdlet" error).
    $util = $null
    $cand = if ($cfg.IntuneWinAppUtil) { Resolve-ToolPath $cfg.IntuneWinAppUtil } else { $null }
    if ($cand -and ($cand -like '*.exe') -and (Test-Path $cand -PathType Leaf)) { $util = $cand }
    if (-not $util) {
        $searchDirs = @()
        if ($cand -and (Test-Path $cand -PathType Container)) { $searchDirs += $cand }
        $searchDirs += (Join-Path (Get-ToolRoot) 'Lib'); $searchDirs += (Get-ToolRoot)
        foreach ($dir in ($searchDirs | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)) {
            $found = Get-ChildItem -Path $dir -Recurse -Filter 'IntuneWinAppUtil.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $util = $found.FullName; break }
        }
    }
    if (-not $util -or -not (Test-Path $util -PathType Leaf)) { Write-Log "IntuneWinAppUtil.exe not found (put it under the tool's Lib\ or set Intune.IntuneWinAppUtil to the exe path)." Error; return $null }
    # STABLE LOCAL output folder per package (kept - NOT a random temp that gets cleaned). Both the prepared content
    # and the resulting .intunewin persist here so nothing is lost after upload / a failed run can be retried.
    if (-not "$OutputFolder".Trim()) { $OutputFolder = Get-WorkPath (Join-Path 'IntuneWin' $FullName) }
    if (-not (Test-Path $OutputFolder)) { New-Item $OutputFolder -ItemType Directory -Force | Out-Null }
    Get-ChildItem -LiteralPath $OutputFolder -Filter *.intunewin -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue  # drop only a stale .intunewin
    # ALWAYS snapshot the EXACT content that gets wrapped into <out>\Content, so it can be inspected after the fact
    # (this is what shipped inside the .intunewin - path/file issues are visible here). The original package is left
    # untouched: any v3 ServiceUI staging happens in THIS copy, not in the source. IntuneWinAppUtil then wraps the copy.
    $localContent = Join-Path $OutputFolder 'Content'
    if (Test-Path $localContent) { Remove-Item $localContent -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item $localContent -ItemType Directory -Force | Out-Null
    Write-Log "Intune: staging the content to wrap -> $localContent (from $ContentFolder)"
    # per-item copy with -LiteralPath so a package name containing [ ] (wildcard chars) copies correctly, and the
    # WHOLE tree (Files\, SupportFiles\, subfolders) comes across - a "\*" LiteralPath would copy nothing.
    foreach ($it in @(Get-ChildItem -LiteralPath $ContentFolder -Force -ErrorAction SilentlyContinue)) {
        Copy-Item -LiteralPath $it.FullName -Destination $localContent -Recurse -Force
    }
    if ("$Generation" -eq 'v3') { Initialize-IntuneV3Content -ContentRoot $localContent }   # stage ServiceUI into the COPY
    $ContentFolder = $localContent
    $setup = Join-Path $ContentFolder $SetupFile
    if (-not (Test-Path $setup)) { Write-Log "Setup file '$SetupFile' not found in the content to wrap: $ContentFolder" Error; return $null }
    $dest = Join-Path $OutputFolder "$FullName.intunewin"
    # Log the EXACT command line + the top-level content so a packager can spot a wrong path / missing file.
    $cmdLine = "IntuneWinAppUtil.exe -c `"$ContentFolder`" -s `"$SetupFile`" -o `"$OutputFolder`" -q"
    Write-Log "Intune: building .intunewin  ->  $cmdLine"
    $topList = @(Get-ChildItem -LiteralPath $ContentFolder -Force -ErrorAction SilentlyContinue | ForEach-Object { if ($_.PSIsContainer) { "$($_.Name)\" } else { $_.Name } })
    Write-Log "Intune: content root holds: $($topList -join ', ')"
    # Manifest next to the .intunewin: how it was built (so path/content problems are traceable without re-running).
    $manifest = @(
        "Package     : $FullName",
        "Built       : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Generation  : $(if($Generation){$Generation}else{'(auto)'})",
        "Source root : $ContentFolder",
        "Setup file  : $SetupFile   (-s, relative to the content root)",
        "Command     : $cmdLine",
        "Wrapped .intunewin = <content root> zipped whole; Intune extracts it and runs the setup file from the root.",
        "",
        "Content tree (this is EXACTLY what shipped inside the .intunewin):"
    ) + @(Get-ChildItem -LiteralPath $ContentFolder -Recurse -Force -ErrorAction SilentlyContinue |
          ForEach-Object { '  ' + $_.FullName.Substring($ContentFolder.Length).TrimStart('\') + $(if($_.PSIsContainer){'\'}else{"  ($([math]::Round($_.Length/1KB,1)) KB)"}) })
    Set-Content -LiteralPath (Join-Path $OutputFolder '_IntuneWin-manifest.txt') -Value $manifest -Encoding UTF8
    $utilOut = @(& $util -c "$ContentFolder" -s "$SetupFile" -o "$OutputFolder" -q 2>&1 | ForEach-Object { "$_" })
    $made = Get-ChildItem -LiteralPath $OutputFolder -Filter *.intunewin -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $made) {
        # Surface WHY: exit code + the tool's last output lines (usually names the actual problem).
        $tail = (@($utilOut | Where-Object { $_ } | Select-Object -Last 4) -join ' | ')
        Write-Log "Intune: .intunewin was not produced (IntuneWinAppUtil exit $LASTEXITCODE)$(if($tail){": $tail"})" Error
        return $null
    }
    if ($made.FullName -ne $dest) { Move-Item $made.FullName $dest -Force }
    Write-Log "Intune: kept for inspection -> .intunewin: $dest  |  content: $ContentFolder  |  manifest: $(Join-Path $OutputFolder '_IntuneWin-manifest.txt')"
    return $dest
}

# --- Read Detection.xml (encryption info + sizes) from the .intunewin. ------------------------
function Get-IntuneWinMetadata {
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -like '*Detection.xml' } | Select-Object -First 1
        if (-not $entry) { throw "Detection.xml not found in $Path" }
        $sr = New-Object System.IO.StreamReader($entry.Open()); [xml]$xml = $sr.ReadToEnd(); $sr.Close()
    } finally { $zip.Dispose() }
    $i = $xml.ApplicationInfo
    [pscustomobject]@{ InnerFileName=$i.FileName; Size=[int64]$i.UnencryptedContentSize; Enc=$i.EncryptionInfo }
}
function Get-IntuneEncryptedPayload {
    param([string]$IntuneWinPath, [string]$InnerFileName)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tmp = Join-Path (Get-WorkPath 'Temp') ("iw_{0}.bin" -f ([guid]::NewGuid().ToString('N')))
    $zip = [System.IO.Compression.ZipFile]::OpenRead($IntuneWinPath)
    try {
        $e = $zip.Entries | Where-Object { $_.FullName -like "*Contents/$InnerFileName" -or $_.FullName -like "*Contents\$InnerFileName" } | Select-Object -First 1
        if (-not $e) { throw "Encrypted payload '$InnerFileName' not found in .intunewin" }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $tmp, $true)
    } finally { $zip.Dispose() }
    $tmp
}

function Wait-IntuneFileState {
    param([string]$FileUri, [string]$Stage, [int]$TimeoutSec = 900)
    $deadline = (Get-Date).AddSeconds($TimeoutSec); $state = ''
    do {
        Start-Sleep -Seconds 4
        # A transient Graph/network blip while POLLING must not kill the whole stage - log and keep polling
        # until the deadline (Invoke-Graph itself already retried; this catches the post-retry residue).
        $f = $null
        try { $f = Invoke-Graph GET $FileUri }
        catch { Write-Log "Intune: status poll blip at '$Stage' ($($_.Exception.Message)) - continuing to poll..." Warning; continue }
        $state = "$($f.uploadState)"
        if ($state -eq "$($Stage)Success") { return $f }
        if ($state -eq "$($Stage)Failed")  { throw "Intune file stage '$Stage' failed (uploadState=$state)" }
    } while ((Get-Date) -lt $deadline)
    throw "Timed out at Intune stage '$Stage' (last state: $state)"
}

# Before committing, the file's uploadState MUST be a SUCCESS state (initial SAS request, OR a renewal).
# If a SAS renewal happened during the upload and is still settling, Intune rejects commit with
# "File commit can not be started until status for SAS request or renewal has transitioned to 'Success'".
# So we poll until a committable success state, then the caller commits (with its own retry).
function Wait-IntuneCommittable {
    param([string]$FileUri, [int]$TimeoutSec = 300)
    $deadline = (Get-Date).AddSeconds($TimeoutSec); $state = ''
    do {
        $f = $null
        try { $f = Invoke-Graph GET $FileUri }
        catch { Write-Log "Intune: pre-commit poll blip ($($_.Exception.Message)) - continuing..." Warning; Start-Sleep -Seconds 4; continue }
        $state = "$($f.uploadState)"
        if ($state -in 'azureStorageUriRequestSuccess','azureStorageUriRenewalSuccess') { return $f }
        if ($state -like '*Failed') { throw "Intune upload failed before commit (uploadState=$state)" }
        Start-Sleep -Seconds 4
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for a committable upload state (last: $state)"
}

# --- FAST + robust block upload to the Azure SAS URI via HttpClient. One reused HTTP keep-alive
#     connection across all blocks (the big speed win vs Invoke-WebRequest, which reconnects every call),
#     RAW bytes via ByteArrayContent (no PS-cmdlet corruption, no per-block string conversion), system
#     proxy + logged-on creds (kills 407), per-block retry, and SAS renewal for long/large uploads. ----
function Send-IntuneBlob {
    param([string]$SasUri, [string]$FilePath, [string]$FileUri)
    $cfg = Get-IntuneConfig
    $blockSize = [int]($cfg.BlockSizeMB) * 1MB
    $total = (Get-Item -LiteralPath $FilePath).Length
    $blocks = [Math]::Max(1, [Math]::Ceiling($total / $blockSize))
    $ids = New-Object System.Collections.Generic.List[string]

    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    $handler = New-Object System.Net.Http.HttpClientHandler
    try {
        $handler.Proxy = [System.Net.WebRequest]::DefaultWebProxy; $handler.UseProxy = $true
        if ($handler.Proxy) { $handler.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials }
    } catch {}
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(15)

    # PUT helper: raw bytes ($buf[0..$len]) with custom request headers; retry up to 4x. Reads $client from scope.
    $put = {
        param($u, [byte[]]$buf, [int]$len, [hashtable]$reqHdrs, [string]$ctype, [string]$what)
        for ($t = 1; $t -le 4; $t++) {
            $req = $null
            try {
                $req = New-Object System.Net.Http.HttpRequestMessage -ArgumentList ([System.Net.Http.HttpMethod]::Put, $u)
                $content = New-Object System.Net.Http.ByteArrayContent -ArgumentList ($buf, [int]0, [int]$len)
                $content.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue -ArgumentList $ctype
                $req.Content = $content
                if ($reqHdrs) { foreach ($k in $reqHdrs.Keys) { [void]$req.Headers.TryAddWithoutValidation($k, "$($reqHdrs[$k])") } }
                $resp = $client.SendAsync($req).GetAwaiter().GetResult()
                $code = [int]$resp.StatusCode; $resp.Dispose()
                if ($code -ge 200 -and $code -lt 300) { return }
                throw "HTTP $code"
            } catch {
                if ($t -ge 4) { throw "$what failed after retries: $($_.Exception.Message)" }
                Start-Sleep -Seconds ([Math]::Min(30, 3 * $t))
            } finally { if ($req) { $req.Dispose() } }
        }
    }

    $fs = [System.IO.File]::OpenRead($FilePath)
    $lastRenew = Get-Date
    try {
        $buffer = New-Object byte[] $blockSize
        $idx = 0; $sent = 0
        while (($read = $fs.Read($buffer, 0, $buffer.Length)) -gt 0) {
            # SAS expires ~1h: renew before it does on long uploads. A FAILED scheduled renewal must not kill
            # the upload - the per-block resume below renews again the moment a block actually fails.
            if (((Get-Date) - $lastRenew).TotalMinutes -ge $cfg.RenewMinutes) {
                try {
                    Write-Log "Intune: renewing upload SAS..."
                    Invoke-Graph POST "$FileUri/renewUpload" '{}' | Out-Null
                    $r = Wait-IntuneFileState -FileUri $FileUri -Stage 'azureStorageUriRenewal'
                    $SasUri = $r.azureStorageUri; $lastRenew = Get-Date
                } catch { Write-Log "Intune: scheduled SAS renewal failed ($($_.Exception.Message)) - continuing; per-block resume will renew if needed." Warning }
            }
            $blockId = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($idx.ToString('D6'))); $ids.Add($blockId)
            # RESUME-on-failure: if a block exhausts its retries (often an expired SAS on a long/large upload),
            # renew the SAS and retry the SAME block. Already-uploaded blocks stay in Azure, so we resume rather
            # than restart. Up to 3 renew-and-resume rounds per block.
            $ok = $false
            for ($round = 1; $round -le 3 -and -not $ok; $round++) {
                $uri = "$SasUri&comp=block&blockid=$([uri]::EscapeDataString($blockId))"
                try { & $put $uri $buffer $read @{ 'x-ms-blob-type'='BlockBlob' } 'application/octet-stream' "Block $idx"; $ok = $true }
                catch {
                    if ($round -ge 3) { throw }
                    Write-Log "Intune: block $idx failed ($($_.Exception.Message)); renewing SAS and resuming..." Warning
                    Set-PbProgress -Indeterminate -Status "Renewing upload SAS and resuming at block $($idx+1)..."
                    try { Invoke-Graph POST "$FileUri/renewUpload" '{}' | Out-Null; $r = Wait-IntuneFileState -FileUri $FileUri -Stage 'azureStorageUriRenewal'; $SasUri = $r.azureStorageUri; $lastRenew = Get-Date } catch {}
                }
            }
            $idx++; $sent += $read
            $mbSent = [math]::Round($sent/1MB,1); $mbTotal = [math]::Round($total/1MB,1)
            Write-Log ("Intune: block {0}/{1} ({2} MB)" -f $idx, $blocks, $mbSent)
            Set-PbProgress -Percent ([int](15 + 75 * ($sent / $total))) -Status ("Uploading $mbSent / $mbTotal MB  (block $idx/$blocks)")
        }
        # Commit the block list (raw UTF-8 bytes via the same client).
        $list = '<?xml version="1.0" encoding="utf-8"?><BlockList>' + (($ids | ForEach-Object { "<Latest>$_</Latest>" }) -join '') + '</BlockList>'
        $listBytes = [Text.Encoding]::UTF8.GetBytes($list)
        Write-Log "Intune: committing block list ($($ids.Count) blocks)..."
        Set-PbProgress -Percent 91 -Status 'Committing uploaded blocks...'
        & $put "$SasUri&comp=blocklist" $listBytes $listBytes.Length $null 'text/plain' 'Block-list commit'
    } finally {
        $fs.Close(); $fs.Dispose()
        try { $client.Dispose(); $handler.Dispose() } catch {}
    }
}

# --- Upload the .intunewin content to an app id (create content version -> file -> blob -> commit -> patch).
function Set-IntuneAppContent {
    param([string]$AppId, [string]$IntuneWinPath)
    $cfg = Get-IntuneConfig
    $meta = Get-IntuneWinMetadata -Path $IntuneWinPath
    $payload = Get-IntuneEncryptedPayload -IntuneWinPath $IntuneWinPath -InnerFileName $meta.InnerFileName
    try {
        $encSize = (Get-Item -LiteralPath $payload).Length
        $appUri  = "$($cfg.GraphBase)/deviceAppManagement/mobileApps/$AppId"
        $base    = "$appUri/microsoft.graph.win32LobApp/contentVersions"
        $cv  = Invoke-Graph POST $base '{}'
        $vid = $cv.id
        $fileBody = @{ '@odata.type'='#microsoft.graph.mobileAppContentFile'; name=$meta.InnerFileName
                       size=[int64]$meta.Size; sizeEncrypted=[int64]$encSize; manifest=$null; isDependency=$false }
        $file    = Invoke-Graph POST "$base/$vid/files" $fileBody
        $fileUri = "$base/$vid/files/$($file.id)"
        $ready   = Wait-IntuneFileState -FileUri $fileUri -Stage 'azureStorageUriRequest'
        Write-Log "Intune: uploading $([math]::Round($encSize/1MB,1)) MB to Azure blob..."
        Set-PbProgress -Percent 15 -Status 'Uploading content to Azure...'
        Send-IntuneBlob -SasUri $ready.azureStorageUri -FilePath $payload -FileUri $fileUri
        $commit = @{ fileEncryptionInfo = @{
                        encryptionKey        = $meta.Enc.EncryptionKey
                        macKey               = $meta.Enc.MacKey
                        initializationVector = $meta.Enc.InitializationVector
                        mac                  = $meta.Enc.Mac
                        profileIdentifier    = 'ProfileVersion1'
                        fileDigest           = $meta.Enc.FileDigest
                        fileDigestAlgorithm  = $meta.Enc.FileDigestAlgorithm } }
        Write-Log "Intune: committing file (sending encryption info)..."
        Set-PbProgress -Percent 92 -Status 'Finalizing (commit)...'
        # Make sure the SAS request/renewal has settled to a Success state, THEN commit - retrying the
        # transient "commit can not be started ... 'Success'" 400 that appears right after a renewal.
        $committed = $false
        for ($ct = 1; $ct -le 6 -and -not $committed; $ct++) {
            Wait-IntuneCommittable -FileUri $fileUri | Out-Null
            try { Invoke-Graph POST "$fileUri/commit" $commit | Out-Null; $committed = $true }
            catch {
                $em = "$($_.Exception.Message)"
                if ($ct -ge 6 -or $em -notmatch 'commit can not be started|transitioned to|SAS request or renewal') { throw }
                Write-Log "Intune: commit not ready (SAS/renewal still settling); waiting 10s and retrying ($ct/6)..." Warning
                Set-PbProgress -Percent 93 -Status "Waiting for the upload to settle, then committing ($ct/6)..."
                Start-Sleep -Seconds 10
            }
        }
        Write-Log "Intune: waiting for commitFileSuccess..."
        Set-PbProgress -Percent 95 -Status 'Waiting for Intune to confirm the upload...'
        Wait-IntuneFileState -FileUri $fileUri -Stage 'commitFile' | Out-Null
        Write-Log "Intune: setting committed content version $vid..."
        Set-PbProgress -Percent 98 -Status 'Setting committed content version...'
        Invoke-Graph PATCH $appUri (@{ '@odata.type'='#microsoft.graph.win32LobApp'; committedContentVersion="$vid" }) | Out-Null
        return $vid
    } finally { Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue }
}

# --- Detection rules (mirror SCCM): branding (Revision == rev) + uninstall key (DisplayVersion >= ver). ---
function Get-IntuneDetectionRules {
    param([hashtable]$Fields)
    $rules = New-Object System.Collections.Generic.List[object]
    $rules.Add(@{ '@odata.type'='#microsoft.graph.win32LobAppRegistryDetection'
                  keyPath="HKEY_LOCAL_MACHINE\$($Fields.BrandingKey)"; valueName='Revision'
                  detectionType='string'; operator='equal'; detectionValue="$($Fields.Revision)"; check32BitOn64System=$false })
    # STRICT: exactly ONE secondary rule for the selected type, never the other (no cross-fallback).
    $type = if ($Fields.DetectType) { "$($Fields.DetectType)" } else { 'Version' }
    if ($type -eq 'ProductCode') {
        if ($Fields.ProductCode) { $rules.Add(@{ '@odata.type'='#microsoft.graph.win32LobAppProductCodeDetection'; productCode=$Fields.ProductCode }) }
    } elseif ($type -ne 'None' -and $Fields.UninstallKey) {
        $r = @{ '@odata.type'='#microsoft.graph.win32LobAppRegistryDetection'
                keyPath="HKEY_LOCAL_MACHINE\$($Fields.UninstallKey)"; valueName='DisplayVersion'
                detectionValue="$($Fields.DetectVersion)"; check32BitOn64System=[bool]$Fields.Is32Bit }
        if ($type -eq 'String') { $r['detectionType']='string';  $r['operator']='equal' }
        else                    { $r['detectionType']='version'; $r['operator']='greaterThanOrEqual' }
        $rules.Add($r)
    }
    # Return the rules as a plain enumerable array; the call sites wrap with @() so a SINGLE rule (branding-only) still
    # serialises as a JSON array `[{}]`, not a bare object `{}` (Graph 400 "detectionRules ... does not match schema").
    # NOTE: do NOT use `,$rules.ToArray()` here - the leading comma + the caller's @() DOUBLE-wraps to `[[{}]]` (also invalid).
    return $rules.ToArray()
}

# The install-level IDENTITY of a package for the "extra shield" duplicate check: the uninstall detection key path
# (full, incl. whether it's the 32-bit hive) + the detection version + the ProductCode. This is what a NON-branded
# pre-existing install (another team / out-of-band) shares even when the name/branding key differs.
function Get-IntuneUninstallSignature {
    param([hashtable]$Fields)
    $keyPath = if ("$($Fields.UninstallKey)".Trim()) { "HKEY_LOCAL_MACHINE\$($Fields.UninstallKey)" } else { '' }
    return @{ KeyPath=$keyPath; ValueName='DisplayVersion'; Is32Bit=[bool]$Fields.Is32Bit; Version="$($Fields.DetectVersion)".Trim(); ProductCode="$($Fields.ProductCode)".Trim() }
}
# PURE: does an existing Intune app's detectionRules match our uninstall SIGNATURE (the 2nd/uninstall detection), and
# does that app carry a VWG\CM branding key? Returns @{ Match; Branded }.
#   Registry (uninstall-string) detection: compare EVERYTHING except the operator (>=/=) and the datatype
#     (detectionType string/version) - i.e. keyPath + valueName + detectionValue (version) + 32/64-bit hive must match.
#   ProductCode (GUID) detection: match the GUID DIRECTLY (a dedicated ProductCode rule, or the {GUID} in the key path).
function Test-IntuneAppMatchesUninstall {
    param($DetectionRules, [hashtable]$Sig)
    $branded = $false; $match = $false
    foreach ($r in @($DetectionRules)) {
        $kp = "$($r.keyPath)"
        if ($kp -match '(?i)\\SOFTWARE\\VWG\\CM\\') { $branded = $true; continue }   # our branding rule - not an identity signal
        $od = "$($r.'@odata.type')"
        if ($od -match '(?i)ProductCodeDetection') {
            if ($Sig.ProductCode -and "$($r.productCode)".Trim() -ieq $Sig.ProductCode) { $match = $true }   # GUID matched directly
            continue
        }
        if ($od -match '(?i)RegistryDetection' -and $kp) {
            $sameKey  = $Sig.KeyPath -and ($kp.TrimEnd('\') -ieq $Sig.KeyPath.TrimEnd('\'))
            $sameName = (-not $Sig.ValueName) -or (-not "$($r.valueName)".Trim()) -or ("$($r.valueName)".Trim() -ieq $Sig.ValueName)  # everything-but-operator/datatype
            $sameBits = ([bool]$r.check32BitOn64System -eq $Sig.Is32Bit)
            $sameVer  = (-not $Sig.Version) -or ("$($r.detectionValue)".Trim() -ieq $Sig.Version)
            if ($sameKey -and $sameName -and $sameBits -and $sameVer) { $match = $true }
            # MSI uninstall key whose {GUID} matches but the hive/prefix differs - still a registry (uninstall-string)
            # detection, so version + 32/64-bit must ALSO match (only a dedicated ProductCode rule matches GUID-alone).
            elseif ($Sig.ProductCode -and $kp -match [regex]::Escape($Sig.ProductCode) -and $sameBits -and $sameVer) { $match = $true }
        }
    }
    return @{ Match=$match; Branded=$branded }
}

function Get-IconBase64 {
    param([string]$PackagePath)
    # Icons folder resolved from ANY path level (root/Content/subfolder) - see Resolve-IconsDir. Passing the Content
    # folder used to miss "<Content>\Icons" (Icons is at the package ROOT), which LOST the app icon on a content update.
    $iconDir = if (Get-Command Resolve-IconsDir -ErrorAction SilentlyContinue) { Resolve-IconsDir -PackagePath $PackagePath } else { Join-Path $PackagePath 'Icons' }
    if (-not $iconDir -or -not (Test-Path -LiteralPath $iconDir)) { return @{} }
    # Prefer the png that has a MATCHING .ico sibling (same basename) - that pair is guaranteed to be the SAME image
    # (Copy-PackageIcons generates it from the ico), so Intune and ARP/SCCM show the SAME icon. Any other stray png
    # (e.g. screenshots/marketing art lying in the Icons folder) is only a fallback.
    $pngs = @(Get-ChildItem $iconDir -Filter *.png -File -ErrorAction SilentlyContinue)
    $png = $pngs | Where-Object { Test-Path -LiteralPath (Join-Path $iconDir ($_.BaseName + '.ico')) } | Select-Object -First 1
    if (-not $png) { $png = $pngs | Select-Object -First 1 }
    if ($png) { return @{ type='image/png'; value=([Convert]::ToBase64String([IO.File]::ReadAllBytes($png.FullName))) } }
    # No PNG: CONVERT a .ico to real PNG bytes. (Sending raw .ico bytes labelled image/png is what made Graph
    # reject the icon.) WPF's BitmapDecoder handles .ico with BOTH classic BMP and PNG-compressed frames and
    # lets us pick the largest; Icon.ToBitmap() chokes on PNG frames, so we avoid it. System.Drawing
    # Bitmap(path) is the fallback if WPF is unavailable.
    $ico = Get-ChildItem $iconDir -Filter *.ico -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ico) {
        try {
            Add-Type -AssemblyName PresentationCore, WindowsBase -ErrorAction Stop
            $fs = [IO.File]::OpenRead($ico.FullName)
            try {
                $dec   = [System.Windows.Media.Imaging.BitmapDecoder]::Create($fs, 'None', 'Default')
                $frame = $dec.Frames | Sort-Object PixelWidth -Descending | Select-Object -First 1
                $enc   = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($frame))
                $ms = New-Object System.IO.MemoryStream; $enc.Save($ms); $bytes = $ms.ToArray(); $ms.Dispose()
                Write-Log "Intune: converted icon $($ico.Name) -> PNG ($($frame.PixelWidth)px) for the app icon."
                return @{ type='image/png'; value=([Convert]::ToBase64String($bytes)) }
            } finally { $fs.Close() }
        } catch {
            try {
                Add-Type -AssemblyName System.Drawing -ErrorAction Stop
                $bmp = New-Object System.Drawing.Bitmap($ico.FullName); $ms = New-Object System.IO.MemoryStream
                $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $bytes = $ms.ToArray(); $ms.Dispose(); $bmp.Dispose()
                Write-Log "Intune: converted icon $($ico.Name) -> PNG (fallback) for the app icon."
                return @{ type='image/png'; value=([Convert]::ToBase64String($bytes)) }
            } catch { Write-Log "Intune: could not convert .ico to PNG ($($_.Exception.Message)); creating the app without an icon (not fatal)." Warning; return @{} }
        }
    }
    return @{}
}

# --- Create the Win32 app (no assignment). Returns @{ Ok; Message; AppId }. -------------------
function New-IntuneApp {
    param([Parameter(Mandatory)][hashtable]$Fields, [Parameter(Mandatory)][string]$LocalPackagePath)
    $cfg = Get-IntuneConfig
    $appId = $null; $iw = $null
    try {
        Set-PbProgress -Indeterminate -Status 'Connecting to Intune (sign in if prompted)...'
        if (-not (Connect-Intune)) { return @{ Ok=$false; Message='Could not connect to Intune (Graph).' } }
        # DUPLICATE GUARD: Intune allows several apps with the same name in parallel, so check BEFORE creating.
        # Match by the BRANDING identity only (fileName '<FullName>.intunewin' / detection key ...\VWG\CM\<FullName>)
        # - never by display name. The GUI asks the user whether to create another copy (ForceCreate skips this).
        if (-not $Fields.ForceCreate) {
            Set-PbProgress -Indeterminate -Status 'Checking whether this app already exists in Intune...'
            $dups = @(); try { $dups = @(Get-IntuneBrandingMatches -DisplayName $Fields.FullName) } catch {}
            if ($dups.Count) {
                Write-Log "Intune: '$($Fields.FullName)' already exists ($($dups.Count) copy/copies by branding key) - asking before creating a duplicate." Warning
                $lines = @($dups | ForEach-Object { "  - '$($_.displayName)'  (AppId $($_.id))  -  lifecycle: $(Get-IntuneAppLifecycle -App $_);  created $($_.createdDateTime)" })
                return @{ Ok=$false; AlreadyExists=$true; AppId="$($dups[0].id)"
                          Message="'$($Fields.FullName)' ALREADY EXISTS in Intune - $($dups.Count) copy/copies matched by branding key:`r`n$($lines -join "`r`n")`r`nNothing was created." }
            }
            # EXTRA SHIELD: no branding-key duplicate, but one or MORE apps with the SAME uninstall detection (key path
            # incl. 32/64-bit + version, or ProductCode) may already exist (another team / out-of-band / a differently
            # named copy). List them ALL with lifecycle (LIVE/RETIRED) + whether they carry a branding key. The trigger
            # to warn is a NON-branded match (branded ones are already owned by the branding logic - shown for context).
            Set-PbProgress -Indeterminate -Status 'Checking for existing apps with the same uninstall detection...'
            $sigMatches = @(); try { $sigMatches = @(Find-IntuneUninstallMatches -Fields $Fields) } catch { Write-Log "Intune: uninstall-signature shield skipped: $($_.Exception.Message)" Warning }
            if (@($sigMatches | Where-Object { -not $_.Branded }).Count -gt 0) {
                $lines = @($sigMatches | ForEach-Object { "  - '$($_.Name)'  (AppId $($_.Id))  -  lifecycle: $($_.Lifecycle);  branding key: $(if($_.Branded){'yes'}else{'NO'})" })
                return @{ Ok=$false; AlreadyExists=$true; SoftMatch=$true; AppId="$(@($sigMatches | Where-Object { -not $_.Branded })[0].Id)"
                          Message="$(@($sigMatches).Count) app(s) already exist in Intune with the SAME uninstall detection (key path incl. 32/64-bit + version) as this package - at least one has NO branding key, so it may be the same underlying app from another team / tool:`r`n$($lines -join "`r`n")`r`nVERIFY in Intune before creating." }
            }
        }
        $contentFolder = Join-Path $LocalPackagePath 'Content'
        if (-not (Test-Path $contentFolder)) { $contentFolder = $LocalPackagePath }
        # Resolve the actual content root (may be a subfolder like Content\MUL_x64_0001) + PSADT generation.
        $res = Resolve-IntuneContentRoot -ContentFolder $contentFolder
        if (-not $res) {
            return @{ Ok=$false; NoPsadt=$true; Message="No PSADT launcher (Deploy-Application.exe/.ps1 or Invoke-AppDeployToolkit.exe/.ps1) was found under Content. This doesn't look like a PSADT package - integrate it in Intune MANUALLY (set your own setup file + install/uninstall commands)." }
        }
        $wrapRoot = $res.Root; $gen = $res.Generation; $setupFile = $res.SetupFile
        # (v3 ServiceUI staging happens inside New-IntuneWinPackage, on the LOCAL COPY - the source package is untouched.)
        # Install/uninstall commands. The publish fields are SHARED with SCCM, so for a v3 package they carry the SCCM
        # form (Deploy-Application.exe direct) - Intune must ServiceUI-WRAP them (that's why a shared field can't just
        # pass through for v3). A field override is respected but still wrapped for v3; an empty field -> the v3 default.
        $install   = if ("$($Fields.InstallCmd)".Trim())   { "$($Fields.InstallCmd)" }   else { if ($gen -eq 'v3') { $cfg.InstallCmdV3 }   else { $cfg.InstallCmd } }
        $uninstall = if ("$($Fields.UninstallCmd)".Trim()) { "$($Fields.UninstallCmd)" } else { if ($gen -eq 'v3') { $cfg.UninstallCmdV3 } else { $cfg.UninstallCmd } }
        if ($gen -eq 'v3') {
            $install   = ConvertTo-IntuneV3Command $install
            $uninstall = ConvertTo-IntuneV3Command $uninstall
            Write-Log "Intune v3: commands wrapped with ServiceUI -> install: $install ; uninstall: $uninstall"
        }
        Write-Log "Intune: $gen package; wrapping content root '$wrapRoot' (setup: $setupFile)"
        Set-PbProgress -Indeterminate -Status 'Packaging .intunewin...'
        $iw = New-IntuneWinPackage -ContentFolder $wrapRoot -FullName $Fields.FullName -SetupFile $setupFile -Generation $gen
        if (-not $iw) { return @{ Ok=$false; Message='Failed to create .intunewin.' } }

        # Name = the product/app name (e.g. "TestDemo"), NOT the full package folder name - matches the
        # migrator tool, which differentiates versions by displayVersion. Fall back to FullName if missing.
        $appName = if ($Fields.ProductName) { "$($Fields.ProductName)" } else { "$($Fields.FullName)" }
        $body = @{
            '@odata.type'           = '#microsoft.graph.win32LobApp'
            displayName             = $appName
            description             = "$($Fields.Description)"
            publisher               = $Fields.Publisher
            displayVersion          = "$($Fields.Version)"     # the app version (was missing)
            isFeatured              = $false                   # not a featured app (per request)
            fileName                = "$($Fields.FullName).intunewin"
            setupFilePath           = $setupFile
            installCommandLine      = $install
            uninstallCommandLine    = $uninstall
            applicableArchitectures = 'x64,x86'                # All - allow on all systems (exact value the module uses; order matters to Graph)
            minimumSupportedWindowsRelease = $cfg.MinWindowsRelease
            allowAvailableUninstall = $true
            installExperience       = @{ runAsAccount='system'; deviceRestartBehavior='basedOnReturnCode' }
            returnCodes             = @(
                @{ returnCode=0;    type='success' }, @{ returnCode=1707; type='success' },
                @{ returnCode=3010; type='softReboot' }, @{ returnCode=1641; type='hardReboot' },
                @{ returnCode=1618; type='retry' }, @{ returnCode=60012; type='retry' })
            detectionRules          = @(Get-IntuneDetectionRules -Fields $Fields)
            # "notes" records WHO integrated the app (the tool user, from $Fields.Author = Get-AuthorName), not the
            # package's script author - better for reporting. Just the name. Falls back to a live resolve, then generic.
            notes                   = $(if ("$($Fields.Author)".Trim()) { "Created by $($Fields.Author)." }
                                        elseif (Get-Command Get-AuthorName -ErrorAction SilentlyContinue) { "Created by $(Get-AuthorName)." }
                                        else { 'Created by Package Builder.' })
        }
        $icon = Get-IconBase64 -PackagePath $LocalPackagePath
        if ($icon.Count) { $body['largeIcon'] = $icon }

        Write-Log "Intune: creating Win32 app $($Fields.FullName)"
        Set-PbProgress -Percent 12 -Status 'Creating Win32 app...'
        $app = Invoke-Graph POST "$($cfg.GraphBase)/deviceAppManagement/mobileApps" $body
        if (-not $app.id) { return @{ Ok=$false; Message='Create app returned no id.' } }
        $appId = $app.id   # tracked so we can delete it if the content upload fails
        $vid = Set-IntuneAppContent -AppId $appId -IntuneWinPath $iw
        # KEEP the .intunewin + its prepared content locally (do NOT delete) so it can be inspected / re-uploaded.
        Set-PbProgress -Percent 100 -Status 'Done.'
        Write-Log "Intune OK: '$($Fields.FullName)'  AppId=$appId. Kept locally: $iw" Success
        return @{ Ok=$true; AppId=$appId; IntuneWinPath="$iw"; Message="Intune Win32 app '$($Fields.FullName)' created (content v$vid).  AppId: $appId`r`n.intunewin kept at: $iw" }
    } catch {
        $err = $_.Exception.Message
        # Surface the REAL failure in the log (was previously only returned to the GUI label).
        Write-Log "Intune create failed: $err" Error
        try { if ($_.ScriptStackTrace) { Write-Log "Intune fail at: $(( $_.ScriptStackTrace -split "`n" | Select-Object -First 1))" } } catch {}
        # ROLL BACK: if the app shell was created but a later step failed, delete it so there's no
        # orphaned half-created app to remove by hand in the Intune portal. If even the delete fails,
        # SAY SO - the user must know an orphan may be left in the portal.
        $rbNote = ''
        if ($appId) {
            try { Invoke-Graph DELETE "$($cfg.GraphBase)/deviceAppManagement/mobileApps/$appId" | Out-Null; Write-Log "Intune: rolled back partial app $appId." Warning; $rbNote = ' (rolled back - retry is safe, it will create fresh)' }
            catch { Write-Log "Intune: rollback delete of $appId ALSO failed: $($_.Exception.Message)" Error; $rbNote = " (ROLLBACK FAILED - a partial app with id $appId may remain in the Intune portal; delete it there before retrying)" }
        }
        # Keep the .intunewin on failure so it can be uploaded manually (per design) - tell the user where.
        $iwNote = ''
        if ($iw -and (Test-Path $iw)) { $iwNote = "`nThe built .intunewin was KEPT for manual upload: $iw" }
        return @{ Ok=$false; Message="Intune create failed${rbNote}: $err$iwNote" }
    }
}

function Test-IsGuid { param([string]$s) return ("$s" -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') }

function Find-IntuneApp {
    # Resolve an Intune Win32 app. PRIORITY:
    #   1) explicit -AppId (the app's Intune id GUID), or a GUID passed as $DisplayName  -> direct GET.
    #   2) branding-key identity: the package FullName, which is embedded in the app's .intunewin fileName
    #      ("<FullName>.intunewin") and in its branding detection keyPath (...\VWG\CM\<FullName>) - the same
    #      marker the migration tool matches on. Purely Intune, no SCCM.
    #   3) product display name (e.g. TestDemo). Returns the newest match, or $null.
    param([string]$DisplayName, [string]$AppId)
    return (@(Get-IntuneBrandingMatches -DisplayName $DisplayName -AppId $AppId) | Select-Object -First 1)
}

# ALL Win32 apps in the tenant, following @odata.nextLink paging (the list is paged - a >1-page tenant would
# otherwise hide apps and make a duplicate look like it "doesn't exist" / "only one copy").
function Get-IntuneWin32Apps {
    $cfg = Get-IntuneConfig
    $apps = New-Object System.Collections.Generic.List[object]
    $uri = "$($cfg.GraphBase)/deviceAppManagement/mobileApps?`$filter=isof('microsoft.graph.win32LobApp')"
    $guard = 0
    while ($uri -and $guard -lt 200) {
        $guard++
        $r = $null; try { $r = Invoke-Graph GET $uri } catch { break }
        foreach ($a in @($r.value)) { [void]$apps.Add($a) }
        $uri = "$($r.'@odata.nextLink')"
    }
    return $apps.ToArray()
}

# Normalized key for a fuzzy name compare: lowercase, strip non-alphanumeric ('CUBISCAN QbitDB' ~ 'cubiscanqbitdb').
function Get-IntuneNameKey { param([string]$s) return ([regex]::Replace("$s", '[^A-Za-z0-9]', '')).ToLowerInvariant() }

# ALL Intune Win32 apps that carry the branding KEY ...\VWG\CM\<FullName> (there can be several - Intune allows
# duplicate apps in parallel). fileName is NOT used (unreliable - depends on the upload name). Candidates are narrowed
# by a FUZZY app-name match (perf: the branding key check needs a per-app GET), then the EXACT branding key decides
# each match. Returns every copy, newest first, for the caller to list with lifecycle.
function Get-IntuneBrandingMatches {
    param([string]$DisplayName, [string]$AppId)
    $cfg = Get-IntuneConfig
    $id = if (Test-IsGuid $AppId) { $AppId } elseif (Test-IsGuid $DisplayName) { $DisplayName } else { $null }
    if ($id) { try { return @((Invoke-Graph GET "$($cfg.GraphBase)/deviceAppManagement/mobileApps/$id")) } catch { return @() } }
    $name = "$DisplayName"
    if (-not $name) { return @() }
    $all = @(Get-IntuneWin32Apps)
    # Candidate narrowing (the exact branding key below is the real decider - this only limits the per-app GETs):
    # the branding key ...\VWG\CM\<FullName> EMBEDS the version, so any app carrying it was created with the SAME
    # displayVersion (free in the list response). Narrow by VERSION - which is APPNAME-INDEPENDENT, so a copy whose
    # display name was later changed is still caught - OR by a fuzzy appname (belt-and-braces for odd displayVersions).
    $appSeg = if ($name -match '_') { ($name -split '_')[1] } else { $name }
    $appTok = Get-IntuneNameKey $appSeg
    $verWanted = ''
    try { if (Get-Command Parse-PackageName -ErrorAction SilentlyContinue) { $verWanted = "$((Parse-PackageName $name).Version)".Trim() } } catch {}
    $cand = @($all | Where-Object {
        $dv = "$($_.displayVersion)".Trim()
        $dn = Get-IntuneNameKey $_.displayName
        ($verWanted -and ($dv -ieq $verWanted)) -or ($appTok -and $dn -and ($dn.Contains($appTok) -or $appTok.Contains($dn)))
    })
    if ($cand.Count) { Write-Log "Intune: deep-checking $($cand.Count) app(s) (same version or similar name, of $($all.Count)) for the branding key..." }
    $rxKey = "(?i)\\VWG\\CM\\$([regex]::Escape($name))(\\|$)"       # just the KEY (segment) - value/operator ignored
    $acc = New-Object System.Collections.Generic.List[object]
    foreach ($a in $cand) {
        $full = $null; try { $full = Invoke-Graph GET "$($cfg.GraphBase)/deviceAppManagement/mobileApps/$($a.id)" } catch { continue }
        if (@($full.detectionRules) | Where-Object { "$($_.keyPath)" -match $rxKey }) { [void]$acc.Add($full) }
    }
    return @($acc | Sort-Object createdDateTime -Descending)
}

# Lifecycle (LIVE / RETIRED / ...) of an Intune app from its notes JSON ({"...","lifecycle":"RETIRED"}). The team's
# automator writes it there. Returns the raw value (upper-cased) or 'unknown' when absent/unparseable.
function Get-IntuneAppLifecycle {
    param($App)
    $n = "$($App.notes)".Trim()
    if ($n -match '^\s*\{') { try { $j = $n | ConvertFrom-Json; if ("$($j.lifecycle)".Trim()) { return "$($j.lifecycle)".Trim().ToUpper() } } catch {} }
    if ($n -match '(?i)"?lifecycle"?\s*[:=]\s*"?([A-Za-z]+)') { return $Matches[1].ToUpper() }   # loose fallback
    return 'unknown'
}

# EXTRA SHIELD (runs only when the branding-key check found nothing): find EVERY existing Win32 app that has the SAME
# uninstall detection (key path incl. 32/64-bit + version, or ProductCode) as this package - the same underlying app
# the branding+name check can't see (another team / out-of-band / a differently-named copy). Returns the FULL list
# (there can be several), each with { Id; Name; Created; Branded; Lifecycle }. The caller decides: a NON-branded match
# is the trigger to warn; branded ones are listed for context (branding logic already owns them).
# Cost control: detection rules aren't in the list response, so per-app GET is needed - candidates are pre-filtered to
# apps with the SAME displayVersion (or an unset one), since version is part of the match anyway.
function Find-IntuneUninstallMatches {
    param([hashtable]$Fields)
    $out = New-Object System.Collections.Generic.List[object]
    $sig = Get-IntuneUninstallSignature -Fields $Fields
    if (-not $sig.KeyPath -and -not $sig.ProductCode) { return $out.ToArray() }   # nothing to match on
    $cfg = Get-IntuneConfig
    $all = @(Get-IntuneWin32Apps)
    # candidates: same VERSION (appname-independent - the uninstall detection embeds the version) OR a fuzzy appname.
    # OR (not AND) so a copy with a DIFFERENT app name but the same uninstall/version is still caught.
    $wantVer = "$($Fields.Version)".Trim()
    $appTok  = Get-IntuneNameKey "$($Fields.ProductName)"; if (-not $appTok) { $appTok = Get-IntuneNameKey (($('' + $Fields.FullName) -split '_')[1]) }
    $cands = @($all | Where-Object {
        $v = "$($_.displayVersion)".Trim(); $verOk = $wantVer -and ($v -ieq $wantVer)
        $dn = Get-IntuneNameKey $_.displayName; $nameOk = $appTok -and $dn -and ($dn.Contains($appTok) -or $appTok.Contains($dn))
        $verOk -or $nameOk })
    if ($cands.Count) { Write-Log "Intune: uninstall/ProductCode shield - deep-checking $($cands.Count) same-version-or-similar-name app(s) of $($all.Count)..." }
    foreach ($a in $cands) {
        $full = $null; try { $full = Invoke-Graph GET "$($cfg.GraphBase)/deviceAppManagement/mobileApps/$($a.id)" } catch { continue }
        $res = Test-IntuneAppMatchesUninstall -DetectionRules $full.detectionRules -Sig $sig
        if (-not $res.Match) { continue }
        $lc = Get-IntuneAppLifecycle -App $full
        [void]$out.Add([pscustomobject]@{ Id="$($full.id)"; Name="$($full.displayName)"; Created="$($full.createdDateTime)"; Branded=[bool]$res.Branded; Lifecycle=$lc })
        Write-Log "Intune: '$($full.displayName)' (AppId $($full.id)) shares the SAME uninstall detection - branding key: $(if($res.Branded){'yes'}else{'NO'}), lifecycle: $lc." Warning
    }
    # LIVE first, then RETIRED/others; non-branded (the real concern) ahead of branded within each.
    return @($out | Sort-Object @{e={ if($_.Lifecycle -eq 'LIVE'){0}elseif($_.Lifecycle -eq 'RETIRED'){2}else{1} }}, @{e={[int]$_.Branded}}, Name)
}

# Resolve an Azure AD group to its Object ID. Accepts a GUID (used as-is) or a display name (looked up via
# Graph - needs Group/Directory read on the sign-in; if not granted, the caller is told to use the Object ID).
function Resolve-IntuneGroupId {
    param([string]$Group)
    $g = "$Group".Trim()
    if (-not $g) { return @{ Ok=$false; Message='Enter a group name or Object ID.' } }
    if ($g -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { return @{ Ok=$true; Id=$g; Name=$g } }
    $cfg = Get-IntuneConfig; $esc = $g -replace "'","''"
    try {
        $r = Invoke-Graph GET "$($cfg.GraphBase)/groups?`$filter=displayName eq '$esc'&`$select=id,displayName"
        $grp = @($r.value)
        if ($grp.Count -eq 1) { Write-Log "Intune: group '$g' -> $($grp[0].id)"; return @{ Ok=$true; Id="$($grp[0].id)"; Name="$($grp[0].displayName)" } }
        if ($grp.Count -gt 1) { return @{ Ok=$false; Message="More than one group is named '$g' - use its Object ID (GUID) instead." } }
        return @{ Ok=$false; Message="No group named '$g' found (or the sign-in can't read groups). Use the group's Object ID (GUID)." }
    } catch { return @{ Ok=$false; Message="Group name lookup failed ($($_.Exception.Message)). Use the group's Object ID (GUID)." } }
}

# --- Intune assignments (ISOLATED): add / remove ONE group assignment. Never touches the app itself or
#     any OTHER assignment - it only POSTs a new assignment or DELETEs the single matching one. -----------
function Add-IntuneGroupAssignment {
    param([string]$AppName, [Parameter(Mandatory)][string]$Group, [string]$AppId, [ValidateSet('available','required','uninstall')][string]$Intent='available')
    $cfg = Get-IntuneConfig
    Set-PbProgress -Indeterminate -Status 'Connecting to Intune...'
    if (-not (Connect-Intune)) { return @{ Ok=$false; Message='Could not connect to Intune (Graph).' } }
    $app = Find-IntuneApp -DisplayName $AppName -AppId $AppId
    if (-not $app) { return @{ Ok=$false; Message="Application not found in Intune (by App ID or branding key). Nothing changed." } }
    $gr = Resolve-IntuneGroupId -Group $Group; if (-not $gr.Ok) { return @{ Ok=$false; Message=$gr.Message } }
    $GroupId = $gr.Id
    Write-Log "Intune: target app '$($app.displayName)' v$($app.displayVersion) ($($app.id))."
    $base = "$($cfg.GraphBase)/deviceAppManagement/mobileApps/$($app.id)/assignments"
    $existing = @((Invoke-Graph GET $base).value)
    if ($existing | Where-Object { "$($_.target.groupId)" -eq $GroupId -and "$($_.intent)" -eq $Intent }) {
        return @{ Ok=$true; AppId=$app.id; Message="Group $GroupId already has an '$Intent' assignment on '$($app.displayName)' - nothing added." }
    }
    $body = @{ '@odata.type'='#microsoft.graph.mobileAppAssignment'; intent=$Intent
               target  =@{ '@odata.type'='#microsoft.graph.groupAssignmentTarget'; groupId=$GroupId }
               settings=@{ '@odata.type'='#microsoft.graph.win32LobAppAssignmentSettings'; notifications='showAll'; deliveryOptimizationPriority='notConfigured' } }
    Invoke-Graph POST $base $body | Out-Null
    Write-Log "Intune: added '$Intent' assignment of group $GroupId to '$($app.displayName)'." Success
    return @{ Ok=$true; AppId=$app.id; Message="Added '$Intent' assignment of group $GroupId to '$($app.displayName)' v$($app.displayVersion). Other assignments untouched." }
}

function Remove-IntuneGroupAssignment {
    param([string]$AppName, [Parameter(Mandatory)][string]$Group, [string]$AppId, [string]$Intent)
    $cfg = Get-IntuneConfig
    Set-PbProgress -Indeterminate -Status 'Connecting to Intune...'
    if (-not (Connect-Intune)) { return @{ Ok=$false; Message='Could not connect to Intune (Graph).' } }
    $app = Find-IntuneApp -DisplayName $AppName -AppId $AppId
    if (-not $app) { return @{ Ok=$false; Message="Application not found in Intune (by App ID or branding key). Nothing changed." } }
    $gr = Resolve-IntuneGroupId -Group $Group; if (-not $gr.Ok) { return @{ Ok=$false; Message=$gr.Message } }
    $GroupId = $gr.Id
    $base = "$($cfg.GraphBase)/deviceAppManagement/mobileApps/$($app.id)/assignments"
    $hits = @((Invoke-Graph GET $base).value | Where-Object { "$($_.target.groupId)" -eq $GroupId -and (-not $Intent -or "$($_.intent)" -eq $Intent) })
    if (-not $hits) { return @{ Ok=$false; Message="No assignment for group $GroupId found on '$($app.displayName)'." } }
    foreach ($h in $hits) { Invoke-Graph DELETE "$base/$($h.id)" | Out-Null; Write-Log "Intune: removed assignment $($h.id) (intent=$($h.intent)) for group $GroupId." }
    return @{ Ok=$true; AppId=$app.id; Message="Removed $($hits.Count) assignment(s) for group $GroupId from '$($app.displayName)'. Other assignments untouched." }
}

# --- Post-create updates: content, icon, detection. -----------------------------------------
function Update-IntuneContent {
    param([string]$AppName, [string]$AppId, [Parameter(Mandatory)][string]$LocalPackagePath)
    $cfg = Get-IntuneConfig
    try {
        Set-PbProgress -Indeterminate -Status 'Connecting to Intune...'
        if (-not (Connect-Intune)) { return @{ Ok=$false; Message='Could not connect to Intune.' } }
        $app = Find-IntuneApp -DisplayName $AppName -AppId $AppId
        if (-not $app) { return @{ Ok=$false; Message="Application not found in Intune (by App ID or branding key). Nothing changed." } }
        $cf = Join-Path $LocalPackagePath 'Content'; if (-not (Test-Path $cf)) { $cf = $LocalPackagePath }
        # Resolve the real content root (may be a subfolder) + generation; stage v3 utilities. NOTE: content-update
        # keeps the app's EXISTING install/uninstall commands (set at create) - only the wrapped content changes.
        $res = Resolve-IntuneContentRoot -ContentFolder $cf
        if (-not $res) { return @{ Ok=$false; NoPsadt=$true; Message="No PSADT launcher found under Content ($cf) - not a PSADT package. Update this app's content in Intune MANUALLY." } }
        # (v3 ServiceUI staging happens inside New-IntuneWinPackage, on the LOCAL COPY - the source package is untouched.)
        Set-PbProgress -Indeterminate -Status 'Packaging new .intunewin...'
        $iw = New-IntuneWinPackage -ContentFolder $res.Root -FullName (("$($app.fileName)" -replace '\.intunewin$','') -replace '[^\w\.\-]','_') -SetupFile $res.SetupFile -Generation $res.Generation
        if (-not $iw) { return @{ Ok=$false; Message='Failed to repackage .intunewin.' } }
        $vid = Set-IntuneAppContent -AppId $app.id -IntuneWinPath $iw
        # KEEP the repackaged .intunewin + its content locally (do NOT delete).
        # Re-apply the icon: updating content can drop it in Intune, so reintegrate it from the content source.
        $iconMsg = ''
        try {
            $icon = Get-IconBase64 -PackagePath $LocalPackagePath
            if ($icon.Count) { Invoke-Graph PATCH "$($cfg.GraphBase)/deviceAppManagement/mobileApps/$($app.id)" (@{ '@odata.type'='#microsoft.graph.win32LobApp'; largeIcon=$icon }) | Out-Null; $iconMsg=' (icon re-applied)' }
        } catch { Write-Log "Intune: icon re-apply after content update failed: $($_.Exception.Message)" Warning }
        Set-PbProgress -Percent 100 -Status 'Done.'
        return @{ Ok=$true; AppId=$app.id; IntuneWinPath="$iw"; Message="Intune content updated for '$($app.displayName)' (content v$vid)$iconMsg. App settings + assignments untouched.`r`n.intunewin kept at: $iw" }
    } catch { return @{ Ok=$false; Message="Intune update content failed: $($_.Exception.Message)" } }
}
function Update-IntuneIcon {
    param([Parameter(Mandatory)][hashtable]$Fields, [Parameter(Mandatory)][string]$LocalPackagePath)
    try {
        if (-not (Connect-Intune)) { return @{ Ok=$false; Message='Could not connect to Intune.' } }
        $app = Find-IntuneApp -DisplayName $Fields.FullName
        if (-not $app) { return @{ Ok=$false; Message="App not found." } }
        $icon = Get-IconBase64 -PackagePath $LocalPackagePath
        if (-not $icon.Count) { return @{ Ok=$false; Message='No icon found in the package.' } }
        Invoke-Graph PATCH "$($(Get-IntuneConfig).GraphBase)/deviceAppManagement/mobileApps/$($app.id)" (@{ '@odata.type'='#microsoft.graph.win32LobApp'; largeIcon=$icon }) | Out-Null
        return @{ Ok=$true; Message="Intune icon updated for '$($Fields.FullName)'." }
    } catch { return @{ Ok=$false; Message="Intune icon update failed: $($_.Exception.Message)" } }
}
function Update-IntuneDetection {
    param([Parameter(Mandatory)][hashtable]$Fields)
    try {
        if (-not (Connect-Intune)) { return @{ Ok=$false; Message='Could not connect to Intune.' } }
        $app = Find-IntuneApp -DisplayName $Fields.FullName
        if (-not $app) { return @{ Ok=$false; Message="App not found." } }
        Invoke-Graph PATCH "$($(Get-IntuneConfig).GraphBase)/deviceAppManagement/mobileApps/$($app.id)" (@{ '@odata.type'='#microsoft.graph.win32LobApp'; detectionRules=@(Get-IntuneDetectionRules -Fields $Fields) }) | Out-Null
        return @{ Ok=$true; Message="Intune detection rules updated for '$($Fields.FullName)'." }
    } catch { return @{ Ok=$false; Message="Intune detection update failed: $($_.Exception.Message)" } }
}
