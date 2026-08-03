# ==============================================================================
#  Installs the Audi SCCM Integration endpoint on this server.   SCENARIO A
# ==============================================================================
#  Run ON the server, once, as a local administrator, under a change record.
#
#    .\Install-AudiSwEndpoint.ps1 -Gmsa 'DEAUDI005T\svc-swintegration$' `
#                                 -OperatorGroup 'DEAUDI005T\G-Audi-SwIntegration-Operators' `
#                                 -WhatIf
#
#  Re-running is safe: it unregisters and re-registers cleanly.
#  Removing it entirely:  Unregister-PSSessionConfiguration -Name AudiSwIntegration
#
#  What it does NOT do, deliberately:
#    * it does not create the gMSA or the group   - that is the AD team
#    * it does not grant any SCCM rights          - that is the SCCM team
#    * it does not open any firewall port         - that is the network team
#  It only verifies those exist and then registers the endpoint.
# ==============================================================================

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    # e.g. DEAUDI005T\svc-swintegration$   (note the trailing $ on a gMSA)
    [Parameter(Mandatory = $true)][string]$Gmsa,

    # e.g. DEAUDI005T\G-Audi-SwIntegration-Operators
    [Parameter(Mandatory = $true)][string]$OperatorGroup,

    [string]$ConfigurationName = 'AudiSwIntegration',
    [string]$InstallRoot       = 'C:\Program Files\Audi\SwIntegration',
    [string]$TranscriptRoot    = 'C:\ProgramData\Audi\SwIntegration\Transcripts',
    [switch]$SkipChecks
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Text) Write-Host "  $Text" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "  OK    $Text" -ForegroundColor Green }
function Write-Bad  { param([string]$Text) Write-Host "  FAIL  $Text" -ForegroundColor Red }

Write-Host ''
Write-Host "Audi SCCM Integration - endpoint installation" -ForegroundColor Cyan
Write-Host ''

# --------------------------------------------------------------- prerequisites
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
    throw 'Run this on the server as a local administrator.'
}

if (-not $SkipChecks) {
    Write-Step 'Checking prerequisites'

    # 1. the ConfigMgr console must be present, or the engine has nothing to call
    if ($env:SMS_ADMIN_UI_PATH -and (Test-Path (Join-Path (Split-Path -Parent $env:SMS_ADMIN_UI_PATH) 'ConfigurationManager.psd1'))) {
        Write-Ok 'ConfigMgr console found.'
    } else {
        Write-Bad 'The ConfigMgr console is not installed here. The engine needs it to reach the site.'
        throw 'Install the ConfigMgr console on this server first.'
    }

    # 2. the gMSA must be installed on THIS machine and usable
    $account = $Gmsa.Split('\')[-1].TrimEnd('$')
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        if (Test-ADServiceAccount -Identity $account) { Write-Ok "gMSA '$Gmsa' is installed and usable on this server." }
        else {
            Write-Bad "gMSA '$Gmsa' is not usable here."
            throw "Ask the AD team to add this server to the gMSA's PrincipalsAllowedToRetrieveManagedPassword, then run: Install-ADServiceAccount -Identity $account"
        }
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        Write-Host '  WARN  RSAT ActiveDirectory module not present - cannot verify the gMSA. Continuing.' -ForegroundColor Yellow
    }

    # 3. the operator group must resolve
    try {
        $null = (New-Object System.Security.Principal.NTAccount($OperatorGroup)).Translate([System.Security.Principal.SecurityIdentifier])
        Write-Ok "Operator group '$OperatorGroup' resolves."
    }
    catch { Write-Bad "Operator group '$OperatorGroup' does not resolve."; throw 'Ask the AD team to create it first.' }

    # 4. WinRM must be listening
    if ((Get-Service WinRM).Status -eq 'Running') { Write-Ok 'WinRM is running.' }
    else { Write-Bad 'WinRM is not running.'; throw 'Start WinRM (Enable-PSRemoting) before installing the endpoint.' }
}

