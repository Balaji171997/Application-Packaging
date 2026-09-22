##############################################################
# Agent.App.ps1  -  the Packaging Agent's OWN window (WPF, standalone). No wizard, no Package Assistance code path is
# changed: the tool's engine files (Source / Predecessor / Snapshot / Screenshots / Theme ...) are loaded as a LIBRARY
# by Start-PackagingAgent.ps1 before this file, and the results are handed over as files the tool can load.
#
# Flow:  [Run intake] -> facts + form/screenshots reading + assessment  (missing / questions / READY)
#        [Start evaluation] -> baseline snapshot -> proposed silent install on THIS machine -> after snapshot + diff
#        -> model classification -> change report -> [Export] writes the evaluation sheet, the snapshot report
#        (loadable by Package Assistance's "Analyze installer > Load report...") and agent-handover.json.
# All handlers are PLAIN scriptblocks (modal window = they run in this function's dynamic scope); background work is
# polled by ONE DispatcherTimer through the shared $ctx hashtable.
##############################################################
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms -ErrorAction SilentlyContinue
$script:AgentWin = $null

# ---- small WPF helpers (self-contained) ------------------------------------------------------------------------------
function Set-AgentTheme { param($Window) if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $Window }; $Window.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x18,0x1A,0x1F))); $Window.FontFamily = 'Segoe UI'; $Window.FontSize = 13 }
function New-AgentButton { param([string]$Glyph, [string]$Text, [string]$ToolTip, [switch]$Accent, [string]$Margin = '0,0,8,0')
    $b = New-Object Windows.Controls.Button; $b.Padding = '12,5'; $b.Margin = $Margin; $b.VerticalAlignment = 'Center'
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    if ($Glyph) { $g = New-Object Windows.Controls.TextBlock; $g.Text = [string][char][Convert]::ToInt32($Glyph, 16); $g.FontFamily = 'Segoe MDL2 Assets'; $g.FontSize = 13; $g.VerticalAlignment = 'Center'; $g.Margin = '0,1,7,0'; [void]$sp.Children.Add($g) }
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $Text; $t.VerticalAlignment = 'Center'; [void]$sp.Children.Add($t)
    $b.Content = $sp; if ($ToolTip) { $b.ToolTip = $ToolTip }
    if ($Accent) { try { $b.Style = $script:AgentWin.FindResource('PbAccentButton') } catch { $b.Background = '#2BA6B8'; $b.Foreground = '#0E1013' } }
    return $b
}
function New-AgentText { param([string]$Text, [string]$Color = '#E7E9ED', [double]$Size = 12.5, [string]$Margin = '0,0,0,4', [switch]$Bold, [switch]$Mono)
    $tb = New-Object Windows.Controls.TextBox; $tb.Text = "$Text"; $tb.IsReadOnly = $true; $tb.BorderThickness = '0'; $tb.Background = 'Transparent'; $tb.Foreground = $Color; $tb.FontSize = $Size; $tb.TextWrapping = 'Wrap'; $tb.Margin = $Margin; $tb.Padding = '0'
    if ($Bold) { $tb.FontWeight = 'SemiBold' }; if ($Mono) { $tb.FontFamily = 'Consolas' }
    try { $tb.Style = $script:AgentWin.FindResource('PbCopyText') } catch {}
    return $tb
}
function New-AgentCard { param([string]$Title, [string]$Accent = '#2A2F38', [string]$Background = '#1E2128')
    $b = New-Object Windows.Controls.Border; $b.Background = $Background; $b.BorderBrush = $Accent; $b.BorderThickness = '3,1,1,1'; $b.CornerRadius = '5'; $b.Padding = '12,9'; $b.Margin = '0,0,0,8'
    $sp = New-Object Windows.Controls.StackPanel
    if ($Title) { $c = New-Object Windows.Controls.TextBlock; $c.Text = $Title.ToUpper(); $c.FontSize = 10; $c.FontWeight = 'SemiBold'; $c.Foreground = '#A0A8B4'; $c.Margin = '0,0,0,6'; [void]$sp.Children.Add($c) }
    $b.Child = $sp; return $b
}
function New-AgentHeader { param([string]$Title, [string]$Subtitle)
    $band = New-Object Windows.Controls.Border; $band.Background = '#1F232B'; $band.BorderBrush = '#2E3340'; $band.BorderThickness = '0,0,0,1'; $band.Padding = '16,9'
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    $gl = New-Object Windows.Controls.TextBlock; $gl.Text = [string][char]0xE82F; $gl.FontFamily = 'Segoe MDL2 Assets'; $gl.FontSize = 14; $gl.Foreground = '#56C8D6'; $gl.VerticalAlignment = 'Center'; $gl.Margin = '0,1,9,0'
    $tt = New-Object Windows.Controls.TextBlock; $tt.Text = $Title; $tt.FontSize = 14; $tt.FontWeight = 'SemiBold'; $tt.Foreground = '#F2F4F7'; $tt.VerticalAlignment = 'Center'
    $st = New-Object Windows.Controls.TextBlock; $st.Text = $Subtitle; $st.FontSize = 11.5; $st.Foreground = '#A0A8B4'; $st.VerticalAlignment = 'Center'; $st.Margin = '14,1,0,0'
    [void]$sp.Children.Add($gl); [void]$sp.Children.Add($tt); [void]$sp.Children.Add($st); $band.Child = $sp; return $band
}

