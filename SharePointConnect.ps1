#Install-Module PnPOnline.PowerShell -Scope CurrentUser
Import-Module "C:\Users\AW140\Downloads\PnP.PowerShell\1.12.0\PnP.PowerShell.psd1" -Verbose
(Get-Command Connect-PnPOnline).Parameters.Keys
Connect-PnPOnline -Url "https://manonlineservices.sharepoint.com/sites/SWPackaging" -ClientId "28bf2c22-437c-42e7-a4be-e8a0f44a8264" -Interactive
#Get-PnPWeb

Get-PnPFolderItem -FolderSiteRelativeUrl "PackageSources"
