##############################################################
# Start-PackagingAgent.ps1  -  the Packaging Agent EXECUTOR.
#   Run-PackagingAgent.cmd                      -> opens the agent window (double-click; or drop an order folder onto the .cmd)
#   powershell -STA -ExecutionPolicy Bypass -File .\Start-PackagingAgent.ps1 [-Folder <order>] [-Tool <brand tool folder>]
#   ... -Console [-NoModel] [-NoOpen]           -> text mode (intake only, prints the summary, opens the HTML sheet)
#
# STANDALONE: everything the agent needs is in THIS folder.
#   Engine\                 the agent's OWN library (source resolver, predecessor, snapshot, knowledge base) - edit it freely
#   engine-settings.json    the share paths the agent reads from
#   agent.settings.json     AI endpoint, model, headers (and optionally key/secret)
# -Tool <folder> is only for the rare case that you want to run against a live packaging tool folder instead.
##############################################################
[CmdletBinding()]
param([string]$Folder, [string]$Tool, [switch]$Console, [switch]$NoModel, [switch]$NoOpen, [int]$List = 15)
$agentRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
function Say($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c }

# ---- 1. engine library: our own copy, unless a tool folder was named explicitly ---------------------------------------
$engineRoot = if ($Tool) { $Tool } else { Join-Path $agentRoot 'Engine' }
$engineFiles = 'Core.ps1', 'Predecessor.ps1', 'Source.ps1', 'Snapshot.ps1', 'BundledMsi.ps1'
$missing = @($engineFiles | Where-Object { -not (Test-Path (Join-Path $engineRoot $_)) })
if ($missing.Count) {
    # Engine\ incomplete: rather than stopping, borrow a packaging tool folder if one happens to be next door.
    $fallback = @(Get-ChildItem -LiteralPath (Split-Path -Parent $agentRoot) -Directory -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match 'PackageAssistance' -and (Test-Path (Join-Path $_.FullName 'Core.ps1')) } |
                  Select-Object -First 1 -ExpandProperty FullName)
    if ($fallback) {
        Write-Warning "Engine\ is incomplete (missing: $($missing -join ', ')) - using $fallback for this run. Restore the missing file(s) from the repository."
        $engineRoot = $fallback
    } else {
        $msg = "The Engine folder is incomplete: $engineRoot`r`nMissing: $($missing -join ', ')`r`n`r`nRestore the missing file(s) from the repository - Engine\ is part of the agent, so they are versioned with it."
        if ($Console) { Say $msg Red; Read-Host 'Enter to close' | Out-Null } else { Add-Type -AssemblyName PresentationFramework; [Windows.MessageBox]::Show($msg, 'Packaging Agent') | Out-Null }
        exit 1
    }
}
foreach ($f in 'Core.ps1','Theme.ps1','Predecessor.ps1','Build.ps1','Source.ps1','BundledMsi.ps1','Snapshot.ps1','Screenshots.ps1','PSADT_V3toV4_Mappings.ps1') { if (Test-Path "$engineRoot\$f") { . "$engineRoot\$f" } }
$srcRoot = Join-Path $agentRoot 'Src'
foreach ($f in 'Agent.Tools.ps1','Agent.Gemini.ps1','Agent.Docs.ps1','Agent.Prompts.ps1','Agent.Ops.ps1','Agent.Core.ps1','Agent.Brain.ps1','Agent.Ui.ps1','Agent.Console.ps1') { . "$srcRoot\$f" }
if (Test-Path "$engineRoot\SharePoint.ps1") { . "$engineRoot\SharePoint.ps1" }   # only present when running against a SharePoint-enabled tool folder
# NOTE: $agentRoot and $script:AgentRoot are the SAME variable in a script - use distinct names.
$script:AgentHome = $agentRoot        # the folder itself (settings, PsExec)
$script:AgentSrc  = $srcRoot          # where the Agent.*.ps1 live (background runspaces load them from here)
$script:AgentToolRoot = $engineRoot   # the engine library
$script:AgentSettingsPath = Join-Path $agentRoot 'agent.settings.json'
if (-not (Test-Path $script:AgentSettingsPath)) { try { Copy-Item (Join-Path $agentRoot 'agent.settings.example.json') $script:AgentSettingsPath } catch {} }
# paths (shares, work folder): our own file; a named tool folder brings its own settings.json instead
$pathsFile = if ($Tool -and (Test-Path (Join-Path $Tool 'settings.json'))) { Join-Path $Tool 'settings.json' } else { Join-Path $agentRoot 'engine-settings.json' }
Initialize-Config $pathsFile
Write-Log "Packaging Agent started (engine: $engineRoot; paths: $(Split-Path -Leaf $pathsFile))"
# ELEVATION, said once and plainly. Two things need it: installing on this machine (the evaluation) and recording an
# install with Process Monitor. Started from an elevated prompt, neither asks - the agent inherits the token. Started
# normally, Windows asks for each one, which means a prompt per install attempt during a trial. Nothing breaks either
# way; it is only a question of how many prompts the packager gets, so tell them rather than letting them discover it.
$script:AgentElevated = $false
try { $script:AgentElevated = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch {}
if ($script:AgentElevated) { Write-Log 'Running elevated - installs and Process Monitor will not ask for permission.' Success }
else { Write-Log 'NOT running elevated. Windows will ask for permission for each test install and for Process Monitor. To avoid that, start the agent from an elevated prompt.' Warning }
# SharePoint sign-in, if a tool folder with SharePoint was used, must happen before any window exists
if ((Get-Command Get-SPWorkerToken -ErrorAction SilentlyContinue) -and (Get-SPConfig).Enabled) { try { $null = Get-SPWorkerToken } catch { Write-Log "SharePoint sign-in failed: $($_.Exception.Message)" Warning } }

# ---- 2. WINDOW mode (default) ----------------------------------------------------------------------------------------
if (-not $Console) {
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        # WPF needs STA: relaunch ourselves
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$($MyInvocation.MyCommand.Path)`"")
        if ($Folder) { $args += @('-Folder', "`"$Folder`"") }; if ($Tool) { $args += @('-Tool', "`"$Tool`"") }
        Start-Process powershell.exe -ArgumentList ($args -join ' ') -WindowStyle Hidden; exit 0
    }
    Show-AgentConsole -Folder $Folder
    exit 0
}

# ---- 3. CONSOLE mode --------------------------------------------------------------------------------------------------
$host.UI.RawUI.WindowTitle = 'Packaging Agent'
Say ''; Say '  PACKAGING AGENT - order intake' Cyan; Say "  engine: $engineRoot" DarkGray; Say "  model: $(Get-AgentModel)   audit: $(Get-WorkPath 'AI')" DarkGray; Say ''
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
