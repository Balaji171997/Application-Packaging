# Step 1: prove we can sign in and resolve the SharePoint site. No repo access yet.

$modPath = Join-Path $PSScriptRoot 'lib\MSAL.PS\MSAL.PS.psd1'
Import-Module $modPath -Force

$tenantId = 'm365.man'                                   # from PB settings.json -> Intune.TenantId
$clientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'        # Microsoft's own "Graph Command Line Tools" app
$scope    = 'https://graph.microsoft.com/Sites.Read.All'

$tok = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes $scope -Interactive
if (-not $tok) { Write-Host "No token acquired." -ForegroundColor Red; return }
Write-Host "Signed in as: $($tok.Account.Username)" -ForegroundColor Green

$headers = @{ Authorization = "Bearer $($tok.AccessToken)" }
$site = Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/sites/manonlineservices.sharepoint.com:/sites/SWPackaging' -Headers $headers

Write-Host "Site resolved:" -ForegroundColor Green
$site | Select-Object displayName, webUrl, id | Format-List
