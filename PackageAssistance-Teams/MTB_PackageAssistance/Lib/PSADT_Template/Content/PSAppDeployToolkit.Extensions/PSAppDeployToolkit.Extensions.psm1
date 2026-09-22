<#

.SYNOPSIS
PSAppDeployToolkit.Extensions - Provides the ability to extend and customize the toolkit by adding your own functions that can be re-used.

.DESCRIPTION
This module is a template that allows you to extend the toolkit with your own custom functions.

This module is imported by the Invoke-AppDeployToolkit.ps1 script which is used when installing or uninstalling an application.

#>

##*===============================================
##* MARK: MODULE GLOBAL SETUP
##*===============================================

# Set strict error handling across entire module.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1
$adtSession = Get-AdtSession
$AppFullName		= $adtSession.AppVendor + "_" + $adtSession.AppName + "_" + $adtSession.AppArch + "_" + $adtSession.AppVersion + "-" + $adtSession.AppRevision + "_" + $adtSession.AppLang

##*===============================================
##* MARK: FUNCTION LISTINGS
##*===============================================

function New-ADTExampleFunction
{
    <#
    .SYNOPSIS
        Basis for a new PSAppDeployToolkit extension function.

    .DESCRIPTION
        This function serves as the basis for a new PSAppDeployToolkit extension function.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        None

        This function does not return any output.

    .EXAMPLE
        New-ADTExampleFunction

        Invokes the New-ADTExampleFunction function and returns any output.
    #>

    [CmdletBinding()]
    param
    (
    )

    begin
    {
        # Initialize function.
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                Write-Error -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            Invoke-ADTFunctionErrorHandler -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_
        }
    }

    end
    {
        # Finalize function.
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}


