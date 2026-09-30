##############################################################
# Agent.Core.ps1  -  THE HANDS.
# The sheet, the flow, and everything the tool does itself: read the order, fingerprint installers, find the previous
# version by name, place files, build the package from the team template, install and measure on this machine, and
# write the report. Every JUDGEMENT is the AI's and lives in Agent.Brain.ps1; nothing here chooses a command.
#
#   intake -> plan (AI) -> prepare -> evaluate (gate; AI judges) -> build -> verify (AI) -> handover
# The sheet is JSON on disk under WorkRoot\AI\<package>\ plus an HTML report.
##############################################################

#region Sheet ------------------------------------------------------------------------------------------------------
function New-AgentSheet {
    param([string]$PkgName, [string]$Ritm, [string]$Folder)
    return [ordered]@{
        schema = 'eval-sheet/1.0'; generated = (Get-Date -Format 'yyyy-MM-dd HH:mm'); package = "$PkgName"; ritm = "$Ritm"; folder = "$Folder"
        brand = $(try { "$(Get-Setting 'Brand' 'MTB')" } catch { 'MTB' })
        status = 'new'                      # new | blocked | ask_ao | ready | evaluated  (kept: the short answer)
        stages = [ordered]@{}               # the FLOW: one record per stage - see Get-AgentPipeline
        identity = [ordered]@{}; sources = [ordered]@{}; documents = [ordered]@{}
        declared = [ordered]@{}             # the form's tick boxes, read by rule
        history = [ordered]@{}              # predecessor / knowledge base / catalogue
        gaps = @()                          # @{ id; severity = block|ask|info; text; question }
        plan = [ordered]@{}                 # AI: route, what to install, what the test must prove, what the package does
        observed = [ordered]@{}             # snapshot run facts
        decision = [ordered]@{}             # AI: what the test install did, and what the package must therefore do
        audit = [ordered]@{}
        timeline = @()
    }
}
function Add-AgentTimeline { param($Sheet, [string]$Text) $Sheet.timeline += @{ at = (Get-Date -Format 'HH:mm:ss'); text = "$Text" } }
function Get-AgentSheetDir {
    param($Sheet)
    $name = if ("$($Sheet.package)".Trim()) { "$($Sheet.package)" } else { 'order' }
    $safe = ($name -replace '[\\/:*?"<>|]', '_')
    $dir = if (Get-Command Get-WorkPath -ErrorAction SilentlyContinue) { Get-WorkPath "AI\$safe" } else { Join-Path $env:TEMP "PackagingAgent\$safe" }
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch {}
    return $dir
}
function Save-AgentSheet {
    param([Parameter(Mandatory)]$Sheet)
    $dir = Get-AgentSheetDir -Sheet $Sheet
    $Sheet.audit = Get-AgentUsageSummary
    # keep the working conversation out of the saved sheet, then put it back for the rest of the run
    $conv = $null
    if ($Sheet.Contains('conversation')) { $conv = $Sheet.conversation; $Sheet.Remove('conversation') }
    try { return (Save-AgentSheetInner -Sheet $Sheet -Dir $dir) }
    finally { if ($null -ne $conv) { $Sheet['conversation'] = $conv } }
}

function Save-AgentSheetInner {
    param([Parameter(Mandatory)]$Sheet, [Parameter(Mandatory)][string]$Dir)
    $dir = $Dir
    $json = Join-Path $dir 'evaluation-sheet.json'; $html = Join-Path $dir 'evaluation-sheet.html'
    try { $Sheet | ConvertTo-Json -Depth 20 | Out-File -LiteralPath $json -Encoding utf8 -Force } catch { Write-Log "AI: sheet save failed: $($_.Exception.Message)" Warning }
    try { ConvertTo-AgentSheetHtml -Sheet $Sheet | Out-File -LiteralPath $html -Encoding utf8 -Force } catch { Write-Log "AI: sheet html failed: $($_.Exception.Message)" Warning }
    return @{ Json = $json; Html = $html; Dir = $dir }
}
function Read-AgentSheet { param([string]$Path) if (-not (Test-Path -LiteralPath $Path)) { return $null }; try { return (ConvertTo-AgentHashtable ((Get-Content -LiteralPath $Path -Raw) | ConvertFrom-Json)) } catch { return $null } }
#endregion

#region Pipeline (the flow) ------------------------------------------------------------------------------------------
# ONE definition of how a package moves through the agent. The sheet stores where it got to, and the window, the CLI
# and the report all read the flow from here - no stage is "somewhere else".
#
#   intake (hands) -> plan (AI) -> prepare (hands) -> evaluate (GATE: hands install, AI judges)
#     -> build (hands) -> verify (AI checks and fixes) -> handover (hands)
#
# The AI is asked exactly where a packager's judgement is needed: planning, reading the test, signing off. Everything
# in between is the hands. The one human gate is before anything is installed on this machine.
function Get-AgentPipeline {
    return @(
        [ordered]@{ Id = 'intake';   Title = 'Read the order';               Phase = 'Understand'; Needs = @();                      Gate = $false; Owner = 'tool'; Say = 'Reading the order - copying it locally, fingerprinting the installers, looking for the previous version.'
                    What = 'The hands gather the dossier: the delivered files and what their headers say, the documents, the previous version by name, what is already on this machine. No judgement.' }
        [ordered]@{ Id = 'plan';     Title = 'Plan the package';             Phase = 'Understand'; Needs = @('intake');              Gate = $false; Owner = 'agent'; Say = 'Reading everything and planning the package.'
                    What = 'The AI reads the dossier, settles the previous version, chooses the route, and says exactly what to install, what the test must prove and what the package must do - with the questions that are still open.' }
        [ordered]@{ Id = 'prepare';  Title = 'Prepare the source';           Phase = 'Evaluate';   Needs = @('plan');                Gate = $false; Owner = 'tool'; Say = 'Getting the source ready.'
                    What = 'Expand a delivered zip, or hand you the one thing only a person can do - record a response file, supply a licence - exactly as the plan asked.' }
        [ordered]@{ Id = 'evaluate'; Title = 'Test-install on this machine'; Phase = 'Evaluate';   Needs = @('prepare');             Gate = $true;  Owner = 'agent'; Say = 'Installing it here for real, and watching exactly what it does.'
                    What = 'Remove what the plan said must go, baseline snapshot, run the planned install lines, snapshot again, then the AI judges what the installer really did.' }
        [ordered]@{ Id = 'build';    Title = 'Build it with our template';   Phase = 'Create';     Needs = @('plan', 'evaluate');    Gate = $false; Owner = 'tool'; Say = 'Building the package from our template.'
                    What = 'The hands build it - from the predecessor''s script when the plan reuses it (the AI''s changes applied as written), otherwise fresh from the template with the AI''s steps at the section markers. Delivered files placed with their folder tree.' }
        [ordered]@{ Id = 'verify';   Title = 'Check and finish the package'; Phase = 'Verify';     Needs = @('build');               Gate = $false; Owner = 'agent'; Say = 'Checking the finished package, and fixing what is wrong.'
                    What = 'The AI reads the built script against the order, the source, the test and the predecessor, fixes it in place, runs every check, and signs it off - or says exactly why not.' }
        [ordered]@{ Id = 'handover'; Title = 'Hand it over';                 Phase = 'Handover';   Needs = @('intake');              Gate = $false; Owner = 'tool'; Say = 'Writing everything up and handing it over.'
                    NeedsCommand = 'Export-AgentEvaluation'
                    What = 'Evaluation sheet, agent-handover.json and the snapshot report Package Assistance can load.' }
    )
}
function Get-AgentStageDef { param([Parameter(Mandatory)][string]$Id) return (Get-AgentPipeline | Where-Object { $_.Id -eq $Id } | Select-Object -First 1) }

# Stamp where a stage got to. Status: done | failed | skipped | running.
function Set-AgentStage {
    param([Parameter(Mandatory)]$Sheet, [Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Status, [string]$Note, [hashtable]$Data)
    if (-not $Sheet.stages) { $Sheet.stages = [ordered]@{} }
    $rec = [ordered]@{ status = "$Status"; at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); note = "$Note" }
    if ($Data) { foreach ($k in $Data.Keys) { $rec[$k] = $Data[$k] } }
    $Sheet.stages["$Id"] = $rec
    return $Sheet
}
function Get-AgentStageStatus { param($Sheet, [string]$Id) if ($Sheet.stages -and $Sheet.stages["$Id"]) { return "$($Sheet.stages["$Id"].status)" }; return '' }

# The flow as it stands right now: every stage with state = done | failed | ready | waiting | blocked, and WHY.
# 'waiting' = a human has to say go (the evaluate gate, or the tool has to build). 'blocked' = a prerequisite is missing.
function Get-AgentFlow {
    param([Parameter(Mandatory)]$Sheet)
    $out = @()
    foreach ($st in (Get-AgentPipeline)) {
        $own = "$(Get-AgentStageStatus -Sheet $Sheet -Id $st.Id)"
        # a SKIPPED prerequisite is a decision, not a failure - it must not stall everything behind it
        $missing = @($st.Needs | Where-Object { (Get-AgentStageStatus -Sheet $Sheet -Id $_) -notin 'done', 'skipped' })
        $state = ''; $why = ''
        if ($own -in 'done', 'failed', 'skipped') { $state = $own; $why = "$($Sheet.stages["$($st.Id)"].note)" }
        elseif ($missing.Count) { $state = 'blocked'; $why = "needs: $($missing -join ', ')" }
        elseif ("$($st.NeedsCommand)".Trim() -and -not (Get-Command "$($st.NeedsCommand)" -ErrorAction SilentlyContinue)) { $state = 'waiting'; $why = 'runs in the agent window (the CLI does not load the export)' }
        elseif ($st.Gate) { $state = 'waiting'; $why = 'needs your go-ahead - it installs on this machine' }
        else { $state = 'ready'; $why = '' }
        # intake decided the order is not workable yet: evaluating it would waste a machine
        if ($st.Id -eq 'evaluate' -and $state -eq 'waiting' -and "$($Sheet.status)" -eq 'blocked') { $state = 'blocked'; $why = 'the order is blocked - clarify with the AO first' }
        $out += [ordered]@{ id = $st.Id; title = $st.Title; owner = $st.Owner; state = $state; why = $why; what = $st.What }
    }
    return $out
}
function Get-AgentNextStage { param([Parameter(Mandatory)]$Sheet) return (@(Get-AgentFlow -Sheet $Sheet | Where-Object { $_.state -in 'ready', 'waiting' }) | Select-Object -First 1) }

# Run ONE stage by name. Everything the stage needs beyond the sheet travels in -With (folder, built script path, ...).
function Invoke-AgentStage {
    param([Parameter(Mandatory)]$Sheet, [Parameter(Mandatory)][string]$Id, [hashtable]$With = @{}, [scriptblock]$Progress)
    $def = Get-AgentStageDef -Id $Id
    if (-not $def) { throw "Unknown stage '$Id'. Known: $((Get-AgentPipeline | ForEach-Object { $_.Id }) -join ', ')" }
    # A SKIPPED prerequisite counts as satisfied, exactly as Get-AgentFlow already treats it. Skipping is a normal
    # decision here - no predecessor to compare with, the packager chose to move on, a failed stage the packager
    # decided to carry on without - and the two used to disagree: the flow showed the next stage as READY and this
    # threw "needs these first" the moment it was clicked.
    $missing = @($def.Needs | Where-Object { (Get-AgentStageStatus -Sheet $Sheet -Id $_) -notin 'done', 'skipped' })
    if ($missing.Count -and -not $With.Force) { throw "Stage '$Id' needs these first: $($missing -join ', ')" }
    switch ($Id) {
        'intake'   { # the console hands over a fresh sheet; the CLI passes only the folder
                     $f = "$($With.Folder)"; if (-not $f -and $Sheet) { $f = "$($Sheet.folder)" }
                     $n = "$($With.PkgName)"; if (-not $n -and $Sheet) { $n = "$($Sheet.package)" }
                     return (Invoke-AgentIntake -Folder $f -PkgName $n -Ritm "$($With.Ritm)" -SkipPredecessor:([bool]$With.SkipPredecessor) -Progress $Progress) }
        'plan'     { if ($With.NoModel) { return (Set-AgentStage -Sheet $Sheet -Id 'plan' -Status 'skipped' -Note 'no model this run') }
                     return (Invoke-AgentPlan -Sheet $Sheet -Progress $Progress) }
        'prepare'  { return (Invoke-AgentPrepare -Sheet $Sheet -Progress $Progress) }
        'evaluate' { throw 'The evaluation runs on this machine: start it from the agent window (it needs elevation and a real install).' }
        'build'    { # -BuiltScript means a package already exists (built elsewhere); otherwise the agent builds it now
                     $p = "$($With.BuiltScript)"
                     if ($p -and (Test-Path -LiteralPath $p)) { return (Set-AgentStage -Sheet $Sheet -Id 'build' -Status 'done' -Note "already built: $(Split-Path -Leaf $p)" -Data @{ script = "$p"; folder = (Split-Path -Parent $p) }) }
                     return (Invoke-AgentPackageBuild -Sheet $Sheet -TemplatePath "$($With.TemplatePath)" -Destination "$($With.Destination)" -Progress $Progress) }
        'verify'   { $p = "$($With.BuiltScript)"; if (-not $p) { $p = "$($Sheet.stages.build.script)" }
                     if (-not $p -or -not (Test-Path -LiteralPath $p)) { throw "Stage 'verify': no built script to read - run the build stage first, or pass -BuiltScript." }
                     return (Invoke-AgentVerifyLoop -Sheet $Sheet -ScriptPath $p -Progress $Progress) }
        'handover' { if (-not (Get-Command Export-AgentEvaluation -ErrorAction SilentlyContinue)) { throw 'Stage ''handover'' needs Agent.Ui.ps1 (it is loaded by Start-PackagingAgent.ps1, not by the CLI).' }
                     $r = Export-AgentEvaluation -Sheet $Sheet
                     return (Set-AgentStage -Sheet $Sheet -Id 'handover' -Status 'done' -Note "sheet + handover + snapshot report" -Data @{ files = @("$($r.Html)", "$($r.Handover)", "$($r.SnapshotReport)") }) }
    }
    throw "Stage '$Id' has no runner."
}

# Run the flow from where it stands, stopping at the first stage that is not ours to run (a gate, or the tool's build).
function Invoke-AgentFlow {
    param([Parameter(Mandatory)]$Sheet, [hashtable]$With = @{}, [string]$StopAfter, [scriptblock]$Progress)
    while ($true) {
        $next = @(Get-AgentFlow -Sheet $Sheet | Where-Object { $_.state -eq 'ready' }) | Select-Object -First 1
        if (-not $next) { break }
        if ($Progress) { & $Progress "stage: $($next.title)" }
        $Sheet = Invoke-AgentStage -Sheet $Sheet -Id $next.id -With $With -Progress $Progress
        if ($StopAfter -and $next.id -eq $StopAfter) { break }
    }
    return $Sheet
}

function Format-AgentFlowText {
    param([Parameter(Mandatory)]$Sheet)
    $mark = @{ done = '[x]'; failed = '[!]'; ready = '[ ]'; waiting = '[~]'; blocked = '[-]'; skipped = '[/]' }
    $sb = New-Object Text.StringBuilder
    foreach ($s in (Get-AgentFlow -Sheet $Sheet)) {
        [void]$sb.AppendLine(("  {0} {1,-30} {2,-8} {3}" -f $mark["$($s.state)"], $s.title, $s.state, $s.why))
    }
    return $sb.ToString().TrimEnd()
}
#endregion

#region Scrub ------------------------------------------------------------------------------------------------------
# Personal data never leaves the machine: e-mails, phone numbers and the AO / cost-centre / contact table values are
# replaced before ANY model call. Packaging decisions never need a person's name.
function Invoke-AgentScrub {
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = $Text
    # GUIDs are product codes, not phone numbers: set them aside first, or their digit runs are "redacted" and the
    # detection and uninstall facts in a document are destroyed
    $guids = New-Object System.Collections.Generic.List[string]
    $t = [regex]::Replace($t, '\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}?', { param($m) $guids.Add($m.Value); "<<GUID$($guids.Count - 1)>>" })
    $t = [regex]::Replace($t, '[\w.+-]+@[\w-]+(\.[\w-]+)+', '[email]')
    # phone numbers = runs with 9+ digits (spaces/dashes/brackets allowed); dates (8 digits) and versions survive
    $t = [regex]::Replace($t, '(?<![\d.])(\+?\d[\d ()/-]{7,}\d)(?![\d.])', { param($m) if (($m.Value -replace '\D', '').Length -ge 9) { '[phone]' } else { $m.Value } })
    $t = [regex]::Replace($t, '(?im)^((?:Last Name|First Name|Nachname|Vorname|Name of (?:the )?(?:AO|owner)|Phone|Telefon|Email|E-Mail)\s*\|\s*)[^|\r\n]+', '${1}[redacted]')
    if ($guids.Count) { $t = [regex]::Replace($t, '<<GUID(\d+)>>', { param($m) $guids[[int]$m.Groups[1].Value] }) }
    return $t
}
#endregion

#region Facts (deterministic) ---------------------------------------------------------------------------------------
# Installer facts without executing anything: engine fingerprint, PE/MSI arch, version, MSI properties, size,
# prerequisite recognition, security-product flag, response files beside it.
function Get-AgentInstallerFacts {
    param([Parameter(Mandatory)]$File)
    $p = $File.FullName; $ext = $File.Extension.ToLower()
    # 'path' is where it sits on THIS machine right now - the tool copies installers locally before running them, so it
    # is useless in a package script. 'name' is what the file will be called in Files\, and that is what commands use.
    $f = [ordered]@{ name = $File.Name; path = $p; sizeMB = [math]::Round($File.Length / 1MB, 1); ext = $ext; engine = ''; arch = ''; version = ''; productName = ''; manufacturer = ''; productCode = ''; upgradeCode = ''; isPrerequisite = $false; prerequisiteLabel = ''; securityProduct = $false; responseFilesNearby = @(); mstNearby = @() }
    try { $f.engine = Get-InstallerEngine -Path $p } catch {}
    if ($ext -eq '.msi') {
        try { $f.arch = Get-MsiTemplateArch $p } catch {}
        foreach ($prop in 'ProductName','ProductVersion','Manufacturer','ProductCode','UpgradeCode') {
            $v = try { Get-MsiProperty -MsiPath $p -Property $prop } catch { $null }
            switch ($prop) { 'ProductName' { $f.productName = "$v" } 'ProductVersion' { $f.version = "$v" } 'Manufacturer' { $f.manufacturer = "$v" } 'ProductCode' { $f.productCode = "$v" } 'UpgradeCode' { $f.upgradeCode = "$v" } }
        }
    } elseif ($ext -eq '.exe') {
        try { $f.arch = Get-PeArch $p } catch {}
        try { $fvi = [Diagnostics.FileVersionInfo]::GetVersionInfo($p); $f.version = "$($fvi.ProductVersion)".Trim(); if (-not $f.version) { $f.version = "$($fvi.FileVersion)".Trim() }; $f.productName = "$($fvi.ProductName)".Trim(); $f.manufacturer = "$($fvi.CompanyName)".Trim() } catch {}
    }
    try { $pr = Get-PrerequisiteSpec -Name $File.Name; if ($pr.IsPrereq) { $f.isPrerequisite = $true; $f.prerequisiteLabel = $pr.Label } } catch {}
    try { $f.securityProduct = [bool](Test-IsSecurityProduct "$($File.Name) $($f.productName) $($f.manufacturer)") } catch {}
    try {
        $dir = Split-Path $p -Parent
        $f.responseFilesNearby = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '(?i)^\.(iss|inf|properties|rsp|ini|xml|cfg|config|json|txt)$' -and $_.Name -notmatch '(?i)^(readme|license|eula|changelog)' } | Select-Object -First 12 | ForEach-Object { $_.Name })
        $f.mstNearby = @(Get-ChildItem -LiteralPath $dir -File -Filter *.mst -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    } catch {}
    return $f
}

