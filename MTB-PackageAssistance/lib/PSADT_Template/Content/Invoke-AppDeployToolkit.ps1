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
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging
)


##================================================
## MARK: Variables
##================================================

#region VARIABLE DECLARATION
	##*===============================================
	##* Script History
	##*===============================================
	## Date			Name				Revision	Comment
	## {ScriptDate}	{ScriptAuthor}		{Revision}	{Action}
	

    ##*===============================================
    ##* VARIABLE DECLARATION
    ##*===============================================

$adtSession = @{
    # App variables.
    AppVendor = ''
    AppName = ''
    AppVersion = ''
    AppArch = ''
    AppLang = ''
    AppRevision = ''
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppScriptVersion = '1.0.0'
    AppScriptDate = ''
    AppScriptAuthor = ''
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = ''
    InstallTitle = $($adtSession.AppVendor)+" "+$($adtSession.AppName)+" "+$($adtSession.AppVersion)

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'

    # MTB Script variables.
    ProcToClose = @()
	ProcToCloseNonUI	= ''
	ProcToBlock		= @()

	FreeSpace       = ''
    FreeSpaceUninst = '100'
	CheckForReboot	= $false
	ShowBalloonTips	= $true
	UseDialogs		= $true
	AllowDefer		= $false
    SoftIdent       = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\<Appname> [DisplayVersion = <version>]'
    OrderNumber     = ''
}
$AppFullName		= $adtSession.AppVendor + "_" + $adtSession.AppName + "_" + $adtSession.AppArch + "_" + $adtSession.AppVersion + "-" + $adtSession.AppRevision + "_" + $adtSession.AppLang

#region CUSTOM APPLICATION VARIABLES AND FUNCTIONS				
#*====================================CUSTOM APPLICATION VARIABLES BEGIN=========================================================



#*====================================CUSTOM APPLICATION VARIABLES END===========================================================

#*====================================CUSTOM APPLICATION FUNCTIONS BEGIN=========================================================

#*====================================CUSTOM APPLICATION FUNCTIONS END===========================================================
#endregion CUSTOM APPLICATION VARIABLES AND FUNCTIONS

#region INSTALLATION
function Install-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    #region PRE-INSTALLATION
    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
    #*====================================PRE-INSTALLATION BEGIN==================================================================
    # check for pending reboot and stop script execution on true with exit code 1641, if not running in task sequence.
    if ($adtSession.CheckForReboot){
	    Set-MTBReboot -ForceExitScript -OnlyOnPendingReboot -MandatoryDeviceRestart
    }

    if ($adtSession.UseDialogs){
			if ($adtSession.AllowDefer){
                Show-ADTInstallationWelcome -AllowDefer -DeferTimes 4
			}
			if ($adtSession.ProcToClose) {
                Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace $adtSession.FreeSpace -CloseProcesses $adtSession.ProcToClose -AllowDeferCloseProcesses -DeferTimes 4 -Title $adtSession.InstallTitle 
			}
			if ($adtSession.ProcToCloseNonUI) {
                Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace $adtSession.FreeSpace -CloseProcesses $adtSession.ProcToCloseNonUI -Silent
			}
			if (!($adtSession.ProcToClose) -or !($adtSession.ProcToCloseNonUI)) {
                Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace $adtSession.FreeSpace
			}
			if ($adtSession.ProcToBlock) {
               Show-ADTInstallationWelcome -CloseProcesses $adtSession.ProcToClose -AllowDeferCloseProcesses -DeferTimes 4 -BlockExecution
			}
	}

    ## <Perform Pre-Installation tasks here>
    
          

    #*====================================PRE-INSTALLATION END==================================================================
	#endregion PRE-INSTALLATION
    
    #region MAIN-INSTALLATION
    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType
    #*====================================MAIN-INSTALLATION BEGIN==================================================================
    
    # user dialogs (deprecated)
	if ($adtSession.UseDialogs){
		## Only use for longer installations (Installation duration approx. >3 minutes)
	   #Show-ADTInstallationProgress -WindowLocation 'BottomRight'
    }

    ## <Perform Installation tasks here>
    Write-ADTLogEntry -Message "Start Installation $($adtSession.InstallTitle)" -Severity 2 -Source $adtSession.deployAppScriptFriendlyName
    
    
  
    Write-ADTLogEntry -Message "Installation of $($adtSession.InstallTitle) is successful." -Severity 2 -Source $adtSession.deployAppScriptFriendlyName

    #*====================================MAIN-INSTALLATION END==================================================================
	#endregion MAIN-INSTALLATION
    
    #region POST-INSTALLATION
    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
    #*====================================POST-INSTALLATION BEGIN==================================================================
   
    ## <Perform Post-Installation tasks here>

        
		## Branding Detection Registry Key
		Set-MTBDetectionKey

		##Handling for required reboot
        #Set-MTBReboot

    #*====================================POST-INSTALLATION END==================================================================
	#endregion POST-INSTALLATION
}
#endregion INSTALLATION

