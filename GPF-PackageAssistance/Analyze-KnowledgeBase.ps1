<#
.SYNOPSIS
  Mines the live package library (read-only) into a structured Knowledge Base that the tool can use to
  auto-suggest silent switches, detection formats, auto-update suppression and customizations per vendor.

.DESCRIPTION
  Walks every package folder, reads its PSADT script (v3 Deploy-Application.ps1 or v4
  Invoke-AppDeployToolkit.ps1) and extracts, per package:
    - identity (vendor/app/arch/version/lang, template version)
    - installer type + the actual install / uninstall command lines and SILENT SWITCHES
    - detection / branding key patterns + uninstall-registry references + MSI product codes
    - AUTO-UPDATE suppression artifacts (scheduled-task removal, update services, update policies/configs)
    - the cmdlets/functions used (frequency) and notable customization blocks
  Then aggregates into per-vendor and global recommendation tables.

  READ-ONLY: the script only reads from the repo. It never writes to, moves or modifies the library.

.EXAMPLE
  # quick test on 25 packages
  .\Analyze-KnowledgeBase.ps1 -Limit 25

  # full run (the default live repo) - REPLACES the KB
  .\Analyze-KnowledgeBase.ps1

  # EXPAND the KB: mine another brand's repo and ADD it to what's already there (accumulate over time)
  .\Analyze-KnowledgeBase.ps1 -RepoPath '\\otherbrand\share\Apps' -Merge

  # combine several repos in ONE run (note: invoke directly / with the call operator, NOT powershell.exe -File,
  # so the array binds)
  .\Analyze-KnowledgeBase.ps1 -RepoPath '\\liveshare\Apps','\\eqs\Outgoing','\\team2\Apps'
#>
[CmdletBinding()]
param(
    [string[]]$RepoPath = @('\\mbddfsovpc01.mn-man.biz\SWDLive-Gate\CMLib_LIVE\Apps'),  # ONE or MANY repos
    [string]$OutFile,               # default resolved below (param-default context can't see the script path)
    [int]$Limit       = 0,          # 0 = all packages
    [switch]$Merge,                 # ACCUMULATE: fold the new repo(s) into the existing KnowledgeBase.json (keep prior brands)
    [string[]]$BrandPrefixes = @('INA','VWG','G1V','MAN','MTB','VWFS','PON','G3P'),  # folder-name brand prefixes to strip so the REAL vendor is recorded (the script's own AppVendor still wins over the folder)
    [switch]$NoSummary              # skip the human-readable .md summary
)

# Resolve the default output location in the BODY: $MyInvocation.MyCommand.Path is $null inside a param
# default when launched via -File, which is what threw "Split-Path ... Path is null".
if (-not $OutFile) {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $OutFile = Join-Path $scriptDir 'KnowledgeBase.json'
}
# Normalised set of brand prefixes to strip from folder names (case-insensitive).
$script:BrandPrefixSet = @{}
foreach ($bp in @($BrandPrefixes)) { if ("$bp".Trim()) { $script:BrandPrefixSet["$bp".Trim().ToUpper()] = $true } }

