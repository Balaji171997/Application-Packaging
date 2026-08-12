<#
Copyright (c) Microsoft Corporation. All rights reserved.
#>

Set-StrictMode -Version Latest

# AppMan
Set-Alias -Scope Global -Name New-CMAppCatalog -Value New-CMApplicationDisplayInfo

# Alternative Add-CM*DeploymentType alias shortcuts
Set-Alias -Scope Global -Name Add-CMWindowsPhone8DeploymentType -Value Add-CMWindowsPhoneDeploymentType
Set-Alias -Scope Global -Name Add-CMWindowsPhone8DeeplinkDeploymentType -Value Add-CMWindowsPhoneStoreDeploymentType
Set-Alias -Scope Global -Name Add-CMWindowsPhone8StoreDeploymentType -Value Add-CMWindowsPhoneStoreDeploymentType
Set-Alias -Scope Global -Name Add-CMWindowsStoreDeeplinkDeploymentType -Value Add-CMWindowsStoreDeploymentType
Set-Alias -Scope Global -Name Add-CMAppxDeploymentType -Value Add-CMWindowsAppxDeploymentType
Set-Alias -Scope Global -Name Add-CMMsixDeploymentType -Value Add-CMWindowsAppxDeploymentType
Set-Alias -Scope Global -Name Add-CMWindowsMsixDeploymentType -Value Add-CMWindowsAppxDeploymentType
Set-Alias -Scope Global -Name Add-CMXapDeploymentType -Value Add-CMWindowsPhoneDeploymentType

# Alternative Set-CM*DeploymentType alias shortcuts
Set-Alias -Scope Global -Name Set-CMWindowsPhone8DeploymentType -Value Set-CMWindowsPhoneDeploymentType
Set-Alias -Scope Global -Name Set-CMWindowsPhone8DeeplinkDeploymentType -Value Set-CMWindowsPhoneStoreDeploymentType
Set-Alias -Scope Global -Name Set-CMWindowsPhone8StoreDeploymentType -Value Set-CMWindowsPhoneStoreDeploymentType
Set-Alias -Scope Global -Name Set-CMWindowsDeeplinkDeploymentType -Value Set-CMWindowsStoreDeploymentType
Set-Alias -Scope Global -Name Set-CMAppxDeploymentType -Value Set-CMWindowsAppxDeploymentType
Set-Alias -Scope Global -Name Set-CMMsixDeploymentType -Value Set-CMWindowsAppxDeploymentType
Set-Alias -Scope Global -Name Set-CMWindowsMsixDeploymentType -Value Set-CMWindowsAppxDeploymentType
Set-Alias -Scope Global -Name Set-CMXapDeploymentType -Value Set-CMWindowsPhoneDeploymentType

# Alternative Convert/ConvertTo-CMApplication alias shortcuts
Set-Alias -Scope Global -Name Convert-CMApplicationGroup -Value Convert-CMApplication
Set-Alias -Scope Global -Name ConvertTo-CMApplicationGroup -Value ConvertTo-CMApplication

# For consistency, have shortcuts for all current supported DTs to Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMAppleAppStoreDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMAppvDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMAppv5XDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMGooglePlayDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMIosAppStoreDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMIosDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMMacDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMMobileMsiDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMMsiDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMScriptDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMWebApplicationDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMWindowsAppxDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMWindowsPhoneDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMWindowsPhoneStoreDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMWindowsStoreDeploymentType -Value Remove-CMDeploymentType
Set-Alias -Scope Global -Name Remove-CMIosDeepLinkDeploymentType -Value Remove-CMIosAppStoreDeploymentType
Set-Alias -Scope Global -Name Remove-CMWindowsPhone8DeploymentType -Value Remove-CMWindowsPhoneDeploymentType
Set-Alias -Scope Global -Name Remove-CMWindowsPhone8DeeplinkDeploymentType -Value Remove-CMWindowsPhoneStoreDeploymentType
Set-Alias -Scope Global -Name Remove-CMWindowsPhone8StoreDeploymentType -Value Remove-CMWindowsPhoneStoreDeploymentType
Set-Alias -Scope Global -Name Remove-CMWindowsStoreDeeplinkDeploymentType -Value Remove-CMWindowsStoreDeploymentType
Set-Alias -Scope Global -Name Remove-CMAppxDeploymentType -Value Remove-CMWindowsAppxDeploymentType
Set-Alias -Scope Global -Name Remove-CMMsixDeploymentType -Value Remove-CMWindowsAppxDeploymentType
Set-Alias -Scope Global -Name Remove-CMWindowsMsixDeploymentType -Value Remove-CMWindowsAppxDeploymentType
Set-Alias -Scope Global -Name Remove-CMApkDeploymentType -Value Remove-CMAndroidDeploymentType
Set-Alias -Scope Global -Name Remove-CMXapDeploymentType -Value Remove-CMWindowsPhoneDeploymentType
Set-Alias -Scope Global -Name Remove-CMIpaDeploymentType -Value Remove-CMIosDeploymentType

# ClientOperations
Set-Alias -Scope Global -Name Get-CMClientOperations -Value Get-CMClientOperation

# Collections
Set-Alias -Scope Global -Name Export-CMDeviceCollection -Value Export-CMCollection
Set-Alias -Scope Global -Name Export-CMUserCollection -Value Export-CMCollection
Set-Alias -Scope Global -Name Import-CMDeviceCollection -Value Import-CMCollection
Set-Alias -Scope Global -Name Import-CMUserCollection -Value Import-CMCollection
Set-Alias -Scope Global -Name Set-CMUserCollection -Value Set-CMCollection
Set-Alias -Scope Global -Name Set-CMDeviceCollection -Value Set-CMCollection
Set-Alias -Scope Global -Name Remove-CMUserCollection -Value Remove-CMCollection
Set-Alias -Scope Global -Name Remove-CMDeviceCollection -Value Remove-CMCollection
Set-Alias -Scope Global -Name Remove-CMCollectionMember -Value Remove-CMResource
Set-Alias -Scope Global -Name Invoke-CMUserCollectionUpdate -Value Invoke-CMCollectionUpdate
Set-Alias -Scope Global -Name Invoke-CMDeviceCollectionUpdate -Value Invoke-CMCollectionUpdate
Set-Alias -Scope Global -Name Invoke-CMEndpointProtectionDefinitionDownload -Value Save-CMEndpointProtectionDefinition
Set-Alias -Scope Global -Name Invoke-CMClientNotification -Value Invoke-CMClientAction

# Object
Set-Alias -Scope Global -Name Disconnect-CMObject -Value Disconnect-CMTrackedObject

# Wrapper functions
function Get-CMUserCollection {
    [CmdletBinding(DefaultParameterSetName = "ByName")]
    param(
        [Parameter(ParameterSetName = "ByName")]
        [ValidateNotNullOrEmpty()]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(ParameterSetName = "ById", Mandatory = $true)]
        [Alias("CollectionId")]
        [string]$Id,

        [Parameter(ParameterSetName = "ByDPGroupName", Mandatory = $true)]
        [string]$DistributionPointGroupName,

        [Parameter(ParameterSetName = "ByDPGroupId", Mandatory = $true)]
        [string]$DistributionPointGroupId,

        [Parameter(ParameterSetName = "ByDPGroup", Mandatory = $true)]
        [PSTypeName("IResultObject#SMS_DistributionPointGroup")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$DistributionPointGroup
    )

    process{
        Get-CMCollection -CollectionType User @PSBoundParameters
    }
}

function Get-CMDeviceCollection {
    [CmdletBinding(DefaultParameterSetName = "ByName")]
    param(
        [Parameter(ParameterSetName = "ByName")]
        [ValidateNotNullOrEmpty()]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(ParameterSetName = "ById", Mandatory = $true)]
        [Alias("CollectionId")]
        [string]$Id,

        [Parameter(ParameterSetName = "ByDPGroupName", Mandatory = $true)]
        [string]$DistributionPointGroupName,

        [Parameter(ParameterSetName = "ByDPGroupId", Mandatory = $true)]
        [string]$DistributionPointGroupId,

        [Parameter(ParameterSetName = "ByDPGroup", Mandatory = $true)]
        [PSTypeName("IResultObject#SMS_DistributionPointGroup")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$DistributionPointGroup
    )

    process{
        Get-CMCollection -CollectionType Device @PSBoundParameters
    }
}

function New-CMDeviceCollection {
    [CmdletBinding(DefaultParameterSetName = "ByName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter()]
        [string]$Comment,

        [Parameter(ParameterSetName = "ByValue", Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("LimitingCollection")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(ParameterSetName = "ById", Mandatory = $true)]
        [string]$LimitingCollectionId,

        [Parameter(ParameterSetName = "ByName", Mandatory = $true)]
        [string]$LimitingCollectionName,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [PSTypeName("IResultObject#SMS_ScheduleToken")]
        [ValidateNotNullOrEmpty()]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$RefreshSchedule,

        [Parameter()]
        [Microsoft.ConfigurationManagement.ManagementProvider.CollectionRefreshType]$RefreshType
    )

    process {
        New-CMCollection -CollectionType Device @PSBoundParameters
    }
}

function New-CMUserCollection {
    [CmdletBinding(DefaultParameterSetName = "ByName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter()]
        [string]$Comment,

        [Parameter(ParameterSetName = "ByValue", Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("LimitingCollection")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(ParameterSetName = "ById", Mandatory = $true)]
        [string]$LimitingCollectionId,

        [Parameter(ParameterSetName = "ByName", Mandatory = $true)]
        [string]$LimitingCollectionName,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [PSTypeName("IResultObject#SMS_ScheduleToken")]
        [ValidateNotNullOrEmpty()]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$RefreshSchedule,

        [Parameter()]
        [Microsoft.ConfigurationManagement.ManagementProvider.CollectionRefreshType]$RefreshType
    )

    process {
        New-CMCollection -CollectionType User @PSBoundParameters
    }
}

function Add-CMDeviceCollectionExcludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName")]
        [string]$ExcludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$ExcludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$ExcludeCollection,

        [Parameter()]
        [switch]$PassThru
    )

    process {
        $ruleClassName = "SMS_CollectionRuleExcludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("ExcludeCollectionName")) {
            $searchCriteria.Add("Name", $ExcludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("ExcludeCollectionId")) {
            $searchCriteria.Add("CollectionID", $ExcludeCollectionId)
        } elseif ($ExcludeCollection -ne $null) {
            $searchCriteria.Add("CollectionID", $ExcludeCollection["CollectionID"].StringValue)
        }

        Add-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType Device -RulePropertyName "ExcludeCollectionID" @PSBoundParameters
    }
}

function Add-CMDeviceCollectionIncludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName")]
        [string]$IncludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$IncludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$IncludeCollection,

        [Parameter()]
        [switch]$PassThru
    )

    process {
        $ruleClassName = "SMS_CollectionRuleIncludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionName")) {
            $searchCriteria.Add("Name", $IncludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionId")) {
            $searchCriteria.Add("CollectionID", $IncludeCollectionId)
        } elseif ($IncludeCollection -ne $null) {
            $searchCriteria.Add("CollectionID", $IncludeCollection["CollectionID"].StringValue)
        }

        Add-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType Device -RulePropertyName "IncludeCollectionID" @PSBoundParameters
    }
}

