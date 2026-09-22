# ==============================================================================
#  Creates the scheduled task that keeps the two drop folders in step.
#  Run ON THE MIDDLE SERVER, once, as a local administrator.
# ==============================================================================
#
#    .\Install-AudiSwDropFolderSync.ps1 -Account 'DEAUDI005T\svc-swsync$' `
#                                       -ClientRoot '\\packager-side\DropFolder' `
#                                       -ServerRoot '\\sccm-side\DropFolder' -WhatIf
#
#  The account needs MODIFY on both roots and nothing else - no SCCM rights,
#  no environment files. A gMSA is preferred (no password stored); an
#  ordinary service account works too, then Task Scheduler asks for its
#  password once at registration.
#  Removing it:  Unregister-ScheduledTask -TaskName 'Audi SW Integration - drop folder sync'
# ==============================================================================

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Account,
    # written into Sync-Settings.txt in the install folder; may be left out when
    # the Sync-Settings.txt beside this script is already filled in
    [string]$ClientRoot = '',
    [string]$ServerRoot = '',
    [string]$EnvironmentCode = '',
    [string]$TaskName    = 'Audi SW Integration - drop folder sync',
    [string]$InstallRoot = 'C:\Program Files\Audi\SwIntegration',
    [int]$EveryMinutes   = 2
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
    throw 'Run this on the middle server as a local administrator.'
}

Write-Host ''
Write-Host 'Audi SCCM Integration - drop folder sync (middle server)' -ForegroundColor Cyan
Write-Host ''

# ------------------------------------------------------------------- settings
# ALL PATHS LIVE IN Sync-Settings.txt next to the installed script - the task
# carries none. A path change is an edit to that file, never a re-install.
$settingsSource = Join-Path $PSScriptRoot 'Sync-Settings.txt'
$settingsLines  = @(if (Test-Path -LiteralPath $settingsSource) { Get-Content -LiteralPath $settingsSource } else { @('ClientRoot = ', 'ServerRoot = ', 'EnvironmentCode = ') })
$given = @{ ClientRoot = $ClientRoot; ServerRoot = $ServerRoot; EnvironmentCode = $EnvironmentCode }
$settingsLines = @($settingsLines | ForEach-Object {
    $line = $_
    foreach ($key in $given.Keys) { if ($given[$key] -and $line -match "^\s*$key\s*=") { $line = "$key = $($given[$key])" } }
    $line
})
foreach ($key in 'ClientRoot', 'ServerRoot') {
    $value = @($settingsLines | Where-Object { $_ -match "^\s*$key\s*=\s*(.+?)\s*$" } | ForEach-Object { $matches[1] })
    if ($value.Count -eq 0 -or -not $value[0]) { throw "Give -$key, or fill $key in $settingsSource first." }
    Set-Variable -Name $key -Value $value[0]
}

$target = Join-Path $InstallRoot 'DropFolderSync'
if ($PSCmdlet.ShouldProcess($target, 'Copy the sync script and its settings')) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'Sync-AudiSwDropFolders.ps1') -Destination $target -Force
    Set-Content -LiteralPath (Join-Path $target 'Sync-Settings.txt') -Value $settingsLines -Encoding UTF8
    Write-Host "  OK    Installed to $target" -ForegroundColor Green
    Write-Host "  OK    Paths in $(Join-Path $target 'Sync-Settings.txt')  (ClientRoot = $ClientRoot ; ServerRoot = $ServerRoot)" -ForegroundColor Green
}

if ($PSCmdlet.ShouldProcess($TaskName, 'Register the scheduled task')) {
    # no path on the command line - the script reads Sync-Settings.txt beside it
    $script = Join-Path $target 'Sync-AudiSwDropFolders.ps1'
    $arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`""
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
    $trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes $EveryMinutes)
    $principal = New-ScheduledTaskPrincipal -UserId $Account -LogonType Password -RunLevel Limited
    $settings  = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 4) -StartWhenAvailable -DontStopOnIdleEnd
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
                           -Description 'Keeps the packagers'' drop folder and the SCCM server''s in step: jobs and package content one way, results the other.' | Out-Null
    Write-Host "  OK    Scheduled task '$TaskName' created, running every $EveryMinutes minutes as $Account" -ForegroundColor Green
}

Write-Host ''
Write-Host '  Still required, and NOT done by this script:' -ForegroundColor Yellow
Write-Host "    - MODIFY for $Account on $ClientRoot"
Write-Host "    - MODIFY for $Account on $ServerRoot"
Write-Host ''
Write-Host "  To change a path later: edit $(Join-Path $target 'Sync-Settings.txt') - the next pass uses it." -ForegroundColor Cyan
Write-Host "  To remove:  Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false" -ForegroundColor Cyan
Write-Host ''