# ---- API key dialog: masked, session-only by default; optional Credential Manager store ------------------------------
function Show-AgentKeyDialog {
    $win = New-Object Windows.Window
    $win.Title = 'Gemini API key'; $win.Width = 560; $win.SizeToContent = 'Height'; $win.WindowStartupLocation = 'CenterOwner'; $win.ResizeMode = 'NoResize'
    try { if ($script:AgentWin) { $win.Owner = $script:AgentWin } } catch {}
    Set-AgentTheme $win
    $g = New-Object Windows.Controls.StackPanel; $g.Margin = '16,14'
    $t = New-Object Windows.Controls.TextBlock; $t.Text = 'Endpoint URL, model and API key as you received them. Everything stays in memory for this session; nothing is written unless you tick "remember" (URL + model go to agent.settings.json, the key to Windows Credential Manager).'; $t.Foreground = '#B7BEC8'; $t.TextWrapping = 'Wrap'; $t.Margin = '0,0,0,10'; [void]$g.Children.Add($t)
    $cfg0 = Get-AgentConfig
    $lu = New-Object Windows.Controls.TextBlock; $lu.Text = 'Endpoint URL  (empty = Google Gemini API directly; a sk-... key needs its gateway URL, e.g. https://gateway.company.com/v1)'; $lu.Foreground = '#A0A8B4'; $lu.FontSize = 11.5; [void]$g.Children.Add($lu)
    $tbUrl = New-Object Windows.Controls.TextBox; $tbUrl.Height = 28; $tbUrl.FontFamily = 'Consolas'; $tbUrl.FontSize = 12.5; $tbUrl.Text = "$($cfg0.BaseUrl)"; $tbUrl.Margin = '0,2,0,8'; [void]$g.Children.Add($tbUrl)
    $lm = New-Object Windows.Controls.TextBlock; $lm.Text = 'Model name  (as the provider lists it, e.g. gemini-2.5-flash-lite)'; $lm.Foreground = '#A0A8B4'; $lm.FontSize = 11.5; [void]$g.Children.Add($lm)
    $tbModel = New-Object Windows.Controls.TextBox; $tbModel.Height = 28; $tbModel.FontFamily = 'Consolas'; $tbModel.FontSize = 12.5; $tbModel.Text = "$($cfg0.Model)"; $tbModel.Margin = '0,2,0,8'; [void]$g.Children.Add($tbModel)
    $lk = New-Object Windows.Controls.TextBlock; $lk.Text = 'API key  (sk-... or AIza...)'; $lk.Foreground = '#A0A8B4'; $lk.FontSize = 11.5; [void]$g.Children.Add($lk)
    $pb = New-Object Windows.Controls.PasswordBox; $pb.Height = 30; $pb.FontFamily = 'Consolas'; $pb.FontSize = 13; $pb.Margin = '0,2,0,8'; [void]$g.Children.Add($pb)
    $lt = New-Object Windows.Controls.TextBlock; $lt.Text = 'Only if the gateway sits behind an identity provider (client id + secret): token URL  (…/protocol/openid-connect/token)'; $lt.Foreground = '#A0A8B4'; $lt.FontSize = 11.5; [void]$g.Children.Add($lt)
    $tbTok = New-Object Windows.Controls.TextBox; $tbTok.Height = 28; $tbTok.FontFamily = 'Consolas'; $tbTok.FontSize = 12.5; $tbTok.Text = "$($cfg0.TokenUrl)"; $tbTok.Margin = '0,2,0,6'; [void]$g.Children.Add($tbTok)
    $row = New-Object Windows.Controls.Grid; foreach ($w in '*', '12', '*') { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $w; [void]$row.ColumnDefinitions.Add($cd) }
    $c1 = New-Object Windows.Controls.StackPanel; $lc = New-Object Windows.Controls.TextBlock; $lc.Text = 'Client ID'; $lc.Foreground = '#A0A8B4'; $lc.FontSize = 11.5; [void]$c1.Children.Add($lc)
    $tbCid = New-Object Windows.Controls.TextBox; $tbCid.Height = 28; $tbCid.FontFamily = 'Consolas'; $tbCid.FontSize = 12.5; $tbCid.Text = "$($cfg0.ClientId)"; $tbCid.Margin = '0,2,0,0'; [void]$c1.Children.Add($tbCid)
    $c2 = New-Object Windows.Controls.StackPanel; $ls = New-Object Windows.Controls.TextBlock; $ls.Text = 'Client secret  (memory only, never stored)'; $ls.Foreground = '#A0A8B4'; $ls.FontSize = 11.5; [void]$c2.Children.Add($ls)
    $pbSec = New-Object Windows.Controls.PasswordBox; $pbSec.Height = 28; $pbSec.FontFamily = 'Consolas'; $pbSec.FontSize = 12.5; $pbSec.Margin = '0,2,0,0'; [void]$c2.Children.Add($pbSec)
    [Windows.Controls.Grid]::SetColumn($c1, 0); [Windows.Controls.Grid]::SetColumn($c2, 2); [void]$row.Children.Add($c1); [void]$row.Children.Add($c2); [void]$g.Children.Add($row)
    $chk = New-Object Windows.Controls.CheckBox; $chk.Content = 'Remember on this machine (URLs, model, client id -> agent.settings.json; key -> Credential Manager; secret never)'; $chk.Foreground = '#E7E9ED'; $chk.Margin = '0,10,0,0'; [void]$g.Children.Add($chk)
    $applyEndpoint = { if ("$($pb.Password)".Trim()) { Set-AgentApiKey -Key $pb.Password -Remember:([bool]$chk.IsChecked) }; Set-AgentAuth -TokenUrl $tbTok.Text -ClientId $tbCid.Text -ClientSecret $pbSec.Password; Set-AgentEndpoint -BaseUrl $tbUrl.Text -Model $tbModel.Text -Remember:([bool]$chk.IsChecked) }
    # results: a scrollable, copyable box (the probe / TLS diagnostics can be 30+ lines)
    $lbl = New-Object Windows.Controls.TextBox; $lbl.Foreground = '#A0A8B4'; $lbl.FontSize = 12; $lbl.TextWrapping = 'Wrap'; $lbl.Margin = '0,10,0,0'; $lbl.IsReadOnly = $true; $lbl.AcceptsReturn = $true; $lbl.Height = 220; $lbl.VerticalScrollBarVisibility = 'Auto'; $lbl.Background = '#0C0C0C'; $lbl.BorderThickness = '1'; $lbl.BorderBrush = '#2A2F38'; $lbl.FontFamily = 'Consolas'; $lbl.Padding = '6'
    $lbl.Text = if (Test-AgentHasKey) { "A key is already set ($($script:PkgAgent.KeySource)). Leave empty to keep it." } else { 'No key set. Fill the fields and click Test - the result (incl. gateway probe + certificate check) appears here.' }
    [void]$g.Children.Add($lbl)
    $bar = New-Object Windows.Controls.StackPanel; $bar.Orientation = 'Horizontal'; $bar.HorizontalAlignment = 'Right'; $bar.Margin = '0,14,0,0'
    $bTest = New-Object Windows.Controls.Button; $bTest.Content = 'Test'; $bTest.Padding = '14,4'; $bTest.Margin = '0,0,8,0'
    $bForget = New-Object Windows.Controls.Button; $bForget.Content = 'Forget'; $bForget.Padding = '14,4'; $bForget.Margin = '0,0,8,0'; $bForget.ToolTip = 'Clear the key from this session and from Credential Manager.'
    $ok = New-Object Windows.Controls.Button; $ok.Content = 'Use key'; $ok.Padding = '16,4'; $ok.Margin = '0,0,8,0'; $ok.IsDefault = $true; try { $ok.Style = $win.FindResource('PbAccentButton') } catch {}
    $cn = New-Object Windows.Controls.Button; $cn.Content = 'Cancel'; $cn.Padding = '14,4'; $cn.IsCancel = $true
    foreach ($b in @($bTest, $bForget, $ok, $cn)) { [void]$bar.Children.Add($b) }
    [void]$g.Children.Add($bar)
    $bTest.add_Click({
        if ("$($pb.Password)".Trim()) { Set-AgentApiKey -Key $pb.Password }
        Set-AgentAuth -TokenUrl $tbTok.Text -ClientId $tbCid.Text -ClientSecret $pbSec.Password
        Set-AgentEndpoint -BaseUrl $tbUrl.Text -Model $tbModel.Text
        if (-not (Test-AgentHasKey) -and -not "$($pbSec.Password)".Trim()) { $lbl.Text = 'Enter a key (or client id + secret) first.'; return }
        $lbl.Text = 'Testing (name resolution -> proxy -> service -> key -> model)...'; try { $win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch {}
        $r = Test-GeminiConnection
        $lbl.Text = (@($r.Steps) -join "`n")
        $lbl.Foreground = if ($r.Ok) { '#6A9955' } else { '#F48771' }
    })
    $bForget.add_Click({ Set-AgentApiKey -Forget; $pb.Password = ''; $lbl.Text = 'Key cleared.'; $lbl.Foreground = '#A0A8B4' })
    $ok.add_Click({ & $applyEndpoint; $win.DialogResult = [bool]((Test-AgentHasKey) -or "$($pbSec.Password)".Trim()) })
    $root = New-Object Windows.Controls.StackPanel; [void]$root.Children.Add((New-AgentHeader -Title 'Gemini API key' -Subtitle 'session only unless you tick remember')); [void]$root.Children.Add($g)
    $win.Content = $root
    return [bool]$win.ShowDialog()
}
function Confirm-AgentKey { if (Test-AgentHasKey) { return $true }; return (Show-AgentKeyDialog) }

# ---- background runspace: the tool's engine files + the agent, loaded as a library --------------------------------------
function Start-AgentRunspace {
    param([Parameter(Mandatory)][string]$Script, [hashtable]$Arg = @{})
    $box = [hashtable]::Synchronized(@{ Done = $false; Result = $null; Error = ''; Progress = '' })
    $payload = @{ tool = "$script:AgentToolRoot"; agent = "$script:AgentRoot"; settings = "$script:AgentSettingsPath"; script = $Script; arg = $Arg; box = $box; key = "$($script:PkgAgent.ApiKey)" }
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $ps = [PowerShell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($p)
        try {
            foreach ($f in 'Core.ps1', 'Predecessor.ps1', 'Source.ps1', 'BundledMsi.ps1', 'Snapshot.ps1', 'Screenshots.ps1') { . "$($p.tool)\$f" }
            foreach ($f in 'Agent.Gemini.ps1', 'Agent.Docs.ps1', 'Agent.Core.ps1') { . "$($p.agent)\$f" }
            Initialize-Config (Join-Path $p.tool 'settings.json')
            $script:AgentSettingsPath = $p.settings
            if ($p.key) { Set-AgentApiKey -Key $p.key }
            $p.box.Result = (& ([scriptblock]::Create($p.script)) $p.arg $p.box)
        } catch { $p.box.Error = "$($_.Exception.Message)" }
        finally { $p.box.Done = $true }
    }).AddArgument($payload)
    $box['_ps'] = $ps; $box['_rs'] = $rs; $box['_h'] = $ps.BeginInvoke()
    return $box
}
function Stop-AgentRunspace { param($Box) try { $Box._ps.EndInvoke($Box._h) } catch {}; try { $Box._ps.Dispose(); $Box._rs.Close(); $Box._rs.Dispose() } catch {} }