# Resolve the order folder with the tool's own resolver and describe what is there.
function Get-AgentSourceFacts {
    param([Parameter(Mandatory)][string]$Folder, $Parsed)
    $s = [ordered]@{ folder = $Folder; reachable = $false; layout = ''; installers = @(); allInstallerCount = 0; zips = @(); docsInSource = 0; iconsFolder = ''; payloadRoot = ''; totalSizeMB = 0; fileCount = 0; topLevel = @(); transforms = @(); documents = @(); otherFiles = @(); archiveInspection = @(); notes = @() }
    if (-not (Test-Path -LiteralPath $Folder)) { $s.notes += 'folder not reachable'; return $s }
    $s.reachable = $true
    try {
        $all = @(Get-ChildItem -LiteralPath $Folder -File -Recurse -Depth 8 -ErrorAction SilentlyContinue)
        $s.fileCount = $all.Count; $s.totalSizeMB = [math]::Round((($all | Measure-Object Length -Sum).Sum) / 1MB, 1)
        $s.zips = @($all | Where-Object { $_.Extension -ieq '.zip' } | ForEach-Object { $_.Name })
        $s.topLevel = @(Get-ChildItem -LiteralPath $Folder -ErrorAction SilentlyContinue | ForEach-Object { if ($_.PSIsContainer) { "$($_.Name)\" } else { $_.Name } })

        # WHAT WAS ACTUALLY DELIVERED, BY NAME. This used to be a top-level listing, the installers, and a COUNT of
        # documents - so a transform one folder down was invisible unless it happened to sit beside the MSI, and the
        # AI could never ask to read a document because it was never told one existed. The tool's job is to hand over
        # what is there and let the AI decide; summarising the delivery was the tool deciding what mattered.
        $rel = { param($F) $r = "$($F.FullName)"; if ($r.StartsWith($Folder, [StringComparison]::OrdinalIgnoreCase)) { $r = $r.Substring($Folder.Length) }; return $r.TrimStart('\', '/') }
        # A transform anywhere in the delivery. It is never an installer, so it never appeared in the installer list.
        $s.transforms = @($all | Where-Object { $_.Extension -ieq '.mst' } | ForEach-Object { @{ name = $_.Name; relativePath = (& $rel $_); sizeKB = [math]::Round($_.Length / 1KB, 1) } })
        # What the orderer sent us to READ - the form, the mails, the screenshots in it.
        $docExt = '(?i)^\.(docx?|pdf|xlsx?|pptx?|msg|eml|rtf|txt|md|png|jpe?g|gif|bmp)$'
        $s.documents = @($all | Where-Object { $_.Extension -match $docExt } | Select-Object -First 60 | ForEach-Object { @{ name = $_.Name; relativePath = (& $rel $_) } })
        # Everything else, so the whole delivery is visible rather than a summary of it.
        $seen = @{}
        foreach ($x in @($s.transforms) + @($s.documents)) { $seen["$($x.relativePath)"] = $true }
        $rest = @($all | Where-Object { -not $seen[(& $rel $_)] -and $_.Extension -notmatch '(?i)^\.(msi|msp)$' })
        # THE FILES THAT DECIDE A PACKAGE, ALWAYS WITH THEIR PATH - never cut off by a count. A flat "first 150 files"
        # listing once dropped a delivered driver zip three folders down; the AI guessed its path wrong and asked the
        # packager to extract it by hand.
        $keyExt = '(?i)^\.(zip|7z|rar|cab|exe|msi|msp|mst|inf|cat|sys|ini|cfg|conf|config|xml|json|reg|bat|cmd|ps1|vbs|iss|properties|lic|key|pfx|cer|crt|udl|pwd|lnk|ttf|otf)$'
        $s.keyFiles = @($all | Where-Object { $_.Extension -match $keyExt } | Select-Object -First 400 | ForEach-Object { "$(& $rel $_)  ($([math]::Round($_.Length / 1KB, 1)) KB)" })
        $s.zips = @($all | Where-Object { $_.Extension -ieq '.zip' } | ForEach-Object { & $rel $_ })
        # what is INSIDE every delivered zip - read from its directory, nothing is extracted here
        $s.zipContents = @(foreach ($z in @($all | Where-Object { $_.Extension -ieq '.zip' } | Select-Object -First 10)) {
            $entries = @(); $count = 0
            try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue; $za = [IO.Compression.ZipFile]::OpenRead($z.FullName); try { $count = $za.Entries.Count; $entries = @($za.Entries | Where-Object { $_.Name } | Select-Object -First 80 | ForEach-Object { "$($_.FullName -replace '/', '\')" }) } finally { $za.Dispose() } } catch { $entries = @("(could not be read: $($_.Exception.Message.Split([char]10)[0]))") }
            [ordered]@{ zip = (& $rel $z); entryCount = $count; entries = $entries } })
        # every folder, with how many files and of which kinds - so nothing is invisible even in a payload of thousands
        $s.folders = @($all | Group-Object { Split-Path -Parent (& $rel $_) } | Sort-Object Name | Select-Object -First 200 | ForEach-Object {
            $kinds = ($_.Group | Group-Object { $_.Extension.ToLowerInvariant() } | Sort-Object Count -Descending | Select-Object -First 6 | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', '
            "$(if ($_.Name) { $_.Name } else { '(top)' })\  $($_.Count) file(s): $kinds" })
        # THE COMPLETE LIST, every file with its path and size, whenever it is a size a person could read (most orders).
        # Only a very large payload is summarised - and then keyFiles, zipContents and folders still cover all of it.
        if ($all.Count -le 600) {
            $s.allFiles = @($all | ForEach-Object { "$(& $rel $_)  ($([math]::Round($_.Length / 1KB, 1)) KB)" })
            $s.otherFiles = @()
        } else {
            $s.otherFiles = @($rest | Select-Object -First 150 | ForEach-Object { (& $rel $_) })
            $s.notes += "$($all.Count) files in the delivery - too many to list one by one; keyFiles, zipContents and folders cover all of it, and run_powershell (Get-ChildItem -Recurse on the order folder) lists any folder in full"
        }
    } catch { $s.notes += "listing the delivery failed: $($_.Exception.Message)" }
    $res = $null
    try { $res = Resolve-Source -RootPath $Folder } catch { $s.notes += "resolver failed: $($_.Exception.Message)" }
    if ($res -and $res.Valid) {
        $s.layout = "$($res.Mode)"; $s.payloadRoot = "$($res.PayloadRoot)"; $s.iconsFolder = "$($res.IconsPath)"; $s.docsInSource = @($res.DocItems).Count
        $inst = @($res.Installers | Where-Object { $_.Extension -and ($_.Extension.ToLower() -in '.exe', '.msi', '.msp') })
        $s.allInstallerCount = $inst.Count
        # Facts for up to 12 installers (a payload tree can hold hundreds of vendor exes - the rest are listed by name only)
        $s.installers = @($inst | Sort-Object Length -Descending | Select-Object -First 12 | ForEach-Object { Get-AgentInstallerFacts -File $_ })
        # What is actually inside the installer, read from its headers by 7-Zip. This replaced a byte scan that
        # read the whole file: measured over these same 8 real deliveries (1.8-3.9 GB engineering suites) the scan
        # cost 86-113 SECONDS each and found nothing in all 8, while the header read takes 0.4-63 s and found three
        # MSIs inside RevitCoreEngine_2026.exe that the scan had missed. Only the biggest few are worth the time;
        # extraction itself is NOT done here - the AI asks for it when the route depends on it.
        $s.archiveInspection = @($inst | Where-Object { $_.Extension -and $_.Extension.ToLower() -eq '.exe' } |
            Sort-Object Length -Descending | Select-Object -First 3 |
            ForEach-Object { Get-AgentArchiveInsight -Path $_.FullName -TimeoutSeconds 120 })
        if ($inst.Count -gt 12) { $s.notes += "$($inst.Count) installer-type files; facts read for the 12 largest" }
        if ($res.Mode -eq 'loose') { $s.notes += 'no installer - loose files / scripts only' }
    } else { $s.notes += 'no installer found by the resolver' }
    return $s
}

# Predecessor + knowledge base + catalogue. Read-only on the shares.
function Get-AgentHistoryFacts {
    param($Parsed, $SourceFacts, [switch]$SkipPredecessor, [string]$OrderFolder = '')
    $h = [ordered]@{ predecessorSearched = [bool]($Parsed -and $Parsed.IsValid -and -not $SkipPredecessor); predecessorCandidates = @(); predecessor = $null; predecessorFrom = ''; predecessorPayload = $null; kb = @(); catalogueOutgoing = @(); catalogueIncoming = @() }
    if ($Parsed -and $Parsed.IsValid -and -not $SkipPredecessor) {
        try {
            # THE ORDER FOLDER COMES FIRST. A previous version delivered inside the order - a "predecessor" or
            # "previous version" subfolder holding the whole package - was put there deliberately FOR THIS ORDER, so it
            # outranks anything matched by name off a share. The engine only searches the shares, so this is agent-side.
            $best = $null; $from = ''
            if ("$OrderFolder".Trim() -and (Get-Command Find-AgentPredecessorInOrder -ErrorAction SilentlyContinue)) {
                $inOrder = @(Find-AgentPredecessorInOrder -OrderFolder "$OrderFolder" -CurrentPackageName "$($Parsed.FullName)")
                foreach ($io in @($inOrder | Select-Object -First 4)) {
                    $h.predecessorCandidates += @{ name = "$($io.name)"; version = ''; score = 100; note = "delivered with the order ($($io.relativeTo)): $($io.why)"; sameVersion = $false; deliveredWithTheOrder = $true }
                }
                if (@($inOrder).Count) {
                    $best = [pscustomobject]@{ Name = "$(@($inOrder)[0].name)"; FullName = "$(@($inOrder)[0].path)" }
                    $from = "delivered with the order ($(@($inOrder)[0].relativeTo))"
                }
            }
            # Otherwise the shares, as before.
            $cands = @(Get-PredecessorCandidates -Parsed $Parsed)
            $h.predecessorCandidates += @($cands | Select-Object -First 6 | ForEach-Object { @{ name = $_.Name; version = "$($_.Version)"; score = $_.Score; note = "$($_.MatchNote)"; sameVersion = [bool]$_.SameVersion; deliveredWithTheOrder = $false } })
            if (-not $best) {
                $best = $cands | Where-Object { $_.Score -ge 92 } | Select-Object -First 1
                if ($best) { $from = 'found on the package share by name' }
            }
            if ($best) {
                $m = Read-PredecessorModel -PackagePath $best.FullName -PackageName $best.Name
                if ($m) {
                    $h.predecessorFrom = $from
                    $h.predecessor = [ordered]@{
                        name = $best.Name; path = $best.FullName; foundBy = $from; psadt = "$($m.TemplateVer)"; type = "$($m.Installer.Type)"; isMulti = [bool]$m.IsMulti
                        installSeq   = @($m.InstallSeq   | ForEach-Object { "$($_.Display)".Trim() } | Select-Object -First 8)
                        uninstallSeq = @($m.UninstallSeq | ForEach-Object { "$($_.Display)".Trim() } | Select-Object -First 8)
                        productCode = "$($m.Installer.ProductCode)"; mst = "$($m.Installer.MstFileName)"
                        preInstallCode = (Get-AgentCodeExcerpt "$($m.Code.PreInstallCode)"); postInstallCode = (Get-AgentCodeExcerpt "$($m.Code.PostInstallCode)"); postUninstallCode = (Get-AgentCodeExcerpt "$($m.Code.PostUninstallCode)")
                    }
                    # WHAT THE PREVIOUS PACKAGE RAN IT ON. The script says what it ran; only the payload says on what -
                    # and when the kind of file changed between then and now, that change has to be explained before
                    # the old script can be reused.
                    if (Get-Command Get-AgentPredecessorPayload -ErrorAction SilentlyContinue) {
                        try { $h.predecessorPayload = Get-AgentPredecessorPayload -PackagePath "$($best.FullName)" } catch {}
                    }
                }
            }
        } catch { Write-Log "AI: predecessor lookup failed: $($_.Exception.Message)" Warning }
    }
    if ($SourceFacts -and $SourceFacts.installers) {
        foreach ($i in @($SourceFacts.installers)) {
            try {
                $rec = Get-KBRecommendation -Vendor $(if ($Parsed) { $Parsed.Vendor }) -App $(if ($Parsed) { $Parsed.AppName }) -Engine $i.engine -InstallerName $i.name
                if ($rec) { $h.kb += [ordered]@{ installer = $i.name; install = "$($rec.Install)"; uninstall = "$($rec.Uninstall)"; uninstallExe = "$($rec.UninstallExe)"; confidence = "$($rec.Confidence)"; source = "$($rec.Source)"; autoUpdate = @($rec.AutoUpdate); packagedAsMsi = [bool]$rec.PackagedAsMsi; engineHelp = "$(Get-EngineParameterHelp -Engine $i.engine)" } }
            } catch {}
        }
    }
    if ($Parsed -and $Parsed.IsValid) {
        foreach ($pair in @(@('OutgoingPath', 'catalogueOutgoing'), @('RepositoryPath', 'catalogueIncoming'))) {
            try {
                $root = Get-Setting $pair[0]
                if ($root -and (Test-Path -LiteralPath $root)) {
                    $h[$pair[1]] = @(Get-ChildItem -LiteralPath $root -Directory -Filter "$($Parsed.Vendor)_$($Parsed.AppName)_*" -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $Parsed.FullName } | Select-Object -First 8 | ForEach-Object { $_.Name })
                }
            } catch {}
        }
    }
    return $h
}
function Get-AgentCodeExcerpt { param([string]$Code, [int]$Max = 1800) $c = "$Code".Trim(); if ($c.Length -gt $Max) { return $c.Substring(0, $Max) + "`n... (truncated)" }; return $c }

# Deterministic gap check - the things a rule can see without a model. Each gap: id, severity (block | ask | info), text.
function Get-AgentDeterministicGaps {
    param($Sheet)
    $g = New-Object System.Collections.Generic.List[object]
    $add = { param($id, $sev, $text) $g.Add([ordered]@{ id = $id; severity = $sev; text = $text; source = 'rule' }) }
    $src = $Sheet.sources; $docs = $Sheet.documents; $id = $Sheet.identity; $decl = $Sheet.declared
    if (-not $src.reachable) { & $add 'SRC-UNREACHABLE' 'block' 'The order folder is not reachable from this machine.' }
    elseif ($src.allInstallerCount -eq 0 -and -not $src.zips.Count) { & $add 'SRC-NOINSTALLER' 'block' 'No installer (.exe/.msi/.msp) or zip in the order folder - ask the AO for the sources.' }
    # A MISSING FORM IS A QUESTION, NOT A WALL. This was a hard block, so an order with no .docx stopped dead after
    # the source was prepared - and the window then reported it as "finished". Two things were wrong with that.
    # The form is not the only way to know what to build: when there is a predecessor, the previous package IS the
    # specification - "make it the same, with this version's installer" - and that is a normal, correct way to work.
    # And there is no fixed name for these documents; an order can carry install instructions as .docx, .xlsm, .pdf
    # or a mail, under any name. So: report what IS there, say the form is missing, and let the AI decide whether it
    # has enough to proceed. If it does not, it asks the packager - which is what a person would do.
    if (-not $docs.form) { & $add 'DOC-NOFORM' 'ask' "No Software Package Request form recognised in the order. $(if (@($src.documents).Count) { "These documents WERE delivered: $(@(@($src.documents) | ForEach-Object { "$($_.relativePath)" }) -join ', ') - read them before deciding anything is missing." } else { 'No documents were delivered at all.' }) If a predecessor exists, the previous package is a usable specification on its own; if not, ask the packager to place the install instructions." }
    elseif (-not $docs.formReadable) { & $add 'DOC-FORMUNREADABLE' 'ask' "The form could not be read ($($docs.formNotes)) - open it manually; if it is a legacy .doc ask for .docx." }
    if (-not $docs.complexity) { & $add 'DOC-NOCOMPLEXITY' 'info' 'No Complexity Matrix in the order (EQS fills it during evaluation).' }
    if (-not $Sheet.ritm) { & $add 'ORD-NORITM' 'info' 'No RITM marker (RITMxxxxxxx.txt) or RITM in the form.' }
    if ($id.Count -and $id.parsedOk -eq $false) { & $add 'ORD-NAME' 'ask' "The folder/package name does not parse as Vendor_App_Arch_Version-Release_Lang ('$($Sheet.package)')." }
    # installer vs name: version + arch
    foreach ($i in @($src.installers)) {
        if ($i.isPrerequisite) { continue }
        if ($i.version -and $id.version) {
            $pn = ("$($id.version)" -replace '[^0-9.]', '').Trim('.'); $iv = ("$($i.version)" -replace '[^0-9.]', '').Trim('.')
            if ($pn -and $iv -and -not ($iv -like "$pn*" -or $pn -like "$iv*")) { & $add 'VER-MISMATCH' 'ask' "Installer '$($i.name)' reports version $($i.version) but the order says $($id.version)." }
        }
        if ($i.arch -in 'x86', 'x64' -and $id.arch) {
            $pa = if ("$($id.arch)" -match '(?i)x86$') { 'x86' } elseif ("$($id.arch)" -match '(?i)x64|x86_64') { 'x64' } else { '' }
            if ($pa -and $pa -ne $i.arch) { & $add 'ARCH-MISMATCH' 'ask' "Installer '$($i.name)' is $($i.arch) but the order says $($id.arch)." }
        }
        if ($i.securityProduct) { & $add 'SEC-PRODUCT' 'info' "'$($i.name)' looks like a security/EDR product - installing it on this machine is usually blocked; evaluate on a clean VM." }
    }
    # the form's tick boxes, read by rule; everything the form SAYS in words is read by the AI at plan
    if ($decl.Count -and $decl.fromRules) {
        if ($docs.formReadable -and -not (Get-AgentList $decl.fromRules.distribution).Count) { & $add 'FORM-DIST' 'ask' 'Distribution behaviour (SCCM / Intune) is not ticked in the form.' }
        $predDeclared = ($decl.fromRules.removePredecessorTicked -eq $true)
        if ($predDeclared -and $Sheet.history.predecessorSearched -and -not $Sheet.history.predecessor -and -not (Get-AgentList $Sheet.history.predecessorCandidates).Count) { & $add 'PRED-DECLARED-NOTFOUND' 'ask' 'The form says a previous version must be removed, but no predecessor was matched by name - the AI searches further at plan.' }
        if (-not $predDeclared -and $Sheet.history.predecessor) { & $add 'PRED-FOUND-NOTDECLARED' 'info' "A predecessor package exists ($($Sheet.history.predecessor.name)) but the form does not ask to remove the previous version." }
    }
    return $g.ToArray()   # NOT @($g): wrapping a List[object] of hashtables throws "Argument types do not match" on PS 5.1
}
# $null-safe list: @($null) is ONE null element on PS 5.1, which renders as an empty bullet - filter it out.
function Get-AgentList { param($X) if ($null -eq $X) { return @() }; return @(@($X) | Where-Object { $null -ne $_ -and "$_" -ne '' }) }
# A schema field the model may fill with either a sentence or a small object. "$obj" on a hashtable prints
# "System.Collections.Specialized.OrderedDictionary" in the report, so read the sentence out of it instead.
function ConvertTo-AgentPlainText {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return "$Value".Trim() }
    if ($Value -is [array]) { return (@($Value | ForEach-Object { ConvertTo-AgentPlainText $_ } | Where-Object { $_ }) -join ' | ') }
    $props = if ($Value -is [System.Collections.IDictionary]) { @($Value.Keys) } elseif ($Value.PSObject) { @($Value.PSObject.Properties.Name) } else { @() }
    if (-not $props.Count) { return "$Value".Trim() }
    $get = { param($k) if ($Value -is [System.Collections.IDictionary]) { $Value[$k] } else { $Value.$k } }
    # the sentence first, then whatever qualifies it
    $head = @('question', 'what', 'text', 'decision', 'item', 'topic', 'title', 'name') | Where-Object { $props -contains $_ } | Select-Object -First 1
    $tailKeys = @('options', 'why', 'reason', 'note', 'impact', 'source') | Where-Object { $props -contains $_ }
    if ($head) {
        $s = "$(& $get $head)".Trim()
        foreach ($k in $tailKeys) { $v = (ConvertTo-AgentPlainText (& $get $k)); if ($v) { $s += "  ($k`: $v)" } }
        if ($s.Trim()) { return $s.Trim() }
    }
    return ((@($props | ForEach-Object { $v = "$(& $get $_)".Trim(); if ($v) { "$_`: $v" } }) | Where-Object { $_ }) -join '; ')
}
#endregion

#region Intake ---------------------------------------------------------------------------------------------------------
# THE INTAKE. $Folder = the order folder (Incoming\<pkg>, a SharePoint staging copy, or any folder). $PkgName optional
# (defaults to the folder name). Returns the sheet; also saved to disk. $Progress gets short status strings.
function Invoke-AgentIntake {
    param([Parameter(Mandatory)][string]$Folder, [string]$PkgName, [string]$Ritm, [scriptblock]$Progress, [switch]$NoModel, [switch]$SkipPredecessor)
    $say = { param($t) Write-Log "AI intake: $t"; if ($Progress) { try { & $Progress $t } catch {} } }
    if (-not $PkgName) { $PkgName = Split-Path $Folder -Leaf }
    # A NETWORK ORDER IS COPIED LOCALLY FIRST, WITH ITS DATES INTACT. Working off a share is slow and sometimes
    # read-only, but an ordinary copy resets every file's CREATED date and stamps every folder with today - and the
    # package then carries a payload that looks edited. Copy-AgentTreeWithTimestamps puts the original dates back.
    # Settings key StageSourceLocal turns this off; a folder already on a local disk is used exactly as it is.
    $stagedFrom = ''
    $doStage = $true
    try { $sv = "$(Get-Setting 'StageSourceLocal')"; if ($sv -and $sv -match '(?i)^(false|0|no)$') { $doStage = $false } } catch {}
    if ($doStage -and "$Folder" -match '^\\\\' -and (Test-Path -LiteralPath $Folder)) {
        $localOrder = Join-Path (try { Get-WorkPath 'Source' } catch { Join-Path $env:TEMP 'PackagingAgent\Source' }) $PkgName
        & $say 'copying the order to a local disk (keeping the original file dates)'
        $cp = Copy-AgentTreeWithTimestamps -Source $Folder -Destination $localOrder -Progress $Progress
        if ($cp.ok -and $cp.files) {
            Write-Log "Order staged locally: $($cp.note) in $($cp.seconds)s -> $localOrder" Info
            $stagedFrom = "$Folder"; $Folder = $localOrder
        } else {
            Write-Log "Could not stage the order locally ($($cp.note)) - reading it from the share instead." Warning
        }
    }
    # THE FOLDER NAME IS ONLY A HINT. The parser is positional, so an order that arrives under a working name with a
    # team prefix - 'EQS_BRAK_beAClientSecurity_x64_...' for 'BRAK_beAClientSecurity_x64_...' - parses its VENDOR as
    # 'EQS'. The name-based search then looks for a vendor that does not exist and reports, confidently, that there
    # is no previous version. There was one; it was on the share the whole time.
    # The name search below still runs because it is cheap and usually right. When it finds nothing that is NOT a
    # conclusion - it is a question for the AI, which has the installer, its product and manufacturer metadata, the
    # documents, and search_previous_packages to look with. A folder name is the weakest evidence in the order.
    $parsed = Parse-PackageName -Name $PkgName
    $sheet = New-AgentSheet -PkgName $PkgName -Ritm $Ritm -Folder $Folder
    if ($stagedFrom) { $sheet.orderStagedFrom = $stagedFrom }
    [void](Start-AgentAudit -Name $PkgName); Reset-AgentUsage
    Add-AgentTimeline $sheet 'intake started'
    if ($stagedFrom) { Add-AgentTimeline $sheet "order copied locally from $stagedFrom with its original file dates" }
    $sheet.identity = [ordered]@{ parsedOk = [bool]$parsed.IsValid; vendor = "$($parsed.Vendor)"; app = "$($parsed.AppName)"; arch = "$($parsed.Arch)"; version = "$($parsed.Version)"; release = "$($parsed.Release)"; lang = "$($parsed.Lang)" }
    # 1. documents
    & $say 'reading the order folder'
    $docs = Find-AgentOrderDocs -Folder $Folder
    if (-not $sheet.ritm -and $docs.Ritm) { $sheet.ritm = $docs.Ritm }
    $sheetDir = Get-AgentSheetDir -Sheet $sheet
    $formDoc = $null
    if ($docs.Form) { & $say "reading the form: $([IO.Path]::GetFileName($docs.Form))"; $formDoc = Read-AgentDocx -Path $docs.Form -ImageDir (Join-Path $sheetDir 'form-images') }
    $sheet.documents = [ordered]@{ form = "$($docs.Form)"; formReadable = [bool]($formDoc -and $formDoc.Ok); formNotes = $(if ($formDoc) { ($formDoc.Notes -join '; ') } else { '' }); formImages = $(if ($formDoc) { @($formDoc.Images).Count } else { 0 })
                                   complexity = "$($docs.Complexity)"; ritmFile = "$($docs.RitmFile)"; pdfs = @($docs.Pdfs | ForEach-Object { [IO.Path]::GetFileName($_) }); readmes = @($docs.Readmes | ForEach-Object { [IO.Path]::GetFileName($_) }); mails = @($docs.Mails | ForEach-Object { [IO.Path]::GetFileName($_) }); otherDocs = @($docs.Other | ForEach-Object { [IO.Path]::GetFileName($_) }) }
    # deterministic form fields (cheap, exact) - the RITM and the ticked distribution from the identity table
    if ($formDoc -and $formDoc.Ok) {
        $ft = $formDoc.Text
        if (-not $sheet.ritm -and $ft -match '(RITM\d{6,})') { $sheet.ritm = $Matches[1] }
        $sheet.declared = [ordered]@{ fromRules = [ordered]@{
            minorUpdate = $(if ($ft -match '(?s)Minor Update.*?\|\s*([☐☒])\s*Yes\s*/\s*([☐☒])\s*No') { if ($Matches[1] -eq [string][char]0x2612) { 'yes' } elseif ($Matches[2] -eq [string][char]0x2612) { 'no' } else { 'unticked' } } else { 'unknown' })
            distribution = @($(if ($ft -match 'Distribution Behaviour\s*\|\s*([☐☒])\s*SCCM\s*/\s*([☐☒])\s*Intune') { if ($Matches[1] -eq [string][char]0x2612) { 'SCCM' }; if ($Matches[2] -eq [string][char]0x2612) { 'Intune' } }))
            archTicked = ''
            removePredecessorTicked = [bool]($ft -match '☒\s*Any previous version of this software')
        } }
        if ($ft -match 'SW Architecture\s*\|\s*([☐☒])\s*x86\s*/\s*([☐☒])\s*x64\s*/\s*([☐☒])\s*All') {
            $ticked = @(); $x = [string][char]0x2612
            if ($Matches[1] -eq $x) { $ticked += 'x86' }; if ($Matches[2] -eq $x) { $ticked += 'x64' }; if ($Matches[3] -eq $x) { $ticked += 'All' }
            $sheet.declared.fromRules.archTicked = ($ticked -join ',')
        }
    }
    # 2. sources. A delivered zip with no loose installer beside it is expanded by the source resolver itself (into
    #    the work folder, never onto a share), so the installers inside it are fingerprinted here like any other.
    & $say 'fingerprinting the installers'
    $sheet.sources = Get-AgentSourceFacts -Folder $Folder -Parsed $parsed
    # 3. history - the previous version by name; finding it properly is the AI's job at plan
    & $say 'looking for the previous version and in the knowledge base'
    $sheet.history = Get-AgentHistoryFacts -Parsed $parsed -SourceFacts $sheet.sources -SkipPredecessor:$SkipPredecessor -OrderFolder $Folder
    # 4. what a rule can see without judgement
    $sheet.gaps = @(Get-AgentDeterministicGaps -Sheet $sheet)
    $ruleBlock = @($sheet.gaps | Where-Object { $_.severity -eq 'block' }).Count -gt 0
    $ruleAsk   = @($sheet.gaps | Where-Object { $_.severity -eq 'ask' }).Count -gt 0
    $sheet.status = if ($ruleBlock) { 'blocked' } elseif ($ruleAsk) { 'ask_ao' } else { 'ready' }
    Add-AgentTimeline $sheet "intake done: $(@($sheet.sources.installers).Count) installer(s), predecessor $(if ($sheet.history.predecessor) { $sheet.history.predecessor.name } else { 'not matched by name' })"
    [void](Set-AgentStage -Sheet $sheet -Id 'intake' -Status 'done' -Note "$(@($sheet.sources.installers).Count) installer(s), $(@($sheet.sources.documents).Count) document(s)$(if ($sheet.history.predecessor) { ", previous version $($sheet.history.predecessor.name)" })")
    [void](Save-AgentSheet -Sheet $sheet)
    return $sheet
}

# WHERE THE AI MEANT, NOT WHAT IT TYPED. The checks are called by the model with whatever path it has in mind - a
# bare file name, a path relative to the package, sometimes still wrapped in quotes - while the tool's own process
# sits in a different directory. Test-Path -LiteralPath then says "not reachable" for a file the AI had just read
# with run_powershell, which is exactly the contradiction it reported: "not reachable, even though its content can
# be read". Resolve it the way a person would before giving up.
function Resolve-AgentScriptPath {
    param([string]$Path, [string]$PackageFolder)
    $p = "$Path".Trim().Trim('"').Trim("'")
    if (-not $p) { return '' }
    if (Test-Path -LiteralPath $p) { return "$((Resolve-Path -LiteralPath $p).Path)" }
    $bases = @("$PackageFolder", (Join-Path "$PackageFolder" 'Content'), "$((Get-Location).Path)")
    foreach ($b in $bases) {
        if (-not "$b".Trim()) { continue }
        $c = try { Join-Path $b $p } catch { '' }
        if ("$c".Trim() -and (Test-Path -LiteralPath $c)) { return "$((Resolve-Path -LiteralPath $c).Path)" }
    }
    # last resort: it is in there somewhere under that name
    $leaf = try { Split-Path -Leaf $p } catch { '' }
    if ("$leaf".Trim() -and "$PackageFolder".Trim() -and (Test-Path -LiteralPath $PackageFolder)) {
        $hit = @(Get-ChildItem -LiteralPath $PackageFolder -Filter $leaf -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($hit.Count) { return "$($hit[0].FullName)" }
    }
    return ''
}

#endregion

#region Package measurements (facts for the AI's verdict) ----------------------------------------------------------------

# DOES THE SCRIPT MATCH THE PACKAGE IT IS IN?
# A script can parse perfectly, read beautifully, be the right shape in every section - and still install nothing,
# because the file it names is not the file that was delivered. That is exactly what happened on a real run: the
# predecessor's script was copied over the built one, so it asked for last version's MSI while this version's MSI sat
# in Files\ beside it. Everything else looked right. This is the check that catches it, and it is pure measurement:
# the names the script installs, against the names actually present.
function Test-AgentPackageConsistency {
    param([Parameter(Mandatory)][string]$ScriptPath, [string]$ExpectedVersion, [string]$PackageName)
    $res = [ordered]@{ ok = $null; installerFilesNamed = @(); missingFromPackage = @(); filesPresent = @()
                       transformsInPackage = @(); transformsNotUsed = @()
                       versionsInScript = @(); expectedVersion = "$ExpectedVersion"; versionLooksWrong = $null; note = '' }
    if (-not (Test-Path -LiteralPath $ScriptPath)) { $res.note = 'the script is not reachable'; return $res }
    $text = ''
    try { $text = [IO.File]::ReadAllText($ScriptPath) } catch { $res.note = 'the script could not be read'; return $res }

    # what the package actually carries
    $dir = Split-Path -Parent $ScriptPath
    $filesDir = Join-Path $dir 'Files'
    if (Test-Path -LiteralPath $filesDir) {
        $res.filesPresent = @(Get-ChildItem -LiteralPath $filesDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    }
    # what the script says it installs - the file names it quotes
    $named = @()
    foreach ($m in [regex]::Matches($text, "(?i)['""]([^'""\\/:*?<>|\r\n]+\.(?:msi|msp|exe|mst))['""]")) { $named += $m.Groups[1].Value }
    $res.installerFilesNamed = @($named | Select-Object -Unique)
    $present = @{}; foreach ($f in @($res.filesPresent)) { $present["$f".ToLowerInvariant()] = $true }
    $res.missingFromPackage = @(@($res.installerFilesNamed) | Where-Object { -not $present["$($_.ToLowerInvariant())"] })

    # THE OTHER DIRECTION: A TRANSFORM DELIVERED, PLACED, AND THEN NEVER USED. The order shipped an .mst, it was
    # copied into Files\, and no command in the script names it - so the choices the owner captured in that transform
    # are simply not applied. The install still succeeds and every other check passes, which is exactly what makes
    # this one dangerous: nothing fails, the package is just quietly wrong.
    $namedLower = @{}; foreach ($n in @($res.installerFilesNamed)) { $namedLower["$n".ToLowerInvariant()] = $true }
    $res.transformsInPackage = @(@($res.filesPresent) | Where-Object { $_ -match '(?i)\.mst$' })
    $res.transformsNotUsed = @(@($res.transformsInPackage) | Where-Object { -not $namedLower["$($_.ToLowerInvariant())"] })

    # version strings the script carries, and whether the expected one is among them
    $res.versionsInScript = @(@([regex]::Matches($text, '(?<![\d.])\d+\.\d+(?:\.\d+){0,2}(?![\d.])') | ForEach-Object { $_.Value }) | Group-Object | Sort-Object Count -Descending | Select-Object -First 6 -ExpandProperty Name)
    if ("$ExpectedVersion".Trim()) {
        $av = [regex]::Match($text, "(?im)^\s*AppVersion\s*=\s*['""]([^'""]+)['""]")
        $res.appVersionInScript = $(if ($av.Success) { $av.Groups[1].Value } else { '' })
        $res.versionLooksWrong = [bool]($av.Success -and $av.Groups[1].Value -ne "$ExpectedVersion".Trim())
    }

    $problems = @()
    if (@($res.missingFromPackage).Count) { $problems += "the script installs $(@($res.missingFromPackage) -join ', ') but $(if (@($res.filesPresent).Count) { "Files\ holds $(@($res.filesPresent) -join ', ')" } else { 'Files\ is empty' })" }
    if ($res.versionLooksWrong) { $problems += "AppVersion says '$($res.appVersionInScript)' but this package is $ExpectedVersion" }
    if (@($res.transformsNotUsed).Count) { $problems += "$(@($res.transformsNotUsed) -join ', ') was delivered with the order and is sitting in Files\, but no command in the script names it - the transform is not being applied" }
    $res.ok = -not @($problems).Count
    $res.note = if ($res.ok) { 'the script names files that are in the package, and the version matches' }
                else { "THIS PACKAGE WOULD NOT INSTALL: $($problems -join '; ')" }
    return $res
}

# Does the finished script parse? This is not an opinion and must never be left for the model to notice by eye.
function Test-AgentScriptParses {
    param([Parameter(Mandatory)][string]$ScriptPath)
    $out = [ordered]@{ parses = $null; errorCount = 0; errors = @(); note = '' }
    if (-not (Test-Path -LiteralPath $ScriptPath)) { $out.note = 'the script is not reachable'; return $out }
    $errs = $null
    try { [void][System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$errs) }
    catch { $out.parses = $false; $out.note = "the script could not be parsed at all: $($_.Exception.Message)"; return $out }
    $out.errorCount = @($errs).Count
    $out.parses = ($out.errorCount -eq 0)
    $out.errors = @(@($errs) | Select-Object -First 15 | ForEach-Object { [ordered]@{ line = $_.Extent.StartLineNumber; message = "$($_.Message)"; text = "$($_.Extent.Text)".Substring(0, [Math]::Min(160, "$($_.Extent.Text)".Length)) } })
    $out.note = if ($out.parses) { 'the script is valid PowerShell' }
                else { "THE SCRIPT DOES NOT PARSE - $($out.errorCount) syntax error(s). A script PowerShell cannot read installs nothing, whatever else it says." }
    return $out
}

# How many real lines sit in each section, here and in the predecessor. On a reuse they should be close; a section
# that has grown a lot is the shape of code that has been written twice. Measurement only - the AI reads the numbers.
# THE NINE PHASES OF A DEPLOY SCRIPT, whatever generation wrote it: the team's v4 template (#region PRE-REPAIR ...),
# a plain v4 script (InstallPhase assignments inside Install-/Uninstall-/Repair-ADTDeployment: pre, main, post), or a v3
# Deploy-Application.ps1 ($installPhase = 'Pre-Repair'). Returns phase -> the lines of real code in it.
function Get-AgentScriptPhases {
    param([string]$Text)
    $names = [ordered]@{ preInstall = @(); install = @(); postInstall = @(); preUninstall = @(); uninstall = @(); postUninstall = @(); preRepair = @(); repair = @(); postRepair = @() }
    $byLabel = @{ 'pre-installation' = 'preInstall'; 'installation' = 'install'; 'post-installation' = 'postInstall'; 'pre-install' = 'preInstall'; 'install' = 'install'; 'post-install' = 'postInstall'
                  'pre-uninstallation' = 'preUninstall'; 'uninstallation' = 'uninstall'; 'post-uninstallation' = 'postUninstall'; 'pre-uninstall' = 'preUninstall'; 'uninstall' = 'uninstall'; 'post-uninstall' = 'postUninstall'
                  'pre-repair' = 'preRepair'; 'repair' = 'repair'; 'post-repair' = 'postRepair'; 'main-installation' = 'install'; 'main-uninstallation' = 'uninstall'; 'main-repair' = 'repair' }
    $cur = $null; $fn = ''; $ord = 0
    foreach ($line in @("$Text" -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match '(?i)^function\s+(Install|Uninstall|Repair)-ADTDeployment') { $fn = $Matches[1].ToLower(); $ord = 0; $cur = $null; continue }
        if ($t -match '(?i)^##\s*MARK:\s*(Initialization|Invocation)' -or $t -match '(?i)^#region\s+(Initialization|Invocation)') { $cur = $null; $fn = ''; continue }
        if ($t -match '(?i)^#region\s+((PRE|MAIN|POST)-(INSTALLATION|UNINSTALLATION|REPAIR))\b') { $k = $byLabel[$Matches[1].ToLower()]; if ($k) { $cur = $k }; continue }
        if ($t -match '(?i)^#endregion\s+(PRE|MAIN|POST)-') { $cur = $null; continue }
        if ($t -match '(?i)\$(adtSession\.)?installPhase\s*=\s*["'']([^"'']+)["'']') {
            $v = $Matches[2].ToLower()
            if ($byLabel.ContainsKey($v)) { $cur = $byLabel[$v] }
            elseif ($fn) { $ord++; $pre = if ($ord -eq 1) { 'pre' } elseif ($ord -eq 3) { 'post' } else { '' }
                           $cur = if ($pre) { "$pre$($fn.Substring(0,1).ToUpper())$($fn.Substring(1))" } else { $fn } }
            continue
        }
        if (-not $cur -or -not $t -or $t.StartsWith('#') -or $t -match '^[{}()\s]*$') { continue }
        $names[$cur] += $t
    }
    return $names
}

function Get-AgentSectionSizes {
    param([Parameter(Mandatory)][string]$ScriptPath, [string]$PredecessorScriptPath)
    # only lines that are NOT the template's own - the boilerplate every script carries says nothing about the package
    $tplLines = @{}
    try { $tp = Join-Path (Get-AgentTemplatePath) 'Invoke-AppDeployToolkit.ps1'; foreach ($l in @(Get-Content -LiteralPath $tp -ErrorAction Stop)) { $tplLines["$l".Trim()] = $true } } catch {}
    # ...and the dialog/reboot boilerplate every generation of the team template carries (v3 $VWG_..., v4 $adtSession....)
    $boiler = '(?i)^(\}?\s*(else)?if\s*\(\s*!?\(?\s*\$(VWG_|adtSession\.)(CheckForReboot|UseDialogs|AllowDefer|ProcToClose|ProcToCloseNonUI|ProcToBlock)|Show-(ADT)?Installation(Welcome|Progress)\b|Set-(MTB)?Reboot\s+-ForceExitScript|Write-(ADT)?Log(Entry)?\s+-Message\s+["''](Start|Installation of|Uninstallation of|Repair of) )'
    $read = { param($path) if (-not "$path".Trim() -or -not (Test-Path -LiteralPath $path)) { return $null }; $ph = Get-AgentScriptPhases -Text ([IO.File]::ReadAllText($path)); $o = [ordered]@{}; foreach ($k in @($ph.Keys)) { $o[$k] = @($ph[$k] | Where-Object { -not $tplLines.ContainsKey("$_") -and "$_" -notmatch $boiler }) }; return $o }
    $now = & $read $ScriptPath
    $was = & $read $PredecessorScriptPath
    $rows = @(); $dropped = @()
    foreach ($k in @('preInstall', 'install', 'postInstall', 'preUninstall', 'uninstall', 'postUninstall', 'preRepair', 'repair', 'postRepair')) {
        $n = if ($now) { @($now[$k]).Count } else { $null }
        $p = if ($was) { @($was[$k]).Count } else { $null }
        $rows += [ordered]@{ section = $k; builtLines = $n; predecessorLines = $p; difference = $(if ($null -ne $n -and $null -ne $p) { $n - $p } else { $null }) }
        # A PHASE THE PREDECESSOR FILLED AND THIS PACKAGE LEFT EMPTY - on a real order the pre-repair uninstall was
        # simply dropped. Say so, with what was there.
        if ($was -and $p -gt 0 -and $n -eq 0) { $dropped += [ordered]@{ section = $k; predecessorHad = @($was[$k] | Select-Object -First 12) } }
    }
    return [ordered]@{ sections = @($rows); droppedFromPredecessor = @($dropped)
                       note = $(if ($was) { 'package lines (not the template''s own) per phase, versus the predecessor. droppedFromPredecessor = phases the predecessor filled and this package left empty - each needs a reason or restoring.' }
                                else { 'no predecessor script to compare against - the built sizes are given on their own' }) }
}

#endregion

#region Prepare ------------------------------------------------------------------------------------------------------
# STAGE prepare: what must happen before an installer can run and the tool cannot do alone - walk a wizard once to
# record a response file, supply a licence file or a server name. The AI said so in its plan (humanNeeded); this
# stage hands the request to the packager and never guesses its way past a missing piece.
function Invoke-AgentPrepare {
    param([Parameter(Mandatory)]$Sheet, [scriptblock]$Progress)
    $did = New-Object System.Collections.Generic.List[string]
    $need = $null
    # THE MSI INSIDE THE WRAPPER, when the plan wants it: taken out HERE, before the test, so a plan line can name it and
    # the test can run it. Into this machine's work folder - the order folder itself is never written into.
    $ev = if ($Sheet.plan) { $Sheet.plan.evaluate } else { $null }
    if ($ev -and $ev.extractMsi -and [bool]$ev.extractMsi.wanted -and -not @(Get-AgentList $Sheet.extractedMsis.candidates).Count) {
        $wrap = @(@(Get-AgentList $Sheet.sources.archiveInspection) | Where-Object { @($_.msiCandidates).Count }) | Select-Object -First 1
        $wrapPath = if ($wrap) { Find-AgentOrderFile -Folder "$($Sheet.folder)" -Name "$($wrap.installer)" -AlsoLookIn @("$($Sheet.sources.payloadRoot)") } else { '' }
        if ($wrapPath) {
            if ($Progress) { & $Progress "taking the MSI(s) out of $($wrap.installer)" }
            $dir = if (Get-Command Get-WorkPath -ErrorAction SilentlyContinue) { Get-WorkPath ("Extracted\" + ("$($Sheet.package)" -replace '[\\/:*?"<>|]', '_')) } else { Join-Path $env:TEMP "PackagingAgent\Extracted\$($Sheet.package)" }
            try { if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
            $ef = Get-AgentExtractedMsiFacts -InstallerPath $wrapPath -WorkFolder $dir -ExpectedName "$($Sheet.identity.app)" -ExpectedVersion "$($Sheet.identity.version)" -ExpectedVendor "$($Sheet.identity.vendor)"
            $Sheet.extractedMsis = $ef
            if (@($ef.candidates).Count) { $Sheet.extractedDir = $dir; $did.Add("took $(@($ef.candidates).Count) MSI(s) out of $($wrap.installer): $((@($ef.candidates) | ForEach-Object { "$($_.file) ($($_.productName) $($_.productVersion))" }) -join ', ')") }
            else { $did.Add("could not take the MSI out of $($wrap.installer): $($ef.note)") }
        } else {
            $did.Add('extraction was asked for, but no delivered installer lists an MSI inside (7-Zip cannot read Inno Setup, InstallShield or Wise) - the MSIs the installer unpacks are caught while it runs in the test instead')
        }
    }
    # EVERY DELIVERED ZIP, EXPANDED - into this machine's work folder, never into the order. Drivers, configuration and
    # licence files often arrive zipped; the AI reads them, the test uses them, the build can place them, and nobody is
    # asked to extract anything by hand.
    $zips = @(Get-AgentList $Sheet.sources.zips)
    if ($zips.Count -and -not @(Get-AgentList $Sheet.expandedZips).Count) {
        $root = if (Get-Command Get-WorkPath -ErrorAction SilentlyContinue) { Get-WorkPath ("Expanded\" + ("$($Sheet.package)" -replace '[\\/:*?"<>|]', '_')) } else { Join-Path $env:TEMP "PackagingAgent\Expanded\$($Sheet.package)" }
        $exp = @()
        foreach ($z in $zips) {
            $src = Join-Path "$($Sheet.folder)" "$z"
            if (-not (Test-Path -LiteralPath $src)) { $src = Find-AgentOrderFile -Folder "$($Sheet.folder)" -Name (Split-Path -Leaf "$z") }
            if (-not $src) { continue }
            $dest = Join-Path $root ([IO.Path]::GetFileNameWithoutExtension($src))
            try {
                if ($Progress) { & $Progress "expanding $(Split-Path -Leaf $src)" }
                if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
                Expand-Archive -LiteralPath $src -DestinationPath $dest -Force -ErrorAction Stop
                $files = @(Get-ChildItem -LiteralPath $dest -File -Recurse -ErrorAction SilentlyContinue)
                $exp += [ordered]@{ zip = "$z"; expandedTo = $dest; fileCount = $files.Count; files = @($files | Select-Object -First 60 | ForEach-Object { $_.FullName.Substring($dest.Length).TrimStart('\') }) }
                $did.Add("expanded $(Split-Path -Leaf $src) ($($files.Count) file(s)) to $dest")
            } catch { $did.Add("could not expand $(Split-Path -Leaf $src): $($_.Exception.Message.Split([char]10)[0])") }
        }
        $Sheet.expandedZips = @($exp)
        if ($exp.Count) { $Sheet.expandedDir = $root }
    }
    if ($Sheet.plan -and $Sheet.plan.humanNeeded -and [bool]$Sheet.plan.humanNeeded.required) { $need = $Sheet.plan.humanNeeded }
    $Sheet.prepare = [ordered]@{ toolDid = @($did.ToArray()); humanNeeded = $need
                                 route = $(if ($Sheet.plan) { "$($Sheet.plan.route.kind) $($Sheet.plan.route.number)" } else { '' }) }
    if ($need) {
        Add-AgentTimeline $Sheet "prepare: waiting for a person - $($need.what)"
        return (Set-AgentStage -Sheet $Sheet -Id 'prepare' -Status 'waiting' -Note "$($need.what)" -Data @{ exactCommand = "$($need.exactCommand)"; sendBack = "$($need.sendBack)" })
    }
    $note = if ($did.Count) { $did -join '; ' } else { 'nothing to prepare' }
    Add-AgentTimeline $Sheet "prepare: $note"
    return (Set-AgentStage -Sheet $Sheet -Id 'prepare' -Status 'done' -Note $note)
}

#endregion

#region Build the package (tool lays it out, the AI writes the script) ---------------------------------------------------
# The team's PSADT template is the skeleton - it is never rewritten, only filled in. The tool does the mechanical part
# (copy the template, place the delivered files where the layout plan says) because that is what an on-site admin is
# for; the AI then writes the script itself, line by line, through the command channel.
# WHICH TEMPLATE the package is built from. Say it out loud, once - a package built from the wrong brand's template is
# the kind of mistake that is only caught after handover.
function Write-AgentTemplateChoice {
    param([string]$Path, [string]$How)
    if ($script:AgentTemplateLogged -eq "$Path") { return }
    $script:AgentTemplateLogged = "$Path"
    if (-not "$Path".Trim()) { return }
    $owner = ''
    try { $owner = @("$Path".Split('\') | Where-Object { $_ -match '(?i)PackageAssistance|PackageBuilder' } | Select-Object -First 1) } catch {}
    Write-Log "Building from the PSADT template at $Path ($How$(if ($owner) { "; that is the $owner template" }))." $(if ($How -match 'fallback') { 'Warning' } else { 'Info' })
}

# THE TEMPLATE LIVES HERE, IN THE AGENT. `PackagingAgent\Template\` holds the team's PSADT template - the toolkit, the
# team's own extensions, Config, Assets, Strings - and that is the ONLY place the agent looks by default.
#
# It used to hunt through sibling folders for a Package Assistance copy. That made the agent depend on whatever else
# happened to sit next to it, and with MTB, GPF and PAG variants all present it would silently take the first one it
# found - so a GPF order could be built with the MTB template and nobody would know until after handover. The agent
# carries its own template now. An explicit TemplatePath in engine-settings.json still wins, for the case where a
# different brand's template is deliberately wanted.
function Get-AgentTemplatePath {
    $p = ''
    try { $p = "$(Get-Setting 'TemplatePath')" } catch {}
    if ("$p".Trim() -and (Test-Path -LiteralPath $p)) { Write-AgentTemplateChoice -Path $p -How 'TemplatePath in engine-settings.json'; return $p }
    if (-not "$script:AgentHome".Trim()) { return '' }      # bare runspace: nothing to resolve from
    foreach ($c in 'Template', 'Template\Content') {
        $t = Join-Path "$script:AgentHome" $c
        if (Test-Path -LiteralPath (Join-Path $t 'Invoke-AppDeployToolkit.ps1')) {
            Write-AgentTemplateChoice -Path $t -How "the agent's own copy"
            return $t
        }
    }
    return ''
}

# The tool's hands: a real package folder with the template in it and every delivered file where the plan says.
function New-AgentPackageSkeleton {
    param([Parameter(Mandatory)]$Sheet, [string]$TemplatePath, [string]$Destination)
    if (-not "$TemplatePath".Trim()) { $TemplatePath = Get-AgentTemplatePath }
    if (-not "$TemplatePath".Trim() -or -not (Test-Path -LiteralPath $TemplatePath)) {
        throw "The PSADT template was not found. It belongs in PackagingAgent\Template\ (the folder holding Invoke-AppDeployToolkit.ps1, PSAppDeployToolkit\, Config\, Assets\) - restore it from the repository, or set TemplatePath in engine-settings.json to point somewhere else deliberately."
    }
    if (-not "$Destination".Trim()) {
        $root = if (Get-Command Get-WorkPath -ErrorAction SilentlyContinue) { Get-WorkPath 'Packages' } else { Join-Path $env:TEMP 'PackagingAgent\Packages' }
        $Destination = Join-Path $root (("$($Sheet.package)" -replace '[\\/:*?"<>|]', '_'))
    }
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue }
    # A SHIPPED package looks like this - the template's Content is a subfolder, not the package root:
    #   <pkg>\Content\   Invoke-AppDeployToolkit.ps1, Files\, SupportFiles\, Assets\, Config\, PSAppDeployToolkit\...
    #   <pkg>\Documents\ the order paperwork        <pkg>\Icons\ the app icon
    $content = Join-Path $Destination 'Content'
    foreach ($d in $content, (Join-Path $Destination 'Documents'), (Join-Path $Destination 'Icons')) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    foreach ($sub in @(Get-ChildItem -LiteralPath $TemplatePath -Force)) {
        Copy-Item -LiteralPath $sub.FullName -Destination (Join-Path $content $sub.Name) -Recurse -Force -ErrorAction SilentlyContinue
    }
    $script = @(Get-ChildItem -LiteralPath $content -Filter 'Invoke-AppDeployToolkit.ps1' -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName)
    # Files\ and SupportFiles\ belong NEXT TO THE SCRIPT - that is what the script's own paths resolve against.
    $scriptDir = if ("$script".Trim()) { Split-Path -Parent $script } else { $content }
    foreach ($d in 'Files', 'SupportFiles') { New-Item -ItemType Directory -Force -Path (Join-Path $scriptDir $d) | Out-Null }

    $placed = New-Object System.Collections.Generic.List[object]
    $order = "$($Sheet.folder)".TrimEnd('\')
    $filesDest = Join-Path $scriptDir 'Files'
    $docDest = Join-Path $Destination 'Documents'
    $iconDest = Join-Path $Destination 'Icons'

    # THE TOOL PLACES THE PAYLOAD, exactly as Package Assistance does: Resolve-Source works out the payload root and
    # Copy-ResolvedSource copies the WHOLE source tree into Files\ - subfolders intact (defaults\pref, distribution\
    # extensions, License-Info, startpages ...) - with the documents going to Documents\ and the icon to Icons\.
    # Placing files one by one flattens that structure, and the script's own paths then point at nothing.
    $usedResolver = $false
    if ((Get-Command Resolve-Source -ErrorAction SilentlyContinue) -and (Get-Command Copy-ResolvedSource -ErrorAction SilentlyContinue)) {
        try {
            $res = Resolve-Source -RootPath $order
            if ($res -and $res.Valid) {
                $chosen = @($res.Installers)
                Copy-ResolvedSource -Resolved $res -ChosenInstallers $chosen -InstallerDest $filesDest -DocDest $docDest -IconDest $iconDest
                $usedResolver = $true
                foreach ($f in @(Get-ChildItem -LiteralPath $filesDest -File -Recurse -ErrorAction SilentlyContinue)) {
                    $placed.Add([ordered]@{ file = $f.FullName.Substring($filesDest.Length).TrimStart('\'); to = "Content\Files\$($f.FullName.Substring($filesDest.Length).TrimStart('\'))"; ok = $true; note = 'placed by the source resolver' })
                }
                foreach ($f in @(Get-ChildItem -LiteralPath $docDest -File -ErrorAction SilentlyContinue)) {
                    $placed.Add([ordered]@{ file = $f.Name; to = "Documents\$($f.Name)"; ok = $true; note = 'placed by the source resolver' })
                }
            } else { Write-Log 'Source resolver found nothing to copy - falling back to the layout plan.' Warning }
        } catch { Write-Log "Source resolver failed ($($_.Exception.Message)) - falling back to the layout plan." Warning }
    }

    # ICONS. The order often does not carry one - the icon was sorted out when the FIRST version of this package was
    # made and has travelled with the package ever since. So when the order has none, take the predecessor's, which is
    # what Package Assistance does (Get-PredecessorIconsPath). Without this the Icons folder ships EMPTY and somebody
    # has to go and find the icon again by hand.
    if (-not @(Get-ChildItem -LiteralPath $iconDest -File -ErrorAction SilentlyContinue).Count) {
        $predPath = if ($Sheet.history -and $Sheet.history.predecessor) { "$($Sheet.history.predecessor.path)" } else { '' }
        if ($predPath -and (Test-Path -LiteralPath $predPath) -and (Get-Command Get-PredecessorIconsPath -ErrorAction SilentlyContinue)) {
            $predIcons = Get-PredecessorIconsPath -PredecessorPath $predPath
            if ($predIcons -and (Test-Path -LiteralPath $predIcons)) {
                $n = 0
                foreach ($ic in @(Get-ChildItem -LiteralPath $predIcons -File -ErrorAction SilentlyContinue)) {
                    try {
                        Copy-Item -LiteralPath $ic.FullName -Destination (Join-Path $iconDest $ic.Name) -Force -ErrorAction Stop
                        $placed.Add([ordered]@{ file = $ic.Name; to = "Icons\$($ic.Name)"; ok = $true; note = 'taken from the predecessor package - the order carried no icon' }); $n++
                    } catch {}
                }
                if ($n) { Write-Log "Icons: the order carried none, so $n came from the predecessor package." Info }
            }
        }
        if (-not @(Get-ChildItem -LiteralPath $iconDest -File -ErrorAction SilentlyContinue).Count) {
            $placed.Add([ordered]@{ file = '(none)'; to = 'Icons'; ok = $false; note = 'no icon in the order and none in the predecessor - the package ships without one' })
            Write-Log 'Icons: none in the order and none in the predecessor - the package has no icon.' Warning
        }
    }

    # ROUTE 5: the AI read the extracted MSIs and said one of them IS the application. Then that MSI is what the
    # package installs, so it goes into Files\ and the wrapper comes out. Only ever for a file that really was among
    # the extracted candidates - never a name the model produced on its own.
    $pem = $Sheet.decision.packageExtractedMsi
    if ($pem -and [bool]$pem.use -and "$($pem.file)".Trim()) {
        $cand = @(Get-AgentList $Sheet.extractedMsis.candidates | Where-Object { "$($_.file)" -eq "$($pem.file)" -and $_.readable }) | Select-Object -First 1
        if (-not $cand) {
            $placed.Add([ordered]@{ file = "$($pem.file)"; to = 'Files'; ok = $false; note = 'the AI named an MSI that is not among the extracted candidates - not placed' })
            Write-Log "Route 5 asked for '$($pem.file)' but it is not in the extracted facts - the wrapper stays." Warning
        } else {
            $wrapper = "$($Sheet.extractedMsis.installer)"
            $wrapPath = @(Get-ChildItem -LiteralPath $order -File -Recurse -Depth 8 -Filter $wrapper -ErrorAction SilentlyContinue | Select-Object -First 1)
            $r5 = Copy-AgentExtractedMsiIntoPackage -Candidate $cand -WrapperPath $(if ($wrapPath.Count) { $wrapPath[0].FullName } else { $wrapper }) -FilesDest $filesDest
            foreach ($nm in @($r5.placed)) { $placed.Add([ordered]@{ file = $nm; to = "Content\Files\$nm"; ok = $true; note = "route 5: taken out of $wrapper" }) }
            if (-not $r5.ok) { $placed.Add([ordered]@{ file = "$($pem.file)"; to = 'Files'; ok = $false; note = "route 5 failed: $($r5.note)" }) }
            Write-Log "Route 5: $($r5.note)" $(if ($r5.ok) { 'Info' } else { 'Warning' })
            $Sheet.route5Placement = $r5
        }
    }

    # WHAT THE PACKAGE INSTALLS BUT THE ORDER DID NOT DELIVER: an MSI caught while the vendor EXE ran, one extracted
    # from it, a transform the previous package shipped. The steps the machine proved name them; they go into Files\
    # beside the delivered payload (with the cabinets that sat beside a caught MSI), and each one says where it came from.
    $useSteps = if (@(Get-AgentList $Sheet.provenSteps).Count) { @(Get-AgentList $Sheet.provenSteps) } else { @(Get-AgentList $Sheet.plan.install.steps) }
    $roots = @(Get-AgentInstallerRoots -Sheet $Sheet)
    $want = New-Object System.Collections.Generic.List[string]
    foreach ($st in $useSteps) {
        $nm = "$($st.installer)"; if (-not $nm.Trim() -and "$($st.commandLine)".Trim()) { $nm = (ConvertFrom-AgentCommandLine "$($st.commandLine)").installer }
        if ($nm.Trim()) { $want.Add((Split-Path -Leaf $nm)) }
        foreach ($m in @([regex]::Matches("$($st.arguments) $($st.commandLine)", '(?i)(?:TRANSFORMS|PATCH)\s*=\s*(?:"([^"]+)"|(\S+))'))) {
            $v = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
            foreach ($t in @("$v" -split ';' | Where-Object { "$_".Trim() })) { $want.Add((Split-Path -Leaf "$t".Trim())) }
        }
    }
    foreach ($nm in @($want.ToArray() | Select-Object -Unique)) {
        if (@(Get-ChildItem -LiteralPath $filesDest -File -Recurse -Filter $nm -ErrorAction SilentlyContinue).Count) { continue }
        $src = Find-AgentOrderFile -Folder $order -Name $nm -AlsoLookIn $roots
        if (-not $src) { $placed.Add([ordered]@{ file = $nm; to = 'Files'; ok = $false; note = 'the proven steps use it, but it is nowhere - not delivered, caught, extracted or in the previous package' }); continue }
        $from = if ("$($Sheet.capturedDir)".Trim() -and $src.StartsWith("$($Sheet.capturedDir)", [StringComparison]::OrdinalIgnoreCase)) { 'caught while the vendor installer ran' }
                elseif ("$($Sheet.extractedDir)".Trim() -and $src.StartsWith("$($Sheet.extractedDir)", [StringComparison]::OrdinalIgnoreCase)) { 'extracted from the vendor installer' }
                elseif ($src -match '^\\\\') { 'taken from the previous package' } else { 'from the order' }
        try {
            Copy-Item -LiteralPath $src -Destination (Join-Path $filesDest $nm) -Force -ErrorAction Stop
            $placed.Add([ordered]@{ file = $nm; to = "Content\Files\$nm"; ok = $true; note = "not delivered - $from" })
            if ($nm -match '(?i)\.msi$' -and $from -match 'caught|extracted') {
                foreach ($cab in @(Get-ChildItem -LiteralPath (Split-Path -Parent $src) -File -Filter '*.cab' -ErrorAction SilentlyContinue)) {
                    if (-not (Test-Path -LiteralPath (Join-Path $filesDest $cab.Name))) { Copy-Item -LiteralPath $cab.FullName -Destination (Join-Path $filesDest $cab.Name) -Force -ErrorAction SilentlyContinue; $placed.Add([ordered]@{ file = $cab.Name; to = "Content\Files\$($cab.Name)"; ok = $true; note = "the cabinet $nm needs - $from" }) }
                }
            }
        } catch { $placed.Add([ordered]@{ file = $nm; to = 'Files'; ok = $false; note = "could not copy from $src`: $($_.Exception.Message)" }) }
    }

    # FALLBACK, and it has to be a real one. This used to walk a layout plan that an earlier pipeline stage produced;
    # that stage was removed (deciding where files go BEFORE the package exists produced inaccurate packages), so the
    # fallback silently placed nothing at all and a resolver failure shipped an EMPTY Files folder. Now: take what the
    # intake already found - the installers, the documents, the icon - and copy them by hand. The tree is not preserved
    # the way the resolver would, so say so loudly rather than letting it pass for a proper placement.
    if (-not $usedResolver) {
        Write-Log 'The source resolver could not place the payload - falling back to copying what the intake found.' Warning
        $fallbackCount = 0
        foreach ($i in @(Get-AgentList $Sheet.sources.installers)) {
            $src = "$($i.path)"
            if (-not $src -or -not (Test-Path -LiteralPath $src)) {
                $hit = @(Get-ChildItem -LiteralPath $order -File -Recurse -Depth 8 -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "$($i.name)" } | Select-Object -First 1)
                if ($hit.Count) { $src = $hit[0].FullName }
            }
            if (-not $src -or -not (Test-Path -LiteralPath $src)) { $placed.Add([ordered]@{ file = "$($i.name)"; to = 'Files'; ok = $false; note = 'not found in the order folder' }); continue }
            try {
                Copy-Item -LiteralPath $src -Destination (Join-Path $filesDest (Split-Path -Leaf $src)) -Force -ErrorAction Stop
                $placed.Add([ordered]@{ file = (Split-Path -Leaf $src); to = "Content\Files\$(Split-Path -Leaf $src)"; ok = $true; note = 'copied by the fallback - NOT the resolver, so any folder structure around it is missing' })
                $fallbackCount++
            } catch { $placed.Add([ordered]@{ file = (Split-Path -Leaf $src); to = 'Files'; ok = $false; note = "$($_.Exception.Message)" }) }
        }
        # the paperwork, so the handover is not empty either
        foreach ($d in @(@(Get-AgentList $Sheet.documents.allDocs) | Select-Object -First 20)) {
            if (-not "$d".Trim() -or -not (Test-Path -LiteralPath "$d")) { continue }
            try { Copy-Item -LiteralPath "$d" -Destination (Join-Path $docDest (Split-Path -Leaf "$d")) -Force -ErrorAction Stop
                  $placed.Add([ordered]@{ file = (Split-Path -Leaf "$d"); to = "Documents\$(Split-Path -Leaf "$d")"; ok = $true; note = 'copied by the fallback' }) } catch {}
        }
        if (-not $fallbackCount) {
            Write-Log 'THE FALLBACK PLACED NO INSTALLER - the package has an empty Files folder and must not be shipped.' Warning
            $placed.Add([ordered]@{ file = '(nothing)'; to = 'Files'; ok = $false; note = 'NO installer could be placed at all - neither the resolver nor the fallback found one. This package cannot install anything.' })
        }
    }
    # THE DELIVERED FILES MUST LOOK UNTOUCHED. A package is evidence of what the vendor shipped, and a reviewer reads
    # the dates: a file stamped with today's date looks like somebody edited it. Copy-Item preserves LastWriteTime on
    # FILES but resets their CreationTime, and gives every folder it creates today's date - which is what happened on
    # the first live run. So put the original stamps back, on files and folders alike.
    # Anything the agent MADE (a transform it generated, a stub it wrote) keeps its own real date - only files that
    # exist in the order folder are restored, and they are matched by their path under Files\.
    $restored = 0
    if (Test-Path -LiteralPath $order) {
        $byRel = @{}
        try {
            foreach ($o in @(Get-ChildItem -LiteralPath $order -Recurse -Force -ErrorAction SilentlyContinue)) {
                $rel = $o.FullName.Substring($order.Length).TrimStart('\')
                if ($rel) { $byRel[$rel.ToLowerInvariant()] = $o }
            }
        } catch {}
        # deepest first, so restoring a folder's date is not undone by writing a file inside it afterwards
        $items = @(Get-ChildItem -LiteralPath $filesDest -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object { "$($_.FullName)".Length } -Descending)
        foreach ($it in $items) {
            $rel = $it.FullName.Substring($filesDest.Length).TrimStart('\')
            if (-not $rel) { continue }
            $orig = $null
            if ($byRel.ContainsKey($rel.ToLowerInvariant())) { $orig = $byRel[$rel.ToLowerInvariant()] }
            else {
                # the resolver may have lifted the payload out of a sub-folder, so fall back to matching on the tail
                $hit = @($byRel.Values | Where-Object { $_.Name -eq $it.Name -and $_.PSIsContainer -eq $it.PSIsContainer } | Select-Object -First 1)
                if ($hit.Count) { $orig = $hit[0] }
            }
            if (-not $orig) { continue }
            try {
                $it.CreationTimeUtc = $orig.CreationTimeUtc
                $it.LastWriteTimeUtc = $orig.LastWriteTimeUtc
                $restored++
            } catch {}
        }
        if ($restored) { Write-Log "Timestamps: restored the original created/modified dates on $restored delivered item(s) - the payload must not look edited." Info }
    }

    return [ordered]@{ folder = $Destination; script = "$script"; contentRoot = "$scriptDir"; template = "$TemplatePath"
                       timestampsRestored = $restored
                       placedBy = $(if ($usedResolver) { 'source resolver (tree preserved)' } else { 'FALLBACK - flat copy of what the intake found, folder structure NOT preserved' })
                       placed = $placed.ToArray() }
}

# The template's section markers - where each part of the build order is written.
function Get-AgentSectionMarkers {
    return [ordered]@{
        preInstall    = '## <Perform Pre-Installation tasks here>'
        install       = '## <Perform Installation tasks here>'
        postInstall   = '## <Perform Post-Installation tasks here>'
        preUninstall  = '## <Perform Pre-Uninstallation tasks here>'
        uninstall     = '## <Perform Main-UnInstallation tasks here>'
        postUninstall = '## <Perform Post-UnInstallation tasks here>'
        repair        = '## <Perform Main-Repair tasks here>'
    }
}

# THE TOOL WRITES THE PACKAGE. The AI decided WHAT goes in (the build order); this puts it into the template, under
# the right marker, in the order the AI numbered - deterministically, so the same build order always produces the same
# script. The template's own lines are never touched: steps are inserted directly after the marker.
# Does this text stand on its own as PowerShell? Parsing it is the only honest test - a regex cannot tell.
function Test-AgentCommandParses {
    param([string]$Command)
    $errs = $null
    try { [void][System.Management.Automation.Language.Parser]::ParseInput("$Command", [ref]$null, [ref]$errs) }
    catch { return [ordered]@{ parses = $false; error = "$($_.Exception.Message)" } }
    if (@($errs).Count) { return [ordered]@{ parses = $false; error = "$(@($errs)[0].Message) (line $(@($errs)[0].Extent.StartLineNumber))" } }
    return [ordered]@{ parses = $true; error = '' }
}

function Write-AgentPackageScript {
    param([Parameter(Mandatory)][string]$ScriptPath, [Parameter(Mandatory)]$Instructions)
    if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "Package script not found: $ScriptPath" }
    $lines = [System.Collections.Generic.List[string]](Get-Content -LiteralPath $ScriptPath)
    $written = New-Object System.Collections.Generic.List[object]
    $missing = New-Object System.Collections.Generic.List[object]
    foreach ($kv in (Get-AgentSectionMarkers).GetEnumerator()) {
        # @() around the sort: a single step would unroll to one hashtable, whose .Count is its KEY count, not 1
        $steps = @(@(Get-AgentList $Instructions.($kv.Key)) | Sort-Object { [int]"$($_.order)" })
        if (-not $steps.Count) { continue }
        $at = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ("$($lines[$i])".Trim() -eq $kv.Value) { $at = $i; break } }
        if ($at -lt 0) { $missing.Add([ordered]@{ section = $kv.Key; why = "the template has no marker '$($kv.Value)'" }); continue }
        $indent = ([regex]::Match("$($lines[$at])", '^\s*')).Value
        $block = New-Object System.Collections.Generic.List[string]
        foreach ($s in $steps) {
            $cmd = "$($s.command)".Trim()
            if (-not $cmd) { $missing.Add([ordered]@{ section = $kv.Key; why = "step '$($s.what)' carried no command" }); continue }
            # THE COMMAND IS THE AI'S AND GOES IN EXACTLY AS GIVEN. The tool does not rewrite it, tidy it or "repair"
            # it - a command the tool edited is no longer the command the AI reasoned about, and nobody could then say
            # what the package really does. What the tool DOES do is measure: does this text parse as PowerShell?
            # One command that does not parse makes the WHOLE script unreadable, so a command that fails is left OUT
            # and reported as a fact, with its error. The AI reads that in the verification and decides what to do.
            $chk = Test-AgentCommandParses -Command $cmd
            if (-not $chk.parses) {
                $hint = if ("$cmd" -match "\\'" -or "$cmd" -match '\\\\') { " It contains \' or \\ - escaping that belongs to JSON, not to PowerShell." } else { '' }
                Write-Log "Step '$($s.what)' is not valid PowerShell and was NOT written: $($chk.error)$hint" Warning
                $missing.Add([ordered]@{ section = $kv.Key
                                         why = "step '$($s.what)' is not valid PowerShell, so it was NOT written: $($chk.error)$hint"
                                         command = $cmd.Substring(0, [Math]::Min(300, $cmd.Length)) })
                continue
            }
            if ("$($s.what)".Trim()) { $block.Add("$indent## $($s.what)$(if ("$($s.source)".Trim()) { "   [$($s.source)]" })") }
            foreach ($cl in @($cmd -split "`r?`n")) { $block.Add("$indent$cl") }
        }
        if (-not $block.Count) { continue }
        $lines.InsertRange($at + 1, $block)
        $written.Add([ordered]@{ section = $kv.Key; marker = $kv.Value; steps = $steps.Count; lines = $block.Count })
    }
    # ProcToClose: the template declares it in the session hashtable ("ProcToClose = @()"), so fill that line in place.
    $procs = @(Get-AgentList $Instructions.closeProcesses)
    if ($procs.Count) {
        $list = "@($(($procs | ForEach-Object { "'$(("$_" -replace '\.exe$', '') -replace "'", "''")'" }) -join ', '))"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ("$($lines[$i])" -match '^(?<pre>\s*\$?ProcToClose\s*=\s*)(?<old>.*)$') {
                $lines[$i] = "$($Matches['pre'])$list"
                $written.Add([ordered]@{ section = 'ProcToClose'; marker = 'ProcToClose'; steps = $procs.Count; lines = 1 }); break
            }
        }
    }
    Set-Content -LiteralPath $ScriptPath -Value $lines.ToArray() -Encoding UTF8
    return [ordered]@{ written = $written.ToArray(); notWritten = $missing.ToArray(); totalLines = $lines.Count }
}

# Does this pre-install already remove the application GENERICALLY - by name, folder, service, registry, shortcuts -
# rather than by naming one version? If so, the tool's generated "uninstall the predecessor" block would duplicate
# removal the script already performs. Deterministic safety net behind the AI's own reading.
function Test-AgentGenericRemoval {
    param([string]$Code, $Identity)
    $c = "$Code"
    if (-not $c.Trim()) { return $false }
    # a version-pinned block names a ProductCode, or the previous package/version literally
    $pinned = [bool]([regex]::IsMatch($c, '(?i)Get-ADTApplication\s+-ProductCode|-ProductCode\s+[''"]\{[0-9A-Fa-f-]{36}\}'))
    if (-not $pinned -and $Identity) {
        foreach ($lit in @("$($Identity.Version)", "$($Identity.FullName)")) {
            if ("$lit".Trim() -and $c.Contains("$lit")) { $pinned = $true; break }
        }
    }
    if ($pinned) { return $false }
    # generic removal looks like: stop the processes, remove the install folder / service / registry / shortcuts
    $signals = 0
    foreach ($rx in '(?i)Remove-ADTFolder', '(?i)Remove-ADTRegistryKey', '(?i)Remove-ADTFile[^\r\n]*\.lnk', '(?i)Stop-Process|Stop-Service', '(?i)helper\.exe|uninstall[^\r\n]*\.exe') {
        if ([regex]::IsMatch($c, $rx)) { $signals++ }
    }
    return ($signals -ge 3)
}

# ---- what we know about installers -------------------------------------------------------------------------------------
# Two sources, and the model gets both: the PLAYBOOK (how to recognise each installer technology, what to try, how to
# record a response file, what the exit codes mean) and the PRIORS measured from our OWN shipped packages. Where they
# disagree the corpus wins - it is what has actually worked here. Neither is code: they are evidence for the AI.
function Get-AgentInstallerKnowledge {
    param([switch]$Refresh)
    if ($script:AgentInstallerKnowledge -and -not $Refresh) { return $script:AgentInstallerKnowledge }
    $k = [ordered]@{ playbook = $null; priors = $null; troubleshooting = $null; method = $null }
    # HOW TO WORK, as opposed to what to do. The playbook knows installers; this knows how to read a script, how to
    # verify so that being wrong is still possible, and how to troubleshoot without inventing a story. Every rule in
    # it was paid for by a defect that passed every check we had at the time.
    $mt = Join-Path "$script:AgentHome" 'Knowledge\Method.json'
    if (Test-Path -LiteralPath $mt) { try { $k.method = (Get-Content -LiteralPath $mt -Raw) | ConvertFrom-Json } catch { Write-Log "Method notes would not parse: $($_.Exception.Message)" Warning } }
    $pb = Join-Path "$script:AgentHome" 'Knowledge\InstallerPlaybook.json'
    if (Test-Path -LiteralPath $pb) { try { $k.playbook = (Get-Content -LiteralPath $pb -Raw) | ConvertFrom-Json } catch { Write-Log "Installer playbook unreadable: $($_.Exception.Message)" Warning } }
    $sp = Join-Path "$script:AgentHome" 'Knowledge\SwitchPriors.json'
    if (Test-Path -LiteralPath $sp) { try { $k.priors = (Get-Content -LiteralPath $sp -Raw) | ConvertFrom-Json } catch { Write-Log "Switch priors unreadable: $($_.Exception.Message)" Warning } }
    # Problems this team has already diagnosed, so nobody works one out twice. Grows as we hit new ones.
    $ts = Join-Path "$script:AgentHome" 'Knowledge\Troubleshooting.json'
    if (Test-Path -LiteralPath $ts) { try { $k.troubleshooting = (Get-Content -LiteralPath $ts -Raw) | ConvertFrom-Json } catch { Write-Log "Troubleshooting notes would not parse: $($_.Exception.Message)" Warning } }
    $script:AgentInstallerKnowledge = $k
    return $k
}

# ---- what the template actually gives a package author -----------------------------------------------------------------
# The AI should write configuration with the functions the TEMPLATE ships - the PSADT v4 module and the team's own
# extensions - and fall back to raw PowerShell only when none of them fits. So give it the real inventory, with
# parameters, read from the template itself rather than a guessed list.
function Get-AgentToolkitApi {
    param([string]$TemplatePath, [switch]$Refresh)
    if ($script:AgentToolkitApi -and -not $Refresh) { return $script:AgentToolkitApi }
    if (-not "$TemplatePath".Trim()) { $TemplatePath = Get-AgentTemplatePath }
    $api = [ordered]@{ toolkit = @(); extensions = @(); source = "$TemplatePath" }
    if (-not "$TemplatePath".Trim() -or -not (Test-Path -LiteralPath $TemplatePath)) { $script:AgentToolkitApi = $api; return $api }
    $read = {
        param($Psm1)
        if (-not (Test-Path -LiteralPath $Psm1)) { return @() }
        try {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($Psm1, [ref]$null, [ref]$null)
            return @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object {
                $ps = @(); $al = @()
                $plist = if ($_.Body.ParamBlock) { @($_.Body.ParamBlock.Parameters) } else { @($_.Parameters) }
                foreach ($pp in $plist) {
                    if (-not $pp) { continue }
                    $ps += "-$($pp.Name.VariablePath.UserPath)"
                    # [Alias('Path')] - a call using the alias is a valid call
                    foreach ($at in @($pp.Attributes | Where-Object { $_ -is [System.Management.Automation.Language.AttributeAst] -and "$($_.TypeName.Name)" -ieq 'Alias' })) {
                        foreach ($pa in @($at.PositionalArguments)) { if ($pa.Value) { $al += "-$($pa.Value)" } }
                    }
                }
                [ordered]@{ name = $_.Name; parameters = $ps; aliases = $al; dynamic = [bool]$_.Body.DynamicParamBlock }
            })
        } catch { return @() }
    }
    $api.toolkit = @(& $read (Join-Path $TemplatePath 'PSAppDeployToolkit\PSAppDeployToolkit.psm1'))
    $api.extensions = @(& $read (Join-Path $TemplatePath 'PSAppDeployToolkit.Extensions\PSAppDeployToolkit.Extensions.psm1'))
    # the manifest is the authority on what is actually EXPORTED - keep only those, when it can be read
    foreach ($pair in @(@('toolkit', 'PSAppDeployToolkit\PSAppDeployToolkit.psd1'), @('extensions', 'PSAppDeployToolkit.Extensions\PSAppDeployToolkit.Extensions.psd1'))) {
        try {
            $d = Import-PowerShellDataFile (Join-Path $TemplatePath $pair[1]) -ErrorAction Stop
            $exp = @($d.FunctionsToExport | Where-Object { $_ -and $_ -ne '*' })
            if ($exp.Count) {
                $have = @($api[$pair[0]]); $byName = @{}; foreach ($f in $have) { $byName["$($f.name)"] = $f }
                $api[$pair[0]] = @($exp | ForEach-Object { if ($byName.ContainsKey($_)) { $byName[$_] } else { [ordered]@{ name = $_; parameters = @() } } })
            }
        } catch {}
    }
    $script:AgentToolkitApi = $api
    return $api
}

# A compact, promptable form: "Start-ADTMsiProcess(-Action -FilePath -Transforms ...)" - enough for the model to
# write a valid call without us pasting a 1.2 MB module into the request.
function Format-AgentToolkitApi {
    param($Api, [int]$MaxParams = 10)
    if (-not $Api) { $Api = Get-AgentToolkitApi }
    $fmt = { param($list) @($list | ForEach-Object {
                $p = @($_.parameters | Where-Object { $_ -notmatch '(?i)^-(Verbose|Debug|ErrorAction|WarningAction|InformationAction|ErrorVariable|WarningVariable|InformationVariable|OutVariable|OutBuffer|PipelineVariable|Confirm|WhatIf)$' })
                if ($p.Count -gt $MaxParams) { $p = @($p | Select-Object -First $MaxParams) + @('...') }
                "$($_.name)($($p -join ' '))" }) }
    return [ordered]@{
        toolkit = @(& $fmt $Api.toolkit)
        extensions = @(& $fmt $Api.extensions)
    }
}

# Deterministic v3->v4 / "does this command exist" check on a built script. This is the conversion verification:
# a leftover v3 name (Execute-MSI, Show-InstallationWelcome ...) or an invented function fails at run time, and
# nobody should have to spot that by eye.
function Test-AgentScriptCommands {
    param([Parameter(Mandatory)][string]$ScriptPath, $Api)
    if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "Script not found: $ScriptPath" }
    if (-not $Api) { $Api = Get-AgentToolkitApi }
    $known = @{}
    foreach ($f in @($Api.toolkit)) { $known["$($f.name)".ToLower()] = 'toolkit' }
    foreach ($f in @($Api.extensions)) { $known["$($f.name)".ToLower()] = 'extension' }
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
    $calls = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { "$($_.GetCommandName())" } | Where-Object { $_ -match '^[A-Za-z]+-[A-Za-z0-9]+$' } | Sort-Object -Unique)
    $v3 = @{}
    if ($script:V3ToV4Functions) { foreach ($k in $script:V3ToV4Functions.Keys) { $v3["$k".ToLower()] = "$($script:V3ToV4Functions[$k].NewName)" } }
    $unknown = New-Object System.Collections.Generic.List[object]
    $used = New-Object System.Collections.Generic.List[object]
    foreach ($c in $calls) {
        $lc = $c.ToLower()
        if ($known.ContainsKey($lc)) { $used.Add([ordered]@{ name = $c; from = $known[$lc] }); continue }
        if ($v3.ContainsKey($lc)) { $unknown.Add([ordered]@{ name = $c; why = "PSADT v3 name - the v4 template has no such function; use $($v3[$lc])"; kind = 'v3-leftover' }); continue }
        if (Get-Command $c -ErrorAction SilentlyContinue) { $used.Add([ordered]@{ name = $c; from = 'powershell' }); continue }
        $kind = if ($c -match '(?i)^(Execute|Show|Set|Get|Remove|Copy|New|Test|Write)-(MSI|Process|Installation|RegistryKey|File|Folder|Log|Shortcut)') { 'looks like a v3 name' } else { 'not found anywhere' }
        $unknown.Add([ordered]@{ name = $c; why = $kind; kind = 'unknown' })
    }
    # EVERY PARAMETER HAS TO EXIST ON THE FUNCTION IT IS GIVEN TO. A v3 habit on a v4 name (-ContinueOnError $true on
    # Remove-ADTFile, -Path where v4 only has -LiteralPath) parses fine and fails at run time on the client - a real
    # package shipped three of them past a "every command exists" check. PowerShell also accepts a unique prefix.
    $byName = @{}; foreach ($f in @(@($Api.toolkit) + @($Api.extensions))) { if ($f) { $byName["$($f.name)".ToLower()] = $f } }
    $common = @('verbose', 'debug', 'erroraction', 'warningaction', 'informationaction', 'errorvariable', 'warningvariable', 'informationvariable', 'outvariable', 'outbuffer', 'pipelinevariable', 'whatif', 'confirm', 'ea', 'wa', 'ia', 'ev', 'wv', 'iv', 'ov', 'ob', 'pv', 'vb', 'db', 'wi', 'cf')
    $msiDefaults = try { Get-AgentTemplateMsiDefaults } catch { $null }
    $bad = New-Object System.Collections.Generic.List[object]
    foreach ($cmd in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))) {
        $cn = "$($cmd.GetCommandName())"; $f = $byName[$cn.ToLower()]
        if (-not $f -or $f.dynamic -or -not @($f.parameters).Count) { continue }
        $names = @(@($f.parameters) + @($f.aliases) | ForEach-Object { "$_".TrimStart('-').ToLower() } | Where-Object { $_ })
        $els = @($cmd.CommandElements)
        for ($i = 0; $i -lt $els.Count; $i++) {
            $el = $els[$i]
            if ($el -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
            $pn = "$($el.ParameterName)".ToLower()
            if ($common -contains $pn) { continue }
            $hit = @($names | Where-Object { $_ -eq $pn }); if (-not $hit.Count) { $hit = @($names | Where-Object { $_.StartsWith($pn) }) }
            if ($hit.Count -ne 1 -and -not ($names -contains $pn)) {
                $bad.Add([ordered]@{ line = $el.Extent.StartLineNumber; command = $cn; parameter = "-$($el.ParameterName)"
                                     why = "$cn has no -$($el.ParameterName)$(if ($pn -eq 'continueonerror') { ' (a PSADT v3 habit - v4 functions use -ErrorAction)' }) - it takes $((@($f.parameters) | Select-Object -First 14) -join ' ')" })
                continue
            }
            # -ArgumentList on Start-ADTMsiProcess REPLACES the template's MSI parameters; the template already adds them
            if ($cn -ieq 'Start-ADTMsiProcess' -and "$($hit[0])" -eq 'argumentlist') {
                $val = if ($el.Argument) { "$($el.Argument.Extent.Text)" } elseif ($i + 1 -lt $els.Count) { "$($els[$i + 1].Extent.Text)" } else { '' }
                if ($val -match '(?i)(^|[\s''"])/q|REBOOT\s*=|(^|[\s''"])/l\*?v') {
                    $bad.Add([ordered]@{ line = $el.Extent.StartLineNumber; command = $cn; parameter = '-ArgumentList'
                                         why = "-ArgumentList $val REPLACES the template's own MSI parameters ($(if ($msiDefaults) { $msiDefaults.SilentParams } else { 'config.psd1 MSI section' }) plus logging) - Start-ADTMsiProcess already adds them. Remove it; extra properties go in -AdditionalArgumentList." })
                }
            }
        }
    }
    # PS 5.1: @() over a List[object] of ordered hashtables throws "Argument types do not match" - .ToArray() first.
    $u = $used.ToArray(); $unk = $unknown.ToArray(); $bp = $bad.ToArray()
    return [ordered]@{
        ok = (@($unk).Count -eq 0 -and @($bp).Count -eq 0)
        unknown = $unk
        badParameters = $bp
        usedToolkit = @($u | Where-Object { $_.from -eq 'toolkit' } | ForEach-Object { $_.name })
        usedExtensions = @($u | Where-Object { $_.from -eq 'extension' } | ForEach-Object { $_.name })
        usedPowerShell = @($u | Where-Object { $_.from -eq 'powershell' } | ForEach-Object { $_.name })
    }
}

# THE TEMPLATE MUST SURVIVE UNTOUCHED. A package is the team's blank template plus code injected at the section
# markers - nothing else. So every line of the template should still be in the built script, except the handful that
# are SUPPOSED to differ: the session fields that carry this package's identity, the change-history placeholder, and
# the log entries the build rewrites. Anything else missing means the template itself was altered, which is a defect
# no matter how good the added code looks.
function Test-AgentTemplateIntegrity {
    param([Parameter(Mandatory)][string]$ScriptPath, [string]$TemplatePath)
    if (-not "$TemplatePath".Trim()) { $TemplatePath = Get-AgentTemplatePath }
    $tplFile = if ("$TemplatePath".Trim()) { Join-Path $TemplatePath 'Invoke-AppDeployToolkit.ps1' } else { '' }
    if (-not $tplFile -or -not (Test-Path -LiteralPath $tplFile)) { return [ordered]@{ ok = $null; note = 'the blank template is not reachable - integrity not checked' } }
    if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "Built script not found: $ScriptPath" }
    $norm = { param($p) @(Get-Content -LiteralPath $p | ForEach-Object { ($_ -replace '\s+', ' ').Trim() }) }
    $tpl = & $norm $tplFile
    $built = @{}; foreach ($l in (& $norm $ScriptPath)) { if ($l) { $built[$l] = 1 } }
    # Lines that are MEANT to differ: every field of the session block (they carry THIS package's identity), the
    # change-history placeholder, and the log entries the build rewrites.
    $sessionFields = 'App(Vendor|Name|Version|Arch|Lang|Revision|SuccessExitCodes|RebootExitCodes|ScriptVersion|ScriptDate|ScriptAuthor)|' +
                     'RequireAdmin|InstallName|InstallTitle|DeployAppScript(FriendlyName|Parameters|Version)|' +
                     'ProcToClose|ProcToCloseNonUI|ProcToBlock|FreeSpace|FreeSpaceUninst|CheckForReboot|ShowBalloonTips|UseDialogs|AllowDefer|SoftIdent|OrderNumber'
    $expected = "(?i)^\s*(##\s*\{ScriptDate\}|#+\s*\d{1,2}[./]\d{1,2}[./]\d{4})|^\s*($sessionFields)\s*=|Write-ADTLogEntry|setuplogName|LogName\s*="
    $missing = New-Object System.Collections.Generic.List[string]
    $ignored = 0
    foreach ($l in $tpl) {
        if (-not $l) { continue }
        if ($l -match $expected) { $ignored++; continue }
        if (-not $built.ContainsKey($l)) { $missing.Add($l) }
    }
    # NOTE ON DUPLICATES. "Untouched" should also mean "not duplicated" - the template's own log entry and a
    # predecessor copy of it must not both survive. It is deliberately NOT checked here: the template repeats the
    # same calls (Show-ADTInstallationWelcome, Set-MTBReboot, the phase log entries) in every phase, and measuring a
    # live SHIPPED package produced the same 89 "duplicates" as a fresh build. A check that fires on every correct
    # package is worse than no check. Duplication is a judgement call, so the verify prompt asks the AI for it, with
    # the rule that only the SAME work twice in the SAME phase counts.
    $m = $missing.ToArray()
    return [ordered]@{
        ok = (@($m).Count -eq 0)
        missingFromBuilt = @($m | Select-Object -First 40)
        missingCount = @($m).Count
        templateLines = @($tpl | Where-Object { $_ }).Count
        ignoredAsExpected = $ignored
        template = "$tplFile"
    }
}

# The folder tree of a package, as relative paths - the toolkit's own files left out so the shape is readable.
# This is what a packager looks at first, and the verification needs it: a script can be perfect and the package
# still broken because a folder the script reads was flattened.
function Get-AgentPackageTree {
    param([Parameter(Mandatory)][string]$Root, [int]$Max = 200)
    if (-not (Test-Path -LiteralPath $Root)) { return @() }
    $skip = '(?i)\\(PSAppDeployToolkit|PSAppDeployToolkit\.Extensions|Strings|Assets|Config)\\'
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($i in @(Get-ChildItem -LiteralPath $Root -Recurse -ErrorAction SilentlyContinue)) {
        $rel = $i.FullName.Substring($Root.Length).TrimStart('\')
        if ("$rel\" -match $skip) { continue }
        $out.Add($(if ($i.PSIsContainer) { "$rel\" } else { "$rel  ($([math]::Round($i.Length / 1KB)) KB)" }))
        if ($out.Count -ge $Max) { $out.Add('...(truncated)'); break }
    }
    return $out.ToArray()
}

# The folder that carries the template, for the builders that want a root rather than a path. That is the AGENT's own
# folder now: Template\Content\ holds the template, which is exactly one of the layouts Get-TemplateScript looks for.
# It no longer searches sibling Package Assistance folders - the agent does not depend on what sits next to it, and
# with MTB, GPF and PAG variants around, "the first one found" was a silent way to build the wrong brand.
function Get-AgentToolFolder {
    $p = ''
    try { $p = "$(Get-Setting 'ToolPath')" } catch {}
    if ("$p".Trim() -and (Test-Path -LiteralPath (Join-Path $p 'Build.ps1'))) { return $p }
    if (-not "$script:AgentHome".Trim()) { return '' }
    if (Test-Path -LiteralPath (Join-Path "$script:AgentHome" 'Template\Content\Invoke-AppDeployToolkit.ps1')) { return "$script:AgentHome" }
    return ''
}

# Reduce a full install command to the ARGUMENTS ONLY. The tool already builds the launch itself
# (Get-InstallerRunSpec gives "msiexec /i <local path>" for an MSI), so anything left here that names the installer
# again produces a SECOND /i - which msiexec rejects with 1639 "invalid command line".
# Installer file names routinely contain spaces ("Firefox Setup 140.16.0esr_en-us.msi"), so every pattern that eats a
# path must accept a quoted string with spaces.
# IT LIVES HERE, not in Agent.Ui.ps1, because the evaluation runs in a background runspace and a runspace loads only
# Tools/Gemini/Docs/Prompts/Ops/Core. Defined in Ui it was simply not there when the stage ran, and the whole
# evaluation died with "The term 'Get-AgentArgsOnly' is not recognized".
function Get-AgentArgsOnly { param([string]$Command, [string]$InstallerName)
    $c = "$Command".Trim(); if (-not $c) { return '' }
    $path = '(?:"[^"]+"|''[^'']+''|\S+)'                       # quoted (may contain spaces) or bare
    $c = [regex]::Replace($c, '(?i)^\s*(?:"[^"]*msiexec(?:\.exe)?"|msiexec(?:\.exe)?)\s+', '')   # drop a leading msiexec
    $c = [regex]::Replace($c, "(?i)^\s*/(?:i|package|a|j[mu]?|p|x|fa|fo|fe|fd|fc|fu|fm|fs|fv)\s+$path\s*", '')  # drop the MSI action + its target
    if ("$InstallerName".Trim()) {                              # drop a bare or quoted mention of the installer itself
        $n = [regex]::Escape("$InstallerName".Trim())
        $c = [regex]::Replace($c, "(?i)^\s*(?:""[^""]*$n""|'[^']*$n'|\S*$n)\s*", '')
    }
    $c = [regex]::Replace($c, '(?i)^\s*(?:"[^"]+\.(?:exe|msi|msp)"|''[^'']+\.(?:exe|msi|msp)''|\S+\.(?:exe|msi|msp))\s*', '')
    return $c.Trim()
}
# The $newPkg the tool's builders expect, assembled from what the agent knows. Same shape Build-Step3Script makes.
function New-AgentNewPkg {
    param([Parameter(Mandatory)]$Sheet)
    $id = $Sheet.identity
    $inst = @(Get-AgentList $Sheet.sources.installers)
    $main = $null
    $spec = Get-AgentPackageSpec -Sheet $Sheet
    # WHAT THE MACHINE PROVED beats what the plan hoped - including a second method tested after the first
    $steps = if (@(Get-AgentList $Sheet.provenSteps).Count) { @(@(Get-AgentList $Sheet.provenSteps) | Sort-Object { [int]"$($_.order)" }) }
             else { @(@(Get-AgentList $Sheet.plan.install.steps) | Sort-Object { [int]"$($_.order)" }) }
    $mainStep = @($steps | Where-Object { "$($_.purpose)" -match '(?i)main' }) | Select-Object -First 1
    if (-not $mainStep -and $steps.Count) { $mainStep = $steps[-1] }
    # on a reuse the plan names the file the predecessor installed from; otherwise the main install step
    $wanted = if ((Test-AgentIsReuse -Sheet $Sheet) -and "$($spec.sourceFileToUse)".Trim()) { Split-Path -Leaf "$($spec.sourceFileToUse)" } elseif ($mainStep) { Split-Path -Leaf "$($mainStep.installer)" } else { '' }
    if ($wanted) { $main = @($inst | Where-Object { "$($_.name)" -ieq $wanted }) | Select-Object -First 1 }
    if ($wanted -and -not $main) {
        # the resolver fingerprints only the largest installers - the plan may name one further down the list
        $p = Find-AgentOrderFile -Folder "$($Sheet.folder)" -Name $wanted -AlsoLookIn @(Get-AgentInstallerRoots -Sheet $Sheet)
        if ($p) { try { $main = Get-AgentInstallerFacts -File (Get-Item -LiteralPath $p) } catch {} }
    }
    if (-not $main) { $main = @($inst | Where-Object { $_.ext -in '.msi', '.exe' }) | Select-Object -First 1 }
    $np = @{
        Vendor = "$($id.vendor)"; AppName = "$($id.app)"; Arch = "$($id.arch)"; Lang = "$($id.lang)"
        Revision = "$($id.release)"; Version = "$($id.version)"; FullName = "$($Sheet.package)"
        ProductCode = "$($main.productCode)"; Ritm = "$($Sheet.ritm)"; Author = "$(try { Get-AuthorName } catch { '' })"
    }
    # WHICH MODE? The tool's builder already knows how to write a single installer, an ordered sequence of them, or a
    # loose-files package - it just has to be told which. That decision is the AI's route and its install steps.
    $route = $Sheet.plan.route
    $seq = $steps
    $byName = @{}; foreach ($i in $inst) { $byName["$($i.name)"] = $i }
    # MSIs that were not delivered - caught while the vendor EXE ran, or extracted - carry their product code too
    foreach ($c in @(@(Get-AgentList $Sheet.msiCaptured) + @(Get-AgentList $Sheet.extractedMsis.candidates))) { if ($c -and "$($c.file)".Trim() -and -not $byName.ContainsKey("$($c.file)")) { $byName["$($c.file)"] = @{ name = "$($c.file)"; productCode = "$($c.productCode)" } } }
    # ROUTE 5: package the MSI that came out of the wrapper instead of the wrapper. Only honoured when the AI said so
    # AND the file it named is really among the extracted candidates - a name it invented must never reach the build.
    $extractedMsi = $null
    $pem = $Sheet.decision.packageExtractedMsi
    if ($pem -and [bool]$pem.use -and "$($pem.file)".Trim()) {
        $extractedMsi = @(Get-AgentList $Sheet.extractedMsis.candidates | Where-Object { "$($_.file)" -eq "$($pem.file)" -and $_.readable }) | Select-Object -First 1
    }

    if ("$($route.number)" -eq '7' -or ($inst.Count -eq 0 -and @($Sheet.sources.installers).Count -eq 0)) {
        # LOOSE FILES - 13% of orders arrive with no installer at all. The script copies the payload, makes the
        # shortcut and writes the ARP entry; there is nothing to run.
        $np.InstallerMode = 'LooseFiles'
        $np.CreateArp = $true
        $sc = @(Get-AgentList $Sheet.decision.items | Where-Object { "$($_.category)" -match '(?i)shortcut' -and "$($_.action)" -eq 'keep' })
        if ($sc.Count) { $np.Shortcuts = @($sc | ForEach-Object { @{ Target = "$($_.label)" } }) }
    }
    elseif (@($seq).Count -ge 2) {
        # SEVERAL INSTALLERS in the order the instructions gave - 59% of our packages
        $np.InstallerMode = 'Multiple'
        $np.Installers = @(@($seq | Sort-Object { [int]"$($_.order)" }) | ForEach-Object {
                $nm = Split-Path -Leaf "$($_.installer)"; $f = $byName[$nm]
                if ([IO.Path]::GetExtension($nm) -ieq '.msi') { @{ Type = 'MSI'; MsiFileName = $nm; ProductCode = "$($f.productCode)" } }
                else { @{ Type = 'EXE'; ExeFileName = $nm; InstallParams = "$($_.arguments)"; UninstallParams = '' } } })
    }
    elseif ($extractedMsi) {
        # ROUTE 5 - the wrapper turned out to be a shell around the real MSI, and the AI confirmed from the extracted
        # facts that THIS MSI is the application. Packaging it directly gives a cleaner install and a real ProductCode
        # to detect on. New-AgentPackageSkeleton places the file; here we only name it.
        $np.MsiFileName = "$($extractedMsi.file)"
        $np.ProductCode = "$($extractedMsi.productCode)"
        $np.InstallerMode = 'SingleMSI'
    }
    elseif ($main) {
        # ONE installer, whatever else was delivered beside it - the mode is set explicitly, because the builder would
        # otherwise read "more than one file in Installers" as a multi-installer package
        if ("$($main.ext)" -eq '.msi') { $np.MsiFileName = "$($main.name)"; $np.InstallerMode = 'SingleMSI' }
        else {
            $np.InstallerMode = 'SingleEXE'
            $np.ExeFileName = "$($main.name)"
            $won = if ($Sheet.trial -and $Sheet.trial.winner) { "$($Sheet.trial.winner.arguments)" } else { '' }
            if (-not $won -and @($seq).Count -eq 1) { $won = "$(@($seq)[0].arguments)" }
            if ($won) { $np.InstallParams = $won }            # what the machine PROVED, not what the form hoped
            if ($Sheet.decision -and "$($Sheet.decision.uninstall.command)".Trim()) { $np.UninstallCommand = "$($Sheet.decision.uninstall.command)" }
        }
        $np.Installers = @($inst | ForEach-Object { @{ Name = "$($_.name)"; Path = "$($_.path)"; Ext = "$($_.ext)" } })
        # the transform the plan's install line applies; otherwise one delivered right beside the MSI
        $tm = [regex]::Match("$($mainStep.arguments)", '(?i)TRANSFORMS\s*=\s*"?([^";]+?\.mst)')
        if ($tm.Success) { $np.MstFileName = Split-Path -Leaf $tm.Groups[1].Value }
        elseif (@($main.mstNearby).Count) { $np.MstFileName = "$(@($main.mstNearby)[0])" }
    }
    # what the plan and the test settled, where they said anything
    if ("$($spec.detection.key)".Trim()) { $np.SoftIdent = "$($spec.detection.key)" }
    $procs = @(Get-AgentList $spec.closeProcesses)
    if ($procs.Count) {
        # PROCESS NAMES, NOT OBJECTS. On the first live run this wrote
        # "ProcToClose gained System.Collections.Specialized.OrderedDictionary, ..." into the package, because the
        # list held structured items and "$_" on one of those is its TYPE NAME. Take the name out of whatever shape
        # arrives, and drop anything that does not look like a process name rather than writing rubbish into a script.
        $names = @($procs | ForEach-Object {
            $v = $_
            if ($null -eq $v) { return }
            $s = if ($v -is [string]) { $v }
                 elseif ($v -is [System.Collections.IDictionary]) { "$(@($v['name'], $v['process'], $v['processName'], $v['exe'], $v['label']) | Where-Object { "$_".Trim() } | Select-Object -First 1)" }
                 else {
                     $p = @('name', 'process', 'processName', 'exe', 'label') | Where-Object { $v.PSObject.Properties[$_] } | Select-Object -First 1
                     if ($p) { "$($v.PSObject.Properties[$p].Value)" } else { "$v" }
                 }
            $s = "$s".Trim() -replace '\.exe$', ''
            # a real process name: no spaces, no path separators, no type names
            if ($s -and $s -notmatch '[\\/:*?"<>|\s]' -and $s -notmatch '^System\.') { $s }
        } | Where-Object { $_ } | Select-Object -Unique)
        if ($names.Count) { $np.SnapshotProcs = @($names) }
        $dropped = @($procs).Count - $names.Count
        if ($dropped -gt 0) { Write-Log "ProcToClose: $dropped entry(ies) were not usable process names and were left out." Warning }
    }
    if (-not "$($np.SoftIdent)".Trim() -and "$($np.ProductCode)".Trim()) { $np.SoftIdent = "$($np.ProductCode)" }
    return $np
}

# The same edit, matched line by line with each line trimmed: the find's lines must appear consecutively (blank lines
# ignored), exactly once; the matched lines are replaced, the first line's indentation kept. Parsing is protected.
function Edit-AgentScriptTrimmed {
    param([Parameter(Mandatory)][string]$Path, [string]$Find, [string]$ReplaceWith = '')
    $res = [ordered]@{ ok = $false; path = "$Path"; note = ''; occurrences = 0 }
    $want = @("$Find" -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $want.Count -or -not (Test-Path -LiteralPath $Path)) { $res.note = 'nothing to match'; return $res }
    $bytes = [IO.File]::ReadAllBytes($Path); $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [Text.Encoding]::UTF8.GetString($bytes, $(if ($bom) { 3 } else { 0 }), $bytes.Length - $(if ($bom) { 3 } else { 0 }))
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = @($text -split "`r?`n")
    $hits = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ne $want[0]) { continue }
        $j = $i; $k = 0
        while ($j -lt $lines.Count -and $k -lt $want.Count) { $t = $lines[$j].Trim(); if (-not $t) { $j++; continue }; if ($t -ne $want[$k]) { break }; $j++; $k++ }
        if ($k -eq $want.Count) { $hits += , @($i, ($j - 1)) }
    }
    $res.occurrences = $hits.Count
    if ($hits.Count -ne 1) { $res.note = $(if ($hits.Count) { "matches $($hits.Count) places - not changed" } else { 'not found even ignoring indentation' }); return $res }
    $from = $hits[0][0]; $to = $hits[0][1]
    $indent = [regex]::Match($lines[$from], '^\s*').Value
    $newLines = @("$ReplaceWith" -split "`r?`n" | ForEach-Object { if ($_.Trim()) { $indent + $_.TrimStart() } else { '' } })
    $out = @(); if ($from -gt 0) { $out += $lines[0..($from - 1)] }; $out += $newLines; if ($to -lt $lines.Count - 1) { $out += $lines[($to + 1)..($lines.Count - 1)] }
    $new = $out -join $nl
    $e1 = $null; $e2 = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$e1)
    [void][System.Management.Automation.Language.Parser]::ParseInput($new, [ref]$null, [ref]$e2)
    if (@($e2).Count -gt @($e1).Count) { $res.note = 'NOT WRITTEN - the script would stop parsing'; return $res }
    [IO.File]::WriteAllText($Path, $new, (New-Object Text.UTF8Encoding $bom))
    $res.ok = $true; $res.line = $from + 1; $res.note = 'matched ignoring indentation'
    return $res
}

# THE AI'S OWN EDITS TO A REUSED SCRIPT, applied exactly as written: each find must occur once, and a change that would
# stop the script parsing is not made. What could not be applied is reported, never guessed at - verify sees both.
function Invoke-AgentPlannedChanges {
    param([Parameter(Mandatory)][string]$ScriptPath, $Changes)
    $done = New-Object System.Collections.Generic.List[object]; $notDone = New-Object System.Collections.Generic.List[object]
    foreach ($ch in @(Get-AgentList $Changes)) {
        if (-not "$($ch.find)".Trim()) { $notDone.Add([ordered]@{ why = "$($ch.why)"; problem = 'no find text' }); continue }
        $e = Edit-AgentScript -Path $ScriptPath -Find "$($ch.find)" -ReplaceWith "$($ch.replaceWith)"
        # THE FIND WAS COPIED FROM A v3 PREDECESSOR: the build converted it to v4, so try the converted form
        if (-not $e.ok -and [int]$e.occurrences -eq 0 -and (Get-Command Convert-V3ToV4Content -ErrorAction SilentlyContinue)) {
            $conv = try { "$(Convert-V3ToV4Content -Content "$($ch.find)")" } catch { '' }
            if ($conv.Trim() -and $conv -ne "$($ch.find)") { $e2 = Edit-AgentScript -Path $ScriptPath -Find $conv -ReplaceWith "$($ch.replaceWith)"; if ($e2.ok) { $e = $e2; $e.note = 'matched after converting the find text from v3 to v4' } }
        }
        # ...or it differs only in indentation: match line by line, trimmed - still exactly once
        if (-not $e.ok -and [int]$e.occurrences -eq 0) {
            $e3 = Edit-AgentScriptTrimmed -Path $ScriptPath -Find "$($ch.find)" -ReplaceWith "$($ch.replaceWith)"
            if (-not $e3.ok -and (Get-Command Convert-V3ToV4Content -ErrorAction SilentlyContinue)) { $conv = try { "$(Convert-V3ToV4Content -Content "$($ch.find)")" } catch { '' }; if ($conv.Trim()) { $e3 = Edit-AgentScriptTrimmed -Path $ScriptPath -Find $conv -ReplaceWith "$($ch.replaceWith)" } }
            if ($e3.ok) { $e = $e3 }
        }
        if ($e.ok) { $done.Add([ordered]@{ section = "$($ch.section)"; why = "$($ch.why)"; line = $e.line; how = "$($e.note)" }) }
        else {
            # already in? (the builder may have made the same swap itself) - only believable for a substantial text
            # whose old form is gone; a short replacement like 'x' is in every script by accident
            $newT = "$($ch.replaceWith)".Trim(); $oldT = "$($ch.find)".Trim()
            $already = try { $txt = [IO.File]::ReadAllText($ScriptPath); ($newT.Length -ge 12 -and $txt.Contains($newT) -and -not $txt.Contains($oldT)) } catch { $false }
            if ($already) { $done.Add([ordered]@{ section = "$($ch.section)"; why = "$($ch.why)"; note = 'already in the built script' }) }
            else { $notDone.Add([ordered]@{ section = "$($ch.section)"; why = "$($ch.why)"; find = "$($ch.find)"; problem = "$($e.note)" }) }
        }
    }
    return [ordered]@{ applied = $done.ToArray(); notApplied = $notDone.ToArray() }
}

# STAGE build: THE TOOL builds the package - template in, delivered files placed, the AI's plan written into the
# script. No model call: the thinking happened at plan and evaluate; the AI checks the result in 'verify'.
function Invoke-AgentPackageBuild {
    param([Parameter(Mandatory)]$Sheet, [string]$TemplatePath, [string]$Destination, [scriptblock]$Progress)
    # THE SCRIPT IS BUILT THE WAY PACKAGE ASSISTANCE BUILDS IT - by its own builders, on its own template:
    #   Build-PredecessorScript   when a predecessor model exists and the AI said to reuse it. The predecessor's code
    #                             sections and session block go into a FRESH template, installer references and the
    #                             version are swapped, the uninstall-previous chain is preserved, SoftIdent carried.
    #   Build-FreshScript         otherwise.
    # The agent contributes the DECISIONS ($newPkg) and, afterwards, its own extra steps at the section markers.
    $decision = "$($Sheet.plan.route.kind)"
    $spec = Get-AgentPackageSpec -Sheet $Sheet
    $predPath = if ($Sheet.history -and $Sheet.history.predecessor) { "$($Sheet.history.predecessor.path)" } else { '' }
    $wantReuse = (Test-AgentIsReuse -Sheet $Sheet) -and $predPath -and (Test-Path -LiteralPath $predPath)
    # A PREDECESSOR THAT EXISTS BUT IS NOT BEING REUSED IS WORTH SAYING OUT LOUD - deliberate when the plan chose a
    # fresh package, an accident when there was no plan at all.
    $Sheet.predecessorNotReused = $null
    if ($predPath -and (Test-Path -LiteralPath $predPath) -and -not $wantReuse) {
        $deliberate = ($decision -eq 'fresh')
        $Sheet.predecessorNotReused = [ordered]@{
            predecessor = (Split-Path -Leaf $predPath); path = $predPath; aiDecision = $decision; deliberate = $deliberate
            what = $(if ($deliberate) { "the plan builds it fresh: $($Sheet.plan.route.why)" }
                     else { "a predecessor WAS found ($(Split-Path -Leaf $predPath)) but there is no plan to reuse it ($(Get-AgentStageStatus -Sheet $Sheet -Id 'plan')), so this package is built from the bare template - check that is what you want." })
        }
        if (-not $deliberate) { Write-Log "A predecessor was found ($(Split-Path -Leaf $predPath)) but is NOT being reused - there is no plan saying so. Building from the template instead." Warning }
    }
    $base = $null; $builtText = ''; $builtWith = ''
    try {
        if ($Progress) { & $Progress 'laying out the package from the team template' }
        $base = New-AgentPackageSkeleton -Sheet $Sheet -TemplatePath $TemplatePath -Destination $Destination
        if (Get-Command Build-PredecessorScript -ErrorAction SilentlyContinue) {
            $toolRoot = Get-AgentToolFolder
            $tpl = if ($toolRoot) { try { Get-TemplateScript -Root $toolRoot } catch { '' } } else { '' }
            if (-not "$tpl".Trim() -and (Test-Path -LiteralPath $base.script)) { $tpl = [IO.File]::ReadAllText($base.script) }
            $newPkg = New-AgentNewPkg -Sheet $Sheet
            $model = $null
            if ($wantReuse) { try { $model = Read-PredecessorModel -PackagePath $predPath -PackageName (Split-Path -Leaf $predPath) } catch { Write-Log "AI: predecessor model unreadable: $($_.Exception.Message)" Warning } }
            if ($model) {
                # Does this package already remove the old version GENERICALLY? Then a version-pinned block would
                # duplicate it. The AI decides from the pre-install text; Test-AgentGenericRemoval is the safety net.
                $addPrev = $true; $why = "the tool's default"
                $pr = $spec.predecessorRemoval
                if ($pr -and $null -ne $pr.addGeneratedBlock) {
                    $addPrev = [bool]$pr.addGeneratedBlock
                    $why = "the AI read the pre-install: removal is $($pr.handledToday)"
                } elseif (Test-AgentGenericRemoval -Code "$($model.Code.PreInstallCode)" -Identity $model.Identity) {
                    $addPrev = $false
                    $why = 'the pre-install already removes the application generically (no version or ProductCode pinned)'
                }
                Write-Log "Reuse: uninstall-previous block $(if ($addPrev) { 'ADDED' } else { 'NOT added' }) - $why"
                if ($Progress) { & $Progress "building from the predecessor ($decision); uninstall-previous block: $(if ($addPrev) { 'added' } else { 'not needed - ' + $why })" }
                $builtText = Build-PredecessorScript -Model $model -NewPkg $newPkg -Template $tpl -AddUninstallPrevious $addPrev
                $builtWith = 'Build-PredecessorScript'
                $uninstallPrevNote = $why; $uninstallPrevAdded = $addPrev
            } elseif (Get-Command Build-FreshScript -ErrorAction SilentlyContinue) {
                if ($Progress) { & $Progress "building a fresh script with the tool's own builder" }
                $builtText = Build-FreshScript -NewPkg $newPkg -Template $tpl
                $builtWith = 'Build-FreshScript'
            }
            if ("$builtText".Trim() -and "$builtText" -notmatch '^\s*#\s*(Build failed|Blank template not found)') {
                Set-Content -LiteralPath $base.script -Value $builtText -Encoding UTF8 -NoNewline
            } elseif ("$builtText".Trim()) {
                throw "the tool's builder returned: $("$builtText" -split "`n" | Select-Object -First 1)"
            }
        }
    } catch {
        Write-Log "Package build failed: $($_.Exception.Message)" Warning
        $Sheet.build = [ordered]@{ error = "$($_.Exception.Message)" }
        [void](Set-AgentStage -Sheet $Sheet -Id 'build' -Status 'failed' -Note "$($_.Exception.Message)")
        [void](Save-AgentSheet -Sheet $Sheet); return $Sheet
    }
    if (-not "$($base.script)".Trim()) {
        $why = "the template produced no Invoke-AppDeployToolkit.ps1"
        $Sheet.build = [ordered]@{ error = "$why under $($base.folder)"; folder = "$($base.folder)" }
        [void](Set-AgentStage -Sheet $Sheet -Id 'build' -Status 'failed' -Note "$why")
        [void](Save-AgentSheet -Sheet $Sheet); return $Sheet
    }
    $Sheet.package_folder = "$($base.folder)"
    try {
        $basedOn = if ($builtWith -eq 'Build-PredecessorScript') { 'predecessor' } elseif ($builtWith) { 'template' } else { 'template (agent fallback)' }
        $b = [ordered]@{ folder = "$($base.folder)"; script = "$($base.script)"; placed = $base.placed
                         placedBy = "$($base.placedBy)"; contentRoot = "$($base.contentRoot)"
                         basedOn = $basedOn; builtWith = "$builtWith"; template = "$($base.template)"
                         reuseDecision = "$decision" }
        $files = @($base.placed | Where-Object { $_.ok }).Count
        $note = if ($builtWith) { "$builtWith, $files file(s) placed" } else { "template only (the tool's builders are not loaded), $files file(s) placed" }
        if ($builtWith -eq 'Build-PredecessorScript') {
            $b.uninstallPreviousAdded = [bool]$uninstallPrevAdded; $b.uninstallPreviousWhy = "$uninstallPrevNote"
            $note = "$note; uninstall-previous block $(if ($uninstallPrevAdded) { 'added' } else { 'not added' }) - $uninstallPrevNote"
        }
        # THE AI'S PLAN GOES IN. Two ways, never both:
        #   a reused script   IS the build order - the AI's changes are applied to it as find/replace, in place. Writing
        #                     section steps on top of it is how a package once carried the same logic twice.
        #   a fresh script    gets the AI's section steps written under the template markers.
        $steps = 0
        if ($builtWith -eq 'Build-PredecessorScript') {
            if (@(Get-AgentList $spec.changes).Count) {
                if ($Progress) { & $Progress "applying the $(@(Get-AgentList $spec.changes).Count) change(s) the plan asked for" }
                $pc = Invoke-AgentPlannedChanges -ScriptPath $base.script -Changes $spec.changes
                $b.changesApplied = $pc.applied; $b.changesNotApplied = $pc.notApplied
                $note = "$note; $(@($pc.applied).Count) planned change(s) applied$(if (@($pc.notApplied).Count) { ", $(@($pc.notApplied).Count) NOT - left for verify" })"
            }
        }
        elseif (@('preInstall', 'install', 'postInstall', 'preUninstall', 'uninstall', 'postUninstall', 'repair') | Where-Object { @(Get-AgentList $spec[$_]).Count }) {
            if ($Progress) { & $Progress 'writing the planned steps at the section markers' }
            $w = Write-AgentPackageScript -ScriptPath $base.script -Instructions $spec
            $b.sectionsWritten = $w.written; $b.notWritten = $w.notWritten
            foreach ($s in @($w.written)) { $steps += [int]$s.steps }
            if ($steps) { $note = "$note; plus $steps agent step(s) in $(@($w.written).Count) section(s)" }
        } elseif (-not $builtWith) {
            throw 'no plan to build from and the tool''s builders are not available'
        }

        # THE TOOL MEASURES, THE AI DECIDES. Whether the finished script parses is a fact PowerShell can answer
        # exactly, so the tool answers it and records it - it does NOT decide what that means for the package. The
        # verification stage reads `scriptParses` and returns the verdict, and only a pass completes the package.
        # (The first live run shipped a script with 15 syntax errors because nobody measured; now everyone can see it.)
        $chkParse = Test-AgentScriptParses -ScriptPath $base.script
        $b.scriptParses = $chkParse
        if ($chkParse.parses -eq $false) {
            $first = @($chkParse.errors) | Select-Object -First 3 | ForEach-Object { "line $($_.line): $($_.message)" }
            $note = "$note; THE SCRIPT DOES NOT PARSE - $($chkParse.errorCount) error(s): $($first -join ' | ')"
            Write-Log "Built script does not parse ($($chkParse.errorCount) error(s)) - recorded for the verification to judge." Warning
            Add-AgentTimeline $Sheet "built script does not parse: $($chkParse.errorCount) error(s) - the verification decides what happens next"
        }
        $Sheet.build = $b
        Add-AgentTimeline $Sheet "package built at $($base.folder) ($($b.basedOn))"
        [void](Set-AgentStage -Sheet $Sheet -Id 'build' -Status 'done' -Note "$note" -Data @{ script = "$($base.script)"; folder = "$($base.folder)"; basedOn = "$($b.basedOn)" })
    } catch {
        Write-Log "Package build failed: $($_.Exception.Message)" Warning
        $Sheet.build = [ordered]@{ error = "$($_.Exception.Message)"; folder = "$($base.folder)"; script = "$($base.script)" }
        [void](Set-AgentStage -Sheet $Sheet -Id 'build' -Status 'failed' -Note "$($_.Exception.Message)" -Data @{ script = "$($base.script)"; folder = "$($base.folder)" })
    }
    [void](Save-AgentSheet -Sheet $Sheet)
    return $Sheet
}
#endregion

#region Install runner (this machine) -----------------------------------------------------------------------------------
# A command the AI wrote names files the way a human would - "TRANSFORMS=Firefox Setup 140.16.0esr_en-us.mst". msiexec
# resolves that against the CURRENT DIRECTORY, not against the .msi, so the moment the installer is run from a copy the
# transform is silently not found and the install fails. Give every file-valued property a full path before running it.
function Resolve-AgentArgumentPaths {
    param([string]$Arguments, [string]$InstallerPath, [string[]]$AlsoLookIn = @())
    $a = "$Arguments"
    if (-not $a.Trim()) { return $a }
    $roots = @()
    if ("$InstallerPath".Trim()) { $roots += (Split-Path -Parent $InstallerPath) }
    $roots += @($AlsoLookIn | Where-Object { "$_".Trim() })
    $roots = @($roots | Where-Object { "$_".Trim() -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
    if (-not $roots.Count) { return $a }
    # TRANSFORMS / PATCH take a semicolon-separated list; the others take one file
    foreach ($prop in 'TRANSFORMS', 'PATCH', 'ADDLOCAL_FILE', 'SETUPEXEPATH') {
        # two shapes: PROP="a name with spaces.mst"  or  PROP=noSpaces.mst
        # (a lazy [^"]+? with a \s lookahead would stop at the first space inside the quotes - that was the bug)
        $a = [regex]::Replace($a, "(?i)(?<pre>(?<![\w-])$prop\s*=\s*)(?:""(?<val>[^""]*)""|(?<val>[^""\s]+))", {
            param($m)
            $vals = @("$($m.Groups['val'].Value)" -split ';')
            $out = @()
            foreach ($v in $vals) {
                $t = "$v".Trim()
                if (-not $t) { continue }
                if ($t -match '^[-/]') { $out += $t; continue }   # a switch
                if ($t -match '^[A-Za-z]:\\|^\\\\') {
                    if (Test-Path -LiteralPath $t) { $out += $t; continue }   # absolute and really there
                    # an instructions document's own path ("C:\SW-Source\x.mst") that does not exist here: the file is
                    # the delivered one with that name
                    $t = Split-Path -Leaf $t
                }
                $hit = $null
                foreach ($r in $roots) { $c = Join-Path $r $t; if (Test-Path -LiteralPath $c) { $hit = $c; break } }
                $out += $(if ($hit) { $hit } else { $t })
            }
            return "$($m.Groups['pre'].Value)`"$($out -join ';')`""
        })
    }
    return $a
}

# THE AI WRITES THE WHOLE COMMAND, THE HANDS READ IT. A full line as a packager would type it at an elevated prompt -
# msiexec /i "C:\SW-Source\x.msi" TRANSFORMS="x.mst", or "Ceus82.exe" /SILENT - is split into the installer it names
# and the arguments it passes, so what runs is exactly what the AI wrote, and nothing it wrote is silently dropped.
function ConvertFrom-AgentCommandLine {
    param([string]$Line)
    $out = [ordered]@{ ok = $false; installer = ''; arguments = ''; note = '' }
    $c = "$Line".Trim()
    if (-not $c) { $out.note = 'no command line'; return $out }
    $m = [regex]::Match($c, '(?i)^\s*"?(?:[^"\s]*\\)?msiexec(?:\.exe)?"?\s+(?:/i|/package|-i|/p|/update)\s+(?:"([^"]+)"|(\S+))\s*(.*)$')
    if ($m.Success) { $f = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }; $out.installer = Split-Path -Leaf $f; $out.arguments = $m.Groups[3].Value.Trim() }
    elseif ($c -match '^\s*"([^"]+)"\s*(.*)$') { $out.installer = Split-Path -Leaf $Matches[1]; $out.arguments = "$($Matches[2])".Trim() }
    elseif ($c -match '(?i)^\s*(\S+?\.(exe|msi|msp|cmd|bat))(\s+(.*))?$') { $out.installer = Split-Path -Leaf $Matches[1]; $out.arguments = "$($Matches[4])".Trim() }
    elseif ($c -match '(?i)^\s*(.+?\.(exe|msi|msp))(\s+(.*))?$') { $out.installer = Split-Path -Leaf $Matches[1]; $out.arguments = "$($Matches[4])".Trim() }   # an unquoted path with spaces
    if (-not $out.installer) { $out.note = "no installer could be read out of: $c"; return $out }
    $out.ok = $true
    return $out
}

# Did the MSI line really run as written? The verbose log answers what an exit code cannot: which package was opened,
# whether the transform was applied, how the install ended.
function Test-AgentMsiLog {
    param([string]$LogPath, [string]$Arguments = '')
    $r = [ordered]@{ exists = $false; transformsAsked = @(); transformsApplied = @(); transformsNotSeen = @(); product = ''; outcome = ''; returnValue = $null; errorLines = @() }
    foreach ($m in @([regex]::Matches("$Arguments", '(?i)TRANSFORMS\s*=\s*(?:"([^"]+)"|(\S+))'))) {
        $v = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        foreach ($t in @("$v" -split ';' | Where-Object { "$_".Trim() })) { $r.transformsAsked += (Split-Path -Leaf "$t".Trim()) }
    }
    if (-not "$LogPath".Trim() -or -not (Test-Path -LiteralPath $LogPath)) { return $r }
    $r.exists = $true
    $text = try { [IO.File]::ReadAllText($LogPath) } catch { '' }   # msiexec writes UTF-16; ReadAllText detects the BOM
    # "Looking for file transform: C:\...\x.mst" / "Applying transform" - the name on a line that talks about a transform
    foreach ($t in $r.transformsAsked) { if ($text -match "(?im)^[^\r\n]*transform[^\r\n]*$([regex]::Escape($t))") { $r.transformsApplied += $t } else { $r.transformsNotSeen += $t } }
    $pm = [regex]::Match($text, '(?im)Product:\s*(.+?)\s--\s*(Installation|Removal|Configuration)\s+(completed successfully|operation failed|failed)[^\r\n]*')
    if ($pm.Success) { $r.product = $pm.Groups[1].Value.Trim(); $r.outcome = "$($pm.Groups[2].Value) $($pm.Groups[3].Value)" }
    $rv = [regex]::Match($text, '(?i)MainEngineThread is returning (\d+)'); if ($rv.Success) { $r.returnValue = [int]$rv.Groups[1].Value }
    $r.errorLines = @([regex]::Matches($text, '(?im)^.*(Return value 3|Error \d{4}\.|error code \d+).*$') | Select-Object -First 6 | ForEach-Object { $_.Value.Trim().Substring(0, [Math]::Min(220, $_.Value.Trim().Length)) })
    return $r
}

# WHAT THE TEMPLATE'S TOOLKIT ADDS TO EVERY MSIEXEC CALL BY ITSELF - Config\config.psd1, MSI section. Start-ADTMsiProcess
# puts SilentParams (or UninstallParams) and the logging switch on the command line unless the script REPLACES them with
# -ArgumentList. A test that runs an MSI without them tests a line the package never runs: on a real order the bare
# "msiexec /i x.msi TRANSFORMS=x.mst" showed the wizard, was judged "not silent", and verify then wrote
# /qn REBOOT=ReallySuppress into a package whose template already supplies exactly that.
function Get-AgentTemplateMsiDefaults {
    if ($script:AgentMsiDefaults) { return $script:AgentMsiDefaults }
    $d = [ordered]@{ InstallParams = 'REBOOT=ReallySuppress /QN'; SilentParams = 'REBOOT=ReallySuppress /QN'; UninstallParams = 'REBOOT=ReallySuppress /QN'; LoggingOptions = '/L*V'; source = 'built-in (the template config could not be read)' }
    try {
        $cfg = Join-Path (Get-AgentTemplatePath) 'Config\config.psd1'
        if (Test-Path -LiteralPath $cfg) {
            $text = [IO.File]::ReadAllText($cfg)
            $m = [regex]::Match($text, '(?s)\bMSI\s*=\s*@\{(.*?)\r?\n\s*\}')
            $block = if ($m.Success) { $m.Groups[1].Value } else { $text }
            foreach ($k in 'InstallParams', 'SilentParams', 'UninstallParams', 'LoggingOptions') {
                $km = [regex]::Match($block, "(?m)^\s*$k\s*=\s*'([^']*)'")
                if ($km.Success) { $d[$k] = $km.Groups[1].Value }
            }
            $d.source = "$cfg"
        }
    } catch {}
    $script:AgentMsiDefaults = $d
    return $d
}

# The MSI line exactly as Start-ADTMsiProcess builds it from these arguments: the template's parameters are added
# unless the arguments already carry a UI level, and a verbose log is written so a failure can be read.
function Add-AgentMsiDefaults {
    param([string]$Arguments, [ValidateSet('install', 'uninstall')][string]$Action = 'install', [string]$LogPath = '')
    $d = Get-AgentTemplateMsiDefaults
    $a = "$Arguments".Trim(); $added = @()
    if ($a -notmatch '(?i)(^|\s)/(q[nbrf]?[+-]?|quiet|passive)(\s|$)') {
        $p = if ($Action -eq 'uninstall') { "$($d.UninstallParams)" } else { "$($d.SilentParams)" }
        if ($p.Trim()) { $a = "$a $p".Trim(); $added += $p }
    }
    if ("$LogPath".Trim() -and $a -notmatch '(?i)(^|\s)/l[\*a-z+!]*\s') {
        $lo = if ("$($d.LoggingOptions)".Trim()) { "$($d.LoggingOptions)" } else { '/L*V' }
        $a = "$a $lo `"$LogPath`"".Trim(); $added += "$lo <log>"
    }
    return @{ Arguments = $a; Added = @($added) }
}

# START IT THE WAY DEPLOYMENT STARTS IT: as a process, not through the Windows shell. SCCM and Intune create the process
# directly; the shell adds what they never show - a UAC prompt, and for a file that carries the "downloaded from the
# internet" mark, the "Open File - Security Warning / publisher could not be verified - Run / Cancel" box. On a real
# order that box came up for every attempt, the packager had to click it, and one click on Cancel failed an attempt
# with "the operation was canceled by the user". This session runs elevated, so the process is created directly.
function Start-AgentInstallerProcess {
    param([Parameter(Mandatory)][string]$File, [string]$Arguments = '', [string]$WorkingDirectory = '')
    if (Test-AgentElevated) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $File; $psi.Arguments = "$Arguments"; $psi.UseShellExecute = $false
        if ("$WorkingDirectory".Trim()) { $psi.WorkingDirectory = $WorkingDirectory }
        return @{ Process = [System.Diagnostics.Process]::Start($psi); How = 'started directly (this session is elevated - no shell, no UAC, no security prompt)' }
    }
    $sp = @{ FilePath = $File; PassThru = $true; ErrorAction = 'Stop'; Verb = 'RunAs' }
    if ("$WorkingDirectory".Trim()) { $sp.WorkingDirectory = $WorkingDirectory }
    if ("$Arguments".Trim()) { $sp.ArgumentList = $Arguments }
    return @{ Process = (Start-Process @sp); How = 'started elevated through the shell (this session is not elevated - expect a UAC prompt)' }
}

# THE DOWNLOAD MARK. Files unpacked from a zip that came from the internet carry Zone.Identifier (ZoneId=3), and Windows
# then treats every launch of them as untrusted. Removing the mark changes nothing inside the file - the build does the
# same to the package payload - and only LOCAL copies are touched: never a share, never Windows' own folders.
function Clear-AgentDownloadMark {
    param([string]$Path)
    $done = @()
    if (-not "$Path".Trim() -or "$Path" -match '^\\\\' -or -not (Test-Path -LiteralPath $Path)) { return $done }
    if ("$env:windir".Trim() -and "$Path".StartsWith("$env:windir", [StringComparison]::OrdinalIgnoreCase)) { return $done }
    $dir = Split-Path -Parent $Path
    foreach ($f in @(@(Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue) + @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue))) {
        if (-not $f) { continue }
        try { if (Get-Item -LiteralPath $f.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue) { Unblock-File -LiteralPath $f.FullName -ErrorAction Stop; $done += $f.Name } } catch {}
    }
    return @($done | Select-Object -Unique)
}

function Get-AgentProcessTable {
    $t = @{}
    try { foreach ($p in @(Get-CimInstance Win32_Process -ErrorAction Stop)) { $t[[int]$p.ProcessId] = $p } } catch {}
    return $t
}

# EVERY WINDOW ON SCREEN, not one per process. Get-Process knows only a process's "main window": a second dialog of the
# same installer, or a console that Windows 11 opens inside Windows Terminal (a window of WindowsTerminal.exe, not of
# the installer), never appeared - on a real order three installer windows sat in the taskbar while the agent reported
# that nothing was open. EnumWindows lists them all: visible, not cloaked, titled (or a dialog), with owner process
# and window class.
function Initialize-AgentWindowApi {
    if ('PA.Win' -as [type]) { return $true }
    try {
        Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
namespace PA {
public static class Win {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int size);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  public static List<string> List() {
    List<string> r = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      int c = 0; try { if (DwmGetWindowAttribute(h, 14, out c, 4) == 0 && c != 0) return true; } catch { }
      StringBuilder t = new StringBuilder(512); GetWindowText(h, t, 512);
      StringBuilder k = new StringBuilder(256); GetClassName(h, k, 256);
      string title = t.ToString(); string cls = k.ToString();
      if (title.Trim().Length == 0 && cls != "#32770") return true;
      uint pid; GetWindowThreadProcessId(h, out pid);
      r.Add(h.ToInt64() + "\t" + pid + "\t" + cls + "\t" + title.Replace("\t", " "));
      return true; }, IntPtr.Zero);
    return r; }
  public static bool Close(long h) { return PostMessage(new IntPtr(h), 0x0010, IntPtr.Zero, IntPtr.Zero); }
  public static bool Exists(long h) { return IsWindow(new IntPtr(h)); }
  // THE WORDS IN A WINDOW: its labels, text boxes and buttons - a help box lists the switches as a label
  delegate bool EnumChildProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumChildProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, StringBuilder l, uint f, uint t, out IntPtr r);
  public static List<string> Texts(long h) {
    List<string> r = new List<string>();
    EnumChildWindows(new IntPtr(h), delegate(IntPtr c, IntPtr l) {
      StringBuilder s = new StringBuilder(8192); IntPtr res;
      SendMessageTimeout(c, 0x000D, new IntPtr(8192), s, 0x0002, 500, out res);
      string t = s.ToString().Trim(); if (t.Length > 0 && !r.Contains(t)) r.Add(t);
      return true; }, IntPtr.Zero);
    return r; }
}}
'@ -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Get-AgentVisibleWindows {
    if (Initialize-AgentWindowApi) {
        $names = @{}; foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) { $names[[int]$p.Id] = "$($p.ProcessName)" }
        return @(@([PA.Win]::List()) | ForEach-Object {
                $f = "$_" -split "`t", 4; $wpid = [int]$f[1]
                if ($wpid -ne $PID) { [ordered]@{ id = $wpid; hwnd = [long]$f[0]; process = "$($names[$wpid])"; class = "$($f[2])"; title = "$($f[3])" } } })
    }
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and "$($_.MainWindowTitle)".Trim() -and $_.Id -ne $PID } |
             ForEach-Object { [ordered]@{ id = [int]$_.Id; hwnd = [long]$_.MainWindowHandle; process = "$($_.ProcessName)"; class = ''; title = "$($_.MainWindowTitle)" } })
}

# Close windows by handle - WM_CLOSE, the X button - and then end the processes of this install that are still holding
# one of them. A window of a process that is NOT part of the install (a console hosted by Windows Terminal) is only
# asked to close; that process is never killed.
function Close-AgentWindows {
    param($Windows, [hashtable]$Family = @{}, [int[]]$NeverKill = @(), [int]$GraceSec = 3)
    $w = @(@($Windows) | Where-Object { $_ })
    if (-not $w.Count) { return @() }
    foreach ($x in $w) { try { if ('PA.Win' -as [type]) { [void][PA.Win]::Close([long]$x.hwnd) } else { $p = Get-Process -Id ([int]$x.id) -ErrorAction SilentlyContinue; if ($p) { [void]$p.CloseMainWindow() } } } catch {} }
    Start-Sleep -Seconds $GraceSec
    $ended = @()
    foreach ($x in $w) {
        $still = if ('PA.Win' -as [type]) { [PA.Win]::Exists([long]$x.hwnd) } else { [bool](Get-Process -Id ([int]$x.id) -ErrorAction SilentlyContinue) }
        if (-not $still) { continue }
        if ($Family.ContainsKey([int]$x.id) -and @($NeverKill) -notcontains [int]$x.id) { try { Stop-Process -Id ([int]$x.id) -Force -ErrorAction Stop; $ended += "$($x.process) ($($x.id))" } catch {} }
    }
    return $ended
}

# Close windows the polite way first (WM_CLOSE - the same as pressing X or OK on a message box), and only then end what
# is still there. Force-killing a process that shows a modal dialog leaves a ghost window nobody can clear.
function Close-AgentProcesses {
    param([int[]]$Ids, [int]$GraceSec = 4, [int[]]$NeverKill = @())
    $names = @()
    foreach ($id in @($Ids)) { try { $p = Get-Process -Id $id -ErrorAction SilentlyContinue; if ($p) { $names += "$($p.ProcessName) ($id)"; if ($p.MainWindowHandle -ne 0) { [void]$p.CloseMainWindow() } } } catch {} }
    if (@($Ids).Count) { Start-Sleep -Seconds $GraceSec }
    foreach ($id in @($Ids)) { if (@($NeverKill) -contains $id) { continue }; try { if (Get-Process -Id $id -ErrorAction SilentlyContinue) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue } } catch {} }
    return $names
}

# Where the template's toolkit writes its logs (Config\config.psd1: Toolkit.LogPath, MSI.LogPath), expanded.
function Get-AgentPackageLogDirs {
    $dirs = @()
    try {
        $cfg = Join-Path (Get-AgentTemplatePath) 'Config\config.psd1'
        if (Test-Path -LiteralPath $cfg) {
            foreach ($m in @([regex]::Matches([IO.File]::ReadAllText($cfg), "(?m)^\s*LogPath\s*=\s*'([^']+)'"))) {
                $v = $m.Groups[1].Value -replace '(?i)\$envAllUsersProfile', $env:ALLUSERSPROFILE -replace '(?i)\$envProgramData', $env:ProgramData -replace '(?i)\$envWinDir', $env:windir -replace '(?i)\$envSystemRoot', $env:SystemRoot -replace '(?i)\$envTemp', $env:TEMP
                if ($v -notmatch '\$') { $dirs += $v }
            }
        }
    } catch {}
    return @(@($dirs) + @((Join-Path $env:windir 'Logs\Software'), (Join-Path $env:ProgramData 'VWG\Logs')) | Select-Object -Unique)
}

# THE MACHINE AS IT IS NOW - ONLY WHAT CHANGED SINCE $Since. Sending the engineer everything (whole logs, every process)
# costs a fortune and buries the one line that matters; sending nothing leaves it guessing. So, by time: processes started
# since, windows on screen now, every log file written since (its error lines and its last lines, not the whole file),
# and the Windows Installer / application-error events since. The screenshot travels separately as a picture.
function Get-AgentRecentEvidence {
    param([Parameter(Mandatory)][datetime]$Since, [string[]]$LogDirs = @(), [int]$MaxFiles = 8, [int]$TailLines = 40, [int]$MaxErrorLines = 25)
    $ev = [ordered]@{ since = $Since.ToString('HH:mm:ss'); processesStartedSince = @(); windowsNow = @(); recentLogs = @(); events = @() }
    try {
        $ev.processesStartedSince = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CreationDate -and $_.CreationDate -ge $Since } |
            Sort-Object CreationDate | Select-Object -First 30 | ForEach-Object { $cl = "$($_.CommandLine)".Trim(); "$($_.CreationDate.ToString('HH:mm:ss')) $($_.Name) ($($_.ProcessId), parent $($_.ParentProcessId))$(if ($cl) { ': ' + $cl.Substring(0, [Math]::Min(180, $cl.Length)) })" })
    } catch {}
    try { $ev.windowsNow = @(Get-AgentVisibleWindows | Where-Object { "$($_.process)" -notmatch '^(explorer|msedge|chrome|claude|Teams|OUTLOOK|SearchHost|ShellExperienceHost|TextInputHost)$' } | Select-Object -First 25 | ForEach-Object { "$($_.process) ($($_.id)): $($_.title) [$($_.class)]" }) } catch {}
    $dirs = @(@($LogDirs) + @(Get-AgentPackageLogDirs) + @($env:TEMP, (Join-Path $env:windir 'Temp')) | Where-Object { "$_".Trim() -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
    $files = @(foreach ($d in $dirs) { Get-ChildItem -LiteralPath $d -File -Recurse -Depth 2 -Include '*.log', '*.txt' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $Since -and $_.Length -gt 0 } })
    foreach ($f in @($files | Sort-Object LastWriteTime -Descending | Select-Object -First $MaxFiles)) {
        $lines = @()
        try {
            # MSI logs are UTF-16; ReadAllLines detects the BOM. Only the end of a big file is read.
            if ($f.Length -gt 20MB) { $lines = @(Get-Content -LiteralPath $f.FullName -Tail 2000 -ErrorAction Stop) } else { $lines = @([IO.File]::ReadAllLines($f.FullName)) }
        } catch { continue }
        $last = @($lines | Select-Object -Last 2000)
        $errs = @($last | Where-Object { $_ -match '(?i)\b(error|failed|failure|exception|return value 3|exit code \d+|cannot|denied|type="3"|\[Error\])' } | Select-Object -Last $MaxErrorLines)
        $ev.recentLogs += [ordered]@{ file = $f.FullName; written = $f.LastWriteTime.ToString('HH:mm:ss'); sizeKB = [math]::Round($f.Length / 1KB, 1)
                                      errorLines = @($errs | ForEach-Object { $s = "$_".Trim(); $s.Substring(0, [Math]::Min(300, $s.Length)) })
                                      lastLines = @($last | Select-Object -Last $TailLines | ForEach-Object { $s = "$_".Trim(); $s.Substring(0, [Math]::Min(300, $s.Length)) }) }
    }
    try {
        $ev.events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $Since } -MaxEvents 200 -ErrorAction Stop |
            Where-Object { $_.ProviderName -match '(?i)MsiInstaller|Application Error|Application Hang|Windows Error Reporting|\.NET Runtime|SideBySide' } |
            Select-Object -First 15 | ForEach-Object { $m = "$($_.Message)" -replace '\s+', ' '; "$($_.TimeCreated.ToString('HH:mm:ss')) $($_.ProviderName) $($_.Id): $($m.Substring(0, [Math]::Min(300, $m.Length)))" })
    } catch {}
    return $ev
}

