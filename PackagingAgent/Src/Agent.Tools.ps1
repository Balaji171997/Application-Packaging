#  =====================================================================================================
#   Agent.Tools.ps1  -  the small free tools the agent drives, and what it asks them.
#
#   These live in PackagingAgent\Tools. Every one of them is OPTIONAL: when a tool is missing the
#   agent says so in the feed, tells the AI which evidence is unavailable, and carries on with less.
#   Nothing here ever decides anything - each function turns a tool's output into plain facts, and
#   the AI reads those facts and makes the call.
#
#   This lives in Src\ because that is where the agent's own behaviour belongs. (Engine\ used to be
#   overwritten by a sync script, which is why nothing was ever written there; that script is gone and
#   Engine\ is the agent's own code now - but new agent behaviour still belongs here.)
#
#     7z.exe / 7z.dll     names the installer technology and extracts without running it
#     DTF dll             MSI/MST/MSP reading, and proving a transform applies before handover
#     autorunsc.exe       every autostart point - which is where the auto-updater actually lives
#     Procmon64.exe       what the installer really did, including child process command lines
#  =====================================================================================================

function Get-AgentToolsFolder {
    # The Tools folder sits next to Src, under the agent home.
    foreach ($c in @(
        $(if ($script:AgentHome) { Join-Path $script:AgentHome 'Tools' }),
        $(if ($script:AgentSrc) { Join-Path (Split-Path -Parent $script:AgentSrc) 'Tools' }),
        $(if ($script:AgentToolRoot) { Join-Path (Split-Path -Parent $script:AgentToolRoot) 'Tools' })
    )) {
        if ($c -and (Test-Path -LiteralPath $c)) { return (Get-Item -LiteralPath $c).FullName }
    }
    return $null
}

# Files copied from another machine or downloaded with a browser carry a Zone.Identifier stream, and
# .NET flatly refuses to load a DLL that has one - it fails with 0x80131515 "Operation is not
# supported", which says nothing about the real cause. Clearing it costs nothing and saves an hour.
function Unblock-AgentTools {
    param([string]$Folder)
    if (-not $Folder -or -not (Test-Path -LiteralPath $Folder)) { return }
    try { Get-ChildItem -LiteralPath $Folder -File -ErrorAction Stop | Unblock-File -ErrorAction SilentlyContinue } catch {}
}

function Initialize-AgentTools {
    <#
      Finds the tools once per session and records what is available. Safe to call repeatedly.
      Returns the inventory; also publishes $script:ArchiveTool so the engine's own
      Get-ArchiveTool / Find-BundledMsi / Expand-BundledMsi light up with no changes to Engine.
    #>
    param([switch]$Force)
    if ($script:AgentTools -and -not $Force) { return $script:AgentTools }

    $folder = Get-AgentToolsFolder
    Unblock-AgentTools -Folder $folder
    $inv = [ordered]@{ folder = $folder; sevenZip = $null; dtf = $null; autoruns = $null; procmon = $null; notes = @() }

    $find = {
        param($names)
        foreach ($n in $names) {
            if ($folder) { $p = Join-Path $folder $n; if (Test-Path -LiteralPath $p) { return $p } }
        }
        foreach ($n in $names) { try { $c = Get-Command $n -ErrorAction Stop; if ($c.Source) { return $c.Source } } catch {} }
        return $null
    }

    # ---- 7-Zip -------------------------------------------------------------------------------------
    $inv.sevenZip = & $find @('7z.exe', '7za.exe')
    if (-not $inv.sevenZip) {
        foreach ($p in @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) { if (Test-Path -LiteralPath $p) { $inv.sevenZip = $p; break } }
    }
    if ($inv.sevenZip) {
        # Reuse, not duplication: the engine caches its archive tool here, so every engine function
        # that wanted 7-Zip now has it.
        $script:ArchiveTool = $inv.sevenZip
    } else {
        $inv.notes += 'no 7-Zip: cannot name the installer technology from the file, and cannot extract without running the installer'
    }

    # ---- WiX DTF (managed MSI API) -----------------------------------------------------------------
    $already = @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Microsoft.Deployment.WindowsInstaller' })
    if ($already.Count) {
        $inv.dtf = 'loaded'
    } else {
        $dll = & $find @('Microsoft.Deployment.WindowsInstaller.dll', 'WixToolset.Dtf.WindowsInstaller.dll')
        if ($dll) {
            try { Add-Type -LiteralPath $dll -ErrorAction Stop; $inv.dtf = $dll }
            catch { $inv.notes += "the MSI library would not load ($($_.Exception.Message.Split([char]10)[0])) - falling back to the COM API" }
        } else {
            $inv.notes += 'no MSI library: MSI reads fall back to the COM API, and a transform cannot be proven to apply'
        }
    }

    # ---- Sysinternals ------------------------------------------------------------------------------
    $inv.autoruns = & $find @('autorunsc64.exe', 'autorunsc.exe')
    if (-not $inv.autoruns) { $inv.notes += 'no autorunsc: the auto-update mechanism has to be found by hand' }
    $inv.procmon = & $find @($(if ([Environment]::Is64BitOperatingSystem) { 'Procmon64.exe' } else { 'Procmon.exe' }), 'Procmon.exe')
    if (-not $inv.procmon) { $inv.notes += 'no Process Monitor: cannot see the child processes an installer launched' }

    $script:AgentTools = $inv
    return $inv
}

function Get-AgentToolInventory {
    # The same facts, shaped for the AI and for the feed: what is available and what each one buys.
    $t = Initialize-AgentTools
    return [ordered]@{
        installerInspection = $(if ($t.sevenZip) { 'available (7-Zip): the installer technology can be read from the file, and named entries extracted without running it. NOTE it has no handler for Inno Setup, Wise or InstallShield - those read as a bare PE, and the answer for them is to run the installer and watch.' } else { 'NOT available - route choice must rest on the documents and the installer help text' })
        msiLibrary          = $(if ($t.dtf) { 'available (WiX DTF): MSI properties and tables read reliably, and a transform can be PROVEN to apply to this MSI before handover' } else { 'NOT available - MSI reads use the COM API, and a transform cannot be verified' })
        autostartScan       = $(if ($t.autoruns) { 'available (autorunsc): every service, scheduled task and Run key, so the auto-updater is found rather than guessed at' } else { 'NOT available' })
        processTrace        = $(if ($t.procmon) { 'available (Process Monitor, needs elevation): the child processes the installer launched and their exact command lines' } else { 'NOT available' })
        limitations         = @($t.notes)
    }
}

