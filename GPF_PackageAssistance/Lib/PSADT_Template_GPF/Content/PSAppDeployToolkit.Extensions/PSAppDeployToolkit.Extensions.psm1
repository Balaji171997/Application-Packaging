## Modified by AUDI AG (26/02/2026) under the provisions of the LGPLv3 or any later version.
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

##*===============================================
##* CUSTOM VARIABLE DECLARATION
##*===============================================

	#region WoW6432Node
	<#
		.SYNOPSIS
		Get the right Value for x86 or x64 systems
	#>
	
		## Variables: Registry
		if ( $env:PROCESSOR_ARCHITECTURE -eq 'AMD64' ) {
			[string]$Global:VWG_CurrentRegWOW = "Wow6432Node\"
		} else {
			[string]$Global:VWG_CurrentRegWOW = ""
		}

		## Variables: SysWOW
		if ( $env:PROCESSOR_ARCHITECTURE -eq 'AMD64' ) {
			[string]$Global:VWG_CurrentSysWOW = "SysWow64"
		} else {
			[string]$Global:VWG_CurrentSysWOW = "System32"
		}
	#endregion

	#region Installtitel 
	<#
		.SYNOPSIS
		Set the variable "installtitle", if this is not set.
	#>
    if (!($installTitle)){
        If ("*$appName*" -match $appVendor){
            $Global:installTitle = "$appName $appVersion"
        }Else{
            $Global:installTitle = "$appVendor $appName $appVersion"
        }
	}
	#endregion

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


# Custom functions from the PSAppDeployToolkit.psm1



# Custom functions from VWG

