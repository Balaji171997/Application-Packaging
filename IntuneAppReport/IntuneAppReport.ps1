<#
    Intune App Monitor - Win32 app reporting for Intune.  Dark, six pages, one Sync button.

      Overview   lifecycle tiles, apps by lifecycle / kind, created + changes per month, what needs attention
      Apps       every Win32 app; Excel-style filter on every column; click a row for the app page
      App page   Overview / All settings / Assignments / History - everything known about one app
      Activity   every change in the tenant, by period (incl. custom range), kind, person, text
      People     who changes what
      Insights   built-in checks (Failed UAT, stale, unassigned LIVE, test apps left behind, ...)

    Sync pulls the apps, reads the app audit log (deep once, incremental after), resolves people and
    groups to names, snapshots, and translates history. Data\ is the long-term record - Intune forgets
    audit events after about a year, this tool does not.

    Run:  Run.cmd     -NoGui: headless sync + export   -SelfTest: verify
                      -Screenshot x.png [-Page apps|activity|people|insights] [-SelectApp 'Name*' [-Tab history]]
#>
[CmdletBinding()]
param([switch]$NoGui, [switch]$Full, [switch]$SelfTest, [string]$Screenshot, [string]$SelectApp, [string]$Page, [string]$Tab)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

# Tool root. Compiled build (IntuneAppMonitor.exe): Build-Team.ps1 embeds the libs, $PSScriptRoot is empty in ps2exe, so the root is the exe's folder
# and the lib sources are already embedded ($script:PackedLibs), so nothing is read from disk.
$script:Root = if ($script:ToolRoot) { $script:ToolRoot } elseif ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
if (-not $script:PackedLibs) {
    . (Join-Path $script:Root 'lib\Intune.ps1')
    . (Join-Path $script:Root 'lib\Xlsx.ps1')
}

# --- settings ---------------------------------------------------------------------------------------
$cfg = [pscustomobject]@{
    TenantId = ''; ModulePath = ''; DataPath = ''
    IncludeRelationships = $true; FetchCreators = $true; CreatorBackfillDays = 400
    TestPatterns = @('^test\d*$'); UpdPatterns = @('^upd\d*$'); WingetVersionValues = @('^winget$')
    CreationMethodRules = @(); LifecycleRules = @(); StaleAfterDays = 365
}
$cfgPath = Join-Path $script:Root 'settings.json'
if (Test-Path $cfgPath) {
    try {
        $j = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) { if ($p.Name -notlike '_comment*') { $cfg | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force } }
    } catch { [void][Windows.MessageBox]::Show("settings.json is not valid JSON:`n$($_.Exception.Message)", 'Intune App Monitor') }
}

# --- paths: relative to the tool unless settings.json gives an existing absolute path ------------------------
function Resolve-ToolPath {
    param([string]$Path, [string]$Fallback)
    $p = "$Path".Trim()
    if (-not $p) { return $Fallback }
    if ([IO.Path]::IsPathRooted($p)) { if (Test-Path -LiteralPath $p) { return $p }; Write-Log "settings.json path not found, using the tool's own copy instead: $p" Warning; return $Fallback }
    return (Join-Path $script:Root $p)
}
$script:ModuleDir  = Resolve-ToolPath -Path $cfg.ModulePath -Fallback (Join-Path $script:Root 'lib\PowerShell Module')
$cfg.ModulePath    = $script:ModuleDir
$script:DataDir    = Resolve-ToolPath -Path $cfg.DataPath -Fallback (Join-Path $script:Root 'Data')
$script:SnapDir    = Join-Path $script:DataDir 'Snapshots'
$script:CacheDir   = Join-Path $script:DataDir 'ModuleCache'
$script:LogPath    = Join-Path $script:DataDir 'ChangeLog.json'
$script:AuditPath  = Join-Path $script:DataDir 'AuditCache.json'
$script:FeedPath   = Join-Path $script:DataDir 'ActivityFeed.json'
$script:PeoplePath = Join-Path $script:DataDir 'people.json'
foreach ($d in @($script:DataDir, $script:SnapDir, $script:CacheDir)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
$script:LogFile = Join-Path $script:DataDir 'IntuneAppMonitor.log'

$script:Apps = @(); $script:Ledger = @(); $script:Feed = $null; $script:Coverage = $null; $script:Connected = $false; $script:GroupMap = @{}
$script:Filters = @{}            # apps grid: column key -> HashSet of allowed values
$script:FilterBtns = @{}; $script:ColState = @{}   # column key -> 'auto' | 'on' | 'off'
$script:AppsQuery = ''; $script:CurrentPage = 'overview'; $script:CurrentApp = $null; $script:AppTab = 'overview'
$script:HistFilter = @{ Kind = ''; Who = '' }
$script:Act = @{ Preset = '30'; From = $null; To = $null; Kind = ''; Who = ''; Q = ''; Shown = 100 }

# Apps grid columns, in PRIORITY order (what stays when the window is narrow). Every column's minimum
# width is measured from its full header text at start-up, so a header is never cut to "Kir" or "Versi":
# columns that do not fit are hidden (Columns button brings them back with a horizontal scroll).
$script:Cols = @(
    @{ Key='DisplayName';       Title='Name';            Width=2.0; Min=170 }
    @{ Key='Lifecycle';         Title='Lifecycle';       Width=1.0; Min=104 }   # "Not recorded" chip
    @{ Key='Kind';              Title='Kind';            Width=0.8; Min=88  }   # "Standard" chip
    @{ Key='DisplayVersion';    Title='Version';         Width=1.0; Min=0   }
    @{ Key='LastChange';        Title='Last change';     Width=1.0; Min=0   }
    @{ Key='AssignmentCount';   Title='Assignments';     Width=0.9; Min=0   }
    @{ Key='Created';           Title='Created';         Width=1.0; Min=0   }
    @{ Key='CreatedByName';     Title='Created by';      Width=1.5; Min=0   }
    @{ Key='LastChangedByName'; Title='Last changed by'; Width=1.4; Min=0   }
    @{ Key='CreatedVia';        Title='Created via';     Width=1.3; Min=0   }
    @{ Key='Publisher';         Title='Publisher';       Width=1.3; Min=0   }
)
$script:GridOrder = @('DisplayName','DisplayVersion','Kind','Lifecycle','Publisher','Created','CreatedByName','CreatedVia','AssignmentCount','LastChange','LastChangedByName')

# Palette (dark). Lifecycle stages and change kinds each get one colour, used the same way everywhere.
$script:C = @{
    Bg='#FF0F1419'; Rail='#FF0B0F14'; Panel='#FF161C24'; Panel2='#FF1C242E'; Line='#FF242E3A'; Line2='#FF1D2530'
    Ink='#FFE7ECF2'; Ink2='#FFA3B0BF'; Ink3='#FF6C7A8A'; Accent='#FF4C8DFF'; AccentInk='#FF08111F'; AccentSoft='#FF17263F'
    OldBg='#FF3A2529'; OldInk='#FFF2A6A6'; NewBg='#FF173427'; NewInk='#FF96E3B4'
}
$script:LifeOrder  = @('LIVE','SAT','UAT','FailedUAT','PreRollout','RETIRED','Not recorded')
$script:LifeColour = @{ 'LIVE'='#FF3FCF8E'; 'SAT'='#FFF2B84B'; 'UAT'='#FF5FA8FF'; 'FailedUAT'='#FFFF6B6B'; 'PreRollout'='#FFB48CFF'; 'RETIRED'='#FF8A97A6'; 'Not recorded'='#FF5A6775' }
$script:LifeBg     = @{ 'LIVE'='#FF123126'; 'SAT'='#FF3A2E14'; 'UAT'='#FF152B45'; 'FailedUAT'='#FF3B2020'; 'PreRollout'='#FF2A2140'; 'RETIRED'='#FF1C242E'; 'Not recorded'='#FF1C242E' }
$script:KindColour = @{ 'Test'='#FFFF9F6B'; 'UPD'='#FF6AA9FF'; 'Winget'='#FFB48CFF'; 'Standard'='#FFA3B0BF' }
$script:KindBg     = @{ 'Test'='#FF3A2718'; 'UPD'='#FF152B45'; 'Winget'='#FF2A2140'; 'Standard'='#FF1C242E' }
$script:ChangeColour = @{ 'lifecycle'='#FFF2B84B'; 'assign'='#FF3ECFB2'; 'version'='#FF6AA9FF'; 'content'='#FFB48CFF'; 'create'='#FF3FCF8E'; 'delete'='#FFFF6B6B'; 'relation'='#FFC79BFF'; 'edit'='#FF9AA8B8'; 'note'='#FF7F8C9B'; 'minor'='#FF5F6C7B' }
$script:ChangeKinds  = [ordered]@{ ''='All kinds'; lifecycle='Lifecycle'; assign='Assignments'; version='Versions'; content='Content'; create='Created'; relation='Supersedence'; edit='Other' }
function Get-ChangeGroup { param([string]$Kind) if ($Kind -in 'lifecycle','assign','version','content','create','relation') { return $Kind }; return 'edit' }
function Get-CellText { param($App, [string]$Key) $v = $App.$Key; if ($null -eq $v -or "$v" -eq '') { return '(blank)' }; return "$v" }

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
    $apps = Get-Win32AppInventory -Previous $prev -Full:$FullSync -IncludeRelationships:([bool]$cfg.IncludeRelationships) -Progress $Progress
    if ($script:CancelRequested) { Write-Log 'Sync cancelled.' Warning; return $false }

    # Same button, same run: first time the app audit log is read back a year, afterwards only what is new.
    $cache = $null
    if ($cfg.FetchCreators) {
        if (-not (Test-Path $script:AuditPath)) { & $report 'First sync: reading the app audit log for who changed what (cached afterwards)...' 88 }
        elseif ((Get-AuditCache -Path $script:AuditPath).Legacy) { & $report 'Rebuilding readable change history: re-reading the app audit log once...' 88 }
        $cache = Update-AuditCache -Path $script:AuditPath -BackfillDays ([int]$cfg.CreatorBackfillDays) -Progress $Progress
    } else { $cache = Get-AuditCache -Path $script:AuditPath }
    [void](Repair-DetachedDetails -Cache $cache -KnownAppIds @($apps | ForEach-Object { $_.Id }))
    Save-AuditCache -Cache $cache -Path $script:AuditPath
    [void](Update-PeopleFile -Path $script:PeoplePath -Cache $cache)
    $script:UserMap  = Build-UserMap -Cache $cache -PeoplePath $script:PeoplePath
    $apps = Add-AuditToApps -Apps $apps -Cache $cache
    $script:GroupMap = Build-GroupMap -Cache $cache -Apps $apps
    $script:Coverage = Get-HistoryCoverage -Cache $cache

    & $report 'Comparing against the previous sync...' 99
    $changes = Compare-Snapshots -Current $apps -Previous $prev
    Save-Snapshot -Apps $apps -SnapshotDir $script:SnapDir | Out-Null
    Add-ToChangeLog -Changes $changes -LogPath $script:LogPath
    Initialize-AppView -Apps $apps
    $script:Feed = $null
    [void](Get-Feed -Progress $Progress)
    $known = @((AsArray $script:Apps) | Where-Object { "$($_.CreatedBy)" }).Count
    & $report "Done - $((AsArray $script:Apps).Count) apps, $((AsArray $changes).Count) change(s) since last sync, creator known for $known." 100
    return $true
}
function Initialize-AppView {
    param([object[]]$Apps)
    $script:Ledger = Get-ChangeLog -LogPath $script:LogPath
    $script:Apps   = Add-AppClassification -Apps $Apps -Cfg $cfg
    foreach ($a in (AsArray $script:Apps)) {      # newest audit event = "last change" for the grid; Intune's lastModified as fallback
        $ev = (AsArray $a.AuditEvents) | Select-Object -First 1
        $when = $(if ($ev) { "$($ev.When)" } else { "$($a.LastModifiedDateTime)" })
        $a | Add-Member -NotePropertyName LastChangeWhen -NotePropertyValue $when -Force
        $a | Add-Member -NotePropertyName LastChange -NotePropertyValue $(try { ([datetime]$when).ToString('yyyy-MM-dd') } catch { '' }) -Force
        if ($ev) { $a | Add-Member -NotePropertyName LastChangedByName -NotePropertyValue (Format-Who "$($ev.Who)" "$($ev.WhoId)") -Force }
    }
}
function Build-GroupMap {
    param($Cache, [object[]]$Apps)
    $map = @{}
    if ($Cache -and $Cache.Groups) { foreach ($k in $Cache.Groups.Keys) { if ("$($Cache.Groups[$k])") { $map[$k] = "$($Cache.Groups[$k])" } } }
    foreach ($a in (AsArray $Apps)) { foreach ($asg in (AsArray $a.Assignments)) { $gid = "$($asg.GroupId)"; $name = "$($asg.Target)" -replace '^EXCLUDE: ', ''; if ($gid -and $name -and $name -ne $gid) { $map[$gid] = $name } } }
    return $map
}
function Get-Feed { param([scriptblock]$Progress) if ($null -eq $script:Feed) { $script:Feed = Get-ActivityFeed -Apps $script:Apps -ChangeLog $script:Ledger -GroupMap $script:GroupMap -CachePath $script:FeedPath -Progress $Progress; Build-FeedIndex }; return $script:Feed }
# One pass over the feed, once per load: lower-case search text, day label, kind group and people counts per entry.
# The Activity page then filters 12k+ entries with plain string compares instead of re-deriving all of this per keystroke.
function Build-FeedIndex {
    $f = AsArray $script:Feed; $n = $f.Count
    $hay = New-Object string[] $n; $day = New-Object string[] $n; $grp = New-Object string[] $n; $when = New-Object string[] $n; $who = New-Object string[] $n; $minor = New-Object bool[] $n
    $dayCache = @{}; $people = @{}
    for ($i = 0; $i -lt $n; $i++) {
        $e = $f[$i]
        $hay[$i] = "$($e.App) $($e.Title) $($e.Lines) $($e.WhoText) $($e.Who)".ToLowerInvariant()
        $k = "$($e.Kind)"; $grp[$i] = $(if ($k -eq 'lifecycle' -or $k -eq 'assign' -or $k -eq 'version' -or $k -eq 'content' -or $k -eq 'create' -or $k -eq 'relation') { $k } else { 'edit' }); $minor[$i] = ($k -eq 'minor')
        $w = "$($e.When)"; $when[$i] = $w; $dk = $(if ($w.Length -ge 10) { $w.Substring(0, 10) } else { $w })
        if (-not $dayCache.ContainsKey($dk)) { $dayCache[$dk] = Get-DayLabel $w }
        $day[$i] = $dayCache[$dk]
        $who[$i] = "$($e.WhoText)"
        if ("$($e.Who)") { $people[$who[$i]] = [int]$people[$who[$i]] + 1 }
    }
    $script:FeedHay = $hay; $script:FeedDay = $day; $script:FeedGroup = $grp; $script:FeedWhen = $when; $script:FeedWho = $who; $script:FeedMinor = $minor; $script:FeedPeople = $people
}
function Get-AppHistory { param($App) return ,@((AsArray (Get-Feed)) | Where-Object { $_.AppId -eq $App.Id }) }

# --- Excel export -----------------------------------------------------------------------------------
$script:AppCols = @('DisplayName','Kind','Lifecycle','NoteStatus','ManagedText','CreatedVia','DisplayVersion','Created','CreatedByName','CreatedBy','CreatedById','Modified','LastChange','LastChangedByName','Publisher','Owner',
                    'AssignmentCount','AssignmentSummary','PilotDate','RolloutDate','NotesText','AgeDays','IdleDays','Flags','InstallCommandLine','UninstallCommandLine','SetupFilePath','RunAsAccount','MinimumOS','SizeMB','ContentVersion','ScopeTags','Id')
$script:HistCols = @('App','When','Who','Account','Action','Change','Kind','Source')
function Format-When { param([string]$When) if (-not "$When".Trim()) { return '' }; try { return ([datetime]::Parse("$When")).ToString('dd MMM yyyy  HH:mm') } catch {}; return ("$When" -replace '(?<=\d)[Tt](?=\d)', ' ' -replace '(?<=\d:\d\d)\.\d+Z?$', '') }
function Format-Date { param([string]$When) if (-not "$When".Trim()) { return '' }; try { return ([datetime]::Parse("$When")).ToString('dd MMM yyyy') } catch { return "$When" } }
function ConvertTo-HistoryRows { param([object[]]$Entries) foreach ($h in (AsArray $Entries)) { $lines = @($h.Lines); if ($lines.Count -eq 0) { $lines = @('') }; foreach ($l in $lines) { [pscustomobject]@{ App = $h.App; When = (Format-When $h.When); Who = $h.WhoText; Account = $h.Who; Action = $h.Title; Change = $l; Kind = $script:ChangeKinds[(Get-ChangeGroup $h.Kind)]; Source = $h.Source } } } }
function ConvertTo-AppRows { param([object[]]$Rows) foreach ($a in (AsArray $Rows)) { $o = [ordered]@{}; foreach ($c in $script:AppCols) { $v = $a.$c; if ($v -is [array]) { $v = ((AsArray $v) | ForEach-Object { "$_" }) -join '; ' }; $o[$c] = $v }; [pscustomobject]$o } }
function Export-ToExcel {
    param([object[]]$Rows, [string]$Path)
    $ids = @{}; foreach ($a in (AsArray $Rows)) { $ids[$a.Id] = 1 }
    $hist = @((AsArray (Get-Feed)) | Where-Object { $ids.ContainsKey($_.AppId) })
    return (New-XlsxWorkbook -Path $Path -Sheets @(
        @{ Name = 'Apps';           Rows = @(ConvertTo-AppRows $Rows);     Columns = $script:AppCols }
        @{ Name = 'Change history'; Rows = @(ConvertTo-HistoryRows $hist); Columns = $script:HistCols } ))
}
function Export-ActivityToExcel { param([object[]]$Entries, [string]$Path) return (New-XlsxWorkbook -Path $Path -Sheets @( @{ Name = 'Activity'; Rows = @(ConvertTo-HistoryRows $Entries); Columns = $script:HistCols } )) }
function Export-AppReport {
    param($App, [string]$Path)
    $settings = @(foreach ($c in $script:AppCols) { $v = $App.$c; if ($v -is [array]) { $v = ((AsArray $v) | ForEach-Object { "$_" }) -join '; ' }; [pscustomobject]@{ Setting = $c; Value = "$v" } })
    $settings += [pscustomobject]@{ Setting = 'DetectionRules';   Value = ((AsArray $App.DetectionRules) -join ' | ') }
    $settings += [pscustomobject]@{ Setting = 'RequirementRules'; Value = ((AsArray $App.RequirementRules) -join ' | ') }
    $asg = @(foreach ($s in (AsArray $App.Assignments)) { [pscustomobject]@{ Intent = $s.Intent; Target = $s.Target; Filter = $s.FilterType; GroupId = $s.GroupId } })
    return (New-XlsxWorkbook -Path $Path -Sheets @(
        @{ Name = 'Settings';    Rows = $settings; Columns = @('Setting','Value') }
        @{ Name = 'Assignments'; Rows = $asg;      Columns = @('Intent','Target','Filter','GroupId') }
        @{ Name = 'History';     Rows = @(ConvertTo-HistoryRows (Get-AppHistory $App)); Columns = $script:HistCols } ))
}

