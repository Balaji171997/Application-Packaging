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
$xamlPath   = Join-Path $root 'Client\MainWindow.xaml'
$clientPath = Join-Path $root 'Client\Start-AudiSwClient.ps1'

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
$notFromXaml = @('Window', 'LogFolder', 'Contains')

$unknown = @($used | Sort-Object -Unique |
             Where-Object { $notFromXaml -notcontains $_ -and -not $declared.ContainsKey($_) })

Assert-True 'every control the client uses is named in the XAML' `
    ($unknown.Count -eq 0) "missing from MainWindow.xaml: $($unknown -join ', ')"

# The three tabs are switched to by name when an action starts, so each one has
# to be findable.
foreach ($tab in 'tabPackage', 'tabModify', 'tabResult') {
    Assert-True "the $tab tab is named" $declared.ContainsKey($tab)
}

# ------------------------------------------------- colours have to be readable
Write-Host ''
Write-Host 'Readability' -ForegroundColor White

# A filled accent button with dark ink on it is unreadable. Both were shipped
# that way once; this keeps them apart.
$primary = [regex]::Match($xamlText, '(?s)x:Key="BtnPrimary".*?</Style>')
Assert-True 'the filled primary button sets its own light foreground' `
    ($primary.Success -and $primary.Value -match 'Foreground"\s+Value="#FFF') $primary.Value

# The dark theme's literals are gone - anything very dark left in a Background
# would be a leftover sitting behind dark text.
$darkLeftovers = @()
foreach ($m in [regex]::Matches($xamlText, 'Background"?\s*(?:=|Value=)\s*"(#FF[0-9A-Fa-f]{6})"')) {
    $hex = $m.Groups[1].Value
    $r = [Convert]::ToInt32($hex.Substring(2,2),16)
    $g = [Convert]::ToInt32($hex.Substring(4,2),16)
    $b = [Convert]::ToInt32($hex.Substring(6,2),16)
    # perceived luminance
    if ((0.299*$r + 0.587*$g + 0.114*$b) -lt 90) { $darkLeftovers += $hex }
}
Assert-True 'no dark backgrounds are left behind the dark text' `
    ($darkLeftovers.Count -eq 0) "dark backgrounds still present: $($darkLeftovers -join ', ')"

# ------------------------------------------------- the client / server boundary
Write-Host ''
Write-Host 'The client carries no SCCM code' -ForegroundColor White

# Client and Server are deployed to different machines. The window never
# connects to a site, holds no SCCM rights and needs no ConfigMgr console - so
# the SCCM half must not be in its folder at all. A window that CAN reach SCCM
# will eventually be made to.
$lib       = Join-Path $root 'Client\Lib'
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
    (Test-Path -LiteralPath (Join-Path $root 'Client\Config\Defaults.xml'))

# It must NOT have the environment files. Those describe SCCM topology -
# collections, security scopes, console folders, distribution point groups - and
# putting them on every packager PC spreads the site's layout around and gives
# an environment change N copies to keep in step. The window works the
# environment out from the package name and the drop folder instead.
Assert-True 'the client has NO environment files' `
    (-not (Test-Path -LiteralPath (Join-Path $root 'Client\Config\Environments'))) `
    'Client\Config\Environments still exists'

foreach ($banned in 'Get-AudiEnvironment', 'Get-AudiEnvironmentCode', 'Resolve-AudiEnvironmentCode') {
    $calls = @($codeLinesEarly | Where-Object { $_ -match "\b$banned\b" })
    Assert-True "the window never calls $banned" ($calls.Count -eq 0) ($calls -join ' | ')
}

# And the server still has them - this moved the files, it did not delete them.
Assert-True 'the server still holds the environment files' `
    (@(Get-ChildItem (Join-Path $root 'Server\Engine\Config\Environments') -Filter '*.xml' -File).Count -gt 0)

# Nothing in the window may reach for the server's engine while it is running.
# The self-test loads it deliberately to play both sides, and says so, so that
# one line is allowed - any other is the boundary being eroded.
# Code lines only - the comments above explain the boundary and naturally name
# the folder they are describing.
$codeLines = @($clientText -split "\r?\n" | Where-Object { $_.Trim() -and $_.Trim() -notlike '#*' })
$serverReaches = @($codeLines |
                   Where-Object { $_ -match 'Server\\Engine' } |
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