function Add-CMUserCollectionExcludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName")]
        [string]$ExcludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$ExcludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$ExcludeCollection,

        [Parameter()]
        [switch]$PassThru
    )

    process {
        $ruleClassName = "SMS_CollectionRuleExcludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("excludeCollectionName")) {
            $searchCriteria.Add("Name", $ExcludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("excludeCollectionId")) {
            $searchCriteria.Add("CollectionID", $ExcludeCollectionId)
        } elseif ($ExcludeCollection -ne $null) {
            $searchCriteria.Add("CollectionID", $ExcludeCollection["CollectionID"].StringValue)
        }

        Add-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType User -RulePropertyName "ExcludeCollectionID" @PSBoundParameters
    }
}

function Add-CMUserCollectionIncludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName")]
        [string]$IncludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$IncludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$IncludeCollection,

        [Parameter()]
        [switch]$PassThru
    )

    process {
        $ruleClassName = "SMS_CollectionRuleIncludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($PSBoundParameters.ContainsKey("IncludeCollectionName")) {
            $searchCriteria.Add("Name", $IncludeCollectionName)
        } elseif ($PSBoundParameters.ContainsKey("IncludeCollectionId")) {
            $searchCriteria.Add("CollectionID", $IncludeCollectionId)
        } elseif ($IncludeCollection -ne $null) {
            $searchCriteria.Add("CollectionID", $IncludeCollection["CollectionID"].StringValue)
        }

        Add-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType User -RulePropertyName "IncludeCollectionID" @PSBoundParameters
    }
}

function Get-CMCollectionDirectMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(ParameterSetName = "ByNameAndName")]
        [Parameter(ParameterSetName = "ByIdAndName")]
        [Parameter(ParameterSetName = "ByValueAndName")]
        [SupportsWildcards()]
        [string]$ResourceName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$ResourceId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [Microsoft.ConfigurationManagement.PowerShell.Framework.PSTypeNamesAttribute("IResultObject#SMS_Resource", "IResultObject#SMS_CombinedResources")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$Resource
    )

    process {
        $ruleClassName = "SMS_CollectionRuleDirect"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("ResourceName")) {
            $searchCriteria.Add("RuleName", $ResourceName, $true)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("ResourceId")) {
            $searchCriteria.Add("ResourceId", $ResourceId)
        } elseif ($Resource -ne $null) {
            $searchCriteria.Add("ResourceId", $Resource["ResourceID"].StringValue)
        }

        Get-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName @PSBoundParameters
    }
}

function Get-CMCollectionExcludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(ParameterSetName = "ByNameAndName")]
        [Parameter(ParameterSetName = "ByIdAndName")]
        [Parameter(ParameterSetName = "ByValueAndName")]
        [string]$ExcludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$ExcludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$ExcludeCollection
    )

    process {
        $ruleClassName = "SMS_CollectionRuleExcludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("ExcludeCollectionName")) {
            $searchCriteria.Add("RuleName", $ExcludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("ExcludeCollectionId")) {
            $searchCriteria.Add("ExcludeCollectionID", $ExcludeCollectionId)
        } elseif ($ExcludeCollection -ne $null) {
            $searchCriteria.Add("ExcludeCollectionID", $ExcludeCollection["CollectionID"].StringValue)
        }

        Get-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName @PSBoundParameters
    }
}

function Get-CMCollectionIncludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(ParameterSetName = "ByNameAndName")]
        [Parameter(ParameterSetName = "ByIdAndName")]
        [Parameter(ParameterSetName = "ByValueAndName")]
        [string]$IncludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$IncludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$IncludeCollection
    )

    process {
        $ruleClassName = "SMS_CollectionRuleIncludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionName")) {
            $searchCriteria.Add("RuleName", $IncludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionId")) {
            $searchCriteria.Add("IncludeCollectionID", $IncludeCollectionId)
        } elseif ($IncludeCollection -ne $null) {
            $searchCriteria.Add("IncludeCollectionID", $IncludeCollection["CollectionID"].StringValue)
        }

        Get-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName @PSBoundParameters
    }
}

function Get-CMCollectionQueryMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByName", SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByName")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ById")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter()]
        [string]$RuleName
    )

    process {
        $ruleClassName = "SMS_CollectionRuleQuery"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("RuleName")) {
            $searchCriteria.Add("RuleName", $RuleName)
        }

        Get-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName @PSBoundParameters
    }
}

function Get-CMDeviceCollectionDirectMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(ParameterSetName = "ByNameAndName")]
        [Parameter(ParameterSetName = "ByIdAndName")]
        [Parameter(ParameterSetName = "ByValueAndName")]
        [SupportsWildcards()]
        [string]$ResourceName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$ResourceId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [Microsoft.ConfigurationManagement.PowerShell.Framework.PSTypeNamesAttribute("IResultObject#SMS_Resource", "IResultObject#SMS_CombinedResources")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$Resource
    )

    process {
        $ruleClassName = "SMS_CollectionRuleDirect"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("ResourceName")) {
            $searchCriteria.Add("RuleName", $ResourceName, $true)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("ResourceId")) {
            $searchCriteria.Add("ResourceId", $ResourceId)
        } elseif ($Resource -ne $null) {
            $searchCriteria.Add("ResourceId", $Resource["ResourceID"].StringValue)
        }

        Get-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType Device @PSBoundParameters
    }
}

function Get-CMDeviceCollectionExcludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(ParameterSetName = "ByNameAndName")]
        [Parameter(ParameterSetName = "ByIdAndName")]
        [Parameter(ParameterSetName = "ByValueAndName")]
        [string]$ExcludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$ExcludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$ExcludeCollection
    )

    process {
        $ruleClassName = "SMS_CollectionRuleExcludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("ExcludeCollectionName")) {
            $searchCriteria.Add("RuleName", $ExcludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("ExcludeCollectionId")) {
            $searchCriteria.Add("ExcludeCollectionID", $ExcludeCollectionId)
        } elseif ($ExcludeCollection -ne $null) {
            $searchCriteria.Add("ExcludeCollectionID", $ExcludeCollection["CollectionID"].StringValue)
        }

        Get-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType Device @PSBoundParameters
    }
}

function Get-CMDeviceCollectionIncludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(ParameterSetName = "ByNameAndName")]
        [Parameter(ParameterSetName = "ByIdAndName")]
        [Parameter(ParameterSetName = "ByValueAndName")]
        [string]$IncludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$IncludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$IncludeCollection
    )

    process {
        $ruleClassName = "SMS_CollectionRuleIncludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionName")) {
            $searchCriteria.Add("RuleName", $IncludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionId")) {
            $searchCriteria.Add("IncludeCollectionID", $IncludeCollectionId)
        } elseif ($IncludeCollection -ne $null) {
            $searchCriteria.Add("IncludeCollectionID", $IncludeCollection["CollectionID"].StringValue)
        }

        Get-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType Device @PSBoundParameters
    }
}

function Get-CMDeviceCollectionQueryMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByName", SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByName")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ById")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter()]
        [string]$RuleName
    )

    process {
        $ruleClassName = "SMS_CollectionRuleQuery"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("RuleName")) {
            $searchCriteria.Add("RuleName", $RuleName)
        }

        Get-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType Device @PSBoundParameters
    }
}

function Get-CMUserCollectionDirectMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(ParameterSetName = "ByNameAndName")]
        [Parameter(ParameterSetName = "ByIdAndName")]
        [Parameter(ParameterSetName = "ByValueAndName")]
        [SupportsWildcards()]
        [string]$ResourceName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$ResourceId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [Microsoft.ConfigurationManagement.PowerShell.Framework.PSTypeNamesAttribute("IResultObject#SMS_Resource", "IResultObject#SMS_CombinedResources")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$Resource
    )

    process {
        $ruleClassName = "SMS_CollectionRuleDirect"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("ResourceName")) {
            $searchCriteria.Add("RuleName", $ResourceName, $true)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("ResourceId")) {
            $searchCriteria.Add("ResourceId", $ResourceId)
        } elseif ($Resource -ne $null) {
            $searchCriteria.Add("ResourceId", $Resource["ResourceID"].StringValue)
        }

        Get-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType User @PSBoundParameters
    }
}

function Get-CMUserCollectionExcludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(ParameterSetName = "ByNameAndName")]
        [Parameter(ParameterSetName = "ByIdAndName")]
        [Parameter(ParameterSetName = "ByValueAndName")]
        [string]$ExcludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$ExcludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$ExcludeCollection
    )

    process {
        $ruleClassName = "SMS_CollectionRuleExcludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("ExcludeCollectionName")) {
            $searchCriteria.Add("RuleName", $ExcludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("ExcludeCollectionId")) {
            $searchCriteria.Add("ExcludeCollectionID", $ExcludeCollectionId)
        } elseif ($ExcludeCollection -ne $null) {
            $searchCriteria.Add("ExcludeCollectionID", $ExcludeCollection["CollectionID"].StringValue)
        }

        Get-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType User @PSBoundParameters
    }
}

function Get-CMUserCollectionIncludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(ParameterSetName = "ByNameAndName")]
        [Parameter(ParameterSetName = "ByIdAndName")]
        [Parameter(ParameterSetName = "ByValueAndName")]
        [string]$IncludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$IncludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$IncludeCollection
    )

    process {
        $ruleClassName = "SMS_CollectionRuleIncludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionName")) {
            $searchCriteria.Add("RuleName", $IncludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionId")) {
            $searchCriteria.Add("IncludeCollectionID", $IncludeCollectionId)
        } elseif ($IncludeCollection -ne $null) {
            $searchCriteria.Add("IncludeCollectionID", $IncludeCollection["CollectionID"].StringValue)
        }

        Get-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType User @PSBoundParameters
    }
}

function Get-CMUserCollectionQueryMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByName", SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByName")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ById")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter()]
        [string]$RuleName
    )

    process {
        $ruleClassName = "SMS_CollectionRuleQuery"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("RuleName")) {
            $searchCriteria.Add("RuleName", $RuleName)
        }

        Get-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType User @PSBoundParameters
    }
}

