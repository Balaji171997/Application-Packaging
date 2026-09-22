##############################################################
# Invoke-PackagingAgent.ps1  -  headless entry to the Packaging Agent (order INTAKE stage).
#   powershell -ExecutionPolicy Bypass -File .\Invoke-PackagingAgent.ps1 -Folder "\\share\Incoming\Vendor_App_x64_1.0-0001_MUL" [-Open]
#   -NoModel     facts + rule checks only (no API call)
#   -Newest N    run over the N newest orders in RepositoryPath (demo / batch)
# The API key comes from GEMINI_API_KEY, Windows Credential Manager (PackagingAgent-Gemini) or a masked prompt.
# Output: text summary on the console + evaluation-sheet.json/.html under WorkRoot\AI\<package>\ (+ the audit log).
##############################################################
#   -Tool <folder>   the brand tool whose engines + settings.json to use (default: ..\MTB-PackageAssistance)
[CmdletBinding()]
param([string]$Folder, [string]$PkgName, [string]$Ritm, [switch]$NoModel, [switch]$Open, [int]$Newest = 0, [switch]$SkipPredecessor, [string]$Tool)
$agentRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = if ($Tool) { $Tool } else { Join-Path (Split-Path -Parent $agentRoot) 'MTB-PackageAssistance' }
if (-not (Test-Path "$root\Core.ps1")) { throw "Tool folder not found: $root (use -Tool)" }
foreach ($f in 'Core.ps1','Predecessor.ps1','Build.ps1','Source.ps1','MstBuilder.ps1','BundledMsi.ps1','Snapshot.ps1','Screenshots.ps1','PSADT_V3toV4_Mappings.ps1') { . "$root\$f" }
foreach ($f in 'Agent.Gemini.ps1','Agent.Docs.ps1','Agent.Core.ps1') { . "$agentRoot\$f" }
if (Test-Path "$root\SharePoint.ps1") { . "$root\SharePoint.ps1" }   # LAST - overrides source/predecessor lookups when enabled
Initialize-Config (Join-Path $root 'settings.json')
Write-Log "Packaging Agent CLI started"

if (-not $NoModel -and -not (Test-AgentHasKey)) {
    $sec = Read-Host -Prompt 'Gemini API key (session only; Enter = run without the model)' -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    if ("$plain".Trim()) { Set-AgentApiKey -Key $plain } else { $NoModel = $true }
}
$targets = @()
if ($Newest -gt 0) {
    $repo = Get-Setting 'RepositoryPath'
    $targets = @(Get-ChildItem -LiteralPath $repo -Directory -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First $Newest | ForEach-Object { $_.FullName })
} elseif ($Folder) { $targets = @($Folder) } else { throw 'Give -Folder <order folder> or -Newest N.' }

foreach ($t in $targets) {
    Write-Host "`n=== $t" -ForegroundColor Cyan
    try {
        $sheet = Invoke-AgentIntake -Folder $t -PkgName $PkgName -Ritm $Ritm -NoModel:$NoModel -SkipPredecessor:$SkipPredecessor -Progress { param($m) Write-Host "  > $m" -ForegroundColor DarkGray }
        Write-Host (Format-AgentSheetText -Sheet $sheet)
        $paths = Save-AgentSheet -Sheet $sheet
        Write-Host "sheet: $($paths.Html)" -ForegroundColor DarkGray
        if ($Open) { try { Start-Process $paths.Html } catch {} }
    } catch { Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red }
}
