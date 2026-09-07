# Step 2: list the site's document libraries, then the top level of PackageSources.
# Still read-only. Confirms the drive id + shows the Vendor-folder layer.

$modPath = Join-Path $PSScriptRoot 'lib\MSAL.PS\MSAL.PS.psd1'
Import-Module $modPath -Force

$tenantId    = 'm365.man'
$clientId    = '6beebafa-4759-41cf-8c61-34735059ad62'
$scope       = 'https://graph.microsoft.com/Sites.Read.All'
$redirectUri = 'urn:ietf:wg:oauth:2.0:oob'

$tok = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes $scope -RedirectUri $redirectUri -Interactive
if (-not $tok) { Write-Host "No token acquired." -ForegroundColor Red; return }

$headers = @{ Authorization = "Bearer $($tok.AccessToken)" }
$g = 'https://graph.microsoft.com/v1.0'

$site = Invoke-RestMethod -Uri "$g/sites/manonlineservices.sharepoint.com:/sites/SWPackaging" -Headers $headers
Write-Host "Site: $($site.displayName)  [$($site.id)]" -ForegroundColor Green

$drives = (Invoke-RestMethod -Uri "$g/sites/$($site.id)/drives" -Headers $headers).value
Write-Host "`nDocument libraries on this site:" -ForegroundColor Cyan
$drives | Select-Object name, id | Format-Table -AutoSize

$drive = $drives | Where-Object Name -eq 'PackageSources'
if (-not $drive) {
    Write-Host "Could not find a library named 'PackageSources' - check the exact name above." -ForegroundColor Red
    return
}
Write-Host "Using drive: $($drive.name)  [$($drive.id)]" -ForegroundColor Green

$top = (Invoke-RestMethod -Uri "$g/drives/$($drive.id)/root/children?`$top=999" -Headers $headers).value
Write-Host "`nTop level of PackageSources (Vendor folders, expect ~$($top.Count)):" -ForegroundColor Cyan
$top | Select-Object name, folder, size | Format-Table -AutoSize