function Remove-CMCollectionDirectMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName")]
        [SupportsWildcards()]
        [Alias("ResourceNames")]
        [string[]]$ResourceName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [Alias("ResourceIds")]
        [string[]]$ResourceId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [Microsoft.ConfigurationManagement.PowerShell.Framework.PSTypeNamesAttribute("IResultObject#SMS_Resource", "IResultObject#SMS_CombinedResources")]
        [Alias("Resources")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject[]]$Resource,

        [Parameter()]
        [switch]$Force
    )

    process {
        $ruleClassName = "SMS_CollectionRuleDirect"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("ResourceName")) {
            $searchCriteria.Add("RuleName", $ResourceName, $true)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("ResourceId")) {
            $searchCriteria.Add("ResourceId", $ResourceId)
        } elseif ($Resource -ne $null) {
            $resList = @()
            foreach ($res in $Resource)
            {
                $resList += $res["ResourceID"].StringValue
            }
            $searchCriteria.Add("ResourceId", $resList)
        }

        Remove-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName @PSBoundParameters
    }
}

function Remove-CMCollectionExcludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName")]
        [string]$ExcludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$ExcludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$ExcludeCollection,

        [Parameter()]
        [switch]$Force
    )

    process {
        $ruleClassName = "SMS_CollectionRuleExcludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("ExcludeCollectionName")) {
            $searchCriteria.Add("RuleName", $ExcludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("ExcludeCollectionId")) {
            $searchCriteria.Add("ExcludeCollectionID", $ExcludeCollectionId)
        } elseif ($ExcludeCollection -ne $null) {
            $searchCriteria.Add("ExcludeCollectionID", $ExcludeCollection["CollectionID"].StringValue)
        }

        Remove-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName @PSBoundParameters
    }
}

function Remove-CMCollectionIncludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName")]
        [string]$IncludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$IncludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$IncludeCollection,

        [Parameter()]
        [switch]$Force
    )

    process {
        $ruleClassName = "SMS_CollectionRuleIncludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionName")) {
            $searchCriteria.Add("RuleName", $IncludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionId")) {
            $searchCriteria.Add("IncludeCollectionID", $IncludeCollectionId)
        } elseif ($IncludeCollection -ne $null) {
            $searchCriteria.Add("IncludeCollectionID", $IncludeCollection["CollectionID"].StringValue)
        }

        Remove-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName @PSBoundParameters
    }
}

function Remove-CMCollectionQueryMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByValue", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByName")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ById")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$RuleName,

        [Parameter()]
        [switch]$Force
    )

    process {
        $ruleClassName = "SMS_CollectionRuleQuery"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("RuleName")) {
            $searchCriteria.Add("RuleName", $RuleName)
        }

        Remove-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName @PSBoundParameters
    }
}

function Remove-CMDeviceCollectionDirectMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName")]
        [SupportsWildcards()]
        [Alias("ResourceNames")]
        [string[]]$ResourceName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [Alias("ResourceIds")]
        [string[]]$ResourceId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [Microsoft.ConfigurationManagement.PowerShell.Framework.PSTypeNamesAttribute("IResultObject#SMS_Resource", "IResultObject#SMS_CombinedResources")]
        [Alias("Resources")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject[]]$Resource,

        [Parameter()]
        [switch]$Force
    )

    process {
        $ruleClassName = "SMS_CollectionRuleDirect"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("ResourceName")) {
            $searchCriteria.Add("RuleName", $ResourceName, $true)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("ResourceId")) {
            $searchCriteria.Add("ResourceId", $ResourceId)
        } elseif ($Resource -ne $null) {
            $resList = @()
            foreach ($res in $Resource)
            {
                $resList += $res["ResourceID"].StringValue
            }
            $searchCriteria.Add("ResourceId", $resList)
        }

        Remove-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType Device @PSBoundParameters
    }
}

function Remove-CMDeviceCollectionExcludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName")]
        [string]$ExcludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$ExcludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$ExcludeCollection,

        [Parameter()]
        [switch]$Force
    )

    process {
        $ruleClassName = "SMS_CollectionRuleExcludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("ExcludeCollectionName")) {
            $searchCriteria.Add("RuleName", $ExcludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("ExcludeCollectionId")) {
            $searchCriteria.Add("ExcludeCollectionID", $ExcludeCollectionId)
        } elseif ($ExcludeCollection -ne $null) {
            $searchCriteria.Add("ExcludeCollectionID", $ExcludeCollection["CollectionID"].StringValue)
        }

        Remove-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType Device @PSBoundParameters
    }
}

function Remove-CMDeviceCollectionIncludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName")]
        [string]$IncludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$IncludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$IncludeCollection,

        [Parameter()]
        [switch]$Force
    )

    process {
        $ruleClassName = "SMS_CollectionRuleIncludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionName")) {
            $searchCriteria.Add("RuleName", $IncludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionId")) {
            $searchCriteria.Add("IncludeCollectionID", $IncludeCollectionId)
        } elseif ($IncludeCollection -ne $null) {
            $searchCriteria.Add("IncludeCollectionID", $IncludeCollection["CollectionID"].StringValue)
        }

        Remove-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType Device @PSBoundParameters
    }
}

function Remove-CMDeviceCollectionQueryMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByValue", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByName")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ById")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$RuleName,

        [Parameter()]
        [switch]$Force
    )

    process {
        $ruleClassName = "SMS_CollectionRuleQuery"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("RuleName")) {
            $searchCriteria.Add("RuleName", $RuleName)
        }

        Remove-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType Device @PSBoundParameters
    }
}

function Remove-CMUserCollectionDirectMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName")]
        [SupportsWildcards()]
        [Alias("ResourceNames")]
        [string[]]$ResourceName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [Alias("ResourceIds")]
        [string[]]$ResourceId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [Microsoft.ConfigurationManagement.PowerShell.Framework.PSTypeNamesAttribute("IResultObject#SMS_Resource", "IResultObject#SMS_CombinedResources")]
        [Alias("Resources")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject[]]$Resource,

        [Parameter()]
        [switch]$Force
    )

    process {
        $ruleClassName = "SMS_CollectionRuleDirect"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("ResourceName")) {
            $searchCriteria.Add("RuleName", $ResourceName, $true)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("ResourceId")) {
            $searchCriteria.Add("ResourceId", $ResourceId)
        } elseif ($Resource -ne $null) {
            $resList = @()
            foreach ($res in $Resource)
            {
                $resList += $res["ResourceID"].StringValue
            }
            $searchCriteria.Add("ResourceId", $resList)
        }

        Remove-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType User @PSBoundParameters
    }
}

function Remove-CMUserCollectionExcludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName")]
        [string]$ExcludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$ExcludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$ExcludeCollection,

        [Parameter()]
        [switch]$Force
    )

    process {
        $ruleClassName = "SMS_CollectionRuleExcludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("excludeCollectionName")) {
            $searchCriteria.Add("RuleName", $ExcludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("excludeCollectionId")) {
            $searchCriteria.Add("ExcludeCollectionID", $ExcludeCollectionId)
        } elseif ($ExcludeCollection -ne $null) {
            $searchCriteria.Add("ExcludeCollectionID", $ExcludeCollection["CollectionID"].StringValue)
        }

        Remove-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType User @PSBoundParameters
    }
}

function Remove-CMUserCollectionIncludeMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByNameAndName", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId", ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndName")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndName")]
        [string]$IncludeCollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndId")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndId")]
        [string]$IncludeCollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByNameAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIdAndValue")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByValueAndValue")]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$IncludeCollection,

        [Parameter()]
        [switch]$Force
    )

    process {
        $ruleClassName = "SMS_CollectionRuleIncludeCollection"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionName")) {
            $searchCriteria.Add("RuleName", $IncludeCollectionName)
        } elseif ($MyInvocation.BoundParameters.ContainsKey("IncludeCollectionId")) {
            $searchCriteria.Add("IncludeCollectionID", $IncludeCollectionId)
        } elseif ($IncludeCollection -ne $null) {
            $searchCriteria.Add("IncludeCollectionID", $IncludeCollection["CollectionID"].StringValue)
        }

        Remove-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType User @PSBoundParameters
    }
}