if ($NoGui) {
    $script:LogSink = { param($m, $l) Write-Host $m -ForegroundColor $(switch ($l) { 'Error' { 'Red' } 'Warning' { 'Yellow' } 'Success' { 'Green' } default { 'Gray' } }) }
    if (Invoke-AppSync -FullSync:$Full -Progress { param($t, $p) Write-Host "[$p%] $t" -ForegroundColor DarkCyan }) {
        $x = Join-Path $script:DataDir ('IntuneAppMonitor-Apps-{0}.xlsx' -f (Get-Date -Format 'yyyyMMdd-HHmm'))
        Export-ToExcel -Rows $script:Apps -Path $x | Out-Null
        Write-Host "Excel: $x" -ForegroundColor Green
    }
    return
}

# =====================================================================================================
# GUI
# =====================================================================================================
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Intune App Monitor" Width="1500" Height="900" MinWidth="1100" MinHeight="640"
        Background="$($C.Bg)" Foreground="$($C.Ink)" FontFamily="Segoe UI" FontSize="13" TextOptions.TextFormattingMode="Display" UseLayoutRounding="True">
  <Window.Resources>
    <SolidColorBrush x:Key="Bg" Color="$($C.Bg)"/><SolidColorBrush x:Key="Panel" Color="$($C.Panel)"/><SolidColorBrush x:Key="Panel2" Color="$($C.Panel2)"/>
    <SolidColorBrush x:Key="Line" Color="$($C.Line)"/><SolidColorBrush x:Key="Line2" Color="$($C.Line2)"/>
    <SolidColorBrush x:Key="Ink" Color="$($C.Ink)"/><SolidColorBrush x:Key="Ink2" Color="$($C.Ink2)"/><SolidColorBrush x:Key="Ink3" Color="$($C.Ink3)"/>
    <SolidColorBrush x:Key="Accent" Color="$($C.Accent)"/><SolidColorBrush x:Key="AccentSoft" Color="$($C.AccentSoft)"/>
    <Style TargetType="ToolTip"><Setter Property="Background" Value="{StaticResource Panel2}"/><Setter Property="Foreground" Value="{StaticResource Ink}"/><Setter Property="BorderBrush" Value="#FF34404E"/><Setter Property="Padding" Value="8,5"/></Style>
    <Style TargetType="Button">
      <Setter Property="Padding" Value="13,7"/><Setter Property="Foreground" Value="{StaticResource Ink2}"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" CornerRadius="7" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="1" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#FF34404E"/><Setter Property="Foreground" Value="{StaticResource Ink}"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Foreground" Value="$($C.AccentInk)"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" CornerRadius="7" Background="{StaticResource Accent}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#FF3D7CEC"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Link" TargetType="Button"><Setter Property="Foreground" Value="{StaticResource Accent}"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Padding" Value="0"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><ContentPresenter/></ControlTemplate></Setter.Value></Setter></Style>
    <Style x:Key="Ghost" TargetType="Button"><Setter Property="Foreground" Value="{StaticResource Ink3}"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Padding" Value="2"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="Transparent" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border></ControlTemplate></Setter.Value></Setter></Style>
    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource Ink2}"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="0,1"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
        <Border x:Name="b" CornerRadius="8" Padding="12,9" Background="Transparent"><ContentPresenter VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource Panel}"/></Trigger>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource AccentSoft}"/><Setter Property="Foreground" Value="{StaticResource Ink}"/><Setter Property="FontWeight" Value="SemiBold"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="TabBtn" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource Ink2}"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
        <Border x:Name="b" Padding="14,9" BorderThickness="0,0,0,2" BorderBrush="Transparent" Margin="0,0,0,-1"><ContentPresenter/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{StaticResource Accent}"/><Setter Property="Foreground" Value="{StaticResource Ink}"/><Setter Property="FontWeight" Value="SemiBold"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{StaticResource Panel}"/><Setter Property="Foreground" Value="{StaticResource Ink}"/><Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="CaretBrush" Value="{StaticResource Ink}"/><Setter Property="Padding" Value="9,6"/><Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox">
        <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="7"><ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="DatePickerTextBox"><Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="DatePickerTextBox"><Border Background="Transparent"><ScrollViewer x:Name="PART_ContentHost" Margin="6,0" VerticalAlignment="Center"/></Border></ControlTemplate></Setter.Value></Setter></Style>
    <Style TargetType="DatePicker"><Setter Property="Background" Value="{StaticResource Panel}"/><Setter Property="BorderBrush" Value="{StaticResource Line}"/><Setter Property="Foreground" Value="{StaticResource Ink}"/><Setter Property="Width" Value="128"/></Style>
    <Style TargetType="CheckBox"><Setter Property="Foreground" Value="{StaticResource Ink}"/></Style>
    <Style TargetType="ComboBoxItem"><Setter Property="Foreground" Value="{StaticResource Ink2}"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem">
        <Border x:Name="b" Padding="10,6" Background="Transparent"><ContentPresenter/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource Panel2}"/><Setter Property="Foreground" Value="{StaticResource Ink}"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource AccentSoft}"/><Setter Property="Foreground" Value="{StaticResource Ink}"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter></Style>
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="{StaticResource Ink2}"/><Setter Property="MinWidth" Value="130"/><Setter Property="Padding" Value="10,6,26,6"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox">
        <Grid>
          <ToggleButton x:Name="tb" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}" Focusable="False" ClickMode="Press">
            <ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border x:Name="b" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="1" CornerRadius="7"><Path Data="M0,0 L4,4 L8,0" Stroke="{StaticResource Ink3}" StrokeThickness="1.5" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,11,0"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#FF34404E"/></Trigger></ControlTemplate.Triggers></ControlTemplate></ToggleButton.Template>
          </ToggleButton>
          <ContentPresenter Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" Margin="{TemplateBinding Padding}" VerticalAlignment="Center" HorizontalAlignment="Left" IsHitTestVisible="False"/>
          <Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
            <Border Background="{StaticResource Panel}" BorderBrush="#FF34404E" BorderThickness="1" CornerRadius="7" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="340" Margin="0,4,0,0"><ScrollViewer><StackPanel IsItemsHost="True"/></ScrollViewer></Border>
          </Popup>
        </Grid></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="ScrollBar"><Setter Property="Background" Value="Transparent"/><Setter Property="Width" Value="10"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">
        <Grid Background="Transparent"><Track x:Name="PART_Track" IsDirectionReversed="True">
          <Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/></Track.DecreaseRepeatButton>
          <Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/></Track.IncreaseRepeatButton>
          <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border Background="#FF34404E" CornerRadius="5" Margin="2"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
        </Track></Grid></ControlTemplate></Setter.Value></Setter>
      <Style.Triggers><Trigger Property="Orientation" Value="Horizontal"><Setter Property="Width" Value="Auto"/><Setter Property="Height" Value="10"/>
        <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">
          <Grid Background="Transparent"><Track x:Name="PART_Track" IsDirectionReversed="False">
            <Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageLeftCommand" Opacity="0" Focusable="False"/></Track.DecreaseRepeatButton>
            <Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageRightCommand" Opacity="0" Focusable="False"/></Track.IncreaseRepeatButton>
            <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border Background="#FF34404E" CornerRadius="5" Margin="2"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
          </Track></Grid></ControlTemplate></Setter.Value></Setter></Trigger></Style.Triggers>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="{StaticResource Panel2}"/><Setter Property="Foreground" Value="{StaticResource Ink3}"/><Setter Property="FontSize" Value="11.5"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="8,9"/><Setter Property="BorderBrush" Value="{StaticResource Line}"/><Setter Property="BorderThickness" Value="0,0,1,1"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="DataGridColumnHeader">
        <Grid><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/></Border>
          <Thumb x:Name="PART_RightHeaderGripper" HorizontalAlignment="Right" Width="6" Cursor="SizeWE"><Thumb.Template><ControlTemplate TargetType="Thumb"><Border Background="Transparent"/></ControlTemplate></Thumb.Template></Thumb></Grid>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="DataGridRow"><Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="{StaticResource Ink}"/><Setter Property="Cursor" Value="Hand"/>
      <Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{StaticResource Panel2}"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="{StaticResource AccentSoft}"/></Trigger></Style.Triggers></Style>
    <Style TargetType="DataGridCell"><Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="8,0"/><Setter Property="Foreground" Value="{StaticResource Ink}"/><Setter Property="Background" Value="Transparent"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="DataGridCell"><Border Padding="{TemplateBinding Padding}" Background="Transparent"><ContentPresenter VerticalAlignment="Center"/></Border></ControlTemplate></Setter.Value></Setter></Style>
    <Style TargetType="DataGrid">
      <Setter Property="Background" Value="{StaticResource Panel}"/><Setter Property="Foreground" Value="{StaticResource Ink}"/><Setter Property="BorderThickness" Value="0"/><Setter Property="RowBackground" Value="Transparent"/>
      <Setter Property="GridLinesVisibility" Value="Horizontal"/><Setter Property="HorizontalGridLinesBrush" Value="{StaticResource Line2}"/><Setter Property="HeadersVisibility" Value="Column"/><Setter Property="RowHeaderWidth" Value="0"/>
      <Setter Property="AutoGenerateColumns" Value="False"/><Setter Property="IsReadOnly" Value="True"/><Setter Property="SelectionMode" Value="Single"/><Setter Property="RowHeight" Value="34"/><Setter Property="EnableRowVirtualization" Value="True"/>
      <Setter Property="ScrollViewer.CanContentScroll" Value="True"/><Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Auto"/><Setter Property="CanUserResizeRows" Value="False"/>
    </Style>
    <Style x:Key="Card" TargetType="Border"><Setter Property="Background" Value="{StaticResource Panel}"/><Setter Property="BorderBrush" Value="{StaticResource Line}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="10"/><Setter Property="Padding" Value="16,14"/></Style>
    <Style x:Key="PopCard" TargetType="Border"><Setter Property="Background" Value="{StaticResource Panel}"/><Setter Property="BorderBrush" Value="#FF34404E"/><Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="8"/><Setter Property="Padding" Value="10"/></Style>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="188"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Border Grid.Column="0" Background="$($C.Rail)" BorderBrush="{StaticResource Line}" BorderThickness="0,0,1,0">
      <DockPanel Margin="10,18,10,14">
        <StackPanel DockPanel.Dock="Top">
          <TextBlock Text="Intune App Monitor" FontWeight="Bold" FontSize="14" Margin="10,0,10,2"/>
          <TextBlock x:Name="BrandSub" Foreground="{StaticResource Ink3}" FontSize="11.5" Margin="10,0,10,16" TextWrapping="Wrap"/>
          <RadioButton x:Name="NavOverview" Style="{StaticResource Nav}" GroupName="nav" Content="Overview" IsChecked="True"/>
          <RadioButton x:Name="NavApps"     Style="{StaticResource Nav}" GroupName="nav" Content="Apps"/>
          <RadioButton x:Name="NavActivity" Style="{StaticResource Nav}" GroupName="nav" Content="Activity"/>
          <RadioButton x:Name="NavPeople"   Style="{StaticResource Nav}" GroupName="nav" Content="People"/>
          <RadioButton x:Name="NavInsights" Style="{StaticResource Nav}" GroupName="nav" Content="Insights"/>
        </StackPanel>
        <StackPanel DockPanel.Dock="Bottom" Margin="10,0,4,0">
          <Border BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0" Margin="0,0,0,10"/>
          <TextBlock x:Name="Foot" Foreground="{StaticResource Ink3}" FontSize="11.5" TextWrapping="Wrap" LineHeight="17"/>
          <Button x:Name="BtnFolder" Content="Data folder" Margin="0,12,0,0" HorizontalAlignment="Left" Padding="10,5"/>
        </StackPanel>
        <Grid/>
      </DockPanel>
    </Border>

    <Grid Grid.Column="1">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <Border Grid.Row="0" BorderBrush="{StaticResource Line}" BorderThickness="0,0,0,1" Padding="20,10">
        <DockPanel>
          <StackPanel DockPanel.Dock="Left" VerticalAlignment="Center">
            <TextBlock x:Name="Crumb" Foreground="{StaticResource Ink3}" FontSize="12" Visibility="Collapsed"/>
            <TextBlock x:Name="Title" Text="Overview" FontSize="17" FontWeight="SemiBold"/>
          </StackPanel>
          <Button x:Name="BtnExport" DockPanel.Dock="Right" Content="Export" Margin="8,0,0,0"/>
          <Button x:Name="BtnCancel" DockPanel.Dock="Right" Content="Cancel" Margin="8,0,0,0" IsEnabled="False"/>
          <Button x:Name="BtnSync"   DockPanel.Dock="Right" Content="Sync" Style="{StaticResource Primary}" Margin="14,0,0,0"/>
          <Grid DockPanel.Dock="Right" Width="280">
            <TextBox x:Name="GlobalSearch" ToolTip="Find an app by name, publisher, version or person"/>
            <TextBlock Text="Find an app" Foreground="{StaticResource Ink3}" Margin="11,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False">
              <TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed"/><Style.Triggers><DataTrigger Binding="{Binding Text, ElementName=GlobalSearch}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers></Style></TextBlock.Style>
            </TextBlock>
          </Grid>
          <Grid/>
        </DockPanel>
      </Border>

      <Grid Grid.Row="1">
        <ScrollViewer x:Name="PgOverview" VerticalScrollBarVisibility="Auto" Padding="20,18,20,30"><StackPanel x:Name="OverviewPanel"/></ScrollViewer>
        <Grid x:Name="PgApps" Visibility="Collapsed" Margin="20,18,20,12">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <UniformGrid x:Name="AppTiles" Rows="1" Margin="0,0,0,14"/>
          <DockPanel Grid.Row="1" Margin="0,0,0,12" LastChildFill="False">
            <Grid DockPanel.Dock="Left" Width="280">
              <TextBox x:Name="AppsSearch" ToolTip="Filter by name, publisher, version, person, note"/>
              <TextBlock Text="Filter this list" Foreground="{StaticResource Ink3}" Margin="11,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False">
                <TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed"/><Style.Triggers><DataTrigger Binding="{Binding Text, ElementName=AppsSearch}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger></Style.Triggers></Style></TextBlock.Style>
              </TextBlock>
            </Grid>
            <WrapPanel x:Name="FilterChips" DockPanel.Dock="Left" Margin="10,0,0,0" VerticalAlignment="Center"/>
            <Button x:Name="BtnCols" DockPanel.Dock="Right" Content="Columns" Padding="10,5" Margin="10,0,0,0"/>
            <TextBlock x:Name="AppsCount" DockPanel.Dock="Right" Foreground="{StaticResource Ink3}" FontSize="12.5" VerticalAlignment="Center"/>
          </DockPanel>
          <Border Grid.Row="2" Style="{StaticResource Card}" Padding="0"><DataGrid x:Name="Grid1" CanUserSortColumns="True"/></Border>
          <TextBlock x:Name="AppsFoot" Grid.Row="3" Foreground="{StaticResource Ink3}" FontSize="12" Margin="4,8,0,0" TextWrapping="Wrap"/>
        </Grid>
        <ScrollViewer x:Name="PgApp" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" Padding="20,18,20,30"><StackPanel x:Name="AppPanel"/></ScrollViewer>
        <Grid x:Name="PgActivity" Visibility="Collapsed" Margin="20,18,20,12">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <WrapPanel x:Name="ActBar" Margin="0,0,0,12"/>
          <Border Grid.Row="1" Style="{StaticResource Card}" Padding="14,6"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="ActList"/></ScrollViewer></Border>
        </Grid>
        <Grid x:Name="PgPeople" Visibility="Collapsed" Margin="20,18,20,12">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <TextBlock x:Name="PeopleHint" Foreground="{StaticResource Ink3}" FontSize="12.5" Margin="0,0,0,12" HorizontalAlignment="Right"/>
          <Border Grid.Row="1" Style="{StaticResource Card}" Padding="0"><DataGrid x:Name="Grid3"/></Border>
          <TextBlock Grid.Row="2" Foreground="{StaticResource Ink3}" FontSize="12" Margin="4,8,0,0" TextWrapping="Wrap" Text="Names come from Data\people.json. Click a person to see their activity."/>
        </Grid>
        <ScrollViewer x:Name="PgInsights" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" Padding="20,18,20,30"><StackPanel x:Name="InsightsPanel"/></ScrollViewer>
      </Grid>

      <StackPanel Grid.Row="2" Margin="20,0,20,10">
        <ProgressBar x:Name="Bar" Height="3" Minimum="0" Maximum="100" Foreground="{StaticResource Accent}" Background="{StaticResource Line}" BorderThickness="0"/>
        <TextBlock x:Name="StatusText" Margin="0,6,0,0" Foreground="{StaticResource Ink3}" FontSize="12" Text="Ready." TextWrapping="Wrap"/>
      </StackPanel>
    </Grid>

    <Popup x:Name="Pop" StaysOpen="False" AllowsTransparency="True" Placement="Bottom">
      <Border Style="{StaticResource PopCard}">
        <DockPanel MinWidth="240" MaxWidth="380">
          <TextBlock x:Name="PopTitle" DockPanel.Dock="Top" FontWeight="SemiBold" Margin="2,0,2,7"/>
          <TextBox   x:Name="PopSearch" DockPanel.Dock="Top" Margin="0,0,0,7" Padding="7,4"/>
          <DockPanel DockPanel.Dock="Bottom" LastChildFill="False" Margin="0,8,0,0">
            <Button x:Name="BtnPopOk"   DockPanel.Dock="Right" Content="Apply" Padding="10,4" Style="{StaticResource Primary}"/>
            <Button x:Name="BtnPopNone" DockPanel.Dock="Left"  Content="None"  Padding="10,4" Margin="0,0,5,0"/>
            <Button x:Name="BtnPopAll"  DockPanel.Dock="Left"  Content="All"   Padding="10,4" Margin="0,0,5,0"/>
          </DockPanel>
          <ScrollViewer MaxHeight="290" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="PopList"/></ScrollViewer>
        </DockPanel>
      </Border>
    </Popup>
    <Popup x:Name="ColPop" StaysOpen="False" AllowsTransparency="True" Placement="Bottom">
      <Border Style="{StaticResource PopCard}">
        <StackPanel MinWidth="220">
          <TextBlock Text="Columns" FontWeight="SemiBold" Margin="2,0,2,4"/>
          <TextBlock x:Name="ColHint" Foreground="{StaticResource Ink3}" FontSize="11.5" TextWrapping="Wrap" MaxWidth="240" Margin="2,0,2,8"/>
          <StackPanel x:Name="ColList"/>
          <Button x:Name="BtnColsReset" Content="Back to automatic" Padding="10,4" Margin="0,8,0,0" HorizontalAlignment="Left"/>
        </StackPanel>
      </Border>
    </Popup>
  </Grid>
</Window>
"@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
foreach ($n in 'BrandSub','NavOverview','NavApps','NavActivity','NavPeople','NavInsights','Foot','BtnFolder','Crumb','Title','BtnExport','BtnCancel','BtnSync','GlobalSearch',
                'PgOverview','OverviewPanel','PgApps','AppTiles','AppsSearch','FilterChips','BtnCols','AppsCount','Grid1','AppsFoot','PgApp','AppPanel','PgActivity','ActBar','ActList',
                'PgPeople','Grid3','PeopleHint','PgInsights','InsightsPanel','Bar','StatusText','Pop','PopTitle','PopSearch','PopList','BtnPopOk','BtnPopAll','BtnPopNone','ColPop','ColHint','ColList','BtnColsReset') {
    Set-Variable -Name $n -Value $win.FindName($n) -Scope Script
}
# Fit the work area. On a small screen (this team runs 1280 x 752 logical) the window simply opens maximised.
$wa = [Windows.SystemParameters]::WorkArea
$win.MaxWidth = $wa.Width; $win.MaxHeight = $wa.Height
if ($win.Width  -gt ($wa.Width  - 20)) { $win.Width  = $wa.Width  - 20 }
if ($win.Height -gt ($wa.Height - 20)) { $win.Height = $wa.Height - 20 }
$win.Left = $wa.Left + [Math]::Max(0, ($wa.Width - $win.Width) / 2)
$win.Top  = $wa.Top  + [Math]::Max(0, ($wa.Height - $win.Height) / 2)
$script:StartMaximized = ($wa.Width -lt 1500)