# ------------------------------------------------------------------- copy files
$engineSource = Join-Path $PSScriptRoot 'Engine'
$moduleTarget = Join-Path $InstallRoot 'Modules\AudiSwIntegration'
$capTarget    = Join-Path $moduleTarget 'RoleCapabilities'

Write-Step "Installing the engine to $InstallRoot"
if ($PSCmdlet.ShouldProcess($InstallRoot, 'Copy the engine')) {
    New-Item -ItemType Directory -Path $moduleTarget -Force | Out-Null
    New-Item -ItemType Directory -Path $capTarget    -Force | Out-Null
    New-Item -ItemType Directory -Path $TranscriptRoot -Force | Out-Null
    Copy-Item (Join-Path $engineSource '*') -Destination $moduleTarget -Recurse -Force

    # a manifest so the role capability can import it by name
    $manifest = Join-Path $moduleTarget 'AudiSwIntegration.psd1'
    New-ModuleManifest -Path $manifest -RootModule 'AudiSwIntegration.ps1' -ModuleVersion '1.0.0' `
                       -Author 'I-DI-D' -CompanyName 'Volkswagen Group' `
                       -Description 'Audi SCCM software integration engine' `
                       -PowerShellVersion '5.1' -FunctionsToExport '*'
    Copy-Item (Join-Path $PSScriptRoot 'Endpoint\AudiSwIntegration.psrc') -Destination $capTarget -Force
    Write-Ok "Engine installed. Module path: $moduleTarget"
}

# --------------------------------------------------------- build the .pssc file
Write-Step 'Preparing the session configuration'
$psscTemplate = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Endpoint\AudiSwIntegration.pssc') -Raw
$pssc = $psscTemplate.Replace('__GMSA__', $Gmsa).
                      Replace('__OPERATORGROUP__', $OperatorGroup).
                      Replace('__TRANSCRIPTS__', $TranscriptRoot)
$psscPath = Join-Path $env:TEMP "AudiSwIntegration_$([guid]::NewGuid().ToString('N')).pssc"

if ($PSCmdlet.ShouldProcess($ConfigurationName, 'Register the endpoint')) {
    Set-Content -LiteralPath $psscPath -Value $pssc -Encoding UTF8
    try {
        # the module folder must be on the machine PSModulePath for the session to find it
        $machinePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
        $moduleRoot  = Join-Path $InstallRoot 'Modules'
        if ($machinePath -notlike "*$moduleRoot*") {
            [Environment]::SetEnvironmentVariable('PSModulePath', "$machinePath;$moduleRoot", 'Machine')
            $env:PSModulePath = "$env:PSModulePath;$moduleRoot"
            Write-Ok "Added $moduleRoot to the machine module path."
        }

        if (Get-PSSessionConfiguration -Name $ConfigurationName -ErrorAction SilentlyContinue) {
            Write-Step "Removing the existing '$ConfigurationName' endpoint"
            Unregister-PSSessionConfiguration -Name $ConfigurationName -Force -NoServiceRestart
        }

        Register-PSSessionConfiguration -Name $ConfigurationName -Path $psscPath -Force | Out-Null
        Write-Ok "Endpoint '$ConfigurationName' registered."
    }
    finally { Remove-Item -LiteralPath $psscPath -Force -ErrorAction SilentlyContinue }
}

# ------------------------------------------------------------------- summary
Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host ''
Write-Host '  Test from a packager PC with:' -ForegroundColor Cyan
Write-Host "    Invoke-Command -ComputerName $env:COMPUTERNAME -ConfigurationName $ConfigurationName -ScriptBlock { Get-AudiEnvironmentCode }"
Write-Host ''
Write-Host '  Still required, and NOT done by this script:' -ForegroundColor Yellow
Write-Host '    - a firewall rule allowing the packaging subnet to reach this server on 5985/5986'
Write-Host "    - SCCM rights for $Gmsa (the same rights a packager holds today)"
Write-Host "    - read/write for $Gmsa on the package content share"
Write-Host "    - rights for $Gmsa to create and delete groups in the ARS target OU"
Write-Host ''
Write-Host "  To remove:  Unregister-PSSessionConfiguration -Name $ConfigurationName -Force" -ForegroundColor Cyan
Write-Host ''
