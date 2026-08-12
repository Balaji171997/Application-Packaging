<#  ICZ - Audi's test environment.  #>
@{
    SiteCode   = 'ICZ'
    SiteServer = 'AUDIINSA1298.audi.vwg5t'
    DropFolder = 'C:\AudiSwIntegration\DropFolder\ICZ'

    ContentShare           = '\\audiinsv1059.in.audi.vwg5t\sccm-store\pkg\prod'   # CONFIRM: must be UNC
    DistributionPointGroup = 'Test'

    ApplicationFolder = 'ICZ-Applications'
    SecurityScopes    = @('ICZ00001', 'ICZ00002', 'ICZ00005', 'ICZ00006')

    Collections = @(
        @{ Prefix = 'II1-'; Suffix = '';                 Limiting = 'II10000C'; Folder = 'II1-Site\II1-Software Management';  Action = 'Available' }
        @{ Prefix = 'SM1-'; Suffix = '_InstallComputer'; Limiting = 'SMS00001'; Folder = 'SCCM-Manager\Single-Distributions'; Action = 'Available' }
        @{ Prefix = 'SM1-'; Suffix = '_Query';           Limiting = 'SMS00001'; Folder = 'SCCM-Manager\Global-Deployments';   Action = 'Available' }
        @{ Prefix = 'SM1-'; Suffix = '_RemoveComputer';  Limiting = 'SMS00001'; Folder = 'SCCM-Manager\Single-Removals';      Action = 'Uninstall' }
    )

    ArsProviderUrl = 'http://audiinsa4030.audi.vwg5t/ARServerSPML/SPMLProvider.asmx?WDSL'
    ArsGroupOu     = 'OU=Development_in_Progress,OU=Software-Groups,OU=Administration,OU=AUDI AG,DC=audi,DC=vwg5t'
}