function Set-Status {
    param([string]$Text, [int]$Percent = -1, [switch]$Pump)
    $StatusText.Text = $Text
    if ($Percent -ge 0) { $Bar.Value = $Percent }
    if ($Pump) { $frame = New-Object Windows.Threading.DispatcherFrame; [Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, [action]{ $frame.Continue = $false }) | Out-Null; [Windows.Threading.Dispatcher]::PushFrame($frame) }
}
$script:LogSink = { param($m, $l) if ($l -eq 'Error' -or $l -eq 'Warning') { $StatusText.Text = $m } }

# --- WPF builders ------------------------------------------------------------------------------------
$script:Conv = New-Object Windows.Media.BrushConverter
$script:BrushCache = @{}          # hex -> frozen brush; thousands of history rows share a handful of colours
function Brush { param([string]$Hex) $b = $script:BrushCache[$Hex]; if (-not $b) { $b = $script:Conv.ConvertFromString($Hex); $b.Freeze(); $script:BrushCache[$Hex] = $b }; return $b }
$script:MonoFont  = New-Object Windows.Media.FontFamily('Consolas')
$script:LinkStyle = $win.FindResource('Link')
$script:Weights   = @{ Normal = [Windows.FontWeights]::Normal; SemiBold = [Windows.FontWeights]::SemiBold; Bold = [Windows.FontWeights]::Bold; Medium = [Windows.FontWeights]::Medium }
function Th { param([double]$l, [double]$t, [double]$r, [double]$b) return (New-Object Windows.Thickness($l, $t, $r, $b)) }
function New-Text {
    param([string]$Text, [double]$Size = 13, [string]$Colour = $script:C.Ink, [string]$Weight = 'Normal', [bool]$Wrap = $false, $Margin, [switch]$Mono)
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = "$Text"; $t.FontSize = $Size; $t.Foreground = (Brush $Colour); $t.FontWeight = $script:Weights[$Weight]; $t.VerticalAlignment = 'Center'
    if ($Wrap) { $t.TextWrapping = 'Wrap' }
    if ($Mono) { $t.FontFamily = $script:MonoFont }
    if ($Margin) { $t.Margin = $Margin }
    return $t
}
function New-Chip {
    param([string]$Text, [string]$Fg, [string]$Bg, [switch]$Mono)
    $b = New-Object Windows.Controls.Border
    $b.Background = (Brush $Bg); $b.CornerRadius = New-Object Windows.CornerRadius(5); $b.Padding = (Th 8 2 8 3); $b.Margin = (Th 0 0 6 0); $b.VerticalAlignment = 'Center'
    $b.Child = (New-Text -Text $Text -Size 11.5 -Colour $Fg -Weight 'SemiBold' -Mono:$Mono)
    return $b
}
function New-LifeChip { param([string]$Stage) $s = "$Stage"; if (-not $script:LifeColour.ContainsKey($s)) { $s = 'Not recorded' }; return (New-Chip -Text "$Stage" -Fg $script:LifeColour[$s] -Bg $script:LifeBg[$s]) }
function New-KindChip { param([string]$Kind) $k = "$Kind"; if (-not $script:KindColour.ContainsKey($k)) { $k = 'Standard' }; return (New-Chip -Text "$Kind" -Fg $script:KindColour[$k] -Bg $script:KindBg[$k]) }
function New-Card {
    param([string]$Title, [string]$Right, [switch]$NoTitle)
    $b = New-Object Windows.Controls.Border; $b.Style = $win.FindResource('Card'); $b.Margin = (Th 0 0 12 12)
    $sp = New-Object Windows.Controls.StackPanel
    if (-not $NoTitle) {
        $dp = New-Object Windows.Controls.DockPanel; $dp.Margin = (Th 0 0 0 10)
        if ($Right) { $r = New-Text -Text $Right -Size 12 -Colour $script:C.Ink2; [Windows.Controls.DockPanel]::SetDock($r, 'Right'); [void]$dp.Children.Add($r) }
        [void]$dp.Children.Add((New-Text -Text $Title.ToUpper() -Size 11.5 -Colour $script:C.Ink3 -Weight 'SemiBold'))
        [void]$sp.Children.Add($dp)
    }
    $b.Child = $sp
    return @{ Border = $b; Body = $sp }
}
function New-KvGrid {
    param([object[]]$Pairs, [int]$KeyWidth = 140)
    $g = New-Object Windows.Controls.Grid
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = New-Object Windows.GridLength($KeyWidth); $g.ColumnDefinitions.Add($c1)
    $g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
    $r = 0
    foreach ($p in $Pairs) {
        $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = [Windows.GridLength]::Auto; $g.RowDefinitions.Add($rd)
        $k = New-Text -Text $p[0] -Size 12.5 -Colour $script:C.Ink3 -Margin (Th 0 0 12 6); $k.VerticalAlignment = 'Top'
        $val = "$($p[1])"; $mono = ($p.Count -gt 2 -and [bool]$p[2])
        if ($val.Trim()) { $v = New-Text -Text $val -Size 12.5 -Wrap $true -Margin (Th 0 0 0 6) -Mono:$mono } else { $v = New-Text -Text 'not set' -Size 12.5 -Colour $script:C.Ink3 -Margin (Th 0 0 0 6); $v.FontStyle = 'Italic' }
        $v.VerticalAlignment = 'Top'
        [Windows.Controls.Grid]::SetRow($k, $r); [Windows.Controls.Grid]::SetRow($v, $r); [Windows.Controls.Grid]::SetColumn($v, 1)
        [void]$g.Children.Add($k); [void]$g.Children.Add($v); $r++
    }
    return $g
}
function New-Pill {
    param([string]$Text, [string]$Kind = 'plain', [switch]$Strike)   # plain | old | new; Strike = old value of an old -> new pair
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = New-Object Windows.CornerRadius(5); $b.Padding = (Th 7 1 7 1); $b.Margin = (Th 0 2 6 2); $b.MaxWidth = 520; $b.VerticalAlignment = 'Center'
    switch ($Kind) { 'old' { $b.Background = (Brush $script:C.OldBg); $fg = $script:C.OldInk } 'new' { $b.Background = (Brush $script:C.NewBg); $fg = $script:C.NewInk } default { $b.Background = (Brush $script:C.Panel2); $fg = $script:C.Ink2 } }
    $t = New-Text -Text $Text -Size 11.5 -Colour $fg -Mono; $t.TextTrimming = 'CharacterEllipsis'; $t.ToolTip = $Text
    if ($Strike) { $t.TextDecorations = [Windows.TextDecorations]::Strikethrough }
    $b.Child = $t
    return $b
}
function New-Arrow { return (New-Text -Text ([string][char]0x2192) -Size 12 -Colour $script:C.Ink3 -Margin (Th 0 0 6 0)) }
function New-Key { param([string]$Text) return (New-Text -Text $Text -Size 12 -Colour $script:C.Ink3 -Margin (Th 0 0 7 0)) }
# One translated change line -> key + old/new pills. Mirrors the sentence shapes produced by lib\Intune.ps1.
function New-ChangeLine {
    param([string]$Line, [bool]$Removed)
    $w = New-Object Windows.Controls.WrapPanel; $w.Margin = (Th 0 0 14 0); $w.VerticalAlignment = 'Center'
    $l = "$Line"
    if ($l -match '^(?<a>Added|Removed):\s*(?<r>.+)$') { [void]$w.Children.Add((New-Key $Matches.a)); [void]$w.Children.Add((New-Pill $Matches.r $(if ($Matches.a -eq 'Added') { 'new' } else { 'old' }))); return $w }
    if ($l -match '^(?<f>(Detection|Requirement) rule \d+) (?<v>added|removed): (?<n>.+)$') { [void]$w.Children.Add((New-Key $Matches.f)); [void]$w.Children.Add((New-Pill $Matches.n $(if ($Matches.v -eq 'added') { 'new' } else { 'old' }))); return $w }
    if ($l -match '^(?<k>Supersedence|Dependency) (?<v>added|removed) - (?<t>.+)$') { [void]$w.Children.Add((New-Key $Matches.k)); [void]$w.Children.Add((New-Pill $Matches.t $(if ($Matches.v -eq 'added') { 'new' } else { 'old' }))); return $w }
    if ($l -match '^(?<f>[^:]{1,40}):\s*(?<o>.*?)\s+->\s+(?<n>.*)$') {
        $n = $Matches.n -replace '\s+\(new package content\)\s*$', ''
        [void]$w.Children.Add((New-Key $Matches.f))
        if ($Matches.o -and $Matches.o -notin '(empty)','(none)') { [void]$w.Children.Add((New-Pill $Matches.o 'old' -Strike)); [void]$w.Children.Add((New-Arrow)) }
        [void]$w.Children.Add((New-Pill $n 'new')); return $w
    }
    if ($l -match '^(?<i>\w+)\s+->\s+(?<t>.+)$') { [void]$w.Children.Add((New-Pill $Matches.i 'plain')); [void]$w.Children.Add((New-Arrow)); [void]$w.Children.Add((New-Pill $Matches.t $(if ($Removed) { 'old' } else { 'new' }))); return $w }
    [void]$w.Children.Add((New-Text -Text $l -Size 12.5 -Colour $script:C.Ink2 -Wrap $true))
    return $w
}
function Find-App { param([string]$Id) return ((AsArray $script:Apps) | Where-Object { $_.Id -eq $Id } | Select-Object -First 1) }
$script:OnAppLink = { param($s, $e) $app = Find-App "$($s.Tag)"; if ($app) { Show-App $app } }
# One history row: time | dot | app · action + change lines | by whom
function New-HistoryRow {
    param($Entry, [bool]$InApp)
    $g = New-Object Windows.Controls.Grid
    foreach ($w in @(46, 14, 0, 0)) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $(if ($w) { New-Object Windows.GridLength($w) } else { [Windows.GridLength]::Auto }); $g.ColumnDefinitions.Add($cd) }
    $g.ColumnDefinitions[2].Width = New-Object Windows.GridLength(1, 'Star')
    $bd = New-Object Windows.Controls.Border; $bd.Padding = (Th 6 8 6 8); $bd.BorderBrush = (Brush $script:C.Line2); $bd.BorderThickness = (Th 0 0 0 1); $bd.Child = $g
    $t = New-Text -Text $(try { ([datetime]::Parse("$($Entry.When)")).ToString('HH:mm') } catch { '' }) -Size 12 -Colour $script:C.Ink3 -Mono; $t.VerticalAlignment = 'Top'; $t.Margin = (Th 0 2 0 0)
    [void]$g.Children.Add($t)
    $dot = New-Object Windows.Controls.Border; $dot.Width = 8; $dot.Height = 8; $dot.CornerRadius = New-Object Windows.CornerRadius(4); $dot.VerticalAlignment = 'Top'; $dot.Margin = (Th 0 6 0 0); $dot.HorizontalAlignment = 'Center'
    $dot.Background = (Brush $(if ($script:ChangeColour.ContainsKey("$($Entry.Kind)")) { $script:ChangeColour["$($Entry.Kind)"] } else { $script:ChangeColour['edit'] }))
    [Windows.Controls.Grid]::SetColumn($dot, 1); [void]$g.Children.Add($dot)
    $body = New-Object Windows.Controls.StackPanel; $body.Margin = (Th 8 0 10 0)
    $head = New-Object Windows.Controls.WrapPanel
    if (-not $InApp) {
        $btn = New-Object Windows.Controls.Button; $btn.Style = $script:LinkStyle; $btn.Content = (New-Text -Text $Entry.App -Size 13 -Colour $script:C.Ink -Weight 'SemiBold'); $btn.Tag = $Entry.AppId; $btn.Margin = (Th 0 0 8 0); $btn.Add_Click($script:OnAppLink)
        [void]$head.Children.Add($btn)
    }
    [void]$head.Children.Add((New-Text -Text $(if ($InApp) { "$($Entry.Title)" } else { "$($Entry.Title)".Substring(0,1).ToLower() + "$($Entry.Title)".Substring(1) }) -Size 13 -Colour $script:C.Ink2 -Wrap $true))
    [void]$body.Children.Add($head)
    $lines = AsArray $Entry.Lines
    if ($lines.Count -gt 1) { $lines = @($lines | Where-Object { $_ -notmatch 'recorded no detail' }) }   # a detail-less bulk event grouped with detailed ones adds nothing
    if ($lines.Count) {
        $lp = New-Object Windows.Controls.WrapPanel; $lp.Margin = (Th 0 4 0 0)
        $removed = ("$($Entry.Title)" -match 'removed')
        foreach ($l in ($lines | Select-Object -First 4)) { [void]$lp.Children.Add((New-ChangeLine -Line $l -Removed $removed)) }
        if ($lines.Count -gt 4) {
            $more = New-Object Windows.Controls.Button; $more.Style = $script:LinkStyle; $more.Content = (New-Text -Text "+$($lines.Count - 4) more" -Size 12 -Colour $script:C.Accent); $more.Tag = @{ Panel = $lp; Lines = @($lines | Select-Object -Skip 4); Removed = $removed }
            $more.Add_Click({ param($s, $e) $ctx = $s.Tag; $ctx.Panel.Children.Remove($s); foreach ($l in $ctx.Lines) { [void]$ctx.Panel.Children.Add((New-ChangeLine -Line $l -Removed $ctx.Removed)) } })
            [void]$lp.Children.Add($more)
        }
        [void]$body.Children.Add($lp)
    }
    if ($Entry.Legacy) { $body.Opacity = 0.6; $body.ToolTip = 'Older audit format: Intune kept the field names but not the values.' }
    [Windows.Controls.Grid]::SetColumn($body, 2); [void]$g.Children.Add($body)
    $who = New-Object Windows.Controls.TextBlock; $who.FontSize = 12; $who.Foreground = (Brush $script:C.Ink3); $who.VerticalAlignment = 'Top'; $who.Margin = (Th 0 2 0 0); $who.MaxWidth = 190; $who.TextTrimming = 'CharacterEllipsis'
    [void]$who.Inlines.Add('by ')
    $b = New-Object Windows.Documents.Run("$($Entry.WhoText)"); $b.Foreground = (Brush $script:C.Ink2); [void]$who.Inlines.Add($b)
    if ("$($Entry.Who)") { $who.ToolTip = "$($Entry.Who)" }
    [Windows.Controls.Grid]::SetColumn($who, 3); [void]$g.Children.Add($who)
    return $bd
}
function Get-DayLabel { param([string]$When) try { $d = [datetime]::Parse("$When"); $k = ([datetime]::Today - $d.Date).Days; if ($k -eq 0) { return 'Today' }; if ($k -eq 1) { return 'Yesterday' }; return $d.ToString('ddd, dd MMM yyyy') } catch { return "$When".Substring(0, [Math]::Min(10, "$When".Length)) } }
# Day-grouped history list. State-based so the Activity page can paint in small chunks between UI messages
# (-Async): the first rows appear at once and the window stays responsive while the rest fills in.
# $Days = precomputed day labels aligned with $Entries (Activity); otherwise derived here (short app lists).
function New-FeedState {
    param($Panel, [object[]]$List, [string[]]$Days, [bool]$InApp, [int]$Take, [int]$Step)
    $n = $List.Count
    if (-not $Days -or $Days.Count -ne $n) { $Days = New-Object string[] $n; for ($i = 0; $i -lt $n; $i++) { $Days[$i] = Get-DayLabel $List[$i].When } }
    $st = @{ Panel = $Panel; List = $List; Days = $Days; InApp = $InApp; N = $n; Take = [Math]::Min($Take, $n); Step = $Step; Index = 0; LastDay = ''; Counts = @{}; Counted = 0; Gen = 0 }
    Update-FeedCounts $st
    return $st
}
# day totals for every day that is (or is about to be) on screen - walks a little past Take while the day is unchanged
function Update-FeedCounts {
    param($St)
    $lastDay = $(if ($St.Take -gt 0) { $St.Days[$St.Take - 1] } else { '' })
    for ($i = $St.Counted; $i -lt $St.N; $i++) { if ($i -ge $St.Take -and $St.Days[$i] -ne $lastDay) { break }; $St.Counts[$St.Days[$i]] = [int]$St.Counts[$St.Days[$i]] + 1; $St.Counted = $i + 1 }
}
function Add-FeedRows {
    param($St, [int]$Count)
    $end = [Math]::Min($St.Index + $Count, $St.Take)
    for ($i = $St.Index; $i -lt $end; $i++) {
        $d = $St.Days[$i]
        if ($d -ne $St.LastDay) {
            $St.LastDay = $d
            $dp = New-Object Windows.Controls.DockPanel; $dp.Margin = (Th 4 12 4 6)
            $c = [int]$St.Counts[$d]; $lbl = New-Text -Text "$c change$(if ($c -ne 1) { 's' })" -Size 11.5 -Colour $script:C.Ink3; [Windows.Controls.DockPanel]::SetDock($lbl, 'Right'); [void]$dp.Children.Add($lbl)
            [void]$dp.Children.Add((New-Text -Text $d.ToUpper() -Size 11.5 -Colour $script:C.Ink3 -Weight 'SemiBold'))
            [void]$St.Panel.Children.Add($dp)
        }
        [void]$St.Panel.Children.Add((New-HistoryRow -Entry $St.List[$i] -InApp $St.InApp))
    }
    $St.Index = $end
}
function Add-FeedMoreButton {
    param($St)
    if ($St.Take -ge $St.N) { return }
    $more = New-Object Windows.Controls.Button; $more.Content = "Show $([Math]::Min($St.Step, $St.N - $St.Take)) more of $($St.N - $St.Take)"; $more.HorizontalAlignment = 'Center'; $more.Margin = (Th 0 12 0 8); $more.Tag = $St
    $more.Add_Click({ param($s, $e) $st = $s.Tag; $st.Panel.Children.Remove($s); $st.Take = [Math]::Min($st.Take + $st.Step, $st.N); Update-FeedCounts $st; Add-FeedRows $st $st.Step; Add-FeedMoreButton $st })
    [void]$St.Panel.Children.Add($more)
}
function Add-Feed {
    param($Panel, [object[]]$Entries, [bool]$InApp, [int]$Max = 100, [string[]]$Days, [switch]$Async)
    $list = AsArray $Entries
    if ($list.Count -eq 0) { [void]$Panel.Children.Add((New-Text -Text 'Nothing recorded for this selection.' -Size 13 -Colour $script:C.Ink3 -Margin (Th 4 20 0 20))); return }
    $st = New-FeedState -Panel $Panel -List $list -Days $Days -InApp $InApp -Take $Max -Step $Max
    if (-not $Async) { Add-FeedRows $st $st.Take; Add-FeedMoreButton $st; return }
    # async: 20 rows now, the rest in background chunks; a newer render cancels the older one's chunks
    $script:ActGen = [int]$script:ActGen + 1; $st.Gen = $script:ActGen; $script:ActRender = $st
    Add-FeedRows $st 20
    if ($st.Index -lt $st.Take) { [void]$win.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, [action]{ Add-FeedChunk }) } else { Add-FeedMoreButton $st }
}
function Add-FeedChunk {
    $st = $script:ActRender
    if (-not $st -or $st.Gen -ne $script:ActGen) { return }
    Add-FeedRows $st 20
    if ($st.Index -lt $st.Take) { [void]$win.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, [action]{ Add-FeedChunk }) } else { Add-FeedMoreButton $st }
}
function New-Tile {
    param([string]$Label, [string]$Value, [string]$Sub, [string]$Colour, [scriptblock]$OnClick, [bool]$On, $Tag)
    $outer = New-Object Windows.Controls.Border; $outer.Background = (Brush $script:C.Panel); $outer.BorderBrush = (Brush $(if ($On) { $script:C.Accent } else { $script:C.Line })); $outer.BorderThickness = (Th 1 1 1 1)
    $outer.CornerRadius = New-Object Windows.CornerRadius(10); $outer.Margin = (Th 0 0 10 0); $outer.Cursor = 'Hand'; $outer.Tag = $Tag; $outer.ToolTip = 'Click to filter the Apps list'
    $g = New-Object Windows.Controls.Grid
    $g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)); $g.RowDefinitions[0].Height = New-Object Windows.GridLength(3)
    $g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition))
    $rail = New-Object Windows.Controls.Border; $rail.Background = (Brush $(if ($Colour) { $Colour } else { $script:C.Accent })); $rail.CornerRadius = New-Object Windows.CornerRadius(9, 9, 0, 0); $rail.Margin = (Th 0 0 0 0)
    [void]$g.Children.Add($rail)
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = (Th 14 8 14 10)
    [void]$sp.Children.Add((New-Text -Text $Label -Size 11 -Colour $script:C.Ink3))
    [void]$sp.Children.Add((New-Text -Text $Value -Size 24 -Colour $(if ($Colour) { $Colour } else { $script:C.Ink }) -Weight 'SemiBold' -Margin (Th 0 1 0 0)))
    if ($Sub) { [void]$sp.Children.Add((New-Text -Text $Sub -Size 11.5 -Colour $script:C.Ink3)) }
    [Windows.Controls.Grid]::SetRow($sp, 1); [void]$g.Children.Add($sp)
    $outer.Child = $g
    if ($OnClick) { $outer.Add_MouseLeftButtonUp($OnClick) }
    return $outer
}
function New-BarChart {
    param([string[]]$Keys, [hashtable]$Counts, [int]$Height = 84)
    $wrap = New-Object Windows.Controls.StackPanel
    $g = New-Object Windows.Controls.Grid; $g.Height = $Height + 18; $g.Margin = (Th 0 6 0 0)
    $max = 1; foreach ($k in $Keys) { if ([int]$Counts[$k] -gt $max) { $max = [int]$Counts[$k] } }
    $i = 0
    foreach ($k in $Keys) {
        $g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
        $n = [int]$Counts[$k]
        $sp = New-Object Windows.Controls.StackPanel; $sp.VerticalAlignment = 'Bottom'; $sp.Margin = (Th 2 0 2 0)
        # labels only on the peak and the current month - twelve labels in a narrow card overlap; the rest is on hover
        $lbl = New-Text -Text $(if ($n -and ($n -eq $max -or $k -eq $Keys[-1])) { "$n" } else { '' }) -Size 10.5 -Colour $script:C.Ink3 -Margin (Th 0 0 0 2); $lbl.HorizontalAlignment = 'Center'; [void]$sp.Children.Add($lbl)
        $bar = New-Object Windows.Controls.Border; $bar.Background = (Brush $script:C.Accent); $bar.Opacity = 0.85; $bar.CornerRadius = New-Object Windows.CornerRadius(3, 3, 0, 0); $bar.Height = [Math]::Max(2, [int]($Height * $n / $max)); $bar.ToolTip = "$k : $n"
        [void]$sp.Children.Add($bar)
        [Windows.Controls.Grid]::SetColumn($sp, $i); [void]$g.Children.Add($sp); $i++
    }
    [void]$wrap.Children.Add($g)
    $ax = New-Object Windows.Controls.DockPanel; $ax.Margin = (Th 0 6 0 0)
    $r = New-Text -Text $Keys[-1] -Size 11 -Colour $script:C.Ink3; [Windows.Controls.DockPanel]::SetDock($r, 'Right'); [void]$ax.Children.Add($r)
    [void]$ax.Children.Add((New-Text -Text $Keys[0] -Size 11 -Colour $script:C.Ink3))
    [void]$wrap.Children.Add($ax)
    return $wrap
}
function New-Donut {
    param([hashtable]$Counts, [string[]]$Order, [hashtable]$Colours, [double]$Size = 104)
    $total = 0; foreach ($k in $Order) { $total += [int]$Counts[$k] }
    $canvas = New-Object Windows.Controls.Canvas; $canvas.Width = $Size; $canvas.Height = $Size; $canvas.Margin = (Th 0 0 16 0); $canvas.VerticalAlignment = 'Top'
    $cx = $Size / 2; $cy = $Size / 2; $rOut = $Size / 2; $rIn = $Size / 2 - 15
    $start = -90.0
    foreach ($k in $Order) {
        $n = [int]$Counts[$k]; if ($n -le 0 -or $total -le 0) { continue }
        $sweep = 360.0 * $n / $total; if ($sweep -ge 359.99) { $sweep = 359.99 }
        $a0 = $start * [Math]::PI / 180; $a1 = ($start + $sweep) * [Math]::PI / 180
        $p = New-Object Windows.Shapes.Path; $p.Fill = (Brush $Colours[$k]); $p.ToolTip = "$k : $n"
        $geo = New-Object Windows.Media.PathGeometry
        $fig = New-Object Windows.Media.PathFigure; $fig.StartPoint = New-Object Windows.Point(($cx + $rOut * [Math]::Cos($a0)), ($cy + $rOut * [Math]::Sin($a0))); $fig.IsClosed = $true
        $arc1 = New-Object Windows.Media.ArcSegment; $arc1.Point = New-Object Windows.Point(($cx + $rOut * [Math]::Cos($a1)), ($cy + $rOut * [Math]::Sin($a1))); $arc1.Size = New-Object Windows.Size($rOut, $rOut); $arc1.SweepDirection = 'Clockwise'; $arc1.IsLargeArc = ($sweep -gt 180)
        $line = New-Object Windows.Media.LineSegment; $line.Point = New-Object Windows.Point(($cx + $rIn * [Math]::Cos($a1)), ($cy + $rIn * [Math]::Sin($a1)))
        $arc2 = New-Object Windows.Media.ArcSegment; $arc2.Point = New-Object Windows.Point(($cx + $rIn * [Math]::Cos($a0)), ($cy + $rIn * [Math]::Sin($a0))); $arc2.Size = New-Object Windows.Size($rIn, $rIn); $arc2.SweepDirection = 'Counterclockwise'; $arc2.IsLargeArc = ($sweep -gt 180)
        $fig.Segments.Add($arc1); $fig.Segments.Add($line); $fig.Segments.Add($arc2)
        $geo.Figures.Add($fig); $p.Data = $geo
        [void]$canvas.Children.Add($p)
        $start += $sweep
    }
    return $canvas
}
function New-ListLink {
    param($App, [string]$Meta)
    $b = New-Object Windows.Controls.Border; $b.Background = (Brush $script:C.Panel2); $b.CornerRadius = New-Object Windows.CornerRadius(6); $b.Padding = (Th 10 6 10 6); $b.Margin = (Th 0 0 0 6); $b.Cursor = 'Hand'; $b.Tag = $App.Id
    $dp = New-Object Windows.Controls.DockPanel
    if ($Meta) { $m = New-Text -Text $Meta -Size 12 -Colour $script:C.Ink3; [Windows.Controls.DockPanel]::SetDock($m, 'Right'); $m.Margin = (Th 10 0 0 0); [void]$dp.Children.Add($m) }
    $nm = New-Text -Text $App.DisplayName -Size 13; $nm.TextTrimming = 'CharacterEllipsis'; $nm.ToolTip = $App.DisplayName; [void]$dp.Children.Add($nm)
    $b.Child = $dp
    $b.Add_MouseLeftButtonUp({ param($s, $e) $app = Find-App "$($s.Tag)"; if ($app) { Show-App $app } })
    return $b
}
function Get-Ago { param([string]$When) try { $d = ((Get-Date) - [datetime]::Parse("$When")).TotalDays; if ($d -lt 1) { return 'today' }; if ($d -lt 30) { return "$([int]$d) d ago" }; if ($d -lt 365) { return "$([int]($d / 30)) mo ago" }; return ('{0:N1} y ago' -f ($d / 365)) } catch { return '' } }
function Find-Row { param($Source, [type]$Type)   # walk up from a click's OriginalSource to the containing grid row
    $d = $Source
    while ($d) {
        if ($d -is $Type) { return $d }
        if ($d -is [Windows.Controls.Primitives.DataGridColumnHeader] -or $d -is [Windows.Controls.Primitives.ScrollBar] -or $d -is [Windows.Controls.Button]) { return $null }
        if ($d -is [Windows.Media.Visual]) { $d = [Windows.Media.VisualTreeHelper]::GetParent($d) } elseif ($d -is [Windows.FrameworkContentElement]) { $d = $d.Parent } else { return $null }
    }
    return $null
}