# ---------- helpers (self-contained: the analyzer can run independently of the tool) ----------
# Other brands prefix the package FOLDER with a brand code (INA_/VWG_/G1V_/...). Drop a leading "<PREFIX>_" so the
# real vendor is parsed from the folder (the script's own AppVendor is still preferred over this). Only strips a token
# in the known-prefix set, so a legitimate first token (a real vendor) is never removed.
function Strip-BrandPrefix {
    param([string]$Name)
    $m = [regex]::Match($Name, '^(?<pfx>[A-Za-z0-9]{2,5})_(?<rest>.+)$')
    if ($m.Success -and $script:BrandPrefixSet.ContainsKey($m.Groups['pfx'].Value.ToUpper())) { return $m.Groups['rest'].Value }
    return $Name
}
function Parse-Name {
    param([string]$Name)
    $p = '^(?<Vendor>[^_]+)_(?<App>.+)_(?<Arch>x86|x64|x86_64|ALL)_(?<Ver>[^_]+)-(?<Rel>\d{4})_(?<Lang>[\w\-]+)$'
    if ($Name -match $p) { return [ordered]@{ Vendor=$Matches.Vendor; App=$Matches.App; Arch=$Matches.Arch; Version=$Matches.Ver; Release=$Matches.Rel; Lang=$Matches.Lang; Matched=$true } }
    return [ordered]@{ Vendor=($Name -split '_')[0]; App=$Name; Arch=''; Version=''; Release=''; Lang=''; Matched=$false }
}
# Identity straight from the PSADT script ($adtSession in v4, $appVendor/$appName/... in v3). The folder name is
# only a CONVENIENCE; the script is the authoritative source - so a repo whose folders don't follow our naming
# still gets the right Vendor/App/Version. Returns blanks for whatever isn't present.
function Get-ScriptIdentity {
    param([string]$Text)
    $g = { param($field) $pat = '(?im)\$?app' + $field + '\s*=\s*[''"]([^''"]+)[''"]'; $m = [regex]::Match($Text, $pat); if ($m.Success) { $m.Groups[1].Value.Trim() } else { '' } }
    return [ordered]@{
        Vendor  = (& $g 'Vendor')
        App     = (& $g 'Name')
        Version = (& $g 'Version')
        Arch    = (& $g 'Arch')
        Lang    = (& $g 'Lang')
    }
}
function Read-Text { param([string]$Path) try { return [IO.File]::ReadAllText($Path) } catch { return $null } }

# Extract the argument string from a command body. Handles: a quoted LITERAL, OR a $variable reference
# resolved to its first literal assignment elsewhere in the script (many packages do
# "$p = '/NCRC /S ...'" then "-ArgumentList $p" - the literal-only regex returned nothing/partial, which
# is why Wireshark stored only "/S"). Best-effort; returns '' if it can't resolve.
# Strip outer quotes from a captured token and un-escape backtick-quotes (`" -> ").
function Unwrap-ArgToken {
    param([string]$s)
    if (-not $s) { return '' }
    if ($s.Length -ge 2 -and (($s[0] -eq '"' -and $s[$s.Length-1] -eq '"') -or ($s[0] -eq "'" -and $s[$s.Length-1] -eq "'"))) { $s = $s.Substring(1, $s.Length-2) }
    return ($s -replace '`"', '"').TrimEnd('`',' ')
}
function Resolve-ArgString {
    param([string]$Body, [string]$FullText)
    # The arg token after -Parameters/-ArgumentList/-AddParameters: a double-quoted string (allowing backtick-
    # escaped quotes inside), a single-quoted string, or a bare $Var.
    $am = [regex]::Match($Body, '(?i)-(?:Parameters|ArgumentList|AddParameters)\s+(?<tok>"(?:`.|[^"])*"|''[^'']*''|\$\w+)')
    if (-not $am.Success) { return '' }
    $tok = $am.Groups['tok'].Value.Trim()
    # A token that is ONLY a variable reference (bare $Var or "$Var") -> resolve its assignment, again allowing
    # backtick-escaped quotes in the value (this is why GTSuite's 12-arg $Parameters was truncated to one arg).
    $vm = [regex]::Match($tok, '^["'']?\$(\w+)["'']?$')
    if ($vm.Success) {
        $pat = '(?im)^\s*\$' + [regex]::Escape($vm.Groups[1].Value) + '\s*=\s*(?<val>"(?:`.|[^"])*"|''[^'']*'')'
        $asn = [regex]::Match($FullText, $pat)
        if ($asn.Success) { return (Unwrap-ArgToken $asn.Groups['val'].Value) }
        return ''
    }
    return (Unwrap-ArgToken $tok)
}

