##############################################################
# Build-SwitchPriors.ps1  -  what silent switches THIS TEAM has actually made work.
#
#   An MSI is deterministic. An EXE is a research problem, and 76% of our packages involve one. Rather than guess
#   from general knowledge, mine the shipped corpus: every app-installer launch, the arguments that shipped with it,
#   grouped into the switch families that the evidence supports. The agent hands the result to the AI so its
#   candidate list is ranked by what has actually worked here, not by what the internet says.
#
#   .\Build-SwitchPriors.ps1                     read the Outgoing share from engine-settings.json
#   .\Build-SwitchPriors.ps1 -From <share>       read somewhere else
#   -> Knowledge\SwitchPriors.json   (refresh it when the corpus has grown)
##############################################################
[CmdletBinding()]
param([string]$From, [string]$OutFile)

$toolsRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$agentRoot = Split-Path -Parent $toolsRoot
. (Join-Path $agentRoot 'Engine\Core.ps1')
if (-not $From) {
    Initialize-Config (Join-Path $agentRoot 'engine-settings.json')
    $From = Get-Setting 'OutgoingPath'
}
if (-not $From -or -not (Test-Path -LiteralPath $From)) { throw "Shipped-package share not reachable: $From" }
if (-not $OutFile) { $OutFile = Join-Path $agentRoot 'Knowledge\SwitchPriors.json' }

# Launches that are TOOLING, not the application's installer. Counting these as "silent switch evidence" is what
# made the first pass useless: pnputil and schtasks dominate the raw numbers and say nothing about installers.
$tooling = '(?i)^(pnputil|reg|regedit|schtasks|cmd|powershell|pwsh|icacls|takeown|sc|net|netsh|msiexec|robocopy|xcopy|wusa|dism|certutil|rundll32|wscript|cscript|attrib|timeout|taskkill|expand|forfiles|where|whoami)\.exe$'

Write-Host "reading $From ..." -ForegroundColor Cyan
$pkgs = @(Get-ChildItem -LiteralPath $From -Directory -ErrorAction SilentlyContinue)
$rows = New-Object System.Collections.Generic.List[object]
foreach ($p in $pkgs) {
    $s = @(Get-ChildItem -LiteralPath $p.FullName -Filter '*.ps1' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)^(Invoke-AppDeployToolkit|Deploy-Application)\.ps1$' } | Select-Object -First 1)
    if (-not $s) { continue }
    $t = try { [IO.File]::ReadAllText($s.FullName) } catch { '' }
    if (-not $t) { continue }
    foreach ($rx in @('(?is)Start-ADTProcess\b(?<b>.*?)(?=\r?\n\s*(?:[A-Z][\w-]+\s|\}|#|$))',
                      '(?is)Execute-Process\b(?<b>.*?)(?=\r?\n\s*(?:[A-Z][\w-]+\s|\}|#|$))')) {
        foreach ($m in [regex]::Matches($t, $rx)) {
            $b = "$($m.Groups['b'].Value)"
            if ($b -notmatch "(?i)-(?:FilePath|Path)\s+[""']?([^""'\r\n]+?\.exe)[""']?") { continue }
            $file = Split-Path -Leaf $Matches[1]
            if ($file -match $tooling) { continue }
            # an uninstaller is evidence about uninstalling, not installing - keep them apart
            $isUninstall = [bool]($file -match '(?i)uninst|remove' -or $b -match '(?i)-Action\s+.?Uninstall')
            $args = if ($b -match "(?i)-(?:ArgumentList|Parameters|Arguments)\s+[""']([^""']*)[""']") { $Matches[1].Trim() } else { '' }
            if (-not $args) { continue }
            if ($args -match '^\s*`?\s*$') { continue }
            $rows.Add([pscustomobject]@{ Package = $p.Name; Exe = $file; Args = $args; Uninstall = $isUninstall })
        }
    }
}
Write-Host "  $($rows.Count) application-installer launches with arguments (tooling excluded)" -ForegroundColor Green

# Family = the switch technology the arguments imply. Ordered: the most specific test first.
$family = {
    param($a)
    $x = " $a "
    if ($x -match '(?i)/VERYSILENT|/SUPPRESSMSGBOXES|/SP-|/LOADINF') { return 'InnoSetup' }
    if ($x -match '(?i)/s\s*/v|/v"?\s*/qn|/f1|\.iss\b|ISSetupPrerequisites') { return 'InstallShield' }
    if ($x -match '(?i)/quiet|/passive|/norestart') { return 'Burn-WiX-or-Microsoft' }
    if ($x -match '(?i)(^|\s)/S(\s|$)|/AllUsers') { return 'NSIS' }
    if ($x -match '(?i)--silent|--quiet|--install|--noreboot|--accept') { return 'unix-style-double-dash' }
    if ($x -match '(?i)(^|\s)-q(\s|$)|(^|\s)-s(\s|$)|-i\s+silent') { return 'unix-style-single-dash' }
    if ($x -match '(?i)/qn|/qb') { return 'MSI-style' }
    return 'vendor-specific'
}
$install = @($rows | Where-Object { -not $_.Uninstall })
$byFamily = @($install | Group-Object { & $family $_.Args } | Sort-Object Count -Descending)

$out = [ordered]@{
    generated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    source = "$From"
    packagesScanned = $pkgs.Count
    installLaunches = $install.Count
    families = @($byFamily | ForEach-Object {
            $args = @($_.Group | Group-Object Args | Sort-Object Count -Descending)
            [ordered]@{
                family = $_.Name
                seen = $_.Count
                share = [math]::Round(100 * $_.Count / [Math]::Max(1, $install.Count))
                # the actual strings that shipped, most used first - this is what the AI ranks its candidates from
                arguments = @($args | Select-Object -First 8 | ForEach-Object {
                        [ordered]@{ args = $_.Name; seen = $_.Count; examplePackage = @($_.Group)[0].Package } })
            } })
    # the same, for uninstall - derived separately because an uninstall switch is not an install switch
    uninstallArguments = @(@($rows | Where-Object { $_.Uninstall }) | Group-Object Args | Sort-Object Count -Descending |
        Select-Object -First 10 | ForEach-Object { [ordered]@{ args = $_.Name; seen = $_.Count } })
}
$out | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $OutFile -Encoding utf8 -Force
Write-Host "`nwritten: $OutFile" -ForegroundColor Green
Write-Host ''
foreach ($f in $out.families) {
    Write-Host ("  {0,-26} {1,4} launches ({2,2}%)   top: {3}" -f $f.family, $f.seen, $f.share, (@($f.arguments)[0].args)) -ForegroundColor Gray
}