function Remove-CMUserCollectionQueryMembershipRule {
    [CmdletBinding(DefaultParameterSetName = "ByValue", SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByName")]
        [Alias("Name")]
        [string]$CollectionName,

        [Parameter(Mandatory = $true, ParameterSetName = "ById")]
        [Alias("Id")]
        [string]$CollectionId,

        [Parameter(Mandatory = $true, ParameterSetName = "ByValue", ValueFromPipeline = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$RuleName,

        [Parameter()]
        [switch]$Force
    )

    process {
        $ruleClassName = "SMS_CollectionRuleQuery"
        $searchCriteria = New-Object -TypeName ([Microsoft.ConfigurationManagement.PowerShell.Provider.SmsProviderSearch])

        if($MyInvocation.BoundParameters.ContainsKey("RuleName")) {
            $searchCriteria.Add("RuleName", $RuleName)
        }

        Remove-CMCollectionMembershipRule -SearchCriteria $searchCriteria -RuleClassName $ruleClassName -CollectionType User @PSBoundParameters
    }
}

function Get-CMCollectionInfoFromFullEvaluationQueue {
    [CmdletBinding(DefaultParameterSetName = "ByName")]
    param(
        [Parameter(ParameterSetName = "ByName")]
        [Alias("CollectionName")]
        [string]$Name,

        [Parameter(ParameterSetName = "ById", Mandatory = $true)]
        [Alias("CollectionId")]
        [string]$Id,

        [Parameter(ParameterSetName = "ByValue", Mandatory = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject
    )

    process{
        Get-CMCollectionInfoFromEvaluationQueue -EvaluationTypeOption Full @PSBoundParameters
    }
}

function Get-CMCollectionInfoFromIncrementalEvaluationQueue {
    [CmdletBinding(DefaultParameterSetName = "ByName")]
    param(
        [Parameter(ParameterSetName = "ByName")]
        [Alias("CollectionName")]
        [string]$Name,

        [Parameter(ParameterSetName = "ById", Mandatory = $true)]
        [Alias("CollectionId")]
        [string]$Id,

        [Parameter(ParameterSetName = "ByValue", Mandatory = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject
    )

    process{
        Get-CMCollectionInfoFromEvaluationQueue -EvaluationTypeOption Incremental @PSBoundParameters
    }
}

function Get-CMCollectionInfoFromManualEvaluationQueue {
    [CmdletBinding(DefaultParameterSetName = "ByName")]
    param(
        [Parameter(ParameterSetName = "ByName")]
        [Alias("CollectionName")]
        [string]$Name,

        [Parameter(ParameterSetName = "ById", Mandatory = $true)]
        [Alias("CollectionId")]
        [string]$Id,

        [Parameter(ParameterSetName = "ByValue", Mandatory = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject
    )

    process{
        Get-CMCollectionInfoFromEvaluationQueue -EvaluationTypeOption Manual @PSBoundParameters
    }
}

function Get-CMCollectionInfoFromNewEvaluationQueue {
    [CmdletBinding(DefaultParameterSetName = "ByName")]
    param(
        [Parameter(ParameterSetName = "ByName")]
        [Alias("CollectionName")]
        [string]$Name,

        [Parameter(ParameterSetName = "ById", Mandatory = $true)]
        [Alias("CollectionId")]
        [string]$Id,

        [Parameter(ParameterSetName = "ByValue", Mandatory = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject
    )

    process{
        Get-CMCollectionInfoFromEvaluationQueue -EvaluationTypeOption New @PSBoundParameters
    }
}

function Get-CMCollectionFullEvaluationStatus {
    [CmdletBinding(DefaultParameterSetName = "ByName")]
    param(
        [Parameter(ParameterSetName = "ByName")]
        [Alias("CollectionName")]
        [string]$Name,

        [Parameter(ParameterSetName = "ById", Mandatory = $true)]
        [Alias("CollectionId")]
        [string]$Id,

        [Parameter(ParameterSetName = "ByValue", Mandatory = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter()]
        [bool]$IsMemberChanged
    )

    process{
        Get-CMCollectionEvaluationStatus -EvaluationTypeOption Full @PSBoundParameters
    }
}

function Get-CMCollectionIncrementalEvaluationStatus {
    [CmdletBinding(DefaultParameterSetName = "ByName")]
    param(
        [Parameter(ParameterSetName = "ByName")]
        [Alias("CollectionName")]
        [string]$Name,

        [Parameter(ParameterSetName = "ById", Mandatory = $true)]
        [Alias("CollectionId")]
        [string]$Id,

        [Parameter(ParameterSetName = "ByValue", Mandatory = $true)]
        [PSTypeName("IResultObject#SMS_Collection")]
        [Alias("Collection")]
        [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,

        [Parameter()]
        [bool]$IsMemberChanged
    )

    process{
        Get-CMCollectionEvaluationStatus -EvaluationTypeOption Incremental @PSBoundParameters
    }
}

# Content
Set-Alias -Scope Global -Name Add-CMDeviceCollectionToDistributionPointGroup -Value Add-CMCollectionToDistributionPointGroup
Set-Alias -Scope Global -Name Add-CMUserCollectionToDistributionPointGroup -Value Add-CMCollectionToDistributionPointGroup
Set-Alias -Scope Global -Name Remove-CMDeviceCollectionFromDistributionPointGroup -Value Remove-CMCollectionFromDistributionPointGroup
Set-Alias -Scope Global -Name Remove-CMUserCollectionFromDistributionPointGroup -Value Remove-CMCollectionFromDistributionPointGroup

# DCM
# Wrapper function to shim XML definition cmdlets
function Get-CMConfigurationPolicyXml {
    [CmdletBinding(DefaultParameterSetName="ByName", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_ConfigurationPolicy")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][string]$CategoryInstanceType
    )

    process {
        Get-CMConfigurationPolicy -AsXml @PsBoundParameters
    }
}

function Get-CMTermsAndConditionsConfigurationItem {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance "SettingsAndPolicy:SMS_TermsAndConditionsSettings"
    }
}

function Get-CMWindowsEditionUpgradeConfigurationItem {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance "SettingsAndPolicy:SMS_EditionUpgradeSettings"
    }
}

function Get-CMCertificateProfileScep {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance ("SettingsAndPolicy:SMS_ClientAuthCertificateSettings")
    }
}

function Get-CMCertificateProfilePfx {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance ("SettingsAndPolicy:SMS_PfxCertificateSettings")
    }
}

function Get-CMCertificateProfileTrustedRootCA {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance ("SettingsAndPolicy:SMS_TrustedRootCertificateSettings")
    }
}

function Get-CMClientCertificateProfileConfigurationItem {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance ("SettingsAndPolicy:SMS_ClientAuthCertificateSettings", "SettingsAndPolicy:SMS_TrustedRootCertificateSettings")
    }
}

function Get-CMRemoteConnectionProfileConfigurationItem {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance "SettingsAndPolicy:SMS_RemoteConnectionSettings"
    }
}

function Get-CMUserDataAndProfileConfigurationItem {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance "SettingsAndPolicy:SMS_UserStateManagementSettings"
    }
}

function Get-CMVpnProfileConfigurationItem {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance "SettingsAndPolicy:SMS_VpnConnectionSettings"
    }
}

function Get-CMWirelessProfileConfigurationItem {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance "SettingsAndPolicy:SMS_WirelessProfileSettings"
    }
}

function Get-CMWindowsFirewallPolicy {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance "SettingsAndPolicy:SMS_FirewallSettings"
    }
}

function Get-CMEmailProfile {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance "SettingsAndPolicy:SMS_CommunicationsProvisioningSettings"
    }
}

function Get-CMWirelessProfile {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance "SettingsAndPolicy:SMS_WirelessProfileSettings"
    }
}

function Get-CMAdvancedThreatProtectionPolicy {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance "SettingsAndPolicy:SMS_AdvancedThreatProtectionSettings"
    }
}

function Get-CMMicrosoftEdgeBrowserProfiles{
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process{
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance "SettingsAndPolicy:SMS_EdgeBrowserSettings"
    }
}

function Get-CMOneDriveBusinessProfile {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][Alias("CIId", "CI_ID")][int]$Id,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
    )

    process {
        Get-CMConfigurationPolicy @PsBoundParameters -CategoryInstance "SettingsAndPolicy:SMS_OneDriveKnownFolderMigrationSettings"
    }
}

# Shim out these cmdlets to Get-CMConfigurationPolicy
Set-Alias -Scope Global -Name Get-CMRemoteConnectionProfileConfigurationItemXmlDefinition -Value Get-CMConfigurationPolicyXml
Set-Alias -Scope Global -Name Get-CMUserDataAndProfileConfigurationItemXmlDefinition -Value Get-CMConfigurationPolicyXml

# Cmdlet aliases
Set-Alias -Scope Global -Name Copy-CMRemoteConnectionProfileConfigurationItem -Value Copy-CMConfigurationPolicy
Set-Alias -Scope Global -Name Copy-CMUserDataAndProfileConfigurationItem -Value Copy-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMClientCertificateProfileConfigurationItem -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMClientAuthCertificateProfileConfigurationItem -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMRemoteConnectionProfileConfigurationItem -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMRootCertificateProfileConfigurationItem -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMTrustedRootCertificateProfileConfigurationItem -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMUserDataAndProfileConfigurationItem -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMVpnProfileConfigurationItem -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMWirelessProfileConfigurationItem -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMWindowsFirewallPolicy -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMCertificateProfileScep -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMCertificateProfileTrustedRootCA -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMCertificateProfilePfx -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMEmailProfile -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMWirelessProfile -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMAdvancedThreatProtectionPolicy -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMMicrosoftEdgeBrowserProfiles -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Remove-CMOneDriveBusinessProfile -Value Remove-CMConfigurationPolicy
Set-Alias -Scope Global -Name Get-CMTrustedRootCertificateProfileConfigurationItem -Value Get-CMClientCertificateProfileConfigurationItem
Set-Alias -Scope Global -Name Get-CMSupportedPlatforms -Value Get-CMSupportedPlatform
Set-Alias -Scope Global -Name Get-CMClientAuthCertificateProfileConfigurationItem -Value Get-CMClientCertificateProfileConfigurationItem
Set-Alias -Scope Global -Name Get-CMRootCertificateProfileConfigurationItem -Value Get-CMClientCertificateProfileConfigurationItem
Set-Alias -Scope Global -Name Get-CMWindows10EditionUpgrade -Value Get-CMWindowsEditionUpgradeConfigurationItem
Set-Alias -Scope Global -Name Set-CMWindowsEditionUpgradeConfigurationItem -Value Set-CMWindows10EditionUpgrade
Set-Alias -Scope Global -Name New-CMWindowsEditionUpgradeConfigurationItem -Value New-CMWindows10EditionUpgrade
Set-Alias -Scope Global -Name Remove-CMWindowsEditionUpgradeConfigurationItem -Value Remove-CMWindows10EditionUpgrade

Set-Alias -Scope Global -Name Add-CMConfigurationItemDetectionMethod -Value Add-CMCIDetectionMethod

# Deployments
Set-Alias -Name Get-CMDeploymentStatus -Value Get-CMPackageDeploymentStatus -Scope Global

# EP
Set-Alias -Scope Global -Name Unblock-CMThreat -Value Unblock-CMDetectedMalware

# HS
Set-Alias -Scope Global -Name New-CMExchangeServerConnectorAccessRule -Value New-CMExchangeConnectorAccessRule
Set-Alias -Scope Global -Name New-CMExchangeServerConnectorApplicationSetting -Value New-CMExchangeConnectorApplicationSetting
Set-Alias -Scope Global -Name New-CMExchangeServerConnectorEmailManagementSetting -Value New-CMExchangeConnectorEmailManagementSetting
Set-Alias -Scope Global -Name New-CMExchangeServerConnectorGeneralSetting -Value New-CMExchangeConnectorGeneralSetting
Set-Alias -Scope Global -Name New-CMExchangeServerConnectorPasswordSetting -Value New-CMExchangeConnectorPasswordSetting
Set-Alias -Scope Global -Name New-CMExchangeServerConnectorSecuritySetting -Value New-CMExchangeConnectorSecuritySetting
# Set-CMDistributionPointDataTransferRoute is same as Set-CMFileReplicationRoute, just use DP server FQDN as -DestinationSiteCode
Set-Alias -Name Set-CMDistributionPointDataTransferRoute -Value Set-CMFileReplicationRoute -Scope Global

# OSD
Set-Alias -Name New-CMOperatingSystemUpgradePackage -Value New-CMOperatingSystemInstaller -Scope Global
Set-Alias -Name Get-CMOperatingSystemUpgradePackage -Value Get-CMOperatingSystemInstaller -Scope Global
Set-Alias -Name Remove-CMOperatingSystemUpgradePackage -Value Remove-CMOperatingSystemInstaller -Scope Global

Set-Alias -Name New-CMPrestagedMedia -Value New-CMPrestageMedia -Scope Global

Set-Alias -Name Clear-CMOperatingSystemUpgradePackageUpdateSchedule -Value Clear-CMOperatingSystemUpgradeUpdateSchedule -Scope Global
Set-Alias -Name Get-CMOperatingSystemUpgradePackageUpdateSchedule -Value Get-CMOperatingSystemUpgradeUpdateSchedule -Scope Global
Set-Alias -Name New-CMOperatingSystemUpgradePackageUpdateSchedule -Value New-CMOperatingSystemUpgradeUpdateSchedule -Scope Global

