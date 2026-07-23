<#
    IntuneApps - Win32 app inventory with Excel-style filtering.

    ONE Sync button does everything: pulls the apps, and reads the Intune audit log for who created
    each app (a deep backfill the first time, then only what is new). No second button, no separate
    "fetch creators" step.

    Every column header has a filter dropdown - tick the values you want, like Excel AutoFilter.
    Export writes exactly what the filters leave on screen.

    Run:  Run.cmd          (add -NoGui for a headless sync + export, -SelfTest to verify)
#>
[CmdletBinding()]
param([switch]$NoGui, [switch]$Full, [switch]$SelfTest, [string]$Screenshot)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:Root 'lib\Intune.ps1')
. (Join-Path $script:Root 'lib\Xlsx.ps1')

# --- settings ---------------------------------------------------------------------------------------
$cfg = [pscustomobject]@{
    TenantId = ''; ModulePath = ''; DataPath = ''
    IncludeRelationships = $true; FetchCreators = $true; CreatorBackfillDays = 400
    TestPatterns = @('^test\d*$'); UpdPatterns = @('^upd\d*$'); WingetVersionValues = @('^winget$')
    CreationMethodRules = @(); LifecycleRules = @()
}
$cfgPath = Join-Path $script:Root 'settings.json'
if (Test-Path $cfgPath) {
    try {
        $j = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) { if ($p.Name -notlike '_comment*') { $cfg | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force } }
    } catch { [void][Windows.MessageBox]::Show("settings.json is not valid JSON:`n$($_.Exception.Message)", 'IntuneApps') }
}

