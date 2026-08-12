# A cheap, static guard against the ONE mistake that keeps killing the window: code referring to a
# control that no longer exists in the XAML (or that FindName never looked up). $UI is a plain
# hashtable, so a missing control is silently $null and only blows up later - at the click - with
# "The property 'IsEnabled' cannot be found on this object".
#
# This suite reads the script as TEXT. It needs no window, no STA and no fixtures.
$ErrorActionPreference = 'Stop'
$tool = Split-Path -Parent $PSScriptRoot
$src  = Get-Content -LiteralPath (Join-Path $tool 'SCCM2IntuneMigrator.ps1') -Raw

$pass = 0; $fail = 0
function T { param($Name, [scriptblock]$B)
    try { $r = & $B; if ($r -eq $true) { $script:pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
          else { $script:fail++; Write-Host "  FAIL  $Name -> $r" -ForegroundColor Red } }
    catch { $script:fail++; Write-Host "  FAIL  $Name -> $($_.Exception.Message)" -ForegroundColor Red } }

# --- what the code asks for ---------------------------------------------------------------------
$referenced = @()
# case-insensitive: the code uses both $UI.X and $ui.X, and PowerShell treats them as one variable
$referenced += [regex]::Matches($src, '(?i)\$(?:State\.)?UI\.([A-Za-z][A-Za-z0-9]*)')      | ForEach-Object { $_.Groups[1].Value }
$referenced += [regex]::Matches($src, "(?i)\`$(?:State\.)?UI\['([A-Za-z][A-Za-z0-9]*)'\]") | ForEach-Object { $_.Groups[1].Value }
$referenced = @($referenced | Sort-Object -Unique)

# --- what the XAML actually defines --------------------------------------------------------------
$declared = @([regex]::Matches($src, 'Name="([A-Za-z][A-Za-z0-9]*)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

# --- what FindName is asked to resolve -----------------------------------------------------------
# Anchor on the FindName line itself and take the foreach header immediately above it. The engine
# has other 'foreach ($n in ...)' loops, so a bare pattern match finds the wrong one.
$anchor = $src.IndexOf('$UI[$n] = $Win.FindName')
$lookedUp = @()
if ($anchor -gt 0) {
    $start = $src.LastIndexOf('foreach ($n in', $anchor)
    if ($start -ge 0) {
        $header = $src.Substring($start, $anchor - $start)
        $lookedUp = @([regex]::Matches($header, "'([A-Za-z0-9]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    }
}

Write-Host "`n=== control wiring ===" -ForegroundColor Cyan
Write-Host "  ($($referenced.Count) referenced, $($declared.Count) in XAML, $($lookedUp.Count) looked up)" -ForegroundColor DarkGray

T 'FindName block was located'  { $lookedUp.Count -gt 5 }
T 'every referenced control exists in the XAML' {
    $missing = @($referenced | Where-Object { $_ -notin $declared })
    if ($missing.Count) { "not in XAML: $($missing -join ', ')" } else { $true }
}
T 'every referenced control is looked up by FindName' {
    $missing = @($referenced | Where-Object { $_ -notin $lookedUp })
    if ($missing.Count) { "never FindName'd: $($missing -join ', ')" } else { $true }
}
T 'nothing is looked up that the XAML does not define' {
    $extra = @($lookedUp | Where-Object { $_ -notin $declared })
    if ($extra.Count) { "looked up but not in XAML: $($extra -join ', ')" } else { $true }
}
T 'no control is looked up and then never used' {
    $unused = @($lookedUp | Where-Object { $_ -notin $referenced })
    if ($unused.Count) { "looked up but unused: $($unused -join ', ')" } else { $true }
}

Write-Host "`n=== dispatcher calls put the PRIORITY first ===" -ForegroundColor Cyan
# Invoke/BeginInvoke([action]{...}, <priority>) binds to the (Delegate, params object[]) overload
# and hands the priority to a zero-parameter action -> "Parameter count mismatch" at runtime.
T 'no Dispatcher call passes the priority second' {
    $bad = @([regex]::Matches($src, '(?i)\.(?:Begin)?Invoke\(\s*\[action\]') | ForEach-Object { $_.Value })
    if ($bad.Count) { "priority-last dispatcher call(s): $($bad -join ' | ')" } else { $true }
}

Write-Host ""
Write-Host "PASSED $pass   FAILED $fail" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
if ($fail) { exit 1 }