#region Function Set-MTBReboot
function Set-MTBReboot {
<#
.SYNOPSIS
	Set the reboot action
.DESCRIPTION
	Set the reboot action
	Set-MTBReboot does not trigger reboot if the script is running in a task sequence.
.PARAMETER ForceExitScript
	Script execution will be stopped immediatly with exit code 1641 (a mandatory device restart is required before proceeding 
	with any other installtion). Accepts previously used parameter name "ForceReboot" as alias. 
	Default is: $false.
.PARAMETER OnlyOnPendingReboot
	Reboot behavior determined by pending system reboot: checks for pending reboot, if found than set the reboot action. Accepts previously 
	used parameter name "CheckPendingReboot" as alias.
	Default is: $false.
.PARAMETER MandatoryDeviceRestart
	Will set the script exit code to 1641 (a mandatory device restart is required before proceeding with any other installtion) instead of 3010. 
	Default is: $false.
.EXAMPLE
	Set-MTBReboot
	Set $mainexitcode 3010 and continue script execution.
.EXAMPLE
	Set-MTBReboot -MandatoryDeviceRestart
	Set $mainexitcode 1641 and continue script execution.
.EXAMPLE
	Set-MTBReboot -OnlyOnPendingReboot
	Checks for pending reboot, if found set $mainexitcode to 3010 and continue script execution.
.EXAMPLE
	Set-MTBReboot -OnlyOnPendingReboot -MandatoryDeviceRestart
	Checks for pending reboot, if found set $mainexitcode to 1641 and continue script execution.
.EXAMPLE
	Set-MTBReboot -ForceExitScript
	Script execution will be stopped immediatly with $mainexitcode 3010.
.EXAMPLE
	Set-MTBReboot -ForceExitScript -MandatoryDeviceRestart
	Script execution will be stopped immediatly with $mainexitcode 1641.
.EXAMPLE
	Set-MTBReboot -ForceExitScript -OnlyOnPendingReboot
	Checks for pending reboot, if found than script execution will be stopped immediatly with $mainexitcode 3010.
.EXAMPLE
	Set-MTBReboot -ForceExitScript -OnlyOnPendingReboot -MandatoryDeviceRestart
	Checks for pending reboot, if found than script execution will be stopped immediatly with $mainexitcode 1641.
.NOTES
.LINK
	http://www.volkswagen-group.com
#>
	[CmdletBinding()] 
		param( 
		[Parameter(Mandatory=$false)]
		[Alias("ForceReboot")]
		[ValidateNotNullorEmpty()]
		[switch]$ForceExitScript = $false,
		[Parameter(Mandatory=$false)]
		[Alias("CheckPendingReboot")]
		[ValidateNotNullorEmpty()]
		[switch]$OnlyOnPendingReboot = $false,
		[Parameter(Mandatory=$false)]
		[ValidateNotNullorEmpty()]
		[switch]$MandatoryDeviceRestart = $false,
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[boolean]$ContinueOnError = $true
		)
	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		 Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process {
		Try {
			Switch ($($adtSession.InstallPhase)) {
				{($_ -eq "Pre-Installation") -Or ($_ -eq "Pre-Uninstallation")} {$ScriptRegionString = "before";Break}
				{($_ -eq "Post-Installation") -Or ($_ -eq "Post-Uninstallation")} {$ScriptRegionString = "after";Break}
				default {$ScriptRegionString = "within"}
			}
			
			If ($MandatoryDeviceRestart) {
				[string]$RestartType = "Mandatory device restart"
				[int32]$ExitCode = 1641
			}
			Else {
				[string]$RestartType = "Device restart"
				[int32]$ExitCode = 3010
			}
			
			If ($($adtSession.runningTaskSequence)){
				Write-ADTLogEntry -Message "Installation is running in task sequence, reboot will not be triggered. Continue script execution." -Severity 2 -Source ${CmdletName}
				return
			}
			ElseIf ($ForceExitScript) {
				If ($OnlyOnPendingReboot) {
					If ((Get-ADTPendingReboot).IsSystemRebootPending){
						Write-ADTLogEntry -Message "Pending reboot detected. $($RestartType) required $($ScriptRegionString) $($adtSession.DeploymentType)ing [$AppFullName]. Exit script execution." -Severity 2 -Source ${CmdletName}
						Close-ADTSession -ExitCode $ExitCode
					}
					Else {
						Write-ADTLogEntry -Message "No pending reboot detected. $($ScriptRegionString) $($adtSession.DeploymentType)ing [$AppFullName]. Continue script execution." -Severity 2 -Source ${CmdletName}
					}
				}
				Else {
					Write-ADTLogEntry -Message "$($RestartType) required $($ScriptRegionString) $($adtSession.DeploymentType)ing [$AppFullName]. Exit script execution." -Severity 2 -Source ${CmdletName}
					Close-ADTSession -ExitCode $ExitCode
				}
			}
			Else {
				If ($OnlyOnPendingReboot) {
					If ((Get-ADTPendingReboot).IsSystemRebootPending){
						Write-ADTLogEntry -Message "Pending reboot detected. $($RestartType) required $($ScriptRegionString) $($adtSession.DeploymentType)ing [$AppFullName]." -Severity 2 -Source ${CmdletName}
						Set-Variable -Name 'mainExitCode' -Value $ExitCode -Scope 'Script'
					}
					Else {
						Write-ADTLogEntry -Message "No pending reboot detected. $($ScriptRegionString) $($adtSession.DeploymentType)ing [$AppFullName]. Continue script execution." -Severity 2 -Source ${CmdletName}
					}
				}
				Else {
					Write-ADTLogEntry -Message "$($RestartType) required $($ScriptRegionString) $($adtSession.DeploymentType)ing [$AppFullName]." -Severity 2 -Source ${CmdletName}
					#Set-Variable -Name 'mainExitCode' -Value $ExitCode -Scope 'Script'
                    Close-ADTSession -ExitCode $ExitCode 
				}
			}
		}
		Catch {
            Write-ADTLogEntry -Message "Failed to set reboot. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
			If (-not $ContinueOnError) {
				Throw "Failed to set reboot. $($_.Exception.Message)"
			}
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion
#endregion
#region Function Expand-MTBZipFile
function Expand-MTBZipFile{
<#
.SYNOPSIS
	Extract Zip-Files to Destination
.DESCRIPTION
	Extract Zip-Files to Destination
.PARAMETER Path
	Path of Zip-File
.PARAMETER Destination
	Destination to Extract
.PARAMETER ContinueOnError
	Continue if an error is encountered. Default is: $false.
.PARAMETER Override
	Overrides existent Content
.EXAMPLE
	Expand-MTBZipFile -Path "$dirfiles\ZipFile.zip" -Destination "$envProgramFiles\Destination" -Override
.LINK
	http://www.volkswagen-group.com
#>
	param (
		[parameter(Mandatory=$true,Position=0)]
		[ValidateNotNullorEmpty()]
		[string]$Path,
		[parameter(Mandatory=$true,Position=1)]
		[ValidateNotNullorEmpty()]
		[string]$Destination,
		[Parameter(Mandatory=$false,Position=2)]
		[ValidateNotNullorEmpty()]
		[boolean]$ContinueOnError = $false,
		[Parameter(Mandatory=$false,Position=3)]
		[ValidateNotNullorEmpty()]
		[switch]$Override = $false
	)
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
		Add-Type -AssemblyName System.IO.Compression.FileSystem
		Add-Type -AssemblyName  System.IO.Compression
	}
	process{
		Try {
			If (-not(Test-Path -Path "$($Destination)")) {
				New-ADTFolder -Path "$($Destination)"
				Write-ADTLogEntry -Message "Extracting Zip-File [$($Path)] to [$($Destination)]." -Source ${CmdletName}
				[System.IO.Compression.ZipFile]::ExtractToDirectory("$($Path)", "$($Destination)")
			}
			else{
				$objArchive = [System.IO.Compression.ZipFile]::Open("$($Path)", 'Read')
				if($Override){
					Write-ADTLogEntry -Message "Integrating Zip-File [$($Path)] to [$($Destination)] with Override." -Source ${CmdletName}
				}
				else{
					Write-ADTLogEntry -Message "Integrating Zip-File [$($Path)] to [$($Destination)] without Override." -Source ${CmdletName}
				}
				foreach($archiveEntry in $objArchive.Entries){
					if(!$archiveEntry.Name){ #create folder detect without any properties in object
						if(!(Test-Path -Path (Join-Path $Destination $archiveEntry.FullName))){
							$null = New-Item -Path (Join-Path $Destination $archiveEntry.FullName) -ItemType Directory 
						}
					}
					if(Test-Path -Path (Join-Path $Destination $archiveEntry.FullName)){
						if($Override){
							#extract the files with override
							[System.IO.Compression.ZipFileExtensions]::ExtractToFile($archiveEntry , (Join-Path $Destination $archiveEntry.FullName),$Override) 
						}
					}
					elseif(!(Test-Path -Path (Join-Path $Destination $archiveEntry.FullName))){
						#create folder detect if it has properties in object so it looks like file but has no attribute directory (check in 7zip), this case only occurs if used windows zip function!!
						$destinationdir = Split-Path -Path (Join-Path $Destination $archiveEntry.FullName)
						if(!(Test-Path -Path $destinationdir)){
							$null = New-Item -Path $destinationdir -ItemType Directory
						}
						#extract the files
						[System.IO.Compression.ZipFileExtensions]::ExtractToFile($archiveEntry , (Join-Path $Destination $archiveEntry.FullName),$Override)
					}
				}
				$objArchive.Dispose()
			}
		}
		Catch {
            Write-ADTLogEntry -Message "Failed to extract the requested file.. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
			If (-not $ContinueOnError) {
		        	Throw "Failed to extract the requested file: $($_.Exception.Message)"
			}
		}
		finally{
			
		}
	}
	end{
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
function Set-MTBDetectionKey
{
    <#
    .SYNOPSIS
        Basis for a new MTB Customized function.

    .DESCRIPTION
        Creates a new instance in MTB Registry keys which contains all the information about current package and will use these information for Detection Method.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        None

        This function does not return any output.

    .EXAMPLE
        Set-MTBDetectionKey

        Invokes the Set-MTBDetectionKey function and returns any output.
    #>

    [CmdletBinding()]
    param
    (
    )

    begin
    {
        # Initialize function.
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        Try 
        {
            Write-ADTLogEntry -Message "Begin set registry branding." -Severity 1  -Source ${CmdletName}
            [string]$BrandingKey = "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$AppFullName"
            Write-ADTLogEntry -Message "Setting $BrandingKey" -Severity 1  -Source ${CmdletName}
            Write-ADTLogEntry -Message "Writing branding information to registry." -Severity 1 
            Set-ADTRegistryKey -Key "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$AppFullName" -Name 'Architecture' -Value $($adtSession.AppArch)		
            Set-ADTRegistryKey -Key "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$AppFullName" -Name 'Identifier' -Value $($adtSession.SoftIdent)
            Set-ADTRegistryKey -Key "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$AppFullName" -Name 'Language' -Value $($adtSession.AppLang)
            Set-ADTRegistryKey -Key "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$AppFullName" -Name 'LastInstalled' -Value (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Set-ADTRegistryKey -Key "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$AppFullName" -Name 'Name' -Value $AppFullName
            Set-ADTRegistryKey -Key "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$AppFullName" -Name 'OrderNumber' -Value $($adtSession.OrderNumber)
            Set-ADTRegistryKey -Key "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$AppFullName" -Name 'Product' -Value $($adtSession.AppName)
            Set-ADTRegistryKey -Key "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$AppFullName" -Name 'Identifier' -Value $($adtSession.SoftIdent)
            Set-ADTRegistryKey -Key "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$AppFullName" -Name 'Revision' -Value $($adtSession.AppRevision)
            Set-ADTRegistryKey -Key "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$AppFullName" -Name 'Vendor' -Value $($adtSession.AppVendor) 
            Set-ADTRegistryKey -Key "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$AppFullName" -Name 'Version' -Value $($adtSession.AppVersion)   
            
            Write-ADTLogEntry -Message "Registry branding successfully set." -Severity 1  -Source ${CmdletName}
        }
		Catch {
			Write-ADTLogEntry -Message "Failed to set registry branding. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
		}
      
    }

    end
    {
        # Finalize function.
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}

function Remove-MTBFonts
{
    <#
    SYNOPSIS
		Uninstall a Windows font
	.DESCRIPTION
		Removes a font or font family from Windows
	.PARAMETER FontName
		single font file name, valid file types are .fon, .ttf, .otf
	.EXAMPLE
		Remove-MTBFonts -FontName "VWAG_norm.ttf"
			Remove the font from the fonts folder
	.NOTES

        Invokes the Remove-MTBFonts function and returns any output.
    #>

    [CmdletBinding()]
    param
    (
            [Parameter(Mandatory=$true,
			HelpMessage="The font file name of a file located in \Windows\Fonts. Valid file types are .fon, .ttf, .otf")]
			[ValidateScript({($_ -match "(\.fon|\.ttf|\.otf)")})]
			[ValidateNotNullOrEmpty()]
			[string]$FontName
    )

    begin
    {
        # Initialize function.
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        $FontsFolder = New-Object -ComObject "Shell.Application" | foreach {$_.NameSpace(0x14).Self.Path}
	    $FontsRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    }

    process
    {
        try
        {
            try
            {
                $FontFullPath = Join-Path $FontsFolder $FontName
                If(-not(Test-Path $FontFullPath)){
                    Write-ADTLogEntry -Message "The font file $FontFullPath does not exist." -Source ${CmdletName}
                }

                # Get all registry entries in the specified path
                $RegistryEntries = Get-ItemProperty -Path $FontsRegistryPath
                
                # Loop through the entries to find the matching data value
                $FontRegFound = $false
                foreach ($Entry in $RegistryEntries.PSObject.Properties) {
                    if ($Entry.Value -eq $FontName) {
                        # Remove the registry entry
                        $FontRegFound = $true
                        Remove-ItemProperty -Path $FontsRegistryPath -Name $Entry.Name
                        Write-ADTLogEntry -Message "Removing font $($Entry.Name) from Registry" -Source ${CmdletName}
                    }
                }
                If($FontRegFound){
                        Write-ADTLogEntry -Message "The font Registry $FontName does not exist." -Source ${CmdletName}
                    }
                If (Test-Path -Path $FontFullPath -PathType Leaf){
					    Write-ADTLogEntry -Message "Removing font file $FontFullPath" -Severity 1 -Source ${CmdletName}
					    Remove-Item -Path "$FontFullPath" -Force
				}
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                Write-ADTLogEntry -Message "Failed to remove font from windows. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Source ${CmdletName} -Severity 3
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            Invoke-ADTFunctionErrorHandler -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_
        }
    }

    end
    {
        # Finalize function.
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}

#region Function Set-ApplicationWizardEntry

function Set-MTBApplicationWizardEntry {

<#
.SYNOPSIS
Creates custom ARP (Application Wizard) entry and sets display icon.

.DESCRIPTION
Copies icon to ProgramData\AppWizIco and creates registry entry for SCCM detection.

.PARAMETER ApplicationName
Optional display name for the Application Wizard entry.
If not specified, the application name from the PSADT session is used.

.EXAMPLE
Set-MTBApplicationWizardEntry

.EXAMPLE
Set-MTBApplicationWizardEntry -ApplicationName "Adobe Acrobat"

#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ApplicationName
    )

    begin
    {
        # Initialize function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try {

            if ([string]::IsNullOrWhiteSpace($ApplicationName)) {
                $ApplicationName = $adtSession.AppName
            }

            Write-ADTLogEntry -Message "Starting to set Application Wizard entry creation for [$ApplicationName]" -Severity 2 -Source ${CmdletName}

            

                if ($adtSession.AppArch -eq "x64") {
                    $ArpKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ApplicationName"
                }
                else {
                    $ArpKey = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$ApplicationName"
                }

            

            $IconFolder = Join-Path $env:ProgramData "AppWizIco"

            if (!(Test-Path $IconFolder)) {

                New-ADTFolder -Path $IconFolder
            }

            $SourceIcon = Join-Path $adtSession.DirSupportFiles "Icon.ico"
            $DestinationIcon = Join-Path $IconFolder "$($adtSession.AppName).ico"

            Write-ADTLogEntry -Message "Copying icon to $DestinationIcon" -Severity 1 -Source ${CmdletName}
            Copy-ADTFile $SourceIcon $DestinationIcon

            if (!(Test-Path $ArpKey)) {
                Write-ADTLogEntry -Message "Creating registry key $ArpKey" -Severity 1 -Source ${CmdletName}
                New-Item -Path $ArpKey -Force | Out-Null
            }

            Write-ADTLogEntry -Message "Writing ARP registry values." -Severity 1 -Source ${CmdletName}

            Set-ItemProperty -Path $ArpKey -Name "Comments" -Value $adtSession.AppName
            Set-ItemProperty -Path $ArpKey -Name "DisplayIcon" -Value $DestinationIcon
            Set-ItemProperty -Path $ArpKey -Name "DisplayName" -Value $ApplicationName
            Set-ItemProperty -Path $ArpKey -Name "DisplayVersion" -Value $adtSession.AppVersion
            Set-ItemProperty -Path $ArpKey -Name "InstallSource" -Value $adtSession.ScriptDirectory
            Set-ItemProperty -Path $ArpKey -Name "Publisher" -Value $adtSession.AppVendor
            Set-ItemProperty -Path $ArpKey -Name "UninstallString" -Value "Only SCCM Uninstall"

            New-ItemProperty -Path $ArpKey -Name "NoModify" -PropertyType DWord -Value 1 -Force
            New-ItemProperty -Path $ArpKey -Name "NoRepair" -PropertyType DWord -Value 1 -Force
            New-ItemProperty -Path $ArpKey -Name "NoRemove" -PropertyType DWord -Value 1 -Force

            Write-ADTLogEntry -Message "Application Wizard entry created successfully." -Severity 2 -Source ${CmdletName}

        }
        catch {
            Write-ADTLogEntry -Message "Failed to set the Application Wizard entry.`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
        }
    }

    end
    {
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}

#endregion

#region Function Remove-ApplicationWizardEntry
Function Remove-MTBApplicationWizardEntry {
<#
.SYNOPSIS
 	Removes custom Application Wizard entry and icon.
.DESCRIPTION
	Removes icon file from $envProgramData\AppWizIco\$appName.ico.
	Removes Application Wizard entry in registry.
.PARAMETER ApplicationName
	The ApplicationName is the same as appName and default, redefine if $appName contains spaces and special characters to show correct in appwiz.
.EXAMPLE
	Remove-ApplicationWizardEntry
	Remove the custom Application Wizard entry and icon for default $appName.
.EXAMPLE
	Remove-ApplicationWizardEntry -ApplicationName 'Logon Screen'
	Remove the custom Application Wizard entry and icon and overrides default $appName because contains spaces and special characters.
.NOTES
.LINK
	http://www.volkswagen-group.com
#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$ApplicationName = $($adtSession.AppName)
	)
	
	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process {
		Try {
			Write-ADTLogEntry -Message "Begin remove Application Wizard entry." -Severity 1 -Source ${CmdletName} 
			
			$ArpKey = "HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$ApplicationName","HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ApplicationName"
					
			Write-ADTLogEntry -Message "Remove Application Wizard entry from Registry." -Severity 1 -Source ${CmdletName} 
			foreach ($key in $ArpKey) {
				Remove-ADTRegistryKey -Key $Key #-Recurse	
			}
			
			Write-ADTLogEntry -Message "Remove Application Wizard Icon." -Severity 1 -Source ${CmdletName} 
			$CurrentFile = "$envProgramData\AppWizIco\$appName.ico"
			If ( Test-Path -path $CurrentFile -PathType Leaf ) {
				Remove-ADTFile -Path $CurrentFile
			}
			
            #Removing folder "$envProgramData\AppWizIco" if it is empty
            If(Test-Path -Path "$envProgramData\AppWizIco")
            {
                If((Get-ChildItem  -Path "$envProgramData\AppWizIco") -eq $Null)
                {
			        Remove-ADTFolder -Path "$envProgramData\AppWizIco"
                }
            }

			Write-ADTLogEntry -Message "End remove Application Wizard entry successfully." -Severity 1 -Source ${CmdletName} 	
		}
		Catch {
			Write-ADTLogEntry -Message "Failed to set the Application Wizard entry. `n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

function Remove-MTBDetectionKey
{
    <#
    .SYNOPSIS
        Removes MTB Detection registry key(s).

    .DESCRIPTION
        Removes the MTB Registry key(s) created for the current package.
        You can optionally provide one or more names with the -Name parameter.
        If no names are provided, it defaults to removing the current application's key ($AppFullName).

    .PARAMETER Name
        Optional. One or more names of registry keys to remove.
        If not specified, defaults to the current application's key ($AppFullName).

    .EXAMPLE
        Remove-MTBDetectionKey

        Removes the registry key for the current application ($AppFullName).

    .EXAMPLE
        Remove-MTBDetectionKey -Name "Key1","Key2","Key3"

        Removes the specified registry keys.
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Position=0, Mandatory=$false)]
        [string[]]$Name
    )

    begin
    {
        # Initialize function.
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        # If no names are provided, use $AppFullName
        if (-not $Name -or $Name.Count -eq 0) {
            $Name = @($AppFullName)
        }

        foreach ($KeyName in $Name) {
            [string]$BrandingKey = "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$KeyName"
            Write-ADTLogEntry -Message "Begin processing registry key: $BrandingKey" -Severity 1 -Source ${CmdletName}

            if (Test-Path -Path "Registry::$BrandingKey")
            {
                Try 
                {
                    Remove-Item -Path "Registry::$BrandingKey" -Recurse -Force -ErrorAction Stop
                    Write-ADTLogEntry -Message "Registry branding for '$KeyName' successfully removed." -Severity 1 -Source ${CmdletName}
                }
                Catch {
                    Write-ADTLogEntry -Message "Failed to remove registry branding for '$KeyName'. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
                }
            }
            else
            {
                # Key not found, log as warning but continue
                Write-ADTLogEntry -Message "Registry key '$KeyName' does not exist. Skipping." -Severity 2 -Source ${CmdletName}
            }
        }
    }

    end
    {
        # Finalize function.
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}

#endregion


#region Function Add-WindowsDriverOnline
function Add-WindowsDriverOnline {
<#
.SYNOPSIS
    Add and install drivers to the running OS using PnPutil.exe.

.DESCRIPTION
    Adds one or more INF-based drivers to the Windows driver store and
    optionally installs them on matching connected devices.

    LOCALE-SAFE: Uses driver store filesystem snapshot diff (not pnputil
    text output) and ordinal string comparisons. Works on any Windows
    locale (Turkish, German, Greek, Chinese, Hungarian, Polish, etc.).

    INTUNE-SAFE: Reboot codes (3010, 1641) logged but NOT propagated.

.PARAMETER Path
    Path to a driver folder (recursive search for *.inf) or a single .inf file.

.PARAMETER NoInstall
    If set, the driver is added to the store only — not installed on devices.

.PARAMETER ContinueOnError
    Continue if an error is encountered. Default: $true.

.EXAMPLE
    Add-WindowsDriverOnline -Path "$($adtSession.DirFiles)\Drivers"

.EXAMPLE
    Add-WindowsDriverOnline -Path "$($adtSession.DirFiles)\Drivers\mydev.inf"

.EXAMPLE
    Add-WindowsDriverOnline -Path "$($adtSession.DirFiles)\Drivers\mydev.inf" -NoInstall

.OUTPUTS
    System.Collections.Hashtable
    Maps each source INF filename to its assigned oem##.inf published name.

.NOTES
    Requires elevated context. PSADT v4 compatible.

.LINK
    http://www.volkswagen-group.com
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    Param (
        [Parameter(Mandatory = $true,
                   HelpMessage = "A path to the driver folder or a single inf file")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            (Test-Path -Path $_ -PathType Container) -or
            ((Test-Path -Path $_ -PathType Leaf) -and
             $_.EndsWith('.inf', [System.StringComparison]::OrdinalIgnoreCase))
        })]
        [string]$Path,

        [Parameter(Mandatory = $false,
                   HelpMessage = "If set, the driver is added to the repository only")]
        [switch]$NoInstall,

        [Parameter(Mandatory = $false)]
        [boolean]$ContinueOnError = $true
    )

    Begin {
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        $successCodes = @(0, 259, 3010, 1641)
        $rebootCodes  = @(3010, 1641)

        $script:OrdinalCmp = [System.StringComparer]::OrdinalIgnoreCase

        function Get-DriverStoreSnapshot {
            $items = Get-ChildItem -Path "$env:WinDir\inf\oem*.inf" -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty Name

            $set = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
            foreach ($i in $items) { [void]$set.Add($i) }
            return ,$set
        }
    }

    Process {
        Try {
            $exePnPutil = "$env:WinDir\System32\PnPutil.exe"
            $osVersion  = [System.Environment]::OSVersion.Version

            If ($osVersion -gt [Version]'6.1') {
                $addParam     = '/add-driver'
                $installParam = if (-not $NoInstall) { '/install' } else { '' }
            }
            Else {
                $addParam     = '/a'
                $installParam = if (-not $NoInstall) { '/i' } else { '' }
            }

            Write-ADTLogEntry -Message "Using pnputil parameters: '$addParam $installParam' (OS: $osVersion)" -Severity 1 -Source ${CmdletName}

            If (Test-Path -Path $Path -PathType Leaf) {
                $infFiles = @(Get-Item -Path $Path)
            }
            Else {
                $infFiles = @(Get-ChildItem -Path $Path -Recurse -Filter '*.inf')
            }

            If ($infFiles.Count -eq 0) {
                Write-ADTLogEntry -Message "No .inf files found under [$Path]." -Severity 2 -Source ${CmdletName}
                return @{}
            }

            Write-ADTLogEntry -Message "Found $($infFiles.Count) INF file(s) under [$Path]." -Severity 1 -Source ${CmdletName}

            $publishedNames = [System.Collections.Hashtable]::new($script:OrdinalCmp)
            $rebootNeeded   = $false

            foreach ($inf in $infFiles) {

                Write-ADTLogEntry -Message "Adding driver from [$($inf.Name)]..." -Severity 1 -Source ${CmdletName}

                $beforeSnapshot = Get-DriverStoreSnapshot

                $arguments = @($addParam, "`"$($inf.FullName)`"")
                If ($installParam) { $arguments = @($installParam) + $arguments }

                [psobject]$result = Start-ADTProcess `
                    -FilePath        $exePnPutil `
                    -ArgumentList    ($arguments -join ' ') `
                    -CreateNoWindow `
                    -IgnoreExitCodes '*' `
                    -PassThru

                $exitCode = $result.ExitCode

                If ($successCodes -contains $exitCode) {

                    $afterSnapshot = Get-DriverStoreSnapshot

                    $newOems = New-Object System.Collections.Generic.List[string]
                    foreach ($name in $afterSnapshot) {
                        If (-not $beforeSnapshot.Contains($name)) {
                            $newOems.Add($name)
                        }
                    }

                    Switch ($newOems.Count) {
                        1 {
                            $publishedNames[$inf.Name] = $newOems[0]
                            Write-ADTLogEntry -Message "Added [$($inf.Name)] successfully -> published as [$($newOems[0])] (exit code: $exitCode)." -Severity 1 -Source ${CmdletName}
                        }
                        0 {
                            Write-ADTLogEntry -Message "Driver [$($inf.Name)] was already present in the store — no new entry created (exit code: $exitCode)." -Severity 2 -Source ${CmdletName}
                        }
                        Default {
                            $joined = $newOems -join ';'
                            $publishedNames[$inf.Name] = $joined
                            Write-ADTLogEntry -Message "Added [$($inf.Name)] -> multiple new entries detected: $joined (exit code: $exitCode)." -Severity 2 -Source ${CmdletName}
                        }
                    }

                    If ($rebootCodes -contains $exitCode) {
                        $rebootNeeded = $true
                        Write-ADTLogEntry -Message "Driver [$($inf.Name)] reported reboot-required (exit code: $exitCode)." -Severity 2 -Source ${CmdletName}
                    }
                }
                Else {
                    Write-ADTLogEntry -Message "Failed to add driver [$($inf.Name)] (exit code: $exitCode)." -Severity 3 -Source ${CmdletName}

                    If (-not $ContinueOnError) {
                        Throw "Adding driver [$($inf.Name)] failed with exit code $exitCode."
                    }
                }
            }

            If ($rebootNeeded) {
                Write-ADTLogEntry `
                    -Message "Driver installation flagged reboot-required. NOT escalating to session exit code (Intune/SCCM safety)." `
                    -Severity 2 `
                    -Source ${CmdletName}
            }

            return $publishedNames
        }
        Catch {
            Write-ADTLogEntry -Message "Failed to add driver to Windows. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}

            If (-not $ContinueOnError) {
                Throw "Failed to add driver to Windows: $($_.Exception.Message)"
            }
        }
    }

    End {
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}
#endregion


#region Function Remove-PnPDrivers
function Remove-PnPDrivers {
<#
.SYNOPSIS
    Uninstalls signed drivers from the Windows driver store using PnPutil.exe.

.DESCRIPTION
    Searches all oem*.inf files in %WinDir%\inf for matching .cat references,
    then uses pnputil /delete-driver /uninstall /force to remove both the
    driver store entry AND any active device bindings.

    LOCALE-SAFE: All string comparisons use ordinal/invariant-culture rules.
    Works on any Windows locale (Turkish, German, Greek, Chinese, Hungarian,
    Polish, etc.) where default culture-sensitive comparison would risk
    mismatches on ASCII identifiers.

    INTUNE-SAFE: Reboot codes (3010, 1641) logged but NOT propagated to the
    session exit code.

.PARAMETER Delinflist
    Semicolon-separated list of original INF file names (without .inf extension).
    Example: "lmud1p40;lmud1o40;lmud1n40"

.PARAMETER ContinueOnError
    Continue if an error is encountered. Default: $true.

.EXAMPLE
    Remove-PnPDrivers -Delinflist "lmud1p40;lmud1o40;lmud1n40"

.NOTES
    Requires elevated context. PSADT v4 compatible.

#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Delinflist,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [boolean]$ContinueOnError = $true
    )

    Begin {
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        # Exit code classifications
        $successCodes = @(0, 259, 3010, 1641)
        $rebootCodes  = @(3010, 1641)

        # Locale-safe regex options (IgnoreCase + CultureInvariant)
        $regexOpts = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor `
                     [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    }

    Process {
        Try {
            #----------------------------------------------------------------------
            # Setup
            #----------------------------------------------------------------------
            $infDir     = "$env:WinDir\inf"
            $exePnPutil = "$env:WinDir\System32\PnPutil.exe"

            If (-not $Delinflist) {
                Write-ADTLogEntry -Message "Null value, please provide correct inf filenames." -Severity 3 -Source ${CmdletName}
                return
            }

            #----------------------------------------------------------------------
            # Search: find oem*.inf files matching target driver names
            #----------------------------------------------------------------------
            $oemInfList    = Get-ChildItem -Path "$infDir\*.*" -Include 'oem*.inf'
            $targetInfList = $Delinflist.Split(';') | Where-Object { $_ }
            $oemMatches    = New-Object System.Collections.Generic.List[string]

            foreach ($infName in $targetInfList) {

                $pattern = [regex]::Escape($infName) + '\.cat'
                $regex   = [System.Text.RegularExpressions.Regex]::new($pattern, $regexOpts)

                foreach ($inf in $oemInfList) {

                    $content = Get-Content -Path $inf.FullName -Raw -ErrorAction SilentlyContinue

                    If ($content -and $regex.IsMatch($content)) {
                        $oemMatches.Add($inf.Name)
                        Write-ADTLogEntry -Message "Found [$infName] in [$($inf.FullName)]" -Severity 2 -Source ${CmdletName}
                    }
                }
            }

            #----------------------------------------------------------------------
            # Early exit: nothing matched
            #----------------------------------------------------------------------
            If ($oemMatches.Count -eq 0) {
                foreach ($infName in $targetInfList) {
                    Write-ADTLogEntry -Message "No inf-files found matching pattern: $infName" -Severity 2 -Source ${CmdletName}
                }
                return
            }

            #----------------------------------------------------------------------
            # Remove: uninstall each matched driver (deduped with ordinal comparer)
            #----------------------------------------------------------------------
            $uniqueMatches = [System.Collections.Generic.HashSet[string]]::new(
                $oemMatches,
                [System.StringComparer]::OrdinalIgnoreCase
            )

            $rebootNeeded = $false

            foreach ($oem in $uniqueMatches) {

                Write-ADTLogEntry -Message "Removing driver [$oem]..." -Severity 1 -Source ${CmdletName}

                [psobject]$DriverResult = Start-ADTProcess `
                    -FilePath        $exePnPutil `
                    -ArgumentList    "/delete-driver $oem /uninstall /force" `
                    -CreateNoWindow `
                    -IgnoreExitCodes '*' `
                    -PassThru

                $exitCode = $DriverResult.ExitCode

                If ($successCodes -contains $exitCode) {

                    Write-ADTLogEntry -Message "Driver [$oem] removed successfully (exit code: $exitCode)." -Severity 1 -Source ${CmdletName}

                    If ($rebootCodes -contains $exitCode) {
                        $rebootNeeded = $true
                        Write-ADTLogEntry -Message "Driver [$oem] reported reboot-required (exit code: $exitCode)." -Severity 2 -Source ${CmdletName}
                    }
                }
                Else {
                    Write-ADTLogEntry -Message "Failed to remove driver [$oem] (exit code: $exitCode)." -Severity 3 -Source ${CmdletName}
                }
            }

            #----------------------------------------------------------------------
            # Reboot handling - SAFE for Intune/SCCM (never propagates 1641)
            #----------------------------------------------------------------------
            If ($rebootNeeded) {
                Write-ADTLogEntry `
                    -Message "Driver removal flagged reboot-required. NOT escalating to session exit code (Intune/SCCM safety)." `
                    -Severity 2 `
                    -Source ${CmdletName}
            }
        }
        Catch {
            Write-ADTLogEntry -Message "Failed to remove drivers. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}

            If (-not $ContinueOnError) {
                Throw "Failed to remove drivers: $($_.Exception.Message)"
            }
        }
    }

    End {
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}
#endregion


##*===============================================
##* MARK: SCRIPT BODY
##*===============================================

# Announce successful importation of module.
Write-ADTLogEntry -Message "Module [$($MyInvocation.MyCommand.ScriptBlock.Module.Name)] imported successfully." -ScriptSection Initialization
