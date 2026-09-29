##############################################################
# Invoke-PackagingAgent.ps1  -  headless entry to the Packaging Agent FLOW.
#
#   intake -> plan -> prepare -> [evaluate: the window, it installs] -> build -> verify -> handover
#
#   .\Invoke-PackagingAgent.ps1 -Folder "\\share\Incoming\Vendor_App_x64_1.0-0001_MUL"
#         runs every stage that is ready (intake, plan, prepare) and prints where the flow stands
#   .\Invoke-PackagingAgent.ps1 -Folder <order> -Stage verify -BuiltScript <the script the tool produced>
#         one named stage: intake | plan | prepare | build | verify   (evaluate and handover belong to the window)
#   .\Invoke-PackagingAgent.ps1 -Folder <order> -Flow
#         show the flow for this order and stop - nothing is called
#
#   -NoModel     intake + rule checks only (no API call)    -Newest N   the N newest orders in RepositoryPath
#   -Open        open the HTML sheet afterwards              -Tool <folder>  use a live tool folder as the engine
# The API key / client secret come from agent.settings.json, GEMINI_API_KEY, Credential Manager or a masked prompt.
# Output: the flow + a text summary on the console, evaluation-sheet.json/.html under WorkRoot\AI\<package>\.
##############################################################
[CmdletBinding()]
param([string]$Folder, [string]$PkgName, [string]$Ritm, [switch]$NoModel, [switch]$Open, [int]$Newest = 0, [switch]$SkipPredecessor, [string]$Tool,
      [ValidateSet('', 'intake', 'plan', 'prepare', 'build', 'verify', 'handover')][string]$Stage = '', [string]$BuiltScript, [switch]$Flow)
$agentRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$root = if ($Tool) { $Tool } else { Join-Path $agentRoot 'Engine' }
if (-not (Test-Path "$root\Core.ps1")) { throw "Engine not found: $root - restore Engine\ from the repository, or point -Tool at a folder that has it" }
foreach ($f in 'Core.ps1','Predecessor.ps1','Build.ps1','Source.ps1','BundledMsi.ps1','Snapshot.ps1','Screenshots.ps1','PSADT_V3toV4_Mappings.ps1') { if (Test-Path "$root\$f") { . "$root\$f" } }
foreach ($f in 'Agent.Tools.ps1','Agent.Gemini.ps1','Agent.Docs.ps1','Agent.Prompts.ps1','Agent.Ops.ps1','Agent.Core.ps1','Agent.Brain.ps1') { . "$agentRoot\Src\$f" }
if (Test-Path "$root\SharePoint.ps1") { . "$root\SharePoint.ps1" }   # LAST - overrides source/predecessor lookups when enabled
$script:AgentSettingsPath = Join-Path $agentRoot 'agent.settings.json'
Initialize-Config $(if (Test-Path (Join-Path $root 'settings.json')) { Join-Path $root 'settings.json' } else { Join-Path $agentRoot 'engine-settings.json' })
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

$say = { param($m) Write-Host "  > $m" -ForegroundColor DarkGray }
foreach ($t in $targets) {
    Write-Host "`n=== $t" -ForegroundColor Cyan
    try {
        # Continue an order that was already started: the sheet on disk IS the flow state.
        $sheet = $null
        $name = if ("$PkgName".Trim()) { "$PkgName" } else { Split-Path -Leaf $t }
        $prev = Join-Path (Get-AgentSheetDir -Sheet @{ package = $name }) 'evaluation-sheet.json'
        if (Test-Path -LiteralPath $prev) { $sheet = Read-AgentSheet -Path $prev; if ($sheet) { Write-Host "  (continuing the sheet from $prev)" -ForegroundColor DarkGray } }
        if (-not $sheet) { $sheet = New-AgentSheet -PkgName $name -Ritm $Ritm -Folder $t }

        $with = @{ Folder = $t; PkgName = $PkgName; Ritm = $Ritm; NoModel = [bool]$NoModel; SkipPredecessor = [bool]$SkipPredecessor; BuiltScript = $BuiltScript }
        if ($Flow) { Write-Host ''; Write-Host (Format-AgentFlowText -Sheet $sheet); Write-Host '' ; continue }
        if ($Stage) { $sheet = Invoke-AgentStage -Sheet $sheet -Id $Stage -With $with -Progress $say }
        else        { $sheet = Invoke-AgentFlow  -Sheet $sheet -With $with -Progress $say }

        $v = $sheet.verification
        if ($v -and $v.verdict) {
            $col = if ("$($v.verdict)" -eq 'pass') { 'Green' } else { 'Yellow' }
            Write-Host "`n  VERDICT: $("$($v.verdict)".ToUpper())   $(@($v.findings).Count) finding(s)" -ForegroundColor $col
            foreach ($f in @($v.findings)) { Write-Host ("   [{0}] {1}: {2}" -f "$($f.severity)".ToUpper(), $f.section, $f.what) -ForegroundColor $(if ("$($f.severity)" -in 'blocker', 'major') { 'Red' } else { 'DarkGray' }) }
        }
        Write-Host (Format-AgentSheetText -Sheet $sheet)
        $paths = Save-AgentSheet -Sheet $sheet
        Write-Host "sheet: $($paths.Html)" -ForegroundColor DarkGray
        if ($Open) { try { Start-Process $paths.Html } catch {} }
    } catch { Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red }
}