# --- navigation ------------------------------------------------------------------------------------------
function Show-Page {
    param([string]$Name)
    $script:CurrentPage = $Name
    foreach ($p in 'PgOverview','PgApps','PgApp','PgActivity','PgPeople','PgInsights') { (Get-Variable $p -ValueOnly).Visibility = 'Collapsed' }
    $map = @{ overview = 'PgOverview'; apps = 'PgApps'; app = 'PgApp'; activity = 'PgActivity'; people = 'PgPeople'; insights = 'PgInsights' }
    (Get-Variable $map[$Name] -ValueOnly).Visibility = 'Visible'
    $navMap = @{ overview = $NavOverview; apps = $NavApps; app = $NavApps; activity = $NavActivity; people = $NavPeople; insights = $NavInsights }
    $script:NavSuppress = $true; $navMap[$Name].IsChecked = $true; $script:NavSuppress = $false
    $Crumb.Visibility = $(if ($Name -eq 'app') { 'Visible' } else { 'Collapsed' }); $Crumb.Text = 'Apps  /'
    $Title.Text = @{ overview = 'Overview'; apps = 'Apps'; activity = 'Activity'; people = 'People'; insights = 'Insights'; app = "$($script:CurrentApp.DisplayName)" }[$Name]
    $BtnExport.Content = @{ overview = 'Export apps'; apps = 'Export list'; app = 'Export app report'; activity = 'Export activity'; people = 'Export people'; insights = 'Export apps' }[$Name]
    switch ($Name) { 'overview' { Build-Overview } 'apps' { Update-Grid } 'activity' { Build-Activity } 'people' { Build-People } 'insights' { Build-Insights } }
}
function Show-App { param($App, [string]$TabName = 'overview') $script:CurrentApp = $App; $script:AppTab = $TabName; $script:HistFilter = @{ Kind = ''; Who = '' }; Show-Page 'app'; Build-AppPage; $PgApp.ScrollToTop() }

# --- overview -----------------------------------------------------------------------------------------------
function Get-Counts { param([object[]]$List, [string]$Key) $m = @{}; foreach ($a in (AsArray $List)) { $k = "$($a.$Key)"; $m[$k] = [int]$m[$k] + 1 }; return $m }
function Get-MonthKeys { $keys = @(); for ($i = 11; $i -ge 0; $i--) { $keys += (Get-Date).AddMonths(-$i).ToString('yyyy-MM') }; return $keys }
function Set-LifeFilter { param([string]$Stage) $set = New-Object 'System.Collections.Generic.HashSet[string]'; [void]$set.Add($Stage); $script:Filters = @{ Lifecycle = $set }; foreach ($c in $script:Cols) { Set-FilterIndicator -Key $c.Key } }
function Build-Overview {
    $OverviewPanel.Children.Clear()
    $apps = AsArray $script:Apps
    if ($apps.Count -eq 0) { [void]$OverviewPanel.Children.Add((New-Text -Text 'No data yet - click Sync to pull your apps from Intune.' -Colour $script:C.Ink3)); return }
    $lc = Get-Counts $apps 'Lifecycle'; $kc = Get-Counts $apps 'Kind'
    $tiles = New-Object Windows.Controls.Primitives.UniformGrid; $tiles.Rows = 1; $tiles.Margin = (Th 0 0 0 18)
    [void]$tiles.Children.Add((New-Tile -Label 'ALL APPS' -Value "$($apps.Count)" -Sub 'in the tenant' -OnClick { $script:Filters = @{}; foreach ($c in $script:Cols) { Set-FilterIndicator -Key $c.Key }; Show-Page 'apps' }))
    foreach ($l in $script:LifeOrder) { if (-not $lc[$l]) { continue }; [void]$tiles.Children.Add((New-Tile -Label $l -Value "$($lc[$l])" -Sub ("{0}% of apps" -f [int](100 * $lc[$l] / $apps.Count)) -Colour $script:LifeColour[$l] -Tag $l -OnClick { param($s, $e) Set-LifeFilter "$($s.Tag)"; Show-Page 'apps' })) }
    [void]$OverviewPanel.Children.Add($tiles)

    $row = New-Object Windows.Controls.Primitives.UniformGrid; $row.Rows = 1; $row.Columns = 4
    $c = New-Card 'Apps by lifecycle'
    $dk = New-Object Windows.Controls.DockPanel
    [void]$dk.Children.Add((New-Donut -Counts $lc -Order $script:LifeOrder -Colours $script:LifeColour))
    $lg = New-Object Windows.Controls.StackPanel; $lg.VerticalAlignment = 'Center'
    foreach ($l in $script:LifeOrder) { if (-not $lc[$l]) { continue }; $li = New-Object Windows.Controls.StackPanel; $li.Orientation = 'Horizontal'; $li.Margin = (Th 0 1 0 1); $sw = New-Object Windows.Controls.Border; $sw.Width = 9; $sw.Height = 9; $sw.CornerRadius = New-Object Windows.CornerRadius(2); $sw.Background = (Brush $script:LifeColour[$l]); $sw.Margin = (Th 0 0 8 0); $sw.VerticalAlignment = 'Center'; [void]$li.Children.Add($sw); [void]$li.Children.Add((New-Text -Text $l -Size 12)); [void]$li.Children.Add((New-Text -Text "$($lc[$l])" -Size 12 -Colour $script:C.Ink3 -Margin (Th 7 0 0 0))); [void]$lg.Children.Add($li) }
    [void]$dk.Children.Add($lg); [void]$c.Body.Children.Add($dk); [void]$row.Children.Add($c.Border)
    $c = New-Card 'Apps by kind'
    foreach ($k in 'Standard','UPD','Test','Winget') {
        $n = [int]$kc[$k]
        $hb = New-Object Windows.Controls.Grid; $hb.Margin = (Th 0 3 0 3); $hb.Cursor = 'Hand'; $hb.Tag = $k; $hb.Background = [Windows.Media.Brushes]::Transparent; $hb.ToolTip = "Show $k apps"
        foreach ($w in 78, 0, 36) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $(if ($w) { New-Object Windows.GridLength($w) } else { New-Object Windows.GridLength(1, 'Star') }); $hb.ColumnDefinitions.Add($cd) }
        $chip = New-KindChip $k; $chip.HorizontalAlignment = 'Left'; [void]$hb.Children.Add($chip)
        # bar length is set from the column's real width on SizeChanged (Tag = count)
        $scale = New-Object Windows.Controls.Border; $scale.Height = 10; $scale.CornerRadius = New-Object Windows.CornerRadius(3); $scale.Background = (Brush $script:C.Accent); $scale.HorizontalAlignment = 'Left'; $scale.VerticalAlignment = 'Center'
        $scale.Tag = $n; $scale.Width = 4
        [Windows.Controls.Grid]::SetColumn($scale, 1); [void]$hb.Children.Add($scale)
        $hb.Add_SizeChanged({ param($s, $e) $inner = $s.Children[1]; $avail = [Math]::Max(0, $s.ColumnDefinitions[1].ActualWidth - 10); $tot = [Math]::Max(1, (AsArray $script:Apps).Count); $inner.Width = [Math]::Max(3, $avail * [int]$inner.Tag / $tot) })
        $nt = New-Text -Text "$n" -Size 12.5 -Colour $script:C.Ink2; $nt.HorizontalAlignment = 'Right'; [Windows.Controls.Grid]::SetColumn($nt, 2); [void]$hb.Children.Add($nt)
        $hb.Add_MouseLeftButtonUp({ param($s, $e) $set = New-Object 'System.Collections.Generic.HashSet[string]'; [void]$set.Add("$($s.Tag)"); $script:Filters = @{ Kind = $set }; foreach ($c in $script:Cols) { Set-FilterIndicator -Key $c.Key }; Show-Page 'apps' })
        [void]$c.Body.Children.Add($hb)
    }
    $vc = Get-Counts $apps 'CreatedVia'
    [void]$c.Body.Children.Add((New-Text -Text ("Created via  " + (($vc.Keys | Sort-Object { -$vc[$_] } | ForEach-Object { "$_ $($vc[$_])" }) -join '  ·  ')) -Size 11.5 -Colour $script:C.Ink3 -Wrap $true -Margin (Th 0 10 0 0)))
    [void]$row.Children.Add($c.Border)
    $months = Get-MonthKeys
    $cm = @{}; foreach ($a in $apps) { $k = "$($a.CreatedDateTime)"; if ($k.Length -ge 7) { $k = $k.Substring(0, 7); $cm[$k] = [int]$cm[$k] + 1 } }
    $c = New-Card 'Apps created per month'; [void]$c.Body.Children.Add((New-BarChart -Keys $months -Counts $cm)); [void]$row.Children.Add($c.Border)
    $chm = @{}; foreach ($e in (AsArray (Get-Feed))) { $k = "$($e.When)"; if ($k.Length -ge 7) { $k = $k.Substring(0, 7); $chm[$k] = [int]$chm[$k] + 1 } }
    $c = New-Card 'Changes per month'; [void]$c.Body.Children.Add((New-BarChart -Keys $months -Counts $chm)); [void]$row.Children.Add($c.Border)
    [void]$OverviewPanel.Children.Add($row)

    [void]$OverviewPanel.Children.Add((New-Text -Text 'NEEDS ATTENTION' -Size 11.5 -Colour $script:C.Ink3 -Weight 'SemiBold' -Margin (Th 0 8 0 10)))
    $row2 = New-Object Windows.Controls.Primitives.UniformGrid; $row2.Rows = 1; $row2.Columns = 4
    foreach ($s in ((Get-Insights) | Select-Object -First 4)) {
        $c = New-Card $s.Title "$($s.Items.Count)"
        foreach ($a in ($s.Items | Select-Object -First 5)) { [void]$c.Body.Children.Add((New-ListLink -App $a -Meta (& $s.Meta $a))) }
        if ($s.Items.Count -eq 0) { [void]$c.Body.Children.Add((New-Text -Text 'none' -Size 12.5 -Colour $script:C.Ink3)) }
        if ($s.Items.Count -gt 5) { $lnk = New-Object Windows.Controls.Button; $lnk.Style = $script:LinkStyle; $lnk.Content = (New-Text -Text "all $($s.Items.Count) in Insights" -Size 12 -Colour $script:C.Accent); $lnk.HorizontalAlignment = 'Left'; $lnk.Margin = (Th 2 4 0 0); $lnk.Add_Click({ Show-Page 'insights' }); [void]$c.Body.Children.Add($lnk) }
        [void]$row2.Children.Add($c.Border)
    }
    [void]$OverviewPanel.Children.Add($row2)

    [void]$OverviewPanel.Children.Add((New-Text -Text 'RECENT ACTIVITY' -Size 11.5 -Colour $script:C.Ink3 -Weight 'SemiBold' -Margin (Th 0 8 0 10)))
    $c = New-Card -NoTitle
    Add-Feed -Panel $c.Body -Entries ((AsArray (Get-Feed)) | Where-Object { $_.Kind -ne 'minor' } | Select-Object -First 8) -InApp $false
    $lnk = New-Object Windows.Controls.Button; $lnk.Style = $script:LinkStyle; $lnk.Content = (New-Text -Text 'All activity' -Size 12.5 -Colour $script:C.Accent); $lnk.HorizontalAlignment = 'Right'; $lnk.Margin = (Th 0 10 4 0); $lnk.Add_Click({ Show-Page 'activity' }); [void]$c.Body.Children.Add($lnk)
    [void]$OverviewPanel.Children.Add($c.Border)
}

