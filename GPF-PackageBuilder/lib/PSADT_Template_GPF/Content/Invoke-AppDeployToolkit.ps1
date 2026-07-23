## Modified by AUDI AG (26/02/2026) under the provisions of the LGPLv3 or any later version.
<#

.SYNOPSIS
PSAppDeployToolkit - This script performs the installation or uninstallation of an application(s).

.DESCRIPTION
- The script is provided as a template to perform an install, uninstall, or repair of an application(s).
- The script either performs an "Install", "Uninstall", or "Repair" deployment type.
- The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

The script imports the PSAppDeployToolkit module which contains the logic and functions required to install or uninstall an application.

.PARAMETER DeploymentType
The type of deployment to perform.

.PARAMETER DeployMode
Specifies whether the installation should be run in Interactive (shows dialogs), Silent (no dialogs), NonInteractive (dialogs without prompts) mode, or Auto (shows dialogs if a user is logged on, device is not in the OOBE, and there's no running apps to close).

Silent mode is automatically set if it is detected that the process is not user interactive, no users are logged on, the device is in Autopilot mode, or there's specified processes to close that are currently running.

.PARAMETER SuppressRebootPassThru
Suppresses the 3010 return code (requires restart) from being passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

.PARAMETER TerminalServerMode
Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

.PARAMETER DisableLogging
Disables logging to file for the script.

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeployMode Silent

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeploymentType Uninstall

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent

.INPUTS
None. You cannot pipe objects to this script.

.OUTPUTS
None. This script does not generate any output.

.NOTES
Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Invoke-AppDeployToolkit.ps1, and Invoke-AppDeployToolkit.exe
- 69000 - 69999: Recommended for user customized exit codes in Invoke-AppDeployToolkit.ps1
- 70000 - 79999: Recommended for user customized exit codes in PSAppDeployToolkit.Extensions module.

.LINK
https://psappdeploytoolkit.com

#>

[CmdletBinding()]
param
(
    # Default is 'Install'.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType,

    # Default is 'Auto'. Don't hard-code this unless required.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru = $false,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode = $false,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging = $false
)


##================================================
## MARK: Variables
##================================================

# Zero-Config MSI support is provided when "AppName" is null or empty.
# By setting the "AppName" property, Zero-Config MSI will be disabled.
$Global:adtSession = @{
    ## Variables: Application
    AppVendor              = '{Manufacturer}'
    AppName                = '{Softwarename}'
    AppVersion             = '{Version}'
    AppArch                = '{Architecture}'
    AppLang                = '{Language}'
    AppRevision            = '{Revision}'
    AppSuccessExitCodes    = @(0)
    AppRebootExitCodes     = @(1641, 3010)
    AppProcessesToClose    = @()
    
    ## Variables: Script
    AppScriptVersion = '1.0.0'
    AppScriptDate    = '{Date}'
    AppScriptAuthor  = '{Author}'
    RequireAdmin     = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName  = ''
    InstallTitle = ''

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters   = $PSBoundParameters
    DeployAppScriptVersion      = '4.1.5'
}

#region Wrapper Variables
    ##================================================
    ## MARK: Wrapper Variables
    ##================================================

    ## Variables: Script
	[string] $Global:appScriptVersion		= $adtSession.AppScriptVersion
	[string] $Global:appScriptDate			= $adtSession.AppScriptDate
	[string] $Global:appScriptAuthor		= $adtSession.AppScriptAuthor
	
    ## Variables: Application
	[string] $Global:appVendor				= $adtSession.AppVendor
	[string] $Global:appName				= $adtSession.AppName
	[string] $Global:appArch				= $adtSession.AppArch
	[string] $Global:appVersion			    = $adtSession.AppVersion
	[string] $Global:appRevision			= $adtSession.AppRevision
	[string] $Global:appLang				= $adtSession.AppLang

	## Variables: Install Title Only set here to override defaults set by the toolkit
	[string] $Global:installName			= $adtSession.installName
	[string] $Global:installTitle			= $adtSession.installTitle

	## Variables: Wrapper
	[string] $Global:VWG_appfriendlyName	= $appName

	[string[]] $Global:VWG_ProcToClose		= $adtSession.AppProcessesToClose
	[string[]] $Global:VWG_ProcToCloseNonUI	= @()
	[string[]] $Global:VWG_ProcToBlock		= $VWG_ProcToClose

	[int32]  $Global:VWG_FreeSpace			= ''
    [int32]  $Global:VWG_FreeSpaceUninst    = '200'
	[boolean]$Global:VWG_CheckForReboot	    = $false
	[boolean]$Global:VWG_ShowBalloonTips	= $true
	[boolean]$Global:VWG_UseDialogs		    = $true
	[boolean]$Global:VWG_AllowDefer		    = $false

	[string] $Global:VWG_Layout			    = 'Full'
	[string] $Global:VWG_SoftinstTyp		= '{Typ}'
	[string] $Global:VWG_SoftIdent			= ''
	[boolean]$Global:VWG_SetBrandingReg	    = $true

	[string] $Global:VWG_Portfv			    = ''
	[string] $Global:VWG_OrderNumber		= ''
	[string] $Global:VWG_AppAddInfo01		= 'NA'
	[string] $Global:VWG_AppAddInfo02		= 'NA'
	[string] $Global:VWG_AppAddInfo03		= 'NA'
	[string] $Global:VWG_AppAddInfo04		= 'NA'

	[string] $Global:VWG_appFullName		= $appVendor + "_" + $appName + "_" + $appArch + "_" + $appVersion + "-" + $appRevision + "_" + $appLang
    ## Default Deployment type set to Install for logfile
    If(!($deploymentType -eq "Uninstall") -and !($deploymentType -eq "Repair")){ $deploymentType = 'Install'}
	[string] $adtSession.LogName	        = $VWG_appFullName + "_" + $deploymentType + ".log"
    [string] $Global:logName                = $adtSession.logname

    ## Variables: Script
    [String]   $Global:deployAppScriptFriendlyName = $adtSession.DeployAppScriptFriendlyName
    [Version]  $Global:deployAppScriptVersion      = $adtSession.DeployAppScriptVersion    
    [Hashtable]$Global:deployAppScriptParameters   = $adtSession.DeployAppScriptParameters

#endregion Wrapper Variables

##================================================
## MARK: Initialization
##================================================

# Set strict error handling across entire operation.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

# Import the module and instantiate a new session.
try
{
    # Import the module locally if available, otherwise try to find it from PSModulePath.
    if (Test-Path -LiteralPath "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -PathType Leaf)
    {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.5' } -Force
    }
    else
    {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.5' } -Force
    }

    # Open a new deployment session, replacing $adtSession with a DeploymentSession.
    $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
    $adtConfig  = Get-ADTConfig
    # Import any found extensions before proceeding with the deployment.
    Get-ChildItem -LiteralPath $PSScriptRoot -Directory | & {
        process
        {
            if ($_.Name -match 'PSAppDeployToolkit\..+$')
            {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
                Import-Module -Name $_.FullName -Force
            }
        }
    }
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}

#region CUSTOM APPLICATION VARIABLES AND FUNCTIONS
##================================================
## CUSTOM APPLICATION VARIABLES BEGIN
##================================================
#*====================================CUSTOM APPLICATION VARIABLES BEGIN=========================================================


#*====================================CUSTOM APPLICATION VARIABLES END===========================================================
##================================================
## CUSTOM APPLICATION VARIABLES END
##================================================
##================================================
## CUSTOM APPLICATION FUNCTIONS BEGIN
##================================================
#*====================================CUSTOM APPLICATION FUNCTIONS BEGIN=========================================================


#*====================================CUSTOM APPLICATION FUNCTIONS END===========================================================
##================================================
## CUSTOM APPLICATION FUNCTIONS END
##================================================

#endregion CUSTOM APPLICATION VARIABLES AND FUNCTIONS

function Install-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
    $Global:SessionDeploymentType = $($adtSession.DeploymentType)

    #*====================================PRE-INSTALLATION BEGIN==================================================================
		# check for pending reboot and stop script execution on true with exit code 1641, if not running in task sequence.
		if ($VWG_CheckForReboot){
			Set-Reboot -ForceExitScript -OnlyOnPendingReboot -MandatoryDeviceRestart
		}

		# user dialogs (deprecated)
		if ($VWG_UseDialogs){
			if ($VWG_AllowDefer){
				Show-ADTInstallationWelcome -AllowDefer -DeferTimes 4
			}
			if ($VWG_ProcToClose) {
				Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace "$VWG_FreeSpace" -CloseProcesses $VWG_ProcToClose -AllowDeferCloseProcesses -DeferTimes 4
			}
			if ($VWG_ProcToCloseNonUI) {
				Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace "$VWG_FreeSpace" -CloseProcesses $VWG_ProcToCloseNonUI -Silent
			}
			if (!($VWG_ProcToClose) -or !($VWG_ProcToCloseNonUI)) {
				Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace "$VWG_FreeSpace"
			}
			if ($VWG_ProcToBlock) {
				Show-ADTInstallationWelcome -CloseProcesses $VWG_ProcToBlock -AllowDeferCloseProcesses -DeferTimes 4 -BlockExecution
			}
		}
    #*====================================PRE-INSTALLATION END==================================================================




    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    #*====================================MAIN-INSTALLATION BEGIN==================================================================
	    # user dialogs (deprecated)
	    If ($VWG_UseDialogs){
		    ## Only use for longer installations (Installation duration approx. >3 minutes)
		    #Show-ADTInstallationProgress
	    }


        Write-ADTLogEntry -Message "Start Installation $appVendor $appName $appVersion." -Severity 2 -Source $adtSession.DeployAppScriptFriendlyName
        
                

        Write-ADTLogEntry -Message "Installation of $appVendor $appName $appVersion." -Severity 2 -Source $adtSession.DeployAppScriptFriendlyName
    #*====================================MAIN-INSTALLATION END==================================================================


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"



    #*====================================POST-INSTALLATION BEGIN==================================================================
	    ## Branding Install
	    Set-Branding

	    ## Handling for required reboot
        #Set-Reboot
    #*====================================POST-INSTALLATION END==================================================================
}

function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
    $Global:SessionDeploymentType = $($adtSession.DeploymentType)

    #*====================================PRE-UNINSTALLATION BEGIN==================================================================
		# check for pending reboot and stop script execution on true with exit code 1641, if not running in task sequence.
		if ($VWG_CheckForReboot){
			Set-Reboot -ForceExitScript -OnlyOnPendingReboot -MandatoryDeviceRestart
		}

		# user dialogs (deprecated)
		if ($VWG_UseDialogs){
			if ($VWG_AllowDefer){
				Show-ADTInstallationWelcome -AllowDefer -DeferTimes 4
			}
			if ($VWG_ProcToClose) {
				Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace "$VWG_FreeSpaceUninst" -CloseProcesses $VWG_ProcToClose -AllowDeferCloseProcesses -DeferTimes 4
			}
			if ($VWG_ProcToCloseNonUI) {
				Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace "$VWG_FreeSpaceUninst" -CloseProcesses $VWG_ProcToCloseNonUI -Silent
			}
			if (!($VWG_ProcToClose) -or !($VWG_ProcToCloseNonUI)) {
				Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace "$VWG_FreeSpaceUninst"
			}
			if ($VWG_ProcToBlock) {
				Show-ADTInstallationWelcome -CloseProcesses $VWG_ProcToBlock -AllowDeferCloseProcesses -DeferTimes 4 -BlockExecution
			}
		}
    #*====================================PRE-UNINSTALLATION END==================================================================




    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    #*====================================MAIN-UNINSTALLATION BEGIN==================================================================
	    # user dialogs (deprecated)
	    If ($VWG_UseDialogs){
		    ## Only use for longer installations (Installation duration approx. >3 minutes)
		    #Show-ADTInstallationProgress
	    }


        Write-ADTLogEntry -Message "Start Uninstallation $appVendor $appName $appVersion." -Severity 2 -Source $adtSession.DeployAppScriptFriendlyName	   
	   
        

        Write-ADTLogEntry -Message "Uninstallation of $appVendor $appName $appVersion." -Severity 2 -Source $adtSession.DeployAppScriptFriendlyName
    #*====================================MAIN-UNINSTALLATION END==================================================================

    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
        

    #*====================================POST-UNINSTALLATION BEGIN==================================================================
        ## Branding Uninstall
	    Remove-Branding

	    ## Handling for required reboot
        #Set-Reboot
    #*====================================POST-UNINSTALLATION END==================================================================
}

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Repair
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
    $Global:SessionDeploymentType = $($adtSession.DeploymentType)

    #*====================================PRE-REPAIR BEGIN==================================================================
		# check for pending reboot and stop script execution on true with exit code 1641, if not running in task sequence.
		if ($VWG_CheckForReboot){
			Set-Reboot -ForceExitScript -OnlyOnPendingReboot -MandatoryDeviceRestart
		}

		# user dialogs (deprecated)
		if ($VWG_UseDialogs){
			if ($VWG_AllowDefer){
				Show-ADTInstallationWelcome -AllowDefer -DeferTimes 4
			}
			if ($VWG_ProcToClose) {
				Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace "$VWG_FreeSpace" -CloseProcesses $VWG_ProcToClose -AllowDeferCloseProcesses -DeferTimes 4
			}
			if ($VWG_ProcToCloseNonUI) {
				Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace "$VWG_FreeSpace" -CloseProcesses $VWG_ProcToCloseNonUI -Silent
			}
			if (!($VWG_ProcToClose) -or !($VWG_ProcToCloseNonUI)) {
				Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace "$VWG_FreeSpace"
			}
			if ($VWG_ProcToBlock) {
				Show-ADTInstallationWelcome -CloseProcesses $VWG_ProcToBlock -AllowDeferCloseProcesses -DeferTimes 4 -BlockExecution
			}
		}
    #*====================================PRE-REPAIR END==================================================================


    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    #*====================================MAIN-REPAIR BEGIN==================================================================
	    # user dialogs (deprecated)
	    If ($VWG_UseDialogs){
		    ## Only use for longer installations (Installation duration approx. >3 minutes)
		    #Show-ADTInstallationProgress
	    }

        Write-ADTLogEntry -Message "Start Repair $appVendor $appName $appVersion." -Severity 2 -Source $adtSession.DeployAppScriptFriendlyName	   
	   


        Write-ADTLogEntry -Message "Repair of $appVendor $appName $appVersion." -Severity 2 -Source $adtSession.DeployAppScriptFriendlyName
    #*====================================MAIN-REPAIR END==================================================================

    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"


    #*====================================POST-REPAIR BEGIN==================================================================
		## Branding Install
		Set-Branding
		
		## Handling for required reboot
        #Set-Reboot
    #*====================================POST-REPAIR END==================================================================
}

##================================================
## MARK: Invocation
##================================================

# Commence the actual deployment operation.
try
{
    # Invoke the deployment and close out the session.
    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch
{
    # An unhandled error has been caught.
    $mainErrorMessage = "An unhandled error within [$($MyInvocation.MyCommand.Name)] has occurred.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $mainErrorMessage -Severity 3

    ## Error details hidden from the user by default. Show a simple dialog with full stack trace:
    # Show-ADTDialogBox -Text $mainErrorMessage -Icon Stop -NoWait

    ## Or, a themed dialog with basic error message:
    # Show-ADTInstallationPrompt -Message "$($adtSession.DeploymentType) failed at line $($_.InvocationInfo.ScriptLineNumber), char $($_.InvocationInfo.OffsetInLine):`n$($_.InvocationInfo.Line.Trim())`n`nMessage:`n$($_.Exception.Message)" -MessageAlignment Left -ButtonRightText OK -Icon Error -NoWait

    Close-ADTSession -ExitCode 60001
}
