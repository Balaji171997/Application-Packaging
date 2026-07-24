# Step 1: prove we can sign in and resolve the SharePoint site. No repo access yet.

$modPath = Join-Path $PSScriptRoot 'lib\MSAL.PS\MSAL.PS.psd1'
Import-Module $modPath -Force

$tenantId = 'm365.man'                                   # from PB settings.json -> Intune.TenantId
$clientId = '6beebafa-4759-41cf-8c61-34735059ad62'        # same "Microsoft Intune PowerShell" app PB already uses
$scope    = 'https://graph.microsoft.com/Sites.Read.All'

$redirectUri = 'urn:ietf:wg:oauth:2.0:oob'                # matches what Connect-MSIntuneGraph registers for this app
$tok = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes $scope -RedirectUri $redirectUri -Interactive
if (-not $tok) { Write-Host "No token acquired." -ForegroundColor Red; return }
Write-Host "Signed in as: $($tok.Account.Username)" -ForegroundColor Green

$headers = @{ Authorization = "Bearer $($tok.AccessToken)" }
$site = Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/sites/manonlineservices.sharepoint.com:/sites/SWPackaging' -Headers $headers

Write-Host "Site resolved:" -ForegroundColor Green
$site | Select-Object displayName, webUrl, id | Format-List
