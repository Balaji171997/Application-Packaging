##############################################################
# Agent.Ui.ps1  -  the shared pieces the console is built on.
#
#   The window itself is Agent.Console.ps1. This file holds what it stands on:
#     Set-AgentTheme / New-AgentButton / New-AgentHeader   small WPF helpers
#     Show-AgentKeyDialog                                  endpoint, model and credentials for the session
#     Start-AgentRunspace / Stop-AgentRunspace             one stage = one background runspace (carries key,
#                                                          client secret and auth overrides - see the README)
#     $script:AgentAnalyzeScript                           the after-snapshot + diff, run inside that runspace
#     Get-AgentArgsOnly                                    an AI command reduced to ARGUMENTS ONLY, so the tool
#                                                          can build its own launch without a second /i
#     Export-AgentEvaluation                               sheet + agent-handover.json + the snapshot report
##############################################################
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms -ErrorAction SilentlyContinue
$script:AgentWin = $null

# ---- small WPF helpers (self-contained) ------------------------------------------------------------------------------
# The dark chrome. Without this WPF paints its own light-grey buttons and scrollbars, which look broken
# in a dark window. The implicit Button style (no x:Key) applies to every button in the window; PbAccentButton
# is the one loud button a screen is allowed to have.
$script:AgentThemeXaml = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Style x:Key="PbButtonBase" TargetType="Button">
    <Setter Property="Foreground" Value="#E6EAF0"/>
    <Setter Property="Background" Value="#262A33"/>
    <Setter Property="BorderBrush" Value="#39404E"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="SnapsToDevicePixels" Value="True"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="bd" CornerRadius="4" Background="{TemplateBinding Background}"
                  BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                              Margin="{TemplateBinding Padding}"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="bd" Property="Background" Value="#313746"/>
              <Setter TargetName="bd" Property="BorderBrush" Value="#4A5468"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="bd" Property="Background" Value="#1E222A"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter TargetName="bd" Property="Background" Value="#20242C"/>
              <Setter TargetName="bd" Property="BorderBrush" Value="#2A2F3A"/>
              <Setter Property="Foreground" Value="#5C6472"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="Button" BasedOn="{StaticResource PbButtonBase}"/>
  <Style x:Key="PbAccentButton" TargetType="Button" BasedOn="{StaticResource PbButtonBase}">
    <Setter Property="Foreground" Value="#0E1013"/>
    <Setter Property="Background" Value="#2BA6B8"/>
    <Setter Property="BorderBrush" Value="#2BA6B8"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True">
        <Setter Property="Background" Value="#38BCCF"/>
        <Setter Property="BorderBrush" Value="#38BCCF"/>
      </Trigger>
      <Trigger Property="IsEnabled" Value="False">
        <Setter Property="Background" Value="#20242C"/>
        <Setter Property="Foreground" Value="#5C6472"/>
      </Trigger>
    </Style.Triggers>
  </Style>
  <Style TargetType="TextBox">
    <Setter Property="Background" Value="#101318"/>
    <Setter Property="Foreground" Value="#E6EAF0"/>
    <Setter Property="BorderBrush" Value="#333A47"/>
    <Setter Property="CaretBrush" Value="#E6EAF0"/>
    <Setter Property="SelectionBrush" Value="#2BA6B8"/>
    <Setter Property="Padding" Value="6,3"/>
  </Style>
  <Style TargetType="CheckBox">
    <Setter Property="Foreground" Value="#C7CEDA"/>
  </Style>