#  ---------------------------------------------------------------------------------------------------
#   Running one of the tools. Always with a timeout and always without a window: a 4 GB installer can
#   keep 7-Zip busy for a minute, and a hung tool must never take the console with it.
#  ---------------------------------------------------------------------------------------------------
function Invoke-AgentToolProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 180
    )
    $res = [ordered]@{ exitCode = $null; output = @(); seconds = 0; timedOut = $false; error = '' }
    $so = [IO.Path]::GetTempFileName(); $se = [IO.Path]::GetTempFileName()
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru `
                           -RedirectStandardOutput $so -RedirectStandardError $se -ErrorAction Stop
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            $res.timedOut = $true
            try { $p.Kill() } catch {}
            try { $p.WaitForExit(5000) | Out-Null } catch {}
        } else {
            $res.exitCode = $p.ExitCode
        }
    } catch {
        $res.error = $_.Exception.Message.Split([char]10)[0]
    }
    $sw.Stop(); $res.seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    # Get-Content, deliberately: these tools disagree on encoding (autorunsc writes UTF-16 with a BOM, 7-Zip does not)
    # and Get-Content detects the BOM. Decoding by hand got the columns right and the CSV wrong, which is worse.
    try { $res.output = @(Get-Content -LiteralPath $so -ErrorAction SilentlyContinue) } catch {}
    if (-not $res.error) { try { $e = (Get-Content -LiteralPath $se -Raw -ErrorAction SilentlyContinue); if ($e) { $res.error = $e.Trim() } } catch {} }
    foreach ($f in @($so, $se)) { try { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } catch {} }
    return $res
}

#  ---------------------------------------------------------------------------------------------------
#   What is this installer, and what is inside it?
#
#   This replaces a byte scan that read the whole file looking for an MSI signature. Measured over
#   eight real deliveries of 1.8-3.9 GB, that scan cost 86-113 seconds each and found nothing in all
#   eight. 7-Zip reads the headers instead: 0.4-63 seconds on the same files, and on one of them
#   (RevitCoreEngine_2026.exe) it listed three MSIs the byte scan had missed entirely.
#
#   What it CANNOT do, so that nobody reads too much into a quiet answer: there is no handler for
#   Inno Setup, Wise or InstallShield. Those come back as a bare 'PE' with nothing listed, and the
#   only honest answer for them is to run the installer and watch.
#  ---------------------------------------------------------------------------------------------------
function Get-AgentArchiveInsight {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$TimeoutSeconds = 180,
        [int]$MaxEntriesReported = 60
    )
    $res = [ordered]@{
        installer = $(if ($Path) { Split-Path -Leaf $Path } else { '' })
        readBy = 'not read'; technology = 'unknown'; entryCount = 0
        msiCandidates = @(); mspCandidates = @(); notableEntries = @()
        seconds = 0; note = ''
    }
    if (-not (Test-Path -LiteralPath $Path)) { $res.note = 'the installer is not reachable'; return $res }
    $t = Initialize-AgentTools
    if (-not $t.sevenZip) { $res.note = 'no archive tool is available, so the file itself cannot be inspected - the installer technology has to come from the documents, the file version resource, or the run'; return $res }

    $r = Invoke-AgentToolProcess -FilePath $t.sevenZip -Arguments @('l', '-slt', '-ba', "$((Get-Item -LiteralPath $Path).FullName)") -TimeoutSeconds $TimeoutSeconds
    $res.seconds = $r.seconds
    $res.readBy = '7-Zip'
    if ($r.timedOut) { $res.note = "the listing did not finish within $TimeoutSeconds seconds, so nothing can be concluded from it"; return $res }

    # 'Type = ...' appears in the header; with -ba we may not get it, so ask separately and cheaply.
    $h = Invoke-AgentToolProcess -FilePath $t.sevenZip -Arguments @('l', "$((Get-Item -LiteralPath $Path).FullName)") -TimeoutSeconds $TimeoutSeconds
    $typeLine = @($h.output | Where-Object { $_ -match '^Type\s*=\s*(.+)$' } | Select-Object -First 1)
    if ($typeLine.Count) { $res.technology = ([regex]::Match($typeLine[0], '^Type\s*=\s*(.+)$').Groups[1].Value).Trim() }

    $paths = @($r.output | Where-Object { $_ -match '^Path\s*=\s*(.+)$' } | ForEach-Object { ([regex]::Match($_, '^Path\s*=\s*(.+)$').Groups[1].Value).Trim() })
    $res.entryCount = $paths.Count
    $res.msiCandidates = @($paths | Where-Object { $_ -match '(?i)\.msi$' })
    $res.mspCandidates = @($paths | Where-Object { $_ -match '(?i)\.msp$' })
    $res.notableEntries = @($paths | Where-Object { $_ -match '(?i)(setup\.exe|install\.exe|\.cab$|\.jar$|\.properties$|silent|response|\.iss$|\.xml$|\.json$)' } | Select-Object -First $MaxEntriesReported)

    if ($res.entryCount -eq 0) {
        $res.note = if ($res.technology -eq 'PE' -or $res.technology -eq 'unknown') {
            'nothing could be listed. 7-Zip has no handler for Inno Setup, Wise or InstallShield, so this may simply be one of those - it does NOT mean the installer contains no MSI. The run is what settles it.'
        } else { "the file reads as '$($res.technology)' but no entries were listed" }
    } elseif ($res.msiCandidates.Count) {
        $res.note = "$($res.msiCandidates.Count) MSI(s) are inside this installer. Which - if any - is the application itself is not decided here: extract and read them."
    } else {
        $res.note = "listed $($res.entryCount) entries and none is an MSI"
    }
    return $res
}

function Expand-AgentArchiveEntries {
    # Pull named entries out of an installer without running it. Paths are preserved, so two MSIs of
    # the same name in different folders do not overwrite each other.
    param(
        [Parameter(Mandatory)][string]$Path,
        # NOT mandatory on purpose: an empty array makes PowerShell treat a mandatory parameter as missing and
        # prompt for it, which in a background runspace hangs. Better to accept it and answer honestly.
        [string[]]$Entries = @(),
        [Parameter(Mandatory)][string]$Destination,
        [int]$TimeoutSeconds = 900
    )
    $res = [ordered]@{ extracted = @(); seconds = 0; note = '' }
    $t = Initialize-AgentTools
    if (-not $t.sevenZip) { $res.note = 'no archive tool is available'; return $res }
    if (-not (Test-Path -LiteralPath $Path)) { $res.note = 'the installer is not reachable'; return $res }
    if (-not @($Entries).Count) { $res.note = 'nothing was asked for'; return $res }
    try { New-Item -ItemType Directory -Force -Path $Destination -ErrorAction Stop | Out-Null } catch { $res.note = "cannot write to $Destination"; return $res }

    $args = @('x', "$((Get-Item -LiteralPath $Path).FullName)", "-o$Destination", '-y') + @($Entries)
    $r = Invoke-AgentToolProcess -FilePath $t.sevenZip -Arguments $args -TimeoutSeconds $TimeoutSeconds
    $res.seconds = $r.seconds
    if ($r.timedOut) { $res.note = "extraction did not finish within $TimeoutSeconds seconds"; return $res }
    $res.extracted = @(Get-ChildItem -LiteralPath $Destination -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    if (-not $res.extracted.Count) { $res.note = "nothing came out (7-Zip exit $($r.exitCode))$(if ($r.error) { ': ' + $r.error.Split([char]10)[0] })" }
    return $res
}

#  ---------------------------------------------------------------------------------------------------
#   An MSI found inside a wrapper is only worth packaging if it IS the application. The trap is real:
#   RevitCoreEngine_2026.exe carries three MSIs, and one of them is Microsoft SQL Server 2019 LocalDB
#   - a prerequisite that must not be uninstalled and is certainly not the application.
#
#   So: extract the candidates, read each one's identity, and report how well it matches the order.
#   The comparison fields are facts. The route decision is the AI's.
#  ---------------------------------------------------------------------------------------------------
function Get-AgentTokenSet {
    param([string]$Text)
    if (-not $Text) { return @() }
    $norm = ($Text -replace '(?i)\b(setup|install(er)?|x64|x86|win(32|64)?|core|engine|edition|version|professional|enterprise|standard)\b', ' ') -replace '[^A-Za-z0-9]+', ' '
    return @($norm.ToLowerInvariant().Split(' ') | Where-Object { $_.Length -ge 3 } | Select-Object -Unique)
}

function Test-AgentNamesOverlap {
    param([string]$A, [string]$B)
    $x = Get-AgentTokenSet $A; $y = Get-AgentTokenSet $B
    if (-not $x.Count -or -not $y.Count) { return $false }
    return @($x | Where-Object { $y -contains $_ }).Count -gt 0
}

# One MSI, identified: what it really is, whether it can stand on its own, how well it matches the order. Facts only.
function Get-AgentMsiCandidateRecord {
    param([Parameter(Mandatory)][string]$Path, [string]$ExpectedName, [string]$ExpectedVersion, [string]$ExpectedVendor, [string]$HowObtained = '')
    $id = Get-AgentMsiIdentity -Path $Path
    $sizeMb = 0; try { $sizeMb = [math]::Round((Get-Item -LiteralPath $Path).Length / 1MB, 1) } catch {}
    if (-not $id) { return [ordered]@{ file = (Split-Path -Leaf $Path); path = $Path; sizeMB = $sizeMb; readable = $false; howObtained = $HowObtained; note = 'the MSI could not be read' } }
    return [ordered]@{
        file = (Split-Path -Leaf $Path); path = $Path; sizeMB = $sizeMb; readable = $true; howObtained = $HowObtained
        productName = $id.productName; productVersion = $id.productVersion
        productCode = $id.productCode; manufacturer = $id.manufacturer
        selfContained = $id.selfContained
        externalCabs = @($id.externalCabs)
        standsAloneNote = $(if ($id.selfContained) { 'this MSI carries its own payload, so it can be packaged on its own' } else { "this MSI references $(@($id.externalCabs).Count) external cabinet file(s) - it CANNOT be packaged on its own; whatever sat beside it has to travel with it" })
        nameOverlapsOrder = (Test-AgentNamesOverlap $id.productName $ExpectedName)
        manufacturerOverlapsVendor = (Test-AgentNamesOverlap $id.manufacturer $ExpectedVendor)
        versionMatchesOrder = $(if ($ExpectedVersion -and $id.productVersion) { [bool]($id.productVersion -like "$ExpectedVersion*" -or $ExpectedVersion -like "$($id.productVersion)*") } else { $null })
    }
}

function Get-AgentExtractedMsiFacts {
    <#
      Extracts the MSI candidates from an installer and identifies each one. Returns one record per
      MSI with its real identity and plain comparison fields against what the order says. No verdict.
    #>
    param(
        [Parameter(Mandatory)][string]$InstallerPath,
        [string]$ExpectedName,
        [string]$ExpectedVersion,
        [string]$ExpectedVendor,
        [string]$WorkFolder,
        [int]$MaxCandidates = 6,
        [int]$TimeoutSeconds = 900
    )
    $out = [ordered]@{ installer = (Split-Path -Leaf $InstallerPath); candidates = @(); note = ''; seconds = 0 }
    $insight = Get-AgentArchiveInsight -Path $InstallerPath
    if (-not @($insight.msiCandidates).Count) { $out.note = "no MSI could be listed inside this installer - $($insight.note)"; return $out }

    if (-not $WorkFolder) { $WorkFolder = Join-Path ([IO.Path]::GetTempPath()) ("agent-extract-" + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
    $want = @($insight.msiCandidates | Select-Object -First $MaxCandidates)
    $ex = Expand-AgentArchiveEntries -Path $InstallerPath -Entries $want -Destination $WorkFolder -TimeoutSeconds $TimeoutSeconds
    $out.seconds = $ex.seconds
    if (-not @($ex.extracted).Count) { $out.note = "the MSI(s) are listed but could not be extracted - $($ex.note)"; return $out }

    $recs = @()
    foreach ($f in @($ex.extracted | Where-Object { $_ -match '(?i)\.msi$' })) {
        $recs += (Get-AgentMsiCandidateRecord -Path $f -ExpectedName $ExpectedName -ExpectedVersion $ExpectedVersion -ExpectedVendor $ExpectedVendor)
    }
    $out.candidates = @($recs)
    $out.note = "$(@($recs).Count) MSI(s) extracted and identified. Compare each one against the order: an MSI whose name and vendor match the application is a candidate to package instead of the wrapper; one from a different vendor is a bundled prerequisite and must not be treated as the application."
    return $out
}

#  ===================================================================================================
#   CONFIGURATION AFTER INSTALL
#
#   Installing the application is half the job. The other half is the settings a deployed package has to
#   apply on its own: the auto-updater switched off, the "may we send your usage data to us?" box never
#   shown, the first-run wizard skipped, a licence server written down. None of that is reliably
#   reachable from an install switch, and none of it can be guessed from the application's name.
#
#   So the tool gathers the raw material and the AI decides:
#     - every autostart point the install created (autorunsc)         <- that IS the updater
#     - the registry VALUES it wrote, with their contents
#     - the configuration FILES it created, with their text
#     - what the application writes on FIRST RUN, which is where the prompts keep their state
#  ===================================================================================================

function Get-AgentAutostartFacts {
    <#
      Every service, scheduled task and Run-key entry on the machine, from autorunsc. Pass -Baseline
      (an earlier call) to get only what appeared since - which is what the install created.
      Free of charge in under ten seconds, and it does not need elevation.
    #>
    param($Baseline, [int]$TimeoutSeconds = 120)
    $res = [ordered]@{ readBy = 'not read'; services = @(); tasks = @(); logon = @(); note = ''; seconds = 0 }
    $t = Initialize-AgentTools
    if (-not $t.autoruns) { $res.note = 'autorunsc is not available, so the auto-updater has to be found by hand in the snapshot'; return $res }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $sets = @(@{ key = 'services'; flag = 's' }, @{ key = 'tasks'; flag = 't' }, @{ key = 'logon'; flag = 'l' })
    foreach ($set in $sets) {
        $r = Invoke-AgentToolProcess -FilePath $t.autoruns -Arguments @('-accepteula', '-nobanner', '-a', $set.flag, '-c') -TimeoutSeconds $TimeoutSeconds
        $rows = New-Object System.Collections.Generic.List[object]
        # autorunsc -c writes real CSV, and service descriptions are full of commas - splitting on ',' shifts every
        # column after the first long description and hands the AI a company name that is really half a sentence.
        # Let ConvertFrom-Csv do the quoting properly, and read the columns by name.
        $csv = @()
        try { $csv = @(@($r.output) | Where-Object { "$_".Trim() } | ConvertFrom-Csv) } catch {}
        foreach ($row in $csv) {
            $get = { param($names) foreach ($n in $names) { $pv = $row.PSObject.Properties[$n]; if ($pv -and "$($pv.Value)".Trim()) { return "$($pv.Value)".Trim() } } return '' }
            $entry = & $get @('Entry')
            if (-not $entry) { continue }
            $rows.Add([ordered]@{
                location = (& $get @('Entry Location'))
                entry = $entry
                enabled = (& $get @('Enabled'))
                description = (& $get @('Description'))
                company = (& $get @('Company'))
                image = (& $get @('Image Path'))
                launch = (& $get @('Launch String'))
            })
        }
        $res[$set.key] = @($rows.ToArray())
    }
    $sw.Stop(); $res.seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $res.readBy = 'autorunsc'

    if ($Baseline -and "$($Baseline.readBy)" -eq 'autorunsc') {
        foreach ($k in 'services', 'tasks', 'logon') {
            $was = @{}
            foreach ($o in @($Baseline.$k)) { $was["$($o.location)|$($o.entry)"] = $true }
            $res[$k] = @(@($res[$k]) | Where-Object { -not $was["$($_.location)|$($_.entry)"] })
        }
        $res.note = "only what appeared since the baseline: $(@($res.services).Count) service(s), $(@($res.tasks).Count) task(s), $(@($res.logon).Count) logon entr(ies). Anything here was created by this install."
    } else {
        $res.note = "the whole machine: $(@($res.services).Count) service(s), $(@($res.tasks).Count) task(s), $(@($res.logon).Count) logon entr(ies). Take a baseline before installing to see only what the install adds."
    }
    return $res
}

# Names that suggest a setting rather than a file path or a version string. Used only to decide what is worth
# SHOWING the AI - never to decide anything. A value that does not match is still in the snapshot.
$script:AgentPreferenceWords = 'updat|upgrade|telemetry|usage|statistic|metric|analytic|survey|feedback|marketing|advertis|promo|firstrun|first_run|firststart|welcome|wizard|tour|eula|licen[cs]e.?accept|accept(ed)?terms|optin|opt_in|optout|privacy|crash|errorreport|senddata|datacollect|improve|experiment|notif|popup|prompt|checkfor|autostart|autorun|startup|registration|activat'

function Get-AgentConfigFileFacts {
    <#
      The configuration files an install created, with their text. A setting the package has to change lives in
      one of these as often as in the registry, and its real name can only be read - never guessed.
      Small text files only; binaries and big data files are named but not read.
    #>
    param(
        [string[]]$Roots = @(),
        [int]$MaxFiles = 40,
        [long]$MaxBytesEach = 256KB,
        [int]$MaxCharsEach = 3000
    )
    $out = New-Object System.Collections.Generic.List[object]
    $exts = '.xml', '.json', '.ini', '.cfg', '.conf', '.config', '.properties', '.yml', '.yaml', '.toml', '.reg', '.js', '.txt'
    foreach ($root in @($Roots | Where-Object { "$_".Trim() })) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $files = @()
        try { $files = @(Get-ChildItem -LiteralPath $root -File -Recurse -Depth 5 -ErrorAction SilentlyContinue | Where-Object { $exts -contains $_.Extension.ToLower() }) } catch {}
        foreach ($f in @($files | Sort-Object Length | Select-Object -First $MaxFiles)) {
            if ($out.Count -ge $MaxFiles) { break }
            $rec = [ordered]@{ path = $f.FullName; sizeKB = [math]::Round($f.Length / 1KB, 1); text = ''; preferenceLines = @(); note = '' }
            if ($f.Length -gt $MaxBytesEach) { $rec.note = 'too large to read here - named only'; $out.Add($rec); continue }
            $txt = ''
            try { $txt = [IO.File]::ReadAllText($f.FullName) } catch { $rec.note = 'could not be read'; $out.Add($rec); continue }
            if ($txt -match "[\x00-\x08\x0E-\x1F]") { $rec.note = 'looks binary - not read'; $out.Add($rec); continue }
            $rec.preferenceLines = @(@($txt -split "`r?`n") | Where-Object { $_ -match "(?i)$script:AgentPreferenceWords" } | Select-Object -First 25 | ForEach-Object { $_.Trim() })
            $rec.text = $(if ($txt.Length -gt $MaxCharsEach) { $txt.Substring(0, $MaxCharsEach) + "`n...(truncated)" } else { $txt })
            $out.Add($rec)
        }
    }
    return @($out.ToArray())
}

function Get-AgentSettingCandidates {
    <#
      Pulls the settings-looking material out of an install's own footprint and puts it in front of the AI:
      the registry values it wrote (read back in full), the configuration files it created, and the autostart
      entries that appeared. Everything here is observation. Which of it matters, and what to change it to,
      is the AI's call - the shape of that answer is `configurationPlan`.
    #>
    param(
        $RegDiff,                 # the snapshot's registry diff
        [string[]]$InstallRoots = @(),
        $Autostart,               # output of Get-AgentAutostartFacts (ideally baselined)
        [int]$MaxKeys = 40
    )
    $res = [ordered]@{ registryValues = @(); configFiles = @(); autostart = $null; note = '' }

    # Registry: the diff gives KEYS; a setting is a VALUE, so read them back. Reuse the engine's reader.
    if ($RegDiff -and (Get-Command Get-SnapshotRegValuesFor -ErrorAction SilentlyContinue)) {
        $keys = @(@($RegDiff.New) + @($RegDiff.Modified) | ForEach-Object { "$(if ($_.Path) { $_.Path } else { $_ })" } | Where-Object { $_ } | Select-Object -Unique -First $MaxKeys)
        foreach ($k in $keys) {
            $vals = @()
            try { $vals = @(Get-SnapshotRegValuesFor -KeyPath $k -Max 40) } catch {}
            if (-not $vals.Count) { continue }
            $looks = @($vals | Where-Object { "$($_.Name)" -match "(?i)$script:AgentPreferenceWords" -or "$($_.Value)" -match '(?i)^(0|1|true|false|yes|no|enabled|disabled)$' })
            $res.registryValues += , [ordered]@{ key = $k; values = @($vals); settingLikeValues = @($looks) }
        }
    }
    $res.configFiles = @(Get-AgentConfigFileFacts -Roots $InstallRoots)
    $res.autostart = $Autostart
    $res.note = "$(@($res.registryValues).Count) registry key(s) read back with their values, $(@($res.configFiles).Count) configuration file(s) read, $(if ($Autostart) { "$(@($Autostart.services).Count) service(s) / $(@($Autostart.tasks).Count) task(s) / $(@($Autostart.logon).Count) logon entr(ies)" } else { 'no autostart scan' }). The `settingLikeValues` and `preferenceLines` are only a shortlist to look at first - the full values and file text are here too, and the real setting is sometimes named nothing like 'update'."
    return $res
}

#  ===================================================================================================
#   MEMORY - what the packager has told us, kept for next time
#
#   A packaging engineer who has been here fifteen years does not re-learn the same thing every morning.
#   When somebody says "this vendor's EXE always needs the wrapper" or "we never remove that runtime",
#   that answer should still be there next month, on the next version, on the next package.
#
#   So the agent keeps a small memory beside itself and sends the relevant part with every call.
#   WHAT goes in is the AI's decision (it calls remember_this) or the packager's own words when they
#   answer a question. The tool only stores and retrieves - it does not judge what is worth keeping.
#
#   Scope decides when it comes back: global (always), vendor:<name>, or package:<name>.
#  ===================================================================================================
# THE MEMORY LIVES WITH THE AGENT, NOT IN THE WORK FOLDER.
# What this file holds is TRAINING MATERIAL: everything this team has taught the agent about packaging, one hard-won
# sentence at a time. A work folder is scratch space that gets cleared; this has to outlive runs, machines, and the
# model itself. If the API or the model is swapped tomorrow, this file is what teaches the new one how we work - so
# it sits in Knowledge\, beside the installer playbook, and is versioned with the agent.
function Get-AgentMemoryPath {
    # NOT $home - that is a PowerShell automatic variable and it is read-only; assigning to it throws.
    $agentRoot = "$script:AgentHome"
    if (-not "$agentRoot".Trim()) { $agentRoot = Join-Path $env:TEMP 'PackagingAgent' }
    $dir = Join-Path $agentRoot 'Knowledge'
    if (-not (Test-Path -LiteralPath $dir)) { try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch {} }
    $path = Join-Path $dir 'Experience.json'
    # Anything recorded before this moved lives in the old work-folder file - bring it across once, so nothing the
    # packager took the trouble to say is lost.
    if (-not (Test-Path -LiteralPath $path)) {
        try {
            $old = Join-Path (Get-WorkPath 'AI') 'memory.json'
            if (Test-Path -LiteralPath $old) {
                Copy-Item -LiteralPath $old -Destination $path -Force -ErrorAction Stop
                Write-Log "Experience: carried $(@((Get-Content $old -Raw | ConvertFrom-Json)).Count) earlier note(s) over from the work folder into Knowledge\Experience.json." Info
            }
        } catch {}
    }
    return $path
}

function Get-AgentMemoryAll {
    $p = Get-AgentMemoryPath
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    try {
        $raw = Get-Content -LiteralPath $p -Raw -ErrorAction Stop
        if (-not "$raw".Trim()) { return @() }
        # PS 5.1: assign first, then flatten - piping ConvertFrom-Json straight into @() wraps the array
        $parsed = $raw | ConvertFrom-Json
        return @($parsed)
    } catch { return @() }
}

