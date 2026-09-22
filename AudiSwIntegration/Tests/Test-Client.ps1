# ==============================================================================
#  Tests for the operator window itself.
#
#  These exist because of a bug that shipped: the client selected a tab with
#  $ui.tabPackage, but that TabItem carried no x:Name, so the lookup threw
#  "The property 'tabPackage' cannot be found on this object" and Browse and
#  Read details both died. Nothing caught it, because the XAML parses fine and
#  the client only fails at the moment the handler runs.
#
#  So: parse the real XAML, collect every x:Name, and check that every control
#  the client script reaches for actually exists.
#    .\Test-Client.ps1
# ==============================================================================

[CmdletBinding()]
param([switch]$Quiet)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Pass = 0
$script:Fail = 0
function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { $script:Pass++; if (-not $Quiet) { Write-Host ("  PASS  " + $Name) -ForegroundColor Green } }
    else            { $script:Fail++; Write-Host ("  FAIL  " + $Name + $(if ($Detail) { " -- $Detail" } else { '' })) -ForegroundColor Red }
}

$root       = Split-Path -Parent $PSScriptRoot
$xamlPath   = Join-Path $root 'Packager\MainWindow.xaml'
$clientPath = Join-Path $root 'Packager\Start-AudiSwClient.ps1'

Write-Host ''
Write-Host 'Audi SCCM Integration Tool - operator window tests' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------- the XAML loads
Write-Host 'The window definition' -ForegroundColor White

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$xamlText = [System.IO.File]::ReadAllText($xamlPath)

$loaded = $true
try {
    $reader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader $xamlText)
    $null = [System.Windows.Markup.XamlReader]::Load($reader)
}
catch { $loaded = $false; $loadError = $_.Exception.Message }
Assert-True 'the XAML parses and builds a window' $loaded $(if ($loaded) { '' } else { $loadError })

# ------------------------------------------------------- names the XAML defines
$declared = @{}
foreach ($m in [regex]::Matches($xamlText, 'x:Name\s*=\s*"([^"]+)"')) {
    $declared[$m.Groups[1].Value] = $true
}
Assert-True 'the window declares named controls' ($declared.Count -gt 20) "$($declared.Count) found"

# --------------------------------------------- names the client script reaches for
# $ui.Something and $ui['Something'] / $ui[$var] - the literal forms only, since
# a computed name cannot be checked here.
$clientText = [System.IO.File]::ReadAllText($clientPath)

$used = New-Object System.Collections.Generic.List[string]
foreach ($m in [regex]::Matches($clientText, '\$ui\.([A-Za-z_][A-Za-z0-9_]*)')) {
    $used.Add($m.Groups[1].Value) | Out-Null
}
foreach ($m in [regex]::Matches($clientText, "\`$ui\[\s*'([^']+)'\s*\]")) {
    $used.Add($m.Groups[1].Value) | Out-Null
}
# Names listed inside a quoted set and then indexed, e.g.
#   foreach ($b in 'btnPreview','btnIntegrate') { $ui[$b] ... }
foreach ($m in [regex]::Matches($clientText, "foreach\s*\(\s*\`$\w+\s+in\s+((?:'[^']+'\s*,\s*)+'[^']+')\s*\)")) {
    foreach ($q in [regex]::Matches($m.Groups[1].Value, "'([^']+)'")) {
        $used.Add($q.Groups[1].Value) | Out-Null
    }
}

# $ui is a hashtable the client also keeps its own state in, so not every
# member is a control: Window and LogFolder are put there by the client, and
# Contains is the hashtable's own method.
$notFromXaml = @('Window', 'LogFolder', 'Contains', 'Keys')

$unknown = @($used | Sort-Object -Unique |
             Where-Object { $notFromXaml -notcontains $_ -and -not $declared.ContainsKey($_) })

Assert-True 'every control the client uses is named in the XAML' `
    ($unknown.Count -eq 0) "missing from MainWindow.xaml: $($unknown -join ', ')"

# The window runs under StrictMode: a $script: variable that is READ before
# anything ASSIGNED it throws, and the window dies on that click ("SiteState
# cannot be retrieved because it has not been set" - Integrate, 18.09.2026).
# So every $script: variable the client mentions must be assigned once at the
# top level of the script, whatever functions assign it later.
$scriptVars = @([regex]::Matches($clientText, '\$script:([A-Za-z_]\w*)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$topLevel   = @([regex]::Matches($clientText, '(?m)^\$script:([A-Za-z_]\w*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
# the script's own parameters are script-scope variables from the first line
$clientAst  = [System.Management.Automation.Language.Parser]::ParseFile($clientPath, [ref]$null, [ref]$null)
$topLevel  += @($clientAst.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
$uninit = @($scriptVars | Where-Object { $topLevel -notcontains $_ })
Assert-True 'every $script: variable the client reads is initialised at the top level' `
    ($uninit.Count -eq 0) "no top-level assignment for: $($uninit -join ', ')"