Set-Alias -Name New-CMTaskSequenceRule -Value New-CMTSRule -Scope Global
Set-Alias -Name New-CMTaskSequenceNetworkAdapterSetting -Value New-CMTSNetworkAdapterSetting -Scope Global
Set-Alias -Name New-CMTaskSequencePartitionSetting -Value New-CMTSPartitionSetting -Scope Global

Set-Alias -Name New-CMTaskSequenceStepConditionFile -Value New-CMTSStepConditionFile -Scope Global
Set-Alias -Name New-CMTaskSequenceStepConditionFolder -Value New-CMTSStepConditionFolder -Scope Global
Set-Alias -Name New-CMTaskSequenceStepConditionIfStatement -Value New-CMTSStepConditionIfStatement -Scope Global
Set-Alias -Name New-CMTaskSequenceStepConditionOperatingSystem -Value New-CMTSStepConditionOperatingSystem -Scope Global
Set-Alias -Name New-CMTaskSequenceStepConditionQueryWMI -Value New-CMTSStepConditionQueryWMI -Scope Global
Set-Alias -Name New-CMTaskSequenceStepConditionOperatingSystemLanguage -Value New-CMTSStepConditionOperatingSystemLanguage -Scope Global
Set-Alias -Name New-CMTaskSequenceStepConditionRegistry -Value New-CMTSStepConditionRegistry -Scope Global
Set-Alias -Name New-CMTaskSequenceStepConditionSoftware -Value New-CMTSStepConditionSoftware -Scope Global
Set-Alias -Name New-CMTaskSequenceStepConditionVariable -Value New-CMTSStepConditionVariable -Scope Global

Set-Alias -Name Get-CMTaskSequenceStepConditionFile -Value Get-CMTSStepConditionFile -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepConditionFolder -Value Get-CMTSStepConditionFolder -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepConditionIfStatement -Value Get-CMTSStepConditionIfStatement -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepConditionOperatingSystem -Value Get-CMTSStepConditionOperatingSystem -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepConditionQueryWMI -Value Get-CMTSStepConditionQueryWMI -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepConditionRegistry -Value Get-CMTSStepConditionRegistry -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepConditionSoftware -Value Get-CMTSStepConditionSoftware -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepConditionVariable -Value Get-CMTSStepConditionVariable -Scope Global

Set-Alias -Name New-CMTaskSequenceStepPrepareConfigMgrClient -Value New-CMTSStepPrepareConfigMgrClient -Scope Global
Set-Alias -Name New-CMTaskSequenceStepRunTaskSequence -Value New-CMTSStepRunTaskSequence -Scope Global
Set-Alias -Name New-CMTaskSequenceStepCaptureSystemImage -Value New-CMTSStepCaptureWindowsSettings -Scope Global
Set-Alias -Name New-CMTaskSequenceStepCaptureWindowsSettings -Value New-CMTSStepCaptureWindowsSettings -Scope Global
Set-Alias -Name New-CMTaskSequenceStepCaptureNetworkSettings -Value New-CMTSStepCaptureNetworkSettings -Scope Global
Set-Alias -Name New-CMTaskSequenceStepCaptureUserState -Value New-CMTSStepCaptureUserState -Scope Global
Set-Alias -Name New-CMTaskSequenceStepRestoreUserState -Value New-CMTSStepRestoreUserState -Scope Global
Set-Alias -Name New-CMTaskSequenceStepDownloadPackageContent -Value New-CMTSStepDownloadPackageContent -Scope Global
Set-Alias -Name New-CMTaskSequenceStepApplyDataImage -Value New-CMTSStepApplyDataImage -Scope Global
Set-Alias -Name New-CMTaskSequenceStepUpgradeOperatingSystem -Value New-CMTSStepUpgradeOperatingSystem -Scope Global
Set-Alias -Name New-CMTaskSequenceStepPrepareWindows -Value New-CMTSStepPrepareWindows -Scope Global
Set-Alias -Name New-CMTaskSequenceStepReleaseStateStore -Value New-CMTSStepReleaseStateStore -Scope Global
Set-Alias -Name New-CMTaskSequenceStepRequestStateStore -Value New-CMTSStepRequestStateStore -Scope Global
Set-Alias -Name New-CMTaskSequenceStepPrestartCheck -Value New-CMTSStepPrestartCheck -Scope Global
Set-Alias -Name New-CMTaskSequenceStepJoinDomainWorkgroup -Value New-CMTSStepJoinDomainWorkgroup -Scope Global
Set-Alias -Name New-CMTaskSequenceStepOfflineEnableBitLocker -Value New-CMTSStepOfflineEnableBitLocker -Scope Global
Set-Alias -Name New-CMTaskSequenceStepDisableBitLocker -Value New-CMTSStepDisableBitLocker -Scope Global
Set-Alias -Name New-CMTaskSequenceStepEnableBitLocker -Value New-CMTSStepEnableBitLocker -Scope Global
Set-Alias -Name New-CMTaskSequenceStepConnectNetworkFolder -Value New-CMTSStepConnectNetworkFolder -Scope Global
Set-Alias -Name New-CMTaskSequenceStepAutoApplyDriver -Value New-CMTSStepAutoApplyDriver -Scope Global
Set-Alias -Name New-CMTaskSequenceStepApplyDriverPackage -Value New-CMTSStepApplyDriverPackage -Scope Global
Set-Alias -Name New-CMTaskSequenceStepApplyNetworkSetting -Value New-CMTSStepApplyNetworkSetting -Scope Global
Set-Alias -Name New-CMTaskSequenceStepApplyWindowsSetting -Value New-CMTSStepApplyWindowsSetting -Scope Global
Set-Alias -Name New-CMTaskSequenceStepApplyOperatingSystem -Value New-CMTSStepApplyOperatingSystem -Scope Global
Set-Alias -Name New-CMTaskSequenceStepInstallApplication -Value New-CMTSStepInstallApplication -Scope Global
Set-Alias -Name New-CMTaskSequenceStepInstallSoftware -Value New-CMTSStepInstallSoftware -Scope Global
Set-Alias -Name New-CMTaskSequenceStepInstallUpdate -Value New-CMTSStepInstallUpdate -Scope Global
Set-Alias -Name New-CMTaskSequenceStepPartitionDisk -Value New-CMTSStepPartitionDisk -Scope Global
Set-Alias -Name New-CMTaskSequenceStepReboot -Value New-CMTSStepReboot -Scope Global
Set-Alias -Name New-CMTaskSequenceStepRunCommandLine -Value New-CMTSStepRunCommandLine -Scope Global
Set-Alias -Name New-CMTaskSequenceStepRunPowerShellScript -Value New-CMTSStepRunPowerShellScript -Scope Global
Set-Alias -Name New-CMTaskSequenceStepSetupWindowsAndConfigMgr -Value New-CMTSStepSetupWindowsAndConfigMgr -Scope Global
Set-Alias -Name New-CMTaskSequenceStepSetVariable -Value New-CMTSStepSetVariable -Scope Global
Set-Alias -Name New-CMTaskSequenceStepSetDynamicVariable -Value New-CMTSStepSetDynamicVariable -Scope Global

Set-Alias -Name Set-CMTaskSequenceStepPrepareConfigMgrClient -Value Set-CMTSStepPrepareConfigMgrClient -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepRunTaskSequence -Value Set-CMTSStepRunTaskSequence -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepCaptureSystemImage -Value Set-CMTSStepCaptureWindowsSettings -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepCaptureWindowsSettings -Value Set-CMTSStepCaptureWindowsSettings -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepCaptureNetworkSettings -Value Set-CMTSStepCaptureNetworkSettings -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepCaptureUserState -Value Set-CMTSStepCaptureUserState -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepRestoreUserState -Value Set-CMTSStepRestoreUserState -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepDownloadPackageContent -Value Set-CMTSStepDownloadPackageContent -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepApplyDataImage -Value Set-CMTSStepApplyDataImage -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepUpgradeOperatingSystem -Value Set-CMTSStepUpgradeOperatingSystem -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepPrepareWindows -Value Set-CMTSStepPrepareWindows -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepReleaseStateStore -Value Set-CMTSStepReleaseStateStore -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepRequestStateStore -Value Set-CMTSStepRequestStateStore -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepPrestartCheck -Value Set-CMTSStepPrestartCheck -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepJoinDomainWorkgroup -Value Set-CMTSStepJoinDomainWorkgroup -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepOfflineEnableBitLocker -Value Set-CMTSStepOfflineEnableBitLocker -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepDisableBitLocker -Value Set-CMTSStepDisableBitLocker -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepEnableBitLocker -Value Set-CMTSStepEnableBitLocker -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepConnectNetworkFolder -Value Set-CMTSStepConnectNetworkFolder -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepAutoApplyDriver -Value Set-CMTSStepAutoApplyDriver -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepApplyDriverPackage -Value Set-CMTSStepApplyDriverPackage -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepApplyNetworkSetting -Value Set-CMTSStepApplyNetworkSetting -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepApplyWindowsSetting -Value Set-CMTSStepApplyWindowsSetting -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepApplyOperatingSystem -Value Set-CMTSStepApplyOperatingSystem -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepInstallApplication -Value Set-CMTSStepInstallApplication -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepInstallSoftware -Value Set-CMTSStepInstallSoftware -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepInstallUpdate -Value Set-CMTSStepInstallUpdate -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepPartitionDisk -Value Set-CMTSStepPartitionDisk -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepReboot -Value Set-CMTSStepReboot -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepRunCommandLine -Value Set-CMTSStepRunCommandLine -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepRunPowerShellScript -Value Set-CMTSStepRunPowerShellScript -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepSetupWindowsAndConfigMgr -Value Set-CMTSStepSetupWindowsAndConfigMgr -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepSetVariable -Value Set-CMTSStepSetVariable -Scope Global
Set-Alias -Name Set-CMTaskSequenceStepSetDynamicVariable -Value Set-CMTSStepSetDynamicVariable -Scope Global