#region UNINSTALLATION

#region UNINSTALLATION
function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )
    #region PRE-UNINSTALLATION
    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
    ##*====================================PRE-UNINSTALLATION BEGIN============================================================
    
    # check for pending reboot and stop script execution on true with exit code 1641, if not running in task sequence.
    if ($adtSession.CheckForReboot){
	    Set-MTBReboot -ForceExitScript -OnlyOnPendingReboot -MandatoryDeviceRestart
    }
    
    if ($adtSession.UseDialogs){
			if ($adtSession.AllowDefer){
                Show-ADTInstallationWelcome -AllowDefer -DeferTimes 4
			}
			if ($adtSession.ProcToClose) {
                Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace $adtSession.FreeSpaceUninst -CloseProcesses $adtSession.ProcToClose -AllowDeferCloseProcesses -DeferTimes 4 -Title $adtSession.InstallTitle
			}
			if ($adtSession.ProcToCloseNonUI) {
                Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace $adtSession.FreeSpaceUninst -CloseProcesses $adtSession.ProcToCloseNonUI -Silent
			}
			if (!($adtSession.ProcToClose) -or !($adtSession.ProcToCloseNonUI)) {
                Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace $adtSession.FreeSpaceUninst
			}
			if ($adtSession.ProcToBlock) {
               Show-ADTInstallationWelcome -CloseProcesses $adtSession.ProcToClose -AllowDeferCloseProcesses -DeferTimes 4 -BlockExecution
			}
	}

   ## <Perform Pre-Uninstallation tasks here>
    
   
    #*====================================PRE-UNINSTALLATION END==================================================================
	#endregion PRE-UNINSTALLATION
    
    #region MAIN-UNINSTALLATION
    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType
    #*====================================MAIN-UNINSTALLATION BEGIN===============================================================

    # user dialogs (deprecated)
	if ($adtSession.UseDialogs){
		## Only use for longer installations (Installation duration approx. >3 minutes)
	   #Show-ADTInstallationProgress -WindowLocation 'BottomRight'
    }

    ## <Perform Main-UnInstallation tasks here>    

    Write-ADTLogEntry -Message "Start Uninstallation $($adtSession.InstallTitle)" -Severity 2 -Source $adtSession.deployAppScriptFriendlyName

    
    
            
    Write-ADTLogEntry -Message "Uninstallation of $($adtSession.InstallTitle) is successful" -Severity 2 -Source $adtSession.deployAppScriptFriendlyName
        
    #*====================================MAIN-UNINSTALLATION END==================================================================
	#endregion MAIN-UNINSTALLATION
    
    #region POST-UNINSTALLATION
    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    #*====================================POST-UNINSTALLATION BEGIN===============================================================
    
    ## <Perform Post-UnInstallation tasks here>    
  

        ## Removing Branding Detection Key
        Remove-MTBDetectionKey 
    
        ##Handling for required reboot
        #Set-MTBReboot
     

    #*====================================POST-UNINSTALLATION END=================================================================
	#endregion POST-UNINSTALLATION
}
#endregion UNINSTALLATION