# ASK THE INSTALLER WHAT IT ACCEPTS - AND LOOK AT THE ANSWER. Most installers answer /? with a WINDOW listing their
# switches, not console text. The old probe read only the console, killed the process after its timeout, and never
# saw the window (and left an Inno wizard behind for each switch it tried). Now: for each help switch, wait for console
# output OR a window; photograph the window and read the words in it; close everything the probe started; stop at the
# first real answer.
function Get-AgentInstallerHelpLook {
    param([Parameter(Mandatory)][string]$ExePath, [int]$TimeoutSec = 12, [string[]]$Switches = @('/?', '/help', '-h', '--help'), [scriptblock]$Progress)
    $out = New-Object System.Collections.Generic.List[object]
    $stem = [IO.Path]::GetFileNameWithoutExtension($ExePath)
    [void](Initialize-AgentWindowApi)
    [void](Clear-AgentDownloadMark -Path $ExePath)
    foreach ($sw in $Switches) {
        if ($Progress) { try { & $Progress "asking $(Split-Path -Leaf $ExePath) what it accepts: $sw" } catch {} }
        $rec = [ordered]@{ switch = $sw; consoleText = ''; windowTitle = ''; windowText = @(); screenshot = ''; note = '' }
        $before = @{}; foreach ($w in @(Get-AgentVisibleWindows)) { $before["$($w.hwnd)"] = $true }
        $t0 = (Get-Date).AddSeconds(-2)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ExePath; $psi.Arguments = $sw; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        try { $psi.WorkingDirectory = Split-Path -Parent $ExePath } catch {}
        $p = $null
        try { $p = [System.Diagnostics.Process]::Start($psi) } catch { $rec.note = "could not start: $($_.Exception.Message.Split([char]10)[0])"; $out.Add($rec); break }
        $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
        $family = @{}; $family[[int]$p.Id] = $true
        $win = $null
        $sw2 = [Diagnostics.Stopwatch]::StartNew()
        while ($sw2.Elapsed.TotalSeconds -lt $TimeoutSec) {
            Start-Sleep -Milliseconds 500
            foreach ($x in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CreationDate -ge $t0 -and ($family.ContainsKey([int]$_.ParentProcessId) -or "$($_.Name)" -like "$stem*") })) { $family[[int]$x.ProcessId] = $true }
            $new = @(Get-AgentVisibleWindows | Where-Object { $family.ContainsKey([int]$_.id) -and -not $before["$($_.hwnd)"] })
            if ($new.Count) { Start-Sleep -Milliseconds 1500; $win = @(Get-AgentVisibleWindows | Where-Object { $family.ContainsKey([int]$_.id) -and -not $before["$($_.hwnd)"] }); break }
            if ($p.HasExited) { break }
        }
        if ($win -and @($win).Count) {
            $shot = try { Get-AgentScreenshot -Why "what $(Split-Path -Leaf $ExePath) shows for $sw" } catch { $null }
            if ($shot -and $shot.ok) { $rec.screenshot = "$($shot.path)" }
            $rec.windowTitle = (@($win) | ForEach-Object { "$($_.title)" }) -join ' | '
            $txt = @(); foreach ($x in @($win)) { try { $txt += @([PA.Win]::Texts([long]$x.hwnd)) } catch {} }
            $rec.windowText = @($txt | Where-Object { "$_".Trim() } | Select-Object -Unique -First 40)
        }
        # END EVERYTHING THE PROBE STARTED - the loader, the .tmp it handed over to, their windows
        try { if (@($win).Count) { [void](Close-AgentWindows -Windows @($win) -Family $family -GraceSec 2) } } catch {}
        foreach ($id in @($family.Keys)) { try { if (Get-Process -Id $id -ErrorAction SilentlyContinue) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue } } catch {} }
        try { if ($p.HasExited -or $p.WaitForExit(1000)) { $rec.consoleText = ("$($o.Result)`r`n$($e.Result)").Trim() } } catch {}
        if ($rec.consoleText.Length -gt 4000) { $rec.consoleText = $rec.consoleText.Substring(0, 4000) + '...' }
        $all = "$($rec.consoleText) $(@($rec.windowText) -join ' ')"
        $rec.looksLikeHelp = [bool]($all -match '(?i)(^|\s)[/-]{1,2}[a-z]{2,}' -and $all.Length -gt 40)
        if (-not $rec.looksLikeHelp -and -not $rec.consoleText -and -not @($rec.windowText).Count -and $rec.windowTitle) { $rec.note = 'a window opened but carries no readable text (it may be the setup wizard, not help) - look at the picture' }
        $out.Add($rec)
        if ($rec.looksLikeHelp) { break }   # a real answer - no need to try the other switches
    }
    return $out.ToArray()
}