# --- insights ------------------------------------------------------------------------------------------------
function Get-Insights {
    $apps = AsArray $script:Apps; $now = Get-Date; $stale = [int]$cfg.StaleAfterDays
    $byName = @{}; foreach ($a in $apps) { $k = "$($a.DisplayName)"; if (-not $byName.ContainsKey($k)) { $byName[$k] = New-Object 'System.Collections.Generic.List[object]' }; [void]$byName[$k].Add($a) }
    $days = { param($w) try { ($now - [datetime]::Parse("$w")).TotalDays } catch { 0 } }
    return @(
        @{ Title = 'Failed UAT';                      Items = @($apps | Where-Object { $_.Lifecycle -eq 'FailedUAT' });                                                  Meta = { param($a) "$(Get-Ago $a.LastChangeWhen)" } }
        @{ Title = 'In UAT longer than 30 days';      Items = @($apps | Where-Object { $_.Lifecycle -eq 'UAT' -and (& $days $_.LastModifiedDateTime) -gt 30 });           Meta = { param($a) "idle $(Get-Ago $a.LastModifiedDateTime)" } }
        @{ Title = 'LIVE but not assigned';           Items = @($apps | Where-Object { $_.Lifecycle -eq 'LIVE' -and [int]$_.AssignmentCount -eq 0 });                  Meta = { param($a) "$($a.DisplayVersion)" } }
        @{ Title = 'RETIRED but still assigned';      Items = @($apps | Where-Object { $_.Lifecycle -eq 'RETIRED' -and [int]$_.AssignmentCount -gt 0 });               Meta = { param($a) "$($a.AssignmentCount) assignment$(if ([int]$a.AssignmentCount -ne 1) { 's' })" } }
        @{ Title = 'Test apps still present';         Items = @($apps | Where-Object { $_.Kind -eq 'Test' });                                                           Meta = { param($a) "created $(Get-Ago $a.CreatedDateTime)" } }
        @{ Title = 'Superseded but still LIVE';       Items = @($apps | Where-Object { [int]$_.SupersededByCount -gt 0 -and $_.Lifecycle -eq 'LIVE' });                Meta = { param($a) "$($a.DisplayVersion)" } }
        @{ Title = 'Same name, several versions';     Items = @($byName.Keys | Where-Object { $byName[$_].Count -gt 1 } | Sort-Object | ForEach-Object { $byName[$_] }); Meta = { param($a) "$($a.DisplayVersion)  ·  $($a.Lifecycle)" } }
        @{ Title = "No change for over $stale days";  Items = @($apps | Where-Object { $_.Lifecycle -ne 'RETIRED' -and (& $days $_.LastModifiedDateTime) -gt $stale }); Meta = { param($a) "idle $(Get-Ago $a.LastModifiedDateTime)" } }
        @{ Title = 'Without detection rules';         Items = @($apps | Where-Object { (AsArray $_.DetectionRules).Count -eq 0 });                                       Meta = { param($a) "$($a.Lifecycle)" } }
        @{ Title = 'Created by hand (no tool note)';  Items = @($apps | Where-Object { "$($_.CreatedVia)" -match 'Manual' });                                           Meta = { param($a) "$(if ($a.CreatedByName) { $a.CreatedByName } else { 'creator unknown' })  ·  $(Format-Date $a.CreatedDateTime)" } }
    )
}
function Build-Insights {
    $InsightsPanel.Children.Clear()
    $g = New-Object Windows.Controls.Grid
    $g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition)); $g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
    $cols = @((New-Object Windows.Controls.StackPanel), (New-Object Windows.Controls.StackPanel))
    [Windows.Controls.Grid]::SetColumn($cols[1], 1); [void]$g.Children.Add($cols[0]); [void]$g.Children.Add($cols[1])
    $i = 0
    foreach ($s in (Get-Insights)) {
        $c = New-Card $s.Title "$($s.Items.Count)"
        if ($s.Items.Count -eq 0) { [void]$c.Body.Children.Add((New-Text -Text 'none' -Size 12.5 -Colour $script:C.Ink3)) }
        foreach ($a in ($s.Items | Select-Object -First 25)) { [void]$c.Body.Children.Add((New-ListLink -App $a -Meta (& $s.Meta $a))) }
        if ($s.Items.Count -gt 25) { [void]$c.Body.Children.Add((New-Text -Text "+$($s.Items.Count - 25) more - use the Apps grid filters" -Size 12 -Colour $script:C.Ink3 -Margin (Th 2 2 0 0))) }
        [void]$cols[$i % 2].Children.Add($c.Border); $i++
    }
    $InsightsPanel.Children.Add($g) | Out-Null
}

