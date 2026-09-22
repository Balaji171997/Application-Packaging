##############################################################
# Start-PackagingAgent.ps1  -  the Packaging Agent EXECUTOR.
#   Run-PackagingAgent.cmd                      -> opens the agent window (double-click; or drop an order folder onto the .cmd)
#   powershell -STA -ExecutionPolicy Bypass -File .\Start-PackagingAgent.ps1 [-Folder <order>] [-Tool <brand tool folder>]
#   ... -Console [-NoModel] [-NoOpen]           -> text mode (intake only, prints the summary, opens the HTML sheet)
#
# The agent is standalone: it needs a Package Assistance tool folder ONLY as a library (its engine .ps1 files +
# settings.json paths). Default: the first *PackageAssistance* folder next to this one, or -Tool.
# Agent settings: agent.settings.json in this folder (created from settings.agent.example.json on first run).
##############################################################
[CmdletBinding()]
param([string]$Folder, [string]$Tool, [switch]$Console, [switch]$NoModel, [switch]$NoOpen, [int]$List = 15)
$agentRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
function Say($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c }

# ---- 1. tool folder (engine library + settings.json) -----------------------------------------------------------------
if (-not $Tool) {
    $parent = Split-Path -Parent $agentRoot
    $cands = @('MTB-PackageAssistance', 'MTB_PackageAssistance', 'GPF-PackageAssistance', 'PAG-PackageAssistance') | ForEach-Object { Join-Path $parent $_ }
    $cands += @(Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'PackageAssistance' } | ForEach-Object { $_.FullName })
    $cands += @(Get-ChildItem -LiteralPath $agentRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })   # a tool copy INSIDE this folder
    $Tool = $cands | Where-Object { Test-Path (Join-Path $_ 'Core.ps1') } | Select-Object -First 1
}
if (-not $Tool -or -not (Test-Path (Join-Path $Tool 'Core.ps1'))) {
    $msg = "No Package Assistance tool folder found next to $agentRoot (the agent uses its engine files + settings.json as a library). Put a tool folder beside this one, or start with -Tool <folder>."
    if ($Console) { Say $msg Red; Read-Host 'Enter to close' | Out-Null } else { Add-Type -AssemblyName PresentationFramework; [Windows.MessageBox]::Show($msg, 'Packaging Agent') | Out-Null }
    exit 1
}
foreach ($f in 'Core.ps1','Theme.ps1','Predecessor.ps1','Build.ps1','Source.ps1','MstBuilder.ps1','BundledMsi.ps1','Snapshot.ps1','Screenshots.ps1','PSADT_V3toV4_Mappings.ps1') { if (Test-Path "$Tool\$f") { . "$Tool\$f" } }
foreach ($f in 'Agent.Gemini.ps1','Agent.Docs.ps1','Agent.Core.ps1','Agent.App.ps1') { . "$agentRoot\$f" }
if (Test-Path "$Tool\SharePoint.ps1") { . "$Tool\SharePoint.ps1" }   # overrides source/predecessor lookups when the tool has SharePoint on
$script:AgentRoot = $agentRoot; $script:AgentToolRoot = $Tool
$script:AgentSettingsPath = Join-Path $agentRoot 'agent.settings.json'
if (-not (Test-Path $script:AgentSettingsPath)) { try { Copy-Item (Join-Path $agentRoot 'settings.agent.example.json') $script:AgentSettingsPath } catch {} }
Initialize-Config (Join-Path $Tool 'settings.json')
Write-Log "Packaging Agent started (tool library: $Tool)"
# SharePoint sign-in, if the tool has it enabled, must happen before any window exists (same rule as the tool itself)
if ((Get-Command Get-SPWorkerToken -ErrorAction SilentlyContinue) -and (Get-SPConfig).Enabled) { try { $null = Get-SPWorkerToken } catch { Write-Log "SharePoint sign-in failed: $($_.Exception.Message)" Warning } }

# ---- 2. WINDOW mode (default) ----------------------------------------------------------------------------------------
if (-not $Console) {
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        # WPF needs STA: relaunch ourselves
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$($MyInvocation.MyCommand.Path)`"")
        if ($Folder) { $args += @('-Folder', "`"$Folder`"") }; if ($Tool) { $args += @('-Tool', "`"$Tool`"") }
        Start-Process powershell.exe -ArgumentList ($args -join ' ') -WindowStyle Hidden; exit 0
    }
    Show-AgentApp -Folder $Folder
    exit 0
}

# ---- 3. CONSOLE mode --------------------------------------------------------------------------------------------------
$host.UI.RawUI.WindowTitle = 'Packaging Agent'
Say ''; Say '  PACKAGING AGENT - order intake' Cyan; Say "  tool library: $Tool" DarkGray; Say "  model: $(Get-AgentModel)   audit: $(Get-WorkPath 'AI')" DarkGray; Say ''
if (-not $Folder) {
    $repo = Get-Setting 'RepositoryPath'; $orders = @()
    if ($repo -and (Test-Path -LiteralPath $repo)) {
        Say "  Newest orders in $repo" Gray
        $orders = @(Get-ChildItem -LiteralPath $repo -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First $List)
        for ($i = 0; $i -lt $orders.Count; $i++) { Say ("  {0,3}  {1,-64} {2:yyyy-MM-dd}" -f ($i + 1), $orders[$i].Name, $orders[$i].LastWriteTime) White }
        Say ''
    }
    $in = Read-Host '  Number from the list, or paste an order folder path'
    if ($in -match '^\d+$' -and [int]$in -ge 1 -and [int]$in -le $orders.Count) { $Folder = $orders[[int]$in - 1].FullName } else { $Folder = "$in".Trim('"', ' ') }
}
if (-not $Folder -or -not (Test-Path -LiteralPath $Folder)) { Say "  Order folder not found: $Folder" Red; Read-Host 'Enter to close' | Out-Null; exit 1 }
if (-not $NoModel -and -not (Test-AgentHasKey)) {
    $u = Read-Host "  Endpoint URL (Enter = keep '$((Get-AgentConfig).BaseUrl)'; empty + Google key = Google API directly)"
    $m = Read-Host "  Model (Enter = $(Get-AgentModel))"
    Set-AgentEndpoint -BaseUrl $u -Model $m
    $sec = Read-Host '  API key (typed hidden, kept only for this run; Enter = facts + rule checks without the model)' -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    if ("$plain".Trim()) { Set-AgentApiKey -Key $plain; $t = Test-GeminiConnection; foreach ($s in $t.Steps) { Say "    $s" DarkGray }; if ($t.Ok) { Say "  key OK - $($t.Model) answered" Green } else { Say "  key test failed: $($t.Error)" Red; $NoModel = $true } } else { $NoModel = $true }
}
if ($NoModel) { Say '  running WITHOUT the model (facts + rule checks only)' Yellow }
Say ''; Say "  Intake: $Folder" Cyan
try {
    $sheet = Invoke-AgentIntake -Folder $Folder -NoModel:$NoModel -Progress { param($m) Write-Host "    > $m" -ForegroundColor DarkGray }
    Say ''; Write-Host (Format-AgentSheetText -Sheet $sheet)
    $paths = Save-AgentSheet -Sheet $sheet
    Say "  Sheet: $($paths.Html)" Green; Say "  Audit: $(Get-AgentAuditDir)" DarkGray
    if (-not $NoOpen) { try { Start-Process $paths.Html } catch {} }
} catch { Say "  FAILED: $($_.Exception.Message)" Red }
if (-not $PSBoundParameters.ContainsKey('Folder') -or -not $NoOpen) { Say ''; Read-Host '  Enter to close' | Out-Null }