Set-Alias -Name Get-CMTaskSequenceStepPrepareConfigMgrClient -Value Get-CMTSStepPrepareConfigMgrClient -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepRunTaskSequence -Value Get-CMTSStepRunTaskSequence -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepCaptureSystemImage -Value Get-CMTSStepCaptureWindowsSettings -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepCaptureWindowsSettings -Value Get-CMTSStepCaptureWindowsSettings -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepCaptureNetworkSettings -Value Get-CMTSStepCaptureNetworkSettings -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepCaptureUserState -Value Get-CMTSStepCaptureUserState -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepRestoreUserState -Value Get-CMTSStepRestoreUserState -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepDownloadPackageContent -Value Get-CMTSStepDownloadPackageContent -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepApplyDataImage -Value Get-CMTSStepApplyDataImage -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepUpgradeOperatingSystem -Value Get-CMTSStepUpgradeOperatingSystem -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepPrepareWindows -Value Get-CMTSStepPrepareWindows -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepReleaseStateStore -Value Get-CMTSStepReleaseStateStore -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepRequestStateStore -Value Get-CMTSStepRequestStateStore -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepPrestartCheck -Value Get-CMTSStepPrestartCheck -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepJoinDomainWorkgroup -Value Get-CMTSStepJoinDomainWorkgroup -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepOfflineEnableBitLocker -Value Get-CMTSStepOfflineEnableBitLocker -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepDisableBitLocker -Value Get-CMTSStepDisableBitLocker -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepEnableBitLocker -Value Get-CMTSStepEnableBitLocker -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepConnectNetworkFolder -Value Get-CMTSStepConnectNetworkFolder -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepAutoApplyDriver -Value Get-CMTSStepAutoApplyDriver -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepApplyDriverPackage -Value Get-CMTSStepApplyDriverPackage -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepApplyNetworkSetting -Value Get-CMTSStepApplyNetworkSetting -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepApplyWindowsSetting -Value Get-CMTSStepApplyWindowsSetting -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepApplyOperatingSystem -Value Get-CMTSStepApplyOperatingSystem -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepInstallApplication -Value Get-CMTSStepInstallApplication -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepInstallSoftware -Value Get-CMTSStepInstallSoftware -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepInstallUpdate -Value Get-CMTSStepInstallUpdate -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepPartitionDisk -Value Get-CMTSStepPartitionDisk -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepReboot -Value Get-CMTSStepReboot -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepRunCommandLine -Value Get-CMTSStepRunCommandLine -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepRunPowerShellScript -Value Get-CMTSStepRunPowerShellScript -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepSetupWindowsAndConfigMgr -Value Get-CMTSStepSetupWindowsAndConfigMgr -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepSetVariable -Value Get-CMTSStepSetVariable -Scope Global
Set-Alias -Name Get-CMTaskSequenceStepSetDynamicVariable -Value Get-CMTSStepSetDynamicVariable -Scope Global

Set-Alias -Name Remove-CMTaskSequenceStepPrepareConfigMgrClient -Value Remove-CMTSStepPrepareConfigMgrClient -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepRunTaskSequence -Value Remove-CMTSStepRunTaskSequence -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepCaptureSystemImage -Value Remove-CMTSStepCaptureWindowsSettings -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepCaptureWindowsSettings -Value Remove-CMTSStepCaptureWindowsSettings -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepCaptureNetworkSettings -Value Remove-CMTSStepCaptureNetworkSettings -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepCaptureUserState -Value Remove-CMTSStepCaptureUserState -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepRestoreUserState -Value Remove-CMTSStepRestoreUserState -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepDownloadPackageContent -Value Remove-CMTSStepDownloadPackageContent -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepApplyDataImage -Value Remove-CMTSStepApplyDataImage -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepUpgradeOperatingSystem -Value Remove-CMTSStepUpgradeOperatingSystem -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepPrepareWindows -Value Remove-CMTSStepPrepareWindows -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepReleaseStateStore -Value Remove-CMTSStepReleaseStateStore -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepRequestStateStore -Value Remove-CMTSStepRequestStateStore -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepPrestartCheck -Value Remove-CMTSStepPrestartCheck -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepJoinDomainWorkgroup -Value Remove-CMTSStepJoinDomainWorkgroup -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepOfflineEnableBitLocker -Value Remove-CMTSStepOfflineEnableBitLocker -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepDisableBitLocker -Value Remove-CMTSStepDisableBitLocker -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepEnableBitLocker -Value Remove-CMTSStepEnableBitLocker -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepConnectNetworkFolder -Value Remove-CMTSStepConnectNetworkFolder -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepAutoApplyDriver -Value Remove-CMTSStepAutoApplyDriver -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepApplyDriverPackage -Value Remove-CMTSStepApplyDriverPackage -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepApplyNetworkSetting -Value Remove-CMTSStepApplyNetworkSetting -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepApplyWindowsSetting -Value Remove-CMTSStepApplyWindowsSetting -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepApplyOperatingSystem -Value Remove-CMTSStepApplyOperatingSystem -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepInstallApplication -Value Remove-CMTSStepInstallApplication -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepInstallSoftware -Value Remove-CMTSStepInstallSoftware -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepInstallUpdate -Value Remove-CMTSStepInstallUpdate -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepPartitionDisk -Value Remove-CMTSStepPartitionDisk -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepReboot -Value Remove-CMTSStepReboot -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepRunCommandLine -Value Remove-CMTSStepRunCommandLine -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepRunPowerShellScript -Value Remove-CMTSStepRunPowerShellScript -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepSetupWindowsAndConfigMgr -Value Remove-CMTSStepSetupWindowsAndConfigMgr -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepSetVariable -Value Remove-CMTSStepSetVariable -Scope Global
Set-Alias -Name Remove-CMTaskSequenceStepSetDynamicVariable -Value Remove-CMTSStepSetDynamicVariable -Scope Global


function Get-CMTSStepRunCommandLine {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_RunCommandLineAction
    }
}

function Get-CMTSStepSetVariable {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_SetVariableAction
    }
}

function Get-CMTSStepInstallApplication {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_InstallApplicationAction
    }
}

function Get-CMTSStepInstallSoftware {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_InstallSoftwareAction
    }
}

function Get-CMTSStepReboot {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_RebootAction
    }
}

function Get-CMTSStepRunPowerShellScript {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_RunPowerShellScriptAction
    }
}

function Get-CMTSStepSetupWindowsAndConfigMgr {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_SetupWindowsAndSMSAction
    }
}

function Get-CMTSStepInstallUpdate {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_InstallUpdateAction
    }
}

function Get-CMTSStepPartitionDisk {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_PartitionDiskAction
    }
}

function Get-CMTSStepApplyOperatingSystem {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ApplyOperatingSystemAction
    }
}

function Get-CMTSStepApplyWindowsSetting {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ApplyWindowsSettingsAction
    }
}

function Get-CMTSStepApplyNetworkSetting {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ApplyNetworkSettingsAction
    }
}

function Get-CMTSStepApplyDriverPackage {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ApplyDriverPackageAction
    }
}

function Get-CMTSStepSetDynamicVariable {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_SetDynamicVariablesAction
    }
}

function Get-CMTSStepAutoApplyDriver {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_AutoApplyAction
    }
}

function Get-CMTSStepConnectNetworkFolder {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ConnectNetworkFolderAction
    }
}

function Get-CMTSStepEnableBitLocker {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_EnableBitLockerAction
    }
}

function Get-CMTSStepDisableBitLocker {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_DisableBitLockerAction
    }
}

function Get-CMTSStepOfflineEnableBitLocker {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_OfflineEnableBitLockerAction
    }
}

function Get-CMTSStepJoinDomainWorkgroup {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_JoinDomainWorkgroupAction
    }
}

function Get-CMTSStepPrestartCheck {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_PrestartCheckAction
    }
}

function Get-CMTSStepRequestStateStore {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_RequestStateStoreAction
    }
}

function Get-CMTSStepReleaseStateStore {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ReleaseStateStoreAction
    }
}

function Get-CMTSStepPrepareWindows {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_PrepareOSAction
    }
}

function Get-CMTSStepUpgradeOperatingSystem {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_UpgradeOperatingSystemAction
    }
}

function Get-CMTSStepApplyDataImage {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ApplyDataImageAction
    }
}

function Get-CMTSStepDownloadPackageContent {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_DownloadPackageContentAction
    }
}

function Get-CMTSStepRestoreUserState {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_RestoreUserStateAction
    }
}

function Get-CMTSStepCaptureUserState {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_CaptureUserStateAction
    }
}

function Get-CMTSStepCaptureNetworkSettings {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_CaptureNetworkSettingsAction
    }
}

function Get-CMTSStepCaptureWindowsSettings {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_CaptureWindowsSettingsAction
    }
}

function Get-CMTSStepCaptureSystemImage {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_CaptureSystemImageAction
    }
}

function Get-CMTSStepPrepareConfigMgrClient {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_PrepareSMSClientAction
    }
}

function Remove-CMTSStepRunCommandLine {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_RunCommandLineAction
    }
}

function Remove-CMTSStepSetVariable {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_SetVariableAction
    }
}

function Remove-CMTSStepInstallApplication {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_InstallApplicationAction
    }
}

function Remove-CMTSStepInstallSoftware {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_InstallSoftwareAction
    }
}

function Remove-CMTSStepReboot {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_RebootAction
    }
}

function Remove-CMTSStepRunPowerShellScript {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_RunPowerShellScriptAction
    }
}

function Remove-CMTSStepSetupWindowsAndConfigMgr {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_SetupWindowsAndSMSAction
    }
}

function Remove-CMTSStepInstallUpdate {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_InstallUpdateAction
    }
}

function Remove-CMTSStepPartitionDisk {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_PartitionDiskAction
    }
}

function Remove-CMTSStepApplyOperatingSystem {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ApplyOperatingSystemAction
    }
}

function Remove-CMTSStepApplyWindowsSetting {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ApplyWindowsSettingsAction
    }
}

function Remove-CMTSStepApplyNetworkSetting {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ApplyNetworkSettingsAction
    }
}

function Get-CMTSStepRunTaskSequence {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName
    )
    process {
        Get-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_SubTasksequence
    }
}


function Remove-CMTSStepApplyDriverPackage {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ApplyDriverPackageAction
    }
}

function Remove-CMTSStepSetDynamicVariable {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_SetDynamicVariablesAction
    }
}

function Remove-CMTSStepAutoApplyDriver {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_AutoApplyAction
    }
}

function Remove-CMTSStepConnectNetworkFolder {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ConnectNetworkFolderAction
    }
}

function Remove-CMTSStepEnableBitLocker {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_EnableBitLockerAction
    }
}

function Remove-CMTSStepDisableBitLocker {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_DisableBitLockerAction
    }
}

function Remove-CMTSStepOfflineEnableBitLocker {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_OfflineEnableBitLockerAction
    }
}

function Remove-CMTSStepJoinDomainWorkgroup {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_JoinDomainWorkgroupAction
    }
}

function Remove-CMTSStepPrestartCheck {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_PrestartCheckAction
    }
}

function Remove-CMTSStepRequestStateStore {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_RequestStateStoreAction
    }
}

function Remove-CMTSStepReleaseStateStore {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ReleaseStateStoreAction
    }
}

function Remove-CMTSStepPrepareWindows {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_PrepareOSAction
    }
}

function Remove-CMTSStepUpgradeOperatingSystem {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_UpgradeOperatingSystemAction
    }
}

function Remove-CMTSStepApplyDataImage {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_ApplyDataImageAction
    }
}

function Remove-CMTSStepDownloadPackageContent {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_DownloadPackageContentAction
    }
}