# Pull the install / uninstall installer commands + their argument strings (v3 + v4 cmdlet names).
function Get-InstallerCalls {
    param([string]$Text)
    $calls = @()
    # PSADT wraps long commands with a trailing backtick + newline. Join those into one logical line first,
    # so multi-line install/uninstall arguments are captured WHOLE (not truncated at the first newline).
    $Text = [regex]::Replace($Text, '`[ \t]*\r?\n[ \t]*', ' ')
    $full = $Text
    # MSI:  Execute-MSI / Start-ADTMsiProcess  -Action <x> ... (-Parameters|-ArgumentList|-AddParameters) "<args>"
    foreach ($m in [regex]::Matches($Text, '(?is)\b(Execute-MSI|Start-ADTMsiProcess)\b(?<body>.*?)(?=\r?\n)')) {
        $b = $m.Groups['body'].Value
        $act = ([regex]::Match($b, "(?i)-Action\s+['""]?(?<a>Install|Uninstall|Repair|Patch)")).Groups['a'].Value
        $arg = Resolve-ArgString -Body $b -FullText $full
        $calls += [pscustomobject]@{ Kind='MSI'; Action=$act; Args=$arg }
    }
    # EXE:  Execute-Process / Start-ADTProcess  -Path|-FilePath "<exe>" ... (-Parameters|-ArgumentList) "<args>"
    foreach ($m in [regex]::Matches($Text, '(?is)\b(Execute-Process|Start-ADTProcess)\b(?<body>.*?)(?=\r?\n)')) {
        $b = $m.Groups['body'].Value
        $exe = ([regex]::Match($b, "(?i)-(?:Path|FilePath)\s+['""](?<e>[^'""]*?\.exe)['""]")).Groups['e'].Value
        if (-not $exe) { continue }
        if ($exe -match '(?i)schtasks|reg\.exe|cmd\.exe|powershell|msiexec') { continue }   # not the app installer
        $arg = Resolve-ArgString -Body $b -FullText $full
        $calls += [pscustomobject]@{ Kind='EXE'; Action=''; Args=$arg; Exe=[IO.Path]::GetFileName($exe) }
    }
    return ,$calls
}

# Identify the installer ENGINE of an EXE from a known silent-switch fingerprint (helps the sandbox later).
# NOTE: param is $Switches, NOT $Args - $Args is a reserved PowerShell automatic variable and would never bind.
function Get-ExeEngine {
    param([string]$Switches)
    switch -Regex ($Switches) {
        '(?i)/VERYSILENT|/SUPPRESSMSGBOXES|/SP-'      { 'InnoSetup'; break }
        '(?i)/s\s+/v|/clone_wait|ISSetup|-record|\.iss' { 'InstallShield'; break }
        '(?i)(^|\s)/S(\s|$)|/NCRC'                    { 'NSIS'; break }
        '(?i)-ms\b'                                    { 'Mozilla'; break }
        '(?i)/noGui|/userSettings|-inputFile|-i\s+silent|-silent' { 'vendor-custom'; break }
        '(?i)/quiet|/passive|--quiet|/install'        { 'Burn/WiX/other'; break }
        default { if ("$Switches".Trim()) { 'unknown-args' } else { 'no-args' } }
    }
}

# Auto-update suppression artifacts (the "standard" the team applies). Returns the recipes detected.
function Get-AutoUpdateRecipes {
    param([string]$Text)
    $r = New-Object System.Collections.Generic.List[string]
    if ($Text -match '(?i)(Unregister-ScheduledTask|schtasks(\.exe)?\s+/delete|Get-ScheduledTask)') { $r.Add('scheduled-task') }
    if ($Text -match '(?i)(GoogleUpdate|gupdate|AdobeARM|AdobeAAMUpdater|mozilla\s+maintenance|FirefoxDefaultBrowserAgent|Default Browser Agent)') { $r.Add('vendor-updater-service/task') }
    if ($Text -match '(?i)(mozilla\.cfg|policies\.json|app\.update\.enabled|DisableAppUpdate|autoupdate\s*=\s*0|"?AutoUpdate"?\s*=\s*0|NoUpdate|update.*disabled)') { $r.Add('update-policy/config') }
    if ($Text -match '(?i)(Set-Service|sc(\.exe)?\s+config).{0,40}(update|gupdate|adobearm)') { $r.Add('disable-update-service') }
    if ($Text -match '(?i)Stop-ADTServiceAndDependencies|Stop-Service.{0,40}update') { $r.Add('stop-update-service') }
    return @($r | Select-Object -Unique)
}