# ---- the install runner: start it, watch it PATIENTLY, look at the screen, give the machine back --------------------
# A window is not a verdict. Inno's /SILENT shows a progress window, an application may open itself at the end to
# finish its settings, a cmd window may check drivers - the instructions often say so. The old rule ("a window for
# 12 seconds = not silent, kill it") killed a working install on a real order and left the application's own windows
# on the screen. Now:
#   - the whole family is watched: what we started, what it started at any depth, anything named after the installer,
#     and the Windows Installer processes doing an MSI's work. While any of them uses CPU or disk, it is WORKING.
#   - only a window with NOTHING moving for $StallSec is a question - and then the screen is photographed and the AI
#     ($Judge) looks at it and says what it is: progress (wait), a prompt waiting for a click (stop - not silent),
#     an application or console window the install opened (close it and carry on), something for the packager (ask).
#     Without a Judge the rule decides: two stall periods of nothing with a window up = waiting for a click.
#   - when the installer process ends, what it started gets time to finish ($SettleSec of quiet, up to $SettleMaxSec),
#     and whatever it leaves on screen is photographed and judged before it is closed.
# Returns everything seen: exit code, windows during and after, each look (with its screenshot), what was started.
function Invoke-AgentInstallRun {
    param([Parameter(Mandatory)][string]$Installer, [string]$Arguments = '', [string]$RunAs = 'Admin', [int]$TimeoutSec = 1800,   # NOT $Args - that name is the automatic unbound-args variable and binds EMPTY
          [scriptblock]$Progress, [scriptblock]$Judge, [int]$StallSec = 45, [int]$SettleSec = 20, [int]$SettleMaxSec = 300,
          [int]$MaxLooks = 5, [ValidateSet('install', 'uninstall')][string]$Action = 'install', [int]$TickMs = 2000,
          [string]$CaptureMsiTo = '')
    $say = { param($t) if ($Progress) { try { & $Progress $t } catch {} } }
    # CATCH THE MSI WHILE IT EXISTS. Inno Setup, InstallShield and many vendor EXEs unpack their real MSI into %TEMP%
    # during the install and delete it at the end - 7-Zip cannot see inside them, and a diff taken afterwards finds
    # nothing. That is how the team gets "the MSI extracted from the EXE": run it and take the MSI while it is there.
    # So the watch folders are scanned while the install runs and every new MSI (with the .cab/.mst/.msp beside it) is
    # copied out as soon as it appears, and copied again if it was still being written.
    $cap = @{ dirs = @(); base = @{}; lastScan = -100.0; got = [ordered]@{}; evLast = -100.0; events = [ordered]@{}; evSince = (Get-Date).AddSeconds(-2) }
    # copy one MSI (and the .cab/.mst/.msp beside it) the moment its path is known
    $grabPath = {
        param([string]$mp, [string]$how)
        if (-not "$CaptureMsiTo".Trim() -or -not "$mp".Trim() -or $cap.got.Contains($mp)) { return }
        if ($mp.StartsWith([IO.Path]::GetFullPath($CaptureMsiTo), [StringComparison]::OrdinalIgnoreCase) -or (Test-RuntimeCacheMsi $mp) -or -not (Test-Path -LiteralPath $mp)) { return }
        $fi = Get-Item -LiteralPath $mp -ErrorAction SilentlyContinue
        if (-not $fi) { return }
        $dest = Join-Path $CaptureMsiTo ("{0:D2}_{1}" -f ($cap.got.Count + 1), ($fi.Directory.Name -replace '[^\w.-]', '_'))
        try {
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            Copy-Item -LiteralPath $mp -Destination $dest -Force -ErrorAction Stop
            foreach ($sib in @(Get-ChildItem -LiteralPath $fi.DirectoryName -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '(?i)^\.(cab|mst|msp)$' })) { Copy-Item -LiteralPath $sib.FullName -Destination $dest -Force -ErrorAction SilentlyContinue }
            $cap.got[$mp] = @{ dir = $dest; path = (Join-Path $dest $fi.Name); len = $fi.Length; time = $fi.LastWriteTimeUtc; from = "$mp ($how)" }
            & $say "caught $($fi.Name) ($how)"
        } catch {}
    }
    # THE WINDOWS INSTALLER EVENTS since the start: every MSI transaction with its path, every product installed or
    # failed. Kept as evidence whether or not the file still exists.
    $readMsiEvents = {
        $evs = @(); try { $evs = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'MsiInstaller'; StartTime = $cap.evSince } -ErrorAction Stop) } catch {}
        foreach ($e in $evs) {
            if ($cap.events.Contains("$($e.RecordId)")) { continue }
            $msg = ("$($e.Message)" -replace '\s+', ' ').Trim()
            $cap.events["$($e.RecordId)"] = "$($e.TimeCreated.ToString('HH:mm:ss')) event $($e.Id): $($msg.Substring(0, [Math]::Min(260, $msg.Length)))"
            foreach ($m in @([regex]::Matches($msg, '(?i)([A-Z]:\\[^:*?"<>|\r\n]+?\.msi)\b'))) { & $grabPath $m.Groups[1].Value 'named in the Windows Installer events' }
        }
    }
    if ("$CaptureMsiTo".Trim() -and (Get-Command Get-MsiWatchDirs -ErrorAction SilentlyContinue)) {
        $cap.dirs = @(Get-MsiWatchDirs | Where-Object { -not (Test-RuntimeCacheMsi $_) })
        try { $cap.base = Get-MsiSnapshot -Dirs $cap.dirs } catch {}
    }
    $grab = {
        foreach ($d in @($cap.dirs)) {
            foreach ($f in @(Get-ChildItem -LiteralPath $d -Filter *.msi -File -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue)) {
                if ($f.Length -lt 100KB) { continue }
                if ($f.FullName.StartsWith([IO.Path]::GetFullPath($CaptureMsiTo), [StringComparison]::OrdinalIgnoreCase)) { continue }   # our own copies
                if ($cap.base.ContainsKey($f.FullName) -and $f.LastWriteTimeUtc -le $cap.base[$f.FullName]) { continue }
                $had = $cap.got[$f.FullName]
                if ($had -and $had.len -eq $f.Length -and $had.time -eq $f.LastWriteTimeUtc) { continue }
                $dest = if ($had) { $had.dir } else { Join-Path $CaptureMsiTo ("{0:D2}_{1}" -f ($cap.got.Count + 1), ($f.Directory.Name -replace '[^\w.-]', '_')) }
                try {
                    New-Item -ItemType Directory -Force -Path $dest | Out-Null
                    Copy-Item -LiteralPath $f.FullName -Destination $dest -Force -ErrorAction Stop
                    foreach ($s in @(Get-ChildItem -LiteralPath $f.DirectoryName -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '(?i)^\.(cab|mst|msp)$' })) { Copy-Item -LiteralPath $s.FullName -Destination $dest -Force -ErrorAction SilentlyContinue }
                    $cap.got[$f.FullName] = @{ dir = $dest; path = (Join-Path $dest $f.Name); len = $f.Length; time = $f.LastWriteTimeUtc; from = $f.FullName }
                    if (-not $had) { & $say "caught $($f.Name) while the installer had it unpacked ($([math]::Round($f.Length / 1MB, 1)) MB)" }
                } catch {}
            }
        }
    }
    $spec = if (Get-Command Get-InstallerRunSpec -ErrorAction SilentlyContinue) { Get-InstallerRunSpec -Path $Installer } else { @{ File = $Installer; Args = '' } }
    $stem = [IO.Path]::GetFileNameWithoutExtension($Installer)
    # NeededIntervention: every window the hands had to close for the install to go on or to finish - an error box, a
    # prompt, an application or console left open. Silent means nobody touches anything; each one makes the line NOT
    # silent, whatever the instructions say about ignoring it. (A progress window that goes away on its own is fine.)
    $r = [ordered]@{ ExitCode = $null; DurationSec = 0; WindowsSeen = @(); TimedOut = $false; Error = ''; Command = ''; Interactive = $false; Interrupted = $false; NeededIntervention = @()
                     Looks = @(); WindowsAfterInstall = @(); LeftRunning = @(); StartedByInstall = @(); LaunchedHow = ''; Unblocked = @()
                     TemplateDefaultsAdded = @(); MsiLog = ''; ExitedAfterSec = $null; ScreenshotWhileRunning = ''; WindowsOnScreen = @(); RunningProcesses = @() }
    $argsIn = "$Arguments"
    if ([IO.Path]::GetExtension($Installer) -ieq '.msi') {
        $log = Join-Path $env:TEMP ("PackagingAgent_{0}_{1}.log" -f ($stem -replace '[^\w.-]', '_'), (Get-Date -Format 'HHmmss'))
        $md = Add-AgentMsiDefaults -Arguments $argsIn -Action $Action -LogPath $log
        $argsIn = $md.Arguments; $r.TemplateDefaultsAdded = @($md.Added); $r.MsiLog = $log
    }
    $allArgs = ("$($spec.Args) $argsIn").Trim()
    $wd = Split-Path $Installer -Parent
    $r.Command = "`"$($spec.File)`" $allArgs".Trim()
    $r.Unblocked = @(Clear-AgentDownloadMark -Path $Installer)
    if (@($r.Unblocked).Count) { & $say "removed the download mark from $(@($r.Unblocked).Count) local file(s) so Windows does not ask 'Run / Cancel'" }
    $st = @{ lastActive = 0.0; lastLook = -1000.0; looks = 0; prevLoad = -1.0; prevCount = -1; slowShot = $false }
    $looks = New-Object System.Collections.Generic.List[object]
    $started = [ordered]@{}
    $ours = @{}
    # One look at the screen: photograph it, and let the AI say what it is. $NoJudge only records the picture.
    $look = {
        param([string]$Phase, $Wins, [double]$Now, [double]$Idle, $Procs, [switch]$NoJudge)
        $titles = @($Wins | ForEach-Object { "$($_.process): $($_.title)$(if ("$($_.class)".Trim()) { " [$($_.class)]" })" })
        $shot = try { Get-AgentScreenshot -Why "$Phase - $($titles -join ' | ')" } catch { $null }
        $rec = [ordered]@{ atSec = [int]$Now; phase = $Phase; idleSec = [int]$Idle; windows = $titles; screenshot = $(if ($shot -and $shot.ok) { "$($shot.path)" } else { '' }); processes = @($Procs) }
        $ans = $null
        if ($Judge -and -not $NoJudge -and $st.looks -lt $MaxLooks) {
            $st.looks++
            & $say "looking at the screen ($Phase): $($titles -join ' | ')"
            # the machine since this attempt started: new processes, every window, recent log lines, installer events
            $recent = try { Get-AgentRecentEvidence -Since $t0 -MaxFiles 4 -TailLines 15 -MaxErrorLines 10 } catch { $null }
            $ans = try { & $Judge ([ordered]@{ phase = $Phase; action = $Action; command = $r.Command; elapsedSec = [int]$Now; idleSec = [int]$Idle; windows = $titles; processes = @($Procs); screenshot = $rec.screenshot; machineSinceThisAttemptStarted = $recent }) } catch { $null }
        }
        if ($ans -and "$($ans.action)".Trim()) {
            # the AI's words (close_it, ask_packager, ...) become the four things the hands know how to do
            $act = switch -Regex ("$($ans.action)") { '(?i)^close' { 'close' } '(?i)^stop' { 'stop' } '(?i)^ask' { 'ask' } default { 'wait' } }
            $rec.whatItIs = "$($ans.whatItIs)"; $rec.decided = $act; $rec.windowToClose = "$($ans.windowToClose)"; $rec.why = "$($ans.why)"; $rec.by = 'ai'
        } elseif ($NoJudge) {
            $rec.decided = 'closed by the hands'; $rec.by = 'record'; $rec.why = 'what the install left on screen, photographed before it was closed'
        } else {
            # nobody to ask: the installer's OWN window sitting idle is a question it is waiting on; any other window
            # it left behind (the application, a console) is a leftover to close
            $installerish = @($Wins | Where-Object { "$($_.process)" -like "$stem*" -or "$($_.process)" -match '(?i)setup|install|msiexec|\.tmp$|unins' }).Count
            $rec.decided = if ($Phase -eq 'running') { if ($Idle -ge 2 * $StallSec) { 'stop' } else { 'wait' } } elseif ($installerish) { 'stop' } else { 'close' }
            $rec.by = 'rule'; $rec.why = 'no AI look available - decided by the rule (idle window of the installer = waiting; anything else it opened = close)'
        }
        $looks.Add($rec)
        return $rec
    }
    $closeNamed = {
        param($Rec, $Wins, [int]$ProcId, [bool]$Exited)
        $target = "$($Rec.windowToClose)".Trim()
        $tw = @($Wins | Where-Object { -not $target -or "$($_.title)" -like "*$target*" -or "$($_.process)" -like "*$target*" })
        if (-not $tw.Count) { & $say "the AI asked to close '$target', but no window on screen matches it"; return }
        & $say "closing $(@($tw | ForEach-Object { $_.title }) -join ', ') - $($Rec.why)"
        # the installer itself is asked to close, never killed while it is running - that is the 'stop' decision's job
        $keep = @(); if (-not $Exited) { $keep = @($ProcId) + @($Wins | Where-Object { "$($_.process)" -like "$stem*" } | ForEach-Object { [int]$_.id }) }
        [void](Close-AgentWindows -Windows $tw -Family $ours -NeverKill $keep)
    }
    # STALE COPIES OF THIS INSTALLER FROM AN EARLIER ATTEMPT OR PROBE: an Inno setup still sitting on its wizard holds the
    # installer's mutex, and a new attempt then waits behind it or refuses. Close them first - never for a Windows binary
    # (msiexec, powershell), whose name would match unrelated processes.
    if ("$env:windir".Trim() -and -not "$Installer".StartsWith("$env:windir", [StringComparison]::OrdinalIgnoreCase)) {
        $stale = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "$stem*" -and $_.Id -ne $PID })
        if ($stale.Count) {
            $r.StaleClosed = @(Close-AgentProcesses -Ids @($stale | ForEach-Object { [int]$_.Id }) -GraceSec 3)
            & $say "closed $($stale.Count) copy(ies) of $stem still running from before: $(@($r.StaleClosed) -join ', ')"
        }
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $t0 = Get-Date
    try {
        if ($RunAs -eq 'SYSTEM') {
            $ps = if (Get-Command Find-PsExec -ErrorAction SilentlyContinue) { Find-PsExec } else { $null }
            # SYSTEM needs PsExec. Without it, run elevated instead of failing the whole evaluation: almost every
            # installer behaves the same either way, and an Admin result beats no result.
            if (-not $ps) {
                Write-Log 'SYSTEM run asked for but PsExec is not here - running elevated (Admin) instead.' Warning
                & $say 'PsExec not available - running as Admin instead of SYSTEM'
                $r.RanAs = 'Admin'; $RunAs = 'Admin'
            }
        }
        $before = @{}; foreach ($w in @(Get-AgentVisibleWindows)) { $before["$($w.hwnd)"] = $true }
        $launch = if ($RunAs -eq 'SYSTEM') {
            $inner = "`"$($spec.File)`"" + $(if ($allArgs) { " $allArgs" } else { '' })
            Start-AgentInstallerProcess -File $ps -Arguments "-accepteula -s -w `"$wd`" $inner" -WorkingDirectory $wd
        } else { Start-AgentInstallerProcess -File $spec.File -Arguments $allArgs -WorkingDirectory $wd }
        $proc = $launch.Process; $r.LaunchedHow = "$($launch.How)"
        $ours[[int]$proc.Id] = $true
        $seen = [ordered]@{}; $after = [ordered]@{}
        $exitedAt = $null
        while ($true) {
            Start-Sleep -Milliseconds $TickMs
            $now = $sw.Elapsed.TotalSeconds
            if (@($cap.dirs).Count -and ($now - $cap.lastScan) -ge 1.5) { $cap.lastScan = $now; & $grab }
            $tab = Get-AgentProcessTable
            # AN MSI IS CAUGHT WHEREVER IT LIVES, the moment anything names it: on a new msiexec command line, or in the
            # Windows Installer events ("Beginning a Windows Installer transaction: <path>"). A setup can unpack into any
            # folder - not only %TEMP% - and delete it again within seconds; those two places say where it was.
            foreach ($p in @($tab.Values | Where-Object { "$($_.Name)" -ieq 'msiexec.exe' -and "$($_.CommandLine)" -match '(?i)\.msi' -and $_.CreationDate -ge $t0.AddSeconds(-2) })) {
                foreach ($m in @([regex]::Matches("$($p.CommandLine)", '(?i)"([^"]+\.msi)"|(\S+\.msi)'))) { & $grabPath $(if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }) "named on msiexec's command line" }
            }
            if (($now - $cap.evLast) -ge 1.5) { $cap.evLast = $now; & $readMsiEvents }
            # THE FAMILY: what we started, what it started at any depth, anything new named after the installer
            # (an elevated Inno relaunch as <name>.tmp is not our child)
            $grew = $true
            while ($grew) {
                $grew = $false
                foreach ($p in @($tab.Values)) {
                    $id = [int]$p.ProcessId
                    if ($ours.ContainsKey($id) -or $id -eq $PID) { continue }
                    $young = ($p.CreationDate -and $p.CreationDate -ge $t0.AddSeconds(-2))
                    if ($young -and ($ours.ContainsKey([int]$p.ParentProcessId) -or "$($p.Name)" -like "$stem*")) { $ours[$id] = $true; $grew = $true }
                }
            }
            # IS IT WORKING? CPU and disk of the family, plus Windows Installer (an MSI's work happens in its service)
            $load = 0.0; $alive = @()
            foreach ($p in @($tab.Values)) {
                $id = [int]$p.ProcessId
                $isOurs = $ours.ContainsKey($id)
                if ($isOurs -or "$($p.Name)" -ieq 'msiexec.exe') {
                    $load += ([double]$p.KernelModeTime + [double]$p.UserModeTime) / 1e7 + ([double]$p.ReadTransferCount + [double]$p.WriteTransferCount) / 1MB
                }
                if ($isOurs) {
                    $alive += $p
                    if (-not $started.Contains("$id") -and $started.Count -lt 40) { $cl = "$($p.CommandLine)".Trim(); $started["$id"] = "$($p.Name)$(if ($cl) { ': ' + $cl.Substring(0, [Math]::Min(160, $cl.Length)) })" }
                }
            }
            $active = ($st.prevLoad -lt 0) -or (($load - $st.prevLoad) -gt 0.05) -or (@($alive).Count -ne $st.prevCount)
            $st.prevLoad = $load; $st.prevCount = @($alive).Count
            if ($active) { $st.lastActive = $now }
            $idle = $now - $st.lastActive
            # WHAT IS ON SCREEN that belongs to this install: the family's windows, and any window of a process
            # started since we pressed go
            $wins = @(Get-AgentVisibleWindows | Where-Object {
                        $ours.ContainsKey([int]$_.id) -or -not $before["$($_.hwnd)"] })
            # a NEW window of a process that is itself new belongs to the install; a new window of an old process (a
            # console tab in Windows Terminal) is watched and closed, but that process is never counted as ours
            foreach ($w in $wins) { if ($tab.ContainsKey([int]$w.id) -and $tab[[int]$w.id].CreationDate -and $tab[[int]$w.id].CreationDate -ge $t0.AddSeconds(-2)) { $ours[[int]$w.id] = $true } }
            $procNames = @($alive | Select-Object -First 12 | ForEach-Object { $cl = "$($_.CommandLine)".Trim(); "$($_.Name)$(if ($cl) { ': ' + $cl.Substring(0, [Math]::Min(140, $cl.Length)) })" })
            # THE PACKAGER CAN SEE THE SCREEN AND WE CANNOT - if they say something now, stop and hear it
            try {
                if ($script:AgentHumanInbox -and $script:AgentHumanInbox.Count) {
                    $said = @($script:AgentHumanInbox.ToArray()); [void]$script:AgentHumanInbox.Clear()
                    $r.PackagerSaid = @($said)
                    $r.Error = "the packager stopped this while it was running: $(@($said) -join ' / ')"
                    & $say "the packager said: $(@($said) -join ' / ') - stopping this attempt"
                    $r.Interrupted = $true
                    break
                }
            } catch {}
            $exited = $proc.HasExited
            if (-not $exited) {
                foreach ($w in $wins) { $seen["$($w.title)"] = $true }
                if ($now -gt $TimeoutSec) { $r.TimedOut = $true; & $say "it has run $([int]$now)s - past the limit of $($TimeoutSec)s"; break }
                if (@($wins).Count -and $idle -ge $StallSec -and ($now - $st.lastLook) -ge $StallSec) {
                    $st.lastLook = $now
                    $rec = & $look 'running' $wins $now $idle $procNames
                    if (-not $r.ScreenshotWhileRunning -and $rec.screenshot) { $r.ScreenshotWhileRunning = $rec.screenshot; $r.WindowsOnScreen = @($rec.windows) }
                    if ("$($rec.decided)" -eq 'stop') {
                        $r.Interactive = $true
                        $r.Error = "it put a window up ($(@($wins)[0].title)) and sat waiting with nothing moving for $([int]$idle)s$(if ("$($rec.whatItIs)".Trim()) { " - $($rec.whatItIs)" }) - this command is not silent"
                        & $say "not silent - '$(@($wins)[0].title)' is waiting for a click"
                        break
                    } elseif ("$($rec.decided)" -eq 'close') {
                        $r.NeededIntervention += "$(@($wins | ForEach-Object { $_.title }) -join ' | ')$(if ("$($rec.whatItIs)".Trim()) { " ($($rec.whatItIs))" }) - closed by the hands while the install ran"
                        & $closeNamed $rec $wins ([int]$proc.Id) $false; $st.lastActive = $sw.Elapsed.TotalSeconds }
                    elseif ("$($rec.decided)" -eq 'ask') { & $say "the AI asks you to look at the screen: $($rec.why)" }
                } elseif (-not @($wins).Count -and -not $st.slowShot -and $now -gt 90 -and $idle -ge 60) {
                    # nothing on screen of its own and nothing moving for a minute: photograph the screen and write down
                    # what is running - a dialog behind another window or an elevation prompt reaches no process handle
                    $st.slowShot = $true
                    $rec = & $look 'running-quiet' @() $now $idle $procNames -NoJudge
                    if (-not $r.ScreenshotWhileRunning -and $rec.screenshot) { $r.ScreenshotWhileRunning = $rec.screenshot }
                }
                & $say ("installer running {0:N0}s{1}{2}" -f $now, $(if (@($wins).Count) { " - window: $(@($wins)[0].title)" } else { ' - no window' }), $(if ($idle -ge 10) { " - quiet for $([int]$idle)s" } else { ' - working' }))
            } else {
                if ($null -eq $exitedAt) {
                    $exitedAt = $now; $r.ExitedAfterSec = [int]$now
                    try { $r.ExitCode = $proc.ExitCode } catch {}
                    & $say "the installer process ended (exit $($r.ExitCode)) after $([int]$now)s - waiting for anything it started to finish"
                }
                foreach ($w in $wins) { $after["$($w.process): $($w.title)"] = $true }
                if ($idle -ge $SettleSec) {
                    if (@($wins).Count -and ($now - $st.lastLook) -ge $SettleSec) {
                        $st.lastLook = $now
                        $rec = & $look 'after-exit' $wins $now $idle $procNames
                        if ("$($rec.decided)" -eq 'stop') {
                            $r.Interactive = $true
                            $r.Error = "the installer handed over to '$(@($wins)[0].title)', which sat waiting$(if ("$($rec.whatItIs)".Trim()) { " - $($rec.whatItIs)" }) - this command is not silent"
                            break
                        }
                        if ("$($rec.decided)" -eq 'close') {
                            $r.NeededIntervention += "$(@($wins | ForEach-Object { $_.title }) -join ' | ')$(if ("$($rec.whatItIs)".Trim()) { " ($($rec.whatItIs))" }) - left open after the installer ended, closed by the hands"
                            & $closeNamed $rec $wins ([int]$proc.Id) $true; $st.lastActive = $sw.Elapsed.TotalSeconds; continue }
                    } elseif (-not @($wins).Count) { break }   # quiet, and nothing of it on screen: finished
                }
                if (($now - $exitedAt) -ge $SettleMaxSec) { & $say "stopped waiting for what the installer started after $SettleMaxSec s"; break }
            }
        }
        if ($null -eq $r.ExitCode) { try { if ($proc.HasExited) { $r.ExitCode = $proc.ExitCode } } catch {} }
        if (@($cap.dirs).Count) { & $grab }
        & $readMsiEvents
        $r.WindowsSeen = @($seen.Keys); $r.WindowsAfterInstall = @($after.Keys)
        # GIVE THE MACHINE BACK. Everything this install started that is still running is closed - photographed first
        # when it has a window, so the AI sees what was on screen (the application it opened, a console, an error).
        # (a child started just after the last look - the application a setup launches as it ends - is still family:
        # find every descendant once more, after a moment, or it is left running on the packager's screen)
        Start-Sleep -Milliseconds 1500
        $tab = Get-AgentProcessTable
        $grew = $true
        while ($grew) {
            $grew = $false
            foreach ($p in @($tab.Values)) { $id = [int]$p.ProcessId; if ($ours.ContainsKey($id) -or $id -eq $PID) { continue }; if ($p.CreationDate -and $p.CreationDate -ge $t0.AddSeconds(-2) -and ($ours.ContainsKey([int]$p.ParentProcessId) -or "$($p.Name)" -like "$stem*")) { $ours[$id] = $true; $grew = $true } }
        }
        $left = @($tab.Values | Where-Object { $ours.ContainsKey([int]$_.ProcessId) -and [int]$_.ProcessId -ne $PID -and -not ("$($_.Name)" -ieq 'msiexec.exe' -and "$($_.CommandLine)" -match '(?i)\s/V\b') })
        # every window opened since go that is still there: the family's, and consoles hosted elsewhere (Windows Terminal)
        $leftWins = @(Get-AgentVisibleWindows | Where-Object { $ours.ContainsKey([int]$_.id) -or (-not $before["$($_.hwnd)"] -and "$($_.class)" -match '^(ConsoleWindowClass|CASCADIA_HOSTING_WINDOW_CLASS)$') })
        if ($leftWins.Count) {
            [void](& $look 'left-on-screen' $leftWins $sw.Elapsed.TotalSeconds 0 @() -NoJudge)
            if (-not $r.Interrupted) { $r.NeededIntervention += "$(@($leftWins | ForEach-Object { $_.title }) -join ' | ') - still open at the end, closed by the hands" }
            [void](Close-AgentWindows -Windows $leftWins -Family $ours)
        }
        if (@($left).Count) {
            $r.LeftRunning = @($left | ForEach-Object { "$($_.Name) ($($_.ProcessId))" })
            & $say "closing what the install left running: $(@($r.LeftRunning) -join ', ')"
            [void](Close-AgentProcesses -Ids @($left | ForEach-Object { [int]$_.ProcessId }))
        }
    } catch { $r.Error = "$($_.Exception.Message)" }
    $r.Looks = $looks.ToArray()
    $r.MsiEvents = @($cap.events.Values | Select-Object -First 40)
    $r.MsiCaptured = @($cap.got.Values | ForEach-Object { [ordered]@{ file = (Split-Path -Leaf "$($_.path)"); path = "$($_.path)"; unpackedAt = "$($_.from)"; sizeMB = [math]::Round($_.len / 1MB, 1) } })
    if ("$($r.MsiLog)".Trim()) { $r.MsiLogFacts = Test-AgentMsiLog -LogPath $r.MsiLog -Arguments $argsIn }
    $r.StartedByInstall = @($started.Values)
    $r.RunningProcesses = @($started.Values | Select-Object -First 15)
    $r.DurationSec = [int]$sw.Elapsed.TotalSeconds
    return $r
}

# ---- trial and error: prove a silent line on this machine -------------------------------------------------------------
# The AI names the lines to try; the machine tries them one at a time and reports what it saw. The verdict is decided
# HERE, from what the process did and what the AI said about the screen - not from what anyone hoped:
#   silent       it finished on its own, no window
#   progress     windows came and went but it finished on its own (a progress bar, the app finishing its settings)
#   interactive  a window sat there with nothing moving, and the look at the screen said it waits for a click
#   hung         nothing on screen, never finished
#   failed       it finished with an exit code that means it did not install, or could not be started
# An installer that does nothing is also silent, so "silent" alone is never success: the snapshot decides that.
function Test-AgentSilentCandidate {
    param([Parameter(Mandatory)][string]$Installer, [string]$Arguments = '', [string]$RunAs = 'Admin',
          [int]$PatienceSec = 1800, [scriptblock]$Progress, [string[]]$AlsoLookIn = @(), [scriptblock]$Judge, [string]$CaptureMsiTo = '')
    # Resolve file-valued properties ONLY for this run. The package script must keep the plain file name - the
    # transform will sit in Files\ next to the MSI - so the resolved form never leaves this function except as a record.
    $asRun = Resolve-AgentArgumentPaths -Arguments $Arguments -InstallerPath $Installer -AlsoLookIn $AlsoLookIn
    $run = Invoke-AgentInstallRun -Installer $Installer -Arguments $asRun -RunAs $RunAs -TimeoutSec $PatienceSec -Progress $Progress -Judge $Judge -CaptureMsiTo $CaptureMsiTo
    $windows = @($run.WindowsSeen)
    $ok = @(0, 1641, 3010)
    $verdict = if ($run.Interrupted) { 'stopped-by-the-packager' }
               elseif ($run.Interactive) { 'interactive' }
               elseif (@(@($run.NeededIntervention) | Where-Object { $_ }).Count) { 'interactive' }   # it only got through because the hands closed windows
               elseif ($run.Error) { 'failed' }
               elseif ($run.TimedOut -and $windows.Count) { 'interactive' }
               elseif ($run.TimedOut) { 'hung' }
               elseif ($null -ne $run.ExitCode -and $ok -notcontains [int]$run.ExitCode) { 'failed' }
               elseif ($windows.Count) { 'progress' }
               else { 'silent' }
    return [ordered]@{ arguments = "$Arguments"; argumentsAsRun = "$asRun"; runAs = $(if ($run.RanAs) { "$($run.RanAs)" } else { "$RunAs" }); verdict = $verdict; exitCode = $run.ExitCode
                       neededIntervention = @($run.NeededIntervention)
                       durationSec = $run.DurationSec; installerEndedAfterSec = $run.ExitedAfterSec; windowsSeen = $windows; timedOut = [bool]$run.TimedOut
                       error = "$($run.Error)"; command = "$($run.Command)"; launchedHow = "$($run.LaunchedHow)"
                       templateDefaultsAdded = @($run.TemplateDefaultsAdded); msiLog = "$($run.MsiLog)"; downloadMarkRemovedFrom = @($run.Unblocked)
                       # did it run as written? the MSI log says which package, whether the transform applied, how it ended
                       msiLogFacts = $run.MsiLogFacts
                       # MSIs the installer unpacked while it ran, copied out before it could delete them
                       msiCaptured = @($run.MsiCaptured)
                       # every Windows Installer transaction and result since the start, with the MSI paths - even
                       # the ones whose file was gone before it could be copied
                       msiEvents = @($run.MsiEvents)
                       # what the machine looked like: every look at the screen (with what the AI said it was), what the
                       # install opened after it ended, and every process it started
                       looks = @($run.Looks)
                       windowsAfterInstall = @($run.WindowsAfterInstall)
                       screenshotWhileRunning = "$($run.ScreenshotWhileRunning)"
                       windowsOnScreen = @($run.WindowsOnScreen)
                       processesThatAppeared = @($run.StartedByInstall)
                       leftRunning = @($run.LeftRunning)
                       packagerSaid = @($run.PackagerSaid) }
}

# TURN A WRITTEN UNINSTALL LINE INTO SOMETHING THE HANDS CAN RUN. The AI writes it the way it will sit in the package
# (Start-ADTMsiProcess -Action Uninstall -ProductCode ..., a quoted unins000.exe with its switches, $envProgramFilesX86\...);
# the test runs the same thing directly. Nothing is invented: a line that cannot be read is reported, not guessed at.
function ConvertTo-AgentRunnable {
    param([string]$Command)
    $out = [ordered]@{ ok = $false; file = ''; args = ''; kind = ''; note = '' }
    $c = "$Command".Trim()
    if (-not $c) { $out.note = 'no uninstall command was given'; return $out }
    $vars = [ordered]@{ '$envProgramFilesX86' = ${env:ProgramFiles(x86)}; '$envProgramFiles' = $env:ProgramFiles; '$envProgramData' = $env:ProgramData
                        '$envCommonProgramFilesX86' = ${env:CommonProgramFiles(x86)}; '$envCommonProgramFiles' = $env:CommonProgramFiles
                        '$envWinDir' = $env:windir; '$envSystemRoot' = $env:SystemRoot; '$envSystemDrive' = $env:SystemDrive; '$envAllUsersProfile' = $env:ALLUSERSPROFILE }
    foreach ($k in $vars.Keys) { $c = [regex]::Replace($c, [regex]::Escape($k) + '(?![A-Za-z0-9])', ("$($vars[$k])" -replace '\$', '$$$$'), 'IgnoreCase') }
    foreach ($m in @([regex]::Matches($c, '\$\{env:([^}]+)\}|\$env:([A-Za-z_][A-Za-z0-9_]*)'))) {
        $n = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        $v = [Environment]::GetEnvironmentVariable($n); if ($v) { $c = $c.Replace($m.Value, $v) }
    }
    $guid = [regex]::Match($c, '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}')
    if ($guid.Success -and $c -match '(?i)msiexec|Start-ADTMsiProcess|Execute-MSI|ProductCode|^\{') {
        $d = Get-AgentTemplateMsiDefaults
        $log = Join-Path $env:TEMP ("PackagingAgent_uninstall_{0}.log" -f (Get-Date -Format 'HHmmss'))
        $out.file = Join-Path $env:SystemRoot 'System32\msiexec.exe'
        $out.args = "/x $($guid.Value) $($d.UninstallParams) $($d.LoggingOptions) `"$log`"" -replace '\s+', ' '
        $out.kind = 'msi'; $out.ok = $true; $out.log = $log
        $out.note = "uninstalled by ProductCode with the template's own uninstall parameters ($($d.UninstallParams)), as Start-ADTMsiProcess does"
        return $out
    }
    if ($c -match '(?i)^\s*(Start-ADTProcess|Execute-Process)\b') {
        $fp = [regex]::Match($c, '(?i)-(FilePath|Path)\s+(?:"([^"]+)"|''([^'']+)''|(\S+))')
        $al = [regex]::Match($c, '(?i)-(ArgumentList|Parameters)\s+(?:"((?:[^"`]|`.)*)"|''([^'']*)''|(\S+))')
        if ($fp.Success) { $out.file = "$(@($fp.Groups[2].Value, $fp.Groups[3].Value, $fp.Groups[4].Value) | Where-Object { $_ } | Select-Object -First 1)" }
        if ($al.Success) { $out.args = "$(@($al.Groups[2].Value, $al.Groups[3].Value, $al.Groups[4].Value) | Where-Object { $_ } | Select-Object -First 1)" -replace '`"', '"' }
    } elseif ($c -match '^\s*"([^"]+)"\s*(.*)$') { $out.file = $Matches[1]; $out.args = $Matches[2] }
    elseif ($c -match '(?i)^\s*(.+?\.(exe|cmd|bat))(\s+(.*))?$') { $out.file = $Matches[1]; $out.args = "$($Matches[4])" }
    $out.file = "$($out.file)".Trim().Trim('"')
    if (-not $out.file) { $out.note = "could not read an executable out of: $Command"; return $out }
    if ($out.file -match '\$') { $out.note = "the uninstaller path still holds a variable the hands cannot resolve: $($out.file)"; return $out }
    if (-not (Test-Path -LiteralPath $out.file)) { $out.note = "the uninstaller it names is not on this machine: $($out.file)"; return $out }
    $out.args = "$($out.args)".Trim(); $out.kind = 'exe'; $out.ok = $true
    return $out
}