# --- apps grid ------------------------------------------------------------------------------------------------
$script:OnFilterClick = { param($s, $e) $key = "$($s.Tag)"; $script:PopCol = $key; $col = $script:Cols | Where-Object { $_.Key -eq $key } | Select-Object -First 1; $PopTitle.Text = "Filter by $($col.Title.ToLower())"; $PopSearch.Text = ''; Build-PopupList -Key $key; $Pop.PlacementTarget = $s; $Pop.IsOpen = $true }
function Measure-Header { param([string]$Title)   # full header text + padding + filter button + gripper, in px
    $tf = New-Object Windows.Media.Typeface((New-Object Windows.Media.FontFamily('Segoe UI')), [Windows.FontStyles]::Normal, [Windows.FontWeights]::SemiBold, [Windows.FontStretches]::Normal)
    $ft = New-Object Windows.Media.FormattedText($Title, [Globalization.CultureInfo]::CurrentUICulture, [Windows.FlowDirection]::LeftToRight, $tf, 11.5, [Windows.Media.Brushes]::White)
    return [int][Math]::Ceiling($ft.WidthIncludingTrailingWhitespace + 16 + 26 + 6)
}
function Build-Columns {
    $Grid1.Columns.Clear(); $script:ColByKey = @{}
    foreach ($key in $script:GridOrder) {
        $c = $script:Cols | Where-Object { $_.Key -eq $key } | Select-Object -First 1
        $c.Min = [Math]::Max([int]$c.Min, (Measure-Header $c.Title))
        $col = New-Object Windows.Controls.DataGridTemplateColumn
        $col.SortMemberPath = $c.Key
        $col.Width = New-Object Windows.Controls.DataGridLength($c.Width, [Windows.Controls.DataGridLengthUnitType]::Star)
        $col.MinWidth = $c.Min
        $xml = switch ($c.Key) {
            'Lifecycle'       { '<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Border CornerRadius="5" Padding="8,2,8,3" HorizontalAlignment="Left" Background="{Binding LifeBg}"><TextBlock Text="{Binding Lifecycle}" FontSize="11.5" FontWeight="SemiBold" Foreground="{Binding LifeFg}"/></Border></DataTemplate>' }
            'Kind'            { '<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Border CornerRadius="5" Padding="8,2,8,3" HorizontalAlignment="Left" Background="{Binding KindBg}"><TextBlock Text="{Binding Kind}" FontSize="11.5" FontWeight="SemiBold" Foreground="{Binding KindFg}"/></Border></DataTemplate>' }
            'DisplayName'     { '<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock Text="{Binding DisplayName}" FontWeight="SemiBold" TextTrimming="CharacterEllipsis" ToolTip="{Binding DisplayName}"/></DataTemplate>' }
            'DisplayVersion'  { '<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock Text="{Binding DisplayVersion}" FontFamily="Consolas" FontSize="12" TextTrimming="CharacterEllipsis" ToolTip="{Binding DisplayVersion}"/></DataTemplate>' }
            'AssignmentCount' { '<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock Text="{Binding AssignmentCount}" HorizontalAlignment="Right" Margin="0,0,24,0" ToolTip="{Binding AssignmentSummary}"/></DataTemplate>' }
            default           { "<DataTemplate xmlns=`"http://schemas.microsoft.com/winfx/2006/xaml/presentation`"><TextBlock Text=`"{Binding $($c.Key)}`" Foreground=`"#FFA3B0BF`" TextTrimming=`"CharacterEllipsis`" ToolTip=`"{Binding $($c.Key)}`"/></DataTemplate>" }
        }
        $col.CellTemplate = [Windows.Markup.XamlReader]::Parse($xml)
        $dp = New-Object Windows.Controls.DockPanel
        $btn = New-Object Windows.Controls.Button; $btn.Style = $win.FindResource('Ghost'); $btn.Content = [string][char]0x25BC; $btn.FontSize = 8; $btn.Tag = $c.Key; $btn.ToolTip = 'Filter this column'; $btn.Margin = (Th 6 0 0 0); $btn.Padding = (Th 4 2 4 2); $btn.VerticalAlignment = 'Center'
        $btn.Add_Click($script:OnFilterClick)
        [Windows.Controls.DockPanel]::SetDock($btn, 'Right'); [void]$dp.Children.Add($btn)
        [void]$dp.Children.Add((New-Text -Text $c.Title -Size 11.5 -Colour $script:C.Ink3 -Weight 'SemiBold'))
        $col.Header = $dp
        $script:FilterBtns[$c.Key] = $btn; $script:ColByKey[$c.Key] = $col
        if (-not $script:ColState.ContainsKey($c.Key)) { $script:ColState[$c.Key] = 'auto' }
        $Grid1.Columns.Add($col)
    }
}
# Show as many columns (in priority order) as fit at their measured minimum width; never squeeze a header.
function Update-ColumnLayout {
    $avail = $Grid1.ActualWidth - 14
    if ($avail -lt 100) { return }
    $used = 0; $hidden = New-Object 'System.Collections.Generic.List[string]'
    foreach ($c in $script:Cols) {
        $col = $script:ColByKey[$c.Key]; if (-not $col) { continue }
        $st = "$($script:ColState[$c.Key])"
        if ($st -eq 'off') { $col.Visibility = 'Collapsed'; continue }
        if ($st -eq 'on' -or ($used + $c.Min) -le $avail) { $col.Visibility = 'Visible'; $used += $c.Min } else { $col.Visibility = 'Collapsed'; [void]$hidden.Add($c.Title) }
    }
    $script:HiddenCols = $hidden.ToArray()
    # everything fits -> no horizontal scrollbar at all (stars fill the width exactly); forced columns -> scroll
    [Windows.Controls.ScrollViewer]::SetHorizontalScrollBarVisibility($Grid1, $(if ($used -le $avail) { 'Disabled' } else { 'Auto' }))
    $AppsFoot.Text = $(if ($hidden.Count) { "Click a row to open the app.  $($hidden -join ', ') hidden at this width (headers are never cut) - Columns to show them." } else { 'Click a row to open the app.  Filter any column with its arrow; tiles filter by lifecycle.' })
}
function Open-ColumnChooser {
    $ColList.Children.Clear()
    $ColHint.Text = "Ticked columns are always shown (the list scrolls sideways if needed); unticked ones are hidden. Automatic shows what fits."
    foreach ($c in $script:Cols) {
        $col = $script:ColByKey[$c.Key]
        $cb = New-Object Windows.Controls.CheckBox; $cb.Tag = $c.Key; $cb.Margin = (Th 2 3 2 3)
        $cb.Content = $c.Title + $(if ("$($script:ColState[$c.Key])" -eq 'auto') { '  (auto)' } else { '' })
        $cb.IsChecked = ($col.Visibility -eq 'Visible')
        $cb.Add_Click({ param($s, $e) $script:ColState["$($s.Tag)"] = $(if ($s.IsChecked) { 'on' } else { 'off' }); Update-ColumnLayout; Open-ColumnChooser })
        [void]$ColList.Children.Add($cb)
    }
    $ColPop.PlacementTarget = $BtnCols; $ColPop.IsOpen = $true
}
function Build-PopupList {
    param([string]$Key)
    $PopList.Children.Clear()
    $counts = @{}; foreach ($a in (Get-VisibleRows -IgnoreColumn $Key)) { $v = Get-CellText $a $Key; $counts[$v] = [int]$counts[$v] + 1 }
    $allowed = $script:Filters[$Key]
    foreach ($v in ($counts.Keys | Sort-Object)) { $cb = New-Object Windows.Controls.CheckBox; $cb.Content = "$v  ($($counts[$v]))"; $cb.Tag = $v; $cb.Margin = (Th 2 3 2 3); $cb.IsChecked = $(if ($null -eq $allowed) { $true } else { $allowed.Contains($v) }); [void]$PopList.Children.Add($cb) }
    if ($PopList.Children.Count -eq 0) { [void]$PopList.Children.Add((New-Text -Text '(no values)' -Colour $script:C.Ink3)) }
}
function Set-FilterIndicator { param([string]$Key) $btn = $script:FilterBtns[$Key]; if (-not $btn) { return }; $on = ($script:Filters.ContainsKey($Key) -and $null -ne $script:Filters[$Key]); $btn.Foreground = (Brush $(if ($on) { $script:C.Accent } else { $script:C.Ink3 })); $btn.FontSize = $(if ($on) { 10 } else { 8 }) }
function Get-VisibleRows {
    param([string]$IgnoreColumn)
    $q = "$script:AppsQuery".Trim().ToLower()
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($a in (AsArray $script:Apps)) {
        $ok = $true
        foreach ($k in @($script:Filters.Keys)) { if ($k -eq $IgnoreColumn) { continue }; $set = $script:Filters[$k]; if ($null -eq $set) { continue }; if (-not $set.Contains((Get-CellText $a $k))) { $ok = $false; break } }
        if (-not $ok) { continue }
        if ($q) { $hay = ((@($a.DisplayName, $a.DisplayVersion, $a.Publisher, $a.Owner, $a.NotesText, $a.Flags, $a.AssignmentSummary, $a.CreatedBy, $a.CreatedByName, $a.LastChangedByName, $a.CreatedVia, $a.Lifecycle, $a.Kind, $a.Id)) -join ' ').ToLower(); if ($hay -notmatch [regex]::Escape($q)) { continue } }
        [void]$out.Add($a)
    }
    return ,$out.ToArray()
}
function Update-Tiles {
    $AppTiles.Children.Clear()
    $all = Get-Counts (AsArray $script:Apps) 'Lifecycle'; $vis = Get-Counts (Get-VisibleRows) 'Lifecycle'
    $active = $script:Filters['Lifecycle']
    foreach ($l in $script:LifeOrder) {
        if (-not $all[$l]) { continue }
        $on = [bool]($active -and $active.Count -eq 1 -and $active.Contains($l))
        [void]$AppTiles.Children.Add((New-Tile -Label $l -Value "$([int]$vis[$l])" -Sub "of $($all[$l])" -Colour $script:LifeColour[$l] -On $on -Tag $l -OnClick { param($s, $e) $l = "$($s.Tag)"; $cur = $script:Filters['Lifecycle']; if ($cur -and $cur.Count -eq 1 -and $cur.Contains($l)) { $script:Filters.Remove('Lifecycle') } else { $set = New-Object 'System.Collections.Generic.HashSet[string]'; [void]$set.Add($l); $script:Filters['Lifecycle'] = $set }; Set-FilterIndicator -Key 'Lifecycle'; Update-Grid }))
    }
}
function Update-Chips {
    $FilterChips.Children.Clear()
    foreach ($k in @($script:Filters.Keys | Sort-Object)) {
        $set = $script:Filters[$k]; if ($null -eq $set) { continue }
        $col = $script:Cols | Where-Object { $_.Key -eq $k } | Select-Object -First 1
        $vals = @($set) | Sort-Object
        $b = New-Object Windows.Controls.Border; $b.Background = (Brush $script:C.AccentSoft); $b.CornerRadius = New-Object Windows.CornerRadius(11); $b.Padding = (Th 10 3 8 4); $b.Margin = (Th 0 0 6 0); $b.Cursor = 'Hand'; $b.Tag = $k; $b.ToolTip = "Remove this filter`n$($vals -join "`n")"
        $b.Child = (New-Text -Text ("$($col.Title): $(if ($vals.Count -le 2) { $vals -join ', ' } else { "$($vals.Count) values" })   x") -Size 11.5 -Colour $script:C.Accent -Weight 'SemiBold')
        $b.Add_MouseLeftButtonUp({ param($s, $e) $script:Filters.Remove("$($s.Tag)"); Set-FilterIndicator -Key "$($s.Tag)"; Update-Grid })
        [void]$FilterChips.Children.Add($b)
    }
    if ($script:Filters.Count -or $script:AppsQuery) { $clr = New-Object Windows.Controls.Button; $clr.Content = 'Clear all'; $clr.Padding = (Th 9 3 9 4); $clr.FontSize = 12; $clr.Add_Click({ $script:Filters = @{}; $script:AppsQuery = ''; $AppsSearch.Text = ''; $GlobalSearch.Text = ''; foreach ($c in $script:Cols) { Set-FilterIndicator -Key $c.Key }; Update-Grid }); [void]$FilterChips.Children.Add($clr) }
}
function Update-Grid {
    $rows = Get-VisibleRows
    foreach ($a in $rows) {
        if (-not ($a.PSObject.Properties['LifeFg'])) {
            $l = "$($a.Lifecycle)"; if (-not $script:LifeColour.ContainsKey($l)) { $l = 'Not recorded' }
            $k = "$($a.Kind)"; if (-not $script:KindColour.ContainsKey($k)) { $k = 'Standard' }
            $a | Add-Member -NotePropertyName LifeFg -NotePropertyValue (Brush $script:LifeColour[$l]) -Force
            $a | Add-Member -NotePropertyName LifeBg -NotePropertyValue (Brush $script:LifeBg[$l]) -Force
            $a | Add-Member -NotePropertyName KindFg -NotePropertyValue (Brush $script:KindColour[$k]) -Force
            $a | Add-Member -NotePropertyName KindBg -NotePropertyValue (Brush $script:KindBg[$k]) -Force
        }
    }
    $script:GridSuppress = $true; $Grid1.ItemsSource = $rows; $Grid1.SelectedItem = $null; $script:GridSuppress = $false
    Update-Tiles; Update-Chips; Update-ColumnLayout
    $n = (AsArray $rows).Count; $total = (AsArray $script:Apps).Count
    $AppsCount.Text = "$n of $total apps"
    if ($script:CurrentPage -eq 'apps') { Set-Status $(if ($n -eq $total) { "$total apps.  Export writes exactly the list you see." } else { "$n of $total apps match.  Export writes exactly the list you see." }) }
}

# --- app page -------------------------------------------------------------------------------------------------
function New-AssignmentRow { param($S, [bool]$Detail)
    $row = New-Object Windows.Controls.Border; $row.Background = (Brush $script:C.Panel2); $row.CornerRadius = New-Object Windows.CornerRadius(6); $row.Padding = (Th 10 6 10 6); $row.Margin = (Th 0 0 0 6)
    $wp = New-Object Windows.Controls.WrapPanel
    [void]$wp.Children.Add((New-Chip -Text $S.Intent -Fg $script:C.Ink2 -Bg $script:C.Panel -Mono))
    [void]$wp.Children.Add((New-Text -Text $S.Target -Size 13 -Wrap $true))
    $ft = "$($S.FilterType)"; if ($ft -and $ft -ne 'none') { [void]$wp.Children.Add((New-Text -Text "   filter: $ft" -Size 12 -Colour $script:C.Ink3)) }
    if ($Detail -and "$($S.GroupId)") { [void]$wp.Children.Add((New-Text -Text "   $($S.GroupId)" -Size 11.5 -Colour $script:C.Ink3 -Mono)) }
    $row.Child = $wp
    return $row
}
function Build-AppPage {
    $AppPanel.Children.Clear()
    $a = $script:CurrentApp; if (-not $a) { return }
    $hist = Get-AppHistory $a
    $hd = New-Object Windows.Controls.DockPanel; $hd.Margin = (Th 0 0 0 14)
    $acts = New-Object Windows.Controls.StackPanel; $acts.Orientation = 'Horizontal'; $acts.VerticalAlignment = 'Top'
    $back = New-Object Windows.Controls.Button; $back.Content = 'Back to Apps'; $back.Add_Click({ Show-Page 'apps' }); [void]$acts.Children.Add($back)
    [Windows.Controls.DockPanel]::SetDock($acts, 'Right'); [void]$hd.Children.Add($acts)
    $hl = New-Object Windows.Controls.StackPanel
    [void]$hl.Children.Add((New-Text -Text $a.DisplayName -Size 22 -Weight 'SemiBold' -Wrap $true))
    $meta = New-Object Windows.Controls.WrapPanel; $meta.Margin = (Th 0 6 0 0)
    [void]$meta.Children.Add((New-LifeChip $a.Lifecycle)); [void]$meta.Children.Add((New-KindChip $a.Kind))
    if ("$($a.DisplayVersion)") { [void]$meta.Children.Add((New-Text -Text $a.DisplayVersion -Size 12.5 -Colour $script:C.Ink2 -Mono -Margin (Th 4 0 12 0))) }
    if ("$($a.Publisher)") { [void]$meta.Children.Add((New-Text -Text $a.Publisher -Size 13 -Colour $script:C.Ink2 -Margin (Th 0 0 12 0))) }
    [void]$meta.Children.Add((New-Text -Text "$($hist.Count) changes on record" -Size 13 -Colour $script:C.Ink3))
    [void]$hl.Children.Add($meta); [void]$hd.Children.Add($hl)
    [void]$AppPanel.Children.Add($hd)
    $tabs = New-Object Windows.Controls.StackPanel; $tabs.Orientation = 'Horizontal'
    $tabBorder = New-Object Windows.Controls.Border; $tabBorder.BorderBrush = (Brush $script:C.Line); $tabBorder.BorderThickness = (Th 0 0 0 1); $tabBorder.Margin = (Th 0 0 0 16); $tabBorder.Child = $tabs
    foreach ($t in @(@('overview','Overview',$null), @('settings','All settings',$null), @('assignments','Assignments',$a.AssignmentCount), @('history','History',$hist.Count))) {
        $rb = New-Object Windows.Controls.RadioButton; $rb.Style = $win.FindResource('TabBtn'); $rb.GroupName = 'apptabs'; $rb.Tag = $t[0]
        $lbl = New-Object Windows.Controls.TextBlock; [void]$lbl.Inlines.Add($t[1]); if ($null -ne $t[2]) { $r = New-Object Windows.Documents.Run("  $($t[2])"); $r.Foreground = (Brush $script:C.Ink3); [void]$lbl.Inlines.Add($r) }
        $rb.Content = $lbl; $rb.IsChecked = ($script:AppTab -eq $t[0])
        $rb.Add_Checked({ param($s, $e) if ($script:AppTab -ne "$($s.Tag)") { $script:AppTab = "$($s.Tag)"; Build-AppPage } })
        [void]$tabs.Children.Add($rb)
    }
    [void]$AppPanel.Children.Add($tabBorder)
    $ver = { param($x) $s = "$x"; if ($s) { $s } else { '' } }
    switch ($script:AppTab) {
        'overview' {
            $grid = New-Object Windows.Controls.Primitives.UniformGrid; $grid.Columns = 2
            $c = New-Card 'Summary'
            $created = "$(Format-When $a.CreatedDateTime)" + $(if ($a.CreatedByName) { "  ·  $($a.CreatedByName)" } else { '  ·  creator outside audit retention' }) + $(if ($a.CreatedVia) { "  ·  $($a.CreatedVia)" } else { '' })
            $last = "$(Format-When $a.LastChangeWhen)" + $(if ($a.LastChangedByName) { "  ·  $($a.LastChangedByName)" } else { '' })
            [void]$c.Body.Children.Add((New-KvGrid @(@('Created',$created),@('Last change',$last),@('Publisher',$a.Publisher),@('Owner',$a.Owner),@('Developer',$a.Developer),@('Status',$a.NoteStatus),@('Managed',$a.ManagedText),@('Pilot',$a.PilotDate),@('Rollout',$a.RolloutDate),@('Note',$a.NotesText),@('Scope tags',$a.ScopeTags),@('App ID',$a.Id,$true))))
            [void]$grid.Children.Add($c.Border)
            $c = New-Card 'Package'
            [void]$c.Body.Children.Add((New-KvGrid @(@('Setup file',$a.SetupFilePath,$true),@('Install',$a.InstallCommandLine,$true),@('Uninstall',$a.UninstallCommandLine,$true),@('Run as',$a.RunAsAccount),@('Restart',$a.RestartBehavior),@('Minimum OS',$a.MinimumOS),@('Size',$(if ($a.SizeMB) { "$($a.SizeMB) MB" } else { '' })),@('Content version',$a.ContentVersion),@('Publishing',$a.PublishingState))))
            [void]$grid.Children.Add($c.Border)
            $c = New-Card 'Deployment' "$($a.AssignmentCount) assignment$(if ([int]$a.AssignmentCount -ne 1) { 's' })"
            if ((AsArray $a.Assignments).Count -eq 0) { [void]$c.Body.Children.Add((New-Text -Text 'Not assigned to anything.' -Size 12.5 -Colour $script:C.Ink3)) }
            foreach ($s in (AsArray $a.Assignments)) { [void]$c.Body.Children.Add((New-AssignmentRow -S $s -Detail $false)) }
            [void]$grid.Children.Add($c.Border)
            $dn = (AsArray $a.DetectionRules).Count
            $c = New-Card 'Detection' "$dn rule$(if ($dn -ne 1) { 's' })"
            if ($dn -eq 0) { [void]$c.Body.Children.Add((New-Text -Text 'No detection rules.' -Size 12.5 -Colour $script:C.Ink3)) }
            foreach ($r in (AsArray $a.DetectionRules)) { $p = New-Pill $r 'plain'; $p.MaxWidth = 4000; $p.HorizontalAlignment = 'Left'; $p.Child.TextWrapping = 'Wrap'; $p.Margin = (Th 0 0 0 6); [void]$c.Body.Children.Add($p) }
            if ((AsArray $a.RequirementRules).Count) { [void]$c.Body.Children.Add((New-Text -Text 'REQUIREMENTS' -Size 11.5 -Colour $script:C.Ink3 -Weight 'SemiBold' -Margin (Th 0 10 0 6))); foreach ($r in (AsArray $a.RequirementRules)) { $p = New-Pill $r 'plain'; $p.MaxWidth = 4000; $p.HorizontalAlignment = 'Left'; $p.Child.TextWrapping = 'Wrap'; $p.Margin = (Th 0 0 0 6); [void]$c.Body.Children.Add($p) } }
            [void]$grid.Children.Add($c.Border)
            $rels = @((AsArray $a.Relationships) | Where-Object { "$($_.TargetName)".Trim() })
            if ($rels.Count) { $c = New-Card 'Supersedence and dependencies'; foreach ($r in $rels) { [void]$c.Body.Children.Add((New-Text -Text "$("$($r.Kind)" -replace 'mobileApp','' -replace 'Relationship','')  ·  $($r.Direction)  ·  $($r.TargetName) $($r.TargetVer)" -Size 13 -Colour $script:C.Ink2 -Margin (Th 0 0 0 4))) }; [void]$grid.Children.Add($c.Border) }
            [void]$AppPanel.Children.Add($grid)
            $c = New-Card 'Recent history' "$($hist.Count) total"
            Add-Feed -Panel $c.Body -Entries ($hist | Select-Object -First 6) -InApp $true
            $lnk = New-Object Windows.Controls.Button; $lnk.Style = $script:LinkStyle; $lnk.Content = (New-Text -Text 'Open full history' -Size 12.5 -Colour $script:C.Accent); $lnk.HorizontalAlignment = 'Right'; $lnk.Margin = (Th 0 10 4 0); $lnk.Add_Click({ $script:AppTab = 'history'; Build-AppPage }); [void]$c.Body.Children.Add($lnk)
            [void]$AppPanel.Children.Add($c.Border)
        }
        'settings' {
            $grid = New-Object Windows.Controls.Primitives.UniformGrid; $grid.Columns = 2
            $groups = @(
                @('Identity', @(@('Name',$a.DisplayName),@('Version',$a.DisplayVersion),@('Publisher',$a.Publisher),@('Owner',$a.Owner),@('Developer',$a.Developer),@('Description',$a.Description),@('App ID',$a.Id,$true),@('Kind (derived)',$a.Kind),@('Created via (derived)',$a.CreatedVia)))
                @('Lifecycle (from the Notes JSON)', @(@('Lifecycle',$a.Lifecycle),@('Status',$a.NoteStatus),@('Managed',$a.ManagedText),@('Pilot',$a.PilotDate),@('Rollout',$a.RolloutDate),@('Note text',$a.NotesText)))
                @('Program', @(@('Setup file',$a.SetupFilePath,$true),@('Install command',$a.InstallCommandLine,$true),@('Uninstall command',$a.UninstallCommandLine,$true),@('Run as',$a.RunAsAccount),@('Device restart behaviour',$a.RestartBehavior)))
                @('Requirements', @(@('Minimum OS',$a.MinimumOS),@('Requirement rules',((AsArray $a.RequirementRules) -join "`n"))))
                @('Detection', @(@('Rules',((AsArray $a.DetectionRules) -join "`n"),$true)))
                @('Content', @(@('Size',$(if ($a.SizeMB) { "$($a.SizeMB) MB" } else { '' })),@('Committed content version',$a.ContentVersion),@('Publishing state',$a.PublishingState)))
                @('Metadata', @(@('Created (Intune)',(Format-When $a.CreatedDateTime)),@('Created by',$(if ($a.CreatedByName) { $a.CreatedByName } else { $a.CreatedBy })),@('Last modified (Intune)',(Format-When $a.LastModifiedDateTime)),@('Last change (audit)',"$(Format-When $a.LastChangeWhen)$(if ($a.LastChangedByName) { "  ·  $($a.LastChangedByName)" })"),@('Scope tags',$a.ScopeTags),@('Superseded by',$(if ([int]$a.SupersededByCount) { "$($a.SupersededByCount) app(s)" } else { '' })),@('Flags',$a.Flags)))
            )
            foreach ($g in $groups) { $c = New-Card $g[0]; [void]$c.Body.Children.Add((New-KvGrid $g[1] -KeyWidth 170)); [void]$grid.Children.Add($c.Border) }
            [void]$AppPanel.Children.Add($grid)
            $c = New-Card 'Notes as stored in Intune (raw JSON)'
            [void]$c.Body.Children.Add((New-Text -Text $(if ("$($a.RawNotes)") { $a.RawNotes } else { '(empty)' }) -Size 11.5 -Colour $script:C.Ink2 -Wrap $true -Mono)); [void]$AppPanel.Children.Add($c.Border)
        }
        'assignments' {
            $c = New-Card 'Current assignments' "$($a.AssignmentCount)"
            if ((AsArray $a.Assignments).Count -eq 0) { [void]$c.Body.Children.Add((New-Text -Text 'Not assigned to anything.' -Size 12.5 -Colour $script:C.Ink3)) }
            foreach ($s in (AsArray $a.Assignments)) { [void]$c.Body.Children.Add((New-AssignmentRow -S $s -Detail $true)) }
            [void]$AppPanel.Children.Add($c.Border)
            $ah = @($hist | Where-Object { $_.Kind -eq 'assign' })
            $c = New-Card 'Assignment history' "$($ah.Count)"; Add-Feed -Panel $c.Body -Entries $ah -InApp $true; [void]$AppPanel.Children.Add($c.Border)
        }
        'history' {
            $bar = New-Object Windows.Controls.WrapPanel; $bar.Margin = (Th 0 0 0 12)
            $kc = @{}; foreach ($e in $hist) { $k = Get-ChangeGroup $e.Kind; $kc[$k] = [int]$kc[$k] + 1 }
            [void]$bar.Children.Add((New-Text -Text 'Kind' -Size 12 -Colour $script:C.Ink3 -Margin (Th 0 0 8 0)))
            $cbK = New-Object Windows.Controls.ComboBox; $cbK.Margin = (Th 0 0 14 0)
            foreach ($k in $script:ChangeKinds.Keys) { if ($k -and -not $kc[$k]) { continue }; $it = New-Object Windows.Controls.ComboBoxItem; $it.Content = $(if ($k) { "$($script:ChangeKinds[$k]) ($($kc[$k]))" } else { "All ($($hist.Count))" }); $it.Tag = $k; [void]$cbK.Items.Add($it); if ($k -eq $script:HistFilter.Kind) { $cbK.SelectedItem = $it } }
            if (-not $cbK.SelectedItem) { $cbK.SelectedIndex = 0 }
            $cbK.Add_SelectionChanged({ param($s, $e) if ($s.SelectedItem) { $script:HistFilter.Kind = "$($s.SelectedItem.Tag)"; Build-AppPage } })
            [void]$bar.Children.Add($cbK)
            $ppl = @{}; foreach ($e in $hist) { if ("$($e.Who)") { $ppl["$($e.WhoText)"] = [int]$ppl["$($e.WhoText)"] + 1 } }
            [void]$bar.Children.Add((New-Text -Text 'By' -Size 12 -Colour $script:C.Ink3 -Margin (Th 0 0 8 0)))
            $cbW = New-Object Windows.Controls.ComboBox; $cbW.MinWidth = 200
            $it = New-Object Windows.Controls.ComboBoxItem; $it.Content = 'Everyone'; $it.Tag = ''; [void]$cbW.Items.Add($it); $cbW.SelectedIndex = 0
            foreach ($p in ($ppl.Keys | Sort-Object { -$ppl[$_] })) { $it = New-Object Windows.Controls.ComboBoxItem; $it.Content = "$p ($($ppl[$p]))"; $it.Tag = $p; [void]$cbW.Items.Add($it); if ($p -eq $script:HistFilter.Who) { $cbW.SelectedItem = $it } }
            $cbW.Add_SelectionChanged({ param($s, $e) if ($s.SelectedItem) { $script:HistFilter.Who = "$($s.SelectedItem.Tag)"; Build-AppPage } })
            [void]$bar.Children.Add($cbW)
            $shown = @($hist | Where-Object { (-not $script:HistFilter.Kind -or (Get-ChangeGroup $_.Kind) -eq $script:HistFilter.Kind) -and (-not $script:HistFilter.Who -or "$($_.WhoText)" -eq $script:HistFilter.Who) })
            [void]$bar.Children.Add((New-Text -Text "$($shown.Count) of $($hist.Count) changes  ·  newest first" -Size 12.5 -Colour $script:C.Ink3 -Margin (Th 16 0 0 0)))
            [void]$AppPanel.Children.Add($bar)
            $c = New-Card -NoTitle; Add-Feed -Panel $c.Body -Entries $shown -InApp $true; [void]$AppPanel.Children.Add($c.Border)
        }
    }
}

