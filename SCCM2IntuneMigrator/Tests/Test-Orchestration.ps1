# Exercises the per-application orchestration and the ROLLBACK paths end to end, with SCCM and
# Graph stubbed out. Nothing here touches a real site or tenant.
$ErrorActionPreference = 'Stop'
$sp   = $PSScriptRoot
$tool = Split-Path -Parent $PSScriptRoot
$fix  = Join-Path $sp 'fixtures'

$full = Get-Content -LiteralPath (Join-Path $tool 'SCCM2IntuneMigrator.ps1') -Raw
$cut  = $full.IndexOf('}   # ---- end of $Engine')
$tmpPs1 = Join-Path $sp '_engine_only2.ps1'
[IO.File]::WriteAllText($tmpPs1, $full.Substring(0, $cut + 1), (New-Object Text.UTF8Encoding($true)))
. $tmpPs1
. $Engine
$script:ToolRoot = $tool

$pass = 0; $fail = 0
function T { param($Name, [scriptblock]$B)
    try { $r = & $B; if ($r -eq $true) { $script:pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
          else { $script:fail++; Write-Host "  FAIL  $Name -> $r" -ForegroundColor Red } }
    catch { $script:fail++; Write-Host "  FAIL  $Name -> $($_.Exception.Message)" -ForegroundColor Red } }

# ---------------------------------------------------------------------------------------------
# the simulated world
# ---------------------------------------------------------------------------------------------
$global:SIM = @{
    GraphCalls   = New-Object System.Collections.ArrayList
    FailUpload   = $false
    FailDelete   = $false
    FailAssign   = $false
    ExistingApp  = $null
    GroupExists  = $false
    CreatedApps  = New-Object System.Collections.ArrayList
    CreatedGroups= New-Object System.Collections.ArrayList
}
function Reset-Sim {
    $global:SIM.GraphCalls.Clear(); $global:SIM.CreatedApps.Clear(); $global:SIM.CreatedGroups.Clear()
    $global:SIM.FailUpload = $false; $global:SIM.FailDelete = $false; $global:SIM.FailAssign = $false
    $global:SIM.ExistingApp = $null; $global:SIM.GroupExists = $false
}

function Get-MigSccmApplication {
    param([string]$SiteCode, [string]$DisplayName)
    $content = switch -Regex ($DisplayName) {
        'V3'       { Join-Path $fix 'Contoso_TestAppV3_x64_1.0.0-0001_MUL' }
        'NoContent'{ 'X:\does\not\exist' }
        default    { Join-Path $fix 'Contoso_TestAppV4_x64_2.5.1-0003_ENU' }
    }
    return @{
        DisplayName = $DisplayName; Title = $DisplayName; Publisher = 'Contoso'; SccmVersion = '2.5.1'
        Description = ''; LocalizedDesc = ''; ContentPath = $content; ExecutionCtx = 'System'
        MaxRuntimeMin = 45; IconBase64 = ''
        ReturnCodes = @(@{ returnCode = 0; type = 'success' }); Digest = $null
    }
}
function Get-MigDetectionRules {
    param([string]$SiteCode, [string]$ApplicationName, [hashtable]$Name)
    return @{ Rules = @(@{ '@odata.type' = '#microsoft.graph.win32LobAppRegistryDetection'
                           keyPath = "HKEY_LOCAL_MACHINE\Software\X\$($Name.FullName)"; valueName = 'Revision'
                           detectionType = 'string'; operator = 'equal'; detectionValue = $Name.Revision
                           check32BitOn64System = $false })
              Summary = 'branding rule'; Synthesised = $false }
}
function Find-MigExistingApp { param([hashtable]$Name); return $global:SIM.ExistingApp }
function Invoke-MigGraph {
    param([string]$Method, [string]$Uri, $Body)
    [void]$global:SIM.GraphCalls.Add("$Method $Uri")
    if ($Method -eq 'POST' -and $Uri -match '/mobileApps$') {
        $id = "app-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        [void]$global:SIM.CreatedApps.Add($id)
        return [pscustomobject]@{ id = $id }
    }
    if ($Method -eq 'DELETE' -and $Uri -match '/mobileApps/([^/]+)$') {
        if ($global:SIM.FailDelete) { throw 'simulated delete failure (403)' }
        [void]$global:SIM.CreatedApps.Remove($Matches[1]); return $null
    }
    if ($Method -eq 'DELETE' -and $Uri -match '/groups/(.+)$') {
        if ($global:SIM.FailDelete) { throw 'simulated group delete failure' }
        [void]$global:SIM.CreatedGroups.Remove($Matches[1]); return $null
    }
    if ($Method -eq 'DELETE') { return $null }
    return [pscustomobject]@{ id = 'x' }
}
function Set-MigAppContent {
    param([string]$AppId, [string]$IntuneWinPath, [string]$WorkFolder)
    if ($global:SIM.FailUpload) { throw 'simulated Azure blob upload failure after 3 blocks' }
    return '1'
}
function Get-MigEntraGroup {
    param([string]$DisplayName)
    [void]$global:SIM.GraphCalls.Add("GET /groups?displayName=$DisplayName")
    if ($global:SIM.GroupExists) { return [pscustomobject]@{ id = 'grp-existing'; displayName = $DisplayName } }
    return $null
}
function Add-MigAppAssignment {
    param([string]$AppId, [string]$GroupId)
    if ($global:SIM.FailAssign) { throw 'simulated assignment failure' }
    [void]$global:SIM.GraphCalls.Add("POST assignment $GroupId")
    return "asg-1"
}

$script:Cfg = Import-MigratorSettings -Path (Join-Path $tool 'settings.json')
$script:Cfg.ToolRoot = $tool
$script:Sync = $null
$script:Auth = 'Bearer fake'

function New-Run {
    $r = Join-Path $sp ("run_" + [guid]::NewGuid().ToString('N').Substring(0,6))
    New-Item $r -ItemType Directory -Force | Out-Null
    $script:RunFolder = $r
    $script:BatchLogPath = Join-Path $r '_Batch.log'
    New-Item -Path $script:BatchLogPath -ItemType File -Force | Out-Null
    return $r
}

Write-Host "`n=== happy path ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
$r = Invoke-MigApplication -DisplayName 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'
T 'status is Success'                { $r.Status -eq 'Success' }
T 'an App ID is reported'            { $r.AppId -match '^app-' }
T 'the UAT group NAME is reported'   { $r.UatGroup -eq 'MDM_MN_SWW_Contoso_TestAppV4_UAT' }
T 'NO group was created'             { @($global:SIM.GraphCalls | Where-Object { $_ -match '^POST .*/groups' }).Count -eq 0 }
T 'a missing group is flagged'       { $r.UatGroupExists -eq $false }
T 'NOTHING was assigned'             { @($global:SIM.GraphCalls | Where-Object { $_ -match 'assignment' }).Count -eq 0 }
T 'no noisy group warning'           { $r.Warnings -notmatch 'does not exist yet' }
T 'toolkit is recorded'              { $r.Psadt -eq 'PSADT v4' }
T 'the icon source is recorded'      { $r.IconSource -eq 'Content' }
T 'the description source is recorded' { $r.DescriptionSrc -match 'Installation instructions.docx' }
T 'the .intunewin path is reported'  { $r.IntuneWinPath -and (Test-Path -LiteralPath $r.IntuneWinPath) }
T 'a per-app log was written'        { (Test-Path -LiteralPath $r.LogPath) -and ((Get-Content $r.LogPath -Raw).Length -gt 200) }
T 'the app still exists in the sim'  { $global:SIM.CreatedApps.Count -eq 1 }
T 'content size was measured'        { $r.ContentSizeMB -ne $null -and [double]$r.ContentSizeMB -ge 0 }
T 'duration was measured'            { $r.DurationSec -ge 0 }

Write-Host "`n=== v3 package takes the ServiceUI path ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
$r3 = Invoke-MigApplication -DisplayName 'Contoso_TestAppV3_x64_1.0.0-0001_MUL'
T 'v3 detected'                { $r3.Psadt -eq 'PSADT v3' }
T 'v3 succeeded'               { $r3.Status -eq 'Success' }
T 'v3 falls back to the default icon' { $r3.IconSource -eq 'Default' }
T 'v3 warns about the default icon'   { $r3.Warnings -match 'default icon used' }
T 'a real content size is reported'   { [double]$r3.ContentSizeMB -gt 0 }

Write-Host "`n=== rollback: upload fails ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
$global:SIM.FailUpload = $true
$rf = Invoke-MigApplication -DisplayName 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'
T 'status is Failed'                    { $rf.Status -eq 'Failed' }
T 'the real reason is reported'         { $rf.Message -match 'simulated Azure blob upload failure' }
T 'the half-created app was deleted'    { $global:SIM.CreatedApps.Count -eq 0 }
T 'no App ID is left in the report'     { -not $rf.AppId }
T 'the user is told retrying is safe'   { $rf.Message -match 'rolled back' -and $rf.Message -match 'retrying is safe' }
T 'the built .intunewin is kept'        { $rf.Message -match 'kept for a manual upload' }
T 'a DELETE was actually issued'        { @($global:SIM.GraphCalls | Where-Object { $_ -match '^DELETE .*mobileApps/' }).Count -eq 1 }


Write-Host "`n=== an EXISTING group is REPORTED, never assigned ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
$global:SIM.GroupExists = $true
$rg = Invoke-MigApplication -DisplayName 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'
T 'the app succeeded'              { $rg.Status -eq 'Success' }
T 'the group id is reported'       { $rg.UatGroupExists -eq $true -and $rg.UatGroupId -eq 'grp-existing' }
T 'the group name is reported'     { $rg.UatGroup -eq 'MDM_MN_SWW_Contoso_TestAppV4_UAT' }
T 'NO assignment call was made'    { @($global:SIM.GraphCalls | Where-Object { $_ -match '(?i)assignment' }).Count -eq 0 }
T 'the message names the group'    { $rg.Message -match 'UAT group: MDM_MN_SWW_Contoso_TestAppV4_UAT' }
Write-Host "`n=== rollback that itself fails is reported loudly ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
$global:SIM.FailUpload = $true; $global:SIM.FailDelete = $true
$rr = Invoke-MigApplication -DisplayName 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'
T 'status says the rollback was incomplete' { $rr.Status -match 'rollback incomplete' }
T 'manual cleanup is demanded'              { $rr.Message -match 'ROLLBACK INCOMPLETE, clean up by hand' }
T 'the orphaned ids are named'              { $rr.Message -match 'could not be deleted' }

Write-Host "`n=== already in Intune -> skipped, nothing created ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
$global:SIM.ExistingApp = [pscustomobject]@{ id = 'app-already'; displayName = 'TestAppV4'; createdDateTime = '2026-01-01' }
$rs = Invoke-MigApplication -DisplayName 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'
T 'status is Skipped'          { $rs.Status -eq 'Skipped' }
T 'the existing App ID is given'{ $rs.AppId -eq 'app-already' }
T 'nothing new was created'    { $global:SIM.CreatedApps.Count -eq 0 }

Write-Host "`n=== dry run creates nothing ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
$rd = Invoke-MigApplication -DisplayName 'Contoso_TestAppV4_x64_2.5.1-0003_ENU' -DryRun
T 'status is DryRun'                  { $rd.Status -eq 'DryRun' }
T 'no Graph call was made at all'     { $global:SIM.GraphCalls.Count -eq 0 }
T 'the .intunewin was still built'    { Test-Path -LiteralPath $rd.IntuneWinPath }

Write-Host "`n=== unreachable content fails cleanly ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
$rn = Invoke-MigApplication -DisplayName 'Contoso_NoContent_x64_1.0-1_MUL'
T 'status is Failed'            { $rn.Status -eq 'Failed' }
T 'the reason names the path'   { $rn.Message -match 'not reachable from this machine' }
T 'nothing was created'         { $global:SIM.CreatedApps.Count -eq 0 }

Write-Host "`n=== batch: a failure does not stop the others ===" -ForegroundColor Cyan
Reset-Sim; $run = New-Run
$script:Cfg.RollbackScope = 'FailedAppOnly'
$queue = @('Contoso_TestAppV4_x64_2.5.1-0003_ENU', 'Contoso_NoContent_x64_1.0-1_MUL', 'Contoso_TestAppV3_x64_1.0.0-0001_MUL')
$res = Invoke-MigBatch -Applications $queue 
T 'every application is in the result'  { @($res).Count -eq 3 }
T 'the good ones succeeded'             { @($res | Where-Object { $_.Status -eq 'Success' }).Count -eq 2 }
T 'the bad one failed'                  { @($res | Where-Object { $_.Status -eq 'Failed' }).Count -eq 1 }
T 'the survivors are still in Intune'   { $global:SIM.CreatedApps.Count -eq 2 }
$rep = Write-MigReports -Results $res -RunFolder $run
T 'the report lists all three'          { (Get-Content -LiteralPath $rep.Html -Raw) -match 'Contoso_TestAppV4' }
T 'the report carries both App IDs'     { @([regex]::Matches((Get-Content -LiteralPath $rep.Html -Raw), 'app-[0-9a-f]{8}')).Count -ge 2 }
T 'the report carries the UAT names'    { @([regex]::Matches((Get-Content -LiteralPath $rep.Html -Raw), 'MDM_MN_SWW_')).Count -ge 2 }

Write-Host "`n=== batch: RollbackScope = WholeBatch ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
$script:Cfg.RollbackScope = 'WholeBatch'
$res2 = Invoke-MigBatch -Applications @('Contoso_TestAppV4_x64_2.5.1-0003_ENU', 'Contoso_NoContent_x64_1.0-1_MUL', 'Contoso_TestAppV3_x64_1.0.0-0001_MUL') 
T 'the earlier success was rolled back' { @($res2 | Where-Object { $_.Status -eq 'Rolled back' }).Count -eq 1 }
T 'the later one was never started'     { @($res2 | Where-Object { $_.Status -eq 'Not started' }).Count -eq 1 }
T 'nothing is left in Intune'           { $global:SIM.CreatedApps.Count -eq 0 }

Write-Host "`n=== batch: RollbackScope = FailedAppAndStop ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
$script:Cfg.RollbackScope = 'FailedAppAndStop'
$res3 = Invoke-MigBatch -Applications @('Contoso_TestAppV4_x64_2.5.1-0003_ENU', 'Contoso_NoContent_x64_1.0-1_MUL', 'Contoso_TestAppV3_x64_1.0.0-0001_MUL') 
T 'the earlier success is KEPT'      { @($res3 | Where-Object { $_.Status -eq 'Success' }).Count -eq 1 -and $global:SIM.CreatedApps.Count -eq 1 }
T 'the rest was not started'         { @($res3 | Where-Object { $_.Status -eq 'Not started' }).Count -eq 1 }
$script:Cfg.RollbackScope = 'FailedAppOnly'

Write-Host "`n=== no group pattern configured ===" -ForegroundColor Cyan
Reset-Sim; New-Run | Out-Null
$keepPat = $script:Cfg.UatGroupNamePattern
$script:Cfg.UatGroupNamePattern = ''
$rno = Invoke-MigApplication -DisplayName 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'
T 'the app is still created'   { $rno.Status -eq 'Success' -and $rno.AppId }
T 'no group name is reported'  { -not $rno.UatGroup }
$script:Cfg.UatGroupNamePattern = $keepPat

Write-Host ""
Write-Host "PASSED $pass   FAILED $fail" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
if ($fail) { exit 1 }