# What is still on the machine after the uninstall, compared with the machine before the install.
function ConvertTo-AgentLeftoverSummary {
    param($Compare)
    $o = [ordered]@{}; $total = 0
    foreach ($cat in 'Programs', 'Services', 'Tasks', 'RunKeys', 'Shortcuts', 'Drivers', 'Certificates', 'Printers', 'ProgramDirs') {
        if (-not $Compare -or -not $Compare[$cat]) { continue }
        $a = @($Compare[$cat].Added); if (-not $a.Count) { continue }
        $total += $a.Count
        $o[$cat] = @($a | Select-Object -First 15 | ForEach-Object {
                $i = $_.Info
                $n = @($i.DisplayName, $i.Name, $i.Command, $i.Subject) | Where-Object { "$_".Trim() } | Select-Object -First 1
                "$(if ($n) { $n } else { $_.Id })$(if ($cat -eq 'Programs' -and "$($i.DisplayVersion)".Trim()) { " $($i.DisplayVersion)" })   [$($_.Id)]" })
    }
    $o.count = $total
    $o.note = if ($total) { 'still here after the uninstall, and not here before the install' } else { 'nothing the install added is left - the machine is back where it started' }
    return $o
}

# THE UNINSTALL IS TESTED TOO. A package is two commands; a silent install with an uninstall that shows a wizard, leaves
# the ARP entry behind or asks to reboot fails in production exactly the same way. Run the uninstall the package will
# use, with the same patience and the same looks at the screen, then compare the machine with how it was before the
# install: what is left is either deliberate (user data, shared runtimes) or something the package must clean up.
function Invoke-AgentUninstallTest {
    param([Parameter(Mandatory)]$Sheet, [string]$Command, $Before, [scriptblock]$Judge, [scriptblock]$Progress, [int]$TimeoutSec = 1800)
    $out = [ordered]@{ command = "$Command"; ran = $false; verdict = ''; note = '' }
    $rc = ConvertTo-AgentRunnable -Command $Command
    $out.asRun = $rc
    if (-not $rc.ok) { $out.verdict = 'not-run'; $out.note = "$($rc.note)"; return $out }
    if ($Progress) { & $Progress "uninstall test: $(Split-Path -Leaf $rc.file) $($rc.args)" }
    $run = Invoke-AgentInstallRun -Installer $rc.file -Arguments $rc.args -RunAs 'Admin' -TimeoutSec $TimeoutSec -Progress $Progress -Judge $Judge -Action 'uninstall'
    $out.ran = $true
    $ok = @(0, 1641, 3010)
    $out.verdict = if ($run.Interrupted) { 'stopped-by-the-packager' } elseif ($run.Interactive -or @(@($run.NeededIntervention) | Where-Object { $_ }).Count) { 'interactive' } elseif ($run.Error) { 'failed' }
                   elseif ($run.TimedOut) { 'hung' } elseif ($null -ne $run.ExitCode -and $ok -notcontains [int]$run.ExitCode) { 'failed' }
                   elseif (@($run.WindowsSeen).Count) { 'progress' } else { 'silent' }
    foreach ($k in 'ExitCode', 'DurationSec', 'Error', 'Command', 'LaunchedHow', 'MsiLog') { $out[$k.Substring(0, 1).ToLower() + $k.Substring(1)] = $run[$k] }
    $out.windowsSeen = @($run.WindowsSeen); $out.windowsAfter = @($run.WindowsAfterInstall); $out.looks = @($run.Looks); $out.neededIntervention = @($run.NeededIntervention); $out.msiEvents = @($run.MsiEvents)
    $out.processesThatAppeared = @($run.StartedByInstall); $out.leftRunning = @($run.LeftRunning)
    if ($Before -and (Get-Command Get-MachineSnapshot -ErrorAction SilentlyContinue)) {
        if ($Progress) { & $Progress 'uninstall test: comparing the machine with how it was before the install' }
        try {
            $afterU = Get-MachineSnapshot -NoDeep
            $cmp = Compare-MachineSnapshot -Before $Before -After $afterU -AppVendor "$($Sheet.identity.vendor)" -AppName "$($Sheet.identity.app)"
            $out.leftBehind = ConvertTo-AgentLeftoverSummary $cmp
        } catch { $out.leftBehindError = "$($_.Exception.Message)" }
    } else { $out.leftBehindError = 'there was no before-picture to compare with' }
    return $out
}

