# ==============================================================================
#  Creates the scheduled task that collects jobs from the drop folder.  SCENARIO B
# ==============================================================================
#  Run ON the server, once, as a local administrator, under a change record.
#
#    .\Install-AudiSwDropWatcher.ps1 -Gmsa 'DEAUDI005T\svc-swintegration$' `
#                                    -DropFolder '\\audiinsv1059\SwIntegration-Inbox$' `
#                                    -WhatIf
#
#  The task runs as the gMSA, so no password is stored in Task Scheduler either.
#  Removing it:  Unregister-ScheduledTask -TaskName 'Audi SW Integration - collect jobs'
# ==============================================================================

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Gmsa,
    [Parameter(Mandatory = $true)][string]$DropFolder,
    [string]$TaskName     = 'Audi SW Integration - collect jobs',
    [string]$InstallRoot  = 'C:\Program Files\Audi\SwIntegration',
    [int]$EveryMinutes    = 3
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
    throw 'Run this on the server as a local administrator.'
}

Write-Host ''
Write-Host 'Audi SCCM Integration - drop folder watcher' -ForegroundColor Cyan
Write-Host ''

# ------------------------------------------------------------------- copy files
$target = Join-Path $InstallRoot 'Watcher'
if ($PSCmdlet.ShouldProcess($target, 'Copy the engine and watcher')) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'Engine') -Destination $target -Recurse -Force
    Copy-Item (Join-Path $PSScriptRoot 'Watch-AudiSwDropFolder.ps1') -Destination $target -Force
    Write-Host "  OK    Watcher installed to $target" -ForegroundColor Green
}

# ------------------------------------------------------------- the folder itself
if ($PSCmdlet.ShouldProcess($DropFolder, 'Create the drop folder structure')) {
    foreach ($sub in 'New', 'Working', 'Done', 'Failed') {
        $path = Join-Path $DropFolder $sub
        if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    }
    Write-Host "  OK    Drop folder ready: $DropFolder" -ForegroundColor Green
    Write-Host '        Packagers need CREATE FILES on \New only - not read, not delete.' -ForegroundColor Yellow
    Write-Host "        $Gmsa needs full control on all four subfolders." -ForegroundColor Yellow
}

# ------------------------------------------------------------------ the task
if ($PSCmdlet.ShouldProcess($TaskName, 'Register the scheduled task')) {
    $script = Join-Path (Join-Path $target 'Watch-AudiSwDropFolder.ps1') ''
    $script = Join-Path $target 'Watch-AudiSwDropFolder.ps1'

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument ("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`" -DropFolder `"$DropFolder`"")

    # every N minutes, indefinitely
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
                   -RepetitionInterval (New-TimeSpan -Minutes $EveryMinutes)

    # gMSA principal: Task Scheduler retrieves the password from AD itself
    $principal = New-ScheduledTaskPrincipal -UserId $Gmsa -LogonType Password -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
                    -ExecutionTimeLimit (New-TimeSpan -Hours 4) `
                    -StartWhenAvailable -DontStopOnIdleEnd

    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
                           -Principal $principal -Settings $settings `
                           -Description 'Collects Audi SCCM integration jobs from the drop folder and runs them as the service account.' | Out-Null
    Write-Host "  OK    Scheduled task '$TaskName' created, running every $EveryMinutes minutes as $Gmsa" -ForegroundColor Green
}

Write-Host ''
Write-Host '  Still required, and NOT done by this script:' -ForegroundColor Yellow
Write-Host '    - share and NTFS rights on the drop folder (see above)'
Write-Host "    - SCCM rights for $Gmsa"
Write-Host "    - read/write for $Gmsa on the package content share"
Write-Host "    - rights for $Gmsa in the ARS target OU"
Write-Host ''
Write-Host "  To remove:  Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false" -ForegroundColor Cyan
Write-Host ''