# The analyze step = exactly what Package Assistance's analyzer computes (engine functions only), run in a runspace.
$script:AgentAnalyzeScript = @'
param($a, $box)
$before = $a.before; $vend = $a.vendor; $app = $a.app
$box.Progress = 'capturing the AFTER snapshot'
$after = Get-MachineSnapshot
$box.Progress = 'diffing'
$diff = Compare-MachineSnapshot -Before $before -After $after -AppVendor $vend -AppName $app
$appTokens = if (Get-Command Get-SnapshotAppTokens -EA SilentlyContinue) { Get-SnapshotAppTokens -Vendor $vend -AppName $app -Diff $diff } else { Get-AppMatchTokens -Vendor $vend -AppName $app }
$fileDiff = Get-SnapshotRawDiff -Before $before -After $after -Kind Files    -AppTokens $appTokens
$regDiff  = Get-SnapshotRawDiff -Before $before -After $after -Kind Registry -AppTokens $appTokens
$un = Get-UninstallFromSnapshotDiff -Diff $diff -AppName $app
$envChanges = @(Get-EnvDiff -Before $before -After $after)
$reportText = Get-SnapshotReportText -Diff $diff -FileDiff $fileDiff -RegDiff $regDiff -EnvChanges $envChanges -Un $un -AppTokens $appTokens
$changeSet = New-SnapshotChangeSet -Diff $diff -FileDiff $fileDiff -RegDiff $regDiff -EnvChanges $envChanges -AppName ("$vend $app".Trim())
$shortcuts = if (Get-Command Get-AppStartMenuShortcuts -EA SilentlyContinue) { @(Get-AppStartMenuShortcuts -Diff $diff -AppTokens $appTokens) } else { @() }
$hkcu      = if (Get-Command Get-SnapshotHkcuValues -EA SilentlyContinue) { @(Get-SnapshotHkcuValues -RegDiff $regDiff -AppTokens $appTokens) } else { @() }
$userFiles = if (Get-Command Get-SnapshotUserFiles -EA SilentlyContinue) { @(Get-SnapshotUserFiles -FileDiff $fileDiff -AppTokens $appTokens) } else { @() }
$leftover  = if (Get-Command Get-LeftoverCandidates -EA SilentlyContinue) { Get-LeftoverCandidates -Diff $diff -FileDiff $fileDiff -RegDiff $regDiff -Vendor "$vend" -App "$app" } else { $null }
$cleanups  = if (Get-Command Get-SnapshotCleanups -EA SilentlyContinue) { @(Get-SnapshotCleanups -Diff $diff -AppName $app -FileDiff $fileDiff -EnvChanges $envChanges) } else { @() }
@{ After=$after; Diff=$diff; AppTokens=$appTokens; FileDiff=$fileDiff; RegDiff=$regDiff; Un=$un; EnvChanges=$envChanges; ReportText=$reportText; ChangeSet=$changeSet; Shortcuts=$shortcuts; Hkcu=$hkcu; UserFiles=$userFiles; LeftoverCandidates=$leftover; Cleanups=$cleanups }
'@

