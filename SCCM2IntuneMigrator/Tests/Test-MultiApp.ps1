# Proves a MULTI-APPLICATION run is safe: applications are processed one at a time, each is fully
# isolated (own work folder, own log, own rollback), one failure cannot damage another, cancelling
# stops cleanly, and the report accounts for every application that was ticked.
# Everything is stubbed - no SCCM, no tenant, nothing created anywhere.
$ErrorActionPreference = 'Stop'
$sp   = $PSScriptRoot
$tool = Split-Path -Parent $PSScriptRoot
$fix  = Join-Path $sp 'fixtures'
if (-not (Test-Path (Join-Path $fix 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'))) {
    & (Join-Path $sp 'Build-TestFixtures.ps1') -Root $fix | Out-Null
}

$full = Get-Content -LiteralPath (Join-Path $tool 'SCCM2IntuneMigrator.ps1') -Raw
$cut  = $full.IndexOf('}   # ---- end of $Engine')
$tmpPs1 = Join-Path $sp '_engine_multi.ps1'
[IO.File]::WriteAllText($tmpPs1, $full.Substring(0, $cut + 1), (New-Object Text.UTF8Encoding($true)))
. $tmpPs1
. $Engine
$script:ToolRoot = $tool

$pass = 0; $fail = 0
function T { param($Name, [scriptblock]$B)
    try { $r = & $B; if ($r -eq $true) { $script:pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
          else { $script:fail++; Write-Host "  FAIL  $Name -> $r" -ForegroundColor Red } }
    catch { $script:fail++; Write-Host "  FAIL  $Name -> $($_.Exception.Message)" -ForegroundColor Red } }

# --------------------------------------------------------------------------------------------
# a simulated tenant + site, with a per-application failure switch
# --------------------------------------------------------------------------------------------
$global:SIM = @{
    Apps = New-Object System.Collections.ArrayList      # app ids that exist "in Intune"
    Graph = New-Object System.Collections.ArrayList
    FailUploadFor = @()                                  # app display names whose upload fails
    Order = New-Object System.Collections.ArrayList      # the order applications were processed in
    Concurrent = 0; MaxConcurrent = 0
}
function Reset-Sim {
    $global:SIM.Apps.Clear(); $global:SIM.Graph.Clear(); $global:SIM.Order.Clear()
    $global:SIM.FailUploadFor = @(); $global:SIM.Concurrent = 0; $global:SIM.MaxConcurrent = 0
}
function Get-MigSccmApplication {
    param([string]$SiteCode, [string]$DisplayName)
    [void]$global:SIM.Order.Add($DisplayName)
    $global:SIM.Concurrent++
    if ($global:SIM.Concurrent -gt $global:SIM.MaxConcurrent) { $global:SIM.MaxConcurrent = $global:SIM.Concurrent }
    return @{
        DisplayName = $DisplayName; Title = $DisplayName; Publisher = 'Contoso'; SccmVersion = '1.0'
        Description = "Description for $DisplayName"; LocalizedDesc = ''
        ContentPath = (Join-Path $fix 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'); ExecutionCtx = 'System'
        MaxRuntimeMin = 30; IconBase64 = ''
        SccmInstall = '"Invoke-AppDeployToolkit.exe" Install'; SccmUninstall = '"Invoke-AppDeployToolkit.exe" Uninstall'
        ReturnCodes = @(@{ returnCode = 0; type = 'success' }); Digest = $null
    }
}
function Get-MigDetectionRules {
    param([string]$SiteCode, [string]$ApplicationName, [hashtable]$Name)
    return @{ Rules = @(@{ '@odata.type'='#microsoft.graph.win32LobAppRegistryDetection'
                           keyPath="HKEY_LOCAL_MACHINE\Software\X\$($Name.FullName)"; valueName='Revision'
                           detectionType='string'; operator='equal'; detectionValue='1'; check32BitOn64System=$false })
              Summary = 'branding'; Synthesised = $false }
}
function Find-MigExistingApp { param([hashtable]$Name); return $null }
function Get-MigEntraGroup { param([string]$DisplayName); return $null }
function Invoke-MigGraph {
    param([string]$Method, [string]$Uri, $Body)
    [void]$global:SIM.Graph.Add("$Method $Uri")
    if ($Method -eq 'POST' -and $Uri -match '/mobileApps$') {
        $id = "app-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        [void]$global:SIM.Apps.Add($id)
        return [pscustomobject]@{ id = $id }
    }
    if ($Method -eq 'DELETE' -and $Uri -match '/mobileApps/([^/]+)$') { [void]$global:SIM.Apps.Remove($Matches[1]); return $null }
    return [pscustomobject]@{ id = 'x' }
}
function Set-MigAppContent {
    param([string]$AppId, [string]$IntuneWinPath, [string]$WorkFolder)
    $global:SIM.Concurrent--
    $name = Split-Path -Leaf (Split-Path -Parent $WorkFolder)
    if ($global:SIM.FailUploadFor | Where-Object { $WorkFolder -match [regex]::Escape((Get-MigSafeName $_)) }) {
        throw 'simulated upload failure'
    }
    return '1'
}

$script:Cfg = Import-MigratorSettings -Path (Join-Path $tool 'settings.json')
$script:Cfg.ToolRoot = $tool
$script:Sync = $null
$script:Auth = 'Bearer fake'

function New-Run {
    $r = Join-Path $sp ("multi_" + [guid]::NewGuid().ToString('N').Substring(0,6))
    New-Item $r -ItemType Directory -Force | Out-Null
    $script:RunFolder = $r
    $script:BatchLogPath = Join-Path $r '_Batch.log'
    New-Item -Path $script:BatchLogPath -ItemType File -Force | Out-Null
    return $r
}

$names = 1..8 | ForEach-Object { "Contoso_App{0:D2}_x64_1.{0}.0-000{0}_MUL" -f $_ }

Write-Host "`n=== 8 applications in one run ===" -ForegroundColor Cyan
Reset-Sim; $run = New-Run
$res = @(Invoke-MigBatch -Applications $names)
T 'every application produced a result'  { $res.Count -eq 8 }
T 'all eight succeeded'                  { @($res | Where-Object { $_.Status -eq 'Success' }).Count -eq 8 }
T 'eight apps exist in the tenant'       { $global:SIM.Apps.Count -eq 8 }
T 'they ran ONE AT A TIME'               { $global:SIM.MaxConcurrent -eq 1 }
T 'they ran in the order ticked'         { (($global:SIM.Order) -join ',') -eq ($names -join ',') }
T 'every App ID is different'            { @($res | ForEach-Object { $_.AppId } | Sort-Object -Unique).Count -eq 8 }
T 'every work folder is its own'         { @($res | ForEach-Object { $_.WorkFolder } | Sort-Object -Unique).Count -eq 8 }
T 'every log file is its own'            { @($res | ForEach-Object { $_.LogPath } | Sort-Object -Unique).Count -eq 8 }
T 'every log actually exists'            { @($res | Where-Object { Test-Path -LiteralPath $_.LogPath }).Count -eq 8 }
T 'each log only mentions its own app'   {
    $bad = @()
    foreach ($r in $res) {
        $txt = Get-Content -LiteralPath $r.LogPath -Raw
        foreach ($other in $names) { if ($other -ne $r.Application -and $txt -match [regex]::Escape($other)) { $bad += "$($r.Application) leaked $other" } }
    }
    if ($bad.Count) { $bad -join '; ' } else { $true }
}
T 'each .intunewin is its own file'      { @($res | ForEach-Object { $_.IntuneWinPath } | Sort-Object -Unique).Count -eq 8 }
T 'each UAT group name is its own'       { @($res | ForEach-Object { $_.UatGroup } | Sort-Object -Unique).Count -eq 8 }
T 'each description came from SCCM'      { @($res | Where-Object { $_.DescriptionSrc -eq 'SCCM' }).Count -eq 8 }
$rep = Write-MigReports -Results $res -RunFolder $run
T 'the report has all eight rows'        { @([regex]::Matches((Get-Content -LiteralPath $rep.Html -Raw), 'Contoso_App\d\d')).Count -ge 8 }
T 'the batch log records the whole run'  { (Get-Content -LiteralPath $script:BatchLogPath -Raw) -match 'Batch finished: 8 succeeded' }

Write-Host "`n=== failures in the middle do not touch the others ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
$global:SIM.FailUploadFor = @($names[2], $names[5])
$res2 = @(Invoke-MigBatch -Applications $names)
T 'the run still covered all eight'      { $res2.Count -eq 8 }
T 'exactly two failed'                   { @($res2 | Where-Object { "$($_.Status)" -like 'Failed*' }).Count -eq 2 }
T 'the right two failed'                 {
    $got  = (@($res2 | Where-Object { "$($_.Status)" -like 'Failed*' } | ForEach-Object { $_.Application }) | Sort-Object) -join ','
    $want = (@($names[2], $names[5]) | Sort-Object) -join ','
    if ($got -eq $want) { $true } else { "got [$got] want [$want]" }
}
T 'the other six succeeded'              { @($res2 | Where-Object { $_.Status -eq 'Success' }).Count -eq 6 }
T 'only the six survivors are in Intune' { $global:SIM.Apps.Count -eq 6 }
T 'each failure was rolled back'         { @($res2 | Where-Object { "$($_.Status)" -like 'Failed*' -and $_.Message -match 'rolled back' }).Count -eq 2 }
T 'a failed app reports no App ID'       { @($res2 | Where-Object { "$($_.Status)" -like 'Failed*' -and $_.AppId }).Count -eq 0 }
T 'survivors kept their App IDs'         { @($res2 | Where-Object { $_.Status -eq 'Success' -and $_.AppId -match '^app-' }).Count -eq 6 }
T 'a failure did not stop the batch'     { $global:SIM.Order.Count -eq 8 }

Write-Host "`n=== cancelling mid-run stops cleanly ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
$script:Sync = [hashtable]::Synchronized(@{ CancelRequested = $false; LogQueue = $null; Results = $null
                                            Status=''; Percent=0; Indeterminate=$false
                                            CurrentIndex=0; CurrentTotal=0; CurrentApp='' })
# cancel as soon as the third application starts
$global:SIM.CancelAfter = 3
function Get-MigSccmApplication {
    param([string]$SiteCode, [string]$DisplayName)
    [void]$global:SIM.Order.Add($DisplayName)
    if ($global:SIM.Order.Count -ge 3) { $script:Sync.CancelRequested = $true }
    return @{
        DisplayName = $DisplayName; Title = $DisplayName; Publisher = 'Contoso'; SccmVersion = '1.0'
        Description = 'x'; LocalizedDesc = ''
        ContentPath = (Join-Path $fix 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'); ExecutionCtx = 'System'
        MaxRuntimeMin = 30; IconBase64 = ''
        SccmInstall = '"Invoke-AppDeployToolkit.exe" Install'; SccmUninstall = ''
        ReturnCodes = @(@{ returnCode = 0; type = 'success' }); Digest = $null
    }
}
$res3 = @(Invoke-MigBatch -Applications $names)
T 'the cancelled run still reports every app' { $res3.Count -eq 8 }
T 'the untouched ones say Not started'        { @($res3 | Where-Object { $_.Status -eq 'Not started' }).Count -ge 5 }
T 'nothing was left half-created'             { $global:SIM.Apps.Count -eq @($res3 | Where-Object { $_.Status -eq 'Success' }).Count }
T 'the log says it was cancelled'             { (Get-Content -LiteralPath $script:BatchLogPath -Raw) -match 'Cancelled' }
$script:Sync = $null

Write-Host "`n=== two applications whose names collapse to the same folder ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
function Get-MigSccmApplication {
    param([string]$SiteCode, [string]$DisplayName)
    [void]$global:SIM.Order.Add($DisplayName)
    return @{
        DisplayName = $DisplayName; Title = $DisplayName; Publisher = 'Contoso'; SccmVersion = '1.0'
        Description = 'x'; LocalizedDesc = ''
        ContentPath = (Join-Path $fix 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'); ExecutionCtx = 'System'
        MaxRuntimeMin = 30; IconBase64 = ''
        SccmInstall = '"Invoke-AppDeployToolkit.exe" Install'; SccmUninstall = ''
        ReturnCodes = @(@{ returnCode = 0; type = 'success' }); Digest = $null
    }
}
# 'App:One' and 'App|One' both sanitise to 'App_One'
$clash = @('Contoso_App:One_x64_1.0-1_MUL', 'Contoso_App|One_x64_1.0-1_MUL')
$res4 = @(Invoke-MigBatch -Applications $clash)
T 'both were migrated'                  { @($res4 | Where-Object { $_.Status -eq 'Success' }).Count -eq 2 }
T 'they did NOT share a work folder'    { $res4[0].WorkFolder -ne $res4[1].WorkFolder }
T 'they did NOT share a log file'       { $res4[0].LogPath -ne $res4[1].LogPath }
T 'both logs survive'                   { (Test-Path -LiteralPath $res4[0].LogPath) -and (Test-Path -LiteralPath $res4[1].LogPath) }

Write-Host ""
Write-Host "PASSED $pass   FAILED $fail" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
if ($fail) { exit 1 }
