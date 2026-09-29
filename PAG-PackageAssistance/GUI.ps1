##############################################################
# GUI.ps1  -  Package Builder wizard (Step 1 + Step 2 live; 3/4 stubbed)
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -STA -File GUI.ps1
##############################################################
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ZERO-COPY portability fix: when the exe runs FROM A UNC SHARE (via a shortcut), the process CURRENT DIRECTORY is the
# network path. That breaks WMI (SCCM connect) and WinHTTP proxy/DNS (Intune sign-in) on this environment - the exact
# "database lookup" / "Error creating the Web Proxy" / "Error sending the request" failures seen from the share (local
# copies work because their CWD is local). Pin the working directory to a LOCAL folder so those network operations work
# while the tool still RUNS from the share. The tool resolves ALL of its own files by ABSOLUTE path (Get-ToolRoot /
# Resolve-ToolPath), so moving CWD never affects file loading.
try {
    $__localCwd = if ($env:TEMP -and (Test-Path $env:TEMP)) { $env:TEMP } elseif (Test-Path 'C:\Windows\Temp') { 'C:\Windows\Temp' } else { $null }
    if ($__localCwd) { [Environment]::CurrentDirectory = $__localCwd; try { Set-Location -LiteralPath $__localCwd } catch {} }
} catch {}

if ($script:PBEngineSource) {
    # MERGED / EXE build (Build-Exe.ps1): the engine modules are already defined from the embedded
    # source above this body - no .ps1 files exist on disk. Root = the exe's own folder.
    $root = Get-ToolRoot
} else {
    # DEV mode: engine modules are sibling files.
    $root = Split-Path -Parent $MyInvocation.MyCommand.Path
    . "$root\Core.ps1"
    . "$root\Theme.ps1"                   # shared modern dark theme (Apply-PbTheme) for every window/dialog
    . "$root\Predecessor.ps1"
    . "$root\Build.ps1"
    . "$root\Source.ps1"
    . "$root\MstBuilder.ps1"              # Build-Mst / Get-StandardMstProperties (Step 4 MST)
    . "$root\BundledMsi.ps1"              # extract an MSI bundled inside a wrapper EXE (Step 2)
    . "$root\Snapshot.ps1"                # before/after machine snapshot + diff ("what did the installer do")
    . "$root\Screenshots.ps1"             # shortcut launch + screenshot jobs (analyzer / validation)
    . "$root\Assemble.ps1"                # New-Package (Step 4 assembler)
    . "$root\Snippets.ps1"                # Initialize-Snippets / Get-FilteredSnippets (Step 3 panel)
    . "$root\Sccm.ps1"                    # SCCM automator (Step 4 Publish)
    . "$root\Intune.ps1"                  # Intune automator (Step 4 Publish)
    . "$root\BrandGpf.ps1"                # brand targets / order-number rules (settings-driven) - the pak carries it too
    . "$root\PSADT_V3toV4_Mappings.ps1"   # Convert-V3ToV4Content, used when the predecessor is v3
}

# ---- RUN-FROM-SHARE -> RELAUNCH LOCAL --------------------------------------------------------------------------
# Launched from a UNC/network share, the process network stack is restricted: SCCM (WMI/DNS to the site server) and
# Intune (WinHTTP/proxy to Microsoft) FAIL, though the identical tool works copied locally. So mirror the CORE
# (package-building) files to a LOCAL cache (%LOCALAPPDATA%\PackageBuilder) and relaunch there. The HEAVY SCCM/Intune
# modules are NOT copied yet - they come later, on demand, the first time the user publishes (Ensure-PublishModules-
# Staged), to keep this first launch small + fast. Users only ever use a shortcut. Best-effort: any failure -> fall
# through and run from the share unchanged. Disable centrally with settings.json -> "LocalRelaunch": false.
if ($script:PBEngineSource -and (Test-NetworkPath "$root") -and ($env:PB_LOCALRUN -ne '1')) {
    $doRelaunch = $true
    try { $sj = Join-Path $root 'settings.json'; if (Test-Path $sj) { $sc = (Get-Content $sj -Raw).TrimStart([char]0xFEFF) | ConvertFrom-Json
          if (($sc.PSObject.Properties.Name -contains 'LocalRelaunch') -and (-not $sc.LocalRelaunch)) { $doRelaunch = $false } } } catch {}
    if ($doRelaunch) {
        $localExe = Invoke-SelfStage -Root "$root"      # core-only mirror; writes the .source marker for later module staging
        if ($localExe) {
            try { $env:PB_LOCALRUN = '1'; $env:PB_SHAREROOT = "$root"; Start-Process -FilePath $localExe; [Environment]::Exit(0) } catch {}
        }
    }
}

Initialize-Log
Initialize-Config (Join-Path $root 'settings.json')

# ---- AvalonEdit (Step 3 editor) - load defensively: if missing, the wizard still
#      runs and Step 3 shows a message instead of the editor. Same unblock + load-
#      from-bytes trick the standalone Editor.ps1 proved (avoids Mark-of-the-Web lock).
$script:HasEditor = $false
$script:AvalonDll = Join-Path $root 'Lib\ICSharpCode.AvalonEdit.dll'
if (Test-Path $script:AvalonDll) {
    try { Unblock-File -LiteralPath $script:AvalonDll -ErrorAction SilentlyContinue } catch {}
    try {
        [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($script:AvalonDll)) | Out-Null
        $script:HasEditor = $true
    } catch {
        try { Add-Type -Path $script:AvalonDll; $script:HasEditor = $true }
        catch { Write-Log "AvalonEdit failed to load: $($_.Exception.Message)" Warning }
    }
} else { Write-Log "AvalonEdit DLL not found at $script:AvalonDll - Step 3 editor disabled." Warning }

$script:State = @{
    # Step 1 (Info): identity + predecessor + source
    PkgName=''; Parsed=$null; Ritm=''; TargetBrand=(Get-GpfDefaultTargetTag)
    PredecessorPath=$null; PredecessorModel=$null; AddUninstallPrevious=$false; ReusePkg=$null
    SourceFolder=$null; Resolved=$null; ChosenInstallers=@(); LooseFiles=$false
    ZipPayload=$null; ZipInstallers=@()   # GPF: a Sources\Files\*.zip kept VERBATIM + the installer entries selected inside it
    SourceNotes=@()     # review notes tied to the source (e.g. MSI extracted from a wrapper EXE)
    GpfRequest=$null    # GPF brand: the harvested AES request (OrderNumber/FilesDir/Icons/Docs/PredecessorPath)
    # Step 2 (Detection): installer type, product code, MST flags
    # Remove flags default ON: the MST strips desktop shortcut / Startup(autostart) / SendTo+stray shortcuts / Run keys when present in the MSI.
    InstallerType=''; ProductCode=''
    GenerateMst=$true   # F27/F29: build an MST (standard transform + cleanup flags). Untick -> reuse source MST if present, else plain MSI.
    CarryPredMst=$true  # carry the predecessor MST's changes forward (properties / Keep toggles / removals). The packager's standing choice; the page tick + the dialog's master switch are the same thing.
    PredMstDeclined=@{} # per MSI path: the predecessor properties ("prop:NAME") / removals ("item:LABEL") the packager unticked - never brought back automatically
    RemoveShortcut=$true; RemoveRun32=$true; RemoveRun64=$true; RemoveStartup=$true; RemoveStray=$true
    # Step 2: EXE parameters + loose-files options
    MstReviewNotes=@()  # report-only notes from "Match predecessor MST" (other tables the old MST touched)
    MstApplyExtras=@()  # user-confirmed predecessor MST removals to replicate at build time
    ReviewAck=@{}       # review items the packager CONFIRMED (key = item text): they drop out of the amber count
    MstOtherItems=@()   # full predecessor-MST other-table comparison (Read-MstSettings OtherItems) shown in the "Other tables" tab
    SnapshotNotes=@()   # "what did the installer do" findings (cleanups, dirs/services created) -> review items
    SnapshotUninstall=$null  # derived uninstall command + product code from the before/after snapshot
    SnapshotDisplayVersion=$null # the REAL registry DisplayVersion from the snapshot ARP entry - SoftIdent uses THIS (full version wins)
    SnapshotCleanupCommands=@()  # TICKED snapshot exclusions -> removal commands written into the ps1 POST-INSTALLATION
    SnapshotReport=''   # the last snapshot report text - PERSISTED (survives closing the dialog) until Reset
    SnapshotExclusions=@()  # master list of exclusion items {Label;Command;Checked} - re-openable/editable until Reset
    SnapshotShortcuts=@()   # OPTIONAL reference: the real app Start-Menu shortcuts seen at snapshot time, for the integration diff
    SnapshotLeftoverCandidates=$null   # what the install created (files/dirs/reg/lnk) -> drives the after-uninstall leftover check
    SnapshotLeftoverChecked=$false     # leftover check ran? post-uninstall cleanup is DEFERRED until it has
    SnapshotInstalledMB=0   # measured installed footprint (MB) from the snapshot -> FreeSpace floor
    SnapshotHkcu=@()        # detected per-user (HKCU) values from the snapshot -> auto-fills the Per-user config code
    SnapshotUserFiles=@()   # detected per-user FILES (AppData) from the snapshot -> staged + copied to every profile
    PerUserMode='None'      # per-user config: 'None' | 'AllUsersReg' (Invoke-ADTAllUsersRegistryAction) | 'ActiveSetup'
    InstallParams=''; UninstallParams=''
    InstallerArgs=@{}   # per-installer (Multiple mode): FullName -> @{ Install; Uninstall }
    MsiProps=@{}        # per-MSI extra properties text: FullName -> "KEY=VALUE; ..."
    MsiFlags=@{}        # per-MSI MST cleanup: FullName -> @{ KeepShortcut; KeepRunKey; KeepStartup; KeepStray }
    LooseArp=$false; LooseShortcut=$false; LooseTargets=''
    # Step 3 (Editor): assembled / edited script
    ScriptText=$null
    # Step 4 (Create / Publish): created package path + auto-fetched publish base fields
    CreatedPath=$null; PublishBase=$null
}
# Guard: set true while we write controls FROM state, so the change handlers
# (which write state FROM controls and invalidate downstream) don't fire back.
$script:Rehydrating = $false

# ---------- central state: ownership + invalidation (Plan section 7) ----------
# Each step OWNS a set of $State keys. Invalidating a step clears its owned keys
# and every downstream step's, so nothing stale survives an upstream change.
# Raw inputs the user types (StepInputs) are cleared only by an explicit Reset.
# CLOSURE-SAFE accessors: a .GetNewClosure() handler CANNOT reach $script:State / $script:Win directly (its $script:
# scope is the closure's own empty module - the "property CreatedPath cannot be found" bug class). FUNCTIONS execute in
# the scope they were DEFINED in, so handlers reach the real objects through these instead.
function Get-PBState { return $script:State }
function Get-PBMainWindow { return $script:Win }

$script:StepOwns   = @{
    1 = @('PredecessorPath','PredecessorModel','SourceFolder','Resolved','ChosenInstallers','LooseFiles','ZipPayload','ZipInstallers','AddUninstallPrevious','SourceNotes','ReusePkg','GpfRequest')
    2 = @('InstallerType','ProductCode','RemoveShortcut','RemoveRun32','RemoveRun64','RemoveStartup','RemoveStray','InstallParams','UninstallParams','InstallerArgs','MsiProps','MsiFlags','MstApplyExtras','MstReviewNotes','CarryPredMst','PredMstDeclined','SnapshotNotes','SnapshotUninstall','SnapshotDisplayVersion','SnapshotCleanupCommands','SnapshotReport','SnapshotExclusions','SnapshotShortcuts','SnapshotLeftoverCandidates','SnapshotLeftoverChecked','SnapshotInstalledMB','SnapshotHkcu','SnapshotUserFiles','PerUserMode','LooseArp','LooseShortcut','LooseTargets')
    3 = @('ScriptText','ReviewAck')
    4 = @('CreatedPath','PublishBase')   # stale publish targets must die with upstream changes -
                                         # otherwise Step 4 would happily publish the PREVIOUS package
}
$script:StepInputs = @{ 1=@('PkgName','Parsed','Ritm'); 2=@(); 3=@(); 4=@() }
$script:StateDefaults = @{ ChosenInstallers=@(); LooseFiles=$false; AddUninstallPrevious=$false; RemoveShortcut=$true; RemoveRun32=$true; RemoveRun64=$true; RemoveStartup=$true; RemoveStray=$true
                           InstallParams=''; UninstallParams=''; MstApplyExtras=@(); MstReviewNotes=@(); CarryPredMst=$true; PredMstDeclined=@{}; PredMstProps=@{}; PredMstAppliedKey=''; SnapshotNotes=@(); ReviewAck=@{}; SnapshotUninstall=$null; SnapshotDisplayVersion=$null; SnapshotCleanupCommands=@(); SnapshotReport=''; SnapshotExclusions=@(); SnapshotShortcuts=@(); SnapshotLeftoverCandidates=$null; SnapshotLeftoverChecked=$false; SnapshotInstalledMB=0; SnapshotHkcu=@(); SnapshotUserFiles=@(); PerUserMode='None'; SourceNotes=@(); LooseArp=$false; LooseShortcut=$false; LooseTargets='' }
function Reset-Key { param([string]$k)
    $script:State[$k] = if ($script:StateDefaults.ContainsKey($k)) { $script:StateDefaults[$k] } else { $null }
}
function Invalidate-From { param([int]$n)
    for ($i=$n; $i -le 4; $i++) { foreach ($k in $script:StepOwns[$i]) { Reset-Key $k } }
    # Per-application session caches that live OUTSIDE $script:State (so the resets above don't touch them). When
    # anything from Step 2 up is invalidated (name/source change, Reset), drop them so the PREVIOUS application's
    # KB suggestion / validator findings don't "stick around". (The snapshot report/exclusions are in State and
    # cleared by the loop above.)
    if ($n -le 2) {
        $script:InstallerValCache = @{}
        $script:KbHintSwitch = ''; $script:KbHintInstaller = $null
        $script:ReviewAutoShown = $false
        try { if ($PnlKbHint) { $PnlKbHint.Visibility = 'Collapsed' } } catch {}
    }
}
function Reset-Step { param([int]$n)
    foreach ($k in $script:StepInputs[$n]) { Reset-Key $k }
    Invalidate-From $n
    Populate-Step $n
    # Step-4 tabs (Integration/Testing/Troubleshoot/Dev-Test) hold MANUAL text/list entries that are not in
    # $script:State, so the resets above never clear them. Empty them here (Step 4 is always downstream).
    if (Get-Command Clear-Step4Fields -ErrorAction SilentlyContinue) { Clear-Step4Fields }
    Write-Log "Reset step $n (and downstream)."
}
function Reset-All { Reset-Step 1; if ($LblStatusBar) { $LblStatusBar.Text = '' }; Show-Step 1; Write-Log "Reset all." }

# ---------- helpers ----------
# Get-PredecessorCandidates moved to Predecessor.ps1 and Find-SourceFolder to Source.ps1 (r154): they run inside
# Invoke-PBAsync BACKGROUND runspaces, which load the ENGINE modules only - as GUI.ps1 functions they were invisible
# there, so 'Find predecessor' / 'Fetch source' silently returned nothing in the packed build.

# Single-select predecessor picker. Returns the chosen candidate object, or $null.
function Show-PredecessorPicker {
    param([object[]]$Candidates, [int]$DefaultIndex = 0)
    [xml]$px = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Select predecessor" Height="380" Width="560" WindowStartupLocation="CenterOwner" Background="#2A2E36">
  <Grid Margin="12">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Foreground="#E7E9ED" TextWrapping="Wrap" Margin="0,0,0,8"
       Text="Pick the predecessor to base this package on (newest first). '(same version)' means a different revision of the same version."/>
    <ListBox x:Name="Lb" Grid.Row="1" Background="#181A1F" Foreground="#E7E9ED"/>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="Ok" Content="Use selected" Width="110" Margin="0,0,8,0"/>
      <Button x:Name="Cancel" Content="Cancel" Width="80"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $w  = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $px))
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $w }
    $lb = $w.FindName('Lb')
    foreach ($c in $Candidates) {
        $tag = if ($c.SameVersion) { '   (same version)' } else { '' }
        [void]$lb.Items.Add("$($c.Name)$tag")
    }
    if ($DefaultIndex -ge 0 -and $DefaultIndex -lt $lb.Items.Count) { $lb.SelectedIndex = $DefaultIndex } else { $lb.SelectedIndex = 0 }
    $script:predPick = $null
    $w.FindName('Ok').add_Click({ if ($lb.SelectedIndex -ge 0) { $script:predPick = $Candidates[$lb.SelectedIndex] }; $w.DialogResult=$true; $w.Close() })
    $w.FindName('Cancel').add_Click({ $w.DialogResult=$false; $w.Close() })
    $w.Owner = $script:Win
    Set-PBDialogChrome -Window $w -Glyph 'E721' -Title 'Select predecessor' -PrimaryName 'Ok'
    if ($w.ShowDialog()) { return $script:predPick }
    return $null
}
# ---------- installer picker (multiple installers, ordered) ----------
function Show-InstallerPicker {
    param([object[]]$Installers)
    [xml]$px = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Select installer(s)" Height="470" Width="680" MinHeight="380" MinWidth="560" WindowStartupLocation="CenterOwner" Background="#2A2E36">
  <Grid Margin="12">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Foreground="#E7E9ED" TextWrapping="Wrap" Margin="0,0,0,8"
       Text="Multiple installers found. Tick the one(s) to use and order them with Up/Down (install order). Or tick 'loose files' below to package the whole payload as a zip (no installer is required)."/>
    <DockPanel Grid.Row="1">
      <StackPanel DockPanel.Dock="Right" VerticalAlignment="Top" Margin="8,0,0,0">
        <Button x:Name="Up" Content="Up" Width="60" Margin="0,0,0,6"/>
        <Button x:Name="Down" Content="Down" Width="60"/>
      </StackPanel>
      <ListBox x:Name="Lb" SelectionMode="Extended" Background="#181A1F" Foreground="#E7E9ED"/>
    </DockPanel>
    <CheckBox x:Name="Loose" Grid.Row="2" Foreground="#E7E9ED" Margin="0,12,0,0"
              Content="Treat as loose files (zip the whole payload, extract at install - no installer command)"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="Ok" Content="Use selected" Width="110" Margin="0,0,8,0"/>
      <Button x:Name="Cancel" Content="Cancel" Width="80"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $w  = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $px))
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $w }
    $lb = $w.FindName('Lb')
    $map = @{}
    foreach ($i in $Installers) {
        $name = $i.Name; if ($map.ContainsKey($name)) { $name = "$name  [$($i.Directory.Name)]" }
        $map[$name] = $i; [void]$lb.Items.Add($name)
    }
    $w.FindName('Up').add_Click({
        $idx=$lb.SelectedIndex; if ($idx -gt 0){ $it=$lb.Items[$idx]; $lb.Items.RemoveAt($idx); $lb.Items.Insert($idx-1,$it); $lb.SelectedIndex=$idx-1 }
    })
    $w.FindName('Down').add_Click({
        $idx=$lb.SelectedIndex; if ($idx -ge 0 -and $idx -lt $lb.Items.Count-1){ $it=$lb.Items[$idx]; $lb.Items.RemoveAt($idx); $lb.Items.Insert($idx+1,$it); $lb.SelectedIndex=$idx+1 }
    })
    $script:pickResult=@(); $script:pickLoose=$false
    $w.FindName('Ok').add_Click({
        $sel = @($lb.SelectedItems)
        # return in list order, not click order
        $ordered = @(); foreach ($it in $lb.Items) { if ($sel -contains $it) { $ordered += $map[$it] } }
        $script:pickLoose  = [bool]$w.FindName('Loose').IsChecked
        # Loose files don't need a specific installer picked - default to the whole payload.
        if ($script:pickLoose -and $ordered.Count -eq 0) { $ordered = @(); foreach ($it in $lb.Items) { $ordered += $map[$it] } }
        $script:pickResult = $ordered
        $w.DialogResult=$true; $w.Close()
    })
    $w.FindName('Cancel').add_Click({ $w.DialogResult=$false; $w.Close() })
    $w.Owner = $script:Win
    Set-PBDialogChrome -Window $w -Glyph 'E8E5' -Title 'Choose installers' -PrimaryName 'Ok'
    if ($w.ShowDialog()) { return $script:pickResult }
    return @()
}

# ---------- main window ----------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Package Assistance" Height="760" Width="1200" MinHeight="640" MinWidth="1040"
        WindowStartupLocation="CenterScreen" Background="#181A1F" FontFamily="Segoe UI" FontSize="13">
  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>

    <!-- HEADER: identity of the thing being worked on - the package name, its order number, the brand it goes to.
         Nothing else: where it reads from / goes to lives in the step strip. The name column trims with an
         ellipsis (full name on hover), so a long name never squeezes the rest off the row. -->
    <Border Grid.Row="0" Background="#1F232B" BorderBrush="#2E3340" BorderThickness="0,0,0,1" Padding="16,11">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="PACKAGE ASSISTANCE" Foreground="#56C8D6" FontWeight="Bold" FontSize="12" VerticalAlignment="Center" Margin="0,0,34,0"/>
        <TextBox x:Name="LblHdrPkg" Text="No package yet" Foreground="#E7E9ED" FontFamily="Consolas" FontSize="13.5" MaxWidth="640" VerticalAlignment="Center" Style="{DynamicResource PbCopyText}"/>
        <StackPanel x:Name="PnlHdrRitm" Orientation="Horizontal" VerticalAlignment="Center" Margin="22,0,0,0" Visibility="Collapsed">
          <TextBlock x:Name="LblHdrRitmCaption" Text="ORDER" Foreground="#A0A8B4" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,1,8,0"/>
          <TextBox x:Name="LblHdrRitm" Text="" Foreground="#E7E9ED" FontFamily="Consolas" FontSize="13.5" VerticalAlignment="Center" Style="{DynamicResource PbCopyText}"/>
        </StackPanel>
        <StackPanel x:Name="PnlHdrBrand" Orientation="Horizontal" VerticalAlignment="Center" Margin="22,0,0,0" Visibility="Collapsed">
          <TextBlock Text="BRAND" Foreground="#A0A8B4" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,1,8,0"/>
          <TextBox x:Name="LblHdrBrand" Text="" Foreground="#E7E9ED" FontSize="13" VerticalAlignment="Center" Style="{DynamicResource PbCopyText}"/>
        </StackPanel>
      </StackPanel>
    </Border>

    <!-- STEP STRIP: the four wizard pages as a row of quiet pills. The current page is a filled teal-tinted pill;
         pages already completed read in light text; pages not reached yet read muted. Progress is shown by weight
         and colour only - no numbers, no counters. Painted by Update-StepStrip from central state. -->
    <Border Grid.Row="1" Background="#21242B" BorderBrush="#2A2F38" BorderThickness="0,0,0,1" Padding="16,0" Height="60">
      <DockPanel>
        <TextBox x:Name="LblOrigin" DockPanel.Dock="Right" Foreground="#B7BEC8" FontSize="12.5" VerticalAlignment="Center" Margin="24,0,0,0" Style="{DynamicResource PbCopyText}"/>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Border x:Name="S1" CornerRadius="5" Padding="13,5,13,4" Margin="0,0,6,0" BorderThickness="1" Cursor="Hand" MinWidth="150">
            <StackPanel>
              <StackPanel Orientation="Horizontal"><TextBlock x:Name="G1" Style="{DynamicResource PbGlyph}" Text="&#xE7B8;"/><TextBlock x:Name="N1" Text="Info" VerticalAlignment="Center"/></StackPanel>
              <TextBlock x:Name="ST1" FontSize="10.5" Foreground="#7F8794" Margin="21,2,0,0" TextTrimming="CharacterEllipsis" MaxWidth="260"/>
            </StackPanel>
          </Border>
          <Border x:Name="S2" CornerRadius="5" Padding="13,5,13,4" Margin="0,0,6,0" BorderThickness="1" Cursor="Hand" MinWidth="150">
            <StackPanel>
              <StackPanel Orientation="Horizontal"><TextBlock x:Name="G2" Style="{DynamicResource PbGlyph}" Text="&#xE713;"/><TextBlock x:Name="N2" Text="Configure" VerticalAlignment="Center"/></StackPanel>
              <TextBlock x:Name="ST2" FontSize="10.5" Foreground="#7F8794" Margin="21,2,0,0" TextTrimming="CharacterEllipsis" MaxWidth="260"/>
            </StackPanel>
          </Border>
          <Border x:Name="S3" CornerRadius="5" Padding="13,5,13,4" Margin="0,0,6,0" BorderThickness="1" Cursor="Hand" MinWidth="150">
            <StackPanel>
              <StackPanel Orientation="Horizontal"><TextBlock x:Name="G3" Style="{DynamicResource PbGlyph}" Text="&#xE70F;"/><TextBlock x:Name="N3" Text="Editor" VerticalAlignment="Center"/></StackPanel>
              <TextBlock x:Name="ST3" FontSize="10.5" Foreground="#7F8794" Margin="21,2,0,0" TextTrimming="CharacterEllipsis" MaxWidth="260"/>
            </StackPanel>
          </Border>
          <Border x:Name="S4" CornerRadius="5" Padding="13,5,13,4" Margin="0,0,6,0" BorderThickness="1" Cursor="Hand" MinWidth="150">
            <StackPanel>
              <StackPanel Orientation="Horizontal"><TextBlock x:Name="G4" Style="{DynamicResource PbGlyph}" Text="&#xE898;"/><TextBlock x:Name="N4" Text="Create" VerticalAlignment="Center"/></StackPanel>
              <TextBlock x:Name="ST4" FontSize="10.5" Foreground="#7F8794" Margin="21,2,0,0" TextTrimming="CharacterEllipsis" MaxWidth="260"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </DockPanel>
    </Border>

    <Grid Grid.Row="2">
      <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

      <!-- STEP 1: two columns. Left = the package's identity (what we are building); right = where its content
           comes from (predecessor + source) as one lifted panel, so the page uses the width instead of stacking
           everything down a narrow column. -->
      <Grid x:Name="P1" Grid.Row="0" Margin="24,20,24,16" Visibility="Visible">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="28"/><ColumnDefinition Width="460"/></Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" VerticalAlignment="Top">
          <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE7B8;" Foreground="#56C8D6"/><TextBlock Text="Package" Style="{DynamicResource PbSectionTitle}"/></StackPanel>
          <TextBlock Style="{DynamicResource PbSectionDesc}" Text="The name drives everything downstream: where the source is looked up, which predecessor is offered, and the folders inside the built package."/>
          <Border Style="{DynamicResource PbSectionRule}"/>
          <TextBlock Text="Target package name" Foreground="#E7E9ED" Margin="0,0,0,5"/>
          <TextBox x:Name="TxtPkg" Height="30" FontFamily="Consolas" FontSize="13"
                   ToolTip="Vendor_App_Arch_Version-Release_Lang. This name drives everything: where the source is looked up, which predecessor is offered, and the folders inside the built package."/>
          <TextBlock Foreground="#A0A8B4" FontSize="11.5" TextWrapping="Wrap" Margin="0,4,0,0"
                     Text="Vendor_App_Arch_Version-Release_Lang    e.g. Mozilla_FirefoxESR_x64_140.15.0-0001_MUL"/>
          <!-- MECM name-length counter (Brand.NameLengthLimit in settings.json, Porsche = 34): text only, never a popup. -->
          <TextBlock x:Name="LblNameLen" Foreground="#A0A8B4" FontSize="11.5" TextWrapping="Wrap" Margin="0,2,0,0" Visibility="Collapsed"/>
          <TextBlock x:Name="LblRitmCaption" Text="RITM ID" Foreground="#E7E9ED" Margin="0,14,0,5"/>
          <TextBox x:Name="TxtRitm" Height="30" Width="260" HorizontalAlignment="Left" FontFamily="Consolas" FontSize="13"
                   ToolTip="The request's order number. It is written into the generated script and the package documentation."/>
          <TextBlock x:Name="LblRitmExample" Foreground="#A0A8B4" FontSize="11.5" TextWrapping="Wrap" Margin="0,4,0,0"/>
          <TextBlock x:Name="LblBrand" Text="Target brand" Foreground="#E7E9ED" Margin="0,14,0,5"/>
          <!-- Items come from settings.json Brand.OutgoingPrefix at startup; with one target the row is hidden. -->
          <ComboBox x:Name="CmbBrand" Height="30" Width="260" HorizontalAlignment="Left" ToolTip="Which brand this package is for. Sets the outgoing prefix and the brand-specific rules (Audi: silent process close; VW: Volkswagen install title; Group: 34-character name check). Auto-set from the request; change it if needed."/>

          <TextBox x:Name="LblParsed" Foreground="#6A9955" TextWrapping="Wrap" Margin="0,12,0,12" Style="{DynamicResource PbCopyText}"/>
        </StackPanel>

        <Border Grid.Column="2" Background="#1E2128" BorderBrush="#2A2F38" BorderThickness="1" CornerRadius="6" Padding="18,16" VerticalAlignment="Top">
          <StackPanel>
            <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE8B7;" Foreground="#56C8D6"/><TextBlock Text="Source and predecessor" Style="{DynamicResource PbSectionTitle}"/></StackPanel>
            <TextBlock Style="{DynamicResource PbSectionDesc}" Margin="0,3,0,12"
                       Text="Find the previous release to reuse its script, then fetch the installer files. Or add an installer by hand."/>
            <WrapPanel Margin="0,0,0,6">
              <Button x:Name="BtnPred" Margin="0,0,8,8"><StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE721;"/><TextBlock Text="Find predecessor"/></StackPanel></Button>
              <Button x:Name="BtnFetch" Margin="0,0,8,8"><StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE896;"/><TextBlock Text="Fetch source"/></StackPanel></Button>
              <Button x:Name="BtnAddInst" Margin="0,0,8,8"><StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE8E5;"/><TextBlock Text="Add installer(s) / source..."/></StackPanel></Button>
            </WrapPanel>
            <TextBox x:Name="LblPred" Foreground="#56C8D6" TextWrapping="Wrap" Margin="0,0,0,6" Style="{DynamicResource PbCopyText}"/>
            <CheckBox x:Name="ChkAddUninstall" Visibility="Collapsed" Foreground="#E7E9ED" Margin="0,0,0,10"
                      Content="Add predecessor uninstall block (remove the old version on install)"/>
            <TextBox x:Name="LblSrc"  Foreground="#CE9178" TextWrapping="Wrap" Style="{DynamicResource PbCopyText}"/>
          </StackPanel>
        </Border>
      </Grid>

      <!-- STEP 2 (scrolls: the knowledge-base hint, per-installer args and loose-file options can all show at once).
           Titled SECTIONS - Installer / MST cleanup and properties / Silent switches / Analysis / Per-installer /
           Loose files - separated by rhythm, not by boxes. Every control keeps its name; the section wrappers
           (SecMsi / SecExe / SecAnalysis) only follow the visibility Populate-Step2 already decides. -->
      <ScrollViewer x:Name="P2" Grid.Row="0" Margin="24,20,24,12" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="0,0,12,0" MinWidth="940" MaxWidth="980" HorizontalAlignment="Left">

          <!-- SECTION: Installer (always) -->
          <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE7B8;" Foreground="#56C8D6"/><TextBlock Text="Installer" Style="{DynamicResource PbSectionTitle}"/></StackPanel>
          <TextBlock Style="{DynamicResource PbSectionDesc}" Text="What was chosen on the Info step, with the type and product code the tool read from it."/>
          <Border Style="{DynamicResource PbSectionRule}"/>
          <TextBox x:Name="LblInst" Foreground="#CE9178" Margin="0,0,0,10" TextWrapping="Wrap" Style="{DynamicResource PbCopyText}"/>
          <Grid Margin="0,0,0,22">
            <Grid.ColumnDefinitions><ColumnDefinition Width="180"/><ColumnDefinition Width="20"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
              <TextBlock Text="Installer type" Foreground="#E7E9ED" Margin="0,0,0,4"/>
              <TextBox x:Name="TxtType" Height="28" IsReadOnly="True"/>
            </StackPanel>
            <StackPanel Grid.Column="2">
              <TextBlock Text="MSI ProductCode (read from the MSI)" Foreground="#E7E9ED" Margin="0,0,0,4"/>
              <TextBox x:Name="TxtPC" Height="28" FontFamily="Consolas" Width="440" HorizontalAlignment="Left"/>
            </StackPanel>
          </Grid>

          <!-- SECTION: MST cleanup + properties (MSI only) -->
          <StackPanel x:Name="SecMsi" Margin="0,0,0,22">
            <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE713;" Foreground="#56C8D6"/><TextBlock Text="MST cleanup and properties" Style="{DynamicResource PbSectionTitle}"/></StackPanel>
            <TextBlock Style="{DynamicResource PbSectionDesc}" Text="A transform that sets the standard properties and removes what a packaged install should not leave behind. Untick to reuse a vendor MST or install the MSI plain."/>
            <Border Style="{DynamicResource PbSectionRule}"/>
            <!-- F27/F29: master toggle - generate an MST (standard transform + cleanup) or not. Unticked: reuse a source
                 MST if the vendor shipped one, else install the MSI plain. Hides the MST options below when off. -->
            <CheckBox x:Name="ChkGenerateMst" Content="Generate MST (standard transform + cleanup options below)" IsChecked="True" Foreground="#E7E9ED" Margin="0,0,0,6"
                      ToolTip="On: build a transform that sets the standard properties and applies the cleanup ticked below. Off: if the source already ships an MST it's reused as-is; otherwise the MSI installs plain (no transform)."/>
            <!-- The predecessor's MST carried forward - the packager's standing choice, shown only when a predecessor MST
                 exists. NOT gated by Generate MST (it also decides the Keep toggles). The same switch sits at the top of
                 "View MSI properties" as the master switch; both read and write State.CarryPredMst. -->
            <CheckBox x:Name="ChkCarryPredMst" Content="Carry forward the predecessor's MST changes (properties, Keep toggles, removals)" IsChecked="True" Foreground="#E7E9ED" Margin="0,0,0,8" Visibility="Collapsed"
                      ToolTip="On: what the predecessor's transform did is applied as the default - its property changes, its shortcut / Run-key cleanup and its safe removals; you can still untick single items in View MSI properties, and those stay unticked. Off: the predecessor MST is ignored entirely."/>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <!-- MST cleanup: removed by default per MSI when present; tick to KEEP (independent). -->
              <StackPanel x:Name="PnlMstFlags" Grid.Column="0">
                <TextBlock Text="Keep (instead of removing)" Foreground="#E7E9ED" Margin="0,0,0,6"/>
                <CheckBox x:Name="ChkKeepShortcut" Content="Desktop shortcut" Foreground="#E7E9ED" Margin="0,3"/>
                <CheckBox x:Name="ChkKeepStartup" Content="Startup / autostart shortcut" Foreground="#E7E9ED" Margin="0,3"/>
                <CheckBox x:Name="ChkKeepStray" Content="SendTo / other stray shortcuts" Foreground="#E7E9ED" Margin="0,3"/>
                <CheckBox x:Name="ChkKeepRunKey"  Content="Run key (32 and 64-bit)" Foreground="#E7E9ED" Margin="0,3"/>
              </StackPanel>
              <StackPanel x:Name="PnlMsiProps" Grid.Column="2">
                <TextBlock Text="Extra MSI properties (one per line, e.g. ALLUSERS=1)" Foreground="#E7E9ED" Margin="0,0,0,6"/>
                <TextBox x:Name="TxtMsiProps" Height="64" FontFamily="Consolas" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" VerticalContentAlignment="Top"/>
                <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                  <Button x:Name="BtnMsiPropsView" ToolTip="Open the MSI's Property table: tick + edit values (e.g. IAGREE, AGREETOLICENSE) - no Orca needed. Ticked rows are written into the box above and merged into the MST.">
                    <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE7C3;"/><TextBlock Text="View MSI properties..."/></StackPanel>
                  </Button>
                  <Button x:Name="BtnMatchPredMst" Margin="8,0,0,0" Visibility="Collapsed"
                          ToolTip="Read the predecessor package's MST and replicate it: sets the Keep-shortcut / Keep-Run-key toggles and extra properties to whatever the predecessor's transform did. Predecessor reuse only.">
                    <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE8C8;"/><TextBlock Text="Match predecessor MST"/></StackPanel>
                  </Button>
                </StackPanel>
                <TextBox x:Name="LblMatchMst" Foreground="#6A9955" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,0" Style="{DynamicResource PbCopyText}"/>
              </StackPanel>
            </Grid>
          </StackPanel>

          <!-- SECTION: Silent switches (lone EXE; SecExe follows PnlExeParams' visibility). The knowledge-base
               suggestion belongs here - it exists to fill these two boxes. -->
          <StackPanel x:Name="SecExe" Margin="0,0,0,22">
            <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE756;" Foreground="#56C8D6"/><TextBlock Text="Silent switches" Style="{DynamicResource PbSectionTitle}"/></StackPanel>
            <TextBlock x:Name="LblExeParams" Style="{DynamicResource PbSectionDesc}" Text="The command-line arguments for a silent install and uninstall. Leave blank to keep a TODO in the script."/>
            <Border Style="{DynamicResource PbSectionRule}"/>
            <StackPanel x:Name="PnlExeParams" Orientation="Horizontal">
              <StackPanel Margin="0,0,16,0">
                <TextBlock Text="Install args" Foreground="#E7E9ED" Margin="0,0,0,4"/>
                <TextBox x:Name="TxtInstArgs" Width="300" Height="28" FontFamily="Consolas"/>
              </StackPanel>
              <StackPanel>
                <TextBlock Text="Uninstall args" Foreground="#E7E9ED" Margin="0,0,0,4"/>
                <TextBox x:Name="TxtUninstArgs" Width="300" Height="28" FontFamily="Consolas"/>
              </StackPanel>
            </StackPanel>
          </StackPanel>

          <!-- SECTION: Knowledge base (its own show/hide - Update-KbHint decides). What 920 past packages did:
               silent switches for an EXE (by installer, app, vendor, then engine fingerprint); for an MSI the
               previous release and the auto-update mechanisms seen, so the script remembers to disable them. -->
          <StackPanel x:Name="PnlKbHint" Visibility="Collapsed" Margin="0,0,0,22">
            <DockPanel LastChildFill="False">
              <StackPanel Orientation="Horizontal" DockPanel.Dock="Left"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE8F1;" Foreground="#56C8D6"/><TextBlock Text="Knowledge base" Style="{DynamicResource PbSectionTitle}"/></StackPanel>
              <TextBox x:Name="LblKbConf" DockPanel.Dock="Right" FontSize="12" VerticalAlignment="Center" Style="{DynamicResource PbCopyText}"/>
            </DockPanel>
            <TextBlock Style="{DynamicResource PbSectionDesc}" Text="What past packages of this app, this vendor, or installers with the same engine used. Suggestions only - verify before building."/>
            <Border Style="{DynamicResource PbSectionRule}"/>
            <Border Background="#16202B" BorderBrush="#2E4760" BorderThickness="1" CornerRadius="5" Padding="14,11">
            <StackPanel>
              <Grid x:Name="PnlKbInst">
                <Grid.ColumnDefinitions><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="Install args" Foreground="#B7BEC8" FontSize="12" VerticalAlignment="Center"/>
                <Border Grid.Column="1" Background="#0C0C0C" CornerRadius="3" Padding="8,5">
                  <TextBox x:Name="LblKbArgs" IsReadOnly="True" BorderThickness="0" Background="Transparent" Foreground="#D7FFD7" FontFamily="Consolas" FontSize="12" TextWrapping="Wrap"/>
                </Border>
                <Button Grid.Column="2" x:Name="BtnKbUse" Content="Use these args" Padding="12,4" Margin="10,0,0,0" VerticalAlignment="Center"/>
              </Grid>
              <Grid x:Name="PnlKbUninst" Margin="0,6,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="Uninstall args" Foreground="#B7BEC8" FontSize="12" VerticalAlignment="Center"/>
                <Border Grid.Column="1" Background="#0C0C0C" CornerRadius="3" Padding="8,5">
                  <TextBox x:Name="LblKbUninst" IsReadOnly="True" BorderThickness="0" Background="Transparent" Foreground="#FFE7C2" FontFamily="Consolas" FontSize="12" TextWrapping="Wrap"/>
                </Border>
                <Button Grid.Column="2" x:Name="BtnKbUseUninst" Content="Use" Padding="12,4" Margin="10,0,0,0" VerticalAlignment="Center"/>
              </Grid>
              <TextBox x:Name="LblKbNote" Foreground="#DCDCAA" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0" Visibility="Collapsed" Style="{DynamicResource PbCopyText}"/>
              <Button x:Name="BtnProbeHelp" Content="Probe installer for /? help" Padding="10,3" Margin="0,8,0,0" HorizontalAlignment="Left" Visibility="Collapsed"
                      ToolTip="Run the installer with /? /help --help -h and capture any usage text it prints, shown here. Best-effort: a GUI installer may ignore these and just open a window (close it). Runs NON-elevated; only offered when nothing else identifies the switches."/>
              <TextBox x:Name="LblKbSrc" Foreground="#A0A8B4" FontSize="11" TextWrapping="Wrap" Margin="0,6,0,0" Style="{DynamicResource PbCopyText}"/>
            </StackPanel>
            </Border>
          </StackPanel>

          <!-- SECTION: Per-installer arguments (several installers; SecMulti follows PnlMultiArgs' visibility) -->
          <StackPanel x:Name="SecMulti" Margin="0,0,0,22">
            <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE71D;" Foreground="#56C8D6"/><TextBlock Text="Per-installer arguments" Style="{DynamicResource PbSectionTitle}"/></StackPanel>
            <TextBlock x:Name="LblMultiArgs" Style="{DynamicResource PbSectionDesc}" Text="In install order. Each EXE gets its own argument boxes; each MSI uses its transform."/>
            <Border Style="{DynamicResource PbSectionRule}"/>
            <StackPanel x:Name="PnlMultiArgs"/>
          </StackPanel>

          <!-- SECTION: Analysis (any real installer; SecAnalysis follows PnlSnapshot's visibility) -->
          <StackPanel x:Name="SecAnalysis" Margin="0,0,0,22">
            <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE9D9;" Foreground="#56C8D6"/><TextBlock Text="Analysis" Style="{DynamicResource PbSectionTitle}"/></StackPanel>
            <TextBlock Style="{DynamicResource PbSectionDesc}" Text="When the switches are unknown: snapshot this machine, run the installer, snapshot again. The tool lists everything it created and derives the uninstall command and product code. This really installs on THIS machine."/>
            <Border Style="{DynamicResource PbSectionRule}"/>
            <!-- Snapshot analysis: works for ANY installer (lone EXE, MSI, or several) - before/after diff of the machine. -->
            <StackPanel x:Name="PnlSnapshot" Orientation="Horizontal">
              <Button x:Name="BtnSnapshot" ToolTip="Snapshot this machine, you run the installer, snapshot again - the tool reports EVERYTHING the installer created (programs, services, tasks, shortcuts, drivers, certs...) and derives the uninstall command + product code. WARNING: this actually installs on THIS machine - clean up afterwards.">
                <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE9D9;"/><TextBlock Text="Analyze installer (snapshot)..."/></StackPanel>
              </Button>
              <TextBox x:Name="LblSnapshot" Foreground="#B7BEC8" FontSize="12" TextWrapping="Wrap" VerticalAlignment="Center" Margin="12,0,0,0" MaxWidth="560" Style="{DynamicResource PbCopyText}"/>
            </StackPanel>
            <!-- Wrapper EXE that bundles an MSI: extract it (no install) and build a clean MSI+MST package. Hidden for now. -->
            <StackPanel x:Name="PnlBundled" Orientation="Horizontal" Margin="0,8,0,0">
              <Button x:Name="BtnBundledMsi" Content="Check for bundled MSI..."
                      ToolTip="See if this EXE is a wrapper that bundles an MSI. If so (and the wrapper does nothing else), extract the MSI and build an MSI+MST package instead. Static check - it does NOT run the installer; needs 7-Zip to extract."/>
              <Button x:Name="BtnCaptureMsi" Content="Run &amp; capture MSI..." Margin="8,0,0,0"
                      ToolTip="For installers that BUILD the MSI at runtime: you run the EXE (it extracts the MSI to a temp folder - you don't have to finish installing), and the tool grabs the dropped MSI. WARNING: this actually runs the installer on THIS machine."/>
              <TextBox x:Name="LblBundled" Foreground="#B7BEC8" FontSize="12" TextWrapping="Wrap" VerticalAlignment="Center" Margin="12,0,0,0" MaxWidth="480" Style="{DynamicResource PbCopyText}"/>
            </StackPanel>
          </StackPanel>

          <!-- Per-user configuration lives in the Analyze window (Show-SnapshotDialog), next to the HKCU/profile
               findings that inform it. -->

          <!-- SECTION: Loose files (source treated as loose files; SecLoose follows PnlLoose's visibility) -->
          <StackPanel x:Name="SecLoose" Margin="0,0,0,22">
            <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE8B7;" Foreground="#56C8D6"/><TextBlock Text="Loose files" Style="{DynamicResource PbSectionTitle}"/></StackPanel>
            <TextBlock Style="{DynamicResource PbSectionDesc}" Text="No installer - the files are copied to the install path. Choose what the package should register so the app is findable and removable."/>
            <Border Style="{DynamicResource PbSectionRule}"/>
            <StackPanel x:Name="PnlLoose">
              <CheckBox x:Name="ChkArp" Content="Create ARP / Application Wizard entry (Set-ApplicationWizardEntry)" Foreground="#E7E9ED" Margin="0,3"/>
              <CheckBox x:Name="ChkLooseShortcut" Content="Create Start Menu shortcut(s)" Foreground="#E7E9ED" Margin="0,3"/>
              <TextBlock Text="Shortcut target exe(s), relative to the install path - comma separated (e.g. bin\App.exe, Helper.exe)" Foreground="#E7E9ED" Margin="0,8,0,4"/>
              <TextBox x:Name="TxtLooseTargets" Height="28" FontFamily="Consolas" MaxWidth="620" HorizontalAlignment="Left" MinWidth="620"/>
            </StackPanel>
          </StackPanel>
        </StackPanel>
      </ScrollViewer>

      <!-- STEP 3: editor -->
      <Grid x:Name="P3" Grid.Row="0" Visibility="Collapsed">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <!-- Buttons are allocated FIRST (docked right) so a LONG header/warning text can never push them
             out of view; the header is the fill child and TRIMS with an ellipsis (full text on hover). -->
        <!-- Toolbar on the strip surface: file name (glyph + Consolas, trims with an ellipsis) left, actions right. -->
        <DockPanel Grid.Row="0" Background="#21242B" LastChildFill="True">
          <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" Margin="0,6,10,6">
            <Button x:Name="BtnLoadScript" Padding="10,3" Margin="0,0,8,0"
                    ToolTip="Load an existing Invoke-AppDeployToolkit.ps1 / Deploy-Application.ps1 into this editor to tweak and save back - no need to open it externally after testing.">
              <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE8E5;"/><TextBlock Text="Load .ps1..."/></StackPanel>
            </Button>
            <Button x:Name="BtnSaveScript" Padding="10,3" Margin="0,0,8,0" IsEnabled="False"
                    ToolTip="Save your edits back to the loaded .ps1 (enabled only after Load .ps1).">
              <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE74E;"/><TextBlock Text="Save changes"/></StackPanel>
            </Button>
            <Button x:Name="BtnReview" Padding="10,3" Margin="0,0,8,0"
                    ToolTip="Open the items that need your attention before this package is complete (missing silent switches, predecessor-MST changes carried over, etc.). Re-scans the current script each time.">
              <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE7BA;"/><TextBlock Text="Review"/></StackPanel>
            </Button>
            <Button x:Name="BtnRebuild" Padding="10,3" ToolTip="Throw away edits and regenerate the script from the Info and Configure steps.">
              <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE72C;"/><TextBlock Text="Rebuild from inputs"/></StackPanel>
            </Button>
          </StackPanel>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="16,0,8,0"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE70F;" Foreground="#56C8D6"/><TextBlock x:Name="LblScriptHdr" Text="Invoke-AppDeployToolkit.ps1" Foreground="#E7E9ED" VerticalAlignment="Center" FontFamily="Consolas" FontSize="12.5" TextTrimming="CharacterEllipsis"/></StackPanel>
        </DockPanel>
        <Grid Grid.Row="1">
          <Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Border Grid.Column="0" Background="#1E2128" BorderBrush="#2A2F38" BorderThickness="0,1,1,0">
            <DockPanel>
              <TextBlock DockPanel.Dock="Top" Text="SECTIONS" Foreground="#A0A8B4" FontSize="10" FontWeight="SemiBold" Margin="12,10,0,6"/>
              <ListBox x:Name="LstAnchors" Background="Transparent" Foreground="#E7E9ED" BorderThickness="0" FontSize="12" Margin="6,0,6,6"/>
            </DockPanel>
          </Border>
          <Border x:Name="EditorHost" Grid.Column="1" Background="#181A1F"/>
        </Grid>
        <!-- Snippets drawer (collapsible): category + search + list (left) and a preview (right). -->
        <Expander x:Name="ExpSnippets" Grid.Row="2" IsExpanded="False" Background="#21242B" Foreground="#E7E9ED" BorderBrush="#2A2F38" BorderThickness="0,1,0,0" Padding="6,4">
          <Expander.Header><StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE8F1;" Foreground="#56C8D6"/><TextBlock Text="Snippets" FontWeight="SemiBold" VerticalAlignment="Center"/><TextBlock Text="reusable PSADT blocks - insert at the cursor" Foreground="#A0A8B4" FontSize="11.5" VerticalAlignment="Center" Margin="12,0,0,0"/></StackPanel></Expander.Header>
          <Grid Height="230" Margin="10">
            <Grid.ColumnDefinitions><ColumnDefinition Width="320"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Grid Grid.Column="0" Margin="0,0,10,0">
              <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <ComboBox x:Name="CmbSnipCat" Grid.Row="0" Margin="0,0,0,4"/>
              <TextBox  x:Name="TxtSnipSearch" Grid.Row="1" Margin="0,0,0,4" ToolTip="Search snippets..."/>
              <ListBox  x:Name="LstSnippets" Grid.Row="2" Background="#181A1F" Foreground="#E7E9ED" FontSize="12"/>
            </Grid>
            <Grid Grid.Column="1">
              <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
              <Border Grid.Row="0" Background="#181A1F" BorderBrush="#2F343D" BorderThickness="1" CornerRadius="5">
                <ScrollViewer HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto" Padding="8">
                  <TextBlock x:Name="TxtSnipPreview" Foreground="#E7E9ED" FontFamily="Cascadia Mono, Consolas" FontSize="12" TextWrapping="NoWrap"/>
                </ScrollViewer>
              </Border>
              <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
                <Button x:Name="BtnAddSnip" Content="Add..." Padding="12,5" Margin="0,0,6,0" ToolTip="Save a new snippet into snippets.json (paste code, name it, pick a category) - no hand-editing JSON."/>
                <Button x:Name="BtnEditSnip" Content="Edit..." Padding="12,5" Margin="0,0,6,0" ToolTip="Edit the selected snippet (name / category / code) and save it back."/>
                <Button x:Name="BtnDelSnip" Content="Delete" Padding="12,5" Margin="0,0,6,0" ToolTip="Remove the selected snippet from snippets.json."/>
                <Button x:Name="BtnInsertSnip" Padding="14,5"><StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE710;"/><TextBlock Text="Insert at cursor"/></StackPanel></Button>
              </StackPanel>
            </Grid>
          </Grid>
        </Expander>
      </Grid>
      <Grid x:Name="P4" Grid.Row="0" Margin="22,10,22,6" Visibility="Collapsed">
        <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TabControl x:Name="TabsP4" Grid.Row="0" Background="#181A1F" BorderThickness="0" Foreground="#E7E9ED" Padding="0,8,0,0">
          <TabControl.Resources>
            <Style TargetType="TabItem">
              <Setter Property="Foreground" Value="#C8C8C8"/>
              <Setter Property="FontSize" Value="13"/>
              <Setter Property="Template">
                <Setter.Value>
                  <ControlTemplate TargetType="TabItem">
                    <!-- same pill language as the step strip: current = teal-tinted, others quiet -->
                    <Border x:Name="Bd" Background="Transparent" BorderBrush="Transparent" BorderThickness="1" CornerRadius="5" Margin="0,0,6,6" Padding="14,6">
                      <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#2A2E36"/></Trigger>
                      <Trigger Property="IsSelected" Value="True">
                        <Setter TargetName="Bd" Property="Background" Value="#1C3A42"/>
                        <Setter TargetName="Bd" Property="BorderBrush" Value="#2BA6B8"/>
                        <Setter Property="Foreground" Value="#F2F4F7"/>
                        <Setter Property="FontWeight" Value="SemiBold"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </Setter.Value>
              </Setter>
            </Style>
          </TabControl.Resources>
        <TabItem Header="Review &amp; Create">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel Margin="8,4,8,8" MaxWidth="1100" HorizontalAlignment="Left">
          <!-- BUILD SUMMARY: what Create will assemble, as label/value rows (filled by Populate-Step4), then the
               review items in their own amber block. Replaces the old Consolas dump. -->
          <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE8FB;" Foreground="#56C8D6"/><TextBlock Text="Build summary" Style="{DynamicResource PbSectionTitle}"/></StackPanel>
          <TextBlock Style="{DynamicResource PbSectionDesc}" Text="What Create will assemble from the previous steps. Press Create at the bottom right when it looks right."/>
          <Border Style="{DynamicResource PbSectionRule}"/>
          <Border Background="#1E2128" BorderBrush="#2A2F38" BorderThickness="1" CornerRadius="6" Padding="18,12">
            <Grid x:Name="PnlSummary">
              <Grid.ColumnDefinitions><ColumnDefinition Width="128"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            </Grid>
          </Border>
          <Border x:Name="PnlReviewItems" Background="#26231A" BorderBrush="#4A4020" BorderThickness="1" CornerRadius="6" Padding="16,11" Margin="0,10,0,0" Visibility="Collapsed">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,6"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE7BA;" Foreground="#E0BE7C"/><TextBlock x:Name="LblReviewHdr" Text="Needs your review" Foreground="#E0BE7C" FontWeight="SemiBold" VerticalAlignment="Center"/></StackPanel>
              <TextBox x:Name="LblReview" Foreground="#E7E9ED" FontSize="12.5" TextWrapping="Wrap" Style="{DynamicResource PbCopyText}"/>
              <TextBlock Foreground="#B7BEC8" FontSize="11.5" TextWrapping="Wrap" Margin="0,6,0,0" Text="The package still builds - fix script items on the Editor step, then Rebuild. Tick 'Confirmed' in Review once you have looked at an item."/>
            </StackPanel>
          </Border>
          <!-- Brand outgoing prefix (GPF: INA=Gpf / VWG=Group package / G1V=VW). Hidden when the brand has none. -->
          <StackPanel x:Name="PnlOutPrefix" Orientation="Horizontal" Margin="0,12,0,0" Visibility="Collapsed">
            <TextBlock Text="Outgoing prefix" Foreground="#E7E9ED" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <ComboBox x:Name="CmbOutPrefix" Width="240" Height="28"/>
          </StackPanel>
          <TextBox x:Name="LblCreateResult" Foreground="#6A9955" FontFamily="Consolas" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0" Style="{DynamicResource PbCopyText}"/>
          <StackPanel Orientation="Horizontal" Margin="0,10,0,0" HorizontalAlignment="Left">
            <Button x:Name="BtnCopyOutgoing" Margin="0,0,8,0"
                    ToolTip="Copy the created package to the Outgoing share (settings.json -&gt; OutgoingPath). Asks before replacing if it is already there.">
              <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE8B7;"/><TextBlock Text="Copy package to Outgoing share..."/></StackPanel>
            </Button>
            <Button x:Name="BtnTsShots" Padding="10,4"
                    ToolTip="Launch this package's Start-Menu shortcuts on this machine and screenshot each. The package must be INSTALLED on this machine first (Create, then Install below) - the shortcuts only exist after that.">
              <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE722;"/><TextBlock Text="Screenshot shortcuts (this machine)"/></StackPanel>
            </Button>
            <TextBlock Text="install the created package on this machine first - the shortcuts exist only after that" Foreground="#A0A8B4" FontSize="11.5" VerticalAlignment="Center" Margin="10,0,0,0"/>
          </StackPanel>
          <TextBlock Text="Test on THIS machine - runs the same install/uninstall/repair command the deployment uses, against the CREATED package (or a Loaded .ps1's folder):" Foreground="#56C8D6" FontSize="12" TextWrapping="Wrap" Margin="0,10,0,4"/>
          <StackPanel Orientation="Horizontal" Margin="0,2,0,0" HorizontalAlignment="Left">
            <TextBlock Text="Admin:" Foreground="#E7E9ED" VerticalAlignment="Center" Width="60"/>
            <Button x:Name="BtnAdminInstall"   Content="Install"   Padding="12,4" Margin="0,0,6,0" ToolTip="Run &quot;Invoke-AppDeployToolkit.exe install&quot; ELEVATED (admin) in the package Content folder."/>
            <Button x:Name="BtnAdminUninstall" Content="Uninstall" Padding="12,4" Margin="0,0,6,0" ToolTip="Run the package's uninstall ELEVATED (admin)."/>
            <Button x:Name="BtnAdminRepair"    Content="Repair"    Padding="12,4" Margin="0,0,6,0" ToolTip="Run the package's repair ELEVATED (admin)."/>
            <Button x:Name="BtnAdminCmd"       Content="CMD"       Padding="12,4" ToolTip="Open an ELEVATED command prompt in the package Content folder for manual testing."/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,6,0,0" HorizontalAlignment="Left">
            <TextBlock Text="SYSTEM:" Foreground="#E7E9ED" VerticalAlignment="Center" Width="60"/>
            <Button x:Name="BtnSysInstall"   Content="Install"   Padding="12,4" Margin="0,0,6,0" ToolTip="Run the install as SYSTEM/LocalSystem via PsExec (-s), in the package Content folder."/>
            <Button x:Name="BtnSysUninstall" Content="Uninstall" Padding="12,4" Margin="0,0,6,0" ToolTip="Run the uninstall as SYSTEM via PsExec (-s)."/>
            <Button x:Name="BtnSysRepair"    Content="Repair"    Padding="12,4" Margin="0,0,6,0" ToolTip="Run the repair as SYSTEM via PsExec (-s)."/>
            <Button x:Name="BtnSystemCmd"    Content="CMD"       Padding="12,4" ToolTip="Open a SYSTEM/LocalSystem command prompt in the package Content folder."/>
          </StackPanel>
        </StackPanel>
        </ScrollViewer>
        </TabItem>
        <TabItem Header="Integration" x:Name="TabIntegration">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel Margin="8">
          <TextBlock Text="Publish to SCCM / Intune" Foreground="#56C8D6" FontWeight="Bold" FontSize="14" Margin="0,0,0,8"/>
          <TextBlock Text="Use the package just created above, OR load an existing one by name from the Outgoing share (no build needed)." Foreground="#A0A8B4" FontSize="11" Margin="0,0,0,8"/>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
            <TextBlock Text="Package name:" Foreground="#E7E9ED" VerticalAlignment="Center" Margin="0,0,8,0"/>
            <TextBox x:Name="TxtPubPkgName" Width="330" Height="24" FontFamily="Consolas" VerticalContentAlignment="Center"/>
            <Button x:Name="BtnLoadOutgoing" Content="Load from Outgoing" Padding="10,4" Margin="8,0,0,0"/>
            <Button x:Name="BtnBrowsePkg" Content="Browse..." Padding="10,4" Margin="8,0,0,0"/>
          </StackPanel>
          <StackPanel x:Name="PnlPublish" IsEnabled="False">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Grid.RowDefinitions><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="0"/><RowDefinition Height="30"/><RowDefinition Height="30"/></Grid.RowDefinitions>
              <TextBlock Grid.Row="0" Grid.Column="0" Text="Product name"     Foreground="#E7E9ED" VerticalAlignment="Center"/>
              <TextBox   Grid.Row="0" Grid.Column="1" x:Name="TxtPubProductName" Height="24" FontFamily="Consolas" Margin="0,2" ToolTip="Display name - Intune displayName + SCCM localized name/keyword. Auto-filled from the package; editable."/>
              <TextBlock Grid.Row="1" Grid.Column="0" Text="Publisher"        Foreground="#E7E9ED" VerticalAlignment="Center"/>
              <TextBox   Grid.Row="1" Grid.Column="1" x:Name="TxtPubPublisher"   Height="24" FontFamily="Consolas" Margin="0,2"/>
              <TextBlock Grid.Row="2" Grid.Column="0" Text="Version"          Foreground="#E7E9ED" VerticalAlignment="Center"/>
              <TextBox   Grid.Row="2" Grid.Column="1" x:Name="TxtPubVersion"     Height="24" FontFamily="Consolas" Margin="0,2"/>
              <TextBlock Grid.Row="3" Grid.Column="0" Text="ProductCode"      Foreground="#E7E9ED" VerticalAlignment="Center"/>
              <TextBox   Grid.Row="3" Grid.Column="1" x:Name="TxtPubProductCode" Height="24" FontFamily="Consolas" Margin="0,2"/>
              <!-- Branding key is always automatic (SOFTWARE\VWG\CM\<name>) - kept hidden, never edited. -->
              <TextBlock Grid.Row="4" Grid.Column="0" Text="Branding key"     Foreground="#E7E9ED" VerticalAlignment="Center" Visibility="Collapsed"/>
              <TextBox   Grid.Row="4" Grid.Column="1" x:Name="TxtPubBrandingKey" Height="24" FontFamily="Consolas" Margin="0,2" Visibility="Collapsed"/>
              <TextBlock Grid.Row="5" Grid.Column="0" Text="Uninstall key"    Foreground="#E7E9ED" VerticalAlignment="Center"/>
              <TextBox   Grid.Row="5" Grid.Column="1" x:Name="TxtPubUninstallKey" Height="24" FontFamily="Consolas" Margin="0,2"/>
              <TextBlock Grid.Row="6" Grid.Column="0" Text="Detect version"   Foreground="#E7E9ED" VerticalAlignment="Center"/>
              <TextBox   Grid.Row="6" Grid.Column="1" x:Name="TxtPubDetectVersion" Height="24" FontFamily="Consolas" Margin="0,2"/>
            </Grid>
            <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
              <TextBlock Text="2nd detection:" Foreground="#E7E9ED" VerticalAlignment="Center" Margin="0,0,8,0"/>
              <ComboBox x:Name="CmbDetectType" Width="170" VerticalAlignment="Center">
                <ComboBoxItem Content="Version (default)" IsSelected="True"/>
                <ComboBoxItem Content="String"/>
                <ComboBoxItem Content="ProductCode"/>
                <ComboBoxItem Content="None (branding only)"/>
              </ComboBox>
            </StackPanel>
            <TextBlock Text="Commands (used by both SCCM and Intune; Repair is SCCM-only)" Foreground="#56C8D6" FontSize="12" Margin="0,8,0,2"/>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Grid.RowDefinitions><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/></Grid.RowDefinitions>
              <TextBlock Grid.Row="0" Grid.Column="0" Text="Install"   Foreground="#E7E9ED" VerticalAlignment="Center"/>
              <TextBox   Grid.Row="0" Grid.Column="1" x:Name="TxtPubInstall"   Height="24" FontFamily="Consolas" Margin="0,2"/>
              <TextBlock Grid.Row="1" Grid.Column="0" Text="Uninstall" Foreground="#E7E9ED" VerticalAlignment="Center"/>
              <TextBox   Grid.Row="1" Grid.Column="1" x:Name="TxtPubUninstall" Height="24" FontFamily="Consolas" Margin="0,2"/>
              <TextBlock Grid.Row="2" Grid.Column="0" Text="Repair (SCCM)" Foreground="#E7E9ED" VerticalAlignment="Center"/>
              <TextBox   Grid.Row="2" Grid.Column="1" x:Name="TxtPubRepair"  Height="24" FontFamily="Consolas" Margin="0,2"/>
            </Grid>
            <TextBlock Text="Description" Foreground="#E7E9ED" Margin="0,6,0,2"/>
            <TextBox x:Name="TxtPubDescription" Height="60" FontFamily="Consolas" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
            <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
              <!-- CreatePanel = create-only controls; shown only when a package is loaded for creation. -->
              <StackPanel x:Name="CreatePanel" Orientation="Horizontal" Visibility="Collapsed">
                <CheckBox x:Name="ChkPubAllowInteract" Content="Allow user to view/interact (SCCM)" Foreground="#E7E9ED" IsChecked="True" VerticalAlignment="Center" Margin="0,0,16,0"/>
                <Button x:Name="BtnCreateSccm"   Content="Create in SCCM"   Padding="10,4" Margin="0,0,8,0"/>
                <Button x:Name="BtnCreateIntune" Content="Create in Intune" Padding="10,4" Margin="0,0,8,0"/>
              </StackPanel>
              <Button x:Name="BtnOpenCmTrace"  Content="Open log (CMTrace)" Padding="10,4" Margin="0,0,8,0"/>
              <Button x:Name="BtnOpenWork"     Content="Open work folder" Padding="10,4" Margin="0,0,8,0"/>
              <!-- LOCAL shortcut screenshots (BtnTsShots) live on the Review & Create tab (test the package you just
                   built, right after Admin/SYSTEM CMD). REMOTE screenshots (BtnRemoteShots) live on Troubleshoot. -->
            </StackPanel>
          </StackPanel>
          <!-- Modify section + progress live OUTSIDE PnlPublish so they work without a loaded package. -->
            <Border BorderBrush="#4EC9B0" BorderThickness="0,2,0,0" Margin="0,16,0,0" Padding="0,12,0,0">
              <StackPanel>
                <TextBlock Text="Modify an existing SCCM application" Foreground="#4EC9B0" FontWeight="Bold" FontSize="14"/>
                <TextBlock Text="Independent of the Create fields above. Branding key stays automatic and is never shown." Foreground="#A0A8B4" FontSize="11" TextWrapping="Wrap" Margin="0,2,0,8"/>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" Text="Application name" Foreground="#E7E9ED" VerticalAlignment="Center"/>
                  <TextBox   Grid.Column="1" x:Name="TxtModAppName" Height="24" FontFamily="Consolas" Margin="0,2,8,2"/>
                  <Button    Grid.Column="2" x:Name="BtnFetchDetection" Content="Fetch detection" Padding="10,4"/>
                </Grid>
                <TextBlock Text="Detection - 2nd clause only (branding is automatic):" Foreground="#56C8D6" FontSize="12" Margin="0,10,0,4"/>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <Grid.RowDefinitions><RowDefinition Height="32"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/></Grid.RowDefinitions>
                  <TextBlock Grid.Row="0" Grid.Column="0" Text="Type" Foreground="#E7E9ED" VerticalAlignment="Center"/>
                  <StackPanel Grid.Row="0" Grid.Column="1" Orientation="Horizontal">
                    <ComboBox x:Name="CmbModDetectType" Width="180" VerticalAlignment="Center">
                      <ComboBoxItem Content="Version" IsSelected="True"/>
                      <ComboBoxItem Content="String"/>
                      <ComboBoxItem Content="ProductCode"/>
                      <ComboBoxItem Content="None (branding only)"/>
                    </ComboBox>
                    <CheckBox x:Name="ChkMod32Bit" Content="32-bit key on 64-bit Windows" Foreground="#E7E9ED" VerticalAlignment="Center" Margin="16,0,0,0"/>
                  </StackPanel>
                  <TextBlock Grid.Row="1" Grid.Column="0" Text="Uninstall key" Foreground="#E7E9ED" VerticalAlignment="Center"/>
                  <TextBox   Grid.Row="1" Grid.Column="1" x:Name="TxtModUninstallKey" Height="24" FontFamily="Consolas" Margin="0,2"/>
                  <TextBlock Grid.Row="2" Grid.Column="0" Text="Detect version" Foreground="#E7E9ED" VerticalAlignment="Center"/>
                  <TextBox   Grid.Row="2" Grid.Column="1" x:Name="TxtModDetectVersion" Height="24" FontFamily="Consolas" Margin="0,2"/>
                  <TextBlock Grid.Row="3" Grid.Column="0" Text="Product code" Foreground="#E7E9ED" VerticalAlignment="Center"/>
                  <TextBox   Grid.Row="3" Grid.Column="1" x:Name="TxtModProductCode" Height="24" FontFamily="Consolas" Margin="0,2"/>
                </Grid>
                <Grid Margin="0,10,0,0">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" Text="Content source" Foreground="#E7E9ED" VerticalAlignment="Center"/>
                  <TextBox   Grid.Column="1" x:Name="TxtModContentSrc" Height="24" FontFamily="Consolas" Margin="0,2,8,2" ToolTip="For Update content. Blank = auto-find this package by name in Outgoing. Or browse/paste a package folder (SCCM and Intune sources can differ)."/>
                  <Button    Grid.Column="2" x:Name="BtnModBrowseSrc" Content="Browse..." Padding="10,4"/>
                </Grid>
                <CheckBox x:Name="ChkModRefreshOnly" Content="Content already in prelive - just refresh the DPs (don't copy)" Foreground="#E7E9ED" Margin="150,6,0,0" ToolTip="Check this when you updated the prelive content yourself. The tool will NOT copy anything - it only refreshes the existing content on the distribution points. The Content source above is ignored."/>
                <StackPanel Orientation="Horizontal" Margin="0,12,0,0">
                  <Button x:Name="BtnUpdateDetection" Content="Update detection" Padding="10,4" Margin="0,0,8,0"/>
                  <Button x:Name="BtnUpdateContent"   Content="Update content"   Padding="10,4" Margin="0,0,8,0"/>
                  <Button x:Name="BtnContentStatus"   Content="Content status"   Padding="10,4" Margin="0,0,8,0" ToolTip="Per-DP state + the real last-update time."/>
                  <Button x:Name="BtnDeleteApp"       Content="Delete app"       Padding="10,4" Background="#5A1D1D" Foreground="#F0C0C0"/>
                </StackPanel>
                <TextBlock Text="Fetch loads the app's current detection to edit; Update detection replaces only that clause. Update content refreshes prelive (or just the DPs when ticked). Hover a button for details." Foreground="#A0A8B4" FontSize="10" TextWrapping="Wrap" Margin="0,8,0,0"/>
              </StackPanel>
            </Border>
        </StackPanel>
        </ScrollViewer>
        </TabItem>

        <TabItem Header="Testing" x:Name="TabTesting">
        <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="12">
          <TextBlock Text="Testing - add machines to the app's TEST collections and refresh client policy" Foreground="#56C8D6" FontWeight="Bold" FontSize="14" Margin="0,0,0,10"/>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Grid.RowDefinitions><RowDefinition Height="34"/><RowDefinition Height="34"/></Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Grid.Column="0" Text="Application name" Foreground="#E7E9ED" VerticalAlignment="Center"/>
            <TextBox   Grid.Row="0" Grid.Column="1" x:Name="TxtTestAppName" Height="24" FontFamily="Consolas" Margin="0,2"/>
            <TextBlock Grid.Row="1" Grid.Column="0" Text="Machine name(s)" Foreground="#E7E9ED" VerticalAlignment="Center"/>
            <StackPanel Grid.Row="1" Grid.Column="1" Orientation="Horizontal">
              <TextBox x:Name="TxtTestMachine" Width="220" Height="24" FontFamily="Consolas" VerticalContentAlignment="Center" ToolTip="Type one or more machine names (comma/space separated, no domain suffix), then Add to list"/>
              <Button x:Name="BtnTestAddList" Content="Add to list" Padding="10,3" Margin="8,0,0,0"/>
              <TextBlock Text="Collection:" Foreground="#E7E9ED" VerticalAlignment="Center" Margin="12,0,6,0"/>
              <ComboBox x:Name="CmbTestAction" Width="130" VerticalAlignment="Center">
                <ComboBoxItem Content="Install" IsSelected="True"/>
                <ComboBoxItem Content="Uninstall"/>
              </ComboBox>
            </StackPanel>
          </Grid>
          <!-- List box on the left; the collection actions sit BESIDE it (not below) - compact + tidy. -->
          <Grid Margin="0,6,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Machines list" Foreground="#E7E9ED" VerticalAlignment="Top" Margin="0,4,0,0"/>
            <StackPanel Grid.Column="1">
              <ListBox x:Name="LstTestMachines" Width="300" Height="112" Background="#21242B" Foreground="#E7E9ED" FontFamily="Consolas" FontSize="12"/>
              <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                <Button x:Name="BtnTestRemoveSel" Content="Remove selected" Padding="8,2" Margin="0,0,8,0" FontSize="11"/>
                <Button x:Name="BtnTestClearList" Content="Clear list" Padding="8,2" FontSize="11"/>
              </StackPanel>
            </StackPanel>
            <StackPanel Grid.Column="2" VerticalAlignment="Top" Margin="14,0,0,0" MaxWidth="230">
              <Button x:Name="BtnAddTestMachine"    Content="Add to collection"      Padding="10,5" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
              <Button x:Name="BtnRemoveTestMachine" Content="Remove from collection" Padding="10,5" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
              <Button x:Name="BtnRunMachinePolicy"  Content="Run machine policy"      Padding="10,5" HorizontalAlignment="Stretch"/>
            </StackPanel>
          </Grid>
          <TextBlock Text="Add machines to the list, then Add/Remove/Run policy acts on ALL of them (against &lt;app&gt;-INSTALL/UNINSTALL TEST). Add and Remove are independent - adding to Uninstall does not remove from Install." Foreground="#A0A8B4" FontSize="10" TextWrapping="Wrap" Margin="0,10,0,0"/>
          <Border BorderBrush="#3C3C3C" BorderThickness="0,1,0,0" Margin="0,16,0,0" Padding="0,12,0,0">
            <StackPanel>
              <TextBlock Text="Intune operations (assignment + content) - app resolved by App ID, else branding key" Foreground="#4EC9B0" FontWeight="Bold" FontSize="13"/>
              <Grid Margin="0,8,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <Grid.RowDefinitions><RowDefinition Height="34"/><RowDefinition Height="34"/><RowDefinition Height="34"/><RowDefinition Height="34"/></Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Grid.Column="0" Text="App ID (preferred)" Foreground="#E7E9ED" VerticalAlignment="Center"/>
                <TextBox   Grid.Row="0" Grid.Column="1" Grid.ColumnSpan="2" x:Name="TxtIntuneAppId" Height="24" FontFamily="Consolas" Margin="0,2" ToolTip="The Intune app's id (GUID). If set, it is used directly. Leave blank to match by branding key (package name) below."/>
                <TextBlock Grid.Row="1" Grid.Column="0" Text="App name (fallback)" Foreground="#E7E9ED" VerticalAlignment="Center"/>
                <TextBox   Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2" x:Name="TxtIntuneAssignApp" Height="24" FontFamily="Consolas" Margin="0,2" ToolTip="Full package name - used when no App ID is given: the app is matched by its branding key (..\VWG\CM\&lt;name&gt;). No display-name guessing."/>
                <TextBlock Grid.Row="2" Grid.Column="0" Text="Group (name or ID)" Foreground="#E7E9ED" VerticalAlignment="Center"/>
                <TextBox   Grid.Row="2" Grid.Column="1" Grid.ColumnSpan="2" x:Name="TxtIntuneGroupId" Height="24" FontFamily="Consolas" Margin="0,2" ToolTip="Azure AD group display name OR Object ID. A name is looked up automatically (needs group-read on your sign-in; if not, paste the Object ID)."/>
                <TextBlock Grid.Row="3" Grid.Column="0" Text="Content source" Foreground="#E7E9ED" VerticalAlignment="Center"/>
                <TextBox   Grid.Row="3" Grid.Column="1" x:Name="TxtIntuneContentSrc" Height="24" FontFamily="Consolas" Margin="0,2,8,2" ToolTip="For Update content: the package folder to upload (its Content + Icons). Can differ from the SCCM source."/>
                <Button    Grid.Row="3" Grid.Column="2" x:Name="BtnIntuneBrowseSrc" Content="Browse..." Padding="10,4"/>
              </Grid>
              <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                <Button x:Name="BtnIntuneAssignAvail" Content="Add 'Available' assignment" Padding="10,4" Margin="0,0,8,0"/>
                <Button x:Name="BtnIntuneUnassign"    Content="Remove assignment"          Padding="10,4" Margin="0,0,8,0"/>
                <Button x:Name="BtnIntuneUpdateContent" Content="Update content"           Padding="10,4"/>
              </StackPanel>
              <TextBlock Text="Add/Remove change only this group's assignment. Update content uploads a new version and re-applies the icon. Nothing else on the app is touched." Foreground="#A0A8B4" FontSize="10" TextWrapping="Wrap" Margin="0,6,0,0"/>
            </StackPanel>
          </Border>
        </StackPanel></ScrollViewer>
        </TabItem>

        <TabItem Header="Troubleshoot" Visibility="Collapsed">
        <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="12">
          <TextBlock Text="Troubleshoot - pull a target machine's logs and open them in CMTrace" Foreground="#56C8D6" FontWeight="Bold" FontSize="14" Margin="0,0,0,10"/>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Grid.RowDefinitions><RowDefinition Height="34"/><RowDefinition Height="34"/></Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Grid.Column="0" Text="Machine name" Foreground="#E7E9ED" VerticalAlignment="Center"/>
            <TextBox   Grid.Row="0" Grid.Column="1" x:Name="TxtTsMachine" Height="24" FontFamily="Consolas" Margin="0,2" ToolTip="Target machine (no domain suffix)"/>
            <TextBlock Grid.Row="1" Grid.Column="0" Text="Application name" Foreground="#E7E9ED" VerticalAlignment="Center"/>
            <TextBox   Grid.Row="1" Grid.Column="1" x:Name="TxtTsAppName" Height="24" FontFamily="Consolas" Margin="0,2" ToolTip="Used for the install/uninstall (PSADT) log under ProgramData\VWG\Logs\&lt;app&gt;"/>
          </Grid>
          <StackPanel Orientation="Horizontal" Margin="0,14,0,0">
            <Button x:Name="BtnLogDiscovery" Content="AppDiscovery log"       Padding="10,4" Margin="0,0,8,0"/>
            <Button x:Name="BtnLogEnforce"   Content="AppEnforce log"         Padding="10,4" Margin="0,0,8,0"/>
            <Button x:Name="BtnLogPackage"   Content="Package logs..."  Padding="10,4" ToolTip="List the app's package logs (install/uninstall/repair) to open one."/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
            <Button x:Name="BtnRemoteShots" Content="Remote screenshots (target machine)" Padding="10,4"
                    ToolTip="Launch the app's shortcuts on the target machine(s) named above and screenshot each. App must already be installed there."/>
          </StackPanel>
          <TextBlock Text="Remote screenshots: a visual smoke test on the target machine (app must already be installed there; locked RDP is fine). For THIS machine, use 'Screenshot shortcuts' on the Review &amp; Create tab. Hover any button for full details." Foreground="#A0A8B4" FontSize="10" TextWrapping="Wrap" Margin="0,8,0,0"/>
          <TextBlock Text="AppDiscovery = detection log, AppEnforce = install/uninstall log (from CCM\Logs). Package logs... lists the app's own PSADT logs (install / uninstall / repair). All are copied to the work folder and opened in CMTrace." Foreground="#A0A8B4" FontSize="10" TextWrapping="Wrap" Margin="0,10,0,0"/>
          <Border BorderBrush="#3C3C3C" BorderThickness="0,1,0,0" Margin="0,16,0,0" Padding="0,12,0,0">
            <StackPanel>
              <TextBlock Text="Members and install state" Foreground="#56C8D6" FontWeight="Bold" FontSize="13"/>
              <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                <TextBlock Text="Collection:" Foreground="#E7E9ED" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <ComboBox x:Name="CmbTsColl" Width="130" VerticalAlignment="Center">
                  <ComboBoxItem Content="Install" IsSelected="True"/>
                  <ComboBoxItem Content="Uninstall"/>
                </ComboBox>
                <Button x:Name="BtnTsShowMembers" Content="Show members"       Padding="10,4" Margin="10,0,0,0"/>
                <Button x:Name="BtnTsCheckState"  Content="Check install state" Padding="10,4" Margin="8,0,0,0"/>
                <Button x:Name="BtnTsReboot"      Content="Reboot machine"      Padding="10,4" Margin="8,0,0,0" Background="#5A1D1D" Foreground="#F0C0C0" ToolTip="Force-restart the machine named above (asks first)."/>
              </StackPanel>
              <ListBox x:Name="LstTsMembers" Height="110" Margin="0,8,0,0" Background="#21242B" Foreground="#E7E9ED" FontFamily="Consolas" FontSize="12"/>
              <TextBlock Text="Show members lists the collection's machines (click one to load it above). Check install state asks that machine whether the app is installed and whether it matches its collection." Foreground="#A0A8B4" FontSize="10" TextWrapping="Wrap" Margin="0,6,0,0"/>
            </StackPanel>
          </Border>
        </StackPanel></ScrollViewer>
        </TabItem>

        <TabItem Header="Dev &#8594; Test" x:Name="TabDevTest">
        <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="12">
          <TextBlock Text="Dev / Test movement (UAT) - move the app and its collections between folders" Foreground="#56C8D6" FontWeight="Bold" FontSize="14" Margin="0,0,0,10"/>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Application name" Foreground="#E7E9ED" VerticalAlignment="Center"/>
            <TextBox   Grid.Column="1" x:Name="TxtMoveAppName" Height="24" FontFamily="Consolas" Margin="0,2"/>
          </Grid>
          <StackPanel Orientation="Horizontal" Margin="0,14,0,0">
            <Button x:Name="BtnMoveToTest" Content="Move to TEST"     Padding="12,4" Margin="0,0,8,0"/>
            <Button x:Name="BtnMoveToDev"  Content="Move back to DEV" Padding="12,4"/>
          </StackPanel>
          <TextBlock Text="Move to TEST promotes the app + its collections to the TEST (UAT) folders; Move back to DEV returns them. Folders are set in settings.json." Foreground="#A0A8B4" FontSize="10" TextWrapping="Wrap" Margin="0,10,0,0"/>
        </StackPanel></ScrollViewer>
        </TabItem>
        </TabControl>

        <!-- Shared progress + status + copyable log for ALL Step-4 tabs. Background jobs report here: a thin line
             (same as the busy card's) + the current step as a sentence + the percentage at the right. Collapsed
             while there is nothing to say, so it never reserves empty space under the page. -->
        <StackPanel x:Name="PnlPublishStatus" Grid.Row="1" Margin="0,8,0,0" Visibility="Collapsed">
          <ProgressBar x:Name="PbPublish" Height="4" Minimum="0" Maximum="100" Value="0" Visibility="Collapsed"
                       Foreground="#2BA6B8" Background="#2A2E36" BorderThickness="0"/>
          <DockPanel Margin="0,6,0,0" LastChildFill="True">
            <TextBlock x:Name="LblPbPct" DockPanel.Dock="Right" Foreground="#A0A8B4" FontSize="11.5" VerticalAlignment="Center" Margin="12,0,0,0"/>
            <TextBox x:Name="LblPubStatus" Foreground="#56C8D6" FontSize="12.5" TextWrapping="Wrap" Style="{DynamicResource PbCopyText}"/>
          </DockPanel>
          <TextBox x:Name="LblPublishLog" Foreground="#CE9178" Background="Transparent" BorderThickness="0" Padding="0"
                   FontFamily="Consolas" FontSize="12" TextWrapping="Wrap" IsReadOnly="True" IsReadOnlyCaretVisible="True"
                   Margin="0,6,0,0" MaxHeight="110" VerticalScrollBarVisibility="Auto"/>
        </StackPanel>
      </Grid>

      <DockPanel Grid.Row="1" Background="#2A2E36" LastChildFill="False">
        <Button x:Name="BtnBack" Padding="14,5" Margin="14,8" DockPanel.Dock="Left" IsEnabled="False">
          <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE72B;"/><TextBlock Text="Back"/></StackPanel>
        </Button>
        <Button x:Name="BtnResetStep" Margin="0,8,6,8" DockPanel.Dock="Left">
          <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE7A7;"/><TextBlock Text="Reset step"/></StackPanel>
        </Button>
        <Button x:Name="BtnResetAll" Margin="0,8" DockPanel.Dock="Left">
          <StackPanel Orientation="Horizontal"><TextBlock Style="{DynamicResource PbGlyph}" Text="&#xE72C;"/><TextBlock Text="Reset all"/></StackPanel>
        </Button>
        <Button x:Name="BtnNext" Content="Next" Padding="16,5" Margin="14,8" DockPanel.Dock="Right"/>
        <!-- STATUS BAR: what the tool is working on RIGHT NOW. Empty when idle - a standing "Ready" reads as a button. -->
        <TextBox x:Name="LblStatusBar" DockPanel.Dock="Left" VerticalAlignment="Center" Margin="18,0,18,0"
                   Foreground="#A0A8B4" FontSize="11.5" Style="{DynamicResource PbCopyText}"/>
      </DockPanel>
    </Grid>
  </Grid>
</Window>
"@

$script:Win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
# SAFETY NET: an exception that escapes ANY WPF handler would end ShowDialog and close the tool (that is what
# "it just closed" always was). The dispatcher raises UnhandledException first; handling it there keeps the window,
# logs the error and tells the user in one box. The try/catch around ShowDialog at the end stays as the last line.
$script:Win.Dispatcher.add_UnhandledException({
    param($sender, $e)
    try {
        $e.Handled = $true
        $ex = $e.Exception; if ($ex.InnerException) { $ex = $ex.InnerException }
        $msg = "$($ex.Message)"
        try { Write-Log "Unhandled UI error (kept the window open): $msg`r`n$($e.Exception.StackTrace)" Error } catch {}
        try {
            $crash = Join-Path (Get-WorkPath 'Logs') 'PackageAssistance-crash.log'
            Add-Content -LiteralPath $crash -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  HANDLED  $($ex.GetType().Name): $msg`r`n$($e.Exception.StackTrace)`r`n" -Encoding UTF8
        } catch {}
        try { Hide-PBBusy } catch {}
        [Windows.MessageBox]::Show("Something went wrong in this step and was stopped:`r`n`r`n$msg`r`n`r`nThe tool stays open - you can carry on. Details are in the log.", 'Package Assistance', 'OK', 'Warning') | Out-Null
    } catch {}
})
if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $script:Win }   # modern theme for all controls
# Custom title-bar/taskbar icon: drop your icon at Lib\PackageBuilder.ico and it is picked up here.
# (Build-Exe.ps1 uses the SAME file for the compiled exe's icon, so both stay consistent.)
$icoPath = Join-Path $root 'Lib\PackageBuilder.ico'
if (Test-Path $icoPath) {
    try { $script:Win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri $icoPath)) }
    catch { Write-Log "Window icon load failed ($($_.Exception.Message)) - using default." Warning }
}
# Build stamp in the title: instantly answers "is my exe running the latest pak?" after an update.
try { $script:Win.Title = "$(if (Get-Command Get-PBToolName -EA SilentlyContinue) { Get-PBToolName } else { 'Package Assistance' })  -  build $($script:BuildStamp)" } catch {}
foreach ($n in 'N1','N2','N3','N4','S1','S2','S3','S4','G1','G2','G3','G4','ST1','ST2','ST3','ST4',
                'LblHdrPkg','PnlHdrRitm','LblHdrRitm','LblHdrRitmCaption','PnlHdrBrand','LblHdrBrand','LblOrigin','LblStatusBar','LblRitmExample',
                'SecMsi','SecExe','SecAnalysis','SecMulti','SecLoose','PnlKbInst','PnlPublishStatus','ChkCarryPredMst','LblNameLen','PnlSummary','PnlReviewItems','LblReviewHdr',
                'P1','P2','P3','P4','TabsP4','TxtPkg','LblParsed','BtnPred','BtnFetch','BtnAddInst','ChkAddUninstall',
                'LblReview','LblCreateResult','BtnCopyOutgoing','TxtPubPkgName','BtnLoadOutgoing','BtnBrowsePkg','PnlPublish','TxtPubProductName','TxtPubPublisher','TxtPubVersion','TxtPubProductCode',
                'TxtPubBrandingKey','TxtPubUninstallKey','TxtPubDetectVersion','TxtPubInstall','TxtPubUninstall','TxtPubRepair','TxtPubDescription','CmbDetectType','ChkPubAllowInteract',
                'CreatePanel','BtnCreateSccm','BtnCreateIntune','BtnOpenCmTrace','BtnOpenWork','PbPublish','LblPbPct','LblPubStatus','LblPublishLog',
                'BtnFetchDetection','BtnUpdateDetection','BtnUpdateContent','BtnContentStatus','BtnDeleteApp',
                'TxtModAppName','CmbModDetectType','ChkMod32Bit','TxtModUninstallKey','TxtModDetectVersion','TxtModProductCode','TxtModContentSrc','ChkModRefreshOnly','BtnModBrowseSrc',
                'TxtIntuneContentSrc','BtnIntuneBrowseSrc','BtnIntuneUpdateContent',
                'TxtTestAppName','TxtTestMachine','CmbTestAction','BtnAddTestMachine','BtnRemoveTestMachine','BtnRunMachinePolicy',
                'BtnTestAddList','LstTestMachines','BtnTestRemoveSel','BtnTestClearList','BtnMsiPropsView',
                'TxtIntuneAppId','TxtIntuneAssignApp','TxtIntuneGroupId','BtnIntuneAssignAvail','BtnIntuneUnassign',
                'TxtTsMachine','TxtTsAppName','BtnLogDiscovery','BtnLogEnforce','BtnLogPackage','BtnTsShots','BtnRemoteShots',
                'CmbTsColl','BtnTsShowMembers','BtnTsCheckState','BtnTsReboot','LstTsMembers',
                'TxtMoveAppName','BtnMoveToTest','BtnMoveToDev',
                'LblPred','LblSrc','LblInst','TxtType','TxtPC','ChkKeepShortcut','ChkKeepStartup','ChkKeepStray','ChkKeepRunKey','BtnMsiPropsView','BtnMatchPredMst','LblMatchMst','BtnBack','BtnNext','TxtRitm','CmbBrand',
                'LblRitmCaption','LblBrand','TabIntegration','TabTesting','TabDevTest','PnlOutPrefix','CmbOutPrefix',
                'PnlMstFlags','PnlMsiProps','TxtMsiProps','ChkGenerateMst',
                'LblExeParams','PnlExeParams','TxtInstArgs','TxtUninstArgs','PnlBundled','BtnBundledMsi','BtnCaptureMsi','LblBundled','PnlSnapshot','BtnSnapshot','LblSnapshot','PnlPerUser','CmbPerUser','LblPerUser','PnlKbHint','LblKbConf','LblKbArgs','LblKbNote','BtnProbeHelp','LblKbSrc','BtnKbUse','LblKbUninst','BtnKbUseUninst','PnlKbUninst','PnlLoose','ChkArp','ChkLooseShortcut','TxtLooseTargets',
                'LblMultiArgs','PnlMultiArgs',
                'BtnResetStep','BtnResetAll','BtnAdminCmd','BtnSystemCmd','BtnAdminInstall','BtnAdminUninstall','BtnAdminRepair','BtnSysInstall','BtnSysUninstall','BtnSysRepair',
                'LblScriptHdr','ExpSnippets','CmbSnipCat','TxtSnipSearch','LstSnippets','TxtSnipPreview','BtnInsertSnip','BtnAddSnip','BtnEditSnip','BtnDelSnip','BtnRebuild','BtnReview','BtnLoadScript','BtnSaveScript','LstAnchors','EditorHost') {
    Set-Variable -Name $n -Value $script:Win.FindName($n) -Scope Script
}

# ---------- BUSY INDICATOR (own UI thread) ----------
# Fetch / predecessor / Create all run ON the main UI thread by design (async attempts were reverted for
# reliability). That thread is therefore frozen for the duration, so nothing drawn on the main window can move.
# This card lives in its OWN STA runspace with its own dispatcher: it animates and updates while the main thread
# blocks. Communication is one synchronized hashtable that the main thread WRITES and a 100 ms timer on the busy
# thread READS - no cross-thread delegates (a scriptblock delegate invoked from another thread has no runspace).
$script:Busy = [hashtable]::Synchronized(@{
    Show = $false; Title = ''; Detail = ''; Percent = -1     # Percent -1 = indeterminate
    L = 0; T = 0; W = 0; H = 0                               # owner window rect, so the card centres on it
    Quit = $false; Ready = $false; Error = ''
})
function Start-PBBusyHost {
    try {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
        $rs.SessionStateProxy.SetVariable('Busy', $script:Busy)
        $ps = [powershell]::Create(); $ps.Runspace = $rs
        [void]$ps.AddScript({
            try {
                Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
                [xml]$x = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True" ShowInTaskbar="False"
        ShowActivated="False" ResizeMode="NoResize" Width="460" SizeToContent="Height" FontFamily="Segoe UI">
  <Border Background="#F21F232B" BorderBrush="#2BA6B8" BorderThickness="1" CornerRadius="8" Padding="22,18">
    <StackPanel>
      <TextBlock x:Name="T" Foreground="#F2F4F7" FontSize="14" FontWeight="SemiBold" TextWrapping="Wrap"/>
      <TextBlock x:Name="D" Foreground="#B7BEC8" FontSize="12" TextWrapping="Wrap" Margin="0,5,0,0" MinHeight="16"/>
      <ProgressBar x:Name="P" Height="4" Margin="0,14,0,0" Minimum="0" Maximum="100" IsIndeterminate="True"
                   Foreground="#2BA6B8" Background="#2A2E36" BorderThickness="0"/>
      <TextBlock Text="The window stays busy until this finishes. Progress is also written to the log." Foreground="#A0A8B4" FontSize="11" Margin="0,10,0,0"/>
    </StackPanel>
  </Border>
</Window>
'@
                $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
                $t = $w.FindName('T'); $d = $w.FindName('D'); $p = $w.FindName('P')
                $timer = New-Object Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromMilliseconds(100)
                $timer.add_Tick({
                    try {
                        if ($Busy.Quit) { $timer.Stop(); try { $w.Close() } catch {}; [Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown(); return }
                        if ($Busy.Show) {
                            if ($t.Text -ne $Busy.Title)  { $t.Text = $Busy.Title }
                            if ($d.Text -ne $Busy.Detail) { $d.Text = $Busy.Detail }
                            $pct = [int]$Busy.Percent
                            if ($pct -lt 0) { if (-not $p.IsIndeterminate) { $p.IsIndeterminate = $true } }
                            else { if ($p.IsIndeterminate) { $p.IsIndeterminate = $false }; $p.Value = [Math]::Min(100, $pct) }
                            if (-not $w.IsVisible) {
                                $w.UpdateLayout()
                                $w.Left = $Busy.L + ($Busy.W - $w.Width) / 2
                                $w.Top  = $Busy.T + ($Busy.H - [Math]::Max($w.ActualHeight, 120)) / 2
                                $w.Show()
                            }
                        } elseif ($w.IsVisible) { $w.Hide() }
                    } catch {}
                })
                $timer.Start()
                $Busy.Ready = $true
                [Windows.Threading.Dispatcher]::Run()
            } catch { $Busy.Error = "$($_.Exception.Message)" }
        })
        $script:BusyPs = $ps; $script:BusyHandle = $ps.BeginInvoke()
    } catch { Write-Log "Busy indicator could not start: $($_.Exception.Message) - operations still run, just without the card." Warning }
}
# Show / update / hide - all from the main thread, all just writes.
function Show-PBBusy {
    param([string]$Title, [string]$Detail = '')
    try {
        $b = $script:Busy
        $b.Title = $Title; $b.Detail = $Detail; $b.Percent = -1
        $wnd = $script:Win
        if ($wnd) { $b.L = $wnd.Left; $b.T = $wnd.Top; $b.W = $wnd.ActualWidth; $b.H = $wnd.ActualHeight }
        $b.Show = $true
        if (Get-Command Set-PBStatus -EA SilentlyContinue) { Set-PBStatus "$Title..." }
        # Give the busy thread one tick to paint before the main thread blocks (it runs regardless; this just makes
        # the card appear instantly instead of ~100 ms in).
        Start-Sleep -Milliseconds 120
    } catch {}
}
function Set-PBProgress {
    param([int]$Percent = -1, [string]$Status = '')
    try { if ($Status) { $script:Busy.Detail = $Status }; $script:Busy.Percent = $Percent } catch {}
}
function Hide-PBBusy { try { $script:Busy.Show = $false; $script:Busy.Percent = -1; $script:BusySuspend = 0; if (Get-Command Set-PBStatus -EA SilentlyContinue) { Set-PBStatus '' } } catch {} }

# THE BUSY CARD MUST STEP ASIDE FOR A QUESTION. It lives on its own STA thread and is Topmost, so it floats over
# ANY dialog - including "which source do you want?" when several installers are found. The packager then sees a
# progress card covering the window and has to drag the window to reach the picker (23.09.2026). So every modal
# suspends it and the card comes back when the dialog closes. Counted, because dialogs nest.
$script:BusySuspend = 0
function Suspend-PBBusy {
    try { if ($script:Busy -and $script:Busy.Show) { $script:BusySuspend++; $script:Busy.Show = $false; Start-Sleep -Milliseconds 60 } } catch {}
}
function Resume-PBBusy {
    try { if ($script:BusySuspend -gt 0) { $script:BusySuspend--; if ($script:BusySuspend -eq 0) { $script:Busy.Show = $true } } } catch {}
}
# Run a block with the busy card out of the way (for a MessageBox, which has no window object to hook).
function Invoke-PBWithoutBusy {
    param([scriptblock]$Action)
    Suspend-PBBusy
    try { & $Action } finally { Resume-PBBusy }
}
Start-PBBusyHost
# While the main thread is blocked, Windows would otherwise paint "(Not Responding)" into the title and grey the
# window - alarming, and wrong: the busy card says exactly what is happening. Standard call for tools that block
# their UI thread on purpose.
try {
    Add-Type -Namespace PBNative -Name User32 -MemberDefinition '[DllImport("user32.dll")] public static extern void DisableProcessWindowsGhosting();' -ErrorAction Stop
    [PBNative.User32]::DisableProcessWindowsGhosting()
} catch {}

# SNIPPET OWNERSHIP: only owners (Core.ps1 $script:SnippetOwners, matched on $env:USERNAME) may ADD/EDIT/DELETE the
# SHARED snippet library - everyone else just USES it. Hide the write buttons for non-owners so juniors can't clutter
# or delete team snippets. (Insert stays visible for everyone.)
if ((Get-Command Test-IsSnippetOwner -EA SilentlyContinue) -and -not (Test-IsSnippetOwner)) {
    foreach ($b in @($BtnAddSnip, $BtnEditSnip, $BtnDelSnip)) { if ($b) { $b.Visibility = 'Collapsed' } }
}

# BRAND PROFILE at startup: order-number label (RITM vs AES), SCCM/Intune feature hiding, outgoing-prefix picker.
try {
    $onl = "$(Get-PBBrand -Path 'OrderNumberLabel' -Default 'RITM')"
    if ($LblRitmCaption -and $onl -and $onl -ne 'RITM') { $LblRitmCaption.Text = $(if ($onl -match '(?i)\b(id|number)$') { $onl } else { "$onl number" }) }
    if ($LblHdrRitmCaption -and $onl) { $LblHdrRitmCaption.Text = "$onl".ToUpper() }
    if ($LblRitmExample) { $ex = $(try { "$(Get-GpfOrderNumberExample)" } catch { '' }); $LblRitmExample.Text = $(if (-not $ex) { '' } elseif ($ex -match '(?i)\be\.g\.') { $ex } else { "e.g. $ex" }) }
    # TARGET BRANDS from settings (Brand.OutgoingPrefix: tag -> outgoing label). GPF lists Audi/VW/Group; a brand
    # with ONE target (Porsche: PAG) gets no dropdown at all - the row is hidden and the tag is simply set.
    if ($CmbBrand) {
        $CmbBrand.Items.Clear()
        $labels = @{ INA = 'Audi (INA)'; G1V = 'VW (G1V)'; VWG = 'Group (VWG)' }
        $prefixMap = Get-PBBrand -Path 'OutgoingPrefix' -Default $null
        foreach ($tag in @(Get-GpfTargetTags)) {
            $text = $(if ($labels.ContainsKey($tag)) { $labels[$tag] } else {
                $pretty = $(try { "$(Get-PBMember -Object $prefixMap -Name $tag)" } catch { '' })
                if ($pretty) { "$pretty ($tag)" } else { $tag } })
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $text; $item.Tag = $tag
            [void]$CmbBrand.Items.Add($item)
        }
        if ($CmbBrand.Items.Count -le 1) {
            $CmbBrand.Visibility = 'Collapsed'
            if ($LblBrand) { $LblBrand.Visibility = 'Collapsed' }
        }
    }
    if (-not (Test-PBFeature 'Publish')) { foreach ($tb in @($TabIntegration, $TabDevTest)) { if ($tb) { $tb.Visibility = 'Collapsed' } } }
    if (-not (Test-PBFeature 'Sccm'))    { if ($TabTesting) { $TabTesting.Visibility = 'Collapsed' } }
    # ONE visible tab = no tab strip: a lone "Review & Create" pill above its own page is noise. The tab strip is
    # the template's HeaderPanel; it is collapsed once the TabControl has applied its template (Loaded), and again
    # on every SizeChanged in case the template is re-applied.
    try {
        $shown = @($TabsP4.Items | Where-Object { $_.Visibility -eq 'Visible' })
        if ($shown.Count -eq 1) {
            # a TabItem's Visibility hides its HEADER only; the selected item's content still shows
            $TabsP4.SelectedItem = $shown[0]; $shown[0].Visibility = 'Collapsed'; $TabsP4.Padding = '0'
        }
    } catch {}
    # The publish/status strip under the Step-4 page shows only while it has something to say.
    if ($PnlPublishStatus) {
        $showStatus = {
            try {
                $any = ("$($LblPubStatus.Text)".Trim() -or "$($LblPublishLog.Text)".Trim() -or ($PbPublish.Visibility -eq 'Visible'))
                $PnlPublishStatus.Visibility = $(if ($any) { 'Visible' } else { 'Collapsed' })
            } catch {}
        }
        $LblPubStatus.add_TextChanged($showStatus); $LblPublishLog.add_TextChanged($showStatus); $PbPublish.add_IsVisibleChanged($showStatus)
    }
    # The separate "outgoing prefix" dropdown is SUPERSEDED by the Step-1 Target-brand dropdown - the outgoing folder
    # prefix (INA_/VWG_/G1V_) now comes straight from that selection ($script:State.TargetBrand). Keep PnlOutPrefix hidden.
    if ($PnlOutPrefix) { $PnlOutPrefix.Visibility = 'Collapsed' }
} catch { Write-Log "Brand UI init: $($_.Exception.Message)" Warning }

# Visual hierarchy: give each Step-4 tab ONE accented PRIMARY action so a junior sees the main button at a glance.
# (Secondary / query / destructive buttons keep the default or danger style.) Applied in code so no XAML churn.
try {
    $accent = $script:Win.FindResource('PbAccentButton')
    if ($accent) {
        $primary = @($BtnNext,            # wizard: advance / Create
                     $BtnCreateSccm, $BtnCreateIntune,   # Integration: publish (the point of the tab)
                     $BtnAddTestMachine,  # Testing: add machines to the collection
                     $BtnMoveToTest)      # Dev->Test: promote to TEST
        foreach ($b in $primary) { if ($b) { $b.Style = $accent } }
    }
} catch {}

# SCOPE RULE: never touch $script:State directly inside a .GetNewClosure() handler - the closure runs in its
# own module scope where $script:State does NOT exist ($null), so an assignment dies with "The property ...
# cannot be found on this object" (that was the popup AFTER a successful Intune upload). FUNCTIONS execute in
# the scope they were DEFINED in (this main script), so closures must go through these helpers instead.
function Set-IntuneAppIdUi { param([string]$Id)
    $script:State.IntuneAppId = $Id
    if ($TxtIntuneAppId) { $TxtIntuneAppId.Text = $Id }
}
function Get-MsiPropsFor { param([string]$Fn)
    if (-not $script:State.MsiProps) { $script:State.MsiProps = @{} }
    return [string]$script:State.MsiProps[$Fn]
}
function Set-MsiPropsFor { param([string]$Fn, [string]$Text)
    if (-not $script:State.MsiProps) { $script:State.MsiProps = @{} }
    $script:State.MsiProps[$Fn] = $Text
}

# Clear the MANUAL entries across the Step-4 tabs (Integration publish form, Modify, Testing, Troubleshoot,
# Intune, Dev->Test). These are WPF control values, not $script:State, so Reset-Step/Invalidate-From miss them.
function Clear-Step4Fields {
    $boxes = @($TxtPubPkgName,$TxtPubProductName,$TxtPubPublisher,$TxtPubVersion,$TxtPubProductCode,
               $TxtPubBrandingKey,$TxtPubUninstallKey,$TxtPubDetectVersion,$TxtPubInstall,$TxtPubUninstall,$TxtPubRepair,$TxtPubDescription,
               $TxtModAppName,$TxtModUninstallKey,$TxtModDetectVersion,$TxtModProductCode,$TxtModContentSrc,
               $TxtTestAppName,$TxtTestMachine,$TxtTsMachine,$TxtTsAppName,
               $TxtIntuneAppId,$TxtIntuneAssignApp,$TxtIntuneGroupId,$TxtIntuneContentSrc,$TxtMoveAppName,
               $LblPublishLog,$LblPubStatus,$LblCreateResult)
    foreach ($b in $boxes) { if ($b) { $b.Text = '' } }
    foreach ($l in @($LstTestMachines,$LstTsMembers)) { if ($l) { $l.Items.Clear() } }
    foreach ($c in @($ChkMod32Bit,$ChkModRefreshOnly)) { if ($c) { $c.IsChecked = $false } }
    foreach ($cb in @($CmbModDetectType,$CmbTsColl,$CmbTestAction)) { if ($cb -and $cb.Items.Count) { $cb.SelectedIndex = 0 } }
    if ($ChkPubAllowInteract) { $ChkPubAllowInteract.IsChecked = $true }
    if ($PnlPublish) { $PnlPublish.IsEnabled = $false }
    if ($CreatePanel) { $CreatePanel.Visibility = 'Collapsed' }
    $script:State.IntuneAppId = $null
}

# ONE gate for every SCCM/Intune action: ALL action buttons disable while ANY background job runs.
# (Two concurrent jobs would fight over the shared progress bar/status/log label and the log file.)
$script:JobRunning = $false
$script:ActionButtons = @($BtnCreateSccm,$BtnCreateIntune,$BtnFetchDetection,$BtnUpdateDetection,$BtnUpdateContent,$BtnContentStatus,$BtnDeleteApp,
                          $BtnAddTestMachine,$BtnRemoveTestMachine,$BtnRunMachinePolicy,$BtnLogDiscovery,$BtnLogEnforce,$BtnLogPackage,
                          $BtnTsShowMembers,$BtnTsCheckState,$BtnTsReboot,$BtnIntuneAssignAvail,$BtnIntuneUnassign,$BtnIntuneUpdateContent,
                          $BtnMoveToTest,$BtnMoveToDev)
function Set-ActionButtons { param([bool]$Enabled) $script:JobRunning = -not $Enabled; foreach ($b in $script:ActionButtons) { if ($b) { $b.IsEnabled = $Enabled } } }
# Warn before closing while a job is still running (the runspace would keep working headless).
$script:Win.add_Closing({ param($s,$e)
    if ($script:JobRunning) {
        $ans = [Windows.MessageBox]::Show('A SCCM/Intune operation is still running. Close anyway?', 'Operation running', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { $e.Cancel = $true }
    }
})

$script:Step = 1

# CHROME: the header says WHAT is being worked on (package, order number, brand), the step strip's right end says
# WHERE it comes from and goes to, and the bottom strip says what is happening RIGHT NOW. Each fact lives in
# exactly one place. Refreshed when the underlying thing changes, never on a timer.
function Update-PBChrome {
    $pkg = "$($script:State.PkgName)".Trim()
    if ($LblHdrPkg)  { $LblHdrPkg.Text = $(if ($pkg) { $pkg } else { 'No package yet' })
                       $LblHdrPkg.Foreground = $(if ($pkg) { '#E7E9ED' } else { '#A0A8B4' }) }
    # The order number shows label+value only once there is one - an empty label would just be noise.
    $ritm = "$($script:State.Ritm)".Trim()
    if ($LblHdrRitm) { $LblHdrRitm.Text = $ritm }
    if ($PnlHdrRitm) { $PnlHdrRitm.Visibility = $(if ($ritm) { 'Visible' } else { 'Collapsed' }) }
    # Brand: only when the family has more than one target (otherwise the header would repeat the tool's name).
    $brandText = ''
    try { if ($CmbBrand -and $CmbBrand.Visibility -eq 'Visible' -and $CmbBrand.SelectedItem) { $brandText = "$($CmbBrand.SelectedItem.Content)" } } catch {}
    if ($LblHdrBrand) { $LblHdrBrand.Text = $brandText }
    if ($PnlHdrBrand) { $PnlHdrBrand.Visibility = $(if ($brandText) { 'Visible' } else { 'Collapsed' }) }
    if (Get-Command Update-StepStrip -ErrorAction SilentlyContinue) { Update-StepStrip }
    # Right end of the step strip: WHERE this build's files actually came from - the folder the source was taken
    # from and the predecessor package - as a quiet record (user, 20.09.2026: no platform / target / share kind
    # for GPF and Porsche; the locations are what matters). Full paths on hover; nothing until they are known.
    if ($LblOrigin) {
        $parts = @(); $tips = @()
        try {
            $r = $script:State.Resolved
            $srcPath = $(if ($r -and $r.RootPath) { "$($r.RootPath)" } elseif ($r -and $r.PayloadRoot) { "$($r.PayloadRoot)" } else { '' })
            if ($srcPath) { $parts += "Source: $(Split-Path $srcPath -Leaf)"; $tips += "Source: $srcPath" }
            $pp = "$($script:State.PredecessorPath)"
            if ($pp) { $parts += "Predecessor: $(Split-Path $pp -Leaf)"; $tips += "Predecessor: $pp" }
        } catch {}
        $LblOrigin.Text = ($parts -join '      ')
        $LblOrigin.ToolTip = $(if ($tips.Count) { $tips -join "`r`n" } else { $null })
    }
}
function Update-PBStatusBar { Update-PBChrome }
# One sentence in the bottom strip while something runs; cleared when it is done.
function Set-PBStatus { param([string]$Text = '')
    try { if ($LblStatusBar) { $LblStatusBar.Text = "$Text" } } catch {}
}

# ---------- Step strip ----------
# Paints the four step pills from CENTRAL STATE, never from what was clicked: a step is "done" when the thing
# it exists to produce is present (1 = valid name + installers, 2 = installer type, 3 = script, 4 = created
# folder), "current" is $script:Step, everything else is pending. Called from Show-Step and Update-PBChrome.
$script:StripBrush = @{
    CurBg  = '#1C3A42'; CurBorder = '#2BA6B8'; CurText  = '#F2F4F7'
    DoneText = '#D5D9E0'; PendText = '#A0A8B4'; HoverBg = '#2A2E36'
}
function Test-StepDone { param([int]$i)
    $s = $script:State
    switch ($i) {
        1 { return ([bool]($s.Parsed -and $s.Parsed.IsValid) -and @($s.ChosenInstallers).Count -gt 0) }
        2 { return [bool]"$($s.InstallerType)".Trim() }
        3 { return [bool]"$($s.ScriptText)".Trim() }
        4 { return [bool]"$($s.CreatedPath)".Trim() }
    }
    return $false
}
# One quiet line per step: the fact that step produced. @{ Text; Tone } - Tone: 'ok' (green), 'warn' (amber),
# '' (neutral). Everything read from central state; nothing is counted that the packager cannot act on.
function Get-StepState {
    param([int]$i)
    $s = $script:State
    switch ($i) {
        1 {
            if (-not ($s.Parsed -and $s.Parsed.IsValid)) { return @{ Text = 'name needed'; Tone = '' } }
            $bits = @()
            $bits += $(if (@($s.ChosenInstallers).Count) { 'source fetched' } else { 'no source yet' })
            if ($s.PredecessorPath) { $pn = Split-Path $s.PredecessorPath -Leaf; $pp = Parse-PackageName $pn; $bits += "predecessor $(if ($pp -and $pp.IsValid) { "$($pp.Version)-$($pp.Release)" } else { $pn })" }
            return @{ Text = ($bits -join ' · '); Tone = $(if (@($s.ChosenInstallers).Count) { 'ok' } else { '' }) }
        }
        2 {
            $ins = @($s.ChosenInstallers)
            if (-not $ins.Count) { return @{ Text = 'not started'; Tone = '' } }
            if ($s.LooseFiles) { return @{ Text = 'loose files'; Tone = 'ok' } }
            if ($ins.Count -gt 1) { return @{ Text = "$($ins.Count) installers"; Tone = 'ok' } }
            $type = "$($s.InstallerType)"
            if ($type -eq 'MSI') {
                $props = 0; if ($s.MsiProps -and $ins[0].FullName -and $s.MsiProps.ContainsKey($ins[0].FullName)) { $props = @(("$($s.MsiProps[$ins[0].FullName])" -split "`r?`n") | Where-Object { $_.Trim() }).Count }
                return @{ Text = "MSI$(if ($s.GenerateMst) { ' + MST' })$(if ($props) { " · $props propert$(if ($props -eq 1) { 'y' } else { 'ies' })" })"; Tone = 'ok' }
            }
            if ($type -eq 'EXE') {
                $sw = "$($s.InstallParams)".Trim()
                return @{ Text = $(if ($sw) { "EXE · $sw" } else { 'EXE · switches missing' }); Tone = $(if ($sw) { 'ok' } else { 'warn' }) }
            }
            return @{ Text = $(if ($type) { $type } else { 'not started' }); Tone = $(if ($type) { 'ok' } else { '' }) }
        }
        3 {
            if (-not "$($s.ScriptText)".Trim()) { return @{ Text = 'not built'; Tone = '' } }
            $all = @(Get-CombinedReview).Count; $open = @(Get-OpenReview).Count
            if ($open) { return @{ Text = "$open to review"; Tone = 'warn' } }
            return @{ Text = $(if ($all) { 'reviewed' } elseif ($s.PredecessorModel) { 'predecessor reused' } else { 'built' }); Tone = 'ok' }
        }
        4 {
            if (-not "$($s.CreatedPath)".Trim()) { return @{ Text = 'not created'; Tone = '' } }
            return @{ Text = 'created'; Tone = 'ok' }
        }
    }
    return @{ Text = ''; Tone = '' }
}
function Update-StepStrip {
    if (-not $S1) { return }
    $c = $script:StripBrush
    foreach ($i in 1..4) {
        $btn = Get-Variable -Name "S$i" -ValueOnly; $lbl = Get-Variable -Name "N$i" -ValueOnly
        $gly = Get-Variable -Name "G$i" -ValueOnly -ErrorAction SilentlyContinue
        $st  = Get-Variable -Name "ST$i" -ValueOnly -ErrorAction SilentlyContinue
        if (-not ($btn -and $lbl)) { continue }
        $isCur = ($i -eq $script:Step)
        if ($isCur) {
            $btn.Background = $c.CurBg; $btn.BorderBrush = $c.CurBorder; $lbl.Foreground = $c.CurText; $lbl.FontWeight = 'SemiBold'
            if ($gly) { $gly.Foreground = '#56C8D6' }   # the glyph carries the accent on the current step
        } else {
            $btn.Background = 'Transparent'; $btn.BorderBrush = 'Transparent'; $lbl.FontWeight = 'Normal'
            $lbl.Foreground = $(if (Test-StepDone $i) { $c.DoneText } else { $c.PendText })
            if ($gly) { $gly.Foreground = $lbl.Foreground }
        }
        if ($st) {
            $ss = $null; try { $ss = Get-StepState -i $i } catch { $ss = @{ Text = ''; Tone = '' } }
            $st.Text = "$($ss.Text)"; $st.ToolTip = $(if ("$($ss.Text)".Length -gt 34) { "$($ss.Text)" } else { $null })
            $st.Foreground = switch ("$($ss.Tone)") { 'ok' { '#57BE8C' } 'warn' { '#E0BE7C' } default { $(if ($isCur) { '#B7BEC8' } else { '#7F8794' }) } }
        }
    }
}

function Show-Step {
    param([int]$n)
    $script:Step = $n
    $P1.Visibility = if($n -eq 1){'Visible'}else{'Collapsed'}
    $P2.Visibility = if($n -eq 2){'Visible'}else{'Collapsed'}
    $P3.Visibility = if($n -eq 3){'Visible'}else{'Collapsed'}
    $P4.Visibility = if($n -eq 4){'Visible'}else{'Collapsed'}
    Update-StepStrip
    $BtnBack.IsEnabled = ($n -gt 1)
    $BtnNext.Content = if($n -ge 4){'Create'}else{'Next'}
    if (Get-Command Update-PBStatusBar -ErrorAction SilentlyContinue) { Update-PBStatusBar }
    # The bottom 'Create' button assembles the PACKAGE - it only makes sense on the Review & Create sub-tab.
    # On the other Step-4 tabs (Integration / Testing / Troubleshoot / Dev-Test) hide it. Steps 1-3 always show.
    if ($n -ge 4 -and $TabsP4) {
        $sel = $TabsP4.SelectedItem
        $BtnNext.Visibility = if ($sel -and ("$($sel.Header)" -like 'Review*')) { 'Visible' } else { 'Collapsed' }
    } else {
        $BtnNext.Visibility = 'Visible'
    }
    # Always rehydrate the panel we're showing FROM central state, so Back/Forward
    # reflect the truth and never show a stale installer / product code (Plan section 7).
    Populate-Step $n   # (repaints the chrome too)
}

function Populate-Step { param([int]$n)
    switch ($n) { 1 { Populate-Step1 } 2 { Populate-Step2 } 3 { Populate-Step3 } 4 { Populate-Step4 } }
    Update-PBChrome
}

function Populate-Step1 {
    $script:Rehydrating = $true
    try {
        if ($TxtPkg.Text  -ne [string]$script:State.PkgName) { $TxtPkg.Text  = [string]$script:State.PkgName }
        if ($TxtRitm.Text -ne [string]$script:State.Ritm)    { $TxtRitm.Text = [string]$script:State.Ritm }
        Sync-BrandCombo
        $p = $script:State.Parsed
        if ($p -and $p.IsValid) {
            $LblParsed.Text = "Vendor=$($p.Vendor)  App=$($p.AppName)  Arch=$($p.Arch)  Ver=$($p.Version)  Lang=$($p.Lang)"
            $LblParsed.Foreground = '#6A9955'
        } elseif ($script:State.PkgName) {
            $LblParsed.Text = "Could not parse - expected Vendor_App_Arch_Version-Release_Lang"
            $LblParsed.Foreground = '#F48771'
        } else { $LblParsed.Text = '' }
        # EMPTY STATES: a blank panel says nothing; a quiet sentence says what to do next.
        if ($script:State.PredecessorPath) { $LblPred.Text = "Predecessor: " + (Split-Path $script:State.PredecessorPath -Leaf); $LblPred.Foreground = '#56C8D6' }
        else { $LblPred.Text = 'No predecessor yet - Find predecessor lists earlier releases of this app to reuse.'; $LblPred.Foreground = '#A0A8B4' }
        # Predecessor-uninstall toggle: visible only when a predecessor is in use.
        $ChkAddUninstall.Visibility = if ($script:State.PredecessorModel) { 'Visible' } else { 'Collapsed' }
        $ChkAddUninstall.IsChecked  = [bool]$script:State.AddUninstallPrevious
        $ins = @($script:State.ChosenInstallers)
        if ($ins.Count -gt 0 -and $script:State.Resolved) {
            $names = ($ins | ForEach-Object { $_.Name }) -join ', '
            $LblSrc.Text = "[$($script:State.Resolved.Mode)] installer(s): $names   |   doc items: $($script:State.Resolved.DocItems.Count)"
            $LblSrc.Foreground = '#CE9178'
        } else { $LblSrc.Text = 'No source yet - Fetch source, or add the installer by hand.'; $LblSrc.Foreground = '#A0A8B4' }
    } finally { $script:Rehydrating = $false }
}

# ---------- Review items (Step 3): what the packager must look at before shipping ----------
# Combines the script's own "## REVIEW:" markers (Get-ReviewItems) with the predecessor-MST notes
# the user chose to carry as report-only. Always re-scans the CURRENT script, so it is live.
function Get-CombinedReview {
    $items = New-Object System.Collections.Generic.List[string]
    $txt = [string]$script:State.ScriptText
    # Empty editor / no script yet -> nothing to review (don't flag "SoftIdent empty" etc. on a blank script).
    if (-not "$txt".Trim()) { return @() }
    if (Get-Command Get-ReviewItems -ErrorAction SilentlyContinue) {
        foreach ($r in @(Get-ReviewItems -ScriptText $txt)) { if ("$r".Trim()) { $items.Add("$r") } }
    }
    # Semantic findings (carried-over product code, $adtSession.DeploymentType in the var block, INF reuse...).
    if (Get-Command Get-ScriptReviewFindings -ErrorAction SilentlyContinue) {
        $isPred = [bool]$script:State.PredecessorModel
        foreach ($r in @(Get-ScriptReviewFindings -ScriptText $txt -IsPredecessor $isPred -NewProductCode "$($script:State.ProductCode)")) { if ("$r".Trim()) { $items.Add("$r") } }
    }
    foreach ($n in @($script:State.MstReviewNotes)) { if ("$n".Trim()) { $items.Add("Predecessor MST also modified -> $n (not auto-applied)") } }
    foreach ($n in @($script:State.SnapshotNotes))   { if ("$n".Trim()) { $items.Add("$n") } }
    foreach ($n in @($script:State.SourceNotes))     { if ("$n".Trim()) { $items.Add("$n") } }
    # Validator checks on the chosen installer(s): signature/publisher, version + architecture cross-check.
    # Cached by path+size so the signature / MSI-COM reads don't repeat on every review open.
    if (Get-Command Get-InstallerValidation -ErrorAction SilentlyContinue) {
        if (-not $script:InstallerValCache) { $script:InstallerValCache = @{} }
        foreach ($ins in @($script:State.ChosenInstallers)) {
            if (-not $ins.FullName) { continue }
            # Key includes the PACKAGE NAME so the version/arch cross-check re-runs when the name changes (a name
            # edit must not show the PREVIOUS app's findings).
            $key = "$($ins.FullName)|$($ins.Length)|$($script:State.Parsed.FullName)"
            if (-not $script:InstallerValCache.ContainsKey($key)) {
                try { $script:InstallerValCache[$key] = @(Get-InstallerValidation -Path $ins.FullName -Parsed $script:State.Parsed) } catch { $script:InstallerValCache[$key] = @() }
            }
            foreach ($r in $script:InstallerValCache[$key]) { if ("$r".Trim()) { $items.Add("$r") } }
        }
    }
    return $items.ToArray()
}
# Toolbar button label/colour: "Review (N)" amber when there are items, "Review" green when clear.
# CONFIRMED review items: the packager ticks an item once they have looked at it; it then stops counting as open
# (button, Step 4 block, strip state). Keyed by the item text, so it survives a Rebuild that reproduces the same
# finding, and a CHANGED finding comes back as new. Reset all clears the whole set.
function Test-ReviewAck { param([string]$Item) if (-not $script:State.ReviewAck) { $script:State.ReviewAck = @{} }; return [bool]$script:State.ReviewAck.ContainsKey("$Item".Trim()) }
function Set-ReviewAck  { param([string]$Item, [bool]$On)
    if (-not $script:State.ReviewAck) { $script:State.ReviewAck = @{} }
    $k = "$Item".Trim(); if (-not $k) { return }
    if ($On) { $script:State.ReviewAck[$k] = (Get-Date -Format 's') } else { $script:State.ReviewAck.Remove($k) }
}
function Get-OpenReview { return @(@(Get-CombinedReview) | Where-Object { -not (Test-ReviewAck -Item $_) }) }
function Update-ReviewButton {
    if (-not $BtnReview) { return }
    $all = @(Get-CombinedReview); $open = @(Get-OpenReview).Count
    $isReuse = [bool]$script:State.PredecessorModel
    $label = if ($isReuse) { 'Reuse report' } else { 'Review' }
    $text = $(if ($open -gt 0) { "$label ($open)" } elseif ($all.Count) { "$label (confirmed)" } else { $label })
    # the button's content is glyph + text (XAML); change the TEXT, keep the glyph - the colour goes on the button
    # so the glyph inherits it
    $inner = $null
    try { if ($BtnReview.Content -is [Windows.Controls.StackPanel]) { $inner = @($BtnReview.Content.Children | Where-Object { $_ -is [Windows.Controls.TextBlock] })[-1] } } catch {}
    if ($inner) { $inner.Text = $text } else { $BtnReview.Content = $text }
    $BtnReview.Foreground = $(if ($open -gt 0) { (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xE0,0xBE,0x7C))) }
                              else { (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x57,0xBE,0x8C))) })
    if (Get-Command Update-StepStrip -ErrorAction SilentlyContinue) { Update-StepStrip }
}
# Build the predecessor reuse report (Done + Check) from current state, or $null when not a reuse build.
function Get-CurrentReuseReport {
    if (-not $script:State.PredecessorModel -or -not $script:State.ReusePkg) { return $null }
    if (-not (Get-Command Get-PredecessorReport -ErrorAction SilentlyContinue)) { return $null }
    $mis = ''; try { $mis = Get-SourceWarning } catch {}
    try {
        return Get-PredecessorReport -Model $script:State.PredecessorModel -NewPkg $script:State.ReusePkg `
            -ScriptText ([string]$script:State.ScriptText) -AddUninstallPrevious ([bool]$script:State.AddUninstallPrevious) -MismatchText "$mis"
    } catch { return $null }
}

# Modal popup. For a PREDECESSOR REUSE build it is a two-part REPORT: "Done automatically" (green - trust these) and
# "Please check / fill" (amber - the few unknowns). For a fresh build it is the plain review list. Re-scans live.
function Show-ReviewPopup {
    $items   = @(Get-CombinedReview)                 # everything (open + confirmed)
    $report  = Get-CurrentReuseReport
    $isReuse = [bool]$report
    $done    = if ($isReuse) { @($report.Done) } else { @() }

    $w = New-Object Windows.Window
    $w.Title = if ($isReuse) { 'Predecessor reuse - review' } else { 'Review' }
    $w.Width = 760; $w.SizeToContent = 'Height'; $w.MaxHeight = 680; $w.FontFamily = 'Segoe UI'; $w.FontSize = 13
    $w.WindowStartupLocation = 'CenterOwner'; $w.Owner = $script:Win
    $w.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x18,0x1A,0x1F)))
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $w }
    $g = New-Object Windows.Controls.Grid; $g.Margin = '18,16,18,16'
    foreach ($h in 'Auto','*','Auto') { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = $h; [void]$g.RowDefinitions.Add($rd) }

    # Header row: glyph + title, one-line count, hairline - the same section language as the pages.
    $hdrSp = New-Object Windows.Controls.StackPanel
    $hRow = New-Object Windows.Controls.StackPanel; $hRow.Orientation = 'Horizontal'
    $hGly = New-Object Windows.Controls.TextBlock; $hGly.FontFamily = 'Segoe MDL2 Assets'; $hGly.FontSize = 15; $hGly.VerticalAlignment = 'Center'; $hGly.Margin = '0,1,8,0'
    $hTit = New-Object Windows.Controls.TextBlock; $hTit.FontSize = 15; $hTit.FontWeight = 'SemiBold'; $hTit.Foreground = '#F2F4F7'; $hTit.VerticalAlignment = 'Center'
    [void]$hRow.Children.Add($hGly); [void]$hRow.Children.Add($hTit); [void]$hdrSp.Children.Add($hRow)
    $hdr = New-Object Windows.Controls.TextBlock; $hdr.TextWrapping = 'Wrap'; $hdr.FontSize = 12; $hdr.Margin = '0,4,0,0'; $hdr.Foreground = '#B7BEC8'
    [void]$hdrSp.Children.Add($hdr)
    $hRule = New-Object Windows.Controls.Border; $hRule.BorderBrush = '#2A2F38'; $hRule.BorderThickness = '0,1,0,0'; $hRule.Margin = '0,10,0,12'
    [void]$hdrSp.Children.Add($hRule)
    [Windows.Controls.Grid]::SetRow($hdrSp, 0); [void]$g.Children.Add($hdrSp)

    $sv = New-Object Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'; $sv.MaxHeight = 500
    $sp = New-Object Windows.Controls.StackPanel
    $rows = New-Object System.Collections.Generic.List[object]   # @{ Item; Card; Chk; Txt } for live restyle

    # Refresh header text + card styling from the current acknowledgements (called on every tick).
    $refresh = {
        $open = @($rows | Where-Object { -not $_.Chk.IsChecked }).Count
        $total = $rows.Count
        if ($total -eq 0) {
            $hGly.Text = [string][char]0xE8FB; $hGly.Foreground = '#57BE8C'; $hTit.Text = 'Nothing to review'
            $hdr.Text = $(if ($isReuse) { "Reusing '$(Split-Path "$((Get-PBState).PredecessorPath)" -Leaf)': everything was handled automatically - skim the script, then build." } else { 'The script has no open points.' })
        } elseif ($open -eq 0) {
            $hGly.Text = [string][char]0xE8FB; $hGly.Foreground = '#57BE8C'; $hTit.Text = "All $total item$(if ($total -ne 1) { 's' }) confirmed"
            $hdr.Text = 'Nothing is outstanding. Untick an item to reopen it.'
        } else {
            $hGly.Text = [string][char]0xE7BA; $hGly.Foreground = '#E0BE7C'; $hTit.Text = "$open of $total need$(if ($open -eq 1) { 's' }) your check"
            $hdr.Text = 'Look at each point in the script, fix what applies (then Rebuild), and tick it as confirmed. The package builds either way - confirmed items stop counting as open.'
        }
        foreach ($r in $rows) {
            $on = [bool]$r.Chk.IsChecked
            $r.Card.BorderBrush = $(if ($on) { '#57BE8C' } else { '#E0BE7C' })
            $r.Card.Opacity = $(if ($on) { 0.55 } else { 1.0 })
            # PS 5.1 unrolls the one-item Strikethrough collection into a bare TextDecoration - build the collection explicitly.
            if ($on) { $td = New-Object Windows.TextDecorationCollection; $td.Add((New-Object Windows.TextDecoration([Windows.TextDecorationLocation]::Strikethrough, $null, 0, [Windows.TextDecorationUnit]::FontRecommended, [Windows.TextDecorationUnit]::FontRecommended))); $r.Txt.TextDecorations = $td }
            else { $r.Txt.TextDecorations = $null }
        }
    }
    $i = 0
    foreach ($it in $items) {
        $i++
        $card = New-Object Windows.Controls.Border; $card.Background = '#21242B'; $card.BorderThickness = '3,0,0,0'; $card.CornerRadius = '4'; $card.Padding = '12,9'; $card.Margin = '0,0,0,8'
        $grid = New-Object Windows.Controls.Grid
        foreach ($cw in '*','Auto') { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $cw; [void]$grid.ColumnDefinitions.Add($cd) }
        $tb = New-Object Windows.Controls.TextBox; $tb.Text = "$i.  $it"; $tb.TextWrapping = 'Wrap'; $tb.FontSize = 12.5; $tb.Foreground = '#E7E9ED'; $tb.VerticalAlignment = 'Center'; $tb.Margin = '0,0,14,0'
        try { $tb.Style = $script:Win.FindResource('PbCopyText') } catch {}
        $chk = New-Object Windows.Controls.CheckBox; $chk.Content = 'Confirmed'; $chk.VerticalAlignment = 'Center'; $chk.IsChecked = (Test-ReviewAck -Item $it)
        $chk.Tag = $it
        [Windows.Controls.Grid]::SetColumn($tb, 0); [Windows.Controls.Grid]::SetColumn($chk, 1)
        [void]$grid.Children.Add($tb); [void]$grid.Children.Add($chk); $card.Child = $grid
        $rows.Add(@{ Item = $it; Card = $card; Chk = $chk; Txt = $tb })
        # PLAIN handler (no .GetNewClosure): a closure cannot see the script's functions (Set-ReviewAck) - proven by test.
        # The popup is modal, so this function's locals ($refresh, $rows...) stay reachable for the handler's lifetime.
        $chk.add_Click({ Set-ReviewAck -Item "$($this.Tag)" -On ([bool]$this.IsChecked); & $refresh })
        [void]$sp.Children.Add($card)
    }
    if ($isReuse -and $done.Count) {
        # What was handled automatically - collapsed, so the to-do list above is what people read.
        $exp = New-Object Windows.Controls.Expander; $exp.Header = "What the tool did for you ($($done.Count)) - you can rely on these"; $exp.Foreground = '#A0A8B4'; $exp.FontSize = 12; $exp.IsExpanded = $false; $exp.Margin = '0,6,0,0'
        $dsp = New-Object Windows.Controls.StackPanel; $dsp.Margin = '0,8,0,0'
        foreach ($d in $done) {
            $dt = New-Object Windows.Controls.TextBlock; $dt.Text = "$([char]0x2713)  $d"; $dt.TextWrapping = 'Wrap'; $dt.FontSize = 12; $dt.Foreground = '#B7BEC8'; $dt.Margin = '4,0,0,5'
            [void]$dsp.Children.Add($dt)
        }
        $exp.Content = $dsp; [void]$sp.Children.Add($exp)
    }
    & $refresh
    $sv.Content = $sp; [Windows.Controls.Grid]::SetRow($sv, 1); [void]$g.Children.Add($sv)

    $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.HorizontalAlignment = 'Right'; $btns.Margin = '0,14,0,0'
    if ($items.Count) {
        $all = New-Object Windows.Controls.Button; $all.Content = 'Confirm all'; $all.Padding = '14,5'; $all.Margin = '0,0,10,0'
        $all.add_Click({ foreach ($r in $rows) { $r.Chk.IsChecked = $true; Set-ReviewAck -Item $r.Item -On $true }; & $refresh })
        [void]$btns.Children.Add($all)
    }
    if ($isReuse) {
        $save = New-Object Windows.Controls.Button; $save.Content = 'Save report (HTML)'; $save.Padding = '14,5'; $save.Margin = '0,0,10,0'
        $save.add_Click({
            try {
                $r = Get-CurrentReuseReport; if (-not $r) { return }
                $st = Get-PBState   # closure-safe: direct $script:State here is the closure's empty scope
                $html = Format-PredecessorReportHtml -Report $r -Model $st.PredecessorModel -NewPkg $st.ReusePkg
                $dlg = New-Object Microsoft.Win32.SaveFileDialog
                $dlg.Filter = 'HTML report (*.html)|*.html'; $dlg.FileName = "ReuseReport_$(if($st.Parsed){$st.Parsed.FullName}else{'package'}).html"
                if ($dlg.ShowDialog()) { [IO.File]::WriteAllText($dlg.FileName, $html); try { Start-Process $dlg.FileName } catch {} }
            } catch { Write-Log "Save reuse report failed: $($_.Exception.Message)" Warning }
        }.GetNewClosure())
        [void]$btns.Children.Add($save)
    }
    $ok = New-Object Windows.Controls.Button; $ok.Content = 'OK'; $ok.Padding = '20,5'; $ok.IsDefault = $true
    try { $ok.Style = $script:Win.FindResource('PbAccentButton') } catch {}
    $ok.add_Click({ $w.DialogResult = $true }.GetNewClosure())
    [void]$btns.Children.Add($ok); [Windows.Controls.Grid]::SetRow($btns, 2); [void]$g.Children.Add($btns)

    $w.Content = $g; [void]$w.ShowDialog()
    Update-ReviewButton
}

function Populate-Step3 {
    if (-not $script:AeEditor) { return }   # editor disabled (DLL missing)
    $script:Step3Loading = $true
    try {
        if (-not $script:State.ScriptText) { Show-PBBusy -Title 'Building script' -Detail $(if ($script:State.PredecessorModel) { 'Reusing the predecessor script: converting, swapping identity, merging the snapshot...' } else { 'Filling the template from the installer, transform and analysis...' }); try { $script:State.ScriptText = Build-Step3Script } finally { Hide-PBBusy } }
        if ($script:AeEditor.Text -ne [string]$script:State.ScriptText) { $script:AeEditor.Text = [string]$script:State.ScriptText }
        Update-Anchors
        # HEADS-UP popup: show the few important build notices ONCE per distinct set (not on every rebuild). This is the
        # prominent, must-see channel - separate from the long "review" list that gets ignored.
        if (Get-Command Get-GpfNotices -EA SilentlyContinue) {
            $notices = @(Get-GpfNotices)
            $sig = ($notices -join "`n")
            if ($notices.Count -and $sig -ne "$($script:LastNoticeSig)") {
                $script:LastNoticeSig = $sig
                $body = ($notices | ForEach-Object { "-  $_" }) -join "`r`n`r`n"
                Invoke-PBWithoutBusy { [Windows.MessageBox]::Show("$body", 'Heads-up - please read', 'OK', 'Information') | Out-Null }
            }
        }
        # Structural (parse) problems outrank source warnings - they mean the script is BROKEN.
        $struct = Test-ScriptStructure -Text ([string]$script:State.ScriptText)
        $warn = if ($struct) { "CORRUPT SCRIPT: $struct" } else { Get-SourceWarning }
        if ($warn) {
            $LblScriptHdr.Text = "WARNING  $warn"
            $LblScriptHdr.Foreground = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xF4,0x87,0x71)))
            Write-Log $warn Warning
        } else {
            $LblScriptHdr.Text = if ($script:State.Parsed -and $script:State.Parsed.IsValid) {
                "Invoke-AppDeployToolkit.ps1  -  $($script:State.Parsed.FullName)"
            } else { 'Invoke-AppDeployToolkit.ps1' }
            $LblScriptHdr.Foreground = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x56,0xC8,0xD6)))
        }
        $LblScriptHdr.ToolTip = $LblScriptHdr.Text   # long warnings trim with '...' - hover shows the full text
        Update-ReviewButton
    } finally { $script:Step3Loading = $false }
    # First time the editor opens: surface the popup. For a REUSE build always show it (it is the report of what was
    # auto-done + what to check - the whole point); for a fresh build only when something needs attention. The
    # "Reuse report (N)" / "Review (N)" toolbar button reopens the up-to-date version on demand.
    if (-not $script:ReviewAutoShown -and ($script:State.PredecessorModel -or (@(Get-CombinedReview).Count -gt 0))) { $script:ReviewAutoShown = $true; Show-ReviewPopup }
}
# The Create page's build summary as label/value rows (same as MTB): @(label, value[, colour or 'mono']).
function Set-SummaryRows {
    param([object[]]$Rows)
    if (-not $PnlSummary) { return }
    $PnlSummary.Children.Clear(); $PnlSummary.RowDefinitions.Clear()
    $r = 0
    foreach ($row in @($Rows)) {
        $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = 'Auto'; [void]$PnlSummary.RowDefinitions.Add($rd)
        $l = New-Object Windows.Controls.TextBlock; $l.Text = "$($row[0])"; $l.Foreground = '#A0A8B4'; $l.FontSize = 12; $l.Margin = '0,0,12,7'; $l.VerticalAlignment = 'Top'
        [Windows.Controls.Grid]::SetRow($l, $r); [Windows.Controls.Grid]::SetColumn($l, 0); [void]$PnlSummary.Children.Add($l)
        $v = New-Object Windows.Controls.TextBox; $v.Text = "$($row[1])"; $v.TextWrapping = 'Wrap'; $v.Margin = '0,0,0,7'; $v.FontSize = 12.5
        try { $v.Style = $script:Win.FindResource('PbCopyText') } catch {}
        $opt = if ($row.Count -gt 2) { "$($row[2])" } else { '' }
        $v.Foreground = $(if ($opt -like '#*') { $opt } else { '#E7E9ED' })
        if ($opt -eq 'mono') { $v.FontFamily = 'Consolas'; $v.FontSize = 13 }
        [Windows.Controls.Grid]::SetRow($v, $r); [Windows.Controls.Grid]::SetColumn($v, 1); [void]$PnlSummary.Children.Add($v)
        $r++
    }
}

function Populate-Step4 {
    $p = $script:State.Parsed
    if (-not $p -or -not $p.IsValid) {
        Set-SummaryRows -Rows @(,@('Package', 'Enter a valid package name on the Info step first.', '#E0BE7C'))
        if ($PnlReviewItems) { $PnlReviewItems.Visibility = 'Collapsed' }
        return
    }
    $ins  = @($script:State.ChosenInstallers)
    $mode = if ($script:State.LooseFiles) { 'LooseFiles' }
            elseif ($ins.Count -gt 1)     { 'Multiple' }
            elseif ($ins.Count -eq 1)     { "$($script:State.InstallerType)" }
            else                          { 'None' }
    $out  = Join-Path (Get-Setting 'OutputBasePath' 'c:\temp') $p.FullName
    $scriptReady = [bool]"$($script:State.ScriptText)".Trim()
    # Rows = @(label, value[, colour]). Colour only where the value carries a state (script ready / not built).
    $onl = $(try { "$(Get-PBBrand -Path 'OrderNumberLabel' -Default 'RITM')" } catch { 'RITM' })
    $rows = New-Object System.Collections.Generic.List[object]
    $rows.Add(@('Package',   $p.FullName, 'mono'))
    $rows.Add(@($onl,        $(if ("$($script:State.Ritm)".Trim()) { $script:State.Ritm } else { 'none' }), 'mono'))
    $rows.Add(@('Output',    $out, 'mono'))
    $brandTag = "$($script:State.TargetBrand)".ToUpper()
    if ($brandTag) {
        $pretty = ''
        try { $map = Get-PBBrand -Path 'OutgoingPrefix' -Default $null
              if ($map) { $m = @($map.PSObject.Properties | Where-Object { "$($_.Name)".ToUpper() -eq $brandTag })[0]; if ($m) { $pretty = "$($m.Value)" } } } catch {}
        if (@(Get-GpfTargetTags).Count -gt 1) {
            $rows.Add(@('Brand', $(if ($pretty) { "$pretty ($brandTag)  -  outgoing folder gets the $brandTag`_ prefix" } else { $brandTag })))
        }
    }
    $rows.Add(@('Installer', $(if ($ins.Count) { "$mode  -  " + (($ins | ForEach-Object { $_.Name }) -join ', ') } else { 'none chosen' })))
    if ($script:State.PredecessorPath) { $rows.Add(@('Predecessor', (Split-Path $script:State.PredecessorPath -Leaf) + $(if ($script:State.AddUninstallPrevious) { '   (its uninstall runs first)' } else { '' }))) }
    else { $rows.Add(@('Predecessor', 'none - fresh script')) }
    if (-not $script:State.LooseFiles -and ($mode -eq 'MSI' -or $mode -eq 'Multiple')) {
        $rows.Add(@('MST', $(if ($script:State.GenerateMst) { 'built per MSI: vendor MST merged + standard properties; shortcuts and Run keys removed unless kept' } else { 'not generated - vendor MST reused if present, else the MSI installs plain' })))
    }
    if ($script:State.LooseFiles) {
        $rows.Add(@('Loose files', "zipped to Files\$($p.FullName).zip   ARP entry: $(if ($script:State.LooseArp) { 'yes' } else { 'no' })   Start Menu shortcut: $(if ($script:State.LooseShortcut) { 'yes' } else { 'no' })"))
        if ($script:State.LooseTargets) { $rows.Add(@('Shortcut targets', $script:State.LooseTargets, 'mono')) }
    }
    if ("$($script:State.PerUserMode)" -ne 'None' -and "$($script:State.PerUserMode)".Trim()) {
        $rows.Add(@('Per-user', $(if ($script:State.PerUserMode -eq 'ActiveSetup') { 'Active Setup stub in SupportFiles (runs once per user at logon)' } else { 'All-users registry block (Invoke-ADTAllUsersRegistryAction)' })))
    }
    $rows.Add(@('Script', $(if ($scriptReady) { 'ready' } else { 'not built yet - open the Editor step' }), $(if ($scriptReady) { '#57BE8C' } else { '#E0BE7C' })))
    # REVIEW ITEMS: surface anything the script flagged as needing the packager's attention - CLEARLY,
    # spelled out, instead of leaving a buried "# TODO". (e.g. missing silent install / uninstall switches.)
    # Same combined review the Step-3 popup/button uses (script ## REVIEW markers + semantic findings + MST notes).
    $allReview = @(Get-CombinedReview); $openReview = @(Get-OpenReview)
    if ($openReview.Count) {
        $i = 0; $LblReview.Text = (($openReview | ForEach-Object { $i++; "$i.  $_" }) -join "`r`n")
        $confirmed = $allReview.Count - $openReview.Count
        if ($LblReviewHdr) { $LblReviewHdr.Text = "$($openReview.Count) item$(if ($openReview.Count -ne 1) { 's' }) need$(if ($openReview.Count -eq 1) { 's' }) your check before this package is complete$(if ($confirmed) { "  ($confirmed already confirmed)" })" }
        if ($PnlReviewItems) { $PnlReviewItems.Visibility = 'Visible' }
    } else {
        $LblReview.Text = ''
        if ($PnlReviewItems) { $PnlReviewItems.Visibility = 'Collapsed' }
        if ($allReview.Count) { $rows.Add(@('Review', "all $($allReview.Count) item$(if ($allReview.Count -ne 1) { 's' }) confirmed", '#57BE8C')) }
    }
    Set-SummaryRows -Rows $rows.ToArray()
    # If a package was already created this session, re-enable/refresh the Publish form.
    if ($script:State.CreatedPath -and (Test-Path "$($script:State.CreatedPath)")) { Populate-Publish }
    else { $PnlPublish.IsEnabled = $false; if ($CreatePanel) { $CreatePanel.Visibility = 'Collapsed' } }
}

# Auto-fetch the SCCM/Intune publish fields from the just-created package, fill the form, enable it.
function Populate-Publish {
    if (Get-Command Update-PBChrome -EA SilentlyContinue) { Update-PBChrome }   # CreatedPath just changed -> strip says "created"
    if (-not $PnlPublish) { return }
    if (-not $script:State.CreatedPath -or -not (Test-Path $script:State.CreatedPath)) { $PnlPublish.IsEnabled = $false; if ($CreatePanel) { $CreatePanel.Visibility = 'Collapsed' }; return }
    $base = $null; $fetchErr = $null
    try { $base = Get-SccmFieldsFromPackage -PackagePath $script:State.CreatedPath } catch { $fetchErr = "$($_.Exception.Message)"; Write-Log "Publish fetch failed: $fetchErr" Warning }
    if (-not $base) {
        $LblPublishLog.Text = if ($fetchErr) { "Could not read package fields: $fetchErr" }
                              else { "Could not read package fields - the folder must contain a PSADT script (Invoke-AppDeployToolkit.ps1 or Deploy-Application.ps1). Browse to the package ROOT (or its Content folder)." }
        $LblPublishLog.Foreground = '#F48771'; return
    }
    $script:State.PublishBase = $base
    if ($TxtPubPkgName) { $TxtPubPkgName.Text = "$($base.FullName)" }   # package name field - auto-fill from the created/loaded package
    $TxtPubProductName.Text   = "$($base.ProductName)"
    $TxtPubPublisher.Text     = "$($base.Publisher)"
    $TxtPubVersion.Text       = "$($base.Version)"
    $TxtPubProductCode.Text   = "$($base.ProductCode)"
    $TxtPubBrandingKey.Text   = "$($base.BrandingKey)"
    $TxtPubUninstallKey.Text  = "$($base.UninstallKey)"
    $TxtPubDetectVersion.Text = "$($base.DetectVersion)"
    $TxtPubInstall.Text       = "$($base.InstallCmd)"
    $TxtPubUninstall.Text     = "$($base.UninstallCmd)"
    $TxtPubRepair.Text        = "$($base.RepairCmd)"
    $TxtPubDescription.Text   = "$($base.Description)"
    # Convenience: pre-fill the app-name fields across the Modify/Testing/Troubleshoot/Dev-Test tabs.
    foreach ($tb in @($TxtModAppName,$TxtTestAppName,$TxtTsAppName,$TxtMoveAppName,$TxtIntuneAssignApp)) { if ($tb -and -not $tb.Text.Trim()) { $tb.Text = "$($base.FullName)" } }
    foreach ($sb in @($TxtModContentSrc,$TxtIntuneContentSrc)) { if ($sb -and -not $sb.Text.Trim()) { $sb.Text = "$($script:State.CreatedPath)" } }
    $PnlPublish.IsEnabled = $true
    if ($CreatePanel) { $CreatePanel.Visibility = 'Visible' }   # a package is loaded -> show the Create buttons
    $LblPublishLog.Text = "Ready - fields auto-fetched from $($base.FullName). Edit if needed, then Create in SCCM / Intune."
    $LblPublishLog.Foreground = '#A0A8B4'
}
# Merge the (possibly edited) form fields over the auto-fetched base. Used by both SCCM and Intune.
function Get-PublishFields {
    $f = @{}; foreach ($k in $script:State.PublishBase.Keys) { $f[$k] = $script:State.PublishBase[$k] }
    $f.ProductName   = $TxtPubProductName.Text.Trim()
    $f.Publisher     = $TxtPubPublisher.Text.Trim()
    $f.Version       = $TxtPubVersion.Text.Trim()
    $f.ProductCode   = $TxtPubProductCode.Text.Trim()
    $f.BrandingKey   = $TxtPubBrandingKey.Text.Trim()
    $f.UninstallKey  = $TxtPubUninstallKey.Text.Trim()
    $f.DetectVersion = $TxtPubDetectVersion.Text.Trim()
    $f.InstallCmd    = $TxtPubInstall.Text.Trim()
    $f.UninstallCmd  = $TxtPubUninstall.Text.Trim()
    $f.RepairCmd     = $TxtPubRepair.Text.Trim()
    $f.Description   = $TxtPubDescription.Text
    $sel = if ($CmbDetectType.SelectedItem) { "$($CmbDetectType.SelectedItem.Content)" } else { 'Version' }
    $f.DetectType = switch -Wildcard ($sel) { 'String*' {'String'} 'ProductCode*' {'ProductCode'} 'None*' {'None'} default {'Version'} }
    return $f
}

# Manual installer selection: browse (default to RepositoryPath) and pick installers one by
# one. Bypasses Resolve-Source's subfolder auto-detection (sources scattered in subfolders).
function Add-ManualInstallers {
    param([string[]]$Paths)
    $cur = New-Object System.Collections.Generic.List[object]
    foreach ($i in @($script:State.ChosenInstallers)) { $cur.Add($i) }
    $have = @{}; foreach ($i in $cur) { $have[$i.FullName] = $true }
    foreach ($p in @($Paths)) {
        if ((Test-Path -LiteralPath $p) -and -not $have.ContainsKey($p)) { $cur.Add((Get-Item -LiteralPath $p)); $have[$p] = $true }
    }
    if ($cur.Count -eq 0) { return }
    $script:State.ChosenInstallers = $cur.ToArray()
    Update-ChosenResolved
}
# Re-derive $State.Resolved from whatever is in ChosenInstallers (common parent = source folder; detect Icons/Docs
# under it; install paths made relative to it). Shared by Add-ManualInstallers and Replace-InstallerInChain.
function Update-ChosenResolved {
    if (Get-Command Update-PBChrome -EA SilentlyContinue) { Update-PBChrome }   # installers changed -> strip
    $ins = @($script:State.ChosenInstallers)
    if (-not $ins.Count) { return }
    $parent = Get-CommonParent -Files $ins
    if (-not $parent) { $parent = Split-Path -Parent $ins[0].FullName }
    $iconFolder = Find-FolderByNames -Root $parent -Names $script:IconNames -MaxDepth 4
    $docFolder  = Find-FolderByNames -Root $parent -Names $script:DocNames  -MaxDepth 4
    # The installers' common parent is often a SUBfolder (e.g. \source); the package's Documents/Icons sit higher up
    # as SIBLINGS. Climb to the package root (scoped - never into a different package) and search there too, exactly
    # like Resolve-Source. Without this, mixing a MANUAL pick with a FETCHED installer dropped the \doc folder.
    if (-not $iconFolder -or -not $docFolder) {
        $pkgRoot = if (Get-Command Get-PackageRootFolder -EA SilentlyContinue) { Get-PackageRootFolder -Path $parent } else { $null }
        if ($pkgRoot -and $pkgRoot -ne $parent) {
            if (-not $iconFolder) { $iconFolder = Find-FolderByNames -Root $pkgRoot -Names $script:IconNames -MaxDepth 4 }
            if (-not $docFolder)  { $docFolder  = Find-FolderByNames -Root $pkgRoot -Names $script:DocNames  -MaxDepth 4 }
        }
    }
    if (-not $iconFolder) { $ico = Get-ChildItem -LiteralPath $parent -File -Recurse -Filter *.ico -ErrorAction SilentlyContinue | Select-Object -First 1; if ($ico) { $iconFolder = $ico.Directory.FullName } }
    # GPF request auto-detect: a manual installer pick from INSIDE a GPF request tree (<Request>\Sources\Files\setup.msi)
    # must ship the REQUEST's curated documents (module request, install instructions, mails, Docs_EQS - Complexity +
    # Predecessor excluded), exactly like the fetch flow - not an empty Documents folder. Climb to the request root once
    # and resolve it so State.GpfRequest is populated even when the user never clicked Fetch.
    if (-not $script:State.GpfRequest -and (Get-Command Find-GpfRequestRoot -EA SilentlyContinue) -and (Get-Command Resolve-GpfRequest -EA SilentlyContinue)) {
        $reqRoot = Find-GpfRequestRoot -StartPath $parent
        if ($reqRoot) {
            try { $script:State.GpfRequest = Resolve-GpfRequest -RequestPath $reqRoot; Write-Log "GPF request detected from manual pick: '$(Split-Path $reqRoot -Leaf)' - shipping its curated documents." Success }
            catch { Write-Log "GPF request auto-resolve failed for '$reqRoot': $($_.Exception.Message)" Warning }
        }
    }
    $gpfDocs = if ($script:State.GpfRequest) { @($script:State.GpfRequest.DocItems) } else { @() }

    $docItems = @(); if ($docFolder) { $docItems += $docFolder }
    # When a GPF request is in play, ITS curated document set is authoritative - do NOT also sibling/loose-harvest (that
    # would drag in Sources\SupportFiles and other non-documents). Only run the generic harvesting for a non-GPF pick.
    if (-not $gpfDocs.Count) {
        # Manual pick with NO doc folder found: if the installer sits in a real package layout (<Pkg>\source\setup.exe),
        # the docs are SIBLINGS of the source folder - carry them into Documentation. A generic/temp parent yields nothing
        # (Get-SiblingDocItems returns @()), so a throwaway temp\setup.exe just puts the exe into Files with no extras.
        if (-not $docFolder -and (Get-Command Get-SiblingDocItems -EA SilentlyContinue)) {
            $excl = @(@($ins | ForEach-Object { $_.FullName }) + @($iconFolder) | Where-Object { $_ })
            $sib  = @(Get-SiblingDocItems -InstallerParent $parent -ExcludePaths $excl)
            if ($sib.Count) { $docItems += $sib; Write-Log "Manual source: carried $($sib.Count) sibling item(s) of '$(Split-Path $parent -Leaf)' into Documentation." }
        }
        # FLAT manual pick: installer sits directly in a mixed folder (NOT a \source subfolder, NOT a generic/temp folder).
        # Route loose DOCUMENT files (by extension) to Documentation; installers + support files (.dll/.inf/.cfg/...) stay
        # in Files, and subfolders (e.g. Firefox's payload tree) are left in Files untouched. The \doc folder, if any, was
        # already added above. For a \source pick everything in source -> Files (siblings handle docs); for a temp\ pick
        # nothing extra is pulled (it's a generic scratch folder).
        $parentLeaf = "$(Split-Path -Leaf $parent)".ToLower()
        if (($script:SourceNames -inotcontains $parentLeaf) -and ($script:GenericFolderNames -inotcontains $parentLeaf) -and (Get-Command Get-LooseDocFiles -EA SilentlyContinue)) {
            $loose = @(Get-LooseDocFiles -Folder $parent)
            if ($loose.Count) { $docItems += $loose; Write-Log "Manual source (flat): routed $($loose.Count) loose document file(s) to Documentation; installer + support files stay in Files." }
        }
    }
    # GPF request docs are authoritative when present; else the generic harvest above. NEVER ship a predecessor's doc.
    if ($gpfDocs.Count) { $docItems = @($gpfDocs) }
    $docItems = @($docItems | Where-Object { $_ -and ("$_" -notmatch '(?i)[\\/]predecessor([\\/]|$)') } | Select-Object -Unique)
    if ($gpfDocs.Count) { Write-Log "Documents from the GPF request: $($docItems.Count) item(s) (module request, install instructions, mails, Docs_EQS)." }
    $script:State.Resolved = @{ Valid=$true; Mode='manual'; Manual=$false; RootPath=$parent; PayloadRoot=$parent; Installers=$ins; DocItems=$docItems; IconsPath=$iconFolder }
    $script:State.SourceFolder = $parent
    $script:State.LooseFiles = $false
    Invalidate-From 2
    $names = ($ins | ForEach-Object { $_.Name }) -join ', '
    $LblSrc.Text = "[source: $(Split-Path $parent -Leaf)] installer(s): $names   |   doc items: $($docItems.Count)"
    $LblSrc.Foreground = '#CE9178'
}
# Swap ONE installer in the chain for the given replacement path(s), preserving the order of the others (used when
# a per-EXE 'bundled MSI' / 'run & capture' yields MSIs for just that one source in a multi-installer package).
function Replace-InstallerInChain {
    param([Parameter(Mandatory)][string]$OldFullName, [string[]]$NewPaths)
    $cur = New-Object System.Collections.Generic.List[object]
    foreach ($i in @($script:State.ChosenInstallers)) {
        if ($i.FullName -eq $OldFullName) { foreach ($np in @($NewPaths)) { if (Test-Path -LiteralPath $np) { $cur.Add((Get-Item -LiteralPath $np)) } } }
        else { $cur.Add($i) }
    }
    $script:State.ChosenInstallers = $cur.ToArray()
    Update-ChosenResolved
}

# SOFT length counter (Porsche, 22.09.2026): Brand.NameLengthLimit in settings.json (34, the same count GPF checks:
# Manufacturer + Product + Version + Language, prefix not counted). Live while typing, text under the name only -
# amber when over, never a popup, never a block. Brands without the setting (GPF) keep their own rule and show nothing.
function Update-NameLengthCounter {
    param($Parsed)
    if (-not $LblNameLen) { return }
    $lim = 0; try { $lim = [int](Get-PBBrand -Path 'NameLengthLimit' -Default 0) } catch {}
    if ($lim -le 0) { $LblNameLen.Visibility = 'Collapsed'; return }
    $name = "$($TxtPkg.Text)".Trim()
    if (-not $name) { $LblNameLen.Visibility = 'Collapsed'; $LblNameLen.Text = ''; return }
    if (-not $Parsed) { $Parsed = Parse-PackageName $name }
    if ($Parsed -and $Parsed.IsValid) {
        $len = Get-GpfVwgNameLength -NewPkg $Parsed          # the exact count once the name is complete
    } else {
        # FROM THE FIRST CHARACTER (user, 22.09.2026): count what is typed so far the same way - everything except
        # the '_' separators, the architecture token and the "-0001" release, which the limit does not count.
        $parts = @($name -split '_' | Where-Object { $_ -notmatch '^(?i)(x86|x64|x86_64|ALL)$' })
        $len = (($parts -join '') -replace '-\d{1,4}$', '').Length
    }
    $LblNameLen.Visibility = 'Visible'
    if ($len -gt $lim) { $LblNameLen.Text = "$len of $lim characters used (Manufacturer + Product + Version + Language) - $($len - $lim) over the limit; consider a shorter name"; $LblNameLen.Foreground = '#F48771' }
    else { $LblNameLen.Text = "$len of $lim characters used (Manufacturer + Product + Version + Language)"; $LblNameLen.Foreground = '#57BE8C' }
}

function Parse-Current {
    $name = $TxtPkg.Text.Trim()
    $script:State.PkgName = $name
    # GPF name rules (finding): SPECIAL characters are not allowed, but a SPACE is fine (GPF app names may contain spaces);
    # a space must NOT sit directly before or after an underscore (the "_" are the field separators). Allowed = letters,
    # numbers, dot, dash, underscore and space; block anything else, and reject " _" / "_ ".
    # Brand.NameAllowSpecialChars (settings.json, Porsche = true, 22.09.2026): their names carry special characters, which
    # are then carried into the package as typed. Only what Windows cannot put in a folder name is refused there
    # (\ / : * ? " < > |); the space-next-to-underscore rule stays for every brand.
    $allowSpecial = $false; try { $allowSpecial = [bool](Get-PBBrand -Path 'NameAllowSpecialChars' -Default $false) } catch {}
    $badChars = @([regex]::Matches($name, $(if ($allowSpecial) { '[\\/:*?"<>|]' } else { '[^A-Za-z0-9._\- ]' })))
    if ($name -and ($badChars.Count -or ($name -match '\s_' ) -or ($name -match '_\s'))) {
        $script:State.Parsed = @{ IsValid = $false; FullName = $name }
        if ($badChars.Count) {
            $uniq = (@($badChars | ForEach-Object { "'$($_.Value)'" } | Select-Object -Unique) -join ', ')
            $LblParsed.Text = $(if ($allowSpecial) { "Character(s) that cannot be part of a folder name: $uniq. Please change the name." }
                                else { "Special character(s) not allowed in the package name: $uniq. Letters, numbers, dot, dash, underscore and spaces are fine. Please change the name." })
        } else {
            $LblParsed.Text = "A space must not sit directly before or after an underscore ('_'). Remove the space next to the '_'. Please change the name."
        }
        $LblParsed.Foreground = '#F48771'
        return $false
    }
    $p = Parse-PackageName $name
    $script:State.Parsed = $p
    Update-NameLengthCounter -Parsed $p
    if ($p.IsValid) {
        $LblParsed.Text = "Vendor=$($p.Vendor)  App=$($p.AppName)  Arch=$($p.Arch)  Ver=$($p.Version)  Lang=$($p.Lang)"
        $LblParsed.Foreground = '#6A9955'
        # Group (VWG) MECM name-length gate (#14): HARD STOP at Step 1 when Manufacturer+Product+Version+Language
        # exceeds 34 characters - the name is treated as invalid so Next/step-jump are blocked until it is shortened.
        if ("$($script:State.TargetBrand)".ToUpper() -eq 'VWG') {
            $vwgLen = Get-GpfVwgNameLength -NewPkg $p
            if ($vwgLen -gt 34) {
                $p.IsValid = $false; $script:State.Parsed = $p
                $LblParsed.Text = "Group/VWG name is $vwgLen characters - over the 34-character MECM limit (Manufacturer+Product+Version+Language). Shorten the name to continue."
                $LblParsed.Foreground = '#F48771'
                return $false
            }
        }
    } else {
        $LblParsed.Text = "Could not parse - expected Vendor_App_Arch_Version-Release_Lang"
        $LblParsed.Foreground = '#F48771'
    }
    if (Get-Command Update-PBChrome -EA SilentlyContinue) { Update-PBChrome }   # header + strip follow the parsed name
    return $p.IsValid
}
# The order-number field (RITM / AES / Order ID) is FREE TEXT in every brand (user, 20.09.2026: "those don't have
# to be strict"). No format, no "required" - the package name carries the rules; the order number is recorded as
# typed. The gate stays as a function so the two call sites keep reading naturally; it always passes.
function Test-OrderNumberGate { return $true }
# PROACTIVE: when a valid name is entered, check the live share for the SAME vendor+app at another version and,
# if found, tell the user predecessor reuse is available. Server-side -Filter keeps it fast; cached per app so it
# scans at most once per vendor+app; skipped once a predecessor is already chosen. Run on LostFocus (not per
# keystroke) so typing never hitches.
# (The automatic 'a previous version exists' hint was removed 23.09.2026 on the team's request: it searched the
#  live share while the packager was still typing, which is exactly what Find predecessor is for.)

# Copy a NETWORK source folder to a LOCAL cache ONCE so all later work (re-resolve, Icons/Docs detection, the build
# copy) reads locally instead of hammering the share. Local sources pass through unchanged. Returns the path to use.
function Stage-SourceLocal {
    param([string]$Folder)
    if (-not $Folder -or -not (Test-Path -LiteralPath $Folder)) { return $Folder }
    if ($Folder -notmatch '^\\\\') { return $Folder }                 # only stage UNC / network sources
    if ((Get-Setting 'StageSourceLocal' $true) -eq $false) { return $Folder }   # opt-out via settings.json
    $ownCard = $false   # set once the card is ours; the finally below is what guarantees it comes down
    try {
        $leaf = Split-Path $Folder -Leaf
        $dest = Join-Path (Get-WorkPath 'Source') $leaf
        if ($LblSrc) { $LblSrc.Text = "Copying source locally (one-time, from the share)..."; try { (Get-PBMainWindow).Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch {} }
        # Inside Fetch the card is already up - just change its line; from any other caller show it ourselves, so a
        # multi-minute copy is never a frozen window with no explanation.
        $ownCard = -not $script:Busy.Show
        if ($ownCard) { Show-PBBusy -Title 'Copying source locally' -Detail "One-time copy of $leaf from the share..." }
        else { Set-PBProgress -Percent -1 -Status "Copying $leaf from the share to this machine (one-time)..." }
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }   # refresh any stale copy
        # an access problem on the share offers a sign-in and copies once more (Invoke-PBWithShareAccess)
        Invoke-PBWithShareAccess -Path $Folder -Purpose 'the source folder' -Action {
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
            Copy-Item -LiteralPath $Folder -Destination $dest -Recurse -Force -ErrorAction Stop
        }
        if (Get-Command Unblock-PBPath -EA SilentlyContinue) { Unblock-PBPath -Path $dest }   # strip Mark-of-the-Web
        Write-Log "Staged source locally (one-time): $Folder -> $dest" Success
        return $dest
    } catch {
        Write-Log "Could not stage source locally ($($_.Exception.Message)) - working directly from the share." Warning
        return $Folder
    } finally { if ($ownCard) { Hide-PBBusy } }   # the ONLY place the card comes down: every exit passes here
}

function Set-ResolvedSource {
    param([string]$Folder)
    $Folder = Stage-SourceLocal -Folder $Folder   # network -> local copy, then work from local
    $script:State.SourceFolder = $Folder
    $res = Resolve-Source -RootPath $Folder
    $script:State.Resolved = $res
    $script:State.ZipPayload = $null; $script:State.ZipInstallers = @()
    # GPF ZIP PAYLOAD (F25/F34): the source is a single .zip kept VERBATIM. Read the installer entries INSIDE it (one step
    # into the wrapper folder - INSTANT, no extraction), auto-pick a single msi/exe, else let the packager choose. The zip
    # is Expand-ZipFile'd to $envTemp\<App>_<Ver> at install and the chosen installer(s) run from there.
    if ("$($res.ZipPayload)".Trim()) {
        $script:State.ZipPayload = $res.ZipPayload
        $zipEntries = @(Get-ZipInstallerEntries -ZipPath $res.ZipPayload)
        $zipReal    = @($zipEntries | Where-Object { $_.Extension -in '.msi','.exe' })
        $picked = @()
        if ($zipEntries.Count -eq 0) {
            # nothing recognisable inside - keep the zip as a plain loose payload (packager writes the command)
            $script:State.ChosenInstallers = @([pscustomobject]@{ Name=[IO.Path]::GetFileName($res.ZipPayload); FullName=$res.ZipPayload; Extension='.zip' })
            $script:State.LooseFiles = $true
            $LblSrc.Text = "[zip] $([IO.Path]::GetFileName($res.ZipPayload)) - kept as-is; no installer detected inside (fill the install command)."
            $LblSrc.Foreground='#CE9178'; Invalidate-From 2; return
        }
        elseif ($zipEntries.Count -eq 1 -or $zipReal.Count -eq 1) {
            $picked = if ($zipEntries.Count -eq 1) { @($zipEntries) } else { @($zipReal) }   # single installer (or a single real msi/exe) -> auto
        }
        else {
            $picked = @(Show-InstallerPicker -Installers $zipEntries)   # multiple -> prompt
            if (-not $picked -or $picked.Count -eq 0) { $LblSrc.Text='No installer selected from the zip.'; $LblSrc.Foreground='#F48771'; return }
        }
        $script:State.ZipInstallers    = $picked
        $script:State.ChosenInstallers = @($picked | ForEach-Object { [pscustomobject]@{ Name=$_.Name; FullName=("$($res.ZipPayload)".TrimEnd('\') + '\' + "$($_.RelPath)".TrimStart('\')); Extension=$_.Extension; RelPath=$_.RelPath; InZip=$true } })
        $script:State.LooseFiles = $false
        Invalidate-From 2
        $LblSrc.Text = "[zip] $([IO.Path]::GetFileName($res.ZipPayload)) -> run: $(($picked | ForEach-Object { $_.Name }) -join ', ')   (zip kept as-is; extracted to `$envTemp at install)"
        $LblSrc.Foreground='#CE9178'
        return
    }
    if (-not $res.Valid) { $LblSrc.Text = "Source at $Folder - no installer found."; $LblSrc.Foreground='#F48771'; return }
    $sel = Select-Installers -Installers $res.Installers
    $script:State.LooseFiles = $false
    if ($sel.NeedsPrompt) {
        $chosen = Show-InstallerPicker -Installers $sel.Options
        if (-not $chosen -or $chosen.Count -eq 0) { $LblSrc.Text="No installer selected."; return }
        $script:State.ChosenInstallers = $chosen
        $script:State.LooseFiles = [bool]$script:pickLoose   # user opted to treat the selection as loose files
    } else { $script:State.ChosenInstallers = $sel.Chosen }
    # The resolver may also classify a payload with no installer as 'loose'/'scan' - honour that too.
    if ($res.Mode -eq 'loose') { $script:State.LooseFiles = $true }
    Invalidate-From 2   # new source => Step 2 detection (type/PC/MST) and Step 3 script must rebuild
    $names = ($script:State.ChosenInstallers | ForEach-Object { $_.Name }) -join ', '
    $looseTag = if ($script:State.LooseFiles) { '  [loose files]' } else { '' }
    $LblSrc.Text = "[$($res.Mode)] installer(s): $names$looseTag   |   doc items: $($res.DocItems.Count)"
    $LblSrc.Foreground = '#CE9178'
    Update-PBChrome
    # If the new source's TYPE or STRUCTURE differs from the predecessor, warn loudly (popup) - the predecessor's
    # commands are kept (with the version/filename/ProductCode swaps) and must be reviewed/aligned.
    $warn = Get-SourceWarning
    if ($warn -and $warn -match 'Source (TYPE|STRUCTURE)|MULTI-COMPONENT') {
        Invoke-PBWithoutBusy { [System.Windows.MessageBox]::Show($warn, 'Source differs from the predecessor', 'OK', 'Warning') | Out-Null }
    }
}

# Per-MSI MST cleanup flags (Keep desktop shortcut / Keep Run key), keyed by full path.
function Get-MsiFlags {
    param([string]$FullName)
    if (-not $script:State.MsiFlags) { $script:State.MsiFlags = @{} }
    if (-not $script:State.MsiFlags.ContainsKey($FullName)) { $script:State.MsiFlags[$FullName] = @{ KeepShortcut=$false; KeepRunKey=$false; KeepStartup=$false; KeepStray=$false } }
    return $script:State.MsiFlags[$FullName]
}

# Build per-installer rows for Multiple mode: each EXE gets install/uninstall arg boxes; each
# MSI gets its own Keep-shortcut / Keep-Run-key toggles + an extra-properties box.
function Build-MultiArgRows {
    param([object[]]$Installers)
    if (-not $script:State.InstallerArgs) { $script:State.InstallerArgs = @{} }
    # Prune cached install/uninstall args for installers no longer in the set, so a previous source's typed args
    # can't bleed into a new package (the "cache/reset" issue). Keyed by FullName; only current installers survive.
    $live = @{}; foreach ($it in $Installers) { $live["$($it.FullName)"] = $true }
    foreach ($k in @($script:State.InstallerArgs.Keys)) { if (-not $live.ContainsKey($k)) { [void]$script:State.InstallerArgs.Remove($k) } }
    foreach ($it in $Installers) {
        $fn = $it.FullName
        if (-not $script:State.InstallerArgs.ContainsKey($fn)) { $script:State.InstallerArgs[$fn] = @{ Install=''; Uninstall='' } }
        $row = New-Object Windows.Controls.StackPanel; $row.Margin = '0,2,0,8'
        $lbl = New-Object Windows.Controls.TextBlock; $lbl.Text = $it.Name; $lbl.Foreground = '#CE9178'; [void]$row.Children.Add($lbl)
        if ($it.Extension.ToLower() -eq '.exe') {
            $li = New-Object Windows.Controls.TextBlock; $li.Text='install args'; $li.Foreground='#B7BEC8'; $li.FontSize=12; [void]$row.Children.Add($li)
            $ti = New-Object Windows.Controls.TextBox; $ti.Text=[string]$script:State.InstallerArgs[$fn].Install; $ti.Tag=$fn; $ti.FontFamily='Consolas'; $ti.Margin='0,0,0,4'
            $ti.add_TextChanged({ if ($script:Rehydrating) { return }; $script:State.InstallerArgs[$this.Tag].Install = $this.Text; Invalidate-From 3 })
            [void]$row.Children.Add($ti)
            $lu = New-Object Windows.Controls.TextBlock; $lu.Text='uninstall args'; $lu.Foreground='#B7BEC8'; $lu.FontSize=12; [void]$row.Children.Add($lu)
            $tu = New-Object Windows.Controls.TextBox; $tu.Text=[string]$script:State.InstallerArgs[$fn].Uninstall; $tu.Tag=$fn; $tu.FontFamily='Consolas'
            $tu.add_TextChanged({ if ($script:Rehydrating) { return }; $script:State.InstallerArgs[$this.Tag].Uninstall = $this.Text; Invalidate-From 3 })
            [void]$row.Children.Add($tu)
            # KB suggestions (install + uninstall) for THIS exe - keyed off vendor/app AND engine type.
            $eng = try { Get-InstallerEngine -Path $fn } catch { $null }
            $pp  = $script:State.Parsed
            $rec = try { Get-KBRecommendation -Vendor $(if($pp){$pp.Vendor}) -App $(if($pp){$pp.AppName}) -Engine $eng -InstallerName $it.Name } catch { $null }
            # Install suggestion: KB match -> else the engine's own default silent switch (parity with the single-EXE
            # Update-KbHint, so a no-KB-match EXE still shows SOMETHING). PackagedAsMsi recs carry the MSI command, not
            # EXE args, so they're not offered as install args here.
            $recIn = if ($rec -and "$($rec.Install)".Trim() -and -not $rec.PackagedAsMsi) { "$($rec.Install)" }
                     elseif ($rec -and $rec.PackagedAsMsi) { '' }
                     elseif (Get-Command Get-EngineSwitch -EA SilentlyContinue) { "$(Get-EngineSwitch -Engine $eng)" }
                     else { '' }
            $recUn = if ($rec -and "$($rec.Uninstall)".Trim()) { "$($rec.Uninstall)" } elseif (Get-Command Get-EngineUninstallSwitch -EA SilentlyContinue) { "$(Get-EngineUninstallSwitch -Engine $eng)" } else { '' }
            $recUnExe = if ($rec -and "$($rec.UninstallExe)".Trim()) { "$($rec.UninstallExe)" } elseif (Get-Command Get-EngineUninstaller -EA SilentlyContinue) { "$(Get-EngineUninstaller -Engine $eng)" } else { '' }
            $mkKbRow = {
                param($label, $val, $colour, $targetBox)
                if (-not "$val".Trim()) { return }
                $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation='Horizontal'; $sp.Margin='0,4,0,2'
                $sl = New-Object Windows.Controls.TextBlock; $sl.Text = "$label  $val"; $sl.Foreground=$colour; $sl.FontSize=11
                $sl.VerticalAlignment='Center'; $sl.TextWrapping='Wrap'; $sl.MaxWidth=560; $sl.FontFamily='Consolas'
                [void]$sp.Children.Add($sl)
                $bu = New-Object Windows.Controls.Button; $bu.Content='Use'; $bu.FontSize=12; $bu.Padding='8,1'; $bu.Margin='10,0,0,0'; $bu.VerticalAlignment='Center'
                $useV = "$val"; $box = $targetBox
                $bu.add_Click({ $box.Text = $useV }.GetNewClosure())
                [void]$sp.Children.Add($bu); [void]$row.Children.Add($sp)
            }
            $afNote = if (Test-NeedsAnswerFile -Switch $recIn) { '  (+ response file needed)' } else { '' }
            & $mkKbRow "KB [$eng] install:" "$recIn$afNote" '#56C8D6' $ti
            & $mkKbRow ("KB [$eng] uninstall$(if($recUnExe.Trim()){" ($recUnExe)"}):") $recUn '#FFE7C2' $tu
            # Per-EXE tooling: probe /? help. ('Check bundled MSI' / 'Run & capture' are hidden for now - same as the
            # single-EXE case; the snapshot analyzer covers capture without running the installer on this machine.)
            $rowStatus = New-Object Windows.Controls.TextBlock; $rowStatus.Foreground='#A0A8B4'; $rowStatus.FontSize=12; $rowStatus.TextWrapping='Wrap'; $rowStatus.Margin='0,2,0,0'
            $tools = New-Object Windows.Controls.StackPanel; $tools.Orientation='Horizontal'; $tools.Margin='0,4,0,0'
            $exeIt = $it
            foreach ($spec in @(,@('Probe /?','p'))) {
                $btn = New-Object Windows.Controls.Button; $btn.Content=$spec[0]; $btn.FontSize=12; $btn.Padding='8,1'; $btn.Margin='0,0,6,0'; $btn.Tag=$spec[1]
                $btn.add_Click({
                    switch ("$($this.Tag)") {
                        'b' { Invoke-BundledMsiCheck -Exe $exeIt -ReplaceInChain -StatusLabel $rowStatus }
                        'c' { Invoke-RunCapture      -Exe $exeIt -ReplaceInChain -StatusLabel $rowStatus }
                        'p' { Invoke-ProbeHelp       -Exe $exeIt -StatusLabel $rowStatus }
                    }
                }.GetNewClosure())
                [void]$tools.Children.Add($btn)
            }
            [void]$row.Children.Add($tools); [void]$row.Children.Add($rowStatus)
        } else {
            # MSI: per-MSI Keep toggles + extra-properties box. Neither affects the script -> no rebuild.
            $fl = Get-MsiFlags $fn
            $cs = New-Object Windows.Controls.CheckBox; $cs.Content='Keep desktop shortcut (else removed)'; $cs.Foreground='#E7E9ED'; $cs.FontSize=12; $cs.IsChecked=[bool]$fl.KeepShortcut; $cs.Tag=$fn
            $cs.add_Click({ if ($script:Rehydrating) { return }; (Get-MsiFlags $this.Tag).KeepShortcut = [bool]$this.IsChecked })
            [void]$row.Children.Add($cs)
            $cst = New-Object Windows.Controls.CheckBox; $cst.Content='Keep Startup / autostart shortcut (else removed)'; $cst.Foreground='#E7E9ED'; $cst.FontSize=12; $cst.IsChecked=[bool]$fl.KeepStartup; $cst.Tag=$fn
            $cst.add_Click({ if ($script:Rehydrating) { return }; (Get-MsiFlags $this.Tag).KeepStartup = [bool]$this.IsChecked })
            [void]$row.Children.Add($cst)
            $csy = New-Object Windows.Controls.CheckBox; $csy.Content='Keep SendTo / stray shortcuts (else removed)'; $csy.Foreground='#E7E9ED'; $csy.FontSize=12; $csy.IsChecked=[bool]$fl.KeepStray; $csy.Tag=$fn
            $csy.add_Click({ if ($script:Rehydrating) { return }; (Get-MsiFlags $this.Tag).KeepStray = [bool]$this.IsChecked })
            [void]$row.Children.Add($csy)
            $cr = New-Object Windows.Controls.CheckBox; $cr.Content='Keep Run key 32/64 (else removed)'; $cr.Foreground='#E7E9ED'; $cr.FontSize=12; $cr.IsChecked=[bool]$fl.KeepRunKey; $cr.Tag=$fn
            $cr.add_Click({ if ($script:Rehydrating) { return }; (Get-MsiFlags $this.Tag).KeepRunKey = [bool]$this.IsChecked })
            [void]$row.Children.Add($cr)
            if (-not $script:State.MsiProps) { $script:State.MsiProps = @{} }
            if (-not $script:State.MsiProps.ContainsKey($fn)) { $script:State.MsiProps[$fn] = '' }
            $lp = New-Object Windows.Controls.TextBlock; $lp.Text='extra MSI properties (one per line, e.g. ALLUSERS=1)'; $lp.Foreground='#B7BEC8'; $lp.FontSize=12; [void]$row.Children.Add($lp)
            $tp = New-Object Windows.Controls.TextBox; $tp.Text=[string]$script:State.MsiProps[$fn]; $tp.Tag=$fn; $tp.FontFamily='Consolas'; $tp.AcceptsReturn=$true; $tp.TextWrapping='Wrap'
            $tp.add_TextChanged({ if ($script:Rehydrating) { return }; $script:State.MsiProps[$this.Tag] = $this.Text })
            [void]$row.Children.Add($tp)
            # In-tool Property-table editor for THIS MSI (no Orca needed); result lands in the box above.
            $bv = New-Object Windows.Controls.Button; $bv.Content='View MSI properties...'; $bv.Padding='8,2'; $bv.FontSize=12; $bv.HorizontalAlignment='Left'; $bv.Margin='0,4,0,0'; $bv.Tag=$fn
            $bv.add_Click({
                # via main-scope helpers: $script:State is NOT reachable inside this GetNewClosure block.
                $res = Show-MsiPropertiesDialog -MsiPath $this.Tag -ExistingText (Get-MsiPropsFor $this.Tag) -MsiName (Split-Path $this.Tag -Leaf)
                if ($null -ne $res) { $t = "$($res.Text)"; Set-MsiPropsFor $this.Tag $t; $tp.Text = $t }
            }.GetNewClosure())
            [void]$row.Children.Add($bv)
        }
        [void]$PnlMultiArgs.Children.Add($row)
    }
}

function Populate-Step2 {
    # Rehydrate from $State. Type + ProductCode are computed ONCE and cached in
    # state; on later visits we just reflect what's there (no recompute, no stale).
    $script:Rehydrating = $true
    try {
        $ins = @($script:State.ChosenInstallers)
        if ($ins.Count -eq 0) {
            $LblInst.Text='No installer chosen yet - go back to Info and fetch the source, or add the installer by hand.'; $LblInst.Foreground = '#A0A8B4'; $TxtType.Text=''; $TxtPC.Text=''
            # nothing to configure: the option sections stay out of the way until there is an installer
            foreach ($sec in @($SecMsi, $SecExe, $SecAnalysis, $SecMulti, $SecLoose, $PnlLoose, $PnlKbHint)) { if ($sec) { $sec.Visibility = 'Collapsed' } }
            return
        }
        $LblInst.Foreground = '#CE9178'
        $first = $ins[0]
        $LblInst.Text = ($ins | ForEach-Object { $_.Name }) -join ', '
        if (-not $script:State.InstallerType) {
            $script:State.InstallerType = switch ($first.Extension.ToLower()) { '.msi'{'MSI'} '.exe'{'EXE'} '.msp'{'MSP'} default{'Unknown'} }
        }
        $isLoose = [bool]$script:State.LooseFiles
        $isMulti = (-not $isLoose) -and ($ins.Count -gt 1)
        $type = if ($isLoose) { 'LooseFiles' } elseif ($isMulti) { 'Multiple' } else { $script:State.InstallerType }
        $script:State.InstallerType = $type
        $TxtType.Text = $type
        $isMsi = (-not $isLoose) -and (-not $isMulti) -and ($type -eq 'MSI')
        if ($isMsi) {
            if (-not $script:State.ProductCode) {
                $pc = Get-MsiProductCode -MsiPath $first.FullName
                if ($pc) { $script:State.ProductCode = $pc; Write-Log "Auto ProductCode: $pc" Success }
                else     { Write-Log "ProductCode not read (run on Windows with the real MSI)" Warning }
            }
            $TxtPC.Text = [string]$script:State.ProductCode; $TxtPC.IsEnabled = $true
        } else {
            $TxtPC.Text='(not an MSI)'; $TxtPC.IsEnabled=$false; $script:State.ProductCode=''
        }
        # F27/F29: the Generate-MST master toggle is relevant only for an MSI. Sync it and let it gate the option panels.
        if ($ChkGenerateMst) { $ChkGenerateMst.IsChecked = [bool]$script:State.GenerateMst; $ChkGenerateMst.Visibility = if ($isMsi) { 'Visible' } else { 'Collapsed' } }
        $genMst = (-not $isMsi) -or [bool]$script:State.GenerateMst
        # MST cleanup toggles (KEEP = don't remove), PER MSI. The single pair is shown only for a
        # lone MSI; in Multiple mode each MSI row carries its own pair (Build-MultiArgRows). Hidden when not generating an MST.
        $PnlMstFlags.Visibility = if ($isMsi -and $genMst) { 'Visible' } else { 'Collapsed' }
        # Section wrappers follow the same decisions (title + description only make sense with their content).
        if ($SecMsi) { $SecMsi.Visibility = if ($isMsi) { 'Visible' } else { 'Collapsed' } }
        if ($isMsi -and $first) {
            $fl = Get-MsiFlags $first.FullName
            $ChkKeepShortcut.IsChecked = [bool]$fl.KeepShortcut
            $ChkKeepStartup.IsChecked  = [bool]$fl.KeepStartup
            $ChkKeepStray.IsChecked    = [bool]$fl.KeepStray
            $ChkKeepRunKey.IsChecked   = [bool]$fl.KeepRunKey
        }
        # Single-MSI extra-properties box (merged into its MST at assemble time). Hidden when not generating an MST.
        $PnlMsiProps.Visibility = if ($isMsi -and $genMst) { 'Visible' } else { 'Collapsed' }
        if ($isMsi -and $first) {
            if (-not $script:State.MsiProps) { $script:State.MsiProps = @{} }
            $TxtMsiProps.Text = if ($script:State.MsiProps.ContainsKey($first.FullName)) { [string]$script:State.MsiProps[$first.FullName] } else { '' }
        }
        # The old "Match predecessor MST" button is GONE - the predecessor MST is now applied AUTOMATICALLY when the
        # predecessor + MSI are both known (Set-PredecessorMstAuto), and the differences are shown/edited in "View MSI
        # properties". Guard by a predecessor|MSI KEY so it applies ONCE per combo and never clobbers the user's edits
        # on a later UI refresh (re-selecting a predecessor resets the key in Set-PredecessorUi).
        if ($BtnMatchPredMst) { $BtnMatchPredMst.Visibility = 'Collapsed' }
        $canMatch = $isMsi -and $first -and $script:State.PredecessorModel -and $script:State.PredecessorPath
        # the carry-forward switch: shown for an MSI with a predecessor, reflecting the standing choice (Set-PredecessorMstAuto
        # hides it again when the predecessor turns out to have no MSI/MST)
        if ($ChkCarryPredMst) { $ChkCarryPredMst.Visibility = $(if ($canMatch -and ((@($script:State.PredMstProps.Keys).Count -gt 0) -or (@($script:State.MstOtherItems).Count -gt 0))) { 'Visible' } else { 'Collapsed' }); $ChkCarryPredMst.IsChecked = [bool]$script:State.CarryPredMst }
        if ($canMatch -and (Get-Command Set-PredecessorMstAuto -ErrorAction SilentlyContinue)) {
            $mstKey = "$($script:State.PredecessorPath)|$($first.FullName)"
            if ($script:State.PredMstAppliedKey -ne $mstKey) { Set-PredecessorMstAuto; $script:State.PredMstAppliedKey = $mstKey }
        } elseif ($LblMatchMst) { $LblMatchMst.Text = '' }
        # Single-EXE parameter boxes - only for a lone EXE (not multiple, not loose). Blank => TODO.
        $isExe = (-not $isLoose) -and (-not $isMulti) -and ($type -eq 'EXE')
        $LblExeParams.Visibility = if ($isExe) { 'Visible' } else { 'Collapsed' }
        $PnlExeParams.Visibility = if ($isExe) { 'Visible' } else { 'Collapsed' }
        if ($SecExe) { $SecExe.Visibility = if ($isExe) { 'Visible' } else { 'Collapsed' } }
        if ($SecAnalysis) { $SecAnalysis.Visibility = if ((-not $isLoose) -and $ins.Count) { 'Visible' } else { 'Collapsed' } }
        # 'Check bundled MSI' / 'Run & capture MSI' are HIDDEN for now (per request) - the snapshot analyzer covers
        # capture, and Run&capture runs the installer on this machine. Keep the panel/handlers wired for easy re-enable.
        if ($PnlBundled) { $PnlBundled.Visibility = 'Collapsed'; if ($isExe) { $LblBundled.Text = '' } }
        # Snapshot analysis works for ANY real installer (lone EXE/MSI or several) - just not loose-files.
        if ($PnlSnapshot) { $PnlSnapshot.Visibility = if ((-not $isLoose) -and $ins.Count) { 'Visible' } else { 'Collapsed' }; if ($LblSnapshot) { $LblSnapshot.Text = '' } }
        # Per-user config dropdown: available for any real installer (not loose). Restore the saved selection.
        if ($PnlPerUser) {
            $PnlPerUser.Visibility = if ((-not $isLoose) -and $ins.Count) { 'Visible' } else { 'Collapsed' }
            if ($CmbPerUser) { $CmbPerUser.SelectedIndex = switch ("$($script:State.PerUserMode)") { 'AllUsersReg' {1} 'ActiveSetup' {2} default {0} } }
            Update-PerUserHint
        }
        $TxtInstArgs.Text   = [string]$script:State.InstallParams
        $TxtUninstArgs.Text = [string]$script:State.UninstallParams
        # KB ASSIST for a lone EXE: fingerprint the chosen installer + look up what similar packages used.
        Update-KbHint -Show:$isExe -Installer $first
        # Multiple installers - per-installer arg rows (EXE gets boxes, MSI uses its MST).
        $LblMultiArgs.Visibility = if ($isMulti) { 'Visible' } else { 'Collapsed' }
        $PnlMultiArgs.Visibility = if ($isMulti) { 'Visible' } else { 'Collapsed' }
        if ($SecMulti) { $SecMulti.Visibility = if ($isMulti) { 'Visible' } else { 'Collapsed' } }
        $PnlMultiArgs.Children.Clear()
        if ($isMulti) { Build-MultiArgRows -Installers $ins }
        # Loose-files options - shown only when the source is being treated as loose files.
        $PnlLoose.Visibility = if ($isLoose) { 'Visible' } else { 'Collapsed' }
        if ($SecLoose) { $SecLoose.Visibility = $PnlLoose.Visibility }
        $ChkArp.IsChecked          = [bool]$script:State.LooseArp
        $ChkLooseShortcut.IsChecked = [bool]$script:State.LooseShortcut
        $TxtLooseTargets.Text      = [string]$script:State.LooseTargets
    } finally { $script:Rehydrating = $false }
}

# ---------- Step 3 editor (AvalonEdit, embedded) ----------
$script:AeEditor     = $null
$script:Step3Loading = $false   # guard: programmatic editor.Text writes must not dirty $State

$script:PsXshd = @'
<SyntaxDefinition name="PowerShell" xmlns="http://icsharpcode.net/sharpdevelop/syntaxdefinition/2008">
  <Color name="Comment"  foreground="#6A9955"/>
  <Color name="String"   foreground="#CE9178"/>
  <Color name="Keyword"  foreground="#569CD6" fontWeight="bold"/>
  <Color name="Cmdlet"   foreground="#DCDCAA"/>
  <Color name="Variable" foreground="#56C8D6"/>
  <Color name="Number"   foreground="#B5CEA8"/>
  <Color name="Marker"   foreground="#608B4E" fontWeight="bold"/>
  <RuleSet ignoreCase="true">
    <Span color="Comment" multiline="true" begin="&lt;#" end="#&gt;"/>
    <Span color="Marker"  begin="\#\*=+" />
    <Span color="Comment" begin="\#" />
    <Span color="String" multiline="true"> <Begin>"</Begin> <End>"</End> </Span>
    <Span color="String"> <Begin>'</Begin> <End>'</End> </Span>
    <Keywords color="Keyword">
      <Word>if</Word><Word>else</Word><Word>elseif</Word><Word>switch</Word>
      <Word>foreach</Word><Word>for</Word><Word>while</Word><Word>do</Word>
      <Word>function</Word><Word>param</Word><Word>return</Word><Word>break</Word>
      <Word>continue</Word><Word>try</Word><Word>catch</Word><Word>finally</Word>
      <Word>throw</Word><Word>begin</Word><Word>process</Word><Word>end</Word>
    </Keywords>
    <Rule color="Variable">\$[\w:\.]+</Rule>
    <Rule color="Cmdlet">\b[A-Z][a-zA-Z]+\-[A-Z][a-zA-Z0-9]+\b</Rule>
    <Rule color="Number">\b\d+(\.\d+)*\b</Rule>
  </RuleSet>
</SyntaxDefinition>
'@

# Snippet library: a SHARED file (settings.json -> SnippetsPath, on the team share) so everyone reads + writes the
# same set; else the local snippets.json next to the exe. If a shared path is set but missing, seed it from the local
# copy so the first user populates the team library instead of starting empty.
$snipPath = "$(if (Get-Command Get-Setting -EA SilentlyContinue) { Get-Setting 'SnippetsPath' })".Trim()
$localSnip = Join-Path $root 'snippets.json'
if (-not $snipPath) { $snipPath = $localSnip }
elseif (-not (Test-Path $snipPath) -and (Test-Path $localSnip)) {
    try { $dir = Split-Path $snipPath -Parent; if ($dir -and -not (Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
          Copy-Item $localSnip $snipPath -Force; Write-Log "Seeded shared snippet library -> $snipPath" } catch { Write-Log "Could not seed shared snippets ($snipPath): $($_.Exception.Message)" Warning }
}
Initialize-Snippets $snipPath   # single source of truth - no inline snippets

# Fill the snippet ListBox for the selected category + search text (snippet object in .Tag).
function Update-SnippetList {
    if (-not $LstSnippets) { return }
    $LstSnippets.Items.Clear()
    $cat    = if ($CmbSnipCat.SelectedItem) { "$($CmbSnipCat.SelectedItem)" } else { 'All' }
    $search = if ($TxtSnipSearch) { "$($TxtSnipSearch.Text)".Trim() } else { '' }
    foreach ($s in (Get-FilteredSnippets -CategoryName $cat -SearchText $search)) {
        $it = New-Object Windows.Controls.ListBoxItem
        $it.Content = if ($cat -eq 'All') { $s.Label } else { "$($s.Subcategory) / $($s.Name)" }
        $it.Tag = $s; $it.Foreground = 'White'
        [void]$LstSnippets.Items.Add($it)
    }
    if ($TxtSnipPreview) { $TxtSnipPreview.Text = '' }
}
function Show-SnippetPreview {
    if ($TxtSnipPreview -and $LstSnippets.SelectedItem) {
        $TxtSnipPreview.Text = ("$($LstSnippets.SelectedItem.Tag.Code)" -replace "\r?\n", "`r`n")
    }
}
function Insert-SelectedSnippet {
    if (-not $script:AeEditor -or -not $LstSnippets.SelectedItem) { return }
    $code = "$($LstSnippets.SelectedItem.Tag.Code)" -replace "\r?\n", "`r`n"
    $script:AeEditor.Document.Insert($script:AeEditor.CaretOffset, $code + "`r`n")
    $script:AeEditor.TextArea.Focus() | Out-Null
}

# "Add / Edit snippet" dialog - paste code, name it, pick/enter a category, optionally auto-convert v3->v4, and it's
# saved into snippets.json (all escaping handled by Save-Snippet). Pass -Original @{Name;Category;Subcategory;Code}
# to EDIT an existing one (pre-fills the fields; if the identity changes on save, the old entry is removed).
# Returns $true if a snippet was saved.
function Show-AddSnippetDialog {
    param([string]$InitialCode = '', [hashtable]$Original)
    $isEdit = [bool]$Original
    [xml]$x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="620" Height="520" WindowStartupLocation="CenterOwner" Background="#181A1F" Title="Add snippet">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Grid.ColumnDefinitions><ColumnDefinition Width="110"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <TextBlock Grid.Row="0" Grid.Column="0" Text="Name" Foreground="#E7E9ED" VerticalAlignment="Center" Margin="0,4"/>
    <TextBox   x:Name="TName" Grid.Row="0" Grid.Column="1" Margin="0,4"/>
    <TextBlock Grid.Row="1" Grid.Column="0" Text="Category" Foreground="#E7E9ED" VerticalAlignment="Center" Margin="0,4"/>
    <ComboBox  x:Name="TCat" Grid.Row="1" Grid.Column="1" IsEditable="True" Margin="0,4"/>
    <TextBlock Grid.Row="2" Grid.Column="0" Text="Subcategory" Foreground="#E7E9ED" VerticalAlignment="Center" Margin="0,4"/>
    <TextBox   x:Name="TSub" Grid.Row="2" Grid.Column="1" Text="General" Margin="0,4"/>
    <CheckBox  x:Name="TConv" Grid.Row="3" Grid.Column="1" Content="Convert PSADT v3 -&gt; v4 on save (cmdlet renames - review the result)" Foreground="#E7E9ED" Margin="0,6" IsChecked="True"/>
    <TextBlock Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="2" Text="Code (paste your script):" Foreground="#56C8D6" Margin="0,6,0,2"/>
    <TextBox   x:Name="TCode" Grid.Row="5" Grid.Column="0" Grid.ColumnSpan="2" AcceptsReturn="True" AcceptsTab="True"
               VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" FontFamily="Cascadia Mono, Consolas"
               Background="#21242B" Foreground="#E7E9ED" Margin="0,0,0,8"/>
    <StackPanel Grid.Row="6" Grid.Column="0" Grid.ColumnSpan="2" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="BOk" Content="Save" Padding="16,5" Margin="0,0,8,0" IsDefault="True"/>
      <Button x:Name="BCancel" Content="Cancel" Padding="16,5" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
    if (Get-Command Apply-PbTheme -EA SilentlyContinue) { Apply-PbTheme $w }
    try { $w.Owner = $script:Win } catch {}
    $tName=$w.FindName('TName'); $tCat=$w.FindName('TCat'); $tSub=$w.FindName('TSub'); $tConv=$w.FindName('TConv'); $tCode=$w.FindName('TCode')
    foreach ($c in (Get-SnippetCategoryNames | Where-Object { $_ -ne 'All' })) { [void]$tCat.Items.Add($c) }
    if ($isEdit) {
        $w.Title = 'Edit snippet'
        $tName.Text = "$($Original.Name)"; $tCat.Text = "$($Original.Category)"
        $tSub.Text = "$($Original.Subcategory)"; $tCode.Text = "$($Original.Code)"
        $tConv.IsChecked = $false   # editing an existing (already-v4) snippet - don't auto-convert by default
    } else { $tCode.Text = "$InitialCode" }
    $w.FindName('BOk').add_Click({
        if (-not "$($tName.Text)".Trim()) { [Windows.MessageBox]::Show('Enter a name.','Snippet') | Out-Null; return }
        if (-not "$($tCat.Text)".Trim())  { [Windows.MessageBox]::Show('Enter or pick a category.','Snippet') | Out-Null; return }
        if (-not "$($tCode.Text)".Trim()) { [Windows.MessageBox]::Show('Paste the snippet code.','Snippet') | Out-Null; return }
        $w.DialogResult = $true
    }.GetNewClosure())
    Set-PBDialogChrome -Window $w -Glyph 'E8F1' -PrimaryName 'BOk'
    if ($w.ShowDialog() -ne $true) { return $false }
    $code = "$($tCode.Text)"
    if ($tConv.IsChecked -and (Get-Command Convert-V3ToV4Snippet -EA SilentlyContinue)) { $code = Convert-V3ToV4Snippet $code }
    $newName = "$($tName.Text)".Trim(); $newCat = "$($tCat.Text)".Trim()
    $newSub  = if ("$($tSub.Text)".Trim()) { "$($tSub.Text)".Trim() } else { 'General' }
    $saved = [bool](Save-Snippet -Name $newName -Category $newCat -Subcategory $newSub -Code $code)
    # On EDIT, if the name/category/subcategory changed, drop the OLD entry (scoped precisely so we never delete the
    # one we just saved). Save-then-remove order means a failed save leaves the original intact.
    if ($saved -and $isEdit) {
        $idChanged = ("$($Original.Name)" -ne $newName) -or ("$($Original.Category)" -ne $newCat) -or ("$($Original.Subcategory)" -ne $newSub)
        if ($idChanged) { Remove-Snippet -Name "$($Original.Name)" -Category "$($Original.Category)" -Subcategory "$($Original.Subcategory)" | Out-Null }
    }
    return $saved
}

function Initialize-Editor {
    if (-not $script:HasEditor) {
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = "AvalonEdit not loaded - put ICSharpCode.AvalonEdit.dll in Lib\ next to GUI.ps1. The rest of the wizard works without it."
        $tb.Foreground = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xF4,0x87,0x71)))
        $tb.TextWrapping = 'Wrap'; $tb.Margin = '16'
        $EditorHost.Child = $tb
        return
    }
    $ed = New-Object ICSharpCode.AvalonEdit.TextEditor
    $ed.FontFamily = New-Object Windows.Media.FontFamily 'Cascadia Mono, Consolas'
    $ed.FontSize = 13; $ed.ShowLineNumbers = $true; $ed.WordWrap = $false
    $ed.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x1E,0x1E,0x1E))
    $ed.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xD4,0xD4,0xD4))
    $ed.Options.ConvertTabsToSpaces  = $true
    $ed.Options.IndentationSize      = 4
    $ed.Options.HighlightCurrentLine = $true
    try {
        $sr  = New-Object System.IO.StringReader $script:PsXshd
        $xr  = [System.Xml.XmlReader]::Create($sr)
        $ed.SyntaxHighlighting = [ICSharpCode.AvalonEdit.Highlighting.Xshd.HighlightingLoader]::Load(
                                    $xr, [ICSharpCode.AvalonEdit.Highlighting.HighlightingManager]::Instance)
    } catch {}
    [ICSharpCode.AvalonEdit.Search.SearchPanel]::Install($ed) | Out-Null
    $ed.add_TextChanged({
        if ($script:Step3Loading) { return }
        $script:State.ScriptText = $script:AeEditor.Text
    })
    $EditorHost.Child = $ed
    $script:AeEditor = $ed
}

function Update-Anchors {
    if (-not $script:AeEditor) { return }
    $LstAnchors.Items.Clear()
    $doc = $script:AeEditor.Document
    for ($n = 1; $n -le $doc.LineCount; $n++) {
        $ln = $doc.GetLineByNumber($n); $text = $doc.GetText($ln.Offset, $ln.Length)
        $label = $null
        if     ($text -match '#\*=+\s*([A-Z\- ]+?)\s+BEGIN') { $label = $Matches[1].Trim() }
        elseif ($text -match '^\s*function\s+([\w\-]+)')      { $label = "fn: $($Matches[1])" }
        if ($label) {
            $item = New-Object Windows.Controls.ListBoxItem
            $item.Content = $label; $item.Tag = $n; $item.Foreground = 'White'
            [void]$LstAnchors.Items.Add($item)
        }
    }
}

# STRUCTURAL safety net: parse the generated script with the real PowerShell parser. Any
# corruption (unbalanced braces, broken blocks - like the v3 nested-scriptblock bug) shows up
# as parse errors HERE, before a broken package is ever built. Returns $null when clean.
function Test-ScriptStructure {
    param([string]$Text)
    if (-not $Text) { return $null }
    $tok = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tok, [ref]$errs)
    if ($errs -and $errs.Count) {
        $f = $errs[0]
        return "script has $($errs.Count) parse error(s) - first at line $($f.Extent.StartLineNumber): $($f.Message)"
    }
    return $null
}

function Get-SourceWarning {
    # Warn when the NEW source differs from the predecessor (type or installer filename),
    # so a changed installer never silently keeps the predecessor's command/filename.
    $m   = $script:State.PredecessorModel
    $ins = @($script:State.ChosenInstallers)
    # Unsupported installer type guard (works with or without a predecessor): only MSI and EXE
    # have standard command sets - an .msp/.iso would silently get an EXE-style command line.
    if ($ins.Count -gt 0 -and -not $script:State.LooseFiles) {
        $bad = @($ins | Where-Object { $_.Extension.ToLower() -notin '.msi','.exe' })
        if ($bad.Count) { return "No standard command set for $((($bad | ForEach-Object { $_.Extension }) | Select-Object -Unique) -join ', ') ($((($bad | ForEach-Object { $_.Name })) -join ', ')) - author the install/uninstall commands manually in this script." }
    }
    if (-not $m -or $ins.Count -eq 0) { return '' }
    # Predecessor reuse KEEPS the predecessor's install/uninstall commands and only SWAPS the version, the installer
    # FILENAME, and the MSI ProductCode (same-type single installer). When your source has a different STRUCTURE
    # (loose files / several installers) or a different TYPE, the swap can't apply, so the predecessor's commands are
    # carried as-is. Tell the user plainly: predecessor had X, you have Y, and how to make it match automatically.
    $predType = "$($m.Installer.Type)"
    $predName = if ($m.Installer.MsiFileName) { "$($m.Installer.MsiFileName)" } elseif ($m.Installer.ExeFileName) { "$($m.Installer.ExeFileName)" } else { '' }
    $predDesc = if ($predName) { "$predType '$predName'" } else { "$predType" }
    $predCount = if ($m.InstallCount) { [int]$m.InstallCount } else { 1 }
    # MULTI-COMPONENT predecessor: the swap retargets only the PRIMARY installer, so every command needs a look.
    if ($predCount -gt 1) {
        return "Predecessor is a MULTI-COMPONENT package - it installs $predCount component(s) and uninstalls $(@($m.UninstallSeq).Count) (use 'View predecessor install / uninstall...'). Predecessor reuse keeps the whole sequence and swaps the PRIMARY installer/ProductCode only; your source has $($ins.Count) installer(s). Verify EACH install/uninstall command in the editor matches your new source (filenames, ProductCodes, order)."
    }
    if ($script:State.LooseFiles) {
        return "Source STRUCTURE differs from the predecessor - predecessor was $predDesc, your source is LOOSE FILES. Predecessor reuse KEEPS the predecessor's commands (with the version + ProductCode swaps); it does not auto-wire loose files. To stay automatic, supply the same single $predType installer as the predecessor; otherwise edit the install/uninstall commands here (or build FRESH without a predecessor to use loose-files mode)."
    }
    if ($ins.Count -gt 1) {
        $names = ($ins | ForEach-Object { $_.Name }) -join ', '
        return "Source STRUCTURE differs - predecessor was a single $predDesc, your source is $($ins.Count) installers ($names). Predecessor reuse KEEPS the predecessor's single command (swapped) - it does NOT chain the new installers. To stay automatic, use ONE $predType installer matching the predecessor; otherwise edit the commands here (or build FRESH without a predecessor to install them in order)."
    }
    $newType = switch ($ins[0].Extension.ToLower()) { '.msi'{'MSI'} '.exe'{'EXE'} '.msp'{'MSP'} default{'?'} }
    if ($predType -and $predType -ne 'Unknown' -and $newType -ne $predType) {
        return "Source TYPE changed - predecessor was $predDesc, your source is a $newType ('$($ins[0].Name)'). Predecessor reuse KEEPS the predecessor's $predType commands (there is no cross-type swap). To stay automatic, provide a $predType source like the predecessor; otherwise edit the install/uninstall commands here to match the new installer."
    }
    if ($predName) {
        # Same type + single installer: FUZZY filename check (after version-bumping the predecessor name) so a pure
        # version change never warns. The swap retargets the predecessor's command to your filename either way.
        $predVer = "$($m.Identity.Version)"; $newVer = "$($script:State.Parsed.Version)"
        $predBumped = if ($predVer -and $newVer) { Invoke-VersionSwap -Text $predName -OldVersion $predVer -NewVersion $newVer } else { $predName }
        $a = ($predBumped -replace '[^A-Za-z]','').ToLower()
        $b = ($ins[0].Name -replace '[^A-Za-z]','').ToLower()
        $similar = ($a -eq $b) -or ($a -and $b -and ($a.Contains($b) -or $b.Contains($a)))
        if (-not $similar) { return "Source FILE differs (beyond a version change) - predecessor '$predBumped' vs your '$($ins[0].Name)'. The predecessor's command was swapped onto your filename; verify the install/uninstall command + switches still fit this installer." }
    }
    return ''
}

function Build-Step3Script {
    # Assemble the script from current inputs onto the real blank v4 template
    # (predecessor fills the session block + authored code; fresh-fill when no predecessor).
    if (Get-Command Reset-GpfNotices -EA SilentlyContinue) { Reset-GpfNotices }   # fresh heads-up notices for this build
    $p = $script:State.Parsed
    if (-not $p -or -not $p.IsValid) { return "# Enter a valid package name in Step 1 first (Vendor_App_Arch_Version-Release_Lang)." }
    $author = Get-AuthorName
    $newPkg = @{
        Vendor=$p.Vendor; AppName=$p.AppName; Arch=$p.Arch; Lang=$p.Lang
        Revision=$p.Release; Version=$p.Version; FullName=$p.FullName
        ProductCode=$script:State.ProductCode; Ritm=$script:State.Ritm; Author=$author
        TargetBrand=$script:State.TargetBrand   # Step-1 brand dropdown (INA=Audi / VWG=Group / G1V=VW) - drives brand rules
    }
    $ins = @($script:State.ChosenInstallers)
    # FreeSpace = max(installer payload, measured installed footprint from the snapshot, 150 MB floor). The snapshot
    # footprint matters when a small installer expands to GBs on disk; 0 when no snapshot ran, so it never lowers the value.
    if (@($script:State.ZipInstallers).Count -and "$($script:State.ZipPayload)".Trim() -and (Test-Path -LiteralPath "$($script:State.ZipPayload)")) {
        # ZIP PAYLOAD: size from the .zip itself (it's Expand-ZipFile'd at install) - the pseudo "installer" paths inside
        # the zip aren't on disk. Rough x3 for compressed->extracted+installed, floored at 300 MB.
        $zmb = [math]::Round((Get-Item -LiteralPath "$($script:State.ZipPayload)").Length/1MB)
        $newPkg.FreeSpace = [Math]::Max(300, $zmb * 3)
    }
    elseif ($ins.Count -gt 0) { $newPkg.FreeSpace = Get-PayloadSizeMB -ChosenInstallers $ins -InstalledMB ([int]$script:State.SnapshotInstalledMB) }   # required disk space (MB) from payload
    # Install-command paths are the installer's location relative to the copied payload root,
    # so an MSI/EXE in a subfolder keeps that subfolder under $adtSession.DirFiles. Manual mode
    # copies flat, so paths are just file names. (MST defaults to <relpath>.mst in the builder.)
    $payloadRoot = if ($script:State.Resolved -and -not $script:State.Resolved.Manual) { $script:State.Resolved.PayloadRoot } else { $null }
    if (@($script:State.ZipInstallers).Count -and "$($script:State.ZipPayload)".Trim()) {
        # GPF ZIP PAYLOAD: the source is a single .zip kept VERBATIM in Files\; Expand-ZipFile it at install to
        # $envTemp\<App>_<Ver> and run the installer(s) the packager selected from inside it.
        $newPkg.InstallerMode = 'ZipPayload'
        $newPkg.ZipName      = [IO.Path]::GetFileName("$($script:State.ZipPayload)")
        $newPkg.ZipRunItems  = @($script:State.ZipInstallers | ForEach-Object { @{ RelPath = $_.RelPath; Extension = $_.Extension; Name = $_.Name } })
    }
    elseif ($script:State.LooseFiles) {
        # User chose loose files: script copies the payload (+ optional shortcut(s)/ARP).
        $newPkg.InstallerMode = 'LooseFiles'
        $newPkg.CreateArp = [bool]$script:State.LooseArp
        # F25/F34 (GPF): a zipped source is kept FLAT under its OWN name (mirrors the incoming Files\), and the ps1's
        # Expand-ZipFile extracts THAT file - not a tool-renamed <PackageName>.zip. Only when the payload is a single .zip.
        if ((Test-PBGpfFamily) -and @($ins).Count -eq 1 -and "$($ins[0].Extension)" -match '(?i)^\.zip$') {
            $newPkg.ZipName = $ins[0].Name
        }
        if ($script:State.LooseShortcut -and $script:State.LooseTargets) {
            $newPkg.Shortcuts = @(($script:State.LooseTargets -split ',') |
                ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { @{ Target = $_ } })
        }
    } elseif ($ins.Count -gt 1) {
        # Multiple installers: ordered install / reverse uninstall.
        $newPkg.InstallerMode = 'Multiple'
        $newPkg.Installers = @($ins | ForEach-Object {
            $rel = Get-RelativePath -Base $payloadRoot -Full $_.FullName
            $rel = $rel -replace '(?i)^Files\\', ''   # nested Files\Files payloads are hoisted at assembly - the command must match
            if ($_.Extension.ToLower() -eq '.msi') {
                $mit = @{ Type='MSI'; MsiFileName=$rel; ProductCode=(Get-MsiProductCode $_.FullName) }
                # F27/F29: honour the Generate-MST choice per MSI too (reuse a source MST, else plain).
                if (-not $script:State.GenerateMst) {
                    $sm = if (Get-Command Find-VendorMst -EA SilentlyContinue) { Find-VendorMst $_.FullName } else { $null }
                    if ($sm) { $sub = Split-Path $rel -Parent; $ml = [IO.Path]::GetFileName($sm); $mit.MstFileName = if ($sub) { Join-Path $sub $ml } else { $ml } }
                    else { $mit.NoMst = $true }
                }
                $mit
            } else {
                $a = $script:State.InstallerArgs[$_.FullName]
                @{ Type='EXE'; ExeFileName=$rel; InstallParams=$(if($a){$a.Install}else{''}); UninstallParams=$(if($a){$a.Uninstall}else{''}) }
            }
        })
    } elseif ($ins.Count -eq 1) {
        $rel = Get-RelativePath -Base $payloadRoot -Full $ins[0].FullName
        $rel = $rel -replace '(?i)^Files\\', ''   # nested Files\Files payloads are hoisted at assembly - the command must match
        switch ($ins[0].Extension.ToLower()) {
            '.msi' {
                $newPkg.MsiFileName = $rel
                # F27/F29: MST generation is a user choice. Generate ON (default) -> the builder builds <msi>.mst.
                # Generate OFF -> if the SOURCE already ships an MST, reuse it as-is (it's copied flat next to the MSI);
                # otherwise install the MSI PLAIN (no transform).
                $newPkg.GenerateMst = [bool]$script:State.GenerateMst
                if (-not $script:State.GenerateMst) {
                    $srcMst = if (Get-Command Find-VendorMst -EA SilentlyContinue) { Find-VendorMst $ins[0].FullName } else { $null }
                    if ($srcMst) {
                        $sub = Split-Path $rel -Parent
                        $mstLeaf = [IO.Path]::GetFileName($srcMst)
                        $newPkg.MstFileName = if ($sub) { Join-Path $sub $mstLeaf } else { $mstLeaf }
                    } else { $newPkg.NoMst = $true }
                }
            }
            '.exe' { $newPkg.ExeFileName = $rel; $newPkg.InstallParams = $script:State.InstallParams; $newPkg.UninstallParams = $script:State.UninstallParams
                     $newPkg.UninstallCommand = "$($script:State.SnapshotUninstall)" }   # snapshot-captured full uninstall -> written into the ps1
            '.zip' {
                # GPF zip source (F25/F34): the source IS a single .zip - keep it VERBATIM in Files\ and Expand-ZipFile it
                # at install to $envTemp\<App>_<Version>. Route through LooseFiles so New-PayloadZip copies the zip as-is
                # (not extracted) and Get-LooseFilesCommandSet emits the Expand-ZipFile line. The packager fills the actual
                # install command for the extracted payload (surfaced as a review item below).
                $newPkg.InstallerMode = 'LooseFiles'
                $newPkg.ZipName   = $ins[0].Name
                $newPkg.CreateArp = [bool]$script:State.LooseArp
            }
        }
    }
    # Snapshot cleanups / exclusions -> the ps1. MOST go to POST-INSTALLATION (remove desktop/uninstall shortcut,
    # Run key, disable auto-update, custom excludes). Items TAGGED '# [post-uninstall]' (certificate / driver removal)
    # go to POST-UNINSTALLATION instead - removing a cert/driver at install time would break the app; they're cleaned
    # up only when the package is removed.
    if (@($script:State.SnapshotCleanupCommands).Count) {
        $allClean = @($script:State.SnapshotCleanupCommands)
        $unInst   = @($allClean | Where-Object { $_ -match '(?i)#\s*\[post-uninstall\]' })
        $inst     = @($allClean | Where-Object { $_ -notmatch '(?i)#\s*\[post-uninstall\]' })
        if ($inst.Count)   { $newPkg.PostInstallExtra   = ($inst   -join "`r`n") }
        if ($unInst.Count) { $newPkg.PostUninstallExtra = ($unInst -join "`r`n") }
    }
    # PER-USER CONFIG (user-selected, FRESH builds only): auto-generate the correct PSADT v4 code so the packager
    # doesn't hand-write it. All-users registry -> POST-INSTALL only; Active Setup -> POST-INSTALL (stage+register) +
    # POST-UNINSTALL (purge), and New-Package writes the plain-PowerShell stub into SupportFiles. APPENDS to snapshot
    # cleanups. PREDECESSOR reuse is left untouched (it carries the old code); add per-user code there via snippets.
    $puMode = "$($script:State.PerUserMode)"
    if ($script:State.PredecessorModel) { $puMode = 'None' }
    if ($puMode -and $puMode -ne 'None' -and (Get-Command Get-PerUserConfig -EA SilentlyContinue)) {
        $newPkg.PerUserMode = $puMode
        $pu = Get-PerUserConfig -Mode $puMode -Vendor $p.Vendor -App $p.AppName -Version $p.Version -HkcuItems @($script:State.SnapshotHkcu)
        if ("$($pu.PostInstall)".Trim())   { $newPkg.PostInstallExtra   = (@("$($newPkg.PostInstallExtra)", "$($pu.PostInstall)")   | Where-Object { $_.Trim() }) -join "`r`n`r`n" }
        if ("$($pu.PostUninstall)".Trim()) { $newPkg.PostUninstallExtra = (@("$($newPkg.PostUninstallExtra)", "$($pu.PostUninstall)") | Where-Object { $_.Trim() }) -join "`r`n`r`n" }
        # Per-user FILES (snapshot-detected AppData files) -> Get-ADTUserProfiles copy loop into every profile, regardless
        # of the registry mechanism. New-Package stages the files into SupportFiles. Removed per profile on uninstall.
        if (@($script:State.SnapshotUserFiles).Count -and (Get-Command Get-PerUserFileCopy -EA SilentlyContinue)) {
            $puf = Get-PerUserFileCopy -Files @($script:State.SnapshotUserFiles)
            if ("$($puf.PostInstall)".Trim())   { $newPkg.PostInstallExtra   = (@("$($newPkg.PostInstallExtra)", "$($puf.PostInstall)")   | Where-Object { $_.Trim() }) -join "`r`n`r`n" }
            if ("$($puf.PostUninstall)".Trim()) { $newPkg.PostUninstallExtra = (@("$($newPkg.PostUninstallExtra)", "$($puf.PostUninstall)") | Where-Object { $_.Trim() }) -join "`r`n`r`n" }
        }
    }
    # AUTO DETECTION KEY from the snapshot: single MSI -> its ProductCode; an EXE that wraps an MSI -> the GUID from its
    # snapshot-captured uninstall ('MsiExec /X{GUID}'). FRESH fills $newPkg.SoftIdent (the detection). REUSE keeps it
    # SEPARATELY as SnapshotSoftIdent: the merge refreshes detection only when the predecessor's is missing/simple, so a
    # hand-crafted predecessor detection is never blindly overridden. Stops the 0x87D00324 "installed but not detected" trap.
    if (Get-Command Get-AutoSoftIdent -EA SilentlyContinue) {
        $auto = Get-AutoSoftIdent -ProductCode "$($script:State.ProductCode)" -Version "$($p.Version)" -SnapshotUninstall "$($script:State.SnapshotUninstall)" -DisplayVersion "$($script:State.SnapshotDisplayVersion)"
        if ($auto) {
            if ($script:State.PredecessorModel) {
                # REUSE: only refresh the predecessor's detection from the snapshot when the snapshot resolves to a SINGLE
                # product code. If the new installer is MULTI-COMPONENT (several ProductCodes in the snapshot), a one-code
                # swap would be WRONG - keep the predecessor's own detection (its per-component codes are already correct /
                # were swapped by identity). Count distinct GUIDs the snapshot captured.
                $snapPCs = @([regex]::Matches("$($script:State.SnapshotUninstall)", '(?i)\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}') | ForEach-Object { $_.Value.ToUpperInvariant() } | Select-Object -Unique)
                if (@($snapPCs).Count -le 1) { $newPkg.SnapshotSoftIdent = $auto }
                else { Write-Log "Snapshot shows $(@($snapPCs).Count) product codes (multi-component) - NOT swapping detection from snapshot; keeping the predecessor's values." Warning }
            }
            elseif (-not "$($newPkg.SoftIdent)".Trim()) { $newPkg.SoftIdent = $auto; Write-Log "Auto detection key (SoftIdent) from ProductCode: $auto" }
        }
    }
    # AUTO ProcToClose/ProcToBlock: the app's OWN executables = the Start-Menu shortcut TARGETS the snapshot captured
    # (reliable - they're the app's shortcuts). FRESH sets both. REUSE keeps them as SnapshotProcs and the merge UNIONs
    # any new ones into the predecessor's lists (never replaces them).
    $procs = @(@($script:State.SnapshotShortcuts) | ForEach-Object { "$($_.Target)" } |
               Where-Object { $_ -match '(?i)\.exe$' } | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) } |
               Where-Object { "$_".Trim() } | Select-Object -Unique)
    if ($procs.Count) {
        if ($script:State.PredecessorModel) { $newPkg.SnapshotProcs = $procs }
        else { $newPkg.ProcToClose = $procs; $newPkg.ProcToBlock = $procs; Write-Log "Auto ProcToClose/Block from app shortcuts: $($procs -join ', ')" }
    }
    $tpl   = Get-TemplateScript -Root $root
    $model = $script:State.PredecessorModel
    if (-not $tpl) {
        if ($model -and $model.RawV4Content) { $tpl = $model.RawV4Content }  # interim fallback
        else { return "# Blank template not found (PSADT_Template\ or PSADT_Template.zip) and no predecessor to fall back to." }
    }
    try {
        if ($model) { $script:State.ReusePkg = $newPkg; $built = (Build-PredecessorScript -Model $model -NewPkg $newPkg -Template $tpl -AddUninstallPrevious ([bool]$script:State.AddUninstallPrevious)) }
        else        { $script:State.ReusePkg = $null; $built = (Build-FreshScript -NewPkg $newPkg -Template $tpl) }
        # PROMOTE the few must-see review items into the heads-up popup channel (the review list still shows everything).
        if (Get-Command Add-CriticalNoticesFromScript -EA SilentlyContinue) {
            Add-CriticalNoticesFromScript -ScriptText $built -IsPredecessor ([bool]$model) -NewProductCode "$($newPkg.ProductCode)"
        }
        return $built
    } catch { Write-Log "Step 3 build failed: $($_.Exception.Message)" Error; return "# Build failed: $($_.Exception.Message)" }
}

Initialize-Editor
foreach ($c in (Get-SnippetCategoryNames)) { [void]$CmbSnipCat.Items.Add($c) }
if ($CmbSnipCat.Items.Count -gt 0) { $CmbSnipCat.SelectedIndex = 0 }
Update-SnippetList
$CmbSnipCat.add_SelectionChanged({ Update-SnippetList })
$TxtSnipSearch.add_TextChanged({ Update-SnippetList })
$LstSnippets.add_SelectionChanged({ Show-SnippetPreview })
$LstSnippets.add_MouseDoubleClick({ Insert-SelectedSnippet })
$BtnInsertSnip.add_Click({ Insert-SelectedSnippet })
# Rebuild the category dropdown + list after an add/delete (categories may have appeared/disappeared).
function Refresh-SnippetUi {
    param([string]$SelectCategory)
    if (-not $CmbSnipCat) { return }
    $CmbSnipCat.Items.Clear()
    foreach ($c in (Get-SnippetCategoryNames)) { [void]$CmbSnipCat.Items.Add($c) }
    $idx = 0
    if ($SelectCategory) { $f = [array]::IndexOf(@($CmbSnipCat.Items), $SelectCategory); if ($f -ge 0) { $idx = $f } }
    if ($CmbSnipCat.Items.Count -gt 0) { $CmbSnipCat.SelectedIndex = $idx }
    Update-SnippetList
}
$BtnAddSnip.add_Click({
    if (-not (Get-Command Show-AddSnippetDialog -EA SilentlyContinue)) { return }
    # Pre-fill with the editor's current selection, so this doubles as "save selection as snippet".
    $sel = ''
    try { if ($script:AeEditor -and $script:AeEditor.SelectedText) { $sel = "$($script:AeEditor.SelectedText)" } } catch {}
    if (Show-AddSnippetDialog -InitialCode $sel) { Refresh-SnippetUi }
})
$BtnEditSnip.add_Click({
    if (-not ($LstSnippets.SelectedItem -and $LstSnippets.SelectedItem.Tag)) { [Windows.MessageBox]::Show('Select a snippet to edit.','Edit snippet') | Out-Null; return }
    if (-not (Get-Command Show-AddSnippetDialog -EA SilentlyContinue)) { return }
    $t = $LstSnippets.SelectedItem.Tag
    $orig = @{ Name="$($t.Name)"; Category="$($t.Category)"; Subcategory="$($t.Subcategory)"; Code="$($t.Code)" }
    if (Show-AddSnippetDialog -Original $orig) { Refresh-SnippetUi -SelectCategory "$($t.Category)" }
})
$BtnDelSnip.add_Click({
    if (-not ($LstSnippets.SelectedItem -and $LstSnippets.SelectedItem.Tag)) { [Windows.MessageBox]::Show('Select a snippet to delete.','Delete snippet') | Out-Null; return }
    $nm = "$($LstSnippets.SelectedItem.Tag.Name)"; $cat = "$($LstSnippets.SelectedItem.Tag.Category)"; $sub = "$($LstSnippets.SelectedItem.Tag.Subcategory)"
    if ([Windows.MessageBox]::Show("Delete snippet '$nm' from snippets.json?", 'Delete snippet', 'YesNo', 'Question') -ne 'Yes') { return }
    if (Remove-Snippet -Name $nm -Category $cat -Subcategory $sub) { Refresh-SnippetUi }
})

$LstAnchors.add_SelectionChanged({
    if (-not $script:AeEditor -or -not $LstAnchors.SelectedItem) { return }
    $line = [int]$LstAnchors.SelectedItem.Tag
    $script:AeEditor.ScrollToLine($line)
    $script:AeEditor.CaretOffset = $script:AeEditor.Document.GetLineByNumber($line).Offset
    $script:AeEditor.TextArea.Focus() | Out-Null
})
$BtnRebuild.add_Click({
    # a rebuild needs an identity to build FROM - otherwise the click looks ignored
    if (-not $script:State.Parsed -or -not $script:State.Parsed.IsValid) {
        [Windows.MessageBox]::Show("Nothing to rebuild from yet.

Enter the package name on the Info step (and choose the installer on Configure); the script is then built from those.", 'Nothing to rebuild', 'OK', 'Information') | Out-Null
        return
    }
    Show-PBBusy -Title 'Building script' -Detail $(if ($script:State.PredecessorModel) { 'Reusing the predecessor script: converting, swapping identity, merging the snapshot...' } else { 'Filling the template from the installer, transform and analysis...' })
    try { $script:State.ScriptText = Build-Step3Script } finally { Hide-PBBusy }   # discard manual edits, rebuild from inputs
    Populate-Step3
    Update-ReviewButton
    # Leaving "edit a loaded file" mode - the editor now holds a freshly-built wizard script again.
    $script:LoadedScriptPath = $null
    if ($BtnSaveScript) { $BtnSaveScript.IsEnabled = $false }
    if ($LblScriptHdr) { $LblScriptHdr.Text = 'Invoke-AppDeployToolkit.ps1'; $LblScriptHdr.Foreground = '#56C8D6' }
})
$BtnReview.add_Click({
    # nothing built yet -> say so; an unexplained no-op reads as a broken button
    if (-not "$($script:State.ScriptText)".Trim()) {
        [Windows.MessageBox]::Show("There is nothing to review yet - the script has not been built.

Open the Editor step (it builds the script from the Info and Configure steps), or press 'Rebuild from inputs'.", 'Nothing to review', 'OK', 'Information') | Out-Null
        return
    }
    Show-ReviewPopup
})

# LOAD / SAVE an existing .ps1 directly in the editor - so after testing a package you can tweak its script and save
# WITHOUT opening the file externally. Save is enabled only once a file is Loaded (so we only ever overwrite the file
# the user explicitly opened, never a freshly-built wizard script).
$script:LoadedScriptPath = $null
$BtnLoadScript.add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'PSADT deployment script (Invoke-AppDeployToolkit.ps1;Deploy-Application.ps1)|Invoke-AppDeployToolkit.ps1;Deploy-Application.ps1|PowerShell (*.ps1)|*.ps1|All files (*.*)|*.*'
    $dlg.Title = 'Load a deployment script to edit'
    $og = Get-Setting 'OutputBasePath'; if ($og -and (Test-Path $og)) { $dlg.InitialDirectory = $og }
    if ($dlg.ShowDialog() -ne 'OK') { return }
    try { $content = [IO.File]::ReadAllText($dlg.FileName) }
    catch { [Windows.MessageBox]::Show("Could not read the file:`n$($_.Exception.Message)", 'Load script', 'OK', 'Error') | Out-Null; return }
    $script:State.ScriptText = $content
    if ($script:AeEditor) { $script:Step3Loading = $true; try { $script:AeEditor.Text = $content } finally { $script:Step3Loading = $false } }
    $script:LoadedScriptPath = $dlg.FileName
    $BtnSaveScript.IsEnabled = $true
    $LblScriptHdr.Text = "EDITING loaded file: $($dlg.FileName)"; $LblScriptHdr.Foreground = '#DCDCAA'
    if (Get-Command Update-Anchors -EA SilentlyContinue) { Update-Anchors }
    Write-Log "Loaded external script for editing: $($dlg.FileName)"
})
$BtnSaveScript.add_Click({
    if (-not $script:LoadedScriptPath) { return }
    if (-not (Test-Path (Split-Path $script:LoadedScriptPath -Parent))) { [Windows.MessageBox]::Show('The original folder no longer exists.', 'Save script', 'OK', 'Warning') | Out-Null; return }
    $content = if ($script:AeEditor) { "$($script:AeEditor.Text)" } else { "$($script:State.ScriptText)" }
    $e = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$null, [ref]$e)
    if ($e -and $e.Count) {
        if ([Windows.MessageBox]::Show("The script has $($e.Count) parse error(s). Save anyway?", 'Save script', 'YesNo', 'Warning') -ne 'Yes') { return }
    }
    try {
        [IO.File]::WriteAllText($script:LoadedScriptPath, $content, (New-Object System.Text.UTF8Encoding $true))
        $LblScriptHdr.Text = "SAVED: $($script:LoadedScriptPath)"; $LblScriptHdr.Foreground = '#6A9955'
        Write-Log "Saved edits to $($script:LoadedScriptPath)" Success
    } catch { [Windows.MessageBox]::Show("Could not save:`n$($_.Exception.Message)", 'Save script', 'OK', 'Error') | Out-Null }
})

# ---------- MSI property editor (in-tool Orca replacement) - rebuilt (#3) ----------
# The base MSI is NEVER edited: every change here is captured as an MST, so it is safe by construction and nothing
# is applied unless the row is ticked. Three tabs: Properties (Base | Predecessor MST | Your value | Apply),
# the installer-CheckBox table (now editable), and the Other-tables comparison from the predecessor's MST
# (Registry/Shortcut/RemoveFile/LaunchCondition/Feature/Environment - replicate where safe, review-only otherwise).
# A master switch carries the predecessor MST forward (Off = ignore it entirely). Ctrl+Z / Undo + Reset can revert
# changes even after Apply+close (Reset returns the package to the base MSI). Amber = a predecessor diff; teal = your edit.
if (-not ([System.Management.Automation.PSTypeName]'MsiPropRow').Type) {
    Add-Type -TypeDefinition @'
public class MsiPropRow : System.ComponentModel.INotifyPropertyChanged {
    public event System.ComponentModel.PropertyChangedEventHandler PropertyChanged;
    void Raise(string n){ var h = PropertyChanged; if (h != null) h(this, new System.ComponentModel.PropertyChangedEventArgs(n)); }
    public string Property  { get; set; }
    public string BaseValue { get; set; }   // MSI Property-table value ("" = property not in the base MSI => a NEW property)
    public bool   InMsi     { get; set; }
    public string PredValue { get; set; }    // predecessor MST value ("" = predecessor did not set it)
    public bool   HasPred   { get; set; }    // predecessor MST added or changed this property
    private bool _userEdited;
    public bool UserEdited { get { return _userEdited; } set { _userEdited = value; RaiseC(); } }
    private string _your = "";
    public string YourValue { get { return _your; } set { _your = value; _userEdited = true; Raise("YourValue"); RaiseC(); } }
    private bool _apply;
    public bool Apply { get { return _apply; } set { _apply = value; Raise("Apply"); RaiseC(); } }
    // amber: value carried straight from the predecessor MST (applied, predecessor-driven, not hand-edited)
    public bool IsPredDiff { get { return _apply && HasPred && !_userEdited; } }
    // teal: your own edit (applied and either hand-edited, or a value the predecessor did not set)
    public bool IsYourEdit { get { return _apply && (_userEdited || !HasPred); } }
    public string Change {
        get {
            if (!_apply) { return ""; }
            if (!InMsi)  { return "NEW (not in current MSI)"; }
            if (!string.Equals(_your, BaseValue)) { return "overrides current MSI (was '" + BaseValue + "')"; }
            return "set (same as current MSI)";
        }
    }
    void RaiseC(){ Raise("IsPredDiff"); Raise("IsYourEdit"); Raise("Change"); }
    // quiet setters: change the value WITHOUT flagging a user edit (initialisation / master-toggle / reset / undo)
    public void SetValueQuiet(string v){ _your = v; Raise("YourValue"); RaiseC(); }
    public void SetApplyQuiet(bool v){ _apply = v; Raise("Apply"); RaiseC(); }
    public void SetEditedQuiet(bool v){ _userEdited = v; RaiseC(); }
}
'@
}
# One row of the MSI CheckBox table (Orca "CheckBox" view) - NOW EDITABLE: the property an installer checkbox drives,
# the value it sets (editable), and an Apply tick to push that property into the MST.
if (-not ([System.Management.Automation.PSTypeName]'MsiCheckRow').Type) {
    Add-Type -TypeDefinition @'
public class MsiCheckRow : System.ComponentModel.INotifyPropertyChanged {
    public event System.ComponentModel.PropertyChangedEventHandler PropertyChanged;
    void Raise(string n){ var h = PropertyChanged; if (h != null) h(this, new System.ComponentModel.PropertyChangedEventArgs(n)); }
    public string Property { get; set; }
    private string _val = ""; public string CheckedValue { get { return _val; } set { _val = value; Raise("CheckedValue"); } }
    private bool _apply; public bool Apply { get { return _apply; } set { _apply = value; Raise("Apply"); } }
}
'@
}
# One row of the Other-tables comparison (from the predecessor MST): the safe-to-replicate removals are ticked via
# Replicate (enabled only when CanApply); adds/changes are shown read-only as "review - not applied".
if (-not ([System.Management.Automation.PSTypeName]'MstOtherRow').Type) {
    Add-Type -TypeDefinition @'
public class MstOtherRow : System.ComponentModel.INotifyPropertyChanged {
    public event System.ComponentModel.PropertyChangedEventHandler PropertyChanged;
    void Raise(string n){ var h = PropertyChanged; if (h != null) h(this, new System.ComponentModel.PropertyChangedEventArgs(n)); }
    private bool _rep; public bool Replicate { get { return _rep; } set { _rep = value; Raise("Replicate"); } }
    public bool   CanApply { get; set; }   // false => report-only (add/change) - cannot be transformed, Replicate disabled
    public bool   FromPred { get; set; }   // true => came from the predecessor MST (master switch governs it); false => user-added
    public string Category { get; set; }
    public string Action   { get; set; }   // only 'remove' rows are applied at build
    private string _table = ""; public string Table { get { return _table; } set { _table = value; Raise("Table"); } }
    public string PkCol    { get; set; }   // primary-key column for the table (derived; used by the build to delete-by-PK)
    private string _keys = ""; public string Keys { get { return _keys; } set { _keys = value; Raise("Keys"); } }  // comma/newline-separated
    public string Detail   { get; set; }
}
'@
}
# Show the MSI's Property table + checkbox table + predecessor Other-tables. The user ticks/edits rows; everything is
# captured as an MST (base MSI untouched). Returns @{ Text=<KEY=VALUE lines>; Extras=@(selected OtherItems); Master=<bool> }
# or $null on Cancel.
function Show-MsiPropertiesDialog {
    param(
        [Parameter(Mandatory)][string]$MsiPath,
        [string]$ExistingText,
        [hashtable]$PredecessorProps,
        [object[]]$PredecessorItems = @(),
        [bool]$PredecessorLoaded = $false,
        [string]$MsiName = '',
        [bool]$MasterOn = $true,     # the packager's standing choice (State.CarryPredMst) - the dialog opens with it, never "always on"
        [string[]]$Declined = @()    # "prop:NAME" / "item:LABEL" the packager unticked last time - stay unticked
    )
    $declinedSet = @{}; foreach ($dk in @($Declined)) { if ("$dk".Trim()) { $declinedSet["$dk".Trim()] = $true } }
    $props = @(Get-MsiProperties -MsiPath $MsiPath)
    if (-not $props.Count) { [Windows.MessageBox]::Show("Could not read the Property table of:`n$MsiPath", 'MSI properties') | Out-Null; return $null }
    if (-not $PredecessorProps) { $PredecessorProps = @{} }
    $hasPred = [bool]($PredecessorLoaded -or $PredecessorProps.Count -or @($PredecessorItems).Count)
    $carry = $hasPred -and $MasterOn
    $checks     = @(Get-MsiCheckBoxTable -MsiPath $MsiPath)
    $checkProps = @{}; foreach ($c in $checks) { if ("$($c.Property)".Trim()) { $checkProps["$($c.Property)"] = "$($c.Value)" } }
    $existing   = ConvertTo-MsiPropHashtable -Text $ExistingText

    # ----- Property rows -----
    $rows = New-Object 'System.Collections.ObjectModel.ObservableCollection[MsiPropRow]'
    $seen = @{}
    foreach ($p in $props) {
        $r = New-Object MsiPropRow
        $r.Property = "$($p.Property)"; $r.InMsi = $true; $r.BaseValue = "$($p.Value)"; $seen[$r.Property] = $true
        if ($PredecessorProps.ContainsKey($r.Property)) { $r.HasPred = $true; $r.PredValue = "$($PredecessorProps[$r.Property])" }
        # initial Your value / Apply. A saved value that merely EQUALS the predecessor's is the carry-forward, not a
        # user edit - it follows the master switch (before: it counted as "your edit", so switching the master off
        # and pressing OK left it ticked, and the dialog came back ticked - 20.09.2026). A saved value that DIFFERS
        # from the predecessor's is the user's own and always wins.
        $saved = $(if ($existing.ContainsKey($r.Property)) { "$($existing[$r.Property])" } else { $null })
        if ($null -ne $saved -and -not ($r.HasPred -and $saved -eq $r.PredValue)) { $r.SetValueQuiet($saved); $r.SetApplyQuiet($true); $r.SetEditedQuiet($true) }
        elseif ($r.HasPred -and $carry -and -not $declinedSet.ContainsKey("prop:$($r.Property)")) { $r.SetValueQuiet($r.PredValue); $r.SetApplyQuiet($true); $r.SetEditedQuiet($false) }
        else { $r.SetValueQuiet($r.BaseValue); $r.SetApplyQuiet($false); $r.SetEditedQuiet($false) }
        $rows.Add($r)
    }
    # properties requested by the predecessor MST or the user's saved value but NOT in the MSI Property table (NEW properties)
    foreach ($src in @($PredecessorProps, $existing)) {
        foreach ($k in @($src.Keys)) {
            if ($seen.ContainsKey("$k")) { continue }; $seen["$k"] = $true
            $r = New-Object MsiPropRow; $r.Property = "$k"; $r.InMsi = $false; $r.BaseValue = ''
            if ($PredecessorProps.ContainsKey($k)) { $r.HasPred = $true; $r.PredValue = "$($PredecessorProps[$k])" }
            $saved = $(if ($existing.ContainsKey($k)) { "$($existing[$k])" } else { $null })
            if ($null -ne $saved -and -not ($r.HasPred -and $saved -eq $r.PredValue)) { $r.SetValueQuiet($saved); $r.SetApplyQuiet($true); $r.SetEditedQuiet($true) }
            elseif ($r.HasPred -and $carry -and -not $declinedSet.ContainsKey("prop:$($r.Property)")) { $r.SetValueQuiet($r.PredValue); $r.SetApplyQuiet($true); $r.SetEditedQuiet($false) }
            else { $r.SetValueQuiet($(if ($r.HasPred) { $r.PredValue } else { '' })); $r.SetApplyQuiet($false); $r.SetEditedQuiet($false) }
            $rows.Add($r)
        }
    }
    # ----- CheckBox rows (editable) -----
    $checkRows = New-Object 'System.Collections.ObjectModel.ObservableCollection[MsiCheckRow]'
    foreach ($c in $checks) { $cr = New-Object MsiCheckRow; $cr.Property = "$($c.Property)"; $cr.CheckedValue = "$($c.Value)"; $checkRows.Add($cr) }
    # ----- Other-tables rows (predecessor MST comparison) -----
    $otherRows = New-Object 'System.Collections.ObjectModel.ObservableCollection[MstOtherRow]'
    foreach ($it in @($PredecessorItems)) {
        $orow = New-Object MstOtherRow
        $orow.CanApply = [bool]$it.CanApply; $orow.FromPred = $true
        $orow.Category = "$($it.Category)"; $orow.Action = "$($it.Action)"
        $orow.Table = "$($it.Table)"; $orow.PkCol = "$($it.PkCol)"
        $orow.Keys = (@($it.Keys) -join ', '); $orow.Detail = "$($it.Label)"
        $orow.Replicate = ([bool]$it.CanApply -and $carry -and -not $declinedSet.ContainsKey("item:$("$($it.Label)".Trim())"))   # pre-tick safe removals only while the carry-forward is on and not declined before
        $otherRows.Add($orow)
    }

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:pr="clr-namespace:System.Windows.Controls.Primitives;assembly=PresentationFramework"
        xmlns:sys="clr-namespace:System;assembly=mscorlib"
        Width="900" Height="700" WindowStartupLocation="CenterOwner" Background="#1E1E1E"
        Title="MSI properties">
  <Window.Resources>
    <x:Array x:Key="RemovableTables" Type="{x:Type sys:String}">
      <sys:String>Registry</sys:String>
      <sys:String>Shortcut</sys:String>
      <sys:String>RemoveFile</sys:String>
      <sys:String>LaunchCondition</sys:String>
      <sys:String>Feature</sys:String>
      <sys:String>Environment</sys:String>
    </x:Array>
    <Style x:Key="Dim" TargetType="TextBlock"><Setter Property="Foreground" Value="#9A9A9A"/></Style>
    <Style x:Key="Hdr" TargetType="{x:Type pr:DataGridColumnHeader}">
      <Setter Property="Background" Value="#33373F"/><Setter Property="Foreground" Value="#9CDCFE"/>
      <Setter Property="FontWeight" Value="Bold"/><Setter Property="Padding" Value="8,5"/>
      <Setter Property="BorderBrush" Value="#3F3F46"/><Setter Property="BorderThickness" Value="0,0,1,1"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
    </Style>
    <Style x:Key="Grid" TargetType="DataGrid">
      <Setter Property="AutoGenerateColumns" Value="False"/><Setter Property="CanUserAddRows" Value="False"/>
      <Setter Property="HeadersVisibility" Value="Column"/><Setter Property="Background" Value="#21242B"/>
      <Setter Property="Foreground" Value="#E7E9ED"/><Setter Property="RowBackground" Value="#2A2E36"/>
      <Setter Property="AlternatingRowBackground" Value="#21242B"/><Setter Property="BorderBrush" Value="#3F3F46"/>
      <Setter Property="HorizontalGridLinesBrush" Value="#3F3F46"/><Setter Property="FontFamily" Value="Consolas"/>
      <Setter Property="FontSize" Value="12"/><Setter Property="GridLinesVisibility" Value="Horizontal"/>
      <Setter Property="ColumnHeaderStyle" Value="{StaticResource Hdr}"/>
    </Style>
    <Style x:Key="EditBox" TargetType="TextBox"><Setter Property="Background" Value="#1E1E1E"/><Setter Property="Foreground" Value="White"/></Style>
  </Window.Resources>
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,6">
      <CheckBox x:Name="ChkMaster" Foreground="#E7E9ED" VerticalAlignment="Center"
                Content="Carry forward predecessor MST changes"/>
      <TextBlock x:Name="LblMasterHint" Foreground="#A0A8B4" FontSize="11" Margin="12,0,0,0" VerticalAlignment="Center"/>
    </StackPanel>
    <TextBlock Grid.Row="1" TextWrapping="Wrap" Foreground="#9CDCFE" FontSize="11" Margin="0,0,0,8"
               Text="Everything here is read from the CURRENT MSI. Only YOUR VALUE is written (as an MST - the MSI itself is never edited); the Current MSI and Predecessor MST columns are read-only reference. When a predecessor value is carried, Your value starts equal to it - edit to override, untick to skip. Amber = carried from the predecessor MST; teal = your own edit. Standard ALLUSERS=1 / REBOOT=ReallySuppress are added at build."/>

    <TabControl Grid.Row="2" Background="#21242B" BorderBrush="#3F3F46">
      <TabItem Header="Properties">
        <Grid Margin="0,6,0,0">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <TextBox x:Name="TxtFilter" Grid.Row="0" Height="24" FontFamily="Consolas" Margin="0,0,0,6"
                   Background="#1E1E1E" Foreground="#E7E9ED" BorderBrush="#3F3F46"/>
          <DataGrid x:Name="GridProps" Grid.Row="1" Style="{StaticResource Grid}">
            <DataGrid.RowStyle>
              <Style TargetType="DataGridRow">
                <Style.Triggers>
                  <DataTrigger Binding="{Binding IsPredDiff}" Value="True">
                    <Setter Property="Background" Value="#4A3C1E"/><Setter Property="Foreground" Value="#FFE7A6"/>
                  </DataTrigger>
                  <DataTrigger Binding="{Binding IsYourEdit}" Value="True">
                    <Setter Property="Background" Value="#123A40"/><Setter Property="Foreground" Value="#7FE3D0"/>
                  </DataTrigger>
                </Style.Triggers>
              </Style>
            </DataGrid.RowStyle>
            <DataGrid.Columns>
              <DataGridCheckBoxColumn Header="Apply" Binding="{Binding Apply, UpdateSourceTrigger=PropertyChanged}" Width="46"/>
              <DataGridTextColumn Header="Property" Binding="{Binding Property}" Width="180" EditingElementStyle="{StaticResource EditBox}"/>
              <DataGridTextColumn Header="Current MSI (ref)" Binding="{Binding BaseValue}" Width="150" IsReadOnly="True" ElementStyle="{StaticResource Dim}"/>
              <DataGridTextColumn Header="Predecessor MST (ref)" Binding="{Binding PredValue}" Width="150" IsReadOnly="True" ElementStyle="{StaticResource Dim}"/>
              <DataGridTextColumn Header="Your value -> MST" Binding="{Binding YourValue}" Width="170" EditingElementStyle="{StaticResource EditBox}"/>
              <DataGridTextColumn Header="Change" Binding="{Binding Change}" Width="150" IsReadOnly="True"/>
            </DataGrid.Columns>
          </DataGrid>
        </Grid>
      </TabItem>
      <TabItem Header="Installer checkboxes">
        <Grid Margin="0,6,0,0">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <TextBlock x:Name="LblChk" Grid.Row="0" Foreground="#DCDCAA" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,6"
                     Text="Installer checkboxes from the CURRENT MSI only (the predecessor MSI is never mixed in here). Edit a value and tick Apply to set that property in the MST."/>
          <DataGrid x:Name="GridChecks" Grid.Row="1" Style="{StaticResource Grid}">
            <DataGrid.Columns>
              <DataGridCheckBoxColumn Header="Apply" Binding="{Binding Apply, UpdateSourceTrigger=PropertyChanged}" Width="46"/>
              <DataGridTextColumn Header="Property" Binding="{Binding Property}" Width="260" IsReadOnly="True"/>
              <DataGridTextColumn Header="Checked value" Binding="{Binding CheckedValue}" Width="300" EditingElementStyle="{StaticResource EditBox}"/>
            </DataGrid.Columns>
          </DataGrid>
        </Grid>
      </TabItem>
      <TabItem Header="Other tables (editable)">
        <Grid Margin="0,6,0,0">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <TextBlock x:Name="LblOther" Grid.Row="0" Foreground="#DCDCAA" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,4"/>
          <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,6">
            <Button x:Name="BtnOtherAdd" Content="Add removal" Padding="10,3" Margin="0,0,8,0"/>
            <Button x:Name="BtnOtherDel" Content="Delete selected" Padding="10,3" Margin="0,0,8,0"/>
            <TextBlock Foreground="#E0A030" FontSize="11" TextWrapping="Wrap" VerticalAlignment="Center"
                       Text="Only REMOVALS transform safely (delete-by-key; a no-op if the key is absent). Add/change rows are review-only and are NOT applied - make those in the source. Remove only keys you are sure the current MSI does not need."/>
          </StackPanel>
          <DataGrid x:Name="GridOther" Grid.Row="2" Style="{StaticResource Grid}">
            <DataGrid.Columns>
              <DataGridCheckBoxColumn Header="Replicate" Binding="{Binding Replicate, UpdateSourceTrigger=PropertyChanged}" Width="70">
                <DataGridCheckBoxColumn.ElementStyle>
                  <Style TargetType="CheckBox"><Setter Property="IsEnabled" Value="{Binding CanApply}"/><Setter Property="HorizontalAlignment" Value="Center"/></Style>
                </DataGridCheckBoxColumn.ElementStyle>
                <DataGridCheckBoxColumn.EditingElementStyle>
                  <Style TargetType="CheckBox"><Setter Property="IsEnabled" Value="{Binding CanApply}"/></Style>
                </DataGridCheckBoxColumn.EditingElementStyle>
              </DataGridCheckBoxColumn>
              <DataGridComboBoxColumn Header="Table" SelectedItemBinding="{Binding Table}" ItemsSource="{StaticResource RemovableTables}" Width="120"/>
              <DataGridTextColumn Header="Key(s) - comma separated" Binding="{Binding Keys}" Width="220" EditingElementStyle="{StaticResource EditBox}">
                <DataGridTextColumn.ElementStyle>
                  <Style TargetType="TextBlock"><Setter Property="TextWrapping" Value="Wrap"/></Style>
                </DataGridTextColumn.ElementStyle>
              </DataGridTextColumn>
              <DataGridTextColumn Header="Action" Binding="{Binding Action}" Width="80" IsReadOnly="True"/>
              <DataGridTextColumn Header="What / note" Binding="{Binding Detail}" Width="*" IsReadOnly="True">
                <DataGridTextColumn.ElementStyle>
                  <Style TargetType="TextBlock"><Setter Property="TextWrapping" Value="Wrap"/></Style>
                </DataGridTextColumn.ElementStyle>
              </DataGridTextColumn>
            </DataGrid.Columns>
          </DataGrid>
        </Grid>
      </TabItem>
    </TabControl>

    <Border Grid.Row="3" Background="#181A1F" BorderBrush="#3F3F46" BorderThickness="1" Margin="0,8,0,0" Padding="8" CornerRadius="2">
      <StackPanel>
        <TextBlock Text="Change summary - exactly what this MST will do:" Foreground="#6A9955" FontWeight="Bold" FontSize="11" Margin="0,0,0,4"/>
        <ScrollViewer MaxHeight="96" VerticalScrollBarVisibility="Auto">
          <TextBlock x:Name="TxtSummary" Foreground="#C8C8C8" FontFamily="Consolas" FontSize="11" TextWrapping="Wrap"/>
        </ScrollViewer>
      </StackPanel>
    </Border>

    <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnAdd" Content="Add property" Padding="10,4" Margin="0,0,8,0"/>
      <Button x:Name="BtnDel" Content="Delete selected" Padding="10,4" Margin="0,0,8,0"/>
      <Button x:Name="BtnUndo" Content="Undo (Ctrl+Z)" Padding="10,4" Margin="0,0,8,0"/>
      <Button x:Name="BtnReset" Content="Reset to base MSI" Padding="10,4" Margin="0,0,16,0"/>
      <Button x:Name="BtnOk" Content="OK" Padding="16,4" Margin="0,0,8,0" IsDefault="True"/>
      <Button x:Name="BtnCancel" Content="Cancel" Padding="12,4" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@

    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $w }
    $w.Title = "MSI properties - $(if ($MsiName) { $MsiName } else { Split-Path $MsiPath -Leaf })"
    try { $w.Owner = $script:Win } catch {}

    $ChkMaster = $w.FindName('ChkMaster'); $LblMasterHint = $w.FindName('LblMasterHint')
    $GridProps = $w.FindName('GridProps'); $TxtFilter = $w.FindName('TxtFilter')
    $GridChecks = $w.FindName('GridChecks'); $GridOther = $w.FindName('GridOther')
    $LblChk = $w.FindName('LblChk'); $LblOther = $w.FindName('LblOther'); $TxtSummary = $w.FindName('TxtSummary')
    $BtnAdd = $w.FindName('BtnAdd'); $BtnDel = $w.FindName('BtnDel'); $BtnUndo = $w.FindName('BtnUndo'); $BtnReset = $w.FindName('BtnReset')
    $BtnOtherAdd = $w.FindName('BtnOtherAdd'); $BtnOtherDel = $w.FindName('BtnOtherDel')
    $BtnOk = $w.FindName('BtnOk'); $BtnCancel = $w.FindName('BtnCancel')

    $GridProps.ItemsSource = $rows
    $GridChecks.ItemsSource = $checkRows
    $GridOther.ItemsSource = $otherRows

    if (@($PredecessorItems).Count) {
        $LblOther.Text = "$(@($PredecessorItems).Count) change(s) the predecessor MST made to other MSI tables - edit the Table/Key(s), tick Replicate, or Add/Delete your own removals below."
    } else {
        $LblOther.Text = 'No predecessor MST loaded. You can still Add your own removals (Table + Key) below.'
    }

    # ----- shared dialog state (single captured hashtable; per PS/WPF closure-scope rule) -----
    $ui = @{ Init = $true; Undo_Stack = (New-Object 'System.Collections.Generic.Stack[object]') }

    $ui.UpdateSummary = {
        $lines = New-Object System.Collections.Generic.List[string]
        if ($hasPred) { $lines.Add("Predecessor MST carry-forward: $(if ($ChkMaster.IsChecked) { 'ON' } else { 'OFF (predecessor changes ignored)' })") | Out-Null }
        foreach ($r in $rows) {
            if (-not $r.Apply -or -not "$($r.Property)".Trim()) { continue }
            $tag = if ($r.IsPredDiff) { ' [carried from predecessor MST]' } elseif ($r.UserEdited -or -not $r.HasPred) { ' [your edit]' } else { '' }
            if (-not $r.InMsi) { $lines.Add("  + NEW property $($r.Property) = $($r.YourValue)$tag") | Out-Null }
            elseif ("$($r.YourValue)" -ne "$($r.BaseValue)") { $lines.Add("  ~ $($r.Property) = $($r.YourValue)  (current MSI has '$($r.BaseValue)')$tag") | Out-Null }
            else { $lines.Add("  = $($r.Property) = $($r.YourValue) (set, value unchanged)") | Out-Null }
        }
        foreach ($c in $checkRows) { if ($c.Apply -and "$($c.Property)".Trim()) { $lines.Add("  [checkbox] $($c.Property) = $($c.CheckedValue)") | Out-Null } }
        foreach ($o in $otherRows) { if ($o.Replicate -and "$($o.Action)" -eq 'remove' -and "$($o.Table)".Trim() -and "$($o.Keys)".Trim()) { $lines.Add("  remove from $($o.Table): $($o.Keys)$(if ($o.FromPred) { ' [predecessor]' } else { ' [your removal]' })") | Out-Null } }
        if ($lines.Count -le $(if ($hasPred) { 1 } else { 0 })) { $lines.Add('  (no property changes yet - nothing beyond the standard ALLUSERS / REBOOT)') | Out-Null }
        $lines.Add('  + standard: ALLUSERS=1, REBOOT=ReallySuppress (added at build)') | Out-Null
        $TxtSummary.Text = ($lines -join "`r`n")
    }.GetNewClosure()

    $onChg = { param($s,$e) if (-not $ui.Init) { & $ui.UpdateSummary } }.GetNewClosure()
    foreach ($r in $rows) { $r.add_PropertyChanged($onChg) }
    foreach ($c in $checkRows) { $c.add_PropertyChanged($onChg) }
    foreach ($o in $otherRows) { $o.add_PropertyChanged($onChg) }

    # map a table name to its primary-key column (the build deletes rows by this PK); unknown table => not transformable
    $ui.PkFor = { param($t) @{ Registry='Registry'; Shortcut='Shortcut'; RemoveFile='FileKey'; LaunchCondition='Condition'; Feature='Feature'; Environment='Environment' }["$t"] }.GetNewClosure()

    # ----- undo (whole-state snapshots) -----
    $ui.Snap = {
        $ps = @(); foreach ($r in $rows) { $ps += ,@{ R=$r; V=$r.YourValue; A=$r.Apply; E=$r.UserEdited } }
        $cs = @(); foreach ($c in $checkRows) { $cs += ,@{ R=$c; V=$c.CheckedValue; A=$c.Apply } }
        $os = @(); foreach ($o in $otherRows) { $os += ,@{ R=$o; Rep=$o.Replicate; T=$o.Table; K=$o.Keys } }
        return @{ Order=@($rows); OtherOrder=@($otherRows); Props=$ps; Checks=$cs; Other=$os; Master=[bool]$ChkMaster.IsChecked }
    }.GetNewClosure()
    $ui.Restore = {
        param($snap)
        $ui.Init = $true
        $rows.Clear(); foreach ($r in $snap.Order) { $rows.Add($r) }
        $otherRows.Clear(); foreach ($o in $snap.OtherOrder) { $otherRows.Add($o) }
        foreach ($p in $snap.Props) { $p.R.SetValueQuiet($p.V); $p.R.SetApplyQuiet($p.A); $p.R.SetEditedQuiet($p.E) }
        foreach ($c in $snap.Checks) { $c.R.CheckedValue = $c.V; $c.R.Apply = $c.A }
        foreach ($o in $snap.Other) { $o.R.Replicate = $o.Rep; $o.R.Table = $o.T; $o.R.Keys = $o.K }
        $ChkMaster.IsChecked = $snap.Master
        $ui.Init = $false
        & $ui.UpdateSummary
    }.GetNewClosure()
    $ui.Push = { $ui.Undo_Stack.Push((& $ui.Snap)) | Out-Null }.GetNewClosure()
    $ui.DoUndo = { if ($ui.Undo_Stack.Count) { & $ui.Restore ($ui.Undo_Stack.Pop()) } }.GetNewClosure()

    # snapshot BEFORE each cell edit so Ctrl+Z / Undo steps back one change
    $beforeEdit = { param($s,$e) if (-not $ui.Init) { & $ui.Push } }.GetNewClosure()
    $GridProps.add_BeginningEdit($beforeEdit)
    $GridChecks.add_BeginningEdit($beforeEdit)
    $GridOther.add_BeginningEdit($beforeEdit)

    # ----- master switch: opens with the packager's standing choice (State.CarryPredMst), never forced on -----
    $ChkMaster.IsChecked = [bool]$carry
    if ($hasPred) { $LblMasterHint.Text = 'Off = ignore the predecessor MST entirely. Remembered until you change it.' } else { $ChkMaster.IsEnabled = $false; $LblMasterHint.Text = 'No predecessor MST loaded.' }
    $ChkMaster.add_Checked({
        if ($ui.Init) { return }
        & $ui.Push; $ui.Undo_Stack.Peek().Master = $false   # a CheckBox event fires AFTER the toggle, so record the PRE-toggle state
        $ui.Init = $true
        foreach ($r in $rows) { if ($r.HasPred -and -not $r.UserEdited) { $r.SetValueQuiet($r.PredValue); $r.SetApplyQuiet($true); $r.SetEditedQuiet($false) } }
        foreach ($o in $otherRows) { if ($o.FromPred -and $o.CanApply) { $o.Replicate = $true } }   # only predecessor rows; user-added removals are left alone
        $ui.Init = $false; & $ui.UpdateSummary
    }.GetNewClosure())
    $ChkMaster.add_Unchecked({
        if ($ui.Init) { return }
        & $ui.Push; $ui.Undo_Stack.Peek().Master = $true    # a CheckBox event fires AFTER the toggle, so record the PRE-toggle state
        $ui.Init = $true
        foreach ($r in $rows) { if ($r.HasPred -and -not $r.UserEdited) { $r.SetApplyQuiet($false); $r.SetValueQuiet($r.BaseValue) } }
        foreach ($o in $otherRows) { if ($o.FromPred) { $o.Replicate = $false } }   # off ignores the predecessor; keep the user's own removals
        $ui.Init = $false; & $ui.UpdateSummary
    }.GetNewClosure())

    # ----- filter (Properties tab) -----
    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($rows)
    $TxtFilter.add_TextChanged({
        $f = $TxtFilter.Text.Trim()
        if ($f) { $view.Filter = { param($x) ("$($x.Property)" -like "*$f*") -or ("$($x.YourValue)" -like "*$f*") }.GetNewClosure() }
        else { $view.Filter = $null }
    }.GetNewClosure())

    # ----- buttons -----
    $BtnAdd.add_Click({
        & $ui.Push
        $r = New-Object MsiPropRow; $r.Property = ''; $r.InMsi = $false; $r.BaseValue = ''; $r.SetApplyQuiet($true); $r.SetEditedQuiet($true)
        $r.add_PropertyChanged($onChg); $rows.Add($r); $GridProps.ScrollIntoView($r); $GridProps.SelectedItem = $r
        & $ui.UpdateSummary
    }.GetNewClosure())
    $BtnDel.add_Click({
        $sel = @($GridProps.SelectedItems | ForEach-Object { $_ })
        if (-not $sel.Count) { [Windows.MessageBox]::Show('Select a property row (or rows) to delete.', 'Delete property') | Out-Null; return }
        & $ui.Push
        foreach ($r in $sel) { [void]$rows.Remove($r) }
        & $ui.UpdateSummary
    }.GetNewClosure())
    $BtnOtherAdd.add_Click({
        & $ui.Push
        $o = New-Object MstOtherRow
        $o.FromPred = $false; $o.CanApply = $true; $o.Action = 'remove'; $o.Category = 'custom'
        $o.Table = 'Registry'; $o.PkCol = 'Registry'; $o.Keys = ''; $o.Detail = 'your removal (deletes matching rows; no-op if absent)'
        $o.Replicate = $true
        $o.add_PropertyChanged($onChg); $otherRows.Add($o); $GridOther.ScrollIntoView($o); $GridOther.SelectedItem = $o
        & $ui.UpdateSummary
    }.GetNewClosure())
    $BtnOtherDel.add_Click({
        $sel = @($GridOther.SelectedItems | ForEach-Object { $_ })
        if (-not $sel.Count) { [Windows.MessageBox]::Show('Select a row (or rows) in the Other tables tab to delete.', 'Delete') | Out-Null; return }
        & $ui.Push
        foreach ($o in $sel) { [void]$otherRows.Remove($o) }
        & $ui.UpdateSummary
    }.GetNewClosure())
    $BtnUndo.add_Click({ & $ui.DoUndo }.GetNewClosure())
    $BtnReset.add_Click({
        & $ui.Push; $ui.Init = $true
        foreach ($r in $rows) { $r.SetValueQuiet($r.BaseValue); $r.SetApplyQuiet($false); $r.SetEditedQuiet($false) }
        foreach ($c in $checkRows) { $c.Apply = $false }
        foreach ($o in $otherRows) { $o.Replicate = $false }
        $ChkMaster.IsChecked = $false
        $ui.Init = $false; & $ui.UpdateSummary
    }.GetNewClosure())
    $BtnOk.add_Click({
        $GridProps.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null
        $GridChecks.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null
        $GridOther.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null
        $w.DialogResult = $true
    }.GetNewClosure())

    $w.add_PreviewKeyDown({
        param($s,$e)
        if ($e.Key -eq 'Z' -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) { & $ui.DoUndo; $e.Handled = $true }
    }.GetNewClosure())

    # Build the OK result (the KEY=VALUE lines + selected replications + master state) from the current UI state.
    # Factored out so the headless test seam can exercise the exact same output logic without the modal loop.
    $ui.BuildResult = {
        $keys = @{}
        $outLines = New-Object System.Collections.Generic.List[string]
        foreach ($r in $rows) {
            if ($r.Apply -and "$($r.Property)".Trim()) { $k = "$($r.Property)".Trim(); $keys[$k] = $true; $outLines.Add("$k=$($r.YourValue)") | Out-Null }
        }
        foreach ($c in $checkRows) {
            if ($c.Apply -and "$($c.Property)".Trim()) { $k = "$($c.Property)".Trim(); if (-not $keys.ContainsKey($k)) { $keys[$k] = $true; $outLines.Add("$k=$($c.CheckedValue)") | Out-Null } }
        }
        # Rebuild the replication list from the (editable) Other-tables grid. Only ticked REMOVALS with a known
        # table + at least one key are transformable; the tick state already reflects the master switch (off unticks
        # predecessor rows). A no-op at build if the key is absent, so it can never corrupt the new MSI.
        $extras = New-Object System.Collections.Generic.List[object]
        foreach ($o in $otherRows) {
            if (-not $o.Replicate) { continue }
            if ("$($o.Action)" -ne 'remove') { continue }
            $tbl = "$($o.Table)".Trim(); if (-not $tbl) { continue }
            $pk = & $ui.PkFor $tbl; if (-not $pk) { continue }
            $ks = @("$($o.Keys)" -split '[\r\n,;]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            if (-not $ks.Count) { continue }
            [void]$extras.Add([pscustomobject]@{ Action='remove'; Table=$tbl; PkCol=$pk; Keys=$ks; Category="$($o.Category)"; Label="$($o.Detail)" })
        }
        # DECLINED: every predecessor property / removal the packager UNTICKED is remembered by name, so the next
        # open (and the auto-apply) does not bring it back (20.09.2026: "changes I removed come back").
        $declined = New-Object System.Collections.Generic.List[string]
        foreach ($r in $rows)      { if ($r.HasPred -and -not $r.Apply -and "$($r.Property)".Trim()) { $declined.Add("prop:" + "$($r.Property)".Trim()) | Out-Null } }
        foreach ($o in $otherRows) { if ($o.FromPred -and -not $o.Replicate -and "$($o.Detail)".Trim()) { $declined.Add("item:" + "$($o.Detail)".Trim()) | Out-Null } }
        return @{ Text = ($outLines -join "`r`n"); Extras = @($extras.ToArray()); Master = [bool]$ChkMaster.IsChecked; Declined = @($declined.ToArray()) }
    }.GetNewClosure()

    $ui.Init = $false
    & $ui.UpdateSummary

    # Dormant test seam (normally $script:MsiDlgSmoke is unset => skipped): the WPF modal loop cannot run in a headless
    # station, so this runs the SAME logic paths and returns without ShowDialog. Modes: 'reset' (Reset button),
    # 'masteroff' (untick master), 'ok'/anything-else (accept current state), 'cancel' (return $null).
    if ($script:MsiDlgSmoke) {
        try {
            switch ("$script:MsiDlgSmoke") {
                'cancel'    { return $null }
                'reset'     { $BtnReset.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
                'masteroff' { $ChkMaster.IsChecked = $false }
                'undo'      { $ChkMaster.IsChecked = $false; & $ui.DoUndo }
                'del'       { & $ui.Push; foreach ($x in @($rows | Where-Object { $_.Property -eq 'IAGREE' })) { [void]$rows.Remove($x) } }
                'delundo'   { & $ui.Push; foreach ($x in @($rows | Where-Object { $_.Property -eq 'IAGREE' })) { [void]$rows.Remove($x) }; & $ui.DoUndo }
                'otheradd'  { $BtnOtherAdd.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))); ($otherRows | Select-Object -Last 1).Keys = 'k1, k2' }
                'otheredit' { ($otherRows | Where-Object { $_.FromPred -and $_.Action -eq 'remove' } | Select-Object -First 1).Keys = 'edited1, edited2' }
                'otherdel'  { & $ui.Push; foreach ($x in @($otherRows)) { [void]$otherRows.Remove($x) } }
                'otherundo' { $k=($otherRows | Where-Object { $_.FromPred } | Select-Object -First 1).Keys; & $ui.Push; ($otherRows | Where-Object { $_.FromPred } | Select-Object -First 1).Keys='ZZZ'; & $ui.DoUndo }
            }
        } catch { $script:MsiDlgSmokeErr = "$($_.Exception.Message)" }
        return (& $ui.BuildResult)
    }

    Set-PBDialogChrome -Window $w -Glyph 'E7C3' -Title 'MSI properties' -Subtitle (Split-Path $MsiPath -Leaf)
    if ($w.ShowDialog()) { return (& $ui.BuildResult) }
    return $null
}

# ---------- MST plan dialog (predecessor reuse): confirm what the MST will apply ----------
# Shows the STANDARD changes that will be applied (desktop-shortcut / Run-key removal pre-ticked from what the
# predecessor did, + the properties to set) and the EXTRA changes the predecessor MST also made. Safe removals
# are opt-in checkboxes; additions/changes are report-only (can't auto-apply without risking the new MSI).
# Nothing is applied until the user clicks "Apply plan"; Cancel returns $null and changes nothing.
if (-not ([System.Management.Automation.PSTypeName]'MstPlanRow').Type) {
    Add-Type -TypeDefinition 'public class MstPlanRow { public bool Apply { get; set; } public bool CanApply { get; set; } public string Change { get; set; } public string Mode { get; set; } public int Idx { get; set; } }'
}
function Show-MstPlanDialog {
    param([Parameter(Mandatory)][hashtable]$Result, [string]$MsiName = '')
    $items = @($Result.OtherItems)
    $rows = New-Object 'System.Collections.ObjectModel.ObservableCollection[MstPlanRow]'
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]
        $r = New-Object MstPlanRow
        $r.Idx = $i; $r.CanApply = [bool]$it.CanApply; $r.Apply = $false
        $r.Change = "$($it.Label)"
        $r.Mode = if ($it.CanApply) { 'can apply' } else { 'manual only' }
        $rows.Add($r)
    }

    $w = New-Object Windows.Window
    $w.Title = "MST plan - $MsiName"
    $w.Width = 760; $w.Height = 600; $w.WindowStartupLocation = 'CenterOwner'; $w.Owner = $script:Win
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $w }
    $g = New-Object Windows.Controls.Grid; $g.Margin = '16,12,16,14'
    foreach ($h in 'Auto','Auto','Auto','*','Auto') { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = $h; [void]$g.RowDefinitions.Add($rd) }

    $hint = New-Object Windows.Controls.TextBlock
    $hint.Text = "Review what the new MST will do, then confirm. The standard items below are pre-selected from what the predecessor's transform did - untick any you don't want. Tick any extra removals to replicate too. NOTHING is applied until you click 'Apply plan'."
    $hint.Foreground = '#B7BEC8'; $hint.FontSize = 12; $hint.TextWrapping = 'Wrap'; $hint.Margin = '0,0,0,12'
    [Windows.Controls.Grid]::SetRow($hint, 0); [void]$g.Children.Add($hint)

    # --- Standard section: will be applied ---
    $std = New-Object Windows.Controls.StackPanel; $std.Margin = '0,0,0,10'
    $stdHdr = New-PBCaption -Text 'Will be applied (standard)' -Margin '0,0,0,6'; $stdHdr.Foreground = '#57BE8C'
    [void]$std.Children.Add($stdHdr)
    $cbShort   = New-Object Windows.Controls.CheckBox; $cbShort.Content   = 'Remove desktop shortcut'; $cbShort.Foreground = '#E7E9ED'; $cbShort.Margin = '0,2,0,2'; $cbShort.IsChecked = [bool]$Result.RemovedShortcut
    $cbStartup = New-Object Windows.Controls.CheckBox; $cbStartup.Content = 'Remove Startup / autostart shortcut'; $cbStartup.Foreground = '#E7E9ED'; $cbStartup.Margin = '0,2,0,2'; $cbStartup.IsChecked = [bool]$Result.RemovedStartup
    $cbStray   = New-Object Windows.Controls.CheckBox; $cbStray.Content   = 'Remove SendTo / stray shortcuts'; $cbStray.Foreground = '#E7E9ED'; $cbStray.Margin = '0,2,0,2'; $cbStray.IsChecked = [bool]$Result.RemovedStray
    $cbRun     = New-Object Windows.Controls.CheckBox; $cbRun.Content     = 'Remove Run key'; $cbRun.Foreground = '#E7E9ED'; $cbRun.Margin = '0,2,0,2'; $cbRun.IsChecked = [bool]($Result.RemovedRunKey32 -or $Result.RemovedRunKey64)
    [void]$std.Children.Add($cbShort); [void]$std.Children.Add($cbStartup); [void]$std.Children.Add($cbStray); [void]$std.Children.Add($cbRun)
    $propTxt = ''
    if ($Result.ExtraProps -and $Result.ExtraProps.Count) { $propTxt = (($Result.ExtraProps.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ';  ') }
    $propLbl = New-Object Windows.Controls.TextBlock; $propLbl.TextWrapping = 'Wrap'; $propLbl.Foreground = '#B7BEC8'; $propLbl.FontSize = 12; $propLbl.Margin = '0,6,0,0'
    $propLbl.Text = "Properties to set: ALLUSERS=1; REBOOT=ReallySuppress (always)" + $(if ($propTxt) { ";  + from predecessor: $propTxt" } else { '' })
    [void]$std.Children.Add($propLbl)
    [Windows.Controls.Grid]::SetRow($std, 1); [void]$g.Children.Add($std)

    $exHdr = New-Object Windows.Controls.TextBlock
    $exHdr.Text = if ($items.Count) { "EXTRA CHANGES the predecessor MST also made ($($items.Count)) - tick removals to replicate:" } else { 'No extra changes detected beyond the standard items above.' }
    $exHdr.Foreground = '#E0BE7C'; $exHdr.FontSize = 10; $exHdr.FontWeight = 'SemiBold'; $exHdr.Text = $exHdr.Text.ToUpper(); $exHdr.Margin = '0,4,0,6'
    [Windows.Controls.Grid]::SetRow($exHdr, 2); [void]$g.Children.Add($exHdr)

    $grid = New-Object Windows.Controls.DataGrid
    $grid.AutoGenerateColumns = $false; $grid.CanUserAddRows = $false; $grid.HeadersVisibility = 'Column'; $grid.IsReadOnly = $false
    $grid.Background = '#21242B'; $grid.Foreground = '#E7E9ED'; $grid.RowBackground = '#2A2E36'; $grid.AlternatingRowBackground = '#21242B'
    $grid.BorderBrush = '#2F343D'; $grid.HorizontalGridLinesBrush = '#2A2F38'; $grid.FontFamily = 'Consolas'; $grid.FontSize = 12; $grid.GridLinesVisibility = 'Horizontal'
    $hdr = New-Object Windows.Style ([Windows.Controls.Primitives.DataGridColumnHeader])
    $hdr.Setters.Add((New-Object Windows.Setter ([Windows.Controls.Control]::BackgroundProperty), (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x21,0x24,0x2B)))))
    $hdr.Setters.Add((New-Object Windows.Setter ([Windows.Controls.Control]::ForegroundProperty), (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xA0,0xA8,0xB4)))))
    $hdr.Setters.Add((New-Object Windows.Setter ([Windows.Controls.Control]::PaddingProperty),    (New-Object Windows.Thickness 8,4,8,4)))
    $grid.ColumnHeaderStyle = $hdr
    # Apply checkbox: enabled only for CanApply rows (safety net on OK also filters), so report-only rows can't be ticked.
    $enBind = New-Object Windows.Style ([Windows.Controls.CheckBox])
    $enBind.Setters.Add((New-Object Windows.Setter ([Windows.UIElement]::IsEnabledProperty), (New-Object Windows.Data.Binding('CanApply'))))
    $colA = New-Object Windows.Controls.DataGridCheckBoxColumn; $colA.Header = 'Apply'; $colA.Binding = (New-Object Windows.Data.Binding('Apply')); $colA.Width = 55
    $colA.ElementStyle = $enBind; $colA.EditingElementStyle = $enBind
    $colM = New-Object Windows.Controls.DataGridTextColumn; $colM.Header = 'Type'; $colM.Binding = (New-Object Windows.Data.Binding('Mode')); $colM.Width = 95; $colM.IsReadOnly = $true
    $colC = New-Object Windows.Controls.DataGridTextColumn; $colC.Header = 'Change the predecessor MST made'; $colC.Binding = (New-Object Windows.Data.Binding('Change')); $colC.Width = '*'; $colC.IsReadOnly = $true
    # Wrap the (long) change descriptions so the full text is visible. Build the Setter via explicit
    # .Property/.Value assignment - the constructor (prop,value) form mis-binds ENUM values in PS 5.1.
    $wrapStyle = New-Object Windows.Style ([Windows.Controls.TextBlock])
    $wrapSetter = New-Object Windows.Setter; $wrapSetter.Property = [Windows.Controls.TextBlock]::TextWrappingProperty; $wrapSetter.Value = [Windows.TextWrapping]::Wrap
    $wrapStyle.Setters.Add($wrapSetter); $colC.ElementStyle = $wrapStyle
    foreach ($c in @($colA,$colM,$colC)) { [void]$grid.Columns.Add($c) }
    $grid.ItemsSource = $rows
    [Windows.Controls.Grid]::SetRow($grid, 3); [void]$g.Children.Add($grid)

    $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.HorizontalAlignment = 'Right'; $btns.Margin = '0,12,0,0'
    $bOk = New-PBGlyphButton -Glyph 'E8FB' -Text 'Apply plan' -Padding '16,5'; $bOk.IsDefault = $true
    try { $bOk.Style = $script:Win.FindResource('PbAccentButton') } catch {}
    $bOk.add_Click({ $w.DialogResult = $true }.GetNewClosure())
    $bCancel = New-Object Windows.Controls.Button; $bCancel.Content = 'Cancel'; $bCancel.Padding = '12,4'; $bCancel.IsCancel = $true
    foreach ($b in @($bOk,$bCancel)) { [void]$btns.Children.Add($b) }
    [Windows.Controls.Grid]::SetRow($btns, 4); [void]$g.Children.Add($btns)

    $w.Content = $g
    Set-PBDialogChrome -Window $w -Glyph 'E8C8' -Title 'Match predecessor MST' -Subtitle $MsiName
    if ($w.ShowDialog()) {
        $grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null
        $sel = @($rows | Where-Object { $_.Apply -and $_.CanApply } | ForEach-Object { $items[$_.Idx] })
        return @{ RemoveShortcut = [bool]$cbShort.IsChecked; RemoveRun = [bool]$cbRun.IsChecked; RemoveStartup = [bool]$cbStartup.IsChecked; RemoveStray = [bool]$cbStray.IsChecked; SelectedExtras = $sel; ExtraProps = $Result.ExtraProps }
    }
    return $null
}

# ---------- Package-log picker (Troubleshoot): choose which PSADT/MSI/EXE log to fetch ----------
if (-not ([System.Management.Automation.PSTypeName]'PBLogRow').Type) {
    Add-Type -TypeDefinition 'public class PBLogRow { public string Name { get; set; } public string Modified { get; set; } public string SizeKB { get; set; } public string Folder { get; set; } public string RemotePath { get; set; } }'
}
function Show-LogPicker {
    param([object[]]$Logs, [string]$Machine)
    $rows = New-Object 'System.Collections.ObjectModel.ObservableCollection[PBLogRow]'
    foreach ($l in $Logs) {
        $r = New-Object PBLogRow
        $r.Name = "$($l.Name)"; $r.Modified = "$($l.Modified)"; $r.SizeKB = "$($l.SizeKB)"
        $r.Folder = "$($l.Folder)"; $r.RemotePath = "$($l.RemotePath)"
        $rows.Add($r)
    }
    # Built from XAML (same mechanism as the main window) - declarative brush strings are parsed by the
    # XAML reader and never hit the .NET Setter value-validation that rejected a programmatic
    # ForegroundProperty=Brushes.White on the selection trigger inside the packed exe.
    [xml]$x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="780" Height="500" WindowStartupLocation="CenterOwner" Background="#181A1F"
        Title="Package logs - pick one to open in CMTrace">
  <Grid Margin="12">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock x:Name="Hint" Grid.Row="0" Foreground="#B7BEC8" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,8"/>
    <ListView x:Name="Lv" Grid.Row="1" Background="#21242B" Foreground="#E7E9ED" BorderBrush="#3F3F46"
              FontFamily="Consolas" FontSize="12">
      <ListView.ItemContainerStyle>
        <Style TargetType="ListViewItem">
          <Setter Property="Foreground" Value="#E7E9ED"/>
          <Style.Triggers>
            <Trigger Property="IsSelected" Value="True">
              <Setter Property="Background" Value="#0E639C"/>
              <Setter Property="Foreground" Value="White"/>
            </Trigger>
          </Style.Triggers>
        </Style>
      </ListView.ItemContainerStyle>
      <ListView.View>
        <GridView>
          <GridViewColumn Header="Log file"  Width="340" DisplayMemberBinding="{Binding Name}"/>
          <GridViewColumn Header="Modified"  Width="130" DisplayMemberBinding="{Binding Modified}"/>
          <GridViewColumn Header="KB"        Width="60"  DisplayMemberBinding="{Binding SizeKB}"/>
          <GridViewColumn Header="Subfolder" Width="180" DisplayMemberBinding="{Binding Folder}"/>
        </GridView>
      </ListView.View>
    </ListView>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BOk" Content="Open in CMTrace" Padding="14,4" Margin="0,0,8,0" IsDefault="True"/>
      <Button x:Name="BCancel" Content="Cancel" Padding="12,4" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $w }
    $w.Title = "Package logs on $Machine - pick one to open in CMTrace"
    try { $w.Owner = $script:Win } catch {}
    $hint = $w.FindName('Hint'); $lv = $w.FindName('Lv')
    $hint.Text = "Newest first. Install / uninstall / repair / MSI / EXE logs that match the package's vendor or app name. Double-click (or OK) opens the log in CMTrace."
    $lv.ItemsSource = $rows
    if ($rows.Count) { $lv.SelectedIndex = 0 }
    $w.FindName('BOk').add_Click({ if ($lv.SelectedItem) { $w.DialogResult = $true } }.GetNewClosure())
    $lv.add_MouseDoubleClick({ if ($lv.SelectedItem) { $w.DialogResult = $true } }.GetNewClosure())
    Set-PBDialogChrome -Window $w -Glyph 'E7C3' -PrimaryName 'BOk'
    if ($w.ShowDialog() -and $lv.SelectedItem) { return "$($lv.SelectedItem.RemotePath)" }
    return $null
}


# Single-MSI "View MSI properties..." (Step 2). Writes the ticked rows into TxtMsiProps (state syncs via TextChanged).
$BtnMsiPropsView.add_Click({
    $msi = @($script:State.ChosenInstallers) | Where-Object { $_.Extension -and $_.Extension.ToLower() -eq '.msi' } | Select-Object -First 1
    if (-not $msi) { [Windows.MessageBox]::Show('No MSI selected in this package.', 'MSI properties') | Out-Null; return }
    # Auto-load the predecessor MST's property changes so this dialog shows the COMBINED (predecessor + current) diff
    # by itself - no need to click "Match predecessor MST" first. (That button ALSO sets the shortcut / Run-key removal
    # toggles, which this property view doesn't cover - so it stays.) Best-effort; silent on failure.
    if ((-not $script:State.PredMstProps -or @($script:State.PredMstProps.Keys).Count -eq 0) -and $script:State.PredecessorPath -and (Test-Path "$($script:State.PredecessorPath)")) {
        try {
            $pMsi = Get-ChildItem -LiteralPath $script:State.PredecessorPath -Recurse -Filter *.msi -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 1
            $pMst = Get-ChildItem -LiteralPath $script:State.PredecessorPath -Recurse -Filter *.mst -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($pMsi -and $pMst) { $ps = Read-MstSettings -MsiPath $pMsi.FullName -MstPath $pMst.FullName; if ($ps) { if ($ps.ExtraProps) { $script:State.PredMstProps = $ps.ExtraProps }; if ($ps.OtherItems) { $script:State.MstOtherItems = @($ps.OtherItems) } } }
            elseif ($LblMatchMst) { $LblMatchMst.Text = "The predecessor has no MSI+MST pair to carry forward - showing this MSI's own properties only."; $LblMatchMst.Foreground = '#A0A8B4' }
        } catch {
            # NOT silent: without this the dialog just opens with no predecessor column and nobody knows why
            Write-Log "Could not read the predecessor MST ($($script:State.PredecessorPath)): $($_.Exception.Message)" Warning
            if ($LblMatchMst) { $LblMatchMst.Text = "The predecessor's MST could not be read - its changes are NOT carried forward. $($_.Exception.Message)"; $LblMatchMst.Foreground = '#E0BE7C' }
        }
    }
    $predLoaded = [bool]($script:State.PredecessorPath -and (Test-Path "$($script:State.PredecessorPath)") -and (@($script:State.PredMstProps.Keys).Count -or @($script:State.MstOtherItems).Count))
    $declinedNow = @(); try { $declinedNow = @($script:State.PredMstDeclined[$msi.FullName]) } catch {}
    $res = Show-MsiPropertiesDialog -MsiPath $msi.FullName -ExistingText $TxtMsiProps.Text -PredecessorProps $script:State.PredMstProps -PredecessorItems @($script:State.MstOtherItems) -PredecessorLoaded $predLoaded -MsiName $msi.Name `
                                    -MasterOn ([bool]$script:State.CarryPredMst) -Declined $declinedNow
    if ($null -ne $res) {
        $TxtMsiProps.Text = "$($res.Text)"
        # the Other-tables tab is the authority for which predecessor removals to replicate at build (master-gated)
        $script:State.MstApplyExtras = @($res.Extras)
        # what the packager decided IS the state: the master switch and every unticked predecessor item are kept
        # by name, so the next open - and the auto-apply - start from this decision, not from the predecessor again
        if (-not $script:State.PredMstDeclined) { $script:State.PredMstDeclined = @{} }
        $script:State.PredMstDeclined[$msi.FullName] = @($res.Declined)
        if ([bool]$script:State.CarryPredMst -ne [bool]$res.Master) {
            $script:State.CarryPredMst = [bool]$res.Master
            $script:Rehydrating = $true; try { if ($ChkCarryPredMst) { $ChkCarryPredMst.IsChecked = [bool]$res.Master } } finally { $script:Rehydrating = $false }
            Invalidate-From 3
        }
        Invalidate-From 3
    }
})
# The page switch and the dialog's master switch are one decision. Toggling it re-applies (or withdraws) the
# predecessor MST defaults - properties, Keep toggles, removals - and the script is rebuilt.
$ChkCarryPredMst.add_Click({
    if ($script:Rehydrating) { return }
    $script:State.CarryPredMst = [bool]$ChkCarryPredMst.IsChecked
    $first = @($script:State.ChosenInstallers) | Where-Object { $_.Extension -and $_.Extension.ToLower() -eq '.msi' } | Select-Object -First 1
    if ($first) {
        if (-not $script:State.CarryPredMst) {
            # withdraw: drop the predecessor's property lines (the user's own lines stay), reset Keep toggles to the standard cleanup
            # PredMstProps is an OrderedDictionary (Read-MstSettings) - it has Contains, not ContainsKey (crash 20.09.2026)
            $pred = @{}; try { foreach ($kv in @($script:State.PredMstProps.GetEnumerator())) { $pred["$($kv.Key)"] = "$($kv.Value)" } } catch {}
            $keep = @(($TxtMsiProps.Text -split "`r?`n") | Where-Object { $l = $_.Trim(); if (-not $l) { $false } else { $k = ($l -split '=', 2)[0].Trim(); $v = $(if ($l -match '=') { ($l -split '=', 2)[1].Trim() } else { '' }); -not ($pred.ContainsKey($k) -and "$($pred[$k])" -eq $v) } })
            $TxtMsiProps.Text = ($keep -join "`r`n")
            $fl = Get-MsiFlags $first.FullName; $fl.KeepShortcut = $false; $fl.KeepStartup = $false; $fl.KeepStray = $false; $fl.KeepRunKey = $false
            $ChkKeepShortcut.IsChecked = $false; $ChkKeepStartup.IsChecked = $false; $ChkKeepStray.IsChecked = $false; $ChkKeepRunKey.IsChecked = $false
            $script:State.MstApplyExtras = @(); $script:State.MstReviewNotes = @()
            if ($LblMatchMst) { $LblMatchMst.Text = 'Predecessor MST found but NOT carried forward (switch above is off) - the new MSI gets the standard transform only.'; $LblMatchMst.Foreground = '#A0A8B4' }
        } else {
            $script:State.PredMstAppliedKey = ''   # re-apply the defaults once
            if (Get-Command Set-PredecessorMstAuto -EA SilentlyContinue) { Set-PredecessorMstAuto; $script:State.PredMstAppliedKey = "$($script:State.PredecessorPath)|$($first.FullName)" }
        }
    }
    Invalidate-From 3
})
# AUTO-MATCH the predecessor's MST onto the new MSI (no separate button/dialog - runs when the predecessor loads):
# reads the predecessor's transform and applies it as the DEFAULT - shortcut/Run-key Keep toggles, extra properties
# (also surfaced + editable in "View MSI properties", where the amber diff shows changed/new props), and the
# replicable removals. The packager REVIEWS/EDITS via those toggles and the View-MSI dialog; nothing else to click.
# Best-effort; silent no-op when there's no MSI, no predecessor MSI/MST, or the read fails.
function Set-PredecessorMstAuto {
    if (-not $LblMatchMst) { return }
    $script:State.PredMstProps = @{}   # clear stale props first (a no-op below then leaves it empty for a non-MSI / no-MST predecessor)
    $pp = "$($script:State.PredecessorPath)"
    $first = @($script:State.ChosenInstallers) | Where-Object { $_.Extension -and $_.Extension.ToLower() -eq '.msi' } | Select-Object -First 1
    if (-not $pp -or -not (Test-Path $pp) -or -not $first) { $LblMatchMst.Text = ''; return }
    $predMsi = Get-ChildItem -LiteralPath $pp -Recurse -Filter *.msi -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 1
    $predMst = Get-ChildItem -LiteralPath $pp -Recurse -Filter *.mst -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $predMsi -or -not $predMst) { $LblMatchMst.Text = ''; return }
    $s = Read-MstSettings -MsiPath $predMsi.FullName -MstPath $predMst.FullName
    if (-not $s) { $LblMatchMst.Text = ''; return }
    # property changes -> shown + editable in "View MSI properties" (amber diff) - always READ, so the dialog can show
    # the predecessor column; APPLIED only while the carry-forward switch is on
    $script:State.PredMstProps = if ($s.ExtraProps) { $s.ExtraProps } else { @{} }
    $script:State.MstOtherItems  = @($s.OtherItems)   # full comparison for the "Other tables" tab of View MSI properties
    if ($ChkCarryPredMst) { $ChkCarryPredMst.Visibility = 'Visible'; $ChkCarryPredMst.IsChecked = [bool]$script:State.CarryPredMst }
    if (-not $script:State.CarryPredMst) {
        $script:State.MstApplyExtras = @(); $script:State.MstReviewNotes = @()
        $LblMatchMst.Text = 'Predecessor MST found but NOT carried forward (switch above is off) - the new MSI gets the standard transform only.'; $LblMatchMst.Foreground = '#A0A8B4'
        return
    }
    $declined = @{}; try { $dl = $script:State.PredMstDeclined[$first.FullName]; foreach ($k in @($dl)) { if ("$k") { $declined["$k"] = $true } } } catch {}
    # standard removals -> Keep toggles (Keep = INVERSE of remove). Write State.MsiFlags directly (a programmatic
    # IsChecked set does NOT fire add_Click) so the plan actually takes effect at build.
    $fl = Get-MsiFlags $first.FullName
    $fl.KeepShortcut = (-not $s.RemovedShortcut)
    $fl.KeepStartup  = (-not $s.RemovedStartup)
    $fl.KeepStray    = (-not $s.RemovedStray)
    $fl.KeepRunKey   = (-not ($s.RemovedRunKey32 -or $s.RemovedRunKey64))
    $ChkKeepShortcut.IsChecked = $fl.KeepShortcut
    $ChkKeepStartup.IsChecked  = $fl.KeepStartup
    $ChkKeepStray.IsChecked    = $fl.KeepStray
    $ChkKeepRunKey.IsChecked   = $fl.KeepRunKey
    # properties the packager unticked earlier stay out (View MSI properties remembers them by name)
    $applyProps = @{}; if ($s.ExtraProps) { foreach ($kv in $s.ExtraProps.GetEnumerator()) { if (-not $declined.ContainsKey("prop:$($kv.Key)")) { $applyProps[$kv.Key] = $kv.Value } } }
    if ($applyProps.Count) { $TxtMsiProps.Text = (($applyProps.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`r`n") }
    # replicate the predecessor's can-apply removals at build (minus the declined ones); manual-only items -> review notes (Step 4)
    $script:State.MstApplyExtras = @($s.OtherItems | Where-Object { $_.CanApply -and -not $declined.ContainsKey("item:$("$($_.Label)".Trim())") })
    $manual = @($s.OtherItems | Where-Object { -not $_.CanApply } | ForEach-Object { $_.Label })
    $script:State.MstReviewNotes = @($manual)
    $msg = "Predecessor MST applied automatically: $($applyProps.Count) property change(s) + shortcut/Run-key Keep toggles"
    if (@($script:State.MstApplyExtras).Count) { $msg += " + $(@($script:State.MstApplyExtras).Count) replicated removal(s)" }
    $msg += ". Review/edit in 'View MSI properties' and the Keep toggles."
    if ($manual.Count) { $msg += "  ($($manual.Count) report-only item(s) flagged - see Step 4.)" }
    $LblMatchMst.Text = $msg; $LblMatchMst.Foreground = if ($manual.Count) { '#DCDCAA' } else { '#6A9955' }
}

# ---------- events ----------
$TxtPkg.add_TextChanged({
    if ($script:Rehydrating) { return }
    $script:State.PkgName = $TxtPkg.Text
    $script:State.Parsed  = $null
    $script:LastPredScanKey = ''           # name edited => let the proactive predecessor check re-run on blur
    Invalidate-From 1                     # name changed => predecessor, source, detection, script all stale
    $LblParsed.Text=''
    Update-NameLengthCounter   # live while typing
    $LblPred.Text = 'No predecessor yet - Find predecessor lists earlier releases of this app to reuse.'; $LblPred.Foreground = '#A0A8B4'
    $LblSrc.Text  = 'No source yet - Fetch source, or add the installer by hand.'; $LblSrc.Foreground = '#A0A8B4'
    Update-PBChrome
})
$TxtPkg.add_LostFocus({ Parse-Current | Out-Null; Update-PBChrome })
$TxtRitm.add_TextChanged({
    if ($script:Rehydrating) { return }
    $script:State.Ritm = $TxtRitm.Text.Trim()
    Invalidate-From 3                     # RITM is written into the script/docs => rebuild Step 3
    Update-PBChrome
})
# Target-brand dropdown: reflect the current State on the control, and on change re-apply the brand rules by rebuilding.
function Sync-BrandCombo {
    if (-not $CmbBrand) { return }
    $tags = @(Get-GpfTargetTags)
    $want = "$($script:State.TargetBrand)".ToUpper(); if ($want -notin $tags) { $want = Get-GpfDefaultTargetTag; $script:State.TargetBrand = $want }
    foreach ($it in $CmbBrand.Items) { if ("$($it.Tag)".ToUpper() -eq $want) { if ($CmbBrand.SelectedItem -ne $it) { $CmbBrand.SelectedItem = $it }; break } }
}
$CmbBrand.add_SelectionChanged({
    if ($script:Rehydrating) { return }
    if (-not $CmbBrand.SelectedItem) { return }
    $tag = "$($CmbBrand.SelectedItem.Tag)".ToUpper()
    if ($tag -in @(Get-GpfTargetTags) -and $tag -ne "$($script:State.TargetBrand)") {
        $script:State.TargetBrand = $tag
        if ("$($TxtPkg.Text)".Trim()) { Parse-Current | Out-Null }   # re-check the Group/VWG 34-char name gate for the new brand
        Invalidate-From 3                 # brand drives InstallTitle / ProcToClose / name rules => rebuild Step 3
    }
    Update-PBChrome
})
Sync-BrandCombo

# Warn if the EXACT package name (same version + release) already exists in the live share. Returns $true if
# the user chose to STOP. Asked once per distinct name (shared by Find-predecessor and Next so it never nags twice).
function Test-LiveShareDuplicate {
    if (-not $script:State.Parsed -or -not $script:State.Parsed.IsValid) { return $false }
    $full = "$($script:State.Parsed.FullName)"
    if ($full -eq $script:LiveCheckedName) { return $false }
    $script:LiveCheckedName = $full
    $roots = if (Get-Command Get-PredecessorRoots -EA SilentlyContinue) { @(Get-PredecessorRoots) } else { @(Get-Setting 'PredecessorPath') }
    $hit = $null
    foreach ($lib in $roots) { try { $c = Join-Path $lib $full; if (Test-Path $c) { $hit = $c; break } } catch {} }
    if (-not $hit) { return $false }
    $ans = [Windows.MessageBox]::Show("'$full' already exists in the live share:`n$hit`n`nThis exact package (same version + release) is already packaged. Continue anyway?", 'Already in the live share', 'YesNo', 'Warning')
    return ($ans -ne 'Yes')
}
# Applies a LOADED predecessor model to the Step-1 UI (checkbox default, summary label, tooltip). Shared by the
# async continuation below so the click handler stays readable.
function Set-PredecessorUi {
    param($Chosen)
    # Default the "add predecessor uninstall block" choice: ON when the predecessor ALREADY
    # carries an uninstall block, OFF (ask the user) when it does not.
    $script:State.AddUninstallPrevious = $false
    if ($script:State.PredecessorModel) {
        $ex = Find-ExistingUninstallBlock -Code "$($script:State.PredecessorModel.Code.PreInstallCode)"
        $script:State.AddUninstallPrevious = [bool]$ex.Found
    }
    $ChkAddUninstall.Visibility = if ($script:State.PredecessorModel) { 'Visible' } else { 'Collapsed' }
    $ChkAddUninstall.IsChecked  = [bool]$script:State.AddUninstallPrevious
    # Show HOW the predecessor installs/uninstalls (esp. multi-component packages): a summary on the label, the full
    # ordered sequence in the tooltip, and a 'View predecessor install / uninstall...' button for the full detail.
    $pm = $script:State.PredecessorModel
    if ($pm) {
        $ic = [int]$pm.InstallCount; $uc = @($pm.UninstallSeq).Count
        if ($pm.IsMulti) { $LblPred.Text += "   -  MULTI-COMPONENT: installs $ic component(s) in order, uninstalls $uc in reverse (hover for the full sequence)." }
        else             { $LblPred.Text += "   -  installs 1 component$(if($uc){", uninstalls in $uc step(s)"}else{''})." }
        try { $LblPred.ToolTip = Format-PredecessorSeq -Model $pm } catch {}

    }
    # Predecessor just loaded -> auto-apply its MST (replaces the old "Match predecessor MST" button). Set the key so
    # the Step-2 refresh doesn't apply it a second time. Re-applies automatically if the MSI later changes (new key).
    $script:State.PredMstAppliedKey = ''
    if ($pm -and (Get-Command Set-PredecessorMstAuto -ErrorAction SilentlyContinue)) {
        Set-PredecessorMstAuto
        $mstMsi = @($script:State.ChosenInstallers) | Where-Object { $_.Extension -and $_.Extension.ToLower() -eq '.msi' } | Select-Object -First 1
        if ($mstMsi) { $script:State.PredMstAppliedKey = "$($script:State.PredecessorPath)|$($mstMsi.FullName)" }
    }
    Invalidate-From 3
}
$BtnPred.add_Click({
    if (-not (Parse-Current)) { return }
    Reset-PBShareAsk   # a cancel earlier must not silence this click
    if (Test-LiveShareDuplicate) { return }
    # SYNCHRONOUS by design (reverted from the r148 async experiment that repeatedly broke this critical path via
    # closure/runspace scope traps). The live-share walk takes a couple of seconds - a brief pause is fine; a working
    # predecessor popup is what matters. Plain add_Click (NOT .GetNewClosure) so $script:State + all functions resolve.
    $BtnPred.IsEnabled = $false
    $LblPred.Text = 'Searching the live share for predecessors...'
    try { $script:Win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch {}
    $predBox = @{ Cands = @() }   # filled by the search block; an access error offers a sign-in and searches once more
    $predRoot = "$(Get-Setting 'PredecessorPath')"; if (-not $predRoot) { $predRoot = "$(Get-Setting 'RepositoryPath')" }
    # THIS is the one place a predecessor sign-in belongs: the packager asked for the predecessor. Connect-PBShare
    # only prompts when the location is actually DENIED - a missing / unreachable path just falls through to the
    # "browse to the folder / pick a .zip" prompt below, as it always did.
    if ($predRoot -and -not (Test-Path -LiteralPath $predRoot)) { [void](Connect-PBShare -Path $predRoot -Purpose 'the predecessor location' -AllowPrompt) }
    try {
      Invoke-PBWithShareAccess -Path $predRoot -Purpose 'the predecessor location' -AllowPrompt -Action {
        # GPF: candidates come from the request's OWN Predecessor\ folder ONLY (no share scans - user rule).
        # If the packager clicks Predecessor BEFORE Fetch, locate the request here so it still works.
        $predBox.Cands = if ((Test-PBGpfFamily)) {
            if (-not $script:State.GpfRequest) {
                # (1) PRIORITY - the fetched SOURCE location: climb from the chosen installer up to its request root so the
                #     Predecessor\ folder sitting NEXT TO the source is used, even when the source came from somewhere other
                #     than the settings RepositoryPath. This is the packager's expectation: predecessor near the source wins.
                $rp = $null
                $srcInst = @($script:State.ChosenInstallers) | Select-Object -First 1
                if ($srcInst -and "$($srcInst.FullName)" -and (Get-Command Find-GpfRequestRoot -EA SilentlyContinue)) {
                    try { $rp = Find-GpfRequestRoot -StartPath (Split-Path -Parent "$($srcInst.FullName)") } catch {}
                    if ($rp) { Write-Log "GPF request located next to the fetched source: $(Split-Path $rp -Leaf)" }
                }
                # (2) FALLBACK - the settings RepositoryPath (Incoming) lookup by parsed identity.
                if (-not $rp) {
                    $rp = Find-GpfRequestFolder -IncomingRoot (Get-Setting 'RepositoryPath') -PackageName $script:State.Parsed.FullName `
                                                -Vendor $script:State.Parsed.Vendor -AppName $script:State.Parsed.AppName
                    if ($rp) { Write-Log "GPF request located under the settings RepositoryPath: $(Split-Path $rp -Leaf)" }
                }
                if ($rp) {
                    $script:State.GpfRequest = Resolve-GpfRequest -RequestPath $rp
                    if ($script:State.GpfRequest.OrderNumber -and -not "$($TxtRitm.Text)".Trim()) { $TxtRitm.Text = $script:State.GpfRequest.OrderNumber }
                }
            }
            @(Get-GpfPredecessorCandidates -Parsed $script:State.Parsed -Request $script:State.GpfRequest)
        } else {
            @(Get-PredecessorCandidates -Parsed $script:State.Parsed)
        }
      } | Out-Null
      $cands = @($predBox.Cands)
    } catch {
        Write-Log "Predecessor search failed: $($_.Exception.Message)" Error
        $LblPred.Text = "Predecessor search FAILED: $($_.Exception.Message)"; $LblPred.Foreground = '#F48771'
        $BtnPred.IsEnabled = $true; return
    }
    $BtnPred.IsEnabled = $true
    if (-not $cands -or $cands.Count -eq 0) {
        # SAY WHAT HAPPENED. Not "nothing found" plus a browse box: each location the search used is reported with
        # its own verdict (no rights / not there / nothing matching, with the closest names). Then two ways on -
        # sign in and search again (only when a location refused us), or pick the package yourself. ONE picker:
        # it takes a folder OR a zip and works out the rest (Resolve-PredecessorSelection).
        $rep = Get-PredecessorSearchReport -Parsed $script:State.Parsed
        $body = "No earlier release of $($script:State.Parsed.Vendor) $($script:State.Parsed.AppName) could be found.`r`n`r`n" +
                (@($rep.Lines | ForEach-Object { "  -  $_" }) -join "`r`n")
        $selPath = $null
        while ($true) {
            $choice = Show-PredecessorMissingDialog -Body $body -CanSignIn $rep.CanSignIn
            if ($choice -eq 'signin') {
                $any = $false
                foreach ($r in @($rep.Roots)) { if ("$r" -match '^\\\\' -and -not (Test-Path -LiteralPath $r)) { if (Connect-PBShare -Path $r -Purpose 'the predecessor location' -AllowPrompt -Retry) { $any = $true } } }
                if ($any) { $LblPred.Text = 'Signed in - searching again...'; $BtnPred.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))); return }
                $rep = Get-PredecessorSearchReport -Parsed $script:State.Parsed
                $body = "Still no access to the predecessor location.`r`n`r`n" + (@($rep.Lines | ForEach-Object { "  -  $_" }) -join "`r`n")
                continue
            }
            if ($choice -eq 'browse') {
                $dlg = New-Object System.Windows.Forms.OpenFileDialog
                $dlg.Title = 'Select the predecessor package - its folder, any file inside it, or its .zip'
                $dlg.Filter = 'Package or zip (*.zip;*.ps1;*.exe;*.msi)|*.zip;*.ps1;*.exe;*.msi|All files (*.*)|*.*'
                $dlg.CheckFileExists = $false; $dlg.FileName = 'Select this folder'
                foreach ($r in @($rep.Roots)) { if (Test-Path -LiteralPath $r) { $dlg.InitialDirectory = $r; break } }
                if ($dlg.ShowDialog() -eq 'OK' -and $dlg.FileName) {
                    # "Select this folder" (or any file inside the package) resolves to the folder itself
                    $selPath = $(if (Test-Path -LiteralPath $dlg.FileName -PathType Leaf) { $dlg.FileName } else { Split-Path $dlg.FileName -Parent })
                }
                break
            }
            break   # skip
        }
        if ($selPath) {
            $reason = ''
            $cands = @(Resolve-PredecessorSelection -Path $selPath -Parsed $script:State.Parsed -Reason ([ref]$reason))
            if (-not $cands.Count -and $reason) { $LblPred.Text = $reason; $LblPred.Foreground = '#E0BE7C'; Write-Log "Predecessor selection: $reason" Warning }
            elseif ($cands.Count) { Write-Log "Predecessor selected by hand: $($cands.Count) package(s) from $selPath" }
        }
        if (-not $cands -or $cands.Count -eq 0) {
            $script:State.PredecessorPath=$null; $script:State.PredecessorModel=$null
            # keep the diagnosis on screen (and in the tooltip in full) instead of a bare "not found"
            if (-not "$($LblPred.Text)".Trim() -or $LblPred.Text -like 'Searching*') {
                $LblPred.Text = "No predecessor used - $(@($rep.Lines)[0])"
                $LblPred.Foreground = '#E0BE7C'
            }
            $LblPred.ToolTip = $body
            $ChkAddUninstall.Visibility = 'Collapsed'

            Invalidate-From 3
            return
        }
    }
    # default selection: newest candidate strictly OLDER than the new version; else newest.
    $newVer = try { [version]($script:State.Parsed.Version -replace '[^0-9.]','') } catch { $null }
    $defIdx = 0
    for ($i=0; $i -lt $cands.Count; $i++) { if ($newVer -and $cands[$i].Ver -and $cands[$i].Ver -lt $newVer) { $defIdx = $i; break } }
    # ALWAYS show the picker so the packager SEES which predecessor is used and can pick a DIFFERENT one - even when
    # there's only a single candidate (the default is pre-selected; one click confirms). Previously a lone candidate was
    # auto-taken silently, which looked like "it just grabs the immediate predecessor with no choice".
    $chosen = Show-PredecessorPicker -Candidates $cands -DefaultIndex $defIdx
    if (-not $chosen) { $LblPred.Text = 'Predecessor selection cancelled.'; return }
    $script:State.PredecessorPath = $chosen.FullName
    $LblPred.Text = "Predecessor: $($chosen.Name)" + $(if ($chosen.SameVersion) { '   (same version - revision update)' } else { '' }) + '   - loading...'
    $BtnPred.IsEnabled = $false
    try { $script:Win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch {}
    try {
        Show-PBBusy -Title 'Loading predecessor' -Detail "$($chosen.Name) - reading its script, transforms and icons..."
        # an access problem inside the predecessor package offers a sign-in and reads once more
        try { $script:State.PredecessorModel = Invoke-PBWithShareAccess -Path "$($chosen.FullName)" -Purpose 'the predecessor package' -AllowPrompt -Action { Read-PredecessorModel -PackagePath $chosen.FullName -PackageName $chosen.Name } } finally { Hide-PBBusy }
    } catch {
        $script:State.PredecessorModel = $null; Write-Log "Predecessor load failed: $($_.Exception.Message)" Error
        $LblPred.Text = $LblPred.Text -replace '   - loading\.\.\.$', ''; $LblPred.Text += '   - LOAD FAILED (see log)'
    }
    $BtnPred.IsEnabled = $true
    $LblPred.Text = $LblPred.Text -replace '   - loading\.\.\.$', ''
    $LblPred.Foreground = '#56C8D6'
    Set-PredecessorUi -Chosen $chosen
    Update-PBChrome
})
# Show the predecessor's full install + uninstall sequence (how it goes, in order / reverse) in a dialog.
# ('View predecessor install / uninstall' was removed 23.09.2026 on the team's request - the same sequence stays
#  on the predecessor label's tooltip and in the reuse report.)
$BtnFetch.add_Click({
    # say why nothing happens instead of ignoring the click (control sweep, 24.09.2026)
    if (-not (Parse-Current)) {
        $LblSrc.Text = 'Enter a valid package name first (Vendor_App_Arch_Version-Release_Lang) - the source is looked up by that name.'
        $LblSrc.Foreground = '#E0BE7C'; $TxtPkg.Focus() | Out-Null; return
    }
    Reset-PBShareAsk   # a cancel earlier must not silence this click
    # SYNCHRONOUS (reverted from async - same closure-scope reliability reasons as BtnPred). A short share walk.
    $BtnFetch.IsEnabled = $false
    $LblSrc.Text = 'Searching the Incoming share for the source...'; $LblSrc.Foreground = '#A0A8B4'
    try { $script:Win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch {}
    # The Incoming share may need other credentials than the signed-in user has (Porsche): a root that cannot be
    # opened gets a sign-in prompt first; an access error DURING the search offers one too and searches once more.
    $repoRoot = "$(Get-Setting 'RepositoryPath')"
    if ($repoRoot -and -not (Connect-PBShare -Path $repoRoot -Purpose 'the Incoming share' -AllowPrompt)) {
        $LblSrc.Text = "The Incoming share could not be opened ($repoRoot) - sign in when asked, or use 'Add installer(s) / source'."; $LblSrc.Foreground = '#F48771'
        $BtnFetch.IsEnabled = $true; Update-PBChrome; return
    }
    Show-PBBusy -Title 'Fetching source' -Detail "Looking for $($script:State.Parsed.FullName) in $(Split-Path "$repoRoot" -Leaf)..."
    $folder = $null
    $found = @{ Folder = $null }   # filled by the search block (a scriptblock's own assignments stay inside it)
    try {
        Invoke-PBWithShareAccess -Path $repoRoot -Purpose 'the Incoming share' -AllowPrompt -Action {
            $found.Folder = $null
            if ((Test-PBGpfFamily)) {
                # GPF Incoming = one AES-1-... request folder per ticket. Find it by package name (with or without the
                # AES prefix; vendor+app fallback covers free-text folder names), harvest EVERYTHING it offers.
                $reqPath = Find-GpfRequestFolder -IncomingRoot (Get-Setting 'RepositoryPath') -PackageName $script:State.Parsed.FullName `
                                                 -Vendor $script:State.Parsed.Vendor -AppName $script:State.Parsed.AppName
                if ($reqPath) {
                    $req = Resolve-GpfRequest -RequestPath $reqPath
                    $script:State.GpfRequest = $req
                    if ($req.OrderNumber -and -not "$($TxtRitm.Text)".Trim()) { $TxtRitm.Text = $req.OrderNumber }   # AES -> order number (TextChanged persists it)
                    foreach ($n in @($req.Notes)) { Write-Log "GPF request: $n" Warning }
                    Write-Log ("GPF request matched: {0}  (AES {1}; icons {2}; doc items {3}; predecessor {4})" -f (Split-Path $reqPath -Leaf), $req.OrderNumber, @($req.IconFiles).Count, @($req.DocItems).Count, $(if($req.PredecessorPath){'in request'}else{'not provided'})) Success
                    $found.Folder = if ($req.FilesDir) { Split-Path $req.FilesDir -Parent }      # Sources\ (pre-shaped Files[+SupportFiles])
                                    elseif ($req.PayloadRoot) { $req.PayloadRoot }               # raw payload folder
                                    else { $reqPath }
                }
            } else {
                $found.Folder = Find-SourceFolder -PkgName $script:State.Parsed.FullName
            }
        } | Out-Null
        $folder = $found.Folder
    }
    catch { Hide-PBBusy; Write-Log "Source search failed: $($_.Exception.Message)" Error; $LblSrc.Text = "Source search FAILED: $($_.Exception.Message)"; $LblSrc.Foreground='#F48771'; $BtnFetch.IsEnabled = $true; return }
    $BtnFetch.IsEnabled = $true
    if ($folder) {
        Set-PBProgress -Status "Reading the installer files in $(Split-Path "$folder" -Leaf)..."
        try { Invoke-PBWithShareAccess -Path "$folder" -Purpose 'the source folder' -AllowPrompt -Action { Set-ResolvedSource -Folder "$folder" } | Out-Null }
        catch { Hide-PBBusy; Write-Log "Reading the source failed: $($_.Exception.Message)" Error; $LblSrc.Text = "Reading the source FAILED: $($_.Exception.Message)"; $LblSrc.Foreground='#F48771'; Update-PBChrome; return }
        finally { Hide-PBBusy }
        # GPF: the request's Icons\ + docs/mails/'Shortcut Behavior' complete whatever the source resolver found.
        $req = $script:State.GpfRequest
        if ($req -and $script:State.Resolved) {
            if (@($req.IconFiles).Count -and -not "$($script:State.Resolved.IconsPath)".Trim()) {
                $script:State.Resolved.IconsPath = Split-Path @($req.IconFiles)[0] -Parent
                Write-Log "Icons from the request folder: $($script:State.Resolved.IconsPath)"
            }
            # PREDECESSOR DOCUMENTS ARE NEVER TAKEN (user rule): the request's Predecessor\ lives INSIDE the request
            # folder, so the generic doc scan can catch its Documents - drop anything under a Predecessor path.
            $curDocs = @(@($script:State.Resolved.DocItems) | Where-Object { "$_" -notmatch '(?i)\\Predecessor\\' })
            if (@($curDocs).Count -ne @($script:State.Resolved.DocItems).Count) { Write-Log "Documents: dropped $((@($script:State.Resolved.DocItems).Count - @($curDocs).Count)) predecessor document item(s) (never carried)." }
            $script:State.Resolved.DocItems = $curDocs
            if (@($req.DocItems).Count) {
                $have = @{}; foreach ($d in @($curDocs)) { $have["$d".ToLower()] = $true }
                $merged = New-Object System.Collections.Generic.List[string]
                foreach ($d in @($curDocs)) { [void]$merged.Add("$d") }
                $added = 0
                foreach ($d in @($req.DocItems)) {
                    if ("$d" -match '(?i)\\Predecessor\\') { continue }
                    if (-not $have.ContainsKey("$d".ToLower())) { [void]$merged.Add("$d"); $added++ }
                }
                if ($added) { $script:State.Resolved.DocItems = $merged.ToArray(); Write-Log "Documents: +$added item(s) from the request folder (forms/mails/screenshots)." }
            }
        }
    }
    else { Hide-PBBusy; $LblSrc.Text = "Source folder not found in RepositoryPath - use 'Add installer(s) / source'."; $LblSrc.Foreground='#F48771' }
    Update-PBChrome
})
$BtnAddInst.add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Multiselect = $true
    $dlg.Title  = 'Select installer(s) - pick one or many; click the button again to add more'
    $dlg.Filter = 'Installers (*.msi;*.exe;*.msp)|*.msi;*.exe;*.msp|All files (*.*)|*.*'
    # Default to C:\temp (where downloaded installers usually land); fall back to the Incoming repository.
    $repo = Get-Setting 'RepositoryPath'
    if (Test-Path 'C:\temp') { $dlg.InitialDirectory = 'C:\temp' }
    elseif ($repo -and (Test-Path $repo)) { $dlg.InitialDirectory = $repo }
    if ($dlg.ShowDialog() -eq 'OK') { Add-ManualInstallers -Paths $dlg.FileNames }
})
$ChkAddUninstall.add_Click({ if ($script:Rehydrating) { return } ; $script:State.AddUninstallPrevious = [bool]$ChkAddUninstall.IsChecked; Invalidate-From 3 })
# KB ASSIST: fingerprint the chosen EXE + look up what similar packages used; show an advisory + Use button.
$script:KbHintSwitch = ''
function Update-KbHint {
    param($Installer, [switch]$Show)
    if (-not $PnlKbHint) { return }
    if (-not $Show -or -not $Installer -or -not $Installer.FullName -or -not (Test-Path $Installer.FullName)) { $PnlKbHint.Visibility = 'Collapsed'; return }
    $rec = $null; $eng = $null
    try { $eng = Get-InstallerEngine -Path $Installer.FullName } catch {}
    $script:KbHintInstaller = $Installer   # remembered for the "Probe /? help" button (wired once, runs on the current installer)
    if ($BtnProbeHelp) { $BtnProbeHelp.Visibility = 'Collapsed' }
    $p = $script:State.Parsed
    try { $rec = Get-KBRecommendation -Vendor $(if($p){$p.Vendor}) -App $(if($p){$p.AppName}) -Engine $eng -InstallerName $Installer.Name } catch {}
    # PackagedAsMsi recs legitimately have an EMPTY Install (the MSI installs via its MST, no extra params) - they
    # must NOT be treated as "no match" or we'd show the engine default and hide the "packaged as MSI+MST" note.
    if (-not $rec -or (-not "$($rec.Install)".Trim() -and -not $rec.PackagedAsMsi)) {
        # No KB match (e.g. a custom/unknown vendor installer like SentinelOne): GUIDE the packager instead of
        # showing nothing. The empty Install box then flags "no silent switches" for review at build time.
        # No KB match: fall back to the installer's ENGINE itself - suggest its default silent switch and show
        # the FULL parameter reference for that engine (every switch it supports), so a first-time / brand-new
        # installer still gets a useful starting point straight from the file's fingerprint.
        $engSwitch = if (Get-Command Get-EngineSwitch -EA SilentlyContinue) { "$(Get-EngineSwitch -Engine $eng)" } else { '' }
        $engHelp   = if (Get-Command Get-EngineParameterHelp -EA SilentlyContinue) { "$(Get-EngineParameterHelp -Engine $eng)" } else { '' }
        if ($engSwitch.Trim()) {
            $script:KbHintSwitch = $engSwitch
            $LblKbConf.Text = "[$eng]  engine default (no KB match)"
            $LblKbConf.Foreground = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#DCDCAA')))
            $LblKbArgs.Text = $engSwitch
            if ($BtnKbUse) { $BtnKbUse.Visibility = 'Visible' }
        } else {
            $script:KbHintSwitch = ''
            $LblKbConf.Text = "[$eng]  no known args"
            $LblKbConf.Foreground = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#A0A8B4')))
            $LblKbArgs.Text = ''
            if ($BtnKbUse) { $BtnKbUse.Visibility = 'Collapsed' }
        }
        $engUn  = if (Get-Command Get-EngineUninstallSwitch -EA SilentlyContinue) { "$(Get-EngineUninstallSwitch -Engine $eng)" } else { '' }
        $engUnE = if (Get-Command Get-EngineUninstaller -EA SilentlyContinue) { "$(Get-EngineUninstaller -Engine $eng)" } else { '' }
        $script:KbHintUninstall = $engUn   # 'Use' applies only the ARGS; the exe is shown for context
        if ($LblKbUninst) { $LblKbUninst.Text = if ($engUnE.Trim()) { ("{0}   {1}" -f $engUnE, $engUn).Trim() } else { $engUn } }
        if ($BtnKbUseUninst) { $BtnKbUseUninst.Visibility = if ($engUn.Trim()) { 'Visible' } else { 'Collapsed' } }
        $LblKbNote.Text = "All $eng parameters:  $engHelp"
        $LblKbNote.Visibility = 'Visible'
        # No confident KB/engine match -> offer to PROBE the installer's own /? help (the user's request).
        if ($BtnProbeHelp) { $BtnProbeHelp.Visibility = 'Visible' }
        $LblKbSrc.Text = "First-time suggestion from the installer's engine fingerprint (no past package matched) - verify against the vendor docs, or 'Probe installer for /? help' below."
        $PnlKbHint.Visibility = 'Visible'
        return
    }
    # The app was PREVIOUSLY PACKAGED AS MSI+MST (the MSI was extracted from this EXE) - don't offer the MSI
    # command as EXE args; tell the user to extract/capture the MSI, and show the previous uninstall.
    if ($rec.PackagedAsMsi) {
        $script:KbHintSwitch = ''
        $LblKbConf.Text = "[$eng]  previously packaged as MSI + MST"
        $LblKbConf.Foreground = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#DCDCAA')))
        $LblKbArgs.Text = ''
        if ($BtnKbUse) { $BtnKbUse.Visibility = 'Collapsed' }
        $script:KbHintUninstall = ''; if ($LblKbUninst) { $LblKbUninst.Text = '' }; if ($BtnKbUseUninst) { $BtnKbUseUninst.Visibility = 'Collapsed' }
        $note = "The previous version of this app was built as MSI + MST - the MSI was EXTRACTED from this installer (not installed as an EXE). Extract the bundled MSI (e.g. with 7-Zip) or capture it, then the tool builds MSI+MST. Previous MSI install: $($rec.Install)"
        if ("$($rec.Uninstall)".Trim()) { $note += "   Previous uninstall: $($rec.Uninstall)" }
        $LblKbNote.Text = $note
        $LblKbNote.Visibility = 'Visible'
        $LblKbSrc.Text = "Source: $($rec.Source)"
        $PnlKbHint.Visibility = 'Visible'
        return
    }
    if ($BtnKbUse) { $BtnKbUse.Visibility = 'Visible' }
    $confTxt = switch ($rec.Confidence) { 'high' {'HIGH confidence'} 'medium' {'MEDIUM confidence'} default {'LOW (engine default)'} }
    $col     = switch ($rec.Confidence) { 'high' {'#6A9955'} 'medium' {'#DCDCAA'} default {'#56C8D6'} }
    $LblKbConf.Text = "[$eng]  $confTxt"
    $LblKbConf.Foreground = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($col)))
    $LblKbArgs.Text = "$($rec.Install)"
    $script:KbHintSwitch = "$($rec.Install)"
    # answer/response-file note: the switch references a file the packager must supply (we can't know its name).
    if (Test-NeedsAnswerFile -Switch $rec.Install) {
        $LblKbNote.Text = "Needs a response/properties file: this switch points at an answer file (e.g. -f / .iss / -inputFile). The path is package-specific - point it at the file from THIS source (or capture one). The KB stores the switch pattern, not the old file path."
        $LblKbNote.Visibility = 'Visible'
    } else { $LblKbNote.Visibility = 'Collapsed' }
    # Uninstall suggestion: from the KB rec, else the engine's own default - so the uninstall box is never left
    # without a starting point. Shown in its own row with a 'Use' button that fills the Uninstall args box.
    $unArgs = if ("$($rec.Uninstall)".Trim()) { "$($rec.Uninstall)" } elseif (Get-Command Get-EngineUninstallSwitch -EA SilentlyContinue) { "$(Get-EngineUninstallSwitch -Engine $eng)" } else { '' }
    $unExe  = "$($rec.UninstallExe)"; if (-not $unExe.Trim() -and (Get-Command Get-EngineUninstaller -EA SilentlyContinue)) { $unExe = "$(Get-EngineUninstaller -Engine $eng)" }
    $script:KbHintUninstall = $unArgs   # 'Use' applies only the ARGS into the uninstall-args box; the exe is context
    if ($LblKbUninst) { $LblKbUninst.Text = if ("$unExe".Trim()) { ("{0}   {1}" -f $unExe, $unArgs).Trim() } else { $unArgs } }
    if ($BtnKbUseUninst) { $BtnKbUseUninst.Visibility = if ("$unArgs".Trim()) { 'Visible' } else { 'Collapsed' } }
    # Low-confidence (engine-based) suggestion: also surface the full engine parameter reference + the /? probe,
    # so a first-time installer keeps that guidance even though the KB now returns an engine-level rec.
    if ("$($rec.Confidence)" -eq 'low') {
        if ($LblKbNote.Visibility -ne 'Visible') {
            $engHelp = if (Get-Command Get-EngineParameterHelp -EA SilentlyContinue) { "$(Get-EngineParameterHelp -Engine $eng)" } else { '' }
            if ($engHelp.Trim()) { $LblKbNote.Text = "All $eng parameters:  $engHelp"; $LblKbNote.Visibility = 'Visible' }
        }
        if ($BtnProbeHelp) { $BtnProbeHelp.Visibility = 'Visible' }
    }
    $au = if ($rec.AutoUpdate.Count) { "   auto-update seen: $($rec.AutoUpdate -join ', ')" } else { '' }
    $LblKbSrc.Text = "Source: $($rec.Source)$au`r`nsuggestion only; verify before building."
    $PnlKbHint.Visibility = 'Visible'
}
$BtnKbUse.add_Click({
    if ($script:KbHintSwitch) { $TxtInstArgs.Text = $script:KbHintSwitch }   # TextChanged writes state + invalidates
})
$BtnKbUseUninst.add_Click({
    if ($script:KbHintUninstall) { $TxtUninstArgs.Text = $script:KbHintUninstall }   # fills the Uninstall args box
})
# Probe an unidentified installer for its own /? help text and show it - so the packager isn't stuck guessing.
# Probe an EXE for its /? help text and show it. Reusable (single-EXE panel or a per-EXE row). $StatusLabel optional.
function Invoke-ProbeHelp {
    param([Parameter(Mandatory)]$Exe, $StatusLabel)
    $st = { param($t) if ($StatusLabel) { $StatusLabel.Text="$t" } }
    if (-not $Exe -or -not (Test-Path $Exe.FullName)) { return }
    if (-not (Get-Command Get-InstallerHelp -EA SilentlyContinue)) { return }
    $ans = [Windows.MessageBox]::Show("Run '$($Exe.Name)' with /? /help --help -h to capture its usage text?`n`nIt tries non-elevated first; if the installer requires elevation (e.g. SentinelOne) it will ask for UAC once and capture the output from an elevated run. Most installers just print help, but a few may open a window - close any window that appears. Continue?", 'Probe installer help', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    & $st 'Probing /? /help ... (up to ~40s)'
    try { (Get-PBMainWindow).Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch {}
    $res = @(Get-InstallerHelp -ExePath $Exe.FullName)
    $hit = $res | Where-Object { "$($_.Output)".Trim() } | Select-Object -First 1
    if ($hit) {
        Show-TextDialog -Title "Help output: $($Exe.Name)  ($($hit.Switch))" -Text $hit.Output
        & $st "Probed $($Exe.Name): got output from '$($hit.Switch)'. Look for a silent/quiet switch and type it into Install args."
    } else {
        $notes = (($res | ForEach-Object { "$($_.Switch): $($_.Note)" }) -join "`r`n")
        Show-TextDialog -Title "Help output: $($Exe.Name)" -Text "No usage text was captured.`r`n`r`n$notes`r`n`r`nThis installer likely shows a GUI and ignores console help flags. Try the vendor's documentation, or check the engine parameter reference shown above."
        & $st "Probed $($Exe.Name): no console help captured (likely a GUI installer)."
    }
}
$BtnProbeHelp.add_Click({ if ($script:KbHintInstaller) { Invoke-ProbeHelp -Exe $script:KbHintInstaller -StatusLabel $LblKbSrc } })
# When a wrapper bundles MORE THAN ONE MSI (e.g. a suite that installs several products), let the packager pick
# WHICH MSIs to include and in what INSTALL ORDER (top installs first; uninstall runs in reverse). Each chosen MSI
# keeps its own vendor transform if the wrapper bundled one, and gets its package MST at assemble time. Returns an
# ORDERED string[] of the picked MSI paths, or $null on cancel.
function Show-BundledMsiPickerDialog {
    param([Parameter(Mandatory)][object[]]$Msis, [string]$WrapperName)
    $win = New-Object Windows.Window
    $win.Title = "Bundled MSIs - choose & order  ($WrapperName)"
    $win.Width = 820; $win.Height = 540; $win.WindowStartupLocation = 'CenterOwner'
    try { $win.Owner = $script:Win } catch {}
    $win.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x18,0x1A,0x1F)))
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $win }
    $g = New-Object Windows.Controls.Grid; $g.Margin='14'
    foreach ($h in 'Auto','*','Auto') { $rd=New-Object Windows.Controls.RowDefinition; $rd.Height=$h; [void]$g.RowDefinitions.Add($rd) }
    $hdr = New-Object Windows.Controls.TextBlock; $hdr.TextWrapping='Wrap'; $hdr.Foreground='#56C8D6'; $hdr.FontSize=12; $hdr.Margin='0,0,0,8'
    $hdr.Text = "This wrapper bundles $($Msis.Count) MSIs. Tick the ones to INCLUDE and use Up/Down to set the INSTALL ORDER (top installs first; uninstall runs in reverse). Each MSI keeps its own vendor transform (if present) and gets a package MST. Likely prerequisites (redists/runtimes) are unticked by default - re-tick if the suite needs them. TEST the full install AND uninstall before shipping."
    [Windows.Controls.Grid]::SetRow($hdr,0); [void]$g.Children.Add($hdr)

    $mid = New-Object Windows.Controls.Grid
    foreach ($c in '*','Auto') { $cd=New-Object Windows.Controls.ColumnDefinition; $cd.Width=$c; [void]$mid.ColumnDefinitions.Add($cd) }
    $lb = New-Object Windows.Controls.ListBox; $lb.Background='#15171B'; $lb.Foreground='#E7E9ED'; $lb.FontFamily='Consolas'; $lb.FontSize=12
    $lb.HorizontalContentAlignment='Stretch'
    [Windows.Controls.Grid]::SetColumn($lb,0); [void]$mid.Children.Add($lb)
    foreach ($m in $Msis) {
        $pn = $null; $pv = $null; $pc = $null
        if (Get-Command Get-MsiProperty -EA SilentlyContinue) {
            try { $pn = Get-MsiProperty -MsiPath $m.FullName -Property 'ProductName' }    catch {}
            try { $pv = Get-MsiProperty -MsiPath $m.FullName -Property 'ProductVersion' } catch {}
            try { $pc = Get-MsiProperty -MsiPath $m.FullName -Property 'ProductCode' }     catch {}
        }
        $vm = if (Get-Command Find-VendorMst -EA SilentlyContinue) { Find-VendorMst $m.FullName } else { $null }
        $sizeMB = [math]::Round($m.Length/1MB,1)
        $desc = "{0}   v{1}   ({2} MB)   [{3}]{4}" -f $(if($pn){$pn}else{$m.Name}), $(if($pv){$pv}else{'?'}), $sizeMB, $m.Name, $(if($vm){"   + vendor MST: $([IO.Path]::GetFileName($vm))"}else{''})
        $cb = New-Object Windows.Controls.CheckBox; $cb.Content=$desc; $cb.Foreground='#E7E9ED'; $cb.Margin='2'; $cb.IsChecked=$true; $cb.Tag=$m
        if ($pc) { $cb.ToolTip = "ProductName: $pn`nProductCode: $pc" }
        if ("$pn $($m.Name)" -match '(?i)redist|vcredist|visual c\+\+|\.net|dotnet|runtime|prerequisite|bootstrap') { $cb.IsChecked=$false }
        [void]$lb.Items.Add($cb)
    }
    if ($lb.Items.Count) { $lb.SelectedIndex = 0 }
    $side = New-Object Windows.Controls.StackPanel; $side.Margin='8,0,0,0'; $side.VerticalAlignment='Top'
    $bUp = New-Object Windows.Controls.Button; $bUp.Content='Up'; $bUp.Padding='14,4'; $bUp.Margin='0,0,0,6'
    $bDn = New-Object Windows.Controls.Button; $bDn.Content='Down'; $bDn.Padding='14,4'
    [void]$side.Children.Add($bUp); [void]$side.Children.Add($bDn)
    [Windows.Controls.Grid]::SetColumn($side,1); [void]$mid.Children.Add($side)
    [Windows.Controls.Grid]::SetRow($mid,1); [void]$g.Children.Add($mid)
    $bUp.add_Click({ $i=$lb.SelectedIndex; if ($i -gt 0) { $it=$lb.Items[$i]; $lb.Items.RemoveAt($i); $lb.Items.Insert($i-1,$it); $lb.SelectedIndex=$i-1 } }.GetNewClosure())
    $bDn.add_Click({ $i=$lb.SelectedIndex; if ($i -ge 0 -and $i -lt $lb.Items.Count-1) { $it=$lb.Items[$i]; $lb.Items.RemoveAt($i); $lb.Items.Insert($i+1,$it); $lb.SelectedIndex=$i+1 } }.GetNewClosure())

    $bar = New-Object Windows.Controls.StackPanel; $bar.Orientation='Horizontal'; $bar.HorizontalAlignment='Right'; $bar.Margin='0,10,0,0'
    $ok = New-Object Windows.Controls.Button; $ok.Content='Use selected (in order)'; $ok.Padding='16,4'; $ok.Margin='0,0,8,0'; $ok.IsDefault=$true; try { $ok.Style=$script:Win.FindResource('PbAccentButton') } catch {}
    $cn = New-Object Windows.Controls.Button; $cn.Content='Cancel'; $cn.Padding='14,4'; $cn.IsCancel=$true
    [void]$bar.Children.Add($ok); [void]$bar.Children.Add($cn)
    [Windows.Controls.Grid]::SetRow($bar,2); [void]$g.Children.Add($bar)
    $box = @{ Paths = $null }
    $ok.add_Click({
        $sel = New-Object System.Collections.Generic.List[string]
        foreach ($it in $lb.Items) { if ($it.IsChecked) { $sel.Add($it.Tag.FullName) } }
        if ($sel.Count -eq 0) { [Windows.MessageBox]::Show('Tick at least one MSI to include.','Nothing selected','OK','Information') | Out-Null; return }
        $box.Paths = $sel.ToArray(); $win.DialogResult = $true
    }.GetNewClosure())
    $win.Content = $g
    Set-PBDialogChrome -Window $win -Glyph 'E7B8' -Title 'Bundled MSIs - choose and order' -Subtitle $WrapperName
    if ($win.ShowDialog()) { return $box.Paths }
    return $null
}

# Wrapper EXE -> MSI: static check (no install run); extract the bundled MSI with 7-Zip if present and switch
# the package to MSI+MST. Heavily warned, because a wrapper often does more than just launch the MSI.
# Check a wrapper EXE for a bundled MSI and (opt-in) extract it. Reusable for a lone EXE (replaces the whole
# source) and for ONE EXE in a multi-installer chain (-ReplaceInChain swaps just that installer). $StatusLabel is
# any TextBlock to report into (the single-EXE panel's label, or a per-row label); may be $null.
function Invoke-BundledMsiCheck {
    param([Parameter(Mandatory)]$Exe, [switch]$ReplaceInChain, $StatusLabel)
    $st = { param($t,$c='#B7BEC8') if ($StatusLabel) { $StatusLabel.Text="$t"; $StatusLabel.Foreground="$c" } }
    if (-not $Exe) { return }
    if (-not (Get-Command Test-ExeBundlesMsi -ErrorAction SilentlyContinue)) { & $st 'Bundled-MSI module not loaded.' '#F48771'; return }
    & $st 'Checking the installer (no install is run)...' '#A0A8B4'
    try { (Get-PBMainWindow).Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch {}
    $tool  = Get-ArchiveTool
    $found = if ($tool) { @(Find-BundledMsi -ExePath $Exe.FullName) } else { @() }
    if ($found.Count -gt 0) {
        $multi   = $found.Count -gt 1
        $listTxt = ($found | Sort-Object Size -Descending | ForEach-Object { "   $($_.Name)  ($([math]::Round($_.Size/1MB,1)) MB)" }) -join "`n"
        $ans = [Windows.MessageBox]::Show(
            "'$($Exe.Name)' bundles $($found.Count) MSI$(if($multi){'s'}):`n$listTxt`n`nExtract $(if($multi){'them'}else{'it'}) (no install is run)$(if($multi){' and choose which to include + the INSTALL ORDER' }else{' and build a clean MSI + MST package instead of the EXE'})?`n`nWARNING: a wrapper often ALSO installs prerequisites, sets registry, or runs custom actions that the bare MSI(s) will NOT. Only do this if the EXE simply launches the MSI(s) - then TEST install AND uninstall.",
            'Bundled MSI found', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { & $st "Found $($found.Count) bundled MSI(s) (not extracted)." '#DCDCAA'; return }
        $dest = Get-WorkPath ('BundledMsi\' + [IO.Path]::GetFileNameWithoutExtension($Exe.Name))
        try { Get-ChildItem -LiteralPath $dest -File -EA SilentlyContinue | Remove-Item -Force -EA SilentlyContinue } catch {}
        $msis = @(Expand-BundledMsi -ExePath $Exe.FullName -DestDir $dest)
        if (-not $msis.Count) { & $st 'Extraction produced no MSI (compressed in a way 7-Zip cannot open, or encrypted). Keep the EXE.' '#F48771'; return }
        # Which MSI path(s) to use: 1 -> use it; many -> picker (order + prune unticked).
        $usePaths = @()
        if ($msis.Count -eq 1) { $usePaths = @($msis[0].FullName) }
        else {
            $picked = @(Show-BundledMsiPickerDialog -Msis $msis -WrapperName $Exe.Name)
            if (-not $picked -or $picked.Count -eq 0) { & $st "Extracted $($msis.Count) MSIs to $dest, but none were selected." '#DCDCAA'; return }
            $keep = @{}; foreach ($pp in $picked) { $keep[$pp] = $true }
            foreach ($m in $msis) { if (-not $keep.ContainsKey($m.FullName)) { try { Remove-Item -LiteralPath $m.FullName -Force -EA SilentlyContinue } catch {} } }
            $usePaths = $picked
        }
        if ($ReplaceInChain) {
            Replace-InstallerInChain -OldFullName $Exe.FullName -NewPaths $usePaths   # swap just this EXE in the chain
        } else {
            $script:State.ChosenInstallers = @(); Add-ManualInstallers -Paths $usePaths   # lone EXE: replace whole source
        }
        $verb = if (@($usePaths).Count -gt 1) { "$(@($usePaths).Count) MSIs (install in order, uninstall reverse, one MST each)" } else { "$([IO.Path]::GetFileName($usePaths[0]))" }
        $script:State.SourceNotes = @("$verb was EXTRACTED from the wrapper '$($Exe.Name)'. A wrapper may also install prerequisites / set registry / run custom actions the bare MSI(s) do NOT - TEST install AND uninstall before shipping.")
        & $st "Extracted -> $verb. Review the warning before shipping." '#6A9955'
        Populate-Step2
        return
    }
    # No 7-Zip, or nothing listed: static signature scan for an honest verdict.
    $scan = Test-ExeBundlesMsi -ExePath $Exe.FullName
    if ($scan.HasEmbeddedMsi -and -not $tool) { & $st "An MSI appears embedded, but 7-Zip isn't available to extract it. Install 7-Zip (or drop 7za.exe in Lib\)." '#DCDCAA' }
    elseif (-not $tool) { & $st "7-Zip isn't installed - only a limited static check ran ($($scan.Reason)). It CANNOT see an MSI in a PE resource (e.g. SentinelOne). Install 7-Zip (or 7za.exe in Lib\) and retry." '#DCDCAA' }
    else { & $st "$($scan.Reason)" $(if ($scan.HasEmbeddedMsi) { '#DCDCAA' } else { '#A0A8B4' }) }
}
$BtnBundledMsi.add_Click({
    $exe = @($script:State.ChosenInstallers) | Where-Object { $_.Extension -and $_.Extension.ToLower() -eq '.exe' } | Select-Object -First 1
    if ($exe) { Invoke-BundledMsiCheck -Exe $exe -StatusLabel $LblBundled }
})
# Capture a machine snapshot on a BACKGROUND runspace (the whole-system scan takes minutes - running it on the UI
# thread would freeze the window into "Not Responding"). $OnDone (a scriptblock) is invoked back ON the UI thread
# with ($snapshot, $errorText) when finished. Mirrors Start-PublishJob's runspace+DispatcherTimer pattern.
function Start-SnapshotJob {
    param([Parameter(Mandatory)][scriptblock]$OnDone)
    $box = [hashtable]::Synchronized(@{ Done = $false; Snap = $null; Error = $null })
    $jobArgs = @{ engine = $script:PBEngineSource; root = $root; box = $box }
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $psi = [PowerShell]::Create(); $psi.Runspace = $rs
    [void]$psi.AddScript({
        param($a)
        try {
            if ($a.engine) { . ([scriptblock]::Create($a.engine)) } else { . "$($a.root)\Core.ps1"; . "$($a.root)\Snapshot.ps1" }
            $a.box.Snap = Get-MachineSnapshot
        } catch { $a.box.Error = "$($_.Exception.Message)" }
        finally { $a.box.Done = $true }
    }).AddArgument($jobArgs)
    $h = $psi.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.add_Tick({
        if (-not $box.Done) { return }
        $timer.Stop()
        try { $psi.EndInvoke($h) } catch {}
        try { $psi.Dispose(); $rs.Close(); $rs.Dispose() } catch {}
        & $OnDone $box.Snap $box.Error
    }.GetNewClosure())
    $timer.Start()
}

# ANALYZE in the BACKGROUND: capture the after-snapshot AND run the whole heavy diff (compare + raw diffs + report +
# change set + shortcuts + leftovers + cleanups) off the UI thread, so the window never freezes. The OnDone callback
# then only assigns results + renders (fast). Every function called here lives in the engine (background-visible).
function Start-SnapshotAnalyzeJob {
    param([Parameter(Mandatory)]$Before, [string]$AppVendor, [string]$AppName, [Parameter(Mandatory)][scriptblock]$OnDone)
    $box = [hashtable]::Synchronized(@{ Done = $false; Result = $null; Error = $null })
    $jobArgs = @{ engine = $script:PBEngineSource; root = $root; box = $box; before = $Before; vendor = $AppVendor; app = $AppName }
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $psi = [PowerShell]::Create(); $psi.Runspace = $rs
    [void]$psi.AddScript({
        param($a)
        try {
            if ($a.engine) { . ([scriptblock]::Create($a.engine)) } else { . "$($a.root)\Core.ps1"; . "$($a.root)\Snapshot.ps1"; . "$($a.root)\Screenshots.ps1" }
            $before = $a.before; $vend = $a.vendor; $app = $a.app
            $after = Get-MachineSnapshot
            $diff  = Compare-MachineSnapshot -Before $before -After $after -AppVendor $vend -AppName $app
            $appTokens = if (Get-Command Get-SnapshotAppTokens -EA SilentlyContinue) { Get-SnapshotAppTokens -Vendor $vend -AppName $app -Diff $diff }
                         elseif (Get-Command Get-AppMatchTokens -EA SilentlyContinue) { Get-AppMatchTokens -Vendor $vend -AppName $app }
                         else { @($vend, $app | Where-Object { $_ } | ForEach-Object { $_.ToLower() }) }
            $fileDiff = Get-SnapshotRawDiff -Before $before -After $after -Kind Files    -AppTokens $appTokens
            $regDiff  = Get-SnapshotRawDiff -Before $before -After $after -Kind Registry -AppTokens $appTokens
            $un = Get-UninstallFromSnapshotDiff -Diff $diff -AppName $app
            $envChanges = @(Get-EnvDiff -Before $before -After $after)
            $reportText = Get-SnapshotReportText -Diff $diff -FileDiff $fileDiff -RegDiff $regDiff -EnvChanges $envChanges -Un $un -AppTokens $appTokens
            $changeSet = if (Get-Command New-SnapshotChangeSet -EA SilentlyContinue) { New-SnapshotChangeSet -Diff $diff -FileDiff $fileDiff -RegDiff $regDiff -EnvChanges $envChanges -AppName ("$vend $app".Trim()) } else { $null }
            $shortcuts = if (Get-Command Get-AppStartMenuShortcuts -EA SilentlyContinue) { @(Get-AppStartMenuShortcuts -Diff $diff -AppTokens $appTokens) } else { @() }
            $hkcu      = if (Get-Command Get-SnapshotHkcuValues -EA SilentlyContinue) { @(Get-SnapshotHkcuValues -RegDiff $regDiff -AppTokens $appTokens) } else { @() }
            $userFiles = if (Get-Command Get-SnapshotUserFiles -EA SilentlyContinue) { @(Get-SnapshotUserFiles -FileDiff $fileDiff -AppTokens $appTokens) } else { @() }
            $leftover  = if (Get-Command Get-LeftoverCandidates -EA SilentlyContinue) { Get-LeftoverCandidates -Diff $diff -FileDiff $fileDiff -RegDiff $regDiff -Vendor "$vend" -App "$app" } else { $null }
            $cleanups  = if (Get-Command Get-SnapshotCleanups -EA SilentlyContinue) { @(Get-SnapshotCleanups -Diff $diff -AppName $app -FileDiff $fileDiff -EnvChanges $envChanges) } else { @() }
            $a.box.Result = @{ After=$after; Diff=$diff; AppTokens=$appTokens; FileDiff=$fileDiff; RegDiff=$regDiff; Un=$un; EnvChanges=$envChanges
                               ReportText=$reportText; ChangeSet=$changeSet; Shortcuts=$shortcuts; Hkcu=$hkcu; UserFiles=$userFiles; LeftoverCandidates=$leftover; Cleanups=$cleanups }
        } catch { $a.box.Error = "$($_.Exception.Message)" }
        finally { $a.box.Done = $true }
    }).AddArgument($jobArgs)
    $h = $psi.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(400)
    $timer.add_Tick({
        if (-not $box.Done) { return }
        $timer.Stop()
        try { $psi.EndInvoke($h) } catch {}
        try { $psi.Dispose(); $rs.Close(); $rs.Dispose() } catch {}
        & $OnDone $box.Result $box.Error
    }.GetNewClosure())
    $timer.Start()
}

# Minimal single-line text input. Returns the typed string, or $null on cancel.
function Show-InputDialog {
    param([string]$Title = 'Add', [string]$Prompt = 'Enter value:', [string]$Default = '')
    $win = New-Object Windows.Window
    $win.Title = $Title; $win.Width = 640; $win.SizeToContent = 'Height'; $win.WindowStartupLocation = 'CenterOwner'
    try { $win.Owner = $script:Win } catch {}
    $win.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x18,0x1A,0x1F)))
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $win }
    $g = New-Object Windows.Controls.StackPanel; $g.Margin = '14'
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $Prompt; $t.Foreground='#E7E9ED'; $t.TextWrapping='Wrap'; $t.Margin='0,0,0,8'; [void]$g.Children.Add($t)
    $tb = New-Object Windows.Controls.TextBox; $tb.Text = $Default; $tb.FontFamily='Consolas'; $tb.FontSize=12; $tb.MinWidth=580; [void]$g.Children.Add($tb)
    $bar = New-Object Windows.Controls.StackPanel; $bar.Orientation='Horizontal'; $bar.HorizontalAlignment='Right'; $bar.Margin='0,12,0,0'
    $ok = New-Object Windows.Controls.Button; $ok.Content='Add'; $ok.Padding='16,4'; $ok.Margin='0,0,8,0'; $ok.IsDefault=$true; try { $ok.Style=$script:Win.FindResource('PbAccentButton') } catch {}
    $cn = New-Object Windows.Controls.Button; $cn.Content='Cancel'; $cn.Padding='14,4'; $cn.IsCancel=$true
    [void]$bar.Children.Add($ok); [void]$bar.Children.Add($cn); [void]$g.Children.Add($bar)
    $box = @{ Val = $null }
    $ok.add_Click({ $box.Val = $tb.Text; $win.DialogResult = $true }.GetNewClosure())
    $win.Content = $g
    Set-PBDialogChrome -Window $win -Glyph 'E70F'
    if ($win.ShowDialog()) { return $box.Val }
    return $null
}

# Pick one of the captured certificates to open in the Windows cert viewer. Returns the chosen diff item, or $null.
function Show-CertPickerDialog {
    param([object[]]$Certs)
    $win = New-Object Windows.Window
    $win.Title = 'Open a captured certificate'; $win.Width = 660; $win.Height = 380; $win.WindowStartupLocation = 'CenterOwner'
    try { $win.Owner = $script:Win } catch {}
    $win.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x18,0x1A,0x1F)))
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $win }
    $g = New-Object Windows.Controls.Grid; $g.Margin = '14'
    foreach ($h in 'Auto','*','Auto') { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = $h; [void]$g.RowDefinitions.Add($rd) }
    $hdr = New-Object Windows.Controls.TextBlock; $hdr.Text = 'Select a certificate the installer added, then Open to view it directly:'; $hdr.Foreground='#E7E9ED'; $hdr.TextWrapping='Wrap'; $hdr.Margin='0,0,0,8'
    [Windows.Controls.Grid]::SetRow($hdr,0); [void]$g.Children.Add($hdr)
    $lb = New-Object Windows.Controls.ListBox; $lb.Background='#15171B'; $lb.Foreground='#E7E9ED'; $lb.FontFamily='Consolas'; $lb.FontSize=12; $lb.DisplayMemberPath='Display'
    foreach ($c in $Certs) { [void]$lb.Items.Add([pscustomobject]@{ Display = "$($c.Info.Subject)   ($($c.Info.Store))   $(($c.Id -split '\\')[-1])"; Cert = $c }) }
    if ($lb.Items.Count) { $lb.SelectedIndex = 0 }
    [Windows.Controls.Grid]::SetRow($lb,1); [void]$g.Children.Add($lb)
    $bar = New-Object Windows.Controls.StackPanel; $bar.Orientation='Horizontal'; $bar.HorizontalAlignment='Right'; $bar.Margin='0,10,0,0'
    $bOpen = New-Object Windows.Controls.Button; $bOpen.Content='Open'; $bOpen.Padding='16,4'; $bOpen.Margin='0,0,8,0'; try { $bOpen.Style = $script:Win.FindResource('PbAccentButton') } catch {}
    $bC = New-Object Windows.Controls.Button; $bC.Content='Cancel'; $bC.Padding='14,4'; $bC.IsCancel=$true
    [void]$bar.Children.Add($bOpen); [void]$bar.Children.Add($bC)
    [Windows.Controls.Grid]::SetRow($bar,2); [void]$g.Children.Add($bar)
    $box = @{ Pick = $null }
    $bOpen.add_Click({ if ($lb.SelectedItem) { $box.Pick = $lb.SelectedItem.Cert; $win.DialogResult = $true } }.GetNewClosure())
    $win.Content = $g
    Set-PBDialogChrome -Window $win -Glyph 'E72E'
    if ($win.ShowDialog()) { return $box.Pick }
    return $null
}

# Simple read-only scrollable text viewer (probe help output, captured logs, etc.). Modal, themed.
function Show-TextDialog {
    param([string]$Title = 'Output', [string]$Text = '')
    $win = New-Object Windows.Window
    $win.Title = $Title; $win.Width = 760; $win.Height = 520; $win.WindowStartupLocation = 'CenterOwner'
    try { $win.Owner = $script:Win } catch {}
    $win.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x18,0x1A,0x1F)))
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $win }
    $g = New-Object Windows.Controls.Grid; $g.Margin = '14'
    foreach ($h in '*','Auto') { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = $h; [void]$g.RowDefinitions.Add($rd) }
    $tb = New-Object Windows.Controls.TextBox
    $tb.Text = "$Text"; $tb.IsReadOnly = $true; $tb.TextWrapping = 'NoWrap'; $tb.AcceptsReturn = $true
    $tb.VerticalScrollBarVisibility = 'Auto'; $tb.HorizontalScrollBarVisibility = 'Auto'
    $tb.FontFamily = 'Consolas'; $tb.FontSize = 12; $tb.Background = '#0C0C0C'; $tb.Foreground = '#D7D7D7'
    [Windows.Controls.Grid]::SetRow($tb,0); [void]$g.Children.Add($tb)
    $bar = New-Object Windows.Controls.StackPanel; $bar.Orientation='Horizontal'; $bar.HorizontalAlignment='Right'; $bar.Margin='0,10,0,0'
    $bCopy = New-Object Windows.Controls.Button; $bCopy.Content='Copy'; $bCopy.Padding='14,4'; $bCopy.Margin='0,0,8,0'
    $bCopy.add_Click({ try { [Windows.Clipboard]::SetText($tb.Text) } catch {} }.GetNewClosure())
    $bClose = New-Object Windows.Controls.Button; $bClose.Content='Close'; $bClose.Padding='14,4'; $bClose.IsCancel=$true
    [void]$bar.Children.Add($bCopy); [void]$bar.Children.Add($bClose)
    [Windows.Controls.Grid]::SetRow($bar,1); [void]$g.Children.Add($bar)
    $win.Content = $g; Set-PBDialogChrome -Window $win -Glyph 'E7C3'; $win.ShowDialog() | Out-Null
}

# Re-render the snapshot report into the read-only box from the live filter controls. A real function (not a
# closure) so the search/category handlers avoid the per-closure scope traps. When a fresh diff is in memory
# ($Ctx.Diff) it re-runs Get-SnapshotReportText with -Search/-OnlyCat (structure-aware: section headers appear
# only when they have matches). When only a SAVED report text is loaded (re-opened package, no diff objects),
# it falls back to a plain case-insensitive line filter so the box still responds.
function Update-SnapshotReportView {
    param($Ctx, $SearchBox, $CatBox, $ReportBox, $CountLabel)
    $search = if ($SearchBox) { "$($SearchBox.Text)".Trim() } else { '' }
    $cat = ''
    if ($CatBox -and $CatBox.SelectedItem -and $CatBox.SelectedItem.Tag) { $cat = "$($CatBox.SelectedItem.Tag)" }
    if ($Ctx.Diff) {
        $ReportBox.Text = Get-SnapshotReportText -Diff $Ctx.Diff -FileDiff $Ctx.FileDiff -RegDiff $Ctx.RegDiff `
                            -EnvChanges $Ctx.EnvChanges -Un $Ctx.Un -AppTokens $Ctx.AppTokens -Search $search -OnlyCat $cat
    } elseif ("$($Ctx.ReportText)".Trim()) {
        $full = "$($Ctx.ReportText)"
        if (-not $search) { $ReportBox.Text = $full }
        else {
            $lines = @($full -split "`r?`n" | Where-Object { $_.IndexOf($search, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
            $ReportBox.Text = if ($lines.Count) { ($lines -join "`r`n") } else { "(no lines contain '$search')" }
        }
    }
    if ($CountLabel) {
        $shown = if ($search -or $cat) { 'filtered' } else { 'all' }
        $CountLabel.Text = if ($search -or $cat) { "Showing $shown view" } else { '' }
    }
}

# Force a WPF window minimized / restored via Win32 ShowWindow. WPF's WindowState='Minimized' does NOT reliably
# minimize the OWNER of a modal dialog (observed: the analyze dialog minimized but the main window stayed up), so for
# the screenshot capture - where every tool window MUST be off-screen - we drive ShowWindow directly on the HWND.
# Cmd 6=SW_MINIMIZE, 9=SW_RESTORE, 11=SW_FORCEMINIMIZE (works even across the modal-owner relationship / busy thread).
if (-not ('PB.Win' -as [type])) {
    try { Add-Type -Namespace PB -Name Win -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);' -ErrorAction SilentlyContinue } catch {}
}
# Builders for CODE-BUILT windows (the analyzer), so they look like the XAML pages: glyph + text buttons, and the
# small uppercase caption that names a group of controls.
function New-PBGlyphButton {
    param([string]$Glyph, [string]$Text, [string]$Padding = '12,5', [string]$Margin = '0,0,8,0', [string]$ToolTip)
    $b = New-Object Windows.Controls.Button; $b.Padding = $Padding; $b.Margin = $Margin; $b.VerticalAlignment = 'Center'
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    if ($Glyph) {
        $g = New-Object Windows.Controls.TextBlock; $g.Text = [string][char][Convert]::ToInt32($Glyph, 16)
        $g.FontFamily = 'Segoe MDL2 Assets'; $g.FontSize = 13; $g.VerticalAlignment = 'Center'; $g.Margin = '0,1,7,0'
        [void]$sp.Children.Add($g)
    }
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $Text; $t.VerticalAlignment = 'Center'; [void]$sp.Children.Add($t)
    $b.Content = $sp
    if ($ToolTip) { $b.ToolTip = $ToolTip }
    return $b
}
# Give ANY dialog the shell's header band (glyph + title) above its existing content, the shell's ground and
# type, and an accent primary button. Works on XAML-loaded and code-built windows alike: the current Content is
# re-parented under a header row, names stay resolvable. Fixed-height windows grow by the band's height.
function Set-PBDialogChrome {
    param([Parameter(Mandatory)]$Window, [string]$Glyph = 'E7C3', [string]$Title = '', [string]$PrimaryName = '', [string]$Subtitle = '')
    try {
        $Window.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x18,0x1A,0x1F)))
        $Window.FontFamily = 'Segoe UI'; if (-not $Window.FontSize -or $Window.FontSize -lt 13) { $Window.FontSize = 13 }
        if (-not $Title) { $Title = "$($Window.Title)" }
        $old = $Window.Content; $Window.Content = $null
        $g = New-Object Windows.Controls.Grid
        foreach ($h in 'Auto','*') { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = $h; [void]$g.RowDefinitions.Add($rd) }
        $band = New-Object Windows.Controls.Border; $band.Background = '#1F232B'; $band.BorderBrush = '#2E3340'; $band.BorderThickness = '0,0,0,1'; $band.Padding = '16,9'
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        $gl = New-Object Windows.Controls.TextBlock; $gl.Text = [string][char][Convert]::ToInt32($Glyph, 16); $gl.FontFamily = 'Segoe MDL2 Assets'; $gl.FontSize = 14; $gl.Foreground = '#56C8D6'; $gl.VerticalAlignment = 'Center'; $gl.Margin = '0,1,9,0'
        $tt = New-Object Windows.Controls.TextBlock; $tt.Text = $Title; $tt.FontSize = 14; $tt.FontWeight = 'SemiBold'; $tt.Foreground = '#F2F4F7'; $tt.VerticalAlignment = 'Center'
        [void]$sp.Children.Add($gl); [void]$sp.Children.Add($tt)
        if ($Subtitle) { $st = New-Object Windows.Controls.TextBlock; $st.Text = $Subtitle; $st.FontSize = 11.5; $st.Foreground = '#A0A8B4'; $st.VerticalAlignment = 'Center'; $st.Margin = '14,1,0,0'; $st.TextTrimming = 'CharacterEllipsis'; [void]$sp.Children.Add($st) }
        $band.Child = $sp
        [Windows.Controls.Grid]::SetRow($band, 0); [void]$g.Children.Add($band)
        if ($old) { [Windows.Controls.Grid]::SetRow($old, 1); [void]$g.Children.Add($old) }
        $Window.Content = $g
        if ($Window.SizeToContent -eq 'Manual' -and $Window.Height -gt 0) { $Window.Height = $Window.Height + 42 }
        if ($PrimaryName) { $pb = $Window.FindName($PrimaryName); if ($pb -is [Windows.Controls.Button]) { try { $pb.Style = $script:Win.FindResource('PbAccentButton') } catch {} } }
        # Chrome is applied immediately before ShowDialog, so this is the one place that knows a modal is coming:
        # take the busy card down for it and bring it back when the dialog closes.
        if (Get-Command Suspend-PBBusy -ErrorAction SilentlyContinue) {
            Suspend-PBBusy
            $Window.Add_Closed({ try { Resume-PBBusy } catch {} })
        }
    } catch { Write-Log "Dialog chrome not applied ($Title): $($_.Exception.Message)" Warning }
}
function New-PBCaption {
    param([string]$Text, [string]$Margin = '0,0,0,6')
    $c = New-Object Windows.Controls.TextBlock; $c.Text = $Text.ToUpper(); $c.FontSize = 10; $c.FontWeight = 'SemiBold'
    $c.Foreground = '#A0A8B4'; $c.Margin = $Margin
    return $c
}
# A confirmation that carries a LIST (what will be replaced, what was found) reads as a wide, monospace,
# scrollable text with the question under it and Yes / No - not a cramped MessageBox. Returns $true on Yes.
function Show-ConfirmTextDialog {
    param([string]$Title = 'Confirm', [string]$Text = '', [string]$Question = 'Proceed?', [string]$YesText = 'Yes', [string]$Glyph = 'E7BA')
    $win = New-Object Windows.Window
    $win.Title = $Title; $win.Width = 880; $win.Height = 480; $win.MinWidth = 520; $win.MinHeight = 260; $win.WindowStartupLocation = 'CenterOwner'
    try { $win.Owner = $script:Win } catch {}
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $win }
    $g = New-Object Windows.Controls.Grid; $g.Margin = '14'
    foreach ($h in '*','Auto','Auto') { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = $h; [void]$g.RowDefinitions.Add($rd) }
    $tb = New-Object Windows.Controls.TextBox
    $tb.Text = "$Text"; $tb.IsReadOnly = $true; $tb.TextWrapping = 'NoWrap'; $tb.AcceptsReturn = $true
    $tb.VerticalScrollBarVisibility = 'Auto'; $tb.HorizontalScrollBarVisibility = 'Auto'
    $tb.FontFamily = 'Consolas'; $tb.FontSize = 12; $tb.Background = '#0C0C0C'; $tb.Foreground = '#D7D7D7'
    [Windows.Controls.Grid]::SetRow($tb,0); [void]$g.Children.Add($tb)
    $q = New-Object Windows.Controls.TextBlock; $q.Text = "$Question"; $q.Foreground = '#E7E9ED'; $q.FontWeight = 'SemiBold'; $q.Margin = '2,12,0,0'; $q.TextWrapping = 'Wrap'
    [Windows.Controls.Grid]::SetRow($q,1); [void]$g.Children.Add($q)
    $bar = New-Object Windows.Controls.StackPanel; $bar.Orientation='Horizontal'; $bar.HorizontalAlignment='Right'; $bar.Margin='0,12,0,0'
    $script:__confirmResult = $false
    $bNo = New-Object Windows.Controls.Button; $bNo.Content='Cancel'; $bNo.Padding='14,5'; $bNo.Margin='0,0,8,0'; $bNo.IsCancel=$true; $bNo.MinWidth = 96
    $bNo.add_Click({ $script:__confirmResult = $false; $win.DialogResult = $false; $win.Close() }.GetNewClosure())
    $bYes = New-Object Windows.Controls.Button; $bYes.Content=$YesText; $bYes.Padding='16,5'; $bYes.MinWidth = 120
    try { $bYes.Style = $script:Win.FindResource('PbAccentButton') } catch {}
    $bYes.add_Click({ $script:__confirmResult = $true; $win.DialogResult = $true; $win.Close() }.GetNewClosure())
    [void]$bar.Children.Add($bNo); [void]$bar.Children.Add($bYes)
    [Windows.Controls.Grid]::SetRow($bar,2); [void]$g.Children.Add($bar)
    $win.Content = $g
    Set-PBDialogChrome -Window $win -Glyph $Glyph
    $win.ShowDialog() | Out-Null
    return [bool]$script:__confirmResult
}

# PRELIVE MIRROR GUARD. Creating / updating content runs robocopy /MIR, which REPLACES and PRUNES whatever is on the
# prelive share. The old check sat in a try/catch{} that swallowed its own failure and then mirrored anyway - a guard
# that fails OPEN is worse than none. This one never does: if the share cannot be read (no config, no rights, share
# down) it says so and asks. $true = go ahead.
function Confirm-PreliveMirror {
    param([string]$PackageName, [string]$Action = 'This')
    $ask = { param($t, $c) ([Windows.MessageBox]::Show($t, $c, 'YesNo', 'Warning') -eq 'Yes') }
    $dest = ''
    try { $cfg = Get-SccmConfig; $dest = Join-Path (Join-Path $cfg.ContentShare $PackageName) 'Content' }
    catch {
        Write-Log "Prelive content check could not run: $($_.Exception.Message)" Warning
        return (& $ask "The prelive content share could not be read from settings:`n$($_.Exception.Message)`n`n$Action will MIRROR (replace and prune) whatever is already there. Continue anyway?" 'Prelive content could not be checked')
    }
    if (Test-Path -LiteralPath $dest) {
        return (& $ask "Content for '$PackageName' already exists in PRELIVE:`n$dest`n`n$Action will MIRROR (replace) it. Continue?" 'Prelive content already exists')
    }
    # Test-Path says no - but "no" and "I am not allowed to look" are the same answer here. If the share root itself
    # cannot be opened we do NOT know, so offer the sign-in (this is an explicit click) and then say what we found.
    $root = "$($cfg.ContentShare)"
    if ($root -and -not (Test-Path -LiteralPath $root)) {
        if ((Get-Command Connect-PBShare -EA SilentlyContinue) -and (Connect-PBShare -Path $root -Purpose 'the prelive content share' -AllowPrompt)) {
            if (Test-Path -LiteralPath $dest) {
                return (& $ask "Content for '$PackageName' already exists in PRELIVE:`n$dest`n`n$Action will MIRROR (replace) it. Continue?" 'Prelive content already exists')
            }
            return $true
        }
        Write-Log "Prelive content share not reachable: $root - could not check for existing content." Warning
        return (& $ask "The prelive content share cannot be opened from this machine:`n$root`n`nSo it is unknown whether content for '$PackageName' is already there. $Action will MIRROR (replace and prune) it if it is. Continue anyway?" 'Prelive content could not be checked')
    }
    return $true
}

# The "no predecessor" dialog: the diagnosis, then the ways on. Returns 'signin' | 'browse' | 'skip'.
function Show-PredecessorMissingDialog {
    param([string]$Body, [bool]$CanSignIn)
    $win = New-Object Windows.Window
    $win.Title = 'No predecessor found'; $win.Width = 760; $win.SizeToContent = 'Height'; $win.MinHeight = 240
    $win.WindowStartupLocation = 'CenterOwner'; try { $win.Owner = $script:Win } catch {}
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $win }
    $g = New-Object Windows.Controls.Grid; $g.Margin = '16,14,16,14'
    foreach ($h in 'Auto','Auto','Auto') { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = $h; [void]$g.RowDefinitions.Add($rd) }
    $tb = New-Object Windows.Controls.TextBox
    $tb.Text = "$Body"; $tb.IsReadOnly = $true; $tb.TextWrapping = 'Wrap'; $tb.AcceptsReturn = $true; $tb.BorderThickness = '0'
    $tb.Background = 'Transparent'; $tb.Foreground = '#E7E9ED'; $tb.FontSize = 12.5; $tb.MaxHeight = 320; $tb.VerticalScrollBarVisibility = 'Auto'
    [Windows.Controls.Grid]::SetRow($tb,0); [void]$g.Children.Add($tb)
    $hint = New-Object Windows.Controls.TextBlock
    $hint.Text = 'Picking it yourself accepts either form - the package folder, any file inside it, or the package .zip (a zip is unpacked for you).'
    $hint.Foreground = '#A0A8B4'; $hint.FontSize = 11.5; $hint.TextWrapping = 'Wrap'; $hint.Margin = '2,12,0,0'
    [Windows.Controls.Grid]::SetRow($hint,1); [void]$g.Children.Add($hint)
    $bar = New-Object Windows.Controls.StackPanel; $bar.Orientation = 'Horizontal'; $bar.HorizontalAlignment = 'Right'; $bar.Margin = '0,14,0,0'
    $script:__predMissing = 'skip'
    $bSkip = New-Object Windows.Controls.Button; $bSkip.Content = 'Continue without a predecessor'; $bSkip.Padding = '14,5'; $bSkip.Margin = '0,0,8,0'; $bSkip.IsCancel = $true
    $bSkip.add_Click({ $script:__predMissing = 'skip'; $win.DialogResult = $false; $win.Close() }.GetNewClosure())
    [void]$bar.Children.Add($bSkip)
    if ($CanSignIn) {
        $bIn = New-Object Windows.Controls.Button; $bIn.Content = 'Sign in and search again'; $bIn.Padding = '14,5'; $bIn.Margin = '0,0,8,0'; $bIn.MinWidth = 150
        $bIn.add_Click({ $script:__predMissing = 'signin'; $win.DialogResult = $true; $win.Close() }.GetNewClosure())
        [void]$bar.Children.Add($bIn)
    }
    $bBrowse = New-Object Windows.Controls.Button; $bBrowse.Content = 'Select the package...'; $bBrowse.Padding = '16,5'; $bBrowse.MinWidth = 150; $bBrowse.IsDefault = $true
    try { $bBrowse.Style = $script:Win.FindResource('PbAccentButton') } catch {}
    $bBrowse.add_Click({ $script:__predMissing = 'browse'; $win.DialogResult = $true; $win.Close() }.GetNewClosure())
    [void]$bar.Children.Add($bBrowse)
    [Windows.Controls.Grid]::SetRow($bar,2); [void]$g.Children.Add($bar)
    $win.Content = $g
    Set-PBDialogChrome -Window $win -Glyph 'E721' -Title 'No predecessor found'
    $win.ShowDialog() | Out-Null
    return "$($script:__predMissing)"
}

# WHY WAS NO PREDECESSOR FOUND? Silence plus a browse prompt tells the packager nothing - they cannot tell a
# location they have no rights to from one that simply holds no earlier release. This walks the locations the
# search actually used and reports each one: not configured / cannot be opened (no rights, other domain) / open
# but nothing matching / open with near-misses (same app spelled differently). Returns
# @{ Lines=@(); CanSignIn=[bool]; Roots=@() } - CanSignIn drives the "Sign in and search again" button.
function Get-PredecessorSearchReport {
    param($Parsed)
    $lines = New-Object System.Collections.Generic.List[string]
    $roots = New-Object System.Collections.Generic.List[string]
    $canSignIn = $false
    foreach ($r in @((Get-Setting 'PredecessorPath'), (Get-Setting 'PredecessorPaths'))) { foreach ($p in @($r)) { if ("$p".Trim()) { [void]$roots.Add("$p") } } }
    # the request's own Predecessor\ folder (GPF/PAG: this is the primary source)
    $req = $script:State.GpfRequest
    if ($req -and "$($req.PredecessorPath)".Trim()) { [void]$roots.Insert(0, "$($req.PredecessorPath)") }
    elseif ($req) { [void]$lines.Add("The request folder '$(Split-Path "$($req.RequestPath)" -Leaf)' has no Predecessor\ folder.") }
    if (-not $roots.Count) { [void]$lines.Add('No predecessor location is configured (settings.json -> PredecessorPath).') }
    foreach ($root in $roots) {
        $isUnc = "$root" -match '^\\\\'
        if (-not (Test-Path -LiteralPath $root)) {
            if ($isUnc) { $canSignIn = $true; [void]$lines.Add("Cannot open  $root`r`n      This machine has no access to it - a different account (another domain: DOMAIN\user) may be needed.") }
            else { [void]$lines.Add("Does not exist  $root") }
            continue
        }
        $kids = @(); try { $kids = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop) } catch { $canSignIn = $true; [void]$lines.Add("Cannot read  $root`r`n      $($_.Exception.Message)"); continue }
        $zips  = @(try { Get-ChildItem -LiteralPath $root -Filter '*.zip' -File -ErrorAction SilentlyContinue } catch { @() })
        $names = @($kids | ForEach-Object { $_.Name }) + @($zips | ForEach-Object { $_.BaseName })
        # near misses: the same vendor OR the same app, so a spelling difference is visible instead of invisible
        $near = @($names | Where-Object { $_ -like "$($Parsed.Vendor)_*" -or $_ -like "*_$($Parsed.AppName)_*" -or $_ -like "*$($Parsed.AppName)*" } | Select-Object -First 5)
        if ($near.Count) { [void]$lines.Add("Nothing matching '$($Parsed.Vendor)_$($Parsed.AppName)_*' in  $root`r`n      Closest names there: $($near -join ', ')") }
        else { [void]$lines.Add("No earlier release in  $root   ($($names.Count) package(s) present)") }
    }
    return @{ Lines = @($lines); CanSignIn = $canSignIn; Roots = @($roots) }
}

# ONE selection that works out for itself what it was given (the packager should not have to say "folder" or "zip"
# up front). Accepts: a package .zip -> extracted; a package folder (Content\ / Deploy-Application.ps1 / *.ps1);
# a folder holding ONE package zip -> that zip; a folder holding several packages -> the best name match, else
# every entry offered. Returns @(candidate objects) or @() plus a reason in -Reason.
function Resolve-PredecessorSelection {
    param([string]$Path, $Parsed, [ref]$Reason)
    $mk = {
        param($name, $full)
        $norm = if (Get-Command Get-GpfPredecessorPackageName -EA SilentlyContinue) { Get-GpfPredecessorPackageName $name } else { $name }
        $pp = Parse-PackageName $norm
        $pv = try { [version]($pp.Version -replace '[^0-9.]','') } catch { $null }
        if (-not $pp.IsValid) { Write-Log "Selected predecessor '$name' does not parse as Vendor_App_Arch_Version-Rev_Lang - identity fields may need review." Warning }
        [pscustomobject]@{ Name=$norm; FullName=$full; Version=$pp.Version; Ver=$pv; Revision=$pp.Release
                           SameVersion=($pp.Version -eq "$($Parsed.Version)") }
    }
    $unzip = {
        param($zip)
        if (-not (Get-Command Expand-PredecessorZip -EA SilentlyContinue)) { return $zip }
        $ex = Expand-PredecessorZip -ZipPath $zip
        if ($ex) { return $ex }
        Write-Log "Predecessor zip '$(Split-Path $zip -Leaf)' has no deployment script inside - using the zip as-is." Warning
        return $zip
    }
    if (-not "$Path".Trim() -or -not (Test-Path -LiteralPath $Path)) { if ($Reason) { $Reason.Value = "That path does not exist: $Path" }; return @() }
    $item = Get-Item -LiteralPath $Path
    if (-not $item.PSIsContainer) {
        if ($item.Extension -notmatch '(?i)^\.zip$') { if ($Reason) { $Reason.Value = "'$($item.Name)' is not a package zip - pick the package FOLDER or its .zip." }; return @() }
        return @(& $mk $item.BaseName (& $unzip $item.FullName))
    }
    # a package folder? (its own script / Content folder / an MST + Files layout)
    $looksLikePkg = @('Content','Files','SupportFiles') | Where-Object { Test-Path (Join-Path $item.FullName $_) }
    $hasScript = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -Depth 2 -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '(?i)^(Invoke-AppDeployToolkit|Deploy-Application)\.ps1$' } | Select-Object -First 1)
    if ($looksLikePkg.Count -or $hasScript.Count) { return @(& $mk $item.Name $item.FullName) }
    # a folder of packages: sub-folders and/or zips - prefer the ones that match this app
    $subs = @(Get-ChildItem -LiteralPath $item.FullName -Directory -ErrorAction SilentlyContinue)
    $zips = @(Get-ChildItem -LiteralPath $item.FullName -Filter '*.zip' -File -ErrorAction SilentlyContinue)
    $entries = @()
    foreach ($s in $subs) { $entries += [pscustomobject]@{ Name=$s.Name; Full=$s.FullName; Zip=$false } }
    foreach ($z in $zips) { $entries += [pscustomobject]@{ Name=$z.BaseName; Full=$z.FullName; Zip=$true } }
    if (-not $entries.Count) { if ($Reason) { $Reason.Value = "'$($item.Name)' holds no package folder and no package zip." }; return @() }
    $match = @($entries | Where-Object { $_.Name -like "$($Parsed.Vendor)_$($Parsed.AppName)_*" -or $_.Name -like "*$($Parsed.AppName)*" })
    $use = if ($match.Count) { $match } else { $entries }
    if ($use.Count -gt 12) { $use = @($use | Sort-Object Name -Descending | Select-Object -First 12) }
    return @($use | ForEach-Object { & $mk $_.Name $(if ($_.Zip) { & $unzip $_.Full } else { $_.Full }) })
}

# SIGN IN TO A SHARE THAT CANNOT BE OPENED (Porsche: the predecessor location needs other credentials than the
# Incoming share, and it can live in ANOTHER DOMAIN - which Windows reports as "network path not found", not as
# "access denied"). ONE simple rule: the packager clicked something, the UNC path does not open -> ask. Drops a
# stale session to the same server first (Windows error 1219) and connects with New-PSDrive -Credential, so no
# password ever reaches a command line. A local or mapped path has nothing to sign in to and is just tested.
$script:PBSharePrompts = 0          # only for tests: how often a credential dialog was actually raised
$script:PBShareCancelled = @{}      # shares the packager said "no" to - cleared when they click something again
# NEVER ask while the window is only reacting to typing (the predecessor hint on LostFocus, any background scan):
# a modal credential prompt there steals the focus before the packager reaches the next field. (Porsche, 23.09.2026.)
$script:PBNoSharePrompt = $false
# Called at the start of every handler the packager starts, so one cancel does not silence the next attempt.
function Reset-PBShareAsk { $script:PBShareCancelled = @{} }
function Connect-PBShare {
    param([string]$Path, [string]$Purpose = 'this folder', [switch]$Retry, [switch]$AllowPrompt)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    # ASKING IS OPT-IN. Without -AllowPrompt this only reports whether the path opens. Only a handler the packager
    # STARTED (Fetch source, Find predecessor, Copy to Outgoing) passes it; everything that merely reacts to typing
    # or repaints the window can call this freely and will never produce a dialog.
    if (-not $AllowPrompt -or $script:PBNoSharePrompt) { return (Test-Path -LiteralPath $Path) }
    # -Retry = an ACCESS error already happened on this path (the share opens, a folder inside is denied): ask
    # again even though Test-Path says the root is there.
    if (-not $Retry -and (Test-Path -LiteralPath $Path)) { return $true }
    $m = [regex]::Match("$Path", '^(\\\\[^\\]+\\[^\\]+)'); if (-not $m.Success) { return $false }
    $share = $m.Groups[1].Value; $server = ($share -split '\\')[2]
    if ($script:PBShareCancelled.ContainsKey($share.ToLower())) { return (Test-Path -LiteralPath $Path) }
    # a stale session under another account blocks every new one (1219) - drop it and look again
    try { foreach ($line in @(net use 2>$null)) { if ($line -match ('(\\\\' + [regex]::Escape($server) + '\\\S+)')) { $null = net use $matches[1] /delete /y 2>$null } } } catch {}
    if (-not $Retry -and (Test-Path -LiteralPath $Path)) { return $true }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $cred = $null
        $script:PBSharePrompts++
        # the account often belongs to ANOTHER domain - say so, or people type their own user name and fail 3 times
        try { $cred = Get-Credential -Message "Sign in to $share to open $Purpose (attempt $attempt of 3).`r`nIf it belongs to another domain, enter the user name as DOMAIN\user." } catch {}
        if (-not $cred) { $script:PBShareCancelled[$share.ToLower()] = $true; Write-Log "Sign-in to $share cancelled - $Purpose not opened." Warning; return $false }
        try {
            $name = 'PBShare' + [guid]::NewGuid().ToString('N').Substring(0, 6)
            $null = New-PSDrive -Name $name -PSProvider FileSystem -Root $share -Credential $cred -Scope Global -ErrorAction Stop
            if (Test-Path -LiteralPath $Path) { Write-Log "Signed in to $share as $($cred.UserName)." Success; return $true }
            Write-Log "Signed in to $share, but $Path is still not there." Warning; return $false
        } catch {
            $why = "$($_.Exception.Message)"
            if ($why -match '1219|multiple connections|Mehrfachverbindungen') { try { foreach ($line in @(net use 2>$null)) { if ($line -match ('(\\\\' + [regex]::Escape($server) + '\\\S+)')) { $null = net use $matches[1] /delete /y 2>$null } } } catch {}; $attempt--; continue }
            Write-Log "Sign-in to $share as $($cred.UserName) failed: $why" Warning
        }
    }
    return $false
}
# ACCESS PROBLEM ANYWHERE = OFFER A SIGN-IN (Porsche, 22.09.2026: "wherever an access issue comes, copying or
# fetching, give the user a way to enter credentials"). Test-PBAccessError recognises the Windows / .NET wording
# (English and German); Invoke-PBWithShareAccess runs a step, and when it fails that way offers a sign-in to the
# share behind the path and runs the step ONCE more. Any other error is rethrown unchanged.
function Test-PBAccessError {
    param([string]$Message)
    # Includes the wording Windows uses for a share in ANOTHER DOMAIN, which it reports as "network path/name not
    # found" rather than "access denied" - a credential IS the fix there. Only ever consulted after an explicit
    # action already failed, so a needless prompt cannot reach someone who is just typing.
    return ("$Message" -match '(?i)access (is |to the path .* is )?denied|zugriff (auf den pfad .* )?verweigert|unauthorized|logon failure|anmeldefehler|1219|multiple connections|mehrfachverbindungen|user name or password|benutzername oder kennwort|network path was not found|netzwerkpfad wurde nicht gefunden|network name cannot be found|netzwerkname wurde nicht gefunden|cannot find path|0x80070005|0x8007052e|0x80070035|0x80070043|1326')
}
function Invoke-PBWithShareAccess {
    param([string]$Path, [string]$Purpose = 'this folder', [scriptblock]$Action, [switch]$AllowPrompt)
    try { & $Action }
    catch {
        $why = "$($_.Exception.Message)"
        if (-not $AllowPrompt -or $script:PBNoSharePrompt -or -not (Test-PBAccessError $why)) { throw }
        Write-Log "Access problem on $Purpose - $why. Offering a sign-in." Warning
        if (-not (Connect-PBShare -Path $Path -Purpose $Purpose -Retry -AllowPrompt)) { throw }
        & $Action
    }
}

# HIDE / SHOW THE MAIN WINDOW WITHOUT WPF NOTICING. The main window is shown with ShowDialog(), and in WPF
# Window.Hide() (or Visibility=Hidden) on a ShowDialog window ENDS that ShowDialog call. Nothing visible happens
# while a nested modal dialog (the snapshot window) is still up - but the moment that dialog closes ("Apply to
# package"), control falls back into a ShowDialog that has already returned, the script runs off its end and the
# process exits with no error at all (19.09.2026, GPF/MTB/PAG: "predecessor reuse + MSI snapshot + shortcut
# screenshots + Apply = tool closes"). The same thing left the hidden-but-alive PackageCompanion.exe processes
# found on the 18th. So the HWND is hidden and shown through Win32 directly; WPF's dialog loop never hears of it.
function Hide-PBMainWindow { param($Window)
    if (-not $Window) { return }
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($Window)).Handle
        if ($h -and $h -ne [IntPtr]::Zero -and ('PB.Win' -as [type])) { [void][PB.Win]::ShowWindow($h, 0) }   # SW_HIDE
    } catch {}
}
function Show-PBMainWindow { param($Window)
    if (-not $Window) { return }
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($Window)).Handle
        if ($h -and $h -ne [IntPtr]::Zero -and ('PB.Win' -as [type])) { [void][PB.Win]::ShowWindow($h, 5) }   # SW_SHOW
    } catch {}
}
function Set-PBWindowState {
    param($Window, [int]$Cmd)   # 11=SW_FORCEMINIMIZE, 6=SW_MINIMIZE, 9=SW_RESTORE
    if (-not $Window) { return }
    try {
        # WindowState AND Win32 ShowWindow - belt and suspenders. WindowState alone does NOT minimize the OWNER of a
        # modal dialog (that's why the main window stayed up); ShowWindow(SW_FORCEMINIMIZE) on the real HWND does.
        if ($Cmd -eq 9) { try { $Window.WindowState = 'Normal' } catch {} } else { try { $Window.WindowState = 'Minimized' } catch {} }
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($Window)
        $h = $helper.Handle
        if ((-not $h) -or $h -eq [IntPtr]::Zero) { try { $h = $helper.EnsureHandle() } catch {} }
        if ($h -and $h -ne [IntPtr]::Zero -and ('PB.Win' -as [type])) { [void][PB.Win]::ShowWindow($h, $Cmd) }
    } catch {}
}

# "WHAT DID THE INSTALLER DO?" snapshot dialog. Sandbox-INDEPENDENT: snapshot THIS machine, the user runs the
# installer (manually), snapshot again, diff -> a SIMPLE categorised report of everything created, with background
# noise collapsed (context-aware: the app's own vendor is never hidden). Derives the uninstall command + product
# code + recommended cleanups. Returns @{ ProductCode; Uninstall; Detection; Notes=@() } or $null. Does NOT auto-run.
# ---------- SysTracer-style change TREE (Files/Registry as the real system hierarchy; the rest as colored lists) ----------
# Colours (the ONE rule, used everywhere): green=added, amber=modified, red=removed. Scaffolding folders/keys stay
# NEUTRAL (they're just the path) and carry a count badge; only genuine changed LEAVES are coloured.
$script:SnapTreeCol = @{ new='#6A9955'; modified='#D7BA7D'; deleted='#F48771'; neutral='#9AA4B2'; sub='#8A929E' }
$script:SnapTreeLbl = @{ new='added'; modified='modified'; deleted='removed' }

# (Add-SnapshotTreePath + Get-SnapshotTreeCounts moved to Snapshot.ps1 - pure logic, engine-level + unit-tested.)
# CUSTOM-RENDERED rows (NOT a raw WPF TreeView - its default chrome looked wrong). Each node = a Border row (chevron +
# coloured left-accent + badge + name) followed by a collapsible child StackPanel. A single shared click handler reads
# the header's .Tag (kids panel + chevron) so we never need a per-node closure. Colour = ARGB '#22RRGGBB' tint.
function ConvertTo-SnapArgb { param([string]$Hex, [string]$Alpha='22') "#$Alpha$($Hex.TrimStart('#'))" }
# Children are built LAZILY - the FIRST time a node is opened (see New-SnapNodeUI). Building the whole tree up front
# created one WPF Border/StackPanel per changed item, so a huge install (a 10 GB app -> tens of thousands of changed
# files) constructed tens of thousands of visuals on the UI thread and the window went "not responding". Every node
# still starts collapsed, so the visible result is identical - only the work is deferred to the click that reveals it.
$script:SnapToggle = {
    $t = $this.Tag; if (-not $t -or -not $t.Kids) { return }
    if ($t.Build) { $b = $t.Build; $t.Build = $null; try { & $b $t.Kids } catch {} }
    $vis = if ($t.Kids.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }
    $t.Kids.Visibility = $vis
    if ($t.Chev) { $t.Chev.Text = if ($vis -eq 'Visible') { [char]0x25BC } else { [char]0x25B6 } }
}
# Max child rows built per node on expand; beyond this a "… +N more" line points at the full report. Bounds even a
# single pathological folder (some installers drop 20k+ files in one directory).
$script:SnapTreeChildCap = 400
$script:SnapHover   = { if ($this.Tag) { $this.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0x30,0x3A,0x40,0x4A))) } }
$script:SnapUnhover = { if ($this.Tag -and $this.Tag.Bg) { $this.Background = $this.Tag.Bg } }

# One coloured badge (added/modified/removed).
function New-SnapBadge {
    param([string]$Status, [double]$Size = 10.5)
    $b = New-Object Windows.Controls.Border
    $b.Background = (ConvertTo-SnapArgb $script:SnapTreeCol[$Status] '2E'); $b.CornerRadius = '3'; $b.Padding = '5,0'; $b.Margin = '0,0,6,0'; $b.VerticalAlignment = 'Center'
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $script:SnapTreeLbl[$Status]; $t.Foreground = $script:SnapTreeCol[$Status]; $t.FontSize = $Size
    $b.Child = $t; return $b
}
function Get-SnapCountStr {
    param($Counts)
    $p = @(); if ($Counts.new) { $p += "+$($Counts.new)" }; if ($Counts.modified) { $p += "~$($Counts.modified)" }; if ($Counts.deleted) { $p += "-$($Counts.deleted)" }
    return ($p -join '  ')
}
# The visual row (Border). $Kids = the collapsible child panel to toggle (or $null for a leaf).
function New-SnapRowBorder {
    param([bool]$Expandable, [bool]$Open, [string]$Status, [string]$Text, [string]$CountText, $Kids, [switch]$Bold, [string]$Detail, [switch]$Root, [string]$Icon, $Ctx, [string]$FullPath, [string]$Kind, [scriptblock]$Build)
    $bd = New-Object Windows.Controls.Border; $bd.Padding = '6,2'; $bd.Margin = '0,1,0,0'
    # ROOT node (a drive C:\ or a hive HKLM/HKCU) gets a distinct raised bar + teal accent so the top of each tree is
    # clearly a "system root", not just another folder. Status rows get a faint tinted bar; plain segments are transparent.
    $bg = if ($Root) { New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x23,0x2A,0x33)) }
          elseif ($Status) { New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x1A,0x1E,0x24)) }
          else { New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0,0,0,0)) }
    $bd.Background = $bg
    if ($Root) { $bd.Padding='6,4'; $bd.CornerRadius='4'; $bd.BorderThickness = '3,0,0,0'; $bd.BorderBrush = '#2BA6B8' }
    elseif ($Status) { $bd.BorderThickness = '3,0,0,0'; $bd.BorderBrush = $script:SnapTreeCol[$Status] }
    if ($Expandable) { $bd.Cursor = 'Hand' }
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    $chev = New-Object Windows.Controls.TextBlock; $chev.Width = 13; $chev.FontSize = 10; $chev.Foreground = '#A0A8B4'; $chev.VerticalAlignment = 'Center'; $chev.Margin = '0,0,4,0'
    $chev.Text = if ($Expandable) { if ($Open) { [char]0x25BC } else { [char]0x25B6 } } else { ' ' }
    [void]$sp.Children.Add($chev)
    if ($Icon) { $ic = New-Object Windows.Controls.TextBlock; $ic.Text = "$Icon "; $ic.FontSize = 12; $ic.VerticalAlignment='Center'; $ic.Foreground = if ($Root) { '#7FD4E0' } else { $script:SnapTreeCol.sub }; [void]$sp.Children.Add($ic) }
    if ($Status) { [void]$sp.Children.Add((New-SnapBadge -Status $Status)) }
    $tb = New-Object Windows.Controls.TextBlock; $tb.Text = $Text; $tb.FontFamily = 'Consolas'; $tb.FontSize = 12; $tb.VerticalAlignment = 'Center'; $tb.TextTrimming = 'CharacterEllipsis'
    $tb.Foreground = if ($Root) { '#7FD4E0' } elseif ($Bold) { '#E7E9ED' } elseif ($Status) { $script:SnapTreeCol[$Status] } else { $script:SnapTreeCol.neutral }
    if ($Bold -or $Root) { $tb.FontWeight = if ($Root) { 'SemiBold' } else { 'Medium' } }
    [void]$sp.Children.Add($tb)
    if ($CountText) { $ctb = New-Object Windows.Controls.TextBlock; $ctb.Text = "   $CountText"; $ctb.FontSize = 10.5; $ctb.Foreground = $script:SnapTreeCol.sub; $ctb.VerticalAlignment = 'Center'; [void]$sp.Children.Add($ctb) }
    if ($Detail) { $dtb = New-Object Windows.Controls.TextBlock; $dtb.Text = "   $Detail"; $dtb.FontSize = 12; $dtb.Foreground = $script:SnapTreeCol.sub; $dtb.VerticalAlignment = 'Center'; $dtb.TextTrimming = 'CharacterEllipsis'; [void]$sp.Children.Add($dtb) }
    $bd.Child = $sp
    $bd.Tag = @{ Kids = $Kids; Chev = $chev; Bg = $bg; Build = $Build }   # Build = deferred child-builder, run once on first expand
    if ($Expandable) { $bd.add_MouseLeftButtonUp($script:SnapToggle) }
    $bd.add_MouseEnter($script:SnapHover); $bd.add_MouseLeave($script:SnapUnhover)
    # RIGHT-CLICK menu: copy the exact path/key, and exclude this item (post-install OR post-uninstall removal).
    if ($FullPath) {
        $cm = New-Object Windows.Controls.ContextMenu
        $miC = New-Object Windows.Controls.MenuItem; $miC.Header = 'Copy path'
        $miC.add_Click({ try { [Windows.Clipboard]::SetText($FullPath) } catch {} }.GetNewClosure())
        [void]$cm.Items.Add($miC)
        if ($Ctx -and $Kind) {
            [void]$cm.Items.Add((New-Object Windows.Controls.Separator))
            $miI = New-Object Windows.Controls.MenuItem; $miI.Header = 'Exclude - remove POST-INSTALL'
            $miI.add_Click({ Add-SnapExclusion -Ctx $Ctx -Path $FullPath -Kind $Kind -Timing 'PostInstall' }.GetNewClosure())
            [void]$cm.Items.Add($miI)
            $miU = New-Object Windows.Controls.MenuItem; $miU.Header = 'Exclude - remove POST-UNINSTALL'
            $miU.add_Click({ Add-SnapExclusion -Ctx $Ctx -Path $FullPath -Kind $Kind -Timing 'PostUninstall' }.GetNewClosure())
            [void]$cm.Items.Add($miU)
        }
        $bd.ContextMenu = $cm
    }
    return $bd
}
# A collapsible node = row + (optional) kids panel, returned as one outer StackPanel.
function New-SnapCollapsible {
    param($Row, $Kids)
    $outer = New-Object Windows.Controls.StackPanel
    [void]$outer.Children.Add($Row)
    if ($Kids) { [void]$outer.Children.Add($Kids) }
    return $outer
}
# Recursive file/registry node -> UI. $ValueReader (registry) returns value Border rows for a changed key.
function New-SnapNodeUI {
    param($Node, [hashtable]$FileInfo, [hashtable]$RegValues, [switch]$Root, $Ctx, [string]$TreeKind = 'files', [hashtable]$CountCache)
    $regVals = if ($RegValues -and $Node.s) { @($RegValues["$($Node.f)"]) } else { @() }
    $hasVals = ($regVals.Count -gt 0)
    $expandable = ($Node.c.Count -gt 0) -or $hasVals
    $kids = $null; $build = $null
    # Capture the cap as a LOCAL: .GetNewClosure() bakes locals into the closure, but a $script: var does NOT resolve
    # reliably inside one - it read as $null, so every folder collapsed to a single "+N more" row. See the
    # ps-wpf-closure-scope trap: pass state into a closure through captured locals, never $script: vars.
    $cap = [int]$script:SnapTreeChildCap; if ($cap -le 0) { $cap = 400 }
    if ($expandable) {
        $kids = New-Object Windows.Controls.StackPanel; $kids.Margin = '13,0,0,0'; $kids.Visibility = 'Collapsed'
        # DEFERRED: this node's children are constructed by $script:SnapToggle on the first expand, not now. Same rows,
        # same order - just not materialised until the user actually reveals them (see the note on $script:SnapToggle).
        $build = {
            param($panel)
            if ($hasVals) { foreach ($vr in @(New-SnapRegValueRows -Values $regVals)) { [void]$panel.Children.Add($vr) } }
            $i = 0
            foreach ($ck in $Node.c.Keys) {
                if ($i -ge $cap) {
                    $more = New-Object Windows.Controls.TextBlock
                    $more.Text = "...  +$($Node.c.Count - $cap) more (use 'Open full report (CMTrace)' for the full list)"
                    $more.FontFamily = 'Consolas'; $more.FontSize = 12; $more.Foreground = $script:SnapTreeCol.sub; $more.Margin = '19,2,0,2'
                    [void]$panel.Children.Add($more); break
                }
                [void]$panel.Children.Add((New-SnapNodeUI -Node $Node.c[$ck] -FileInfo $FileInfo -RegValues $RegValues -Ctx $Ctx -TreeKind $TreeKind -CountCache $CountCache))
                $i++
            }
        }.GetNewClosure()
    }
    $count = if ($Node.c.Count -gt 0) { Get-SnapCountStr -Counts (Get-SnapshotTreeCounts -Node $Node -Cache $CountCache) } else { '' }
    # File leaf detail: size · date (captured in the change set).
    $detail = ''
    if ($FileInfo -and $Node.c.Count -eq 0 -and $Node.s) {
        $fi = $FileInfo["$($Node.f)"]
        if ($fi) { $ex = @(); if ($fi.Size) { $ex += (Format-PBSize $fi.Size) }; if ($fi.Modified) { $ex += "$($fi.Modified)" }; $detail = ($ex -join '  ·  ') }
    }
    # Right-click Copy/Exclude targets the REAL full path/key ($Node.f). Kind drives the removal command.
    $kind = if ($TreeKind -eq 'reg') { 'Registry' } elseif ($Node.c.Count -eq 0) { 'File' } else { 'Folder' }
    $fp = if ($Node.s -or $TreeKind -eq 'reg') { "$($Node.f)" } else { '' }
    $row = New-SnapRowBorder -Expandable:$expandable -Open:$false -Status $Node.s -Text $Node.n -CountText $count -Detail $detail -Kids $kids -Root:$Root -Ctx $Ctx -FullPath $fp -Kind $kind -Build $build
    return (New-SnapCollapsible -Row $row -Kids $kids)
}
# Registry-value rows (Border) from CAPTURED data (@{Name;Type;Value;Old;New;Change}) - not live, so a saved/loaded
# report renders identically. Per-value colour: added=green, removed=red, changed=amber (shows old -> new).
function New-SnapRegValueRows {
    param([object[]]$Values)
    $trim = { param($s) $t="$s"; if ($t.Length -gt 160) { $t.Substring(0,160)+'…' } else { $t } }
    $out = @()
    foreach ($v in @($Values)) {
        $ch = "$($v.Change)"; if (-not $ch) { $ch = 'added' }
        $col = switch ($ch) { 'removed' { $script:SnapTreeCol.deleted } 'changed' { $script:SnapTreeCol.modified } default { $script:SnapTreeCol.new } }
        $bgRgb = switch ($ch) { 'removed' { @(0x24,0x1B,0x1B) } 'changed' { @(0x25,0x22,0x18) } default { @(0x1B,0x22,0x1B) } }
        $bd = New-Object Windows.Controls.Border; $bd.Padding='6,2'; $bd.Margin='0,1,0,0'; $bd.BorderThickness='3,0,0,0'; $bd.BorderBrush=$col
        $bd.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb($bgRgb[0],$bgRgb[1],$bgRgb[2])))
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation='Horizontal'
        $spc = New-Object Windows.Controls.TextBlock; $spc.Width=13; [void]$sp.Children.Add($spc)
        $vt = New-Object Windows.Controls.TextBlock; $vt.FontFamily='Consolas'; $vt.FontSize=11.5; $vt.VerticalAlignment='Center'; $vt.TextTrimming='CharacterEllipsis'; $vt.Foreground='#E7E9ED'
        $nr = New-Object Windows.Documents.Run "$($v.Name) "; $nr.Foreground='#E7E9ED'; $vt.Inlines.Add($nr)   # explicit: default Run foreground is BLACK (invisible on the dark row)
        $tyr = New-Object Windows.Documents.Run "[$($v.Type)] "; $tyr.Foreground=$script:SnapTreeCol.sub; $vt.Inlines.Add($tyr)
        if ($ch -eq 'changed') {
            $or = New-Object Windows.Documents.Run "= $(& $trim $v.Old)"; $or.Foreground=$script:SnapTreeCol.deleted; $or.TextDecorations=[Windows.TextDecorations]::Strikethrough; $vt.Inlines.Add($or)
            $ar = New-Object Windows.Documents.Run "  →  $(& $trim $v.New)"; $ar.Foreground=$script:SnapTreeCol.new; $vt.Inlines.Add($ar)
        } elseif ($ch -eq 'removed') {
            $rr = New-Object Windows.Documents.Run "(removed;  was $(& $trim $v.Old))"; $rr.Foreground=$script:SnapTreeCol.deleted; $vt.Inlines.Add($rr)
        } else {
            $vr = New-Object Windows.Documents.Run "= $(& $trim $(if("$($v.New)"){$v.New}else{$v.Value}))"; $vr.Foreground=$script:SnapTreeCol.new; $vt.Inlines.Add($vr)
        }
        [void]$sp.Children.Add($vt); $bd.Child=$sp; $out += $bd
    }
    return $out
}
# A list leaf (Shortcut / Service / Program / ...) - coloured row + expandable field detail rows.
function New-SnapListLeafUI {
    param([string]$Label, $Info, [string]$Status = 'new', [string]$Detail)
    $fields = @(); if ($Info) { foreach ($key in @($Info.Keys | Sort-Object)) { $v = "$($Info[$key])"; if (-not $v.Trim()) { continue }; if ($v.Length -gt 200) { $v = $v.Substring(0,200)+'…' }; $fields += @{ K=$key; V=$v } } }
    $kids = $null
    if ($fields.Count) {
        $kids = New-Object Windows.Controls.StackPanel; $kids.Margin='13,0,0,0'; $kids.Visibility='Collapsed'
        foreach ($f in $fields) {
            $bd = New-Object Windows.Controls.Border; $bd.Padding='6,2'; $bd.Margin='0,1,0,0'
            $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation='Horizontal'; $spc=New-Object Windows.Controls.TextBlock; $spc.Width=13; [void]$sp.Children.Add($spc)
            $dt = New-Object Windows.Controls.TextBlock; $dt.FontFamily='Consolas'; $dt.FontSize=11.5; $dt.TextTrimming='CharacterEllipsis'; $dt.Foreground='#E7E9ED'
            $kr = New-Object Windows.Documents.Run "$($f.K) = "; $kr.Foreground='#E7E9ED'; $dt.Inlines.Add($kr)   # explicit light: default Run foreground is BLACK
            $vr=New-Object Windows.Documents.Run $f.V; $vr.Foreground=$script:SnapTreeCol.sub; $dt.Inlines.Add($vr)
            [void]$sp.Children.Add($dt); $bd.Child=$sp; [void]$kids.Children.Add($bd)
        }
    }
    $row = New-SnapRowBorder -Expandable:([bool]$kids) -Open:$false -Status $Status -Text $Label -Detail $Detail -Kids $kids
    return (New-SnapCollapsible -Row $row -Kids $kids)
}
# A CATEGORY (Files / Registry / Shortcuts / ...) - neutral bold header + collapsible children.
function New-SnapCategoryUI {
    param([string]$Title, [string]$CountText, [bool]$Expanded, [object[]]$ChildUIs)
    $kids = New-Object Windows.Controls.StackPanel; $kids.Visibility = if ($Expanded) { 'Visible' } else { 'Collapsed' }
    foreach ($c in @($ChildUIs)) { if ($c) { [void]$kids.Children.Add($c) } }
    $row = New-SnapRowBorder -Expandable:$true -Open:$Expanded -Status $null -Text $Title -CountText $CountText -Kids $kids -Bold
    $outer = New-SnapCollapsible -Row $row -Kids $kids; $outer.Margin = '0,3,0,0'
    return $outer
}

# Ordered list of the categories PRESENT in a change set (for the inline category buttons). 'All' is prepended by caller.
function Get-SnapTreeCategories {
    param($ChangeSet)
    $cs = $ChangeSet; $out = New-Object System.Collections.Generic.List[string]
    if (@($cs.Files).Count)    { [void]$out.Add('Files') }
    if (@($cs.Registry).Count) { [void]$out.Add('Registry') }
    foreach ($k in @($cs.Lists.Keys)) { if (@($cs.Lists[$k]).Count) { [void]$out.Add("$k") } }
    if (@($cs.Env).Count)   { [void]$out.Add('Environment') }
    # 'Ignored' is intentionally NOT a category here - the "View ignored OS junk (CMTrace)" button already covers it.
    return $out.ToArray()
}

# Build the change-tree BODY (a StackPanel of collapsible category sections) from a ChangeSet. -Category filters to ONE
# section ('All' = everything). Shared by the inline dialog view AND the standalone tree window, so both look identical.
function New-SnapTreeBody {
    param($ChangeSet, [string]$Category = 'All', $Ctx)
    $cs = $ChangeSet
    $body = New-Object Windows.Controls.StackPanel
    $body.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x0C,0x0C,0x0C)))
    if (-not $cs) {
        $t = New-Object Windows.Controls.TextBlock; $t.Text='Take a baseline, install the app, then Analyze - the change tree appears here.'; $t.Foreground='#B7BEC8'; $t.Margin='10'; $t.TextWrapping='Wrap'; [void]$body.Children.Add($t); return $body
    }
    $one = ($Category -and $Category -ne 'All')
    $show = { param($n) (-not $one) -or ($Category -eq $n) }
    # FILES (size/date on each leaf)
    if (& $show 'Files') {
        $froot = [ordered]@{}; $fileInfo = @{}
        foreach ($f in @($cs.Files)) { Add-SnapshotTreePath -Root $froot -Path "$($f.Path)" -Status "$($f.Change)"; $fileInfo["$($f.Path)"] = @{ Size=$f.Size; Modified=$f.Modified } }
        if ($froot.Count) {
            # ONE shared count cache for the whole files tree (and reused by the lazy child builders) - without it the
            # per-node count call re-walks each subtree and the build is O(n^2).
            $fCache = @{}
            $fcount = @{ new=0; modified=0; deleted=0 }; foreach ($n in $froot.Values) { $cc=Get-SnapshotTreeCounts -Node $n -Cache $fCache; $fcount.new+=$cc.new;$fcount.modified+=$cc.modified;$fcount.deleted+=$cc.deleted }
            $fkids = @(); foreach ($k in $froot.Keys) { $fkids += (New-SnapNodeUI -Node $froot[$k] -FileInfo $fileInfo -Root -Ctx $Ctx -TreeKind 'files' -CountCache $fCache) }   # top node = a drive root (C:\) -> distinct style
            [void]$body.Children.Add((New-SnapCategoryUI -Title 'Files & folders' -CountText (Get-SnapCountStr $fcount) -Expanded $true -ChildUIs $fkids))
        }
    }
    # REGISTRY (captured values on each changed key)
    if (& $show 'Registry') {
        $rroot = [ordered]@{}; $regValues = @{}
        foreach ($r in @($cs.Registry)) { Add-SnapshotTreePath -Root $rroot -Path "$($r.Path)" -Status "$($r.Change)" }
        foreach ($k in @($cs.RegValues.Keys)) { $regValues["$k"] = @($cs.RegValues[$k]) }
        if ($rroot.Count) {
            $rCache = @{}   # shared count cache for the registry tree (see the files note above)
            $rcount = @{ new=0; modified=0; deleted=0 }; foreach ($n in $rroot.Values) { $cc=Get-SnapshotTreeCounts -Node $n -Cache $rCache; $rcount.new+=$cc.new;$rcount.modified+=$cc.modified;$rcount.deleted+=$cc.deleted }
            $rkids = @(); foreach ($k in $rroot.Keys) { $rkids += (New-SnapNodeUI -Node $rroot[$k] -RegValues $regValues -Root -Ctx $Ctx -TreeKind 'reg' -CountCache $rCache) }   # top node = a hive (HKLM/HKCU) -> distinct style
            [void]$body.Children.Add((New-SnapCategoryUI -Title 'Registry' -CountText (Get-SnapCountStr $rcount) -Expanded ([bool]$one) -ChildUIs $rkids))
        }
    }
    # LIST categories (Shortcuts / Services / Tasks / Autostart / Drivers / Certificates / Printers / Programs)
    foreach ($catName in @($cs.Lists.Keys)) {
        if (-not (& $show "$catName")) { continue }
        $items = @($cs.Lists[$catName]); if (-not $items.Count) { continue }
        $leaves = @()
        foreach ($it in $items) {
            $fh = @{}; foreach ($fk in @($it.Fields.Keys)) { $fh[$fk] = $it.Fields[$fk] }
            # Inline detail so the key info shows WITHOUT expanding: shortcut target, Run-key command, task action,
            # service image path, cert subject, driver inf. Everything else stays in the expandable field list.
            $inline = ''; foreach ($pk in @('Target','TargetPath','Command','Action','Path','Subject','Inf')) { if ("$($fh[$pk])".Trim()) { $inline = "-> $($fh[$pk])"; break } }
            $leaves += (New-SnapListLeafUI -Label "$($it.Label)" -Info $fh -Detail $inline)
        }
        [void]$body.Children.Add((New-SnapCategoryUI -Title "$catName" -CountText "($($items.Count))" -Expanded ([bool]$one) -ChildUIs $leaves))
    }
    # ENV
    if ((& $show 'Environment') -and @($cs.Env).Count) {
        $eleaves = @()
        foreach ($e in @($cs.Env)) { $st = if ("$($e.Change)" -eq 'added') { 'new' } else { 'modified' }; $eleaves += (New-SnapListLeafUI -Label "$($e.Name) = $(if($e.Old){"$($e.Old) -> "})$($e.New)" -Info @{} -Status $st) }
        [void]$body.Children.Add((New-SnapCategoryUI -Title 'Environment variables' -CountText "($(@($cs.Env).Count))" -Expanded ([bool]$one) -ChildUIs $eleaves))
    }
    # (Ignored / OS-vendor noise is NOT rendered in the tree - the "View ignored OS junk (CMTrace)" button covers it.)
    if ($body.Children.Count -eq 0) {
        $empty = New-Object Windows.Controls.TextBlock; $empty.Text = if ($cs) { 'No changes in this category.' } else { 'Take a baseline, install the app, then Analyze - the change tree appears here.' }
        $empty.Foreground='#B7BEC8'; $empty.Margin='10'; [void]$body.Children.Add($empty)
    }
    return $body
}

# Render the inline change tree into the dialog (category buttons + tree body). A SCRIPT FUNCTION (not a stored closure)
# so category-button click handlers can call it reliably - the self-referencing $ctx.RefreshTree closure failed with
# "object not found" (per ps-wpf-closure-scope). State comes from the captured $Ctx hashtable.
function Get-SnapCategoryCount {
    param($ChangeSet, [string]$Category)
    $cs = $ChangeSet
    switch ($Category) {
        'All'         { return ([int]$cs.Counts.new + [int]$cs.Counts.modified + [int]$cs.Counts.deleted) }
        'Files'       { return @($cs.Files).Count }
        'Registry'    { return @($cs.Registry).Count }
        'Environment' { return @($cs.Env).Count }
        default       { return @($cs.Lists[$Category]).Count }
    }
}
# ONE exclusion/cleanup row = [checkbox] + a post-install/post-uninstall SELECTOR the user can override (the tool guesses
# the timing from the command tag; changing the combo rewrites that tag on the SAME entry, so Apply uses the new timing).
# Every exclusion source (analyze cleanups, leftover check, right-click, loaded report) routes through here.
function Add-ExclusionRow {
    param($Ctx, [string]$Label, [string]$Command, [bool]$Checked = $true)
    if (-not $Ctx -or -not $Ctx.RepPanel) { return $null }
    $row = New-Object Windows.Controls.StackPanel; $row.Orientation='Horizontal'; $row.Margin='4,2,0,2'
    $cb = New-Object Windows.Controls.CheckBox; $cb.Content=$Label; $cb.Foreground='#E7E9ED'; $cb.IsChecked=$Checked; $cb.ToolTip=$Command; $cb.VerticalAlignment='Center'
    [void]$row.Children.Add($cb)
    $entry = [pscustomobject]@{ Chk=$cb; Item=@{ Label=$Label; Command=$Command; Note=$Command } }
    $cmb = New-Object Windows.Controls.ComboBox; $cmb.Width=122; $cmb.Height=20; $cmb.Margin='10,0,0,0'; $cmb.FontSize=10; $cmb.VerticalAlignment='Center'; $cmb.ToolTip='When this removal runs in the package. Change it if the tool guessed the timing wrong.'
    foreach ($o in 'post-install','post-uninstall') { $it=New-Object Windows.Controls.ComboBoxItem; $it.Content=$o; [void]$cmb.Items.Add($it) }
    $cmb.SelectedIndex = if ("$Command" -match '(?i)\[post-uninstall\]') { 1 } else { 0 }
    [void]$row.Children.Add($cmb)
    $cmb.add_SelectionChanged({
        $to = "$($cmb.SelectedItem.Content)"
        $base = ("$($entry.Item.Command)" -replace '\s*#.*$','').TrimEnd()   # strip the timing/tag comment, re-add the chosen one
        $entry.Item.Command = if ($to -eq 'post-uninstall') { "$base  # [post-uninstall] manual-exclude" } else { "$base  # manual-exclude" }
        $cb.ToolTip = $entry.Item.Command
    }.GetNewClosure())
    [void]$Ctx.RepPanel.Children.Add($row)
    $Ctx.Cleanups.Add($entry)
    if ($Ctx.ExpExclusions) { $Ctx.ExpExclusions.IsExpanded = $true }
    return $entry
}
# Add a manual EXCLUSION from the tree's right-click menu. De-duplicates. Post-uninstall manual excludes are NOT deferred.
function Add-SnapExclusion {
    param($Ctx, [string]$Path, [ValidateSet('File','Folder','Registry')][string]$Kind, [ValidateSet('PostInstall','PostUninstall')][string]$Timing)
    if (-not $Path -or -not $Ctx -or -not $Ctx.RepPanel) { return }
    $tag = if ($Timing -eq 'PostUninstall') { '# [post-uninstall] manual-exclude' } else { '# manual-exclude' }
    $cmd = switch ($Kind) {
        'Registry' { $f = ConvertTo-PBRegForms -Key $Path; if (-not $f) { return }; "Remove-ADTRegistryKey -Key '$($f.Drive)' -Recurse  $tag" }
        'Folder'   { "Remove-ADTFolder -Path $(Format-PBPathArg $Path)  $tag" }
        default    { "Remove-ADTFile -Path $(Format-PBPathArg $Path)  $tag" }
    }
    foreach ($c in $Ctx.Cleanups) { if (("$($c.Item.Command)" -replace '\s*#.*$','') -eq ($cmd -replace '\s*#.*$','')) { if ($Ctx.ExpExclusions) { $Ctx.ExpExclusions.IsExpanded = $true }; return } }
    $when  = if ($Timing -eq 'PostUninstall') { 'post-uninstall' } else { 'post-install' }
    [void](Add-ExclusionRow -Ctx $Ctx -Label "Exclude ($when): $Path" -Command $cmd -Checked $true)
}
# Swap the RIGHT pane to one category - FAST: panels are cached in $Ctx.TreePanels, so re-clicking a category is instant
# (the previous version rebuilt the whole tree on every click, which felt slow / unresponsive). Also re-highlights buttons.
function Show-SnapCategory {
    param($Ctx, [string]$Category)
    $Ctx.TreeCategory = "$Category"
    foreach ($b in @($Ctx.CatBar.Children)) {
        if ($b -is [Windows.Controls.Button] -and $b.Tag) {
            if ("$($b.Tag)" -eq "$Category") { try { $b.Style = $script:Win.FindResource('PbAccentButton') } catch {} }
            else { $b.ClearValue([Windows.Controls.Control]::StyleProperty) }
        }
    }
    if (-not $Ctx.TreePanels) { $Ctx.TreePanels = @{} }
    if (-not $Ctx.TreePanels.ContainsKey("$Category")) { $Ctx.TreePanels["$Category"] = New-SnapTreeBody -ChangeSet $Ctx.ChangeSet -Category $Category -Ctx $Ctx }
    $Ctx.TreeSV.Content = $Ctx.TreePanels["$Category"]
}
function Update-SnapInlineTree {
    param($Ctx)
    # NOTE: this does NOT clear the panel cache - the data-changing callers (Analyze / Load) reset $Ctx.TreePanels
    # themselves, so returning here (e.g. the leftover 'Change tree' button) reuses the cache and is instant.
    $cs = $Ctx.ChangeSet; $bar = $Ctx.CatBar; $sv = $Ctx.TreeSV; $hdr = $Ctx.TreeHdr
    if (-not $bar -or -not $sv) { return }
    $bar.Children.Clear()
    if (-not $cs) {
        if ($hdr) { $hdr.Text = ''; $hdr.ToolTip = $null }
        $ph = New-Object Windows.Controls.TextBlock; $ph.Text = 'Take a baseline, install the app, then click Analyze - the change tree appears here (or load a saved report).'; $ph.Foreground='#B7BEC8'; $ph.Margin='8'; $ph.TextWrapping='Wrap'
        $sv.Content = $ph; return
    }
    if ($hdr) { $hdr.Text = "$($cs.Counts.new) added  ·  $($cs.Counts.modified) modified  ·  $($cs.Counts.deleted) removed"; $hdr.ToolTip = 'green = added, amber = modified, red = removed. Right-click a row to copy its path or exclude it.' }
    if (-not "$($Ctx.TreeCategory)") { $Ctx.TreeCategory = 'All' }
    # LEFT: one full-width button per present category, with its item count (built ONCE; clicks just swap the right pane).
    foreach ($c in (@('All') + @(Get-SnapTreeCategories -ChangeSet $cs))) {
        $n = Get-SnapCategoryCount -ChangeSet $cs -Category $c
        $b = New-Object Windows.Controls.Button; $b.Content = "$c  ($n)"; $b.Tag = "$c"; $b.Padding='8,5'; $b.Margin='0,0,0,4'; $b.FontSize=11
        $b.HorizontalAlignment='Stretch'; $b.HorizontalContentAlignment='Left'
        $b.add_Click({ Show-SnapCategory -Ctx $Ctx -Category $c }.GetNewClosure())
        [void]$bar.Children.Add($b)
    }
    Show-SnapCategory -Ctx $Ctx -Category $Ctx.TreeCategory
}

# Build + show the change TREE window (standalone). Renders a ChangeSet - built from the live diff or a loaded report.
function Show-SnapshotTreeView {
    param($Diff, $FileDiff, $RegDiff, $EnvChanges, $ChangeSet, [string]$AppName = '', [string]$Title = 'Snapshot changes (tree view)')
    if (-not $ChangeSet) { $ChangeSet = New-SnapshotChangeSet -Diff $Diff -FileDiff $FileDiff -RegDiff $RegDiff -EnvChanges $EnvChanges -AppName $AppName }
    $cs = $ChangeSet
    $w = New-Object Windows.Window
    $w.Title = $Title; $w.Width = 900; $w.Height = 680; $w.WindowStartupLocation = 'CenterOwner'
    try { $w.Owner = $script:Win } catch {}
    $w.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x18,0x1A,0x1F)))
    if (Get-Command Apply-PbTheme -EA SilentlyContinue) { Apply-PbTheme $w }
    $grid = New-Object Windows.Controls.Grid; $grid.Margin = '12'
    foreach ($h in 'Auto','*','Auto') { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = $h; [void]$grid.RowDefinitions.Add($rd) }

    # summary bar
    $bar = New-Object Windows.Controls.StackPanel; $bar.Orientation='Horizontal'; $bar.Margin='0,0,0,10'
    if ($cs.App) { $ah = New-Object Windows.Controls.TextBlock; $ah.Text = "$($cs.App)   "; $ah.Foreground='#E7E9ED'; $ah.FontWeight='Medium'; $ah.VerticalAlignment='Center'; [void]$bar.Children.Add($ah) }
    foreach ($pair in @(@('new',$cs.Counts.new),@('modified',$cs.Counts.modified),@('deleted',$cs.Counts.deleted))) {
        $bd = New-Object Windows.Controls.Border; $bd.Background=(ConvertTo-SnapArgb $script:SnapTreeCol[$pair[0]] '2E'); $bd.CornerRadius='4'; $bd.Padding='9,3'; $bd.Margin='0,0,8,0'
        $tx = New-Object Windows.Controls.TextBlock; $tx.Text = "$($pair[1]) $($script:SnapTreeLbl[$pair[0]])"; $tx.Foreground=$script:SnapTreeCol[$pair[0]]; $tx.FontSize=12
        $bd.Child = $tx; [void]$bar.Children.Add($bd)
    }
    [Windows.Controls.Grid]::SetRow($bar,0); [void]$grid.Children.Add($bar)

    # body (shared builder - identical to the inline dialog view)
    $sv = New-Object Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility='Auto'
    $body = New-SnapTreeBody -ChangeSet $cs
    $sv.Content = $body
    [Windows.Controls.Grid]::SetRow($sv,1); [void]$grid.Children.Add($sv)

    # footer: legend + Copy / Export / Import / Close
    $bp = New-Object Windows.Controls.StackPanel; $bp.Orientation='Horizontal'; $bp.HorizontalAlignment='Right'; $bp.Margin='0,10,0,0'
    $legend = New-Object Windows.Controls.TextBlock; $legend.Text = 'green = added   amber = modified   red = removed'; $legend.Foreground=$script:SnapTreeCol.sub; $legend.FontSize=12; $legend.VerticalAlignment='Center'; $legend.Margin='0,0,14,0'
    [void]$bp.Children.Add($legend)
    $btnCopy = New-Object Windows.Controls.Button; $btnCopy.Content='Copy'; $btnCopy.Padding='12,5'; $btnCopy.Margin='0,0,8,0'; $btnCopy.ToolTip='Copy the whole change report as text to the clipboard.'
    $btnExport = New-Object Windows.Controls.Button; $btnExport.Content='Export...'; $btnExport.Padding='12,5'; $btnExport.Margin='0,0,8,0'; $btnExport.ToolTip='Save the report - colour-coded HTML (opens in a browser), plain text, or the registry changes as a .reg file (import into regedit / inspect).'
    $close = New-Object Windows.Controls.Button; $close.Content='Close'; $close.Padding='16,5'
    $btnCopy.add_Click({ try { Set-Clipboard -Value (Format-SnapshotChangeSetText $cs); $btnCopy.Content='Copied' } catch {} }.GetNewClosure())
    $btnExport.add_Click({
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = 'HTML report (*.html)|*.html|Text report (*.txt)|*.txt|Registry changes (*.reg)|*.reg'
        $dlg.FileName = ("SnapshotChanges_" + ("$($cs.App)" -replace '[\\/:*?"<>|]','_')) + '.html'
        if ($dlg.ShowDialog()) {
            try {
                switch -Wildcard ($dlg.FileName) {
                    '*.reg' { [IO.File]::WriteAllText($dlg.FileName, (Format-SnapshotChangeSetReg $cs), (New-Object System.Text.UnicodeEncoding $false, $true)) }
                    '*.txt' { [IO.File]::WriteAllText($dlg.FileName, (Format-SnapshotChangeSetText $cs)) }
                    default { [IO.File]::WriteAllText($dlg.FileName, (Format-SnapshotChangeSetHtml $cs)) }
                }
                try { Start-Process $dlg.FileName } catch {}
            } catch { [Windows.MessageBox]::Show("Export failed: $($_.Exception.Message)",'Export') | Out-Null }
        }
    }.GetNewClosure())
    $close.add_Click({ $w.Close() }.GetNewClosure())
    foreach ($b in @($btnCopy,$btnExport,$close)) { [void]$bp.Children.Add($b) }
    [Windows.Controls.Grid]::SetRow($bp,2); [void]$grid.Children.Add($bp)

    $w.Content = $grid
    Set-PBDialogChrome -Window $w -Glyph 'E9D9'
    [void]$w.ShowDialog()
}

function Show-SnapshotDialog {
    # $ExePath is OPTIONAL: the snapshot is independent of the source file. With no installer selected the user runs /
    # installs the app themselves (an Admin or SYSTEM console is provided) and still gets a full before/after diff.
    param([string]$ExePath, [string]$AppVendor, [string]$AppName,
          [string]$ExistingReport, [object[]]$ExistingExclusions)
    # ONE shared reference object captured by every handler's closure. (Each .GetNewClosure() gets its OWN
    # $script: module scope, so a $script:var written in one handler is NOT visible in another - that bug made
    # Analyze report "baseline pending" after the baseline had actually been captured. A hashtable is a reference
    # type: all closures + the function body hold the SAME object, so field mutations are shared.)
    $ctx = @{ Before = $null; Result = $null; DiffUninstall = $null; ReportText = ''; Certs = @(); Cleanups = (New-Object System.Collections.Generic.List[object])
              Diff = $null; FileDiff = $null; RegDiff = $null; EnvChanges = $null; Un = $null; AppTokens = @()
              LeftoverCandidates = $null; LeftoverChecked = $false; ChangeSet = $null }   # ChangeSet drives the Tree view + is saved with the report
    # $stateRef: $script:State is NOT reachable inside the dialog's .GetNewClosure() handlers (closure module scope is
    # empty) - capture the REAL State here so handlers read/write the live hashtable (per ps-wpf-closure-scope).
    $stateRef = $script:State
    $w = New-Object Windows.Controls.Grid; $w.Margin = '12,10,12,10'
    $win = New-Object Windows.Window
    $win.Title = "Analyze installer (snapshot)$(if ("$ExePath".Trim()) { " - $(Split-Path $ExePath -Leaf)" } else { ' - manual (no installer selected)' })"
    # Open LARGE by default (90% of the work area, capped) so the report is fully visible WITHOUT maximizing - that was
    # the "report blank until I maximize" problem. The report ROW also gets a hard MinHeight below so it can never be
    # squeezed to nothing by the exclusions panel that appears after Analyze. NOT maximized (that misbehaved).
    $wa = try { [System.Windows.SystemParameters]::WorkArea } catch { $null }
    $win.Width  = if ($wa -and $wa.Width  -gt 0) { [Math]::Min(1500, [int]($wa.Width  * 0.9)) } else { 1200 }
    $win.Height = if ($wa -and $wa.Height -gt 0) { [Math]::Min(1000, [int]($wa.Height * 0.92)) } else { 820 }
    $win.MinWidth = 820; $win.MinHeight = 600
    $win.WindowStartupLocation = 'CenterScreen'; $win.Owner = $script:Win
    $win.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x18,0x1A,0x1F)))
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $win }
    foreach ($h in 'Auto','Auto','*','Auto','Auto') { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = $h; [void]$w.RowDefinitions.Add($rd) }
    $w.RowDefinitions[2].MinHeight = 200   # the REPORT row can never be squeezed to nothing by the other rows (200 still fits a 768-px screen with the footer visible)

    # HEADER: what this window is for, in the same voice as the wizard pages (glyph + title + one line + hairline).
    $hdr = New-Object Windows.Controls.StackPanel; $hdr.Margin = '0,0,0,4'
    $hRow = New-Object Windows.Controls.StackPanel; $hRow.Orientation = 'Horizontal'
    $hGly = New-Object Windows.Controls.TextBlock; $hGly.Text = [string][char]0xE9D9; $hGly.FontFamily = 'Segoe MDL2 Assets'; $hGly.FontSize = 15; $hGly.Foreground = '#56C8D6'; $hGly.VerticalAlignment = 'Center'; $hGly.Margin = '0,1,8,0'
    $hTit = New-Object Windows.Controls.TextBlock; $hTit.Text = 'Analyze installer'; $hTit.FontSize = 15; $hTit.FontWeight = 'SemiBold'; $hTit.Foreground = '#F2F4F7'; $hTit.VerticalAlignment = 'Center'
    [void]$hRow.Children.Add($hGly); [void]$hRow.Children.Add($hTit); [void]$hdr.Children.Add($hRow)
    # The explanation is a tooltip on the title - the tree is what needs the height (SysTracer-style: data first).
    $hTit.ToolTip = "Compares this machine before and after the install: everything the installer created, the uninstall command, the product code and the shortcuts. The app really installs on THIS machine - use a clean test VM."
    $hGly.ToolTip = $hTit.ToolTip
    [Windows.Controls.Grid]::SetRow($hdr,0); [void]$w.Children.Add($hdr)

    # WORKFLOW: captioned groups on one row - BEFORE (baseline), INSTALL (run it, or do it yourself), AFTER INSTALL
    # (analyze), UNINSTALL (run uninstall, leftover check). The numbers stay: this IS a sequence to follow in order.
    $barWrap = New-Object Windows.Controls.StackPanel; $barWrap.Orientation='Vertical'; $barWrap.Margin='0,6,0,6'
    $bar = New-Object Windows.Controls.WrapPanel; $bar.Orientation='Horizontal'
    $newGroup = { param($caption) $g = New-Object Windows.Controls.StackPanel; $g.Margin = '0,0,18,0'; [void]$g.Children.Add((New-PBCaption -Text $caption)); $r = New-Object Windows.Controls.StackPanel; $r.Orientation = 'Horizontal'; [void]$g.Children.Add($r); [void]$bar.Children.Add($g); return $r }
    $gBefore = & $newGroup '1  Before'
    $bBaseline = New-PBGlyphButton -Glyph 'E722' -Text 'Take baseline' -ToolTip 'Capture the machine state BEFORE the install (files, registry, services, tasks, shortcuts, certificates...).'
    try { $bBaseline.Style = $script:Win.FindResource('PbAccentButton') } catch {}
    [void]$gBefore.Children.Add($bBaseline)
    $gInstall = & $newGroup '2  Install'
    $bRun = New-PBGlyphButton -Glyph 'E768' -Text 'Run installer' -Margin '0,0,6,0'; $bRun.IsEnabled = [bool]("$ExePath".Trim())
    $lblRunAs = New-Object Windows.Controls.TextBlock; $lblRunAs.Text='as'; $lblRunAs.Foreground='#A0A8B4'; $lblRunAs.FontSize=12; $lblRunAs.VerticalAlignment='Center'; $lblRunAs.Margin='0,0,6,0'
    $cmbRunMode = New-Object Windows.Controls.ComboBox; $cmbRunMode.Width=104; $cmbRunMode.VerticalAlignment='Center'; $cmbRunMode.VerticalContentAlignment='Center'; $cmbRunMode.ToolTip='Admin = run + screenshot elevated (normal). SYSTEM = run + screenshot as LocalSystem via PsExec (-s), to reproduce an SCCM/Intune SYSTEM install (some apps behave differently, or fail, as SYSTEM). This also picks which sub-folder the screenshots go to (admin\ vs system\) so you can compare.'
    foreach ($m in 'Admin','SYSTEM') { $it=New-Object Windows.Controls.ComboBoxItem; $it.Content=$m; [void]$cmbRunMode.Items.Add($it) }
    $cmbRunMode.SelectedIndex=0
    $lblManual = New-Object Windows.Controls.TextBlock; $lblManual.Text='or'; $lblManual.Foreground='#A0A8B4'; $lblManual.FontSize=12; $lblManual.VerticalAlignment='Center'; $lblManual.Margin='10,0,8,0'
    $bAdminCmd = New-PBGlyphButton -Glyph 'E756' -Text 'Admin CMD' -Padding '10,5' -Margin '0,0,6,0' -ToolTip "Open an ELEVATED command prompt so you can run the installer / install by hand, then click 'Analyze'. Works with no installer selected."
    $bSysCmd   = New-PBGlyphButton -Glyph 'E756' -Text 'SYSTEM CMD' -Padding '10,5' -Margin '0' -ToolTip "Open a SYSTEM / LocalSystem command prompt via PsExec (-s -i) so you can install exactly as SCCM/Intune would, then click 'Analyze'. Needs PsExec next to PackageAssistance.exe."
    foreach ($c in @($bRun,$lblRunAs,$cmbRunMode,$lblManual,$bAdminCmd,$bSysCmd)) { [void]$gInstall.Children.Add($c) }
    $gAfter = & $newGroup '3  After install'
    $bAnalyze = New-PBGlyphButton -Glyph 'E9D9' -Text 'Analyze' -Margin '0,0,6,0' -ToolTip 'Capture the AFTER state and diff it against the baseline.'; $bAnalyze.IsEnabled=$false
    # After-uninstall LEFTOVER check: enabled once an analyze/loaded report provides the install-created candidates.
    $bLeftover = New-PBGlyphButton -Glyph 'E74D' -Text 'Leftover check' -Margin '0' -ToolTip "AFTER you manually UNINSTALL the app on THIS machine: live-checks every file / folder / registry key / shortcut the INSTALL created and lists what the uninstaller LEFT BEHIND (incl. now-empty folders). Ticked leftovers become POST-UNINSTALLATION cleanup (Remove-ADTFolder / Remove-ADTFile / Remove-ADTRegistryKey) on Apply - only items belonging to THIS app, never a machine-wide guess."
    $bLeftover.IsEnabled = [bool]$script:State.SnapshotLeftoverCandidates
    [void]$gAfter.Children.Add($bAnalyze)
    # Its own phase: uninstall the app again (the command the snapshot derived, or by hand), THEN check what it
    # left behind. Run uninstall is enabled once Analyze / a loaded report knows the uninstall command.
    $gUninst = & $newGroup '4  Uninstall'
    $bRunUn = New-PBGlyphButton -Glyph 'E74D' -Text 'Run uninstall' -Margin '0,0,6,0' -ToolTip "Runs the uninstall command the snapshot derived (Add/Remove Programs entry), as Admin or SYSTEM per the dropdown. Runs on THIS machine. Let it finish, then click Leftover check."
    $bRunUn.IsEnabled = [bool]"$($script:State.SnapshotUninstall)".Trim()
    $bLeftover.Margin = '0'
    [void]$gUninst.Children.Add($bRunUn); [void]$gUninst.Children.Add($bLeftover)
    [void]$barWrap.Children.Add($bar)
    # Status line under the groups: a thin activity line + the sentence saying what happened / what to do next.
    $pb = New-Object Windows.Controls.ProgressBar; $pb.Height=3; $pb.IsIndeterminate=$true; $pb.Visibility='Collapsed'; $pb.Margin='0,8,0,0'; $pb.BorderThickness='0'
    $pb.Foreground = '#2BA6B8'; $pb.Background = '#2A2E36'
    $lblStat = New-Object Windows.Controls.TextBlock; $lblStat.Foreground='#B7BEC8'; $lblStat.FontSize=12; $lblStat.TextWrapping='Wrap'; $lblStat.Margin='0,6,0,0'
    [void]$barWrap.Children.Add($pb); [void]$barWrap.Children.Add($lblStat)
    # Registered AFTER $lblStat exists: a .GetNewClosure() captures by value, so a later-created control would be $null here.
    $bRunUn.add_Click({
        $cmd = "$($ctx.Un.Uninstall)".Trim(); if (-not $cmd) { $cmd = "$($stateRef.SnapshotUninstall)".Trim() }
        if (-not $cmd) { $lblStat.Text = 'No uninstall command known yet - run Analyze first (or uninstall by hand, then Leftover check).'; return }
        $mode = "$($cmbRunMode.SelectedItem.Content)"
        $ans = [Windows.MessageBox]::Show("Run this uninstall on THIS machine as $mode`?`n`n$cmd`n`nIf the uninstaller shows a window, complete it. When it has finished, click Leftover check.", "Run uninstall ($mode)", 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { return }
        try {
            # A .cmd file sidesteps the quoting of arbitrary uninstall strings (nested quotes, msiexec switches).
            $bat = Join-Path (Get-WorkPath 'Temp') 'run-uninstall.cmd'
            [IO.File]::WriteAllText($bat, "@echo off`r`n" + ($cmd -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { $_ }) -join "`r`n" + "`r`n", [Text.Encoding]::ASCII)
            if ($mode -eq 'SYSTEM') {
                $ps = if (Get-Command Find-PsExec -EA SilentlyContinue) { Find-PsExec } else { $null }
                if (-not $ps) { $lblStat.Text = 'SYSTEM run unavailable on this copy (no PsExec) - use Admin.'; return }
                Start-Process $ps -Verb RunAs -ArgumentList "-accepteula -s -i cmd.exe /c `"$bat`""
            } else {
                Start-Process cmd.exe -Verb RunAs -ArgumentList "/c `"$bat`""
            }
            $lblStat.Text = "Uninstall launched as $mode - let it finish, then click Leftover check."
        } catch { $lblStat.Text = "Uninstall did not start: $($_.Exception.Message)" }
    })   # plain handler: Get-WorkPath / Find-PsExec are script functions - invisible inside a .GetNewClosure()
    # Manual consoles open at the default (C:\Windows\System32) like any elevated / SYSTEM prompt - the user cd's
    # wherever they need. PsExec is the owner's to stage, so a missing PsExec is a quiet status line, not a user warning.
    $bAdminCmd.add_Click({ $lblStat=$lblStat
        try { Start-Process 'cmd.exe' -Verb RunAs ; $lblStat.Text = "Admin CMD open - run/install the app, then click 'Analyze'." }
        catch { $lblStat.Text = 'Admin CMD did not open (UAC declined?).' }
    }.GetNewClosure())
    $bSysCmd.add_Click({ $lblStat=$lblStat
        $ps = if (Get-Command Find-PsExec -EA SilentlyContinue) { Find-PsExec } else { $null }
        if (-not $ps) { $lblStat.Text = 'SYSTEM console unavailable on this copy - use "Open CMD (Admin)".'; return }
        try { Start-Process $ps -Verb RunAs -ArgumentList '-accepteula -s -i cmd.exe' ; $lblStat.Text = "SYSTEM CMD open - install as SYSTEM, then click 'Analyze'." }
        catch { $lblStat.Text = 'SYSTEM CMD did not open (UAC declined?).' }
    }.GetNewClosure())
    [Windows.Controls.Grid]::SetRow($barWrap,1); [void]$w.Children.Add($barWrap)

    # MAIN VIEW = the change TREE as a MASTER-DETAIL: category list on the LEFT (Files / Registry / Shortcuts / ...),
    # the selected category's tree on the RIGHT. Uses horizontal space, no top button row. $txtReport is kept as an
    # OFF-SCREEN text buffer (never added to the layout) so Save/Copy/leftover-append keep working against $ctx.ReportText.
    $txtReport = New-Object Windows.Controls.TextBox; $txtReport.IsReadOnly=$true; $txtReport.AcceptsReturn=$true; $txtReport.Text=''
    $repWrap = New-Object Windows.Controls.Grid
    foreach ($h in 'Auto','*') { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = $h; [void]$repWrap.RowDefinitions.Add($rd) }
    # Tree header row = caption left, the report/action TOOLBAR right (moved up from the footer so the tree - the
    # thing the packager actually reads - gets that height back). Buttons are added into $treeTools further down.
    $treeBar = New-Object Windows.Controls.DockPanel; $treeBar.Margin = '0,0,0,6'; $treeBar.LastChildFill = $true
    $treeTools = New-Object Windows.Controls.StackPanel; $treeTools.Orientation = 'Horizontal'; $treeTools.HorizontalAlignment = 'Right'
    [Windows.Controls.DockPanel]::SetDock($treeTools, 'Right'); [void]$treeBar.Children.Add($treeTools)
    # No 'CHANGE TREE' caption: the tree is self-evident and the row belongs to the toolbar. $treeHdr stays for code that sets it.
    $treeHdr = New-Object Windows.Controls.TextBlock; $treeHdr.Foreground='#A0A8B4'; $treeHdr.FontSize=12; $treeHdr.VerticalAlignment='Center'; $treeHdr.TextTrimming='CharacterEllipsis'; $treeHdr.Margin='0,0,12,0'
    [void]$treeBar.Children.Add($treeHdr)
    [Windows.Controls.Grid]::SetRow($treeBar,0); [void]$repWrap.Children.Add($treeBar)
    $bodyGrid = New-Object Windows.Controls.Grid
    foreach ($cw in @('165','*')) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $cw; [void]$bodyGrid.ColumnDefinitions.Add($cd) }
    # LEFT: category list (vertical full-width buttons) in its own surface panel.
    $catHost = New-Object Windows.Controls.Border; $catHost.Background=(New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x16,0x18,0x1D))); $catHost.CornerRadius='4'; $catHost.Padding='6'; $catHost.Margin='0,0,8,0'
    $catSV = New-Object Windows.Controls.ScrollViewer; $catSV.VerticalScrollBarVisibility='Auto'
    $catBar = New-Object Windows.Controls.StackPanel; $catSV.Content=$catBar; $catHost.Child=$catSV
    [Windows.Controls.Grid]::SetColumn($catHost,0); [void]$bodyGrid.Children.Add($catHost)
    # RIGHT: the selected category's tree.
    $treeSV = New-Object Windows.Controls.ScrollViewer; $treeSV.VerticalScrollBarVisibility='Auto'; $treeSV.HorizontalScrollBarVisibility='Auto'; $treeSV.MinHeight=240
    $treeSV.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x0C,0x0C,0x0C))); $treeSV.Padding='4'
    [Windows.Controls.Grid]::SetColumn($treeSV,1); [void]$bodyGrid.Children.Add($treeSV)
    [Windows.Controls.Grid]::SetRow($bodyGrid,1); [void]$repWrap.Children.Add($bodyGrid)
    [Windows.Controls.Grid]::SetRow($repWrap,2); [void]$w.Children.Add($repWrap)
    # Inline-tree state (shared via the $ctx hashtable per ps-wpf-closure-scope). Category buttons + Analyze + Load all
    # call the SCRIPT FUNCTION Update-SnapInlineTree -Ctx $ctx (a stored self-invoking closure failed with "object not found").
    $ctx.CatBar = $catBar; $ctx.TreeSV = $treeSV; $ctx.TreeHdr = $treeHdr; $ctx.TreeCategory = 'All'
    Update-SnapInlineTree -Ctx $ctx

    # EXCLUSIONS - their OWN collapsible section (collapsed by default) so they never crowd the tree; auto-expands when
    # the analyze/loaded report actually has exclusions to tick. Ticked = removed in the package POST-INSTALLATION.
    $exp = New-Object Windows.Controls.Expander; $exp.Header='Exclusions & cleanup  (tick to remove in the package - each item is tagged post-install or post-uninstall)'; $exp.Foreground='#56C8D6'; $exp.FontWeight='Bold'; $exp.FontSize=12; $exp.IsExpanded=$false; $exp.Margin='0,8,0,0'
    $sv = New-Object Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility='Auto'; $sv.MaxHeight=140
    $rep = New-Object Windows.Controls.StackPanel; $rep.Margin='0,4,0,0'
    $sv.Content = $rep; $exp.Content = $sv; $ctx.ExpExclusions = $exp; $ctx.RepPanel = $rep   # RepPanel = where tree-menu excludes drop their checkbox
    [Windows.Controls.Grid]::SetRow($exp,3); [void]$w.Children.Add($exp)

    # Footer = three labeled rows (nothing hidden, nothing duplicated - just grouped so the window reads cleanly):
    #   Report:  save / load / view-ignored     Actions:  screenshot / exclude / certificate / driverstore     then the commit row.
    $footWrap = New-Object Windows.Controls.StackPanel; $footWrap.Orientation='Vertical'; $footWrap.Margin='0,8,0,0'
    $fRule = New-Object Windows.Controls.Border; $fRule.BorderBrush = '#2A2F38'; $fRule.BorderThickness = '0,1,0,0'; $fRule.Margin = '0,0,0,8'
    [void]$footWrap.Children.Add($fRule)
    # PER-USER CONFIGURATION lives here, next to the HKCU / profile findings in the tree that inform the choice.
    # The selection is central state (State.PerUserMode); Build-Step3Script generates the PSADT v4 code for it.
    # One footer row: [Per-user config â–¾]  summary text  [Apply to package] [Cancel] - the explanation of each option
    # is the dropdown's tooltip, so the footer stays one line and the tree keeps the height.
    $puRow = New-Object Windows.Controls.StackPanel; $puRow.Orientation='Horizontal'; $puRow.Margin='0,0,16,0'
    $lblPuRow = New-Object Windows.Controls.TextBlock; $lblPuRow.Text='Per-user config'; $lblPuRow.Foreground='#A0A8B4'; $lblPuRow.FontSize=12; $lblPuRow.VerticalAlignment='Center'; $lblPuRow.Margin='0,0,8,0'; [void]$puRow.Children.Add($lblPuRow)
    $cmbPerUser = New-Object Windows.Controls.ComboBox; $cmbPerUser.Width=300; $cmbPerUser.VerticalAlignment='Center'; $cmbPerUser.VerticalContentAlignment='Center'
    foreach ($m in 'None','All-users registry (Invoke-ADTAllUsersRegistryAction)','Active Setup (per-user at logon)') { $it=New-Object Windows.Controls.ComboBoxItem; $it.Content=$m; [void]$cmbPerUser.Items.Add($it) }
    $cmbPerUser.SelectedIndex = Get-PerUserModeIndex -Mode $stateRef.PerUserMode
    $cmbPerUser.ToolTip = "For settings the app keeps per user (HKCU, profile files) - the tool generates the PSADT v4 code.`r`n" + (Get-PerUserHintText -Mode $stateRef.PerUserMode)
    $cmbPerUser.add_SelectionChanged({
        $i = [int]$cmbPerUser.SelectedIndex
        Set-PerUserMode -Index $i
        $cmbPerUser.ToolTip = "For settings the app keeps per user (HKCU, profile files) - the tool generates the PSADT v4 code.`r`n" + (Get-PerUserHintText -Mode $stateRef.PerUserMode)
    })   # plain handler: it calls script functions, which a .GetNewClosure() cannot see
    [void]$puRow.Children.Add($cmbPerUser)
    $reportRow = New-Object Windows.Controls.StackPanel; $reportRow.Orientation='Horizontal'; $reportRow.Margin='0,0,0,6'
    $lblRepRow = New-Object Windows.Controls.TextBlock; $lblRepRow.Text='Report:'; $lblRepRow.Foreground='#A0A8B4'; $lblRepRow.FontSize=12; $lblRepRow.Width=$rowLabelW; $lblRepRow.VerticalAlignment='Center'; [void]$reportRow.Children.Add($lblRepRow)
    $actionRow = New-Object Windows.Controls.StackPanel; $actionRow.Orientation='Horizontal'; $actionRow.Margin='0,0,0,10'
    $lblActRow = New-Object Windows.Controls.TextBlock; $lblActRow.Text='Actions:'; $lblActRow.Foreground='#A0A8B4'; $lblActRow.FontSize=12; $lblActRow.Width=$rowLabelW; $lblActRow.VerticalAlignment='Center'; [void]$actionRow.Children.Add($lblActRow)
    $dp = New-Object Windows.Controls.DockPanel; $dp.LastChildFill=$true
    [Windows.Controls.DockPanel]::SetDock($puRow,'Left'); [void]$dp.Children.Add($puRow)   # per-user dropdown leads the commit row
    $bCancel = New-Object Windows.Controls.Button; $bCancel.Content='Cancel'; $bCancel.Padding='12,4'; $bCancel.IsCancel=$true
    [Windows.Controls.DockPanel]::SetDock($bCancel,'Right'); [void]$dp.Children.Add($bCancel)
    $bApply = New-PBGlyphButton -Glyph 'E8FB' -Text 'Apply to package' -Padding '16,5'; $bApply.IsEnabled=$false
    try { $bApply.Style = $script:Win.FindResource('PbAccentButton') } catch {}
    [Windows.Controls.DockPanel]::SetDock($bApply,'Right'); [void]$dp.Children.Add($bApply)
    $bCopy = New-PBGlyphButton -Glyph 'E8A7' -Text 'View ignored OS noise (CMTrace)' -Padding '10,5'; $bCopy.IsEnabled=$false
    $bCopy.ToolTip='Open ONLY the items that were filtered out as OS / vendor / churn NOISE in CMTrace, so you can confirm nothing app-relevant was hidden. The app changes are shown here in the report (and "Save report...").'
    $bSave = New-PBGlyphButton -Glyph 'E74E' -Text 'Save report...' -Padding '10,5'; $bSave.IsEnabled=$false
    $bSave.ToolTip='Save the report to a .txt file (e.g. to attach to a ticket). (Apply ALSO auto-saves the full re-loadable report to the work folder''s Reports\.)'
    $bLoad = New-PBGlyphButton -Glyph 'E8E5' -Text 'Load report...' -Padding '10,5'
    $bLoad.ToolTip='Load a previously saved snapshot report (auto-saved to the work folder''s Reports\ on every Apply) - restores the report, exclusions, shortcuts and the leftover-check data, so you can re-apply actions, screenshot shortcuts, or run the after-uninstall leftover check WITHOUT re-running the installer snapshot.'
    $bExclude = New-PBGlyphButton -Glyph 'E738' -Text 'Exclude item...' -Padding '10,5'; $bExclude.IsEnabled=$false
    $bExclude.ToolTip='Add a file / folder / registry key / shortcut to EXCLUDE - it gets a removal command in the ps1 POST-INSTALLATION (inclusions are unchanged - the installer keeps everything else).'
    $bCertMgr = New-PBGlyphButton -Glyph 'E72E' -Text 'Open certificate...' -Padding '10,5'; $bCertMgr.ToolTip='Open a certificate the installer added, directly in the Windows certificate viewer (pick which one). Falls back to certmgr if none captured.'
    $bCertMgr.add_Click({
        $certs = @($ctx.Certs)
        if (-not $certs.Count) { try { Start-Process 'certlm.msc' } catch { try { Start-Process 'certmgr.msc' } catch {} }; return }
        $pick = if ($certs.Count -eq 1) { $certs[0] } else { Show-CertPickerDialog -Certs $certs }
        if (-not $pick) { return }
        $store = "$($pick.Info.Store)"; $thumb = ($pick.Id -split '\\')[-1]
        if (-not (Open-CapturedCertificate -Store $store -Thumbprint $thumb)) { [Windows.MessageBox]::Show("Could not open the certificate ($thumb). It may have been removed.", 'Open certificate', 'OK', 'Warning') | Out-Null }
    }.GetNewClosure())
    $bDrvStore = New-PBGlyphButton -Glyph 'E8B7' -Text 'DriverStore' -Padding '10,5'; $bDrvStore.ToolTip='Open the DriverStore folder'
    $bDrvStore.add_Click({ try { Start-Process explorer.exe (Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository') } catch {} })
    # INITIAL VALIDATION: screenshot the shortcuts THIS install created. The snapshot diff gives the EXACT shortcuts
    # (no name/timestamp guessing) and the app is freshly installed - the ideal moment for the reference screenshots.
    $bShots = New-PBGlyphButton -Glyph 'E722' -Text 'Launch + screenshot shortcuts' -Padding '10,5'
    # Enabled whenever shortcuts are KNOWN - freshly analyzed OR persisted from an earlier analyze/loaded report in this
    # session (flexibility: reopening the dialog keeps the button usable until the tool closes or the step is reset).
    $bShots.IsEnabled = [bool](@($script:State.SnapshotShortcuts).Count)
    $bShots.ToolTip='Launch the app shortcuts this install CREATED (exact, from the snapshot diff) and screenshot each (captioned + index.html), then close them. Everything is minimized first and each app gets >=10s to finish launching. Saved under the work folder''s Screenshots\<app>\snapshot\<admin|system> (matching the "install as" choice, so you can install as Admin then as SYSTEM and compare). These are the reference the Troubleshoot validation compares against.'
    # $lblSummary MUST be created BEFORE the click handler below: a .GetNewClosure() captures it by value, so if it
    # were created later it would be $null in the handler and ".Text =" would throw "property Text cannot be found".
    $lblSummary = New-Object Windows.Controls.TextBlock; $lblSummary.Foreground='#D7FFD7'; $lblSummary.FontSize=12; $lblSummary.TextWrapping='Wrap'; $lblSummary.VerticalAlignment='Center'; $lblSummary.Margin='8,0,0,0'
    $bShots.add_Click({
        $sc = @($ctx.Shortcuts)
        if (-not $sc.Count) { $sc = @($stateRef.SnapshotShortcuts) }   # persisted from an earlier analyze/loaded report
        if (-not $sc.Count) { $lblSummary.Text = 'No app shortcuts were captured by the snapshot to screenshot.'; return }
        if (-not (Get-Command Start-ScreenshotJob -EA SilentlyContinue)) { return }
        # Clarify the count: the snapshot may have recorded more .lnks than we launch - uninstall/update/help/desktop
        # shortcuts are deliberately NOT launched, so "$($sc.Count) of N" is expected, not a miss.
        $rawSc = if ($ctx.Diff -and $ctx.Diff.Shortcuts) { @($ctx.Diff.Shortcuts.Added).Count } else { $sc.Count }
        $skipNote = if ($rawSc -gt $sc.Count) { "  ($($rawSc - $sc.Count) uninstall/update/help/desktop shortcut(s) are skipped.)" } else { '' }
        $ans = [Windows.MessageBox]::Show("Launch the $($sc.Count) real app shortcut(s) this install created and screenshot each, then close them?$skipNote`n`nThe tool + other windows are minimized first, each app gets up to 45s to appear and at least 10s to finish drawing, then it's captured and closed. This starts the real app(s) on THIS machine.", 'Screenshot shortcuts (initial validation)', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { return }
        $nm = if ("$AppName".Trim()) { "$AppName" } elseif ("$ExePath".Trim()) { [IO.Path]::GetFileNameWithoutExtension($ExePath) } else { 'app' }
        # Keep Admin vs SYSTEM captures apart so the two install contexts can be compared side by side.
        $mode = "$($cmbRunMode.SelectedItem.Content)".ToLower()
        $out = Join-Path (Get-WorkPath ("Screenshots\$nm\snapshot\$mode")) (Get-Date -Format 'yyyyMMdd_HHmmss')
        # Re-bind TRUE locals for the nested OnDone closure (per ps-wpf-closure-scope). Run in the BACKGROUND so the
        # minimize-all + >=10s-per-app waits never freeze the GUI thread.
        $lblSummary=$lblSummary; $bShots=$bShots; $win=$win
        $bShots.IsEnabled=$false
        # ROOT CAUSE of "main window won't minimize": this dialog is MODAL, and Windows will not keep the visible
        # OWNER of a modal dialog minimized (it gets reactivated). So we HIDE the main window outright (works with a
        # modal child) and force-minimize the dialog. (Capture correctness no longer depends on this anyway - the job
        # now forces each app window to the foreground and captures only ITS rectangle.) Restored in OnDone.
        # NEVER (Get-PBMainWindow).Hide() here - that ends the main window's ShowDialog and the tool exits when this
        # dialog closes. Win32 SW_HIDE on the HWND instead (see Hide-PBMainWindow). Closure-safe via Get-PBMainWindow.
        Hide-PBMainWindow (Get-PBMainWindow)
        Set-PBWindowState $win 11
        $lblSummary.Text = "Minimizing windows, then launching + screenshotting $($sc.Count) shortcut(s) in the background (~10s+ each)..."
        Start-ScreenshotJob -ExactShortcuts $sc -OutDir $out -Title "Snapshot validation ($mode) - $nm" -OnDone {
            param($res, $err)
            Show-PBMainWindow (Get-PBMainWindow)                                     # un-hide the main window (Win32)
            try { Set-PBWindowState $win 9; $win.Activate() } catch {}        # restore + refocus the dialog
            $bShots.IsEnabled=$true
            if (-not $lblSummary) { return }
            if ($err -or -not $res) { $lblSummary.Text = "Screenshot failed: $err"; return }
            $shots=@($res.Shots); $ok=@($shots | Where-Object { $_.Ok }).Count
            $lblSummary.Text = "Captured $ok/$($shots.Count) shortcut screenshot(s) -> $($res.OutDir) (open index.html)."
            try { Start-Process explorer.exe $res.OutDir } catch {}
        }.GetNewClosure()
    }.GetNewClosure())
    # $bShots is placed on the Actions row below (with Exclude / certificate / DriverStore).
    [void]$dp.Children.Add($lblSummary)
    # Docked children stretch PERPENDICULAR to their dock edge - so when $lblSummary (the fill child) wraps to several
    # lines after Analyze, the Left/Right-docked BUTTONS were stretching to that full height ("bar chart" buttons in a
    # non-maximized window). Pin every button to Center height so they keep their natural size no matter how tall the
    # status text gets.
    # Assemble the labeled footer rows (report tools, then actions, then the commit row). Nothing hidden, no duplicates.
    # Toolbar on the tree header: report tools, a thin divider, then actions. Compact padding - they are secondary.
    foreach ($b in @($bSave,$bLoad,$bCopy,$bShots,$bExclude,$bCertMgr,$bDrvStore)) { $b.Padding = '9,3'; $b.Margin = '0,0,6,0'; $b.MinHeight = 26; $b.FontSize = 12 }
    foreach ($c in @($bSave,$bLoad,$bCopy)) { [void]$treeTools.Children.Add($c) }
    $tDiv = New-Object Windows.Controls.Border; $tDiv.Width = 1; $tDiv.Height = 18; $tDiv.Background = '#2F343D'; $tDiv.Margin = '4,0,10,0'; $tDiv.VerticalAlignment = 'Center'
    [void]$treeTools.Children.Add($tDiv)
    foreach ($c in @($bShots,$bExclude,$bCertMgr,$bDrvStore)) { [void]$treeTools.Children.Add($c) }
    $bDrvStore.Margin = '0'
    foreach ($c in @($dp.Children)) { if ($c -is [Windows.Controls.Button]) { $c.VerticalAlignment = 'Center' } }
    # Footer = per-user row + the commit row only.
    [void]$footWrap.Children.Add($dp)
    [Windows.Controls.Grid]::SetRow($footWrap,4); [void]$w.Children.Add($footWrap)
    $bCopy.add_Click({
        try {
            # ONLY the IGNORED / noise items (what was filtered out), written to a log and opened in CMTrace so the
            # user can search/verify nothing app-relevant was hidden. App changes stay in this dialog (+ Save report).
            if (-not $ctx.Diff) { $lblSummary.Text = 'Run Analyze first.'; return }
            $txt = Get-SnapshotReportText -Diff $ctx.Diff -FileDiff $ctx.FileDiff -RegDiff $ctx.RegDiff -EnvChanges $ctx.EnvChanges -Un $ctx.Un -AppTokens $ctx.AppTokens -NoiseOnly
            if (-not "$txt".Trim()) { $txt = '(nothing was filtered as noise - the report above is the complete change set.)' }
            $log = Join-Path (Get-WorkPath 'Logs') ("snapshot_ignored_$([DateTime]::Now.ToString('yyyyMMdd_HHmmss')).log")
            [IO.File]::WriteAllText($log, $txt, (New-Object System.Text.UTF8Encoding $false))
            if (Get-Command Open-CMTrace -EA SilentlyContinue) { Open-CMTrace -LogPath $log } elseif (Test-Path $log) { Start-Process $log }
            $lblSummary.Text = "Ignored (OS/vendor/churn) items opened in CMTrace: $log"
        } catch { $lblSummary.Text = "Could not open ignored items: $($_.Exception.Message)" }
    }.GetNewClosure())
    $bSave.add_Click({
        try {
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Filter = 'Text file (*.txt)|*.txt'; $dlg.FileName = "snapshot_$([IO.Path]::GetFileNameWithoutExtension($ExePath)).txt"
            $wr = if (Get-Command Get-WorkPath -EA SilentlyContinue) { Get-WorkPath 'Logs' } else { $env:TEMP }
            $dlg.InitialDirectory = $wr
            if ($dlg.ShowDialog() -eq 'OK') { [IO.File]::WriteAllText($dlg.FileName, "$($txtReport.Text)"); $lblSummary.Text = "Saved: $($dlg.FileName)" }
        } catch { $lblSummary.Text = "Save failed: $($_.Exception.Message)" }
    }.GetNewClosure())
    $bExclude.add_Click({
        $item = Show-InputDialog -Title 'Exclude an item' -Prompt "Enter a file / folder / registry key / shortcut to EXCLUDE - it gets a removal command in the package's POST-INSTALLATION. Examples:`n  C:\Program Files\App\Updater`n  HKLM\SOFTWARE\App\AutoRun`n  C:\Users\Public\Desktop\App.lnk"
        if (-not "$item".Trim()) { return }
        $ex = Get-ExclusionCommand -Item $item
        if (-not $ex) { return }
        [void](Add-ExclusionRow -Ctx $ctx -Label "$($ex.Label)" -Command "$($ex.Command)" -Checked $true)
        $lblSummary.Text = "Added exclusion: $($ex.Label)  (removed in POST-INSTALL on Apply)."
    }.GetNewClosure())

    # On open: NO automatic scan (auto-baseline is risky). Just re-load any SAVED report + exclusions so they
    # aren't lost; the user clicks 'Take baseline' when they're ready.
    $win.add_Loaded({
        $ctx=$ctx; $stateRef=$stateRef; $lblStat=$lblStat; $txtReport=$txtReport; $rep=$rep; $bApply=$bApply; $bCopy=$bCopy; $bSave=$bSave; $bExclude=$bExclude; $bLeftover=$bLeftover; $bRunUn=$bRunUn; $ExistingReport=$ExistingReport; $ExistingExclusions=$ExistingExclusions
        if ($bRunUn) { $bRunUn.IsEnabled = [bool]"$($stateRef.SnapshotUninstall)".Trim() }   # a previous Analyze this session knows the command
        if ("$ExistingReport".Trim()) {
            $ctx.ReportText = "$ExistingReport"; $txtReport.Text = "$ExistingReport"
            foreach ($x in @($ExistingExclusions)) {
                [void](Add-ExclusionRow -Ctx $ctx -Label "$($x.Label)" -Command "$($x.Command)" -Checked ([bool]$x.Checked))
            }
            $ctx.LeftoverCandidates = $stateRef.SnapshotLeftoverCandidates   # same-session persisted -> leftover check stays usable
            $ctx.LeftoverChecked = [bool]$stateRef.SnapshotLeftoverChecked
            $ctx.Shortcuts = @($stateRef.SnapshotShortcuts)
            # Same-session re-open: rebuild a structural change set from the persisted leftovers/shortcuts so the Tree still works.
            if ((@($ctx.LeftoverCandidates).Count -or @($ctx.Shortcuts).Count) -and (Get-Command New-SnapshotChangeSetFromState -EA SilentlyContinue)) {
                $ctx.ChangeSet = New-SnapshotChangeSetFromState -State @{ LeftoverCandidates=$ctx.LeftoverCandidates; Shortcuts=$ctx.Shortcuts } -AppName ("$AppVendor $AppName".Trim())
            }
            if ($ctx.LeftoverCandidates -and $bLeftover) { $bLeftover.IsEnabled = $true }
            $ctx.TreePanels=@{}; $ctx.TreeCategory = 'All'; Update-SnapInlineTree -Ctx $ctx   # render the inline tree from the re-opened snapshot
            if (@($ExistingExclusions).Count -and $ctx.ExpExclusions) { $ctx.ExpExclusions.IsExpanded = $true }
            $bApply.IsEnabled=$true; $bCopy.IsEnabled=$true; $bSave.IsEnabled=$true; $bExclude.IsEnabled=$true
            $lblStat.Text = 'Loaded the previous snapshot (report + exclusions). Add/edit exclusions and Apply, or click "Take baseline" for a brand-new capture.'
        } else {
            # Beginner-aware guidance: what to do (and whether a snapshot is even needed) for THIS installer type /
            # predecessor reuse. Falls back to the generic prompt if the helper isn't present.
            # Idle: one short sentence. (The engine's per-installer-type guidance was dropped from here on request.)
            $lblStat.Text = 'Nothing scans until you click Take baseline.'
        }
    }.GetNewClosure())

    # MANUAL baseline - the user decides when. Runs on a BACKGROUND runspace so the window stays responsive.
    $bBaseline.add_Click({
        $pb=$pb; $ctx=$ctx; $lblStat=$lblStat; $bAnalyze=$bAnalyze; $bBaseline=$bBaseline
        $bBaseline.IsEnabled=$false; $pb.Visibility='Visible'
        $lblStat.Text = 'Capturing baseline (BEFORE) snapshot - main locations + registry; about a minute. The window stays usable...'
        Start-SnapshotJob -OnDone {
            param($snap, $err)
            $pb.Visibility = 'Collapsed'; $bBaseline.IsEnabled = $true
            if ($err -or -not $snap) { $lblStat.Text = "Baseline failed: $err"; return }
            $ctx.Before = $snap
            $lblStat.Text = "Baseline captured ($($snap._FileMap.Count) files, $($snap._RegMap.Count) registry keys). Now RUN the installer, let it FINISH, then click 'Analyze'."
            $bAnalyze.IsEnabled = $true
        }.GetNewClosure()
    }.GetNewClosure())

    $bRun.add_Click({ $cmbRunMode=$cmbRunMode; $lblStat=$lblStat
        if (-not "$ExePath".Trim()) { $lblStat.Text = 'No installer selected - use "Open CMD (Admin)" / "Open CMD (SYSTEM)" to install manually, then Analyze.'; return }
        $mode = "$($cmbRunMode.SelectedItem.Content)"
        if ((Get-Command Test-IsSecurityProduct -EA SilentlyContinue) -and (Test-IsSecurityProduct "$ExePath $AppVendor $AppName")) {
            $sec = [Windows.MessageBox]::Show("'$([IO.Path]::GetFileName($ExePath))' looks like a SECURITY / EDR / AV product. Re-running its installer on a real endpoint is normally BLOCKED - tamper protection or the resident agent (SentinelOne/McAfee) kills it with 'invalid image' or a DLL error, so the snapshot won't capture a clean install.`n`nSafer: Cancel and use a throwaway Sandbox, or analyze it on a clean test VM.`n`nRun it on THIS machine anyway?", 'Security product detected', 'YesNo', 'Warning')
            if ($sec -ne 'Yes') { $lblStat.Text = 'Cancelled - run security/EDR installers in a sandbox or clean test VM, not on this protected machine.'; return }
        }
        $isUnc = ("$ExePath" -match '^\\\\')   # only a UNC source is copied locally; a staged/local source runs in place
        $copyNote = if ($isUnc) { "`n`nThe tool copies it to a LOCAL folder first (a UNC path fails once the installer elevates)." } else { '' }
        $ans = [Windows.MessageBox]::Show("This RUNS the installer on THIS machine as $mode and lets it install fully:`n$ExePath$copyNote`n`nOnly do this on a test/VM machine you can clean up. Continue?", "Run installer ($mode)", 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { return }
        $lblStat.Text = if ($isUnc) { 'Copying the installer locally, then launching elevated...' } else { 'Launching the installer elevated...' }
        try { (Get-PBMainWindow).Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch {}
        $local = if (Get-Command Copy-InstallerLocal -EA SilentlyContinue) { Copy-InstallerLocal -ExePath $ExePath } else { $ExePath }
        if (-not $local -or -not (Test-Path $local)) { $lblStat.Text = 'Could not access the installer.'; return }
        if ($mode -eq 'SYSTEM') {
            $ps = if (Get-Command Find-PsExec -EA SilentlyContinue) { Find-PsExec } else { $null }
            if (-not $ps) { $lblStat.Text = 'SYSTEM run unavailable on this copy - switch "install as" to Admin.'; return }
            # MSI/MSP can't be run by PsExec directly (not an .exe) - route through msiexec, same as the Admin path.
            $spec = if (Get-Command Get-InstallerRunSpec -EA SilentlyContinue) { Get-InstallerRunSpec -Path $local } else { @{ File=$local; Args='' } }
            $psInner = "`"$($spec.File)`"" + $(if ("$($spec.Args)".Trim()) { " $($spec.Args)" } else { '' })
            try { Start-Process $ps -Verb RunAs -ArgumentList "-accepteula -s -i -d $psInner" ; $lblStat.Text = "Launched $([IO.Path]::GetFileName($local)) as SYSTEM (PsExec). Let it FINISH, then click 'Analyze'." }
            catch { $lblStat.Text = "SYSTEM launch failed: $($_.Exception.Message). Try Admin, or run it yourself from the SYSTEM CMD, then Analyze." }
            return
        }
        $r = Start-InstallerLaunch -Path $local
        if ($r.Ok) { $lblStat.Text = "Launched $([IO.Path]::GetFileName($local)) ($($r.Mode)). Let the install FINISH, then click 'Analyze'." }
        else { $lblStat.Text = "Launch failed: $($r.Error). If UAC was declined, re-try; if policy blocks it, run the installer yourself, then click 'Analyze'." }
    }.GetNewClosure())

    $bAnalyze.add_Click({
        if (-not $ctx.Before) { $lblStat.Text = 'No baseline yet - click "Take baseline" first (then run the installer, then Analyze).'; return }
        # Re-bind to TRUE locals so the nested -OnDone closure can capture them (see ps-wpf-closure-scope memory).
        # EVERY dialog control the callback touches must be here - a missing one (e.g. $lblSummary) is $null in the
        # callback and throws "property Text cannot be found", aborting the render half-way.
        $pb=$pb; $ctx=$ctx; $lblStat=$lblStat; $lblSummary=$lblSummary; $bAnalyze=$bAnalyze; $bApply=$bApply; $bCopy=$bCopy; $bSave=$bSave; $bExclude=$bExclude; $bShots=$bShots; $bLeftover=$bLeftover; $bRunUn=$bRunUn; $rep=$rep; $txtReport=$txtReport; $AppVendor=$AppVendor; $AppName=$AppName
        $bAnalyze.IsEnabled=$false; $bApply.IsEnabled=$false
        $lblStat.Text = 'Capturing the after-snapshot + diffing in the BACKGROUND - the window stays responsive...'
        $pb.Visibility = 'Visible'
        # The whole heavy diff (compare + raw diffs + report + change set + shortcuts + leftovers + cleanups) runs OFF the
        # UI thread now, so Analyze no longer freezes the window. The callback below only assigns + renders (fast).
        Start-SnapshotAnalyzeJob -Before $ctx.Before -AppVendor $AppVendor -AppName $AppName -OnDone {
          param($res, $err)
          $pb.Visibility = 'Collapsed'; $bAnalyze.IsEnabled = $true
          if ($err -or -not $res) { $lblStat.Text = "Analyze failed: $err"; return }
          # Assign the background-computed results (no diffing on the UI thread).
          $ctx.Diff=$res.Diff; $ctx.FileDiff=$res.FileDiff; $ctx.RegDiff=$res.RegDiff; $ctx.EnvChanges=@($res.EnvChanges); $ctx.Un=$res.Un; $ctx.AppTokens=$res.AppTokens
          $ctx.DiffUninstall=$res.Un; $ctx.Certs=@($res.Diff.Certificates.Added); $ctx.ReportText="$($res.ReportText)"; $ctx.ChangeSet=$res.ChangeSet
          $ctx.Shortcuts=@($res.Shortcuts); $ctx.Hkcu=@($res.Hkcu); $ctx.UserFiles=@($res.UserFiles); $ctx.LeftoverCandidates=$res.LeftoverCandidates
          $rep.Children.Clear(); $ctx.Cleanups.Clear()
          $txtReport.Text = "$($res.ReportText)"            # off-screen buffer (Save/Copy); the visible view is the tree
          $ctx.TreePanels=@{}; $ctx.TreeCategory='All'; Update-SnapInlineTree -Ctx $ctx   # render the inline change tree for the fresh result
          $un=$res.Un
          if ($un) { $lblSummary.Text = "App: $($un.DisplayName) $($un.DisplayVersion)$(if($un.ProductCode){"  -  $($un.ProductCode)"})" }
          else     { $lblSummary.Text = "No Add/Remove entry matched '$AppName' - see the tree." }
          # Recommended cleanup checkboxes (from the background-computed data).
          $cleanups = @($res.Cleanups)
          if ($cleanups.Count) {
              $ch = New-Object Windows.Controls.TextBlock; $ch.Text='Tick to REMOVE in the package (POST-INSTALL for shortcuts/Run keys, POST-UNINSTALL for certificate/driver cleanup):'; $ch.Foreground='#A0A8B4'; $ch.FontSize=12; $ch.Margin='0,2,0,4'; $ch.TextWrapping='Wrap'
              [void]$rep.Children.Add($ch)
              foreach ($c in $cleanups) {
                  [void](Add-ExclusionRow -Ctx $ctx -Label "$($c.Label)" -Command "$($c.Command)" -Checked ([bool]$c.Default))
              }
              if ($ctx.ExpExclusions) { $ctx.ExpExclusions.IsExpanded = $true }   # auto-open the exclusions section when there ARE some
          }
          $bApply.IsEnabled = $true; $bExclude.IsEnabled = $true; $bCopy.IsEnabled = $true; $bSave.IsEnabled = $true
          if ($bShots) { $bShots.IsEnabled = [bool](@($ctx.Shortcuts).Count) }
          if ($bLeftover) { $bLeftover.IsEnabled = [bool]$ctx.LeftoverCandidates }
          if ($bRunUn) { $bRunUn.IsEnabled = [bool]"$($un.Uninstall)".Trim() }
          $puMsg = ''
          if (@($ctx.Hkcu).Count -or @($ctx.UserFiles).Count) { $puMsg = "  Per-user footprint detected ($(@($ctx.Hkcu).Count) HKCU value(s), $(@($ctx.UserFiles).Count) profile file(s)) - pick a 'Per-user config' option to auto-apply them to every user." }
          # RELIABILITY signals: warn when the scan was capped (false add/delete possible) or nothing app-related changed.
          $incomplete = [bool]($ctx.Before._Incomplete -or $res.After._Incomplete)
          $appChanged = [bool]($un) -or (@($res.Diff.Programs.Added).Count -gt 0) -or (@($res.Diff.Services.Added).Count -gt 0) -or (@($res.Diff.ProgramDirs.Added).Count -gt 0) -or (@($res.FileDiff.New | Where-Object { $_.IsApp }).Count -gt 0) -or (@($res.RegDiff.New | Where-Object { $_.IsApp }).Count -gt 0)
          $relWarn = ''
          if ($incomplete) { $relWarn = "  [!] INCOMPLETE SCAN - a file/registry scan hit its limit; results may show false changes. Re-run on a less-full machine or raise the cap before trusting this." }
          elseif (-not $appChanged) { $relWarn = "  [!] No app changes detected - did the installer RUN AND FINISH before you clicked Analyze? Re-run the installer, then Analyze again." }
          $lblStat.Text = "Done - $(@($res.FileDiff.New).Count) file(s), $(@($res.RegDiff.New).Count) registry key(s), $(@($res.EnvChanges).Count) env var(s) (background noise hidden). Tick/add exclusions, then 'Apply'.$puMsg$relWarn"
          $lblStat.Foreground = if ($relWarn) { '#F48771' } else { '#A0A8B4' }
        }.GetNewClosure()
    }.GetNewClosure())

    $bApply.add_Click({
        $notes = New-Object System.Collections.Generic.List[string]
        $cleanupCmds = New-Object System.Collections.Generic.List[string]
        $exclusions  = New-Object System.Collections.Generic.List[object]   # full master list (ticked + unticked) - PERSISTED
        # Real installed footprint (sum of new app FILE bytes) -> drives FreeSpace so a tiny installer that expands
        # to GBs still reserves enough disk. 0 when nothing measured; Get-PayloadSizeMB still applies the 150 MB floor.
        $instMB = 0; try { if ($ctx.FileDiff -and $ctx.FileDiff.InstalledBytes) { $instMB = [int][Math]::Ceiling([double]$ctx.FileDiff.InstalledBytes / 1MB) } } catch {}
        $result = [ordered]@{ ProductCode=''; Uninstall=''; Detection=''; DisplayVersion=''; Notes=@(); CleanupCommands=@(); Exclusions=@(); ReportText=("$($ctx.ReportText)"); Shortcuts=@($ctx.Shortcuts); InstalledMB=$instMB; Hkcu=@($ctx.Hkcu); UserFiles=@($ctx.UserFiles); LeftoverCandidates=$ctx.LeftoverCandidates; LeftoverChecked=[bool]$ctx.LeftoverChecked; ChangeSet=$ctx.ChangeSet }
        $un = $ctx.DiffUninstall
        if ($un) {
            if ($un.ProductCode) { $result.ProductCode = $un.ProductCode }
            $result.Uninstall = $un.Uninstall
            $result.DisplayVersion = "$($un.DisplayVersion)"   # the REAL registry version - detection must use THIS, not the package version
            $result.Detection = "$($un.DisplayName) $($un.DisplayVersion)"
            $nU = [int]$un.UninstallCount
            if ($nU -gt 1) {
                $names = (@($un.AllUninstalls) | ForEach-Object { $_.DisplayName }) -join ', '
                $notes.Add("Snapshot: installs as '$($un.DisplayName)' $($un.DisplayVersion)$(if($un.ProductCode){" (ProductCode $($un.ProductCode))"}). Detected $nU uninstall entries ($names) - ALL written to the package's uninstall (reverse order). Verify each is part of THIS app (shared runtimes like VC++/.NET are excluded).")
            } else {
                $notes.Add("Snapshot: installs as '$($un.DisplayName)' $($un.DisplayVersion)$(if($un.ProductCode){" (ProductCode $($un.ProductCode))"}). Uninstall captured + written to the package: $($un.Uninstall)")
            }
        }
        # Remember EVERY exclusion (with its tick state) so re-opening shows them; only TICKED ones become ps1 commands.
        # TIMING (user rule): POST-UNINSTALL-tagged cleanup is written into the package ONLY after the after-uninstall
        # LEFTOVER CHECK has run - the install-snapshot Apply carries just the uninstall command + POST-INSTALL
        # exclusions. The deferred items stay ticked in the list; run '4. Leftover check' after uninstalling, then
        # Apply again and they (plus the real leftovers) go into POST-UNINSTALLATION.
        $deferred = 0
        foreach ($cc in $ctx.Cleanups) {
            $on = [bool]$cc.Chk.IsChecked
            $exclusions.Add([pscustomobject]@{ Label="$($cc.Item.Label)"; Command="$($cc.Item.Command)"; Checked=$on })
            if ($on -and "$($cc.Item.Command)".Trim()) {
                # Leftover-check + cert/driver post-uninstall items are DEFERRED until the leftover check runs; a MANUAL
                # post-uninstall exclude (the user chose it from the tree) is written immediately.
                if (("$($cc.Item.Command)" -match '(?i)#\s*\[post-uninstall\]') -and ("$($cc.Item.Command)" -notmatch '(?i)manual-exclude') -and -not $ctx.LeftoverChecked) { $deferred++; continue }
                $cleanupCmds.Add("$($cc.Item.Command)"); $notes.Add("Exclusion applied: $($cc.Item.Label)")
            }
        }
        if ($deferred) { $notes.Add("$deferred POST-UNINSTALL cleanup item(s) DEFERRED - they are written only after the '4. Leftover check (after uninstall)' has run (uninstall the app, run the check, then Apply again).") }
        $result.Notes = $notes.ToArray()
        $result.CleanupCommands = $cleanupCmds.ToArray()
        $result.Exclusions = $exclusions.ToArray()
        $ctx.Result = $result
        $win.DialogResult = $true
    }.GetNewClosure())

    # 4. AFTER-UNINSTALL LEFTOVER CHECK: user manually uninstalls, then this LIVE-checks everything the install created
    #    and turns what's still on disk/registry into ticked POST-UNINSTALLATION cleanup items (existing Apply pipe).
    $bLeftover.add_Click({
        $cands = if ($ctx.LeftoverCandidates) { $ctx.LeftoverCandidates } else { $stateRef.SnapshotLeftoverCandidates }
        if (-not $cands) { $lblStat.Text = 'No install snapshot data - run Analyze (or Load report...) first.'; return }
        $ans = [Windows.MessageBox]::Show("Run the AFTER-UNINSTALL leftover check now?`n`nDo this AFTER you manually UNINSTALLED the app on THIS machine. The tool live-checks every file / folder / registry key / shortcut the INSTALL created and lists what the uninstaller LEFT BEHIND (incl. now-empty folders). Ticked leftovers become POST-UNINSTALLATION cleanup commands on Apply.", 'Uninstall leftover check', 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }
        $lblStat.Text = 'Checking what the uninstaller left behind...'
        $left = @(Get-UninstallLeftovers -Candidates $cands)
        $stampTxt = "=== UNINSTALL LEFTOVERS (checked $(Get-Date -Format 'HH:mm:ss')) ==="
        # Show the RESULT prominently in the tree pane (the main visible area) - the previous version only wrote to the
        # off-screen report + the collapsed exclusions panel, so nothing appeared. A 'Change tree' button restores the view.
        $ctx.CatBar.Children.Clear()
        $back = New-Object Windows.Controls.Button; $back.Content=([char]0x25C0 + ' Change tree'); $back.Padding='8,5'; $back.Margin='0,0,0,4'; $back.FontSize=12; $back.HorizontalAlignment='Stretch'; $back.HorizontalContentAlignment='Left'
        $back.add_Click({ Update-SnapInlineTree -Ctx $ctx }.GetNewClosure())
        [void]$ctx.CatBar.Children.Add($back)
        if (-not $left.Count) {
            $ctx.LeftoverChecked = $true   # the check RAN - deferred post-uninstall items may apply now
            $ctx.TreeHdr.Text = 'After uninstall: nothing left behind'; $ctx.TreeHdr.ToolTip = $null
            $msg = New-Object Windows.Controls.TextBlock; $msg.Text='CLEAN UNINSTALL - nothing the install created was left behind on this machine.'; $msg.Foreground='#6A9955'; $msg.Margin='10'; $msg.TextWrapping='Wrap'; $ctx.TreeSV.Content = $msg
            $lblStat.Text = 'CLEAN UNINSTALL - nothing left behind. No extra cleanup needed.'
            $txtReport.Text = "$($txtReport.Text)`r`n`r`n$stampTxt`r`nNone - the uninstaller removed everything it installed."
            $ctx.ReportText = $txtReport.Text
            $bApply.IsEnabled = $true
            return
        }
        # A REAL after-uninstall DIFF (removed / left-behind / added) of the app footprint, rendered by the SAME tree as
        # the install diff (green added / amber left-behind / red removed by uninstaller) - the reliability view.
        $ucs = if (Get-Command New-UninstallChangeSet -EA SilentlyContinue) { New-UninstallChangeSet -Candidates $cands -AppName ("$AppVendor $AppName".Trim()) } else { $null }
        if ($ucs) {
            $ctx.TreeHdr.Text = "After uninstall:  $($ucs.Counts.deleted) removed by the uninstaller  Â·  $($ucs.Counts.modified) LEFT BEHIND  Â·  $($ucs.Counts.new) added"; $ctx.TreeHdr.ToolTip = 'red = removed by the uninstaller, amber = left behind (clean these), green = added. Right-click a row to copy its path or exclude it.'
            $ctx.TreeSV.Content = New-SnapTreeBody -ChangeSet $ucs -Ctx $ctx
        } else {
            $ctx.TreeHdr.Text = "After uninstall: $($left.Count) left behind"; $ctx.TreeHdr.ToolTip = $null
        }
        # Actionable cleanup: the LEFT-BEHIND items become ticked exclusion rows (post-uninstall; timing changeable).
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($c in $left) {
            # Default tick: install-created leftovers ON; vendor-shared runtime data OFF (Default=$false) - a human decides.
            $tick = if ($c.ContainsKey('Default')) { [bool]$c.Default } else { $true }
            [void](Add-ExclusionRow -Ctx $ctx -Label "$($c.Label)" -Command "$($c.Command)" -Checked $tick)
            $lines.Add("  $(if($tick){'[x]'}else{'[ ]'}) $($c.Label)")
        }
        if ($ctx.ExpExclusions) { $ctx.ExpExclusions.IsExpanded = $true }   # make the tick-to-clean checkboxes visible
        $ctx.LeftoverChecked = $true   # post-uninstall cleanup may now be written on Apply (deferred until this check)
        $txtReport.Text = "$($txtReport.Text)`r`n`r`n$stampTxt`r`n" + ($lines -join "`r`n")
        $ctx.ReportText = $txtReport.Text
        $bApply.IsEnabled = $true
        $lblStat.Text = "After uninstall: $(if($ucs){"$($ucs.Counts.deleted) removed / "})$($left.Count) left behind$(if($ucs -and $ucs.Counts.new){" / $($ucs.Counts.new) added"}) - see the tree; tick leftovers in Exclusions, then Apply."
    }.GetNewClosure())

    # LOAD a saved snapshot report (auto-saved on every Apply) - restores report/exclusions/shortcuts/leftover data so
    # actions can be re-applied, shortcuts screenshotted, or the leftover check run, without re-running the installer.
    $bLoad.add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = 'Snapshot reports (*.snapshot.json)|*.snapshot.json|All files (*.*)|*.*'
        $repDir = Get-WorkPath 'Reports'; if (Test-Path $repDir) { $dlg.InitialDirectory = $repDir }
        if (-not $dlg.ShowDialog()) { return }
        $st = Read-SnapshotState -Path $dlg.FileName
        if (-not $st) { $lblStat.Text = "Could not load: $($dlg.FileName)"; return }
        $ctx.ReportText = "$($st.ReportText)"; $txtReport.Text = "$($st.ReportText)"
        $rep.Children.Clear(); $ctx.Cleanups.Clear()
        foreach ($x in @($st.Exclusions)) {
            [void](Add-ExclusionRow -Ctx $ctx -Label "$($x.Label)" -Command "$($x.Command)" -Checked ([bool]$x.Checked))
        }
        $ctx.Shortcuts = @($st.Shortcuts); $ctx.Hkcu = @($st.Hkcu); $ctx.UserFiles = @($st.UserFiles)
        $ctx.LeftoverCandidates = $st.LeftoverCandidates
        $ctx.LeftoverChecked = [bool]$st.LeftoverChecked
        # Restore the change set (JSON -> hashtables) so the Tree view works on a LOADED report, not just a fresh analyze.
        # A report saved by an OLDER build has no ChangeSet - rebuild a structural one from the leftovers/shortcuts it does have.
        $ctx.ChangeSet =
            if ($st.ChangeSet -and (Get-Command ConvertTo-PBHashtable -EA SilentlyContinue)) { ConvertTo-PBHashtable $st.ChangeSet }
            elseif ($st.ChangeSet) { $st.ChangeSet }
            elseif ((@($st.LeftoverCandidates).Count -or @($st.Shortcuts).Count) -and (Get-Command New-SnapshotChangeSetFromState -EA SilentlyContinue)) { New-SnapshotChangeSetFromState -State $st -AppName "$($st.Detection)" }
            else { $null }
        # Rebuild the minimal detected-app info so Apply re-writes uninstall/detection exactly as the original Apply did.
        if ("$($st.Uninstall)".Trim() -or "$($st.ProductCode)".Trim()) {
            $ctx.DiffUninstall = @{ ProductCode="$($st.ProductCode)"; Uninstall="$($st.Uninstall)"; DisplayName="$($st.Detection)"; DisplayVersion=''; UninstallCount=1; AllUninstalls=@() }
        }
        if ([int]$st.InstalledMB -gt 0) { $ctx.FileDiff = @{ InstalledBytes = [int64]$st.InstalledMB * 1MB } }
        $ctx.TreePanels=@{}; $ctx.TreeCategory = 'All'; Update-SnapInlineTree -Ctx $ctx   # render the inline change tree from the loaded report
        if (@($st.Exclusions).Count -and $ctx.ExpExclusions) { $ctx.ExpExclusions.IsExpanded = $true }
        $bApply.IsEnabled = $true; $bSave.IsEnabled = $true; $bExclude.IsEnabled = $true
        if ($bShots) { $bShots.IsEnabled = [bool](@($ctx.Shortcuts).Count) }
        if ($bLeftover) { $bLeftover.IsEnabled = [bool]$ctx.LeftoverCandidates }
        $lblStat.Text = "Loaded report: $(Split-Path $dlg.FileName -Leaf). Re-apply, screenshot shortcuts, or run the leftover check - no re-install needed."
    }.GetNewClosure())

    $win.Content = $w
    # Whatever happened inside (a screenshot job that never called back, an error mid-capture), the main window
    # must be back on screen when this dialog is gone - it was hidden through Win32 for the captures.
    $win.Add_Closed({ Show-PBMainWindow (Get-PBMainWindow) })
    if ($win.ShowDialog()) { return $ctx.Result }
    return $null
}

# RUN & CAPTURE dialog: the user runs the installer (it drops the MSI in a temp folder); we snapshot before and
# list what the run added, then copy the MSI (+ sibling cabs) and switch to MSI+MST. Does NOT auto-run anything.
function Show-MsiCaptureDialog {
    param([Parameter(Mandatory)][string]$ExePath)
    $dirs = Get-MsiWatchDirs
    $baseline = Get-MsiSnapshot -Dirs $dirs
    $setupBase = Get-SetupSnapshot -Dirs $dirs   # for nested-setup awareness (wrapper extracts another setup)
    $w = New-Object Windows.Controls.Grid
    $win = New-Object Windows.Window
    $win.Title = "Run & capture MSI - $(Split-Path $ExePath -Leaf)"
    $win.Width = 780; $win.Height = 520; $win.WindowStartupLocation = 'CenterOwner'; $win.Owner = $script:Win
    $win.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x18,0x1A,0x1F)))
    if (Get-Command Apply-PbTheme -ErrorAction SilentlyContinue) { Apply-PbTheme $win }
    $w.Margin = '14'
    foreach ($h in 'Auto','Auto','*','Auto') { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = $h; [void]$w.RowDefinitions.Add($rd) }
    $hint = New-Object Windows.Controls.TextBlock; $hint.TextWrapping='Wrap'; $hint.Foreground='#56C8D6'; $hint.FontSize=12; $hint.Margin='0,0,0,10'
    $hint.Text = "For installers that BUILD the MSI at runtime. 1) Run the installer (button, or run it yourself) - it extracts the MSI to a temp folder; you do NOT have to finish installing.  2) Click 'Scan for new MSI'.  3) Pick the MSI + 'Use selected'. WARNING: this RUNS the installer on THIS machine - clean up / uninstall afterwards."
    [Windows.Controls.Grid]::SetRow($hint,0); [void]$w.Children.Add($hint)
    $bar = New-Object Windows.Controls.StackPanel; $bar.Orientation='Horizontal'; $bar.Margin='0,0,0,8'
    $bSandbox = New-Object Windows.Controls.Button; $bSandbox.Content='Run in Sandbox (auto)'; $bSandbox.Padding='12,4'; $bSandbox.Margin='0,0,8,0'
    try { $bSandbox.Style = $script:Win.FindResource('PbAccentButton') } catch {}
    $bSandbox.ToolTip = 'Run the installer in a throwaway Windows Sandbox VM and capture the MSI automatically - safe (never touches this machine) and self-cleaning. Needs Windows Sandbox enabled.'
    if (-not (Get-Command Test-SandboxAvailable -EA SilentlyContinue) -or -not (Test-SandboxAvailable)) { $bSandbox.IsEnabled = $false; $bSandbox.ToolTip = 'Windows Sandbox is not enabled on this machine (enable the "Windows Sandbox" optional feature to use automatic capture).' }
    $bRun  = New-Object Windows.Controls.Button; $bRun.Content='Run installer (manual)'; $bRun.Padding='12,4'; $bRun.Margin='0,0,8,0'
    $bScan = New-Object Windows.Controls.Button; $bScan.Content='Scan for new MSI'; $bScan.Padding='12,4'; $bScan.Margin='0,0,8,0'
    $lblStat = New-Object Windows.Controls.TextBlock; $lblStat.VerticalAlignment='Center'; $lblStat.Foreground='#A0A8B4'; $lblStat.FontSize=11
    [void]$bar.Children.Add($bSandbox); [void]$bar.Children.Add($bRun); [void]$bar.Children.Add($bScan); [void]$bar.Children.Add($lblStat)
    [Windows.Controls.Grid]::SetRow($bar,1); [void]$w.Children.Add($bar)
    $bSandbox.add_Click({
        $sb = Start-SandboxCapture -ExePath $ExePath
        if (-not $sb) { $lblStat.Text = 'Could not launch the sandbox.'; return }
        $lblStat.Text = 'Sandbox launched - running the installer in isolation and capturing... (this can take a few minutes)'
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(3)
        $deadline = (Get-Date).AddMinutes(8)
        $timer.add_Tick({
            $done = Test-Path (Join-Path $sb.Out '_done.txt')
            $msis = @(Get-ChildItem $sb.Out -Filter *.msi -File -EA SilentlyContinue)
            if ($msis.Count -gt 0) {
                $list.Items.Clear()
                foreach ($f in $msis) { [void]$list.Items.Add([pscustomobject]@{ Display = "$($f.Name)   $([math]::Round($f.Length/1MB,1))MB   [sandbox]"; Info = $f }) }
            }
            $lblStat.Text = "sandbox capturing... $($msis.Count) MSI(s) so far$(if($done){' - done'}else{''})"
            if ($done -or (Get-Date) -gt $deadline) {
                $timer.Stop()
                $lblStat.Text = if ($done) { "Sandbox finished - $($msis.Count) MSI(s) captured. Pick + Use selected." } else { "Sandbox timed out - $($msis.Count) MSI(s) so far. Pick + Use, or retry." }
            }
        }.GetNewClosure())
        $timer.Start()
    }.GetNewClosure())
    $list = New-Object Windows.Controls.ListBox; $list.SelectionMode='Extended'; $list.Background='#15171B'; $list.Foreground='#E7E9ED'; $list.FontFamily='Consolas'; $list.FontSize=12; $list.DisplayMemberPath='Display'
    [Windows.Controls.Grid]::SetRow($list,2); [void]$w.Children.Add($list)
    $dp = New-Object Windows.Controls.DockPanel; $dp.LastChildFill=$false; $dp.Margin='0,10,0,0'
    $chkFolder = New-Object Windows.Controls.CheckBox; $chkFolder.Content='Copy the whole extract folder (cabs/transforms)'; $chkFolder.Foreground='#E7E9ED'; $chkFolder.VerticalAlignment='Center'
    [Windows.Controls.DockPanel]::SetDock($chkFolder,'Left'); [void]$dp.Children.Add($chkFolder)
    $bCancel = New-Object Windows.Controls.Button; $bCancel.Content='Cancel'; $bCancel.Padding='12,4'; $bCancel.IsCancel=$true
    [Windows.Controls.DockPanel]::SetDock($bCancel,'Right'); [void]$dp.Children.Add($bCancel)
    $bUse = New-Object Windows.Controls.Button; $bUse.Content='Use selected'; $bUse.Padding='16,4'; $bUse.Margin='0,0,8,0'
    try { $bUse.Style = $script:Win.FindResource('PbAccentButton') } catch {}
    [Windows.Controls.DockPanel]::SetDock($bUse,'Right'); [void]$dp.Children.Add($bUse)
    [Windows.Controls.Grid]::SetRow($dp,3); [void]$w.Children.Add($dp)
    $bRun.add_Click({
        if ((Get-Command Test-IsSecurityProduct -EA SilentlyContinue) -and (Test-IsSecurityProduct "$ExePath")) {
            $sec = [Windows.MessageBox]::Show("'$([IO.Path]::GetFileName($ExePath))' looks like a SECURITY / EDR / AV product. Re-running it on a real endpoint is normally BLOCKED - tamper protection or the resident agent (SentinelOne/McAfee) kills it with 'invalid image' or a DLL error, so the MSI won't drop.`n`nSafer: Cancel and use 'Check for bundled MSI' (extracts the MSI with NO execution), or 'Run in Sandbox'.`n`nRun it on THIS machine anyway?", 'Security product detected', 'YesNo', 'Warning')
            if ($sec -ne 'Yes') { $lblStat.Text = "Cancelled - try 'Check for bundled MSI' (no execution) or a sandbox."; return }
        }
        $ans = [Windows.MessageBox]::Show("This RUNS the installer on this machine:`n$ExePath`n`nIt may fully install the product (for an EDR/agent that is hard to undo). The tool copies it to a LOCAL folder first (a network/UNC path fails once the installer elevates). Continue?", 'Run installer', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { return }
        $lblStat.Text = 'Copying the installer locally, then launching elevated...'
        try { (Get-PBMainWindow).Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch {}
        $local = Copy-InstallerLocal -ExePath $ExePath
        if (-not $local -or -not (Test-Path $local)) { $lblStat.Text = 'Could not copy the installer to a local folder.'; return }
        $r = Start-InstallerLaunch -Path $local
        if ($r.Ok) { $lblStat.Text = "Launched from a LOCAL copy $([IO.Path]::GetFileName($local)) ($($r.Mode)). Let it extract, then click 'Scan for new MSI'." }
        else { $lblStat.Text = "Launch failed: $($r.Error). If UAC was declined, re-try; if policy blocks it, run the installer yourself, then Scan." }
    }.GetNewClosure())
    $bScan.add_Click({
        $found = @(Get-NewMsisSince -Dirs $dirs -Snapshot $baseline -MinKB 100)
        $list.Items.Clear()
        foreach ($f in $found) { [void]$list.Items.Add([pscustomobject]@{ Display = "$($f.Name)   $([math]::Round($f.Length/1MB,1))MB   [$($f.DirectoryName)]"; Info = $f }) }
        $setups = @(Get-NewSetupsSince -Dirs $dirs -Snapshot $setupBase)
        $msg = "$($found.Count) new MSI(s) since this dialog opened."
        if ($found.Count -eq 0 -and $setups.Count -gt 0) { $msg += "  No MSI yet, but the wrapper extracted $($setups.Count) setup file(s) (e.g. $($setups[0].Name)) - let the installer run further (it may run that to build the MSI), then Scan again." }
        elseif ($setups.Count -gt 0) { $msg += "  (+$($setups.Count) other setup/exe extracted.)" }
        $lblStat.Text = $msg
    }.GetNewClosure())
    # Shared REF object: a $script: write inside the .GetNewClosure() handler lands in the closure's own scope
    # and the function body would always read $null (Use button returned nothing). A hashtable is by-reference.
    $capRef = @{ Result = $null }
    $bUse.add_Click({
        # Order by appearance time = the order the wrapper extracted/installed them = the install order for a
        # multi-installer package (the package then installs in this order, uninstalls in reverse).
        $sel = @($list.SelectedItems | Sort-Object { $_.Info.LastWriteTimeUtc })
        if (-not $sel.Count) { $lblStat.Text = 'Pick at least one MSI from the list.'; return }
        $dest = Get-WorkPath ('CapturedMsi\' + [IO.Path]::GetFileNameWithoutExtension((Split-Path $ExePath -Leaf)))
        try { Get-ChildItem -LiteralPath $dest -File -EA SilentlyContinue | Remove-Item -Force -EA SilentlyContinue } catch {}
        $res = New-Object System.Collections.Generic.List[string]
        foreach ($it in $sel) { $p = Copy-CapturedMsi -MsiPath $it.Info.FullName -DestDir $dest -WholeFolder:([bool]$chkFolder.IsChecked); if ($p) { $res.Add($p) } }
        $capRef.Result = $res.ToArray()
        $win.DialogResult = $true
    }.GetNewClosure())
    $win.Content = $w
    Set-PBDialogChrome -Window $win -Glyph 'E9D9' -Title 'Run and capture MSI' -Subtitle (Split-Path $ExePath -Leaf)
    if ($win.ShowDialog()) { return $capRef.Result }
    return $null
}
# Run-and-capture the MSI a wrapper builds at runtime. Reusable for a lone EXE (replaces source) or one EXE in a
# chain (-ReplaceInChain swaps just that installer). $StatusLabel optional.
function Invoke-RunCapture {
    param([Parameter(Mandatory)]$Exe, [switch]$ReplaceInChain, $StatusLabel)
    $st = { param($t,$c='#B7BEC8') if ($StatusLabel) { $StatusLabel.Text="$t"; $StatusLabel.Foreground="$c" } }
    if (-not $Exe) { return }
    if (-not (Get-Command Show-MsiCaptureDialog -ErrorAction SilentlyContinue)) { return }
    $caps = Show-MsiCaptureDialog -ExePath $Exe.FullName
    if (-not $caps -or -not @($caps).Count) { & $st 'No MSI captured.' '#B7BEC8'; return }
    if ($ReplaceInChain) { Replace-InstallerInChain -OldFullName $Exe.FullName -NewPaths @($caps) }
    else { $script:State.ChosenInstallers = @(); Add-ManualInstallers -Paths @($caps) }
    $names = (@($caps) | ForEach-Object { Split-Path $_ -Leaf }) -join ', '
    $script:State.SourceNotes = @("MSI ($names) was CAPTURED from a run of the wrapper '$($Exe.Name)'. The wrapper may also install prerequisites / set registry that the bare MSI does NOT - TEST the package. Also clean up / uninstall whatever the test run installed on this machine.")
    & $st "Captured $names - package switched to MSI+MST. Review the warning + clean up the test install." '#6A9955'
    Populate-Step2
}
$BtnCaptureMsi.add_Click({
    $exe = @($script:State.ChosenInstallers) | Where-Object { $_.Extension -and $_.Extension.ToLower() -eq '.exe' } | Select-Object -First 1
    if ($exe) { Invoke-RunCapture -Exe $exe -StatusLabel $LblBundled }
})
$BtnSnapshot.add_Click({
    $ins  = @($script:State.ChosenInstallers)
    $pick = @($ins | Where-Object { $_.Extension } | Sort-Object @{e={$_.Extension.ToLower() -eq '.exe'};Descending=$true} | Select-Object -First 1)[0]
    if (-not (Get-Command Show-SnapshotDialog -ErrorAction SilentlyContinue)) { return }
    # Installer is OPTIONAL: with none selected the snapshot opens in MANUAL mode (the user runs/installs the app via the
    # Admin/SYSTEM console inside the dialog, then Analyze). With one selected, 'Run installer' can auto-run it.
    $exePath = if ($pick) { $pick.FullName } else { '' }
    if (-not $pick) { $LblSnapshot.Text = 'No installer selected - opening snapshot in manual mode (run/install via the Admin/SYSTEM console, then Analyze).'; $LblSnapshot.Foreground='#56C8D6' }
    $vend = "$($script:State.Parsed.Vendor)"; $app = "$($script:State.Parsed.AppName)"
    # Re-open with the SAVED report + exclusions (persisted until Reset) so closing the window never loses them and
    # the packager can come back from Step 3 to add more exclusions.
    $res = Show-SnapshotDialog -ExePath $exePath -AppVendor $vend -AppName $app -ExistingReport "$($script:State.SnapshotReport)" -ExistingExclusions @($script:State.SnapshotExclusions)
    if (-not $res) { return }
    # Auto-write into the package: MSI product code -> uninstall + detection; the captured uninstall command and the
    # ticked exclusions (remove desktop shortcut / Run key / file / folder / key, disable auto-update) -> the ps1.
    if ($res.ProductCode -and -not "$($script:State.ProductCode)".Trim()) {
        if ($TxtPC) { $TxtPC.Text = $res.ProductCode } else { $script:State.ProductCode = $res.ProductCode; Invalidate-From 3 }
    }
    if ("$($res.Uninstall)".Trim())  { $script:State.SnapshotUninstall = $res.Uninstall }
    if ("$($res.DisplayVersion)".Trim()) { $script:State.SnapshotDisplayVersion = "$($res.DisplayVersion)" }   # full version from ARP - wins in SoftIdent
    $script:State.SnapshotCleanupCommands  = @($res.CleanupCommands)
    $script:State.SnapshotExclusions       = @($res.Exclusions)   # PERSIST the full exclusion list (re-openable)
    $script:State.SnapshotShortcuts        = @($res.Shortcuts)    # reference shortcuts for the integration-time diff
    $script:State.SnapshotHkcu             = @($res.Hkcu)         # detected HKCU values -> auto-fill Per-user config
    $script:State.SnapshotUserFiles        = @($res.UserFiles)    # detected per-user files -> staged + copied to every profile
    if ([int]$res.InstalledMB -gt 0) { $script:State.SnapshotInstalledMB = [int]$res.InstalledMB }   # real footprint -> FreeSpace floor
    if ("$($res.ReportText)".Trim())  { $script:State.SnapshotReport = "$($res.ReportText)" }   # PERSIST the report
    $script:State.SnapshotNotes            = @($res.Notes)
    if ($res.LeftoverCandidates) { $script:State.SnapshotLeftoverCandidates = $res.LeftoverCandidates }   # -> after-uninstall leftover check
    $script:State.SnapshotLeftoverChecked = [bool]$res.LeftoverChecked
    # AUTO-SAVE the full, RE-LOADABLE report to the work folder (Reports\<pkg>.snapshot.json) - 'Load report...' in the
    # dialog restores everything later (re-apply actions / screenshot shortcuts / leftover check), even after a restart.
    if (Get-Command Save-SnapshotState -EA SilentlyContinue) {
        $snapName = if ($script:State.Parsed -and $script:State.Parsed.IsValid) { $script:State.Parsed.FullName } else { "$app" }
        [void](Save-SnapshotState -Path (Join-Path (Get-WorkPath 'Reports') "$snapName.snapshot.json") -Data @{
            SavedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Package="$snapName"
            ReportText="$($res.ReportText)"; Exclusions=@($res.Exclusions); Shortcuts=@($res.Shortcuts)
            Hkcu=@($res.Hkcu); UserFiles=@($res.UserFiles); InstalledMB=[int]$res.InstalledMB
            Uninstall="$($res.Uninstall)"; ProductCode="$($res.ProductCode)"; Detection="$($res.Detection)"
            Notes=@($res.Notes); CleanupCommands=@($res.CleanupCommands); LeftoverCandidates=$res.LeftoverCandidates; LeftoverChecked=[bool]$res.LeftoverChecked
            ChangeSet=$res.ChangeSet })   # ChangeSet drives the Tree view on a LOADED report (was missing -> tree came up empty)
    }
    Invalidate-From 3
    if (Get-Command Update-ReviewButton -EA SilentlyContinue) { Update-ReviewButton }
    $nclean = @($res.CleanupCommands).Count
    $LblSnapshot.Text = "Snapshot saved: uninstall$(if($res.ProductCode){" + product code"}) + $nclean exclusion(s) -> ps1. Re-open 'Analyze installer' anytime to add more (kept until Reset)."
    $LblSnapshot.Foreground = '#6A9955'
})
# Step 2 edits: write to state and invalidate the (not-yet-built) Step 3 script.
$TxtPC.add_TextChanged({
    if ($script:Rehydrating) { return }
    $script:State.ProductCode = $TxtPC.Text.Trim()
    Invalidate-From 3
})
# Single-MSI MST cleanup toggles (KEEP = don't remove), stored per MSI. Only affect Step-4 MST.
$ChkKeepShortcut.add_Click({ if ($script:Rehydrating) { return } ; $ins=@($script:State.ChosenInstallers); if ($ins.Count -ge 1) { (Get-MsiFlags $ins[0].FullName).KeepShortcut = [bool]$ChkKeepShortcut.IsChecked } })
$ChkKeepStartup.add_Click({  if ($script:Rehydrating) { return } ; $ins=@($script:State.ChosenInstallers); if ($ins.Count -ge 1) { (Get-MsiFlags $ins[0].FullName).KeepStartup  = [bool]$ChkKeepStartup.IsChecked } })
$ChkKeepStray.add_Click({    if ($script:Rehydrating) { return } ; $ins=@($script:State.ChosenInstallers); if ($ins.Count -ge 1) { (Get-MsiFlags $ins[0].FullName).KeepStray    = [bool]$ChkKeepStray.IsChecked } })
$ChkKeepRunKey.add_Click({   if ($script:Rehydrating) { return } ; $ins=@($script:State.ChosenInstallers); if ($ins.Count -ge 1) { (Get-MsiFlags $ins[0].FullName).KeepRunKey   = [bool]$ChkKeepRunKey.IsChecked } })
$ChkGenerateMst.add_Click({  if ($script:Rehydrating) { return } ; $script:State.GenerateMst = [bool]$ChkGenerateMst.IsChecked
                             # hide the MST cleanup + properties options when not generating an MST
                             $vis = if ($ChkGenerateMst.IsChecked) { 'Visible' } else { 'Collapsed' }
                             if ($PnlMstFlags) { $PnlMstFlags.Visibility = $vis }; if ($PnlMsiProps) { $PnlMsiProps.Visibility = $vis }
                             Invalidate-From 3 })
$TxtMsiProps.add_TextChanged({   if ($script:Rehydrating) { return } ; if (-not $script:State.MsiProps) { $script:State.MsiProps=@{} }
                                  $ins=@($script:State.ChosenInstallers); if ($ins.Count -ge 1) { $script:State.MsiProps[$ins[0].FullName]=$TxtMsiProps.Text } })
$TxtInstArgs.add_TextChanged({   if ($script:Rehydrating) { return } ; $script:State.InstallParams  =$TxtInstArgs.Text;   Invalidate-From 3 })
$TxtUninstArgs.add_TextChanged({ if ($script:Rehydrating) { return } ; $script:State.UninstallParams=$TxtUninstArgs.Text; Invalidate-From 3 })
$ChkArp.add_Click({              if ($script:Rehydrating) { return } ; $script:State.LooseArp     =[bool]$ChkArp.IsChecked;          Invalidate-From 3 })
$ChkLooseShortcut.add_Click({    if ($script:Rehydrating) { return } ; $script:State.LooseShortcut=[bool]$ChkLooseShortcut.IsChecked; Invalidate-From 3 })
$TxtLooseTargets.add_TextChanged({ if ($script:Rehydrating) { return } ; $script:State.LooseTargets=$TxtLooseTargets.Text; Invalidate-From 3 })
# Per-user configuration dropdown: None / All-users registry / Active Setup. Maps the selection to State.PerUserMode
# (Build-Step3Script then auto-generates the PSADT v4 code); a one-line hint explains what each option does.
# PER-USER CONFIG (HKCU / profile files): chosen in the analyzer's footer (where the snapshot shows what the app keeps
# per user), the tool generates the PSADT v4 code. Text + index helpers shared by the analyzer and the build.
function Get-PerUserHintText {
    param([string]$Mode)
    switch ("$Mode") {
        'AllUsersReg' { 'Writes the HKCU settings to every existing user and the default profile at install time (edit the generated Invoke-ADTAllUsersRegistryAction block).' }
        'ActiveSetup' { 'Stages a per-user stub (.ps1) in SupportFiles that runs once per user at logon - also covers users created later (edit the stub for this app''s HKCU settings).' }
        default       { 'No per-user code is generated.' }
    }
}
function Get-PerUserModeIndex { param([string]$Mode) switch ("$Mode") { 'AllUsersReg' {1} 'ActiveSetup' {2} default {0} } }
function Set-PerUserMode {
    param([int]$Index)
    $script:State.PerUserMode = switch ($Index) { 1 {'AllUsersReg'} 2 {'ActiveSetup'} default {'None'} }
    Invalidate-From 3
}
function Update-PerUserHint { if ($LblPerUser) { $LblPerUser.Text = Get-PerUserHintText -Mode $script:State.PerUserMode } }

$BtnResetStep.add_Click({ Reset-Step $script:Step })
$BtnResetAll.add_Click({  Reset-All })

# ---- Step 4 Publish (SCCM / Intune) ----
$BtnLoadOutgoing.add_Click({
    $name = $TxtPubPkgName.Text.Trim()
    if (-not $name) { $LblPublishLog.Text = 'Enter a package name to load.'; $LblPublishLog.Foreground = '#F48771'; return }
    # SYNCHRONOUS (reverted from async - closure-scope reliability, same as BtnPred/BtnFetch). Plain add_Click so
    # $script:State + Populate-Publish resolve directly.
    $BtnLoadOutgoing.IsEnabled = $false
    $LblPublishLog.Text = "Searching Outgoing for '$name'..."; $LblPublishLog.Foreground = '#A0A8B4'
    try { $script:Win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch {}
    $p = $null
    try { $p = Find-OutgoingPackage -Name $name }
    catch { Write-Log "Outgoing search failed: $($_.Exception.Message)" Error }
    $BtnLoadOutgoing.IsEnabled = $true
    if (-not $p) { $LblPublishLog.Text = "Package '$name' not found under the Outgoing path (settings.json -> OutgoingPath)."; $LblPublishLog.Foreground = '#F48771'; return }
    $script:State.CreatedPath = "$p"
    Populate-Publish
})
$BtnBrowsePkg.add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select a built package folder (the one containing Content\Invoke-AppDeployToolkit.ps1)'
    $og = Get-Setting 'OutgoingPath'
    if ($og -and (Test-Path $og)) { $dlg.SelectedPath = $og }
    if ($dlg.ShowDialog() -eq 'OK') { $script:State.CreatedPath = $dlg.SelectedPath; Populate-Publish }
})
# Run a publish (SCCM/Intune) on a BACKGROUND runspace so the window stays responsive and the
# progress bar animates; a DispatcherTimer polls for completion and shows the result.
# Run a scriptblock in a BACKGROUND runspace (full engine loaded) and hand the result to $Done on the UI thread.
# This keeps SHARE ENUMERATION (find source / predecessor candidates / outgoing search) off the UI thread - the
# window stays responsive instead of going "(Not Responding)" while a 900-package share is walked.
# $Done receives @{ Ok; Result } on success or @{ Ok=$false; Error } on failure.
function Invoke-PBAsync {
    param([Parameter(Mandatory)][scriptblock]$Work, [hashtable]$Arg = @{}, [Parameter(Mandatory)][scriptblock]$Done)
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $ps = [PowerShell]::Create(); $ps.Runspace = $rs
    $payload = @{ engine = $script:PBEngineSource; root = "$root"; work = $Work.ToString(); arg = $Arg }
    [void]$ps.AddScript({
        param($p)
        try {
            if ($p.engine) { . ([scriptblock]::Create($p.engine)) }
            else {
                . "$($p.root)\Core.ps1"; . "$($p.root)\Predecessor.ps1"; . "$($p.root)\Build.ps1"; . "$($p.root)\Source.ps1"
                . "$($p.root)\Snippets.ps1"; . "$($p.root)\MstBuilder.ps1"; . "$($p.root)\Sccm.ps1"; . "$($p.root)\Intune.ps1"
                . "$($p.root)\PSADT_V3toV4_Mappings.ps1"
            }
            Initialize-Config (Join-Path $p.root 'settings.json')
            @{ Ok = $true; Result = (& ([scriptblock]::Create($p.work)) $p.arg) }
        } catch { @{ Ok = $false; Error = "$($_.Exception.Message)" } }
    }).AddArgument($payload)
    $handle = $ps.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $timer.add_Tick({
        if (-not $handle.IsCompleted) { return }
        $timer.Stop()
        $out = $null; try { $out = $ps.EndInvoke($handle) } catch {}
        try { $ps.Dispose(); $rs.Close(); $rs.Dispose() } catch {}
        $r = if ($out -and $out.Count) { $out[0] } else { @{ Ok = $false; Error = 'background call returned nothing' } }
        & $Done $r
    }.GetNewClosure())
    $timer.Start()
}

function Start-PublishJob {
    param([ValidateSet('sccm','intune')][string]$Target, [hashtable]$Fields)
    $createdPath = "$($script:State.CreatedPath)"
    # Shared, thread-safe progress object: the runspace writes (via Set-PbProgress), the UI timer reads.
    $prog = [hashtable]::Synchronized(@{ Percent = 0; Status = 'Starting...'; Indeterminate = $true })
    $jobArgs = @{ root=$root; target=$Target; fields=$Fields; createdPath=$createdPath; progress=$prog
               engine=$script:PBEngineSource
               distribute=$true; collections=$true; deploy=$true
               allow=[bool]$ChkPubAllowInteract.IsChecked; ritm="$($script:State.Ritm)" }
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $psi = [PowerShell]::Create(); $psi.Runspace = $rs
    $psi.AddScript({
        param($a)
        if ($a.engine) { . ([scriptblock]::Create($a.engine)) }   # MERGED/EXE build: engine from embedded source
        else {
            . "$($a.root)\Core.ps1"; . "$($a.root)\Predecessor.ps1"; . "$($a.root)\Source.ps1"; . "$($a.root)\Build.ps1"
            . "$($a.root)\MstBuilder.ps1"; . "$($a.root)\Sccm.ps1"; . "$($a.root)\Intune.ps1"
        }
        $Global:PBProgress = $a.progress   # Set-PbProgress writes here; the UI timer polls it.
        # NO Initialize-Log here - it TRUNCATES the file (wiping the session log on every action).
        # Write-Log appends via the lazy Get-LogPath, which is all a background job needs.
        Initialize-Config (Join-Path $a.root 'settings.json')
        if (Get-Command Ensure-PublishModulesStaged -ErrorAction SilentlyContinue) { Ensure-PublishModulesStaged -ToolRoot $a.root }   # first publish: copy SCCM/Intune modules local
        if ($a.target -eq 'sccm') {
            New-SccmApplication -Fields $a.fields -ToolRoot $a.root -LocalPackagePath $a.createdPath `
                -Distribute $a.distribute -Collections $a.collections -Deploy $a.deploy -AllowUserInteraction $a.allow -RfcComment $a.ritm
        } else {
            New-IntuneApp -Fields $a.fields -LocalPackagePath $a.createdPath
        }
    }).AddArgument($jobArgs) | Out-Null
    $handle = $psi.BeginInvoke()

    Set-ActionButtons $false
    $PbPublish.Visibility = 'Visible'; $PbPublish.Value = 0; $PbPublish.IsIndeterminate = $true; $LblPbPct.Text = ''
    $LblPubStatus.Text = 'Starting...'; $LblPubStatus.Foreground = '#56C8D6'
    $LblPublishLog.Foreground = '#CE9178'
    $LblPublishLog.Text = if ($Target -eq 'sccm') { "SCCM: creating '$($Fields.FullName)' (copy to prelive + app + DT + distribute + collections + deploy)... this can take minutes." }
                          else { "Intune: creating '$($Fields.FullName)' - sign in if prompted; the .intunewin upload can take a while." }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(400)
    $timer.add_Tick({
        # Live progress: marquee while indeterminate, else a real 0-100% bar with the current step.
        if ($prog.Indeterminate) { if (-not $PbPublish.IsIndeterminate) { $PbPublish.IsIndeterminate = $true }; $LblPbPct.Text = '' }
        else { if ($PbPublish.IsIndeterminate) { $PbPublish.IsIndeterminate = $false }; $PbPublish.Value = [double]$prog.Percent; $LblPbPct.Text = "$([int]$prog.Percent)%" }
        $LblPubStatus.Text = "$($prog.Status)"
        if (-not $handle.IsCompleted) { return }
        $timer.Stop()
        $r = $null
        try { $out = $psi.EndInvoke($handle); $r = @($out | Where-Object { $_ -is [hashtable] }) | Select-Object -Last 1 }
        catch { $r = @{ Ok=$false; Message=$_.Exception.Message } }
        try { $psi.Dispose(); $rs.Close(); $rs.Dispose() } catch {}
        Set-ActionButtons $true
        if ($r -and $r.Ok) {
            $PbPublish.IsIndeterminate = $false; $PbPublish.Value = 100; $LblPbPct.Text = '100%'
            $LblPubStatus.Text = 'Done.'; $LblPubStatus.Foreground = '#6A9955'
            $LblPublishLog.Text = "$($r.Message)"; $LblPublishLog.Foreground = '#6A9955'
            if ($r.AppId) {
                try { Set-Clipboard -Value $r.AppId } catch {}; $LblPublishLog.Text += '  (id copied to clipboard)'
                # Remember the Intune app id so the Intune tab can act on the exact app we just created.
                # ALWAYS overwrite - a stale id from an earlier rolled-back attempt must never linger
                # (acting on a dead id is what produced the misleading "app id does not exist" while the
                # retry had actually succeeded).
                if ($Target -eq 'intune') { Set-IntuneAppIdUi "$($r.AppId)" }
            }
        } elseif ($r -and $r.AlreadyExists) {
            # Intune duplicate guard tripped: the app exists (matched by branding key). Ask the user.
            $PbPublish.Visibility = 'Collapsed'; $LblPbPct.Text = ''
            $LblPubStatus.Text = 'Already exists.'; $LblPubStatus.Foreground = '#DCDCAA'
            $LblPublishLog.Text = "$($r.Message)"; $LblPublishLog.Foreground = '#DCDCAA'
            if ($r.AppId) {
                Set-IntuneAppIdUi "$($r.AppId)"   # also fills the Intune tab's App ID box (selectable there)
                try { Set-Clipboard -Value "$($r.AppId)"; $LblPublishLog.Text += '  (existing app id copied to clipboard)' } catch {}
            }
            $ans = [Windows.MessageBox]::Show("$($r.Message)`n`nIntune allows the same app to exist several times in parallel.`n`nCreate ANOTHER copy anyway?", 'App already exists in Intune', 'YesNo', 'Question')
            if ($ans -eq 'Yes') {
                $f = @{} + $Fields; $f.ForceCreate = $true
                Start-PublishJob -Target 'intune' -Fields $f
            }
        } else {
            $PbPublish.Visibility = 'Collapsed'; $LblPbPct.Text = ''
            $LblPubStatus.Text = 'Failed.'; $LblPubStatus.Foreground = '#F48771'
            $LblPublishLog.Text = if ($r) { "$($r.Message)" } else { "$Target finished with no result - check the log." }
            $LblPublishLog.Foreground = '#F48771'
        }
    }.GetNewClosure())
    $timer.Start()
}
# Run a "manage existing app" SCCM op (update detection / update content / delete) on a background
# runspace, reusing the same progress bar + result handling as Start-PublishJob.
function Start-SccmManageJob {
    param([string]$Action, [hashtable]$Fields, [hashtable]$Op)
    $prog = [hashtable]::Synchronized(@{ Percent = 0; Status = 'Starting...'; Indeterminate = $true })
    $jobArgs = @{ root=$root; action=$Action; fields=$Fields; op=$Op; createdPath="$($script:State.CreatedPath)"; progress=$prog; engine=$script:PBEngineSource }
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $psi = [PowerShell]::Create(); $psi.Runspace = $rs
    $psi.AddScript({
        param($a)
        if ($a.engine) { . ([scriptblock]::Create($a.engine)) }   # MERGED/EXE build: engine from embedded source
        else {
            . "$($a.root)\Core.ps1"; . "$($a.root)\Predecessor.ps1"; . "$($a.root)\Source.ps1"; . "$($a.root)\Build.ps1"
            . "$($a.root)\MstBuilder.ps1"; . "$($a.root)\Sccm.ps1"; . "$($a.root)\Intune.ps1"
        }
        $Global:PBProgress = $a.progress
        # NO Initialize-Log (it truncates the session log) - jobs append via the lazy Get-LogPath.
        Initialize-Config (Join-Path $a.root 'settings.json')
        if (Get-Command Ensure-PublishModulesStaged -ErrorAction SilentlyContinue) { Ensure-PublishModulesStaged -ToolRoot $a.root }   # ensure SCCM/Intune modules are local
        switch ($a.action) {
            'fetchdetection' { Get-SccmDetection     -FullName $a.fields.FullName -ToolRoot $a.root }
            'detection'      { Update-SccmDetection   -Fields $a.fields -ToolRoot $a.root }
            'content'        {
                if ($a.fields.RefreshOnly) {
                    # User updated the prelive content themselves: DON'T copy, just refresh the DPs.
                    Update-SccmContent -RefreshOnly -FullName $a.fields.FullName -ToolRoot $a.root
                } else {
                    # Source priority: explicit Content source field -> the loaded package (if it matches) -> find by
                    # name under Outgoing. (SCCM and Intune sources can differ, so the field wins.)
                    $src = if ($a.fields.ContentSrc) { $a.fields.ContentSrc }
                           elseif ($a.createdPath -and ((Split-Path $a.createdPath -Leaf) -eq $a.fields.FullName)) { $a.createdPath }
                           else { Find-OutgoingPackage -Name $a.fields.FullName }
                    if (-not $src -or -not (Test-Path $src)) { @{ Ok=$false; Message="Content source not found for '$($a.fields.FullName)' (set the Content source field, or ensure it is in Outgoing)." } }
                    else { Update-SccmContent -LocalPackagePath $src -FullName $a.fields.FullName -ToolRoot $a.root }
                }
            }
            'intunecontent'  {
                if (-not (Test-Path "$($a.op.ContentSrc)")) { @{ Ok=$false; Message="Intune content source folder not found: $($a.op.ContentSrc)" } }
                else { Update-IntuneContent -AppName $a.op.AppName -AppId $a.op.AppId -LocalPackagePath $a.op.ContentSrc }
            }
            'contentstatus'  { Get-SccmContentStatus  -FullName $a.fields.FullName -ToolRoot $a.root }
            'delete'         { Remove-SccmApplication -FullName $a.fields.FullName -ToolRoot $a.root }
            'addmachine'     { Add-SccmTestMachine    -FullName $a.op.FullName -Action $a.op.Action -Machines $a.op.Machines -ToolRoot $a.root }
            'removemachine'  { Remove-SccmTestMachine -FullName $a.op.FullName -Action $a.op.Action -Machines $a.op.Machines -ToolRoot $a.root }
            'machinepolicy'  { Invoke-SccmMachinePolicy -Machines $a.op.Machines }
            'remoteshots'    {
                # Smoke-test screenshots on each remote machine, sequentially (each opens real apps there).
                $msgs = New-Object System.Collections.Generic.List[string]; $anyOk = $false; $lastDir = $null
                foreach ($m in @($a.op.Machines)) {
                    $r = Invoke-RemoteShortcutShots -Machine $m -FullName $a.op.FullName -Tokens $a.op.Tokens -RefShortcuts $a.op.Ref
                    if ($r.Ok) { $anyOk = $true; if ($r.OutDir) { $lastDir = $r.OutDir } }
                    $msgs.Add("$($r.Message)")
                }
                if ($lastDir) { try { Start-Process explorer.exe $lastDir } catch {} }
                @{ Ok = $anyOk; Message = ($msgs -join "`n") }
            }
            'getlog'         { Get-SccmClientLog      -Machine $a.op.Machine -Which $a.op.Which -FullName $a.op.FullName }
            'loglist'        { Get-SccmPsadtLogList   -Machine $a.op.Machine -FullName $a.op.FullName }
            'getlogfile'     { Copy-SccmClientLogFile -Machine $a.op.Machine -RemotePath $a.op.RemotePath }
            'members'        { Get-SccmCollectionMembers -FullName $a.op.FullName -Action $a.op.Action -ToolRoot $a.root }
            'checkstate'     { Get-SccmInstallState   -Machine $a.op.Machine -FullName $a.op.FullName -ExpectedAction $a.op.Action }
            'reboot'         { Restart-SccmMachine    -Machine $a.op.Machine }
            'move'           { Move-SccmDevToTest     -FullName $a.op.FullName -Target $a.op.Target -ToolRoot $a.root }
            'intuneassign'   { Add-IntuneGroupAssignment    -AppName $a.op.AppName -AppId $a.op.AppId -Group $a.op.Group -Intent 'available' }
            'intuneunassign' { Remove-IntuneGroupAssignment -AppName $a.op.AppName -AppId $a.op.AppId -Group $a.op.Group }
        }
    }).AddArgument($jobArgs) | Out-Null
    $handle = $psi.BeginInvoke()

    Set-ActionButtons $false
    $PbPublish.Visibility = 'Visible'; $PbPublish.Value = 0; $PbPublish.IsIndeterminate = $true; $LblPbPct.Text = ''
    $LblPubStatus.Text = 'Starting...'; $LblPubStatus.Foreground = '#56C8D6'
    $LblPublishLog.Foreground = '#CE9178'
    $who = if ($Fields) { "$($Fields.FullName)" } elseif ($Op) { "$($Op.FullName)$($Op.Machine)" } else { '' }
    $LblPublishLog.Text = switch ($Action) {
        'fetchdetection' { "SCCM: reading current detection for '$who'..." }
        'detection'      { "SCCM: updating detection on '$who'..." }
        'content'        { "SCCM: updating content for '$who' (recopy to prelive + redistribute)..." }
        'contentstatus'  { "SCCM: reading per-DP content status for '$who'..." }
        'delete'         { "SCCM: deleting '$who' (app + deployment types + deployments + collections)..." }
        'addmachine'     { "SCCM: adding machine(s) to the $($Op.Action) collection of '$($Op.FullName)'..." }
        'removemachine'  { "SCCM: removing machine(s) from the $($Op.Action) collection of '$($Op.FullName)'..." }
        'machinepolicy'  { "SCCM: triggering client policy on $($Op.Machines -join ', ')..." }
        'remoteshots'    { "Remote screenshots: staging the agent on $($Op.Machines -join ', ') and launching the app's shortcuts there (locked RDP is fine)... this runs the real app(s) on those machines." }
        'getlog'         { "SCCM: fetching $($Op.Which) log from $($Op.Machine)..." }
        'loglist'        { "SCCM: listing package logs on $($Op.Machine)..." }
        'getlogfile'     { "SCCM: fetching $(Split-Path $Op.RemotePath -Leaf) from $($Op.Machine)..." }
        'members'        { "SCCM: reading $($Op.Action) collection members of '$($Op.FullName)'..." }
        'checkstate'     { "SCCM: checking install state of '$($Op.FullName)' on $($Op.Machine)..." }
        'reboot'         { "SCCM: sending restart to $($Op.Machine)..." }
        'move'           { "SCCM: moving '$($Op.FullName)' to $($Op.Target)..." }
        'intuneassign'   { "Intune: adding 'Available' assignment of group '$($Op.Group)' to '$(if($Op.AppId){$Op.AppId}else{$Op.AppName})'..." }
        'intuneunassign' { "Intune: removing assignment of group '$($Op.Group)' from '$(if($Op.AppId){$Op.AppId}else{$Op.AppName})'..." }
        'intunecontent'  { "Intune: updating content for '$(if($Op.AppId){$Op.AppId}else{$Op.AppName})' from $($Op.ContentSrc) (icon re-applied)..." }
        default          { "SCCM: working..." }
    }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(400)
    $timer.add_Tick({
        if ($prog.Indeterminate) { if (-not $PbPublish.IsIndeterminate) { $PbPublish.IsIndeterminate = $true }; $LblPbPct.Text = '' }
        else { if ($PbPublish.IsIndeterminate) { $PbPublish.IsIndeterminate = $false }; $PbPublish.Value = [double]$prog.Percent; $LblPbPct.Text = "$([int]$prog.Percent)%" }
        $LblPubStatus.Text = "$($prog.Status)"
        if (-not $handle.IsCompleted) { return }
        $timer.Stop()
        $r = $null
        try { $out = $psi.EndInvoke($handle); $r = @($out | Where-Object { $_ -is [hashtable] }) | Select-Object -Last 1 }
        catch { $r = @{ Ok=$false; Message=$_.Exception.Message } }
        try { $psi.Dispose(); $rs.Close(); $rs.Dispose() } catch {}
        Set-ActionButtons $true
        if ($r -and $r.Ok) {
            $PbPublish.IsIndeterminate = $false; $PbPublish.Value = 100; $LblPbPct.Text = '100%'
            $LblPubStatus.Text = 'Done.'; $LblPubStatus.Foreground = '#6A9955'
            $LblPublishLog.Text = "$($r.Message)"; $LblPublishLog.Foreground = '#6A9955'
            # Fetch detection -> load the app's current 2nd-clause values into the MODIFY fields.
            if ($r.Detection) {
                $d = $r.Detection
                $TxtModUninstallKey.Text  = "$($d.UninstallKey)"
                $TxtModDetectVersion.Text = "$($d.DetectVersion)"
                $TxtModProductCode.Text   = "$($d.ProductCode)"
                $ChkMod32Bit.IsChecked    = [bool]$d.Is32Bit
                $want = switch ("$($d.DetectType)") { 'String' {'String'} 'ProductCode' {'ProductCode'} 'None' {'None'} default {'Version'} }
                foreach ($it in $CmbModDetectType.Items) { if ("$($it.Content)" -like "$want*") { $CmbModDetectType.SelectedItem = $it; break } }
            }
            # Show members -> fill the Troubleshoot members list.
            if ($null -ne $r.Members) { $LstTsMembers.Items.Clear(); foreach ($mm in @($r.Members)) { [void]$LstTsMembers.Items.Add($mm) } }
            # Package-log list -> picker dialog (like the predecessor picker); fetch the chosen log.
            if ($null -ne $r.LogList) {
                $chosen = Show-LogPicker -Logs @($r.LogList) -Machine "$($r.Machine)"
                if ($chosen) { Start-SccmManageJob -Action 'getlogfile' -Op @{ Machine="$($r.Machine)"; RemotePath="$chosen" } }
            }
        } else {
            $PbPublish.Visibility = 'Collapsed'; $LblPbPct.Text = ''
            $LblPubStatus.Text = 'Failed.'; $LblPubStatus.Foreground = '#F48771'
            $LblPublishLog.Text = if ($r) { "$($r.Message)" } else { 'Operation finished with no result - check the log.' }
            $LblPublishLog.Foreground = '#F48771'
        }
    }.GetNewClosure())
    $timer.Start()
}
# Build the Fields hashtable for a MODIFY op from the self-contained Modify section. Branding is derived
# automatically from the app name (never shown/edited).
function Get-ModifyFields {
    $name = $TxtModAppName.Text.Trim()
    $parts = $name -split '_'; $product = if ($parts.Count -ge 2) { $parts[1] } else { $name }
    $f = @{
        FullName      = $name
        BrandingKey   = "SOFTWARE\VWG\CM\$name"
        ProductName   = $product
        UninstallKey  = $TxtModUninstallKey.Text.Trim()
        DetectVersion = $TxtModDetectVersion.Text.Trim()
        ProductCode   = $TxtModProductCode.Text.Trim()
        Is32Bit       = [bool]$ChkMod32Bit.IsChecked
        ContentSrc    = $TxtModContentSrc.Text.Trim()
        RefreshOnly   = [bool]$ChkModRefreshOnly.IsChecked
    }
    $sel = if ($CmbModDetectType.SelectedItem) { "$($CmbModDetectType.SelectedItem.Content)" } else { 'Version' }
    $f.DetectType = switch -Wildcard ($sel) { 'String*' {'String'} 'ProductCode*' {'ProductCode'} 'None*' {'None'} default {'Version'} }
    return $f
}
# Guard: modify ops need an app name typed in the Modify section.
function Test-ManageReady {
    if ($TxtModAppName.Text.Trim()) { return $true }
    $LblPublishLog.Text = 'Type the exact application name in the "Modify an existing SCCM application" section first.'
    $LblPublishLog.Foreground = '#F48771'; return $false
}
$BtnCreateSccm.add_Click({
    if (-not $script:State.PublishBase) { return }
    $f = Get-PublishFields
    # SAFETY: creating MIRRORS the package Content into PRELIVE (robocopy /MIR replaces + prunes). The check below
    # must never fail OPEN - see Confirm-PreliveMirror.
    if (-not (Confirm-PreliveMirror -PackageName $f.FullName -Action 'Creating')) {
        $LblPublishLog.Text = 'Cancelled - prelive content left unchanged.'; $LblPublishLog.Foreground = '#DCDCAA'; return
    }
    Start-PublishJob -Target 'sccm' -Fields $f
})
$BtnCreateIntune.add_Click({ if ($script:State.PublishBase) { Start-PublishJob -Target 'intune' -Fields (Get-PublishFields) } })
# Copy the CREATED package (c:\temp\<FullName>) to the Outgoing share at any time. Mirrors the folder, but ALWAYS
# asks first if a package with that name is already there - nothing on the share is replaced without a yes.
$BtnCopyOutgoing.add_Click({
    Reset-PBShareAsk   # a cancel earlier must not silence this click
    $src = "$((Get-PBState).CreatedPath)"   # closure-safe
    if (-not $src -or -not (Test-Path $src)) { $LblCreateResult.Text = 'No created package yet - build one with Create first.'; $LblCreateResult.Foreground = '#F48771'; return }
    $outBase = if (Get-Command Get-Setting -EA SilentlyContinue) { Get-Setting 'OutgoingPath' } else { $null }
    if (-not $outBase)            { $LblCreateResult.Text = 'OutgoingPath is not set in settings.json.'; $LblCreateResult.Foreground = '#F48771'; return }
    # an Outgoing share that cannot be opened gets a sign-in prompt (Porsche) before giving up
    $opened = $(if (Get-Command Connect-PBShare -EA SilentlyContinue) { Connect-PBShare -Path $outBase -Purpose 'the Outgoing share' -AllowPrompt } else { Test-Path $outBase })
    if (-not $opened) { $LblCreateResult.Text = "Outgoing path not reachable: $outBase"; $LblCreateResult.Foreground = '#F48771'; return }
    $leaf = Split-Path $src -Leaf
    $dest = Join-Path $outBase $leaf
    if ([IO.Path]::GetFullPath($src) -ieq [IO.Path]::GetFullPath($dest)) { $LblCreateResult.Text = 'The created package already IS the Outgoing copy (same folder) - nothing to do.'; $LblCreateResult.Foreground = '#DCDCAA'; return }
    if (Test-Path $dest) {
        $ans = [Windows.MessageBox]::Show("'$leaf' already exists in the Outgoing share:`n$dest`n`nReplace it? (the folder is mirrored to match your created package.)", 'Package already in Outgoing', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { $LblCreateResult.Text = 'Cancelled - Outgoing copy left unchanged.'; $LblCreateResult.Foreground = '#DCDCAA'; return }
    }
    $LblCreateResult.Text = "Copying to Outgoing: $dest ..."; $LblCreateResult.Foreground = '#A0A8B4'
    # robocopy of a whole package can run for minutes on a share - show the card and lock the button, or the
    # window just sits there looking hung and people click again (control sweep, 24.09.2026)
    $BtnCopyOutgoing.IsEnabled = $false
    Show-PBBusy -Title 'Copying to Outgoing' -Detail "$leaf -> $outBase"
    try { (Get-PBMainWindow).Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch {}
    try {
        $rc = '/MIR','/J','/MT:16','/R:2','/W:2','/NFL','/NDL','/NJH','/NJS','/NP'
        $copy = {
            if (-not (Test-Path $dest)) { New-Item $dest -ItemType Directory -Force -ErrorAction Stop | Out-Null }
            robocopy "$src" "$dest" @rc | Out-Null
            return $LASTEXITCODE
        }
        $rcode = & $copy
        # exit 8+ = files could not be copied - typically no write access on the share: offer a sign-in, copy once more
        if ($rcode -ge 8 -and (Get-Command Connect-PBShare -EA SilentlyContinue)) {
            Write-Log "Copy to Outgoing failed (robocopy exit $rcode) - offering a sign-in to the share." Warning
            if (Connect-PBShare -Path $outBase -Purpose 'the Outgoing share' -Retry -AllowPrompt) { $rcode = & $copy }
        }
        if ($rcode -ge 8) { $LblCreateResult.Text = "Copy to Outgoing FAILED (robocopy exit $rcode) - check the share / permissions."; $LblCreateResult.Foreground = '#F48771'; Write-Log "Copy to Outgoing failed (exit $rcode): $dest" Error }
        else { $LblCreateResult.Text = "Copied to Outgoing: $dest"; $LblCreateResult.Foreground = '#6A9955'; Write-Log "Copied package to Outgoing: $dest" Success }
    } catch {
        $why = "$($_.Exception.Message)"
        # a denied folder create / access error: offer a sign-in and try the copy once more
        if ((Get-Command Test-PBAccessError -EA SilentlyContinue) -and (Test-PBAccessError $why) -and (Connect-PBShare -Path $outBase -Purpose 'the Outgoing share' -Retry -AllowPrompt)) {
            try { $rcode = & $copy; if ($rcode -ge 8) { throw "robocopy exit $rcode" }; $LblCreateResult.Text = "Copied to Outgoing: $dest"; $LblCreateResult.Foreground = '#6A9955'; Write-Log "Copied package to Outgoing: $dest" Success; return }
            catch { $why = "$($_.Exception.Message)" }
        }
        $LblCreateResult.Text = "Copy to Outgoing failed: $why"; $LblCreateResult.Foreground = '#F48771'
    } finally { Hide-PBBusy; $BtnCopyOutgoing.IsEnabled = $true }   # every exit, including the early return above
})   # PLAIN handler: it calls script functions (Reset-PBShareAsk / Connect-PBShare / Test-PBAccessError /
     # Get-PBState / Write-Log) and a .GetNewClosure() cannot see those - it failed with "not recognized" (24.09.2026)

# LOCAL TEST CONSOLES: open an ELEVATED (admin) or SYSTEM/LocalSystem command prompt at the created package's Content
# folder, so the packager can run Invoke-AppDeployToolkit.exe Install / Uninstall / Repair by hand at both privilege
# levels - no separate tooling needed. SYSTEM uses PsExec.exe kept alongside PackageBuilder (user request).
function Get-CreatedContentDir {
    # A LOADED .ps1's OWN folder IS a package Content dir - so after Load .ps1 + Save you can test it immediately (user
    # request). Prefer that; otherwise the created package's Content folder.
    if ("$($script:LoadedScriptPath)".Trim() -and (Test-Path "$($script:LoadedScriptPath)")) { return (Split-Path "$($script:LoadedScriptPath)" -Parent) }
    $p = "$($script:State.CreatedPath)"
    if (-not $p -or -not (Test-Path $p)) { return $null }
    $c = Join-Path $p 'Content'
    return $(if (Test-Path $c) { $c } else { $p })
}
# The deployment entry exe in a package Content folder: v4 Invoke-AppDeployToolkit.exe, else v3 Deploy-Application.exe.
function Get-LocalDeployEntry {
    param([string]$Dir)
    foreach ($e in 'Invoke-AppDeployToolkit.exe','Deploy-Application.exe') { $p = Join-Path $Dir $e; if (Test-Path $p) { return $p } }
    return $null
}
# Run install / uninstall / repair on THIS machine, at admin (RunAs) or SYSTEM (PsExec -s). Same positional command the
# Integration/SCCM deployment uses: "<entry.exe> install|uninstall|repair".
function Invoke-LocalDeploy {
    param([ValidateSet('install','uninstall','repair')][string]$Type, [switch]$System)
    $dir = Get-CreatedContentDir
    if (-not $dir) { $LblCreateResult.Text = 'No package to test - Create one, or Load a .ps1 first.'; $LblCreateResult.Foreground = '#F48771'; return }
    $exe = Get-LocalDeployEntry -Dir $dir
    if (-not $exe) { $LblCreateResult.Text = "No Invoke-AppDeployToolkit.exe / Deploy-Application.exe in: $dir"; $LblCreateResult.Foreground = '#F48771'; return }
    $lvl = if ($System) { 'SYSTEM' } else { 'admin' }
    if ($System) {
        $ps = Find-PsExec
        if (-not $ps) { $LblCreateResult.Text = 'SYSTEM test unavailable on this copy - use the Admin buttons.'; $LblCreateResult.Foreground = '#E0BE7C'; return }
        try { Start-Process $ps -Verb RunAs -ArgumentList "-accepteula -s -i -w `"$dir`" `"$exe`" $Type" ; Write-Log "SYSTEM $Type (PsExec): $exe" }
        catch { $LblCreateResult.Text = "Could not run SYSTEM $($Type): $($_.Exception.Message)"; $LblCreateResult.Foreground = '#F48771'; return }
    } else {
        try { Start-Process $exe -Verb RunAs -ArgumentList "$Type" -WorkingDirectory $dir ; Write-Log "Admin $Type`: $exe" }
        catch { $LblCreateResult.Text = "Could not run admin $($Type): $($_.Exception.Message)"; $LblCreateResult.Foreground = '#F48771'; return }
    }
    $LblCreateResult.Text = "$lvl $Type launched: $([IO.Path]::GetFileName($exe)) (in $dir)"; $LblCreateResult.Foreground = '#DCDCAA'
}
function Find-PsExec {
    $names = @('PsExec64.exe','PsExec.exe')
    # Search the LOCAL tool root, the SHARE it was staged from, and the Incoming repository - each plus PsExec\/Tools\/Lib\
    # subfolders - so PsExec is found wherever the packager dropped it (self-stage also mirrors it into the local copy).
    $share = if (Get-Command Get-StageSource -EA SilentlyContinue) { Get-StageSource -ToolRoot $root } else { '' }
    $repo  = if (Get-Command Get-Setting -EA SilentlyContinue) { Get-Setting 'RepositoryPath' } else { '' }
    $dirs = New-Object System.Collections.Generic.List[string]
    foreach ($b in @($root, $share, $repo, [Environment]::CurrentDirectory) | Where-Object { $_ }) {
        foreach ($sub in @('', 'PsExec', 'Tools', 'Lib')) { $d = if ($sub) { Join-Path $b $sub } else { $b }; if (Test-Path $d) { [void]$dirs.Add($d) } }
    }
    foreach ($dir in $dirs) { foreach ($n in $names) { $p = Join-Path $dir $n; if (Test-Path $p) { return $p } } }
    try { $hit = Get-ChildItem -LiteralPath $root -Recurse -File -EA SilentlyContinue | Where-Object { $_.Name -in $names } | Select-Object -First 1; if ($hit) { return $hit.FullName } } catch {}
    return $null
}
$BtnAdminCmd.add_Click({
    $dir = Get-CreatedContentDir
    if (-not $dir) { $LblCreateResult.Text = 'No created package yet - build one with Create first (or Load from Outgoing).'; $LblCreateResult.Foreground = '#F48771'; return }
    try { Start-Process 'cmd.exe' -Verb RunAs -ArgumentList "/k cd /d `"$dir`"" ; Write-Log "Opened admin CMD at $dir" }
    catch { $LblCreateResult.Text = "Could not open admin CMD: $($_.Exception.Message)"; $LblCreateResult.Foreground = '#F48771' }
})
$BtnSystemCmd.add_Click({
    $dir = Get-CreatedContentDir
    if (-not $dir) { $LblCreateResult.Text = 'No created package yet - build one with Create first (or Load from Outgoing).'; $LblCreateResult.Foreground = '#F48771'; return }
    $ps = Find-PsExec
    if (-not $ps) { $LblCreateResult.Text = 'SYSTEM console unavailable on this copy - use the Admin CMD.'; $LblCreateResult.Foreground = '#E0BE7C'; return }
    # psexec -s -i cmd -> SYSTEM interactive cmd; RunAs elevates psexec so it can install its service. /k keeps the shell.
    try { Start-Process $ps -Verb RunAs -ArgumentList "-accepteula -s -i cmd.exe /k `"cd /d $dir`"" ; Write-Log "Opened SYSTEM CMD (PsExec: $ps) at $dir" }
    catch { $LblCreateResult.Text = "Could not open SYSTEM CMD: $($_.Exception.Message)"; $LblCreateResult.Foreground = '#F48771' }
})
# Admin install / uninstall / repair (RunAs) and the SYSTEM equivalents (PsExec -s).
$BtnAdminInstall.add_Click({   Invoke-LocalDeploy -Type 'install' })
$BtnAdminUninstall.add_Click({ Invoke-LocalDeploy -Type 'uninstall' })
$BtnAdminRepair.add_Click({    Invoke-LocalDeploy -Type 'repair' })
$BtnSysInstall.add_Click({     Invoke-LocalDeploy -Type 'install'   -System })
$BtnSysUninstall.add_Click({   Invoke-LocalDeploy -Type 'uninstall' -System })
$BtnSysRepair.add_Click({      Invoke-LocalDeploy -Type 'repair'    -System })
$BtnFetchDetection.add_Click({  if (Test-ManageReady) { Start-SccmManageJob -Action 'fetchdetection' -Fields (Get-ModifyFields) } })
$BtnUpdateDetection.add_Click({ if (Test-ManageReady) { Start-SccmManageJob -Action 'detection' -Fields (Get-ModifyFields) } })
$BtnUpdateContent.add_Click({
    if (-not (Test-ManageReady)) { return }
    $f = Get-ModifyFields
    # Update content MIRRORS the package into PRELIVE (robocopy /MIR replaces + prunes). Unless 'refresh only' is
    # set (which copies NOTHING - it just refreshes the DPs), ASK before replacing existing prelive content. The
    # copy runs in a background runspace, so the confirmation must happen here on the UI thread, before the job.
    if (-not $f.RefreshOnly) {
        if (-not (Confirm-PreliveMirror -PackageName $f.FullName -Action 'This')) {
            $LblPublishLog.Text = 'Cancelled - prelive content left unchanged.'; $LblPublishLog.Foreground = '#DCDCAA'; return
        }
    }
    Start-SccmManageJob -Action 'content' -Fields $f
})
$BtnContentStatus.add_Click({   if (Test-ManageReady) { Start-SccmManageJob -Action 'contentstatus' -Fields (Get-ModifyFields) } })
$BtnDeleteApp.add_Click({
    if (-not (Test-ManageReady)) { return }
    $f = Get-ModifyFields
    $ans = [Windows.MessageBox]::Show("Delete SCCM application '$($f.FullName)'?`n`nThis removes the application, its deployment types, deployments, and the INSTALL/UNINSTALL (TEST) collections. This cannot be undone.", 'Confirm delete', 'YesNo', 'Warning')
    if ($ans -eq 'Yes') { Start-SccmManageJob -Action 'delete' -Fields $f }
})
# --- Testing tab ---
# Machines list: Add to list builds it; Add/Remove/Policy act on ALL listed machines (or, if the list
# is empty, whatever is typed in the box - so quick one-offs still work without the list).
function Get-TestMachines {
    $fromList = @($LstTestMachines.Items | ForEach-Object { "$_" })
    if ($fromList.Count) { return $fromList }
    return @($TxtTestMachine.Text -split '[,\s]+' | Where-Object { $_ })
}
$BtnTestAddList.add_Click({
    $new = @($TxtTestMachine.Text -split '[,\s]+' | Where-Object { $_ })
    if (-not $new) { $LblPublishLog.Text='Type machine name(s) first (comma/space separated).'; $LblPublishLog.Foreground='#F48771'; return }
    $have = @{}; foreach ($i in $LstTestMachines.Items) { $have["$i".ToUpper()] = $true }
    foreach ($m in $new) { $mu = "$m".Trim().ToUpper(); if ($mu -and -not $have.ContainsKey($mu)) { [void]$LstTestMachines.Items.Add($mu); $have[$mu]=$true } }
    $TxtTestMachine.Text = ''
})
$BtnTestRemoveSel.add_Click({ while ($LstTestMachines.SelectedItems.Count) { $LstTestMachines.Items.Remove($LstTestMachines.SelectedItems[0]) } })
$BtnTestClearList.add_Click({ $LstTestMachines.Items.Clear() })
$BtnAddTestMachine.add_Click({
    $app = $TxtTestAppName.Text.Trim(); $machines = Get-TestMachines
    if (-not $app)       { $LblPublishLog.Text='Enter the application name in the Testing tab.'; $LblPublishLog.Foreground='#F48771'; return }
    if (-not $machines)  { $LblPublishLog.Text='Add at least one machine (Add to list, or type names).'; $LblPublishLog.Foreground='#F48771'; return }
    $act = if ($CmbTestAction.SelectedItem -and "$($CmbTestAction.SelectedItem.Content)" -eq 'Uninstall') { 'Uninstall' } else { 'Install' }
    Start-SccmManageJob -Action 'addmachine' -Op @{ FullName=$app; Action=$act; Machines=$machines }
})
$BtnRemoveTestMachine.add_Click({
    $app = $TxtTestAppName.Text.Trim(); $machines = Get-TestMachines
    if (-not $app)      { $LblPublishLog.Text='Enter the application name in the Testing tab.'; $LblPublishLog.Foreground='#F48771'; return }
    if (-not $machines) { $LblPublishLog.Text='Add at least one machine (Add to list, or type names).'; $LblPublishLog.Foreground='#F48771'; return }
    $act = if ($CmbTestAction.SelectedItem -and "$($CmbTestAction.SelectedItem.Content)" -eq 'Uninstall') { 'Uninstall' } else { 'Install' }
    Start-SccmManageJob -Action 'removemachine' -Op @{ FullName=$app; Action=$act; Machines=$machines }
})
# Intune ops (isolated). App resolved by App ID first, else branding key. Group accepts a name OR an Object ID.
$BtnIntuneAssignAvail.add_Click({
    $id = $TxtIntuneAppId.Text.Trim(); $app = $TxtIntuneAssignApp.Text.Trim(); $grp = $TxtIntuneGroupId.Text.Trim()
    if (-not $id -and -not $app) { $LblPublishLog.Text='Enter the Intune App ID, or the package name (for branding-key match).'; $LblPublishLog.Foreground='#F48771'; return }
    if (-not $grp) { $LblPublishLog.Text='Enter the group name or its Object ID (GUID).'; $LblPublishLog.Foreground='#F48771'; return }
    Start-SccmManageJob -Action 'intuneassign' -Op @{ AppName=$app; AppId=$id; Group=$grp }
})
$BtnIntuneUnassign.add_Click({
    $id = $TxtIntuneAppId.Text.Trim(); $app = $TxtIntuneAssignApp.Text.Trim(); $grp = $TxtIntuneGroupId.Text.Trim()
    if (-not $id -and -not $app) { $LblPublishLog.Text='Enter the Intune App ID, or the package name (for branding-key match).'; $LblPublishLog.Foreground='#F48771'; return }
    if (-not $grp) { $LblPublishLog.Text='Enter the group name or its Object ID (GUID).'; $LblPublishLog.Foreground='#F48771'; return }
    Start-SccmManageJob -Action 'intuneunassign' -Op @{ AppName=$app; AppId=$id; Group=$grp }
})
$BtnIntuneUpdateContent.add_Click({
    $id = $TxtIntuneAppId.Text.Trim(); $app = $TxtIntuneAssignApp.Text.Trim(); $src = $TxtIntuneContentSrc.Text.Trim()
    if (-not $id -and -not $app) { $LblPublishLog.Text='Enter the Intune App ID, or the package name (for branding-key match).'; $LblPublishLog.Foreground='#F48771'; return }
    if (-not $src) { $LblPublishLog.Text='Choose the content source folder (Browse) to upload.'; $LblPublishLog.Foreground='#F48771'; return }
    Start-SccmManageJob -Action 'intunecontent' -Op @{ AppName=$app; AppId=$id; ContentSrc=$src }
})
# Folder pickers for the content-source fields (SCCM Modify + Intune).
$pickFolder = { param($desc)
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog; $dlg.Description = $desc
    $og = Get-Setting 'OutgoingPath'; if ($og -and (Test-Path $og)) { $dlg.SelectedPath = $og }
    if ($dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath } else { return $null }
}
$BtnModBrowseSrc.add_Click({    $p = & $pickFolder 'Select the package folder for SCCM Update content';   if ($p) { $TxtModContentSrc.Text = $p } })
$BtnIntuneBrowseSrc.add_Click({ $p = & $pickFolder 'Select the package folder for Intune Update content'; if ($p) { $TxtIntuneContentSrc.Text = $p } })
$BtnRunMachinePolicy.add_Click({
    $machines = Get-TestMachines
    if (-not $machines) { $LblPublishLog.Text='Add at least one machine (Add to list, or type names).'; $LblPublishLog.Foreground='#F48771'; return }
    Start-SccmManageJob -Action 'machinepolicy' -Op @{ Machines=$machines }
})
$BtnRemoteShots.add_Click({
    # Troubleshoot tab: target machine(s) from the Machine name field (comma/space separated), app from Application name.
    $machines = @("$($TxtTsMachine.Text)" -split '[,;\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $machines) { $LblPublishLog.Text='Enter the target Machine name(s) in the Troubleshoot tab.'; $LblPublishLog.Foreground='#F48771'; return }
    $app = $TxtTsAppName.Text.Trim()
    if (-not $app -and $script:State.PublishBase) { $app = "$($script:State.PublishBase.FullName)" }
    if (-not $app) { $LblPublishLog.Text='Enter the Application name (full package name) in the Troubleshoot tab.'; $LblPublishLog.Foreground='#F48771'; return }
    # If the ONLY target is THIS machine, do it LOCALLY (no agent push / admin share needed) - user rule.
    $me = "$env:COMPUTERNAME"
    $isLocalOnly = ($machines.Count -eq 1) -and (@('.','localhost',$me) -contains $machines[0] -or "$($machines[0])".Split('.')[0] -ieq $me)
    if ($isLocalOnly) {
        Invoke-ShortcutValidation -Name $app -Tokens (Get-ValidationTokens $app) -StatusLabel $LblPublishLog
        return
    }
    $ans = [Windows.MessageBox]::Show("Push the screenshot agent to: $($machines -join ', ')?`n`nOn each machine this LAUNCHES the app's installed Start-Menu shortcuts (in the logged-on user's session - a locked RDP session is fine), screenshots each, closes them, and pulls the report back here. The app must already be INSTALLED there (run the install first).", 'Remote screenshots (smoke test)', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    Start-SccmManageJob -Action 'remoteshots' -Op @{ Machines=$machines; FullName=$app; Tokens=(Get-ValidationTokens $app); Ref=@($script:State.SnapshotShortcuts) }
})
# --- Troubleshoot tab ---
$doLog = { param($which)
    $m = $TxtTsMachine.Text.Trim()
    if (-not $m) { $LblPublishLog.Text='Enter the target machine name in the Troubleshoot tab.'; $LblPublishLog.Foreground='#F48771'; return }
    Start-SccmManageJob -Action 'getlog' -Op @{ Machine=$m; Which=$which; FullName=$TxtTsAppName.Text.Trim() }
}
$BtnLogDiscovery.add_Click({ & $doLog 'AppDiscovery' })
$BtnLogEnforce.add_Click({   & $doLog 'AppEnforce' })
$BtnLogPackage.add_Click({
    # Package logs: LIST what's on the machine (ProgramData\VWG\Logs, filtered by vendor/app) and let
    # the user PICK which log to open - install / uninstall / repair / MSI / EXE logs included.
    $m = $TxtTsMachine.Text.Trim()
    if (-not $m) { $LblPublishLog.Text='Enter the target machine name in the Troubleshoot tab.'; $LblPublishLog.Foreground='#F48771'; return }
    Start-SccmManageJob -Action 'loglist' -Op @{ Machine=$m; FullName=$TxtTsAppName.Text.Trim() }
})
$tsCollAction = { if ($CmbTsColl.SelectedItem -and "$($CmbTsColl.SelectedItem.Content)" -eq 'Uninstall') { 'Uninstall' } else { 'Install' } }
$BtnTsShowMembers.add_Click({
    $app = $TxtTsAppName.Text.Trim()
    if (-not $app) { $LblPublishLog.Text='Enter the application name in the Troubleshoot tab.'; $LblPublishLog.Foreground='#F48771'; return }
    Start-SccmManageJob -Action 'members' -Op @{ FullName=$app; Action=(& $tsCollAction) }
})
$BtnTsCheckState.add_Click({
    $app = $TxtTsAppName.Text.Trim(); $m = $TxtTsMachine.Text.Trim()
    if (-not $app) { $LblPublishLog.Text='Enter the application name in the Troubleshoot tab.'; $LblPublishLog.Foreground='#F48771'; return }
    if (-not $m)   { $LblPublishLog.Text='Enter (or click) a machine name to check.'; $LblPublishLog.Foreground='#F48771'; return }
    Start-SccmManageJob -Action 'checkstate' -Op @{ FullName=$app; Machine=$m; Action=(& $tsCollAction) }
})
$BtnTsReboot.add_Click({
    $m = $TxtTsMachine.Text.Trim()
    if (-not $m) { $LblPublishLog.Text='Enter (or click) a machine name to reboot.'; $LblPublishLog.Foreground='#F48771'; return }
    # Outward-facing + disruptive: confirm before sending a forced restart to someone's machine.
    $ans = [Windows.MessageBox]::Show("Send a FORCED restart to '$m' now?`n`nAnyone signed in will be logged off. Use this only for test machines / when a reboot is pending.", 'Reboot machine', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    Start-SccmManageJob -Action 'reboot' -Op @{ Machine=$m }
})
$LstTsMembers.add_SelectionChanged({ if ($LstTsMembers.SelectedItem) { $TxtTsMachine.Text = "$($LstTsMembers.SelectedItem)" } })
# (Error-code explanation is now folded into "Check install state" - it fetches the code from the client.)
# --- Dev <-> Test tab ---
$BtnMoveToTest.add_Click({
    $app = $TxtMoveAppName.Text.Trim()
    if (-not $app) { $LblPublishLog.Text='Enter the application name in the Dev/Test tab.'; $LblPublishLog.Foreground='#F48771'; return }
    Start-SccmManageJob -Action 'move' -Op @{ FullName=$app; Target='Test' }
})
$BtnMoveToDev.add_Click({
    $app = $TxtMoveAppName.Text.Trim()
    if (-not $app) { $LblPublishLog.Text='Enter the application name in the Dev/Test tab.'; $LblPublishLog.Foreground='#F48771'; return }
    Start-SccmManageJob -Action 'move' -Op @{ FullName=$app; Target='Dev' }
})
$BtnOpenCmTrace.add_Click({
    $log = if (Get-Command Get-LogPath -ErrorAction SilentlyContinue) { Get-LogPath } else { 'C:\temp\GPF-PackageAssistance\Logs\PackageAssistance.log' }
    if (Get-Command Open-CMTrace -ErrorAction SilentlyContinue) { Open-CMTrace -LogPath $log } elseif (Test-Path $log) { Start-Process $log }
})
$BtnOpenWork.add_Click({
    $w = if (Get-Command Get-WorkPath -ErrorAction SilentlyContinue) { Get-WorkPath } else { 'C:\temp\GPF-PackageAssistance' }
    try { Start-Process explorer.exe $w } catch { $LblPublishLog.Text = "Work folder: $w"; $LblPublishLog.Foreground = '#A0A8B4' }
})
# Launch + screenshot the app's installed Start-Menu shortcuts on a BACKGROUND runspace (apps need seconds to
# render; on the UI thread the window would freeze). $OnDone runs on the UI thread with ($result, $err).
function Start-ScreenshotJob {
    param([string[]]$AppTokens, [Parameter(Mandatory)][string]$OutDir, [object[]]$RefShortcuts, [object[]]$ExactShortcuts, [string]$Title='Shortcut screenshots', [Parameter(Mandatory)][scriptblock]$OnDone)
    $box = [hashtable]::Synchronized(@{ Done=$false; Result=$null; Error=$null })
    $jobArgs = @{ engine=$script:PBEngineSource; root=$root; box=$box; tokens=$AppTokens; outdir=$OutDir; ref=$RefShortcuts; exact=$ExactShortcuts; title=$Title }
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState='STA'; $rs.ThreadOptions='ReuseThread'; $rs.Open()
    $psi = [PowerShell]::Create(); $psi.Runspace = $rs
    [void]$psi.AddScript({
        param($a)
        try {
            if ($a.engine) { . ([scriptblock]::Create($a.engine)) } else { . "$($a.root)\Core.ps1"; . "$($a.root)\Source.ps1"; . "$($a.root)\Screenshots.ps1" }
            $win = $null
            if ($a.exact -and @($a.exact).Count) {
                # EXACT mode (snapshot dialog): screenshot the precise shortcuts the snapshot diff captured - no
                # re-identification needed, the caller already knows which ones are this install's.
                $cur = @($a.exact)
            } else {
                # LIVE mode: identify THIS install's shortcuts by the INSTALL WINDOW from the package's own install
                # LOG (reliable, name-independent) - NOT by matching the app's ARP name or install folder. Snapshot
                # ref wins when present.
                $win   = Get-AppInstallWindow -AppTokens $a.tokens
                $since = if ($win) { [datetime]$win.Start } else { [datetime]::MinValue }
                $until = if ($win) { [datetime]$win.End }   else { [datetime]::MinValue }
                $cur   = @(Get-AppStartMenuShortcuts -Live -SinceTime $since -UntilTime $until -RefShortcuts $a.ref)
            }
            $shots = @(Invoke-ShortcutScreenshots -Shortcuts $cur -OutDir $a.outdir -Title $a.title)
            $a.box.Result = @{ Shortcuts=$cur; Shots=$shots; OutDir=$a.outdir; Info=$win }
        } catch { $a.box.Error = "$($_.Exception.Message)" }
        finally { $a.box.Done = $true }
    }).AddArgument($jobArgs)
    $h = $psi.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.add_Tick({
        if (-not $box.Done) { return }
        $timer.Stop()
        try { $psi.EndInvoke($h) } catch {}
        try { $psi.Dispose(); $rs.Close(); $rs.Dispose() } catch {}
        & $OnDone $box.Result $box.Error
    }.GetNewClosure())
    $timer.Start()
}
# Validate the package visually: launch the installed app's real Start-Menu shortcuts + screenshot each, then
# (if a snapshot reference exists) report what changed since the snapshot. Live-enumeration is the authority.
# Tokens for shortcut matching: vendor+app from a full package name, else the words of whatever was typed.
function Get-ValidationTokens {
    param([string]$Name)
    $p = Parse-PackageName -Name $Name
    if ($p.IsValid) { return @($p.Vendor, $p.AppName | Where-Object { $_ } | ForEach-Object { $_.ToLower() }) }
    return @("$Name".ToLower() -split '[_\s]+' | Where-Object { $_.Length -ge 3 })
}
# One-click LOCAL validation: launch THIS app's installed Start-Menu shortcuts (identified by install timestamp /
# folder / snapshot reference - NOT name guessing), screenshot each (captioned + index.html), close them, and diff
# against the snapshot reference. Shared by the Integration tab and the Troubleshoot/testing tab.
function Invoke-ShortcutValidation {
    param([string]$Name, [string[]]$Tokens, $StatusLabel)
    if (-not "$Name".Trim()) { if ($StatusLabel) { $StatusLabel.Text='Enter or load a package/app name first.'; $StatusLabel.Foreground='#F48771' }; return }
    $ans = [Windows.MessageBox]::Show("This LAUNCHES the installed app's Start-Menu shortcuts on THIS machine, one by one, and screenshots each (uninstall/update/help shortcuts are skipped). Each app is closed afterwards. The app must already be installed HERE. Continue?", 'Screenshot app shortcuts', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    $stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outDir = Join-Path (Get-WorkPath ("Screenshots\$Name\integration")) $stamp
    if ($StatusLabel) { $StatusLabel.Text = 'Identifying the app shortcuts, launching + capturing... the window may be busy briefly.'; $StatusLabel.Foreground='#A0A8B4' }
    # Re-bind TRUE locals for the nested OnDone closure (per ps-wpf-closure-scope).
    $lbl = $StatusLabel; $stateRef = $script:State
    # Force-minimize the tool via Win32 so the shots show ONLY the launched app (WPF WindowState was unreliable here;
    # the background job can't touch WPF windows). Restored in OnDone.
    Set-PBWindowState $script:Win 11   # SW_FORCEMINIMIZE
    Start-ScreenshotJob -AppTokens $Tokens -OutDir $outDir -RefShortcuts @($script:State.SnapshotShortcuts) -Title "Shortcut validation - $Name" -OnDone {
        param($res, $err)
        try { $mw = Get-PBMainWindow; Set-PBWindowState $mw 9; $mw.Activate() } catch {}   # SW_RESTORE (closure-safe)
        if (-not $lbl) { return }
        if ($err -or -not $res) { $lbl.Text = "Screenshot validation failed: $err"; $lbl.Foreground='#F48771'; return }
        $cur = @($res.Shortcuts); $shots = @($res.Shots); $ok = @($shots | Where-Object { $_.Ok }).Count
        if (-not $cur.Count) { $lbl.Text = "No shortcuts identified - need a reliable signal: run a SNAPSHOT first (Detection) for the exact list, or make sure the package's install LOG is present (ProgramData\VWG\Logs\<package>) so shortcuts can be matched by the install-time WINDOW. The tool will not guess by app name."; $lbl.Foreground='#DCDCAA'; return }
        $src = if ($res.Info -and "$($res.Info.Source)".Trim()) { "  (matched by $($res.Info.Source))" } else { '  (matched by snapshot reference)' }
        $msg = "Captured $ok/$($shots.Count) screenshot(s) -> $($res.OutDir)  (open index.html).$src"
        $ref = @($stateRef.SnapshotShortcuts)
        if ($ref.Count -and (Get-Command Compare-ShortcutSets -EA SilentlyContinue)) {
            $cmp = Compare-ShortcutSets -Reference $ref -Current $cur
            $added = @($cmp.Added | ForEach-Object { $_.Name }); $gone = @($cmp.Gone | ForEach-Object { $_.Name })
            $msg += "  Vs snapshot: $($cmp.Same.Count) same$(if($added.Count){"; NEW: $($added -join ', ')"})$(if($gone.Count){"; MISSING: $($gone -join ', ')"})."
        }
        $lbl.Text = $msg; $lbl.Foreground = '#6A9955'
        try { Start-Process explorer.exe $res.OutDir } catch {}
    }.GetNewClosure()
}
$BtnTsShots.add_Click({
    # Review & Create tab: screenshot the shortcuts of the package tested locally (installed via the Admin/SYSTEM
    # buttons). Name comes from a Loaded .ps1's package folder, else the parsed / created package.
    $name = if ("$($script:LoadedScriptPath)".Trim() -and (Test-Path "$($script:LoadedScriptPath)")) {
                $dir = Get-CreatedContentDir; $leaf = Split-Path $dir -Leaf
                if ($leaf -ieq 'Content') { Split-Path (Split-Path $dir -Parent) -Leaf } else { $leaf }
            }
            elseif ($script:State.Parsed) { "$($script:State.Parsed.FullName)" }
            elseif ("$($script:State.CreatedPath)".Trim()) { Split-Path "$($script:State.CreatedPath)" -Leaf }
            elseif ($script:State.PublishBase) { "$($script:State.PublishBase.FullName)" } else { '' }
    if (-not $name) { $LblCreateResult.Text = 'Build or Load a package first (its name is needed to find the shortcuts).'; $LblCreateResult.Foreground = '#F48771'; return }
    Invoke-ShortcutValidation -Name $name -Tokens (Get-ValidationTokens $name) -StatusLabel $LblCreateResult
})
# When switching Step-4 tabs, reflect the Integrate app name + content path into the other tabs (if blank).
$TabsP4.add_SelectionChanged({ param($s,$e)
    if (-not ($e.AddedItems.Count -and ($e.AddedItems[0] -is [System.Windows.Controls.TabItem]))) { return }   # ignore inner combo/list changes
    # First time the Integration tab opens: warm the SCCM/Intune module cache in the BACKGROUND (copy them from the share
    # into the local copy) so the first publish isn't delayed. Best-effort - the publish job also ensures it. Only when
    # we were self-staged from a share (.source marker present) and running the packed build.
    if ($script:PBEngineSource -and (-not $script:PublishWarmStarted) -and ("$($e.AddedItems[0].Header)" -eq 'Integration') -and (Test-Path (Join-Path $root '.source'))) {
        $script:PublishWarmStarted = $true
        try {
            $script:WarmRs = [runspacefactory]::CreateRunspace(); $script:WarmRs.ApartmentState = 'STA'; $script:WarmRs.ThreadOptions = 'ReuseThread'; $script:WarmRs.Open()
            $script:WarmPs = [PowerShell]::Create(); $script:WarmPs.Runspace = $script:WarmRs
            [void]$script:WarmPs.AddScript({ param($eng, $rt) try { . ([scriptblock]::Create($eng)); Ensure-PublishModulesStaged -ToolRoot $rt } catch {} }).AddArgument($script:PBEngineSource).AddArgument("$root")
            [void]$script:WarmPs.BeginInvoke()
            Write-Log 'Integration tab: warming the SCCM/Intune module cache in the background.'
        } catch {}
    }
    $base = $script:State.PublishBase
    $nm = if ($base) { "$($base.FullName)" } elseif ($TxtPubPkgName -and $TxtPubPkgName.Text.Trim()) { $TxtPubPkgName.Text.Trim() } else { '' }
    if ($nm) { foreach ($tb in @($TxtModAppName,$TxtTestAppName,$TxtTsAppName,$TxtMoveAppName,$TxtIntuneAssignApp)) { if ($tb -and -not $tb.Text.Trim()) { $tb.Text = $nm } } }
    $src = "$($script:State.CreatedPath)"
    if ($src) { foreach ($sb in @($TxtModContentSrc,$TxtIntuneContentSrc)) { if ($sb -and -not $sb.Text.Trim()) { $sb.Text = $src } } }
    # Keep the Intune App ID we got at creation, until the user edits it.
    if ($script:State.IntuneAppId -and $TxtIntuneAppId -and -not $TxtIntuneAppId.Text.Trim()) { $TxtIntuneAppId.Text = "$($script:State.IntuneAppId)" }
    # The bottom 'Create' (package) button belongs only to the Review & Create tab - hide it elsewhere.
    if ($script:Step -ge 4) {
        $sel = $e.AddedItems[0]
        $BtnNext.Visibility = if ("$($sel.Header)" -like 'Review*') { 'Visible' } else { 'Collapsed' }
    }
})

$BtnBack.add_Click({
    if ($script:Step -gt 1) { Show-Step ($script:Step-1) }
})
$BtnNext.add_Click({
    if ($script:Step -ge 4) {
        $p = $script:State.Parsed
        if (-not $p -or -not $p.IsValid) { [Windows.MessageBox]::Show('Enter a valid package name in Step 1.','Create') | Out-Null; return }
        if (-not $script:State.ScriptText) { Show-PBBusy -Title 'Building script' -Detail $(if ($script:State.PredecessorModel) { 'Reusing the predecessor script: converting, swapping identity, merging the snapshot...' } else { 'Filling the template from the installer, transform and analysis...' }); try { $script:State.ScriptText = Build-Step3Script } finally { Hide-PBBusy } }
        # GENERATION-FAILED detection: Build-Step3Script errors are a SHORT single comment line. A real script is
        # tens of KB - and the GPF template legitimately STARTS with a '#' license line ("Modified by AUDI AG..."),
        # so "starts with #" alone must NOT count as failure.
        $genFailed = (-not $script:State.ScriptText) -or
                     ("$($script:State.ScriptText)" -like '#*' -and "$($script:State.ScriptText)".Length -lt 500)
        if ($genFailed) {
            $why = ''
            if ("$($script:State.ScriptText)" -like '#*') { $why = "`n`nReason: " + ((("$($script:State.ScriptText)") -split "`r?`n")[0].TrimStart('#',' ')) }
            [Windows.MessageBox]::Show("The script could not be generated. Open Step 3, fix the reported problem, then Create.$why",'Create') | Out-Null; return
        }
        # Final structural gate: never silently build a package whose script doesn't parse.
        $structErr = Test-ScriptStructure -Text ([string]$script:State.ScriptText)
        if ($structErr) {
            $ans = [Windows.MessageBox]::Show("The generated script does NOT parse - it would fail at install time.`n`n$structErr`n`nCreate the package anyway?", 'Script validation', 'YesNo', 'Warning')
            if ($ans -ne 'Yes') { return }
        }
        # ALREADY EXISTS? If a package with this EXACT name is already built (output path) or finished
        # (Outgoing share), ask before creating it again - so a version that's already packaged isn't
        # silently re-done. (User request.)
        $existsAt = New-Object System.Collections.Generic.List[string]
        $outPath = Join-Path (Get-Setting 'OutputBasePath' 'c:\temp') $p.FullName
        if (Test-Path $outPath) { $existsAt.Add("Output folder:  $outPath") }
        try { $og = Find-OutgoingPackage -Name $p.FullName; if ($og) { $existsAt.Add("Outgoing share: $og") } } catch {}
        if ($existsAt.Count) {
            $ans2 = [Windows.MessageBox]::Show("A package named '$($p.FullName)' already exists:`n`n$($existsAt -join "`n")`n`nCreate it again?", 'Package already exists', 'YesNo', 'Warning')
            if ($ans2 -ne 'Yes') { return }
        }
        try {
            $ins = @($script:State.ChosenInstallers)
            $author = Get-AuthorName
            $newPkg = @{
                FullName=$p.FullName; Vendor=$p.Vendor; AppName=$p.AppName; Arch=$p.Arch; Lang=$p.Lang
                Revision=$p.Release; Version=$p.Version; ProductCode=$script:State.ProductCode; Ritm=$script:State.Ritm; Author=$author
                PerUserMode=$script:State.PerUserMode   # 'ActiveSetup' -> New-Package stages the stub into SupportFiles
                Hkcu=@($script:State.SnapshotHkcu)      # detected per-user values baked into the staged Active Setup stub
                UserFiles=@($script:State.SnapshotUserFiles)   # detected per-user files -> New-Package stages them into SupportFiles
            }
            if ($script:State.PredecessorModel) { $newPkg.PerUserMode = 'None'; $newPkg.UserFiles = @() }   # predecessor reuse -> no per-user staging (use snippets)
            if ($ins.Count -eq 1 -and $ins[0].Extension.ToLower() -eq '.msi') { $newPkg.MsiFileName = $ins[0].Name }
            # Brand outgoing prefix (GPF: the OUTPUT FOLDER gets INA_/VWG_/G1V_; the in-script AppFullName stays bare).
            # Comes straight from the Step-1 Target-brand selection now (the separate prefix dropdown is retired).
            $newPkg.OutPrefix = "$($script:State.TargetBrand)".Trim().ToUpper()
            $targets = @()
            if ($script:State.LooseShortcut -and $script:State.LooseTargets) {
                $targets = @(($script:State.LooseTargets -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
            $msiPropsMap = @{}; $msiFlagsMap = @{}
            foreach ($i in $ins) {
                if ($script:State.MsiProps -and $script:State.MsiProps.ContainsKey($i.FullName)) { $msiPropsMap[$i.Name] = $script:State.MsiProps[$i.FullName] }
                if ($script:State.MsiFlags -and $script:State.MsiFlags.ContainsKey($i.FullName)) {
                    $fl = $script:State.MsiFlags[$i.FullName]
                    $msiFlagsMap[$i.Name] = @{ Shortcut = (-not [bool]$fl.KeepShortcut); Run = (-not [bool]$fl.KeepRunKey); Startup = (-not [bool]$fl.KeepStartup); Stray = (-not [bool]$fl.KeepStray) }
                }
            }
            # Icons: for a PREDECESSOR REUSE, use the PREDECESSOR's icons (live share) - the new drop usually has
            # none. If the predecessor has no Icons, leave them EMPTY (we never borrow another package's). For a
            # FRESH package, keep whatever the new source resolved (else empty). Clone Resolved so shared state isn't
            # mutated; point RootPath at the predecessor too, so the icon fallback stays INSIDE the predecessor.
            $resolvedForBuild = $script:State.Resolved
            if ($script:State.PredecessorModel -and "$($script:State.PredecessorPath)".Trim()) {
                if ((Test-PBGpfFamily)) {
                    # GPF rule: the CURRENT request's icons win when the Icons folder has BOTH .ico AND .png;
                    # the predecessor is only the fallback. Documents are NEVER taken from the predecessor.
                    $curIcons = "$($script:State.Resolved.IconsPath)"
                    $haveBoth = $false
                    if ($curIcons -and (Test-Path $curIcons)) {
                        $haveBoth = ((@(Get-ChildItem $curIcons -Filter *.ico -File -EA SilentlyContinue).Count -gt 0) -and
                                     (@(Get-ChildItem $curIcons -Filter *.png -File -EA SilentlyContinue).Count -gt 0))
                    }
                    if (-not $haveBoth) {
                        $predIcons = Get-PredecessorIconsPath -PredecessorPath "$($script:State.PredecessorPath)"
                        if ($predIcons) {
                            $resolvedForBuild = @{}
                            if ($script:State.Resolved) { foreach ($k in @($script:State.Resolved.Keys)) { $resolvedForBuild[$k] = $script:State.Resolved[$k] } }
                            $resolvedForBuild.IconsPath = $predIcons
                            Write-Log "Icons: request Icons incomplete (need BOTH .ico and .png) -> using the predecessor's: $predIcons"
                        } else { Write-Log "Icons: request Icons incomplete and the predecessor has none - Icons left as-is." Warning }
                    } else { Write-Log "Icons: current request provides .ico + .png - predecessor icons not used." }
                } else {
                    $predIcons = Get-PredecessorIconsPath -PredecessorPath "$($script:State.PredecessorPath)"
                    $resolvedForBuild = @{}
                    if ($script:State.Resolved) { foreach ($k in @($script:State.Resolved.Keys)) { $resolvedForBuild[$k] = $script:State.Resolved[$k] } }
                    $resolvedForBuild.IconsPath = $predIcons
                    $resolvedForBuild.RootPath  = "$($script:State.PredecessorPath)"
                    Write-Log "Icons: predecessor reuse -> $(if($predIcons){$predIcons}else{'none in predecessor (Icons left empty)'})"
                }
            }
            $BtnNext.IsEnabled = $false
            # Predecessor reuse: pass the predecessor path + version so New-Package carries its Active Setup .ps1 forward
            # (renamed + content version-swapped to match the reused script's references).
            $predPathForBuild = ''; $predVerForBuild = ''
            if ($script:State.PredecessorModel -and "$($script:State.PredecessorPath)".Trim()) {
                $predPathForBuild = "$($script:State.PredecessorPath)"
                $predVerForBuild  = "$($script:State.PredecessorModel.Identity.Version)"
            }
            Show-PBBusy -Title 'Creating package' -Detail "Assembling $($p.FullName): PSADT template, script, installer files, transforms, documents..."
            try {
                $pkg = New-Package -NewPkg $newPkg -ScriptText $script:State.ScriptText -Resolved $resolvedForBuild `
                           -ChosenInstallers $ins -LooseFiles ([bool]$script:State.LooseFiles) `
                           -RemoveShortcut ([bool]$script:State.RemoveShortcut) -RemoveRun32 ([bool]$script:State.RemoveRun32) -RemoveRun64 ([bool]$script:State.RemoveRun64) `
                           -RemoveStartup ([bool]$script:State.RemoveStartup) -RemoveStray ([bool]$script:State.RemoveStray) `
                           -CreateArp ([bool]$script:State.LooseArp) -ShortcutTargets $targets -MsiPropsMap $msiPropsMap -MsiFlagsMap $msiFlagsMap `
                           -MstApplyExtras @($script:State.MstApplyExtras) -PredecessorPath $predPathForBuild -PredVersion $predVerForBuild `
                           -GenerateMst ([bool]$script:State.GenerateMst)
            } finally { Hide-PBBusy }
            $BtnNext.IsEnabled = $true
            if ($pkg -and (Test-Path $pkg)) {
                $LblCreateResult.Text = "Created: $pkg"; $LblCreateResult.Foreground = '#6A9955'
                $script:State.CreatedPath = $pkg
                Populate-Publish
                if ([Windows.MessageBox]::Show("Package created:`n$pkg`n`nOpen the folder?", 'Done', 'YesNo', 'Information') -eq 'Yes') { Start-Process explorer.exe $pkg }
            } else {
                $LblCreateResult.Text = "Create failed - see $(if(Get-Command Get-LogPath -EA SilentlyContinue){Get-LogPath}else{'the log'})"; $LblCreateResult.Foreground = '#F48771'
            }
        } catch {
            $BtnNext.IsEnabled = $true
            $LblCreateResult.Text = "Create failed: $($_.Exception.Message)"; $LblCreateResult.Foreground = '#F48771'
            [Windows.MessageBox]::Show("Create failed: $($_.Exception.Message)", 'Create', 'OK', 'Error') | Out-Null
        }
        return
    }
  if ($script:Step -eq 1) {
        if (-not (Parse-Current)) { return }       # HARD STOP: name format / Group 34-char limit
        if (-not (Test-OrderNumberGate)) { return } # HARD STOP: AES number format (GPF)
        if (Test-LiveShareDuplicate) { return }   # warn once if this exact name is already in the live share
        $script:State.Ritm = $TxtRitm.Text.Trim()
        if (-not $script:State.ChosenInstallers -or $script:State.ChosenInstallers.Count -eq 0) {
            [Windows.MessageBox]::Show('Fetch a source with at least one installer/payload file before continuing.',(Get-PBToolName)) | Out-Null
            return
        }
        if ($script:State.ChosenInstallers | Where-Object { $_.Extension.ToLower() -eq '.iso' }) {
            [Windows.MessageBox]::Show(
                "This source contains an ISO file.`n`nMount the ISO, copy the extracted source files into the Source folder, then fetch again. The build cannot continue with an ISO because the install commands depend on the real installer type.",
                'ISO detected', 'OK', 'Warning') | Out-Null
            return
        }
    }

    Show-Step ($script:Step+1)
})

# Make the step rail (1-4) clickable, so you can jump straight to Step 4 to Publish an existing
# package by name (no build needed). Per-step rehydration keeps each panel truthful.
foreach ($i in 1..4) {
    $btn = Get-Variable -Name "S$i" -ValueOnly
    $btn.Tag = $i
    $btn.add_MouseLeftButtonDown({
        $target = [int]$this.Tag
        # Leaving Step 1 forward must pass the same hard stops as Next (name format / Group 34-char / AES number),
        # so the clickable strip can't be used to skip validation. Backward jumps are always allowed.
        if ($script:Step -eq 1 -and $target -gt 1) {
            if (-not (Parse-Current)) { return }
            if (-not (Test-OrderNumberGate)) { return }
        }
        Show-Step $target
    })
    # Hover lifts a non-current pill slightly so it reads as clickable.
    $btn.add_MouseEnter({ if ([int]$this.Tag -ne $script:Step) { $this.Background = $script:StripBrush.HoverBg } })
    $btn.add_MouseLeave({ if ([int]$this.Tag -ne $script:Step) { $this.Background = 'Transparent' } })
}

Show-Step 1
# An exception that escapes a WPF handler ends ShowDialog - and, compiled, there is no console for it to be
# printed on: the tool would just vanish. So it is caught here, written to a crash log beside the tool's work
# folder and SHOWN, so "it closed without any error" can never be the report again.
try { $script:Win.ShowDialog() | Out-Null }
catch {
    $crash = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $($_.Exception.GetType().Name): $($_.Exception.Message)`r`n$($_.ScriptStackTrace)`r`n"
    $crashFile = $null
    try { $crashFile = Join-Path (Get-WorkPath 'Logs') 'PackageAssistance-crash.log'; Add-Content -LiteralPath $crashFile -Value $crash -Encoding UTF8 } catch {}
    try { [Windows.MessageBox]::Show("The tool hit an error it could not recover from and has to close:`r`n`r`n$($_.Exception.Message)`r`n`r`n$(if ($crashFile) { "Details were written to`r`n$crashFile" })", 'Package Assistance', 'OK', 'Error') | Out-Null } catch {}
}

# ---- SHUT DOWN FOR REAL when the window closes.
# The busy card runs its own WPF dispatcher on a second thread, and the warm-up
# and job runspaces may still be open. Any one of those keeps the process alive
# after the window has gone - which is how three invisible PackageCompanion.exe
# processes from three different days were found running, locking the folder.
# So: tell the busy thread to quit, give it a moment, then stop and dispose
# every runspace we own, and end the process. Nothing is left to linger.
try { $script:Busy.Quit = $true } catch {}
try {
    if ($script:BusyHandle -and $script:BusyPs) {
        $deadline = (Get-Date).AddSeconds(2)
        while (-not $script:BusyHandle.IsCompleted -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50 }
    }
} catch {}
foreach ($name in 'BusyPs', 'WarmPs') {
    try {
        $ps = Get-Variable -Name $name -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if ($ps) {
            try { $ps.Stop() } catch {}
            try { if ($ps.Runspace) { $ps.Runspace.Close(); $ps.Runspace.Dispose() } } catch {}
            try { $ps.Dispose() } catch {}
        }
    } catch {}
}
try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() } catch {}
# Compiled (the exe) or started with -File: end the process outright. Only a
# developer who dot-sourced this into an interactive console is spared.
$interactiveConsole = ($Host.Name -eq 'ConsoleHost') -and $PSScriptRoot -and
                      ([Environment]::GetCommandLineArgs() -notcontains '-File') -and
                      ([Environment]::GetCommandLineArgs() -notcontains '-file')
if (-not $interactiveConsole) { [Environment]::Exit(0) }

