<#  INA - production.  #>
@{
    SiteCode   = 'INA'
    SiteServer = 'AUDIINSC0002.audi.vwg'
    DropFolder = 'C:\AudiSwIntegration\DropFolder\INA'

    ContentShare           = '\\audiinsv0259.in.audi.vwg\sccm-store\pkg\prod'
    DistributionPointGroup = 'INA-DP-Group all'

    ApplicationFolder = 'INA-Applications'
    SecurityScopes    = @('INA00003')

    Collections = @(
        @{ Prefix = 'GY1-'; Suffix = '';                 Limiting = 'INA010CA'; Folder = 'GY1-Site\GY1-Software Management';  Action = 'Available' }
        @{ Prefix = 'IN1-'; Suffix = '';                 Limiting = 'INA000D7'; Folder = 'IN1-Site\IN1-Software Management';  Action = 'Available' }
        @{ Prefix = 'IN9-'; Suffix = '';                 Limiting = 'INA00904'; Folder = 'IN9-Site\IN9-Software Management';  Action = 'Available' }
        @{ Prefix = 'NE1-'; Suffix = '';                 Limiting = 'INA00A6E'; Folder = 'NE1-Site\NE1-Software Management';  Action = 'Available' }
        @{ Prefix = 'NE9-'; Suffix = '';                 Limiting = 'INA00A8A'; Folder = 'NE9-Site\NE9-Software Management';  Action = 'Available' }
        @{ Prefix = 'SJ1-'; Suffix = '';                 Limiting = 'INA014E7'; Folder = 'SJ1-Site\SJ1-Software Management';  Action = 'Available' }
        @{ Prefix = 'SM1-'; Suffix = '_InstallComputer'; Limiting = 'SMS00001'; Folder = 'SCCM-Manager\Single-Distributions'; Action = 'Available' }
        @{ Prefix = 'SM1-'; Suffix = '_Query';           Limiting = 'SMS00001'; Folder = 'SCCM-Manager\Global-Deployments';   Action = 'Available' }
        @{ Prefix = 'SM1-'; Suffix = '_RemoveComputer';  Limiting = 'SMS00001'; Folder = 'SCCM-Manager\Single-Removals';      Action = 'Uninstall' }
    )

    ArsProviderUrl = 'http://audiinsa4438.in.audi.vwg/ARServerSPML/SPMLProvider.asmx?WDSL'
    ArsGroupOu     = 'OU=Development_in_Progress,OU=Software-Groups,OU=Administration,OU=AUDI AG,DC=audi,DC=vwg'
}