function Add-AgentMemory {
    <#
      Record something worth remembering. Returns what was stored, so the caller can show it.
      Scope: 'global' | 'vendor:<name>' | 'package:<name>'. Source: who said it.
    #>
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Scope = 'global',
        [string]$Why = '',
        [string]$Source = 'packager',
        [int]$MaxEntries = 400
    )
    $t = "$Text".Trim()
    if (-not $t) { return $null }
    $entry = [ordered]@{
        at = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        scope = $(if ("$Scope".Trim()) { "$Scope".Trim() } else { 'global' })
        text = $t
        why = "$Why".Trim()
        source = $(if ("$Source".Trim()) { "$Source".Trim() } else { 'packager' })
    }
    $all = @(Get-AgentMemoryAll)
    # THE SAME THING SAID TWICE IS STILL ONE THING. This is the mechanical half of de-duplication: identical text
    # once punctuation, spacing and case are set aside. Recognising that two DIFFERENTLY worded notes say the same
    # thing is a judgement, so that belongs to the AI - it is shown the existing memory and told not to add a
    # near-copy, and to widen an existing note rather than record a second version of it.
    $norm = { param($s) (("$s" -replace '[^\p{L}\p{N}]+', ' ').Trim() -replace '\s+', ' ').ToLowerInvariant() }
    $key = & $norm $t
    $dup = @($all | Where-Object { (& $norm "$($_.text)") -eq $key -and "$($_.scope)" -ieq "$($entry.scope)" })
    if ($dup.Count) { return $dup[0] }
    # already recorded MORE widely? then this narrower copy adds nothing
    $wider = @($all | Where-Object { (& $norm "$($_.text)") -eq $key -and "$($_.scope)" -ieq 'global' })
    if ($wider.Count -and "$($entry.scope)" -ine 'global') {
        Write-Log "Not recorded again - the same note already exists as a house rule: $t" Info
        return $wider[0]
    }
    $all += $entry
    if ($all.Count -gt $MaxEntries) { $all = @($all | Select-Object -Last $MaxEntries) }
    try {
        $json = if ($all.Count -eq 1) { '[' + ($all[0] | ConvertTo-Json -Depth 6) + ']' } else { $all | ConvertTo-Json -Depth 6 }
        Set-Content -LiteralPath (Get-AgentMemoryPath) -Value $json -Encoding UTF8
        Write-Log "Remembered ($($entry.scope)): $t" Info
    } catch { Write-Log "Could not write the memory: $($_.Exception.Message)" Warning }
    return $entry
}