function Remove-CMTSStepRestoreUserState {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_RestoreUserStateAction
    }
}

function Remove-CMTSStepCaptureUserState {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_CaptureUserStateAction
    }
}

function Remove-CMTSStepCaptureNetworkSettings {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_CaptureNetworkSettingsAction
    }
}

function Remove-CMTSStepCaptureWindowsSettings {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_CaptureWindowsSettingsAction
    }
}

function Remove-CMTSStepCaptureSystemImage {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_CaptureSystemImageAction
    }
}

function Remove-CMTSStepPrepareConfigMgrClient {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_PrepareSMSClientAction
    }
}

function Remove-CMTSStepRunTaskSequence {
    [CmdletBinding(DefaultParameterSetName="ByValue", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ById")][ValidateNotNullOrEmpty()][Alias("Id", "TaskSequencePackageId")][string]$TaskSequenceId,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByName")][ValidateNotNullOrEmpty()][string]$TaskSequenceName,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "ByValue", ValueFromPipeline = $true)][PSTypeName("IResultObject#SMS_TaskSequencePackage")][ValidateNotNullOrEmpty()][Alias("TaskSequence")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$InputObject,
        [Parameter()][ValidateNotNullOrEmpty()][string]$StepName,
        [Parameter()][switch]$Force
    )
    process {
        Remove-CMTaskSequenceStep @PsBoundParameters -ActionClassName SMS_TaskSequence_SubTasksequence
    }
}

# RBA
Set-Alias -Name Add-CMDeviceCollectionToAdministrativeUser -Value Add-CMCollectionToAdministrativeUser -Scope Global
Set-Alias -Name Add-CMUserCollectionToAdministrativeUser -Value Add-CMCollectionToAdministrativeUser -Scope Global
Set-Alias -Name Remove-CMDeviceCollectionFromAdministrativeUser -Value Remove-CMCollectionFromAdministrativeUser -Scope Global
Set-Alias -Name Remove-CMUserCollectionFromAdministrativeUser -Value Remove-CMCollectionFromAdministrativeUser -Scope Global

# SUM
Set-Alias -Name Get-CMSoftwareUpdateAutoDeploymentRuleDeployment -Value Get-CMAutoDeploymentRuleDeployment -Scope Global
Set-Alias -Name Remove-CMSoftwareUpdateAutoDeploymentRuleDeployment -Value Remove-CMAutoDeploymentRuleDeployment -Scope Global
Set-Alias -Name New-CMSoftwareUpdateAutoDeploymentRuleDeployment -Value New-CMAutoDeploymentRuleDeployment -Scope Global
Set-Alias -Name Set-CMSoftwareUpdateAutoDeploymentRuleDeployment -Value Set-CMAutoDeploymentRuleDeployment -Scope Global
Set-Alias -Name Get-CMWindowsUpgrade -Value Get-CMWindowsUpdate -Scope Global
Set-Alias -Name Set-CMWindowsServicingPlan -Value Set-CMSoftwareUpdateAutoDeploymentRule -Scope Global
Set-Alias -Name Remove-CMWindowsServicingPlan -Value Remove-CMSoftwareUpdateAutoDeploymentRule -Scope Global
Set-Alias -Name Set-CMAutoDeploymentRule -Value Set-CMSoftwareUpdateAutoDeploymentRule -Scope Global
Set-Alias -Name Get-CMAutoDeploymentRule -Value Get-CMSoftwareUpdateAutoDeploymentRule -Scope Global
Set-Alias -Name New-CMAutoDeploymentRule -Value New-CMSoftwareUpdateAutoDeploymentRule -Scope Global
Set-Alias -Name Remove-CMAutoDeploymentRule -Value Remove-CMSoftwareUpdateAutoDeploymentRule -Scope Global
Set-Alias -Name Invoke-CMSoftwareUpdateDownload -Value Save-CMSoftwareUpdate -Scope Global

# New-CMWindowsServicingPlan is just a wrapper for New-CMSoftwareUpdateAutoDeploymentRule with fewer filter parameters and a couple of extra
# calling requirements.
function New-CMWindowsServicingPlan {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter()][string]$Description,
        [Parameter(Mandatory = $true, ParameterSetName = "NewByCollectionName")][string]$CollectionName,
        [Parameter(Mandatory = $true, ParameterSetName = "NewByCollection")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$Collection,
        [Parameter(Mandatory = $true, ParameterSetName = "NewByCollectionId")][string]$CollectionId,
        [Parameter()][PSDefaultValue(Value = $true)][Alias("Enabled", "EnableDeployment")][bool]$Enable,
        [Parameter()][PSDefaultValue(Value = $true)][bool]$SendWakeupPacket,
        [Parameter()][PSDefaultValue(Value = [Microsoft.ConfigurationManagement.Cmdlets.Sum.Commands.VerboseLevelType]::OnlyErrorMessages)][Microsoft.ConfigurationManagement.Cmdlets.Sum.Commands.VerboseLevelType]$VerboseLevel,
        [Parameter()][string[]]$Language,
        [Parameter()][string[]]$Required,
        [Parameter()][string[]]$Title,
        [Parameter()][PSDefaultValue(Value = [Microsoft.ConfigurationManagement.Cmdlets.Sum.Commands.RunType]::RunTheRuleAfterAnySoftwareUpdatePointSynchronization)][Microsoft.ConfigurationManagement.Cmdlets.Sum.Commands.RunType]$RunType,
        [Parameter()][ValidateNotNullOrEmpty()][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$Schedule,
        [Parameter()][bool]$UseUtc,
        [Parameter()][int]$AvailableTime,
        [Parameter()][PSDefaultValue(Value = $true)][bool]$AvailableImmediately,
        [Parameter()][Microsoft.ConfigurationManagement.Cmdlets.Sum.Commands.TimeUnitType]$AvailableTimeUnit,
        [Parameter()][bool]$DeadlineImmediately,
        [Parameter()][int]$DeadlineTime,
        [Parameter()][PSDefaultValue(Value = [Microsoft.ConfigurationManagement.Cmdlets.Sum.Commands.TimeUnitType]::Days)][Microsoft.ConfigurationManagement.Cmdlets.Sum.Commands.TimeUnitType]$DeadlineTimeUnit,
        [Parameter()][Microsoft.ConfigurationManagement.Cmdlets.Sum.Commands.UserNotificationType]$UserNotification,
        [Parameter()][bool]$AllowSoftwareInstallationOutsideMaintenanceWindow,
        [Parameter()][bool]$AllowRestart,
        [Parameter()][bool]$SuppressRestartServer,
        [Parameter()][bool]$SuppressRestartWorkstation,
        [Parameter()][bool]$WriteFilterHandling,
        [Parameter()][bool]$GenerateSuccessAlert,
        [Parameter()][PSDefaultValue(Value = 90)][int]$SuccessPercentage,
        [Parameter()][int]$AlertTime,
        [Parameter()][Microsoft.ConfigurationManagement.Cmdlets.Sum.Commands.TimeUnitType]$AlertTimeUnit,
        [Parameter()][bool]$DisableOperationManager,
        [Parameter()][bool]$GenerateOperationManagerAlert,
        [Parameter()][bool]$NoInstallOnRemote,
        [Parameter()][bool]$NoInstallOnUnprotected,
        [Parameter()][PSDefaultValue(Value = $true)][bool]$UseBranchCache,
        [Parameter()][bool]$DownloadFromMicrosoftUpdate,
        [Parameter()][bool]$AllowUseMeteredNetwork,
        [Parameter()][Alias("InputObject")][Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]$DeploymentPackage,
        [Parameter()][bool]$DownloadFromInternet,
        [Parameter()][ValidateNotNullOrEmpty()][string]$Location,
        [Parameter()][PSDefaultValue(Value = [Microsoft.ConfigurationManagement.Cmdlets.Sum.Commands.DeploymentRing]::CB)][Microsoft.ConfigurationManagement.Cmdlets.Sum.Commands.DeploymentRing]$DeploymentRing,
        [Parameter()][PSDefaultValue(Value = 0)][Alias("UpdateDeploymentWaitDays")][int]$UpdateDeploymentWaitDay,
        [Parameter()][string[]]$LanguageSelection
    )

    process {
        New-CMSoftwareUpdateAutoDeploymentRule -IsServicingPlan @PsBoundParameters
    }
}

function Get-CMWindowsUpdate {
    param(
          [Parameter(ParameterSetName = "SearchByName")][SupportsWildcards()][Alias("LocalizedDisplayName")][string]$Name,
          [Parameter(ParameterSetName = "SearchById", Mandatory = $true)][Alias("CIId", "CI_ID")][int]$Id,
          [Parameter()][switch]$Fast)
    process {
        $category = Get-CMSoftwareUpdateCategory -UniqueId 'UpdateClassification:3689bdc8-b205-4af4-8d4a-a63924c5e9d5' -Fast
        Get-CMSoftwareUpdate -Category $category -IncludeUpgrades @PSBoundParameters
    }
}