# Branding / detection facts.
function Get-DetectionFacts {
    param([string]$Text)
    [pscustomobject]@{
        UsesBrandingKey = [bool]($Text -match '(?i)SOFTWARE\\VWG\\CM\\|Set-MTBDetectionKey|Set-MTBBranding')
        UninstallKeyRef = [bool]($Text -match '(?i)\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\')
        Wow6432         = [bool]($Text -match '(?i)WOW6432Node')
        ProductCode     = ([regex]::Match($Text, '\{[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}')).Value
    }
}

# Top custom helper/cmdlet calls (excludes the most generic PSADT verbs to surface the INTERESTING ones).
function Get-NotableCmdlets {
    param([string]$Text)
    $skip = 'Write-Log|Write-ADTLogEntry|Show-InstallationWelcome|Show-InstallationProgress|Show-ADTInstallationWelcome|Close-ADTSession|Exit-Script'
    $hits = @{}
    foreach ($m in [regex]::Matches($Text, '\b([A-Z][a-zA-Z]+-[A-Z][a-zA-Z]+)\b')) {
        $c = $m.Groups[1].Value
        if ($c -match $skip) { continue }
        $hits[$c] = ($hits[$c] + 1)
    }
    return $hits
}

# ---------- per-package extraction ----------
function Get-PackageFacts {
    param([string]$Dir)
    $name = Split-Path $Dir -Leaf
    $content = Join-Path $Dir 'Content'
    $v4 = Join-Path $content 'Invoke-AppDeployToolkit.ps1'
    $v3 = Join-Path $content 'Deploy-Application.ps1'
    $scriptPath = if (Test-Path $v4) { $v4 } elseif (Test-Path $v3) { $v3 } else {
        # script may sit a level deeper
        $f = Get-ChildItem -LiteralPath $content -Recurse -Include 'Invoke-AppDeployToolkit.ps1','Deploy-Application.ps1' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { $f.FullName } else { $null }
    }
    if (-not $scriptPath) { return $null }
    $text = Read-Text $scriptPath
    if (-not $text) { return $null }

    # Identity: parse the folder name AFTER stripping any brand prefix (INA_/VWG_/G1V_...), THEN let the SCRIPT's own
    # $adtSession/$app* fields OVERRIDE - the script is authoritative (it holds the real vendor "Tenable", never the
    # brand code "INA"), works for v3 ($appVendor='..') and v4 (AppVendor='..' in the $adtSession hashtable), and is
    # robust to template/custom differences. The (prefix-stripped) folder only fills what the script doesn't declare.
    $id  = Parse-Name (Strip-BrandPrefix $name)
    $sid = Get-ScriptIdentity -Text $text
    if ($sid.Vendor)  { $id.Vendor  = $sid.Vendor }
    if ($sid.App)     { $id.App     = $sid.App }
    if ($sid.Version) { $id.Version = $sid.Version }
    if ($sid.Arch)    { $id.Arch    = $sid.Arch }
    if ($sid.Lang)    { $id.Lang    = $sid.Lang }
    $tmpl = if ($scriptPath -match 'Invoke-AppDeployToolkit') { 'v4' } else { 'v3' }
    $installerFiles = @()
    $filesDir = Join-Path $content 'Files'
    if (Test-Path $filesDir) {
        $installerFiles = @(Get-ChildItem -LiteralPath $filesDir -Recurse -Include *.msi,*.exe,*.msp -ErrorAction SilentlyContinue |
                            Select-Object -First 6 | ForEach-Object { $_.Name })
    }
    $calls = Get-InstallerCalls -Text $text
    $inst  = @($calls | Where-Object { $_.Kind -eq 'MSI' -and $_.Action -eq 'Install' }) + @($calls | Where-Object { $_.Kind -eq 'EXE' })
    $instMsi = @($calls | Where-Object { $_.Kind -eq 'MSI' -and $_.Action -eq 'Install' } | Select-Object -First 1)
    $unin    = @($calls | Where-Object { $_.Kind -eq 'MSI' -and $_.Action -eq 'Uninstall' } | Select-Object -First 1)
    # Prefer the EXE call whose filename matches the APP name (the real product installer), not the FIRST
    # exe (often a prerequisite like Npcap with bare /S). This is why Wireshark recorded "/S" instead of the
    # real "/NCRC /S /desktopicon=no /quicklaunchicon=no" - the prerequisite's call won. Also prefer the call
    # that actually HAS args over an argless one.
    $exeCalls = @($calls | Where-Object { $_.Kind -eq 'EXE' })
    # UNINSTALLER exe calls (Uninstall_X.exe, uninsNNN.exe) must NOT be picked as the install command - and they
    # ALSO must not win the app-name match (e.g. "Uninstall_GT-SUITE.exe" contains "gtsuite", which is why GTSuite
    # recorded the uninstall's "--mode unattended" as its install args). Split them out.
    $exeUninst = @($exeCalls | Where-Object { $_.Exe -match '(?i)uninstall|unins\d|\buninst\b' })
    $exeInst   = @($exeCalls | Where-Object { $_.Exe -notmatch '(?i)uninstall|unins\d|\buninst\b' })
    $appTok = ([regex]::Replace("$($id.App)", '[^A-Za-z0-9]', '')).ToLower()
    $instExe = $null
    if ($appTok) { $instExe = @($exeInst | Where-Object { ([regex]::Replace("$($_.Exe)", '[^A-Za-z0-9]', '')).ToLower() -like "*$appTok*" -and "$($_.Args)".Trim() } | Select-Object -First 1) }
    if (-not $instExe) { $instExe = @($exeInst | Where-Object { ([regex]::Replace("$($_.Exe)", '[^A-Za-z0-9]', '')).ToLower() -like "*$appTok*" } | Select-Object -First 1) }
    if (-not $instExe) { $instExe = @($exeInst | Where-Object { "$($_.Args)".Trim() } | Select-Object -First 1) }
    if (-not $instExe) { $instExe = @($exeInst | Select-Object -First 1) }
    if (-not $instExe) { $instExe = @($exeCalls | Where-Object { "$($_.Args)".Trim() } | Select-Object -First 1) }   # last resort

    $type = if ($instMsi) { 'MSI' } elseif ($instExe) { 'EXE' } elseif ($installerFiles | Where-Object { $_ -match '\.msi$' }) { 'MSI' } elseif ($installerFiles) { 'EXE' } else { 'Unknown' }
    $instArgs = if ($instMsi) { $instMsi.Args } elseif ($instExe) { $instExe.Args } else { '' }
    # uninstall args AND uninstaller EXE: MSI uninstall first (msiexec /x ProductCode), else the EXE uninstaller
    # (e.g. unins000.exe / Uninstall_GT-SUITE.exe --mode unattended). The uninstaller exe DIFFERS from the install
    # exe, so we record it separately - the live tool surfaces "which exe did the uninstall".
    $uninArgs = ''; $uninExe = ''
    if ($unin) { $uninArgs = $unin.Args; $uninExe = 'msiexec /x {ProductCode}' }
    elseif ($exeUninst.Count) {
        $eu = @($exeUninst | Where-Object { ([regex]::Replace("$($_.Exe)", '[^A-Za-z0-9]', '')).ToLower() -like "*$appTok*" -and "$($_.Args)".Trim() } | Select-Object -First 1)
        if (-not $eu) { $eu = @($exeUninst | Where-Object { "$($_.Args)".Trim() } | Select-Object -First 1) }
        if (-not $eu) { $eu = @($exeUninst | Select-Object -First 1) }   # the exe even if no args were captured
        if ($eu) { $uninArgs = $eu.Args; $uninExe = $eu.Exe }
    }
    # Capture the EXE install args SEPARATELY. Multi-installer packages (e.g. Wireshark = Npcap.msi +
    # Wireshark.exe) classify as MSI, which dropped the EXE's rich switches ("/NCRC /S /desktopicon=no ...").
    # Storing them lets the live tool suggest the real EXE switches when the user installs the EXE.
    $exeArgs = if ($instExe) { $instExe.Args } else { '' }
    $exeEng  = if ($instExe) { Get-ExeEngine -Switches $exeArgs } elseif ($type -eq 'EXE') { Get-ExeEngine -Switches $instArgs } else { 'MSI' }

    [pscustomobject]@{
        Name        = $name
        Vendor      = $id.Vendor
        App         = $id.App
        Version     = $id.Version
        Lang        = $id.Lang
        Template    = $tmpl
        InstallerType = $type
        ExeEngine   = $exeEng
        ExeArgs     = $exeArgs
        PrimaryExe  = "$(if ($instExe) { $instExe.Exe } else { '' })"
        InstallArgs = $instArgs
        UninstallArgs = $uninArgs
        UninstallExe = $uninExe
        InstallerFiles = $installerFiles
        AutoUpdate  = Get-AutoUpdateRecipes -Text $text
        Detection   = Get-DetectionFacts -Text $text
        Cmdlets     = Get-NotableCmdlets -Text $text
        LineCount   = ($text -split "\r?\n").Count
    }
}

# ---------- main ----------
$facts = New-Object System.Collections.Generic.List[object]
$minedNames = New-Object 'System.Collections.Generic.HashSet[string]'
$sw = [Diagnostics.Stopwatch]::StartNew()
$reposDone = New-Object System.Collections.Generic.List[string]
foreach ($repo in @($RepoPath)) {
    if (-not (Test-Path $repo)) { Write-Host "Repo not reachable (skipped): $repo" -ForegroundColor Yellow; continue }
    $dirs = @(Get-ChildItem -LiteralPath $repo -Directory -ErrorAction SilentlyContinue)
    if ($Limit -gt 0) { $dirs = $dirs | Select-Object -First $Limit }
    Write-Host "Analyzing $($dirs.Count) package(s) from $repo ..." -ForegroundColor Cyan
    $n = 0
    foreach ($d in $dirs) {
        $n++
        if ($n % 25 -eq 0 -or $n -eq $dirs.Count) { Write-Progress -Activity "Mining $repo" -Status "$n / $($dirs.Count)  ($($d.Name))" -PercentComplete ([int](100*$n/[Math]::Max(1,$dirs.Count))) }
        try { $f = Get-PackageFacts -Dir $d.FullName; if ($f) { $facts.Add($f); [void]$minedNames.Add("$($f.Name)") } } catch {}
    }
    Write-Progress -Activity "Mining $repo" -Completed
    $reposDone.Add($repo)
}
if ($reposDone.Count -eq 0) { Write-Host "No reachable repo - nothing mined." -ForegroundColor Red; return }
# MERGE: fold in packages already in the existing KnowledgeBase.json (accumulate across runs / other brands).
# Freshly-mined records WIN for a package of the same name; every other prior package is carried forward, so the
# KB grows instead of being replaced. A newer VERSION of an app (different package name) is simply added and the
# 'newest version' aggregation picks it automatically.
$carried = 0
if ($Merge -and (Test-Path $OutFile)) {
    try {
        $prior = (Get-Content $OutFile -Raw | ConvertFrom-Json).packages
        foreach ($p in @($prior)) { if ($p -and "$($p.Name)".Trim() -and -not $minedNames.Contains("$($p.Name)")) { $facts.Add($p); $carried++ } }
        Write-Host "Merge: carried $carried prior package(s) forward from $OutFile" -ForegroundColor Cyan
    } catch { Write-Host "Merge: could not read prior KB ($($_.Exception.Message)) - building fresh from the new repo(s)." -ForegroundColor Yellow }
}
$sw.Stop()
Write-Host ("Knowledge base: {0} package(s) total ({1} newly mined from {2} repo(s), {3} carried forward) in {4}s." -f $facts.Count, $minedNames.Count, $reposDone.Count, $carried, [math]::Round($sw.Elapsed.TotalSeconds,1)) -ForegroundColor Green

# ---- aggregate: per-vendor recommendations + global stats ----
function TopOf { param($items) ($items | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { [ordered]@{ value=$_.Name; count=$_.Count } }) }

$vendors = @{}
foreach ($g in ($facts | Group-Object Vendor)) {
    $items = @($g.Group)
    $vendors[$g.Name] = [ordered]@{
        packages        = $items.Count
        installerTypes  = TopOf ($items.InstallerType)
        exeEngines      = TopOf ($items | Where-Object { $_.InstallerType -eq 'EXE' } | ForEach-Object { $_.ExeEngine })
        topInstallArgs  = TopOf ($items.InstallArgs)
        topUninstallArgs= TopOf ($items.UninstallArgs)
        autoUpdate      = TopOf ($items.AutoUpdate)
        usesBrandingKey = @($items | Where-Object { $_.Detection.UsesBrandingKey }).Count
        wow6432         = @($items | Where-Object { $_.Detection.Wow6432 }).Count
        examplePackages = @($items | Select-Object -First 3 | ForEach-Object { $_.Name })
    }
}

$allCmdlets = @{}
foreach ($f in $facts) {
    $cm = $f.Cmdlets; if (-not $cm) { continue }
    if ($cm -is [hashtable]) { foreach ($k in $cm.Keys) { $allCmdlets[$k] = ($allCmdlets[$k] + $cm[$k]) } }   # freshly mined
    else { foreach ($pr in $cm.PSObject.Properties) { $allCmdlets[$pr.Name] = ($allCmdlets[$pr.Name] + $pr.Value) } }  # merged from JSON
}
$topCmdlets = $allCmdlets.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 40 | ForEach-Object { [ordered]@{ cmdlet=$_.Key; total=$_.Value } }

$kb = [ordered]@{
    generated     = (Get-Date).ToString('s')
    repo          = (@($reposDone) -join '; ')
    repos         = @($reposDone)
    packageCount  = $facts.Count
    templateSplit = [ordered]@{ v3 = @($facts | Where-Object Template -eq 'v3').Count; v4 = @($facts | Where-Object Template -eq 'v4').Count }
    installerTypes= TopOf ($facts.InstallerType)
    exeEngines    = TopOf ($facts | Where-Object InstallerType -eq 'EXE' | ForEach-Object { $_.ExeEngine })
    autoUpdate    = TopOf ($facts.AutoUpdate)
    topCmdlets    = $topCmdlets
    vendors       = $vendors
    packages      = $facts
}
$kb | ConvertTo-Json -Depth 8 | Out-File $OutFile -Encoding utf8
Write-Host "Knowledge base -> $OutFile ($([math]::Round((Get-Item $OutFile).Length/1KB)) KB)" -ForegroundColor Green

# ---- SLIM RECOMMENDATION INDEX (what the tool loads at runtime: small + fast) ----
# Per vendor+app: the NEWEST package's actual switches (exact-match = highest confidence). Per vendor:
# the most common switches (fallback). Engine fallback for brand-new apps is computed live by the tool.
function NewestByVersion { param($items) ($items | Sort-Object { try { [version](($_.Version) -replace '[^0-9.]','') } catch { [version]'0.0' } } -Descending | Select-Object -First 1) }
$byApp = [ordered]@{}
foreach ($g in ($facts | Group-Object { "$($_.Vendor)|$($_.App)" })) {
    $newest = NewestByVersion $g.Group
    # exeInstall: the EXE switches from ANY package in this app group (newest first) - so a multi-installer
    # package's EXE args (e.g. Wireshark "/NCRC /S /desktopicon=no ...") are kept even when the package's
    # PRIMARY type is MSI. The live tool prefers this when the user is installing an EXE.
    $exeRec = $g.Group | Sort-Object { try { [version](($_.Version) -replace '[^0-9.]','') } catch { [version]'0.0' } } -Descending | Where-Object { "$($_.ExeArgs)".Trim() } | Select-Object -First 1
    $byApp[$g.Name] = [ordered]@{
        install   = "$($newest.InstallArgs)"; uninstall = "$($newest.UninstallArgs)"; uninstaller = "$($newest.UninstallExe)"
        exeInstall= "$(if($exeRec){$exeRec.ExeArgs}else{''})"; exeEngine = "$(if($exeRec){$exeRec.ExeEngine}else{''})"
        type      = "$($newest.InstallerType)"; engine = "$($newest.ExeEngine)"
        autoUpdate= @($newest.AutoUpdate); fromPackage = "$($newest.Name)"; seen = $g.Count
    }
}
$byVendor = [ordered]@{}
foreach ($g in ($facts | Group-Object Vendor)) {
    $items = @($g.Group)
    $byVendor[$g.Name] = [ordered]@{
        install   = (@($items.InstallArgs   | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name)
        uninstall = (@($items.UninstallArgs | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name)
        uninstaller=(@($items.UninstallExe  | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name)
        autoUpdate= TopOf ($items.AutoUpdate) | ForEach-Object { $_.value }
        seen = $items.Count
    }
}
# STRONGEST match tier: byInstaller, keyed by the FUZZY installer filename (version-stripped) + type. So
# "Wireshark-4.6.5-x64.exe" and "Wireshark-4.4.7-x64.exe" share a key -> "same installer, different version"
# -> reuse that exact recorded command. Adding new packages later (re-mine) just populates more keys.
function Get-InstKey { param([string]$FileName)
    if (-not $FileName) { return '' }
    $n = [IO.Path]::GetFileNameWithoutExtension($FileName).ToLower()
    $n = $n -replace '\d+(\.\d+)+[a-z]*',''      # version tokens: 4.6.5, 140.11.0esr
    $n = $n -replace '[_\-\s]v?\d{2,}',''          # trailing build numbers
    return ($n -replace '[^a-z0-9]','')            # collapse separators -> wiresharkx64
}
# GENERIC names (setup/install/setupx64/...) are ambiguous ACROSS apps, so the installer key is scoped
# "<vendor>::<key>" - a generic 'setup.exe' only matches within the SAME vendor, never cross-app. The live
# lookup tries "<vendor>::<key>" first, then the bare "<key>" only when it's a SPECIFIC (non-generic) name.
$genericKeys = @('setup','install','installer','setupx64','setupx86','installx64','installx86','update','wizard')
$byInstaller = [ordered]@{}
foreach ($fac in $facts) {
    $k = Get-InstKey $fac.PrimaryExe
    if (-not $k -or -not "$($fac.ExeArgs)".Trim()) { continue }
    $ver = try { [version](($fac.Version) -replace '[^0-9.]','') } catch { [version]'0.0' }
    $isGeneric = ($genericKeys -contains $k) -or ($k.Length -lt 5)
    # always store a vendor-scoped key; also store the bare key ONLY for specific (non-generic) names.
    $keys = @("$($fac.Vendor.ToLower())::$k"); if (-not $isGeneric) { $keys += $k }
    foreach ($kk in $keys) {
        if (-not $byInstaller.Contains($kk) -or $ver -gt $byInstaller[$kk]._ver) {
            $byInstaller[$kk] = [ordered]@{ install="$($fac.ExeArgs)"; uninstall="$($fac.UninstallArgs)"; uninstaller="$($fac.UninstallExe)"; type='EXE'; engine=$fac.ExeEngine; vendor=$fac.Vendor; app=$fac.App; fromPackage="$($fac.Name)"; installer="$($fac.PrimaryExe)"; generic=$isGeneric; _ver=$ver }
        }
    }
}
foreach ($k in @($byInstaller.Keys)) { $byInstaller[$k].Remove('_ver') }   # drop the sort-only field
# Derive the recommendation file from -OutFile (KnowledgeBase.json -> KnowledgeBase.Recommend.json), so a custom
# -OutFile gets its OWN index and never clobbers the production KnowledgeBase.Recommend.json the tool loads.
$recFile = Join-Path (Split-Path $OutFile -Parent) ([IO.Path]::GetFileNameWithoutExtension($OutFile) + '.Recommend.json')
([ordered]@{ generated=(Get-Date).ToString('s'); byInstaller=$byInstaller; byVendorApp=$byApp; byVendor=$byVendor }) | ConvertTo-Json -Depth 6 | Out-File $recFile -Encoding utf8
Write-Host "Recommendation index -> $recFile ($([math]::Round((Get-Item $recFile).Length/1KB)) KB)" -ForegroundColor Green

# ---- human-readable summary ----
if (-not $NoSummary) {
    $md = Join-Path (Split-Path $OutFile -Parent) ([IO.Path]::GetFileNameWithoutExtension($OutFile) + '_Summary.md')
    $o = New-Object System.Collections.Generic.List[string]
    $o.Add("# Knowledge Base Summary  ($($facts.Count) packages)")
    $o.Add(""); $o.Add("- Template split: v3 = $($kb.templateSplit.v3), v4 = $($kb.templateSplit.v4)")
    $o.Add("- Installer types: " + (($kb.installerTypes | ForEach-Object { "$($_.value)=$($_.count)" }) -join ', '))
    $o.Add("- EXE engines: " + (($kb.exeEngines | ForEach-Object { "$($_.value)=$($_.count)" }) -join ', '))
    $o.Add("- Auto-update recipes seen: " + (($kb.autoUpdate | ForEach-Object { "$($_.value)=$($_.count)" }) -join ', '))
    $o.Add(""); $o.Add("## Top vendors (by package count)")
    foreach ($v in ($vendors.GetEnumerator() | Sort-Object { $_.Value.packages } -Descending | Select-Object -First 25)) {
        $vv = $v.Value
        $o.Add("- **$($v.Key)** ($($vv.packages)) - types: $(($vv.installerTypes | ForEach-Object { $_.value }) -join '/'); install args e.g. ``$(@($vv.topInstallArgs)[0].value)``; auto-update: $(($vv.autoUpdate | ForEach-Object { $_.value }) -join ',')")
    }
    $o -join "`r`n" | Out-File $md -Encoding utf8
    Write-Host "Summary -> $md" -ForegroundColor Green
}
