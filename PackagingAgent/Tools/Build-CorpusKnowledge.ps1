##############################################################
# Build-CorpusKnowledge.ps1  -  turn the team's shipped package library into knowledge the agent carries.
#
#   Not a switch table. HOW this team packages: how a package is laid out, how the previous version is removed, what
#   goes into post-install (the updater, shortcuts, configuration, per-user settings), how uninstall cleans up, how
#   detection and reboots are handled, what the authors wrote in their comments when something needed a workaround,
#   and what the evaluation left behind (the evaluation document, the owner's form with the packaging team's section,
#   the MRF, the query mails).
#
#   It reads the library ONCE, read-only, and writes consolidated files into Knowledge\Corpus\. At runtime the agent
#   never goes to the shares for this - the knowledge travels with the tool, so it still works on another machine,
#   for another brand, or after the library has moved. Re-run it when the library has grown.
#
#   .\Build-CorpusKnowledge.ps1                   the live library + Outgoing (engine-settings.json)
#   .\Build-CorpusKnowledge.ps1 -Max 20           a quick trial on 20 packages
#   .\Build-CorpusKnowledge.ps1 -From <share>     another library (e.g. another brand's)
#   Default: packages changed in the last 24 months (-SinceMonths 0 = all), read by 8 parallel workers (-Workers).
#   -> Knowledge\Corpus\Index.json      every package, one line: vendor, app, version, technology - to find the right ones
#      Knowledge\Corpus\Packages\<vendor>.json   one profile per package: how it was packaged, evaluated and fixed
#      Knowledge\Corpus\Patterns.json   what the whole library does, section by section, with counts and examples
#      Knowledge\Corpus\Vendors.json    per vendor: how this team packages that vendor's software
#      Knowledge\Corpus\Lessons.json    what package authors wrote down when something needed explaining
##############################################################
[CmdletBinding()]
param([string[]]$From, [int]$Max = 0, [string]$OutDir, [switch]$NoDocuments, [switch]$Fresh,
      [int]$SinceMonths = 24,        # only packages changed in the last N months: current practice, not history (0 = all)
      [int]$Workers = 8,             # parallel readers - the shares are the slow part, so reading 8 at once is ~8x faster
      [string]$CacheDir,             # one small JSON per package read, so a refresh only reads what is new
      [string]$WorkerList)           # internal: this process is a worker reading the packages listed in this file

