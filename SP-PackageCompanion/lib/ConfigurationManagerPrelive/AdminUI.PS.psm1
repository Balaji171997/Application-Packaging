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
Set-Alias -Scope Global -Name New-CMWindows11EditionUpgradeConfigurationItem -Value New-CMWindows11EditionUpgrade

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
# MIIomwYJKoZIhvcNAQcCoIIojDCCKIgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCRiiGFBS+yXR0B
# nN/z/7qMp+tiHzcaEZKJdIYPmKYCHaCCDYUwggYDMIID66ADAgECAhMzAAAEhJji
# EuB4ozFdAAAAAASEMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjUwNjE5MTgyMTM1WhcNMjYwNjE3MTgyMTM1WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDtekqMKDnzfsyc1T1QpHfFtr+rkir8ldzLPKmMXbRDouVXAsvBfd6E82tPj4Yz
# aSluGDQoX3NpMKooKeVFjjNRq37yyT/h1QTLMB8dpmsZ/70UM+U/sYxvt1PWWxLj
# MNIXqzB8PjG6i7H2YFgk4YOhfGSekvnzW13dLAtfjD0wiwREPvCNlilRz7XoFde5
# KO01eFiWeteh48qUOqUaAkIznC4XB3sFd1LWUmupXHK05QfJSmnei9qZJBYTt8Zh
# ArGDh7nQn+Y1jOA3oBiCUJ4n1CMaWdDhrgdMuu026oWAbfC3prqkUn8LWp28H+2S
# LetNG5KQZZwvy3Zcn7+PQGl5AgMBAAGjggGCMIIBfjAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUBN/0b6Fh6nMdE4FAxYG9kWCpbYUw
# VAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjMwMDEyKzUwNTM2MjAfBgNVHSMEGDAW
# gBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDEx
# XzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIB
# AGLQps1XU4RTcoDIDLP6QG3NnRE3p/WSMp61Cs8Z+JUv3xJWGtBzYmCINmHVFv6i
# 8pYF/e79FNK6P1oKjduxqHSicBdg8Mj0k8kDFA/0eU26bPBRQUIaiWrhsDOrXWdL
# m7Zmu516oQoUWcINs4jBfjDEVV4bmgQYfe+4/MUJwQJ9h6mfE+kcCP4HlP4ChIQB
# UHoSymakcTBvZw+Qst7sbdt5KnQKkSEN01CzPG1awClCI6zLKf/vKIwnqHw/+Wvc
# Ar7gwKlWNmLwTNi807r9rWsXQep1Q8YMkIuGmZ0a1qCd3GuOkSRznz2/0ojeZVYh
# ZyohCQi1Bs+xfRkv/fy0HfV3mNyO22dFUvHzBZgqE5FbGjmUnrSr1x8lCrK+s4A+
# bOGp2IejOphWoZEPGOco/HEznZ5Lk6w6W+E2Jy3PHoFE0Y8TtkSE4/80Y2lBJhLj
# 27d8ueJ8IdQhSpL/WzTjjnuYH7Dx5o9pWdIGSaFNYuSqOYxrVW7N4AEQVRDZeqDc
# fqPG3O6r5SNsxXbd71DCIQURtUKss53ON+vrlV0rjiKBIdwvMNLQ9zK0jy77owDy
# XXoYkQxakN2uFIBO1UNAvCYXjs4rw3SRmBX9qiZ5ENxcn/pLMkiyb68QdwHUXz+1
# fI6ea3/jjpNPz6Dlc/RMcXIWeMMkhup/XEbwu73U+uz/MIIHejCCBWKgAwIBAgIK
# YQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
# OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYD
# VQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+la
# UKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc
# 6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4D
# dato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+
# lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nk
# kDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6
# A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmd
# X4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
# 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zd
# sGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3
# T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS
# 4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRI
# bmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBD
# uRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1h
# cnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkA
# YwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn
# 8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7
# v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0b
# pdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/
# KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvy
# CInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBp
# mLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJi
# hsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYb
# BL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
# oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sL
# gOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtX
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGmwwghpoAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAASEmOIS4HijMV0AAAAA
# BIQwDQYJYIZIAWUDBAIBBQCggfcwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEICj7
# mYoQJCXBZN624okuCS1vemsWzWTdcJSBMCuo3KGIMIGKBgorBgEEAYI3AgEMMXww
# eqBcgFoATQBpAGMAcgBvAHMAbwBmAHQALgBUAG8AbwBsAGsAaQB0AC4AVwBwAGYA
# LgBVAEkALgBDAG8AbgB0AHIAbwBsAHMALgBXAGUAYgBWAGkAZQB3AC4AZABsAGyh
# GoAYaHR0cDovL3d3dy5taWNyb3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBADqB
# esLJ8ttmxfL9W+a2vk1TTHt/RBa72X+C2JcLkjb42yJyBW26vxvKgF7KRNJKDcmx
# Hx+CJveL39MZlZ/AjEP87lCWXrbE2DdPPehjyeV0Mk/ektoMXabNyAZaLWj/1qbG
# nlulFfg33GXHzzrTbUtKRGgUlFeU6gF2IUdRtVdd095HxootClE7soY71F2HA+8e
# 24EJblWa9s7bCB8XKj4u8CPtDxlWvk0usPTD+12T7aeC6NbnOI79SntGeB5MynGQ
# 1pYwKbP3PKP4nTPnT/1W/OyH9X5yKvZ3w84XBYHDquWWxG+THnf01MPQyjsn6drT
# yRvjWRGP5GYj3R+HxrShghetMIIXqQYKKwYBBAGCNwMDATGCF5kwgheVBgkqhkiG
# 9w0BBwKggheGMIIXggIBAzEPMA0GCWCGSAFlAwQCAQUAMIIBWgYLKoZIhvcNAQkQ
# AQSgggFJBIIBRTCCAUECAQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQg
# pS+u4uaqS+5LUrjlmScl64sXDGsvef8FsCP4q5ukU7YCBmjx/+7HwBgTMjAyNTEw
# MjMwMjQ2MDMuMzc2WjAEgAIB9KCB2aSB1jCB0zELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3Bl
# cmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046NEMxQS0w
# NUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# ghH7MIIHKDCCBRCgAwIBAgITMwAAAhgl2ZIF4ufl5AABAAACGDANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTA4MTQxODQ4
# MjVaFw0yNjExMTMxODQ4MjVaMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25z
# IExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0QzFBLTA1RTAtRDk0
# NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBALHc6OrrkCagH8S57xAXyL4+pJyvqem5
# zFxBWf0IzzhcsJXIw38yPA4NZ8w5cZu/6am741ocr2syphcjuqmz8ApX0ZyOe4eT
# gosYKTjghiSUCGUk4jILotwfAz4hbST3H80bdxbJ8Yy18ASIxoJ4xn5kJe83owNV
# qGC/6gZkIcPxQxU1nm8X6OJtEQgjsX9qsI99Wjo3NmmFHj7SzFx7FyjxR9LaeUii
# Bf/bScUUoNDWBL0KlYpY3vGkJD3d6swLsdjHORzEiuDTE7VVQmAFg1GeKfuogyPb
# eQTQgSLH+aKBTVFrcQqp6RWIi2JB3xX8YVVAWfCxhsWLAN+rJw+ubNh3+LfOpNHv
# FnpR/7rH4WKjjN89smiPK4NPOt9SJMKlM8kKBD6jLB4AXptcaZjhkiFJ1b07AL/p
# ZhAi9kaq3DmZWWsfCtGooo/IelJFgTdiAP4pGnJE0hlUQUJllmbixVlf0+Mbjc7H
# AtF+8aOH3rYKbKmhANI2P0Hr5E7y7+DpTTfXji/CzYe1ZtEeuT+6GmzkA6rVBQMA
# oI4DydIlf40AmjAHDt0mKRucEgGIiZJOFy4zUpTcVNiHY7NbDkYZe7OywuoTm+21
# QB1cDje+BsXxTYhCAOgX7nQDY6UCdJ1HP6aRF6U+KYAwR7GLVfDsikoyrCMTnRUe
# 3yCSIw3PA71JAgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQUJC6hxFw6G2O3R7qEAgWu
# LF+2i9EwHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgw
# VjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUF
# BwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
# aW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgx
# KS5jcnQwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNV
# HQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQADggIBAJ5I0YY8D4HaCKb7eGIqE/49
# C1rgcRdwEQSlwxDYIK2irwtKET8G4wJrF5zxJrbqOTA/LifV8PXmK8aqpCuAxfbJ
# 2TKxzH6KMQmvvtYqy8/GKKMwuLXIvmuDd+0m5HtabdcbPambb5D4GRlp+QXMFX5g
# MEmSx4tgrmdOmNP1/renzQZ62zFaLzWg1+Fj3ciPRhM8XyIIA7HJNiKaOFVy/wK3
# M+6dhe2xGRkbssY4DAvsKApAyWh/8pP8HGaQLIsXuDznTdA1umW9+Ttw4N/muqaw
# DTHN1iHb3yg5e+T9GqnEG0AEe29H+IB+DTJFHLdFpuBjeSobBNWCu1f8AKgypiuI
# 8d8y892vB7MWvRwdxsorZZgubA4TpeEExjeZEYuqAqFeISvpCBYJ5Fox4UkTaJs9
# +kJ2wkhvwRyxJthkVPbt/yOM1HfRNQAveyCRBn8G/tDVm90BHK5MqXRnVsJdCxDm
# 4a0EfQdVe/nnXMjZrF9KdgV9KxaXdT5FyUm8X/CHBIsP25DYGoGRPlZQ7cV3q7i3
# aOZN5Rjr+6z2LjhGqGWMQ72baRz/T9+sJluCDY0ejSJ59lDPpKz/8Xi50WwwZJvU
# bJZ6A4Va2pYigx+tgcYXIC/bYkYDh5XCNMKr1Vi3b/MlvK8ZGsDpYQkak9xChAlv
# JLVAD8DWwVC5E/qFnLwXMIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAA
# FTANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0
# aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
# b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIP
# ADCCAgoCggIBAOThpkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9s
# SuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3
# po5GawcU88V29YZQ3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2
# vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GP
# sjksUZzpcGkNyjYtcI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3
# rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDP
# c31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8F
# A6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q
# 6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1f
# MHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLv
# jflSxIUXk8A8FdsaN8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGj
# ggHdMIIB2TASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+
# ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIw
# XAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMG
# A1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsG
# A1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJc
# YmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9z
# b2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIz
# LmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0
# MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5H
# ZHixBpOXPTEztTnXwnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2
# HnjYNi6cqYJWAAOwBb6J6Gngugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1
# JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8
# F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99J
# o3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4K
# WN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZ
# kWsNn6Qo3GcZKCS6OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58
# oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w
# /ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+
# 7X6gMTN9vMvpe784cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1iz
# oXBm8qGCA1YwggI+AgEBMIIBAaGB2aSB1jCB0zELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3Bl
# cmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046NEMxQS0w
# NUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wi
# IwoBATAHBgUrDgMCGgMVAJ1rRq11orjRPEKyn5uArRq+e8/poIGDMIGApH4wfDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQELBQACBQDso74b
# MCIYDzIwMjUxMDIyMjAzMzMxWhgPMjAyNTEwMjMyMDMzMzFaMHQwOgYKKwYBBAGE
# WQoEATEsMCowCgIFAOyjvhsCAQAwBwIBAAICH88wBwIBAAICEl0wCgIFAOylD5sC
# AQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEK
# MAgCAQACAwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAzP7tuerDBmVVwVALhJzdT2tL
# wR+MbJnIkCpHFonPHxjbozVwcfWPOuNI/4VHAxHtVMKHkZUQiFKup0knRZ8Urwyr
# yTB7OmbaQJS7qVSmTj2+i9nHVhEhzFsNOrr8Gur7kMmEUpkUX7JLZUSFEMmaP3x7
# kgEG++DfgogFQoxj4LxIkhfOGcaijkoWnA/WiF1r5Fjn7z7IRbfp8piIvNDqfuCQ
# gVvBkqCMpAqWAFqt9TdsOxKkEimXmWWN4zQLzmwdE+S9fMfsceEx+LxOEr9QM5Lz
# 9UNZvz5pB4PTAgYdBHS0XtjrjIe+UPlhx2roeDC79v5JeOPmBI/3RWUhxFMf8TGC
# BA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAC
# GCXZkgXi5+XkAAEAAAIYMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMx
# DQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIHOaBLaKU5mfPVOL6moeV7dB
# P8+C6s4MYcBG7dkbEswCMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgmRPc
# ibjkyLSMFmhEupcxiitV3EqM9cp0c2jlc8fXhWowgZgwgYCkfjB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAhgl2ZIF4ufl5AABAAACGDAiBCDHpesr
# NtXsL2kqUjHHsVJcI2rVrXjFlPaYYSxPmaKi2TANBgkqhkiG9w0BAQsFAASCAgBi
# I2Sf+RkhujL8B8T1aTuOl/mlwshVbJmingsu2lUyIXeFLKqQ/DLlSX2UUO7smA7r
# 5NsVO2yu0oZF3lvALDStAs6JftgAwMXb59w/Gq+cDyTK5xh5NL+aB9YK5pcR4a6t
# ydTDAzyDpBJ+qnO6XY9ZSeH7DsBjS1iIB/18QPU6OcfamlEqkXPisWTlu5oM/qtk
# FhNgcVRKuBR15CsY/e0SwBC81MFbAmts2l+t7suqpoUyTbMj7sV5joY3ES4/cF4W
# iWB3izgpLf4GNho7fqIq/UwKNJ9JCRdUm6zD6QaHUKxx9uYAu+o0pZLkrzleuqfX
# PTe75tmGT8d97zekKwfB6YiT53HoE3t0F7RbGq6IcKAF51IIomQ/0X7lUgPk3dOf
# 8MZr3xJan6mXMe9DvKXhdZP/xlxSdXAUhNkeHJu51AxbzeJwN/UvwLbGU62SC0wB
# nMKHNMQYjRpIAJ7np72K4uPq/Df+GFn2S1Guiyb1L4Hnuu4K5MwfMFe9pj/M220O
# aGLQOpHxQeTSyKi2ZUSkPc4XCOZcLaTDgoeNp5CzGq6GQm6/qgVcU1VOYHnl9ilS
# C9NHck7clfsLg/n9EJJZ1BHe+3Elhea1+qgvZcDPUXuj29OQhJECKly6SCW8ODHo
# 3uxphf714syXgIAEsEcz04BZ7nBmb5SNCCDShf8+kg==
# SIG # End signature block