# The five pages are switched to by name when an action starts, so each one
# has to be findable, and each has a rail entry.
foreach ($tab in 'tabIntegrate', 'tabModify', 'tabMembers', 'tabRemove', 'tabJobs') {
    Assert-True "the $tab page is named" $declared.ContainsKey($tab)
}
foreach ($nav in 'navIntegrate', 'navModify', 'navMembers', 'navRemove', 'navJobs') {
    Assert-True "the $nav rail entry is named" $declared.ContainsKey($nav)
}
Assert-True 'the old Package/Result tab names are gone' `
    (-not $declared.ContainsKey('tabPackage') -and -not $declared.ContainsKey('tabResult'))

# ------------------------------------------------- the theme has to be complete
Write-Host ''
Write-Host 'Theme' -ForegroundColor White

# Every colour in the XAML is a keyed brush looked up dynamically, and the
# script carries a dark and a light value for each. A key declared in one
# place and not the other is a control that stays the wrong colour after a
# toggle - which is exactly how a dark page ends up with a light patch.
$brushKeys = @([regex]::Matches($xamlText, '<SolidColorBrush\s+x:Key="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
Assert-True 'the XAML declares a palette' ($brushKeys.Count -ge 30) "$($brushKeys.Count) brushes"

foreach ($theme in 'Light', 'Dark') {
    $block = [regex]::Match($clientText, "(?s)\b$theme\s*=\s*@\{(.*?)\n\s*\}")
    Assert-True "the script carries a $theme palette" $block.Success
    $keysInScript = @([regex]::Matches($block.Groups[1].Value, '(\w+)\s*=\s*''#FF[0-9A-Fa-f]{6}''') | ForEach-Object { $_.Groups[1].Value })
    $missing = @($brushKeys | Where-Object { $keysInScript -notcontains $_ })
    $extra   = @($keysInScript | Where-Object { $brushKeys -notcontains $_ })
    Assert-True "  $theme defines every brush the XAML declares" ($missing.Count -eq 0) "missing: $($missing -join ', ')"
    Assert-True "  $theme defines nothing the XAML does not use" ($extra.Count -eq 0) "unused: $($extra -join ', ')"
}

# No literal colour may sit on a control: it would not follow the theme.
$literals = @([regex]::Matches($xamlText, '(?:Background|Foreground|BorderBrush|Fill|Stroke)="(#[0-9A-Fa-f]{6,8})"') | ForEach-Object { $_.Groups[1].Value })
Assert-True 'no control carries a literal colour' ($literals.Count -eq 0) ($literals -join ', ')

# Every brush reference is dynamic, so a swapped brush reaches it. A
# StaticResource to a brush would freeze the first theme in place.
$staticBrush = @([regex]::Matches($xamlText, '\{StaticResource\s+([^}]+)\}') |
                 ForEach-Object { $_.Groups[1].Value } |
                 Where-Object { $brushKeys -contains $_ })
Assert-True 'no brush is referenced statically' ($staticBrush.Count -eq 0) ($staticBrush -join ', ')

# The filled primary button sets its own foreground, so its label is never
# the page ink on an accent fill.
$primary = [regex]::Match($xamlText, '(?s)x:Key="BtnPrimary".*?</Style>')
Assert-True 'the filled primary button sets its own foreground' `
    ($primary.Success -and $primary.Value -match 'Foreground"\s+Value="\{DynamicResource PrimaryFg\}')

# Both palettes keep ink and page apart: the dark theme's ink must be light
# and its page dark, and the other way round.
function Get-Luma([string]$hex) {
    $r = [Convert]::ToInt32($hex.Substring(3,2),16); $g = [Convert]::ToInt32($hex.Substring(5,2),16); $b = [Convert]::ToInt32($hex.Substring(7,2),16)
    return (0.299*$r + 0.587*$g + 0.114*$b)
}
foreach ($theme in 'Light', 'Dark') {
    $block = [regex]::Match($clientText, "(?s)\b$theme\s*=\s*@\{(.*?)\n\s*\}").Groups[1].Value
    $ink = [regex]::Match($block, "\bInk\s*=\s*'(#FF[0-9A-Fa-f]{6})'").Groups[1].Value
    $bg  = [regex]::Match($block, "\bBg\s*=\s*'(#FF[0-9A-Fa-f]{6})'").Groups[1].Value
    Assert-True "$theme ink and page are far enough apart to read" ([Math]::Abs((Get-Luma $ink) - (Get-Luma $bg)) -gt 120) "$ink on $bg"
}

# ------------------------------------------------- the client / server boundary
Write-Host ''
Write-Host 'The client carries no SCCM code' -ForegroundColor White