# --- activity -----------------------------------------------------------------------------------------------------
$script:Presets = [ordered]@{ '1'='Today'; '2'='Yesterday'; '7'='Last 7 days'; '30'='Last 30 days'; 'tm'='This month'; 'lm'='Last month'; '90'='Last 90 days'; 'ty'='This year'; '0'='All time'; 'c'='Custom range' }
function Get-ActivityRange {
    $p = "$($script:Act.Preset)"; $now = Get-Date; $from = $null; $to = $null
    switch ($p) {
        '1'  { $from = $now.Date }
        '2'  { $from = $now.Date.AddDays(-1); $to = $now.Date }
        'tm' { $from = Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0 -Millisecond 0 }
        'lm' { $from = (Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0 -Millisecond 0).AddMonths(-1); $to = Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0 -Millisecond 0 }
        'ty' { $from = Get-Date -Month 1 -Day 1 -Hour 0 -Minute 0 -Second 0 -Millisecond 0 }
        'c'  { if ($script:Act.From) { $from = ([datetime]$script:Act.From).Date }; if ($script:Act.To) { $to = ([datetime]$script:Act.To).Date.AddDays(1) } }
        '0'  { }
        default { $from = $now.AddDays(-[int]$p) }
    }
    return @{ From = $(if ($from) { $from.ToUniversalTime().ToString('s') } else { '' }); To = $(if ($to) { $to.ToUniversalTime().ToString('s') } else { '' }) }
}
# Filters the feed with the precomputed index (Build-FeedIndex): no regex, no per-entry string building.
# Also leaves the matching day labels in $script:ActDays, aligned with the result, for Add-Feed.
function Get-ActivityRows {
    $f = AsArray (Get-Feed); $n = $f.Count
    $r = Get-ActivityRange; $q = "$($script:Act.Q)".Trim().ToLowerInvariant()
    $from = "$($r.From)"; $to = "$($r.To)"; $kind = "$($script:Act.Kind)"; $who = "$($script:Act.Who)"
    $hay = $script:FeedHay; $grp = $script:FeedGroup; $day = $script:FeedDay; $when = $script:FeedWhen; $whoArr = $script:FeedWho; $minor = $script:FeedMinor
    $out = New-Object 'System.Collections.Generic.List[object]'; $days = New-Object 'System.Collections.Generic.List[string]'
    for ($i = 0; $i -lt $n; $i++) {
        if ($minor[$i]) { continue }
        if ($from -and $when[$i] -lt $from) { continue }
        if ($to -and $when[$i] -ge $to) { continue }
        if ($kind -and $grp[$i] -ne $kind) { continue }
        if ($who -and $whoArr[$i] -ne $who) { continue }
        if ($q -and $hay[$i].IndexOf($q) -lt 0) { continue }
        [void]$out.Add($f[$i]); [void]$days.Add($day[$i])
    }
    $script:ActDays = $days.ToArray()
    return ,$out.ToArray()
}
function New-ComboFrom { param($Map, [object[]]$Order, [string]$Selected, [scriptblock]$OnChange, [int]$MinWidth = 140)
    $cb = New-Object Windows.Controls.ComboBox; $cb.MinWidth = $MinWidth; $cb.Margin = (Th 0 0 14 0)
    foreach ($k in $Order) { $it = New-Object Windows.Controls.ComboBoxItem; $it.Content = "$($Map[$k])"; $it.Tag = "$k"; [void]$cb.Items.Add($it); if ("$k" -eq "$Selected") { $cb.SelectedItem = $it } }
    if (-not $cb.SelectedItem -and $cb.Items.Count) { $cb.SelectedIndex = 0 }
    $cb.Add_SelectionChanged($OnChange)
    return $cb
}
function Build-Activity {
    $ActBar.Children.Clear(); $ActList.Children.Clear()
    if ((AsArray $script:Apps).Count -eq 0) { [void]$ActList.Children.Add((New-Text -Text 'No data yet - click Sync.' -Colour $script:C.Ink3)); return }
    if ($null -eq $script:Feed) { Set-Status 'Translating change history...' -Pump; [void](Get-Feed -Progress { param($t, $p) Set-Status $t -Pump }) }
    [void]$ActBar.Children.Add((New-Text -Text 'Period' -Size 12 -Colour $script:C.Ink3 -Margin (Th 0 0 8 0)))
    [void]$ActBar.Children.Add((New-ComboFrom -Map $script:Presets -Order @($script:Presets.Keys) -Selected $script:Act.Preset -OnChange { param($s, $e) if ($s.SelectedItem) { $script:Act.Preset = "$($s.SelectedItem.Tag)"; $script:Act.Shown = 100; Build-Activity } }))
    if ($script:Act.Preset -eq 'c') {
        [void]$ActBar.Children.Add((New-Text -Text 'from' -Size 12 -Colour $script:C.Ink3 -Margin (Th 0 0 6 0)))
        $dpF = New-Object Windows.Controls.DatePicker; $dpF.SelectedDate = $script:Act.From; $dpF.Margin = (Th 0 0 10 0); $dpF.Add_SelectedDateChanged({ param($s, $e) $script:Act.From = $s.SelectedDate; Update-ActivityList }); [void]$ActBar.Children.Add($dpF)
        [void]$ActBar.Children.Add((New-Text -Text 'to' -Size 12 -Colour $script:C.Ink3 -Margin (Th 0 0 6 0)))
        $dpT = New-Object Windows.Controls.DatePicker; $dpT.SelectedDate = $script:Act.To; $dpT.Margin = (Th 0 0 14 0); $dpT.Add_SelectedDateChanged({ param($s, $e) $script:Act.To = $s.SelectedDate; Update-ActivityList }); [void]$ActBar.Children.Add($dpT)
    }
    [void]$ActBar.Children.Add((New-Text -Text 'Kind' -Size 12 -Colour $script:C.Ink3 -Margin (Th 0 0 8 0)))
    [void]$ActBar.Children.Add((New-ComboFrom -Map $script:ChangeKinds -Order @($script:ChangeKinds.Keys) -Selected $script:Act.Kind -OnChange { param($s, $e) if ($s.SelectedItem) { $script:Act.Kind = "$($s.SelectedItem.Tag)"; $script:Act.Shown = 100; Update-ActivityList } }))
    $ppl = $script:FeedPeople
    $order = @('') + @($ppl.Keys | Sort-Object { -$ppl[$_] }); $map = @{ '' = 'Everyone' }; foreach ($k in $ppl.Keys) { $map[$k] = $k }
    [void]$ActBar.Children.Add((New-Text -Text 'By' -Size 12 -Colour $script:C.Ink3 -Margin (Th 0 0 8 0)))
    [void]$ActBar.Children.Add((New-ComboFrom -Map $map -Order $order -Selected $script:Act.Who -MinWidth 190 -OnChange { param($s, $e) if ($s.SelectedItem) { $script:Act.Who = "$($s.SelectedItem.Tag)"; $script:Act.Shown = 100; Update-ActivityList } }))
    $sg = New-Object Windows.Controls.Grid; $sg.Width = 200
    $tb = New-Object Windows.Controls.TextBox; $tb.Text = $script:Act.Q; $tb.ToolTip = 'App, group, value, person'
    $ph = New-Text -Text 'Search changes' -Size 13 -Colour $script:C.Ink3 -Margin (Th 11 0 0 0); $ph.IsHitTestVisible = $false; $ph.Visibility = $(if ($tb.Text) { 'Collapsed' } else { 'Visible' })
    # typing only restarts a short timer; the list is rebuilt once the typing pauses, not on every keystroke
    $tb.Tag = $ph; $tb.Add_TextChanged({ param($s, $e) $s.Tag.Visibility = $(if ($s.Text) { 'Collapsed' } else { 'Visible' }); $script:Act.Q = $s.Text; $script:Act.Shown = 100; $script:ActTimer.Stop(); $script:ActTimer.Start() })
    [void]$sg.Children.Add($tb); [void]$sg.Children.Add($ph); [void]$ActBar.Children.Add($sg)
    $script:ActCountText = New-Text -Text '' -Size 12.5 -Colour $script:C.Ink3 -Margin (Th 14 0 0 0); [void]$ActBar.Children.Add($script:ActCountText)
    Update-ActivityList
}
$script:ActTimer = New-Object Windows.Threading.DispatcherTimer; $script:ActTimer.Interval = [TimeSpan]::FromMilliseconds(350)
$script:ActTimer.Add_Tick({ $script:ActTimer.Stop(); Update-ActivityList })
function Update-ActivityList {
    $ActList.Children.Clear()
    $rows = Get-ActivityRows
    Add-Feed -Panel $ActList -Entries $rows -Days $script:ActDays -InApp $false -Max $script:Act.Shown -Async
    $n = (AsArray $rows).Count
    $script:ActCountText.Text = "$($n.ToString('N0')) change$(if ($n -ne 1) { 's' })"
    if ($script:CurrentPage -eq 'activity') { Set-Status "$($n.ToString('N0')) changes in this selection.  Export writes exactly this list." }
}

# --- people ------------------------------------------------------------------------------------------------------------
function Build-People {
    $stats = @{}
    foreach ($e in (AsArray (Get-Feed))) {
        if (-not "$($e.Who)") { continue }
        $k = "$($e.WhoText)"; if (-not $stats.ContainsKey($k)) { $stats[$k] = @{ Name = $k; Account = "$($e.Who)"; N = 0; Apps = @{}; Created = @{}; Kinds = @{}; Last = '' } }
        $s = $stats[$k]; $s.N++; $s.Apps["$($e.AppId)"] = 1; $g = Get-ChangeGroup $e.Kind; $s.Kinds[$g] = [int]$s.Kinds[$g] + 1; if ("$($e.When)" -gt $s.Last) { $s.Last = "$($e.When)" }
        if ($e.Kind -eq 'create') { $s.Created["$($e.AppId)"] = "$($e.When)" }     # apps this person created (also ones deleted since)
    }
    $rows = @(foreach ($s in ($stats.Values | Sort-Object { -$_.N })) {
        $top = ($s.Kinds.Keys | Sort-Object { -$s.Kinds[$_] } | Select-Object -First 3 | ForEach-Object { "$($script:ChangeKinds[$_]) $($s.Kinds[$_])" }) -join '  ·  '
        [pscustomobject]@{ Person = $s.Name; Account = $(if ($s.Account -ne $s.Name) { $s.Account } else { '' }); Created = $s.Created.Count; Changes = $s.N; Apps = $s.Apps.Count; Mostly = $top; LastActive = (Format-When $s.Last) }
    })
    $script:PeopleStats = $stats
    if ($Grid3.Columns.Count -eq 0) {
        foreach ($c in @(@('Person','Person',1.7,150),@('Account','Sign-in name',1.6,120),@('Created','Apps created',0.7,112),@('Changes','Changes',0.6,90),@('Apps','Apps touched',0.7,110),@('Mostly','Mostly',2.6,160),@('LastActive','Last active',1.1,130))) {
            $col = New-Object Windows.Controls.DataGridTextColumn; $col.Header = (New-Text -Text $c[1] -Size 11.5 -Colour $script:C.Ink3 -Weight 'SemiBold'); $col.Binding = New-Object Windows.Data.Binding($c[0]); $col.SortMemberPath = $c[0]; $col.Width = New-Object Windows.Controls.DataGridLength($c[2], [Windows.Controls.DataGridLengthUnitType]::Star); $col.MinWidth = $c[3]
            $es = New-Object Windows.Style([Windows.Controls.TextBlock]); $st = New-Object Windows.Setter; $st.Property = [Windows.Controls.TextBlock]::TextTrimmingProperty; $st.Value = [Windows.TextTrimming]::CharacterEllipsis; $es.Setters.Add($st); $col.ElementStyle = $es
            $Grid3.Columns.Add($col)
        }
        $Grid3.Add_PreviewMouseLeftButtonUp({ param($s, $e) $row = Find-Row $e.OriginalSource ([Windows.Controls.DataGridRow]); if ($row) { $script:Act.Who = "$($row.Item.Person)"; $script:Act.Preset = '0'; $script:Act.Shown = 100; Show-Page 'activity' } })
    }
    $Grid3.ItemsSource = $rows; $script:PeopleRows = $rows
    $open = (Get-UnresolvedPeople).Count
    $PeopleHint.Text = $(if ($open) { "$open sign-in name$(if ($open -ne 1) { 's' }) still to fill in Data\people.json" } else { 'every sign-in name has a display name' })
    Set-Status "$($rows.Count) people and accounts have changed apps. Click one to see their activity."
}
# People workbook: the table as shown + one row per app a person created (productivity view, creations only)
function Export-PeopleToExcel {
    param([string]$Path)
    if (-not $script:PeopleStats) { Build-People }
    $byId = @{}; foreach ($a in (AsArray $script:Apps)) { $byId[$a.Id] = $a }
    $created = @(foreach ($s in ($script:PeopleStats.Values | Sort-Object { -$_.Created.Count })) {
        foreach ($id in ($s.Created.Keys | Sort-Object { $s.Created[$_] } -Descending)) {
            $a = $byId[$id]
            [pscustomobject]@{ Person = $s.Name; Account = $s.Account; App = $(if ($a) { $a.DisplayName } else { '(deleted since)' }); Version = $(if ($a) { "$($a.DisplayVersion)" } else { '' })
                               CreatedOn = (Format-When $s.Created[$id]); LifecycleNow = $(if ($a) { $a.Lifecycle } else { 'deleted' }); Kind = $(if ($a) { $a.Kind } else { '' }); AppId = $id }
        }
    })
    $summary = @($script:PeopleRows | Select-Object Person, Account, Created, Changes, Apps, Mostly, LastActive)
    return (New-XlsxWorkbook -Path $Path -Sheets @(
        @{ Name = 'People';       Rows = $summary; Columns = @('Person','Account','Created','Changes','Apps','Mostly','LastActive') }
        @{ Name = 'Apps created'; Rows = $created; Columns = @('Person','Account','App','Version','CreatedOn','LifecycleNow','Kind','AppId') } ))
}
# people.json entries that are still empty (key = lower-case sign-in name)
function Get-UnresolvedPeople {
    $map = @{}
    if (-not (Test-Path $script:PeoplePath)) { return $map }
    try { $j = Get-Content -LiteralPath $script:PeoplePath -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { if (-not "$($p.Value)".Trim()) { $map[$p.Name.ToLower()] = '' } } } catch {}
    return $map
}