# PS 5.1: without this, ConvertTo-Json writes some arrays as {"value":[...],"Count":n} (the ETS Count property on
# System.Array), and the profiles read back as objects instead of lists
Remove-TypeData System.Array -ErrorAction SilentlyContinue
$toolsRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$agentRoot = Split-Path -Parent $toolsRoot
foreach ($f in 'Core.ps1', 'PSADT_V3toV4_Mappings.ps1', 'Predecessor.ps1') { . (Join-Path $agentRoot "Engine\$f") }
foreach ($f in 'Agent.Docs.ps1', 'Agent.Core.ps1') { . (Join-Path $agentRoot "Src\$f") }
Initialize-Config (Join-Path $agentRoot 'engine-settings.json') | Out-Null
try { Initialize-Log } catch {}
function Write-Log { param($Message, $Level) }   # the engine narrates every package it reads; 1000 packages of that is noise here
$script:AgentHome = $agentRoot
if (-not $OutDir) { $OutDir = Join-Path $agentRoot 'Knowledge\Corpus' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$cacheDir = if ("$CacheDir".Trim()) { $CacheDir } else { Join-Path $env:TEMP 'PackagingAgent\corpus-cache' }
if ($Fresh -and -not $WorkerList -and (Test-Path $cacheDir)) { Remove-Item $cacheDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not $From) {
    $From = @(@(Get-Setting 'PredecessorPath'), '\\MNDEMUCFS120.mn-man.biz\SWDistribution-Gate\CMLib_LIVE\Apps', @(Get-Setting 'OutgoingPath')) | Where-Object { "$_".Trim() }
}
$roots = @($From | Where-Object { try { Test-Path -LiteralPath $_ } catch { $false } })
if (-not $roots.Count) { throw "None of the libraries is reachable: $($From -join '; ')" }

# ---- what every package shares (so only what an author WROTE is kept) ---------------------------------------------------
$tplLines = @{}
$tpl = Join-Path $agentRoot 'Template\Content\Invoke-AppDeployToolkit.ps1'
if (Test-Path $tpl) { foreach ($l in (Get-Content $tpl)) { $k = ($l -replace '\s+', ' ').Trim(); if ($k) { $tplLines[$k] = 1 } } }
$boiler = '(?i)^#+\s*(<Perform|\*|MARK|Show |Handle Zero|Installation tasks|Uninstallation tasks|Repair tasks|Pre-|Post-|Main-|Install|Uninstall|Repair|region|endregion|-{3,}|={3,})'
# a line that DOES something to an updater - not a log variable or a comment that merely mentions "update"
$updaterAction = '(?i)(update|updater|maintenance|telemetry|usage ?data|autostart)'
$updaterVerb = '(?i)(Disable|Stop-|Remove-|Unregister|Set-Service|Set-ADTRegistryKey|Set-ItemProperty|New-ItemProperty|schtasks|sc(\.exe)?\s+(config|stop|delete)|reg(\.exe)?\s+(add|delete)|Copy-ADTFile|Set-ADTIniValue|-StartupType)'
function Test-UpdaterLine { param([string]$l) return ($l -match $updaterAction -and $l -match $updaterVerb -and $l -notmatch '^\s*\$\w*log\w*\s*=' -and $l -notmatch '(?i)Write-ADTLogEntry|Write-Log|^\s*#') }
$issueWords ='(?i)\b(because|workaround|work-around|issue|problem|bug|fix|fixed|known|note|important|attention|caution|otherwise|required|necessary|must|do not|don''t|never|since|due to|wegen|achtung|hinweis|fehler|muss|nicht)\b'

function Get-Cut { param([string]$s, [int]$n = 200) $t = ("$s" -replace '\s+', ' ').Trim(); if ($t.Length -gt $n) { return $t.Substring(0, $n) + '...' }; return $t }
function Get-Shape { param([string]$s) # the SHAPE of a target, so the same practice is counted once across versions
    $t = "$s"
    $t = [regex]::Replace($t, '\{[0-9A-Fa-f-]{36}\}', '{GUID}')
    $t = [regex]::Replace($t, '(?<![A-Za-z])\d+(\.\d+){1,3}', '<ver>')
    return (Get-Cut $t 120)
}
# The operations in a code section: the command, and what it acts on.
function Get-Operations { param([string]$Code)
    $ops = New-Object System.Collections.Generic.List[object]
    foreach ($line in ("$Code" -split "`r?`n")) {
        $l = $line.Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        foreach ($m in [regex]::Matches($l, '(?<![\w$-])([A-Z][A-Za-z]+-(?:ADT|MTB|PB|VWG)?[A-Za-z0-9]+)\b(.*)')) {
            $cmd = $m.Groups[1].Value
            if ($cmd -match '^(Write-ADTLogEntry|Write-Log|Write-Host|Write-Output|Get-Date|Join-Path|Split-Path|Test-Path|Get-Item|Get-ChildItem|Where-Object|ForEach-Object|Select-Object|Out-Null|New-Object|Get-ADTConfig|Get-ADTSession)$') { continue }
            $rest = $m.Groups[2].Value
            $target = ''
            $tm = [regex]::Match($rest, "(?i)-(?:LiteralPath|Path|Key|FilePath|Name|TaskName|ServiceName|Destination|ProductCode)\s+(""[^""]+""|'[^']+'|\S+)")
            if ($tm.Success) { $target = $tm.Groups[1].Value.Trim('"', "'") }
            elseif ($rest -match "^\s*(""[^""]+""|'[^']+')") { $target = $Matches[1].Trim('"', "'") }
            $ops.Add([ordered]@{ cmd = $cmd; target = (Get-Cut $target 160); line = (Get-Cut $l 220) })
            break
        }
    }
    return $ops.ToArray()
}
# What an author wrote: comment lines that are not the template's own.
function Get-AuthorNotes { param([string]$Code)
    $out = @()
    foreach ($line in ("$Code" -split "`r?`n")) {
        $l = $line.Trim()
        if (-not $l.StartsWith('#')) { continue }
        $k = ($l -replace '\s+', ' ').Trim()
        if ($tplLines.ContainsKey($k) -or $l -match $boiler) { continue }
        $txt = ($l -replace '^#+\s*', '').Trim()
        if ($txt.Length -lt 18 -or ($txt -split '\s+').Count -lt 4) { continue }
        if ($txt -match '^[\w-]+\s+-\w+') { continue }   # commented-out code, not a note
        $out += (Get-Cut $txt 260)
    }
    return @($out | Select-Object -Unique)
}
# A small document out of a folder OR out of a zip beside it, read as text.
function Read-DocText { param([string]$Path, [int]$MaxChars = 2500)
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $t = ''
    try {
        if ($ext -eq '.docx') { $d = Read-AgentDocx -Path $Path; if ($d.Ok) { $t = "$($d.Text)" } }
        elseif ($ext -in '.xlsx', '.xlsm') { $x = Read-AgentXlsx -Path $Path; if ($x.Ok) { $t = "$($x.Text)" } }
    } catch {}
    $t = Invoke-AgentScrub $t
    return $t
}
# The part of a form or an evaluation document that says how it was packaged and tested.
function Get-PackagingSection { param([string]$Text, [int]$Max = 2200)
    if (-not "$Text".Trim()) { return '' }
    $i = -1
    foreach ($rx in '(?i)filled (in )?by (the )?packag', '(?i)packaging team', '(?i)evaluation result', '(?i)install(ation)? command', '(?i)silent') {
        $m = [regex]::Match($Text, $rx); if ($m.Success) { $i = [Math]::Max(0, $m.Index - 40); break }
    }
    if ($i -lt 0) { $i = 0 }
    return (Get-Cut $Text.Substring($i) $Max)
}

# ---- one package -> one profile ---------------------------------------------------------------------------------------
function Get-PackageProfile { param([IO.DirectoryInfo]$Dir, [string]$Library)
    $content = Join-Path $Dir.FullName 'Content'
    if (-not (Test-Path -LiteralPath $content)) { $content = $Dir.FullName }
    $script = @('Invoke-AppDeployToolkit.ps1', 'Deploy-Application.ps1') | ForEach-Object { Join-Path $content $_ } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $script) { $script = @(Get-ChildItem -LiteralPath $Dir.FullName -Filter '*.ps1' -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^(Invoke-AppDeployToolkit|Deploy-Application)\.ps1$' } | Select-Object -First 1 -ExpandProperty FullName) }
    if (-not $script) { return $null }
    $raw = Read-FileSmart -Path $script
    $model = Read-PredecessorModel -Content $raw -PackageName $Dir.Name
    if (-not $model) { return $null }
    $pn = Parse-PackageName -Name $Dir.Name
    $code = $model.Code
    $p = [ordered]@{
        package = $Dir.Name; library = $Library; written = $(try { $Dir.LastWriteTime.ToString('yyyy-MM') } catch { '' })
        vendor = "$($pn.Vendor)"; app = "$($pn.AppName)"; version = "$($pn.Version)"; arch = "$($pn.Arch)"
        psadt = "$($model.TemplateVer)"; installerType = "$($model.Installer.Type)"; multi = [bool]$model.IsMulti
    }
    # layout: what the package carries, by name
    $files = Join-Path (Split-Path -Parent $script) 'Files'
    $sup = Join-Path (Split-Path -Parent $script) 'SupportFiles'
    $p.files = @(if (Test-Path -LiteralPath $files) { Get-ChildItem -LiteralPath $files -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 40 | ForEach-Object { $r = $_.FullName.Substring($files.Length).TrimStart('\'); if ($_.PSIsContainer) { "$r\" } else { $r } } })
    $p.supportFiles = @(if (Test-Path -LiteralPath $sup) { Get-ChildItem -LiteralPath $sup -Recurse -Depth 2 -File -ErrorAction SilentlyContinue | Select-Object -First 20 | ForEach-Object { $_.FullName.Substring($sup.Length).TrimStart('\') } })
    $p.transform = "$($model.Installer.MstFileName)"
    $p.responseFiles = @(@($p.files) + @($p.supportFiles) | Where-Object { $_ -match '(?i)\.(iss|inf|properties|rsp|xml|ini|cfg|json)$' } | Select-Object -First 8)
    # how it installs and uninstalls
    $p.install = @(@($model.InstallSeq) | Select-Object -First 6 | ForEach-Object { Get-Cut "$($_.Display)" 240 })
    $p.uninstall = @(@($model.UninstallSeq) | Select-Object -First 6 | ForEach-Object { Get-Cut "$($_.Display)" 240 })
    # what each phase does
    $sections = [ordered]@{}
    foreach ($s in 'PreInstallCode', 'PostInstallCode', 'PreUninstallCode', 'PostUninstallCode', 'MainRepairCode') {
        $ops = @(Get-Operations "$($code[$s])")
        if ($ops.Count) { $sections[($s -replace 'Code$', '')] = @($ops | Select-Object -First 25) }
    }
    $p.phases = $sections
    $allCode = (@('PreInstallCode', 'MainInstallCode', 'PostInstallCode', 'PreUninstallCode', 'MainUninstallCode', 'PostUninstallCode', 'MainRepairCode') | ForEach-Object { "$($code[$_])" }) -join "`n"
    $p.previousVersionRemoval = $(if (-not "$($code.PreInstallCode)".Trim()) { 'none' } elseif (Test-AgentGenericRemoval -Code "$($code.PreInstallCode)" -Identity $model.Identity) { 'generic' } elseif ("$($code.PreInstallCode)" -match '(?i)uninstall|Remove-|msiexec\s+/x|-Action\s+.?Uninstall') { 'version-pinned' } else { 'other' })
    $p.perUser = @(@(if ($allCode -match '(?i)Set-ADTActiveSetup|Set-ActiveSetup') { 'Active Setup' }), @(if ($allCode -match '(?i)Invoke-ADTAllUsersRegistryAction|Invoke-HKCURegistrySettingsForAllUsers') { 'all-users registry' }), @(if (@($p.supportFiles) -match '(?i)activesetup') { 'Active Setup stub in SupportFiles' }) | Where-Object { $_ })
    $p.updater = @(("$allCode" -split "`r?`n") | Where-Object { Test-UpdaterLine $_ } | Select-Object -First 6 | ForEach-Object { Get-Cut $_ 220 })
    $p.shortcuts = @(("$allCode" -split "`r?`n") | Where-Object { $_ -match '(?i)\.lnk' -and $_ -notmatch '^\s*#' } | Select-Object -First 4 | ForEach-Object { Get-Cut $_ 200 })
    $p.reboot = @(("$allCode" -split "`r?`n") | Where-Object { $_ -match '(?i)Set-MTBReboot|Set-ADTReboot|3010|1641|RebootPassThru|-RebootNeeded' -and $_ -notmatch '^\s*#' } | Select-Object -First 3 | ForEach-Object { Get-Cut $_ 160 })
    $p.detection = Get-Cut "$($model.Session.SoftIdent)" 220
    $p.procToClose = "$($model.Session.ProcToClose)"
    $p.authorNotes = @(Get-AuthorNotes $allCode | Select-Object -First 15)
    # the paperwork: what evaluation and the owner left behind
    if (-not $NoDocuments) {
        $docs = Join-Path $Dir.FullName 'Documents'
        $names = New-Object System.Collections.Generic.List[string]
        $texts = [ordered]@{}
        if (Test-Path -LiteralPath $docs) {
            foreach ($f in @(Get-ChildItem -LiteralPath $docs -Recurse -Depth 2 -File -ErrorAction SilentlyContinue)) {
                $names.Add($f.Name)
                if ($f.Extension -ieq '.zip') {
                    try {
                        $z = [IO.Compression.ZipFile]::OpenRead($f.FullName)
                        try {
                            foreach ($e in $z.Entries) {
                                if (-not $e.Name) { continue }
                                $names.Add("$($f.Name)/$($e.FullName -replace '\\', '/')")   # zips made on Windows often store backslashes
                                $want = ($e.Name -match '(?i)\.(docx|xlsx|xlsm)$' -and $e.Length -lt 15MB -and $e.Name -match '(?i)evaluation|installation instructions|MRF|request|instructions')
                                if ($want -and $texts.Count -lt 3) {
                                    $tmp = Join-Path $env:TEMP ('corpus_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + [IO.Path]::GetExtension($e.Name))
                                    try { [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $tmp, $true); $texts[$e.Name] = Get-PackagingSection (Read-DocText $tmp) } catch {} finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
                                }
                            }
                        } finally { $z.Dispose() }
                    } catch {}
                } elseif ($f.Name -match '(?i)\.(docx|xlsx|xlsm)$' -and $f.Name -match '(?i)evaluation|installation instructions|MRF|request|instructions' -and $texts.Count -lt 3 -and $f.Length -lt 15MB) {
                    $texts[$f.Name] = Get-PackagingSection (Read-DocText $f.FullName)
                }
            }
        }
        $all = @($names.ToArray())
        $p.documents = [ordered]@{
            evaluationDoc = @($all | Where-Object { $_ -match '(?i)evaluation' -and $_ -match '(?i)\.docx?$' } | Select-Object -First 2)
            ownerForm = @($all | Where-Object { $_ -match '(?i)installation instructions|request' -and $_ -match '(?i)\.docx?$' } | Select-Object -First 2)
            mrf = [bool]@($all | Where-Object { $_ -match '(?i)MRF' }).Count
            complexity = [bool]@($all | Where-Object { $_ -match '(?i)complexity' }).Count
            eqsChecklist = [bool]@($all | Where-Object { $_ -match '(?i)EQS_Checklist|checklist' }).Count
            sourceValidation = [bool]@($all | Where-Object { $_ -match '(?i)Install_report|Uninstall_report|Source Validat' }).Count
            testLogs = @($all | Where-Object { $_ -match '(?i)(^|/)(Standalone|Upgrade|Predecessor|Admin|System)/' } | ForEach-Object { ($_ -split '/')[-2] } | Select-Object -Unique)
            queryMails = @($all | Where-Object { $_ -match '(?i)\.msg$' } | ForEach-Object { Get-Cut ((Split-Path -Leaf $_) -replace '\.msg$', '') 160 } | Select-Object -First 8)
            whatTheyRecorded = $texts }
    }
    return $p
}

# ---- read one package into the cache (the worker's whole job) -------------------------------------------------------
$readOne = {
    param([string]$Path, [string]$Library)
    $d = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $d) { return }
    $cache = Join-Path $cacheDir ($d.Name + '.json')
    if (Test-Path -LiteralPath $cache) { return }
    $p = $null
    try { $p = Get-PackageProfile -Dir $d -Library $Library } catch { Write-Host "  ! $($d.Name): $($_.Exception.Message)" -ForegroundColor DarkYellow }
    if ($p) { try { ($p | ConvertTo-Json -Depth 10 -Compress) | Out-File -LiteralPath $cache -Encoding utf8 } catch {} }
    else { try { '{}' | Out-File -LiteralPath $cache -Encoding utf8 } catch {} }   # not a package: do not look again
}
if ($WorkerList) {
    foreach ($line in @(Get-Content -LiteralPath $WorkerList)) { $parts = "$line" -split '\|', 2; if ($parts.Count -eq 2) { & $readOne $parts[1] $parts[0] } }
    return
}

# ---- walk the libraries: current practice only (last N months), newest first, each package once --------------------
$seen = @{}
$dirs = New-Object System.Collections.Generic.List[object]
$since = if ($SinceMonths -gt 0) { (Get-Date).AddMonths(-$SinceMonths) } else { [datetime]::MinValue }
foreach ($r in $roots) {
    $lib = if ($r -match '(?i)Outgoing') { 'outgoing' } else { 'live' }
    foreach ($d in @(Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $since } | Sort-Object LastWriteTime -Descending)) {
        $k = $d.Name.ToLowerInvariant(); if ($seen[$k]) { continue }; $seen[$k] = $true
        $dirs.Add(@{ Dir = $d; Library = $lib })
    }
}
if ($Max -gt 0) { $dirs = [System.Collections.Generic.List[object]]@($dirs.ToArray() | Select-Object -First $Max) }
$sw = [Diagnostics.Stopwatch]::StartNew()
$todo = @($dirs.ToArray() | Where-Object { -not (Test-Path -LiteralPath (Join-Path $cacheDir ($_.Dir.Name + '.json'))) })
Write-Host "$($dirs.Count) package(s) since $($since.ToString('yyyy-MM-dd')) from $($roots -join ' + '); $($todo.Count) not read yet" -ForegroundColor Cyan
if ($todo.Count) {
    $w = [Math]::Max(1, [Math]::Min($Workers, [int][Math]::Ceiling($todo.Count / 10)))
    $procs = @()
    for ($i = 0; $i -lt $w; $i++) {
        $list = Join-Path $cacheDir ("_worker$i.txt")
        @(for ($j = $i; $j -lt $todo.Count; $j += $w) { "$($todo[$j].Library)|$($todo[$j].Dir.FullName)" }) | Set-Content -LiteralPath $list -Encoding UTF8
        $a = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -WorkerList `"$list`" -CacheDir `"$cacheDir`"$(if ($NoDocuments) { ' -NoDocuments' })"
        $procs += Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList $a -WindowStyle Hidden -PassThru
    }
    while (@($procs | Where-Object { -not $_.HasExited }).Count) {
        Start-Sleep -Seconds 5
        $done = @($todo | Where-Object { Test-Path -LiteralPath (Join-Path $cacheDir ($_.Dir.Name + '.json')) }).Count
        Write-Host ("  {0}/{1} read by {2} workers  {3:N0}s" -f $done, $todo.Count, $w, $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
    }
    Get-ChildItem -LiteralPath $cacheDir -Filter '_worker*.txt' | Remove-Item -Force -ErrorAction SilentlyContinue
}
$profiles = New-Object System.Collections.Generic.List[object]
foreach ($item in $dirs) {
    $cache = Join-Path $cacheDir ($item.Dir.Name + '.json')
    if (-not (Test-Path -LiteralPath $cache)) { continue }
    # one shape for every profile: Group-Object and Where-Object read PROPERTIES, not hashtable keys
    $p = try { Get-Content -LiteralPath $cache -Raw | ConvertFrom-Json } catch { $null }
    if ($p -and "$($p.package)".Trim()) { $profiles.Add($p) }
}
$all = $profiles.ToArray()
# profiles cached by an older run are held to today's rules too
foreach ($p in $all) { if ($p.PSObject.Properties['updater']) { $p.updater = @(@($p.updater) | Where-Object { Test-UpdaterLine "$_" }) } }
Write-Host "$($all.Count) package profile(s) in $([int]$sw.Elapsed.TotalSeconds)s" -ForegroundColor Green

# ---- consolidate --------------------------------------------------------------------------------------------------------
$pct = { param($c) if ($all.Count) { [math]::Round(100.0 * $c / $all.Count) } else { 0 } }
$phaseOps = [ordered]@{}
foreach ($ph in 'PreInstall', 'PostInstall', 'PreUninstall', 'PostUninstall', 'MainRepair') {
    $byCmd = @{}
    foreach ($p in $all) {
        $ops = @($p.phases.$ph)
        foreach ($c in @($ops | ForEach-Object { "$($_.cmd)" } | Select-Object -Unique)) { if (-not $byCmd[$c]) { $byCmd[$c] = New-Object System.Collections.Generic.List[object] }; $byCmd[$c].Add($p) }
    }
    $phaseOps[$ph] = @($byCmd.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending | Select-Object -First 25 | ForEach-Object {
        $cmd = $_.Key
        $shapes = @{}
        foreach ($p in $_.Value) { foreach ($o in @($p.phases.$ph | Where-Object { "$($_.cmd)" -eq $cmd })) { $s = Get-Shape "$($o.target)"; if ($s) { $shapes[$s] = 1 + [int]$shapes[$s] } } }
        [ordered]@{ command = $cmd; packages = $_.Value.Count; share = (& $pct $_.Value.Count)
                    commonTargets = @($shapes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object { "$($_.Key)  (x$($_.Value))" })
                    example = @($_.Value | Select-Object -First 1 | ForEach-Object { $pk = $_; "$($pk.package): $(@($pk.phases.$ph | Where-Object { "$($_.cmd)" -eq $cmd })[0].line)" }) } })
}
$count = { param($sb) @($all | Where-Object $sb).Count }
$patterns = [ordered]@{
    generated = (Get-Date -Format 's'); libraries = $roots; packages = $all.Count
    whatThisIs = 'How this team packages, measured across every shipped package: what each phase does, how often, on what, with a real example. Evidence of practice, not rules - the order and the machine decide for any one package.'
    templates = [ordered]@{ psadtV4 = (& $count { $_.psadt -eq 'v4' }); psadtV3 = (& $count { $_.psadt -eq 'v3' }) }
    installers = [ordered]@{ msi = (& $count { $_.installerType -eq 'MSI' }); exe = (& $count { $_.installerType -eq 'EXE' }); other = (& $count { $_.installerType -notin 'MSI', 'EXE' }); multiInstaller = (& $count { [bool]$_.multi }); withTransform = (& $count { "$($_.transform)".Trim() }); withResponseFile = (& $count { @($_.responseFiles).Count }); withSupportFiles = (& $count { @($_.supportFiles).Count }) }
    aboutPreviousVersionRemoval = 'generic = removed by name/folder/service whatever the version; version-pinned = a block naming one version or product code; none = nothing in pre-install (an MSI major upgrade or the vendor installer does it); other = something else in pre-install'
    previousVersionRemoval = [ordered]@{ generic = (& $count { $_.previousVersionRemoval -eq 'generic' }); versionPinned = (& $count { $_.previousVersionRemoval -eq 'version-pinned' }); other = (& $count { $_.previousVersionRemoval -eq 'other' }); none = (& $count { $_.previousVersionRemoval -eq 'none' }) }
    perUserConfiguration = [ordered]@{ activeSetup = (& $count { @($_.perUser) -match 'Active Setup' }); allUsersRegistry = (& $count { @($_.perUser) -contains 'all-users registry' }); none = (& $count { -not @($_.perUser).Count }) }
    updaterHandledInScript = (& $count { @($_.updater).Count })
    desktopShortcutHandled = (& $count { @($_.shortcuts).Count })
    rebootHandled = (& $count { @($_.reboot).Count })
    evaluationArtefacts = [ordered]@{ evaluationDocument = (& $count { @($_.documents.evaluationDoc).Count }); ownerForm = (& $count { @($_.documents.ownerForm).Count }); mrf = (& $count { $_.documents.mrf }); complexityMatrix = (& $count { $_.documents.complexity }); sourceValidationReport = (& $count { $_.documents.sourceValidation }); testLogs = (& $count { @($_.documents.testLogs).Count }); withQueryMails = (& $count { @($_.documents.queryMails).Count }) }
    whatEachPhaseDoes = $phaseOps
    howUpdatersWereSwitchedOff = @(@($all | ForEach-Object { $pk = $_; @($_.updater) | ForEach-Object { [pscustomobject]@{ s = (Get-Shape $_); pkg = $pk.package; line = $_ } } }) | Group-Object s | Sort-Object Count -Descending | Select-Object -First 30 | ForEach-Object { "$($_.Count)x  $($_.Group[0].line)   e.g. $($_.Group[0].pkg)" })
    howShortcutsWereHandled = @(@($all | ForEach-Object { $pk = $_; @($_.shortcuts) | ForEach-Object { [pscustomobject]@{ s = (Get-Shape ($_ -replace '[^\\]+\.lnk', '<name>.lnk')); pkg = $pk.package; line = $_ } } }) | Group-Object s | Sort-Object Count -Descending | Select-Object -First 12 | ForEach-Object { "$($_.Count)x  $($_.Group[0].line)" })
    howRebootsWereHandled = @(@($all | ForEach-Object { @($_.reboot) }) | ForEach-Object { Get-Shape $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { "$($_.Count)x  $($_.Name)" })
    detectionShapes = @(@($all | ForEach-Object { Get-Shape (("$($_.detection)" -replace $([regex]::Escape("$($_.package)")), '<package>')) }) | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object { "$($_.Count)x  $($_.Name)" })
}
$vendors = [ordered]@{}
foreach ($g in @($all | Group-Object vendor | Where-Object { "$($_.Name)".Trim() } | Sort-Object Count -Descending)) {
    $ps = @($g.Group)
    $vendors[$g.Name] = [ordered]@{
        packages = $ps.Count; applications = @($ps | ForEach-Object { $_.app } | Select-Object -Unique | Select-Object -First 25)
        installers = @($ps | Group-Object installerType | ForEach-Object { "$($_.Name) x$($_.Count)" })
        previousVersionRemoval = @($ps | Group-Object previousVersionRemoval | ForEach-Object { "$($_.Name) x$($_.Count)" })
        perUser = @($ps | ForEach-Object { @($_.perUser) } | Group-Object | ForEach-Object { "$($_.Name) x$($_.Count)" })
        postInstallPractice = @($ps | ForEach-Object { @($_.phases.PostInstall) | ForEach-Object { "$($_.cmd) $(Get-Shape "$($_.target)")".Trim() } } | Group-Object | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { "$($_.Name)  (x$($_.Count))" })
        updater = @($ps | ForEach-Object { @($_.updater) } | Select-Object -Unique -First 6)
        authorNotes = @($ps | ForEach-Object { $pk = $_.package; @($_.authorNotes) | ForEach-Object { "$_  [$pk]" } } | Select-Object -First 12)
        packagesList = @($ps | Select-Object -First 30 | ForEach-Object { $_.package })
    }
}
$lessons = @($all | ForEach-Object { $pk = $_; @($_.authorNotes) | Where-Object { $_ -match $issueWords } | ForEach-Object { [ordered]@{ note = $_; package = $pk.package; vendor = $pk.vendor } } })
Write-Host "consolidated: $($phaseOps.Count) phases, $($vendors.Count) vendors, $(@($lessons).Count) author lessons" -ForegroundColor Green

$write = { param($name, $obj) $path = Join-Path $OutDir $name; [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 12 -Compress), (New-Object Text.UTF8Encoding $false)); Write-Host "  -> $path ($([math]::Round((Get-Item $path).Length / 1KB)) KB)" }
# A small INDEX to search, and the full profiles one file per vendor - so the agent loads a few KB to find the right
# packages and then only the vendors it needs, instead of the whole library at every order.
$compact = { param($p)
    $o = [ordered]@{}
    foreach ($prop in $p.PSObject.Properties) { $o[$prop.Name] = $prop.Value }
    if ($o.phases) { $ph = [ordered]@{}; foreach ($k in $o.phases.PSObject.Properties) { $ph[$k.Name] = @(@($k.Value) | Select-Object -First 15 | ForEach-Object { [ordered]@{ cmd = $_.cmd; line = (Get-Cut "$($_.line)" 170) } }) }; $o.phases = $ph }
    $o.files = @(@($o.files) | Select-Object -First 20)
    $o.authorNotes = @(@($o.authorNotes) | Select-Object -First 10)
    if ($o.documents -and $o.documents.whatTheyRecorded) { $w = [ordered]@{}; foreach ($k in @($o.documents.whatTheyRecorded.PSObject.Properties | Select-Object -First 2)) { $w[$k.Name] = (Get-Cut "$($k.Value)" 1500) }; $o.documents.whatTheyRecorded = $w }
    return $o }
$pkDir = Join-Path $OutDir 'Packages'
if (Test-Path $pkDir) { Remove-Item $pkDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $pkDir | Out-Null
$index = New-Object System.Collections.Generic.List[object]
foreach ($g in @($all | Group-Object { if ("$($_.vendor)".Trim()) { "$($_.vendor)" } else { '_unparsed' } })) {
    $file = (($g.Name -replace '[^\w.-]', '_') + '.json')
    $rows = @($g.Group | ForEach-Object { & $compact $_ })
    [IO.File]::WriteAllText((Join-Path $pkDir $file), ($(if ($rows.Count -eq 1) { '[' + ($rows[0] | ConvertTo-Json -Depth 12 -Compress) + ']' } else { $rows | ConvertTo-Json -Depth 12 -Compress })), (New-Object Text.UTF8Encoding $false))
    foreach ($p in $g.Group) { $index.Add([ordered]@{ package = $p.package; vendor = $p.vendor; app = $p.app; version = $p.version; arch = $p.arch; psadt = $p.psadt; installerType = $p.installerType; multi = $p.multi; library = $p.library; written = $p.written; file = $file }) }
}
Write-Host "  -> $pkDir ($(@(Get-ChildItem $pkDir).Count) vendor file(s), $([math]::Round((Get-ChildItem $pkDir | Measure-Object Length -Sum).Sum / 1MB, 1)) MB)"
& $write 'Index.json' @($index.ToArray())
& $write 'Patterns.json' $patterns
& $write 'Vendors.json' $vendors
& $write 'Lessons.json' @($lessons)