# Client and Server are deployed to different machines. The window never
# connects to a site, holds no SCCM rights and needs no ConfigMgr console - so
# the SCCM half must not be in its folder at all. A window that CAN reach SCCM
# will eventually be made to.
$lib       = Join-Path $root 'Packager\Lib'
$libFiles  = @(Get-ChildItem -LiteralPath $lib -Filter '*.ps1' -File | ForEach-Object { $_.Name })

$codeLinesEarly = @($clientText -split "\r?\n" |
                    Where-Object { $_.Trim() -and $_.Trim() -notlike '#*' })

Assert-True 'the client ships its own library' (Test-Path -LiteralPath $lib)
foreach ($needed in 'Config.ps1', 'Runtime.ps1', 'Transport.ps1', 'Load.ps1') {
    Assert-True "  it has $needed" ($libFiles -contains $needed)
}
foreach ($banned in 'Provider.ps1', 'Steps.ps1', 'Inspect.ps1', 'Preflight.ps1', 'Orchestrator.ps1') {
    Assert-True "  and NOT $banned" ($libFiles -notcontains $banned)
}

# The window needs Defaults.xml - the patterns that read a PSADT script and an
# instruction document, and the package name layout. That is packaging
# knowledge, not SCCM knowledge.
Assert-True 'the client has its own Defaults.xml' `
    (Test-Path -LiteralPath (Join-Path $root 'Packager\Config\Defaults.xml'))

# It must NOT have the environment files. Those describe SCCM topology -
# collections, security scopes, console folders, distribution point groups - and
# putting them on every packager PC spreads the site's layout around and gives
# an environment change N copies to keep in step. The window works the
# environment out from the package name and the drop folder instead.
Assert-True 'the client has NO environment files' `
    (-not (Test-Path -LiteralPath (Join-Path $root 'Packager\Config\Environments'))) `
    'Packager\Config\Environments still exists'

foreach ($banned in 'Get-AudiEnvironment', 'Get-AudiEnvironmentCode', 'Resolve-AudiEnvironmentCode') {
    $calls = @($codeLinesEarly | Where-Object { $_ -match "\b$banned\b" })
    Assert-True "the window never calls $banned" ($calls.Count -eq 0) ($calls -join ' | ')
}

# And the server still has them - this moved the files, it did not delete them.
Assert-True 'the server still holds the environment files' `
    (@(Get-ChildItem (Join-Path $root 'SccmServer\Engine\Config\Environments') -Filter '*.xml' -File).Count -gt 0)

# Nothing in the window may reach for the server's engine while it is running.
# The self-test loads it deliberately to play both sides, and says so, so that
# one line is allowed - any other is the boundary being eroded.
# Code lines only - the comments above explain the boundary and naturally name
# the folder they are describing.
$codeLines = @($clientText -split "\r?\n" | Where-Object { $_.Trim() -and $_.Trim() -notlike '#*' })
$serverReaches = @($codeLines |
                   Where-Object { $_ -match 'SccmServer\\Engine' } |
                   Where-Object { $_ -notmatch 'serverEngine' })
Assert-True 'the window never loads the server engine outside the self-test' `
    ($serverReaches.Count -eq 0) ($serverReaches -join ' | ')

# Loading the client library must not define a single SCCM function.
$probe = [powershell]::Create()
$null  = $probe.AddScript(@"
Set-StrictMode -Version 2.0
. '$lib\Load.ps1'
@(Get-Command -CommandType Function | Where-Object { `$_.Name -like '*-Audi*' } | ForEach-Object { `$_.Name })
"@)
$loaded = @($probe.Invoke())
$probe.Dispose()

Assert-True 'loading the client library defines the transport functions' `
    (($loaded -contains 'Submit-AudiSwJob') -and ($loaded -contains 'Read-AudiPackageDetail')) `
    ("$($loaded.Count) function(s)")

$sccmOnly = @('Invoke-AudiSwIntegration', 'Invoke-AudiSwRemoval', 'Invoke-AudiSwModification',
              'New-AudiSccmProvider', 'Connect-AudiSccm', 'Get-AudiSwPackageState',
              'Invoke-AudiSwChange', 'Test-AudiSwPrerequisite')
$leaked = @($sccmOnly | Where-Object { $loaded -contains $_ })
Assert-True 'and defines no SCCM function at all' ($leaked.Count -eq 0) ($leaked -join ', ')

# ------------------------------------------------------------------------ done
Write-Host ''
if ($script:Fail -eq 0) { Write-Host "All $($script:Pass) checks passed." -ForegroundColor Green }
else { Write-Host "$($script:Pass) passed, $($script:Fail) FAILED." -ForegroundColor Red }
exit $(if ($script:Fail -eq 0) { 0 } else { 1 })