</ResourceDictionary>
'@
function Set-AgentTheme { param($Window)
    $Window.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x18,0x1A,0x1F)))
    $Window.FontFamily = 'Segoe UI'; $Window.FontSize = 13
    try {
        $rd = [Windows.Markup.XamlReader]::Parse($script:AgentThemeXaml)
        [void]$Window.Resources.MergedDictionaries.Add($rd)
    } catch { Write-Verbose "theme not applied: $($_.Exception.Message)" }
}
function New-AgentButton { param([string]$Glyph, [string]$Text, [string]$ToolTip, [switch]$Accent, [string]$Margin = '0,0,8,0')
    $b = New-Object Windows.Controls.Button; $b.Padding = '12,5'; $b.Margin = $Margin; $b.VerticalAlignment = 'Center'
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    if ($Glyph) { $g = New-Object Windows.Controls.TextBlock; $g.Text = [string][char][Convert]::ToInt32($Glyph, 16); $g.FontFamily = 'Segoe MDL2 Assets'; $g.FontSize = 13; $g.VerticalAlignment = 'Center'; $g.Margin = '0,1,7,0'; [void]$sp.Children.Add($g) }
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $Text; $t.VerticalAlignment = 'Center'; [void]$sp.Children.Add($t)
    $b.Content = $sp; if ($ToolTip) { $b.ToolTip = $ToolTip }
    if ($Accent) { try { $b.Style = $script:AgentWin.FindResource('PbAccentButton') } catch { $b.Background = '#2BA6B8'; $b.Foreground = '#0E1013' } }
    return $b
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
    $win.Title = 'API key / endpoint'; $win.Width = 760; $win.SizeToContent = 'Height'; $win.WindowStartupLocation = 'CenterOwner'; $win.ResizeMode = 'CanResize'
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
    # which header carries the API key, and whether its value is prefixed with "Bearer " (VW LLMaaS wants both)
    $row2 = New-Object Windows.Controls.Grid; foreach ($w in '*', '12', '*') { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $w; [void]$row2.ColumnDefinitions.Add($cd) }
    $d1 = New-Object Windows.Controls.StackPanel; $lh = New-Object Windows.Controls.TextBlock; $lh.Text = 'API key header  (VW LLMaaS: X-LLM-API-CLIENT-ID)'; $lh.Foreground = '#A0A8B4'; $lh.FontSize = 11.5; [void]$d1.Children.Add($lh)
    $tbHdr = New-Object Windows.Controls.TextBox; $tbHdr.Height = 28; $tbHdr.FontFamily = 'Consolas'; $tbHdr.FontSize = 12.5; $tbHdr.Text = "$($cfg0.ApiKeyHeader)"; $tbHdr.Margin = '0,2,0,0'; [void]$d1.Children.Add($tbHdr)
    $d2 = New-Object Windows.Controls.StackPanel; $lp = New-Object Windows.Controls.TextBlock; $lp.Text = 'value prefix  (VW LLMaaS: "Bearer ", else empty)'; $lp.Foreground = '#A0A8B4'; $lp.FontSize = 11.5; [void]$d2.Children.Add($lp)
    $tbPre = New-Object Windows.Controls.TextBox; $tbPre.Height = 28; $tbPre.FontFamily = 'Consolas'; $tbPre.FontSize = 12.5; $tbPre.Text = "$($cfg0.ApiKeyPrefix)"; $tbPre.Margin = '0,2,0,0'; [void]$d2.Children.Add($tbPre)
    [Windows.Controls.Grid]::SetColumn($d1, 0); [Windows.Controls.Grid]::SetColumn($d2, 2); [void]$row2.Children.Add($d1); [void]$row2.Children.Add($d2); $row2.Margin = '0,8,0,0'; [void]$g.Children.Add($row2)
    $chk = New-Object Windows.Controls.CheckBox; $chk.Content = 'Remember on this machine (URLs, model, client id -> agent.settings.json; key -> Credential Manager; secret never)'; $chk.Foreground = '#E7E9ED'; $chk.Margin = '0,10,0,0'; [void]$g.Children.Add($chk)
    $applyEndpoint = { if ("$($pb.Password)".Trim()) { Set-AgentApiKey -Key $pb.Password -Remember:([bool]$chk.IsChecked) }; Set-AgentAuth -TokenUrl $tbTok.Text -ClientId $tbCid.Text -ClientSecret $pbSec.Password -ApiKeyHeader $tbHdr.Text -ApiKeyPrefix $tbPre.Text -NoPrefix:(-not "$($tbPre.Text)"); Set-AgentEndpoint -BaseUrl $tbUrl.Text -Model $tbModel.Text -Remember:([bool]$chk.IsChecked) }
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
        Set-AgentAuth -TokenUrl $tbTok.Text -ClientId $tbCid.Text -ClientSecret $pbSec.Password -ApiKeyHeader $tbHdr.Text -ApiKeyPrefix $tbPre.Text -NoPrefix:(-not "$($tbPre.Text)")
        Set-AgentEndpoint -BaseUrl $tbUrl.Text -Model $tbModel.Text
        if (-not (Test-AgentHasKey) -and -not "$($pbSec.Password)".Trim()) { $lbl.Text = 'Enter a key (or client id + secret) first.'; return }
        $lbl.Text = 'Testing (name resolution -> proxy -> service -> key -> model)...'; try { $win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch {}
        $r = Test-GeminiConnection
        $lbl.Text = (@($r.Steps) -join "`n")
        $lbl.Foreground = if ($r.Ok) { '#6A9955' } else { '#F48771' }
    })
    $bForget.add_Click({ Set-AgentApiKey -Forget; $pb.Password = ''; $lbl.Text = 'Key cleared.'; $lbl.Foreground = '#A0A8B4' })
    $ok.add_Click({ & $applyEndpoint; $win.DialogResult = [bool]((Test-AgentHasKey) -or "$($pbSec.Password)".Trim()) })
    $root = New-Object Windows.Controls.StackPanel; [void]$root.Children.Add((New-AgentHeader -Title 'API key / endpoint' -Subtitle 'session only unless you tick remember')); [void]$root.Children.Add($g)
    $win.Content = $root
    return [bool]$win.ShowDialog()
}

