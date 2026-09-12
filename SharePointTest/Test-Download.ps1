# Why does Get-PnPFile hang? Enumeration works but download does not, so this walks through the
# suspects one at a time and TIMES each. Run it in a console; if a step hangs, Ctrl+C and tell me
# which step number it stopped on - that alone identifies the cause.
#
#   .\Test-Download.ps1

$sp  = 'C:\Users\AW140\Downloads\Application-Packaging\SP-PackageBuilder'
$lib = 'PackageSources'
$verRel = 'PackageSources/Mozilla/FirefoxESRMAN/140.15.0_0001'
$sitePath = '/sites/SWPackaging'
$siteUrl  = 'https://manonlineservices.sharepoint.com/sites/SWPackaging'
$clientId = '28bf2c22-437c-42e7-a4be-e8a0f44a8264'
$dest = Join-Path $env:TEMP ('spdl_' + (Get-Date -Format 'HHmmss'))
New-Item -Path $dest -ItemType Directory -Force | Out-Null

$env:PNPPOWERSHELL_UPDATECHECK = 'Off'
Import-Module (Join-Path $sp 'Lib\PnP.PowerShell\1.12.0\PnP.PowerShell.psd1') -ErrorAction Stop

function Step { param([int]$N, [string]$What) Write-Host "`n[$N] $What" -ForegroundColor Cyan }
function Timed {
    param([string]$Label, [scriptblock]$Do)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try   { $r = & $Do; $sw.Stop(); Write-Host ("    OK   {0,-34} {1,6:N0} ms" -f $Label, $sw.Elapsed.TotalMilliseconds) -ForegroundColor Green; return $r }
    catch { $sw.Stop(); Write-Host ("    FAIL {0,-34} {1,6:N0} ms - {2}" -f $Label, $sw.Elapsed.TotalMilliseconds, $_.Exception.Message) -ForegroundColor Red; return $null }
}

Step 0 'Proxy configuration on this machine'
$proxy = [System.Net.WebRequest]::GetSystemWebProxy()
$target = [uri]$siteUrl
$via = $proxy.GetProxy($target)
Write-Host "    system proxy for that host : $via"
Write-Host "    (same as the URL = direct, different = going through a proxy)"
Write-Host "    netsh winhttp proxy        : " -NoNewline
try { (netsh winhttp show proxy) -join ' ' } catch { 'n/a' }

Step 1 'Connect'
Timed 'Connect-PnPOnline -Interactive' { Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Interactive -ErrorAction Stop; 'connected' } | Out-Null

Step 2 'Enumerate the version folder (this already works in the tool)'
$items = Timed 'Get-PnPFolderItem' { @(Get-PnPFolderItem -FolderSiteRelativeUrl $verRel -ErrorAction Stop) }
if ($items) { $items | ForEach-Object { Write-Host "      $($_.Name)" -ForegroundColor DarkGray } }

Step 3 'Enumerate Documents\ (the folder holding the file that hangs)'
$docs = Timed 'Get-PnPFolderItem Documents' { @(Get-PnPFolderItem -FolderSiteRelativeUrl "$verRel/Documents" -ErrorAction Stop) }
if ($docs) { $docs | ForEach-Object { Write-Host "      $($_.Name)  ($([int]($_.Length/1KB)) KB)" -ForegroundColor DarkGray } }

$first = @($docs)[0]
if (-not $first) { Write-Host "`nNo file found under Documents - stopping." -ForegroundColor Yellow; return }
$fileUrl = "$sitePath/$verRel/Documents/$($first.Name)"
Write-Host "`n    test file: $($first.Name)"
Write-Host "    url      : $fileUrl"

Step 4 'THE SUSPECT: Get-PnPFile -AsFile (what the tool does today)'
Write-Host '    If this is where it hangs, press Ctrl+C and tell me - that confirms it.' -ForegroundColor Yellow
Timed 'Get-PnPFile -AsFile' { Get-PnPFile -Url $fileUrl -Path $dest -FileName $first.Name -AsFile -Force -ErrorAction Stop; 'saved' } | Out-Null

Step 5 'Alternative A: -AsMemoryStream (different code path inside PnP)'
$ms = Timed 'Get-PnPFile -AsMemoryStream' { Get-PnPFile -Url $fileUrl -AsMemoryStream -ErrorAction Stop }
if ($ms) { Write-Host "      bytes: $($ms.Length)" -ForegroundColor DarkGray }

Step 6 'Alternative B: raw CSOM stream (bypasses the PnP cmdlet entirely)'
Timed 'OpenBinaryDirect' {
    $ctx = Get-PnPContext
    $fi  = [Microsoft.SharePoint.Client.File]::OpenBinaryDirect($ctx, $fileUrl)
    $out = [IO.File]::Create((Join-Path $dest ('csom_' + $first.Name)))
    $fi.Stream.CopyTo($out); $out.Close(); $fi.Stream.Close()
    'saved'
} | Out-Null

Step 7 'Alternative C: a file with NO spaces (is it the name?)'
$noSpace = @(Get-PnPFolderItem -FolderSiteRelativeUrl "$verRel/SW-Source" -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notmatch '\s' } | Select-Object -First 1)
if ($noSpace) {
    $u2 = "$sitePath/$verRel/SW-Source/$($noSpace[0].Name)"
    Write-Host "    file: $($noSpace[0].Name)"
    Timed 'Get-PnPFile (no spaces)' { Get-PnPFile -Url $u2 -Path $dest -FileName $noSpace[0].Name -AsFile -Force -ErrorAction Stop; 'saved' } | Out-Null
} else { Write-Host '    (no space-free file found to compare with)' -ForegroundColor DarkGray }

Write-Host "`nSaved into: $dest" -ForegroundColor Cyan
Get-ChildItem $dest -File | Select-Object Name, @{n='KB';e={[int]($_.Length/1KB)}} | Format-Table -AutoSize
