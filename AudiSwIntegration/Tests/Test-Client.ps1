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

# ------------------------------------------------------------------------ done
Write-Host ''
if ($script:Fail -eq 0) { Write-Host "All $($script:Pass) checks passed." -ForegroundColor Green }
else { Write-Host "$($script:Pass) passed, $($script:Fail) FAILED." -ForegroundColor Red }
exit $(if ($script:Fail -eq 0) { 0 } else { 1 })
