<#
.SYNOPSIS
    SAP GUI 8 - Install Reminder (PSAppDeployToolkit v4)
.DESCRIPTION
    Deployed as a REQUIRED Win32 app to SAP GUI 7 users.

    The Intune DETECTION RULE for this app is SAP GUI 8 itself
    (C:\Program Files\SAP\FrontEnd\SAPgui\saplogon.exe exists).

    While SAP 8 is missing, this package shows a PSADT prompt asking the
    user to install SAP GUI 8; the "Install now" button opens the SAP 8
    page in Company Portal. Because detection then still fails, Intune
    automatically re-runs the package on its retry cycle (a few attempts
    on day one, then roughly daily) - so the reminder repeats WITHOUT any
    scheduled task. Once the user installs SAP 8, detection passes and
    the reminders stop for good.

    This package never installs, uninstalls, or modifies SAP.
.NOTES
    Drop over the stock PSADT v4 template folder. No Files/SupportFiles needed.
    >>> FILL IN $Sap8IntuneAppId below before packaging.
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType = 'Install',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode = 'Auto',

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging
)

##================================================
## MARK: Variables
##================================================

$adtSession = @{
    AppVendor                   = 'SAP'
    AppName                     = 'SAP GUI 8 Install Reminder'
    AppVersion                  = '1.0.0'
    AppArch                     = 'x64'
    AppLang                     = 'EN'
    AppRevision                 = '01'
    AppSuccessExitCodes         = @(0)
    AppRebootExitCodes          = @(1641, 3010)
    AppScriptVersion            = '1.0.0'
    AppScriptDate               = '2026-07-02'
    AppScriptAuthor             = 'Packaging Team'
    RequireAdmin                = $true
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters   = $PSBoundParameters
}


## Adjust if your SAP installs land elsewhere (7.x = 32-bit, 8 = 64-bit).
#$script:Sap7Exe = Join-Path ${env:ProgramFiles(x86)} 'SAP\FrontEnd\SAPgui\saplogon.exe'
#$script:Sap8Exe = Join-Path $env:ProgramFiles       'SAP\FrontEnd\SAPgui\saplogon.exe'

##================================================
## MARK: Install
##================================================
function Install-ADTDeployment
{
    ## Already on SAP 8 (or SAP not installed at all): exit quietly.
    <## Detection will pass / the app is not needed - no prompt.
    if (Test-Path -LiteralPath "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SAPGUI7")
    {
        Write-ADTLogEntry -Message 'SAP GUI 8 already installed - no reminder needed.'
        return
    }
    if (-not (Test-Path -LiteralPath "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SAPGUI7*"))
    {
        Write-ADTLogEntry -Message 'SAP GUI not installed on this device - no reminder needed.'
        return
    }#>

    ## Show the reminder. PersistPrompt keeps it in front until answered;
    ## on timeout we exit gracefully and Intune simply retries later.
    $choice = Show-ADTInstallationPrompt `
        -Message ("Your PC is still running SAP GUI 7, which is being retired.`n`n" +
                  "Please install SAP GUI 8 from Company Portal - click ""Install now"" below, " +
                  "then click Install on the SAP GUI 8 page.`n`n" +
                  "You can keep working while it installs. If you choose ""Later"", " +
                  "this reminder will appear again.") `
        -Title 'SAP GUI update required' `
        -Icon Information `
        -ButtonLeftText 'Later' `
        -ButtonRightText 'Install now' `
        -PersistPrompt `
        -Timeout 1800 `
        -NoExitOnTimeout

    if ($choice -eq 'Install now')
    {
        Write-ADTLogEntry -Message "User chose Install now - opening Company Portal deep link."
        ## Open the SAP 8 page in Company Portal in the user's session.
        Start-ADTProcessAsUser -FilePath "explorer.exe" -ArgumentList "companyportal:ApplicationId=1ef97787-2d22-4bd5-ac6d-d9262a948603"
    }
    else
    {
        Write-ADTLogEntry -Message "User deferred ($choice) - Intune will retry on the next cycle."
    }

    ## Exit 0 either way. Intune will report 'installed but not detected'
    ## until SAP 8 is on the machine, which keeps the retry loop alive.
}

##================================================
## MARK: Uninstall
##================================================
function Uninstall-ADTDeployment
{
    ## Nothing installed on the machine - nothing to remove.
    Write-ADTLogEntry -Message 'Reminder app leaves no footprint - nothing to uninstall.'
}

##================================================
## MARK: Repair
##================================================
function Repair-ADTDeployment
{
    Install-ADTDeployment
}

##================================================
## MARK: Initialization (stock v4 template bootstrap - do not modify)
##================================================

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

try
{
    $moduleName = if ([System.IO.File]::Exists("$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"))
    {
        Get-ChildItem -LiteralPath $PSScriptRoot\PSAppDeployToolkit -Recurse -File | Unblock-File -ErrorAction Ignore
        "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"
    }
    else
    {
        'PSAppDeployToolkit'
    }
    Import-Module -FullyQualifiedName @{ ModuleName = $moduleName; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.0.0' } -Force
    try
    {
        $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
        $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
        $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
    }
    catch
    {
        Remove-Module -Name PSAppDeployToolkit* -Force
        throw
    }
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}

##================================================
## MARK: Invocation
##================================================

try
{
    & "$($DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch
{
    Write-ADTLogEntry -Message ($mainErrorMessage = Resolve-ADTErrorRecord -ErrorRecord $_) -Severity 3
    Close-ADTSession -ExitCode 60001
}
finally
{
    Remove-Module -Name PSAppDeployToolkit* -Force -ErrorAction SilentlyContinue
}
