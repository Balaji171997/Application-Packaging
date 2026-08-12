<#
    Undoes an integration: deployments, then collections, then the application.

        .\Remove-AudiIntegration.ps1 -JobFile <job.json> -WhatIf
        .\Remove-AudiIntegration.ps1 -JobFile <job.json>

    Order matters. A collection with a deployment on it cannot be removed, so
    deployments go first. The AD group is not removed either, because it is not
    created yet - see step 9 of Invoke-AudiIntegration.ps1.

    Nothing here is rolled back. Removal that stops halfway has removed real
    things; putting them back would be a fresh integration, not an undo. It
    reports exactly how far it got instead.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$JobFile,
    [string]$EnvironmentRoot = (Join-Path $PSScriptRoot 'Environments')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$real = -not $WhatIfPreference

$job = Get-Content -LiteralPath $JobFile -Raw | ConvertFrom-Json
$pkg = $job.Package

$environmentFile = Join-Path $EnvironmentRoot "$($job.Environment).psd1"
if (-not (Test-Path -LiteralPath $environmentFile)) { throw "No environment file for '$($job.Environment)'." }
$config = Import-PowerShellDataFile -LiteralPath $environmentFile

$appName = $pkg.Name
$steps   = New-Object System.Collections.Generic.List[object]

function Add-Step { param([string]$Name, [bool]$Ok, [string]$Detail)
    $steps.Add([pscustomobject]@{ Step = $Name; Ok = $Ok; Detail = $Detail }) | Out-Null
    Write-Host ("  {0}  {1,-22} {2}" -f $(if ($Ok) { 'OK    ' } else { 'FAILED' }), $Name, $Detail) `
        -ForegroundColor $(if ($Ok) { 'Green' } else { 'Red' })
}

Write-Host ""
Write-Host "Remove $appName from $($config.SiteCode)$(if (-not $real) { '   [WHAT IF - nothing will be removed]' })" -ForegroundColor Cyan
Write-Host ""

$startLocation = Get-Location
try {
    if ($real) {
        if (-not (Get-Module ConfigurationManager)) {
            if (-not $env:SMS_ADMIN_UI_PATH) { throw 'The ConfigMgr console is not installed here.' }
            Import-Module (Join-Path (Split-Path -Parent $env:SMS_ADMIN_UI_PATH) 'ConfigurationManager.psd1') `
                -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            if (-not (Get-Module ConfigurationManager)) { throw 'The ConfigMgr module could not be loaded.' }
        }
        if (-not (Get-PSDrive -Name $config.SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
            New-PSDrive -Name $config.SiteCode -PSProvider CMSite -Root $config.SiteServer -Scope Global `
                        -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
        }
        Set-Location "$($config.SiteCode):"
    }
    Add-Step 'Connect' $true "$($config.SiteCode) on $($config.SiteServer)"

    # ---- 1. deployments, before the collections they sit on
    foreach ($c in $config.Collections) {
        $collectionName = "$($c.Prefix)$($pkg.Name)$($c.Suffix)"
        if ($real) {
            if (Get-CMApplicationDeployment -Name $appName -CollectionName $collectionName -ErrorAction SilentlyContinue) {
                Remove-CMApplicationDeployment -Name $appName -CollectionName $collectionName -Force -ErrorAction Stop
            }
        }
        Add-Step 'Deployment' $true $collectionName
    }

    # ---- 2. the collections
    foreach ($c in $config.Collections) {
        $collectionName = "$($c.Prefix)$($pkg.Name)$($c.Suffix)"
        if ($real) {
            if (Get-CMDeviceCollection -Name $collectionName -ErrorAction SilentlyContinue) {
                Remove-CMDeviceCollection -Name $collectionName -Force -ErrorAction Stop
            }
        }
        Add-Step 'Collection' $true $collectionName
    }

    # ---- 3. the application
    if ($real) {
        if (Get-CMApplication -Name $appName -Fast -ErrorAction SilentlyContinue) {
            Remove-CMApplication -Name $appName -Force -ErrorAction Stop
        }
    }
    Add-Step 'Application' $true $appName

    # ---- 4. the AD group. Not created, so not removed. See step 9 of the engine.
    Add-Step 'AdGroup' $true 'SKIPPED - never created'

    $result = [pscustomobject]@{ Ok = $true; JobId = $job.JobId; Package = $appName
        Environment = $config.SiteCode; Message = 'Removed.'; Steps = $steps.ToArray(); RolledBack = @() }
}
catch {
    $reason = [string]$_.Exception.Message
    if (-not $reason) { $reason = 'Failed with no message.' }
    Add-Step 'FAILED' $false $reason
    $result = [pscustomobject]@{ Ok = $false; JobId = $job.JobId; Package = $appName
        Environment = $config.SiteCode
        Message = "$reason Removal stopped here - what is listed above as OK is already gone, the rest is still on the site."
        Steps = $steps.ToArray(); RolledBack = @() }
}
finally { Set-Location $startLocation }

Write-Host ""
Write-Host $result.Message -ForegroundColor $(if ($result.Ok) { 'Green' } else { 'Red' })
Write-Host ""
return $result
