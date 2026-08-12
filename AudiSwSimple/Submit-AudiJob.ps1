<#
    PACKAGER SIDE. Reads a package and drops a job file into the environment's
    drop folder. Nothing here connects to SCCM or needs any rights on it.

        .\Submit-AudiJob.ps1 -PackagePath C:\temp\II1_Lumivero_Citavi_x86_6.19.2.1-0002_MUL -Environment II1

    Show what would be written without writing it:

        .\Submit-AudiJob.ps1 -PackagePath ... -Environment II1 -WhatIf

    The job file names NO PERSON. Audi's rule: nothing on the SCCM side may
    identify a packager. The RFC number is the audit link instead - their change
    system already knows which person an RFC belongs to - which is why a job
    without one is refused here rather than on the server.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [Parameter(Mandatory = $true)][string]$Environment,

    # Read from the deployment script when not given.
    [string]$Rfc,

    [ValidateSet('Integrate', 'Remove')][string]$Action = 'Integrate'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$environmentFile = Join-Path $PSScriptRoot "Environments\$Environment.psd1"
if (-not (Test-Path -LiteralPath $environmentFile)) { throw "No environment file for '$Environment'. Expected $environmentFile." }
$config = Import-PowerShellDataFile -LiteralPath $environmentFile

$package = & (Join-Path $PSScriptRoot 'Read-AudiPackage.ps1') -PackagePath $PackagePath

# The package is named for the environment it belongs in. Refusing a mismatch is
# what stops an INA package being built on the ICZ site. The tool being replaced
# rewrote the first three characters instead, which is how ADO_ADOBE_Reader
# became INA_INABE_Reader.
if ($package.Site -ne $config.SiteCode) {
    throw "'$($package.Name)' is named for $($package.Site) but you are submitting it to $($config.SiteCode). Rename the package, or submit it to $($package.Site)."
}

if (-not $Rfc) { $Rfc = $package.Rfc }
if (-not $Rfc) { throw "No RFC number. It is read from VWG_OrderNumber in the deployment script, or pass -Rfc. With no name kept on the server it is the only record of who asked, so a job without one is refused." }

$job = [ordered]@{
    JobId       = [guid]::NewGuid().ToString()
    Action      = $Action
    Environment = $config.SiteCode
    Rfc         = $Rfc
    Submitted   = (Get-Date).ToString('o')
    Package     = $package
}

$newFolder = Join-Path $config.DropFolder 'New'
if (-not (Test-Path -LiteralPath $newFolder)) { New-Item -ItemType Directory -Path $newFolder -Force | Out-Null }

$file = Join-Path $newFolder ("{0}_{1}.json" -f $package.Name, $job.JobId)

if ($PSCmdlet.ShouldProcess($file, 'Write job file')) {
    # Written under a temporary name and renamed, so the watcher can never pick
    # up a half-written file.
    $temp = "$file.writing"
    $job | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $file -Force

    Write-Host ""
    Write-Host "Queued $($package.Name) for $($config.SiteCode)." -ForegroundColor Green
    Write-Host "  job     $($job.JobId)"
    Write-Host "  rfc     $Rfc"
    Write-Host "  file    $file"
    Write-Host ""
    Write-Host "The Script Runner picks it up on its next pass. The result appears in" -ForegroundColor DarkGray
    Write-Host "$($config.DropFolder)\Done or \Failed." -ForegroundColor DarkGray
}
else {
    Write-Host ""
    Write-Host "Would write $file" -ForegroundColor Yellow
    $job | ConvertTo-Json -Depth 5
}