# ---- rendering ----------------------------------------------------------------------------------------------------
function Update-AgentSheetView {
    param([Parameter(Mandatory)]$Panel, $Sheet, $Ctx)
    $Panel.Children.Clear()
    if (-not $Sheet) { [void]$Panel.Children.Add((New-AgentText -Text 'Pick an order and click Run intake: the agent reads the form (incl. the wizard screenshots), the installers, the predecessor package and the knowledge base. Nothing is installed and nothing is sent to the AO.' -Color '#B7BEC8')); return }
    $a = $Sheet.assessment; $d = $Sheet.decision
    $statusCol = switch ("$($Sheet.status)") { 'ready' { '#6A9955' } 'evaluated' { '#56C8D6' } 'ask_ao' { '#E0BE7C' } 'blocked' { '#F48771' } default { '#A0A8B4' } }
    $statusTxt = switch ("$($Sheet.status)") { 'ready' { 'READY - nothing missing, evaluation can start' } 'ask_ao' { 'QUESTIONS FOR THE AO - evaluation can still start' } 'blocked' { 'BLOCKED - the order is incomplete' } 'evaluated' { 'EVALUATED - review the decision, then export' } default { "$($Sheet.status)" } }
    $head = New-AgentCard -Title '' -Accent $statusCol
    [void]$head.Child.Children.Add((New-AgentText -Text $statusTxt -Color $statusCol -Size 13.5 -Bold))
    if ($a -and "$($a.summaryForPackager)".Trim()) { [void]$head.Child.Children.Add((New-AgentText -Text "$($a.summaryForPackager)" -Margin '0,4,0,0')) }
    if ($a -and $a.fastLane -eq $true) { [void]$head.Child.Children.Add((New-AgentText -Text "Fast lane: $($a.fastLaneReason)" -Color '#56C8D6' -Margin '0,4,0,0')) }
    [void]$Panel.Children.Add($head)
    $blocks = @(Get-AgentList $Sheet.gaps | Where-Object { $_.severity -eq 'block' } | ForEach-Object { $_.text }) + @(Get-AgentList $a.blockers)
    $asks = @(Get-AgentList $Sheet.gaps | Where-Object { $_.severity -eq 'ask' } | ForEach-Object { $_.text })
    $qs = @(Get-AgentList $a.questionsForAO)
    $infos = @(Get-AgentList $Sheet.gaps | Where-Object { $_.severity -eq 'info' } | ForEach-Object { $_.text })
    if ($blocks.Count -or $asks.Count -or $qs.Count -or $infos.Count) {
        $card = New-AgentCard -Title 'Missing / to clarify with the AO' -Accent $(if ($blocks.Count) { '#F48771' } elseif ($asks.Count -or $qs.Count) { '#E0BE7C' } else { '#2A2F38' })
        foreach ($b in $blocks) { [void]$card.Child.Children.Add((New-AgentText -Text "BLOCKED   $b" -Color '#F48771')) }
        foreach ($q in $asks) { [void]$card.Child.Children.Add((New-AgentText -Text "?   $q" -Color '#E0BE7C')) }
        foreach ($q in $qs) { [void]$card.Child.Children.Add((New-AgentText -Text "?   [$($q.topic)] $($q.question)" -Color '#E0BE7C')); if ("$($q.why)".Trim()) { [void]$card.Child.Children.Add((New-AgentText -Text "        $($q.why)" -Color '#A0A8B4' -Size 11.5)) } }
        foreach ($i in $infos) { [void]$card.Child.Children.Add((New-AgentText -Text "i   $i" -Color '#A0A8B4')) }
        [void]$Panel.Children.Add($card)
    }
    $src = $Sheet.sources; $h = $Sheet.history
    $inst = @(Get-AgentList $src.installers | ForEach-Object { "$($_.name) [$($_.engine)$(if ($_.arch) { ", $($_.arch)" })$(if ($_.version) { ", v$($_.version)" })$(if ($_.isPrerequisite) { ', prerequisite' })]" })
    $fc = New-AgentCard -Title 'What the tool found'
    [void]$fc.Child.Children.Add((New-AgentText -Text "Installers ($($src.allInstallerCount)): $(if ($inst.Count) { $inst -join ' · ' } else { 'none' })" -Mono -Size 12))
    [void]$fc.Child.Children.Add((New-AgentText -Text "Form: $(if ($Sheet.documents.form) { [IO.Path]::GetFileName($Sheet.documents.form) + " ($($Sheet.documents.formImages) screenshots)" } else { 'none' })   Complexity matrix: $(if ($Sheet.documents.complexity) { 'yes' } else { 'no' })   RITM: $($Sheet.ritm)" -Color '#B7BEC8' -Size 12))
    if ($h.predecessor) { [void]$fc.Child.Children.Add((New-AgentText -Text "Predecessor: $($h.predecessor.name) (PSADT $($h.predecessor.psadt), $($h.predecessor.type)) - install: $((Get-AgentList $h.predecessor.installSeq) -join ' ; ')" -Color '#56C8D6' -Size 12)) }
    elseif ((Get-AgentList $h.predecessorCandidates).Count) { [void]$fc.Child.Children.Add((New-AgentText -Text "Predecessor candidates: $((Get-AgentList $h.predecessorCandidates | ForEach-Object { "$($_.name) ($($_.note))" }) -join ', ')" -Color '#56C8D6' -Size 12)) }
    else { [void]$fc.Child.Children.Add((New-AgentText -Text 'Predecessor: none in the catalogue (new product)' -Color '#B7BEC8' -Size 12)) }
    foreach ($k in (Get-AgentList $h.kb)) { if ("$($k.install)".Trim() -or $k.packagedAsMsi) { [void]$fc.Child.Children.Add((New-AgentText -Text "Knowledge base ($($k.installer)): $($k.install)$(if ("$($k.uninstall)".Trim()) { "   uninstall: $($k.uninstallExe) $($k.uninstall)" })   [$($k.confidence): $($k.source)]" -Color '#D7FFD7' -Mono -Size 12)) } }
    [void]$Panel.Children.Add($fc)
    if ($a -and $a.packagingMethod) {
        $pm = $a.packagingMethod
        $pc = New-AgentCard -Title 'Proposed packaging method' -Accent '#56C8D6'
        [void]$pc.Child.Children.Add((New-AgentText -Text "$($pm.method)   -   $($pm.reason)" -Bold))
        $i = 0; foreach ($c in (Get-AgentList $pm.installCandidates)) { $i++; [void]$pc.Child.Children.Add((New-AgentText -Text "$i.  $($c.installer) $($c.command)" -Mono -Color '#D7FFD7')); [void]$pc.Child.Children.Add((New-AgentText -Text "     uninstall: $($c.uninstall)    [$($c.source), $($c.confidence)] $($c.note)" -Color '#A0A8B4' -Size 11.5)) }
        foreach ($pair in @(@('Install order', ((Get-AgentList $pm.installOrder) -join ' -> ')), @('Configuration to script', ((Get-AgentList $pm.configurationToScript) -join '; ')), @('Auto-update', "$($pm.autoUpdateHandling)"), @('Per-user config expected', "$($pm.perUserConfigExpected)"), @('Detection', "$($pm.detectionSuggestion)"), @('Predecessor reuse', "$($pm.reuseOfPredecessor)"))) {
            if ("$($pair[1])".Trim()) { [void]$pc.Child.Children.Add((New-AgentText -Text "$($pair[0]): $($pair[1])" -Color '#B7BEC8' -Size 12)) }
        }
        if ($a.snapshotPlan) { $sp = $a.snapshotPlan; [void]$pc.Child.Children.Add((New-AgentText -Text "Evaluation on this machine: run $($sp.installerToRun) $($sp.argsToRun) as $($sp.runAs); watch: $((Get-AgentList $sp.whatToWatch) -join '; ')$(if ((Get-AgentList $sp.warnings).Count) { "   WARNING: $((Get-AgentList $sp.warnings) -join '; ')" })" -Color '#E7E9ED' -Size 12 -Margin '0,6,0,0')) }
        if ((Get-AgentList $a.risks).Count) { [void]$pc.Child.Children.Add((New-AgentText -Text "Risks: $((Get-AgentList $a.risks) -join ' · ')" -Color '#E0BE7C' -Size 12)) }
        [void]$Panel.Children.Add($pc)
    } elseif ($a -and $a.error) { $ec = New-AgentCard -Title 'Assessment' -Accent '#F48771'; [void]$ec.Child.Children.Add((New-AgentText -Text "Model call failed: $($a.error)" -Color '#F48771')); [void]$Panel.Children.Add($ec) }
    if ($Sheet.observed -and $Sheet.observed.run) {
        $run = $Sheet.observed.run; $sn = $Sheet.observed.snapshot
        $oc = New-AgentCard -Title 'Observed on this machine (snapshot)' -Accent '#2BA6B8'
        [void]$oc.Child.Children.Add((New-AgentText -Text "Ran: $($run.Command)   as $($run.RunAs)   exit $($run.ExitCode) in $($run.DurationSec)s   $(if ((Get-AgentList $run.WindowsSeen).Count) { "WINDOWS SEEN: $((Get-AgentList $run.WindowsSeen) -join ' | ')" } else { 'no window - silent' })$(if ($run.TimedOut) { '   TIMED OUT' })$(if ($run.Error) { "   ERROR: $($run.Error)" })" -Mono -Size 12))
        if ($sn.counts) { [void]$oc.Child.Children.Add((New-AgentText -Text "$($sn.counts.new) added · $($sn.counts.modified) modified · $($sn.counts.deleted) removed   (Show changes = the full tree)" -Color '#B7BEC8' -Size 12)) }
        foreach ($p in (Get-AgentList $sn.Programs.added)) { [void]$oc.Child.Children.Add((New-AgentText -Text "ARP: $($p.DisplayName) $($p.DisplayVersion)  ($($p.Publisher))   uninstall: $($p.UninstallString)" -Size 12 -Mono)) }
        foreach ($p in (Get-AgentList $sn.Services.added)) { [void]$oc.Child.Children.Add((New-AgentText -Text "Service: $($p.DisplayName) [$($p.Start)]" -Size 12 -Color '#B7BEC8')) }
        foreach ($p in (Get-AgentList $sn.Tasks.added)) { [void]$oc.Child.Children.Add((New-AgentText -Text "Task: $($p.Path)$($p.Name) - $($p.Action)" -Size 12 -Color '#B7BEC8')) }
        foreach ($p in (Get-AgentList $sn.RunKeys.added)) { [void]$oc.Child.Children.Add((New-AgentText -Text "Autostart: $($p.Name) = $($p.Command)" -Size 12 -Color '#B7BEC8')) }
        foreach ($p in (Get-AgentList $sn.Shortcuts.added)) { [void]$oc.Child.Children.Add((New-AgentText -Text "Shortcut: $($p.id)" -Size 12 -Color '#B7BEC8')) }
        [void]$Panel.Children.Add($oc)
    }
    if ($d -and $d.Count -and -not $d.error) {
        $dc = New-AgentCard -Title "Decision after the snapshot   [$($d.confidence)]" -Accent '#6A9955'
        [void]$dc.Child.Children.Add((New-AgentText -Text "$($d.packagingMethod.method)   -   $($d.packagingMethod.reason)" -Bold))
        [void]$dc.Child.Children.Add((New-AgentText -Text "install:    $($d.packagingMethod.installCommand)" -Mono -Color '#D7FFD7'))
        [void]$dc.Child.Children.Add((New-AgentText -Text "uninstall:  $($d.packagingMethod.uninstallCommand)" -Mono -Color '#FFE7C2'))
        [void]$dc.Child.Children.Add((New-AgentText -Text "Install run: silent=$($d.installOutcome.silent)  exit ok=$($d.installOutcome.exitCodeOk)  as expected=$($d.installOutcome.installedAsExpected)   $($d.installOutcome.notes)" -Color '#B7BEC8' -Size 12))
        if ($d.autoUpdate -and $d.autoUpdate.found) { [void]$dc.Child.Children.Add((New-AgentText -Text "Auto-update: $($d.autoUpdate.mechanism) -> $($d.autoUpdate.disableAction)" -Color '#E0BE7C' -Size 12)); foreach ($c in (Get-AgentList $d.autoUpdate.commands)) { [void]$dc.Child.Children.Add((New-AgentText -Text "    $c" -Mono -Size 11.5 -Color '#D7FFD7')) } }
        if ($d.perUser) { [void]$dc.Child.Children.Add((New-AgentText -Text "Per-user config: $($d.perUser.mode)$(if ("$($d.perUser.what)".Trim()) { " - $($d.perUser.what)" })" -Color '#B7BEC8' -Size 12)) }
        if ($d.detection) { [void]$dc.Child.Children.Add((New-AgentText -Text "Detection: $($d.detection.type) $($d.detection.key) $($d.detection.value)" -Color '#B7BEC8' -Size 12)) }
        [void]$dc.Child.Children.Add((New-AgentText -Text 'What the installer did - verdicts (keep / remove / disable / review):' -Color '#A0A8B4' -Size 11 -Margin '0,6,0,2'))
        foreach ($it in (Get-AgentList $d.items)) {
            $col = switch ("$($it.action)") { 'remove' { '#F48771' } 'disable' { '#E0BE7C' } 'review' { '#E0BE7C' } default { '#6A9955' } }
            [void]$dc.Child.Children.Add((New-AgentText -Text "[$("$($it.action)".ToUpper())]  $($it.category): $($it.label)  -  $($it.verdict); $($it.reason)$(if ("$($it.command)".Trim()) { "`n        $($it.command)" })" -Color $col -Size 12))
        }
        foreach ($pair in @(@('Pre-install', ((Get-AgentList $d.preInstall) -join '; ')), @('Post-install', ((Get-AgentList $d.postInstall) -join '; ')), @('Post-uninstall cleanup', ((Get-AgentList $d.postUninstallCleanup) -join '; ')))) { if ("$($pair[1])".Trim()) { [void]$dc.Child.Children.Add((New-AgentText -Text "$($pair[0]): $($pair[1])" -Color '#B7BEC8' -Size 12)) } }
        foreach ($hd in (Get-AgentList $d.needsHumanDecision)) { [void]$dc.Child.Children.Add((New-AgentText -Text "YOUR DECISION:  $hd" -Color '#E0BE7C' -Size 12 -Bold)) }
        if ("$($d.summary)".Trim()) { [void]$dc.Child.Children.Add((New-AgentText -Text "$($d.summary)" -Margin '0,6,0,0')) }
        [void]$Panel.Children.Add($dc)
    } elseif ($d -and $d.error) { $ec = New-AgentCard -Title 'Decision' -Accent '#F48771'; [void]$ec.Child.Children.Add((New-AgentText -Text "Model call failed: $($d.error) - the snapshot result is still available (Show changes / Export write the tool's own findings)." -Color '#F48771')); [void]$Panel.Children.Add($ec) }
}

# ---- export: evaluation sheet + snapshot report (loadable by Package Assistance) + handover json ----------------------
function Get-AgentArgsOnly { param([string]$Command, [string]$InstallerName)
    $c = "$Command".Trim(); if (-not $c) { return '' }
    $c = [regex]::Replace($c, '^(?:msiexec(?:\.exe)?\s+)?', '')
    if ($InstallerName) { $c = [regex]::Replace($c, '^["'']?[^"'']*' + [regex]::Escape($InstallerName) + '["'']?\s*', '', 'IgnoreCase') }
    $c = [regex]::Replace($c, '^["'']?[A-Za-z]:\\[^"'']+\.(exe|msi|msp)["'']?\s*', '', 'IgnoreCase')
    $c = [regex]::Replace($c, '^["'']?[^\s"'']+\.(exe|msi|msp)["'']?\s*', '', 'IgnoreCase')
    $c = [regex]::Replace($c, '(?i)^/i\s+["'']?[^"''\s]+\.msi["'']?\s*', '')
    return $c.Trim()
}
function Export-AgentEvaluation {
    param([Parameter(Mandatory)]$Ctx)
    $sheet = $Ctx.Sheet; $res = $Ctx.Result; $dec = $sheet.decision; $run = $Ctx.RunInfo
    $paths = Save-AgentSheet -Sheet $sheet
    $out = @{ Sheet = $paths.Html; Dir = $paths.Dir; SnapshotReport = ''; Handover = '' }
    $pkg = "$($sheet.package)"
    if ($res) {
        $items = @(Get-AgentList $dec.items)
        $exclusions = @(); $cleanupCmds = @(); $notes = @()
        foreach ($cc in @(Get-AgentList $res.Cleanups)) {
            $hit = $items | Where-Object { "$($_.action)" -in 'remove', 'disable' -and "$($_.label)".Length -ge 4 -and ("$($cc.Label)" -match [regex]::Escape("$($_.label)")) } | Select-Object -First 1
            $on = [bool]$cc.Default -or [bool]$hit
            $exclusions += [pscustomobject]@{ Label = "$($cc.Label)"; Command = "$($cc.Command)"; Checked = $on }
            if ($on -and "$($cc.Command)".Trim() -and "$($cc.Command)" -notmatch '(?i)#\s*\[post-uninstall\]') { $cleanupCmds += "$($cc.Command)"; $notes += "Exclusion$(if ($hit) { ' (agent)' }): $($cc.Label)" }
        }
        foreach ($c in @(Get-AgentList $dec.autoUpdate.commands) + @($items | Where-Object { "$($_.command)".Trim() -and "$($_.action)" -in 'remove', 'disable' } | ForEach-Object { $_.command })) {
            $cmd = "$c".Trim(); if (-not $cmd -or ($cleanupCmds -contains $cmd)) { continue }
            $errs = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$null, [ref]$errs)
            if ($errs.Count) { $notes += "Agent command does not parse (not written): $cmd"; continue }
            $exclusions += [pscustomobject]@{ Label = "Agent: $($cmd.Substring(0, [Math]::Min(70, $cmd.Length)))"; Command = "$cmd   # agent: review"; Checked = $true }; $cleanupCmds += "$cmd   # agent: review"; $notes += "Agent cleanup (review): $cmd"
        }
        $un = $res.Un
        if ($dec.packagingMethod) { $notes += "Agent decision: $($dec.packagingMethod.method) - $($dec.packagingMethod.reason)" }
        if ($run) { $notes += "Agent evaluation run: $($run.Command) as $($run.RunAs) -> exit $($run.ExitCode), $($run.DurationSec)s, $(if ((Get-AgentList $run.WindowsSeen).Count) { "windows seen: $((Get-AgentList $run.WindowsSeen) -join ' | ') - NOT silent" } else { 'silent (no window)' })" }
        foreach ($hd in (Get-AgentList $dec.needsHumanDecision)) { $notes += "Agent - your decision needed: $hd" }
        # the SAME shape Package Assistance writes from its analyzer -> "Analyze installer > Load report..." reads it back
        if (Get-Command Save-SnapshotState -ErrorAction SilentlyContinue) {
            $instMB = 0; try { if ($res.FileDiff -and $res.FileDiff.InstalledBytes) { $instMB = [int][Math]::Ceiling([double]$res.FileDiff.InstalledBytes / 1MB) } } catch {}
            $snapPath = Join-Path (Get-WorkPath 'Reports') "$pkg.snapshot.json"
            [void](Save-SnapshotState -Path $snapPath -Data @{
                SavedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Package = "$pkg"; ReportText = "$($res.ReportText)"; Exclusions = @($exclusions); Shortcuts = @(Get-AgentList $res.Shortcuts)
                Hkcu = @(Get-AgentList $res.Hkcu); UserFiles = @(Get-AgentList $res.UserFiles); InstalledMB = $instMB
                Uninstall = "$(if ($un) { $un.Uninstall })"; ProductCode = "$(if ($un) { $un.ProductCode })"; Detection = "$(if ($un) { "$($un.DisplayName) $($un.DisplayVersion)" })"
                Notes = @($notes); CleanupCommands = @($cleanupCmds); LeftoverCandidates = $res.LeftoverCandidates; LeftoverChecked = $false; ChangeSet = $res.ChangeSet })
            $out.SnapshotReport = $snapPath
        }
        $runName = if ($run -and $run.Installer) { [IO.Path]::GetFileName("$($run.Installer)") } else { '' }
        $handover = [ordered]@{
            package = $pkg; ritm = "$($sheet.ritm)"; generated = (Get-Date -Format 'yyyy-MM-dd HH:mm'); status = "$($sheet.status)"
            method = "$($dec.packagingMethod.method)"; installer = $runName
            installArgs = (Get-AgentArgsOnly -Command "$($dec.packagingMethod.installCommand)" -InstallerName $runName)
            installCommand = "$($dec.packagingMethod.installCommand)"; uninstallCommand = "$($dec.packagingMethod.uninstallCommand)"
            uninstallFromArp = "$(if ($un) { $un.Uninstall })"; productCode = "$(if ($un) { $un.ProductCode })"; displayName = "$(if ($un) { $un.DisplayName })"; displayVersion = "$(if ($un) { $un.DisplayVersion })"
            perUserMode = "$($dec.perUser.mode)"; detection = $dec.detection; autoUpdate = $dec.autoUpdate
            cleanupCommands = @($cleanupCmds); notes = @($notes); needsHumanDecision = @(Get-AgentList $dec.needsHumanDecision)
            snapshotReport = $out.SnapshotReport; evaluationSheet = $paths.Html }
        $hp = Join-Path $paths.Dir 'agent-handover.json'
        $handover | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $hp -Encoding utf8 -Force
        $out.Handover = $hp
    }
    Write-Log "Agent export: sheet=$($out.Sheet) snapshot=$($out.SnapshotReport) handover=$($out.Handover)" Success
    return $out
}

# ---- THE WINDOW ------------------------------------------------------------------------------------------------------
function Show-AgentApp {
    param([string]$Folder)
    # handlers run inside the dispatcher where $script: variables do NOT resolve (functions do) - everything they need sits in $ctx
    $ctx = @{ Sheet = $null; Folder = "$Folder"; Phase = 'idle'; Before = $null; Result = $null; RunInfo = $null; Box = $null; Err = ''; Proposal = $null; Exported = $null; ToolRoot = "$script:AgentToolRoot"; AgentRoot = "$script:AgentRoot"; AnalyzeScript = "$script:AgentAnalyzeScript" }
    $win = New-Object Windows.Window; $script:AgentWin = $win
    $win.Title = 'Packaging Agent'; $win.WindowStartupLocation = 'CenterScreen'
    $wa = try { [System.Windows.SystemParameters]::WorkArea } catch { $null }
    $win.Width = if ($wa -and $wa.Width -gt 0) { [Math]::Min(1180, [int]($wa.Width * 0.85)) } else { 1100 }
    $win.Height = if ($wa -and $wa.Height -gt 0) { [Math]::Min(860, [int]($wa.Height * 0.9)) } else { 760 }
    $win.MinWidth = 820; $win.MinHeight = 560
    Set-AgentTheme $win
    $outer = New-Object Windows.Controls.Grid
    foreach ($h in 'Auto', '*') { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = $h; [void]$outer.RowDefinitions.Add($rd) }
    $hdr = New-AgentHeader -Title 'Packaging Agent' -Subtitle "order intake · evaluation on this machine · packaging method  -  you approve every step   ·   engines: $(Split-Path -Leaf $script:AgentToolRoot)"
    [Windows.Controls.Grid]::SetRow($hdr, 0); [void]$outer.Children.Add($hdr)
    $g = New-Object Windows.Controls.Grid; $g.Margin = '14,10,14,10'
    foreach ($h in 'Auto', 'Auto', '*', 'Auto', 'Auto') { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = $h; [void]$g.RowDefinitions.Add($rd) }
    [Windows.Controls.Grid]::SetRow($g, 1); [void]$outer.Children.Add($g)
    # row 0: order + intake
    $top = New-Object Windows.Controls.DockPanel; $top.LastChildFill = $true; $top.Margin = '0,0,0,8'
    $bIntake = New-AgentButton -Glyph 'E8B7' -Text 'Run intake' -Accent -ToolTip 'Read the order: form + screenshots, installers, predecessor, knowledge base. Then decide readiness and propose the packaging method. Nothing is installed.'
    $bKey = New-AgentButton -Glyph 'E72E' -Text 'API key' -ToolTip 'Gemini API key for this session (never stored unless you tick remember).'
    $bBrowse = New-AgentButton -Glyph 'E8DA' -Text 'Order folder...' -ToolTip 'Pick the order folder (Incoming\<package>, or any folder with the installer + the AO form).'
    $cmbOrders = New-Object Windows.Controls.ComboBox; $cmbOrders.Width = 300; $cmbOrders.Margin = '0,0,8,0'; $cmbOrders.ToolTip = 'Newest orders in the Incoming repository'
    [void]$cmbOrders.Items.Add('  newest orders in Incoming...'); $cmbOrders.SelectedIndex = 0
    try { $repo = Get-Setting 'RepositoryPath'; if ($repo -and (Test-Path -LiteralPath $repo)) { foreach ($o in (Get-ChildItem -LiteralPath $repo -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 25)) { [void]$cmbOrders.Items.Add($o.Name) } } } catch {}
    [Windows.Controls.DockPanel]::SetDock($bIntake, 'Right'); [Windows.Controls.DockPanel]::SetDock($bKey, 'Right'); [Windows.Controls.DockPanel]::SetDock($bBrowse, 'Right'); [Windows.Controls.DockPanel]::SetDock($cmbOrders, 'Right')
    [void]$top.Children.Add($bIntake); [void]$top.Children.Add($bKey); [void]$top.Children.Add($bBrowse); [void]$top.Children.Add($cmbOrders)
    $txtFolder = New-Object Windows.Controls.TextBox; $txtFolder.Text = "$($ctx.Folder)"; $txtFolder.Height = 30; $txtFolder.FontFamily = 'Consolas'; $txtFolder.FontSize = 12.5; $txtFolder.VerticalContentAlignment = 'Center'; $txtFolder.Margin = '0,0,10,0'; $txtFolder.ToolTip = 'The order folder the agent reads.'
    [void]$top.Children.Add($txtFolder)
    [Windows.Controls.Grid]::SetRow($top, 0); [void]$g.Children.Add($top)
    # row 1: status
    $sw = New-Object Windows.Controls.StackPanel
    $pb = New-Object Windows.Controls.ProgressBar; $pb.Height = 3; $pb.IsIndeterminate = $true; $pb.Visibility = 'Collapsed'; $pb.BorderThickness = '0'; $pb.Foreground = '#2BA6B8'; $pb.Background = '#2A2E36'
    $lblStat = New-Object Windows.Controls.TextBlock; $lblStat.Foreground = '#B7BEC8'; $lblStat.FontSize = 12; $lblStat.TextWrapping = 'Wrap'; $lblStat.Margin = '0,4,0,6'
    $lblStat.Text = if (Test-AgentHasKey) { "Key: $(Get-AgentKeySource) · model $(Get-AgentModel)" } else { 'No API key for this session - click API key, or run intake to be asked (without a key: facts + rule checks only).' }
    [void]$sw.Children.Add($pb); [void]$sw.Children.Add($lblStat)
    [Windows.Controls.Grid]::SetRow($sw, 1); [void]$g.Children.Add($sw)
    # row 2: sheet
    $sv = New-Object Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'; $sv.HorizontalScrollBarVisibility = 'Disabled'
    $panel = New-Object Windows.Controls.StackPanel; $panel.Margin = '0,0,8,0'; $sv.Content = $panel
    [Windows.Controls.Grid]::SetRow($sv, 2); [void]$g.Children.Add($sv)
    Update-AgentSheetView -Panel $panel -Sheet $null -Ctx $ctx
    # row 3: cost
    $lblCost = New-Object Windows.Controls.TextBlock; $lblCost.Foreground = '#A0A8B4'; $lblCost.FontSize = 11.5; $lblCost.Margin = '0,6,0,0'
    [Windows.Controls.Grid]::SetRow($lblCost, 3); [void]$g.Children.Add($lblCost)
    # row 4: actions
    $bar = New-Object Windows.Controls.DockPanel; $bar.LastChildFill = $false; $bar.Margin = '0,8,0,0'
    $bEval = New-AgentButton -Glyph 'E9D9' -Text 'Start evaluation (snapshot on this machine)' -ToolTip 'Baseline snapshot -> runs the proposed silent install on THIS machine -> after snapshot -> the agent classifies what the installer did.'; $bEval.IsEnabled = $false
    $bTree = New-AgentButton -Glyph 'E8A0' -Text 'Show changes' -ToolTip 'The before/after change report (files, registry, services, tasks, shortcuts...) in the browser.'; $bTree.IsEnabled = $false
    $bExport = New-AgentButton -Glyph 'E74E' -Text 'Export for Package Assistance' -ToolTip 'Writes the evaluation sheet, the snapshot report (Package Assistance > Analyze installer > Load report...) and agent-handover.json (install/uninstall commands, cleanups, notes).'; $bExport.IsEnabled = $false
    $bReport = New-AgentButton -Glyph 'E8A5' -Text 'Open report' -ToolTip 'Open the evaluation sheet (HTML) and the folder with every model call.'; $bReport.IsEnabled = $false
    $bClose = New-Object Windows.Controls.Button; $bClose.Content = 'Close'; $bClose.Padding = '16,5'; $bClose.IsCancel = $true
    [Windows.Controls.DockPanel]::SetDock($bClose, 'Right'); [void]$bar.Children.Add($bClose)
    foreach ($b in @($bEval, $bTree, $bExport, $bReport)) { [Windows.Controls.DockPanel]::SetDock($b, 'Left'); [void]$bar.Children.Add($b) }
    [Windows.Controls.Grid]::SetRow($bar, 4); [void]$g.Children.Add($bar)
    $win.Content = $outer

    $refresh = {
        Update-AgentSheetView -Panel $panel -Sheet $ctx.Sheet -Ctx $ctx
        $lblCost.Text = "Model: $(Format-AgentUsage)$(if ($ctx.Sheet) { "   ·   sheet: $((Get-AgentSheetDir -Sheet $ctx.Sheet))" })"
        $s = $ctx.Sheet
        $bReport.IsEnabled = [bool]$s
        $bEval.IsEnabled = [bool]($s -and $s.status -in 'ready', 'ask_ao' -and $ctx.Phase -eq 'idle' -and (Get-AgentRunProposal -Sheet $s))
        $bTree.IsEnabled = [bool]($ctx.Result -and $ctx.Result.ChangeSet)
        $bExport.IsEnabled = [bool]($s -and $ctx.Phase -eq 'idle')
    }
    $cmbOrders.add_SelectionChanged({ if ($cmbOrders.SelectedIndex -gt 0) { $txtFolder.Text = Join-Path (Get-Setting 'RepositoryPath') "$($cmbOrders.SelectedItem)" } })
    $bKey.add_Click({ if (Show-AgentKeyDialog) { $lblStat.Text = "Key: $(Get-AgentKeySource) · model $(Get-AgentModel)"; $lblStat.Foreground = '#B7BEC8' } })
    $bBrowse.add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog; $dlg.Description = 'Select the order folder (Incoming\<package> or any folder with the installer + the AO form)'
        $repo = Get-Setting 'RepositoryPath'; if ("$($txtFolder.Text)".Trim() -and (Test-Path -LiteralPath $txtFolder.Text)) { $dlg.SelectedPath = $txtFolder.Text } elseif ($repo -and (Test-Path -LiteralPath $repo)) { $dlg.SelectedPath = $repo }
        if ($dlg.ShowDialog() -eq 'OK') { $txtFolder.Text = $dlg.SelectedPath }
    })
    $bReport.add_Click({ if ($ctx.Sheet) { $p = Save-AgentSheet -Sheet $ctx.Sheet; try { Start-Process $p.Html } catch {}; try { Start-Process explorer.exe -ArgumentList "`"$($p.Dir)`"" } catch {} } })
    $bTree.add_Click({
        if (-not $ctx.Result -or -not $ctx.Result.ChangeSet) { return }
        $html = Join-Path (Get-AgentSheetDir -Sheet $ctx.Sheet) 'snapshot-changes.html'
        try { [IO.File]::WriteAllText($html, (Format-SnapshotChangeSetHtml $ctx.Result.ChangeSet)); Start-Process $html } catch { $lblStat.Text = "Could not open the change report: $($_.Exception.Message)" }
    })
    $bExport.add_Click({
        if (-not $ctx.Sheet) { return }
        try { $o = Export-AgentEvaluation -Ctx $ctx; $ctx.Exported = $o
              $lblStat.Text = "Exported: sheet + $(if ($o.SnapshotReport) { 'snapshot report (Package Assistance: Analyze installer > Load report...) + handover.json' } else { 'no snapshot yet (intake only)' })  ->  $($o.Dir)"; $lblStat.Foreground = '#6A9955'
              try { Start-Process explorer.exe -ArgumentList "`"$($o.Dir)`"" } catch {} }
        catch { $lblStat.Text = "Export failed: $($_.Exception.Message)"; $lblStat.Foreground = '#F48771' }
    })
    $bIntake.add_Click({
        $folder = "$($txtFolder.Text)".Trim()
        if (-not $folder -or -not (Test-Path -LiteralPath $folder)) { $lblStat.Text = 'Pick an order folder first.'; $lblStat.Foreground = '#F48771'; return }
        if (-not (Confirm-AgentKey)) { $lblStat.Text = 'No API key - intake runs without the model (facts + rule checks only).'; $lblStat.Foreground = '#E0BE7C' }
        $ctx.Folder = $folder; $ctx.Result = $null; $ctx.RunInfo = $null; $ctx.Phase = 'idle'; $ctx.Exported = $null
        $bIntake.IsEnabled = $false; $pb.Visibility = 'Visible'; $lblStat.Foreground = '#B7BEC8'; $lblStat.Text = 'Intake running - reading the order, then the model reads the form and assesses...'
        try { $win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch {}
        # runs in the background so the window stays alive; the timer picks up the result
        $ctx.Box = Start-AgentRunspace -Arg @{ folder = $folder; noModel = (-not (Test-AgentHasKey)) } -Script @'
param($a, $box)
Invoke-AgentIntake -Folder $a.folder -NoModel:$a.noModel -Progress { param($t) $box.Progress = "$t" }
'@
        $ctx.Phase = 'intake'
    })
    $bEval.add_Click({
        $s = $ctx.Sheet; if (-not $s) { return }
        $prop = Get-AgentRunProposal -Sheet $s; if (-not $prop) { $lblStat.Text = 'No installer to run.'; return }
        if (-not (Test-Path -LiteralPath $prop.Installer)) { $lblStat.Text = "Installer not reachable: $($prop.Installer)"; $lblStat.Foreground = '#F48771'; return }
        if ((Get-Command Test-IsSecurityProduct -ErrorAction SilentlyContinue) -and (Test-IsSecurityProduct "$($prop.Name) $($s.identity.vendor) $($s.identity.app)")) {
            if ([Windows.MessageBox]::Show("'$($prop.Name)' looks like a security/EDR product - installing it on this machine is usually blocked. Run anyway?", 'Security product', 'YesNo', 'Warning') -ne 'Yes') { return }
        }
        $ans = [Windows.MessageBox]::Show("Evaluate on THIS machine?`n`n1. baseline snapshot`n2. run  $($prop.Name) $($prop.Args)  as $($prop.RunAs)  (source: $($prop.Source))`n3. after snapshot + the agent's classification`n`nThe app really installs here (approve the UAC prompt).", 'Start evaluation', 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }
        $ctx.Proposal = $prop; $ctx.Result = $null; $ctx.RunInfo = $null
        $ctx.Phase = 'baseline'; $bEval.IsEnabled = $false; $bExport.IsEnabled = $false; $pb.Visibility = 'Visible'; $lblStat.Foreground = '#B7BEC8'
        $lblStat.Text = 'Step 1/4 - baseline snapshot of this machine (about a minute)...'
        $ctx.Box = Start-AgentRunspace -Arg @{} -Script 'param($a, $box) Get-MachineSnapshot'
    })
    # ONE timer drives every background phase (plain handler: runs in this function's scope while the window is modal).
    $timer = New-Object System.Windows.Threading.DispatcherTimer; $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.add_Tick({
        $box = $ctx.Box
        switch ($ctx.Phase) {
            'intake' {
                if ($box.Progress) { $lblStat.Text = "Intake - $($box.Progress)" }
                if (-not $box.Done) { return }
                Stop-AgentRunspace -Box $box; $ctx.Phase = 'idle'; $pb.Visibility = 'Collapsed'; $bIntake.IsEnabled = $true
                if ($box.Error -or -not $box.Result) { $lblStat.Text = "Intake failed: $($box.Error)"; $lblStat.Foreground = '#F48771'; & $refresh; return }
                $ctx.Sheet = $box.Result; Set-AgentUsage -Summary $ctx.Sheet.audit
                $lblStat.Text = "Intake done: $($ctx.Sheet.status)  ·  $(Format-AgentUsage)"; $lblStat.Foreground = '#B7BEC8'
                & $refresh
                if ($ctx.Sheet.status -eq 'ready' -and $bEval.IsEnabled) {
                    $prop = Get-AgentRunProposal -Sheet $ctx.Sheet
                    if ([Windows.MessageBox]::Show("Nothing is missing. Start the evaluation now?`n`n1. baseline snapshot of this machine`n2. run  $($prop.Name) $($prop.Args)  as $($prop.RunAs)  (source: $($prop.Source))`n3. after snapshot + the agent's classification`n`nThe app really installs on THIS machine.", 'Start evaluation', 'YesNo', 'Question') -eq 'Yes') { $bEval.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent))) }
                }
            }
            'baseline' {
                if (-not $box.Done) { return }
                Stop-AgentRunspace -Box $box
                if ($box.Error -or -not $box.Result) { $ctx.Phase = 'idle'; $pb.Visibility = 'Collapsed'; $lblStat.Text = "Baseline failed: $($box.Error)"; $lblStat.Foreground = '#F48771'; & $refresh; return }
                $ctx.Before = $box.Result
                $p = $ctx.Proposal; $ctx.Phase = 'installing'
                $lblStat.Text = "Step 2/4 - running  $($p.Name) $($p.Args)  as $($p.RunAs). Approve the UAC prompt; the agent waits for the installer to finish..."
                $local = if (Get-Command Copy-InstallerLocal -ErrorAction SilentlyContinue) { Copy-InstallerLocal -ExePath $p.Installer } else { $p.Installer }
                if (-not $local -or -not (Test-Path -LiteralPath $local)) { $local = $p.Installer }
                $psExec = @(Get-ChildItem -LiteralPath $ctx.ToolRoot, $ctx.AgentRoot -Filter 'PsExec*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object { $_.FullName })
                $ctx.Box = Start-AgentRunspace -Arg @{ installer = $local; args = $p.Args; runAs = $p.RunAs; psexec = "$($psExec)" } -Script @'
param($a, $box)
if ($a.psexec) { $script:__psexec = $a.psexec; function Find-PsExec { return $script:__psexec } }
Invoke-AgentInstallRun -Installer $a.installer -Arguments $a.args -RunAs $a.runAs -Progress { param($t) $box.Progress = "$t" }
'@
            }
            'installing' {
                if ($box.Progress) { $lblStat.Text = "Step 2/4 - $($box.Progress)" }
                if (-not $box.Done) { return }
                Stop-AgentRunspace -Box $box
                $ri = $box.Result; if (-not $ri) { $ri = @{ ExitCode = $null; DurationSec = 0; WindowsSeen = @(); TimedOut = $false; Error = "$($box.Error)"; Command = '' } }
                $ri = @{ Installer = $ctx.Proposal.Installer; Args = $ctx.Proposal.Args; RunAs = $ctx.Proposal.RunAs; ExitCode = $ri.ExitCode; DurationSec = $ri.DurationSec; WindowsSeen = @($ri.WindowsSeen); TimedOut = [bool]$ri.TimedOut; Error = "$($ri.Error)"; Command = "$($ri.Command)" }
                $ctx.RunInfo = $ri
                if ($ri.Error -and $null -eq $ri.ExitCode) { $ctx.Phase = 'idle'; $pb.Visibility = 'Collapsed'; $lblStat.Text = "Installer did not run: $($ri.Error). Nothing to analyze."; $lblStat.Foreground = '#F48771'; & $refresh; return }
                $ctx.Phase = 'analyzing'
                $lblStat.Text = "Step 3/4 - installer finished (exit $($ri.ExitCode), $($ri.DurationSec)s$(if ($ri.WindowsSeen.Count) { ', a window was shown - NOT silent' })). After snapshot + diff..."
                $ctx.Box = Start-AgentRunspace -Arg @{ before = $ctx.Before; vendor = "$($ctx.Sheet.identity.vendor)"; app = "$($ctx.Sheet.identity.app)" } -Script $ctx.AnalyzeScript
            }
            'analyzing' {
                if ($box.Progress) { $lblStat.Text = "Step 3/4 - $($box.Progress)" }
                if (-not $box.Done) { return }
                Stop-AgentRunspace -Box $box
                if ($box.Error -or -not $box.Result) { $ctx.Phase = 'idle'; $pb.Visibility = 'Collapsed'; $lblStat.Text = "Analyze failed: $($box.Error)"; $lblStat.Foreground = '#F48771'; & $refresh; return }
                $ctx.Result = $box.Result
                $ctx.Phase = 'deciding'
                $lblStat.Text = 'Step 4/4 - the agent classifies what the installer did and settles the packaging method...'
                $ctx.Box = Start-AgentRunspace -Arg @{ sheet = $ctx.Sheet; result = $ctx.Result; run = $ctx.RunInfo } -Script @'
param($a, $box)
Invoke-AgentSnapshotDecision -Sheet $a.sheet -Result $a.result -RunInfo $a.run -Progress { param($t) $box.Progress = "$t" }
'@
            }
            'deciding' {
                if ($box.Progress) { $lblStat.Text = "Step 4/4 - $($box.Progress)" }
                if (-not $box.Done) { return }
                Stop-AgentRunspace -Box $box
                if ($box.Result) { $ctx.Sheet = $box.Result; Set-AgentUsage -Summary $ctx.Sheet.audit -Add } elseif ($box.Error) { Write-Log "Agent decision failed: $($box.Error)" Error }
                $ctx.Phase = 'idle'; $pb.Visibility = 'Collapsed'
                $lblStat.Text = "Evaluation done - review the decision below, open the change report, then Export.  $(Format-AgentUsage)"; $lblStat.Foreground = '#6A9955'
                & $refresh
                $bTree.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
            }
            default {}
        }
    })
    $timer.Start()
    Write-Log "Packaging Agent window opened (tool: $script:AgentToolRoot; key: $(if (Test-AgentHasKey) { $script:PkgAgent.KeySource } else { 'none' }))"
    try { [void]$win.ShowDialog() } finally { $timer.Stop(); if ($ctx.Box -and -not $ctx.Box.Done) { try { $ctx.Box._ps.Stop() } catch {} } }
    Write-Log "Packaging Agent window closed ($(Format-AgentUsage))"
}