# A toolkit log in CMTrace format, as readable lines: "time [severity] component: message". Nothing is left out - the
# markup is what goes (it is about half the file).
function ConvertFrom-AgentCmTraceLog {
    param([string]$Text)
    $ms = [regex]::Matches("$Text", '(?s)<!\[LOG\[(.*?)\]LOG\]!><time="([^"]*)"[^>]*?component="([^"]*)"[^>]*?type="(\d)"')
    if (-not $ms.Count) { return "$Text" }
    $sev = @{ '1' = 'info'; '2' = 'WARN'; '3' = 'ERROR' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($m in $ms) { $t = $m.Groups[2].Value; if ($t.Length -gt 8) { $t = $t.Substring(0, 8) }; [void]$sb.AppendLine("$t [$($sev[$m.Groups[4].Value])] $($m.Groups[3].Value): $($m.Groups[1].Value.Trim())") }
    return $sb.ToString()
}

# THE TOOLKIT'S OWN LOG OF A PACKAGE RUN, IN FULL. How the install really went is only in there - every step, every
# command line, every exit code, in order - and verification has to see all of it, not excerpts. Logs the toolkit
# wrote since $Since in its log folders (config.psd1 LogPath); MSI verbose logs are not included here (they are huge,
# and the toolkit log already records each MSI's exit and its log file name - their error lines come with the evidence).
function Get-AgentToolkitLogs {
    param([Parameter(Mandatory)][datetime]$Since, [int]$MaxCharsPerLog = 200000)
    $out = @()
    foreach ($d in @(Get-AgentPackageLogDirs | Where-Object { Test-Path -LiteralPath $_ })) {
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Recurse -Depth 2 -Filter '*.log' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $Since })) {
            $raw = try { [IO.File]::ReadAllText($f.FullName) } catch { '' }
            if ($raw -match '=== Verbose logging started' -or $raw -notmatch '(?i)<!\[LOG\[|PSAppDeployToolkit') { continue }   # an MSI verbose log, or not the toolkit's
            $txt = ConvertFrom-AgentCmTraceLog $raw
            $note = 'complete'
            if ($txt.Length -gt $MaxCharsPerLog) { $half = [int]($MaxCharsPerLog / 2); $txt = $txt.Substring(0, $half) + "`n...($($txt.Length - $MaxCharsPerLog) characters in the middle not shown - read the file for them)...`n" + $txt.Substring($txt.Length - $half); $note = 'very long - start and end shown' }
            $out += [ordered]@{ file = $f.FullName; written = $f.LastWriteTime.ToString('HH:mm:ss'); note = $note; log = $txt }
        }
    }
    return @($out)
}