$script:DataDir   = $(if ($cfg.DataPath) { $cfg.DataPath } else { Join-Path $script:Root 'Data' })
$script:SnapDir   = Join-Path $script:DataDir 'Snapshots'
$script:CacheDir  = Join-Path $script:DataDir 'ModuleCache'
$script:LogPath   = Join-Path $script:DataDir 'ChangeLog.json'
$script:AuditPath = Join-Path $script:DataDir 'AuditCache.json'
foreach ($d in @($script:DataDir, $script:SnapDir, $script:CacheDir)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
$script:LogFile = Join-Path $script:DataDir 'IntuneApps.log'

$script:Apps       = @()
$script:Ledger     = @()
$script:Connected  = $false
$script:Filters    = @{}
$script:FilterBtns = @{}

# Min widths matter: the header holds its title AND a filter button, so without a floor the star
# sizing squeezes headers down to "Kir" / "Versi" and the grid sprouts a horizontal scrollbar.
$script:Cols = @(
    @{ Key='DisplayName';       Title='Name';        Width=2.2; Min=140 }
    @{ Key='Kind';              Title='Kind';        Width=0.7; Min=68  }
    @{ Key='Lifecycle';         Title='Lifecycle';   Width=0.9; Min=92  }
    @{ Key='DisplayVersion';    Title='Version';     Width=0.9; Min=80  }
    @{ Key='Created';           Title='Created';     Width=0.9; Min=88  }
    @{ Key='CreatedBy';         Title='Created by';  Width=1.3; Min=100 }
    @{ Key='CreatedVia';        Title='Created via'; Width=1.3; Min=112 }
    @{ Key='AssignmentSummary'; Title='Assigned to'; Width=1.6; Min=105 }
)

# Lifecycle colours, used by both the tiles and the detail badges.
$script:StageColours = @{
    'LIVE'         = @('#FFE8F5EE', '#FF1F7A4D')
    'SAT'          = @('#FFFDF3E0', '#FF8A6100')
    'UAT'          = @('#FFEAF0FD', '#FF2F5BD0')
    'FailedUAT'    = @('#FFFDEDED', '#FFA32A2A')
    'PreRollout'   = @('#FFF1EDFB', '#FF5B44B5')
    'RETIRED'      = @('#FFEFF1F4', '#FF5A6472')
    'Not recorded' = @('#FFEFF1F4', '#FF8A94A3')
}
function Get-StageColour { param([string]$Stage) if ($script:StageColours.ContainsKey($Stage)) { return $script:StageColours[$Stage] } return @('#FFEFF1F4', '#FF5A6472') }

function Get-CellText { param($App, [string]$Key) $v = $App.$Key; if ($null -eq $v -or "$v" -eq '') { return '(blank)' } return "$v" }

# --- sync -------------------------------------------------------------------------------------------
function Invoke-AppSync {
    param([scriptblock]$Progress, [switch]$FullSync)
    $script:CancelRequested = $false
    $report = { param($t, $p) if ($Progress) { try { & $Progress $t $p } catch {} } }

    if (-not $script:Connected) {
        & $report 'Signing in to Intune...' 2
        $script:Connected = Connect-Intune -TenantId $cfg.TenantId -ModulePath $cfg.ModulePath -CacheRoot $script:CacheDir
        if (-not $script:Connected) { return $false }
    }

    $prev = Get-PreviousSnapshot -SnapshotDir $script:SnapDir
    $apps = Get-Win32AppInventory -Previous $prev -Full:$FullSync `
                                  -IncludeRelationships:([bool]$cfg.IncludeRelationships) -Progress $Progress
    if ($script:CancelRequested) { Write-Log 'Sync cancelled.' Warning; return $false }

    # Same button, same run: first time this walks the audit log back a year to find creators,
    # afterwards it only picks up what changed.
    $cache = $null
    if ($cfg.FetchCreators) {
        if (-not (Test-Path $script:AuditPath)) {
            & $report 'First sync: reading the audit log for who created each app (a few minutes, cached afterwards)...' 88
        }
        $cache = Update-AuditCache -Path $script:AuditPath -BackfillDays ([int]$cfg.CreatorBackfillDays) -Progress $Progress
    } else { $cache = Get-AuditCache -Path $script:AuditPath }
    $apps = Add-AuditToApps -Apps $apps -Cache $cache

    & $report 'Comparing against the previous sync...' 99
    $changes = Compare-Snapshots -Current $apps -Previous $prev
    Save-Snapshot -Apps $apps -SnapshotDir $script:SnapDir | Out-Null
    Add-ToChangeLog -Changes $changes -LogPath $script:LogPath

    Initialize-AppView -Apps $apps
    $known = @((AsArray $script:Apps) | Where-Object { "$($_.CreatedBy)" }).Count
    & $report "Done - $((AsArray $script:Apps).Count) apps, $((AsArray $changes).Count) change(s), creator known for $known." 100
    return $true
}

function Initialize-AppView {
    param([object[]]$Apps)
    $script:Ledger = Get-ChangeLog -LogPath $script:LogPath
    $script:Apps   = Add-AppClassification -Apps $Apps -Cfg $cfg
}

# --- Excel export -----------------------------------------------------------------------------------
function Export-ToExcel {
    param([object[]]$Rows, [string]$Path)
    $rows = AsArray $Rows
    $appCols = @('DisplayName','Kind','Lifecycle','NoteStatus','ManagedText','CreatedVia','DisplayVersion',
                 'Created','CreatedBy','CreatedById','Modified','LastChangedBy','Publisher','Owner',
                 'AssignmentCount','AssignmentSummary','PilotDate','RolloutDate','NotesText','AgeDays','IdleDays',
                 'Flags','InstallCommandLine','UninstallCommandLine','SetupFilePath','RunAsAccount','MinimumOS',
                 'SizeMB','ContentVersion','ScopeTags','Id')

    $appRows = foreach ($a in $rows) {
        $o = [ordered]@{}
        foreach ($c in $appCols) {
            $v = $a.$c
            if ($v -is [array]) { $v = ((AsArray $v) | ForEach-Object { "$_" }) -join '; ' }
            $o[$c] = $v
        }
        [pscustomobject]$o
    }
    $verRows = foreach ($a in $rows) {
        foreach ($v in (Get-VersionHistory -App $a -ChangeLog $script:Ledger)) {
            [pscustomobject]@{ App = $a.DisplayName; When = $v.When; Field = $v.Field; From = $v.From; To = $v.To; Who = $v.Who; Source = $v.Source }
        }
    }
    $modRows = foreach ($a in $rows) {
        foreach ($m in (Get-ModificationHistory -App $a -ChangeLog $script:Ledger)) {
            [pscustomobject]@{ App = $a.DisplayName; When = $m.When; Who = $m.Who; What = $m.What; Source = $m.Source }
        }
    }
    return (New-XlsxWorkbook -Path $Path -Sheets @(
        @{ Name = 'Apps';                 Rows = @($appRows); Columns = $appCols }
        @{ Name = 'Version history';      Rows = @($verRows); Columns = @('App','When','Field','From','To','Who','Source') }
        @{ Name = 'Modification history'; Rows = @($modRows); Columns = @('App','When','Who','What','Source') }
    ))
}

if ($NoGui) {
    $script:LogSink = { param($m, $l) Write-Host $m -ForegroundColor $(switch ($l) { 'Error' { 'Red' } 'Warning' { 'Yellow' } 'Success' { 'Green' } default { 'Gray' } }) }
    if (Invoke-AppSync -FullSync:$Full -Progress { param($t, $p) Write-Host "[$p%] $t" -ForegroundColor DarkCyan }) {
        $x = Join-Path $script:DataDir ('IntuneApps-{0}.xlsx' -f (Get-Date -Format 'yyyyMMdd-HHmm'))
        Export-ToExcel -Rows $script:Apps -Path $x | Out-Null
        Write-Host "Excel: $x" -ForegroundColor Green
    }
    return
}

# --- GUI --------------------------------------------------------------------------------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Intune apps" Width="1240" Height="720" MinWidth="900" MinHeight="540"
        WindowStartupLocation="CenterScreen" Background="#FFF7F8FA"
        FontFamily="Segoe UI" FontSize="12.5" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <SolidColorBrush x:Key="Ink"    Color="#FF1B1F24"/>
    <SolidColorBrush x:Key="Ink2"   Color="#FF5A6472"/>
    <SolidColorBrush x:Key="Ink3"   Color="#FF98A1AE"/>
    <SolidColorBrush x:Key="Line"   Color="#FFE6E9ED"/>
    <SolidColorBrush x:Key="Accent" Color="#FF2F5BD0"/>

    <Style TargetType="Button">
      <Setter Property="Padding" Value="13,7"/><Setter Property="Margin" Value="0,0,7,0"/>
      <Setter Property="MinWidth" Value="84"/><Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="6" Background="White" BorderBrush="#FFD9DEE5" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#FFF2F5F9"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Padding" Value="15,7"/><Setter Property="Margin" Value="0,0,7,0"/>
      <Setter Property="MinWidth" Value="92"/><Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="6" Background="#FF2F5BD0">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#FF2750B8"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="9"/>
    </Style>
    <Style TargetType="TextBlock"><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Foreground" Value="{StaticResource Ink}"/></Style>
    <Style TargetType="TextBox">
      <Setter Property="Padding" Value="7,5"/><Setter Property="BorderBrush" Value="#FFD9DEE5"/>
      <Setter Property="BorderThickness" Value="1"/><Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>

    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="#FFFAFBFC"/><Setter Property="Padding" Value="7,7"/>
      <Setter Property="Foreground" Value="{StaticResource Ink2}"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/><Setter Property="BorderThickness" Value="0,0,1,1"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
    </Style>
    <Style TargetType="DataGridRow">
      <Setter Property="Background" Value="White"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#FFF6F9FD"/></Trigger>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#FFE8F0FE"/><Setter Property="Foreground" Value="{StaticResource Ink}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="9,0"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="{StaticResource Ink}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>

  <Grid Margin="15">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <DockPanel Grid.Row="0" LastChildFill="False" Margin="0,0,0,12">
      <TextBlock DockPanel.Dock="Left" FontSize="18" FontWeight="SemiBold" Text="Intune apps"/>
      <TextBlock x:Name="SubText" DockPanel.Dock="Left" Margin="12,2,0,0" Foreground="{StaticResource Ink2}"/>
      <Button x:Name="BtnFolder" DockPanel.Dock="Right" Content="Data folder"/>
      <Button x:Name="BtnExcel"  DockPanel.Dock="Right" Content="Export to Excel"/>
      <Button x:Name="BtnCancel" DockPanel.Dock="Right" Content="Cancel" IsEnabled="False"/>
      <Button x:Name="BtnSync"   DockPanel.Dock="Right" Content="Sync" Style="{StaticResource Primary}"/>
    </DockPanel>

    <ItemsControl x:Name="Tiles" Grid.Row="1" Margin="0,0,0,11">
      <ItemsControl.ItemsPanel><ItemsPanelTemplate><UniformGrid Rows="1"/></ItemsPanelTemplate></ItemsControl.ItemsPanel>
    </ItemsControl>

    <Border Grid.Row="2" Style="{StaticResource Card}" Padding="11,8" Margin="0,0,0,10">
      <DockPanel>
        <TextBlock DockPanel.Dock="Left" Text="Search" Foreground="{StaticResource Ink3}" Margin="2,0,9,0"/>
        <Button x:Name="BtnClear" DockPanel.Dock="Right" Content="Clear all" MinWidth="78" Margin="9,0,0,0"/>
        <TextBox x:Name="SearchBox" DockPanel.Dock="Left" Width="230"/>
        <ItemsControl x:Name="Chips" Margin="10,0,0,0">
          <ItemsControl.ItemsPanel><ItemsPanelTemplate><WrapPanel/></ItemsPanelTemplate></ItemsControl.ItemsPanel>
        </ItemsControl>
      </DockPanel>
    </Border>

    <Grid Grid.Row="3">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/><ColumnDefinition Width="6"/><ColumnDefinition Width="352"/>
      </Grid.ColumnDefinitions>
      <Border Grid.Column="0" Style="{StaticResource Card}" Padding="1">
        <DataGrid x:Name="Grid1" AutoGenerateColumns="False" IsReadOnly="True" CanUserSortColumns="True"
                  GridLinesVisibility="Horizontal" HeadersVisibility="Column" RowHeaderWidth="0"
                  SelectionMode="Single" BorderThickness="0" Background="White" RowHeight="27"
                  HorizontalGridLinesBrush="#FFF1F3F6" VerticalGridLinesBrush="Transparent"
                  EnableRowVirtualization="True" ScrollViewer.CanContentScroll="True"
                  ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
      </Border>
      <GridSplitter Grid.Column="1" Width="6" HorizontalAlignment="Stretch" Background="Transparent"/>
      <Border Grid.Column="2" Style="{StaticResource Card}">
        <ScrollViewer x:Name="DetailScroll" VerticalScrollBarVisibility="Auto" Padding="15,13">
          <StackPanel x:Name="Detail"/>
        </ScrollViewer>
      </Border>
    </Grid>

    <StackPanel Grid.Row="4" Margin="0,10,0,0">
      <ProgressBar x:Name="Bar" Height="3" Minimum="0" Maximum="100" Foreground="#FF2F5BD0" Background="#FFE6E9ED" BorderThickness="0"/>
      <TextBlock x:Name="StatusText" Margin="0,7,0,0" Foreground="{StaticResource Ink2}" Text="Ready."/>
    </StackPanel>

    <Popup x:Name="Pop" StaysOpen="False" AllowsTransparency="True" Placement="Bottom">
      <Border Background="White" BorderBrush="#FFC9D0D9" BorderThickness="1" CornerRadius="7" Padding="9">
        <DockPanel MinWidth="240" MaxWidth="380">
          <TextBlock x:Name="PopTitle" DockPanel.Dock="Top" FontWeight="SemiBold" Margin="2,0,2,7"/>
          <TextBox   x:Name="PopSearch" DockPanel.Dock="Top" Margin="0,0,0,7"/>
          <DockPanel DockPanel.Dock="Bottom" LastChildFill="False" Margin="0,8,0,0">
            <Button x:Name="BtnPopOk"   DockPanel.Dock="Right" Content="Apply" MinWidth="64" Margin="5,0,0,0" Style="{StaticResource Primary}"/>
            <Button x:Name="BtnPopNone" DockPanel.Dock="Left"  Content="None"  MinWidth="52" Margin="0,0,5,0"/>
            <Button x:Name="BtnPopAll"  DockPanel.Dock="Left"  Content="All"   MinWidth="52" Margin="0,0,5,0"/>
          </DockPanel>
          <ScrollViewer MaxHeight="290" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="PopList"/></ScrollViewer>
        </DockPanel>
      </Border>
    </Popup>
  </Grid>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
foreach ($n in 'SubText','BtnSync','BtnCancel','BtnExcel','BtnFolder','BtnClear','SearchBox','Tiles','Chips',
                'Grid1','Detail','DetailScroll','Bar','StatusText','Pop','PopTitle','PopSearch','PopList',
                'BtnPopOk','BtnPopAll','BtnPopNone') {
    Set-Variable -Name $n -Value $win.FindName($n) -Scope Script
}

$wa = [Windows.SystemParameters]::WorkArea
$win.MaxWidth = $wa.Width; $win.MaxHeight = $wa.Height
if ($win.Width  -gt ($wa.Width  - 20)) { $win.Width  = $wa.Width  - 20 }
if ($win.Height -gt ($wa.Height - 20)) { $win.Height = $wa.Height - 20 }
$win.Left = $wa.Left + [Math]::Max(0, ($wa.Width - $win.Width) / 2)
$win.Top  = $wa.Top  + [Math]::Max(0, ($wa.Height - $win.Height) / 2)

# Status only pumps the dispatcher during a sync. Pumping from inside a UI event handler is
# re-entrancy, and that is what crashed the previous build when a filter changed.
function Set-Status {
    param([string]$Text, [int]$Percent = -1, [switch]$Pump)
    $StatusText.Text = $Text
    if ($Percent -ge 0) { $Bar.Value = $Percent }
    if ($Pump) {
        $frame = New-Object Windows.Threading.DispatcherFrame
        [Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
            [Windows.Threading.DispatcherPriority]::Background, [action]{ $frame.Continue = $false }) | Out-Null
        [Windows.Threading.Dispatcher]::PushFrame($frame)
    }
}
$script:LogSink = { param($m, $l) if ($l -eq 'Error' -or $l -eq 'Warning') { $StatusText.Text = $m } }

# --- small WPF builders ------------------------------------------------------------------------------
function New-Text {
    param([string]$Text, [double]$Size = 12.5, [string]$Colour = '#FF1B1F24', [string]$Weight = 'Normal', [bool]$Wrap = $false, $Margin)
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = "$Text"; $t.FontSize = $Size
    $t.Foreground = (New-Object Windows.Media.BrushConverter).ConvertFromString($Colour)
    $t.FontWeight = [Windows.FontWeights]::$Weight
    if ($Wrap) { $t.TextWrapping = 'Wrap' }
    $t.VerticalAlignment = 'Top'
    if ($Margin) { $t.Margin = $Margin }
    return $t
}
function New-Badge {
    param([string]$Text, [string]$Bg, [string]$Fg)
    $conv = New-Object Windows.Media.BrushConverter
    $b = New-Object Windows.Controls.Border
    $b.Background = $conv.ConvertFromString($Bg)
    $b.CornerRadius = New-Object Windows.CornerRadius(4)
    $b.Padding = New-Object Windows.Thickness(7,2,7,3)
    $b.Margin  = New-Object Windows.Thickness(0,0,5,5)
    $b.Child = (New-Text -Text $Text -Size 11 -Colour $Fg -Weight 'SemiBold')
    return $b
}

# --- lifecycle tiles (click to filter) -----------------------------------------------------------------
$script:OnTileClick = {
    param($s, $e)
    $stage = "$($s.Tag)"
    if ($stage -eq '(all)') { $script:Filters.Remove('Lifecycle') }
    else {
        $set = New-Object 'System.Collections.Generic.HashSet[string]'
        [void]$set.Add($stage)
        $script:Filters['Lifecycle'] = $set
    }
    Set-FilterIndicator -Key 'Lifecycle'
    Update-Grid
}

function Update-Tiles {
    $Tiles.Items.Clear()
    $counts = @{}
    foreach ($a in (AsArray $script:Apps)) { $s = "$($a.Lifecycle)"; $counts[$s] = [int]$counts[$s] + 1 }
    $order = @('LIVE','SAT','UAT','FailedUAT','PreRollout','RETIRED','Not recorded')
    $conv  = New-Object Windows.Media.BrushConverter

    $items = New-Object 'System.Collections.Generic.List[object]'
    [void]$items.Add(@{ Label = 'All apps'; Count = (AsArray $script:Apps).Count; Tag = '(all)'; Fg = '#FF1B1F24' })
    foreach ($s in $order) { if ($counts.ContainsKey($s)) { [void]$items.Add(@{ Label = $s; Count = $counts[$s]; Tag = $s; Fg = (Get-StageColour $s)[1] }) } }

    $active = $script:Filters['Lifecycle']
    foreach ($it in $items) {
        $card = New-Object Windows.Controls.Border
        $card.Background = [Windows.Media.Brushes]::White
        $card.BorderThickness = New-Object Windows.Thickness(1)
        $card.CornerRadius = New-Object Windows.CornerRadius(9)
        $card.Padding = New-Object Windows.Thickness(11,8,11,9)
        $card.Margin  = New-Object Windows.Thickness(0,0,8,0)
        $card.Cursor  = 'Hand'
        $card.Tag = $it.Tag
        $on = $(if ($it.Tag -eq '(all)') { $null -eq $active } else { $active -and $active.Count -eq 1 -and $active.Contains($it.Tag) })
        $card.BorderBrush = $conv.ConvertFromString($(if ($on) { '#FF2F5BD0' } else { '#FFE6E9ED' }))
        $sp = New-Object Windows.Controls.StackPanel
        [void]$sp.Children.Add((New-Text -Text $it.Label -Size 11 -Colour '#FF8A94A3'))
        [void]$sp.Children.Add((New-Text -Text ([string]$it.Count) -Size 20 -Colour $it.Fg -Weight 'SemiBold'))
        $card.Child = $sp
        $card.Add_MouseLeftButtonUp($script:OnTileClick)
        [void]$Tiles.Items.Add($card)
    }
}

# --- filter chips ---------------------------------------------------------------------------------------
$script:OnChipClick = {
    param($s, $e)
    $script:Filters.Remove("$($s.Tag)")
    Set-FilterIndicator -Key "$($s.Tag)"
    Update-Grid
}

function Update-Chips {
    $Chips.Items.Clear()
    $conv = New-Object Windows.Media.BrushConverter
    foreach ($k in @($script:Filters.Keys | Sort-Object)) {
        $set = $script:Filters[$k]
        if ($null -eq $set) { continue }
        $col = $script:Cols | Where-Object { $_.Key -eq $k } | Select-Object -First 1
        $vals = @($set) | Sort-Object
        $show = $(if ($vals.Count -le 2) { $vals -join ', ' } else { "$($vals.Count) selected" })

        $b = New-Object Windows.Controls.Border
        $b.Background = $conv.ConvertFromString('#FFEAF0FD')
        $b.CornerRadius = New-Object Windows.CornerRadius(11)
        $b.Padding = New-Object Windows.Thickness(9,3,5,4)
        $b.Margin  = New-Object Windows.Thickness(0,0,6,0)
        $dp = New-Object Windows.Controls.StackPanel; $dp.Orientation = 'Horizontal'
        [void]$dp.Children.Add((New-Text -Text "$($col.Title): $show" -Size 11.5 -Colour '#FF2F5BD0' -Weight 'SemiBold'))
        $x = New-Object Windows.Controls.TextBlock
        $x.Text = ' x'; $x.FontSize = 11.5; $x.Margin = New-Object Windows.Thickness(6,0,3,0)
        $x.Foreground = $conv.ConvertFromString('#FF2F5BD0'); $x.Cursor = 'Hand'
        [void]$dp.Children.Add($x)
        $b.Child = $dp
        $b.Tag = $k; $b.Cursor = 'Hand'
        $b.Add_MouseLeftButtonUp($script:OnChipClick)
        [void]$Chips.Items.Add($b)
    }
}

# --- columns + per-column filter dropdown ------------------------------------------------------------------
$script:OnFilterClick = {
    param($s, $e)
    $key = "$($s.Tag)"
    $script:PopCol = $key
    $col = $script:Cols | Where-Object { $_.Key -eq $key } | Select-Object -First 1
    $PopTitle.Text = "Filter by $($col.Title.ToLower())"
    $PopSearch.Text = ''
    Build-PopupList -Key $key
    $Pop.PlacementTarget = $s
    $Pop.IsOpen = $true
}

function Build-Columns {
    $Grid1.Columns.Clear()
    $conv = New-Object Windows.Media.BrushConverter
    foreach ($c in $script:Cols) {
        $col = New-Object Windows.Controls.DataGridTextColumn
        $col.Binding = New-Object Windows.Data.Binding($c.Key)
        $col.SortMemberPath = $c.Key
        $col.Width = New-Object Windows.Controls.DataGridLength($c.Width, [Windows.Controls.DataGridLengthUnitType]::Star)
        $col.MinWidth = $c.Min

        # The filter button carries its column key in .Tag, so ONE shared handler serves every
        # column - no per-column closures whose scope could go wrong.
        $dp = New-Object Windows.Controls.DockPanel
        $btn = New-Object Windows.Controls.Button
        $btn.Content = [string][char]0x25BC
        $btn.Tag = $c.Key
        $btn.Width = 14; $btn.Height = 14; $btn.MinWidth = 14; $btn.FontSize = 6.5
        $btn.Padding = New-Object Windows.Thickness(0)
        $btn.Margin  = New-Object Windows.Thickness(3,0,0,0)
        $btn.Cursor  = 'Hand'
        $btn.ToolTip = 'Filter this column'
        $btn.Add_Click($script:OnFilterClick)
        [Windows.Controls.DockPanel]::SetDock($btn, [Windows.Controls.Dock]::Right)
        [void]$dp.Children.Add($btn)
        [void]$dp.Children.Add((New-Text -Text $c.Title -Size 12 -Colour '#FF5A6472' -Weight 'SemiBold'))
        $col.Header = $dp
        $script:FilterBtns[$c.Key] = $btn
        $Grid1.Columns.Add($col)
    }
}

# Offer only values still reachable under the OTHER active filters - same as Excel.
function Build-PopupList {
    param([string]$Key)
    $PopList.Children.Clear()
    $counts = @{}
    foreach ($a in (Get-VisibleRows -IgnoreColumn $Key)) {
        $v = Get-CellText $a $Key
        $counts[$v] = [int]$counts[$v] + 1
    }
    $allowed = $script:Filters[$Key]
    foreach ($v in ($counts.Keys | Sort-Object)) {
        $cb = New-Object Windows.Controls.CheckBox
        $cb.Content = "$v  ($($counts[$v]))"
        $cb.Tag = $v
        $cb.Margin = New-Object Windows.Thickness(2,3,2,3)
        $cb.IsChecked = $(if ($null -eq $allowed) { $true } else { $allowed.Contains($v) })
        [void]$PopList.Children.Add($cb)
    }
    if ($PopList.Children.Count -eq 0) { [void]$PopList.Children.Add((New-Text -Text '(no values)' -Colour '#FF98A1AE')) }
}

function Set-FilterIndicator {
    param([string]$Key)
    $btn = $script:FilterBtns[$Key]
    if (-not $btn) { return }
    $conv = New-Object Windows.Media.BrushConverter
    if ($script:Filters.ContainsKey($Key) -and $null -ne $script:Filters[$Key]) {
        $btn.Foreground = $conv.ConvertFromString('#FF2F5BD0'); $btn.FontWeight = 'Bold'; $btn.ToolTip = 'Filtered - click to change'
    } else {
        $btn.Foreground = $conv.ConvertFromString('#FF98A1AE'); $btn.FontWeight = 'Normal'; $btn.ToolTip = 'Filter this column'
    }
}

function Get-VisibleRows {
    param([string]$IgnoreColumn)
    $q = "$($SearchBox.Text)".Trim().ToLower()
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($a in (AsArray $script:Apps)) {
        $ok = $true
        foreach ($k in @($script:Filters.Keys)) {
            if ($k -eq $IgnoreColumn) { continue }
            $set = $script:Filters[$k]
            if ($null -eq $set) { continue }
            if (-not $set.Contains((Get-CellText $a $k))) { $ok = $false; break }
        }
        if (-not $ok) { continue }
        if ($q) {
            $hay = ((@($a.DisplayName, $a.DisplayVersion, $a.Publisher, $a.Owner, $a.NotesText, $a.Flags,
                       $a.AssignmentSummary, $a.CreatedBy, $a.CreatedVia, $a.Lifecycle, $a.Id)) -join ' ').ToLower()
            if ($hay -notmatch [regex]::Escape($q)) { continue }
        }
        [void]$out.Add($a)
    }
    return ,$out.ToArray()      # comma: a 1-row result must stay an array or the DataGrid throws
}

function Update-Grid {
    $rows = Get-VisibleRows
    $Grid1.ItemsSource = $rows
    Update-Tiles
    Update-Chips
    $n = (AsArray $rows).Count
    $total = (AsArray $script:Apps).Count
    Set-Status $(if ($n -eq $total) { "$total apps." } else { "$n of $total apps match. Export writes exactly this list." })
}

# --- detail pane ---------------------------------------------------------------------------------------------
function Add-Section {
    param([string]$Title)
    $t = New-Text -Text $Title.ToUpper() -Size 10.5 -Colour '#FF98A1AE' -Weight 'SemiBold'
    $t.Margin = New-Object Windows.Thickness(0,16,0,6)
    [void]$Detail.Children.Add($t)
}
function Add-Fact {
    param([string]$Key, $Value, [string]$Colour = '#FF1B1F24')
    if ($null -eq $Value -or "$Value" -eq '') { return }
    $g = New-Object Windows.Controls.Grid
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = New-Object Windows.GridLength(104)
    $c2 = New-Object Windows.Controls.ColumnDefinition
    $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
    $k = New-Text -Text $Key -Size 12 -Colour '#FF8A94A3'
    $v = New-Text -Text "$Value" -Size 12 -Colour $Colour -Wrap $true
    [Windows.Controls.Grid]::SetColumn($v, 1)
    [void]$g.Children.Add($k); [void]$g.Children.Add($v)
    $g.Margin = New-Object Windows.Thickness(0,0,0,4)
    [void]$Detail.Children.Add($g)
}
function Add-Bullets {
    param([object[]]$Items, [string]$EmptyText)
    $items = AsArray $Items
    if ($items.Count -eq 0) { [void]$Detail.Children.Add((New-Text -Text $EmptyText -Size 12 -Colour '#FF98A1AE' -Wrap $true)); return }
    foreach ($i in $items) {
        $t = New-Text -Text "$i" -Size 12 -Wrap $true
        $t.Margin = New-Object Windows.Thickness(0,0,0,3)
        [void]$Detail.Children.Add($t)
    }
}

function Show-Detail {
    param($A)
    $Detail.Children.Clear()
    $DetailScroll.ScrollToTop()
    if (-not $A) { [void]$Detail.Children.Add((New-Text -Text 'Select an app to see everything known about it.' -Colour '#FF98A1AE' -Wrap $true)); return }
    $conv = New-Object Windows.Media.BrushConverter

    $title = New-Text -Text $A.DisplayName -Size 16 -Weight 'SemiBold' -Wrap $true
    [void]$Detail.Children.Add($title)
    [void]$Detail.Children.Add((New-Text -Text "$($A.DisplayVersion)  -  $($A.Kind)" -Size 12 -Colour '#FF8A94A3' -Margin (New-Object Windows.Thickness(0,2,0,9))))

    # badges
    $wrap = New-Object Windows.Controls.WrapPanel
    $sc = Get-StageColour "$($A.Lifecycle)"
    [void]$wrap.Children.Add((New-Badge -Text "$($A.Lifecycle)" -Bg $sc[0] -Fg $sc[1]))
    if ($A.ManagedText) { [void]$wrap.Children.Add((New-Badge -Text "$($A.ManagedText)" -Bg '#FFE8F5EE' -Fg '#FF1F7A4D')) }
    if ($A.NoteStatus -and $A.NoteStatus -ne 'OK') { [void]$wrap.Children.Add((New-Badge -Text "Status $($A.NoteStatus)" -Bg '#FFFDEDED' -Fg '#FFA32A2A')) }
    $ac = [int]$A.AssignmentCount
    [void]$wrap.Children.Add((New-Badge -Text $(if ($ac -eq 0) { 'Unassigned' } else { "$ac group$(if ($ac -ne 1) { 's' })" }) -Bg $(if ($ac -eq 0) { '#FFFDF3E0' } else { '#FFEFF1F4' }) -Fg $(if ($ac -eq 0) { '#FF8A6100' } else { '#FF5A6472' })))
    [void]$Detail.Children.Add($wrap)

    Add-Section 'Provenance'
    Add-Fact 'Created'     "$($A.Created)   ($($A.AgeDays) days ago)"
    Add-Fact 'Created by'  $(if ($A.CreatedBy) { "$($A.CreatedBy)" } else { 'not fetched yet - click Sync' }) $(if ($A.CreatedBy) { '#FF1B1F24' } else { '#FF98A1AE' })
    Add-Fact 'Creator ID'  $A.CreatedById
    Add-Fact 'Created via' $A.CreatedVia
    Add-Fact 'Modified'    $A.Modified
    Add-Fact 'Changed by'  $A.LastChangedBy
    Add-Fact 'Publisher'   $A.Publisher
    Add-Fact 'Pilot'       $A.PilotDate
    Add-Fact 'Rollout'     $A.RolloutDate
    Add-Fact 'App ID'      $A.Id '#FF5A6472'

    Add-Section 'Timeline'
    $mh = AsArray (Get-ModificationHistory -App $A -ChangeLog $script:Ledger)
    if ($mh.Count -eq 0) {
        [void]$Detail.Children.Add((New-Text -Text 'Nothing recorded yet. Entries appear from the audit log, from dated lines in the app notes, and from changes this tool sees between syncs.' -Size 12 -Colour '#FF98A1AE' -Wrap $true))
    } else {
        foreach ($m in ($mh | Select-Object -First 25)) {
            $row = New-Object Windows.Controls.Border
            $row.BorderThickness = New-Object Windows.Thickness(2,0,0,0)
            $row.BorderBrush = $conv.ConvertFromString('#FFDCE4F5')
            $row.Padding = New-Object Windows.Thickness(9,1,0,7)
            $sp = New-Object Windows.Controls.StackPanel
            $when = ("$($m.When)" -replace 'T', ' ' -replace '\..*$', '')
            $head = $(if ("$($m.Who)") { "$when   $($m.Who)" } else { $when })
            [void]$sp.Children.Add((New-Text -Text $head -Size 11 -Colour '#FF8A94A3'))
            [void]$sp.Children.Add((New-Text -Text "$($m.What)" -Size 12 -Wrap $true))
            $row.Child = $sp
            [void]$Detail.Children.Add($row)
        }
    }

    Add-Section 'Version history'
    $vh = AsArray (Get-VersionHistory -App $A -ChangeLog $script:Ledger)
    if ($vh.Count -eq 0) {
        [void]$Detail.Children.Add((New-Text -Text "Current version is $($A.DisplayVersion). A transition is only listed once a sync actually sees the version change." -Size 12 -Colour '#FF98A1AE' -Wrap $true))
    } else {
        foreach ($v in $vh) { Add-Fact ("$($v.When)" -replace 'T.*$', '') "$(if ($v.From) { $v.From } else { '?' }) -> $($v.To)" }
    }

    Add-Section 'Assignments'
    Add-Bullets -Items ((AsArray $A.Assignments) | ForEach-Object { "$($_.Intent)  ->  $($_.Target)" }) -EmptyText 'Not assigned to anything.'

    Add-Section 'Install'
    Add-Fact 'Setup file' $A.SetupFilePath
    Add-Fact 'Install'    $A.InstallCommandLine
    Add-Fact 'Uninstall'  $A.UninstallCommandLine
    Add-Fact 'Run as'     $A.RunAsAccount
    Add-Fact 'Minimum OS' $A.MinimumOS
    Add-Fact 'Size (MB)'  $A.SizeMB

    Add-Section 'Detection'
    Add-Bullets -Items $A.DetectionRules -EmptyText 'No detection rules.'

    Add-Section 'Notes (raw, as stored in Intune)'
    $raw = New-Text -Text $(if ("$($A.RawNotes)") { "$($A.RawNotes)" } else { 'Empty - that is why Lifecycle reads "Not recorded".' }) -Size 11.5 -Colour '#FF5A6472' -Wrap $true
    $raw.FontFamily = New-Object Windows.Media.FontFamily('Consolas')
    $box = New-Object Windows.Controls.Border
    $box.Background = $conv.ConvertFromString('#FFF7F8FA')
    $box.CornerRadius = New-Object Windows.CornerRadius(6)
    $box.Padding = New-Object Windows.Thickness(9)
    $box.Child = $raw
    [void]$Detail.Children.Add($box)
}

# --- events ----------------------------------------------------------------------------------------------------
function Start-Sync {
    param([switch]$FullSync)
    $BtnSync.IsEnabled = $false; $BtnCancel.IsEnabled = $true
    try {
        $ok = Invoke-AppSync -FullSync:$FullSync -Progress { param($t, $p) Set-Status $t $p -Pump }
        if ($ok) { Update-Grid; Set-Status "Sync complete - $((AsArray $script:Apps).Count) apps." 100 } else { $Bar.Value = 0 }
    } catch {
        Set-Status "Sync failed: $($_.Exception.Message)" 0
        Write-Log "Sync failed: $($_.Exception.Message)" Error
    } finally { $BtnSync.IsEnabled = $true; $BtnCancel.IsEnabled = $false }
}

$BtnSync.Add_Click({ Start-Sync })
$BtnCancel.Add_Click({ $script:CancelRequested = $true; Set-Status 'Stopping after the current request - anything already fetched is kept...' })
$BtnFolder.Add_Click({ Start-Process explorer.exe $script:DataDir })
$BtnClear.Add_Click({
    $script:Filters = @{}
    $SearchBox.Text = ''
    foreach ($c in $script:Cols) { Set-FilterIndicator -Key $c.Key }
    Update-Grid
})
$SearchBox.Add_TextChanged({ Update-Grid })
$Grid1.Add_SelectionChanged({ Show-Detail $Grid1.SelectedItem })
$PopSearch.Add_TextChanged({
    $q = "$($PopSearch.Text)".Trim().ToLower()
    foreach ($cb in $PopList.Children) {
        if ($cb -is [Windows.Controls.CheckBox]) {
            $cb.Visibility = $(if (-not $q -or "$($cb.Content)".ToLower().Contains($q)) { 'Visible' } else { 'Collapsed' })
        }
    }
})
$BtnPopAll.Add_Click({  foreach ($cb in $PopList.Children) { if ($cb -is [Windows.Controls.CheckBox] -and $cb.Visibility -eq 'Visible') { $cb.IsChecked = $true  } } })
$BtnPopNone.Add_Click({ foreach ($cb in $PopList.Children) { if ($cb -is [Windows.Controls.CheckBox] -and $cb.Visibility -eq 'Visible') { $cb.IsChecked = $false } } })
$BtnPopOk.Add_Click({
    $key = "$($script:PopCol)"
    $sel = New-Object 'System.Collections.Generic.HashSet[string]'
    $total = 0
    foreach ($cb in $PopList.Children) {
        if ($cb -isnot [Windows.Controls.CheckBox]) { continue }
        $total++
        if ($cb.IsChecked) { [void]$sel.Add("$($cb.Tag)") }
    }
    if ($sel.Count -eq $total) { $script:Filters.Remove($key) } else { $script:Filters[$key] = $sel }
    Set-FilterIndicator -Key $key
    $Pop.IsOpen = $false
    Update-Grid
})
$BtnExcel.Add_Click({
    $rows = Get-VisibleRows
    if ((AsArray $rows).Count -eq 0) { Set-Status 'Nothing to export - no apps match the current filters.'; return }
    try {
        Set-Status "Building the workbook for $((AsArray $rows).Count) app(s)..." -Pump
        $path = Join-Path $script:DataDir ('IntuneApps-{0}.xlsx' -f (Get-Date -Format 'yyyyMMdd-HHmm'))
        Export-ToExcel -Rows $rows -Path $path | Out-Null
        Set-Status "Exported $((AsArray $rows).Count) app(s) to $(Split-Path -Leaf $path)"
        Start-Process explorer.exe "/select,`"$path`""
    } catch { Set-Status "Excel export failed: $($_.Exception.Message)" }
})