#region Function New-INIData
function New-IniData {
<#
.SYNOPSIS
 	Creates an INIData object to be used for creating, reading, updating, deleting or testing of INI file settings (sections, keys and values).
	Helper-Function for INI-Functions
.DESCRIPTION
 	Creates an INIData object container to be used for creating, reading, updating, deleting or testing of INI file settings (sections, keys and values).
	This container can then be used to execute multiple operations on a set of INI settings and finally to write those data back to an INI file.
	
	The function will return an empty INIData container, when no file is given and throw an error if accessing the INI source file fails.
.PARAMETER FromFile
	Optional. Set the name of an INI file from where the INIData object should get its settings.
.PARAMETER ContinueOnError
	Continue if an error is encountered. Default is: $true.
.EXAMPLE
	$INIData = New-INIData
	Creates a new empty INIData object.
.EXAMPLE
	$INIData = New-INIData -FromFile "$envWinDir\win.ini"
	Creates a new INIData object with all sections, keys and values of the file defined by parameter [-FromFile].
.NOTES
	This is an internal script function and should typically not be called directly.
.LINK
	http://www.volkswagen-group.com
#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$false)]
		[ValidateNotNullorEmpty()]
		[string]$FromFile,
		[Parameter(Mandatory=$false)] 
		[ValidateNotNullorEmpty()]
		[boolean]$ContinueOnError = $true
	)
	
	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process {
		Write-ADTLogEntry -Message "Create a new INIData object." -Source ${CmdletName}
		$IniData = [ordered]@{}
		if(($FromFile -ne $null) -and (Test-Path -Path $FromFile -PathType Leaf)){	#[1] if -FormFile is defined and valid, get INIData from there, otherwise... [2]
			[byte[]]$byte = get-content -Encoding byte -ReadCount 4 -TotalCount 4 -Path "filesystem::$FromFile"
			[string]$Encoding = ""
		
			if ($byte[0] -eq 0xff -and $byte[1] -eq 0xfe -and $byte[2] -eq 0x00 -and $byte[3] -eq 0x00){ 
				$Encoding = 'UTF32'	#equals UTF32-LE	[Bytes: 255 254 0 0
			}
			elseif ($byte[0] -eq 0x00 -and $byte[1] -eq 0x00 -and $byte[2] -eq 0xfe -and $byte[3] -eq 0xff){
				$Encoding = 'BigEndianUTF32'	#equals UTF32-BE [Bytes: 0   0  254 255 ]
			}
			elseif ($byte[0] -eq 0xff -and $byte[1] -eq 0xfe){ 
				$Encoding = 'Unicode' #equals UTF16-LE or String [Bytes: 255 254 !0 !0]
			}
			elseif ($byte[0] -eq 0xfe -and $byte[1] -eq 0xff){
				$Encoding = 'BigEndianUnicode' #equals UTF16-BE* [Bytes: 254 255 !0 !0]
			}
			elseif ($byte[0] -eq 0xef -and $byte[1] -eq 0xbb -and $byte[2] -eq 0xbf -and $byte[3]){ 
				$Encoding = 'UTF8'	#equals UTF8 BOM [Bytes: 239 187 191 92]
			}
			elseif ($byte[0] -eq 0x2b -and $byte[1] -eq 0x2f -and $byte[2] -eq 0x76){
				$Encoding = 'UTF7'	#equals UTF7 BOM [Bytes: 43 47 118 X]
			}
			else {
				$Encoding = 'ASCII'		#equals  [Bytes: any other/various]
			}
			$IniData["#INIFileEncoding#"] = @{}
			$IniData["#INIFileEncoding#"].add("Encoding",$Encoding)
			
			Try {
				$INIFile = [System.IO.File]::OpenText($FromFile)
				while($null -ne ($TextLine = $INIFile.ReadLine())) {
				    if($TextLine -eq ""){		#empty line
				        $KeyName               = "BlankLine_$CommentLineIndexPerSection"
						$Value                 = ""
						if (-not($SectionName)) {  
				            $SectionName                = "[HeaderCommentSection]"  
				            $IniData[$SectionName]      = [ordered]@{}  
							$CommentLineIndexPerSection = 0
				        } 
				        $IniData[$SectionName][$KeyName] = $Value			
					}
					elseif ($TextLine -match "^(\t*|\s*)\[(.+)\](\t*|\s*)$"){		 # line is ini section (starts with "[" & ends with "]")
						#Write-Host $Matches.Count + $Matches[0] + $Matches[1] + $Matches[2] + "#se"
				        $SectionName                = $TextLine
				        $IniData[$SectionName]      = [ordered]@{}
						$CommentLineIndexPerSection = 0
					}
					elseif ($TextLine -match "^(\t*|\s*)(#|;)(.*)$"){		                 # line is a comment
						if (-not($SectionName)) {  
				            $SectionName                = "[HeaderCommentSection]"  
				            $IniData[$SectionName]      = [ordered]@{}
							$CommentLineIndexPerSection = 0
				        } 
				        $KeyName               = "CommentLine_$CommentLineIndexPerSection"  
						$Value                 = $TextLine	
				        $IniData[$SectionName][$KeyName] = $Value
					}
					elseif ($TextLine -match "^(\t*|\s*)[^#;](\t*|\s*)(.+?)(\t*|\s*)=(\t*|\s*)(.*)(\t*|\s*)$"){		 # line is a key value pair (contains an "=" character between two values)
						if (-not($SectionName)) {  
				            $SectionName           = "[AutoGeneratedSection]"  
				            $IniData[$SectionName] = [ordered]@{}  
				        }
						$KeyName,$Value = $TextLine -split '=',2	#split at first occurence of =
				        $IniData[$SectionName][$KeyName] = $Value
				    }
					else{
					}
					$CommentLineIndexPerSection ++
				}
				$INIFile.close()
				Write-Output -InputObject ($IniData)
			}
			Catch {
				Write-ADTLogEntry -Message "Failed to create a new INIData object from file [$FromFile]. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
				If (-not $ContinueOnError) {
					Throw "Failed to create a new INIData object from file [$FromFile]: $($_.Exception.Message)"
				}
			}
		}
		<# elseif (($FromFile -ne $null) -and (-not (Test-Path -Path $FromFile -PathType Leaf))) { # [2] ... check if a file was given and return an error, if this file does not exit ... or [3]
			Write-Log -Message "The file path [$($FromFile)] does not exist. The INIData object could not be created." -Source ${CmdletName} -Severity 3
			If (-not $ContinueOnError) {
				Throw "The file path [$($FromFile)] does not exist. The INIData object could not be created."
			}
		}#>
		else {                         # [3] ... return an empty INIData Oject, while no file was defined as data source
				Write-Output -InputObject ($IniData)
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion New-INIData

#region Function INI-Create
function INI-Create($FromFile){
<#
.SYNOPSIS
	Creates an INI-Object from a File
	Helper-Function for INI-Functions
.DESCRIPTION
	Creates an INI-Object from a File
.PARAMETER FromFile
	Requires a Path to an INI-File
.EXAMPLE
	$CurrentINIContent = INI-Create -FromFile C:\Windows\ODBC.INI
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
		$IniData = [ordered]@{}
		$CommentLineIndexPerSection = 0
	}
	Process{
		if(($FromFile -ne $null) -and (Test-Path -Path $FromFile -PathType Leaf)){
			#[string]$FromFile
			[byte[]]$byte = get-content -Encoding byte -ReadCount 4 -TotalCount 4 -Path "filesystem::$FromFile"
			[string]$Encoding = ""
		
			if ($byte[0] -eq 0xff -and $byte[1] -eq 0xfe -and $byte[2] -eq 0x00 -and $byte[3] -eq 0x00){ 
				$Encoding = 'UTF32'	#equals UTF32-LE	[Bytes: 255 254 0 0
			}
			elseif ($byte[0] -eq 0x00 -and $byte[1] -eq 0x00 -and $byte[2] -eq 0xfe -and $byte[3] -eq 0xff){
				$Encoding = 'BigEndianUTF32'	#equals UTF32-BE [Bytes: 0   0  254 255 ]
			}
			elseif ($byte[0] -eq 0xff -and $byte[1] -eq 0xfe){ 
				$Encoding = 'Unicode' #equals UTF16-LE or String [Bytes: 255 254 !0 !0]
			}
			elseif ($byte[0] -eq 0xfe -and $byte[1] -eq 0xff){
				$Encoding = 'BigEndianUnicode' #equals UTF16-BE* [Bytes: 254 255 !0 !0]
			}
			elseif ($byte[0] -eq 0xef -and $byte[1] -eq 0xbb -and $byte[2] -eq 0xbf -and $byte[3]){ 
				$Encoding = 'UTF8'	#equals UTF8 BOM [Bytes: 239 187 191 92]
			}
			elseif ($byte[0] -eq 0x2b -and $byte[1] -eq 0x2f -and $byte[2] -eq 0x76){
				$Encoding = 'UTF7'	#equals UTF7 BOM [Bytes: 43 47 118 X]
			}
			else {
				$Encoding = 'ASCII'		#equals  [Bytes: any other/various]
			}
			$IniData["#INIFileEncoding#"] = @{}
			$IniData["#INIFileEncoding#"].add("Encoding",$Encoding)
			
			$INIFile = [System.IO.File]::OpenText($FromFile)
			while($null -ne ($TextLine = $INIFile.ReadLine())) {
			    if($TextLine -eq ""){		#empty line
			        $KeyName               = "BlankLine_$CommentLineIndexPerSection"
					$Value                 = ""
					if (-not($SectionName)) {  
			            $SectionName                = "[HeaderCommentSection]"  
			            $IniData[$SectionName]      = [ordered]@{}  
						$CommentLineIndexPerSection = 0
			        } 
			        $IniData[$SectionName][$KeyName] = $Value			
				}
				elseif ($TextLine -match "^(\t*|\s*)\[(.+)\](\t*|\s*)$"){		 # line is ini section (starts with "[" & ends with "]")
					#Write-Host $Matches.Count + $Matches[0] + $Matches[1] + $Matches[2] + "#se"
			        $SectionName                = $TextLine.Trim()
			        $IniData[$SectionName]      = [ordered]@{}
					$CommentLineIndexPerSection = 0
				}
				elseif ($TextLine -match "^(\t*|\s*)(#|;)(.*)$"){		                 # line is a comment
					if (-not($SectionName)) {  
			            $SectionName                = "[HeaderCommentSection]"  
			            $IniData[$SectionName]      = [ordered]@{}
						$CommentLineIndexPerSection = 0
			        } 
			        $KeyName               = "CommentLine_$CommentLineIndexPerSection"  
					$Value                 = $TextLine.Trim()	
			        $IniData[$SectionName][$KeyName] = $Value
				}
				elseif ($TextLine -match "^(\t*|\s*)[^#;](\t*|\s*)(.+?)(\t*|\s*)=(\t*|\s*)(.*)(\t*|\s*)$"){		 # line is a key value pair (contains an "=" character between two values)
					if (-not($SectionName)) {  
			            $SectionName           = "[AutoGeneratedSection]"  
			            $IniData[$SectionName] = [ordered]@{}  
			        }
					$KeyName,$Value = $TextLine -split '=',2	#split at first occurence of =
			        $IniData[$SectionName][$KeyName.Trim()] = $Value.Trim()
			    }
				else{
				}
				$CommentLineIndexPerSection ++
			}
			$INIFile.close()
		}
		else{
			$IniData["#INIFileEncoding#"] = @{}
			$IniData["#INIFileEncoding#"].add("Encoding","Unicode")
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
		return $IniData
	}
}
#endregion INI-Create

#region Function INI-WriteToFile
function INI-WriteToFile($TargetFile,[bool]$OverwriteTarget=$true){
<#
.SYNOPSIS
	INI-WriteToFile
	Helper-Function for INI-Functions
.DESCRIPTION
	Write INI-Object to INI-File
.PARAMETER TargetFile
	Requires an INI-Object Path to an INI-File
.PARAMETER OverwriteTarget
	Enables/Disables the overwrite. Standard = $true
.EXAMPLE
	$CurrentINIContent | INI-WriteToFile -TargetFile $File -OverwriteTarget $False
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process{
		$IniData = $_
		#if($OverwriteTarget){	#has to be deleted anyway anytime, because the entire file is hold in the IniData object
			if(Test-Path -Path $TargetFile -PathType Leaf){
				Remove-item -Path $TargetFile -Force
			}
		#}
		
		$Encoding = $IniData["#INIFileEncoding#"]["Encoding"]
		foreach ($SectionKey in $IniData.keys) {
	        if ($($IniData[$SectionKey].GetType().Name) -eq "OrderedDictionary"){  	                      #skip everything, which isn't a OrderedDictionary inside the $IniData object
				if($SectionKey -ne "[HeaderCommentSection]"){
					Add-Content -Path $TargetFile -Value "$SectionKey" -Encoding $Encoding                                     #write section entry
				}
	            Foreach ($ValueKey in $($IniData[$SectionKey].keys)) {
					$ValueKey  = $ValueKey
					$Value     = "$($IniData[$SectionKey][$ValueKey])"
	                if($ValueKey -match "^(\t*|\s*)BlankLine_(.*)$"){
						Add-Content -Path $TargetFile -Value "" -Encoding $Encoding 
					} elseif ($ValueKey -match "^(\t*|\s*)CommentLine_(.*)$"){

						Add-Content -Path $TargetFile -Value $Value -Encoding $Encoding 
					} else {
						Add-Content -Path $TargetFile -Value "$ValueKey=$Value" -Encoding $Encoding   #add keys and their values to their refering section
					}
	            }
	        }  
	    }
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function INI-AddSection
function INI-AddSection($SectionName){
<#
.SYNOPSIS
	INI-AddSection
    Helper-Function for INI-Functions
.DESCRIPTION
	Adds a Section to an INI-Object
.PARAMETER SectionName
	Name of a Section to Add
.EXAMPLE
	$CurrentINIContent = $CurrentINIContent | INI-AddSection $AddSection
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process{
		$IniData = $_
		if(-not($IniData["[$SectionName]"])) {
			$IniData.Add("[$SectionName]",[ordered]@{})
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
		return $IniData
	}
}
#endregion

#region Function INI-AddValue
function INI-AddValue($SectionName,$KeyName,$Value){
<#
.SYNOPSIS
	INI-AddValue
    Helper-Function for INI-Functions
.DESCRIPTION
	Adds a Value of a Key of a Section to an INI-Object
.PARAMETER SectionName
	Name of a Section
.PARAMETER Key
	Name of Key
.PARAMETER Value
	Value to set to the Key
.EXAMPLE
	$CurrentINIContent = $CurrentINIContent | INI-AddValue $Section $Key $Value
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process{
		$IniData = $_
		if($IniData["[$SectionName]"] -eq $null) {
			$IniData.Add("[$SectionName]",[ordered]@{})
		}
		if(($IniData["[$SectionName]"][$KeyName] -eq $null)) {
			$IniData["[$SectionName]"].Add($KeyName,"")
		}
		if($IniData["[$SectionName]"][$KeyName] -ne $null)  {
			$IniData["[$SectionName]"][$KeyName] = $Value
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
		return $IniData
	}
}
#endregion

#region Function INI-RemoveSection
function INI-RemoveSection($SectionName){
<#
.SYNOPSIS
	INI-RemoveSection
	Helper-Function for INI-Functions
.DESCRIPTION
	Removes a Section of an INI-Object
.PARAMETER SectionName
	Name of a Section to Remove
.EXAMPLE
	$CurrentINIContent = $CurrentINIContent | INI-RemoveSection $Section
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process{
		$IniData = $_
		if($IniData["[$SectionName]"] -ne $null) {
		$IniData.Remove("[$SectionName]")
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
		return $IniData
	}
}
#endregion

#region Function INI-RemoveKey
function INI-RemoveKey($SectionName,$KeyName){
<#
.SYNOPSIS
	INI-RemoveKey
    Helper-Function for INI-Functions
.DESCRIPTION
	Removes a Key of a Section of an INI-Object
.PARAMETER SectionName
	Name of a Section to Remove
.PARAMETER KeyName
	Name of a the Key to Remove
.EXAMPLE
	$CurrentINIContent = $CurrentINIContent | INI-RemoveKey $Section $Key
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process{
		$IniData = $_
		if($IniData["[$SectionName]"] -ne $null) {
			if(($IniData["[$SectionName]"][$KeyName] -ne $null)) {
				$IniData["[$SectionName]"].Remove($KeyName)
			}
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
		return $IniData
	}
}
#endregion

#region Function INI-CheckForSectionExisting
function INI-CheckForSectionExisting($SectionName){
<#
.SYNOPSIS
	INI-CheckForSectionExisting
    Helper-Function for INI-Functions
.DESCRIPTION
	Checks if a Section exist in an INI-Object
.PARAMETER SectionName
	Name of a Section to check
.EXAMPLE
	$returnValue = $CurrentINIContent | INI-CheckForSectionExisting $Section
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process{
		$IniData = $_
		[bool]$SectionExists = $false
		if($IniData["[$SectionName]"] -ne $null) {
			$SectionExists = $true
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
		return $SectionExists
	}
}
#endregion

#region Function INI-CheckForKeyExisting
function INI-CheckForKeyExisting($SectionName,$KeyName){
<#
.SYNOPSIS
	INI-CheckForKeyExisting
    Helper-Function for INI-Functions
.DESCRIPTION
	Checks if a Key exist in an INI-Object
.PARAMETER SectionName
	Name of a Section
.PARAMETER KeyName
	Name of a Key to check
.EXAMPLE
	$returnValue = $CurrentINIContent | INI-CheckForKeyExisting $Section $Key
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process{
		$IniData   = $_
		[bool]$KeyExists = $false
		if($IniData["[$SectionName]"] -ne $null) {
			if(($IniData["[$SectionName]"][$KeyName] -ne $null)) {
				$KeyExists = $true
			}	
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
		return $KeyExists
	}
}
#endregion

#region Function INI-CheckForValueExisting
function INI-CheckForValueExisting($SectionName,$KeyName,$Value){
<#
.SYNOPSIS
	INI-CheckForValueExisting
    Helper-Function for INI-Functions
.DESCRIPTION
	Checks if a Value exist in an INI-Object
.PARAMETER SectionName
	Name of a Section
.PARAMETER KeyName
	Name of a Key
.PARAMETER Value
	Value to Check
.EXAMPLE
	$returnValue = $CurrentINIContent | INI-CheckForValueExisting $Section
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process{
		$IniData = $_
		[bool]$ValueExists = $false
		if($IniData["[$SectionName]"] -ne $null) {
			if(($IniData["[$SectionName]"][$KeyName] -ne $null)) {
				if(($IniData["[$SectionName]"][$KeyName] -match ("^" + [Regex]::Escape($Value) + "$"))) {
					$ValueExists = $true
				}
			} 		
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
		return $ValueExists
	}
}
#endregion

#region Function INI-GetAllSections
function INI-GetAllSections(){
<#
.SYNOPSIS
	INI-GetAllSections
    Helper-Function for INI-Functions
.DESCRIPTION
	Returns a List of all Sectionnames of an INI-Object
.EXAMPLE
	$CurrentINIContent | INI-GetAllSections
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process{
		$IniData = $_
		$AllSections = $IniData.Keys | Sort
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
		return $AllSections
	}
	
}
#endregion

#region Function INI-GetKey
function INI-GetKey($SectionName,$KeyName){
<#
.SYNOPSIS
	INI-GetKey
    Helper-Function for INI-Functions
.DESCRIPTION
	Returns an Array of all Sectionnames in an INI-Object
.PARAMETER SectionName
	Name of a Section
.PARAMETER KeyName
	Name of a Key
.EXAMPLE
	$CurrentINIContent | INI-GetKey $Section $Key
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process{
		$IniData    = $_
		$KeyContent = $null
		if($IniData["[$SectionName]"] -ne $null) {
			if(($IniData["[$SectionName]"][$KeyName] -ne $null)) {
				$KeyContent = $IniData["[$SectionName]"][$KeyName]
			} 		
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
		return $KeyContent
	}
}
#endregion

#region Function INI-GetAllKeys
function INI-GetAllKeys($SectionName){
<#
.SYNOPSIS
	INI-GetAllKeys
    Helper-Function for INI-Functions
.DESCRIPTION
	Returns an Array of all Sectionnames in an INI-Object
.PARAMETER SectionName
	Name of a Section
.EXAMPLE
	$CurrentINIContent | INI-GetAllKeys $Section 
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process{
		$IniData = $_
		$KeyListContent = $null
		if($IniData["[$SectionName]"] -ne $null) {
			$KeyListContent = $IniData["[$SectionName]"].Keys | Sort
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
		return $KeyListContent
	}
}
#endregion

#region Function Set-IniData
function Set-IniData {
<#
.SYNOPSIS
	Modifies an existing INI-File, if not exist it creates a new one.
.DESCRIPTION
	Modifies an existing INI-File, if not exist it creates a new one.
.PARAMETER File
	Requires a Path to an INI-File
.PARAMETER Section
	Requires a Section of an INI-File
.PARAMETER Key
	Requires an existing Key of an INI-File or a new Keyname
.PARAMETER Value
	The Value of the Key
.EXAMPLE
	Set-IniData -File "C:\Daten\INI\Test File.ini" -Section "TESTSECTION" -Key "TESTKEY" -Value "TESTVALUE"
	Adds a Section,Key and Value if the same not already exists and overrides Value others
.EXAMPLE
	Set-IniData -File "C:\Daten\INI\Test File.ini" -Section "TESTSECTION"
	Adds a Section if it not already exists
.NOTES
	Fileoperations returns $false/$null if everything was successfully, else $true
.LINK
	http://www.volkswagen-group.com
#>
[CmdletBinding()]
	param (
		# File
		[Parameter(Mandatory=$true,Position=0)]
		[ValidateNotNullorEmpty()]
		[String]$File,
		# Section-Operations
		[Parameter(Mandatory=$true,Position=1)]
		[ValidateNotNullorEmpty()]
		[String]$Section,
		# Key
		[Parameter(ParameterSetName="Key",Mandatory=$false,Position=2)]
		[Parameter(ParameterSetName="Value",Mandatory=$true,Position=2)]
		[ValidateNotNullorEmpty()]
		[String]$Key,
		# Value
		[Parameter(ParameterSetName="Value",Mandatory=$true,Position=3)]
		[AllowEmptyString()]
		[String]$Value
	)
begin{
	[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
	Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	#region Declare Global Variables and Constants
	##*===================================================================
	##* Declare Global Variables and Constants
	##*===================================================================
	$returnValue = $false
	$CurrentINIContent = [ordered]@{}
	$iniFileChanged = $false
	$changeNeeded = $false
	$parameter = "Set-IniData to $File"
	#endregion Declare Global Variables and Constants
}
process {
	if (Test-Path -Path $File -PathType Leaf){
		$CurrentINIContent = New-INIData -FromFile $File
	}
	else {
		$destinationPath = Split-Path $File
		if(!(Test-Path -Path $destinationPath)){
			New-ADTFolder -Path $destinationPath
		}
		$CurrentINIContent = INI-Create $File
	}
	#write-host "############1 " $CurrentINIContent.gettype()
	if($Value)
	{ # Set Value to Key
		$parameter = "Set-IniData: Set $Value in $Key in $Section in $File"
		if(!($CurrentINIContent | INI-CheckForValueExisting $Section $Key $Value))
		{
			$CurrentINIContent = $CurrentINIContent | INI-AddValue $Section $Key $Value
			$changeNeeded = $true
		}
		$iniFileChanged = $true
	}
	elseif(!($Value) -and (!$Key) -and $Section)
	{ # Add Section
		$parameter = "Set-IniData: Add $Section in $File"
		if(!($CurrentINIContent | INI-CheckForSectionExisting $Section)){
			$CurrentINIContent = $CurrentINIContent | INI-AddSection $Section
			$changeNeeded = $true
		}
		$iniFileChanged = $true
	}
	if($CurrentINIContent | INI-CheckForSectionExisting "DUMMY"){
		$CurrentINIContent = $CurrentINIContent | INI-RemoveSection "DUMMY"
	}
}
end {
	if($iniFileChanged)
	{
		try{
			$changeNeeded
			if($changeNeeded){
				$CurrentINIContent | INI-WriteToFile -TargetFile $File
				Write-ADTLogEntry -Message "$parameter Sucessfully" -Source "Set-IniData" -Severity 1
			}
			else
			{
				Write-ADTLogEntry -Message "$parameter is already set" -Source "Set-IniData" -Severity 2
			}
		}
		catch{
			Write-ADTLogEntry -Message "Error While: $parameter" -Source "Set-IniData" -Severity 3
			$_
			$returnValue = $true
		}
	}
	Complete-ADTFunction -Cmdlet $PSCmdlet
	Return $returnValue
}
}

#endregion Set-IniData

#region Function Remove-IniData
function Remove-IniData {
<#
.SYNOPSIS
	Remove-IniData removes Sections, Keys or Values from Ini-File
.DESCRIPTION
	Removes Sections, Keys or Values from Ini-File
.PARAMETER File
	Requires a Path to an INI-File
.PARAMETER Section
	Requires a Section of an INI-File
.PARAMETER Key
	Requires an existing Key of an INI-File or a new Keyname
.PARAMETER Value
	The Value of the Key
.EXAMPLE
	Remove-IniData -File "C:\Daten\INI\Test File.ini" -Section "ODBC 32 bit Data Sources" -Key "TESTKEY" -Value
	Removes the Value of a Key
.EXAMPLE
	Remove-IniData -File "C:\Daten\INI\Test File.ini" -Section "ODBC 32 bit Data Sources" -Key "TESTKEY"
	Removes the Key
.EXAMPLE
	Remove-IniData -File "C:\Daten\INI\Test File.ini" -Section "ODBC 32 bit Data Sources"
	Removes a Section
.NOTES
	Fileoperations returns $false/$null if everything was successfully, else $true
.LINK
	http://www.volkswagen-group.com
#>
[CmdletBinding()]
	param (
		# File
		[Parameter(Mandatory=$true,Position=0)]
		[ValidateNotNullorEmpty()]
		[String]$File,
		# Section-Operations
		[Parameter(Mandatory=$true,Position=1)]
		[ValidateNotNullorEmpty()]
		[String]$Section,
		# Key
		[Parameter(ParameterSetName="Key",Mandatory=$false,Position=2)]
		[Parameter(ParameterSetName="Value",Mandatory=$true,Position=2)]
		[ValidateNotNullorEmpty()]
		[String]$Key,
		# Value
		[Parameter(ParameterSetName="Value",Mandatory=$true,Position=3)]
		[Switch]$Value
	)
begin{
	[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
	Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	#region Declare Global Variables and Constants
	##*===================================================================
	##* Declare Global Variables and Constants
	##*===================================================================
	$returnValue = $false
	$CurrentINIContent = [ordered]@{}
	$iniFileChanged = $false
	$changeNeeded = $false
	$parameter = "Remove-IniData from $File"
	#endregion Declare Global Variables and Constants
}
process {
	$CurrentINIContent = INI-Create -FromFile $File
	if($Value)
	{ # Remove Value
		$parameter = "Remove-IniData: Remove Value from $Key from $Section from $File"
		if(!($CurrentINIContent | INI-CheckForValueExisting $Section $Key ""))
		{
			$CurrentINIContent = $CurrentINIContent | INI-AddValue $Section $Key ""
			$changeNeeded = $true
		}
		$iniFileChanged = $true
	}
	elseif(!($Value) -and $Key)
	{ # Remove Key
		$parameter = "Remove-IniData: Remove $Key from $Section from $File"
		if($CurrentINIContent | INI-CheckForKeyExisting $Section $Key)
		{
			$CurrentINIContent = $CurrentINIContent | INI-RemoveKey $Section $Key
			$changeNeeded = $true
		}
		$iniFileChanged = $true
	}
	elseif(!($Value) -and (!$Key) -and $Section)
	{ # Remove Section
		$parameter = "Remove-IniData: Remove $Section from $File"
		if($CurrentINIContent | INI-CheckForSectionExisting $Section){
			$CurrentINIContent = $CurrentINIContent | INI-RemoveSection $Section
			$changeNeeded = $true
		}
		$iniFileChanged = $true
	}
}
end {
	if($iniFileChanged)
	{
		try{
			if($changeNeeded){
				$CurrentINIContent | INI-WriteToFile -TargetFile $File
				Write-ADTLogEntry -Message "$parameter Sucessfully" -Source "Remove-IniData" -Severity 1
			}
			else
			{
				Write-ADTLogEntry -Message "$parameter is already removed" -Source "Remove-IniData" -Severity 2
			}
		}
		catch{
			Write-ADTLogEntry -Message "Error While: $parameter" -Source "Remove-IniData" -Severity 3
			$returnValue = $true
		}
	}
	Complete-ADTFunction -Cmdlet $PSCmdlet
	Return $returnValue
}
}

#endregion Remove-IniData

#region Function Get-IniData
function Get-IniData {
<#
.SYNOPSIS
	Gets Information of an INI-File
.DESCRIPTION
	Gets Information of an INI-File
.PARAMETER File
	Requires a Path to an INI-File
.PARAMETER Section
	Returns a List of Keys of an INI-File
.PARAMETER Key
	Returns the Value from the Key of an INI-File
.Parameter GetSections
	Returns a List of Sections of an INI-File
.EXAMPLE
	Get-IniData -File "C:\Daten\INI\Test.INI" -Section "TestSection" -Key "TestKey"
	Returns the Value from the Key of an INI-File
.EXAMPLE
	Get-IniData -File "C:\Daten\INI\Test.INI" -Section "TestSection"
	Returns a List of all Keys in this Section
.EXAMPLE
	Get-IniData -File "C:\Daten\INI\Test.INI" -GetSections
	Returns a List of all Sections in this File
.NOTES
	Get-IniData returns $false/content/Lists
.LINK
	http://www.volkswagen-group.com
#>
[CmdletBinding()]
	param (
		# File
		[Parameter(Mandatory=$true,Position=0)]
		[ValidateNotNullorEmpty()]
		[String]$File,
		# Section-Operations
		[Parameter(ParameterSetName="Section",Mandatory=$true,Position=1)]
		[Parameter(ParameterSetName="Key",Mandatory=$true,Position=1)]
		[ValidateNotNullorEmpty()]
		[String]$Section,
		[Parameter(ParameterSetName="GetSections",Mandatory=$true,Position=1)]
		[Switch]$GetSections,
		# Key
		[Parameter(ParameterSetName="Key",Mandatory=$true,Position=2)]
		[ValidateNotNullorEmpty()]
		[String]$Key
	)
begin{
	[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
	Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	#region Declare Global Variables and Constants
	##*===================================================================
	##* Declare Global Variables and Constants
	##*===================================================================
	$returnValue = $false
	$CurrentINIContent = [ordered]@{}
	$parameter = "Get-IniData from $File"
	#endregion Declare Global Variables and Constants
}
process {
	$CurrentINIContent = INI-Create -FromFile $File
	if($Key)
	{
		$returnValue = $CurrentINIContent | INI-GetKey $Section $Key
		$parameter = "Get-IniData: Get Value $retunValue From Key: $Key from Section: $Section from $File"
	}
	elseif((!$Key) -and $Section)
	{
		$returnValue = $CurrentINIContent | INI-GetAllKeys $Section
		$returncount = $returnValue.count
		$parameter = "Get-IniData: Get $returncount Keys from Section: $Section from $File"
	}
	elseif((!$Key) -and (!($Section)) -and $GetSections)
	{
		$returnValue = $CurrentINIContent | INI-GetAllSections
		$returncount = $returnValue.count
		$parameter = "Get-IniData: Get $returncount Sections from $File"
	}
}
end {
	if($returnValue){
		Write-ADTLogEntry -Message "$parameter Sucessfully" -Source "Get-IniData" -Severity 1
	}
	else {
		Write-ADTLogEntry -Message "$parameter not Found" -Source "Get-IniData" -Severity 1
	}
	Complete-ADTFunction -Cmdlet $PSCmdlet
	Return $returnValue
}
}

#endregion Get-IniData

#region Function Test-IniData
function Test-IniData {
<#
.SYNOPSIS
	Checks the Content of an INI-File
.DESCRIPTION
	Checks the Content of an INI-File
.PARAMETER File
	Requires a Path to an INI-File
.PARAMETER Section
	Section of an INI-File
.PARAMETER Key
	Key of an INI-File
.PARAMETER Value
	The Value of the Key
.EXAMPLE
	Test-IniData -File "$CurrentINIFile" -Section "ODBC 32 bit Data Sources" -Key "TESTKEY" -Value "TESTVALUE"
	Test Value
.EXAMPLE
	Test-IniData -File "$CurrentINIFile" -Section "ODBC 32 bit Data Sources" -Key "TESTKEY"
	Test Key
.EXAMPLE
	Test-IniData -File "$CurrentINIFile" -Section "ODBC 32 bit Data Sources"
	Test Section
.NOTES
	returns $true if Section/Key/Value exist, else $false 
.LINK
	http://www.volkswagen-group.com
#>
[CmdletBinding()]
	param (
		# File
		[Parameter(Mandatory=$true,Position=0)]
		[ValidateNotNullorEmpty()]
		[String]$File,
		# Section-Operations
		[Parameter(Mandatory=$true,Position=1)]
		[ValidateNotNullorEmpty()]
		[String]$Section,
		# Key
		[Parameter(ParameterSetName="Value",Mandatory=$true,Position=2)]
		[Parameter(ParameterSetName="Key",Mandatory=$false,Position=2)]
		[ValidateNotNullorEmpty()]
		[String]$Key,
		# Value
		[Parameter(ParameterSetName="Value",Mandatory=$true,Position=3)]
		[ValidateNotNullorEmpty()]
		[String]$Value
	)
	
begin{
	[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
	Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	#region Declare Global Variables and Constants
	##*===================================================================
	##* Declare Global Variables and Constants
	##*===================================================================
	$returnValue = $false
	$CurrentINIContent = [ordered]@{}
	$parameter = ""
	#endregion Declare Global Variables and Constants
}
process {
	$CurrentINIContent = INI-Create -FromFile $File
	if($Value)
	{
		$returnValue = $CurrentINIContent | INI-CheckForValueExisting $Section $Key $Value
		$parameter = "Value: $Value in Key: $Key in Section: $Section in $File"
	}
	elseif(!($Value) -and $Key -and $Section)
	{
		$returnValue = $CurrentINIContent | INI-CheckForKeyExisting $Section $Key
		$parameter = "Key: $Key in Section: $Section in $File"
	}
	elseif(!($Value) -and !($Key) -and $Section)
	{
		$returnValue = $CurrentINIContent | INI-CheckForSectionExisting $Section
		$parameter = "Section: $Section in $File"
	}
}
end {
	if($returnValue){
		Write-ADTLogEntry -Message "$parameter Found" -Source "Test-IniData" -Severity 1
	}
	else
	{
		Write-ADTLogEntry -Message "$parameter not Found" -Source "Test-IniData" -Severity 1
	}
	Complete-ADTFunction -Cmdlet $PSCmdlet
	Return $returnValue
}
}

#endregion Test-IniData

#region Function Import-Certificates
function Import-Certificates {
<#
.SYNOPSIS
	Imports certificate
.DESCRIPTION
	Imports certificate in specified certificate store.
.PARAMETER CertFile
	The certificate file to be imported.	
.PARAMETER StoreNames
	The certificate store(s) in which the certificate should be imported.	
.PARAMETER StoreType
	LocalMachine - Using the local machine certificate store to import the certificate
	CurrentUser - Using the current user certificate store to import the certificate	
.PARAMETER CertPassword
	The password which may be used to protect the certificate file
.EXAMPLE
    Import-Certificates C:\Temp\myCert.cer my
.EXAMPLE
    Import-Certificates -CertFile C:\Temp\myCert.cer -StoreNames my
.EXAMPLE
    Import-Certificates -Cert $certificate -StoreNames my -StoreType LocalMachine 
.EXAMPLE
    Import-Certificates -Cert $certificate -StoreNames my -ST Machine 
.EXAMPLE
    ls cert:\currentUser\TrustedPublisher | Import-Certificates -ST Machine -SN TrustedPublisher
	Copies the certificates found in current users TrustedPublishers store to local machines TrustedPublisher using alias  
.NOTES
.LINK
	http://www.volkswagen-group.com
	
#>
    [CmdletBinding()]
    param (
	    [Parameter(ValueFromPipeline=$true,Mandatory=$true, Position=0, ParameterSetName="CertFile")]
	    [System.IO.FileInfo]$CertFile,
	    [Parameter(ValueFromPipeline=$true,Mandatory=$true, Position=0, ParameterSetName="Cert")]
	    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert,  
	    [Parameter(Position=1)]
	    [Alias("SN")]
	    [string[]] $StoreNames = "My",   
	    [Parameter(Position=2)]
	    [Alias("Type","ST")]
	    [ValidateSet("LocalMachine","Machine","CurrentUser","User")]
	    [string]$StoreType = "CurrentUser",
	    [Parameter(Position=3)]
	    [Alias("Password","PW")]
	    [string] $CertPassword
    )
   
    begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	
    	[void][System.Reflection.Assembly]::LoadWithPartialName("System.Security")
    }
   
    process {
	    switch ($pscmdlet.ParameterSetName) {
	        "CertFile" {
	            try {
	                $Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $($CertFile.FullName),$CertPassword
	            }
	            catch {  
					Write-ADTLogEntry -Message " Error reading '$CertFile': $_ ." -Severity 1 -Source ${CmdletName}
	            }
	        }
	        "Cert" {
	      	
			 
	        }
	        default {
				Write-ADTLogEntry -Message " Missing parameter:`nYou need to specify either a certificate or a certificate file name." -Severity 1 -Source ${CmdletName}
	        }
	    }

	    switch -regex ($storeType) {
	        "Machine$" { $StoreScope = "LocalMachine" }
	        "User$"  { $StoreScope = "CurrentUser" }
	    }
	   
	    if ( $Cert ) {
	    	$StoreNames | ForEach-Object {
		        $StoreName = $_
		        Write-Verbose " [Import-Certificate] :: $($Cert.Subject) ($($Cert.Thumbprint))"
		        Write-Verbose " [Import-Certificate] :: Import into cert:\$StoreScope\$StoreName"
	           
		        if (Test-Path "cert:\$StoreScope\$StoreName") {
		                try {
			                $store = New-Object System.Security.Cryptography.X509Certificates.X509Store $StoreName, $StoreScope
			                $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
			                $store.Add($Cert)
							
			                if ( $CertFile ) {
								Write-ADTLogEntry -Message " [Import-Certificate] :: Successfully added '$CertFile' to 'cert:\$StoreScope\$StoreName'." -Severity 1 -Source ${CmdletName}
			                } else {
								Write-ADTLogEntry -Message " [Import-Certificate] :: Successfully added '$($Cert.Subject) ($($Cert.Thumbprint))' to 'cert:\$StoreScope\$StoreName'." -Severity 1 -Source ${CmdletName}
			                }
		                }
		                catch {
							Write-ADTLogEntry -Message "Error adding '$($Cert.Subject) ($($Cert.Thumbprint))' to 'cert:\$StoreScope\$StoreName': $_ ." -Severity 3 -Source ${CmdletName}
		                }
						
		                if ( $store ) {
		                    $store.Close()
		                }
		        } else {
					Write-ADTLogEntry -Message "Certificate store '$StoreName' does not exist. Skipping..." -Severity 3 -Source ${CmdletName}
		        }
	        }
	    } else {
			Write-ADTLogEntry -Message "No certificates found." -Severity 3 -Source ${CmdletName}
	    }
    }
    end {
		Write-ADTLogEntry -Message "Finished importing certificates." -Severity 1 -Source ${CmdletName}
		
		Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}
#endregion

#region Function Replace-StringInFile
Function Replace-StringInFile {
<#
.SYNOPSIS
    Replaces strings in files using a regular expression.
.DESCRIPTION
    Replaces strings in files using a regular expression. Supports
    multi-line searching and replacing.
.PARAMETER Pattern
    Specifies the regular expression pattern.
.PARAMETER Replacement
    Specifies the regular expression replacement pattern.
.PARAMETER Path
    Specifies the path to one or more files. Wildcards are permitted. Each
    file is read entirely into memory to support multi-line searching and
    replacing, so performance may be slow for large files.
.PARAMETER LiteralPath
    Specifies the path to one or more files. The value of the this
    parameter is used exactly as it is typed. No characters are interpreted
    as wildcards. Each file is read entirely into memory to support
    multi-line searching and replacing, so performance may be slow for
    large files.
.PARAMETER CaseSensitive
    Specifies case-sensitive matching. The default is to ignore case.
.PARAMETER Multiline
    Changes the meaning of ^ and $ so they match at the beginning and end,
    respectively, of any line, and not just the beginning and end of the
    entire file. The default is that ^ and $, respectively, match the
    beginning and end of the entire file.
.PARAMETER UnixText
    Causes $ to match only linefeed (\n) characters. By default, $ matches
    carriage return+linefeed (\r\n). (Windows-based text files usually use
    \r\n as line terminators, while Unix-based text files usually use only
    \n.)
.PARAMETER Overwrite
    Overwrites a file by creating a temporary file containing all
    replacements and then replacing the original file with the temporary
    file. The default is to output but not overwrite.
.PARAMETER Force
    Allows overwriting of read-only files. Note that this parameter cannot
    override security restrictions.
.PARAMETER Encoding
    Specifies the encoding for the file when -Overwrite is used. Possible
    values are: ASCII, BigEndianUnicode, Unicode, UTF32, UTF7, or UTF8. The
    default value is ASCII.
.INPUTS
    System.IO.FileInfo.
.OUTPUTS
    System.String without the -Overwrite parameter, or nothing with the
    -Overwrite parameter.
.EXAMPLE
    Replace-StringInFile -Pattern '(Ferb) and (Phineas)' -Replacement '$2 and $1' -Path Story.txt
    This command replaces the string 'Ferb and Phineas' with the string
    'Phineas and Ferb' in the file Story.txt and outputs the file. Note
    that the pattern and replacement strings are enclosed in single quotes
    to prevent variable expansion.
.EXAMPLE
    Replace-StringInFile -Pattern 'Perry' -Replacement 'Agent P' -Path Ferb.txt -Overwrite
    This command replaces the string 'Perry' with the string 'Agent P' in
    the file Ferb.txt and overwrites the file.
.NOTES

.LINK
	http://www.volkswagen-group.com
#>
    [CmdletBinding(DefaultParameterSetName="Path",SupportsShouldProcess=$TRUE)]
    param(
        [parameter(Mandatory=$TRUE,Position=0)]
        [String] $Pattern,
        [parameter(Mandatory=$TRUE,Position=1)]
        [String] [AllowEmptyString()] $Replacement,
        [parameter(Mandatory=$TRUE,ParameterSetName="Path",Position=2,ValueFromPipeline=$TRUE)]
        [String[]] $Path,
        [parameter(Mandatory=$TRUE,ParameterSetName="LiteralPath",Position=2)]
        [String[]] $LiteralPath,
        [Switch] $CaseSensitive,
        [Switch] $Multiline,
        [Switch] $UnixText,
        [Switch] $Overwrite,
        [Switch] $Force,
        [String] $Encoding="ASCII"
    )

    begin {
	
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	
	    # Throw an error if $Encoding is not valid.
	    $encodings = @("ASCII","BigEndianUnicode","Unicode","UTF32","UTF7","UTF8")
	    if ($encodings -notcontains $Encoding) {
		    throw "Encoding must be one of the following: $encodings"
	    }

	    # Extended test-path: Check the parameter set name to see if we
	    # should use -literalpath or not.
	    function test-pathEx($path) {
		    switch ($PSCmdlet.ParameterSetName) {
			    "Path" {
				    test-path $path
			    }
			    "LiteralPath" {
				    test-path -literalpath $path
			    }
		    }
	    }

	    # Extended get-childitem: Check the parameter set name to see if we
	    # should use -literalpath or not.
	    function get-childitemEx($path) {
		    switch ($PSCmdlet.ParameterSetName) {
			    "Path" {
				    get-childitem $path -force
			    }
			    "LiteralPath" {
				    get-childitem -literalpath $path -force
			    }
		    }
	    }

	    # Outputs the full name of a temporary file in the specified path.
	    function get-tempname($path) {
		    do {
			    $tempname = join-path $path ([IO.Path]::GetRandomFilename())
		    }
		    while (test-path $tempname)
		    $tempname
	    }

	    # Use '\r$' instead of '$' unless -UnixText specified because
	    # '$' alone matches '\n', not '\r\n'. Ignore '\$' (literal '$').
	    if (-not $UnixText) {
		    $Pattern = $Pattern -replace '(?<!\\)\$', '\r$'
	    }

	    # Build an array of Regex options and create the Regex object.
	    $opts = @()
	    if (-not $CaseSensitive) {
		    $opts += "IgnoreCase"
	    }
	    if ($MultiLine) {
		    $opts += "Multiline"
	    }
	    if ($opts.Length -eq 0) {
		    $opts += "None"
	    }
	    $regex = new-object Text.RegularExpressions.Regex $Pattern, $opts
	
    }

    process {
	    # The list of items to iterate depends on the parameter set name.
	    switch ($PSCmdlet.ParameterSetName) {
		    "Path" {
			    $list = $Path
		    }
		    "LiteralPath" {
			    $list = $LiteralPath
		    }
	    }

	    # Iterate the items in the list of paths. If an item does not exist,
	    # continue to the next item in the list.
	    foreach ($item in $list) {
		    if (-not (test-pathEx $item)) {
			    Write-ADTLogEntry -Message "Unable to find '$item'." -Source ${CmdletName}
			    continue
		    }

		    # Iterate each item in the path. If an item is not a file,
		    # skip all remaining items.
		    foreach ($file in get-childitemEx $item) {
			    if ($file -isnot [IO.FileInfo]) {
				    Write-ADTLogEntry -Message "'$file' is not in the file system." -Source ${CmdletName}
				    break
			    }

			    # Get a temporary file name in the file's directory and create
			    # it as a empty file. If set-content fails, continue to the next
			    # file. Better to fail before than after reading the file for
			    # performance reasons.
			    if ($Overwrite) {
				    $tempname = get-tempname $file.DirectoryName
				    set-content $tempname $NULL -confirm:$FALSE
				    if (-not $?) {
					    continue
				    }
				    Write-ADTLogEntry -Message "Created file '$tempname'." -Source ${CmdletName}
			    }

			    # Read all the text from the file into a single string. We have
			    # to do it this way to be able to search across line breaks.
			    try {
				    Write-ADTLogEntry -Message "Reading '$file'." -Source ${CmdletName}
				    $text = [IO.File]::ReadAllText($file.FullName)
				    Write-ADTLogEntry -Message "Finished reading '$file'." -Source ${CmdletName}
			    }
			    catch [Management.Automation.MethodInvocationException] {
				    Write-ADTLogEntry -Message "$ERROR[0]" -Source ${CmdletName}
				    continue
			    }

			    # If -Overwrite not specified, output the result of the Replace
			    # method and continue to the next file.
			    if (-not $Overwrite) {
				    $regex.Replace($text, $Replacement)
				    continue
			    }
			    # Do nothing further if we're in 'what if' mode.
			    if ($WHATIFPREFERENCE) {
				    continue
			    }
			    try {
				    Write-ADTLogEntry -Message "Writing '$tempname'." -Source ${CmdletName}
				    [IO.File]::WriteAllText("$tempname", $regex.Replace($text,$Replacement), [Text.Encoding]::$Encoding)
				    Write-ADTLogEntry -Message "Finished writing '$tempname'." -Source ${CmdletName}
				    Write-ADTLogEntry -Message "Copying '$tempname' to '$file'." -Source ${CmdletName}
				    copy-item $tempname $file -force:$Force -erroraction Continue
				    if ($?) {
					    Write-ADTLogEntry -Message "Finished copying '$tempname' to '$file'." -Source ${CmdletName}
				    }
				    remove-item $tempname
				    if ($?) {
					    Write-ADTLogEntry -Message "Removed file '$tempname'." -Source ${CmdletName}
				    }
			    }
			    catch [Management.Automation.MethodInvocationException] {
				    Write-ADTLogEntry -Message "$ERROR[0]" -Source ${CmdletName}
			    }
		    } # foreach $file
	    } # foreach $item
    } # process
    end {
		Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}
#endregion

#region Function Set-ApplicationWizardEntry
Function Set-ApplicationWizardEntry {
<#
.SYNOPSIS
 	Creates custom Application Wizard entry and copy/set display icon in registry for applications which not have one and for detection in SCCM.
.DESCRIPTION
	Creates a folder $envProgramData\AppWizIco, if not exist. Copies an icon file from $dirSupportFiles\Icon.ico into $envProgramData\AppWizIco.
	Creates a new Application Wizard entry in registry.
.PARAMETER ApplicationName
	The ApplicationName is the $VWG_appfriendlyName and default.
.EXAMPLE
	Set-ApplicationWizardEntry 
	Set the custom Application Wizard entry and copy/set display icon for default $VWG_appfriendlyName.
.EXAMPLE
	Set-ApplicationWizardEntry -ApplicationName 'Logon Screen'
	Set the custom Application Wizard entry and copy/set display icon and overrides default $VWG_appfriendlyName because contains spaces and special characters.
.NOTES
.LINK
	http://www.volkswagen-group.com
#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$ApplicationName = $VWG_appfriendlyName
	)
	
	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process {
		Try {
			Write-ADTLogEntry -Message "Begin set Application Wizard entry." -Severity 1 -Source ${CmdletName} 
	
			if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64' ) {
				if ( $appArch -eq 'x64') {
					$ArpKey = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ApplicationName"
				} else {
					$ArpKey = "HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$ApplicationName"	
				}
			} else {
				$ArpKey = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ApplicationName"
	        }
			
            $envProgramData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonApplicationData)

			If (-not (Test-Path -path "$envProgramData\AppWizIco")){
				Write-ADTLogEntry -Message "Create Folder $envProgramData\AppWizIco folder." -Severity 1 -source ${CmdletName} 
				New-ADTFolder -Path "$envProgramData\AppWizIco"
			}
 			Write-ADTLogEntry -Message "Copy Icon for display Application Wizard." -Severity 1 -source ${CmdletName}
			Copy-ADTFile -Path "$($adtSession.dirSupportFiles)\Icon.ico" -Destination "$envProgramData\AppWizIco\$appName.ico"

			#### Display AppWizard
			Write-ADTLogEntry -Message "Set registry entries for display in Application Wizard." -Severity 1 -source ${CmdletName} 
			
			Set-ADTRegistryKey -Key $ArpKey -Name 'Comments'        -Value "$appName"
			Set-ADTRegistryKey -Key $ArpKey -Name 'DisplayIcon'     -Value "$envProgramData\AppWizIco\$appName.ico"
			Set-ADTRegistryKey -Key $ArpKey -Name 'DisplayName'     -Value $ApplicationName
			Set-ADTRegistryKey -Key $ArpKey -Name 'DisplayVersion'  -Value $appVersion
			#Set-ADTRegistryKey -Key $ArpKey -Name 'InstallLocation' -Value "XXX"
			Set-ADTRegistryKey -Key $ArpKey -Name 'InstallSource'   -Value $($adtSession.scriptParentPath)
			Set-ADTRegistryKey -Key $ArpKey -Name 'Publisher'       -Value $appVendor
			Set-ADTRegistryKey -Key $ArpKey -Name 'UninstallString' -Value "Only SCCM Uninstall"
			#Set-ADTRegistryKey -Key $ArpKey -Name 'URLInfoAbout'    -Value "$configToolkitLogDir\$logName"
			#Set-ADTRegistryKey -Key $ArpKey -Name 'HelpLink'        -Value "$configToolkitLogDir\$logName"
			#Set-ADTRegistryKey -Key $ArpKey -Name 'URLUpdateInfo'   -Value "$configToolkitLogDir\$logName"
			Set-ADTRegistryKey -Key $ArpKey -Name 'NoModify'        -Value '1' -Typ 'DWord'
			Set-ADTRegistryKey -Key $ArpKey -Name 'NoRepair'        -Value '1' -Typ 'DWord'
			Set-ADTRegistryKey -Key $ArpKey -Name 'NoRemove'        -Value '1' -Typ 'DWord'
			
			Write-ADTLogEntry -Message "End set Application Wizard entry successfully." -Severity 1 -Source ${CmdletName} 	
		}
		Catch {
			Write-ADTLogEntry -Message "Failed to set the Application Wizard entry. `n$(Resolve-ADTErrorRecord -ErrorRecord $_) " -Severity 3 -Source ${CmdletName}
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Remove-ApplicationWizardEntry
Function Remove-ApplicationWizardEntry {
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
		[string]$ApplicationName = $VWG_appfriendlyName
	)
	
	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process {
		Try {
			Write-ADTLogEntry -Message "Begin remove Application Wizard entry." -Severity 1 -Source ${CmdletName} 
			
			if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64' ) {
				$ArpKey = @("HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$ApplicationName","HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ApplicationName")
			} else {
				$ArpKey = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ApplicationName"
	        }
					
			Write-ADTLogEntry -Message "Remove Application Wizard entry from Registry." -Severity 1 -Source ${CmdletName} 
			foreach ($key in $ArpKey) {
				Remove-ADTRegistryKey -Key $Key #-Recurse	
			}
			
            $envProgramData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonApplicationData)
            
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
			Write-ADTLogEntry -Message "Failed to set the Application Wizard entry. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Update-StartMenu
Function Update-StartMenu {
<#
.SYNOPSIS
	Cleans up the Start Menu by moving shortcuts and deleting unwanted shortcuts and folders.
.DESCRIPTION
    Moves shortcuts to the root or a folder of the Menu and deletes unwanted shortcuts and leftover folders.
.PARAMETER Folder
    The name of the Start Menu subfolder to work in
.PARAMETER GoodLinks
    An array of shortcut names to keep and move to the Menu root. 'All' will keep all links... not useful in some contexts.
.PARAMETER KeepFolder
    A Switch parameter that retains the folder but keeps only the listed links. Can't be used with $OtherFolder or $MoveLinks
.PARAMETER OtherFolder
    A switch that creates a folder (if necessary) into which the links will be placed. Links from anywhere in the Start Menu 
    can be used here. The script will look for them recursively. Only filenames unique in the hierarchy will work.
    Can't be used with $KeepFolder or $MoveLinks
.PARAMETER MoveLinks
    The default mode. A Switch to tell the script to Move the links rather than keeping or creating a folder for them.
    This switch is assumed and so does not have to be specified.
.EXAMPLE
    Update-StartMenu -Folder 'Greenshot' -GoodLinks 'Greenshot','Readme'
	Moves shortcuts 'Greenshot','Readme' from start menu folder 'Greenshot' to the root of the start menu
.EXAMPLE
    Update-StartMenu -Folder 'Greenshot' -GoodLinks 'All'
	Moves all shortcuts from start menu folder 'Greenshot' to the root of the start menu
.EXAMPLE
    Update-StartMenu -Folder 'Some Other App' -GoodLinks 'This App','App Website' -KeepFolder
	Removes all shortcuts except 'This App','App Website' from start menu folder 'Some Other App' 
.EXAMPLE
    Update-StartMenu -Folder '_Staff-Only' -Goodlinks 'One','Two','Three' -OtherFolder
	Moves shortcuts 'One','Two','Three' from anywhere in the start menu to folder 'Some Other App' (created if necessary)
.NOTES

.LINK
	http://www.volkswagen-group.com
#>
    [CmdletBinding(DefaultParametersetName='MoveLinks')]
    Param (
        [Parameter(Mandatory=$true,HelpMessage='Enter the name of a Start Menu subfolder.')]
        [ValidateNotNullorEmpty()]
        [string]$Folder,
        [Parameter(Mandatory=$true,HelpMessage='Enter a list of links to keep. "All" can be used to keep all links.')]
        [ValidateNotNullorEmpty()]
		[string[]]$GoodLinks,
        [Parameter(ParameterSetName='KeepFolder')]
        [switch]$KeepFolder,
        [Parameter(ParameterSetName='OtherFolder')]
        [switch]$OtherFolder,
        [Parameter(ParameterSetName='MoveLinks')]
        [switch]$MoveLinks
    )

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process {
		Try {
		    # Set up a couple of useful variables
            $envCommonStartMenuPrograms=[System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonPrograms)
		    $folderPath = "$envCommonStartMenuPrograms\$($Folder)"
		    
		    #### Using the KeepFolder Mode #### Keep certain files in an existing Folder and delete the rest.
			If ($KeepFolder) {
		        # Check to see if the folder exists. This doesn't make much sense if it doesn't
		        If (Test-Path -Path $folderPath -PathType Container) {
		            # See if 'All' is being used and it's the only thing in GoodLinks
		            If (($GoodLinks -contains 'All') -and ($GoodLinks.Count -eq 1)) {
		                Write-ADTLogEntry -Message 'Warning: Doing nothing. This combination of parameters leaves everything as-is!' -Severity 2 -Source ${CmdletName}
		            }
		            # If 'All' is not being used we can go ahead and remove anything not in GoodLinks
		            ElseIf ($GoodLinks -notcontains 'All') {
		                Write-ADTLogEntry -Message "Removing unwanted links from Start Menu folder [$($Folder)]" -Severity 1 -Source ${CmdletName}
		                # Get a full listing of the files in Folder
		                Get-ChildItem -Path $folderPath -File -Recurse | ForEach-Object {
		                    # If this file's name isn't in GoodLinks then remove it.
		                    If ($GoodLinks -notcontains $_.BaseName) {
		                        Remove-ADTFile -Path $_.FullName
		                    }
		                }
		            }
		            Else {
		                Write-ADTLogEntry -Message 'Error: It does not make sense to use [All] with anything else.' -Severity 3 -Source ${CmdletName}
		            }
		        }
		        Else {
		            Write-ADTLogEntry -Message "Error: Folder [$($Folder)] does not exist." -Severity 3 -Source ${CmdletName}
		        }
		    }
		    #### Using the OtherFolder Mode #### Move files into another folder from anywhere in the Start Menu hierarchy.
		    ElseIf ($OtherFolder) {
		        # Using 'All' with OtherFolder doesn't really make sense. We aren't going to move all the start menu files
		        If (($GoodLinks -contains 'All') -and ($GoodLinks.Count -eq 1)) {
		            Write-ADTLogEntry -Message 'Error: [All] cannot be used with [OtherFolder]. You need to specify lnk names.' -Severity 3 -Source ${CmdletName}
		        }
		        ElseIf ($GoodLinks -notcontains 'All') { # 'All' is not being used, so go ahead
		            New-ADTFolder -Path $folderPath 

		            # Now it's time to move all the goodlinks files into the folder
		            ForEach ($link in $GoodLinks) {
		                # Look recursively through the Start Menu for this filename and move it. Only names unique in the Start hierarchy will work.
		                $fileObj = Get-ChildItem -Path "$envCommonStartMenuPrograms" -Include "$($link).*" -File -Recurse
		                Write-ADTLogEntry -Message "Moving [$($fileObj.Name)] into folder [$($Folder)]" -Severity 1 -Source ${CmdletName}
		                Move-Item -Path $fileObj.FullName -Destination $folderPath
		            }
		        }
		        Else {
		            Write-ADTLogEntry -Message 'Error: It does not make sense to use [All] with anything else.' -Severity 3 -Source ${CmdletName}
		        }
		    }
		    #### Using the MoveFiles Mode #### Move files into the root of the Start Menu.
		    Else {
		        If (Test-Path -Path $folderPath -PathType Container) {
		            If (($GoodLinks -contains 'All') -and ($GoodLinks.Count -eq 1)) {
		                Write-ADTLogEntry -Message 'Moving all Links into main Start Menu folder.' -Severity 1 -Source ${CmdletName}
				        Get-ChildItem -Path $folderPath -File -Recurse | ForEach-Object {
					        Copy-ADTFile -Path $_.FullName -Destination $envCommonStartMenuPrograms
				        }
		                Remove-ADTFolder -Path $folderPath
			        }
			        ElseIf ($GoodLinks -notcontains 'All') {
				        ForEach ($link in $GoodLinks) {
		                    $filePath = (Get-ChildItem "$folderPath\$($link).*" -File -Recurse).FullName
					        Copy-ADTFile -Path $filePath -Destination $envCommonStartMenuPrograms
				        }
		                Remove-ADTFolder -Path $folderPath
			        }
		            Else {
		                Write-ADTLogEntry -Message 'Error: It does not make sense to use [All] with anything else.' -Severity 3 -Source ${CmdletName}
		            }
		        }
		        Else {
		            Write-ADTLogEntry -Message "Error: Folder [$($Folder)] does not exist. Cannot complete moving of links." -Severity 3 -Source ${CmdletName}
		        }
		    }
		}
		Catch {
			Write-ADTLogEntry -Message "Failed to Update StartMenu. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}		
#endregion

#region Function Set-EnvironmentVariable
Function Set-EnvironmentVariable {
<#
.SYNOPSIS
	Adds a new environment variable.
.DESCRIPTION
	Adds a new environment variable.
.PARAMETER EnvironmentVariable
	The new environment variable to add.
.PARAMETER EnvironmentValue
	The value for the environment variable to add.
.PARAMETER EnvironmentType
	The type for the environment variable to add, possible values Machine, User. Default is: Machine
.PARAMETER ExpandEnvironmentVariable
	Set the new environment variable with Expand variable REG_EXPAND_SZ (registry) value
.PARAMETER ContinueOnError
	Continue if an error is encountered. Default is: $true.
.EXAMPLE
	Set-EnvironmentVariable -EnvironmentVariable "MOZ_CRASHREPORTER_DISABLE" -EnvironmentValue "1"
	Set the new environment variable for default type Machine
.EXAMPLE
	Set-EnvironmentVariable -EnvironmentVariable "MOZ_CRASHREPORTER_DISABLE" -EnvironmentValue "1" -EnvironmentType "User"
	Set the new environment variable for type User
.EXAMPLE
	Set-EnvironmentVariable -EnvironmentVariable "Expanded" -EnvironmentValue "%ProgramFiles%\directory" -ExpandEnvironmentVariable
	Set the new environment variable with Expand variable REG_EXPAND_SZ (registry) value for default type Machine 
.NOTES
.LINK
	http://www.volkswagen-group.com
#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]$EnvironmentVariable,
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]$EnvironmentValue,
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[ValidateSet("Machine","User")]
		[string]$EnvironmentType = "Machine",
		[Parameter(Mandatory=$false)]
		[ValidateNotNullorEmpty()]
		[switch]$ExpandEnvironmentVariable = $false,
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[boolean]$ContinueOnError = $true
	)
	Begin {
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process {
		Try {
			
			If ($EnvironmentType -eq "Machine") {
				#Check environment variable different method if $ExpandEnvironmentVariable set to get the right REG_EXPAND_SZ values
				If ($ExpandEnvironmentVariable) {
					$checkcurrentEnvVar = Get-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name $EnvironmentValue -DoNotExpandEnvironmentNames
				} Else{
					$checkcurrentEnvVar = [Environment]::GetEnvironmentVariable($EnvironmentVariable, $EnvironmentType)
				}
				
				If (-not($checkcurrentEnvVar -eq $EnvironmentValue)){
					#Set environment variable different method if $ExpandEnvironmentVariable set to set the right REG_EXPAND_SZ values
					Write-ADTLogEntry -Message "Setting environment variable [$EnvironmentVariable]." -Severity 1 -source ${CmdletName}
					If ($ExpandEnvironmentVariable) {
						Set-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name $EnvironmentVariable -Value $EnvironmentValue -Type 'ExpandString' 
					} Else{
						[Environment]::SetEnvironmentVariable($EnvironmentVariable, $EnvironmentValue, $EnvironmentType)
					}
					#add to the current session
					Set-Item -force -path env:$EnvironmentVariable -value $EnvironmentValue -ErrorAction SilentlyContinue
					Write-ADTLogEntry -Message "Environment variable [$EnvironmentVariable] successfully set to [$EnvironmentValue]." -Severity 1 -Source ${CmdletName}
					#Refresh environment variables to prevent logoff or reboot to detect the change
					Update-ADTDesktop
					Update-ADTEnvironmentPsProvider
				} Else{
					Write-ADTLogEntry -Message "Environment variable [$EnvironmentVariable] already exist and containing the expected value [$EnvironmentValue]." -Severity 2 -source ${CmdletName}
				}
			} Elseif ($EnvironmentType -eq "User") {
			
				Invoke-ADTAllUsersRegistryAction -ScriptBlock {
					#Set environment variable different method if $ExpandEnvironmentVariable set to set the right REG_EXPAND_SZ values
					Write-ADTLogEntry -Message "Setting environment variable [$EnvironmentVariable] for User [$($UserProfile.NTAccount)]." -Severity 1 -source ${CmdletName}
					If ($ExpandEnvironmentVariable) {
						Set-ADTRegistryKey -Key 'HKCU:\Environment' -Name "$EnvironmentVariable" -Value $EnvironmentValue -Type 'ExpandString' -SID $_.SID
					} Else{
						Set-ADTRegistryKey -Key 'HKCU:\Environment' -Name "$EnvironmentVariable" -Value $EnvironmentValue -Type 'String' -SID $_.SID
					}
				}
				
				#add to the current session
				Set-Item -force -path env:$EnvironmentVariable -value $EnvironmentValue -ErrorAction SilentlyContinue
				Write-ADTLogEntry -Message "Environment variable [$EnvironmentVariable] successfully set to [$EnvironmentValue] for all users." -Severity 1 -Source ${CmdletName}
				#Refresh environment variables to prevent logoff or reboot to detect the change
				Update-ADTDesktop
				Update-ADTEnvironmentPsProvider
			}
		}
		Catch {
			Write-ADTLogEntry -Message "Failed to set environment variable [$EnvironmentVariable]. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Source ${CmdletName} -Severity 3
            Throw (New-ADTErrorRecord @naerParams)
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Remove-EnvironmentVariable
Function Remove-EnvironmentVariable {
<#
.SYNOPSIS
	Removes an environment variable.
.DESCRIPTION
	Removes an environment variable.
.PARAMETER EnvironmentVariable
	The variable to remove.
.PARAMETER EnvironmentType
	The type for the variable to remove, possible values Machine, User. Default is: Machine
.PARAMETER ContinueOnError
	Continue if an error is encountered. Default is: $true.
.EXAMPLE
	Remove-EnvironmentVariable -EnvironmentVariable "MOZ_CRASHREPORTER_DISABLE" 
	Remove environment variable for default type Machine
.EXAMPLE
	Remove-EnvironmentVariable -EnvironmentVariable "MOZ_CRASHREPORTER_DISABLE" -EnvironmentType "User" 
	Remove environment variable for type User
.NOTES
.LINK
	http://www.volkswagen-group.com
#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]$EnvironmentVariable,
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[ValidateSet("Machine","User")]
		[string]$EnvironmentType = "Machine",
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[boolean]$ContinueOnError = $true
	)
	Begin {
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process {
		Try {
			
			If ($EnvironmentType -eq "Machine") {
				#Check environment variable
				$checkcurrentEnvVar = [Environment]::GetEnvironmentVariable($EnvironmentVariable, $EnvironmentType)

				If (-not $checkcurrentEnvVar){
					Write-ADTLogEntry -Message "Environment variable [$EnvironmentVariable] not exist." -Severity 3 -source ${CmdletName}	
				} Else{
					Write-ADTLogEntry -Message "Removing environment variable [$EnvironmentVariable]." -Severity 1 -source ${CmdletName}
					[Environment]::SetEnvironmentVariable($EnvironmentVariable, $Null, $EnvironmentType)
					#remove from the current session
					Set-Item -force -path env:$EnvironmentVariable -value '' -ErrorAction SilentlyContinue
					Write-ADTLogEntry -Message "Environment variable [$EnvironmentVariable] removed successfully." -Severity 1 -Source ${CmdletName}
					#Refresh environment variables to prevent logoff or reboot to detect the change
					Update-ADTDesktop
					Update-ADTEnvironmentPsProvider
				}
			} Elseif ($EnvironmentType -eq "User") {
			
				Invoke-ADTAllUsersRegistryAction -ScriptBlock {
					#Remove environment variable for all users
					Write-ADTLogEntry -Message "Removing environment variable [$EnvironmentVariable] for User [$($UserProfile.NTAccount)]." -Severity 1 -source ${CmdletName}
					Remove-ADTRegistryKey -Key 'HKCU:\Environment' -Name "$EnvironmentVariable" -SID $_.SID
				}
								
				#remove from the current session
				Set-Item -force -path env:$EnvironmentVariable -value '' -ErrorAction SilentlyContinue
				Write-ADTLogEntry -Message "Environment variable [$EnvironmentVariable] removed successfully." -Severity 1 -Source ${CmdletName}
				#Refresh environment variables to prevent logoff or reboot to detect the change
				Update-ADTDesktop
				Update-ADTEnvironmentPsProvider		
			}
		}
		Catch {
			Write-ADTLogEntry -Message "Failed to remove environment variable [$EnvironmentVariable]. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Source ${CmdletName} -Severity 3
            Throw (New-ADTErrorRecord @naerParams)
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Set-PathEnvironmentVariable
function Set-PathEnvironmentVariable {
<#
.SYNOPSIS
       Adds a new item to the path environment variable.
.DESCRIPTION
       Adds a new item to the path environment variable.
.PARAMETER Path
       The new directory location to add at the end of the path. Can be an variable itself.
.PARAMETER InsertAsFirstItem
       Adds the new item at first item instead of last one
.EXAMPLE
       Set-PathEnvironmentVariable -Path 'C:\MyPath\MyChildPath'
       Adds the string 'C:\MyPath\MyChildPath' to the path
.EXAMPLE
       Set-PathEnvironmentVariable -Path "%bin%"
       Adds the string "%bin%" to the path, when using it is not expanded.
.EXAMPLE
       Set-PathEnvironmentVariable  Path "%AppData%\npm" -User
       Adds the string "%AppData%\npm" to the path, when using it is not expanded.

.EXAMPLE
       Set-PathEnvironmentVariable -Path "%bin%" -InsertAsFirstItem
       Adds the string "%bin%" to the path, when using it is not expanded and set at first item instead of last item.
.NOTES
.LINK
       http://www.volkswagen-group.com

#>
    [CmdletBinding()] 
     param( 
      [Parameter(Mandatory=$true)]
      [ValidateNotNullorEmpty()]
      [string]$Path,
      [Parameter(Mandatory=$false)]
      [ValidateNotNullorEmpty()]
      [switch]$InsertAsFirstItem = $false,
      [Parameter(Mandatory=$false)]
      [Switch]$User,
      [Parameter(Mandatory=$false)]
      [ValidateNotNullOrEmpty()]
      [boolean]$ContinueOnError = $true
     )
    Begin {
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
       }
       Process {
        Try {

        If($user)
        {  
            Invoke-ADTAllUsersRegistryAction -ScriptBlock {
            $Environment = Convert-ADTRegistryPath -Key "HKEY_CURRENT_USER\Environment" -SID $_.SID
            $PathValues = Get-ADTRegistryKey -Key "$Environment" -Name "Path" -DoNotExpandEnvironmentNames
            Write-ADTLogEntry -Message "Consolidated User environment Pathvariable: [$PathValues]" -Severity 1 -Source ${CmdletName}
            $Path = $Path.Trim()
            $EnvPathSplit = $PathValues.split(";") | Where-Object{$_}   
            
                If ($EnvPathSplit -contains $Path)
                {
                   Write-ADTLogEntry -Message "User environment Pathvariable [$Path] already exist " -Severity 2 -Source ${CmdletName}
                }
                else
                {
                   Write-ADTLogEntry -Message "New User Environment Pathvariable: [$Path]" -Severity 1 -Source ${CmdletName}
           
                   $CurEnvPathSplit = $EnvPathSplit -join ';'
                   $ADDNewEnvPath = $CurEnvPathSplit + ";" + $Path 
                   $ADDNewEnvPath = $ADDNewEnvPath -replace ";;",";"

                   Set-ADTRegistryKey -Key "$Environment" -Name "Path" -Value "$ADDNewEnvPath" 
                   $ADDNewEnvPath = $null
                }        
           }
        }
        else
        {
            # Read the current path variable
            $CurEnvPath = Get-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name "Path" -DoNotExpandEnvironmentNames
            Write-ADTLogEntry -Message "Current system environment Pathvariable: [$CurEnvPath]" -Severity 1 -Source ${CmdletName}
            # Read each individual path into an array and remove empty elements from the array
            $CurEnvPathSplit = $CurEnvPath.split(";") | where {$_}         
                    
                    Write-ADTLogEntry -Message "Consolidated system environment Pathvariable: [$CurEnvPathSplit]" -Severity 1 -Source ${CmdletName}
                    # Trim new location path
                    $Path = $Path.Trim()
                    # check whether the new location is already in the path
                    If ($CurEnvPathSplit -contains $Path)
                    {
                        Write-ADTLogEntry -Message "Current system environment Pathvariable already has item: [$Path]" -Severity 2 -Source ${CmdletName}
                    } 
                    else 
                    {
                        Write-ADTLogEntry -Message "Expand system environment Pathvariable with: [$Path]" -Severity 1 -Source ${CmdletName}
                        # Make a valid string from the array
                        $CurEnvPathSplit = $CurEnvPathSplit -join ';'
                          
                        # build the new path dependent if $InsertAsFirstItem set than at first item instead of last item and make sure we don't have double semicolons
                          if ($InsertAsFirstItem) {
                                 $NewEnvPath = $Path + ";" + $CurEnvPathSplit  
                                 $NewEnvPath = $NewEnvPath -replace ";;",";"    
                          } else {
                                 $NewEnvPath = $CurEnvPathSplit + ";" + $Path
                                 $NewEnvPath = $NewEnvPath -replace ";;",";"
                          }
                          
                          $CurrentRegistryKey     = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
                          $CurrentRegistryKeyType = $(Get-Item -LiteralPath "Registry::$CurrentRegistryKey" -ErrorAction 'Stop').GetValueKind("Path")     
                          if ($CurrentRegistryKeyType -ne "ExpandString") {
                                 #If Path variable has not default type ExpandString remove variable before set to new value, because Set-RegistryKey function cant change the type of an existing Registrykey
                                 Write-ADTLogEntry -Message "Current system environment Pathvariable has wrong type [$CurrentRegistryKeyType] remove variable before set to new value with default type [ExpandString]." -Severity 2 -Source ${CmdletName}
                                 Remove-ADTRegistryKey -Key $CurrentRegistryKey -Name "Path"
                          }

                          Write-ADTLogEntry -Message "New system environment Pathvariable: [$NewEnvPath]" -Severity 1 -Source ${CmdletName}   
                          #Set-ADTRegistryKey -Key  'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name 'Path' -Value $NewEnvPath -Type 'ExpandString' 
                          Set-EnvironmentVariable -EnvironmentVariable "Path" -EnvironmentValue $NewEnvPath -ExpandEnvironmentVariable
                    }
        }
      }
      Catch {
                Write-ADTLogEntry -Message "Failed to change system environment Pathvariable. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
                Throw (New-ADTErrorRecord @naerParams)
            }
       }
       End {
		        Complete-ADTFunction -Cmdlet $PSCmdlet
       }
}
#endregion

#region Function Remove-PathEnvironmentVariable
function Remove-PathEnvironmentVariable {
<#
.SYNOPSIS
       Remove a directory from the path environment variable.
.DESCRIPTION
       Remove a directory from the path environment variable.
.PARAMETER Path
       The directory location to remove from the path. Can be an variable itself.
.EXAMPLE
       Remove-PathEnvironmentVariable -Path 'C:\MyPath\MyChildPath'
       Removes the string 'C:\MyPath\MyChildPath' from the path
.EXAMPLE
       Remove-PathEnvironmentVariable  Path "%AppData%\npm" -User
       Removes the string "%AppData%\npm" from the path, when using it is not expanded.
.EXAMPLE
       Remove-PathEnvironmentVariable -Path "%bin%"
       Removes the string "%bin%" from the path.
.NOTES
.LINK
       http://www.volkswagen-group.com

#>
    [CmdletBinding()] 
     param( 
      [Parameter(Mandatory=$true)]
      [ValidateNotNullorEmpty()]
      [string]$Path,
      [Parameter(Mandatory=$false)]
      [Switch]$User,
         [Parameter(Mandatory=$false)]
         [ValidateNotNullOrEmpty()]
         [boolean]$ContinueOnError = $true
     )
    Begin {
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
       }
       Process {
        Try {
        
        If($user)
        {  
        Invoke-ADTAllUsersRegistryAction -ScriptBlock {

        $Environment = Convert-ADTRegistryPath -Key "HKEY_CURRENT_USER\Environment" -SID $_.SID
        $PathValues = Get-ADTRegistryKey -Key "$Environment" -Name "Path" -DoNotExpandEnvironmentNames
     
        $EnvPathSplit = $PathValues.split(";") | Where-Object{$_}
        $Path = $Path.Trim()      
        If ($EnvPathSplit -Notcontains $Path)
            {
                Write-ADTLogEntry -Message "Current system environment Pathvariable has no valid item to remove: [$Path]" -Severity 2 -Source ${CmdletName}
            }
            else
            {        
                Write-ADTLogEntry -Message "Remove [$Path] from User environment Pathvariable." -Severity 1 -Source ${CmdletName}
                    # build the new path, make sure we don't have double semicolons
                    $NewEnvPath = $EnvPathSplit | Where-Object { $_ -ne $Path }
                    # Make a valid string from the array
                    $NewEnvPath = $NewEnvPath -join ';'
                    $NewEnvPath = $NewEnvPath -replace ";;",";"
                 
                Set-ADTRegistryKey -Key "$Environment" -Name "Path" -Value "$NewEnvPath" 
                $NewEnvPath = $null
            }       
         }    
        }
        else
        {
                # Read the current path variable
                $CurEnvPath = Get-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name "Path" -DoNotExpandEnvironmentNames
                Write-ADTLogEntry -Message "Current system environment Pathvariable: [$CurEnvPath]" -Severity 1 -Source ${CmdletName}
                # Read each individual path into an array and remove empty elements from the array
                $CurEnvPathSplit = $CurEnvPath.split(";") | where {$_}              
                Write-ADTLogEntry -Message "Consolidated system environment Pathvariable: [$CurEnvPathSplit]" -Severity 1 -Source ${CmdletName}
                # Trim new location path
                        $Path = $Path.Trim()
                        If ($CurEnvPathSplit -notcontains $Path) {
                              Write-ADTLogEntry -Message "Current system environment Pathvariable has no valid item to remove: [$Path]" -Severity 2 -Source ${CmdletName}
                        } else {
                       Write-ADTLogEntry -Message "Remove [$Path] from system environment Pathvariable." -Severity 1 -Source ${CmdletName}
                       # build the new path, make sure we don't have double semicolons
                       $NewEnvPath = $CurEnvPathSplit | Where-Object { $_ -ne $Path }
                       # Make a valid string from the array
                       $NewEnvPath = $NewEnvPath -join ';'
                              $NewEnvPath = $NewEnvPath -replace ";;",";"
                          
                              Write-ADTLogEntry -Message "New system environment Pathvariable: [$NewEnvPath]" -Severity 1 -Source ${CmdletName}
                              Set-EnvironmentVariable -EnvironmentVariable "Path" -EnvironmentValue $NewEnvPath -ExpandEnvironmentVariable
                        }
                 }
        }
             Catch {
                    Write-ADTLogEntry -Message "Failed to change system environment Pathvariable. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
                    Throw (New-ADTErrorRecord @naerParams)
             }
       }
       End {
             Complete-ADTFunction -Cmdlet $PSCmdlet
       }
}
#endregion

#region Function Expand-ZipFile
function Expand-ZipFile{
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
	Expand-ZipFile -Path "$dirfiles\ZipFile.zip" -Destination "$envProgramFiles\Destination" -Override
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
			Write-ADTLogEntry -Message "Failed to extract the requested file. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
			If (-not $ContinueOnError) {
		        	Throw "Failed to extract the requested file: $($_.Exception.Message)"
			}
		}
		<#finally{
			#if($objArchive){
				$objArchive.Dispose()
			#}
		}#>
	}
	end{
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Add-EntryToZipFile
function Add-EntryToZipFile{
<#
.SYNOPSIS
	Adds an Entry to Zip-File
.DESCRIPTION
	Adds an Entry to Zip-File
.PARAMETER SourceFile
	Path of a single File to Add
.PARAMETER ZipFile
	Path of Zip-File
.PARAMETER Entryname
	Optional Entryname with Subfolders
.PARAMETER ContinueOnError
	Continue if an error is encountered. Default is: $false.
.PARAMETER Override
	Overrides existent Content
.EXAMPLE
	Add-EntryToZipFile -SourceFile "$envProgramData\VWG\Logs\1.log" -ZipFile "$envProgramData\VWG\Logs\Backup.zip" -Entryname "Backup\$date\1.log" -Override
.LINK
	http://www.volkswagen-group.com
#>
	param (
		[parameter(Mandatory=$true,Position=0)]
		[ValidateNotNullorEmpty()]
		[string]$SourceFile,
		[parameter(Mandatory=$true,Position=1)]
		[ValidateNotNullorEmpty()]
		[string]$ZipFile,
		[parameter(Mandatory=$false,Position=2)]
		[ValidateNotNullorEmpty()]
		[string]$EntryName,
		[Parameter(Mandatory=$false,Position=3)]
		[ValidateSet('Fastest','NoCompression','Optimal')]
		[System.IO.Compression.CompressionLevel]$Compression = 'Fastest',
		[Parameter(Mandatory=$false)]
		[boolean]$ContinueOnError = $false,
		[Parameter(Mandatory=$false)]
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
			$objArchive = [System.IO.Compression.ZipFile]::Open("$($ZipFile)", 'Update')
			$item = Get-Item -Path $SourceFile
			if($EntryName){
				$splitEntryPath = (Split-Path $EntryName).split('\')
				$tmpPath = ''
				foreach($entrySplitter in $splitEntryPath){
					$tmpPath += $entrySplitter + '/'
					if(!($objArchive.GetEntry("$tmpPath"))){
						#Create Subfolders in Zip-File step by step
						$objArchive.CreateEntry("$tmpPath")
					}
				}
				$entryFile = $EntryName.Replace('\','/')
			}
			else{
				$entryFile = $item.Name
			}
			Write-ADTLogEntry -Message "Add [$($Source)] to [$($ZipFile)] with compression setting [$Compression] and BaseDir-Setting [$UseBaseDir]." -Source ${CmdletName}
			if($objArchive.getEntry($entryFile)){
				if(($objArchive.getEntry($entryFile).GetHashCode() -ne $item.GetHashCode()) -and $Override){
					$objArchive.getEntry($entryFile).Delete()
				}
				[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($objArchive,$($item).FullName,$entryFile,$Compression)
			}
			else{
				[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($objArchive,$($item).FullName,$entryFile,$Compression)
			}
		}
		Catch {
			Write-ADTLogEntry -Message "Failed to Compress the requested file. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
			If (!$ContinueOnError) {
		        throw "Failed to Compress the requested file: $($_.Exception.Message)"
			}
		}
		<#finally{
			#if($objArchive){
				$objArchive.Dispose()
			#}
		}#>
	}
	end{
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Expand-SingleEntry
function Expand-SingleEntry{
<#
.SYNOPSIS
	Extract an Entry from a Zip-File to Destination
.DESCRIPTION
	Extract an Entry from a Zip-File to Destination
.PARAMETER ZipFile
	Path of Zip-File
.PARAMETER Entry
	Entry to Expand
.PARAMETER Destination
	Destinationfolder to Extract
.PARAMETER ContinueOnError
	Continue if an error is encountered. Default is: $false.
.PARAMETER Override
	Overrides existent Content
.EXAMPLE
	Expand-SingleEntry -ZipFile "$dirfiles\ZipFile.zip" -Entry "basedir\file.file" -Destination "$envProgramFiles\Destination" -Override
.LINK
	http://www.volkswagen-group.com
#>
	param (
		[parameter(Mandatory=$true,Position=0)]
		[ValidateNotNullorEmpty()]
		[string]$ZipFile,
		[Parameter(Mandatory=$true,Position=1)]
		[ValidateNotNullorEmpty()]
		[String]$Entry,
		[parameter(Mandatory=$true,Position=2)]
		[ValidateNotNullorEmpty()]
		[string]$Destination,
		[Parameter(Mandatory=$false,Position=3)]
		[ValidateNotNullorEmpty()]
		[boolean]$ContinueOnError = $false,
		[Parameter(Mandatory=$false,Position=4)]
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
			Write-ADTLogEntry -Message "Extracting Entry [$($Entry)] from Zip-File [$($Path)] to [$($Destination)]." -Source ${CmdletName}
			$objArchive = [System.IO.Compression.ZipFile]::Open("$($ZipFile)", 'Read')
			$newEntry = $Entry.Replace('\','/')
			$tmpPath = (Join-Path $Destination ($objArchive.getEntry($newEntry).Fullname)).Replace(($objArchive.getEntry($newEntry).Name),'')
			If (-not(Test-Path -Path "$($tmpPath)")) {
				New-ADTFolder -Path "$($tmpPath)"
			}
			[System.IO.Compression.ZipFileExtensions]::ExtractToFile($objArchive.getEntry($newEntry),(Join-Path $Destination $objArchive.getEntry($newEntry).FullName),$Override)
		}
		Catch {
			Write-ADTLogEntry -Message "Failed to extract the requested file. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
			If (-not $ContinueOnError) {
					throw "Failed to extract the requested file: $($_.Exception.Message)"
			}
		}
		<#finally{
			#if($objArchive){
				$objArchive.Dispose()
			#}
		}#>
	}
	end{
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Remove-EntryFromZipFile
function Remove-EntryFromZipFile{
<#
.SYNOPSIS
	Removes one or more Entrys from ZipFile
.DESCRIPTION
	Removes an Entry from ZipFile
.PARAMETER ZipFile
	Path of Zip-File
.PARAMETER Entry
	Entry to Remove from ZipFile
.PARAMETER ContinueOnError
	Continue if an error is encountered. Default is: $false.
.EXAMPLE
	Remove-EntryFromZipFile -ZipFile "$dirfiles\ZipFile.zip" -Entry "Basedir\file.file","Basedir\log.log"
.EXAMPLE
	Remove-EntryFromZipFile -ZipFile "$dirfiles\ZipFile.zip" -Entry "Basedir\file.file","log.log" -All
.LINK
	http://www.volkswagen-group.com
#>
	param (
		[parameter(Mandatory=$true,Position=0)]
		[ValidateNotNullorEmpty()]
		[string]$ZipFile,
		[parameter(Mandatory=$true,Position=1)]
		[ValidateNotNullorEmpty()]
		[string[]]$Entry,
		[Parameter(Mandatory=$false,Position=2)]
		[ValidateNotNullorEmpty()]
		[switch]$All = $false,
		[ValidateNotNullorEmpty()]
		[boolean]$ContinueOnError = $false
	)
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
		Add-Type -AssemblyName System.IO.Compression.FileSystem
		Add-Type -AssemblyName  System.IO.Compression
	}
	process{
		Try {
			If ($All){
				$objArchive = [System.IO.Compression.ZipFile]::Open("$($ZipFile)", 'Update')
				foreach($entryToRemove in ($Entry -split ',')){
					$entryToRemove = Split-Path $entryToRemove -leaf
					Write-ADTLogEntry -Message "Remove Entrys [$($entryToRemove)] From [$($ZipFile)]." -Source ${CmdletName}
					($objArchive.Entries | Where-Object { $entryToRemove -contains $_.Name }) | foreach { $_.Delete() }
				}
			}
			Else{
				$objArchive = [System.IO.Compression.ZipFile]::Open("$($ZipFile)", 'Update')
				foreach($entryToRemove in ($Entry -split ',')){
					Write-ADTLogEntry -Message "Remove Entry [$($Entry)] From [$($ZipFile)]." -Source ${CmdletName}
					$entryToRemove2 = $entryToRemove.replace('\','/')
					if($objArchive.getEntry($entryToRemove)){
						$objArchive.getEntry($entryToRemove).Delete()
					}
					Elseif($objArchive.getEntry($entryToRemove2)){
						$objArchive.getEntry($entryToRemove2).Delete()
					}
					else{
						Write-ADTLogEntry -Message "Can't Remove Entry [$($entryToRemove)] From [$($ZipFile)] because it does not exist." -Severity 2 -Source ${CmdletName}
					}
				}
			}
		}
		Catch {
			Write-ADTLogEntry -Message "Failed to Remove the requested Entry: $($_.Exception.Message)" -Severity 3 -Source ${CmdletName}
			If (-not $ContinueOnError) {
		        	Throw "Failed to Remove the requested Entry: $($_.Exception.Message)"
			}
		}
		<#finally{
			#if($objArchive){
				$objArchive.Dispose()
			#}
		}#>
	}
	end{
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Compress-ZipFile
function Compress-ZipFile{
<#
.SYNOPSIS
	Compress Files or Folders to Zip-Files
.DESCRIPTION
	Compress Files or Folders to Zip-Files
.PARAMETER Source
	Source-File or Source-Folder
.PARAMETER ZipFile
	Destination of the ZipFile
.PARAMETER Compression
	Optional 'Fastest','NoCompression','Optimal'
	Standard = Fastest
.PARAMETER ContinueOnError
	Continue if an error is encountered. Default is: $false.
.PARAMETER UseBaseDir
	When Compress a File or Folder it takes the BaseDir/ParentDir to the ZipFile
	Standard = $false
.EXAMPLE
	Compress-ZipFile -Source "C:\ProgramData\FolderToZip" -Destination "C:\Data\ZipFile.zip"
.EXAMPLE
	Compress-ZipFile -Source "C:\ProgramData\FolderToZip" -Destination "C:\Data\ZipFile.zip" -Compression 'Optimal' -UseBaseDir
.LINK
	http://www.volkswagen-group.com
#>
	param (
		[parameter(Mandatory=$true,Position=0)]
		[ValidateNotNullorEmpty()]
		[string]$Source,
		[parameter(Mandatory=$true,Position=1)]
		[ValidateNotNullorEmpty()]
		[ValidateScript({if(($_.Substring($_.Length - 3)) -eq "zip"){$true}else {$false}})]
		[string]$ZipFile,
		[Parameter(Mandatory=$false,Position=2)]
		[ValidateSet('Fastest','NoCompression','Optimal')]
		[System.IO.Compression.CompressionLevel]$Compression = 'Fastest',
		[Parameter(Mandatory=$false)]
		[boolean]$ContinueOnError = $false,
		[Parameter(Mandatory=$false)]
		[switch]$UseBaseDir = $false,
		[Parameter(Mandatory=$false)]
		[switch]$UpdateZipFile = $false
	)
	begin{
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
		Add-Type -AssemblyName System.IO.Compression.FileSystem
		Add-Type -AssemblyName  System.IO.Compression
	}
	process{
		Try {
			If(!$UpdateZipFile) {
				if(Test-Path -Path $ZipFile){
					Remove-item $ZipFile -force -ErrorAction Stop
				}
				Write-ADTLogEntry -Message "Compressing [$($Source)] to new [$($ZipFile)] with compression setting [$Compression] and BaseDir-Setting [$UseBaseDir]." -Source ${CmdletName}
				If (-not(Test-path -path (Split-Path -Path "$($ZipFile)"))) {
					New-ADTFolder -Path (Split-Path -Path "$($ZipFile)")
				}
				if(Test-Path -Path $Source -PathType Leaf){
					$item = Get-Item -Path $Source
					$cTime = Get-Date -Format yyyyMMddHHmmss
					New-Item -Path $env:SystemDrive\temp_$(${CmdletName})$($cTime) -ItemType Directory
					[System.IO.Compression.ZipFile]::CreateFromDirectory("$env:SystemDrive\temp_$(${CmdletName})$($cTime)", "$($ZipFile)", $Compression, $false)
					Remove-Item -Path $env:SystemDrive\temp_$(${CmdletName})$($cTime) -Force -Recurse
					$objArchive = [System.IO.Compression.ZipFile]::Open("$($ZipFile)", 'Update')
					if($UseBaseDir){
						$EntryName = (Join-Path $item.get_Directory().Name $item.Name).Replace('\','/')
						$objArchive.CreateEntry(($item.get_Directory().Name) + '/')
					}
					else{
						$EntryName = $item.Name
					}
					[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($objArchive,$Source,$EntryName,$Compression)
					$objArchive.Dispose()
				}
				else{
					[System.IO.Compression.ZipFile]::CreateFromDirectory("$($Source)", "$($ZipFile)", $Compression, $UseBaseDir)
				}
			}
			elseif($UpdateZipFile){
				$objArchive = [System.IO.Compression.ZipFile]::Open("$($ZipFile)", 'Update')
				if(Test-Path -Path $Source -PathType Container){
					$sourceList = Get-ChildItem -Path $Source -File -Recurse
					if($UseBaseDir){
						$splitDir = Split-Path -Path $Source -Parent
					}
					else{
						$splitDir = $Source
					}
					Write-ADTLogEntry -Message "Add [$($Source)] to [$($ZipFile)] with compression setting [$Compression] and BaseDir-Setting [$UseBaseDir]." -Source ${CmdletName}
					foreach($item in $sourceList){
						$fileFullPath = Split-Path -Path $item.Fullname
						$entryFile = ($item.Fullname).Replace("$splitDir\", "")
						$splitEntryPath = (split-path $entryFile).split('\')
						$entryFile = $entryFile.Replace('\','/')
						$entryFullPath = ''
						foreach($pathSplitter in $splitEntryPath){
							$entryFullPath += $pathSplitter + '/'
							if(!($objArchive.GetEntry($entryFullPath))){
								$objArchive.CreateEntry("$entryFullPath")
							}
						}
						if($objArchive.getEntry($entryFile)){
							if($objArchive.getEntry($entryFile).GetHashCode() -ne $item.GetHashCode()){
								$objArchive.getEntry($entryFile).Delete()
							}
						}
						[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($objArchive,$($item).FullName,$entryFile,$Compression)
					}
				}
				elseif(Test-Path -Path $Source -PathType Leaf){
					$item = Get-Item -Path $Source
					if($UseBaseDir){
						$entryFile = Join-Path -Path $item.get_Directory().Name $item.Name
						$entryFile = $entryFile.Replace('\','/')
						$objArchive.CreateEntry(($item.get_Directory().Name) + '/')
					}
					else{
						$entryFile = $item.Name
					}
					Write-ADTLogEntry -Message "Add [$($Source)] to [$($ZipFile)] with compression setting [$Compression] and BaseDir-Setting [$UseBaseDir]." -Source ${CmdletName}
					if($objArchive.getEntry($entryFile)){
						if($objArchive.getEntry($entryFile).GetHashCode() -ne $item.GetHashCode()){
							$objArchive.getEntry($entryFile).Delete()
						}
					}
					[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($objArchive,$($item).FullName,$entryFile,$Compression)
				}
			}
		}
		Catch {
			Write-ADTLogEntry -Message "Failed to Compress the requested file. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
			If (!$ContinueOnError) {
		        throw "Failed to Compress the requested file: $($_.Exception.Message)"
			}
		}
		<#finally{
			#if($objArchive){
				$objArchive.Dispose()
			#}
		}#>
	}
	end{
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Get-SCCMSiteCode
function Get-SCCMSiteCode{
<#
.SYNOPSIS
    Returns the Site Code of a SCCM Client as a String   
.DESCRIPTION
    Queries a given computer using WMI and returns its site code for System Center Configuration Manager
.PARAMETER MachineName
    The Computername of the machine that you want to query for it's SCCM Site Code. Default is: $envComputerName
.PARAMETER ContinueOnError
    Continue if an error is encountered. Default is: $true.
.EXAMPLE
    $SCCMSiteCode = Get-SCCMSiteCode
    Get's the site code of the computer
.LINK
    http://www.volkswagen-group.com
#>
    
    param (
        [parameter(Mandatory=$false,Position=0)]
        [ValidateNotNullorEmpty()]
        [boolean]$ContinueOnError = $true
    )

    begin{
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }
    process{
        Try {
            Write-ADTLogEntry -Message "Trying to get current client SCCM site." -Source ${CmdletName}
            [string]$SCCMSiteCode = (Get-WmiObject -ComputerName $envComputerName -Namespace "root\CCM" -Class "sms_authority" -ErrorAction "Stop").Name.TrimStart("SMS:")
            Write-ADTLogEntry -Message "Client is currently assigned to [$SCCMSiteCode] SCCM site." -Source ${CmdletName}
            return $SCCMSiteCode
        }
        Catch {
            Write-ADTLogEntry -Message "Failed to determine SCCM SiteCode. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Source ${CmdletName} -Severity 3
            If (-not $ContinueOnError) {
                Throw "Failed to determine SCCM SiteCode. `n[$($_.Exception.Message)]"
            }
        }
    }
    end{
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}
#endregion

#region Function Get-WMIInstance
Function Get-WMIInstance {
<#
.SYNOPSIS
	A brief description of the Get-WMIInstance function.
.DESCRIPTION
	A detailed description of the Get-WMIInstance function.
.PARAMETER  Namespace
	A description of the Namespace parameter.
.PARAMETER  ClassName
	A description of the ClassName parameter.
.PARAMETER  Query
	A description of the Query parameter.
.EXAMPLE
	Get-WMIInstance -Namespace 'Value1' -ClassName 'Value2' -Query 'WMIQuery'
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true,ValueFromPipeline = $true,ValueFromPipelineByPropertyName = $true,Position = 0)]
		[System.String]$Namespace,
		[Parameter(ValueFromPipeline = $true,ValueFromPipelineByPropertyName = $true,Position = 1)]
		[System.String]$ClassName,
		[Parameter(ValueFromPipeline = $true,ValueFromPipelineByPropertyName = $true,Position = 2)]
		[System.String]$Query
	)
	Begin {
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process	{
		$myQuery = "SELECT * FROM " + $ClassName + " WHERE " + $Query
		$myInstance = Get-WmiObject -Namespace $Namespace -Query $myQuery -ErrorAction 'SilentlyContinue'
		if (-not ($?))
		{
			Write-Warning "WMI Instance Does Not Exist."
			return $false | Out-Null
		}
		return ($myInstance)
	} 
	End	{
        Complete-ADTFunction -Cmdlet $PSCmdlet
        }
}
#endregion

#region Function Get-WMINamespace
Function Get-WMINamespace {
<#
.SYNOPSIS
	Returns a WMI namespace object
.DESCRIPTION
	This function returns an object containing the Namespace requested. If the WMI namespace does not exist, the function returns $false.
.PARAMETER  Namespace
	Mandatory. The parameter is a string value. It's form is <WMI Namespace>\<WMI Class>
.EXAMPLE
	Get-WMINamespace -Namespace 'root\cimv2'
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true)]
		[System.String]$Namespace
	)
	Begin {
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process	{
		try {
			$NamespaceSplit = $Namespace.Split("\")
			$NamespaceName = $NamespaceSplit[$NamespaceSplit.Count - 1]
			$NamespaceRoot = $Namespace -replace "\\$NamespaceName", ""
			$WMINamespace = Get-WmiObject -Namespace $NamespaceRoot -Class "__Namespace" | Where-Object { $_.Name -eq $NamespaceName }
			if (-not ($WMINamespace))
			{
				Write-ADTLogEntry -Message "WMI Namespace ($Namespace) does not exist." -Severity 2 -source ${CmdletName}
				return $false
			}
			Write-ADTLogEntry -Message "WMI Namespace ($Namespace) found." -Severity 1 -source ${CmdletName}
			return $WMINamespace
		}
		catch {
			Write-ADTLogEntry -Message "Error getting namespace." -Severity 3 -source ${CmdletName}
		}
	}
	End{
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function New-WMINamespace
Function New-WMINamespace{
<#
.SYNOPSIS
	Creates a new WMI namespace.
.DESCRIPTION
	This function creates a new WMI namespace if it does not exist
	It returns the WMI namespace object using Get-WMINamespace.
.PARAMETER  Namespace
	Mandatory. The name of the new namespace to create.
.PARAMETER  Rootname
	Mandatory. The name of the root to create the namespace in.
.EXAMPLE
	New-WMINamespace -Namespace 'VWG' -Rootname 'ROOT'
.NOTES
	This is an internal script function and should typically not be called directly.	
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 0)]
		[System.String]$Namespace,
				[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 1)]
		[System.String]$Rootname
	)
	Begin {
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process	{
		try {
			if (Get-WmiNamespace -Namespace $($Rootname,$Namespace -join "\") -ErrorAction 'SilentlyContinue')
			{
				Write-ADTLogEntry -Message "The WMI namespace already exists." -Severity 2 -source ${CmdletName}
			} else {
				Write-ADTLogEntry -Message "Creating new WMI namespace $Rootname/$Namespace" -Severity 1 -source ${CmdletName}
				$FullName = $($Rootname) + ":__namespace" 
				$WMINamespace = [wmiclass]$FullName
				$newNamespace = $WMINamespace.CreateInstance()
				$newNamespace.Name = $Namespace
				$newNamespace.Put() | Out-Null
			}
			return (Get-WmiNamespace -Namespace $($Rootname,$Namespace -join "\") -ErrorAction 'SilentlyContinue')
		}
		catch {
			Write-ADTLogEntry -Message "Error creating new WMI namespace." -Severity 3 -source ${CmdletName}
		}
	}
	End	{
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Get-WMIClass
Function Get-WMIClass{
<#
.SYNOPSIS
	Returns a WMI class object.
.DESCRIPTION
	This function returns an object containing the WMI class requested.
.PARAMETER  Namespace
	Mandatory. The namespace where the class should exist.
.PARAMETER  ClassName
	Mandatory. The name of the class to return.
.EXAMPLE
	Get-WMIClass -Namespace 'Value1' -ClassName 'Value2'
.NOTES
	This is an internal script function and should typically not be called directly.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 0)]
		[System.String]$Namespace,
		[Parameter(ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 1)]
		[System.String]$ClassName
	)
	Begin {
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process	{
		try {
			Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction 'SilentlyContinue' | Out-Null
			if (-not ($?))
			{
				Write-ADTLogEntry -Message "WMI class $ClassName does not exist." -Severity 1 -source ${CmdletName}
				return $false | Out-Null
			}
			Write-ADTLogEntry -Message "WMI class $ClassName found. Returning $($Namespace):$($ClassName)." -Severity 1 -source ${CmdletName}
			return ([WMICLASS]"$Namespace`:$ClassName")
		}
		catch {
			Write-ADTLogEntry -Message "Error getting WMI class. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -source ${CmdletName}
			return $false | Out-Null
		}
	}
	End	{
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function New-WMIClass
Function New-WMIClass{
<#
.SYNOPSIS
	Creates a new WMI class.
.DESCRIPTION
	This function creates a new WMI class and returns the WMI class object using Get-WMIClass. If the requested WMI class still exists, the function returns $false.
.PARAMETER  Name
	Mandatory. The name of the new class to create.
.PARAMETER  Namespace
	Mandatory. The namespace where to create the new class.
.EXAMPLE
	PS C:\> New-WMIClass -Name 'Value1' -Namespace 'Value2'
.NOTES
	This is an internal script function and should typically not be called directly.	
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 0)]
		[System.String]$Namespace,
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 1)]
		[System.String]$ClassName
	)
	Begin {
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process	{
		try {
			if (Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction 'SilentlyContinue')
			{
				Write-ADTLogEntry -Message "The WMI Class already exists." -Severity 1 -source ${CmdletName}
				return $false
			}
			
			Write-ADTLogEntry -Message "Creating New WMI Class $ClassName at $Namespace" -Severity 1 -source ${CmdletName}
			$newClass = New-Object System.Management.ManagementClass($Namespace, [String]::Empty, $null)
			$newClass["__CLASS"] = $ClassName.ToString()
			$newClass.Put() | Out-Null
			
			return (Get-WMIClass -ClassName $ClassName -Namespace $Namespace)
				
		}
		catch {
			Write-ADTLogEntry -Message "Error creating new WMI class." -Severity 3 -source ${CmdletName}
		}
	}
	End	{
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Add-WMIClassProperty
Function Add-WMIClassProperty{
<#
.SYNOPSIS
	Adds a single WMI class property.
.DESCRIPTION
	This function adds a single WMI class property to the custom WMI class. Use this function multiple times to add multiple properties. 
.PARAMETER  Namespace
	Mandatory. The parent namespace where to add the property.
.PARAMETER  Class
	Mandatory. The WMI class where to add the property.
.PARAMETER  PropertyName
	Mandatory. Name of the property to add.
.PARAMETER  PropertyType
	Mandatory. Type of the property to add.
.EXAMPLE
	Add-WMIClassProperty -Namespace 'Value1' -Class 'Value2'
	Add-WMIClassProperty -Namespace "root\vwg" -Classname "VWG_SoftwareBranding" -PropertyName "Name"			-PropertyType "String" -IsKey
.NOTES
	This is an internal script function and should typically not be called directly.	
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 1)]
		[Alias('__NAMESPACE')]
		[System.String]$Namespace,
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 2)]
		[Alias('__CLASS')]
		[System.String]$ClassName,
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 3)]
		[System.String]$PropertyName,
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 4)]
		[System.Management.CIMtype]$PropertyType,
		[Parameter(Mandatory = $false,
				   Position = 5)]
		[switch]$IsKey
	)
	Begin {
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process	{
		try {
			Get-WmiObject -Namespace $Namespace -Class $ClassName | Out-Null
			$wmiClass = [WMICLASS]"\\.\$Namespace`:$ClassName"
			$wmiClass.Properties.Add($PropertyName, $PropertyType, $false)
			if ($IsKey)
			{
				$wmiClass.Properties[$PropertyName].Qualifiers.Add("Key", $true)
			}
			$wmiClass.Put() | Out-Null
		}
		catch {
			Write-ADTLogEntry -Message "The WMI Namespace and/or Class specified are not valid." -Severity 3 -source ${CmdletName}
			return $false
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Set-BrandingREG
Function Set-BrandingREG {
<#
.SYNOPSIS
	Set state information about the installation in the registry of the target computer.
.DESCRIPTION
	Set state information about the installation in the registry of the target computer for VWG.
.PARAMETER  WMIClassProperties
	Mandatory. Hashtable with properties to set.
.EXAMPLE
	Set-BrandingREG -WMIClassProperties $WMIClassProperties
.NOTES
.LINK
#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true,
		ValueFromPipeline = $true,
		ValueFromPipelineByPropertyName = $true,
		Position = 1)]
		[hashtable]$WMIClassProperties
	)
	
	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process {
		Try {
			Write-ADTLogEntry -Message "Begin set registry branding." -Severity 1 -Source ${CmdletName} 
			[string]$BrandingKey = "HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\$VWG_appFullName"
			
			Write-ADTLogEntry -Message "Writing branding information to registry." -Severity 1 -source ${CmdletName}
			$WMIClassProperties.GetEnumerator() |  ForEach-Object{
				$PropertyKey = $_.Key
				$PropertyValue = $_.Value[0]
				Set-ADTRegistryKey -Key $BrandingKey -Name $PropertyKey -Value $PropertyValue
			}

			Write-ADTLogEntry -Message "Registry branding successfully set." -Severity 1 -Source ${CmdletName} 
		}
		Catch {
			Write-ADTLogEntry -Message "Failed to set registry branding. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Set-Branding
Function Set-Branding{
<#
.SYNOPSIS
	Set WMI branding for the current package.
.DESCRIPTION
	Creates a new instance in VWG_Softwarebranding with all the information about the current package.
	If the class does not exist yet, it will be created first.
.PARAMETER  BrandingRoot
	The root name of the WMI class.
.PARAMETER  BrandingNamespace
	The namespace of the WMI class.
.PARAMETER  BrandingClassname
	The name of the WMI class.
.EXAMPLE
	Set-Branding
	Set-Branding -BrandingRoot "ROOT" -BrandingNamespace "MyNamespace" -BrandingClassname "MyClassName"
.NOTES
	This is an internal script function and should typically not be called directly.
.LINK
	
#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false,
			Position = 1)]
			[string]$BrandingRoot = "ROOT",
		[Parameter(Mandatory = $false,
		 	Position = 2)]
			[string]$BrandingNamespace = "vwg",
		[Parameter(Mandatory = $false,
		 	Position = 3)]
			[string]$BrandingClassname = "VWG_SoftwareBranding"
		)
	Begin{
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
		    $BrandingRootNamespace = "$BrandingRoot\$BrandingNamespace"
	}
	Process	{
		try {
             $WMIClassProperties = @{
			    Name 			= $VWG_appFullName, "String", $true
				Architecture	= $AppArch, "String", $false
				Identifier 		= $VWG_SoftIdent, "String", $false
				Information01 	= $VWG_AppAddInfo01, "String", $false
				Information02 	= $VWG_AppAddInfo02, "String", $false
				Information03 	= $VWG_AppAddInfo03, "String", $false
				Information04 	= $VWG_AppAddInfo04, "String", $false
				Language 		= $appLang, "String", $false
				LastInstalled	= [System.Management.ManagementDateTimeConverter]::ToDmtfDateTime([System.DateTime]::Now), "String", $false
				Product 		= $VWG_appfriendlyName, "String", $false
				Revision 		= $AppRevision, "String", $false
				Vendor 			= $AppVendor, "String", $false
				Version 		= $AppVersion, "String", $false
				OrderNumber		= $VWG_OrderNumber, "String", $false
			}

			#set registry branding
			if ($VWG_SetBrandingReg) {
				Set-BrandingREG -WMIClassProperties $WMIClassProperties	
			}

			#create root namespace, if does not exist
            if (-not (Get-WMINamespace $BrandingRootNamespace)){
                Write-ADTLogEntry -Message "Namespace does not exist. Creating namespace." -Severity 1 -source ${CmdletName}
                New-WMINamespace -Namespace $BrandingNamespace -Rootname $BrandingRoot
            }
            #create branding class, if does not exist
            if (-not ($WMIBrandingClass = Get-WMIClass -Namespace $BrandingRootNamespace -Classname $BrandingClassname -ErrorAction 'SilentlyContinue')) {
				# create class, if does not exist
				Write-ADTLogEntry -Message "Branding class does not exist. Creating branding class" -Severity 1 -source ${CmdletName}
				New-WMIClass -Namespace $BrandingRootNamespace -Classname $BrandingClassname | Out-Null
                $WMIClassProperties.GetEnumerator() |  ForEach-Object{
                    $PropertyName = $_.Key
                    $PropertyType = $_.Value[1]
                    $PropertyKey = $_.Value[2]
                    Add-WMIClassProperty -Namespace $BrandingRootNamespace -Classname $BrandingClassname -PropertyName $PropertyName -PropertyType $PropertyType $PropertyKey
                }
			}
			else {
				#check properties and expand class, if needed
				Write-ADTLogEntry -Message "Checking properties of class [$BrandingClassname]." -Severity 1 -source ${CmdletName}
				$WMIBrandingClassProperties = $(Get-WMIClass -Namespace $BrandingRootNamespace -Classname $BrandingClassname).Properties.Name
                $WMIClassProperties.GetEnumerator() |  ForEach-Object{
                    if (-not ($WMIBrandingClassProperties -contains $_.Key)){
						$PropertyName = $_.Key
						$PropertyValue = $_.Value[0]
						$PropertyType = $_.Value[1]
						Write-ADTLogEntry -Message "Property [$PropertyName] does not exist. Expanding class [$BrandingClassname]." -Severity 1 -source ${CmdletName}
                        Expand-SoftwareBrandingWMIClass -PropertyName $PropertyName -PropertyValue $PropertyValue -PropertyType $PropertyType
                    }
                }
			}
			$WMIBrandingClass = Get-WMIClass -Namespace $BrandingRootNamespace -Classname $BrandingClassname

            # create new instance and set properties
            Write-ADTLogEntry -Message "Writing branding information" -Severity 1 -source ${CmdletName}
            $NewInstance = $WMIBrandingClass.CreateInstance()
            $WMIClassProperties.GetEnumerator() |  ForEach-Object{
                $InstanceName = $_.Key
                $InstanceValue = $_.Value[0]
                $NewInstance.($InstanceName) = $InstanceValue
            }
            $NewInstance.Put() | Out-Null
		}
		catch {
			Write-ADTLogEntry -Message "Error during Branding process. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -source ${CmdletName}
		}
	}
	End	{
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Remove-BrandingREG
Function Remove-BrandingREG {
<#
.SYNOPSIS
	Removes state information about the installation in the registry of the target computer.
.DESCRIPTION
	Removes state information about the installation in the registry of the target computer for VWG.
.PARAMETER  Name
	Provide single or multiple name for <PackageName>. Defaults to $VWG_appFullName
.PARAMETER  AdditionalRegPath
	Provide multiple or a single addtional registry path where branding information are stored.
.PARAMETER  BrandingKey
	Provide the standard registry branding key. Defaults to "HKLM:\SOFTWARE\VWG\CM"
.EXAMPLE
	Remove-BrandingREG 
.EXAMPLE
	Remove-BrandingREG -Name <PackageName>
.EXAMPLE
	Remove-BrandingREG -Name <PackageName> -AdditionalRegPaths "HKLM\Software\$($VWG_CurrentRegWOW)VWG\InstalledProducts"
.NOTES
	This is an internal script function and should typically not be called directly.
.LINK
#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()]
		[ValidateLength(5,1023)]
		[String[]]$Name = $VWG_appFullName,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[String[]]$AdditionalRegPaths,		
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$BrandingKey = "HKLM:\SOFTWARE\VWG\CM"
	)
	
	Begin {
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process {
		Try {
			# build up array of registry paths for 'Get-Childitem'
			[string[]]$BrandingKey = Convert-ADTRegistryPath -Key $BrandingKey
			If ($AdditionalRegPaths) {
				ForEach ($Path in $AdditionalRegPaths) {
					$Path = Convert-ADTRegistryPath -Key $Path
					[string[]]$BrandingKey = $BrandingKey += $Path
				}
			}

			Write-ADTLogEntry -Message "Looking for registry branding key(s) in path(s) [$($BrandingKey)]." -Severity 1 -Source ${CmdletName} 
            ## Defining BrandingKey variable value in unique way
            $BrandingKey = $BrandingKey -split ' ' | ForEach-Object { $_.ToLower() } | Select-Object -Unique
            $RegItems = @()

			# test existence of provided key-names in provided locations and remove if exist
			ForEach ($Object in $Name) {
			    #$RegItems = Get-ChildItem -Path $BrandingKey -Recurse -Include $Object
                ## Adding For each loop to test path the registry location present or not on the device
                Foreach ($key in $BrandingKey) {
                    if (Test-Path -Path $key) {
                        $items = Get-ChildItem -Path $key -Recurse -Include $Object
                        $RegItems += $items
                    }
                    else 
                    {        
                        Write-ADTLogEntry -Message "Registry path not found: $key" -Severity 1 -Source ${CmdletName} 
                    }
                }

                If ($RegItems) {
			    	ForEach ($Item in $Regitems){
			    		Write-ADTLogEntry -Message "Removing registry branding key [$($Item)] recursively." -Severity 2 -Source ${CmdletName} 
			    		Remove-ADTRegistryKey -Key $Item -Recurse
			    	}
		    	}
		    	Else {
                    Write-ADTLogEntry -Message "Registry branding key like [$($object)] not set." -Severity 2 -Source ${CmdletName}
			    }
            }
		}
		Catch {
			Write-ADTLogEntry -Message "Failed to remove registry branding. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}
		}
	}
	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Remove-Branding
Function Remove-Branding{
<#
.SYNOPSIS
	Remove WMI branding for the current package.
.DESCRIPTION
	Removes an instance in VWG_Softwarebranding matching the Name.
.PARAMETER Name (Alias InstanceName)
	The name of the WMI instance to remove. Performs a contains match on the instance name by default.
	Defaults to $VWG_appFullName if Null.
.PARAMETER  AdditionalRegPaths
	Provide additional (multiple or single) registry paths to remove branding keys in. Used on calling Remove-BrandingREG.
.EXAMPLE
	Remove-Branding
	Remove WMI branding (will also remove registry branding if flagged) for the current package.
	This is the default entry in Deployapplication.ps1 region POST-UNINSTALLATION.
.EXAMPLE
	Remove-Branding -Name "Mozilla_Firefox ESR_*"
	This should only be used if you want to remove any old Branding.
.EXAMPLE
	Remove-Branding -Name "Adobe_Acrobat DC*_13*","Adobe_Acrobat DC*_14*"
	This should only be used if you want to remove old Brandings.
.EXAMPLE
	Remove-Branding -InstanceName "$($appVendor)_$($VWG_appfriendlyName)_*" -AdditionalRegPaths "HKLM:\Software\$($VWG_CurrentRegWow)VWG\InstalledProducts","HKLM:\Software\$($VWG_CurrentRegWow)VWG\CM"
	This should only be used if you want to remove old Brandings in multiple registry locations. 
	This is the default entry in Deployapplication.ps1 region POST-INSTALLATION and is requried to comment in to remove all known possible brandings.
.NOTES

.LINK
	http://www.volkswagen-group.com
#>
[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[ValidateLength(5,1023)]
		[Alias("InstanceName")]
		[String[]]$Name = $VWG_appFullName,
		[Parameter(Mandatory=$false)]
		[ValidateNotNullorEmpty()]
		[String[]]$AdditionalRegPaths	
	)
	Begin {
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process	{
		try {
			ForEach ($Item in $Name){
				$Item = $Item.Replace("*","%")
				if ($WMIBrandingInstances = Get-WMIInstance -Namespace "root\vwg" -Classname "VWG_SoftwareBranding" -Query "Name LIKE '$Item'" -ErrorAction SilentlyContinue) {
					# remove the instance identified by the name
                    ForEach ($WMIBrandingInstance in $WMIBrandingInstances) {
					    Write-ADTLogEntry -Message "Removing WMI branding entry [$($WMIBrandingInstance.Name)]." -Severity 2 -source ${CmdletName}
					    $WMIBrandingInstance.Delete()
                    }
				} else {
					Write-ADTLogEntry -Message "WMI branding entry [$($item)] not set." -Severity 2 -source ${CmdletName}
				}
			}
			if ($VWG_SetBrandingReg){
				$Name = $Name.Replace("%","*")
				If ($AdditionalRegPaths) {
					Remove-BrandingREG -Name $Name -AdditionalRegPaths $AdditionalRegPaths
				}
				Else {
					Remove-BrandingREG -Name $Name
				}
			}
		}
		catch {
			Write-ADTLogEntry -Message "Error removing Branding. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -source ${CmdletName}
		}
	}
	End	{
		Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Expand-SoftwareBrandingWMIClass
Function Expand-SoftwareBrandingWMIClass{
<#
.SYNOPSIS
	Adds a single property to the branding class.
.DESCRIPTION
	This function adds a single WMI class property to the existing custom WMI class. Use this function multiple times to add multiple properties.
	The function will back up the class, add the property and write it back
.PARAMETER  PropertyName
	Mandatory. Name of the property to add.
.PARAMETER  PropertyValue
	Mandatory. Default value of the property to add.
.PARAMETER  PropertyType
	Mandatory. Type of the property to add.
.PARAMETER  Restore
	Optional. Normally only needed by the function on write back.
.PARAMETER  BrandingRoot
	The root name of the WMI class to expand.
.PARAMETER  BrandingNamespace
	The namespace of the WMI class to expand.
.PARAMETER  BrandingClassname
	The name of the WMI class to expand.
.EXAMPLE
	Set-Branding
	Set-Branding -BrandingRoot "ROOT" -BrandingNamespace "MyNamespace" -BrandingClassname "MyClassName"
.EXAMPLE
	Expand-SoftwareBrandingWMIClass -PropertyName 'Name' -PropertyValue 'Value' -PropertyType 'String'
	Expand-SoftwareBrandingWMIClass -PropertyName "Myname" -PropertyValue "MyValue" -PropertyType "String" -BrandingRoot "ROOT" -BrandingNamespace "MyNamespace" -BrandingClassname "MyClassName"
.NOTES
	This is an internal script function and should typically not be called directly.	
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 1)]
		[System.String]$PropertyName,
		[Parameter(Mandatory = $false,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 2)]
		[System.String]$PropertyValue = "",
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 3)]
		[System.Management.CIMtype]$PropertyType,
		[Parameter(Mandatory = $false,
				   Position = 4)]
		[string]$BrandingRoot = "ROOT",
		[Parameter(Mandatory = $false,
			Position = 5)]
		[string]$BrandingNamespace = "vwg",
		[Parameter(Mandatory = $false,
			Position = 6)]
		[string]$BrandingClassname = "VWG_SoftwareBranding",
		[Parameter(Mandatory = $false,
			Position = 7)]
		[switch]$Restore
	)
	Begin {
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

		    $BrandingRootNamespace = "$BrandingRoot\$BrandingNamespace"
		    $BrandingClassTemp = "$($BrandingClassname)_TEMP"
		    if ($restore){
			    $swap = $BrandingClassname
			    $BrandingClassname = $BrandingClassTemp
			    $BrandingClassTemp = $swap
		    }
	}
	Process	{
		try {$ExtManagementClass = Get-WMIClass -Namespace $BrandingRootNamespace -Classname $BrandingClassname}
		catch {Write-ADTLogEntry -Message "Branding class $BrandingClassname not found. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -source ${CmdletName}}
		
        # check/create the TEMP class
		if (-not ($NewManagementClass = Get-WMIClass -Namespace $BrandingRootNamespace -ClassName $BrandingClassTemp -ErrorAction 'SilentlyContinue'))
        {
			Write-ADTLogEntry -Message "Creating new WMI class $($NewManagementClass.Name)" -Severity 1 -source ${CmdletName}
			New-WMIClass -Namespace $BrandingRootNamespace -ClassName $BrandingClassTemp
		}

		# populate the properties
		foreach ($Property in $ExtManagementClass.Properties)
        {
			Add-WMIClassProperty -Namespace $BrandingRootNamespace -ClassName $BrandingClassTemp -PropertyName $Property.Name -PropertyType $Property.Type $(@{$true=$true;$false=$null}[$Property.Qualifiers.Name -contains 'key'])
		}

		# re-read class after changes
		Write-ADTLogEntry -Message "Reread class $($NewManagementClass.Name) after applying properties." -Severity 1 -source ${CmdletName}
		$NewManagementClass = Get-WMIClass -Namespace $BrandingRootNamespace -ClassName $BrandingClassTemp
		try {
			# clone the instances and remove from source
			Write-ADTLogEntry -Message "Start cloning." -Severity 1 -source ${CmdletName}
			$ExtBrandingInstances = Get-WmiObject -Namespace $BrandingRootNamespace -Query "SELECT * FROM $BrandingClassname"
			foreach ($ExtBrandingInstance in $ExtBrandingInstances)
            {
				$NewBrandingInstance = $NewManagementClass.CreateInstance()
				Get-WMIClass -Namespace $BrandingRootNamespace -ClassName $BrandingClassTemp
				foreach ($Property in $ExtBrandingInstance.Properties)
                {
					$NewBrandingInstance.$($Property.Name) = $Property.Value
				}
				$NewBrandingInstance.Put()
				$ExtBrandingInstance.Delete()
			}
		}
		catch {
			Write-ADTLogEntry -Message "Error during cloning. `n$(Resolve-Error)" -Severity 3 -source ${CmdletName}
		}
	
		# add any property
		if (!($restore)){
			try {
				$ExtManagementClass.Properties.Add($PropertyName,$NULL,$PropertyType)
				$ExtManagementClass.Put()
				Expand-SoftwareBrandingWMIClass -PropertyName $PropertyName -PropertyValue $PropertyValue -PropertyType $PropertyType -Restore
			}
			catch {
				Write-ADTLogEntry -Message "Error adding property. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -source ${CmdletName}
			}
		}
		else {
			$ExtManagementClass.Delete()
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion

#region Function Set-Reboot
function Set-Reboot {
<#
.SYNOPSIS
	Set the reboot action
.DESCRIPTION
	Set the reboot action
	Set-Reboot does not trigger reboot if the script is running in a task sequence.
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
	Set-Reboot
	Set $mainexitcode 3010 and continue script execution.
.EXAMPLE
	Set-Reboot -MandatoryDeviceRestart
	Set $mainexitcode 1641 and continue script execution.
.EXAMPLE
	Set-Reboot -OnlyOnPendingReboot
	Checks for pending reboot, if found set $mainexitcode to 3010 and continue script execution.
.EXAMPLE
	Set-Reboot -OnlyOnPendingReboot -MandatoryDeviceRestart
	Checks for pending reboot, if found set $mainexitcode to 1641 and continue script execution.
.EXAMPLE
	Set-Reboot -ForceExitScript
	Script execution will be stopped immediatly with $mainexitcode 3010.
.EXAMPLE
	Set-Reboot -ForceExitScript -MandatoryDeviceRestart
	Script execution will be stopped immediatly with $mainexitcode 1641.
.EXAMPLE
	Set-Reboot -ForceExitScript -OnlyOnPendingReboot
	Checks for pending reboot, if found than script execution will be stopped immediatly with $mainexitcode 3010.
.EXAMPLE
	Set-Reboot -ForceExitScript -OnlyOnPendingReboot -MandatoryDeviceRestart
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
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState            
	}
	Process {
		Try {
			Switch ($adtSession.InstallPhase){
				{($_ -eq "Pre-Install") -Or ($_ -eq "Pre-Uninstall") -Or ($_ -eq "Pre-Repair")} {$ScriptRegionString = "before";Break}
				{($_ -eq "Post-Install") -Or ($_ -eq "Post-Uninstall") -Or ($_ -eq "Post-Repair")} {$ScriptRegionString = "after";Break}
				default {$ScriptRegionString = "within"}
			}
			
			If ($MandatoryDeviceRestart){
				[string]$RestartType = "Mandatory device restart"
				[int32]$ExitCode = 1641
			}
			Else {
				[string]$RestartType = "Device restart"
				[int32]$ExitCode = 3010
			}

            $RunningTaskSequence = !![System.Type]::GetTypeFromProgID('Microsoft.SMS.TSEnvironment')

			If ($runningTaskSequence){
				Write-ADTLogEntry -Message "Installation is running in task sequence, reboot will not be triggered. Continue script execution." -Severity 2 -Source ${CmdletName}
				return
			}
			ElseIf($ForceExitScript)
                {
				    If($OnlyOnPendingReboot)
                    {
					    If((Get-ADTPendingReboot).IsSystemRebootPending)
                        {
						    Write-ADTLogEntry -Message "Pending reboot detected. $($RestartType) required $($ScriptRegionString) $($SessionDeploymentType)ing [$($VWG_appFullName)]. Exit script execution." -Severity 2 -Source ${CmdletName}
						    Close-ADTSession -ExitCode $ExitCode
					    }
					    Else
                        {
						    Write-ADTLogEntry -Message "No pending reboot detected. $($ScriptRegionString) $($SessionDeploymentType)ing [$($VWG_appFullName)]. Continue script execution." -Severity 2 -Source ${CmdletName}
					    }
				    }
				    Else 
                    {
					    Write-ADTLogEntry -Message "$($RestartType) required $($ScriptRegionString) $($SessionDeploymentType)ing [$($VWG_appFullName)]. Exit script execution." -Severity 2 -Source ${CmdletName}
					    Close-ADTSession -ExitCode $ExitCode
				    }
			}
			Else {
				If ($OnlyOnPendingReboot) {
					If ((Get-ADTPendingReboot).IsSystemRebootPending){
			            If ($MandatoryDeviceRestart) {
				            [string]$RestartType = "Mandatory device restart"
				            [int32]$ExitCode = 1641
						    Write-ADTLogEntry -Message "Pending reboot detected. $($RestartType) required $($ScriptRegionString) $($SessionDeploymentType)ing [$($VWG_appFullName)]." -Severity 2 -Source ${CmdletName}						    
                            Close-ADTSession -ExitCode $ExitCode
			            }
                        else
                        {
				            [string]$RestartType = "Device restart"
				            [int32]$ExitCode = 3010
						    Write-ADTLogEntry -Message "Pending reboot detected. $($RestartType) required $($ScriptRegionString) $($SessionDeploymentType)ing [$($VWG_appFullName)]." -Severity 2 -Source ${CmdletName}
                            Close-ADTSession -ExitCode $ExitCode
                        }
					}
					Else {
						Write-ADTLogEntry -Message "No pending reboot detected. $($ScriptRegionString) $($SessionDeploymentType)ing [$($VWG_appFullName)]. Continue script execution." -Severity 2 -Source ${CmdletName}
					}
				}
				Else {
			            If ($MandatoryDeviceRestart) {
				            [string]$RestartType = "Mandatory device restart"
				            [int32]$ExitCode = 1641
						    Write-ADTLogEntry -Message "Pending reboot detected. $($RestartType) required $($ScriptRegionString) $($SessionDeploymentType)ing [$($VWG_appFullName)]." -Severity 2 -Source ${CmdletName}
                            Close-ADTSession -ExitCode $ExitCode
			            }
                        else
                        {
				            [string]$RestartType = "Device restart"
				            [int32]$ExitCode = 3010
						    Write-ADTLogEntry -Message "$($RestartType) required $($ScriptRegionString) $($SessionDeploymentType)ing [$($VWG_appFullName)]." -Severity 2 -Source ${CmdletName}
                            Close-ADTSession -ExitCode $ExitCode
                        }
				}
			}
		}
		Catch {
			Write-ADTLogEntry -Message "Failed to set reboot. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 3 -Source ${CmdletName}                
			Throw (New-ADTErrorRecord @naerParams)
		}
	}
	End {
		 Complete-ADTFunction -Cmdlet $PSCmdlet
	}
}
#endregion

#region Function Get-WindowsDriverOnline
function Get-WindowsDriverOnline(){
	<#
	.SYNOPSIS
		Displays information about drivers in a Windows installation
	.DESCRIPTION
		Returns driver information from the running OS
		Any information is returned as hashtable
		These features are for Windows 7 under Windows 10 please use the standard cmd-lets ADD-WindowsDriver, Export-WindowsDriver, Get-WindowsDriver and Remove-WindowsDriver
	.PARAMETER Path
		Either a single vendor inf name or a path to a driver inf file or a folder with driver inf files you want to query
		Use * to get a full list of drivers
	.EXAMPLE
		Get-WindowsDriverOnline -Path "oem4.inf"
			Get details about a driver in the running OS
	.EXAMPLE
		Get-WindowsDriverOnline -Path "$dirFiles\drivers\ftdibus.inf"
            Get details about a driver as specified by the named vendor inf
	.EXAMPLE
		Get-WindowsDriverOnline -Path "$dirFiles\drivers"
		    Get details about drivers as specified by all vendor inf in the folder
	.EXAMPLE
		Get-WindowsDriverOnline -Path "*"
			Get details about all drivers
	.NOTES
	
	.LINK
		http://www.volkswagen-group.com
		
	#>
		[CmdletBinding()]
		Param (
			[Parameter(Mandatory=$true,
			HelpMessage="Either a single vendor inf name or a path to a driver inf file or a folder with driver inf files you want to query. Use * to get a full list of drivers")]
			[ValidateNotNullOrEmpty()]
			[ValidateScript({(Test-Path -Path $_ -PathType Container) -or ((Test-Path -Path $_ -PathType Leaf) -and ($_ -match "\\\w+.inf$")) -or ($_ -match "^\w+.inf$") -or ($_ -match "^\*$")})]
			[string]$Path,
			[Parameter(Mandatory=$false)]
			[boolean]$ContinueOnError = $true
		)
		begin{
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
		}
		Process{
			$Drv2Query = @{}
			if ($Path -eq "*"){
				Write-ADTLogEntry -Message "Query all drivers from running OS" -Severity 1 -Source ${CmdletName}
				$InfFiles = "AllDrivers"
			} elseif (Test-Path -Path $Path -PathType Container){
				Write-ADTLogEntry -Message "Query drivers using all files from $Path" -Severity 1 -Source ${CmdletName}
				$InfFiles = @(Get-ChildItem -Path $Path -Recurse -Filter "*.inf")
			} elseif (Test-Path -Path $Path -PathType Leaf){
				Write-ADTLogEntry -Message "Query drivers using single file at $Path" -Severity 1 -Source ${CmdletName}
				$InfFiles = @(Get-ChildItem -Path $Path -Filter "*.inf")
			} elseif ($Path -match "^\w+.inf$"){
				Write-ADTLogEntry -Message "Query drivers using any match for $Path" -Severity 1 -Source ${CmdletName}
				$InfFiles = $Path
			} else {
				Write-ADTLogEntry -Message "Something must be wrong, you shouldn't read this" -Severity 3 -Source ${CmdletName}
				$Drv2Query["AllDrivers"] = @{}
				$Drv2Query["AllDrivers"]["Error"] = "something went wrong"
				return $Drv2Query
			}
	
			foreach ($InfName in $InfFiles){
				# is it a wildcard
				if ($InfName -eq "AllDrivers"){
					$Drv2Query[$InfName] = @{}
					$SysDriver  = Get-WmiObject Win32_PnPSignedDriver
					if ($SysDriver -ne $null){
						foreach ($SingleDriver in $SysDriver){
							$Drv2Query[$InfName][$SingleDriver.DeviceID] = @{}
							$SingleDriver | foreach {$_.Properties | select Name,Value } | foreach {$Drv2Query[$InfName][$SingleDriver.DeviceID].$($_.Name)="$($_.Value)"}
						}			
					} else {
						$Drv2Query[$InfName]["DeviceID"] = "not found"
					}
				}
				# is it any other name of an .inf
				elseif ($InfName -is [string]){
					$Drv2Query[$InfName] = @{}
					$SysDriver  = Get-WmiObject Win32_PnPSignedDriver -Filter "InfName = '$InfName'"
					if ($SysDriver -ne $null){
						foreach ($SingleDriver in $SysDriver){
							$Drv2Query[$InfName][$SingleDriver.DeviceID] = @{}
							$SingleDriver | foreach {$_.Properties | select Name,Value } | foreach {$Drv2Query[$InfName][$SingleDriver.DeviceID].$($_.Name)="$($_.Value)"}
						}			
					} else {
						$Drv2Query[$InfName]["DeviceID"] = "not found"
					}
				}
				# is it an existing inf
				elseif (Test-Path -Path $InfName.FullName){
					$Drv2Query[$InfName.Name] = @{}
					$InfClassGUID	= Get-IniData -File "$($InfName.FullName)" -Section "Version" -Key "ClassGuid"
					$InfProvider	= Get-IniData -File "$($InfName.FullName)" -Section "Version" -Key "Provider"
					if ($InfProvider -like "%*%") {
						$RealProvider = $InfProvider -replace "%",""
						$InfProvider  = (Get-IniData -File "$($InfName.FullName)" -Section "Strings" -Key "$RealProvider").Trim("`"")
					}
					$InfVersion	= (((Get-IniData -File "$($InfName.FullName)" -Section "Version" -Key "DriverVer") -split ",")[1]) -split "\." -replace "\b^0+\B","" -join "."
					$SysDriver  = Get-WmiObject Win32_PnPSignedDriver -Filter "ClassGuid = '$InfClassGUID' AND DriverProviderName = '$InfProvider' AND DriverVersion = '$InfVersion'"
					if ($SysDriver -ne $null){
						if (($SysDriver.InfName -ne "") -and ((Select-String -Path $InfName.FullName -Pattern $SysDriver.HardWareID -SimpleMatch -Quiet) -or (Select-String -Path $InfName.FullName -Pattern $SysDriver.CompatID -SimpleMatch -Quiet))){
							foreach ($SingleDriver in $SysDriver){
								$Drv2Query[$InfName.Name][$SingleDriver.DeviceID] = @{}
								$SingleDriver | foreach {$_.Properties | select Name,Value } | foreach {$Drv2Query[$InfName.Name][$SingleDriver.DeviceID].$($_.Name)="$($_.Value)"}
							}
						} else {
							$Drv2Query[$InfName.Name]["DeviceID"] = "not found"
						}
					} else {
						$Drv2Query[$InfName.Name]["DeviceID"] = "not found"
					}
				}
				# oopsie
				else {
					Write-ADTLogEntry -Message "Something must be wrong, you shouldn't read this" -Severity 3 -Source ${CmdletName}
					$Drv2Query["AllDrivers"]["Error"] = "something went wrong"
				}
			}
			return $Drv2Query
		}
		End {
			Complete-ADTFunction -Cmdlet $PSCmdlet
		}
	}
	#endregion

#region Function Add-WindowsDriverOnline
function Add-WindowsDriverOnline(){
	<#
	.SYNOPSIS
		Add and install drivers
	.DESCRIPTION
		Add and install drivers to the running OS using PnPutil.exe
		These features are for Windows 7 under Windows 10 please use the standard cmd-lets ADD-WindowsDriver, Export-WindowsDriver, Get-WindowsDriver and Remove-WindowsDriver
	.PARAMETER Path
		A path to the driver folder or a single inf name
	.PARAMETER NoInstall
		If set, the driver is added to the repository only
	.PARAMETER ContinueOnError
		If set, ignores all errors
	.EXAMPLE
		Add-WindowsDriverOnline -Path "$dirFiles\drivers"
			Adds the driver to the repository and installs it for any matching and connected device
	.EXAMPLE
		Add-WindowsDriverOnline -Path "$dirFiles\drivers\superdup.inf" -NoInstall
			Adds the driver to the repository without installing it to any matching and connected device
	.NOTES

	.LINK
		http://www.volkswagen-group.com	

	#>
		[CmdletBinding()]
		Param (
			[Parameter(Mandatory=$true,
			HelpMessage="A path to the driver folder or a single inf name")]
			[ValidateNotNullOrEmpty()]
			[ValidateScript({(Test-Path -Path $_ -PathType Container) -or ((Test-Path -Path $_ -PathType Leaf) -and ($_ -match "\\\w+.inf$"))})]
			[string]$Path,
			[Parameter(Mandatory=$false,
			HelpMessage="If set, the driver is added to the repository only")]
			[switch]$NoInstall = $false,
			[Parameter(Mandatory=$false)]
			[boolean]$ContinueOnError = $true
		)
		Begin {
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
		}
		Process {
			Try {
				if ($envOSVersion -gt "7.0.0.0"){
					$DrivAddParameter = "/add-driver"
					if ($NoInstall -eq $false){
						$InstallParameter = "/install"
					}
				} else {
					$DrivAddParameter = "/a"
					if ($NoInstall -eq $false){
						$InstallParameter = "/i"
					}
				}
				$DrvPublishedNames = @{}
				Get-ChildItem -Path $Path -Recurse -Filter "*.inf" | ForEach-Object { `
					$result = Start-ADTProcess -FilePath "PNPUtil.exe" -ArgumentList "$InstallParameter $DrivAddParameter `"$($_.FullName)`"" -PassThru 
					if ($result.ExitCode -eq 0){
						$OEMfile = $($result.StdOut | Select-String -Pattern "(oem[\d]+.inf)" | foreach {$_.Matches.Groups[1].Value})
						Write-ADTLogEntry -Message "Added driver from $($_.Name) successfully with published name $OEMfile" -Severity 1 -Source ${CmdletName}
						$DrvPublishedNames[$_.Name] = $OEMfile
					} else {
						Write-ADTLogEntry -Message "Adding driver failed with RC=$($result.ExitCode)" -Severity 3 -Source ${CmdletName}
                        Throw (New-ADTErrorRecord @naerParams)
					}
				}
				return $DrvPublishedNames
			}
			Catch {
				Write-ADTLogEntry -Message "Failed to add driver to windows. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Source ${CmdletName} -Severity 3
                Throw (New-ADTErrorRecord @naerParams)
			}
		}
		End {
			Complete-ADTFunction -Cmdlet $PSCmdlet
		}
	}
	#endregion

#region Function Remove-WindowsDriverOnline
function Remove-WindowsDriverOnline(){
	<#
	.SYNOPSIS
		Remove driver
	.DESCRIPTION
		Remove drivers from the running OS using PnPutil.exe
		These features are for Windows 7 under Windows 10 please use the standard cmd-lets ADD-WindowsDriver, Export-WindowsDriver, Get-WindowsDriver and Remove-WindowsDriver
	.PARAMETER Path
		The inf filename(s) you want to remove. Can be an arrray.
	.PARAMETER Force
		Forces the deletion of the specified driver package from the driver store
		You must use this parameter if the specified driver package is installed on a device that is connected to the system
	.PARAMETER ContinueOnError
		If set, ignores all errors
	.EXAMPLE
		Remove-WindowsDriverOnline -Path "oem19.inf","oem129.inf"
			Removes the driver from the driver store if it was not used to install drivers for devices that are connected to the system
	.EXAMPLE
		Remove-WindowsDriverOnline -Path "oem49.inf" -Force
			Removes the driver from the driver store and uninstalls it for devices that are connected to the system
	.NOTES
		Caution: Removing a boot-critical driver package can make the Windows OS unbootable
	.LINK
		http://www.volkswagen-group.com	
	#>
		[CmdletBinding()]
		Param (
			[Parameter(Mandatory=$true,
			HelpMessage="The published name of the INF file for the driver package that was added to the driver store")]
			[ValidateNotNullOrEmpty()]
			[ValidateScript({$_ -match "^\w+.inf$"})]
			[array]$Path,
			[Parameter(Mandatory=$false,
			HelpMessage="If set, forces the deletion of the specified driver package from the driver store")]
			[switch]$Force = $false,
			[Parameter(Mandatory=$false)]
			[boolean]$ContinueOnError = $true
		)
		begin{
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
		}
		Process{
			Try {
				if ($envOSVersion -gt "7.0.0.0"){
					$DrivRemParameter = "/delete-driver"
					if ($Force -eq $true){
						$ForceParameter = "/force"
					}
				} else {
					$DrivRemParameter = "/d"
					if ($Force -eq $true){
						$ForceParameter = "/f"
					}
				}
				$DrvRemovedNames = @{}
				foreach ($File in $Path){
					if ($envOSVersion -gt "7.0.0.0"){
						$result = Start-ADTProcess -FilePath "PNPUtil.exe" -ArgumentList "$DrivRemParameter `"$File`" $ForceParameter" -PassThru 
					} else {
						$result = Start-ADTProcess -FilePath "PNPUtil.exe" -ArgumentList "$ForceParameter $DrivRemParameter `"$File`"" -PassThru 
					}
					if ($result.ExitCode -eq 0){
						Write-ADTLogEntry -Message "Removed driver package $File successfully" -Severity 1 -Source ${CmdletName}
						$DrvRemovedNames[$File]="removed"
					}elseif ($result.ExitCode -eq 2){
						Write-ADTLogEntry -Message "No driver package $File found" -Severity 2 -Source ${CmdletName}
						$DrvRemovedNames[$File]="not found"
					} else {
						Write-ADTLogEntry -Message "Removing driver failed with RC=$($result.ExitCode)" -Severity 3 -Source ${CmdletName}
						$DrvRemovedNames[$File]="error $($result.ExitCode)"
                        Throw (New-ADTErrorRecord @naerParams)
					}
				}
			}
			Catch {
				Write-ADTLogEntry -Message "Failed to remove driver from windows. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Source ${CmdletName} -Severity 3                
				Throw (New-ADTErrorRecord @naerParams)
			}
			return $DrvRemovedNames
		}
		End {
			Complete-ADTFunction -Cmdlet $PSCmdlet
		}
	}
	#endregion

#region Function Add-Font
function Add-Font(){
	<#
	.SYNOPSIS
		Install a Windows font
	.DESCRIPTION
		Add a single font to the Windows fonts
	.PARAMETER Path
		Font file path and name, valid file types are .fon, .ttf, .otf
	.PARAMETER Force
		If the font exists, remove and reinstall it
	.PARAMETER ContinueOnError
		If set, ignores all errors
	.EXAMPLE
		Add-Font -Path "$FilesFolder\VWAG_norm.ttf"
			Add the font to Windows
	.NOTES
	.LINK
		http://www.volkswagen-group.com	
	#>
		[CmdletBinding()]
		Param (
			[Parameter(Mandatory=$true,
			HelpMessage="The font file name of a file to add to \Windows\Fonts. Valid file types are .fon, .ttf, .otf")]
			[ValidateNotNullOrEmpty()]
			[ValidateScript({((Test-Path -Path $_ -PathType Leaf) -and ($_ -match "(\.fon|\.ttf|\.otf)"))})]
			[string]$Path,
			[Parameter(Mandatory=$false)]
			[switch]$Force = $false,
			[Parameter(Mandatory=$false)]
			[boolean]$ContinueOnError = $true
		)
		Begin {
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

			$FontsFolder = New-Object -ComObject "Shell.Application" | foreach {$_.NameSpace(0x14).Self.Path}
			$FontsRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
			AddType-Font
			$hashFontFileTypes = @{}
			$hashFontFileTypes.Add(".fon", "")
			$hashFontFileTypes.Add(".ttf", " (TrueType)")
			$hashFontFileTypes.Add(".otf", " (OpenType)")
			# Type 1 fonts require handling multiple resource files and are not supported yet
			#$hashFontFileTypes.Add(".mmm", "")
			#$hashFontFileTypes.Add(".pbf", "")
			#$hashFontFileTypes.Add(".pfm", "")
			#$hashFontFileTypes.Add(".ttc", " (TrueType)")
			#$hashFontFileTypes.Add(".fnt", "")
		}
		Process {
			Try {
				$FontFile = Get-ChildItem -Path $Path | %{$_.Name}
				$FontFullPath = Join-Path $FontsFolder $FontFile
				if (Test-Path -Path $FontFullPath -PathType Leaf){					
                    Write-ADTLogEntry -Message "The file $FontFullPath does already exist" -Source ${CmdletName} -Severity 1
					if (-not($Force)){						
                        Write-ADTLogEntry -Message "Force parameter is not set, leaving any font untouched" -Source ${CmdletName} -Severity 1
						return
					} else {						
                        Write-ADTLogEntry -Message "Force parameter is set, replacing the exisiting font" -Source ${CmdletName} -Severity 1
						Remove-Font -Path $FontFile
					}
				}
				$FontFolder = Get-ChildItem -Path $Path | %{$_.Directory.FullName}
				$FontType = Get-ChildItem -Path $Path | %{$_.Extension}
				$FontName = New-Object -ComObject "Shell.Application" | foreach {$_.NameSpace($FontFolder).GetDetailsOf($_.NameSpace($FontFolder).Items().Item($FontFile),21)}
	
				Copy-Item -Path $Path -Destination $FontsFolder -Force
				$retVal = [FontResource.AddRemoveFonts]::AddFont($FontFullPath)
				if ($retVal -eq 0) {					
                    Write-ADTLogEntry -Message "Adding font file from $Path failed" -Source ${CmdletName} -Severity 3
				} else {					
                    Write-ADTLogEntry -Message "Adding font file from $Path to $FontFullPath" -Source ${CmdletName} -Severity 1
				}				
                Write-ADTLogEntry -Message "Adding font $FontName to Registry" -Source ${CmdletName} -Severity 1
				$FontsRegistryName = "$($fontName)$($hashFontFileTypes.item($FontType))"
				Set-ItemProperty -Path $FontsRegistryPath -Name $FontsRegistryName -Value $FontFile
                Update-ADTDesktop
			}
			Catch {				
                Write-ADTLogEntry -Message "Failed to add font to windows. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Source ${CmdletName} -Severity 3
                Throw (New-ADTErrorRecord @naerParams)
			}
		}
		End {
			Complete-ADTFunction -Cmdlet $PSCmdlet
		}
	}
	#endregion

#region Function AddType-Font
Function AddType-Font {
	<#
	.SYNOPSIS
		C# code added for FontResource.AddRemoveFonts
	.DESCRIPTION
		Add or remove a font using messages to GDI
	.NOTES
		Derived from a script copyright (C) 2010 Microsoft Corporation
	#>
	$FontTypeAdd = @'
	using System;
	using System.Collections.Generic;
	using System.Text;
	using System.IO;
	using System.Runtime.InteropServices;
	namespace FontResource
	{
		public class AddRemoveFonts
		{
			private static IntPtr HWND_BROADCAST = new IntPtr(0xffff);
			private static IntPtr HWND_TOP = new IntPtr(0);
			private static IntPtr HWND_BOTTOM = new IntPtr(1);
			private static IntPtr HWND_TOPMOST = new IntPtr(-1);
			private static IntPtr HWND_NOTOPMOST = new IntPtr(-2);
			private static IntPtr HWND_MESSAGE = new IntPtr(-3);
			private static IntPtr WM_FONTCHANGE = new IntPtr(0x001D);
			[DllImport("gdi32.dll")]
			static extern int AddFontResource(string lpFilename);
			[DllImport("gdi32.dll")]
			static extern int RemoveFontResource(string lpFileName);
			[return: MarshalAs(UnmanagedType.Bool)]
			[DllImport("user32.dll", SetLastError = true)]
			private static extern bool PostMessage(IntPtr hWnd, IntPtr Msg, IntPtr wParam, IntPtr lParam);

			public static int AddFont(string fontFilePath) {
				FileInfo fontFile = new FileInfo(fontFilePath);
				if (!fontFile.Exists) {return 0;}
				try {
					int retVal = AddFontResource(fontFilePath);
					bool posted = PostMessage(HWND_BROADCAST, WM_FONTCHANGE, IntPtr.Zero, IntPtr.Zero);
					return retVal;
				}
				catch {
					return 0;
				}
			}
			
			public static int RemoveFont(string fontFileName) {
				try {
					int retVal = RemoveFontResource(fontFileName);
					bool posted = PostMessage(HWND_BROADCAST, WM_FONTCHANGE, IntPtr.Zero, IntPtr.Zero);
					return retVal;
				}
				catch {
					return 0;
				}
			}
		}
	}
'@
		Add-Type $FontTypeAdd
	}
	#endregion

#region Function Remove-Font
function Remove-Font(){
	<#
	.SYNOPSIS
		Uninstall a Windows font
	.DESCRIPTION
		Removes a font or font family from Windows
	.PARAMETER Path
		single font file name, valid file types are .fon, .ttf, .otf
	.PARAMETER ContinueOnError
		If set, ignores all errors
	.EXAMPLE
		Remove-Font -Path "VWAG_norm.ttf"
			Remove the font from the fonts folder
	.NOTES

	.LINK
		http://www.volkswagen-group.com	

	#>
		[CmdletBinding()]
		Param (
			[Parameter(Mandatory=$true,
			HelpMessage="The font file name of a file located in \Windows\Fonts. Valid file types are .fon, .ttf, .otf")]
			[ValidateScript({($_ -match "(\.fon|\.ttf|\.otf)")})]
			[ValidateNotNullOrEmpty()]
			[string]$Path,
			[Parameter(Mandatory=$false)]
			[boolean]$ContinueOnError = $true
		)
		Begin {
            # Initalize function and get required objects.
            [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
            Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

			$FontsFolder = New-Object -ComObject "Shell.Application" | foreach {$_.NameSpace(0x14).Self.Path}
			$FontsRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
			AddType-Font
		}
		Process {
			Try {
				$FontFullPath = Join-Path $FontsFolder $Path
				if (-not(Test-Path -Path $FontFullPath -PathType Leaf)){
                    Write-ADTLogEntry -Message "The font file $FontFullPath does not exist" -Source ${CmdletName} -Severity 1					
				} else {
					$retVal = [FontResource.AddRemoveFonts]::RemoveFont($FontFullPath)
					if ($retVal -eq 0) {						
                        Write-ADTLogEntry -Message "Removal of font $Path failed" -Source ${CmdletName} -Severity 1
					}
				}
				$Pattern = [Regex]::Escape($Path)
				foreach($Property in (Get-ItemProperty $FontsRegistryPath).PsObject.Properties){
					# Skip PowerShell properties
					if(($Property.Name -eq "PSPath") -or ($Property.Name -eq "PSChildName")){continue}
					## Search the text of the property                    
					$PropertyText = "$($Property.Value)"
                    $FontsRegistryValue = $null
					if($PropertyText -match $Pattern){
                                                        $FontsRegistryValue = "$($property.Name)"
                                                        Break;
                                                     }
				}
				if (($FontsRegistryValue -eq $null) -or ($FontsRegistryValue -eq "")){					
                    Write-ADTLogEntry -Message "The registry entry for $Path does not exist." -Source ${CmdletName} -Severity 1
				} else {
                    Write-ADTLogEntry -Message "Removing font $FontsRegistryValue from Registry" -Source ${CmdletName} -Severity 1					
					Remove-ItemProperty -Path $FontsRegistryPath -Name $FontsRegistryValue
				}
				if (Test-Path -Path $FontFullPath -PathType Leaf){
                    Write-ADTLogEntry -Message "Removing font file $FontFullPath" -Source ${CmdletName} -Severity 1					
					Remove-Item -Path "$FontFullPath" -Force
				}
				Update-ADTDesktop
			}
			Catch {				
                Write-ADTLogEntry -Message "Failed to remove font from windows. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Source ${CmdletName} -Severity 3
				Throw (New-ADTErrorRecord @naerParams)
			}
		}
		End {
			Complete-ADTFunction -Cmdlet $PSCmdlet
		}
}
#endregion

#region Function Add-UGPermission
Function Add-UGPermission {
    <#
    .SYNOPSIS
	    Adding modify or full Control permission to users group on folder/file/registry
    .DESCRIPTION
    The function adds full control rights or modify rights to user group
    Creates permission folder if not exist
    .PARAMETER Path
	    Specifies, as a string array, the Folder/File/Registry path .
    .EXAMPLE
	     Add-UGPermission -Path "c:\Temp\VW","C:\test\Volswagen" -Fullcontrol
         Add-UGPermission -Path "c:\ProgramData\abc.txt" -Modify
         Add-UGPermission -Path "HKLM:\Software\test" -Fullcontrol
    .NOTES
    .LINK
	    http://www.volkswagen-group.com
    #>
	        [CmdletBinding()]
		    Param (
			    [Parameter(Mandatory=$true)]
			    [ValidateNotNullorEmpty()]
			    [string[]]$Path,
                [switch]$FullControl,
                [switch]$Modify			
		    )
		
		    begin{
                    # Initalize function and get required objects.
                    [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
                    Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState			
		    }
		    process{
                Try{
        
                  If($FullControl)
                  {
                    foreach($Directroy in $Path)
                    {
                       If([System.IO.Path]::GetPathRoot($Directroy))
                       {
                         If((-not ([IO.Path]::HasExtension($Directroy))) -and (-not (Test-Path -LiteralPath $Directroy -PathType 'Container'))) 
                         {
				            New-ADTFolder -Path $Directroy
		                 } 
                            If(Test-Path -LiteralPath $Directroy -PathType 'Container')
                            {
                                Write-ADTLogEntry -Message "Adding Full control permission to folder [$Directroy]" -Source ${CmdletName} -Severity 2                                
                                Start-ADTProcess -FilePath "icacls.exe" -ArgumentList "`"$Directroy`" /grant *S-1-5-32-545:(OI)(CI)F /T" -IgnoreExitCodes "3,1332" -WindowStyle "Hidden"
                            }
                            ElseIf(Test-Path -Path $Directroy -PathType Leaf)
                            {
                                Write-ADTLogEntry -Message "Adding Full control permission to  File [$Directroy]" -Source ${CmdletName} -Severity 2
                                Start-ADTProcess -FilePath "icacls.exe" -ArgumentList "`"$Directroy`" /grant *S-1-5-32-545:(F,WA)" -IgnoreExitCodes "3,1332" -WindowStyle "Hidden"                                
                            }
                            Elseif(!(Test-Path -Path $Directroy -PathType Leaf))
                            {
                                Write-ADTLogEntry -Message "File [$Directroy] does not exists to add full control permission" -Source ${CmdletName} -Severity 2                                
                            }
                      }
                      Else
                      {
                        If(Test-Path -Path "$Directroy")
                        {
                            Write-ADTLogEntry -Message "Adding Full control permission to registry key [$Directroy]" -Source ${CmdletName} -Severity 2                            
                                    #ACL group "users"
		                            $Users_SID_Name   = "S-1-5-32-545" 
		                            $Users_SID_Object = New-Object System.Security.Principal.SecurityIdentifier($Users_SID_Name)
		                            $Users_NTAccount  = $Users_SID_Object.Translate([System.Security.Principal.NTAccount])
		                            $Users_GroupName  = $Users_NTAccount.Value.Split("{\}")[1]
                            
                            $acl = Get-Acl -path "$Directroy"
                            $rule = New-Object System.Security.AccessControl.RegistryAccessRule (".\$Users_GroupName","FullControl",@("ObjectInherit","ContainerInherit"),"None","Allow")
                            $acl.SetAccessRule($rule)
                            $acl |Set-Acl -Path "$Directroy"
                        }
                        Elseif(!(Test-Path -Path "$Directroy"))
                        {
                            Write-ADTLogEntry -Message "Registy key [$Directroy] does not exists to add full control permission" -Source ${CmdletName} -Severity 2                            
                        }
                      }
                    }                
                  } 
              
                  If($Modify)
                  {
                       foreach($Directroy in $Path)
                        {
                           If([System.IO.Path]::GetPathRoot($Directroy))
                           {
                                If((-not ([IO.Path]::HasExtension($Directroy))) -and (-not (Test-Path -LiteralPath $Directroy -PathType 'Container'))) 
                                {
				                   New-ADTFolder -Path $Directroy
		                        } 
                                If(Test-Path -Path $Directroy -PathType Container)
                                {
                                     Write-ADTLogEntry -Message "Adding Modify permission to Folder [$Directroy]" -Source ${CmdletName} -Severity 2
                                     Start-ADTProcess -FilePath "icacls.exe" -ArgumentList "`"$Directroy`" /grant *S-1-5-32-545:(OI)(CI)M /T" -IgnoreExitCodes "3,1332" -WindowStyle "Hidden"
                                }
                                ElseIf(Test-Path -Path $Directroy -PathType Leaf)
                                {
                                     Write-ADTLogEntry -Message "Adding Modify permission to file [$Directroy]" -Source ${CmdletName} -Severity 2
                                     Start-ADTProcess -FilePath "icacls.exe" -ArgumentList "`"$Directroy`" /grant *S-1-5-32-545:(M,WA)" -IgnoreExitCodes "3,1332" -WindowStyle "Hidden"                                     
                                }
                                Elseif(!(Test-Path -Path $Directroy -PathType Leaf))
                                {
                                    Write-ADTLogEntry -Message "File [$Directroy] is not exists to add Modify permission" -Source ${CmdletName} -Severity 2                                    
                                }
                           }
                        }
                  }
              }
		      Catch
                {   
                    Write-ADTLogEntry -Message "Failed to wait for mentioned process. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Source ${CmdletName} -Severity 3                            

                    Throw (New-ADTErrorRecord @naerParams)
                }    	
		    }
		    End{
			        Complete-ADTFunction -Cmdlet $PSCmdlet
		       }
	    }
    #endregion

#region Function Remove-Certificate
Function Remove-Certificate {
           <#
        .SYNOPSIS
	        Removes Certificates if they exist.
        .DESCRIPTION
	        Removes Certificates by using Thumbprint if exist.
        .PARAMETER Path
	        Specifies, as a string array, the Certificates to remove.
        .EXAMPLE
	        Remove-Certificate -Thumbprint "F10484EBE454F98F42C846C3885AFCAAC8842F96","BAE19AB8365E8E08A17DF2B42852A4AFD81BE504"
        .NOTES
        .LINK
	        http://www.volkswagen-group.com
        #>
  
        [CmdletBinding()]
            param (
        
                [Parameter(Mandatory=$true)]
		        [ValidateNotNullorEmpty()]
                [ValidatePattern('^[a-zA-Z0-9]+$')]
                [ValidateLength(38,43)] 
	            [string[]] $Thumbprint 
         )
         begin{
                # Initalize function and get required objects.
                [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
                Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState		        
		      }
		      process{
                       Foreach($Thumb in $Thumbprint)
                       {                
                         $CerFiles = gci -Path "Cert:\LocalMachine" -Recurse | Where-Object { $_.Thumbprint -eq "$Thumb"} 
                         If(!($CerFiles))
                         {
                              Write-ADTLogEntry -Message "Certificate : [$($Thumb)] does not exist." -Source ${CmdletName} -Severity 3                              
                         }
                         Else
                         {
                         	Try{
				                   $CerFiles | % {Remove-Item -Path $_.PSPath -Force -ErrorAction 'Stop'}
                                   $location = ($CerFiles.PSParentPath).replace("Microsoft.PowerShell.Security\Certificate::","Certificate:\")
                                                                       
                                   Write-ADTLogEntry -Message "Successfully deleted the Certificate [$($CerFiles.PSChildName)] from the [$location] location" -Source ${CmdletName} -Severity 2
			                   }
			                Catch{ 
                                    Write-ADTLogEntry -Message "The following error(s) took place while deleting Certificate[$Thumb]. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Source ${CmdletName} -Severity 2				                   
			                     }
                          }
                   
                        }   
                    }         
                    End {
			        Complete-ADTFunction -Cmdlet $PSCmdlet
		        }
     }
     #endregion

#region Function Delete-Service
Function Delete-Service {
           <#
        .SYNOPSIS
	        Delete Service(s) if present.
        .DESCRIPTION
	        Deleting the requested Service(s) if exist.
        .PARAMETER Name
	        Specifies, name of the service(s) which needs to be deleted.       
        .EXAMPLE
	        Delete-Service -Name "GoWebApiSrv","AdobeARMservice"
        .NOTES
        .LINK
	        http://www.volkswagen-group.com
        #>
  
[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string[]]$Name
	)
	Begin {
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process {
       Foreach($Names in $Name)
       {
		 Try {                
			    If(Get-Service -Name $Names -ErrorAction SilentlyContinue)
                {
				    Write-ADTLogEntry -Message "Removing the Service [$Names]." -Source ${CmdletName} -Severity 2				    			          

                    ##Deleting the Service
                    #Stopping service                   
                    Stop-Service -Name "$Names"
                    Start-Sleep -Seconds 5

                    #Removing service
                    Start-ADTProcess -FilePath "sc.exe" -ArgumentList "delete `"$Names`"" -WindowStyle 'Hidden'
                    Start-Sleep -Seconds 5

                    Write-ADTLogEntry -Message "Service [$Names] deleted successfully." -Source ${CmdletName} -Severity 2
                 }	
                 else
                 {
                    Write-ADTLogEntry -Message "Service [$Names] does not exist on the build." -Source ${CmdletName} -Severity 2
                 }				
            }
		 Catch {
			     Write-ADTLogEntry -Message "Unable to delete the Service [$Names]. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Source ${CmdletName} -Severity 3
               }
		}
    }        
     	End {
		Complete-ADTFunction -Cmdlet $PSCmdlet
	 }
     }       
     #endregion

#region Function Create-Service
Function Create-Service {
           <#
        .SYNOPSIS
	        Create Service if not exist.
        .DESCRIPTION
	        Creating New Service if does not exist.
        .PARAMETER Name
	        Specifies, Name of the service which needs to be created.
        .PARAMETER TargetPath
	        Specifies, the Path of executable for service creation.
        .PARAMETER DisplayName
	        Specifies, Display Name of Service which will be made visible in services.msc.
        .PARAMETER Description 
	        Specifies, Description of the service.
        .PARAMETER StartupType 
	        Specifies, StartupType of service [Automatic, Automatic (delayed Start), Manual, Disabled]
        .EXAMPLE
	        Create-Service -Name "GoWebApiSrv" -TargetPath "$envProgramFilesX86\GoDEX\Web Print\WebApiSrv.exe" -DisplayName "GoWebApiService" -Description "GoWebApiService Testing" -StartupType Automatic
        .NOTES
        .LINK
	        http://www.volkswagen-group.com
        #>
  
[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$true,Position=0,HelpMessage="Name of the Service to be created")]
		[ValidateNotNullOrEmpty()]
		[string]$Name,
		[Parameter(Mandatory=$true,HelpMessage="Provide Target Path of Service")]
		[ValidateNotNullOrEmpty()]
		[string]$TargetPath,
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]$DisplayName,
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$Description,
		[Parameter(Mandatory=$true)]
		[ValidateSet('Automatic', 'Disabled', 'Manual', 'AutomaticDelayedStart')]
		[string]$StartupType
	)
	Begin {
        # Initalize function and get required objects.
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	}
	Process {
		Try {               
			    If(!(Get-Service -Name $Name -ErrorAction SilentlyContinue))
                {
                    Write-ADTLogEntry -Message "Service [$Name] does not exist." -Source ${CmdletName} -Severity 2
                    
                    ##Creating Service                    
                    New-Service -Name "$Name" -BinaryPathName `"$TargetPath`" -DisplayName "$DisplayName" -Description "$Description" -StartupType $StartupType
                    Start-Sleep -Seconds 10
                    Write-ADTLogEntry -Message "Service [$Name] created successfully." -Source ${CmdletName} -Severity 2
                 }	
                 else
                 {  
                   Write-ADTLogEntry -Message "Service [$Name] already exist on the build." -Source ${CmdletName} -Severity 2
                 }			
            }
		Catch {
               Write-ADTLogEntry -Message "Unable to create the Service [$Name]. `n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Source ${CmdletName} -Severity 3
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