# RUN THE BUILT PACKAGE THE WAY DEPLOYMENT RUNS IT - Invoke-AppDeployToolkit.exe -DeploymentType <x> -DeployMode Silent -
# watched by the same runner, and report what the engineer needs to judge it: exit code, windows, pictures, what is on
# the machine now compared with before the first run, and the recent lines of the toolkit's and msiexec's own logs and
# the installer events. A HAND, not a judge: it never decides whether the package is right.
function Invoke-AgentPackageTest {
    param([Parameter(Mandatory)][string]$ScriptPath, [string[]]$DeploymentTypes = @('Install', 'Uninstall'), $Sheet, $Baseline,
          [scriptblock]$Progress, [int]$TimeoutSec = 3600, [int]$StallSec = 45)
    $content = Split-Path -Parent $ScriptPath
    $exe = Join-Path $content 'Invoke-AppDeployToolkit.exe'
    $out = [ordered]@{ package = "$content"; runs = @(); note = '' }
    if (-not (Test-Path -LiteralPath $exe)) { $out.note = "there is no Invoke-AppDeployToolkit.exe beside the script ($content) - the package cannot be run the way it is deployed"; return $out }
    $logDirs = @(Get-AgentPackageLogDirs)
    foreach ($dt in @($DeploymentTypes)) {
        if ("$dt" -notmatch '^(?i)(Install|Repair|Uninstall)$') { $out.runs += [ordered]@{ deploymentType = "$dt"; verdict = 'not-run'; note = 'only Install, Repair and Uninstall exist' }; continue }
        if ($Progress) { try { & $Progress "testing the built package: $dt" } catch {} }
        $t0 = Get-Date
        $run = Invoke-AgentInstallRun -Installer $exe -Arguments "-DeploymentType $dt -DeployMode Silent" -RunAs 'Admin' -TimeoutSec $TimeoutSec -StallSec $StallSec -Progress $Progress
        $ok = (-not $run.Interactive -and -not @(@($run.NeededIntervention) | Where-Object { $_ }).Count -and -not $run.Error -and -not $run.TimedOut -and $null -ne $run.ExitCode -and [int]$run.ExitCode -in 0, 1641, 3010)
        $rec = [ordered]@{ deploymentType = "$dt"; verdict = $(if ($ok) { 'ok' } elseif ($run.Interactive -or @(@($run.NeededIntervention) | Where-Object { $_ }).Count) { 'waited-on-a-window' } elseif ($run.TimedOut) { 'hung' } else { 'failed' })
                           neededIntervention = @($run.NeededIntervention)
                           exitCode = $run.ExitCode; exitCodeMeaning = $(switch ([int]"$($run.ExitCode)") { 0 { 'success' } 3010 { 'success, restart pending' } 1641 { 'success, restart started' } 60001 { 'PSADT: the script hit an unhandled error (read the toolkit log)' } 60008 { 'PSADT: the toolkit could not start (module/session)' } 60012 { 'PSADT: the user deferred / blocked' } 1602 { 'cancelled' } 1603 { 'fatal error during installation' } default { '' } })
                           durationSec = $run.DurationSec; command = "$($run.Command)"; error = "$($run.Error)"
                           windowsSeen = @($run.WindowsSeen); windowsAfter = @($run.WindowsAfterInstall); looks = @($run.Looks); leftRunning = @($run.LeftRunning)
                           toolkitLog = @(try { Get-AgentToolkitLogs -Since $t0 } catch { @() })
                           machineSinceThisRun = $(try { Get-AgentRecentEvidence -Since $t0 -LogDirs $logDirs -MaxFiles 6 -TailLines 60 -MaxErrorLines 40 } catch { $null }) }
        if ($rec.machineSinceThisRun -and @($rec.toolkitLog).Count) {
            # the toolkit log is already here in full - do not send it twice as excerpts
            $full = @($rec.toolkitLog | ForEach-Object { "$($_.file)" })
            $rec.machineSinceThisRun.recentLogs = @(@($rec.machineSinceThisRun.recentLogs) | Where-Object { $full -notcontains "$($_.file)" })
        }
        if ($Baseline -and (Get-Command Get-MachineSnapshot -ErrorAction SilentlyContinue)) {
            try { $rec.onTheMachineNowComparedWithBeforeTheTest = ConvertTo-AgentLeftoverSummary (Compare-MachineSnapshot -Before $Baseline -After (Get-MachineSnapshot -NoDeep) -AppVendor "$($Sheet.identity.vendor)" -AppName "$($Sheet.identity.app)") } catch {}
        }
        $out.runs += $rec
    }
    $out.note = "$(@($out.runs | Where-Object { $_.verdict -eq 'ok' }).Count) of $(@($out.runs).Count) run(s) ended cleanly. An exit code is not a result: read the toolkit log lines, what is on the machine, and the pictures."
    return $out
}

# PREREQUISITES THAT ARE THIS TEAM'S OWN PACKAGES (a database client, a runtime the instructions require) - installed
# the way deployment installs them, from a local copy of the package, and kept on the sheet so they can be removed the
# same way after the tests.
function Install-AgentPrerequisitePackages {
    param([Parameter(Mandatory)]$Sheet, $Packages, [scriptblock]$Progress)
    $done = @()
    # IN ORDER - a prerequisite can have its own prerequisite, and the chain only works bottom-up. Each is copied from
    # the share to this machine and installed from the local copy (Install-AgentPredecessorPackage), never from the share.
    foreach ($pq in @(@(Get-AgentList $Packages) | Sort-Object { if ("$($_.order)".Trim()) { [int]"$($_.order)" } else { 999 } })) {
        $path = "$($pq.path)".Trim()
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { $done += [ordered]@{ name = "$($pq.name)"; path = $path; ok = $false; error = 'the package folder is not reachable' }; break }
        if (@(Get-AgentList $Sheet.prerequisitesInstalled | Where-Object { "$($_.path)" -eq $path -and $_.ok -and -not $_.removed }).Count) { continue }   # already on
        if ($Progress) { & $Progress "installing the prerequisite $($pq.name) from a local copy of its package" }
        $t0 = Get-Date
        $r = Install-AgentPredecessorPackage -PredecessorPath $path -Progress $Progress
        $rec = [ordered]@{ order = $pq.order; name = "$($pq.name)"; path = $path; why = "$($pq.why)"; ok = [bool]$r.ok; exitCode = $r.exitCode; error = "$($r.error)"; localCopy = "$($r.localCopy)"; ranWith = "$($r.ranWith)" }
        if (-not $r.ok) {
            # ITS OWN LOG says what it was missing - often a prerequisite of the prerequisite
            $rec.itsToolkitLog = @(try { Get-AgentToolkitLogs -Since $t0 -MaxCharsPerLog 60000 } catch { @() })
        }
        $done += $rec
        $Sheet.prerequisitesInstalled = @(@(Get-AgentList $Sheet.prerequisitesInstalled) + @($rec))
        if (-not $r.ok) { break }   # the rest of the chain depends on this one
    }
    return @($done)
}
function Remove-AgentPrerequisitePackages {
    param([Parameter(Mandatory)]$Sheet, [scriptblock]$Progress)
    $out = @()
    $list = @(Get-AgentList $Sheet.prerequisitesInstalled | Where-Object { $_.ok -and -not $_.removed }); [array]::Reverse($list)   # dependents first
    foreach ($pq in $list) {
        if ($Progress) { & $Progress "removing the prerequisite $($pq.name) again" }
        $u = Uninstall-AgentPredecessorPackage -InstallResult @{ localCopy = "$($pq.localCopy)" } -Progress $Progress
        $pq.removed = [bool]$u.ok; $pq.removeResult = "$(if ($u.ok) { "removed (exit $($u.exitCode))" } else { "NOT removed: $($u.error)$($u.exitCode)" })"
        $out += "$($pq.name): $($pq.removeResult)"
    }
    return @($out)
}

# How to take one program entry off silently - only from what the entry itself says, or the technology's documented
# silent uninstall (Windows Installer by product code, Inno Setup's unins000.exe). Nothing is invented: an entry with
# none of these is reported, not guessed at.
function Get-AgentSilentUninstallFor {
    param($Info)
    $key = "$($Info._key)"; $u = "$($Info.UninstallString)".Trim(); $q = "$($Info.QuietUninstallString)".Trim()
    if ($key -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$' -and ($u -match '(?i)msiexec' -or -not $u)) { return @{ command = "msiexec /x $key"; how = 'Windows Installer, by product code' } }
    if ($q) { return @{ command = $q; how = 'the entry''s own QuietUninstallString' } }
    $g = [regex]::Match($u, '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}')
    if ($u -match '(?i)msiexec' -and $g.Success) { return @{ command = "msiexec /x $($g.Value)"; how = 'Windows Installer, by product code' } }
    if ($u -match '(?i)unins\d{3}\.exe' -or $key -match '(?i)_is1$') { if ($u) { return @{ command = "$u /VERYSILENT /SUPPRESSMSGBOXES /NORESTART"; how = 'Inno Setup uninstaller, its documented silent switches' } } }
    return $null
}

# Drivers by their driver-store folder name (ftdibus.inf_amd64_27ad...): the published name (oemNN.inf) comes from
# pnputil /enum-drivers, read by pattern so a localised Windows (German labels) reads the same.
function Remove-AgentAddedDrivers {
    param([string[]]$DriverStoreIds = @(), $Before)
    $res = @{ removed = @(); notRemoved = @() }
    $pn = Join-Path $env:windir 'Sysnative\pnputil.exe'; if (-not (Test-Path -LiteralPath $pn)) { $pn = Join-Path $env:windir 'System32\pnputil.exe' }
    if (-not (Test-Path -LiteralPath $pn)) { $res.notRemoved = @($DriverStoreIds | ForEach-Object { "driver $_ - pnputil is not available" }); return $res }
    $map = @(); $pub = $null
    foreach ($ln in @(& $pn /enum-drivers 2>$null)) {
        if ("$ln" -match '(?i)\b(oem\d+\.inf)\b') { $pub = $Matches[1]; continue }
        if ($pub -and "$ln" -match '(?i):\s*(\S+\.inf)\s*$') { $map += @{ pub = $pub; orig = $Matches[1].ToLowerInvariant() }; $pub = $null }
    }
    $beforeKeys = @(if ($Before -and $Before.Drivers) { @($Before.Drivers.Keys) } else { @() })
    foreach ($id in @($DriverStoreIds)) {
        $orig = ("$id" -split '_')[0].ToLowerInvariant()
        if (@($beforeKeys | Where-Object { "$_".ToLowerInvariant().StartsWith("$orig" + '_') }).Count) { $res.notRemoved += "driver $orig - a copy of it was already installed before the test, so it is left alone"; continue }
        $hits = @($map | Where-Object { $_.orig -eq $orig })
        if (-not $hits.Count) { $res.notRemoved += "driver $orig - not found in pnputil's list"; continue }
        foreach ($h in $hits) {
            $o = @(& $pn /delete-driver $h.pub /uninstall /force 2>&1)
            if ($LASTEXITCODE -eq 0) { $res.removed += "driver $orig ($($h.pub))" } else { $res.notRemoved += "driver $orig ($($h.pub)) - pnputil: $((@($o) | Select-Object -Last 1))" }
        }
    }
    return $res
}

# The record of what a cleanup could not remove - the work folder, per machine, never the knowledge base.
function Get-AgentLeftoversPath { $d = if (Get-Command Get-WorkPath -ErrorAction SilentlyContinue) { Get-WorkPath 'AI' } else { Join-Path $env:TEMP 'PackagingAgent\AI' }; return (Join-Path $d 'machine-leftovers.json') }
function Save-AgentLeftovers {
    param([string]$Package, $Cleanup)
    $p = Get-AgentLeftoversPath
    $items = @()
    if ($Cleanup -and $Cleanup.left) {
        foreach ($cat in 'Programs', 'ProgramDirs', 'Drivers', 'Services', 'Tasks', 'Shortcuts') { foreach ($x in @($Cleanup.left[$cat])) { if ("$x".Trim()) { $items += [ordered]@{ category = $cat; item = "$x"; id = $(if ("$x" -match '\[(.+)\]\s*$') { $Matches[1] } else { "$x" }) } } } }
    }
    $all = @(); if (Test-Path -LiteralPath $p) { try { $raw = [IO.File]::ReadAllText($p) | ConvertFrom-Json; $all = @($raw) } catch {} }
    $all = @($all | Where-Object { "$($_.package)" -ne $Package })
    if ($items.Count) { $all += [pscustomobject]@{ package = $Package; at = (Get-Date -Format 'yyyy-MM-dd HH:mm'); items = @($items) } }
    $json = if (@($all).Count) { ConvertTo-Json -InputObject @($all) -Depth 6 } else { '[]' }
    [IO.File]::WriteAllText($p, $json, (New-Object Text.UTF8Encoding $false))
}
# Before a new evaluation: take off what earlier tests on this machine could not. Folders and drivers they created,
# programs they installed (silently, the same way as any cleanup). What still resists is reported.
function Clear-AgentEarlierLeftovers {
    param([scriptblock]$Progress)
    $p = Get-AgentLeftoversPath
    $out = [ordered]@{ removed = @(); stillThere = @() }
    if (-not (Test-Path -LiteralPath $p)) { return $out }
    $all = @(); try { $all = @([IO.File]::ReadAllText($p) | ConvertFrom-Json) } catch { return $out }
    foreach ($rec in $all) {
        foreach ($it in @($rec.items)) {
            $id = "$($it.id)"
            switch ("$($it.category)") {
                'ProgramDirs' { if (Test-Path -LiteralPath $id) { try { Remove-Item -LiteralPath $id -Recurse -Force -ErrorAction Stop; $out.removed += "$id (left by $($rec.package))" } catch { $out.stillThere += "$id - $($_.Exception.Message.Split([char]10)[0])" } } }
                'Drivers' { $r = Remove-AgentAddedDrivers -DriverStoreIds @($id); $out.removed += @($r.removed); $out.stillThere += @($r.notRemoved | Where-Object { $_ -notmatch 'not found' }) }
                'Programs' {
                    $key = @(Get-Item -LiteralPath ("Registry::$($id -replace '^HKLM:', 'HKEY_LOCAL_MACHINE' -replace '^HKCU:', 'HKEY_CURRENT_USER')") -ErrorAction SilentlyContinue)
                    if (-not $key.Count) { continue }
                    $info = @{}; foreach ($n in $key[0].GetValueNames()) { $info[$n] = $key[0].GetValue($n) }; $info['_key'] = $key[0].PSChildName
                    $u = Get-AgentSilentUninstallFor -Info $info
                    $rc = if ($u) { ConvertTo-AgentRunnable -Command $u.command } else { $null }
                    if ($rc -and $rc.ok) {
                        if ($Progress) { & $Progress "removing $($info.DisplayName), left by an earlier test" }
                        $run = Invoke-AgentInstallRun -Installer $rc.file -Arguments $rc.args -RunAs 'Admin' -TimeoutSec 900 -Action 'uninstall'
                        if ($null -eq $run.ExitCode -or [int]$run.ExitCode -notin 0, 1605, 1641, 3010) { $out.stillThere += "$($info.DisplayName) - exit $($run.ExitCode)" } else { $out.removed += "$($info.DisplayName) (left by $($rec.package))" }
                    } else { $out.stillThere += "$($info.DisplayName) - no silent uninstall known" }
                }
                default { $out.stillThere += "$($it.category): $($it.item)" }
            }
        }
    }
    try { if (-not @($out.stillThere).Count) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } } catch {}
    return $out
}

# GIVE THE MACHINE BACK. Everything a test put on this machine since the baseline comes off again, so the next attempt,
# the next test round and the next order all start from a clean machine: program entries (silently, see above), the
# folders the install created under Program Files / ProgramData, its shortcuts, and scheduled tasks / services / run
# entries that point into what was removed. What cannot be removed is reported - to the AI and to the packager.
# Only what is NEW since the baseline and not background noise is ever touched.
function Invoke-AgentMachineCleanup {
    param([Parameter(Mandatory)]$Before, $Sheet, [scriptblock]$Progress, [scriptblock]$Judge, [string]$Why = '')
    $say = { param($t) if ($Progress) { try { & $Progress $t } catch {} } }
    $out = [ordered]@{ why = "$Why"; programsRemoved = @(); foldersRemoved = @(); otherRemoved = @(); couldNotRemove = @(); left = $null; clean = $false }
    if (-not (Get-Command Get-MachineSnapshot -ErrorAction SilentlyContinue)) { $out.couldNotRemove += 'the snapshot engine is not loaded'; return $out }
    $vendor = "$($Sheet.identity.vendor)"; $app = "$($Sheet.identity.app)"
    $diff = { Compare-MachineSnapshot -Before $Before -After (Get-MachineSnapshot -NoDeep) -AppVendor $vendor -AppName $app }
    $cmp = & $diff
    $progs = @(@($cmp.Programs.Added) | Where-Object { $i = $_.Info; [int]"$($i.SystemComponent)" -ne 1 -and "$($i.DisplayName)".Trim() -and "$($i.DisplayName)" -notmatch '(?i)^(Update for|Security Update|Microsoft Defender|Definition Update)|\bKB\d{6,}\b' })
    foreach ($p in $progs) {
        $name = "$($p.Info.DisplayName) $($p.Info.DisplayVersion)".Trim()
        $u = Get-AgentSilentUninstallFor -Info $p.Info
        if (-not $u) { $out.couldNotRemove += "$name - no silent uninstall is known (UninstallString: $($p.Info.UninstallString))"; continue }
        $rc = ConvertTo-AgentRunnable -Command $u.command
        if (-not $rc.ok) { $out.couldNotRemove += "$name - $($rc.note)"; continue }
        & $say "cleaning up: removing $name ($($u.how))"
        $run = Invoke-AgentInstallRun -Installer $rc.file -Arguments $rc.args -RunAs 'Admin' -TimeoutSec 900 -Progress $Progress -Judge $Judge -Action 'uninstall'
        $ok = (-not $run.Interactive -and -not $run.Error -and -not $run.TimedOut -and ($null -eq $run.ExitCode -or [int]$run.ExitCode -in 0, 1605, 1614, 1641, 3010))
        if ($ok) { $out.programsRemoved += "$name - $($u.how) (exit $($run.ExitCode))" } else { $out.couldNotRemove += "$name - '$($run.Command)' ended $(if ($run.Interactive) { 'waiting on a window' } else { "with exit $($run.ExitCode) $($run.Error)" })" }
    }
    # what the programs left on disk, and what points into it
    $cmp = & $diff
    $gone = New-Object System.Collections.Generic.List[string]
    foreach ($d in @($cmp.ProgramDirs.Added)) {
        $path = "$($d.Id)"
        try { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop; $out.foldersRemoved += $path; $gone.Add($path) }
        catch { if (-not (Test-Path -LiteralPath $path)) { $out.foldersRemoved += $path; $gone.Add($path) } else { $out.couldNotRemove += "$path - $($_.Exception.Message.Split([char]10)[0])" } }
    }
    $pointsIntoGone = { param($text) foreach ($g in $gone) { if ("$text".IndexOf($g, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true } }; return $false }
    foreach ($s in @($cmp.Shortcuts.Added)) { try { Remove-Item -LiteralPath "$($s.Id)" -Force -ErrorAction Stop; $out.otherRemoved += "shortcut $($s.Id)" } catch {} }
    foreach ($t in @($cmp.Tasks.Added)) {
        if (-not (& $pointsIntoGone "$($t.Info.Action)")) { continue }
        try { Unregister-ScheduledTask -TaskName "$($t.Info.Name)" -TaskPath "$($t.Info.Path)" -Confirm:$false -ErrorAction Stop; $out.otherRemoved += "scheduled task $($t.Id)" } catch { $out.couldNotRemove += "task $($t.Id) - $($_.Exception.Message.Split([char]10)[0])" }
    }
    foreach ($sv in @($cmp.Services.Added)) {
        if (-not (& $pointsIntoGone "$($sv.Info.Path)")) { continue }
        try { Stop-Service -Name "$($sv.Id)" -Force -ErrorAction SilentlyContinue; $null = & sc.exe delete "$($sv.Id)"; $out.otherRemoved += "service $($sv.Id)" } catch { $out.couldNotRemove += "service $($sv.Id)" }
    }
    foreach ($rk in @($cmp.RunKeys.Added)) {
        if (-not (& $pointsIntoGone "$($rk.Info.Command)")) { continue }
        try { Remove-ItemProperty -LiteralPath "$($rk.Info.Hive)" -Name "$($rk.Info.Name)" -Force -ErrorAction Stop; $out.otherRemoved += "run entry $($rk.Id)" } catch {}
    }
    # DRIVERS the test added to the driver store - taken out with pnputil, but only when no copy of the same driver
    # was there before the test (then it may belong to a device on this machine, and it is reported instead)
    $drvAdded = @($cmp.Drivers.Added)
    if ($drvAdded.Count) { $r = Remove-AgentAddedDrivers -DriverStoreIds @($drvAdded | ForEach-Object { "$($_.Id)" }) -Before $Before; $out.otherRemoved += @($r.removed); $out.couldNotRemove += @($r.notRemoved) }
    $out.left = ConvertTo-AgentLeftoverSummary (& $diff)
    $out.clean = -not [int]$out.left.count
    # WHAT COULD NOT BE REMOVED IS WRITTEN DOWN, and tried again before the next evaluation starts - so a machine a test
    # left dirty does not stay dirty for the next order
    try { Save-AgentLeftovers -Package "$($Sheet.package)" -Cleanup $out } catch {}
    & $say $(if ($out.clean) { 'the machine is back to its baseline' } else { "the machine is NOT fully back: $([int]$out.left.count) item(s) remain" })
    return $out
}

# THE RELIABLE WAY TO FIND A WRAPPED MSI: watch for it while the installer runs.
# A self-extracting EXE drops its real MSI into %TEMP%, %ProgramData%\Package Cache (WiX/Burn keeps the application's
# own MSI there) or %WINDIR%\Installer. Take the list before, take it after, and the difference is what this
# installer actually used - no guessing from bytes, no 7-Zip needed, and the install was happening anyway.
# %WINDIR%\Installer is the Windows runtime cache: an MSI there is a COPY Windows made, not the vendor's file, so it
# is reported separately rather than offered as something to package.
function Get-AgentMsiWatchBaseline {
    if (-not (Get-Command Get-MsiWatchDirs -ErrorAction SilentlyContinue)) { return $null }
    $dirs = @(Get-MsiWatchDirs)
    return [ordered]@{ dirs = $dirs; snapshot = (Get-MsiSnapshot -Dirs $dirs) }
}
function Get-AgentMsiAppearedDuringInstall {
    param($Baseline, [int]$MinKB = 200)
    if (-not $Baseline -or -not (Get-Command Get-NewMsisSince -ErrorAction SilentlyContinue)) { return @() }
    $new = @(Get-NewMsisSince -Dirs @($Baseline.dirs) -Snapshot $Baseline.snapshot -MinKB $MinKB)
    return @($new | ForEach-Object {
            $p = "$($_.FullName)"; if (-not $p) { $p = "$_" }
            $props = @{}
            try {
                $i = New-Object -ComObject WindowsInstaller.Installer
                $db = $i.OpenDatabase($p, 0)
                $v = $db.OpenView("SELECT ``Property``,``Value`` FROM ``Property`` WHERE ``Property`` = 'ProductName' OR ``Property`` = 'ProductVersion' OR ``Property`` = 'ProductCode' OR ``Property`` = 'Manufacturer'")
                $v.Execute($null)
                while ($true) { $r = $v.Fetch(); if (-not $r) { break }; $props["$($r.StringData(1))"] = "$($r.StringData(2))" }
            } catch {}
            [ordered]@{
                path = $p; name = (Split-Path -Leaf $p)
                sizeMB = $(try { [math]::Round((Get-Item -LiteralPath $p).Length / 1MB, 1) } catch { 0 })
                productName = "$($props.ProductName)"; productVersion = "$($props.ProductVersion)"
                productCode = "$($props.ProductCode)"; manufacturer = "$($props.Manufacturer)"
                isWindowsInstallerCacheCopy = [bool](Test-RuntimeCacheMsi -Path $p)
            } })
}

# IS THE MACHINE ALREADY DIRTY? Installing on top of a copy that is already there produces a diff nobody can read -
# the new version may upgrade in place, or refuse, or leave two ARP entries behind. Before any baseline, look for
# what is already installed that relates to this application, and let the AI decide what to do about it.
function Get-AgentInstalledRelated {
    param([string]$Vendor, [string]$App, [string[]]$ExtraTokens = @())
    $tokens = @()
    foreach ($t in @($Vendor, $App) + @($ExtraTokens)) {
        foreach ($w in @("$t" -split '[^A-Za-z0-9]+')) { if ("$w".Length -ge 4) { $tokens += "$w".ToLower() } }
    }
    $tokens = @($tokens | Sort-Object -Unique)
    if (-not $tokens.Count) { return @() }
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                      'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') {
        foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $p = $null; try { $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop } catch { continue }
            $name = "$($p.DisplayName)"
            if (-not $name.Trim()) { continue }
            if ([int]$p.SystemComponent -eq 1) { continue }
            $hay = "$name $($p.Publisher)".ToLower()
            $hit = @($tokens | Where-Object { $hay.Contains($_) })
            if (-not $hit.Count) { continue }
            $found.Add([ordered]@{
                    displayName = $name; version = "$($p.DisplayVersion)"; publisher = "$($p.Publisher)"
                    productCode = $(if ("$($k.PSChildName)" -match '^\{[0-9A-Fa-f-]{36}\}$') { "$($k.PSChildName)" } else { '' })
                    uninstallString = "$($p.UninstallString)"; quietUninstallString = "$($p.QuietUninstallString)"
                    registryKey = "$root\$($k.PSChildName)"; matchedOn = ($hit -join ', ') })
        }
    }
    return $found.ToArray()
}