function Get-CMWindowsServicingPlan {
    [CmdletBinding(DefaultParameterSetName = "SearchByNameMandatory")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "SearchByIdMandatory", Position = 0)][Alias("AutoDeploymentId")][int]$Id,
        [Parameter(ParameterSetName = "SearchByNameMandatory", Position = 0)][ValidateNotNullOrEmpty()][SupportsWildcards()][string]$Name,
        [Parameter()][switch]$Fast
        )

    process {
        Get-CMSoftwareUpdateAutoDeploymentRule -IsServicingPlan $true @PsBoundParameters
    }
}
# SIG # Begin signature block
# MIInygYJKoZIhvcNAQcCoIInuzCCJ7cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC1SyyDZefZSEqP
# PHfciCFZiHuKm8EkGrPasv/zPLtFI6CCDYEwggX/MIID56ADAgECAhMzAAACzI61
# lqa90clOAAAAAALMMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjIwNTEyMjA0NjAxWhcNMjMwNTExMjA0NjAxWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQCiTbHs68bADvNud97NzcdP0zh0mRr4VpDv68KobjQFybVAuVgiINf9aG2zQtWK
# No6+2X2Ix65KGcBXuZyEi0oBUAAGnIe5O5q/Y0Ij0WwDyMWaVad2Te4r1Eic3HWH
# UfiiNjF0ETHKg3qa7DCyUqwsR9q5SaXuHlYCwM+m59Nl3jKnYnKLLfzhl13wImV9
# DF8N76ANkRyK6BYoc9I6hHF2MCTQYWbQ4fXgzKhgzj4zeabWgfu+ZJCiFLkogvc0
# RVb0x3DtyxMbl/3e45Eu+sn/x6EVwbJZVvtQYcmdGF1yAYht+JnNmWwAxL8MgHMz
# xEcoY1Q1JtstiY3+u3ulGMvhAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUiLhHjTKWzIqVIp+sM2rOHH11rfQw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDcwNTI5MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAeA8D
# sOAHS53MTIHYu8bbXrO6yQtRD6JfyMWeXaLu3Nc8PDnFc1efYq/F3MGx/aiwNbcs
# J2MU7BKNWTP5JQVBA2GNIeR3mScXqnOsv1XqXPvZeISDVWLaBQzceItdIwgo6B13
# vxlkkSYMvB0Dr3Yw7/W9U4Wk5K/RDOnIGvmKqKi3AwyxlV1mpefy729FKaWT7edB
# d3I4+hldMY8sdfDPjWRtJzjMjXZs41OUOwtHccPazjjC7KndzvZHx/0VWL8n0NT/
# 404vftnXKifMZkS4p2sB3oK+6kCcsyWsgS/3eYGw1Fe4MOnin1RhgrW1rHPODJTG
# AUOmW4wc3Q6KKr2zve7sMDZe9tfylonPwhk971rX8qGw6LkrGFv31IJeJSe/aUbG
# dUDPkbrABbVvPElgoj5eP3REqx5jdfkQw7tOdWkhn0jDUh2uQen9Atj3RkJyHuR0
# GUsJVMWFJdkIO/gFwzoOGlHNsmxvpANV86/1qgb1oZXdrURpzJp53MsDaBY/pxOc
# J0Cvg6uWs3kQWgKk5aBzvsX95BzdItHTpVMtVPW4q41XEvbFmUP1n6oL5rdNdrTM
# j/HXMRk1KCksax1Vxo3qv+13cCsZAaQNaIAvt5LvkshZkDZIP//0Hnq7NnWeYR3z
# 4oFiw9N2n3bb9baQWuWPswG0Dq9YT9kb+Cs4qIIwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZnzCCGZsCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgcTivzL2o
# 1VlaK96ynUDJ4iXy2zBxr8/l+q5ySaCVF6QwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQB2K1H7hPLT8cdZKfwzIfXR1DEsuhEPcfoKJrps6Nni
# TWClvLO+uAFIXxkqRGtp1gmQ4S+BKVfWmqw4UxfCMnn0sTpxbInokVyw+g4IoEkf
# COKH386pzX/jRzQnjFTXTCe0uqz9t5KjQH0bTaA/C/uLqDfTJ0mXKUgiXuF6UpMP
# 9incWibjdCGRQHYOEa9KAW606ipWo2sRY9gHQ35ai4Pox0/c1o7T2cGxSUVZW/q2
# ELE91y0Os7741v0GbGHYmNYo2y+eou0Uy3R9gw3NekwBwBeuyPLgBFZX0+dsLwze
# ddH/atjA372qe6NcKX/ec08YggJEXyqI4jQZN5OAFaBuoYIXKTCCFyUGCisGAQQB
# gjcDAwExghcVMIIXEQYJKoZIhvcNAQcCoIIXAjCCFv4CAQMxDzANBglghkgBZQME
# AgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEILsG7zIJSlNSxt8g/FE1CdWHKPNG9WMyi0elDCmS
# cTCaAgZjY+GELuMYEzIwMjIxMTA0MTcyMzQwLjQ2NVowBIACAfSggdikgdUwgdIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046RDA4Mi00QkZELUVFQkExJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghF4MIIHJzCCBQ+gAwIBAgITMwAAAbofPxn3wXW9
# fAABAAABujANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yMjA5MjAyMDIyMTlaFw0yMzEyMTQyMDIyMTlaMIHSMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
# SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOkQwODItNEJGRC1FRUJBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAiE4VgzOS
# NYAT1RWdcX2FEa/TEFHFz4jke7eHFUVfIre7fzG6wRvSkuTCOAa0OxostuuUzGpf
# e0Vv/cGAQ8QLcvTBfvqAPzMe37CIFXmarkFainb2pGuAwkooI9ylCdKOz0H/hcwU
# W+ul0+JxkO/jcUuDP18eoyrQskPDkkAcYNLfRMJj04Xjc/h3jhn2UTsJpVLakkwX
# cvjncxcHnJgr8oNuKWERE/WPGfbKX60YJGC4gCwwbSh46FdrDy5IY6FLoAJIdv55
# uLTTfwwUfKhM2Ep/5Jijg6lJjfE/j6zAEFMoOhg/XAf4J/EbqH1/KYElA9Blqp+X
# SuKIMuOYO6dC0fUYPrgCKvmT0l3CGrnAuZJZePIVUv4gN86l2LEnp/mj4yETofi3
# fXD6mvKAeZ3ZQdDrntQbHoU27PAL5KkAeZXvoxlhpzi4CFOBo/js/Z55LWhyS/KG
# X3Jr70nM98yS6DfF6/MUANaItEyvTroQxXurclJECycJL0ZDTwLgUo9tKHw48zfc
# ueDR9/EA2ccABf8MTtwdzHuX2NpXcByaSPuiqKvgSHa7ljHCJpMTftdoy6ZfYRLc
# 8nk0Fperth0snDJIP5T2mT+2Xh1DW38R6ju4NOWI7JCQPwjvjGlUHRPfX/rsod+Q
# GQVW/LrDJ7bVX70gLy5IP75GAPdHC03aQT8CAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBSKYubxAx4lrbmP0xZ5psjYdK9k5TAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# X8jxTqFtmG8Nyf3qdnq2RtISNc+8pnrCuhpdyCy0SGmBp4TCV4u49ccvMRa24m5j
# Ph6yGaFeoWvj2VsBxflI3n9wSw/TF0VrJvtTk/3gll3ceMW+lZE2g0GEXdIMzQDf
# ywjYf6GOEH9V9fVdxmJ6LVE48DIIdwGAcvJCsS7qadvceFsh2vyHRNrtYXKUaEtI
# VbrCbMq6w/po6WacZJpzk0x+VrqVG9Ngd3byttsKB9KbVGFOChmP5bwNMq2IQzC5
# scneYg8qajzG0khZc+derpcqCV2svlzKcsxf/RZfrk65ZsdXkZMQt19a8ZXcNpms
# c9RD9Q/fUp6pvbGNUJvfQtXCBuMi9hLvs3V0BGQ3wX/2knWA7gi9lYzDIyUooUai
# M7V/XBuNJZwD/nu2xz63ZuWsxaBI0eDMOvTWNs9K6lGPLce31lmzjE3TZ6Jfd4bb
# 3s2u0LqXhz+DOfbR6qipbH+4dbGZOAHQXmiwG5Mc57vsPIQDS6ECsaWAo/3WOCGC
# 385UegfrmDRCoK2Bn7fqacISDog6EWgWsJzR8kUZWZvX7XuAR74dEwzuMGTg7Ton
# 4iigWsjd7c8mM+tBqej8zITeH7MC4FYYwNFxSU0oINTt0ada8fddbAusIIhzP7cb
# BFQywuwN09bY5W/u/V4QmIxIhnY/4zsvbRDxrOdTg4AwggdxMIIFWaADAgECAhMz
# AAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0z
# MDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP9
# 7pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMM
# tY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gm
# U3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130
# /o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP
# 3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7
# vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+A
# utuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz
# 1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6
# EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/Zc
# UlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZy
# acaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJ
# KwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8G
# CCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3Mv
# UmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQC
# BAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYD
# VR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZF
# aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcw
# AoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJB
# dXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cB
# MSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7
# bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/
# SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2
# EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2Fz
# Lixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0
# /fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9
# swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJ
# Xk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+
# pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW
# 4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N
# 7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIC1DCCAj0CAQEwggEAoYHYpIHVMIHSMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOkQwODItNEJGRC1FRUJBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQB2o0d7XXeAInztpkgZrlAF
# SojC8qCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBBQUAAgUA5w+xdjAiGA8yMDIyMTEwNDIzNDI0NloYDzIwMjIxMTA1MjM0
# MjQ2WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDnD7F2AgEAMAcCAQACAgMMMAcC
# AQACAhF1MAoCBQDnEQL2AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
# AwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEFBQADgYEAXs/Z
# WYr0Tu715A9CXzOsf/Z9pK974R7nTeWgzBr44J8ZVlRzMYz2vx29FHOMj0Nii3Ve
# xx/CV/0ucayRyWCenwMXJFL7YaA7LA5Uk12W8fInYlwblq/hLxVzY3TUuOocG6up
# 1ZQJv9hioDrQaL/N5EOZEAu7Ol9izdmaw4vbdpgxggQNMIIECQIBATCBkzB8MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
# b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAbofPxn3wXW9fAABAAABujAN
# BglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8G
# CSqGSIb3DQEJBDEiBCD0byAQSXFUgljjyzKjxjXLqYDZbmkLUFJlIZq6qnY0aDCB
# +gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIClVvTwzbnD61gZayaUa2nWDLWc9
# ypZ+qAwXeeVZhXMFMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTACEzMAAAG6Hz8Z98F1vXwAAQAAAbowIgQgu94v7zX9+AjW4tP1c+oAxVHcw93C
# RBCq3w4XvQZDoGIwDQYJKoZIhvcNAQELBQAEggIAA4stL5gDoFxnMVO2SzDi86qd
# RaCMWFX4qSkFbuqOt74Y6qGv6/3KR8Ce/tehNVm41SQFmynoe1hdWj0F4Qs/olxG
# q+N4RPQTVgD4KDKtUmSOE2Inw55qU/G7yUtrnh8BulDl+LwgcGXCph3bYjy/ZCDX
# 20eEaboCXE44ni3M2lA+JO6545iTNs8Yzoq1snKLQ+/lHVc+1jFkgMzWY76B2RZ2
# Wdh+mh/8iY5MnfAdWaMtT+4HHxnzEz5aGT2JbjyoWLkVW6AdwBIMyt4vG8fFN8MR
# +Dg3VxKAnVykkCyOR26XVqlcd/7xC2PKNKsD33IbsuPSHNP68JVPuqjZTb/STjWh
# axxjFbL70b+3DkgdP/1DiqMoMdVQ4jc8dvDdSkd/R1ASqzmq9Geg7yp9RjjCg3ld
# dkkurHJtw6y9CVoHPQsATJPsphMlf7liH2kIG3XKmZNEbrF+ULQDf49pjorfDqPw
# TC6yOXP+4Mpua/uK1f1IomUhtNx86nrISA/VjD0C7y3Ra4BDl/86H6xQmWaylUF3
# 3FWFSYJbJ+slJOnSFerbPNzzJjssY66tu7PAH87dm25G7rm1x8kXS9I0fXV2w65C
# IdnuhaL8+u4oAFce9zqwpP7J5SmsVHqjfyqF0/q0iCn1eu377ybMGnk2KP00tizx
# j0akC4XPfFT6vTIbCYg=
# SIG # End signature block