# ---- background runspace: the tool's engine files + the agent, loaded as a library --------------------------------------
# WHAT THE PACKAGER HAS SAID WHILE IT IS WORKING. One list for the whole window, shared with every stage runspace,
# so a correction typed mid-run reaches the AI on its very next round instead of waiting for the run to end.
function Get-AgentHumanInbox {
    # $null -eq, NOT -not: an EMPTY collection is falsy in PowerShell, so "-not $inbox" is true for the very list we
    # just made. Every call would have built a fresh one, and anything typed would have gone into an orphan that no
    # runspace was reading - the box would look like it worked and the AI would never hear a word of it.
    if ($null -eq $script:AgentHumanInbox) { $script:AgentHumanInbox = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList)) }
    return ,$script:AgentHumanInbox
}

function Start-AgentRunspace {
    param([Parameter(Mandatory)][string]$Script, [hashtable]$Arg = @{})
    $box = [hashtable]::Synchronized(@{ Done = $false; Result = $null; Error = ''; Progress = '' })
    $inbox = Get-AgentHumanInbox
    # The runspace starts EMPTY: it re-loads the agent from disk, so anything typed in the key dialog (key, client
    # secret, endpoint/auth overrides) must travel with the payload. Without the secret, AuthMode 'auto' falls back
    # to key-only and the gateway answers 401 - even though the Test button just succeeded in the window.
    $ov = @{}; if ($script:PkgAgent.Overrides) { foreach ($k in @($script:PkgAgent.Overrides.Keys)) { $ov[$k] = $script:PkgAgent.Overrides[$k] } }
    $payload = @{ tool = "$script:AgentToolRoot"; agent = "$script:AgentSrc"; home = "$script:AgentHome"; settings = "$script:AgentSettingsPath"; paths = "$($script:SettingsPath)"; script = $Script; arg = $Arg; box = $box
                  key = "$($script:PkgAgent.ApiKey)"; secret = "$($script:PkgAgent.ClientSecret)"; overrides = $ov; inbox = $inbox }
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $ps = [PowerShell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($p)
        try {
            foreach ($f in 'Core.ps1', 'Predecessor.ps1', 'Source.ps1', 'MstBuilder.ps1', 'BundledMsi.ps1', 'Snapshot.ps1', 'Screenshots.ps1', 'PSADT_V3toV4_Mappings.ps1', 'Build.ps1') { if (Test-Path "$($p.tool)\$f") { . "$($p.tool)\$f" } }
            foreach ($f in 'Agent.Tools.ps1', 'Agent.Gemini.ps1', 'Agent.Docs.ps1', 'Agent.Prompts.ps1', 'Agent.Ops.ps1', 'Agent.Core.ps1', 'Agent.Brain.ps1') { . "$($p.agent)\$f" }   # $p.agent = the Src folder
            Initialize-Config $p.paths
            $script:AgentSettingsPath = $p.settings
            # the runspace starts EMPTY: publish the same roots the window has, or anything that resolves a path from
            # them (Get-AgentTemplatePath) gets '' and dies on "Cannot bind argument to parameter 'Path' because it is
            # an empty string".
            $script:AgentToolRoot = $p.tool
            $script:AgentSrc = $p.agent
            $script:AgentHome = $p.home
            # the same list the window writes into - anything the packager types reaches the model's next round
            $script:AgentHumanInbox = $p.inbox
            if ($p.key) { Set-AgentApiKey -Key $p.key }
            if ($p.secret) { $script:PkgAgent.ClientSecret = "$($p.secret)" }
            # $null means "not overridden"; an empty string is a deliberate override (ApiKeyPrefix '' = bare key)
            if ($p.overrides -and $p.overrides.Count) {
                if (-not $script:PkgAgent.Overrides) { $script:PkgAgent.Overrides = @{} }
                foreach ($k in @($p.overrides.Keys)) { $script:PkgAgent.Overrides[$k] = $p.overrides[$k] }
            }
            # what this order has already spent, so the per-package cost cap counts the whole order, not one stage
            if ($p.arg -and $p.arg.sheet -and $p.arg.sheet.audit) { try { Set-AgentUsage -Summary $p.arg.sheet.audit } catch {} }
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
# SETTINGS THE PACKAGE WILL HAVE TO APPLY. The diff names the registry keys and folders; a setting is a VALUE inside
# one, or a line inside a config file, and neither can be guessed from the application's name - they have to be read.
# The autostart delta is what actually found the auto-updater.
$box.Progress = 'reading back the settings this install wrote'
$installRoots = @()
try {
    $installRoots = @(@($fileDiff.New) | ForEach-Object { "$(if ($_.Path) { $_.Path } else { $_ })" } |
        Where-Object { $_ -match '(?i)^[A-Z]:\\(Program Files( \(x86\))?|ProgramData)\\' } |
        ForEach-Object { ($_ -split '\\')[0..2] -join '\' } | Select-Object -Unique -First 6)
} catch {}
$autostartDelta = if (Get-Command Get-AgentAutostartFacts -EA SilentlyContinue) { Get-AgentAutostartFacts -Baseline $a.autostartBefore } else { $null }
$settings = if (Get-Command Get-AgentSettingCandidates -EA SilentlyContinue) { Get-AgentSettingCandidates -RegDiff $regDiff -InstallRoots $installRoots -Autostart $autostartDelta } else { $null }
@{ After=$after; Diff=$diff; AppTokens=$appTokens; FileDiff=$fileDiff; RegDiff=$regDiff; Un=$un; EnvChanges=$envChanges; ReportText=$reportText; ChangeSet=$changeSet; Shortcuts=$shortcuts; Hkcu=$hkcu; UserFiles=$userFiles; LeftoverCandidates=$leftover; Cleanups=$cleanups; Settings=$settings; InstallRoots=$installRoots }
'@


# ---- export: evaluation sheet + snapshot report (loadable by Package Assistance) + handover json ----------------------
function Export-AgentEvaluation {
    param([Parameter(Mandatory)]$Ctx)
    $sheet = $Ctx.Sheet; $res = $Ctx.Result; $dec = $sheet.decision; $run = $Ctx.RunInfo

    # ONE LAST LOOK, AT THE PACKAGE AS IT IS RIGHT NOW.
    # The verification checked the package it was given. Things can happen after that - a fix applied late, a file
    # replaced, a command that did more than intended. On a real run the deploy script was overwritten AFTER the
    # build and the package went out asking for a file that was not in it. So before anything is handed over, the
    # two mechanical questions get asked again, of the files on disk this second: does the script still parse, and
    # does it still name files that are actually there? Facts only - what they mean is already decided by the
    # verdict; this just makes sure the verdict still describes reality.
    $finalScript = "$($sheet.build.script)"
    if ($finalScript -and (Test-Path -LiteralPath $finalScript)) {
        $fp = Test-AgentScriptParses -ScriptPath $finalScript
        $fc = Test-AgentPackageConsistency -ScriptPath $finalScript -ExpectedVersion "$($sheet.identity.version)" -PackageName "$($sheet.package)"
        $sheet.finalCheck = [ordered]@{
            at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            scriptParses = $fp.parses; parseErrors = $fp.errorCount
            namesFilesThatExist = $fc.ok; missingFromPackage = @($fc.missingFromPackage)
            appVersionInScript = "$($fc.appVersionInScript)"; expectedVersion = "$($sheet.identity.version)"
            ok = [bool]($fp.parses -and $fc.ok)
        }
        $sheet.finalCheck.note = if ($sheet.finalCheck.ok) { 'checked again at handover: the script parses and names files that are in the package' }
                                 else { "CHECKED AGAIN AT HANDOVER AND IT IS NOT RIGHT: " + ((@("$(if (-not $fp.parses) { $fp.note })", "$(if (-not $fc.ok) { $fc.note })") | Where-Object { "$_".Trim() }) -join ' | ') }
        if (-not $sheet.finalCheck.ok) {
            Write-Log "HANDOVER CHECK FAILED: $($sheet.finalCheck.note)" Warning
            try { Add-AgentTimeline $sheet "handover check FAILED - $($sheet.finalCheck.note)" } catch {}
        } else {
            try { Add-AgentTimeline $sheet 'handover check passed - the package on disk still matches what was verified' } catch {}
        }
    }
    $paths = Save-AgentSheet -Sheet $sheet
    # EVERY HANDOVER TEACHES THE NEXT ORDER: the case goes into Knowledge\Cases.json, where the next order of the same
    # vendor, application or installer technology finds it in its dossier
    try { [void](Save-AgentCase -Sheet $sheet) } catch { Write-Log "The case could not be recorded: $($_.Exception.Message)" Warning }
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
        foreach ($hd in (Get-AgentList $dec.needsHumanDecision)) { $notes += "Agent - your decision needed: $(ConvertTo-AgentPlainText $hd)" }
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

            # THE PLAN THE PACKAGE WAS BUILT FROM - the route, the install lines with their sources, what every
            # delivered file is for, and the parameter intents, so a reviewer sees the whole command, not just "silent".
            plan = $(if ($sheet.plan -and -not $sheet.plan.error) { [ordered]@{
                route = $sheet.plan.route; predecessor = $sheet.plan.predecessor
                installSteps = @(Get-AgentList $sheet.plan.install.steps); intentsCovered = @(Get-AgentList $sheet.plan.install.intentsCovered)
                restartAtEnd = $sheet.plan.install.restartAtEnd; deliveredFiles = @(Get-AgentList $sheet.plan.package.deliveredFiles)
                questions = @(Get-AgentList $sheet.plan.questions) } } else { $null })
            testProved = @(Get-AgentList $dec.provedWhatWasPlanned)

            # What the package has to APPLY after installing - the updater, the data-sharing prompt, the licence
            # server - and where each setting goes, which is the part that decides whether it actually works.
            configurationPlan = $dec.configurationPlan
            promptsToSuppress = @(Get-AgentList $dec.configurationPlan.promptsToSuppress)
            configurationUnresolved = @(Get-AgentList $dec.configurationPlan.unresolved)

            # Route 5: the package installs an MSI taken out of the wrapper, not the wrapper.
            packagedExtractedMsi = $(if ($dec.packageExtractedMsi -and [bool]$dec.packageExtractedMsi.use) { [ordered]@{
                file = "$($dec.packageExtractedMsi.file)"; productName = "$($dec.packageExtractedMsi.productName)"
                why = "$($dec.packageExtractedMsi.why)"
                prerequisitesStillNeeded = @(Get-AgentList $dec.packageExtractedMsi.prerequisitesStillNeeded)
                placement = $sheet.route5Placement } } else { $null })

            # How the delivered files ended up in the package. 'placedBy' matters to a reviewer: the resolver keeps the
            # delivered folder structure, the fallback does not, and a script whose paths expect subfolders will fail.
            filesPlaced = $(if ($sheet.build) { [ordered]@{
                placedBy = "$($sheet.build.placedBy)"
                ok = @(@(Get-AgentList $sheet.build.placed) | Where-Object { $_.ok }).Count
                failed = @(@(Get-AgentList $sheet.build.placed) | Where-Object { -not $_.ok }).Count
                problems = @(@(Get-AgentList $sheet.build.placed) | Where-Object { -not $_.ok } | ForEach-Object { "$($_.file): $($_.note)" }) } } else { $null })

            # Evidence that only exists when it was asked for - say plainly when it was not, so nobody reads silence
            # as "there was nothing to find".
            firstRunObserved = $(if ($sheet.firstRun) { [ordered]@{
                launched = "$($sheet.firstRun.launched)"; note = "$($sheet.firstRun.note)"
                settingsFound = @(Get-AgentList $sheet.firstRun.settingLike)
                settingsFilesItExpects = @(Get-AgentList $sheet.firstRun.settingsFilesItExpects) } }
                else { 'not observed - the application was never started, so the per-user first-run prompts are UNVERIFIED' })
            whatTheInstallerRan = $(if ($sheet.installTrace) { [ordered]@{
                note = "$($sheet.installTrace.note)"
                msiCommands = @(Get-AgentList $sheet.installTrace.msiCommands) } }
                else { 'not recorded - the child processes the installer launched were not observed' })
            # A predecessor that existed and was NOT reused - deliberate when the plan chose fresh, worth a look if not.
            predecessorNotReused = $sheet.predecessorNotReused
            # On a reuse: the planned edits to the old script the build could not apply as written (verify saw them).
            changesNotApplied = @(Get-AgentList $sheet.build.changesNotApplied)
            # THE GATE. Only a pass completes a package; anything else means it is built but not signed off, and the
            # handover has to say so where nobody can miss it.
            verificationPassed = [bool]$sheet.verificationPassed
            # the same two questions asked again, of the files as they are at this moment
            finalCheck = $sheet.finalCheck
            readyToHandOver = $(if ($sheet.finalCheck -and -not $sheet.finalCheck.ok) { "NO - $($sheet.finalCheck.note). The package changed after it was verified, or the verification missed this. Do not ship it." }
                                elseif ([bool]$sheet.verificationPassed) { 'yes - the verification passed and the package still matches it at handover' }
                                else { "NO - the verification did not pass ($(if ($sheet.verification) { "$($sheet.verification.verdict)" } else { 'it did not run' })). The package is built, but it has not been signed off: read the findings before doing anything with it." })
            verification = $(if ($sheet.verification) { [ordered]@{
                verdict = "$($sheet.verification.verdict)"; summary = "$($sheet.verification.summary)"
                findings = @(Get-AgentList $sheet.verification.findings) } } else { $null })

            snapshotReport = $out.SnapshotReport; evaluationSheet = $paths.Html }
        $hp = Join-Path $paths.Dir 'agent-handover.json'
        $handover | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $hp -Encoding utf8 -Force
        $out.Handover = $hp
    }
    Write-Log "Agent export: sheet=$($out.Sheet) snapshot=$($out.SnapshotReport) handover=$($out.Handover)" Success
    return $out
}

