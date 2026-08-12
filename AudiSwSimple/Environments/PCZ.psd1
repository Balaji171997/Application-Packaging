<#  PCZ - production.

    FIVE VALUES ARE STILL UNCONFIRMED. In the tool being replaced they were
    copies of INA's, or never set at all: the content share, the security scope,
    the application folder, the AD group OU and the ARS provider URL. They are
    marked CONFIRM below. Do not run this environment for real until Audi has
    confirmed them.  #>
@{
    SiteCode   = 'PCZ'
    SiteServer = 'AUDIINSC0003.audi.vwg'          # CONFIRM
    DropFolder = 'C:\AudiSwIntegration\DropFolder\PCZ'

    ContentShare           = '\\audiinsc0027.audi.prod.vwg\SCCM-STORE\PKG\PROD'   # CONFIRM - was INA's
    DistributionPointGroup = 'PCZ-DP-Group all'            # CONFIRM

    ApplicationFolder = 'PCZ-Applications'                 # CONFIRM - was INA's
    SecurityScopes    = @('CONFIRM')                       # CONFIRM - was INA00003

    Collections = @(
        @{ Prefix = 'PC1-'; Suffix = '';                 Limiting = 'CONFIRM';  Folder = 'PC1-Site\PC1-Software Management';  Action = 'Available' }
        @{ Prefix = 'SM1-'; Suffix = '_InstallComputer'; Limiting = 'SMS00001'; Folder = 'SCCM-Manager\Single-Distributions'; Action = 'Available' }
        @{ Prefix = 'SM1-'; Suffix = '_Query';           Limiting = 'SMS00001'; Folder = 'SCCM-Manager\Global-Deployments';   Action = 'Available' }
        @{ Prefix = 'SM1-'; Suffix = '_RemoveComputer';  Limiting = 'SMS00001'; Folder = 'SCCM-Manager\Single-Removals';      Action = 'Uninstall' }
    )

    ArsProviderUrl = 'CONFIRM'                             # CONFIRM - was INA's
    ArsGroupOu     = 'CONFIRM'                             # CONFIRM - was DC=audi,DC=vwg
}