function Get-AgentMemoryFor {
    <#
      The part of the memory that applies here: everything global, plus this vendor's, plus this package's.
      Newest last, so the most recent instruction reads as the latest word.
    #>
    param([string]$Vendor, [string]$Package, [string]$Technology, [int]$Max = 40)
    $all = @(Get-AgentMemoryAll)
    if (-not $all.Count) { return @() }
    $v = "$Vendor".Trim(); $p = "$Package".Trim(); $tech = "$Technology".Trim()
    # A package is also an instance of a TECHNOLOGY - what was learned about Inno Setup on one application is true of
    # the next one, whoever made it. Matched loosely because the same technology gets written several ways
    # ("Inno Setup", "InnoSetup", "inno").
    $techKey = ($tech -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
    $hit = @($all | Where-Object {
        $s = "$($_.scope)".Trim()
        if ($s -ieq 'global') { return $true }
        if ($v -and $s -ieq "vendor:$v") { return $true }
        if ($p -and $s -ieq "package:$p") { return $true }
        # a note about "package:Kistler_Ceus_x86" is about every version of it, not only the one it was written on
        if ($p -and $s -match '(?i)^package:(.+)$' -and $Matches[1].Trim().Length -ge 6 -and $p.StartsWith($Matches[1].Trim(), [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($techKey -and $s -match '(?i)^technology:(.+)$') {
            $k = ($Matches[1] -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
            if ($k -and ($k -eq $techKey -or $techKey.Contains($k) -or $k.Contains($techKey))) { return $true }
        }
        return $false
    })
    return @($hit | Select-Object -Last $Max)
}

function Format-AgentMemory {
    param([string]$Vendor, [string]$Package, [string]$Technology, [int]$Max = 40)
    $m = @(Get-AgentMemoryFor -Vendor $Vendor -Package $Package -Technology $Technology -Max $Max)
    if (-not $m.Count) { return 'nothing has been recorded yet - this is the first time through' }
    return (@($m | ForEach-Object { "- [$($_.scope)] $($_.text)$(if ("$($_.why)".Trim()) { "  (why: $($_.why))" })  - $($_.source), $($_.at)" }) -join "`n")
}

# The tool the AI calls when it learns something that should outlive this package.
function Get-AgentMemoryTools {
    param([string]$Vendor, [string]$Package)
    $ctx = @{ Vendor = "$Vendor"; Package = "$Package" }
    return @(
        @{ Ctx = $ctx
           Decl = (New-AgentFunctionDeclaration -Name 'remember_this' -Description @'
Record something that should still be known the next time this team packages something. Use it when the packager
tells you how they want something done, when you learn a fact about a vendor or an application that will matter
again (this vendor's EXE must not be replaced by its MSI; this runtime is shared and must never be removed), or when
a decision was made that a future run should not have to ask about twice.
Do NOT record one-off details of this package that are already in its own record, and do not record a guess.
Scope it: "global" for a house rule, "vendor:<name>" for something about a vendor, "package:<name>" for this package.
'@ -Parameters @{ type = 'OBJECT'; properties = @{
                text  = @{ type = 'STRING'; description = 'the thing to remember, in one or two plain sentences' }
                scope = @{ type = 'STRING'; description = 'global | vendor:<name> | package:<name>' }
                why   = @{ type = 'STRING'; description = 'why it matters, in a few words' } }
                required = @('text') })
           Run = { param($a, $c)
                   $sc = "$($a.scope)".Trim(); if (-not $sc) { $sc = 'global' }
                   $e = Add-AgentMemory -Text "$($a.text)" -Scope $sc -Why "$($a.why)" -Source 'ai'
                   if (-not $e) { return @{ stored = $false; note = 'nothing to store' } }
                   return @{ stored = $true; scope = "$($e.scope)"; text = "$($e.text)"; note = 'it will be sent with every future run this applies to' } } }
    )
}

#  ===================================================================================================
#   THE CASE LIBRARY - every finished order teaches the next one
#
#   Knowledge\Cases.json holds one compact record per order the agent has worked: what was delivered,
#   the route, the install line the machine PROVED, what failed before it, the auto-updater and how it
#   was switched off, what the verification had to fix, and what the packager said after testing.
#   It is written automatically at handover, so the library grows with every package - nobody has to
#   remember to write anything down. The next order of the same vendor, application or installer
#   technology gets the closest cases in its dossier: worked examples beat rules, and they are what
#   lets a cheaper model do the work of an expensive one.
#  ===================================================================================================
function Get-AgentCasesPath {
    $root = if ("$script:AgentHome".Trim()) { "$script:AgentHome" } else { Join-Path $env:TEMP 'PackagingAgent' }
    $dir = Join-Path $root 'Knowledge'
    if (-not (Test-Path -LiteralPath $dir)) { try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch {} }
    return (Join-Path $dir 'Cases.json')
}
function Get-AgentCasesAll {
    $p = Get-AgentCasesPath
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    try { $raw = Get-Content -LiteralPath $p -Raw -ErrorAction Stop; if (-not "$raw".Trim()) { return @() }; $parsed = $raw | ConvertFrom-Json; return @($parsed) } catch { return @() }
}

# Write (or update) this order's case. Facts only, taken from the sheet - nothing here is judged by the tool.
function Save-AgentCase {
    param([Parameter(Mandatory)]$Sheet, [string]$PackagerNotes = '', [int]$MaxCases = 600)
    $pkg = "$($Sheet.package)".Trim(); if (-not $pkg) { return $null }
    $plan = $Sheet.plan; $dec = $Sheet.decision; $ver = $Sheet.verification
    $spec = try { Get-AgentPackageSpec -Sheet $Sheet } catch { $null }
    $cut = { param($s, [int]$n = 220) $t = "$s".Trim(); if ($t.Length -gt $n) { $t.Substring(0, $n) + '...' } else { $t } }
    $case = [ordered]@{
        at = (Get-Date -Format 'yyyy-MM-dd'); package = $pkg
        vendor = "$($Sheet.identity.vendor)"; app = "$($Sheet.identity.app)"; version = "$($Sheet.identity.version)"; arch = "$($Sheet.identity.arch)"
        technology = @(@(Get-AgentList $Sheet.sources.installers) | ForEach-Object { "$($_.engine)" } | Where-Object { $_ -and $_ -ne 'unknown' } | Select-Object -Unique)
        delivered = @(@(Get-AgentList $Sheet.sources.installers) | ForEach-Object { "$($_.name)" } | Select-Object -First 6) + @(@(Get-AgentList $Sheet.sources.transforms) | ForEach-Object { "$($_.name)" })
        route = $(if ($plan -and $plan.route) { "$($plan.route.kind) / route $($plan.route.number)" } else { '' })
        predecessor = "$($Sheet.history.predecessor.name)"
        installSteps = @(@(Get-AgentList $plan.install.steps) | ForEach-Object { "$($_.installer) $($_.arguments)".Trim() })
        provenLine = $(if ($Sheet.trial -and $Sheet.trial.winner) { "$($Sheet.trial.winner.arguments)" } else { '' })
        failedFirst = @(@(Get-AgentList $Sheet.trial.attempts) | Where-Object { "$($_.verdict)" -notin 'silent', 'progress' } | Select-Object -First 4 | ForEach-Object { "$($_.arguments) -> $($_.verdict)$(if ($null -ne $_.exitCode) { " exit $($_.exitCode)" })$(if (@($_.windowsSeen).Count) { " window '$(@($_.windowsSeen)[0])'" })" })
        autoUpdate = $(if ($dec -and $dec.autoUpdate -and [bool]$dec.autoUpdate.found) { "$($dec.autoUpdate.mechanism): $(@(Get-AgentList $dec.autoUpdate.commands) | Select-Object -First 1)" } else { '' })
        uninstall = & $cut "$($dec.uninstall.command)"
        detection = & $cut "$($spec.detection.key)"
        configuration = @(@(Get-AgentList $dec.configurationPlan.settings) | Select-Object -First 5 | ForEach-Object { & $cut "$($_.what): $($_.target) = $($_.valueToSet) via $($_.carriedBy)" 180 })
        verifyFixed = @(@(Get-AgentList $ver.findings) | Where-Object { [bool]$_.fixed } | Select-Object -First 6 | ForEach-Object { & $cut "$($_.severity): $($_.what)" 160 })
        stillOpen = @(@(Get-AgentList $ver.findings) | Where-Object { -not [bool]$_.fixed -and "$($_.severity)" -in 'blocker', 'major' } | Select-Object -First 4 | ForEach-Object { & $cut "$($_.what)" 160 })
        questionsAsked = @(@(Get-AgentList $plan.questions) | Select-Object -First 4 | ForEach-Object { & $cut "$($_.question)" 160 })
        verdict = "$($ver.verdict)"; signedOff = [bool]$Sheet.verificationPassed
        packagerSaid = @()
    }
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($c in @(Get-AgentCasesAll)) { if ("$($c.package)" -ne $pkg) { $all.Add($c) } else { $case.packagerSaid = @(@($c.packagerSaid) | Where-Object { $_ }) } }
    if ("$PackagerNotes".Trim()) { $case.packagerSaid = @(@($case.packagerSaid) + @(& $cut $PackagerNotes 600)) }
    $all.Add($case)
    $arr = $all.ToArray(); if ($arr.Count -gt $MaxCases) { $arr = @($arr | Select-Object -Last $MaxCases) }
    try {
        $json = if (@($arr).Count -eq 1) { '[' + ($arr[0] | ConvertTo-Json -Depth 6 -Compress) + ']' } else { $arr | ConvertTo-Json -Depth 6 -Compress }
        [IO.File]::WriteAllText((Get-AgentCasesPath), $json, (New-Object Text.UTF8Encoding $false))
    } catch { Write-Log "Could not write the case library: $($_.Exception.Message)" Warning }
    return $case
}

# The cases closest to this order: same vendor and application first, then the vendor, then the installer technology.
function Get-AgentCasesFor {
    param([string]$Vendor, [string]$App, [string[]]$Technology = @(), [string]$ExcludePackage = '', [int]$Max = 5)
    $v = "$Vendor".Trim().ToLowerInvariant(); $a = "$App".Trim().ToLowerInvariant()
    $tech = @($Technology | Where-Object { "$_".Trim() } | ForEach-Object { "$_".ToLowerInvariant() })
    $scored = foreach ($c in @(Get-AgentCasesAll)) {
        if ("$($c.package)" -eq "$ExcludePackage") { continue }
        $s = 0
        if ($v -and "$($c.vendor)".ToLowerInvariant() -eq $v) { $s += 3 }
        if ($a -and "$($c.app)".ToLowerInvariant() -eq $a) { $s += 4 }
        if (@(@($c.technology) | Where-Object { $tech -contains "$_".ToLowerInvariant() }).Count) { $s += 1 }
        if ($s -gt 0) { [pscustomobject]@{ s = $s; at = "$($c.at)"; c = $c } }
    }
    return @(@($scored) | Sort-Object @{ Expression = 's'; Descending = $true }, @{ Expression = 'at'; Descending = $true } | Select-Object -First $Max | ForEach-Object { $_.c })
}

#  ===================================================================================================
#   THE CORPUS - how this team has packaged everything it ever shipped
#
#   Knowledge\Corpus\ is built by Tools\Build-CorpusKnowledge.ps1 from the shipped library (live + Outgoing): per
#   package HOW it was packaged (layout, install/uninstall, what each phase does, how the previous version, the
#   updater, shortcuts, per-user settings and reboots were handled, detection, the author's own notes) and what the
#   evaluation left behind (the evaluation document's packaging section, the owner's form, the query mails, the test
#   logs). Patterns.json, Vendors.json and Lessons.json consolidate it. It is read LOCALLY, never from the shares:
#   the knowledge travels with the tool. It is evidence of practice - how this team thinks - not lines to copy.
#  ===================================================================================================
function Get-AgentCorpusDir {
    if ("$script:AgentCorpusDir".Trim()) { return "$script:AgentCorpusDir" }
    return (Join-Path "$script:AgentHome" 'Knowledge\Corpus')
}
function Get-AgentCorpusPart {
    param([Parameter(Mandatory)][string]$Name)
    if (-not $script:AgentCorpusCache) { $script:AgentCorpusCache = @{} }
    $dir = Get-AgentCorpusDir
    $key = "$dir|$Name"
    if ($script:AgentCorpusCache.ContainsKey($key)) { return $script:AgentCorpusCache[$key] }
    $p = Join-Path $dir $Name
    $v = if (Test-Path -LiteralPath $p) { try { $raw = [IO.File]::ReadAllText($p); $raw | ConvertFrom-Json } catch { $null } } else { $null }
    $script:AgentCorpusCache[$key] = $v
    return $v
}
# The shipped packages closest to this order: same vendor and application first (the predecessor's own family), then
# the vendor, then packages of the same technology whose names share words with it.
function Find-AgentCorpusPackages {
    param([string]$Vendor, [string]$App, [string[]]$Words = @(), [string]$InstallerType = '', [string]$ExcludePackage = '', [int]$Max = 4)
    $index = @(Get-AgentCorpusPart 'Index.json')
    if (-not $index.Count) { return @() }
    $v = "$Vendor".ToLowerInvariant(); $a = ("$App" -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
    $w = @(@($Words) | ForEach-Object { "$_" -split '[\s_\-\.|:]+' } | Where-Object { "$_".Length -ge 4 } | ForEach-Object { "$_".ToLowerInvariant() } | Select-Object -Unique)
    $scored = foreach ($r in $index) {
        if ("$($r.package)" -eq "$ExcludePackage") { continue }
        $s = 0
        $rv = "$($r.vendor)".ToLowerInvariant(); $ra = ("$($r.app)" -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
        if ($v -and $rv -eq $v) { $s += 4 }
        if ($a -and $ra -eq $a) { $s += 6 } elseif ($a -and $ra -and ($ra.Contains($a) -or $a.Contains($ra))) { $s += 3 }
        $hay = "$($r.package)".ToLowerInvariant()
        $s += @($w | Where-Object { $hay.Contains($_) }).Count
        if ($InstallerType -and "$($r.installerType)" -eq $InstallerType -and $s -gt 0) { $s += 1 }
        if ($s -gt 0) { [pscustomobject]@{ s = $s; w = "$($r.written)"; r = $r } }
    }
    $top = @(@($scored) | Sort-Object @{ Expression = 's'; Descending = $true }, @{ Expression = 'w'; Descending = $true } | Select-Object -First $Max)
    $out = @()
    foreach ($t in $top) {
        $vendorFile = @(Get-AgentCorpusPart "Packages\$($t.r.file)")
        $prof = @($vendorFile | Where-Object { "$($_.package)" -eq "$($t.r.package)" }) | Select-Object -First 1
        if ($prof) { $out += $prof }
    }
    return $out
}
function Get-AgentCorpusVendor { param([string]$Vendor) $vs = Get-AgentCorpusPart 'Vendors.json'; if (-not $vs -or -not "$Vendor".Trim()) { return $null }; $hit = @($vs.PSObject.Properties | Where-Object { $_.Name -ieq "$Vendor" }) | Select-Object -First 1; if ($hit) { return $hit.Value }; return $null }
function Get-AgentCorpusLessons {
    param([string[]]$Words = @(), [string]$Vendor = '', [int]$Max = 12)
    $all = @(Get-AgentCorpusPart 'Lessons.json')
    $w = @(@($Words) | ForEach-Object { "$_" -split '[\s,]+' } | Where-Object { "$_".Length -ge 3 } | ForEach-Object { "$_".ToLowerInvariant() })
    # the lesson is captured before the inner Where-Object - inside it $_ is the WORD, and "$($_.note)" was always empty
    return @($all | Where-Object { $l = $_; $hay = "$($l.note) $($l.package)".ToLowerInvariant(); ($Vendor -and "$($l.vendor)" -ieq $Vendor) -or ($w.Count -and @($w | Where-Object { $hay.Contains($_) }).Count) } | Select-Object -First $Max)
}
# The whole-library practice, cut to what fits in every dossier: distributions, the most common operations per phase
# with one real example each, how updaters, shortcuts and reboots were handled, and the detection shapes.
function Get-AgentCorpusPractice {
    $pt = Get-AgentCorpusPart 'Patterns.json'
    if (-not $pt) { return $null }
    $phases = [ordered]@{}
    foreach ($k in @($pt.whatEachPhaseDoes.PSObject.Properties)) { $phases[$k.Name] = @(@($k.Value) | Select-Object -First 8 | ForEach-Object { "$($_.command): $($_.share)% of packages, e.g. $(@($_.example)[0])" }) }
    return [ordered]@{ fromPackages = $pt.packages; templates = $pt.templates; installers = $pt.installers; previousVersionRemoval = $pt.previousVersionRemoval
                       perUserConfiguration = $pt.perUserConfiguration; evaluationArtefacts = $pt.evaluationArtefacts; whatEachPhaseDoes = $phases
                       howUpdatersWereSwitchedOff = @(@($pt.howUpdatersWereSwitchedOff) | Select-Object -First 10); howShortcutsWereHandled = @(@($pt.howShortcutsWereHandled) | Select-Object -First 5)
                       howRebootsWereHandled = @(@($pt.howRebootsWereHandled) | Select-Object -First 5); detectionShapes = @(@($pt.detectionShapes) | Select-Object -First 4) }
}

# The team catalogue (~900 shipped packages, Engine\KnowledgeBase.Recommend.json): proven install/uninstall lines
# per installer, vendor and application. Searched by words, so the AI can ask "what did we use for anything by X".
function Search-AgentCatalogue {
    param([string[]]$Terms, [int]$Max = 12)
    if (-not $script:AgentCatalogue) {
        $p = Join-Path "$script:AgentToolRoot" 'KnowledgeBase.Recommend.json'
        if (-not (Test-Path -LiteralPath $p)) { $p = Join-Path "$script:AgentHome" 'Engine\KnowledgeBase.Recommend.json' }
        $script:AgentCatalogue = try { (Get-Content -LiteralPath $p -Raw) | ConvertFrom-Json } catch { $null }
    }
    $kb = $script:AgentCatalogue
    if (-not $kb) { return [ordered]@{ found = @(); note = 'the catalogue is not reachable' } }
    $words = @(@($Terms) | ForEach-Object { "$_" -split '[\s_\-\.|:]+' } | Where-Object { "$_".Length -ge 3 } | ForEach-Object { "$_".ToLowerInvariant() } | Select-Object -Unique)
    if (-not $words.Count) { return [ordered]@{ found = @(); note = 'give at least one word of three letters or more' } }
    # both indexes: per installer file, and per vendor|application (which holds entries the installer index does not)
    $seen = @{}
    $hits = foreach ($idx in @($kb.byInstaller, $kb.byVendorApp)) {
        if (-not $idx) { continue }
        foreach ($prop in $idx.PSObject.Properties) {
            $e = $prop.Value
            $key = "$($e.fromPackage)|$($e.installer)"; if ($seen[$key]) { continue }
            $hay = "$($prop.Name) $($e.vendor) $($e.app) $($e.installer) $($e.fromPackage)".ToLowerInvariant()
            $n = @($words | Where-Object { $hay.Contains($_) }).Count
            if ($n) { $seen[$key] = $true; [pscustomobject]@{ n = $n; e = $e } }
        }
    }
    $top = @(@($hits) | Sort-Object n -Descending | Select-Object -First $Max | ForEach-Object {
        [ordered]@{ package = "$($_.e.fromPackage)"; installer = "$($_.e.installer)"; type = "$($_.e.type)"; engine = "$($_.e.engine)"
                    install = "$($_.e.install)"; uninstall = "$($_.e.uninstall)"; uninstaller = "$($_.e.uninstaller)"; autoUpdate = $_.e.autoUpdate } })
    return [ordered]@{ found = $top; note = "$(@($top).Count) shipped package(s) match $($words -join ', '). These are lines that WORKED in production for those packages - evidence, not a rule for this one." }
}

#  ===================================================================================================
#   A FAITHFUL LOCAL COPY OF THE ORDER
#
#   Working straight off a share is slow and occasionally read-only, so the order gets copied locally
#   first. That copy has to be FAITHFUL: an ordinary Copy-Item keeps a file's modified date but resets
#   its CREATED date, and stamps every folder it makes with today - so the payload arrives looking like
#   somebody edited it, and the package carries that lie all the way to the reviewer.
#
#   A delivered file's dates are evidence of what the vendor shipped. Only files the agent MAKES (a
#   transform it generates, a stub it writes) should carry today's date.
#  ===================================================================================================
function Copy-AgentTreeWithTimestamps {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [scriptblock]$Progress
    )
    $res = [ordered]@{ ok = $false; files = 0; folders = 0; stamped = 0; seconds = 0; note = '' }
    if (-not (Test-Path -LiteralPath $Source)) { $res.note = 'the source folder is not reachable'; return $res }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        New-Item -ItemType Directory -Force -Path $Destination -ErrorAction Stop | Out-Null
        $root = (Get-Item -LiteralPath $Source).FullName.TrimEnd('\')
        $items = @(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue)
        foreach ($i in $items) {
            $rel = $i.FullName.Substring($root.Length).TrimStart('\')
            $to = Join-Path $Destination $rel
            if ($i.PSIsContainer) {
                if (-not (Test-Path -LiteralPath $to)) { New-Item -ItemType Directory -Force -Path $to -ErrorAction SilentlyContinue | Out-Null }
                $res.folders++
            } else {
                $parent = Split-Path -Parent $to
                if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent -ErrorAction SilentlyContinue | Out-Null }
                try { Copy-Item -LiteralPath $i.FullName -Destination $to -Force -ErrorAction Stop; $res.files++ } catch { continue }
            }
            if ($Progress -and (($res.files + $res.folders) % 200 -eq 0)) { & $Progress "copying the order locally: $($res.files) file(s)" }
        }
        # Stamp AFTERWARDS and deepest-first: writing a file into a folder updates that folder's date again,
        # so folders have to be corrected once everything inside them is already in place.
        foreach ($i in @($items | Sort-Object { "$($_.FullName)".Length } -Descending)) {
            $rel = $i.FullName.Substring($root.Length).TrimStart('\')
            $to = Join-Path $Destination $rel
            if (-not (Test-Path -LiteralPath $to)) { continue }
            try {
                $d = Get-Item -LiteralPath $to -Force -ErrorAction Stop
                $d.CreationTimeUtc = $i.CreationTimeUtc
                $d.LastWriteTimeUtc = $i.LastWriteTimeUtc
                $res.stamped++
            } catch {}
        }
        try { $rt = Get-Item -LiteralPath $Destination -Force; $sr = Get-Item -LiteralPath $root -Force
              $rt.CreationTimeUtc = $sr.CreationTimeUtc; $rt.LastWriteTimeUtc = $sr.LastWriteTimeUtc } catch {}
        $res.ok = $true
        $res.note = "copied $($res.files) file(s) and $($res.folders) folder(s) locally with their original created/modified dates ($($res.stamped) stamped)"
    } catch {
        $res.note = "could not copy the order locally: $($_.Exception.Message.Split([char]10)[0])"
    }
    $sw.Stop(); $res.seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    return $res
}

#  ===================================================================================================
#   THE PREDECESSOR THAT CAME WITH THE ORDER
#
#   The engine looks for the previous version on the package shares. But it is also common practice here
#   to DELIVER the previous version inside the order itself - a subfolder called "predecessor",
#   "previous version", "old" and so on, holding the whole package. That copy is the most authoritative
#   one there is: somebody deliberately put it there for this order, so it beats a name-matched guess
#   off a share. The engine cannot see it, so the agent looks.
#  ===================================================================================================
function Test-AgentIsPackageFolder {
    # A PSADT package root holds the toolkit script - either directly or one level down in Content\.
    param([Parameter(Mandatory)][string]$Path)
    foreach ($probe in @($Path, (Join-Path $Path 'Content'))) {
        if (-not (Test-Path -LiteralPath $probe)) { continue }
        $hit = @(Get-ChildItem -LiteralPath $probe -File -Filter '*.ps1' -Depth 1 -Recurse -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match '(?i)^(Invoke-AppDeployToolkit|Deploy-Application)\.ps1$' } | Select-Object -First 1)
        if ($hit.Count) { return $true }
    }
    return $false
}

function Find-AgentPredecessorInOrder {
    <#
      Looks inside the order folder for a previous version delivered with it. Returns candidates, best first,
      each saying WHY it was taken for one - never a verdict about whether it should be reused.
    #>
    param(
        [Parameter(Mandatory)][string]$OrderFolder,
        [string]$CurrentPackageName = '',
        [int]$Depth = 4
    )
    $out = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $OrderFolder)) { return @() }

    # Folder names people actually use for this, in English and German.
    $words = '(?i)predecessor|previous|prev[_ -]?ver|vorg[aä]nger|vorversion|old[_ -]?(version|package)?$|alt[e]?[_ -]?version|existing|reference|current[_ -]?(live|package)|live[_ -]?package'
    $dirs = @()
    try { $dirs = @(Get-ChildItem -LiteralPath $OrderFolder -Directory -Recurse -Depth $Depth -ErrorAction SilentlyContinue) } catch {}

    foreach ($d in $dirs) {
        $named = [bool]($d.Name -match $words)
        $parentNamed = [bool]((Split-Path -Leaf (Split-Path -Parent $d.FullName)) -match $words)
        # A folder whose own NAME parses as one of our package names is a package copy even without a telling parent.
        $parsesAsPackage = $false
        if (Get-Command Parse-PackageName -ErrorAction SilentlyContinue) {
            try { $pp = Parse-PackageName $d.Name; $parsesAsPackage = [bool]$pp.IsValid } catch {}
        }
        if (-not ($named -or $parentNamed -or $parsesAsPackage)) { continue }
        if ($CurrentPackageName -and $d.Name -ieq $CurrentPackageName) { continue }   # never its own predecessor
        if (-not (Test-AgentIsPackageFolder -Path $d.FullName)) { continue }

        $why = @()
        if ($named) { $why += "the folder is named '$($d.Name)'" }
        elseif ($parentNamed) { $why += "it sits under '$(Split-Path -Leaf (Split-Path -Parent $d.FullName))'" }
        if ($parsesAsPackage) { $why += 'its name parses as one of our package names' }
        $why += 'it contains a PSADT toolkit script'

        $out.Add([ordered]@{
            name = $d.Name; path = $d.FullName
            deliveredWithTheOrder = $true
            relativeTo = $d.FullName.Substring($OrderFolder.TrimEnd('\').Length).TrimStart('\')
            why = ($why -join '; ')
            # a folder explicitly named for it ranks above one merely recognised by its package name
            rank = $(if ($named) { 0 } elseif ($parentNamed) { 1 } else { 2 })
        })
    }
    if (-not $out.Count) { return @() }
    return @($out.ToArray() | Sort-Object rank, name)
}

# WHO BUILT THIS MSI - the vendor, or a packaging team that CAPTURED the vendor's setup into an MSI. The MSI's summary
# information says so (author, comments, the tool that created it). It decides what "the predecessor's method" really
# is: a vendor MSI can be taken again from the new delivery; a captured one cannot - the capture has to be made again.
# On a real order the previous package installed "Ceus_8.6.6.9.msi" (author "MAN Software Packaging", created with
# InstallShield) and the AI kept looking for an MSI inside the vendor EXE that never contained one.
function Get-AgentMsiAuthorship {
    param([Parameter(Mandatory)][string]$Path)
    $r = [ordered]@{ title = ''; subject = ''; author = ''; comments = ''; createdBy = ''; builtByAPackagingTeam = $false; why = '' }
    try {
        $i = New-Object -ComObject WindowsInstaller.Installer
        $si = $i.GetType().InvokeMember('SummaryInformation', 'GetProperty', $null, $i, @($Path, 0))
        $get = { param($n) try { "$($si.GetType().InvokeMember('Property', 'GetProperty', $null, $si, @($n)))" } catch { '' } }
        $r.title = & $get 2; $r.subject = & $get 3; $r.author = & $get 4; $r.comments = & $get 6; $r.createdBy = & $get 18
        try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($si); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($i) } catch {}
    } catch { $r.why = "the summary information could not be read: $($_.Exception.Message.Split([char]10)[0])"; return $r }
    $txt = "$($r.author) $($r.comments) $($r.title)"
    $team = [regex]::Match($txt, '(?i)(software packaging|packaging team|packaging service|repackag\w*|created by [^|]*packag\w*|captured|client management)')
    $tool = [regex]::Match("$($r.createdBy)", '(?i)(AdminStudio|Repackager|Advanced Installer|Master Packager|RayPack|EMCO|MSI Wrapper|Orca|InstallShield)')
    if ($team.Success) { $r.builtByAPackagingTeam = $true; $r.why = "author/comments say '$($team.Value)'$(if ($tool.Success) { "; created with $($tool.Value)" })" }
    elseif ($tool.Success -and $r.createdBy -match '(?i)Repackager|AdminStudio|Master Packager|RayPack|EMCO|MSI Wrapper') { $r.builtByAPackagingTeam = $true; $r.why = "created with $($tool.Value), a repackaging tool" }
    else { $r.why = "no sign of a packaging team - author '$($r.author)'" }
    return $r
}

function Get-AgentPredecessorPayload {
    <#
      What the PREVIOUS package actually shipped in its Files folder. This is the missing half of the reuse
      comparison: the predecessor's script tells you what it ran, but only its payload tells you WHAT IT RAN IT ON -
      and when that differs from what the order delivers now, the difference itself has to be explained before the
      script can be reused. Facts only.
    #>
    param([Parameter(Mandatory)][string]$PackagePath, [int]$MaxFiles = 40)
    $res = [ordered]@{ found = $false; filesFolder = ''; installers = @(); transforms = @(); otherFiles = @(); note = '' }
    if (-not (Test-Path -LiteralPath $PackagePath)) { $res.note = 'the predecessor package is not reachable'; return $res }

    $filesDir = @()
    foreach ($probe in @((Join-Path $PackagePath 'Content'), $PackagePath)) {
        if (-not (Test-Path -LiteralPath $probe)) { continue }
        $filesDir = @(Get-ChildItem -LiteralPath $probe -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -ieq 'Files' } | Select-Object -First 1)
        if ($filesDir.Count) { break }
    }
    if (-not $filesDir.Count) { $res.note = "the predecessor package has no Files folder - it may be a loose-files or script-only package"; return $res }

    $res.found = $true; $res.filesFolder = $filesDir[0].FullName
    $all = @()
    try { $all = @(Get-ChildItem -LiteralPath $filesDir[0].FullName -File -Recurse -ErrorAction SilentlyContinue) } catch {}
    $res.installers = @($all | Where-Object { $_.Extension -match '(?i)^\.(msi|msp|exe|appx|msix)$' } | Select-Object -First $MaxFiles |
        ForEach-Object { $o = [ordered]@{ name = $_.Name; ext = $_.Extension.ToLower(); sizeMB = [math]::Round($_.Length / 1MB, 1) }
                         if ($_.Extension -ieq '.msi') { $o.whoBuiltIt = Get-AgentMsiAuthorship -Path $_.FullName }
                         $o })
    $cap = @($res.installers | Where-Object { $_.whoBuiltIt -and $_.whoBuiltIt.builtByAPackagingTeam })
    if ($cap.Count) { $res.capturedByAPackagingTeam = @($cap | ForEach-Object { "$($_.name): $($_.whoBuiltIt.why)" }) }
    $res.transforms = @($all | Where-Object { $_.Extension -match '(?i)^\.mst$' } | ForEach-Object { $_.Name })
    $res.otherFiles = @($all | Where-Object { $_.Extension -notmatch '(?i)^\.(msi|msp|exe|appx|msix|mst)$' } | Select-Object -First 15 | ForEach-Object { $_.Name })
    $res.note = "the previous package shipped $(@($res.installers).Count) installer file(s)$(if (@($res.transforms).Count) { " and $(@($res.transforms).Count) transform(s)" }). Compare these against what THIS order delivered: if the kind of file changed, the change itself needs explaining before the old script can be reused.$(if ($cap.Count) { " $(@($cap).Count) of its MSI(s) were BUILT BY A PACKAGING TEAM (captured from the vendor setup), not shipped by the vendor - see capturedByAPackagingTeam." })"
    return $res
}

function Get-AgentPackageContents {
    <#
      A PACKAGE OPENED UP, NOT LISTED. The payload reader above answers "what did it install" from Files\ - but a
      parameter is very often nowhere near the install line. It sits in the toolkit's own Config\config.psd1, in a
      settings file the package ships in SupportFiles, in a response file, in an .ini the script copies into place
      afterwards. A reader that returns folder names cannot see any of that, so the AI reasoning from it concludes
      there are no parameters and reuses a command that is missing half of what the package actually does.

      So: the whole tree, and the CONTENT of the small text files where configuration hides. The toolkit module's
      own internals are listed but never read - they are the same in every package and would bury everything else.
      Anything not returned here is still readable with run_powershell; this is the briefing, not the limit.
    #>
    param([Parameter(Mandatory)][string]$PackagePath, [int]$MaxTree = 250, [int]$MaxReadFiles = 14,
          [int]$MaxCharsPerFile = 4000, [int]$MaxFileKB = 64, [switch]$SkipMainScript)
    $res = [ordered]@{ found = $false; root = "$PackagePath"; tree = @(); configFiles = @(); note = '' }
    if (-not (Test-Path -LiteralPath $PackagePath)) { $res.note = 'the package is not reachable'; return $res }
    $res.found = $true
    $all = @()
    try { $all = @(Get-ChildItem -LiteralPath $PackagePath -File -Recurse -Depth 8 -ErrorAction SilentlyContinue) } catch {}
    if (-not $all.Count) { $res.note = 'no files in the package'; return $res }

    $rel = { param($F) $r = "$($F.FullName)"; if ($r.StartsWith($PackagePath, [StringComparison]::OrdinalIgnoreCase)) { $r = $r.Substring($PackagePath.Length) }; return $r.TrimStart('\', '/') }
    # the toolkit module is identical in every package - list it, never read it, and never let it crowd the tree
    $isModuleGuts = { param($R) return ($R -match '(?i)(^|\\)PSAppDeployToolkit(\\|$)' -and $R -notmatch '(?i)\\Config\\') }
    # UI translations and artwork. Every package carries ~40 language files; they are .psd1 like the config is, so a
    # plain extension filter reads them first and spends the whole content budget on button captions in Norwegian.
    $isFurniture = { param($R) return ($R -match '(?i)(^|\\)(Strings|Assets)\\') }
    # Language files and compiled binaries are the same in every package and carry nothing a packager decides on.
    # They are not even worth listing: 40 strings.psd1 and a pile of .dll push the files that matter off the end.
    $ranked = @($all | Where-Object {
                    $r = & $rel $_
                    $r -notmatch '(?i)(^|\\)Strings\\' -and $_.Extension -notmatch '(?i)^\.(dll|pdb|mui|cat|resources)$'
                } | Sort-Object @{ Expression = { $r = & $rel $_
                    if (& $isModuleGuts $r) { 4 } elseif (& $isFurniture $r) { 3 } elseif ($r -match '(?i)(^|\\)Files\\') { 2 } else { 1 } } },
                @{ Expression = { (& $rel $_) } })
    $res.tree = @($ranked | Select-Object -First $MaxTree | ForEach-Object { & $rel $_ })
    if ($ranked.Count -gt $MaxTree) { $res.note = "$($ranked.Count) files in the package; the $MaxTree that matter most are listed - read any other with run_powershell" }

    # WHERE CONFIGURATION ACTUALLY LIVES. Text, small, and none of the furniture.
    $textExt = '(?i)^\.(psd1|ps1|xml|config|json|ini|cfg|conf|reg|js|txt|cmd|bat|vbs|inf|iss|properties|ya?ml|rsp|pref)$'
    $readable = @($all | Where-Object {
        $r = & $rel $_
        $_.Extension -match $textExt -and $_.Length -le ($MaxFileKB * 1KB) -and
        -not (& $isModuleGuts $r) -and -not (& $isFurniture $r) -and $r -notmatch '(?i)(^|\\)Files\\' -and
        # the main deploy script, when the caller already supplies it in full - a truncated second copy is worse
        # than none, because the reader cannot tell which one they are looking at
        -not ($SkipMainScript -and $_.Name -match '(?i)^(Invoke-AppDeployToolkit|Deploy-Application)\.ps1$')
    } | Sort-Object @{ Expression = { $r = & $rel $_; if ($r -match '(?i)\\Config\\') { 1 } elseif ($r -match '(?i)(^|\\)SupportFiles\\') { 2 } elseif ($r -notmatch '\\') { 3 } else { 4 } } }, Length)
    foreach ($f in @($readable | Select-Object -First $MaxReadFiles)) {
        $t = try { [IO.File]::ReadAllText($f.FullName) } catch { '' }
        if (-not "$t".Trim()) { continue }
        $cut = $t.Length -gt $MaxCharsPerFile
        # A FRAGMENT MUST KNOW IT IS A FRAGMENT, AND SAY HOW TO BECOME WHOLE. "(truncated)" on its own tells the
        # reader nothing about what is missing, so a setting further down the file simply does not exist as far as
        # they are concerned - and "I did not see it" becomes "it is not there".
        if ($cut) { $t = $t.Substring(0, $MaxCharsPerFile) + "`n...(this is the first $MaxCharsPerFile characters of $($f.Length) bytes. The REST IS NOT HERE. Read the whole file with run_powershell before concluding anything is missing from it: Get-Content -LiteralPath '$($f.FullName)' -Raw)" }
        # hash the WHOLE file, not the excerpt - it is what lets the caller say "identical to the template" without
        # sending both copies, and a truncated comparison would call two different files the same
        $h = try { (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash } catch { '' }
        $res.configFiles += [ordered]@{ path = (& $rel $f); sizeKB = [math]::Round($f.Length / 1KB, 1); truncated = $cut; hash = $h; text = $t }
    }
    if (-not $res.note) { $res.note = "$(@($res.configFiles).Count) configuration/script file(s) are included with their contents; everything else is listed by name and can be read with run_powershell." }
    return $res
}

function Search-AgentPreviousPackages {
    <#
      LOOK FOR THE PREVIOUS VERSION THE WAY A PACKAGER WOULD - by what the thing IS, not by what the folder is called.

      The name-based search matches a parsed vendor and application against the share. It is cheap and usually right,
      and when it is wrong it is wrong silently: an order delivered as 'EQS_BRAK_beAClientSecurity_x64_...' parses its
      vendor as 'EQS', matches nothing, and the run concludes there is no predecessor. Meanwhile
      'BRAK_beAClientSecurity_x64_4.5.2.633-0001_de-DE' is sitting on the live share.

      So this searches on any term the AI cares to give it: the installer's file name, the ProductName or the
      CompanyName read out of the binary, a word from the instructions. Facts only - it returns what is there and
      says nothing about which one is the predecessor. That judgement needs the installer, the documents and the
      version history in front of it, and it belongs to the AI.
    #>
    param([Parameter(Mandatory)][string[]]$Terms, [int]$MaxPerRoot = 12, [string]$Arch = '', [string]$Version = '')
    $out = [ordered]@{ searched = @(); matches = @(); note = '' }
    # Split what we were given into words, so "beA Client Security" finds "beAClientSecurity" and a file name like
    # 'beAClientSecurity.exe' contributes its stem. A single long term matching nothing is the usual way a search
    # like this fails, and it fails silently.
    $terms = @(@($Terms | ForEach-Object {
                    $t = "$_".Trim() -replace '\.(exe|msi|msp|zip)$', ''
                    @($t) + @($t -split '[\s_\-\.]+') + @([regex]::Matches($t, '(?:[A-Z]+(?![a-z])|[A-Z][a-z]+|[a-z]+|\d+)') | ForEach-Object { $_.Value })
                }) | ForEach-Object { "$_".Trim() } | Where-Object { $_.Length -ge 3 } | Select-Object -Unique)
    if (-not $terms.Count) { $out.note = 'give at least one search term of three characters or more'; return $out }

    $roots = @()
    foreach ($key in 'PredecessorPath', 'OutgoingPath') {
        $p = try { "$(Get-Setting $key '')" } catch { '' }
        if ("$p".Trim()) { $roots += @{ key = $key; path = $p } }
    }
    foreach ($r in $roots) {
        $reachable = try { Test-Path -LiteralPath $r.path } catch { $false }
        $out.searched += [ordered]@{ where = $r.key; path = $r.path; reachable = $reachable }
        if (-not $reachable) { continue }
        $dirs = @()
        try { $dirs = @(Get-ChildItem -LiteralPath $r.path -Directory -ErrorAction SilentlyContinue) } catch {}
        # Score every folder against every term, then keep the best. A folder matching two of your words is a much
        # better lead than one matching a single short word, and the count is the only honest way to say so.
        $scored = New-Object System.Collections.Generic.List[object]
        foreach ($d in $dirs) {
            $hit = @($terms | Where-Object { $d.Name -match "(?i)$([regex]::Escape($_))" })
            if (-not $hit.Count) { continue }
            $parsed = try { Parse-PackageName -Name $d.Name } catch { $null }
            # words matched is the signal; architecture agreeing is a nudge; the SAME version is usually this very
            # package rather than the one before it, so it is flagged rather than promoted
            $score = @($hit).Count * 10
            # 'false' MUST MEAN "I compared them and they differ" - never "nobody told me what to compare against".
            # It did mean the second thing: a search that left arch and version out came back saying a package was a
            # different architecture AND a different version when it was neither, and the run rebuilt from scratch
            # with the real predecessor sitting on the share. An unknown says unknown.
            $knowArch = [bool]("$Arch".Trim() -and "$($parsed.Arch)".Trim())
            $knowVer = [bool]("$Version".Trim() -and "$($parsed.Version)".Trim())
            $sameArch = if ($knowArch) { "$($parsed.Arch)" -ieq "$Arch" } else { 'not compared - no architecture was given to compare against' }
            $sameVersion = if ($knowVer) { "$($parsed.Version)" -ieq "$Version" } else { 'not compared - no version was given to compare against' }
            if ($knowArch -and $sameArch -eq $true) { $score += 5 }
            if ($knowArch -and $sameArch -eq $false) { $score -= 5 }
            $scored.Add([ordered]@{
                name = $d.Name; path = $d.FullName; where = $r.key; score = $score
                matchedWords = @($hit); vendor = "$($parsed.Vendor)"; app = "$($parsed.AppName)"
                version = "$($parsed.Version)"; arch = "$($parsed.Arch)"; lang = "$($parsed.Lang)"
                sameArchAsThisOrder = $sameArch
                sameVersionAsThisOrder = $sameVersion
                note = $(if ($knowVer -and $sameVersion -eq $true) { 'SAME version as the order - this is probably this package already on the share rather than its predecessor, so look for the version BELOW it too' } else { '' })
                lastWritten = try { $d.LastWriteTime.ToString('yyyy-MM-dd') } catch { '' }
            })
        }
        foreach ($m in @($scored.ToArray() | Sort-Object -Property @{ Expression = { $_.score }; Descending = $true }, @{ Expression = { $_.name } } | Select-Object -First $MaxPerRoot)) {
            if (@($out.matches | Where-Object { "$($_.path)" -eq "$($m.path)" }).Count) { continue }
            $out.matches += $m
        }
    }
    # DROP THE NOISE, AND SAY THAT YOU DID. Searching for "beA Client Security" matches every package on the share
    # with the word Client in it - 15 of them, all irrelevant, all looking like candidates. When something has
    # matched several of the words, anything that matched barely one is not a lead, it is a distraction. This
    # removes noise; it does not choose a predecessor, and the count of what went is reported.
    $all = @($out.matches)
    if (@($all).Count -gt 3) {
        # Measure-Object reads PSObject PROPERTIES; these are hashtable KEYS, so -Property score came back empty and
        # the filter below silently never ran. Count it by hand.
        $best = 0; foreach ($m in $all) { $sc = [int]$m.score; if ($sc -gt $best) { $best = $sc } }
        if ($best -ge 20) {
            $keep = @($all | Where-Object { $_.score -ge ($best / 2) })
            if (@($keep).Count -lt @($all).Count) {
                $out.droppedWeakMatches = @($all).Count - @($keep).Count
                $out.matches = $keep
            }
        }
    }
    $out.note = if (@($out.matches).Count) {
        "$(@($out.matches).Count) package(s) on the shares match$(if ($out.droppedWeakMatches) { ", after setting aside $($out.droppedWeakMatches) that matched only one common word" }). Which one is the predecessor - or whether any of them is - is your call: compare the installer, the architecture, the version and what the order says. Ask the packager if two look equally likely."
    } else {
        "nothing on the shares matches $($terms -join ', '). Try the installer's file name, its ProductName, its manufacturer, or a shorter word from the application's name before concluding there is no previous version."
    }
    return $out
}

function Get-AgentScreenshot {
    <#
      LOOK AT THE SCREEN. The AI cannot see this machine, and some evidence exists nowhere else: an installer showing
      a dialog instead of going silent, a wizard waiting on a click, an error box with the only useful text in the
      whole run, whether the application it just installed actually starts. Every one of those is invisible to a
      snapshot diff and to an exit code - and an installer sitting on a dialog looks exactly like one that is working.

      So this takes a picture and hands it back as an image the AI genuinely looks at. Facts only: the file, the size,
      and the list of visible windows to go with it, because "which window is that" is much easier answered from the
      title list than from the pixels.
    #>
    param([string]$Why = '', [int]$DelaySeconds = 0, [int]$MaxEdge = 1280)
    $res = [ordered]@{ ok = $false; path = ''; width = 0; height = 0; takenAt = ''; visibleWindows = @(); why = "$Why"; note = '' }
    try { Add-Type -AssemblyName System.Drawing, System.Windows.Forms -ErrorAction Stop } catch { $res.note = "cannot load the drawing libraries: $($_.Exception.Message)"; return $res }
    if ($DelaySeconds -gt 0) { Start-Sleep -Seconds ([Math]::Min(30, $DelaySeconds)) }
    try {
        $sc = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap $sc.Width, $sc.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($sc.Left, $sc.Top, 0, 0, (New-Object System.Drawing.Size $sc.Width, $sc.Height))
        $g.Dispose()
        $dir = if (Get-Command Get-WorkPath -ErrorAction SilentlyContinue) { Get-WorkPath 'AI\screenshots' } else { Join-Path $env:TEMP 'PackagingAgent\screenshots' }
        try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch {}
        # JPEG, not PNG. A full-screen PNG comes back as ~210,000 base64 characters, and a few of those would crowd
        # out the order itself; the same screen as JPEG is a fraction of that and perfectly readable for "is there a
        # dialog on screen and what does it say".
        $f = Join-Path $dir ("screen_{0}.jpg" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
        $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
        if ($enc) {
            $ep = New-Object System.Drawing.Imaging.EncoderParameters 1
            $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([long]72)
            $bmp.Save($f, $enc, $ep)
        } else { $bmp.Save($f, [System.Drawing.Imaging.ImageFormat]::Jpeg) }
        $res.width = $bmp.Width; $res.height = $bmp.Height; $bmp.Dispose()
        $res.ok = $true; $res.path = $f; $res.takenAt = (Get-Date -Format 'HH:mm:ss')
    } catch { $res.note = "the screen could not be captured: $($_.Exception.Message)"; return $res }
    # what is actually on screen, named - far easier to reason about than pixels alone
    try {
        # every window, not one per process - a second dialog or a console in Windows Terminal is otherwise missing
        $res.visibleWindows = if (Get-Command Get-AgentVisibleWindows -ErrorAction SilentlyContinue) {
            @(Get-AgentVisibleWindows | Select-Object -First 30 | ForEach-Object { [ordered]@{ process = "$($_.process)"; title = "$($_.title)"; class = "$($_.class)" } })
        } else {
            @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and "$($_.MainWindowTitle)".Trim() } |
              Select-Object -First 20 | ForEach-Object { [ordered]@{ process = $_.ProcessName; title = "$($_.MainWindowTitle)" } })
        }
    } catch {}
    $res.note = "screen captured$(if (@($res.visibleWindows).Count) { "; $(@($res.visibleWindows).Count) window(s) with titles are listed" })."
    return $res
}

function Get-AgentEvidenceTools {
    # A CAPABILITY, OFFERED - never taken at the AI and never pushed into its context. It asks for a picture when it
    # decides it needs one, the same way it asks to run a command. The image comes back as an image, not as a path.
    return @(
        @{ Ctx = @{}
           Decl = (New-AgentFunctionDeclaration -Name 'take_screenshot' `
                    -Description 'Take a picture of this machine''s screen and look at it. Use it whenever the answer is on screen and nowhere else: an installer that may be showing a dialog rather than installing silently, a wizard waiting on a click, an error box, or checking that the application you installed actually starts. Returns the image itself plus the titles of the visible windows. Give a short reason, and a delay in seconds if something needs a moment to appear.' `
                    -Parameters @{ type = 'OBJECT'; properties = @{
                        why = @{ type = 'STRING'; description = 'what you are hoping to see - recorded with the picture' }
                        delaySeconds = @{ type = 'INTEGER'; description = 'wait this long before capturing, up to 30, when something needs a moment to appear' } }
                        required = @('why') })
           Run = { param($a, $c)
                   $r = Get-AgentScreenshot -Why "$($a.why)" -DelaySeconds ([int]"$($a.delaySeconds)")
                   if (-not $r.ok) { return $r }
                   # Hand back the PICTURE, not a path the AI cannot open.
                   # MaxEdge is what actually controls the size: New-AgentImagePart re-encodes at its own default
                   # quality, so the quality chosen when saving is discarded. 900px keeps a dialog and its text
                   # legible while costing roughly half what the full screen does.
                   $img = try { New-AgentImagePart -Path $r.path -MaxEdge 900 } catch { $null }
                   if ($img) { return @{ result = $r; images = @($img) } }
                   $r.note += ' (the image could not be attached - the file is on disk at the path above)'
                   return $r } }
    )
}

function Read-AgentDeliveredDocument {
    <#
      OPEN A DOCUMENT THE WAY A PERSON WOULD - the words AND the pictures.

      Only the request form was ever read, once, at intake. Everything else the orderer sent - the install
      instructions, the MRF, the complexity matrix, a mail saved as a document - was listed by name and never
      opened. A packager opens them. More than that, the useful part of these documents is very often a SCREENSHOT
      of the wizard showing which options were ticked, and no amount of text extraction will tell you that.

      So: the text, and the embedded images handed back as images to actually look at.
    #>
    param([Parameter(Mandatory)][string]$Path, [int]$MaxChars = 12000, [int]$MaxImages = 6)
    $res = [ordered]@{ ok = $false; path = "$Path"; kind = ''; text = ''; truncated = $false; imageCount = 0; note = '' }
    if (-not (Test-Path -LiteralPath $Path)) { $res.note = 'that file is not there - check the path against the delivery listing'; return @{ result = $res; images = @() } }
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $imgs = @()
    try {
        switch -Regex ($ext) {
            '^\.docx$' {
                $dir = if (Get-Command Get-WorkPath -ErrorAction SilentlyContinue) { Get-WorkPath 'AI\docimages' } else { Join-Path $env:TEMP 'PackagingAgent\docimages' }
                try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch {}
                $d = Read-AgentDocx -Path $Path -ImageDir $dir
                $res.kind = 'Word document'; $res.ok = [bool]$d.Ok; $res.text = "$($d.Text)"
                # the extracted file is under 'File'; 'Caption' is the text either side of the picture in the
                # document, which is what says WHICH step the screenshot is showing - send it with the picture
                $shots = New-Object System.Collections.Generic.List[string]
                foreach ($im in @($d.Images | Select-Object -First $MaxImages)) {
                    $p = if ($im -is [string]) { $im } else { "$(@($im.File, $im.Path) | Where-Object { "$_".Trim() } | Select-Object -First 1)" }
                    if (-not "$p".Trim() -or -not (Test-Path -LiteralPath $p)) { continue }
                    $ip = New-AgentImagePart -Path $p -MaxEdge 900
                    if (-not $ip) { continue }
                    $imgs += $ip
                    $cap = "$($im.Caption)"; if ($cap.Length -gt 300) { $cap = $cap.Substring(0, 300) + '...' }
                    $shots.Add("picture $(@($imgs).Count): $(if ($cap.Trim()) { $cap } else { 'no caption in the document' })")
                }
                if ($shots.Count) { $res.pictureCaptions = @($shots.ToArray()) }
                if (@($d.Notes).Count) { $res.note = (@($d.Notes) -join '; ') }
            }
            '^\.(xlsx|xlsm)$' {
                $x = Read-AgentXlsx -Path $Path
                $res.kind = 'Excel workbook'; $res.ok = [bool]$x.Ok; $res.text = "$($x.Text)"
                if (@($x.Notes).Count) { $res.note = (@($x.Notes) -join '; ') }
            }
            '^\.doc$' {
                $l = Read-AgentLegacyDoc -Path $Path
                $res.kind = 'legacy Word document'; $res.ok = [bool]$l.Ok; $res.text = "$($l.Text)"
                if (-not $res.ok) { $res.note = 'a legacy .doc cannot be read reliably without Word - ask the packager for a .docx' }
            }
            '^\.(txt|md|csv|log|xml|json|ini|cfg|js|ps1|bat|cmd|reg)$' {
                $res.kind = 'text file'; $res.text = try { [IO.File]::ReadAllText($Path) } catch { '' }; $res.ok = [bool]"$($res.text)".Length
            }
            '^\.(png|jpe?g|gif|bmp)$' {
                $res.kind = 'image'; $res.ok = $true; $res.text = '(an image - look at it below)'
                $ip = New-AgentImagePart -Path $Path -MaxEdge 900; if ($ip) { $imgs += $ip }
            }
            '^\.pdf$' { $res.kind = 'PDF'; $res.note = 'PDFs cannot be read here. Ask the packager what it says, or for it as a .docx.' }
            default   { $res.kind = "$ext"; $res.note = "nothing here can read a $ext - say so rather than guessing at what it contains" }
        }
    } catch { $res.note = "could not read it: $($_.Exception.Message)" }
    if ("$($res.text)".Length -gt $MaxChars) {
        $full = "$($res.text)".Length
        $res.text = "$($res.text)".Substring(0, $MaxChars) + "`n...(this is the first $MaxChars characters of $full. THE REST IS NOT HERE - and the part you have not seen is as likely to hold the instruction that matters as the part you have. Ask for it: read_document again on this file, or read it with run_powershell.)"
        $res.truncated = $true; $res.fullLength = $full
    }
    $res.imageCount = @($imgs).Count
    if (-not $res.note) { $res.note = "read as a $($res.kind)$(if ($res.imageCount) { " - $($res.imageCount) picture(s) from inside it are below; the wizard screenshots are usually the part that matters" })$(if ($res.truncated) { ' (text shortened - ask for more if you need it)' })." }
    return @{ result = $res; images = @($imgs) }
}

function Get-AgentDocumentTools {
    return @(
        @{ Ctx = @{}
           Decl = (New-AgentFunctionDeclaration -Name 'read_document' `
                    -Description 'Open a document delivered with the order and read it - the text AND the pictures inside it. Use it on anything in sources.documents: the install instructions, the request form, the MRF, the complexity matrix, a saved mail. The screenshots inside these documents are usually where the owner''s actual choices are shown - which components, which options, which install folder - and nothing else in the order records them. Handles .docx, .xlsx/.xlsm, .doc, images and plain text.' `
                    -Parameters @{ type = 'OBJECT'; properties = @{
                        path = @{ type = 'STRING'; description = 'the file, as relativePath from the delivery listing or a full path' } }
                        required = @('path') })
           Run = { param($a, $c)
                   $p = "$($a.path)".Trim().Trim('"').Trim("'")
                   if ($p -and -not (Test-Path -LiteralPath $p) -and "$($c.Folder)".Trim()) {
                       $try = try { Join-Path "$($c.Folder)" $p } catch { '' }
                       if ("$try".Trim() -and (Test-Path -LiteralPath $try)) { $p = $try }
                   }
                   return (Read-AgentDeliveredDocument -Path $p) } }
    )
}

function Get-AgentSearchTools {
    # Offered to the AI as a capability, exactly like run_powershell: it calls this when it wants to look, and the
    # tool answers with what is on the share. It is never run at the AI and its results are never pushed.
    # Arch and Version default to THIS order's, so the comparison happens whether or not the AI thought to pass
    # them - it called this with two words and no architecture, and every candidate came back "not a match".
    param([string]$Arch = '', [string]$Version = '')
    return @(
        @{ Ctx = @{ Arch = "$Arch"; Version = "$Version" }
           Decl = (New-AgentFunctionDeclaration -Name 'search_previous_packages' `
                    -Description 'Search the live and outgoing package shares for previous packages matching any terms you give - the installer file name, its ProductName, its manufacturer, a word from the application name. Use this whenever the predecessor search by folder name found nothing, or when the order folder name looks unusual: a team prefix in front of the name makes the automatic search read the wrong vendor and find nothing. Returns what is on the shares; which one is the predecessor is your judgement.' `
                    -Parameters @{ type = 'OBJECT'; properties = @{
                        terms = @{ type = 'ARRAY'; items = @{ type = 'STRING' }; description = 'vendor and application words first - then the installer file name, its ProductName, its manufacturer. Each term is split into words, so "beA Client Security" also finds "beAClientSecurity".' }
                        arch = @{ type = 'STRING'; description = 'this order''s architecture (x64/x86) - used to rank, never to exclude' }
                        version = @{ type = 'STRING'; description = 'this order''s version - a match on it is flagged, because that is usually this package rather than the one before it' } }
                        required = @('terms') })
           Run = { param($a, $c)
                   $arch = if ("$($a.arch)".Trim()) { "$($a.arch)" } else { "$($c.Arch)" }
                   $ver  = if ("$($a.version)".Trim()) { "$($a.version)" } else { "$($c.Version)" }
                   return (Search-AgentPreviousPackages -Terms @(@($a.terms) | ForEach-Object { "$_" }) -Arch "$arch" -Version "$ver") } }
    )
}

#  ---------------------------------------------------------------------------------------------------
#   WHAT THE INSTALLER REALLY DID - Process Monitor.
#
#   The snapshot says what changed. Process Monitor says what the installer DID, and one thing it records
#   that nothing else can give us: THE CHILD PROCESSES IT LAUNCHED, WITH THEIR COMMAND LINES. That is how
#   a packager finds the MSI a vendor wrapper extracted and the exact switches the wrapper passed to it -
#   which is the only route left for InstallShield and Wise suites, where no extractor works.
#
#   Needs elevation. Without it, say so and carry on: this is evidence, not a dependency.
#  ---------------------------------------------------------------------------------------------------
function Test-AgentElevated {
    try { return (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false }
}

function Start-AgentProcessTrace {
    <#
      Begins capturing to a backing file. Returns @{ ok; backingFile; note }. Always pair with Stop-AgentProcessTrace -
      a capture left running fills the disk.
    #>
    param([string]$BackingFile)
    $res = [ordered]@{ ok = $false; backingFile = ''; note = '' }
    $t = Initialize-AgentTools
    if (-not $t.procmon) { $res.note = 'Process Monitor is not available, so the child processes the installer launches cannot be seen'; return $res }
    if (-not (Test-AgentElevated)) { $res.note = 'Process Monitor needs elevation and this session is not elevated - the trace was not started'; return $res }
    if (-not "$BackingFile".Trim()) { $BackingFile = Join-Path ([IO.Path]::GetTempPath()) ("agent-trace-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.pml') }
    try { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $BackingFile) -ErrorAction SilentlyContinue | Out-Null } catch {}
    # A capture is BIG. Measured here: 459 MB for fifteen seconds of an idle machine, about 30 MB per second, and a
    # large suite installs for several minutes. Filling the system drive during an install would be a far worse
    # outcome than not having the trace, so check first and say no when there is not room.
    $freeGB = 0
    try {
        $drive = [IO.Path]::GetPathRoot((Get-Item -LiteralPath (Split-Path -Parent $BackingFile)).FullName)
        $freeGB = [math]::Round((Get-PSDrive -Name $drive.TrimEnd(':\') -ErrorAction Stop).Free / 1GB, 1)
    } catch { $freeGB = -1 }
    if ($freeGB -ge 0 -and $freeGB -lt 12) {
        $res.note = "only $freeGB GB free on $(Split-Path -Qualifier $BackingFile) - a trace grows by roughly 30 MB per second, so it was NOT started. The snapshot still records what changed; what is lost is the list of child processes the installer launched."
        return $res
    }
    try {
        # /Quiet skips the filter dialog, /Minimized keeps it out of the packager's way, /BackingFile writes to disk
        # rather than filling memory on a multi-gigabyte install.
        Start-Process -FilePath $t.procmon -ArgumentList @('/AcceptEula', '/Quiet', '/Minimized', '/BackingFile', "`"$BackingFile`"") -WindowStyle Minimized -ErrorAction Stop | Out-Null
        Start-Sleep -Seconds 4     # it needs a moment to load its driver before anything is captured
        $res.ok = $true; $res.backingFile = $BackingFile
        $res.note = "capturing to $(Split-Path -Leaf $BackingFile)"
    } catch { $res.note = "Process Monitor would not start: $($_.Exception.Message.Split([char]10)[0])" }
    return $res
}

function Stop-AgentProcessTrace {
    param([int]$TimeoutSeconds = 120)
    $res = [ordered]@{ ok = $false; note = '' }
    $t = Initialize-AgentTools
    if (-not $t.procmon) { $res.note = 'Process Monitor is not available'; return $res }
    $r = Invoke-AgentToolProcess -FilePath $t.procmon -Arguments @('/AcceptEula', '/Terminate') -TimeoutSeconds $TimeoutSeconds
    Start-Sleep -Seconds 2
    $res.ok = -not $r.timedOut
    $res.note = $(if ($r.timedOut) { 'the capture would not stop within the timeout' } else { 'capture stopped' })
    return $res
}

function Get-AgentProcessTraceFacts {
    <#
      Converts a capture to CSV and pulls out what is worth the AI's attention - above all the child processes the
      installer started and their full command lines. Returns facts; never a verdict.
    #>
    param(
        [Parameter(Mandatory)][string]$BackingFile,
        [int]$TimeoutSeconds = 240,
        [int]$MaxReported = 80,
        [switch]$KeepCapture
    )
    $res = [ordered]@{ childProcesses = @(); msiCommands = @(); writtenPaths = @(); configPathsRead = @(); settingsFilesItExpects = @(); eventCount = 0; note = ''; seconds = 0 }
    $t = Initialize-AgentTools
    if (-not $t.procmon) { $res.note = 'Process Monitor is not available'; return $res }
    if (-not (Test-Path -LiteralPath $BackingFile)) { $res.note = 'the capture file is not there - either the trace never started, or it was not stopped'; return $res }

    $csv = [IO.Path]::ChangeExtension($BackingFile, '.csv')
    $r = Invoke-AgentToolProcess -FilePath $t.procmon -Arguments @('/AcceptEula', '/OpenLog', "`"$BackingFile`"", '/SaveAs', "`"$csv`"") -TimeoutSeconds $TimeoutSeconds
    $res.seconds = $r.seconds
    if (-not (Test-Path -LiteralPath $csv)) { $res.note = "the capture could not be converted to CSV$(if ($r.timedOut) { ' (it took too long)' })"; return $res }

    # READ IT AS A STREAM. A trace of a long install is millions of rows; Import-Csv of all of it held the whole
    # evaluation for many minutes on a real order ("stuck while loading processes"). Only three kinds of row are ever
    # used - process creations, successful writes, config-file reads - so only those are parsed, and capped.
    $cfgExt = '(?i)\.(xml|json|ini|cfg|conf|config|properties|ya?ml|toml|plist|reg|js)"'
    $rowsCreate = New-Object System.Collections.Generic.List[object]; $rowsWrite = New-Object System.Collections.Generic.List[object]; $rowsCfg = New-Object System.Collections.Generic.List[object]
    $n = 0
    try {
        $rd = [IO.File]::OpenText($csv)
        try {
            $hdr = @(("$($rd.ReadLine())".TrimStart([char]0xFEFF)) -split '","' | ForEach-Object { $_.Trim('"') })
            while ($null -ne ($line = $rd.ReadLine())) {
                $n++
                $isCreate = $line.Contains('"Process Create"')
                $isWrite = (-not $isCreate) -and $rowsWrite.Count -lt 20000 -and $line -match '"(WriteFile|CreateFile)",' -and $line.Contains('"SUCCESS"')
                $isCfg = (-not $isCreate) -and $rowsCfg.Count -lt 20000 -and $line -match '"(CreateFile|QueryOpen|ReadFile)",' -and $line -match $cfgExt
                if (-not ($isCreate -or $isWrite -or $isCfg)) { continue }
                $o = ConvertFrom-Csv -InputObject $line -Header $hdr
                if ($isCreate) { $rowsCreate.Add($o) }; if ($isWrite) { $rowsWrite.Add($o) }; if ($isCfg) { $rowsCfg.Add($o) }
            }
        } finally { $rd.Dispose() }
    } catch { $res.note = "the converted CSV could not be read: $($_.Exception.Message.Split([char]10)[0])"; return $res }
    $res.eventCount = $n
    $rows = @($rowsWrite.ToArray()) + @($rowsCfg.ToArray())

    # THE VALUABLE PART. A "Process Create" event's Detail column carries the full command line of the child.
    $creates = @($rowsCreate.ToArray())
    $res.childProcesses = @($creates | Select-Object -First $MaxReported | ForEach-Object {
        [ordered]@{ startedBy = "$($_.'Process Name')"; path = "$($_.Path)"; detail = "$($_.Detail)" }
    })
    # and the ones that matter most: an msiexec launched by the wrapper names the MSI it extracted and the switches
    # the vendor chose for it - which is exactly what our package has to reproduce.
    $res.msiCommands = @(@($res.childProcesses) | Where-Object { "$($_.path)$($_.detail)" -match '(?i)msiexec|\.msi\b' })

    $writes = @($rows | Where-Object { "$($_.Operation)" -match '(?i)^(WriteFile|CreateFile)$' -and "$($_.Path)" -match '(?i)^[A-Z]:\\' -and "$($_.Result)" -eq 'SUCCESS' })
    $res.writtenPaths = @(@($writes | ForEach-Object { "$($_.Path)" } | Where-Object { $_ -notmatch '(?i)\\Windows\\(Temp|Prefetch|SoftwareDistribution)\\|\\\$Recycle' } | Select-Object -Unique -First $MaxReported))

    # WHERE THE APPLICATION LOOKS FOR ITS SETTINGS - and this is the half a snapshot can never show.
    # A snapshot only sees files that EXIST afterwards. When an application starts up and reads a preferences file or
    # a policy file that is not there yet, the attempt leaves no trace on disk at all - but the trace records it, with
    # Result = NAME NOT FOUND. That path is exactly the file a package must PLACE to pre-configure the application, and
    # it is the answer to a suppression the AI could otherwise only mark NOT SOLVED.
    $cfgExt = '(?i)\.(xml|json|ini|cfg|conf|config|properties|ya?ml|toml|plist|reg|js)$'
    $reads = @($rows | Where-Object { "$($_.Operation)" -match '(?i)^(CreateFile|QueryOpen|ReadFile)$' -and "$($_.Path)" -match $cfgExt })
    $res.configPathsRead = @(@($reads |
        Where-Object { "$($_.Path)" -notmatch '(?i)\\Windows\\(WinSxS|assembly|Microsoft\.NET|Fonts)\\|\\Program Files\\WindowsApps\\.*\\(resources|assets)\\' } |
        Group-Object -Property Path | Select-Object -First $MaxReported | ForEach-Object {
            $first = $_.Group[0]
            $missing = @($_.Group | Where-Object { "$($_.Result)" -match '(?i)NOT FOUND' }).Count
            [ordered]@{
                path = "$($_.Name)"
                readBy = "$($first.'Process Name')"
                existed = [bool](@($_.Group | Where-Object { "$($_.Result)" -eq 'SUCCESS' }).Count -gt 0)
                lookedForButMissing = [bool]($missing -gt 0)
            }
        }))
    $res.settingsFilesItExpects = @(@($res.configPathsRead) | Where-Object { $_.lookedForButMissing -and -not $_.existed })

    $res.note = "$($res.eventCount) event(s); $(@($creates).Count) process(es) started by the install, $(@($res.msiCommands).Count) of them naming an MSI. A child msiexec command line is the vendor's OWN silent command - it is better evidence than any switch we guessed, and for an InstallShield or Wise suite it is the only evidence there is."

    # The facts are extracted, so the capture is dead weight - and it is measured in hundreds of megabytes. Delete it
    # unless the caller wants it kept for a human to open in Process Monitor.
    if (-not $KeepCapture) {
        $freed = 0
        foreach ($x in @($BackingFile, $csv)) {
            try { if (Test-Path -LiteralPath $x) { $freed += (Get-Item -LiteralPath $x).Length; Remove-Item -LiteralPath $x -Force -ErrorAction Stop } } catch {}
        }
        if ($freed) { $res.note += " The capture itself ($([math]::Round($freed / 1MB)) MB) has been deleted now that the facts are out of it." }
    } else { $res.capture = $BackingFile }
    return $res
}

#  ---------------------------------------------------------------------------------------------------
#   WHAT THE APPLICATION WRITES THE FIRST TIME A USER STARTS IT.
#
#   The "may we send your usage data to us?" box, the marketing sign-up, the survey, the first-run wizard
#   and the accepted-licence flag are all written by the APPLICATION, per user, after the install - which
#   is why no install switch reaches them and why the install snapshot does not show them. The only way to
#   find the key or file each one reads is to start the application once and look at what appeared.
#
#   Deliberately narrow and quick: HKCU plus the user's own AppData, not a machine snapshot. Those are the
#   only places a per-user first-run setting can live.
#  ---------------------------------------------------------------------------------------------------
function Get-AgentUserStateSnapshot {
    param([int]$MaxKeys = 40000, [int]$MaxFiles = 40000)
    $snap = @{ keys = @{}; files = @{}; taken = (Get-Date) }
    try {
        $stack = New-Object System.Collections.Generic.Stack[string]
        $stack.Push('HKCU:\Software')
        $n = 0
        while ($stack.Count -and $n -lt $MaxKeys) {
            $path = $stack.Pop(); $n++
            $snap.keys[$path] = $true
            try { foreach ($k in @(Get-ChildItem -LiteralPath $path -ErrorAction SilentlyContinue)) { $stack.Push($k.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_CURRENT_USER', 'HKCU:') } } catch {}
        }
    } catch {}
    foreach ($root in @("$env:APPDATA", "$env:LOCALAPPDATA")) {
        if (-not "$root".Trim() -or -not (Test-Path -LiteralPath $root)) { continue }
        try { foreach ($f in @(Get-ChildItem -LiteralPath $root -File -Recurse -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First $MaxFiles)) { $snap.files[$f.FullName] = $f.LastWriteTimeUtc.Ticks } } catch {}
    }
    return $snap
}

function Get-AgentFirstRunDelta {
    <#
      Starts the application once, waits, closes it, and reports what it wrote to HKCU and AppData. That delta is
      where the first-run prompts keep their state, so it is what tells the package which value to pre-seed.
      Returns facts only: which keys and files appeared, with the values read back. What to set them to is the AI's call.
    #>
    param(
        [Parameter(Mandatory)][string]$LaunchPath,   # a shortcut or an exe
        [int]$SettleSeconds = 25,
        [int]$MaxReported = 60,
        # Record the start with Process Monitor as well. Worth it for ONE thing a snapshot can never show: the
        # settings file the application LOOKS FOR and does not find. That path is what a package has to place.
        [switch]$Trace
    )
    $res = [ordered]@{ launched = ''; ok = $false; newKeys = @(); changedFiles = @(); settingLike = @(); stillRunning = @(); settingsFilesItExpects = @(); traceNote = ''; note = ''; seconds = 0 }
    if (-not (Test-Path -LiteralPath $LaunchPath)) { $res.note = 'the application could not be found to start'; return $res }
    $res.launched = Split-Path -Leaf $LaunchPath

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $before = Get-AgentUserStateSnapshot

    # Which process is "the application" is not simply the one we started. Plenty of executables hand over to another
    # process and exit - Windows 11's own notepad.exe forwards to the Store build under a different PID - so stopping
    # only the PID we launched leaves the application running, holding its files open for the rest of the evaluation.
    # Note every PID beforehand, and work out what the application is actually called.
    $target = $LaunchPath
    if ($LaunchPath -match '(?i)\.lnk$' -and (Get-Command Resolve-ShortcutTarget -ErrorAction SilentlyContinue)) {
        try { $rt = Resolve-ShortcutTarget -Path $LaunchPath; if ("$rt".Trim()) { $target = "$rt" } } catch {}
    }
    $targetName = ''
    try { $targetName = [IO.Path]::GetFileNameWithoutExtension($target) } catch {}
    $preIds = @{}
    try { foreach ($pp in @(Get-Process -ErrorAction SilentlyContinue)) { $preIds[$pp.Id] = $true } } catch {}

    $runTrace = $null
    if ($Trace) {
        $runTrace = Start-AgentProcessTrace
        $res.traceNote = $runTrace.note
    }

    $proc = $null
    try {
        # A shortcut has to go through the shell; an exe can be started directly.
        if ($LaunchPath -match '(?i)\.lnk$') { $proc = Start-Process -FilePath $LaunchPath -PassThru -ErrorAction Stop }
        else { $proc = Start-Process -FilePath $LaunchPath -PassThru -WorkingDirectory (Split-Path -Parent $LaunchPath) -ErrorAction Stop }
    } catch {
        $res.note = "the application would not start: $($_.Exception.Message.Split([char]10)[0])"
        $sw.Stop(); $res.seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); return $res
    }
    Start-Sleep -Seconds $SettleSeconds

    # Everything that appeared since the launch and belongs to this application: the PID we started, plus anything of
    # the same name that was not running before.
    $mine = New-Object System.Collections.Generic.List[object]
    try { $p0 = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue; if ($p0) { $mine.Add($p0) } } catch {}
    if ($targetName) {
        try { foreach ($pp in @(Get-Process -Name $targetName -ErrorAction SilentlyContinue)) { if (-not $preIds[$pp.Id] -and -not @($mine | Where-Object { $_.Id -eq $pp.Id }).Count) { $mine.Add($pp) } } } catch {}
    }

    # Close politely first: force-killing an application that is showing a modal dialog leaves a ghost window behind
    # that cannot be cleared, so the dialogs have to go before the process does.
    # .ToArray(), not @(): wrapping a List[object] of PSObjects in @() throws "Argument types do not match" on 5.1.
    $mineArr = $mine.ToArray()
    foreach ($pp in $mineArr) { try { if ($pp.MainWindowHandle -ne 0) { [void]$pp.CloseMainWindow() } } catch {} }
    Start-Sleep -Seconds 3
    foreach ($pp in $mineArr) {
        try { if (@(Get-Process -Id $pp.Id -ErrorAction SilentlyContinue).Count) { Stop-Process -Id $pp.Id -Force -ErrorAction SilentlyContinue } } catch {}
    }
    Start-Sleep -Milliseconds 500
    $stillUp = @()
    if ($targetName) { try { $stillUp = @(Get-Process -Name $targetName -ErrorAction SilentlyContinue | Where-Object { -not $preIds[$_.Id] }) } catch {} }

    if ($runTrace -and $runTrace.ok) {
        [void](Stop-AgentProcessTrace)
        $tf = Get-AgentProcessTraceFacts -BackingFile $runTrace.backingFile
        $res.settingsFilesItExpects = @($tf.settingsFilesItExpects)
        $res.traceNote = "recorded the start: $(@($tf.configPathsRead).Count) settings file(s) touched, $(@($res.settingsFilesItExpects).Count) of them looked for and NOT there. A file it looks for and does not find is the file the package should place."
    }

    $after = Get-AgentUserStateSnapshot
    $sw.Stop(); $res.seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)

    $newKeys = @(@($after.keys.Keys) | Where-Object { -not $before.keys.ContainsKey($_) })
    $touched = @(@($after.files.Keys) | Where-Object { -not $before.files.ContainsKey($_) -or $before.files[$_] -ne $after.files[$_] })
    $res.changedFiles = @($touched | Select-Object -First $MaxReported)

    $recs = New-Object System.Collections.Generic.List[object]
    foreach ($k in @($newKeys | Select-Object -First $MaxReported)) {
        $vals = @()
        if (Get-Command Get-SnapshotRegValuesFor -ErrorAction SilentlyContinue) { try { $vals = @(Get-SnapshotRegValuesFor -KeyPath $k -Max 30) } catch {} }
        elseif (Get-Command Read-RegValues -ErrorAction SilentlyContinue) { try { $h = Read-RegValues -Path $k; $vals = @($h.GetEnumerator() | ForEach-Object { @{ Name = $_.Key; Value = "$($_.Value)" } }) } catch {} }
        $recs.Add([ordered]@{ key = $k; values = @($vals) })
    }
    $res.newKeys = @($recs.ToArray())
    $res.settingLike = @(@($res.newKeys) | ForEach-Object {
        $kk = $_.key
        @($_.values) | Where-Object { "$($_.Name)" -match "(?i)$script:AgentPreferenceWords" } | ForEach-Object { [ordered]@{ key = $kk; name = "$($_.Name)"; value = "$($_.Value)" } }
    })
    $res.ok = $true
    $res.stillRunning = @(@($stillUp) | ForEach-Object { "$($_.ProcessName) (pid $($_.Id))" })
    $res.note = "started $($res.launched), waited $SettleSeconds s, closed it: $(@($newKeys).Count) new HKCU key(s), $(@($touched).Count) file(s) written under AppData. Anything a first-run prompt remembers is in here - a value named nothing like 'telemetry' still counts, so read the whole list, not only ``settingLike``.$(if (@($stillUp).Count) { " NOTE: $(@($res.stillRunning) -join ', ') would not close and is still running - anything measured after this point may be affected by it." })"
    return $res
}

function Copy-AgentExtractedMsiIntoPackage {
    <#
      Route 5 placement. Puts the chosen MSI into the package's Files folder, and when that MSI needs external
      cabinets it takes the whole folder it lived in inside the wrapper, because the MSI alone would install
      nothing. Returns what was placed and what was removed, for the handover record.
    #>
    param(
        [Parameter(Mandatory)]$Candidate,          # one record from Get-AgentExtractedMsiFacts
        [Parameter(Mandatory)][string]$WrapperPath,# the installer it came out of, for a re-extract
        [Parameter(Mandatory)][string]$FilesDest,
        [int]$TimeoutSeconds = 900
    )
    $res = [ordered]@{ placed = @(); removedWrapper = ''; note = ''; ok = $false }
    if (-not $Candidate -or -not "$($Candidate.file)".Trim()) { $res.note = 'no MSI was named'; return $res }
    try { New-Item -ItemType Directory -Force -Path $FilesDest -ErrorAction Stop | Out-Null } catch { $res.note = "cannot write to $FilesDest"; return $res }

    $needsSiblings = -not [bool]$Candidate.selfContained
    $sourceDir = ''
    if ("$($Candidate.path)".Trim() -and (Test-Path -LiteralPath "$($Candidate.path)")) {
        $sourceDir = Split-Path -Parent "$($Candidate.path)"
    } else {
        # The extraction happened in an earlier stage and its temp folder is gone - take it out again.
        $insight = Get-AgentArchiveInsight -Path $WrapperPath
        $entry = @(@($insight.msiCandidates) | Where-Object { (Split-Path -Leaf $_) -eq "$($Candidate.file)" } | Select-Object -First 1)
        if (-not $entry.Count) { $res.note = "$($Candidate.file) is no longer listed inside $(Split-Path -Leaf $WrapperPath)"; return $res }
        # With external cabinets, everything in that folder inside the wrapper has to come out, not just the MSI.
        $ask = if ($needsSiblings) { @((Split-Path -Parent $entry[0]) + '\*') } else { @($entry[0]) }
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('agent-route5-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $ex = Expand-AgentArchiveEntries -Path $WrapperPath -Entries $ask -Destination $tmp -TimeoutSeconds $TimeoutSeconds
        if (-not @($ex.extracted).Count) { $res.note = "could not take $($Candidate.file) out again: $($ex.note)"; return $res }
        $hit = @(@($ex.extracted) | Where-Object { (Split-Path -Leaf $_) -eq "$($Candidate.file)" } | Select-Object -First 1)
        if (-not $hit.Count) { $res.note = "the extract did not contain $($Candidate.file)"; return $res }
        $sourceDir = Split-Path -Parent $hit[0]
    }

    $toCopy = if ($needsSiblings) {
        @(Get-ChildItem -LiteralPath $sourceDir -File -Recurse -ErrorAction SilentlyContinue)
    } else {
        @(Get-ChildItem -LiteralPath $sourceDir -File -Filter "$($Candidate.file)" -ErrorAction SilentlyContinue)
    }
    if (-not $toCopy.Count) { $res.note = "nothing to copy out of $sourceDir"; return $res }
    foreach ($f in $toCopy) {
        try { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $FilesDest $f.Name) -Force -ErrorAction Stop; $res.placed += $f.Name } catch {}
    }

    # The wrapper itself is no longer what gets installed, so it must not sit in the package pretending otherwise.
    $wrapName = Split-Path -Leaf $WrapperPath
    $inFiles = Join-Path $FilesDest $wrapName
    if (Test-Path -LiteralPath $inFiles) {
        try { Remove-Item -LiteralPath $inFiles -Force -ErrorAction Stop; $res.removedWrapper = $wrapName } catch {}
    }

    $res.ok = [bool]@($res.placed).Count
    $res.note = "placed $(@($res.placed).Count) file(s)$(if ($needsSiblings) { ' including the cabinets the MSI needs' })$(if ($res.removedWrapper) { "; removed the wrapper $($res.removedWrapper) because the MSI is what installs now" })"
    return $res
}

#  ---------------------------------------------------------------------------------------------------
#   MSI identity. The COM reader we used before is not deterministic - its OpenView/StringData path
#   can hand back rows in a different order on the same file - so prefer the managed library and keep
#   COM only as the fallback. Returns $null when the file cannot be read at all.
#  ---------------------------------------------------------------------------------------------------
function Get-AgentMsiIdentity {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $full = (Get-Item -LiteralPath $Path).FullName
    $t = Initialize-AgentTools

    if ($t.dtf) {
        $db = $null
        try {
            $db = New-Object Microsoft.Deployment.WindowsInstaller.Database($full, [Microsoft.Deployment.WindowsInstaller.DatabaseOpenMode]::ReadOnly)
            $prop = {
                param($name)
                try { $db.ExecuteScalar("SELECT ``Value`` FROM ``Property`` WHERE ``Property``='$name'") } catch { $null }
            }
            $tables = @()
            try { $tables = @($db.Tables | ForEach-Object { $_.Name }) } catch {}
            # Does this MSI carry its payload inside, or does it reference CAB files that sit NEXT to it? An MSI
            # pulled out of a wrapper on its own installs nothing when its cabinets were left behind. A cabinet name
            # starting with '#' is embedded in the MSI; anything else is an external file that must travel with it.
            $extCabs = @()
            if ($tables -contains 'Media') {
                try {
                    $v = $db.OpenView("SELECT ``Cabinet`` FROM ``Media``"); $v.Execute()
                    while ($true) {
                        $rec = $v.Fetch(); if (-not $rec) { break }
                        $cab = "$($rec.GetString(1))".Trim()
                        if ($cab -and -not $cab.StartsWith('#')) { $extCabs += $cab }
                        $rec.Close()
                    }
                    $v.Close()
                } catch {}
            }
            return [ordered]@{
                path           = $full
                readBy         = 'WiX DTF'
                productName    = [string](& $prop 'ProductName')
                productVersion = [string](& $prop 'ProductVersion')
                productCode    = [string](& $prop 'ProductCode')
                upgradeCode    = [string](& $prop 'UpgradeCode')
                manufacturer   = [string](& $prop 'Manufacturer')
                allUsers       = [string](& $prop 'ALLUSERS')
                hasUiSequence  = [bool]($tables -contains 'InstallUISequence')
                tableCount     = $tables.Count
                externalCabs   = @($extCabs | Select-Object -Unique)
                selfContained  = [bool](@($extCabs).Count -eq 0)
            }
        } catch {
            # fall through to COM
        } finally { if ($db) { try { $db.Dispose() } catch {} } }
    }

    # Fallback: the engine already knows how to read a property over COM - reuse it rather than
    # writing a second reader.
    if (Get-Command Get-MsiProperty -ErrorAction SilentlyContinue) {
        try {
            return [ordered]@{
                path           = $full
                readBy         = 'COM (fallback)'
                productName    = [string](Get-MsiProperty -Path $full -Property 'ProductName')
                productVersion = [string](Get-MsiProperty -Path $full -Property 'ProductVersion')
                productCode    = [string](Get-MsiProperty -Path $full -Property 'ProductCode')
                upgradeCode    = [string](Get-MsiProperty -Path $full -Property 'UpgradeCode')
                manufacturer   = [string](Get-MsiProperty -Path $full -Property 'Manufacturer')
                allUsers       = ''
                hasUiSequence  = $null
                tableCount     = $null
            }
        } catch { return $null }
    }
    return $null
}

#  ---------------------------------------------------------------------------------------------------
#   Does this transform actually apply to this MSI? We could never answer that honestly before, and a
#   transform built against the wrong build installs nothing and fails at the customer. Applying it to
#   a THROWAWAY COPY is the real test: Windows Installer itself refuses a transform whose validation
#   does not match, so if the copy takes it, the package is sound.
#  ---------------------------------------------------------------------------------------------------
function Test-AgentMstApplies {
    param(
        [Parameter(Mandatory)][string]$MsiPath,
        [Parameter(Mandatory)][string]$MstPath
    )
    $res = [ordered]@{ applies = $null; checkedBy = 'not checked'; reason = ''; msi = $null; changes = $null }
    if (-not (Test-Path -LiteralPath $MsiPath)) { $res.reason = 'the MSI is not reachable'; return $res }
    if (-not (Test-Path -LiteralPath $MstPath)) { $res.reason = 'the transform is not reachable'; return $res }

    $t = Initialize-AgentTools
    if (-not $t.dtf) { $res.reason = 'the MSI library is not available, so this cannot be proven'; return $res }

    $res.msi = Get-AgentMsiIdentity -Path $MsiPath
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("agent-mst-{0}.msi" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
    $db = $null
    try {
        Copy-Item -LiteralPath $MsiPath -Destination $tmp -Force -ErrorAction Stop
        # Clear read-only: a copied-from-share MSI is often read-only, and the transform APIs fail on
        # a read-only target with an error that names three unrelated parameters.
        try { (Get-Item -LiteralPath $tmp).IsReadOnly = $false } catch {}

        $db = New-Object Microsoft.Deployment.WindowsInstaller.Database($tmp, [Microsoft.Deployment.WindowsInstaller.DatabaseOpenMode]::Transact)
        $before = 0; try { $before = @($db.Tables | ForEach-Object { $_.Name }).Count } catch {}
        # TransformErrors.None = suppress nothing. If it does not belong to this MSI, this throws.
        $db.ApplyTransform($(Get-Item -LiteralPath $MstPath).FullName, [Microsoft.Deployment.WindowsInstaller.TransformErrors]::None)
        $after = 0; try { $after = @($db.Tables | ForEach-Object { $_.Name }).Count } catch {}
        $res.applies = $true
        $res.checkedBy = 'WiX DTF, applied to a throwaway copy'
        $res.reason = 'Windows Installer accepted the transform against this MSI'
        $res.changes = [ordered]@{ tablesBefore = $before; tablesAfter = $after }
    } catch {
        $res.applies = $false
        $res.checkedBy = 'WiX DTF, applied to a throwaway copy'
        $res.reason = $_.Exception.Message.Split([char]10)[0]
    } finally {
        if ($db) { try { $db.Dispose() } catch {} }
        try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch {}
    }
    return $res
}
