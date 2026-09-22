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
#
#  -Workers 3 registers three tasks on the same folder ("... #1", "#2", "#3"),
#  started a minute apart, so three packages are integrated at the same time.
#  Safe: a job is claimed by an atomic move, so two workers can never run the
#  same one, and one job per package at a time still holds across workers.
# ==============================================================================

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Gmsa,
    # the SCCM-side drop folder, this environment's subfolder. Written into
    # Watcher-Settings.txt in the install folder; may be left out when that file
    # beside this script is already filled in
    [string]$DropFolder   = '',
    [string]$TaskName     = 'Audi SW Integration - collect jobs',
    [string]$InstallRoot  = 'C:\Program Files\Audi\SwIntegration',
    [int]$EveryMinutes    = 3,
    # how many jobs run side by side - one task each
    [ValidateRange(1, 8)][int]$Workers = 1
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
    throw 'Run this on the server as a local administrator.'
}

Write-Host ''
Write-Host 'Audi SCCM Integration - drop folder watcher' -ForegroundColor Cyan
Write-Host ''

# ------------------------------------------------------------------- settings
# ALL PATHS LIVE IN Watcher-Settings.txt next to the installed script - the task
# carries none. A path change is an edit to that file, never a re-install.
$settingsSource = Join-Path $PSScriptRoot 'Watcher-Settings.txt'
$settingsLines  = @(if (Test-Path -LiteralPath $settingsSource) { Get-Content -LiteralPath $settingsSource } else { @('DropFolder = ', 'EngineRoot = ', 'MaxJobsPerRun = 10') })
if ($DropFolder) {
    $settingsLines = @($settingsLines | ForEach-Object { if ($_ -match '^\s*DropFolder\s*=') { "DropFolder = $DropFolder" } else { $_ } })
} else {
    $fromFile = @($settingsLines | Where-Object { $_ -match '^\s*DropFolder\s*=\s*(.+?)\s*$' } | ForEach-Object { $matches[1] })
    if ($fromFile.Count -eq 0 -or -not $fromFile[0]) { throw "Give -DropFolder, or fill DropFolder in $settingsSource first." }
    $DropFolder = $fromFile[0]
}

# ------------------------------------------------------------------- copy files
$target = Join-Path $InstallRoot 'Watcher'
if ($PSCmdlet.ShouldProcess($target, 'Copy the engine, the watcher and its settings')) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'Engine') -Destination $target -Recurse -Force
    Copy-Item (Join-Path $PSScriptRoot 'Watch-AudiSwDropFolder.ps1') -Destination $target -Force
    Set-Content -LiteralPath (Join-Path $target 'Watcher-Settings.txt') -Value $settingsLines -Encoding UTF8
    Write-Host "  OK    Watcher installed to $target" -ForegroundColor Green
    Write-Host "  OK    Paths in $(Join-Path $target 'Watcher-Settings.txt')  (DropFolder = $DropFolder)" -ForegroundColor Green
}

# ------------------------------------------------------------- the folder itself
if ($PSCmdlet.ShouldProcess($DropFolder, 'Create the drop folder structure')) {
    foreach ($sub in 'New', 'Working', 'Done', 'Failed', 'Sources') {
        $path = Join-Path $DropFolder $sub
        if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    }
    Write-Host "  OK    Drop folder ready: $DropFolder" -ForegroundColor Green
    Write-Host '        Packagers need CREATE FILES on \New only - not read, not delete.' -ForegroundColor Yellow
    Write-Host "        $Gmsa needs full control on all four subfolders." -ForegroundColor Yellow
}

# ------------------------------------------------------------------ the task
# no path on the command line - the script reads Watcher-Settings.txt beside it
$script = Join-Path $target 'Watch-AudiSwDropFolder.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`"")

# gMSA principal: Task Scheduler retrieves the password from AD itself
$principal = New-ScheduledTaskPrincipal -UserId $Gmsa -LogonType Password -RunLevel Highest

# one task may not overlap itself; several tasks side by side are the workers
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
                -ExecutionTimeLimit (New-TimeSpan -Hours 4) `
                -StartWhenAvailable -DontStopOnIdleEnd

# the single task keeps its plain name; workers are numbered
$names = @(if ($Workers -eq 1) { $TaskName } else { 1..$Workers | ForEach-Object { "$TaskName #$_" } })
# whichever shape was installed before is removed, so a change of -Workers never leaves strays
foreach ($old in @(Get-ScheduledTask -TaskName "$TaskName*" -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($old.TaskName, 'Remove the earlier task')) { Unregister-ScheduledTask -TaskName $old.TaskName -Confirm:$false }
}
for ($i = 0; $i -lt $names.Count; $i++) {
    if (-not $PSCmdlet.ShouldProcess($names[$i], 'Register the scheduled task')) { continue }
    # every N minutes, indefinitely; workers start a minute apart so they do not
    # all look at the queue in the same second
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).Date.AddMinutes($i)) `
                   -RepetitionInterval (New-TimeSpan -Minutes $EveryMinutes)
    Register-ScheduledTask -TaskName $names[$i] -Action $action -Trigger $trigger `
                           -Principal $principal -Settings $settings `
                           -Description 'Collects Audi SCCM integration jobs from the drop folder and runs them as the service account.' | Out-Null
    Write-Host "  OK    Scheduled task '$($names[$i])' created, running every $EveryMinutes minutes as $Gmsa" -ForegroundColor Green
}
if ($Workers -gt 1) { Write-Host "        $Workers workers: up to $Workers packages are integrated at the same time." -ForegroundColor Green }
Write-Host ''
Write-Host "  To change a path later: edit $(Join-Path $target 'Watcher-Settings.txt') - the next pass uses it." -ForegroundColor Cyan

Write-Host ''
Write-Host '  Still required, and NOT done by this script:' -ForegroundColor Yellow
Write-Host '    - share and NTFS rights on the drop folder (see above)'
Write-Host "    - SCCM rights for $Gmsa"
Write-Host "    - read/write for $Gmsa on the package content share"
Write-Host "    - rights for $Gmsa in the ARS target OU"
Write-Host ''
Write-Host "  To remove:  Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false" -ForegroundColor Cyan
Write-Host ''