# Install the PREVIOUS package so the diff can be old-versus-new instead of clean-versus-new. That comparison is the
# only reliable way to learn the real ProductCode of each version, whether paths or registry names moved between
# them, and - in a multi-installer package - which installer produced which ARP entry. A packager does this by hand;
# the agent asks for it when the answer it needs is a comparison.
function Install-AgentPredecessorPackage {
    param([Parameter(Mandatory)][string]$PredecessorPath, [int]$TimeoutSec = 1800, [scriptblock]$Progress)
    $script = @(Get-ChildItem -LiteralPath $PredecessorPath -Filter '*.ps1' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '(?i)^(Invoke-AppDeployToolkit|Deploy-Application)\.ps1$' } | Select-Object -First 1)
    if (-not $script) { return [ordered]@{ ok = $false; error = "the previous package has no deploy script under $PredecessorPath" } }
    # run it from a LOCAL copy: a package on a share installs differently (and slower) than one on disk
    $local = Join-Path $env:TEMP ('PredInstall_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    if ($Progress) { & $Progress 'copying the previous package locally' }
    try {
        New-Item -ItemType Directory -Force -Path $local | Out-Null
        $root = $script.Directory.FullName
        foreach ($i in @(Get-ChildItem -LiteralPath $root -Force)) { Copy-Item -LiteralPath $i.FullName -Destination (Join-Path $local $i.Name) -Recurse -Force -ErrorAction SilentlyContinue }
    } catch { return [ordered]@{ ok = $false; error = "could not copy the previous package: $($_.Exception.Message)" } }
    $localScript = Join-Path $local $script.Name
    if (-not (Test-Path -LiteralPath $localScript)) { return [ordered]@{ ok = $false; error = 'the copy did not produce a deploy script' } }
    # RUN THE PACKAGE THE WAY THE PACKAGE IS RUN. A PSADT package ships Invoke-AppDeployToolkit.exe beside its .ps1,
    # and that .exe is what deployment actually launches - it picks the right PowerShell host and architecture and
    # sets the toolkit up before the script gets a say. Driving the .ps1 through powershell.exe by hand tests a path
    # nobody deploys, so a package that works in production can fail here, or worse, pass here and fail there.
    $launcher = @(Get-ChildItem -LiteralPath $local -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match '(?i)^(Invoke-AppDeployToolkit|Deploy-Application)\.exe$' } | Select-Object -First 1)
    $how = if ($launcher) { "$($launcher[0].Name)" } else { "$($script.Name) through powershell.exe (the package ships no .exe launcher)" }
    if ($Progress) { & $Progress "installing the previous package with $how" }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = [ordered]@{ ok = $false; script = "$localScript"; ranWith = "$how"; from = "$PredecessorPath"; exitCode = $null; durationSec = 0; error = '' }
    try {
        if ($launcher) {
            $p = Start-Process -FilePath $launcher[0].FullName -ArgumentList '-DeploymentType Install -DeployMode Silent' -WorkingDirectory $local -Verb RunAs -PassThru -ErrorAction Stop
        } else {
            $psi = "-NoProfile -ExecutionPolicy Bypass -File `"$localScript`" -DeploymentType Install -DeployMode Silent"
            $p = Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList $psi -WorkingDirectory $local -Verb RunAs -PassThru -ErrorAction Stop
        }
        while (-not $p.HasExited) {
            if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) { try { $p.Kill() } catch {}; $r.error = 'timed out'; break }
            Start-Sleep -Milliseconds 1500
            if ($Progress) { & $Progress ("previous package installing {0:N0}s" -f $sw.Elapsed.TotalSeconds) }
        }
        if (-not $r.error) { $r.exitCode = $p.ExitCode; $r.ok = ($p.ExitCode -in 0, 1641, 3010) }
    } catch { $r.error = "$($_.Exception.Message)" }
    $r.durationSec = [int]$sw.Elapsed.TotalSeconds
    # KEEP THE LOCAL COPY. It is how the predecessor gets uninstalled again afterwards - deleting it here left the
    # old version installed on the bench with nothing left to remove it with.
    $r.localCopy = "$local"
    Write-Log "Predecessor install for comparison: $(if ($r.ok) { "ok (exit $($r.exitCode)) via $how" } else { "failed - $($r.error)$($r.exitCode)" })"
    return $r
}

# PUT THE BENCH BACK. The previous version is installed here only to make the comparison read old-versus-new; once
# the evaluation is over it is somebody else's software sitting on the packager's machine. Nothing removed it, so
# every comparison run left the old version behind - and the next order's "what is already installed" check then
# found it and had to reason about a mess this tool made.
# Uninstalled the same way it was installed: through the package's own .exe launcher when it has one.
function Uninstall-AgentPredecessorPackage {
    param([Parameter(Mandatory)]$InstallResult, [int]$TimeoutSec = 1800, [scriptblock]$Progress)
    $r = [ordered]@{ ok = $false; ranWith = ''; exitCode = $null; durationSec = 0; error = '' }
    $local = "$($InstallResult.localCopy)"
    if (-not "$local".Trim() -or -not (Test-Path -LiteralPath $local)) { $r.error = 'the local copy of the previous package is gone, so it cannot be uninstalled the way it was installed'; return $r }
    $launcher = @(Get-ChildItem -LiteralPath $local -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match '(?i)^(Invoke-AppDeployToolkit|Deploy-Application)\.exe$' } | Select-Object -First 1)
    $script = @(Get-ChildItem -LiteralPath $local -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '(?i)^(Invoke-AppDeployToolkit|Deploy-Application)\.ps1$' } | Select-Object -First 1)
    if (-not $launcher -and -not $script) { $r.error = 'no launcher or deploy script in the local copy'; return $r }
    $r.ranWith = if ($launcher) { "$($launcher[0].Name)" } else { "$($script[0].Name) through powershell.exe" }
    if ($Progress) { & $Progress "removing the previous version again with $($r.ranWith)" }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        if ($launcher) {
            $p = Start-Process -FilePath $launcher[0].FullName -ArgumentList '-DeploymentType Uninstall -DeployMode Silent' -WorkingDirectory $local -Verb RunAs -PassThru -ErrorAction Stop
        } else {
            $psi = "-NoProfile -ExecutionPolicy Bypass -File `"$($script[0].FullName)`" -DeploymentType Uninstall -DeployMode Silent"
            $p = Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList $psi -WorkingDirectory $local -Verb RunAs -PassThru -ErrorAction Stop
        }
        while (-not $p.HasExited) {
            if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) { try { $p.Kill() } catch {}; $r.error = 'timed out'; break }
            Start-Sleep -Milliseconds 1500
            if ($Progress) { & $Progress ("removing the previous version {0:N0}s" -f $sw.Elapsed.TotalSeconds) }
        }
        if (-not $r.error) { $r.exitCode = $p.ExitCode; $r.ok = ($p.ExitCode -in 0, 1641, 3010) }
    } catch { $r.error = "$($_.Exception.Message)" }
    $r.durationSec = [int]$sw.Elapsed.TotalSeconds
    try { Remove-Item $local -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    Write-Log "Predecessor removed after the comparison: $(if ($r.ok) { "ok (exit $($r.exitCode))" } else { "FAILED - $($r.error)$($r.exitCode) - the old version is still on this machine" })"
    return $r
}

# MORE THAN ONE INSTALLER IS THE NORM (59% of the corpus). When the instructions document gives the sequence, there is
# nothing to discover: run the steps in the stated order and check each one before moving on. A step that fails stops
# the sequence - installing the main application after its prerequisite failed only produces a confusing diff.
function Invoke-AgentInstallSequence {
    param([Parameter(Mandatory)]$Steps, [Parameter(Mandatory)][string]$SourceFolder, [string]$RunAs = 'Admin',
          [int]$PatienceSec = 1800, [scriptblock]$Progress, [string[]]$AlsoLookIn = @(), [scriptblock]$Judge, [string]$CaptureMsiTo = '')
    $ordered = @(@(Get-AgentList $Steps) | Sort-Object { [int]"$($_.order)" })
    $done = New-Object System.Collections.Generic.List[object]
    $n = 0
    foreach ($s in $ordered) {
        $n++
        $name = "$($s.installer)".Trim()
        $stepArgs = "$($s.arguments)"
        # the AI's whole command line is the authority when it wrote one
        if ("$($s.commandLine)".Trim()) { $cl = ConvertFrom-AgentCommandLine "$($s.commandLine)"; if ($cl.ok) { if (-not $name) { $name = $cl.installer }; if (-not $stepArgs.Trim()) { $stepArgs = $cl.arguments } } }
        if (-not $name) { continue }
        $file = $null
        foreach ($root in @(@($SourceFolder) + @($AlsoLookIn) | Where-Object { "$_".Trim() -and (Test-Path -LiteralPath $_) })) {
            $hit = @(Get-ChildItem -LiteralPath $root -File -Recurse -Depth 8 -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -eq (Split-Path -Leaf $name) } | Select-Object -First 1)
            if ($hit) { $file = $hit.FullName; break }
        }
        if (-not $file) {
            $done.Add([ordered]@{ order = $n; installer = $name; purpose = "$($s.purpose)"; verdict = 'not-delivered'; aiCommand = "$($s.commandLine)"
                                  error = "'$name' is not in the order folder, among the extracted or caught MSIs, or in the previous package" })
            if ($Progress) { & $Progress "step $n of $($ordered.Count): $name is NOT here - stopping" }
            break
        }
        if ($Progress) { & $Progress "step $n of $($ordered.Count): $name $stepArgs   [$($s.purpose)]" }
        $a = Test-AgentSilentCandidate -Installer $file -Arguments $stepArgs -RunAs $RunAs -PatienceSec $PatienceSec -Progress $Progress -AlsoLookIn $AlsoLookIn -Judge $Judge -CaptureMsiTo $CaptureMsiTo
        $a.order = $n; $a.installer = $name; $a.installerPath = $file; $a.purpose = "$($s.purpose)"; $a.expected = "$($s.expect)"; $a.aiCommand = "$($s.commandLine)"
        $done.Add($a)
        Write-Log "AI sequence: step $n '$name $stepArgs' -> $($a.verdict)$(if ($null -ne $a.exitCode) { " (exit $($a.exitCode))" })"
        if ($a.verdict -notin 'silent', 'progress') {
            if ($Progress) { & $Progress "step $n failed ($($a.verdict)) - the rest of the sequence is not run" }
            break
        }
    }
    $steps = $done.ToArray()
    $ranAll = (@($steps).Count -eq @($ordered).Count)
    $allOk = ($ranAll -and -not @($steps | Where-Object { $_.verdict -notin 'silent', 'progress' }).Count)
    return [ordered]@{ steps = $steps; stepCount = @($ordered).Count; completed = @($steps).Count
                       found = $allOk; ranEveryStep = $ranAll
                       winner = $(if ($allOk) { @($steps)[0] } else { $null }) }
}

# Try the candidates in order until one installs silently. Returns every attempt - the failures are evidence too.
function Invoke-AgentSilentTrial {
    param([Parameter(Mandatory)][string]$Installer, [Parameter(Mandatory)][object[]]$Candidates, [string]$RunAs = 'Admin',
          [int]$PatienceSec = 1800, [scriptblock]$Progress, [string[]]$AlsoLookIn = @(), [scriptblock]$Judge, [string]$CaptureMsiTo = '',
          [scriptblock]$BetweenAttempts, [switch]$CleanBeforeFirst)
    $attempts = New-Object System.Collections.Generic.List[object]
    $n = 0
    foreach ($cand in @($Candidates)) {
        $n++
        # EVERY CANDIDATE STARTS ON A CLEAN MACHINE: what a failed attempt half-installed would change how the next
        # one behaves (an installer that finds itself already there repairs, refuses or skips)
        $cleaned = $null
        if ($BetweenAttempts -and ($n -gt 1 -or $CleanBeforeFirst)) { $cleaned = try { & $BetweenAttempts } catch { $null } }
        $cmdArgs = if ($cand -is [string]) { "$cand" } else { "$($cand.command)" }
        $src = if ($cand -is [string]) { '' } else { "$($cand.source)" }
        $aiLine = if ($cand -is [string]) { '' } else { "$($cand.commandLine)" }
        if ($Progress) { & $Progress "candidate $n of $(@($Candidates).Count): $(if ("$cmdArgs".Trim()) { $cmdArgs } else { '(no arguments)' })$(if ($src) { "   [$src]" })" }
        $a = Test-AgentSilentCandidate -Installer $Installer -Arguments $cmdArgs -RunAs $RunAs -PatienceSec $PatienceSec -Progress $Progress -AlsoLookIn $AlsoLookIn -Judge $Judge -CaptureMsiTo $CaptureMsiTo
        $a.candidate = $n; $a.source = $src; $a.aiCommand = $aiLine; $a.installer = (Split-Path -Leaf $Installer); $a.installerPath = $Installer
        if ($cleaned) { $a.cleanedBefore = [ordered]@{ programsRemoved = @($cleaned.programsRemoved); foldersRemoved = @($cleaned.foldersRemoved); couldNotRemove = @($cleaned.couldNotRemove); clean = [bool]$cleaned.clean } }
        $attempts.Add($a)
        Write-Log "AI trial: candidate $n '$cmdArgs' -> $($a.verdict)$(if ($null -ne $a.exitCode) { " (exit $($a.exitCode))" })"
        if ($a.verdict -in 'silent', 'progress') { break }
    }
    $win = @($attempts.ToArray() | Where-Object { $_.verdict -in 'silent', 'progress' }) | Select-Object -First 1
    return [ordered]@{ attempts = $attempts.ToArray(); winner = $win; found = [bool]$win }
}
#endregion

#region Report --------------------------------------------------------------------------------------------------------
function ConvertTo-AgentHtmlText { param([string]$s) return [System.Net.WebUtility]::HtmlEncode("$s") }
function ConvertTo-AgentSheetHtml {
    param([Parameter(Mandatory)]$Sheet)
    $e = { param($s) ConvertTo-AgentHtmlText "$s" }
    $list = { param($items, $empty = '-') $a = @($items | Where-Object { $_ -ne $null -and "$_" -ne '' }); if (-not $a.Count) { return "<span class=muted>$empty</span>" }; return '<ul>' + (($a | ForEach-Object { '<li>' + (& $e $(if ($_ -is [string]) { $_ } else { ($_ | ConvertTo-Json -Compress -Depth 4) })) + '</li>' }) -join '') + '</ul>' }
    $kv = { param($h) if (-not $h -or -not $h.Count) { return '<span class=muted>-</span>' }; $rows = foreach ($k in $h.Keys) { $v = $h[$k]; $vs = if ($v -is [string] -or $v -is [bool] -or $v -is [int] -or $v -is [double]) { & $e "$v" } elseif ($v -is [array]) { & $list $v } else { '<pre>' + (& $e ($v | ConvertTo-Json -Depth 6)) + '</pre>' }; "<tr><th>$(& $e $k)</th><td>$vs</td></tr>" }; return "<table>$($rows -join '')</table>" }
    $statusCol = switch ("$($Sheet.status)") { 'ready' { '#6A9955' } 'evaluated' { '#56C8D6' } 'ask_ao' { '#E0BE7C' } 'blocked' { '#F48771' } default { '#A0A8B4' } }
    $pl = $Sheet.plan; $d = $Sheet.decision
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("<!doctype html><html><head><meta charset='utf-8'><title>Evaluation sheet - $(& $e $Sheet.package)</title><style>
body{background:#181A1F;color:#E7E9ED;font-family:'Segoe UI',sans-serif;font-size:13px;margin:0;padding:20px 28px}h1{font-size:18px;margin:0 0 4px}h2{font-size:14px;color:#56C8D6;margin:22px 0 8px;border-bottom:1px solid #2E3340;padding-bottom:4px}
.badge{display:inline-block;padding:2px 10px;border-radius:10px;font-weight:600;color:#181A1F;background:$statusCol}.muted{color:#A0A8B4}table{border-collapse:collapse;margin:4px 0}th{color:#B7BEC8;text-align:left;vertical-align:top;padding:3px 12px 3px 0;font-weight:500;white-space:nowrap}td{padding:3px 0;vertical-align:top}
ul{margin:2px 0 2px 18px;padding:0}li{margin:1px 0}pre{background:#0C0C0C;color:#D7D7D7;padding:8px;border-radius:4px;white-space:pre-wrap;font-family:Consolas,monospace;font-size:12px;margin:2px 0}
.q{background:#2A2618;border-left:3px solid #E0BE7C;padding:6px 10px;margin:4px 0}.b{background:#2C1E1C;border-left:3px solid #F48771;padding:6px 10px;margin:4px 0}.ok{background:#1C2A1E;border-left:3px solid #6A9955;padding:6px 10px;margin:4px 0}.cand{background:#1E2128;border:1px solid #2A2F38;border-radius:5px;padding:6px 10px;margin:4px 0}code{font-family:Consolas,monospace;color:#D7FFD7}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:24px}</style></head><body>")
    [void]$sb.AppendLine("<h1>$(& $e $Sheet.package) <span class=badge>$(& $e $Sheet.status)</span></h1><div class=muted>RITM $(& $e $Sheet.ritm) · generated $(& $e $Sheet.generated) · $(& $e $Sheet.folder)</div>")
    [void]$sb.AppendLine('<h2>Flow</h2><table><tr><th>Stage</th><th>State</th><th>Who</th><th>What / why</th></tr>')
    foreach ($s in (Get-AgentFlow -Sheet $Sheet)) {
        $cl = switch ("$($s.state)") { 'done' { 'ok' } 'failed' { 'b' } 'blocked' { 'b' } 'waiting' { 'q' } default { 'muted' } }
        [void]$sb.AppendLine("<tr><td>$(& $e $s.title)</td><td class=$cl><b>$(& $e ("$($s.state)".ToUpper()))</b></td><td>$(& $e $s.owner)</td><td>$(& $e $(if ("$($s.why)".Trim()) { $s.why } else { $s.what }))</td></tr>")
    }
    [void]$sb.AppendLine('</table>')
    if ($pl -and "$($pl.summary)".Trim()) { [void]$sb.AppendLine("<h2>Summary</h2><div class=ok>$((& $e $pl.summary) -replace "`n", '<br>')</div>") }
    $blocks = @(Get-AgentList $Sheet.gaps | Where-Object { $_.severity -eq 'block' }); $asks = @(Get-AgentList $Sheet.gaps | Where-Object { $_.severity -eq 'ask' }); $infos = @(Get-AgentList $Sheet.gaps | Where-Object { $_.severity -eq 'info' })
    $qs = @(Get-AgentList $pl.questions)
    [void]$sb.AppendLine('<h2>Missing / to clarify</h2>')
    foreach ($g in $blocks) { [void]$sb.AppendLine("<div class=b><b>BLOCKED</b> · $(& $e $g.text)</div>") }
    foreach ($g in $asks) { [void]$sb.AppendLine("<div class=q>$(& $e $g.text)</div>") }
    foreach ($q in $qs) { [void]$sb.AppendLine("<div class=$(if ([bool]$q.blocksTheTest) { 'b' } else { 'q' })><b>$(& $e $q.forWhom)</b> · $(& $e $q.question)<div class=muted>$(& $e $q.why)</div></div>") }
    if ($pl.humanNeeded -and [bool]$pl.humanNeeded.required) { [void]$sb.AppendLine("<div class=q><b>Needs a person</b> · $(& $e $pl.humanNeeded.what)<br><code>$(& $e $pl.humanNeeded.exactCommand)</code><div class=muted>send back: $(& $e $pl.humanNeeded.sendBack)</div></div>") }
    foreach ($g in $infos) { [void]$sb.AppendLine("<div class=muted>· $(& $e $g.text)</div>") }
    if (-not $blocks.Count -and -not $asks.Count -and -not $qs.Count) { [void]$sb.AppendLine('<div class=ok>Nothing missing.</div>') }
    if ($pl -and $pl.route) {
        [void]$sb.AppendLine("<h2>The plan</h2><div class=cand><b>$(& $e $pl.route.kind) · route $(& $e $pl.route.number)</b> · $(& $e $pl.route.why)</div>")
        if ("$($pl.understanding)".Trim()) { [void]$sb.AppendLine("<div class=muted>$((& $e $pl.understanding) -replace "`n", '<br>')</div>") }
        foreach ($s in (Get-AgentList $pl.install.steps)) { [void]$sb.AppendLine("<div class=cand>$(& $e $s.order). <code>$(& $e $s.installer) $(& $e $s.arguments)</code> <span class=muted>[$(& $e $s.purpose)] $(& $e $s.source)</span></div>") }
        foreach ($s in (Get-AgentList $pl.install.alternatives)) { [void]$sb.AppendLine("<div class=cand><span class=muted>alternative:</span> <code>$(& $e $s.arguments)</code> <span class=muted>$(& $e $s.source) - $(& $e $s.why)</span></div>") }
        [void]$sb.AppendLine((& $kv ([ordered]@{
            'Predecessor' = "$(if ([bool]$pl.predecessor.found) { "$($pl.predecessor.name) ($($pl.predecessor.confidence)) - $($pl.predecessor.why)" } else { "none - $($pl.predecessor.why)" })"
            'Documents read' = (Get-AgentList $pl.documentsRead)
            'The test must prove' = (Get-AgentList $pl.evaluate.mustProve)
            'Removed before the test' = @(Get-AgentList $pl.evaluate.removeFirst | ForEach-Object { "$($_.displayName): $($_.command)" })
            'Compare with the previous version' = "$(if ([bool]$pl.evaluate.compareWithPredecessor) { "yes - $($pl.evaluate.whyCompare)" } else { 'no' })"
            'Parameter intents' = (Get-AgentList $pl.install.intentsCovered)
            'Delivered files' = @(Get-AgentList $pl.package.deliveredFiles | ForEach-Object { "$($_.file): $($_.whatItIs) - $($_.whatThePackageDoesWithIt)" })
            'Changes to the reused script' = @(Get-AgentList $pl.package.changes | ForEach-Object { "$($_.section): $($_.why)" })
            'Confidence' = "$($pl.confidence)" })))
    } elseif ($pl -and $pl.error) { [void]$sb.AppendLine("<h2>The plan</h2><div class=b>$(& $e $pl.error)</div>") }
    if ($d -and $d.Count -and -not $d.error) {
        [void]$sb.AppendLine("<h2>Decision after snapshot</h2><div class=ok>$((& $e $d.summary) -replace "`n", '<br>')</div>")
        [void]$sb.AppendLine((& $kv ([ordered]@{ 'Install outcome' = $d.installOutcome; 'Method' = "$($d.packagingMethod.method)"; 'Install command' = "$($d.packagingMethod.installCommand)"; 'Uninstall command' = "$($d.packagingMethod.uninstallCommand)"; 'Reason' = "$($d.packagingMethod.reason)"; 'Auto-update' = $d.autoUpdate; 'Per-user' = $d.perUser; 'Detection' = $d.detection; 'What the test proved' = @(Get-AgentList $d.provedWhatWasPlanned | ForEach-Object { "$(if ([bool]$_.seen) { 'seen' } else { 'NOT SEEN' }): $($_.claim) - $($_.evidence)" }); 'Package changed by the test' = $d.packageUpdate; 'Needs a human decision' = (Get-AgentList $d.needsHumanDecision); 'Confidence' = "$($d.confidence)" })))
        [void]$sb.AppendLine('<h3>What the installer did - verdicts</h3><table><tr><th>Category</th><th>Item</th><th>Verdict</th><th>Action</th><th>Reason</th></tr>')
        foreach ($it in (Get-AgentList $d.items)) { [void]$sb.AppendLine("<tr><td>$(& $e $it.category)</td><td>$(& $e $it.label)</td><td>$(& $e $it.verdict)</td><td>$(& $e $it.action)</td><td>$(& $e $it.reason)$(if ("$($it.command)".Trim()) { "<br><code>$(& $e $it.command)</code>" })</td></tr>") }
        [void]$sb.AppendLine('</table>')
    } elseif ($d -and $d.error) { [void]$sb.AppendLine("<h2>Decision after snapshot</h2><div class=b>$(& $e $d.error)</div>") }
    $bld = $Sheet.build
    if ($bld -and "$($bld.script)".Trim()) {
        [void]$sb.AppendLine('<h2>The package that was built</h2>' + (& $kv ([ordered]@{
            'Folder' = "$($bld.folder)"; 'Script' = "$($bld.script)"
            'Built from' = "$($bld.basedOn) ($($bld.builtWith))"
            'Files placed by' = "$($bld.placedBy)"
            'Uninstall-previous block' = $(if ($null -ne $bld.uninstallPreviousAdded) { "$(if ($bld.uninstallPreviousAdded) { 'added' } else { 'not added' }) - $($bld.uninstallPreviousWhy)" } else { '' })
            'Sections written' = @(Get-AgentList $bld.sectionsWritten | ForEach-Object { "$($_.section): $($_.steps) step(s)" })
            'Not written' = @(Get-AgentList $bld.notWritten | ForEach-Object { "$($_.section): $($_.why)" }) })))
    }
    $ver = $Sheet.verification
    if ($ver -and $ver.verdict) {
        $cls = if ("$($ver.verdict)" -eq 'pass') { 'ok' } else { 'b' }
        [void]$sb.AppendLine("<h2>Verification of the built package</h2><div class=$cls><b>$(& $e ("$($ver.verdict)".ToUpper()))</b> · $((& $e $ver.summary) -replace "`n", '<br>')</div>")
        [void]$sb.AppendLine((& $kv $ver.coverage))
        if ((Get-AgentList $ver.findings).Count) {
            [void]$sb.AppendLine('<table><tr><th>Severity</th><th>Section</th><th>What</th><th>Why</th><th>Evidence / fix</th></tr>')
            foreach ($f in (Get-AgentList $ver.findings)) { [void]$sb.AppendLine("<tr><td>$(& $e $f.severity)</td><td>$(& $e $f.section)</td><td>$(& $e $f.what)</td><td>$(& $e $f.why)</td><td><code>$(& $e $f.evidence)</code>$(if ([bool]$f.fixed) { '<br><span class=ok>fixed</span>' })</td></tr>") }
            [void]$sb.AppendLine('</table>')
        }
        if ((Get-AgentList $ver.changesApplied).Count) {
            [void]$sb.AppendLine('<h3>What the AI changed in the package</h3><table><tr><th>File</th><th>Line</th><th>Why</th><th>Now reads</th></tr>')
            foreach ($ch in (Get-AgentList $ver.changesApplied)) { [void]$sb.AppendLine("<tr><td>$(& $e $ch.file)</td><td>$(& $e $ch.line)</td><td>$(& $e $ch.what)</td><td><pre>$(& $e $ch.replaceWith)</pre></td></tr>") }
            [void]$sb.AppendLine('</table>')
        }
        if ((Get-AgentList $ver.needsHumanDecision).Count) { [void]$sb.AppendLine('<h3>Needs a human decision</h3>' + (& $list $ver.needsHumanDecision)) }
    } elseif ($ver -and $ver.error) { [void]$sb.AppendLine("<h2>Verification of the built package</h2><div class=b>$(& $e $ver.error)</div>") }
    # THE CONVERSATION: what the AI asked the tool, what the tool answered, what the AI concluded.
    $conv = @(); foreach ($src in @($Sheet.plan, $Sheet.decision, $Sheet.verification)) { if ($src -and $src.transcript) { $conv += @($src.transcript) } }
    if ($conv.Count) {
        [void]$sb.AppendLine('<h2>AI &harr; tool conversation</h2><div class=muted>Every question the model asked the machine, and every answer it got. This is the evidence behind the decisions above.</div>')
        foreach ($t in $conv) {
            [void]$sb.AppendLine("<div class=cand><div class=muted>$(& $e $t.at) &middot; $(& $e $t.stage)</div>")
            if ("$($t.thinking)".Trim()) { [void]$sb.AppendLine("<div><b>AI:</b> $((& $e $t.thinking) -replace "`n", '<br>')</div>") }
            foreach ($cm in @($t.commands)) {
                [void]$sb.AppendLine("<div class=muted style='margin-top:6px'>AI asks the tool ($(& $e $cm.intent)): $(& $e $cm.purpose)</div><pre>$(& $e $cm.script)</pre>")
                $o = "$($cm.output)"; if ($o.Length -gt 3000) { $o = $o.Substring(0, 3000) + "`n...(truncated)" }
                [void]$sb.AppendLine("<div class=muted>tool answers$(if (-not $cm.ok) { ' - FAILED' }):</div><pre>$(& $e $o)</pre>")
                if (@($cm.changedFiles).Count) { [void]$sb.AppendLine("<div class=ok>changed: $(& $e (@($cm.changedFiles) -join ', '))</div>") }
                if ("$($cm.refused)".Trim()) { [void]$sb.AppendLine("<div class=b>refused: $(& $e $cm.refused)</div>") }
            }
            if ("$($t.result)".Trim()) { [void]$sb.AppendLine("<div class=muted>$(& $e $t.result)</div>") }
            [void]$sb.AppendLine('</div>')
        }
    }
    $nxt = Get-AgentNextStage -Sheet $Sheet
    if ($nxt) { [void]$sb.AppendLine("<h2>Next step</h2><div class=q><b>$(& $e $nxt.title)</b> &middot; $(& $e $(if ("$($nxt.why)".Trim()) { $nxt.why } else { $nxt.what }))</div>") }
    if ($Sheet.observed -and $Sheet.observed.run) { [void]$sb.AppendLine('<h2>Observed (snapshot run)</h2>' + (& $kv ([ordered]@{ 'Run' = $Sheet.observed.run; 'Counts' = $Sheet.observed.snapshot.counts; 'Programs (ARP)' = @($Sheet.observed.snapshot.Programs.added | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion) ($($_.Publisher))" }); 'Services' = @($Sheet.observed.snapshot.Services.added | ForEach-Object { "$($_.DisplayName) [$($_.Start)]" }); 'Scheduled tasks' = @($Sheet.observed.snapshot.Tasks.added | ForEach-Object { "$($_.Path)$($_.Name)" }); 'Run keys' = @($Sheet.observed.snapshot.RunKeys.added | ForEach-Object { "$($_.Name) = $($_.Command)" }); 'Shortcuts' = @($Sheet.observed.snapshot.Shortcuts.added | ForEach-Object { "$($_.Name) -> $($_.Target)" }); 'File groups' = @($Sheet.observed.snapshot.fileGroups | Select-Object -First 25); 'Per-user registry' = @($Sheet.observed.snapshot.perUserRegistry | Select-Object -First 15); 'Per-user files' = @($Sheet.observed.snapshot.perUserFiles | Select-Object -First 15) }))) }
    [void]$sb.AppendLine('<div class=grid><div>')
    [void]$sb.AppendLine('<h2>Declared by the AO (form)</h2>' + (& $kv $Sheet.declared))
    [void]$sb.AppendLine('</div><div>')
    [void]$sb.AppendLine('<h2>Sources</h2>' + (& $kv $Sheet.sources))
    [void]$sb.AppendLine('<h2>Documents</h2>' + (& $kv $Sheet.documents))
    [void]$sb.AppendLine('<h2>History</h2>' + (& $kv $Sheet.history))
    [void]$sb.AppendLine('</div></div>')
    [void]$sb.AppendLine('<h2>Audit</h2>' + (& $kv $Sheet.audit) + '<h3>Timeline</h3>' + (& $list @($Sheet.timeline | ForEach-Object { "$($_.at)  $($_.text)" })))
    [void]$sb.AppendLine('</body></html>')
    return $sb.ToString()
}

# Short plain-text rendering for the tool window / CLI.
function Format-AgentSheetText {
    param([Parameter(Mandatory)]$Sheet)
    $sb = New-Object Text.StringBuilder
    $pl = $Sheet.plan
    [void]$sb.AppendLine("$($Sheet.package)   RITM $($Sheet.ritm)   status: $("$($Sheet.status)".ToUpper())")
    [void]$sb.AppendLine(); [void]$sb.AppendLine('FLOW:'); [void]$sb.AppendLine((Format-AgentFlowText -Sheet $Sheet))
    $nx = Get-AgentNextStage -Sheet $Sheet
    if ($nx) { [void]$sb.AppendLine("  next: $($nx.title)$(if ("$($nx.why)".Trim()) { " - $($nx.why)" })") }
    if ($pl -and "$($pl.summary)".Trim()) { [void]$sb.AppendLine(); [void]$sb.AppendLine("$($pl.summary)") }
    $blocks = @(Get-AgentList $Sheet.gaps | Where-Object { $_.severity -eq 'block' })
    $asks = @(Get-AgentList $Sheet.gaps | Where-Object { $_.severity -eq 'ask' })
    $qs = @(Get-AgentList $pl.questions)
    if ($blocks.Count) { [void]$sb.AppendLine(); [void]$sb.AppendLine('BLOCKED:'); foreach ($g in $blocks) { [void]$sb.AppendLine("  x $($g.text)") } }
    if ($asks.Count -or $qs.Count) { [void]$sb.AppendLine(); [void]$sb.AppendLine('OPEN QUESTIONS:'); foreach ($g in $asks) { [void]$sb.AppendLine("  ? $($g.text)") }; foreach ($q in $qs) { [void]$sb.AppendLine("  ? [$($q.forWhom)] $($q.question)") } }
    if ($pl -and $pl.route) {
        [void]$sb.AppendLine(); [void]$sb.AppendLine("PLAN: $($pl.route.kind), route $($pl.route.number) - $($pl.route.why)")
        if ([bool]$pl.predecessor.found) { [void]$sb.AppendLine("  previous version: $($pl.predecessor.name) ($($pl.predecessor.confidence))") }
        foreach ($s in (Get-AgentList $pl.install.steps)) { [void]$sb.AppendLine("  $($s.order). $($s.installer) $($s.arguments)   [$($s.source)]") }
        foreach ($m in (Get-AgentList $pl.evaluate.mustProve)) { [void]$sb.AppendLine("  must prove: $m") }
    }
    $d = $Sheet.decision
    if ($d -and $d.Count -and -not $d.error) {
        [void]$sb.AppendLine(); [void]$sb.AppendLine("DECISION (after snapshot): $($d.packagingMethod.method)  [$($d.confidence)]")
        [void]$sb.AppendLine("  install:   $($d.packagingMethod.installCommand)"); [void]$sb.AppendLine("  uninstall: $($d.packagingMethod.uninstallCommand)")
        [void]$sb.AppendLine("  silent: $($d.installOutcome.silent)  exit ok: $($d.installOutcome.exitCodeOk)  $($d.installOutcome.notes)")
        if ($d.autoUpdate -and $d.autoUpdate.found) { [void]$sb.AppendLine("  auto-update: $($d.autoUpdate.mechanism) -> $($d.autoUpdate.disableAction)") }
        if ($d.perUser) { [void]$sb.AppendLine("  per-user: $($d.perUser.mode) $($d.perUser.what)") }
        foreach ($it in (Get-AgentList $d.items)) { [void]$sb.AppendLine("  [$("$($it.action)".ToUpper())] $($it.category): $($it.label) - $($it.verdict); $($it.reason)") }
        foreach ($h in (Get-AgentList $d.needsHumanDecision)) { [void]$sb.AppendLine("  HUMAN: $h") }
        [void]$sb.AppendLine("  $($d.summary)")
    }
    [void]$sb.AppendLine(); [void]$sb.AppendLine("model: $(Format-AgentUsage)")
    return $sb.ToString()
}
#endregion