#region REPAIR
function Repair-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )
    
    #region PRE-REPAIR
    ##================================================
    ## MARK: Pre-Repair
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
    #*====================================PRE-REPAIR BEGIN============================================================
    
    # check for pending reboot and stop script execution on true with exit code 1641, if not running in task sequence.
    if ($adtSession.CheckForReboot){
	    Set-MTBReboot -ForceExitScript -OnlyOnPendingReboot -MandatoryDeviceRestart
    }
    
    if ($adtSession.UseDialogs){
			if ($adtSession.AllowDefer){
                Show-ADTInstallationWelcome -AllowDefer -DeferTimes 4
			}
			if ($adtSession.ProcToClose) {
                Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace $adtSession.FreeSpace -CloseProcesses $adtSession.ProcToClose -AllowDeferCloseProcesses -DeferTimes 4 -Title $adtSession.InstallTitle -Subtitle "CloseApps"
			}
			if ($adtSession.ProcToCloseNonUI) {
                Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace $adtSession.FreeSpace -CloseProcesses $adtSession.ProcToCloseNonUI -Silent
			}
			if (!($adtSession.ProcToClose) -or !($adtSession.ProcToCloseNonUI)) {
                Show-ADTInstallationWelcome -CheckDiskSpace -RequiredDiskSpace $adtSession.FreeSpace
			}
			if ($adtSession.ProcToBlock) {
               Show-ADTInstallationWelcome -CloseProcesses $adtSession.ProcToClose -AllowDeferCloseProcesses -DeferTimes 4 -BlockExecution
			}
	}

    ## <Perform Pre-Repair tasks here>
    

   

    #*====================================PRE-REPAIR END=============================================================
	#endregion PRE-REPAIR

    #region MAIN-REPAIR
    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType
    #*====================================MAIN-REPAIR BEGIN===============================================================

    # user dialogs (deprecated)
	if ($adtSession.UseDialogs){
		## Only use for longer installations (Installation duration approx. >3 minutes)
	   #Show-ADTInstallationProgress -WindowLocation 'BottomRight'
    }
    
    ## <Perform Main-Repair tasks here>    

    Write-ADTLogEntry -Message "Start Repair $($adtSession.InstallTitle)" -Severity 2 -Source $adtSession.deployAppScriptFriendlyName

    

    Write-ADTLogEntry -Message "Repair of $($adtSession.InstallTitle) is successful." -Severity 2 -Source $adtSession.deployAppScriptFriendlyName

    #*====================================MAIN-REPAIR END=================================================================
	#endregion MAIN-REPAIR

    #region POST-REPAIR
    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
    #*====================================POST-REPAIR BEGIN===============================================================

    ## <Perform Post-Repair tasks here>


		## Branding Detection Registry Key
		Set-MTBDetectionKey

		##Handling for required reboot
        #Set-MTBReboot

    #*====================================POST-REPAIR END=================================================================
	#endregion POST-REPAIR
}
#endregion REPAIR


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
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }
    else
    {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }

    # Open a new deployment session, replacing $adtSession with a DeploymentSession.
    $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}


##================================================
## MARK: Invocation
##================================================

# Commence the actual deployment operation.
try
{
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
    # Show-ADTInstallationPrompt -Message "$($adtSession.DeploymentType) failed at line $($_.InvocationInfo.ScriptLineNumber), char $($_.InvocationInfo.OffsetInLine):`n$($_.InvocationInfo.Line.Trim())`n`nMessage:`n$($_.Exception.Message)" -ButtonRightText OK -Icon Error -NoWait

    Close-ADTSession -ExitCode 60001
}