Build-Columns
Show-Detail $null
$prev = Get-PreviousSnapshot -SnapshotDir $script:SnapDir
if ($prev) {
    Initialize-AppView -Apps (Add-AuditToApps -Apps $prev -Cache (Get-AuditCache -Path $script:AuditPath))
    Update-Grid
    $newest = Get-ChildItem -LiteralPath $script:SnapDir -Filter 'apps-*.json' -File | Sort-Object Name -Descending | Select-Object -First 1
    $SubText.Text = "$((AsArray $script:Apps).Count) apps  -  last sync $($newest.LastWriteTime.ToString('dd MMM HH:mm'))"
    $known = @((AsArray $script:Apps) | Where-Object { "$($_.CreatedBy)" }).Count
    if ($known -eq 0) { Set-Status 'Creator names have not been fetched yet - click Sync. The first run reads the audit log back a year, then keeps itself up to date.' }
} else {
    $SubText.Text = 'no data yet'
    Set-Status 'Click Sync to pull your apps from Intune.'
}

if ($SelfTest) {
    $script:fail = 0
    function Check { param([string]$Name, [scriptblock]$Do)
        try { $r = & $Do; Write-Host ("  PASS  {0}{1}" -f $Name, $(if ($r) { " -> $r" } else { '' })) -ForegroundColor Green }
        catch { $script:fail++; Write-Host ("  FAIL  {0}`n        {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red }
    }
    Write-Host "`nSELF TEST" -ForegroundColor Cyan
    Check 'columns built'   { "$($Grid1.Columns.Count) cols: $((@($Grid1.Columns | ForEach-Object { $_.Header.Children[1].Text }) -join ', '))" }
    Check 'grid populated'  { "$((AsArray $Grid1.ItemsSource).Count) rows" }
    Check 'lifecycle tiles' { "$($Tiles.Items.Count) tiles" }
    foreach ($k in @('Lifecycle','Kind','CreatedVia','CreatedBy','DisplayName')) {
        Check "filter dropdown '$k'" { $script:PopCol = $k; Build-PopupList -Key $k; "$($PopList.Children.Count) values" }
    }
    Check 'single-row filter (PreRollout) - the old crash' {
        $s = New-Object 'System.Collections.Generic.HashSet[string]'; [void]$s.Add('PreRollout')
        $script:Filters['Lifecycle'] = $s; Set-FilterIndicator -Key 'Lifecycle'
        Update-Grid
        Show-Detail (AsArray (Get-VisibleRows))[0]
        "$((AsArray $Grid1.ItemsSource).Count) row, detail has $($Detail.Children.Count) blocks, $($Chips.Items.Count) chip"
    }
    Check 'detail for every lifecycle stage' {
        $n = 0
        foreach ($st in @('LIVE','SAT','UAT','FailedUAT','PreRollout','RETIRED','Not recorded')) {
            $a = (AsArray $script:Apps) | Where-Object { $_.Lifecycle -eq $st } | Select-Object -First 1
            if ($a) { Show-Detail $a; $n++ }
        }
        "$n stages rendered"
    }
    Check 'tile click filters' {
        & $script:OnTileClick ([pscustomobject]@{ Tag = 'RETIRED' }) $null
        "$((AsArray $Grid1.ItemsSource).Count) retired"
    }
    Check 'chip removal clears it' {
        & $script:OnChipClick ([pscustomobject]@{ Tag = 'Lifecycle' }) $null
        if ((AsArray $Grid1.ItemsSource).Count -ne (AsArray $script:Apps).Count) { throw 'filter not cleared' }
        "back to $((AsArray $Grid1.ItemsSource).Count)"
    }
    Check 'combined filters' {
        $s1 = New-Object 'System.Collections.Generic.HashSet[string]'; [void]$s1.Add('Standard')
        $s2 = New-Object 'System.Collections.Generic.HashSet[string]'; [void]$s2.Add('SCCM2Intune')
        $script:Filters['Kind'] = $s1; $script:Filters['CreatedVia'] = $s2
        Update-Grid
        "$((AsArray $Grid1.ItemsSource).Count) rows, $($Chips.Items.Count) chips"
    }
    Check 'search' { $script:Filters = @{}; $SearchBox.Text = 'chrome'; $n = (AsArray (Get-VisibleRows)).Count; $SearchBox.Text = ''; "$n matches" }
    Check 'excel export of a filtered view' {
        $s = New-Object 'System.Collections.Generic.HashSet[string]'; [void]$s.Add('RETIRED')
        $script:Filters['Lifecycle'] = $s
        $rows = Get-VisibleRows
        $p = Join-Path $env:TEMP 'selftest.xlsx'
        Export-ToExcel -Rows $rows -Path $p | Out-Null
        "$((AsArray $rows).Count) apps -> $([int]((Get-Item $p).Length/1KB)) KB"
    }
    Write-Host ("`n{0}" -f $(if ($script:fail) { "$($script:fail) CHECK(S) FAILED" } else { 'ALL CHECKS PASSED' })) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
    return
}

# Renders the real window off the side of the screen to a PNG, so the layout can be reviewed
# without a person having to open it.
if ($Screenshot) {
    $win.Left = -12000
    $win.Show()
    for ($i = 0; $i -lt 6; $i++) {
        $f = New-Object Windows.Threading.DispatcherFrame
        [Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
            [Windows.Threading.DispatcherPriority]::ContextIdle, [action]{ $f.Continue = $false }) | Out-Null
        [Windows.Threading.Dispatcher]::PushFrame($f)
    }
    if ($Grid1.Items.Count -gt 0) { $Grid1.SelectedIndex = 0 }
    for ($i = 0; $i -lt 6; $i++) {
        $f = New-Object Windows.Threading.DispatcherFrame
        [Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
            [Windows.Threading.DispatcherPriority]::ContextIdle, [action]{ $f.Continue = $false }) | Out-Null
        [Windows.Threading.Dispatcher]::PushFrame($f)
    }
    $w = [int]$win.ActualWidth; $h = [int]$win.ActualHeight
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($win)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Open($Screenshot, [IO.FileMode]::Create)
    try { $enc.Save($fs) } finally { $fs.Dispose() }
    $win.Close()
    Write-Host "Saved $Screenshot ($w x $h)"
    return
}

$win.ShowDialog() | Out-Null
