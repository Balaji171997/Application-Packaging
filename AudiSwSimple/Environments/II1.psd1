<#
    II1 - the test site. ICZ's settings on a different server.

    This file is the whole of what makes II1 different from any other
    environment. Adding a fourth environment is a copy of this file.
#>
@{
    SiteCode   = 'II1'
    SiteServer = 'AUDIINSA1299.audi.vwg5t'

    # Where the packager drops job files and the Script Runner picks them up.
    DropFolder = 'C:\AudiSwIntegration\DropFolder\II1'

    # MUST be a UNC path. SCCM hands this to distribution points to fetch from,
    # so a local path is refused - and refused only after the application has
    # been created, which is why it is checked before anything starts.
    ContentShare           = '\\isnasv117.in.audi.vwg\GPF-Package-Documentation\GPF_Working\GPF Team\Balaji'
    DistributionPointGroup = 'Test'

    # Console folders, as the console shows them.
    ApplicationFolder = 'ICZ-Applications'

    SecurityScopes = @('ICZ00001', 'ICZ00002', 'ICZ00005', 'ICZ00006')

    # Collection name = Prefix + package name + Suffix.
    # The deployment for each one is declared here, so a deployment can never be
    # paired with the wrong collection.
    Collections = @(
        @{ Prefix = 'II1-'; Suffix = '';                 Limiting = 'II10000C'; Folder = 'II1-Site\II1-Software Management';  Action = 'Available' }
        @{ Prefix = 'SM1-'; Suffix = '_InstallComputer'; Limiting = 'SMS00001'; Folder = 'SCCM-Manager\Single-Distributions'; Action = 'Available' }
        @{ Prefix = 'SM1-'; Suffix = '_Query';           Limiting = 'SMS00001'; Folder = 'SCCM-Manager\Global-Deployments';   Action = 'Available' }
        @{ Prefix = 'SM1-'; Suffix = '_RemoveComputer';  Limiting = 'SMS00001'; Folder = 'SCCM-Manager\Single-Removals';      Action = 'Uninstall' }
    )

    # For the AD group step, which is not switched on yet.
    ArsProviderUrl = 'http://audiinsa4030.audi.vwg5t/ARServerSPML/SPMLProvider.asmx?WDSL'
    ArsGroupOu     = 'OU=Development_in_Progress,OU=Software-Groups,OU=Administration,OU=AUDI AG,DC=audi,DC=vwg5t'
}