# --- export / events ---------------------------------------------------------------------------------------------------
function Export-Current {
    try {
        switch ($script:CurrentPage) {
            'activity' { $rows = Get-ActivityRows; if ((AsArray $rows).Count -eq 0) { Set-Status 'Nothing to export - no changes match.'; return }; Set-Status "Building the workbook for $((AsArray $rows).Count) change(s)..." -Pump; $path = Join-Path $script:DataDir ('IntuneAppMonitor-Activity-{0}.xlsx' -f (Get-Date -Format 'yyyyMMdd-HHmm')); Export-ActivityToExcel -Entries $rows -Path $path | Out-Null }
            'app'      { $a = $script:CurrentApp; Set-Status "Building the report for $($a.DisplayName)..." -Pump; $safe = ($a.DisplayName -replace '[\\/:*?"<>|]', '_'); $path = Join-Path $script:DataDir ('IntuneAppMonitor-{0}-{1}.xlsx' -f $safe, (Get-Date -Format 'yyyyMMdd-HHmm')); Export-AppReport -App $a -Path $path | Out-Null }
            'people'   { $path = Join-Path $script:DataDir ('IntuneAppMonitor-People-{0}.xlsx' -f (Get-Date -Format 'yyyyMMdd-HHmm')); Set-Status 'Building the people workbook...' -Pump; Export-PeopleToExcel -Path $path | Out-Null }
            default    { $rows = $(if ($script:CurrentPage -eq 'apps') { Get-VisibleRows } else { AsArray $script:Apps }); if ((AsArray $rows).Count -eq 0) { Set-Status 'Nothing to export - no apps match.'; return }; Set-Status "Building the workbook for $((AsArray $rows).Count) app(s)..." -Pump; $path = Join-Path $script:DataDir ('IntuneAppMonitor-Apps-{0}.xlsx' -f (Get-Date -Format 'yyyyMMdd-HHmm')); Export-ToExcel -Rows $rows -Path $path | Out-Null }
        }
        Set-Status "Exported to $(Split-Path -Leaf $path)"
        Start-Process explorer.exe "/select,`"$path`""
    } catch { Set-Status "Export failed: $($_.Exception.Message)" }
}
function Update-Subtitle {
    $n = (AsArray $script:Apps).Count
    $newest = Get-ChildItem -LiteralPath $script:SnapDir -Filter 'apps-*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    $BrandSub.Text = "$n apps" + $(if ($newest) { "  ·  synced $($newest.LastWriteTime.ToString('dd MMM HH:mm'))" } else { '' })
    $cv = $script:Coverage
    $Foot.Text = $(if ($script:SignedInAs) { "Signed in as $($script:SignedInAs)`n" } else { '' }) + $(if ($cv -and $cv.From) { "History on record since $($cv.From.ToString('dd MMM yyyy'))`n$($cv.Events.ToString('N0')) changes  ·  $($cv.Groups) groups named$(if ($cv.People) { "  ·  $($cv.People) people" })`nIntune keeps audit about a year; this tool keeps everything it has read." } else { 'No history yet - click Sync.' }) + $(if ($script:BuildStamp) { "`nBuild $($script:BuildStamp)" } else { '' })
}
function Start-Sync {
    $BtnSync.IsEnabled = $false; $BtnCancel.IsEnabled = $true
    try {
        $ok = Invoke-AppSync -Progress { param($t, $p) Set-Status $t $p -Pump }
        if ($ok) { Update-Subtitle; if ($script:CurrentPage -eq 'app') { $script:CurrentApp = Find-App $script:CurrentApp.Id; if (-not $script:CurrentApp) { $script:CurrentPage = 'apps' } }; Show-Page $script:CurrentPage; if ($script:CurrentPage -eq 'app') { Build-AppPage }; Set-Status "Sync complete - $((AsArray $script:Apps).Count) apps." 100 } else { $Bar.Value = 0 }
    } catch { Set-Status "Sync failed: $($_.Exception.Message)" 0; Write-Log "Sync failed: $($_.Exception.Message)" Error }
    finally { $BtnSync.IsEnabled = $true; $BtnCancel.IsEnabled = $false }
}
$BtnSync.Add_Click({ Start-Sync })
$BtnCancel.Add_Click({ $script:CancelRequested = $true; Set-Status 'Stopping after the current request - anything already fetched is kept...' })
$BtnFolder.Add_Click({ Start-Process explorer.exe $script:DataDir })
$BtnExport.Add_Click({ Export-Current })
$BtnCols.Add_Click({ Open-ColumnChooser })
$BtnColsReset.Add_Click({ foreach ($c in $script:Cols) { $script:ColState[$c.Key] = 'auto' }; Update-ColumnLayout; $ColPop.IsOpen = $false })
$NavOverview.Add_Checked({ if (-not $script:NavSuppress) { Show-Page 'overview' } })
$NavApps.Add_Checked({     if (-not $script:NavSuppress) { Show-Page 'apps' } })
$NavActivity.Add_Checked({ if (-not $script:NavSuppress) { Show-Page 'activity' } })
$NavPeople.Add_Checked({   if (-not $script:NavSuppress) { Show-Page 'people' } })
$NavInsights.Add_Checked({ if (-not $script:NavSuppress) { Show-Page 'insights' } })
$script:AppsTimer = New-Object Windows.Threading.DispatcherTimer; $script:AppsTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$script:AppsTimer.Add_Tick({ $script:AppsTimer.Stop(); if ($script:CurrentPage -ne 'apps') { Show-Page 'apps' } else { Update-Grid } })
$GlobalSearch.Add_TextChanged({ if ($script:SearchSuppress) { return }; $script:AppsQuery = $GlobalSearch.Text; $script:SearchSuppress = $true; $AppsSearch.Text = $GlobalSearch.Text; $script:SearchSuppress = $false; $script:AppsTimer.Stop(); $script:AppsTimer.Start() })
$AppsSearch.Add_TextChanged({   if ($script:SearchSuppress) { return }; $script:AppsQuery = $AppsSearch.Text;   $script:SearchSuppress = $true; $GlobalSearch.Text = $AppsSearch.Text; $script:SearchSuppress = $false; $script:AppsTimer.Stop(); $script:AppsTimer.Start() })
$Grid1.Add_PreviewMouseLeftButtonUp({ param($s, $e) if ($script:GridSuppress) { return }; $row = Find-Row $e.OriginalSource ([Windows.Controls.DataGridRow]); if ($row -and $row.Item) { Show-App $row.Item } })
$Grid1.Add_SizeChanged({ Update-ColumnLayout })
$PopSearch.Add_TextChanged({ $q = "$($PopSearch.Text)".Trim().ToLower(); foreach ($cb in $PopList.Children) { if ($cb -is [Windows.Controls.CheckBox]) { $cb.Visibility = $(if (-not $q -or "$($cb.Content)".ToLower().Contains($q)) { 'Visible' } else { 'Collapsed' }) } } })
$BtnPopAll.Add_Click({  foreach ($cb in $PopList.Children) { if ($cb -is [Windows.Controls.CheckBox] -and $cb.Visibility -eq 'Visible') { $cb.IsChecked = $true  } } })
$BtnPopNone.Add_Click({ foreach ($cb in $PopList.Children) { if ($cb -is [Windows.Controls.CheckBox] -and $cb.Visibility -eq 'Visible') { $cb.IsChecked = $false } } })
$BtnPopOk.Add_Click({
    $key = "$($script:PopCol)"; $sel = New-Object 'System.Collections.Generic.HashSet[string]'; $total = 0
    foreach ($cb in $PopList.Children) { if ($cb -isnot [Windows.Controls.CheckBox]) { continue }; $total++; if ($cb.IsChecked) { [void]$sel.Add("$($cb.Tag)") } }
    if ($sel.Count -eq $total) { $script:Filters.Remove($key) } else { $script:Filters[$key] = $sel }
    Set-FilterIndicator -Key $key; $Pop.IsOpen = $false; Update-Grid
})

# --- sign-in gate -----------------------------------------------------------------------------------------------
# The record in Data\ is readable by the tool only after an Intune sign-in AND a successful authorised read, so
# someone without Intune access cannot browse past data. Always on in the compiled build; from source it is
# skipped only for the offline maintainer modes (-SelfTest / -Screenshot).
function Invoke-SignInGate {
    param([switch]$Quiet)
    $title = 'Intune App Monitor'
    if (-not (Connect-Intune -TenantId $cfg.TenantId -ModulePath $cfg.ModulePath -CacheRoot $script:CacheDir)) {
        if (-not $Quiet) { [void][Windows.MessageBox]::Show("Sign in to Intune is required to open $title.`n`n$($StatusText.Text)".TrimEnd(), $title, 'OK', 'Warning') }
        return $false
    }
    $chk = Test-IntuneAccess
    if (-not $chk.Ok) {
        if (-not $Quiet) { [void][Windows.MessageBox]::Show("Signed in as $($chk.Who), but $($chk.Why)`n`nAn Intune role that can read apps (e.g. Read Only Operator) is required to open $title.", $title, 'OK', 'Warning') }
        return $false
    }
    $script:Connected = $true; $script:SignedInAs = $chk.Who
    Write-Log "Signed in as $($chk.Who)." Success
    return $true
}
# The window goes on screen FIRST - loading the record takes half a minute and an exe with no window looks dead.
# Sign-in and every loading phase report into the status bar of the visible window.
$script:EarlyShow = -not ($SelfTest -or $Screenshot)
if ($script:EarlyShow) {
    if ($script:StartMaximized) { $win.WindowState = 'Maximized' }
    $BrandSub.Text = 'starting...'; $Foot.Text = ''
    [void]$OverviewPanel.Children.Add((New-Text -Text 'Signing in to Intune...' -Size 14 -Colour $script:C.Ink3 -Margin (Th 4 20 0 0)))
    $win.Show()
    Set-Status 'Sign in to Intune to continue...' 3 -Pump
}
if ($script:PackedLibs -or -not ($SelfTest -or $Screenshot)) { if (-not (Invoke-SignInGate)) { if ($script:EarlyShow) { $win.Close() }; return } }

# --- start ----------------------------------------------------------------------------------------------------
Build-Columns
if ($script:EarlyShow) { $OverviewPanel.Children.Clear(); [void]$OverviewPanel.Children.Add((New-Text -Text 'Loading the record...' -Size 14 -Colour $script:C.Ink3 -Margin (Th 4 20 0 0))) }
Set-Status 'Loading the last app list...' 8 -Pump
$prev = Get-PreviousSnapshot -SnapshotDir $script:SnapDir
if ($prev) {
    Set-Status "Loading the change record for $((AsArray $prev).Count) apps..." 25 -Pump
    $startCache = Get-AuditCache -Path $script:AuditPath
    if ($startCache.Migrated) { Set-Status 'Upgrading the record format (one time)...' 40 -Pump; [void](Repair-DetachedDetails -Cache $startCache -KnownAppIds @($prev | ForEach-Object { $_.Id })); Save-AuditCache -Cache $startCache -Path $script:AuditPath }
    Set-Status 'Resolving names...' 50 -Pump
    [void](Update-PeopleFile -Path $script:PeoplePath -Cache $startCache)
    $script:UserMap = Build-UserMap -Cache $startCache -PeoplePath $script:PeoplePath
    Set-Status 'Classifying apps (lifecycle, kind, created via)...' 60 -Pump
    Initialize-AppView -Apps (Add-AuditToApps -Apps $prev -Cache $startCache)
    $script:GroupMap = Build-GroupMap -Cache $startCache -Apps $script:Apps
    $script:Coverage = Get-HistoryCoverage -Cache $startCache
    Update-Subtitle
    Set-Status 'Translating change history...' 80 -Pump
    [void](Get-Feed -Progress { param($t, $p) Set-Status $t -Pump })
    Set-Status "$((AsArray $script:Apps).Count) apps.  $(if ($startCache.Legacy) { 'History is in the old format - click Sync once to rebuild it with values and names.' } else { 'Click Sync to refresh.' })" 0
} else { $BrandSub.Text = 'no data yet'; $Foot.Text = 'Click Sync to pull your apps from Intune.'; Set-Status 'Click Sync to pull your apps from Intune.' 0 }

$startPage = $(if ($Page) { $Page.ToLower() } else { 'overview' })
if ($SelectApp) { $app = (AsArray $script:Apps) | Where-Object { $_.DisplayName -like $SelectApp } | Sort-Object { -(AsArray $_.AuditEvents).Count } | Select-Object -First 1; if ($app) { Show-App $app $(if ($Tab) { $Tab.ToLower() } else { 'overview' }) } else { Show-Page $startPage } }
else { Show-Page $startPage }

if ($SelfTest) {
    $script:fail = 0
    function Check { param([string]$Name, [scriptblock]$Do) try { $r = & $Do; Write-Host ("  PASS  {0}{1}" -f $Name, $(if ($r) { " -> $r" } else { '' })) -ForegroundColor Green } catch { $script:fail++; Write-Host ("  FAIL  {0}`n        {1}`n        {2}" -f $Name, $_.Exception.Message, $_.ScriptStackTrace) -ForegroundColor Red } }
    Write-Host "`nSELF TEST" -ForegroundColor Cyan
    Check 'sign-in gate: refuses without sign-in, refuses without Intune access, admits with both' {
        $r = @()
        function Connect-Intune { param($TenantId, $ModulePath, $CacheRoot) return $false }
        $r += (Invoke-SignInGate -Quiet)
        function Connect-Intune { param($TenantId, $ModulePath, $CacheRoot) return $true }
        function Test-IntuneAccess { return @{ Ok = $false; Who = 'nobody@man.eu'; Why = 'this account has no Intune role that can read apps (403).' } }
        $r += (Invoke-SignInGate -Quiet)
        function Test-IntuneAccess { return @{ Ok = $true; Who = 'tester@man.eu'; Why = '' } }
        $r += (Invoke-SignInGate -Quiet)
        $script:Connected = $false; $script:SignedInAs = ''
        if ("$($r -join ',')" -ne 'False,False,True') { throw "gate returned $($r -join ',')" }
        'no sign-in -> closed · signed in without role -> closed · signed in with role -> open'
    }
    Check 'overview renders' { Show-Page 'overview'; if ($OverviewPanel.Children.Count -lt 5) { throw "only $($OverviewPanel.Children.Count) blocks" }; "$($OverviewPanel.Children.Count) blocks" }
    Check 'apps grid: columns, measured header widths, rows' { Show-Page 'apps'; $mins = ($script:Cols | ForEach-Object { "$($_.Title) $($_.Min)" }) -join ', '; "$($Grid1.Columns.Count) cols; $((AsArray $Grid1.ItemsSource).Count) rows; min px: $mins" }
    Check 'responsive columns: what fits at 1040 px / 1290 px' {
        $out = foreach ($w in 1040, 1290) { $used = 0; $vis = @(); foreach ($c in $script:Cols) { if (($used + $c.Min) -le ($w - 14)) { $vis += $c.Title; $used += $c.Min } }; "$w px -> $($vis.Count) of $($script:Cols.Count) ($used px used)" }
        $out -join ' · '
    }
    foreach ($k in @('Lifecycle','Kind','CreatedVia','CreatedByName','DisplayName','LastChangedByName')) { Check "filter dropdown '$k'" { $script:PopCol = $k; Build-PopupList -Key $k; "$($PopList.Children.Count) values" } }
    Check 'lifecycle tile filters the grid' { Set-LifeFilter 'RETIRED'; Update-Grid; $n = (AsArray $Grid1.ItemsSource).Count; $script:Filters = @{}; Update-Grid; "$n retired, back to $((AsArray $Grid1.ItemsSource).Count)" }
    Check 'single-row filter (PreRollout) - the old crash' { Set-LifeFilter 'PreRollout'; Update-Grid; $n = (AsArray $Grid1.ItemsSource).Count; $script:Filters = @{}; Update-Grid; "$n row(s)" }
    Check 'search' { $script:AppsQuery = 'chrome'; $n = (AsArray (Get-VisibleRows)).Count; $script:AppsQuery = ''; "$n matches" }
    Check 'app page: all four tabs for the busiest app' {
        $busy = (AsArray $script:Apps) | Sort-Object { -(AsArray $_.AuditEvents).Count } | Select-Object -First 1
        $n = @{}; foreach ($t in 'overview','settings','assignments','history') { Show-App $busy $t; $n[$t] = $AppPanel.Children.Count }
        "$($busy.DisplayName): overview $($n.overview) / settings $($n.settings) / assignments $($n.assignments) / history $($n.history) blocks, $((Get-AppHistory $busy).Count) entries"
    }
    Check 'app page for every lifecycle stage' { $c = 0; foreach ($st in $script:LifeOrder) { $a = (AsArray $script:Apps) | Where-Object { $_.Lifecycle -eq $st } | Select-Object -First 1; if ($a) { Show-App $a 'overview'; $c++ } }; "$c stages" }
    Check 'activity: presets, kind, person, search, custom range' {
        Show-Page 'activity'; $script:Act.Preset = '0'; Build-Activity; $all = (AsArray (Get-ActivityRows)).Count
        $script:Act.Kind = 'assign'; $asg = (AsArray (Get-ActivityRows)).Count; $script:Act.Kind = ''
        $script:Act.Q = 'autocad'; $q = (AsArray (Get-ActivityRows)).Count; $script:Act.Q = ''
        $script:Act.Preset = 'c'; $script:Act.From = (Get-Date).AddDays(-30); $script:Act.To = Get-Date; Build-Activity; $c = (AsArray (Get-ActivityRows)).Count; $ctl = $ActBar.Children.Count
        $script:Act.Preset = '30'; $script:Act.From = $null; $script:Act.To = $null; Build-Activity
        if ($all -eq 0) { throw 'feed empty' }; if ($asg -gt $all) { throw 'kind filter did not narrow' }
        "all $all · assignments $asg · 'autocad' $q · custom 30d $c · $ctl toolbar controls with date pickers"
    }
    Check 'activity speed: open, all time, one search rebuild, change kind (each under 2 s; typing is debounced to one rebuild)' {
        $t = @{}; $sw = [Diagnostics.Stopwatch]::new()
        $script:Act = @{ Preset = '30'; From = $null; To = $null; Kind = ''; Who = ''; Q = ''; Shown = 100 }
        $sw.Restart(); Show-Page 'activity'; $t['open 30d'] = $sw.Elapsed.TotalSeconds
        $sw.Restart(); $script:Act.Preset = '0'; Build-Activity; $t['all time'] = $sw.Elapsed.TotalSeconds
        $sw.Restart(); $script:Act.Q = 'a'; Update-ActivityList; $t['search a (broad)'] = $sw.Elapsed.TotalSeconds
        $sw.Restart(); $script:Act.Q = 'autocad'; Update-ActivityList; $t['search autocad'] = $sw.Elapsed.TotalSeconds
        $sw.Restart(); $script:Act.Q = ''; $script:Act.Kind = 'assign'; Update-ActivityList; $t['kind'] = $sw.Elapsed.TotalSeconds
        $sw.Restart(); $rows = Get-ActivityRows; $t['filter only'] = $sw.Elapsed.TotalSeconds
        $sw.Restart(); $ActList.Children.Clear(); Add-Feed -Panel $ActList -Entries $rows -Days $script:ActDays -InApp $false -Max 100; $t['render 100'] = $sw.Elapsed.TotalSeconds
        $script:Act = @{ Preset = '30'; From = $null; To = $null; Kind = ''; Who = ''; Q = ''; Shown = 100 }
        $slow = @($t.Keys | Where-Object { $t[$_] -gt 2 })
        $txt = ($t.Keys | ForEach-Object { '{0} {1:N1}s' -f $_, $t[$_] }) -join ' · '
        if ($slow.Count) { throw "too slow: $txt" }
        $txt
    }
    Check 'people' { Show-Page 'people'; $u = Get-UnresolvedPeople; $ok = $(if ($u.Count) { $PeopleHint.Text -match "^$($u.Count) sign-in" } else { $PeopleHint.Text -match '^every' }); if (-not $ok) { throw "hint says '$($PeopleHint.Text)' for $($u.Count) unnamed" }; "$((AsArray $Grid3.ItemsSource).Count) people, $($Grid3.Columns.Count) cols, $($u.Count) unnamed; hint '$($PeopleHint.Text)'" }
    Check 'people: apps created per person + export with the Apps created sheet' {
        $rows = AsArray $script:PeopleRows; $sum = ($rows | Measure-Object Created -Sum).Sum
        $feedCreates = @((AsArray (Get-Feed)) | Where-Object { $_.Kind -eq 'create' -and "$($_.Who)" }).Count
        if ($sum -ne $feedCreates) { throw "column sums to $sum but the record has $feedCreates creations" }
        $p = Join-Path $env:TEMP 'selftest-people.xlsx'; Export-PeopleToExcel -Path $p | Out-Null
        $top = $rows | Sort-Object Created -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Person) $($_.Created)" }
        "$sum apps created on record; top: $($top -join ', ') -> $([int]((Get-Item $p).Length/1KB)) KB"
    }
    Check 'people.json writer fills only empty entries and keeps the rest' {
        $tmp = Join-Path $env:TEMP 'selftest-people.json'; [IO.File]::WriteAllText($tmp, '{ "x1@azure.man": "", "x2@azure.man": "Kept Name" }', (New-Object Text.UTF8Encoding($false)))
        $n1 = Set-PeopleNames -Path $tmp -Names @{ 'x1@azure.man' = 'Test Person'; 'x2@azure.man' = 'Should Not Win' }; $n2 = Set-PeopleNames -Path $tmp -Names @{ 'x1@azure.man' = 'Other Name' }
        $j = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json; Remove-Item $tmp -Force
        if ($n1 -ne 1 -or $n2 -ne 0 -or $j.'x1@azure.man' -ne 'Test Person' -or $j.'x2@azure.man' -ne 'Kept Name') { throw "filled $n1/$n2, values '$($j.'x1@azure.man')' / '$($j.'x2@azure.man')'" }
        'empty entry filled once, existing name never overwritten'
    }
    Check 'insights' { Show-Page 'insights'; $ins = Get-Insights; $cards = 0; foreach ($col in $InsightsPanel.Children[0].Children) { $cards += $col.Children.Count }; if ($cards -ne $ins.Count) { throw "$cards cards for $($ins.Count) checks" }; "$cards cards: " + (($ins | ForEach-Object { "$($_.Title) $($_.Items.Count)" }) -join ' · ') }
    Check 'excel: apps export' { Set-LifeFilter 'RETIRED'; $rows = Get-VisibleRows; $script:Filters = @{}; $p = Join-Path $env:TEMP 'selftest-apps.xlsx'; Export-ToExcel -Rows $rows -Path $p | Out-Null; "$((AsArray $rows).Count) apps -> $([int]((Get-Item $p).Length/1KB)) KB" }
    Check 'excel: activity export' { $script:Act.Preset = '30'; $rows = Get-ActivityRows; $p = Join-Path $env:TEMP 'selftest-activity.xlsx'; Export-ActivityToExcel -Entries $rows -Path $p | Out-Null; "$((AsArray $rows).Count) changes -> $([int]((Get-Item $p).Length/1KB)) KB" }
    Check 'excel: app report' { $busy = (AsArray $script:Apps) | Sort-Object { -(AsArray $_.AuditEvents).Count } | Select-Object -First 1; $p = Join-Path $env:TEMP 'selftest-app.xlsx'; Export-AppReport -App $busy -Path $p | Out-Null; "$($busy.DisplayName) -> $([int]((Get-Item $p).Length/1KB)) KB" }
    Check 'translator: structured audit events -> sentences -> pills' {
        $mk = { param($when, $who, $op, $act, $changes) [pscustomobject]@{ When = $when; Who = $who; WhoId = ''; Operation = $op; What = $act; Changes = @($changes | ForEach-Object { [pscustomobject]@{ N = $_[0]; O = $_[1]; V = $_[2] } }) } }
        $app = [pscustomobject]@{ Id = 'x'; DisplayName = 'Demo App'; NoteEvents = @(); AuditEvents = @(
            (& $mk '2026-09-10T14:23:05Z' 'gurram.balaji-ext@man.eu' 'Patch' 'Patch MobileApp' @(@('DisplayVersion','1.0','1.1'), @('Notes','{"notes":"x","lifecycle":"SAT","status":"OK"}','{"notes":"x","lifecycle":"LIVE","status":"OK"}'), @('$Collection.Rules.KeyPath[0]','HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\Demo',''), @('$Collection.Rules.RuleType[0]','Detection',''))),
            (& $mk '2026-09-09T09:00:00Z' 'M365EndpointAutomation' 'Create' 'Create MobileAppAssignment' @(@('Intent','','Required'), @('Target.Type','','GroupAssignmentTarget'), @('Target.GroupId','','11111111-1111-1111-1111-111111111111'))),
            (& $mk '2026-09-08T08:00:00Z' 'vaibhav.vinchurkar-ext@man.eu' 'Create' 'Create MobileAppRelationship' @(@('SupersedenceType','','Update'), @('SourceDisplayName','','Demo App'), @('SourceDisplayVersion','','1.1'), @('TargetDisplayName','','Demo App'), @('TargetDisplayVersion','','1.0'))),
            [pscustomobject]@{ When = '2026-09-06T08:00:00Z'; Who = 'bn220@azure.man'; WhoId = 'u-1'; Operation = 'Patch'; What = 'Patch MobileApp'; Changes = 'InstallCommandLine Notes DeviceManagementAPIVersion:  -> x y z' } ) }
        $keep = $script:UserMap; $script:UserMap = @{ 'u-1' = 'Service Account Packaging' }
        $h = AsArray (Get-ChangeHistory -App $app -ChangeLog @() -GroupMap @{ '11111111-1111-1111-1111-111111111111' = 'MDM_MN_SWW_Demo_UAT' })
        $script:UserMap = $keep
        $all = ($h | ForEach-Object { "$($_.Title) | $($_.Lines -join ' ; ') | $($_.WhoText)" }) -join "`n"
        foreach ($must in @('Version: 1.0  ->  1.1', 'Lifecycle: SAT  ->  LIVE', 'Required  ->  group MDM_MN_SWW_Demo_UAT', 'this app supersedes Demo App 1.0 (update)', 'Fields touched: Install command, Notes', 'Service Account Packaging')) { if (-not $all.Contains($must)) { throw "missing '$must' in:`n$all" } }
        if ($all.Contains('Detection rule 1 removed')) { throw 're-saved collection shown as a change' }
        $pills = 0; foreach ($e in $h) { $row = New-HistoryRow -Entry ([pscustomobject]@{ When = $e.When; Kind = $e.Kind; Title = $e.Title; Lines = $e.Lines; WhoText = $e.WhoText; Who = $e.Who; App = 'Demo App'; AppId = 'x'; Legacy = $e.Legacy }) -InApp $false; foreach ($l in (AsArray $e.Lines)) { $wp = New-ChangeLine -Line $l -Removed $false; $pills += @($wp.Children | Where-Object { $_ -is [Windows.Controls.Border] }).Count } }
        if ($pills -lt 4) { throw "only $pills pills rendered" }
        "$($h.Count) entries, sentences ok, $pills old/new pills"
    }
    Write-Host ("`n{0}" -f $(if ($script:fail) { "$($script:fail) CHECK(S) FAILED" } else { 'ALL CHECKS PASSED' })) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
    return
}

# Renders the window off-screen to PNG for layout review: -Screenshot out.png [-Page apps] [-SelectApp 'Revit*' [-Tab history]]
if ($Screenshot) {
    $win.WindowState = 'Normal'; $win.Width = $wa.Width; $win.Height = $wa.Height; $win.Left = -12000
    $win.Show()
    $pump = { for ($i = 0; $i -lt 8; $i++) { $f = New-Object Windows.Threading.DispatcherFrame; [Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ContextIdle, [action]{ $f.Continue = $false }) | Out-Null; [Windows.Threading.Dispatcher]::PushFrame($f) } }
    & $pump; Update-ColumnLayout; & $pump
    $w = [int]$win.ActualWidth; $h = [int]$win.ActualHeight
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($win)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Open($Screenshot, [IO.FileMode]::Create)
    try { $enc.Save($fs) } finally { $fs.Dispose() }
    $win.Close()
    Write-Host "Saved $Screenshot ($w x $h)  hidden columns: $($script:HiddenCols -join ', ')"
    return
}

# The window is already visible (shown before loading), so run the message loop until it is closed.
$script:MainFrame = New-Object Windows.Threading.DispatcherFrame
$win.Add_Closed({ $script:MainFrame.Continue = $false })
if (-not $win.IsVisible) { if ($script:StartMaximized) { $win.WindowState = 'Maximized' }; $win.Show() }
[Windows.Threading.Dispatcher]::PushFrame($script:MainFrame)
