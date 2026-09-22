# ==============================================================================
#  Audi SCCM Integration Tool - packager window
# ==============================================================================
#  Run:   .\Packager\Start-AudiSwClient.ps1
#
#  One window, five pages on a navigation rail:
#
#    Integrate   read a package folder, correct what the script says, submit
#    Modify      read what the site has, change settings, add/retire collections
#    Members     put machines into, or take them out of, the package's collections
#    Remove      take the application out of SCCM, behind a typed confirmation
#    Jobs        what the server is doing now, and everything it has done
#
#  The header carries the three things every job needs - package name, RFC,
#  environment - so they are set once and every page uses them.
#
#  Every action writes a job FILE into the drop folder and waits for the
#  server's result file. The window never connects to SCCM and holds no SCCM
#  rights. It states no identity: the job file has no requester field at all.
#
#  The window never freezes. The work runs in a background runspace and the
#  window polls a shared table for progress - the same arrangement used in
#  Package Builder.
#
#  Dark by default; the theme toggle at the foot of the rail is remembered per
#  user. Every colour is a keyed brush in the XAML and both palettes are below,
#  so a theme change swaps brushes and nothing is reloaded.
#
#  ASCII only.
# ==============================================================================

[CmdletBinding()]
param(
    [string]$EnvironmentCode,

    # Overrides the drop folder from the environment file. For testing only:
    # point it at a local folder and run the collector by hand, and the whole
    # round trip works with no server and no share. The window shows a SANDBOX
    # badge whenever this is in use, so a test run can never be mistaken for a
    # real one.
    [string]$DropFolder,

    # Exercises the window's own code paths and exits, without showing it. Where
    # the server half is also present - the source tree, or the SCCM machine -
    # it plays both sides and checks the full round trip as well.
    [switch]$SelfTest,

    # TESTING ONLY. Every job the window sends asks the server to rehearse
    # rather than change anything. There is deliberately no switch for this in
    # the window: a packager's job is always real. The header shows TEST MODE
    # while it is on.
    [switch]$DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# ------------------------------------------------------------------ the engine
#
# THE CLIENT IS SELF-CONTAINED.
#
# It loads three files from its own Lib folder and nothing from the server:
# Config.ps1 to read the package and the environment files, Transport.ps1 to
# write the job and read results back, Runtime.ps1 for the logging those use.
#
# The SCCM half - Provider, Steps, Inspect, Preflight, Orchestrator - is not in
# this folder at all. The window never connects to a site, so it must not be
# able to; a window that CAN reach SCCM will eventually be made to.
#
# Packager\Config is a COPY of SccmServer\Engine\Config. Update-PackagerLib.ps1
# keeps them identical - the server's is the master, and nothing here is
# edited by hand.
. (Join-Path $PSScriptRoot 'Lib\Load.ps1')

# ------------------------------------------------------------------ settings
#
# ONE FILE PER INSTALL, ONE FILE PER PACKAGER.
#
#   Packager\Settings.txt                            the team's: DropFolder, DocumentsRoot
#   %LOCALAPPDATA%\AudiSwIntegration\settings.txt    what this packager changed in the
#                                                    window: DocumentsRoot, Theme
#
# Both are "key = value" lines; the packager's wins. Nothing else is
# configured on a packager machine - the environments, shares and rules all
# come from Config\Defaults.xml, which is a copy of the server's.
$script:TeamSettingsFile = Join-Path $PSScriptRoot 'Settings.txt'
$script:UserSettingsFile = Join-Path $env:LOCALAPPDATA 'AudiSwIntegration\settings.txt'

function Read-SettingsFile { param([string]$Path)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $map[$t.Substring(0, $eq).Trim()] = $t.Substring($eq + 1).Trim()
    }
    return $map
}
$script:TeamSettings = Read-SettingsFile $script:TeamSettingsFile
$script:UserSettings = Read-SettingsFile $script:UserSettingsFile

function Get-Setting { param([string]$Key)
    if ($script:UserSettings.ContainsKey($Key) -and $script:UserSettings[$Key]) { return $script:UserSettings[$Key] }
    if ($script:TeamSettings.ContainsKey($Key)) { return $script:TeamSettings[$Key] }
    return ''
}
function Save-Setting { param([string]$Key, [string]$Value)
    <#  Remembers one value for this packager. Rewrites the whole small file so
        it always stays readable by hand.  #>
    if ($SelfTest) { return }   # a self test must not overwrite the packager's file
    $script:UserSettings[$Key] = $Value
    try {
        $dir = Split-Path -Parent $script:UserSettingsFile
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $lines = @('# Remembered by the Audi SCCM Integration Tool for this user. key = value.') +
                 @($script:UserSettings.Keys | Sort-Object | ForEach-Object { "{0} = {1}" -f $_, $script:UserSettings[$_] })
        [System.IO.File]::WriteAllLines($script:UserSettingsFile, $lines)
    } catch { }   # a value that is not remembered is not worth an error
}

# The drop folder: -DropFolder on the command line (testing, shows SANDBOX),
# otherwise Settings.txt. The window creates <ENV>\<Package>\New underneath it.
$SandboxDrop = [bool]$DropFolder
if (-not $DropFolder) { $DropFolder = Get-Setting 'DropFolder' }

# ------------------------------------------------------------------ the window
$xamlPath = Join-Path $PSScriptRoot 'MainWindow.xaml'
$xamlText = (Get-Content -LiteralPath $xamlPath -Raw) -replace 'mc:Ignorable="d"', ''
try {
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xamlText)
    $window = [Windows.Markup.XamlReader]::Load($reader)
}
catch { throw "The window layout could not be loaded: $($_.Exception.Message)" }

# one hashtable holds every control, so handlers share a single captured object
# rather than relying on scope - closures each get their own scope otherwise
$ui = @{}
([xml]$xamlText).SelectNodes("//*[@*[local-name()='Name']]") | ForEach-Object {
    $name = $_.Name
    if ($name) { $ui[$name] = $window.FindName($name) }
}
$ui['Window'] = $window

# Size to the screen actually in use rather than a fixed 1180x820, which is
# larger than some laptop displays. Capped so it stays usable on a 4K monitor.
$work = [System.Windows.SystemParameters]::WorkArea
$window.Width  = [Math]::Min([Math]::Max($work.Width  * 0.82, 900), 1500)
$window.Height = [Math]::Min([Math]::Max($work.Height * 0.88, 620), 1000)
if ($window.Width -ge $work.Width -or $window.Height -ge $work.Height) { $window.WindowState = 'Maximized' }

# shared state between the window and the background runspace
$state = [hashtable]::Synchronized(@{
    Running   = $false
    Step      = ''
    Done      = $false
    Result    = $null
    Error     = $null
    StepCount = 8
    Waiting   = $false   # true while the job sits in the drop folder
    Note      = ''
    JobId     = ''
    InspectFrom = ''     # which page asked for the Inspect: Modify or Members
    CopyStep  = $null    # the content-share copy this run did, shown as the first step
    PendingMembers = $null   # member changes sent and not yet answered
    PendingChange  = $null   # collection/setting changes sent and not yet answered
    FindPending    = $false  # a Find is out; its answer goes to the Remove page's list
    # the background run lives here, not in a function local - see Start-Worker
    Runspace  = $null
    Worker    = $null
    Handle    = $null
    Timer     = $null
})

$defaults = Get-AudiDefaults

# ---------------------------------------------------------------- small helpers
# Declared up front: under Set-StrictMode -Version 2.0 reading one of these
# before it has been assigned is a terminating error, and both are read by
# handlers that can fire before the package has been read.
$script:DocOperatingSystems = @()   # Windows versions the instruction document ticked
$script:SettingsBaseline    = @{}   # setting values as the site reported them
$script:CollectionMembers   = @{}   # collection name -> machines the site reported
$script:MemberChanges       = @()   # queued Add/Remove, sent only on Apply
# Under StrictMode a script variable that was never assigned THROWS when read,
# and the window dies on the first click that reads it. Everything the pages
# read before a Read from SCCM or a failed run exists from the start.
$script:SiteState           = $null # the collections the last Read from SCCM returned
$script:FailedRun           = $null # the last failed run, for Run again / Clean up
$script:Theme               = 'Dark' # replaced by Set-Theme at startup

# The colour argument is a TONE, looked up in the current theme, so a warning
# is readable on the dark page as well as the light one. The hex values are
# the light theme's own, kept so every call site reads as the colour it means.
$script:StatusTone = @{
    '#FF16242A' = 'Ink'; '#FF8A5300' = 'Amber'; '#FFB3261E' = 'Danger'; '#FF00707D' = 'TealDeep'
    'Ink' = 'Ink'; 'Amber' = 'Amber'; 'Danger' = 'Danger'; 'Ok' = 'TealDeep'
}
function Set-Status { param([string]$Text, [string]$Colour = 'Ink')
    $ui.txtStatus.Text = $Text
    $key = $(if ($script:StatusTone.ContainsKey($Colour)) { $script:StatusTone[$Colour] } else { 'Ink' })
    # A resource REFERENCE, not the brush: it follows the theme when it changes.
    $ui.txtStatus.SetResourceReference([System.Windows.Controls.TextBox]::ForegroundProperty, $key)
}

# ------------------------------------------------------------------- the theme
#
# Both palettes, keyed exactly as the brushes in MainWindow.xaml. Applying one
# replaces the brush objects in Window.Resources; every DynamicResource in the
# XAML follows. Dark is the default - the choice is remembered per user under
# LOCALAPPDATA, never on the share.
$script:Palettes = @{
    Light = @{
        Bg = '#FFF3F5F6'; Card = '#FFFFFFFF'; CardBorder = '#FFD5DCE0'; Field = '#FFFFFFFF'; FieldBorder = '#FFC3CCD1'
        FieldFocus = '#FFF9FCFC'; Ink = '#FF16242A'; InkMuted = '#FF4C6870'
        Brand = '#FF002733'; BrandInk = '#FFFFFFFF'; BrandSub = '#FF99D1CD'
        Rail = '#FFFFFFFF'; RailBorder = '#FFD5DCE0'; RailInk = '#FF4C6870'; RailActive = '#FFE3F3F1'; RailActiveInk = '#FF002733'
        Teal = '#FF008C82'; TealDeep = '#FF00706A'; TealPale = '#FFE3F3F1'; Mint = '#FF99D1CD'
        Danger = '#FFB3261E'; DangerPale = '#FFFBEAE8'; DangerLine = '#FFE7B4B0'
        Amber = '#FF8A5300'; AmberPale = '#FFFFF6E5'; AmberLine = '#FFE0A93C'; AmberInk = '#FF5C3A00'
        Strip = '#FFE9EDEF'; PrimaryBg = '#FF002733'; PrimaryFg = '#FFFFFFFF'; PrimaryHover = '#FF008C82'
        GhostHover = '#FFF3F5F6'; RowAlt = '#FFF8FAFB'; GridLine = '#FFEDF0F2'; Track = '#FFDCE2E5'; Thumb = '#FFB9C4CA'
        SandboxBg = '#FFF2B400'; SandboxInk = '#FF002733'
    }
    Dark = @{
        Bg = '#FF0F1A1F'; Card = '#FF16252C'; CardBorder = '#FF25383F'; Field = '#FF0F1A1F'; FieldBorder = '#FF31474F'
        FieldFocus = '#FF13222A'; Ink = '#FFE6ECEF'; InkMuted = '#FF93A7AF'
        Brand = '#FF06161C'; BrandInk = '#FFFFFFFF'; BrandSub = '#FF99D1CD'
        Rail = '#FF121F25'; RailBorder = '#FF25383F'; RailInk = '#FFA3B5BC'; RailActive = '#FF1B3036'; RailActiveInk = '#FFFFFFFF'
        Teal = '#FF1FA79B'; TealDeep = '#FF6ED0C5'; TealPale = '#FF15332F'; Mint = '#FF2F6F69'
        Danger = '#FFF08C84'; DangerPale = '#FF3A1B19'; DangerLine = '#FF7A3530'
        Amber = '#FFF2B84B'; AmberPale = '#FF33270F'; AmberLine = '#FF8A5300'; AmberInk = '#FFF7D89A'
        Strip = '#FF121F25'; PrimaryBg = '#FF1FA79B'; PrimaryFg = '#FF06161C'; PrimaryHover = '#FF6ED0C5'
        GhostHover = '#FF1B2B32'; RowAlt = '#FF132128'; GridLine = '#FF1E3037'; Track = '#FF25383F'; Thumb = '#FF3D545D'
        SandboxBg = '#FFF2B400'; SandboxInk = '#FF06161C'
    }
}

function Set-Theme { param([string]$Name)
    if (-not $script:Palettes.ContainsKey($Name)) { $Name = 'Dark' }
    foreach ($key in $script:Palettes[$Name].Keys) {
        $colour = [System.Windows.Media.ColorConverter]::ConvertFromString($script:Palettes[$Name][$key])
        $brush  = New-Object System.Windows.Media.SolidColorBrush $colour
        $brush.Freeze()
        # Remove then Add, through the METHODS: the indexer hands WPF a PSObject
        # wrapper and it throws "Unable to cast PSObject to Brush". Add notifies
        # every DynamicResource the same way the indexer would.
        $null = $window.Resources.Remove($key)
        $window.Resources.Add($key, $brush.psobject.BaseObject)
    }
    $script:Theme = $Name
    # sun to go light, moon to go dark - the glyph says what the click DOES
    $ui.btnTheme.Content = $(if ($Name -eq 'Dark') { [string][char]0xE706 } else { [string][char]0xE708 })
    $ui.btnTheme.ToolTip = $(if ($Name -eq 'Dark') { 'Switch to light' } else { 'Switch to dark' })
    Save-Setting 'Theme' $Name
}

function Get-SavedTheme {
    $saved = Get-Setting 'Theme'
    return $(if ($saved) { $saved } else { 'Dark' })
}

function Show-Warning { param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { $ui.brdWarning.Visibility = 'Collapsed'; return }
    $ui.txtWarning.Text = $Text
    $ui.brdWarning.Visibility = 'Visible'
}

function Show-Box { param([object[]]$A)
    <#  Every dialog goes through here: Show-Box (text, title, buttons, icon).
        Under -SelfTest nothing pops up - the box is recorded and answered
        'No' / 'OK', so a whole click path (Integrate up to its confirmation)
        can be driven without a screen and without a person.  #>
    $text = "$($A[0])"; $title = $(if ($A.Count -gt 1) { "$($A[1])" } else { '' })
    $buttons = $(if ($A.Count -gt 2) { "$($A[2])" } else { 'OK' }); $icon = $(if ($A.Count -gt 3) { "$($A[3])" } else { 'None' })
    if ($SelfTest) {
        $script:SelfTestBoxes += ,([pscustomobject]@{ Title = $title; Text = $text; Buttons = $buttons })
        return $(if ($buttons -like 'YesNo*') { 'No' } else { 'OK' })
    }
    return [Windows.MessageBox]::Show($text, $title, $buttons, $icon)
}
$script:SelfTestBoxes = @()

function Invoke-Guarded { param([string]$What, [scriptblock]$Action)
    <#  Every button goes through this. An error inside a click handler would
        otherwise leave the WPF message loop as an exception and take the whole
        window down - "the tool closed when I pressed Integrate". Here it is
        shown, with the line it came from, and the window stays up.  #>
    try { & $Action }
    catch {
        $where = $(try { " (line $($_.InvocationInfo.ScriptLineNumber))" } catch { '' })
        $text = "$What could not be done: $($_.Exception.Message)$where"
        try { Set-Status $text '#FFB3261E' } catch {}
        try { if ($state.Running) { $state.Running = $false; Set-Busy $false } } catch {}
        $null = Show-Box ($text + "`r`n`r`nNothing was submitted. The window stays open; if this keeps happening, copy this text into a ticket.", "$What", 'OK', 'Error')
    }
}

function Set-Busy { param([bool]$Busy)
    foreach ($b in 'btnHistory','btnFetchStatus','btnIntegrate','btnBrowse','btnRead','btnInspect','btnApplyChanges','btnMembersRead','btnApplyMembers') {
        $ui[$b].IsEnabled = -not $Busy
    }
    # Run again / Clean up follow the last result, never the busy flag; while a
    # run is on they are off, and Show-PreviousRuns switches them back on
    if ($Busy) { $ui.btnRunAgain.IsEnabled = $false; $ui.btnCleanUp.IsEnabled = $false }
    # Remove and the two Apply buttons have their own enabling rules; when the
    # window is free again those rules decide, not this.
    if (-not $Busy) { Update-RemoveGate; Update-MembersSummary; Update-ApplyGate; Update-ContentState }
    else { $ui.btnRemove.IsEnabled = $false; $ui.btnRemoveFound.IsEnabled = $false; $ui.btnFind.IsEnabled = $false; $ui.btnRefreshContent.IsEnabled = $false; $ui.btnCopyContent.IsEnabled = $false }
    if (-not $Busy) { $ui.btnFind.IsEnabled = $true; $ui.btnRefreshContent.IsEnabled = $true }
    $ui.Window.Cursor = if ($Busy) { 'Wait' } else { 'Arrow' }
}

# Everything the packager can correct, as the window currently shows it. These
# travel with the job so the server uses exactly what was on the screen.
function Get-PackageDetail {
    return @{
        Publisher    = $ui.txtPublisher.Text.Trim()
        Product      = $ui.txtProduct.Text.Trim()
        Version      = $ui.txtVersion.Text.Trim()
        Architecture = $ui.txtArchitecture.Text.Trim()
        Revision     = $ui.txtRevision.Text.Trim()
        Language     = $ui.txtLanguage.Text.Trim()
        BrandingKey  = $ui.txtBranding.Text.Trim()
    }
}

# ------------------------------------------------------------- the pages
# The rail's radio buttons drive the TabControl, and the TabControl drives the
# rail back, so a page selected by the script (a run jumps to Jobs) lights up
# the right rail entry too. Pages are selected BY NAME, never by index.
$script:PageOf = [ordered]@{ navIntegrate = 'tabIntegrate'; navModify = 'tabModify'; navMembers = 'tabMembers'
                             navRemove = 'tabRemove'; navJobs = 'tabJobs' }
function Show-Page { param([string]$Tab)
    if (-not $ui[$Tab].IsSelected) { $ui[$Tab].IsSelected = $true }
    foreach ($nav in $script:PageOf.Keys) {
        if ($script:PageOf[$nav] -eq $Tab -and -not $ui[$nav].IsChecked) { $ui[$nav].IsChecked = $true }
    }
}

# ---------------------------------------------------------------- populate once
# THE ENVIRONMENT IS THE PACKAGER'S CHOICE.
#
# It is NOT read from the package name. An INA_ package is published into ICZ
# (test) first and INA (production) after, under the same name - so the prefix
# says who the package is for, not where this job goes. The list offered comes
# from Defaults.xml (ClientEnvironments), which is why PCZ is absent until its
# file is confirmed. Nothing is preselected: a job cannot go to an environment
# nobody chose.
#
# Environment files describe SCCM topology and stay on the server. Whether a
# chosen environment really exists there is the SERVER's decision - the job
# lands in that environment's folder under the drop root, and the collector
# serves each folder with that environment's own file.
$script:EnvironmentLabel = @{}
function Get-SelectedEnvironment {
    <#  The code of the environment chosen in the header, or '' if none.  #>
    $item = $ui.cboEnvironment.SelectedItem
    if ($null -eq $item) { return '' }
    return [string]$item.Code
}

function Update-EnvironmentList {
    $selected = Get-SelectedEnvironment
    $ui.cboEnvironment.Items.Clear()
    foreach ($e in @($defaults.ClientEnvironments)) {
        $script:EnvironmentLabel[$e.Code] = $e.Label
        $null = $ui.cboEnvironment.Items.Add([pscustomobject]@{ Code = $e.Code; Label = $e.Label })
    }
    $ui.cboEnvironment.DisplayMemberPath = 'Label'
    if ($selected) { Select-Environment $selected }
}

function Select-Environment { param([string]$Code)
    foreach ($item in $ui.cboEnvironment.Items) {
        if ($item.Code -eq $Code) { $ui.cboEnvironment.SelectedItem = $item; return $true }
    }
    return $false
}

Update-EnvironmentList
if ($EnvironmentCode) {
    if (-not (Select-Environment $EnvironmentCode)) {
        throw "'$EnvironmentCode' is not an environment this window offers. Defaults.xml lists: $(@($defaults.ClientEnvironments | ForEach-Object { $_.Code }) -join ', ')."
    }
}

# ---------------------------------------------------------- reaching a share
#
# Every network path the window uses - the drop folder, the documents
# location, the content share, a package on a share - goes through
# Connect-AudiShare first. When the path cannot be opened it asks for a user
# name and password, up to three times, and connects with them; a stale
# session on the same server (the "multiple connections to a server" error
# net use gives) is cleared and the attempt repeated. After three failures it
# gives up and says so; the next click asks again. The password lives in a
# PSCredential for the attempt and nowhere else - never on a command line,
# never in a file.
$script:ShareDriveCount = 0

function Get-ShareRoot { param([string]$Path)
    <#  \\server\share out of any UNC path; '' for a local path.  #>
    if ($Path -notlike '\\*') { return '' }
    $parts = @($Path.TrimStart('\') -split '\\' | Where-Object { $_ })
    if ($parts.Count -lt 2) { return '' }
    return '\\' + $parts[0] + '\' + $parts[1]
}

function Request-AudiCredential { param([string]$Target, [int]$Attempt, [string]$LastError)
    <#  A small themed dialog: user name, password, Connect / Cancel. Returns a
        PSCredential, or $null when cancelled.  #>
    $dlg = New-Object System.Windows.Window
    $dlg.Title = 'Sign in to the share'
    $dlg.Owner = $window
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.SizeToContent = 'WidthAndHeight'
    $dlg.ResizeMode = 'NoResize'
    $dlg.FontFamily = $window.FontFamily; $dlg.FontSize = 12
    $dlg.Resources.MergedDictionaries.Add($window.Resources)
    $dlg.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'Card')

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = '22,18,22,18'
    foreach ($w in @('Auto', '320')) { $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = $w; $grid.ColumnDefinitions.Add($c) }
    foreach ($i in 0..5) { $r = New-Object System.Windows.Controls.RowDefinition; $r.Height = 'Auto'; $grid.RowDefinitions.Add($r) }

    $add = { param($el, $row, $col, $span)
        [System.Windows.Controls.Grid]::SetRow($el, $row); [System.Windows.Controls.Grid]::SetColumn($el, $col)
        if ($span) { [System.Windows.Controls.Grid]::SetColumnSpan($el, $span) }
        $null = $grid.Children.Add($el) }

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "This share needs a sign-in ($Attempt of 3)"; $title.FontSize = 14; $title.FontWeight = 'SemiBold'; $title.Margin = '0,0,0,4'
    $title.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Ink')
    & $add $title 0 0 2
    $path = New-Object System.Windows.Controls.TextBlock
    $path.Text = $Target; $path.FontFamily = 'Consolas'; $path.TextWrapping = 'Wrap'; $path.Margin = '0,0,0,10'; $path.MaxWidth = 420
    $path.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'TealDeep')
    & $add $path 1 0 2
    if ($LastError) {
        $why = New-Object System.Windows.Controls.TextBlock
        $why.Text = $LastError; $why.TextWrapping = 'Wrap'; $why.Margin = '0,0,0,10'; $why.MaxWidth = 420; $why.FontSize = 11
        $why.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Danger')
        & $add $why 2 0 2
    }
    $lblUser = New-Object System.Windows.Controls.TextBlock; $lblUser.Text = 'User name'; $lblUser.Margin = '0,0,12,6'; $lblUser.VerticalAlignment = 'Center'
    $lblUser.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'InkMuted')
    & $add $lblUser 3 0 0
    $txtUser = New-Object System.Windows.Controls.TextBox; $txtUser.Margin = '0,0,0,6'; $txtUser.Text = "$env:USERDOMAIN\"
    & $add $txtUser 3 1 0
    $lblPass = New-Object System.Windows.Controls.TextBlock; $lblPass.Text = 'Password'; $lblPass.Margin = '0,0,12,6'; $lblPass.VerticalAlignment = 'Center'
    $lblPass.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'InkMuted')
    & $add $lblPass 4 0 0
    $txtPass = New-Object System.Windows.Controls.PasswordBox; $txtPass.Margin = '0,0,0,12'; $txtPass.Padding = '6,4,6,4'
    & $add $txtPass 4 1 0
    $buttons = New-Object System.Windows.Controls.StackPanel; $buttons.Orientation = 'Horizontal'; $buttons.HorizontalAlignment = 'Right'
    $btnCancel = New-Object System.Windows.Controls.Button; $btnCancel.Content = 'Cancel'; $btnCancel.Style = $window.Resources['BtnGhost']; $btnCancel.IsCancel = $true
    $btnOk = New-Object System.Windows.Controls.Button; $btnOk.Content = 'Connect'; $btnOk.Style = $window.Resources['BtnPrimary']; $btnOk.IsDefault = $true; $btnOk.Margin = '0'
    $null = $buttons.Children.Add($btnCancel); $null = $buttons.Children.Add($btnOk)
    & $add $buttons 5 0 2
    $dlg.Content = $grid

    $result = @{ Credential = $null }
    $btnOk.Add_Click({
        if ([string]::IsNullOrWhiteSpace($txtUser.Text) -or $txtPass.SecurePassword.Length -eq 0) { return }
        $result.Credential = New-Object System.Management.Automation.PSCredential($txtUser.Text.Trim(), $txtPass.SecurePassword)
        $dlg.DialogResult = $true
    })
    $dlg.Add_ContentRendered({ if ($txtUser.Text.EndsWith('\')) { $txtUser.Focus() | Out-Null; $txtUser.CaretIndex = $txtUser.Text.Length } else { $txtPass.Focus() | Out-Null } })
    $null = $dlg.ShowDialog()
    return $result.Credential
}

function Show-Confirm {
    <#  THE confirmation window, one shape for every action that changes
        something: a headline, "This will" as label/value rows, "Not touched"
        as a quiet list, a one-line question, Cancel / <verb>. Themed like the
        window, read top to bottom in ten seconds. Returns $true on the verb.
        Under -SelfTest it is recorded and answered No.  #>
    param(
        [string]$Title,                 # window title and the verb on the button, e.g. 'Integrate'
        [string]$Headline,              # "Integrate INA_… in INA"
        [string]$Lead = '',             # one quiet sentence under the headline
        [object[]]$Rows = @(),          # @{ Label; Value } - what happens
        [string[]]$NotTouched = @(),    # what does not happen
        [string]$Question = '',         # the last line
        [switch]$Danger                 # red accent for removals
    )
    if ($SelfTest) {
        $script:SelfTestBoxes += ,([pscustomobject]@{ Title = $Title; Text = $Headline; Buttons = 'YesNo'; Rows = @($Rows).Count })
        return $false
    }
    $dlg = New-Object System.Windows.Window
    $dlg.Title = $Title; $dlg.Owner = $window; $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.SizeToContent = 'WidthAndHeight'; $dlg.ResizeMode = 'NoResize'; $dlg.MaxWidth = 760
    $dlg.FontFamily = $window.FontFamily; $dlg.FontSize = 12
    $dlg.Resources.MergedDictionaries.Add($window.Resources)
    $dlg.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'Card')

    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '26,20,26,18'; $root.MinWidth = 520
    $accent = $(if ($Danger) { 'Danger' } else { 'Teal' })

    $bar = New-Object System.Windows.Controls.Border; $bar.Height = 3; $bar.Margin = '0,0,0,14'; $bar.HorizontalAlignment = 'Left'; $bar.Width = 44
    $bar.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $accent)
    $null = $root.Children.Add($bar)

    $h = New-Object System.Windows.Controls.TextBlock; $h.Text = $Headline; $h.FontSize = 16; $h.FontWeight = 'SemiBold'; $h.TextWrapping = 'Wrap'
    $h.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Ink'); $null = $root.Children.Add($h)
    if ($Lead) {
        $l = New-Object System.Windows.Controls.TextBlock; $l.Text = $Lead; $l.TextWrapping = 'Wrap'; $l.Margin = '0,4,0,0'; $l.FontSize = 11.5
        $l.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'InkMuted'); $null = $root.Children.Add($l)
    }

    $section = { param($text)
        $t = New-Object System.Windows.Controls.TextBlock; $t.Text = $text; $t.FontSize = 10.5; $t.FontWeight = 'SemiBold'; $t.Margin = '0,16,0,6'
        $t.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'InkMuted'); $null = $root.Children.Add($t) }

    if (@($Rows).Count -gt 0) {
        & $section 'THIS WILL'
        $grid = New-Object System.Windows.Controls.Grid
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = 'Auto'; $grid.ColumnDefinitions.Add($c1)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = '*';    $grid.ColumnDefinitions.Add($c2)
        $i = 0
        foreach ($row in @($Rows)) {
            $r = New-Object System.Windows.Controls.RowDefinition; $r.Height = 'Auto'; $grid.RowDefinitions.Add($r)
            $lab = New-Object System.Windows.Controls.TextBlock; $lab.Text = "$($row.Label)"; $lab.Margin = '0,0,16,5'; $lab.VerticalAlignment = 'Top'; $lab.FontSize = 11.5
            $lab.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'InkMuted')
            $val = New-Object System.Windows.Controls.TextBlock; $val.Text = "$($row.Value)"; $val.TextWrapping = 'Wrap'; $val.Margin = '0,0,0,5'; $val.MaxWidth = 560
            if ($row.PSObject.Properties['Mono'] -and $row.Mono) { $val.FontFamily = 'Consolas' }
            $val.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Ink')
            [System.Windows.Controls.Grid]::SetRow($lab, $i); [System.Windows.Controls.Grid]::SetColumn($lab, 0)
            [System.Windows.Controls.Grid]::SetRow($val, $i); [System.Windows.Controls.Grid]::SetColumn($val, 1)
            $null = $grid.Children.Add($lab); $null = $grid.Children.Add($val); $i++
        }
        $null = $root.Children.Add($grid)
    }
    if (@($NotTouched).Count -gt 0) {
        & $section 'NOT TOUCHED'
        foreach ($n in @($NotTouched)) {
            $t = New-Object System.Windows.Controls.TextBlock; $t.Text = "$([char]0x2022)  $n"; $t.TextWrapping = 'Wrap'; $t.Margin = '0,0,0,3'; $t.FontSize = 11.5; $t.MaxWidth = 640
            $t.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'InkMuted'); $null = $root.Children.Add($t)
        }
    }
    if ($Question) {
        $q = New-Object System.Windows.Controls.TextBlock; $q.Text = $Question; $q.TextWrapping = 'Wrap'; $q.Margin = '0,18,0,0'; $q.FontWeight = 'SemiBold'
        $q.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Ink'); $null = $root.Children.Add($q)
    }

    $buttons = New-Object System.Windows.Controls.StackPanel; $buttons.Orientation = 'Horizontal'; $buttons.HorizontalAlignment = 'Right'; $buttons.Margin = '0,18,0,0'
    $btnNo = New-Object System.Windows.Controls.Button; $btnNo.Content = 'Cancel'; $btnNo.Style = $window.Resources['BtnGhost']; $btnNo.IsCancel = $true; $btnNo.MinWidth = 100
    $btnYes = New-Object System.Windows.Controls.Button; $btnYes.Content = $Title; $btnYes.Style = $window.Resources[$(if ($Danger) { 'BtnDanger' } else { 'BtnPrimary' })]; $btnYes.MinWidth = 140; $btnYes.Margin = '0'
    $btnYes.Add_Click({ $dlg.DialogResult = $true })
    $null = $buttons.Children.Add($btnNo); $null = $buttons.Children.Add($btnYes)
    $null = $root.Children.Add($buttons)

    $scroll = New-Object System.Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.MaxHeight = 640; $scroll.Content = $root
    $dlg.Content = $scroll
    $dlg.Add_ContentRendered({ $btnNo.Focus() | Out-Null })   # Enter must not confirm by accident
    return ($dlg.ShowDialog() -eq $true)
}

function Connect-AudiShare { param([string]$Path, [string]$Purpose = 'this folder')
    <#  Makes sure $Path can be opened, signing in when it cannot. Returns
        $true when it can; $false after the packager cancels or three sign-ins
        fail. A local path is simply tested.  #>
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (Test-Path -LiteralPath $Path) { return $true }
    $root = Get-ShareRoot $Path
    if (-not $root) {
        Set-Status "Cannot open $Purpose - $Path does not exist." '#FFB3261E'
        return $false
    }

    # The share root is what needs the sign-in; a folder that is not there
    # once the root opens is a different problem, and is said so below.
    $lastError = ''
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $cred = Request-AudiCredential -Target $root -Attempt $attempt -LastError $lastError
        if (-not $cred) { Set-Status "Cancelled - $Purpose was not opened." '#FF8A5300'; return $false }

        $connected = $false
        foreach ($try in 1, 2) {
            try {
                $script:ShareDriveCount++
                $null = New-PSDrive -Name ("AudiShare{0}" -f $script:ShareDriveCount) -PSProvider FileSystem -Root $root `
                                    -Credential $cred -Scope Global -ErrorAction Stop
                $connected = $true
                break
            }
            catch {
                $lastError = $_.Exception.Message.Trim()
                # A session to this server already exists under another
                # account - Windows allows one per server. Clear it and try the
                # same sign-in once more.
                if ($try -eq 1 -and ($lastError -match '1219' -or $lastError -match 'multiple connections' -or $lastError -match 'Mehrfache Verbindungen')) {
                    $server = '\\' + (($root.TrimStart('\') -split '\\')[0])
                    & net use $root /delete /y 2>&1 | Out-Null
                    & net use "$server\IPC$" /delete /y 2>&1 | Out-Null
                    continue
                }
                break
            }
        }
        if ($connected) {
            if (Test-Path -LiteralPath $Path) { Set-Status "Signed in to $root."; return $true }
            Set-Status "Signed in to $root, but '$Path' is not there. Check the path." '#FFB3261E'
            return $false
        }
    }
    Set-Status ("Could not open {0} after 3 sign-in attempts: {1}. Try again, or check the account has rights on {2}." -f $Purpose, $lastError, $root) '#FFB3261E'
    return $false
}

# ---------------------------------------------------------- one job at a time
function Test-PackageJobPending { param([string]$DropFolder, [string]$Code, [string]$PackageName)
    <#  True - and the reason on the status line and in a dialog - when a job
        for this package is already waiting in \New or running in \Working.
        Two people integrating the same package minutes apart would otherwise
        queue two jobs, and the second would only fail on the server with
        "already exists". Whatever is in flight is shown on the Jobs page.  #>
    $pending = @()
    try { $pending = @(Get-AudiSwPendingJob -DropFolder $DropFolder -EnvironmentCode $Code -PackageName $PackageName) } catch { return $false }
    if ($pending.Count -eq 0) { return $false }
    $first = $pending[0]
    $who   = $(if ($first.JobId -eq $state.JobId) { 'this window' } else { 'another window' })
    $text  = ("A job for {0} in {1} is already {2}: {3}, submitted {4} from {5}.`r`n`r`n" +
              "One job per package at a time. Wait for its result on the Jobs page - it keeps coming in even if that window was closed - then submit again if it is still needed.") -f `
              $PackageName, $Code, $(if ($first.State -eq 'Running') { 'RUNNING on the server' } else { 'QUEUED' }),
              $(if ($first.Action) { $first.Action } else { 'unknown action' }), $first.Submitted.ToString('dd.MM.yyyy HH:mm'), $who
    Set-Status ($text -replace "`r`n`r`n", '  ') '#FF8A5300'
    $null = Show-Box ($text, 'Already in progress', 'OK', 'Warning')
    Show-Page 'tabJobs'
    Show-PreviousRuns
    return $true
}

# ---------------------------------------------------------- package content
#
# The window never reaches the SCCM content store. It puts the package's
# content beside the job, in <drop root>\<ENV>\Sources\<SCCM name>\, the mail
# man carries it across, and the SCCM server copies it into the store as the
# job's first step. So the only share this needs is the drop folder.
function Get-SourcesFolderFor { param([string]$Code)
    <#  <drop root>\<ENV>\Sources - where the window puts package content.  #>
    $drop = Get-ActiveDropFolder
    if (-not $drop -or -not $Code) { return '' }
    return (Get-AudiDropFolderPath -DropFolder $drop -EnvironmentCode $Code).Sources
}

function Get-ContentCopyPlan { param([string]$Code, [string]$SccmName, [string]$PackagePath, [switch]$Replace)
    <#  Decides, before a job is submitted, whether the package content has to
        be put into Sources and from where. Returns
          @{ From; To; Note; Error; NeedsFolder; Cancelled }
        - From/To set when a copy is needed; Note is what the confirmation says;
        Error is why it cannot go on; Cancelled when the packager declined to
        sign in to the drop folder.  #>
    $out = @{ From = ''; To = ''; Note = ''; Error = ''; NeedsFolder = $false; Cancelled = $false }
    $sources = Get-SourcesFolderFor $Code
    if (-not $sources) { $out.Error = 'No drop folder is set - DropFolder in Packager\Settings.txt.'; return $out }
    if (-not (Connect-AudiShare -Path (Get-ActiveDropFolder) -Purpose 'the drop folder')) { $out.Cancelled = $true; return $out }

    $target = Join-Path $sources $SccmName
    if ((Test-Path -LiteralPath $target) -and -not $Replace) {
        $out.Note = "The package content is already in the drop folder, waiting for the server:`r`n$target"
        return $out
    }
    # The store already holds it (the server said so in a result, and cleared
    # Sources because of that): an Integrate copies nothing - the server would
    # only report "Already in the store" and ignore the copy. Update content
    # is the one action that sends files again, on purpose.
    if (-not $Replace) {
        $inStore = Get-StoreContentRecord -Code $Code -Package $SccmName
        if ($inStore) {
            $out.Note = "The package content is already in the SCCM store ($($inStore.Step.ToLowerInvariant()) on $($inStore.When.ToString('dd.MM.yyyy HH:mm'))). Nothing is copied; Update content replaces it."
            return $out
        }
    }
    if (-not $PackagePath -or -not (Test-Path -LiteralPath $PackagePath)) {
        $out.Error = "The package content has to go with the job ($target), and no package folder is given to take it from. Browse to the package folder first."
        $out.NeedsFolder = $true
        return $out
    }
    try   { $out.From = Get-AudiPackageContentRoot -PackagePath $PackagePath }
    catch { $out.Error = $_.Exception.Message; return $out }
    $out.To = $target
    $contentFiles = @(Get-ChildItem -LiteralPath $out.From -File -Recurse -ErrorAction SilentlyContinue)
    $fileCount = $contentFiles.Count
    $bytes = 0; foreach ($f in $contentFiles) { $bytes += $f.Length }
    $out.Note = ("The package content goes with the job. It is copied into the drop folder first, and the SCCM server " +
                 "{4} the content store as the job's first step:`r`n" +
                 "  from  {0}`r`n  to    {1}`r`n  ({2} files, {5:N1} MB{3}; every copy is checked by file count and size)") -f $out.From, $out.To, $fileCount,
                 $(if ($out.From -ne $PackagePath.TrimEnd('\')) { '; only the Content folder, not Documents or Icons' } else { '' }),
                 $(if ($Replace) { 'compares it with what is in the store and updates only what differs in' } else { 'moves it into' }), ($bytes / 1MB)
    return $out
}

function Get-StoreContentRecord { param([string]$Code, [string]$Package)
    <#  What the server last said about this package's files in the store:
        the newest real (not dry-run, not a Remove) result whose content step
        succeeded - Content copy, Content update, or "Already in the store".
        A later Remove that deleted the folder cancels it. $null when the
        drop folder holds no such record. Never throws.  #>
    try {
        $drop = Get-ActiveDropFolder
        if (-not $drop -or -not (Test-Path -LiteralPath $drop)) { return $null }
        foreach ($run in @(Get-AudiSwJobHistory -DropFolder $drop -EnvironmentCode $Code -PackageName $Package)) {
            if ($run.DryRun -or $run.Outcome -eq 'Running') { continue }
            $folderGone = @($run.Steps | Where-Object { $_.Step -eq 'Content folder' -and $_.Ok -and $_.Message -like 'deleted *' }).Count -gt 0
            if ($folderGone) { return $null }
            $content = @($run.Steps | Where-Object { $_.Step -in @('Content copy', 'Content update') -and $_.Ok })
            if ($content.Count -gt 0) { return [pscustomobject]@{ When = $run.Completed; Step = $content[0].Step; JobId = $run.JobId } }
        }
    } catch { }
    return $null
}

function Update-ContentState {
    <#  The "Content share" row on the Integrate page: where the package must
        be for the chosen environment, and whether it is there. Passive - it
        never asks for a sign-in; that happens on Integrate or Copy to share. #>
    $code    = Get-SelectedEnvironment
    $package = $ui.txtPackage.Text.Trim()
    $sources = $(if ($code) { Get-SourcesFolderFor $code } else { '' })
    $ui.btnCopyContent.IsEnabled = $false
    if (-not $code)    { $ui.txtContentTarget.Text = ''; $ui.txtContentState.Text = 'choose the environment first'; return }
    if (-not $sources) { $ui.txtContentTarget.Text = ''; $ui.txtContentState.Text = 'no drop folder set - DropFolder in Packager\Settings.txt'; return }
    if (-not $package) { $ui.txtContentTarget.Text = $sources; $ui.txtContentState.Text = 'name the package to see where it goes'; return }

    $target = Join-Path $sources $package
    $ui.txtContentTarget.Text = $target
    if (-not (Test-Path -LiteralPath (Get-ActiveDropFolder))) {
        $ui.txtContentState.Text = 'drop folder not reachable from here yet - a sign-in is asked for on Integrate or Copy'
        $ui.btnCopyContent.IsEnabled = -not $state.Running
        return
    }
    if (Test-Path -LiteralPath $target) {
        $ui.txtContentState.Text = 'in the drop folder, waiting for the server - nothing to copy'
        return
    }
    # Sources are cleared the moment the store holds a verified copy - even
    # when a later step of that job failed. The result the server wrote back
    # says so, and that is what a packager must read here, not "not copied".
    $inStore = Get-StoreContentRecord -Code $code -Package $package
    if ($inStore) {
        $ui.txtContentState.Text = ('in the SCCM store since {0} ({1}) - nothing to copy; Integrate or Run again continues from there. Update content replaces it.' -f `
                                    $inStore.When.ToString('dd.MM.yyyy HH:mm'), $inStore.Step.ToLowerInvariant())
        return
    }
    $folder = $ui.txtPackagePath.Text.Trim()
    if ($folder -and (Test-Path -LiteralPath $folder)) {
        $ui.txtContentState.Text = 'not in the drop folder yet - Integrate copies it first, or press Copy now'
        $ui.btnCopyContent.IsEnabled = -not $state.Running
    } else {
        $ui.txtContentState.Text = 'not in the drop folder yet - browse to the package folder so it can be copied'
    }
}

function Start-ContentCopy {
    <#  "Copy to share" on its own: same check and same copy as Integrate,
        no job submitted. Runs in the background with progress on the status
        line, and the Content share row is refreshed when it is done.  #>
    $code = Get-SelectedEnvironment
    if (-not $code) { Set-Status (Test-EnvironmentChosen) '#FF8A5300'; return }
    try   { $plan = New-PlanFromForm } catch { Set-Status $_.Exception.Message '#FF8A5300'; return }
    $contentPlan = Get-ContentCopyPlan -Code $code -SccmName $plan.PackageName -PackagePath $ui.txtPackagePath.Text.Trim()
    if ($contentPlan.Error)     { Set-Status $contentPlan.Error '#FFB3261E'; return }
    if ($contentPlan.Cancelled) { return }
    $replace = $false
    if (-not $contentPlan.To) {
        # Already there. The one reason to copy again is that the earlier copy
        # went wrong (a failed job, a copy that did not verify) - so offer it,
        # replacing what is there, rather than just saying no.
        $again = Show-Confirm -Title 'Copy again' -Headline 'The files are already in the drop folder' `
            -Lead 'Copy them again only when an earlier copy failed or the files were wrong.' `
            -Rows @([pscustomobject]@{ Label = 'Folder'; Value = (Join-Path (Get-SourcesFolderFor $code) $plan.PackageName); Mono = $true },
                    [pscustomobject]@{ Label = 'Happens'; Value = 'the folder there is replaced by a fresh, verified copy of the package folder'; Mono = $false }) `
            -Question 'Copy again, replacing what is there?'
        if (-not $again) { Set-Status $contentPlan.Note.Replace("`r`n", ' '); Update-ContentState; return }
        $contentPlan = Get-ContentCopyPlan -Code $code -SccmName $plan.PackageName -PackagePath $ui.txtPackagePath.Text.Trim() -Replace
        if ($contentPlan.Error) { Set-Status $contentPlan.Error '#FFB3261E'; return }
        $replace = $true
    }

    $files = @(Get-ChildItem -LiteralPath $contentPlan.From -File -Recurse -ErrorAction SilentlyContinue)
    $bytes = 0; foreach ($f in $files) { $bytes += $f.Length }
    $ok = Show-Confirm -Title 'Copy now' -Headline "Copy the package files into the drop folder for $code" `
        -Lead 'Nothing is submitted to SCCM. The SCCM server moves the files into the store when a job for the package runs.' `
        -Rows @([pscustomobject]@{ Label = 'From'; Value = $contentPlan.From; Mono = $true },
                [pscustomobject]@{ Label = 'To'; Value = $contentPlan.To; Mono = $true },
                [pscustomobject]@{ Label = 'Size'; Value = ("{0} files, {1:N1} MB - checked by file count and size after the copy" -f $files.Count, ($bytes / 1MB)); Mono = $false }) `
        -Question 'Copy now?'
    if (-not $ok) { Set-Status 'Cancelled.'; return }

    $state.Note = ''
    Set-Status "Copying the package content into the drop folder for $code ..."
    Start-Worker -Steps 1 -StayOnTab -Arguments @{
        PackagePath = $ui.txtPackagePath.Text.Trim(); CopyTo = $contentPlan.To; Replace = $replace
        DropFolder = (Get-ActiveDropFolder); Environment = $code
    } -Body {
        try {
            . (Join-Path $toolRoot 'Load.ps1')
            $state.Step = 'Copying the package content into the drop folder...'
            Initialize-AudiDropFolder -DropFolder $jobArgs.DropFolder -EnvironmentCode $jobArgs.Environment | Out-Null
            $copied = Copy-AudiPackageContent -PackagePath $jobArgs.PackagePath -Replace:([bool]$jobArgs.Replace) `
                        -ContentShare (Split-Path -Parent $jobArgs.CopyTo) -SccmName (Split-Path -Leaf $jobArgs.CopyTo) `
                        -OnProgress { param($d, $t, $f) $state.Step = "Copying into the drop folder... $d of $t files" }
            $state.Result = [pscustomobject]@{
                Ok = $true; CopyOnly = $true
                Message = $(if ($copied.Copied) { "{0} files put into the drop folder at {1}." -f $copied.Files, $copied.Target } else { "Already in the drop folder: {0}." -f $copied.Target })
                Steps = @([pscustomobject]@{ Step = 'Content copy'; Ok = $true
                    Message = $(if ($copied.Copied) { "{0} files put into the drop folder at {1} - the server copies them into the store" -f $copied.Files, $copied.Target } else { "already in the drop folder: {0}" -f $copied.Target }) })
            }
        }
        catch { $state.Error = $_.Exception.Message }
        finally { $state.Done = $true; $state.Running = $false }
    }
}

# ---------------------------------------------------------- documents location
# Where request forms live when they are NOT in the package: one folder per
# request under a root, found by AES ID. Team default in Settings.txt beside
# this script; what the packager types in the window is remembered for them
# (user settings) and wins.
function Save-DocumentRoot { Save-Setting 'DocumentsRoot' $ui.txtDocumentRoot.Text.Trim() }
$ui.txtDocumentRoot.Text = Get-Setting 'DocumentsRoot'

# ---------------------------------------------------------- Windows versions
# One tick box per <OperatingSystem> in Defaults.xml. The request form ticks
# them (Read details); the packager can correct them; what is ticked travels
# in the job and becomes the deployment type's operating system requirement.
# Nothing ticked is refused - an application no Windows version may install
# would be a pointless object.
$script:OsBoxes = @{}
foreach ($os in @($defaults.OperatingSystems)) {
    $box = New-Object System.Windows.Controls.CheckBox
    $box.Content = $os.Label
    $box.Tag     = $os.Key
    $box.Margin  = '0,0,18,4'
    $box.ToolTip = "Requirement rule: $($os.Value)"
    $box.IsChecked = [bool]$os.SelectedByDefault
    $null = $ui.pnlOperatingSystems.Children.Add($box)
    $script:OsBoxes[$os.Key] = $box
}

function Set-OperatingSystemTicks { param([string[]]$Keys)
    <#  Ticks what the request form asked for. A form that says nothing ticks
        every version - which is what the server would require anyway - and
        says so, rather than leaving the packager to guess.  #>
    $wanted = @($Keys | Where-Object { $_ })
    foreach ($key in $script:OsBoxes.Keys) {
        $script:OsBoxes[$key].IsChecked = $(if ($wanted.Count -gt 0) { $wanted -contains $key } else { $true })
    }
    $ui.txtOperatingSystemsNote.Text = $(if ($wanted.Count -gt 0) {
        'Ticked as the request form says. Only the ticked versions can install the application.'
    } else {
        'The request form did not say - every version is ticked. Untick what does not apply.'
    })
}

function Get-OperatingSystemTicks {
    return @($script:OsBoxes.Keys | Where-Object { $script:OsBoxes[$_].IsChecked } | Sort-Object)
}

# Install minutes is deliberately NOT a field. It came from Defaults.xml and was
# never read back, so showing it invited a packager to change something that had
# no effect. The engine takes it from Application/@estimatedInstallMinutes.

# ------------------------------------------------------------- sandbox badge
# A test run must never be mistakable for a real one.
# Only for -DropFolder on the command line. A path from Settings.txt is the
# normal install, not a test rig, and badging it SANDBOX would train people to
# ignore the badge on the day it means something.
if ($SandboxDrop -or $DryRun) {
    $ui.txtMode.Text = $(if ($DryRun -and $SandboxDrop) { 'TEST MODE  -  SANDBOX' } elseif ($DryRun) { 'TEST MODE' } else { 'SANDBOX' })
    $ui.brdMode.ToolTip = $(if ($DryRun) { 'Started with -DryRun: every job asks the server to rehearse and change nothing. ' } else { '' }) +
                          $(if ($SandboxDrop) { "Jobs go to $DropFolder instead of the configured drop folder." } else { '' })
    $ui.brdMode.Visibility = 'Visible'
}

function Get-ActiveDropFolder {
    # One root for every environment - see Settings.txt. The per-environment
    # and per-package folders underneath it are worked out from the package name
    # when the job is written.
    return $DropFolder
}

# ------------------------------------------------------- package and environment
#
# The package name is never rewritten and never decides the environment. That
# is what corrupted ADO_ADOBE_Reader into INA_INABE_Reader in the old tool, and
# it is also simply wrong for Audi: the same INA_ package goes to ICZ and then
# to INA. What follows the header is everything that NAMES the package and the
# environment together - the Remove page, the history - not the dropdown.

function Update-NextStep {
    <#  The strip under the Integrate title: four steps, the current one lit.
        A first-time user reads this and knows what to press; nothing else on
        the page has to explain itself.  #>
    $steps = @('Choose the environment', 'Pick the package folder', 'Read details', 'Integrate')
    $current = 0
    if (Get-SelectedEnvironment) { $current = 1 }
    if ($current -eq 1 -and $ui.txtPackagePath.Text.Trim()) { $current = 2 }
    if ($current -eq 2 -and ($ui.txtNameEN.Text.Trim() -or $ui.txtBranding.Text.Trim())) { $current = 3 }
    $ui.txtNextStep.Inlines.Clear()
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $run = New-Object System.Windows.Documents.Run
        $run.Text = "{0}  {1}" -f ($i + 1), $steps[$i]
        if ($i -eq $current) {
            $run.FontWeight = 'SemiBold'
            $run.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, 'TealDeep')
        }
        elseif ($i -lt $current) {
            $run.Text = "{0}  {1} " -f [char]0x2713, $steps[$i]
        }
        $ui.txtNextStep.Inlines.Add($run) | Out-Null
        if ($i -lt $steps.Count - 1) { $ui.txtNextStep.Inlines.Add((New-Object System.Windows.Documents.Run -ArgumentList '      ')) | Out-Null }
    }
}

function Sync-EnvironmentToPackage {
    <#  Called after a package is read, its name typed, or the environment
        changed: everything that shows "this package in this environment"
        follows the header.  #>
    Update-EnvironmentNotice
    Update-NextStep
    # The Remove page names what it would remove, and its typed confirmation
    # is against THIS name - so both follow the header.
    $package = $ui.txtPackage.Text.Trim()
    $code    = Get-SelectedEnvironment
    $ui.txtRemoveTarget.Text = $(if ($package -and $code) { "$package   in   $code   ($($script:EnvironmentLabel[$code]))" }
                                 elseif ($package)        { "$package   -   choose the environment in the header" }
                                 else                     { '- no package named -' })
    # the exact objects this side knows: the application, its deployment type,
    # and the collections the last Read from SCCM found; the environment file's
    # own list is on the server and comes back by name in the result
    $ui.txtRemoveObjects.Text = ''
    if ($package -and $code) {
        try {
            $suffix = (Get-AudiDefaults).Naming.deploymentTypeSuffix
            $known  = @(Get-KnownCollectionLines -Package $package | ForEach-Object { 'collection    ' + $_.Trim() })
            $ui.txtRemoveObjects.Text = (@("application   $package", "deployment    $package$suffix") + $known +
                                         @($(if ($known.Count -eq 0) { "collections   every one the $code environment file asks for - read from SCCM (Modify page) to see their names here" }))) -join "`r`n"
        } catch { $ui.txtRemoveObjects.Text = "application   $package" }
    }
    Update-RemoveGate
    Update-ContentState
    Show-PreviousRuns
}

function Read-AudiStatusLine { param([string]$Path)
    <#  One status file = one line "iso-time|host|OK or FAILED|message", written
        by the middle server (sync-status.txt on the drop-folder root) and by
        the SCCM watcher (watcher-status.txt in each environment folder, carried
        back by the middle server). Returns $null when there is none.  #>
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $parts = ([IO.File]::ReadAllText($Path).Trim() -split '\|', 4)
        if ($parts.Count -lt 3) { return $null }
        return [pscustomobject]@{
            When    = [datetime]::Parse($parts[0], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            Host    = $parts[1]
            Ok      = ($parts[2] -eq 'OK')
            Message = $(if ($parts.Count -ge 4) { $parts[3] } else { '' })
        }
    } catch { return $null }
}

function Update-ConnectionHealth {
    <#  The CONNECTION rows on the Jobs page: is the middle server passing, is
        the SCCM watcher passing, and when did each last say so. A packager PC
        has no other way to see those machines; a status older than the
        stale limit is shown amber, a FAILED one red. Never throws.  #>
    $stale = [TimeSpan]::FromMinutes(10)
    $show = { param($dot, $text, $status, $noun)
        if (-not $status) {
            $dot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, 'InkMuted')
            $text.Text = "Not seen yet - no status file from the $noun in the drop folder."
            return
        }
        $age = (Get-Date) - $status.When
        $ageText = $(if ($age.TotalMinutes -lt 1) { 'just now' } elseif ($age.TotalHours -lt 1) { "$([int]$age.TotalMinutes) min ago" } elseif ($age.TotalDays -lt 1) { $status.When.ToString('HH:mm') } else { $status.When.ToString('dd.MM.yyyy HH:mm') })
        $brush = $(if (-not $status.Ok) { 'Danger' } elseif ($age -gt $stale) { 'Amber' } else { 'Teal' })
        $dot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $brush)
        $text.Text = $(if (-not $status.Ok) { "PROBLEM on $($status.Host) ($ageText): $($status.Message)" }
                       elseif ($age -gt $stale) { "No pass since $ageText on $($status.Host) - the $noun may be down. $($status.Message)" }
                       else { "OK - last pass $ageText on $($status.Host). $($status.Message)" })
    }
    try {
        $drop = Get-ActiveDropFolder
        if ([string]::IsNullOrWhiteSpace($drop) -or -not (Test-Path -LiteralPath $drop)) {
            & $show $ui.dotSync $ui.txtSyncHealth $null 'middle server'
            & $show $ui.dotWatcher $ui.txtWatcherHealth $null 'SCCM server'
            return
        }
        & $show $ui.dotSync $ui.txtSyncHealth (Read-AudiStatusLine (Join-Path $drop 'sync-status.txt')) 'middle server'
        $code = Get-SelectedEnvironment
        $watcher = $(if ($code) { Read-AudiStatusLine (Join-Path (Join-Path $drop $code) 'watcher-status.txt') } else { $null })
        & $show $ui.dotWatcher $ui.txtWatcherHealth $watcher 'SCCM server'
        if (-not $code) { $ui.txtWatcherHealth.Text = 'Choose the environment to see its watcher.' }
    } catch { }
}

function Show-PreviousRuns {
    <#  What is happening, or already happened, to this package - read out of the
        drop folder.

        The window holds no connection to the SCCM server. It does not need one:
        the collector writes a heartbeat beside the job after every step, and the
        result when it finishes, whether anyone is watching or not. So this reads
        the folder instead, and the effect is the same as a live connection -

          * a job being worked on RIGHT NOW shows its steps as they complete;
          * closing the window changes nothing, because the server is not
            reporting to the window, it is reporting to the folder;
          * reopening it and typing the package name picks the same job back up
            wherever it has got to, and shows the finished runs before it.

        Called on a timer, so it must stay cheap and must never throw.  #>
    Update-ConnectionHealth
    $package = $ui.txtPackage.Text.Trim()
    $code    = (Get-SelectedEnvironment)
    if (-not $package -or -not $code) { return }

    try {
        $drop = Get-ActiveDropFolder
        if ([string]::IsNullOrWhiteSpace($drop) -or -not (Test-Path -LiteralPath $drop)) { return }
        $runs = @(Get-AudiSwJobHistory -DropFolder $drop -EnvironmentCode $code -PackageName $package)
    }
    catch { return }   # this is a convenience; it must never break the window

    # A job that has not reported a step yet is not among the runs - but it is
    # the thing the packager is waiting on, so say where it is:
    #   \New      = QUEUED, the mail man has not picked it up yet
    #   \Working  = HANDED OVER, on its way to (or waiting at) the SCCM server;
    #               the first heartbeat turns it into a run below
    $queued = @()
    try { $queued = @(Get-AudiSwPendingJob -DropFolder $drop -EnvironmentCode $code -PackageName $package) } catch { }
    $pendingLine = ''
    if ($queued.Count -gt 0) {
        $p = $queued[-1]   # the newest one is the one being waited on
        $pendingLine = '{0}   -   {1}, submitted {2}' -f `
            $(if ($p.State -eq 'Queued') { 'QUEUED - waiting to be picked up from the drop folder' } else { 'HANDED OVER - carried to the SCCM server, no step reported yet' }),
            $(if ($p.Action) { $p.Action } else { 'job' }), $p.Submitted.ToString('dd.MM.yyyy HH:mm')
    }

    if ($runs.Count -eq 0) {
        if (-not $state.Running) {
            $ui.txtHistory.Text = $(if ($pendingLine) { $pendingLine } else { 'No earlier run of this package in this environment.' })
            $ui.txtHistory.ToolTip = $null
            Set-RecoveryButtons -Run $null
        }
        return
    }

    $last    = $runs[0]
    $running = ($last.Outcome -eq 'Running')
    if (-not $running -and -not $state.Running -and $pendingLine) {
        # finished runs exist, but a newer job is waiting: that is the headline
        $ui.txtHistory.Text = '{0}.   Last finished: {1} {2}' -f $pendingLine,
            $last.Completed.ToString('dd.MM.yyyy HH:mm'), $last.Outcome.ToLowerInvariant()
        Set-RecoveryButtons -Run $null
        return
    }

    # While this window is driving its own run, the run owns the grid - except
    # when the job has reached the server, where the heartbeat knows more than
    # the window does.
    if ($state.Running -and -not $running) { return }

    $rows = @($last.Steps | ForEach-Object {
        [pscustomobject]@{
            Step    = $_.Step
            Result  = $(if ($_.Ok) { 'OK' } else { 'FAILED' })
            Message = $_.Message
        } })
    # what a failed run undid, so a reopened window says it too - not only the
    # one that happened to be watching at the time
    if ((Test-HasValue $last 'RolledBack')) {
        foreach ($undone in @($last.RolledBack)) {
            $rows += [pscustomobject]@{ Step = 'Rolled back'; Result = '--'; Message = $undone }
        }
    }
    $ui.lstResults.ItemsSource = $rows

    # A run in flight knows how many steps there are; a finished one is its own total.
    $done = @($last.Steps | Where-Object { $_.Ok }).Count
    $ui.prgRun.Maximum = [Math]::Max(1, $(if ($running -and $last.StepCount -gt 0) { $last.StepCount } else { @($last.Steps).Count }))
    $ui.prgRun.Value   = $done
    if ($running) { $ui.prgRun.IsIndeterminate = $false }

    # No job id on the page: it is a record key, not something a packager
    # reads. It stays on the hover text and in the packagers' Record\ file.
    $ui.txtHistory.Text = if ($running) {
        'IN PROGRESS on the server   -   {0}   (started {1})' -f `
            $last.Message, $last.Completed.ToString('HH:mm')
    } else {
        '{0}   {1}{2}   -   {3}{4}' -f `
            $last.Completed.ToString('dd.MM.yyyy HH:mm'),
            $(if ($last.DryRun) { 'dry run, ' } else { '' }),
            $last.Outcome.ToLowerInvariant(),
            $last.Message,
            $(if ($runs.Count -gt 1) { '    +{0} earlier' -f ($runs.Count - 1) } else { '' })
    }

    $ui.txtHistory.ToolTip = ($runs | ForEach-Object {
        '{0}  {1,-9}  {2}  job {3}' -f $_.Completed.ToString('dd.MM.yyyy HH:mm'), $_.Outcome, $_.Message, $_.JobId
    }) -join "`r`n"

    # What a failed run can be followed by. Audi's rule: nothing on the site
    # without a person confirming - so these are buttons, never automatic.
    #   Run again - the archived job file beside the result is submitted afresh
    #   Clean up  - only when the server said an Integrate left its application
    #               behind: the Remove page, package name typed back
    Set-RecoveryButtons -Run $(if (-not $running -and -not $state.Running -and $last.Outcome -eq 'Failed') { $last } else { $null })

    # Pages are selected BY NAME, never by position. Inserting a tab in the
    # middle once shifted every index by one and quietly sent runs to the wrong
    # tab.
    if ($running -and -not $ui.tabJobs.IsSelected) { Show-Page 'tabJobs' }
}

function Set-RecoveryButtons { param($Run)
    $script:FailedRun = $null
    $ui.btnRunAgain.IsEnabled = $false
    $ui.btnCleanUp.IsEnabled  = $false
    if (-not $Run) { return }
    $archived = $Run.Path -replace '\.result\.xml$', '.xml'
    if (Test-Path -LiteralPath $archived) {
        $script:FailedRun = @{ JobFile = $archived; Result = $Run }
        $ui.btnRunAgain.IsEnabled = $true
    }
    $ui.btnCleanUp.IsEnabled = ($Run.Message -like '*choose Clean up*')
}

function Start-RunAgain {
    <#  The failed job, exactly as it was, submitted as a new job after the
        packager confirms. The server skips what is already done (a collection
        already there, a machine already in, a step already gone) and completes
        the rest. Nothing is guessed from the form - the archived job file is
        the source, so what runs is what ran.  #>
    $info = $script:FailedRun
    if (-not $info) { return }
    $read = Read-AudiSwJobFile -Path $info.JobFile
    if (-not $read.Ok) { Set-Status ("The failed job's file cannot be read back: " + ($read.Errors -join '; ')) '#FFB3261E'; return }
    $j = $read.Job
    $drop = Get-ActiveDropFolder
    if (-not $drop -or -not (Connect-AudiShare -Path $drop -Purpose 'the drop folder')) { return }
    if (Test-PackageJobPending -DropFolder $drop -Code $j.Environment -PackageName $j.PackageName) { return }

    $preview = Get-RunAgainPreview -Job $j -Result $info.Result
    $rows = @(
        [pscustomobject]@{ Label = 'Job';         Value = "$($j.Action) - $($j.PackageName) in $($j.Environment)"; Mono = $true }
        [pscustomobject]@{ Label = 'RFC';         Value = $(if ($j.Rfc) { $j.Rfc } else { 'none' }); Mono = $true }
        [pscustomobject]@{ Label = 'Already done'; Value = $preview.Done; Mono = $false }
        [pscustomobject]@{ Label = 'Still to do'; Value = $preview.Todo; Mono = $false }
        [pscustomobject]@{ Label = 'Attempt';     Value = "$($j.Retried + 2) - goes in as a new job$(if ($j.DryRun) { ', dry run (the server only rehearses)' })"; Mono = $false }
    )
    $ok = Show-Confirm -Title 'Run again' -Headline "Run the failed job again" `
        -Lead 'The server checks every item on the site first: what is already done is left alone, the rest is completed. Every step shows on this page as it happens.' `
        -Rows $rows -NotTouched @('what the earlier attempt already did') -Question 'Run it again now?'
    if (-not $ok) { Set-Status 'Cancelled.'; return }

    try {
        $doc = New-AudiSwJobFile -PackageName $j.PackageName -EnvironmentCode $j.Environment -Action $j.Action -Rfc $j.Rfc `
                   -NameEn $j.NameEn -NameDe $j.NameDe -DescriptionEn $j.DescriptionEn -DescriptionDe $j.DescriptionDe `
                   -Detail $j.Detail -OperatingSystems @($j.OperatingSystems) `
                   -AddCollections @($j.AddCollections) -RemoveCollections @($j.RemoveCollections) `
                   -SettingChanges @($j.SettingChanges) -MemberChanges @($j.MemberChanges) `
                   -Targets @($j.Targets) -RemoveContent:$j.RemoveContent -FindPattern $j.FindPattern `
                   -DryRun:$j.DryRun -Retried ($j.Retried + 1)
        $sub = Submit-AudiSwJob -DropFolder $drop -Job $doc
        Set-Status 'Submitted again. This page follows it.'
        Set-RecoveryButtons -Run $null
        Show-PreviousRuns
    }
    catch { Set-Status ("Could not submit it again: " + $_.Exception.Message) '#FFB3261E' }
}

function Get-RunAgainPreview { param($Job, $Result)
    <#  Two lists for the Run again prompt: what the earlier attempt finished
        (from its result - the server will find these done and skip them) and
        what is still to do (the job's own items, or the steps not reached).
        Built from the same files the server reads, so it is a preview of the
        server's decision, not a guess.  #>
    $doneSteps = @($(if ($Result -and (Test-HasValue $Result 'Steps')) { $Result.Steps } else { @() }) | Where-Object { $_.Ok })
    $doneLines = @($doneSteps | ForEach-Object { "    {0}:  {1}" -f $_.Step, $_.Message })
    $doneText  = @($doneSteps | ForEach-Object { [string]$_.Message }) -join "`n"

    $todo = @()
    switch ($Job.Action) {
        'Change' {
            foreach ($n in @($Job.AddCollections))    { if ($doneText -notlike "*$n created*")  { $todo += "    add collection $n" } }
            foreach ($n in @($Job.RemoveCollections)) { if ($doneText -notlike "*$n and its deployment removed*" -and $doneText -notlike "*$n was already gone*") { $todo += "    remove collection $n" } }
            foreach ($m in @($Job.MemberChanges)) {
                $verb = $(if ($m.Action -eq 'Add') { 'added to' } else { 'removed from' })
                if ($doneText -notlike "*$($m.Machine) $verb $($m.Collection)*" -and $doneText -notlike "*$($m.Machine) was already*") { $todo += "    $($m.Action.ToLower()) machine $($m.Machine)  ($($m.Collection))" }
            }
            foreach ($s in @($Job.SettingChanges)) { if ($doneText -notlike "*$($s.Key)*") { $todo += "    setting $($s.Key) = $($s.To)" } }
        }
        default {
            $all = switch ($Job.Action) {
                'Integrate' { @('Content copy', 'Application', 'Category', 'Content', 'Collections', 'Deployments', 'SecurityScope', 'MoveObjects', 'ArsGroup') }
                'Modify'    { @('Content copy', 'Application', 'DeploymentType', 'Category', 'Content', 'Collections', 'Deployments', 'Retire', 'SecurityScope', 'MoveObjects') }
                'Remove'    { @('Deployments', 'Collections', 'Application', 'ArsGroup') }
                'RefreshContent' { @('Content copy', 'Redistribute') }
                default     { @() }
            }
            $doneKeys = @($doneSteps | ForEach-Object { [string]$_.Step })
            $todo = @($all | Where-Object { $doneKeys -notcontains $_ } | ForEach-Object { "    $_" })
        }
    }
    return @{
        Done = $(if ($doneLines.Count) { (@($doneLines | ForEach-Object { $_.Trim() }) -join "`r`n") } else { 'nothing - the earlier attempt finished no step' })
        Todo = $(if ($todo.Count) { (@($todo | ForEach-Object { $_.Trim() }) -join "`r`n") } else { 'the server re-checks every item; anything not done above' })
    }
}

function Start-CleanUp {
    <#  An Integrate the server died on left its application behind. The
        clean-up is the Remove action - exactly this package's own objects -
        behind the Remove page's typed confirmation, never a silent delete.  #>
    $info = $script:FailedRun
    if (-not $info) { return }
    $ui.txtPackage.Text = $info.Result.Package
    Show-Page 'tabRemove'
    $ui.tglRemoveContent.IsChecked = $true    # the files question is part of a clean-up
    Update-RemoveGate
    Set-Status ("Clean-up: type the package name back on this page to remove what the failed job left on {0}; then Integrate it again." -f $info.Result.Environment) '#FF8A5300'
}

function Get-KnownCollections { param([string]$Package)
    <#  The collection names this window knows for the package: what the last
        Read from SCCM returned. The environment file - the list an environment
        creates - is on the server only, so without a Read the prompt says so
        instead of guessing.  #>
    $rows = @($(if ($script:SiteState) { $script:SiteState } else { @() }) | Where-Object { $_.Name -like "*$Package*" })
    return @($rows | ForEach-Object { "{0}  ({1})" -f $_.Name, $(if ($_.Exists) { 'on the site' } else { 'not there yet' }) })
}

function Get-PlanEffect { param($Plan, [string]$Mode, [switch]$RemoveContent)
    <#  What a job does, as rows for Show-Confirm - from what the packager side
        KNOWS: the SCCM name, the deployment-type suffix and category from
        Defaults.xml, the branding key on screen, the environment chosen, and
        the collection names of the last Read from SCCM if there was one. The
        environment file (collections, store, scopes) is on the server only;
        those come back by name in the result. Nothing here is a pattern.  #>
    $defaults = Get-AudiDefaults
    $name   = "$($Plan.PackageName)"
    $env    = "$($Plan.Environment)"
    $label  = "$($script:EnvironmentLabel[$env])"
    $dtName = "$name$($defaults.Naming.deploymentTypeSuffix)"
    $brand  = $ui.txtBranding.Text.Trim()
    $cols   = @(Get-KnownCollections -Package $name)
    $colText = $(if ($cols.Count -gt 0) { ($cols -join "`r`n") } else { "every one the $env environment file asks for - named one by one in the result" })
    $row = { param($l, $v, $m) [pscustomobject]@{ Label = $l; Value = $v; Mono = [bool]$m } }
    switch ($Mode) {
        'Remove' {
            @{
                Title = 'Remove'; Danger = $true
                Headline = "Remove $name from $env"
                Lead = "Whole names, one object each - nothing is matched by pattern. $label."
                Rows = @(
                    (& $row 'Application' $name $true)
                    (& $row 'Deployment type' $dtName $true)
                    (& $row 'Collections' $colText $($cols.Count -gt 0))
                    (& $row 'Deployments' 'every deployment of this application, so no machine can still receive it')
                    $(if ($RemoveContent) { & $row 'Files in the store' "the folder '$name' is deleted after SCCM has let go of the application - asked once more" })
                ) | Where-Object { $_ }
                NotTouched = @(
                    $(if (-not $RemoveContent) { "the files in $env's content store" })
                    'hand-made collections, any other application, anything already installed on a machine'
                    'the AD group, unless this tool created it'
                ) | Where-Object { $_ }
                Question = "Remove it from $env" + '?'
            }
        }
        'RefreshContent' {
            @{
                Title = 'Update content'; Danger = $false
                Headline = "Update the files of $name in $env"
                Lead = "The package folder is compared with the store file by file - by content, never by timestamp. $label."
                Rows = @(
                    (& $row 'Store folder' "'$name' in $env's content store" $true)
                    (& $row 'Files' 'only files that differ are replaced; new ones added; files no longer in the package removed')
                    (& $row 'Distribution' "$dtName - the distribution points fetch what changed" $true)
                )
                NotTouched = @('name, descriptions, detection rule, collections, deployments, machines', 'file timestamps')
                Question = 'Update the content now?'
            }
        }
        'Modify' {
            @{
                Title = 'Update'; Danger = $false
                Headline = "Update $name in $env"
                Lead = "The application is brought in line with what is on screen and the environment file. It is never rebuilt. $label."
                Rows = @(
                    (& $row 'Detection rule' $brand $true)
                    (& $row 'Content path' "'$name' in $env's content store" $true)
                    (& $row 'Collections' $colText $($cols.Count -gt 0))
                    (& $row 'Retired' 'a collection of this package the environment file no longer asks for - named in the result')
                )
                NotTouched = @('live deployments and the machines in them')
                Question = 'Update it now?'
            }
        }
        default {
            @{
                Title = 'Integrate'; Danger = $false
                Headline = "Integrate $name into $env"
                Lead = "The server creates the application and everything around it, and reports every step. $label."
                Rows = @(
                    (& $row 'Application' $name $true)
                    (& $row 'Deployment type' "$dtName  -  content from the folder '$name' in the store" $true)
                    (& $row 'Detection' "branding key $brand" $true)
                    (& $row 'Category' "$($defaults.Application.category)")
                    (& $row 'Collections' $colText $($cols.Count -gt 0))
                    (& $row 'Distribution' "$env's distribution point group; security scopes as the environment file says")
                    (& $row 'AD group' $(if ($defaults.Steps.CreateArsGroup) { 'created' } else { 'not created (switched off)' }))
                )
                NotTouched = @('any other application or collection')
                Question = "Integrate into $env" + '?'
            }
        }
    }
}

function Format-PlanEffect { param($Plan, [string]$Mode, [switch]$RemoveContent)
    <#  The same, as plain text - for the self-test and the log.  #>
    $e = Get-PlanEffect -Plan $Plan -Mode $Mode -RemoveContent:$RemoveContent
    $lines = @($e.Headline) + @($e.Rows | ForEach-Object { "  {0}: {1}" -f $_.Label, $_.Value }) + @($e.NotTouched | ForEach-Object { "  not touched: $_" })
    return ($lines -join "`r`n")
}

function Test-EnvironmentChosen {
    <#  Returns the reason nothing can be submitted yet, or '' when an
        environment is chosen. Every submit path asks this first, so a job can
        never go to an environment nobody picked.  #>
    if (Get-SelectedEnvironment) { return '' }
    return 'Choose the environment in the header first - ICZ for a test, INA for production. The package name does not decide it.'
}

function Update-EnvironmentNotice {
    # Nothing to warn about any more: the prefix is not a rule. The
    # "unverified environment" warning used to be raised here by reading the
    # environment file; the server still refuses a real run against an
    # unverified environment - that check has not been weakened, it has moved
    # to the side that owns the files.
    Show-Warning $(if (Get-SelectedEnvironment) { '' } else { 'No environment is chosen yet. Pick ICZ or INA in the header before submitting anything.' })
}

# ----------------------------------------------------------------- derive names
function Update-DerivedFields {
    # A name typed with the hyphen is shown the way SCCM will carry it.
    $typed = $ui.txtPackage.Text.Trim()
    if ($typed) {
        $canonical = $(try { Get-AudiSccmName -PackageName $typed } catch { $typed })
        if ($canonical -ne $typed) { $ui.txtPackage.Text = $canonical }
    }
    $package = $ui.txtPackage.Text.Trim()
    foreach ($f in 'txtPublisher','txtProduct','txtVersion','txtArchitecture','txtRevision','txtLanguage','txtBranding') { $ui[$f].Text = '' }
    if (-not $package) { Show-DetectionRules; return }
    try {
        $parts = Split-AudiPackageName -PackageName $package
        $ui.txtPublisher.Text    = $parts.Publisher
        $ui.txtProduct.Text      = $parts.Product
        $ui.txtVersion.Text      = $parts.Version
        $ui.txtArchitecture.Text = $parts.Architecture
        $ui.txtRevision.Text     = $parts.Revision
        $ui.txtLanguage.Text     = $parts.Language
        $ui.txtBranding.Text     = Get-AudiBrandingKey -PackageName $package
        Set-Status 'Package name understood.'
    }
    catch { Set-Status $_.Exception.Message '#FF8A5300' }
    Show-DetectionRules
}

function Show-DetectionRules {
    <#  The ONE rule SCCM will be given, shown as it will be sent.

        There is no "detection key" field to keep in step with the branding key,
        because the branding key IS the rule. Showing the result instead of
        asking for it again means the two can never disagree, and a mistyped
        branding key is visible here rather than on a client three days later. #>
    $branding = $ui.txtBranding.Text.Trim()
    $ui.txtRule1.Text = if ($branding) {
        "HKLM\{0}{1}   {2} = {3}" -f $defaults.Naming.brandingRegistryRoot, $branding,
                                     $defaults.Detection.valueName, $ui.txtRevision.Text.Trim()
    } else { 'waiting for a package name' }
}

# ------------------------------------------------------------- read the package
function Read-PackageFolder { param([string]$Path)
    if (-not $Path) { return }
    Show-Page 'tabIntegrate'
    if (-not (Connect-AudiShare -Path $Path -Purpose 'the package folder')) { return }
    if ($ui.txtDocumentRoot.Text.Trim() -and -not (Connect-AudiShare -Path $ui.txtDocumentRoot.Text.Trim() -Purpose 'the documents location')) { return }
    Set-Status "Reading $Path ..."
    try {
        $docRoot = $ui.txtDocumentRoot.Text.Trim()
        Save-DocumentRoot
        $detail = $(if ($docRoot) { Read-AudiPackageDetail -PackagePath $Path -DocumentRoot $docRoot }
                    else          { Read-AudiPackageDetail -PackagePath $Path })

        if ($ui.txtPackagePath.Text -ne $Path) { $ui.txtPackagePath.Text = $Path }
        # A new folder is a new package: the name and everything read from the
        # previous one go, so nothing from package A is submitted with package B.
        #
        # The header shows the SCCM spelling - underscore before the revision -
        # whichever way the folder was named. The branding key (02) keeps the
        # hyphen; the content folder on the share must carry the underscore.
        $folderName = Split-Path -Leaf $Path
        $ui.txtPackage.Text = $(try { Get-AudiSccmName -PackageName $folderName } catch { $folderName })
        $spellingNote = @()
        if ($ui.txtPackage.Text -ne $folderName) {
            $spellingNote = @("The folder is '$folderName'; in SCCM and on the content share the package is '$($ui.txtPackage.Text)' (underscore before the revision). Only the branding key keeps the hyphen.")
        }
        foreach ($f in 'txtNameEN','txtNameDE','txtDescEN','txtDescDE','txtRfc') { $ui[$f].Text = '' }
        Update-DerivedFields
        Sync-EnvironmentToPackage

        # The deployment script is the authority for everything except the
        # description, which comes from the request document.
        # Read-AudiPackageDetail has already applied the short-then-detailed
        # preference. The install title is what Software Center shows, and it
        # is read from the script - never composed from the package name.
        $map = @{ InstallTitle             = 'txtNameEN'
                  ApplicationDescriptionEN = 'txtDescEN'
                  ApplicationDescriptionDE = 'txtDescDE'
                  OrderNumber              = 'txtRfc' }
        foreach ($key in $map.Keys) {
            if ($detail.Fields.Contains($key)) { $ui[$map[$key]].Text = $detail.Fields[$key] }
        }
        # The German title starts equal to the English one; the packager
        # changes it if the German Software Center should read differently.
        if (-not $ui.txtNameDE.Text) { $ui.txtNameDE.Text = $ui.txtNameEN.Text }

        # Where every value came from, on the status line and in full on its
        # tooltip. The card itself stays uncluttered.
        $script   = if ($detail.ScriptPath)   { "$($detail.Generation) $(Split-Path -Leaf $detail.ScriptPath)" } else { 'no script found' }
        $document = if ($detail.DocumentPath) { Split-Path -Leaf $detail.DocumentPath } else { 'no document found' }
        if ($detail.DocumentFolder) { $document += "   (from the documents location: $(Split-Path -Leaf $detail.DocumentFolder))" }
        $ui.txtDocumentRootNote.Text = $(if ($detail.DocumentFolder) { "form found under $(Split-Path -Leaf $detail.DocumentFolder)" }
                                         elseif ($detail.DocumentPath) { 'form found in the package' }
                                         elseif ($docRoot) { 'no form found in either place' }
                                         else { 'used when the package has no form' })
        # no form anywhere: the one time the documents location matters, so
        # the disclosure that hides it opens by itself
        if (-not $detail.DocumentPath) { $ui.tglMorePlaces.IsChecked = $true }

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("Script:   $script   <- everything except the description")
        $lines.Add("Document: $document   <- the description only")
        $lines.Add('')
        if ($detail.Fields.Count -gt 0) {
            foreach ($key in $detail.Fields.Keys) {
                $lines.Add(("{0,-26} {1}   [{2}]" -f $key, $detail.Fields[$key], $detail.Origin[$key]))
            }
        } else { $lines.Add('Nothing could be read - fill the fields in by hand.') }
        foreach ($n in @($detail.Notes)) { $lines.Add(''); $lines.Add($n) }
        $ui.txtStatus.ToolTip = ($lines -join "`r`n")

        # Anything the reader could not find is said out loud on the status line,
        # not left in a tooltip nobody hovers. A blank form with a cheerful
        # "read 0 values" is exactly the sort of thing that gets noticed only
        # after the package is in SCCM.
        # The Windows versions the instruction document ticked. Kept until the
        # next package is read, so Integrate/Modify require exactly what was
        # asked for rather than every platform the tool knows about.
        $script:DocOperatingSystems = @($detail.OperatingSystems)
        Set-OperatingSystemTicks -Keys $script:DocOperatingSystems

        # What the request form says beyond the fields on screen: the package
        # this one replaces, the sites it asked for, the category. Read for
        # the packager's benefit; nothing here changes what the server does.
        $formInfo = @()
        if ($detail.Fields.Contains('PredecessorPackage')) {
            $formInfo += ("Predecessor: {0}{1}." -f $detail.Fields['PredecessorPackage'],
                          $(if ($detail.Fields.Contains('PredecessorDiscontinued')) { ' - the form says it is discontinued with this release; use Remove on it once this one is live' } else { '' }))
        }
        $sites = @($detail.Fields.Keys | Where-Object { $_ -like 'Site:*' } | ForEach-Object { $_.Substring(5) })
        if ($sites.Count -gt 0) { $formInfo += ("Sites ticked on the form: {0}." -f ($sites -join ', ')) }
        if ($detail.Fields.Contains('SoftwareCategory')) { $formInfo += ("Category on the form: {0}." -f $detail.Fields['SoftwareCategory']) }
        # The status line stays SHORT: one sentence. Everything informative -
        # which files were read, the spelling note, what the form says beyond
        # the fields on screen - is on the hover tooltip with the field origins.
        $infoLines = @($spellingNote) + @($detail.Info) + $formInfo
        if ($infoLines.Count -gt 0) {
            $lines.Add(''); foreach ($i in $infoLines) { $lines.Add($i) }
            $ui.txtStatus.ToolTip = ($lines -join "`r`n")
        }

        $problems = @($detail.Notes)
        if (-not $detail.Fields.Contains('InstallTitle')) {
            $problems += 'No InstallTitle in the deployment script - type the install title by hand.'
        }
        if ($problems.Count -gt 0) {
            Set-Status ($problems -join '  ') '#FF8A5300'
        }
        elseif ($detail.Fields.Count -eq 0) {
            Set-Status 'Nothing could be read from this folder - fill the fields in by hand.' '#FF8A5300'
        }
        else {
            $fromDoc = @($detail.Origin.Values | Where-Object { $_ -like 'document*' }).Count
            Set-Status ("Package read: {0} values from the deployment script, {1} from the request form. Check the fields, then Integrate." -f ($detail.Fields.Count - $fromDoc), $fromDoc)
        }
    }
    catch { Set-Status "Could not read the package: $($_.Exception.Message)" '#FFB3261E' }
}

# ------------------------------------------------------------------- build plan
function New-PlanFromForm {
    $package = $ui.txtPackage.Text.Trim()
    if (-not $package) { throw 'Enter a package name first.' }
    # The environment is the packager's choice, never inferred from the name.
    $code = (Get-SelectedEnvironment)
    if (-not $code) { throw (Test-EnvironmentChosen) }

    # NOT a full plan. Building one needs the environment's collections, scopes,
    # folders and distribution point group - SCCM topology, which does not
    # belong on a packager machine and is not installed there.
    #
    # The server builds the real plan from the job file. All that is needed here
    # is that the package name is well formed and an environment is chosen; the
    # rest of the form travels as Detail and is used exactly as typed.
    $null = Split-AudiPackageName -PackageName $package      # throws if malformed
    return [pscustomobject]@{
        PackageName = $package
        Environment = $code
        Rfc         = $ui.txtRfc.Text.Trim()
    }
}


# ------------------------------------------------------------- reading results
# Wait-AudiSwJobResult hands back a hashtable and the engine hands back a
# PSCustomObject. Under StrictMode a missing member throws, so ask first.
function Test-HasValue { param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [hashtable]) { return $Object.Contains($Name) }
    return [bool]$Object.PSObject.Properties[$Name]
}

function Show-RunOutcome { param($Result, [string]$Note = '')
    $rows = @()
    # The copy to the content share, when this run did one, is the first step
    # shown - it happened on this PC, before the job reached the server.
    if ($state.CopyStep) {
        $rows += [pscustomobject]@{ Step = $state.CopyStep.Step; Result = 'OK'; Message = $state.CopyStep.Message }
        $state.CopyStep = $null
    }
    $rows += @($Result.Steps | ForEach-Object {
        [pscustomobject]@{ Step = $_.Step; Result = $(if ($_.Ok) { 'OK' } else { 'FAILED' }); Message = $_.Message }
    })
    if ((Test-HasValue $Result 'RolledBack') -and $Result.RolledBack.Count -gt 0) {
        foreach ($undone in $Result.RolledBack) {
            $rows += [pscustomobject]@{ Step = 'Rolled back'; Result = '--'; Message = $undone }
        }
    }
    $ui.lstResults.ItemsSource = $rows

    $ui.prgRun.IsIndeterminate = $false
    if ($rows.Count -gt 0) { $ui.prgRun.Maximum = $rows.Count }
    $ui.prgRun.Value = @($rows | Where-Object { $_.Result -eq 'OK' }).Count
    Update-ContentState

    if ((Test-HasValue $Result 'LogPath') -and $Result.LogPath) {
        $ui['LogFolder'] = Split-Path -Parent $Result.LogPath
        $ui.btnOpenLog.IsEnabled = $true
    }

    $prefix = if ((Test-HasValue $Result 'DryRun') -and $Result.DryRun) { '[Dry run] ' } else { '' }
    Set-Status "$prefix$($Result.Message)$Note" $(if ($Result.Ok) { '#FF00707D' } else { '#FFB3261E' })
}

# --------------------------------------------------------------- run in the bg
# One background worker for both buttons. The window only ever polls $state, so
# it stays responsive however long the server takes.
function Start-Worker { param([scriptblock]$Body, [hashtable]$Arguments, [int]$Steps, [switch]$StayOnTab)

    # Show the Jobs page AS THE RUN STARTS, not when it finishes. A packager who
    # presses Integrate wants to watch it happen, and anyone looking over their
    # shoulder should see the same thing without being told which page to open.
    #
    # -StayOnTab is for Inspect, which is not a run: its answer belongs on the
    # page that asked, and switching away and back would just make the window
    # flicker.
    if (-not $StayOnTab) { Show-Page 'tabJobs' }
    $ui.txtHistory.Text = 'Running now - the steps below are this run.'
    $ui.txtHistory.ToolTip = $null

    $ui.lstResults.ItemsSource = $null
    $ui.prgRun.Value = 0
    $ui.prgRun.Maximum = $Steps
    $ui.prgRun.IsIndeterminate = $false
    $state.Running = $true; $state.Done = $false; $state.Result = $null; $state.Error = $null
    $state.Step = ''; $state.Waiting = $false
    Set-Busy $true

    # The runspace, the worker and the timer go into $state, NOT into locals.
    #
    # Start-Worker has returned long before the first tick fires, so anything
    # left in a local variable is gone by then and the handler dies with
    # "The variable '$timer' cannot be retrieved because it has not been set."
    # $state is script-level, so the handler can still reach it.
    $state.Runspace = [runspacefactory]::CreateRunspace()
    $state.Runspace.ApartmentState = 'STA'
    $state.Runspace.ThreadOptions  = 'ReuseThread'
    $state.Runspace.Open()
    $state.Runspace.SessionStateProxy.SetVariable('state', $state)
    $state.Runspace.SessionStateProxy.SetVariable('toolRoot', (Join-Path $PSScriptRoot 'Lib'))
    # NOT called 'args': inside a script $args is the automatic argument list
    $state.Runspace.SessionStateProxy.SetVariable('jobArgs', $Arguments)

    $state.Worker = [powershell]::Create()
    $state.Worker.Runspace = $state.Runspace
    $null = $state.Worker.AddScript($Body)
    $state.Handle = $state.Worker.BeginInvoke()

    $state.Timer = New-Object System.Windows.Threading.DispatcherTimer
    $state.Timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $state.Timer.Add_Tick({
        if ($state.Step) { $ui.txtStep.Text = $state.Step }
        # nothing to count while the job sits in the folder - show movement only
        if ($state.Waiting -and -not $ui.prgRun.IsIndeterminate) { $ui.prgRun.IsIndeterminate = $true }
        if (-not $state.Done) { return }

        $state.Timer.Stop()
        try { $null = $state.Worker.EndInvoke($state.Handle) } catch { }
        $state.Worker.Dispose(); $state.Runspace.Close(); $state.Runspace.Dispose()
        $state.Worker = $null; $state.Runspace = $null; $state.Handle = $null

        Set-Busy $false
        $ui.txtStep.Text = ''
        $ui.prgRun.IsIndeterminate = $false

        if ($state.Error) {
            # nothing was confirmed, so whatever was pending stays pending, visibly
            $state.PendingMembers = $null; $state.PendingChange = $null
            Update-MembersSummary
            Set-Status "Failed: $($state.Error)" '#FFB3261E'; $ui.prgRun.Value = 0; return
        }

        # A Find answer fills the tick list on the Remove page - a picture of
        # the site, not a run. Handled before Inspect: it never carries State.
        if ($state.FindPending) {
            $state.FindPending = $false
            Show-FoundApplications $state.Result
            return
        }

        # An Inspect answer fills the Modify AND Members pages rather than the
        # Jobs grid - it is a picture of the site, not a run. The page that
        # asked is the one shown.
        if ((Test-HasValue $state.Result 'State') -and @($state.Result.State).Count -gt 0) {
            Show-PackageState $state.Result.State
            if (Test-HasValue $state.Result 'Settings') { Show-PackageSettings $state.Result.Settings }
            $ui.txtModifyState.Text  = $state.Result.Message
            $ui.txtMembersState.Text = $state.Result.Message
            Show-Page $(if ($state.InspectFrom -eq 'Members') { 'tabMembers' } else { 'tabModify' })
            Set-Status $state.Result.Message '#FF00707D'
            return
        }

        Show-RunOutcome $state.Result $state.Note

        # A Change job's answer is folded into the page that sent it, so the
        # list shows the site as it now is without another Read from SCCM.
        if ($state.PendingMembers) { Complete-MemberApply $state.Result }
        if ($state.PendingChange)  { Complete-ChangeApply $state.Result }
    })
    $state.Timer.Start()
}

# ------------------------------------------------------ preview: local, no server
# Runs the plan through the dry-run provider on this machine. Nothing is written
# to the drop folder and the server is never involved, so a packager can check a
# package before queuing anything.
# Start-Preview is gone. It ran the whole integration locally through the
# dry-run provider, which meant the window had to load the SCCM half of the
# engine - the one thing this split exists to prevent. It also proved nothing
# about the site, and Dry run already covers rehearsing. History replaced it.

# ------------------------------------------------- integrate / remove: flow 2
# The window writes a job file into the chosen environment's folder under the
# drop root and waits for the result file. It never connects to the SCCM
# server, holds no SCCM rights and states no identity: the job file carries no
# requester at all.
function Start-Run { param([string]$Mode)   # Integrate | Modify | Remove

    # An environment must have been CHOSEN. Refuse here, in front of the
    # packager, rather than letting the server reject it minutes later.
    $notChosen = Test-EnvironmentChosen
    if ($notChosen) {
        Show-Warning $notChosen
        Set-Status $notChosen '#FFB3261E'
        $ui.cboEnvironment.Focus() | Out-Null
        return
    }

    try   { $plan = New-PlanFromForm }      # validates the form before queuing
    catch { Set-Status $_.Exception.Message '#FF8A5300'; return }

    $code = (Get-SelectedEnvironment)
    $drop = Get-ActiveDropFolder
    if ([string]::IsNullOrWhiteSpace($drop)) {
        Set-Status ("No drop folder is set. Put the UNC path of the shared drop folder in {0}." -f `
                    $script:TeamSettingsFile) '#FFB3261E'
        return
    }

    # The RFC is recorded, not required - the application name already
    # identifies the package uniquely. The gate is kept behind the same config
    # switch the server uses, so if Audi ever decides every change must carry
    # one, both sides turn on together and the window is not left letting
    # through jobs the server will reject.
    $rfc = $ui.txtRfc.Text.Trim()
    if ((Get-AudiDefaults).Audit.RequireRfc -and -not $rfc) {
        Set-Status 'Enter the RFC number first - this environment is set to require one.' '#FF8A5300'
        $ui.txtRfc.Focus() | Out-Null
        return
    }
    $rfcShown = if ($rfc) { $rfc } else { 'not given' }

    # Integrate needs the package folder; Modify and Remove do not.
    #
    # Everything Modify and Remove act on - the application name, the deployment
    # type, the collections - comes from the package NAME and the environment
    # file, both of which are on every machine. So a second packager can modify
    # what a first one integrated, from their own PC, without the package folder
    # in front of them.
    #
    # What they cannot do from a blank form is supply the descriptive fields, so
    # those are left alone rather than blanked - see SetApplication. Say which
    # way it is going, so nobody has to guess.
    if ($Mode -notin @('Remove', 'RefreshContent') -and @(Get-OperatingSystemTicks).Count -eq 0) {
        Set-Status 'Tick at least one Windows version - an application no version may install would be pointless.' '#FF8A5300'
        Show-Page 'tabIntegrate'
        return
    }
    # Update content is about files only: the package folder must be there,
    # and it is ALWAYS copied - the whole point is to replace what is in the store
    if ($Mode -eq 'RefreshContent') {
        $folder = $ui.txtPackagePath.Text.Trim()
        if (-not $folder -or -not (Test-Path -LiteralPath $folder)) {
            Set-Status 'Browse to the package folder first - Update content takes the new files from it.' '#FF8A5300'
            Show-Page 'tabIntegrate'; $ui.txtPackagePath.Focus() | Out-Null; return
        }
    }

    $blankDetail = -not ($ui.txtNameEN.Text.Trim() -or $ui.txtDescEN.Text.Trim())
    if ($Mode -eq 'Integrate' -and $blankDetail) {
        Set-Status 'Read the package folder first - Integrate needs its script and instruction document.' '#FF8A5300'
        Show-Page 'tabIntegrate'
        $ui.txtPackagePath.Focus() | Out-Null
        return
    }
    $detailNote = $(if ($Mode -eq 'Modify' -and $blankDetail) {
        "`r`n`r`nNo package details are loaded, so the name and descriptions" +
        "`r`nalready in SCCM are left as they are. Collections and settings" +
        "`r`nare still reconciled."
    } else { '' })

    # The drop folder has to be reachable before anything is written to it.
    if (-not (Connect-AudiShare -Path $drop -Purpose 'the drop folder')) { return }
    if (Test-PackageJobPending -DropFolder $drop -Code $code -PackageName $plan.PackageName) { return }

    # THE PACKAGE CONTENT GOES WITH THE JOB, into <drop>\<ENV>\Sources\<SCCM
    # name>, and the SCCM server copies it into the store as the job's first
    # step. Integrate and Update check, and copy it there when it is not there
    # yet - the Content folder only, when the package is shaped Content\
    # Documents\ Icons\; the whole folder when it is already just the content.
    # Remove needs no content.
    $copyFrom = ''; $copyTo = ''; $copyNote = ''; $replace = $false
    if ($Mode -ne 'Remove') {
        $contentPlan = Get-ContentCopyPlan -Code $code -SccmName $plan.PackageName -PackagePath $ui.txtPackagePath.Text.Trim() -Replace:($Mode -eq 'RefreshContent')
        if ($contentPlan.Error) {
            Set-Status $contentPlan.Error '#FFB3261E'
            if ($contentPlan.NeedsFolder) { Show-Page 'tabIntegrate' }
            return
        }
        if ($contentPlan.Cancelled) { return }
        $copyFrom = $contentPlan.From; $copyTo = $contentPlan.To; $replace = ($Mode -eq 'RefreshContent')
        $copyNote = "`r`n`r`n" + $contentPlan.Note
    }
    # Remove: the content in the store is a separate, explicit choice
    $removeContent = ($Mode -eq 'Remove' -and [bool]$ui.chkRemoveContent.IsChecked)

    # Every job is real. -DryRun on the command line (testing only) makes the
    # server rehearse instead; there is no switch for it in the window.
    $dryRun = [bool]$DryRun
    # EXACTLY WHAT, BY NAME - Audi's rule (Ewald): anything that creates,
    # changes or removes on the site says which objects before it is confirmed,
    # so the packager confirms what they can read, not a verb. One window, one
    # shape, for every action: headline, what it does, what it does not, the
    # question.
    $effect = Get-PlanEffect -Plan $plan -Mode $Mode -RemoveContent:$removeContent
    $rows = @($effect.Rows)
    $rows += [pscustomobject]@{ Label = 'RFC'; Value = $rfcShown; Mono = $true }
    if ($copyTo) {
        $rows += [pscustomobject]@{ Label = 'Package files'; Value = "copied into the drop folder first ($((@(Get-ChildItem -LiteralPath $copyFrom -File -Recurse -ErrorAction SilentlyContinue)).Count) files); the SCCM server moves them into the store as the job's first step"; Mono = $false }
    }
    elseif ($Mode -ne 'Remove' -and $contentPlan.Note) {
        # already in the drop folder or already in the store - say which, so
        # "nothing is copied" is read as a fact, not a gap
        $rows += [pscustomobject]@{ Label = 'Package files'; Value = (@($contentPlan.Note -split "`r`n"))[0]; Mono = $false }
    }
    if ($detailNote) { $rows += [pscustomobject]@{ Label = 'Details'; Value = 'none loaded - the name and descriptions already in SCCM stay as they are'; Mono = $false } }
    $lead = $(if ($dryRun) { 'TEST MODE - the server rehearses this and changes nothing. ' } else { '' }) + $effect.Lead +
            ' Carried out by the service account; your name is not sent and not recorded.'
    $ok = Show-Confirm -Title $effect.Title -Headline $effect.Headline -Lead $lead -Rows $rows -NotTouched $effect.NotTouched `
                       -Question $effect.Question -Danger:$effect.Danger
    if (-not $ok) { Set-Status 'Cancelled.'; return }

    # Deleting files is the one thing no later job can undo - it gets its own
    # window, with the exact folder in it.
    if ($removeContent -and -not $dryRun) {
        $delete = Show-Confirm -Title 'Delete the files' -Danger `
            -Headline "Also delete the files of $($plan.PackageName) from the store?" `
            -Lead 'This cannot be undone. Integrating the package again will need the files copied once more.' `
            -Rows @([pscustomobject]@{ Label = 'Folder'; Value = "'$($plan.PackageName)' in $code's content store - this one folder, directly under the store"; Mono = $true },
                    [pscustomobject]@{ Label = 'When'; Value = 'only after SCCM has let go of the application'; Mono = $false }) `
            -NotTouched @('anything else in the store') `
            -Question 'Delete the files as well? Cancel keeps them and removes from SCCM only.'
        $removeContent = [bool]$delete
    }

    $state.Note = ''
    Set-Status "Submitting to $code ..."
    Start-Worker -Steps $(switch ($Mode) { 'Remove' { 4 } 'Modify' { 9 } 'RefreshContent' { 2 } default { 8 } }) -Arguments @{
        Action        = $Mode
        DropFolder    = $drop
        CopyFrom      = $copyFrom
        CopyTo        = $copyTo
        Replace       = $replace
        RemoveContent = $removeContent
        PackagePath   = $ui.txtPackagePath.Text.Trim()
        Timeout       = $defaults.Runtime.ResultTimeoutMinutes
        PackageName   = $plan.PackageName
        Environment   = $code
        Rfc           = $ui.txtRfc.Text.Trim()
        NameEn        = $ui.txtNameEN.Text.Trim()
        NameDe        = $ui.txtNameDE.Text.Trim()
        DescriptionEn = $ui.txtDescEN.Text.Trim()
        DescriptionDe = $ui.txtDescDE.Text.Trim()
        Detail        = Get-PackageDetail
        # The Windows versions ticked on screen - from the request form, as the
        # packager left them. What is ticked is what the deployment type requires.
        OperatingSystems = @(Get-OperatingSystemTicks)
        DryRun        = $dryRun
    } -Body {
        try {
            . (Join-Path $toolRoot 'Load.ps1')

            $wantsDryRun = [bool]$jobArgs.DryRun

            # Put the package content into the drop folder first, BEFORE the job
            # file - the mail man carries Sources before jobs, so a job can never
            # arrive on the server ahead of its content. The share was opened on
            # the window's thread; that session belongs to the whole process.
            if ($jobArgs.CopyTo) {
                $state.Step = 'Copying the package content into the drop folder...'
                # first package for this environment: the state folders, Sources included
                Initialize-AudiDropFolder -DropFolder $jobArgs.DropFolder -EnvironmentCode $jobArgs.Environment | Out-Null
                $copied = Copy-AudiPackageContent -PackagePath $jobArgs.PackagePath -Replace:([bool]$jobArgs.Replace) `
                            -ContentShare (Split-Path -Parent $jobArgs.CopyTo) -SccmName (Split-Path -Leaf $jobArgs.CopyTo) `
                            -OnProgress { param($d, $t, $f) $state.Step = "Copying into the drop folder... $d of $t files" }
                $copyNote = $(if ($copied.Copied) { "  |  $($copied.Files) files put into the drop folder" } else { '' })
                # shown as the first step on the Jobs page, before the server's own
                $state.CopyStep = [pscustomobject]@{ Step = 'Content copy'; Ok = $true
                    Message = $(if ($copied.Copied) { "{0} files, {1:N0} bytes copied to {2} - verified by file count and size" -f $copied.Files, $copied.Bytes, $copied.Target } else { "already there: {0}" -f $copied.Target }) }
            } else { $copyNote = '' }

            $state.Step = 'Writing the job file...'
            $doc = New-AudiSwJobFile -PackageName $jobArgs.PackageName -EnvironmentCode $jobArgs.Environment `
                                     -Action $jobArgs.Action -Rfc $jobArgs.Rfc `
                                     -NameEn $jobArgs.NameEn -NameDe $jobArgs.NameDe `
                                     -DescriptionEn $jobArgs.DescriptionEn -DescriptionDe $jobArgs.DescriptionDe `
                                     -Detail $jobArgs.Detail -OperatingSystems $jobArgs.OperatingSystems `
                                     -RemoveContent:([bool]$jobArgs.RemoveContent) `
                                     -DryRun:$wantsDryRun

            $submission = Submit-AudiSwJob -DropFolder $jobArgs.DropFolder -Job $doc
            $state.JobId = $submission.JobId

            $state.Waiting = $true
            $started = Get-Date
            # Name the folder it went into. A collector watching a different one
            # is the commonest reason a job is never picked up, and without this
            # the window just says "waiting" forever with no clue why.
            $state.Step = "Queued in $(Split-Path -Parent $submission.Path). Waiting for the server..."

            $state.Result = Wait-AudiSwJobResult -Submission $submission `
                                -TimeoutMinutes $jobArgs.Timeout -PollSeconds 5 -OnWait {
                    $mins = [int]((Get-Date) - $started).TotalMinutes
                    $state.Step = "Waiting for the server... ${mins} min of $($jobArgs.Timeout)"
                }
            $state.Note = $copyNote
        }
        catch { $state.Error = $_.Exception.Message }
        finally { $state.Waiting = $false; $state.Done = $true; $state.Running = $false }
    }
}

# --------------------------------------------------------------------- handlers
$ui.cboEnvironment.Add_SelectionChanged({ Sync-EnvironmentToPackage })
$ui.txtPackage.Add_LostFocus({ Update-DerivedFields; Sync-EnvironmentToPackage })

# The detection read-out follows whatever is on screen, so an edit to the
# branding key or the revision is reflected in the rule SCCM will get before
# anything is submitted.
foreach ($field in 'txtBranding','txtRevision') {
    $ui[$field].Add_TextChanged({ Show-DetectionRules })
}

# The rail and the page host keep each other in step. The handler reads the
# sender's name, so one scriptblock serves every entry.
foreach ($nav in @($script:PageOf.Keys)) {
    $ui[$nav].Add_Checked([System.Windows.RoutedEventHandler]{ param($s, $e) Show-Page $script:PageOf[$s.Name] })
}
$ui.tabMain.Add_SelectionChanged({ param($s, $e)
    if ($e.Source -ne $ui.tabMain) { return }   # a DataGrid inside a page raises this too
    $tab = $ui.tabMain.SelectedItem
    if ($tab -and $tab.Name) { Show-Page $tab.Name }
})

$ui.btnTheme.Add_Click({ Set-Theme $(if ($script:Theme -eq 'Dark') { 'Light' } else { 'Dark' }) })

$ui.btnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the package folder'
    if ($ui.txtPackagePath.Text -and (Test-Path -LiteralPath $ui.txtPackagePath.Text)) { $dialog.SelectedPath = $ui.txtPackagePath.Text }
    if ($dialog.ShowDialog() -eq 'OK') {
        $ui.txtPackagePath.Text = $dialog.SelectedPath
        Read-PackageFolder -Path $dialog.SelectedPath
    }
})

$ui.btnBrowseDocuments.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the folder that holds the request forms - one folder per request under it'
    if ($ui.txtDocumentRoot.Text -and (Test-Path -LiteralPath $ui.txtDocumentRoot.Text)) { $dialog.SelectedPath = $ui.txtDocumentRoot.Text }
    if ($dialog.ShowDialog() -eq 'OK') { $ui.txtDocumentRoot.Text = $dialog.SelectedPath; Save-DocumentRoot }
})
$ui.txtDocumentRoot.Add_LostFocus({ Save-DocumentRoot })
$ui.btnCopyContent.Add_Click({ Invoke-Guarded 'Copy now' { Start-ContentCopy } })
$ui.txtPackagePath.Add_LostFocus({ Update-ContentState })

$ui.btnRead.Add_Click({
    $path = $ui.txtPackagePath.Text.Trim()
    if ($path) { Read-PackageFolder -Path $path }
    else { Update-DerivedFields; Set-Status 'Names derived from the package name. Point at a package folder to also read its script and instruction document.' }
})

# typing a path and pressing Enter reads it, same as the button
$ui.txtPackagePath.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { $ui.btnRead.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Button]::ClickEvent))) } })

# ------------------------------------------------------------- the Modify tab
#
# The window cannot read SCCM - it has no connection and no rights, by design.
# So "Read from SCCM" submits an Inspect job and the answer comes back through
# the drop folder, exactly like an integration result. Ticking rows and pressing
# Apply submits a Change job carrying only the ticked names.
#
# This is what replaces editing an environment XML to add or retire a collection.

function Submit-AudiAction {
    <#  Submits an Inspect or Change job and waits for the answer.

        The same road as Integrate: a file into the drop folder, the server does
        the work, the result comes back. The window still touches no site.  #>
    param([string]$Action, $Plan, [string[]]$Add = @(), [string[]]$Remove = @(),
          [object[]]$SettingChanges = @(), [object[]]$MemberChanges = @(), [string]$Description)

    $code = (Get-SelectedEnvironment)
    $drop = Get-ActiveDropFolder
    if ([string]::IsNullOrWhiteSpace($drop)) {
        Set-Status "No drop folder is set - DropFolder in Packager\Settings.txt." '#FFB3261E'; return
    }
    if (-not (Connect-AudiShare -Path $drop -Purpose 'the drop folder')) { return }
    if (Test-PackageJobPending -DropFolder $drop -Code $code -PackageName $Plan.PackageName) { return }

    $state.Note = ''
    Set-Status "$Description in $code ..."
    # Inspect is not a run - its answer belongs on the Modify tab, so the window
    # stays where it is instead of jumping to Result and back.
    Start-Worker -Steps 1 -StayOnTab:($Action -eq 'Inspect') -Arguments @{
        Action      = $Action
        DropFolder  = $drop
        Timeout     = $defaults.Runtime.ResultTimeoutMinutes
        PackageName = $Plan.PackageName
        Environment = $code
        Rfc         = $ui.txtRfc.Text.Trim()
        Detail      = Get-PackageDetail
        Add         = $Add
        Remove      = $Remove
        SettingChanges = $SettingChanges
        MemberChanges  = $MemberChanges
        DryRun      = [bool]$DryRun
    } -Body {
        try {
            . (Join-Path $toolRoot 'Load.ps1')
            $state.Step = 'Writing the job file...'
            $doc = New-AudiSwJobFile -PackageName $jobArgs.PackageName -EnvironmentCode $jobArgs.Environment `
                                     -Action $jobArgs.Action -Rfc $jobArgs.Rfc -Detail $jobArgs.Detail `
                                     -AddCollections $jobArgs.Add -RemoveCollections $jobArgs.Remove `
                                     -SettingChanges $jobArgs.SettingChanges `
                                     -MemberChanges $jobArgs.MemberChanges `
                                     -DryRun:([bool]$jobArgs.DryRun)

            $submission = Submit-AudiSwJob -DropFolder $jobArgs.DropFolder -Job $doc
            $state.JobId = $submission.JobId
            $state.Waiting = $true
            $state.Step = "Queued in $(Split-Path -Parent $submission.Path). Waiting for the server..."

            $state.Result = Wait-AudiSwJobResult -Submission $submission `
                                -TimeoutMinutes $jobArgs.Timeout -PollSeconds 5
            $state.Note = ''
        }
        catch { $state.Error = $_.Exception.Message }
        finally { $state.Waiting = $false; $state.Done = $true; $state.Running = $false }
    }
}

# ------------------------------------------------------------ the Members page
#
# One list, three plain states, no tick boxes:
#
#   on site           the collection holds the machine now
#   will be added     pasted on the right; sent on Apply
#   will be removed   marked with "Remove selected" / "Remove all"; sent on Apply
#
# Pending changes live in $script:MemberChanges as {Collection, Machine,
# Action} until Apply or Discard, so switching collections loses nothing.
# After Apply the list updates itself from the server's answer - each machine
# the server reports as added or removed moves state here without another
# Read from SCCM.

$script:MembersShown = ''   # the collection the grid is currently showing

function Get-MemberCollectionName {
    $item = $ui.cboMemberCollection.SelectedItem
    if ($null -eq $item) { return '' }
    return [string]$item
}

function Get-MemberChangeList { param([string]$Collection, [string]$Action)
    return @($script:MemberChanges | Where-Object { $_.Collection -eq $Collection -and $_.Action -eq $Action })
}

function Remove-MemberChange { param([string]$Collection, [string]$Machine, [string]$Action)
    $script:MemberChanges = @($script:MemberChanges | Where-Object {
        -not ($_.Collection -eq $Collection -and $_.Machine -eq $Machine -and $_.Action -eq $Action) })
}

function Show-CollectionMembers { param([string]$CollectionName)
    <#  The machines in one collection, each with its state.  #>
    $script:MembersShown = $CollectionName

    if (-not $CollectionName) {
        $ui.lstMembers.ItemsSource = @()
        $ui.txtMembersNote.Text  = ''
        $ui.txtMembersCount.Text = ''
        Update-MembersSummary
        return
    }

    $rows   = New-Object System.Collections.Generic.List[object]
    $onSite = @()
    $note   = ''
    if ($script:CollectionMembers.ContainsKey($CollectionName)) {
        $onSite = @($script:CollectionMembers[$CollectionName].Members)
        $note   = [string]$script:CollectionMembers[$CollectionName].MemberNote
    }
    $removing = @(Get-MemberChangeList $CollectionName 'Remove' | ForEach-Object { $_.Machine })
    foreach ($machine in $onSite) {
        $rows.Add([pscustomobject]@{ Machine = $machine
                                     Status = $(if ($removing -contains $machine) { 'will be removed' } else { 'on site' }) }) | Out-Null
    }
    foreach ($change in @(Get-MemberChangeList $CollectionName 'Add')) {
        $rows.Add([pscustomobject]@{ Machine = $change.Machine; Status = 'will be added' }) | Out-Null
    }

    $ui.lstMembers.ItemsSource = $rows.ToArray()
    $ui.txtMembersCount.Text   = "{0} on site" -f $onSite.Count
    if (-not $note -and $onSite.Count -eq 0) { $note = 'No machines are directly in this collection yet.' }
    $ui.txtMembersNote.Text = $note
    Update-MembersSummary
}

function Update-MembersSummary {
    <#  The not-yet-applied strip and the Apply button.  #>
    if (-not $ui.Contains('txtMembersSummary')) { return }
    $adds    = @($script:MemberChanges | Where-Object { $_.Action -eq 'Add' })
    $removes = @($script:MemberChanges | Where-Object { $_.Action -eq 'Remove' })
    if ($adds.Count -eq 0 -and $removes.Count -eq 0) {
        $ui.txtMembersSummary.Text = 'No changes.'
        $ui.btnApplyMembers.IsEnabled = $false
        return
    }
    $parts = @()
    if ($adds.Count -gt 0)    { $parts += "{0} to add: {1}" -f $adds.Count, (@($adds | ForEach-Object { $_.Machine }) -join ', ') }
    if ($removes.Count -gt 0) { $parts += "{0} to remove: {1}" -f $removes.Count, (@($removes | ForEach-Object { $_.Machine }) -join ', ') }
    $other = @(@($script:MemberChanges | ForEach-Object { $_.Collection }) | Sort-Object -Unique | Where-Object { $_ -ne $script:MembersShown })
    if ($other.Count -gt 0) { $parts += "(also in: {0})" -f ($other -join ', ') }
    $ui.txtMembersSummary.Text = ($parts -join "`r`n")
    $ui.btnApplyMembers.IsEnabled = -not $state.Running
}

function Add-QueuedMachine {
    <#  Puts the pasted machines in the list as "will be added".  #>
    $collection = Get-MemberCollectionName
    if (-not $collection) { Set-Status 'Read from SCCM first, then pick the collection to add machines to.' '#FF8A5300'; return }

    $typed = $ui.txtAddMachines.Text.Trim()
    if (-not $typed) { Set-Status 'Paste or type the machine names first.' '#FF8A5300'; $ui.txtAddMachines.Focus() | Out-Null; return }

    # However the list was separated - pasted straight out of a mail or a ticket.
    $machines = @($typed -split '[,;\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $onSite   = @()
    if ($script:CollectionMembers.ContainsKey($collection)) { $onSite = @($script:CollectionMembers[$collection].Members) }

    $added = 0; $skipped = 0; $kept = 0
    foreach ($machine in $machines) {
        # pasting a machine that is marked for removal means "keep it after all"
        if ((Get-MemberChangeList $collection 'Remove' | ForEach-Object { $_.Machine }) -contains $machine) {
            Remove-MemberChange $collection $machine 'Remove'; $kept++; continue
        }
        if (($onSite -contains $machine) -or ((Get-MemberChangeList $collection 'Add' | ForEach-Object { $_.Machine }) -contains $machine)) { $skipped++; continue }
        $script:MemberChanges += [pscustomobject]@{ Collection = $collection; Machine = $machine; Action = 'Add' }
        $added++
    }

    $ui.txtAddMachines.Text = ''
    Show-CollectionMembers -CollectionName $collection
    Set-Status ("{0} machine(s) will be added to {1}{2}{3}. Nothing is sent until Apply." -f $added, $collection,
                $(if ($kept) { ", $kept kept after all" } else { '' }),
                $(if ($skipped) { ", $skipped already there" } else { '' }))
}

function Set-SelectedMembers { param([string]$To)   # Remove | Keep
    <#  "Remove selected": on site -> will be removed; will be added -> gone.
        "Keep selected":   will be removed -> on site.  #>
    $collection = Get-MemberCollectionName
    $rows = @($ui.lstMembers.SelectedItems)
    if ($rows.Count -eq 0) { Set-Status 'Select one or more machines in the list first (click, Ctrl-click or Shift-click).' '#FF8A5300'; return }
    $n = 0
    foreach ($row in $rows) {
        $machine = [string]$row.Machine
        switch ($To) {
            'Remove' {
                if ($row.Status -eq 'will be added') { Remove-MemberChange $collection $machine 'Add'; $n++ }
                elseif ($row.Status -eq 'on site') {
                    $script:MemberChanges += [pscustomobject]@{ Collection = $collection; Machine = $machine; Action = 'Remove' }; $n++
                }
            }
            'Keep' {
                if ($row.Status -eq 'will be removed') { Remove-MemberChange $collection $machine 'Remove'; $n++ }
            }
        }
    }
    Show-CollectionMembers -CollectionName $collection
    Set-Status $(if ($To -eq 'Remove') { "$n machine(s) will be removed from $collection when you Apply." } else { "$n machine(s) kept." })
}

function Set-AllMembersRemoved {
    $collection = Get-MemberCollectionName
    if (-not $collection -or -not $script:CollectionMembers.ContainsKey($collection)) { return }
    $onSite = @($script:CollectionMembers[$collection].Members)
    if ($onSite.Count -eq 0) { Set-Status 'There is nothing in this collection to remove.' '#FF8A5300'; return }
    $ok = Show-Confirm -Title 'Remove all' -Headline "Mark all $($onSite.Count) machine(s) in $collection to be removed" `
        -Lead 'Nothing is sent until you press Apply - and Apply asks again, naming every machine.' `
        -Rows @([pscustomobject]@{ Label = 'Machines'; Value = ($onSite -join ', '); Mono = $true }) `
        -Question 'Mark them all?'
    if (-not $ok) { return }
    foreach ($machine in $onSite) {
        if ((Get-MemberChangeList $collection 'Remove' | ForEach-Object { $_.Machine }) -notcontains $machine) {
            $script:MemberChanges += [pscustomobject]@{ Collection = $collection; Machine = $machine; Action = 'Remove' }
        }
    }
    Show-CollectionMembers -CollectionName $collection
    Set-Status "All $($onSite.Count) machine(s) will be removed from $collection when you Apply."
}

function Get-QueuedMemberChange { return @($script:MemberChanges) }

function Clear-QueuedMembers {
    $script:MemberChanges = @()
    Show-CollectionMembers -CollectionName (Get-MemberCollectionName)
    Set-Status 'Member changes discarded. Nothing was sent.'
}

function Update-MemberCollectionList {
    <#  Fills the dropdown with the collections that EXIST on the site, from
        the last Inspect. Keeps the current choice if it is still there.  #>
    $current = Get-MemberCollectionName
    $ui.cboMemberCollection.Items.Clear()
    foreach ($name in @($script:CollectionMembers.Keys | Sort-Object)) { $null = $ui.cboMemberCollection.Items.Add($name) }
    if ($current -and $ui.cboMemberCollection.Items.Contains($current)) { $ui.cboMemberCollection.SelectedItem = $current }
    elseif ($ui.cboMemberCollection.Items.Count -gt 0) { $ui.cboMemberCollection.SelectedIndex = 0 }
    else { Show-CollectionMembers -CollectionName '' }
}

function Start-ApplyMembers {
    $members = @(Get-QueuedMemberChange)
    if ($members.Count -eq 0) { Set-Status 'Nothing to apply. Add machines, or mark some to be removed.' '#FF8A5300'; return }

    # Machines are the one change in this tool that reaches real computers -
    # software installs on them - so they are confirmed by NAME, not by count.
    $rows = @()
    foreach ($group in @($members | Sort-Object Collection, Action, Machine | Group-Object Collection)) {
        $adds = @($group.Group | Where-Object { $_.Action -eq 'Add' }    | ForEach-Object { $_.Machine })
        $rems = @($group.Group | Where-Object { $_.Action -eq 'Remove' } | ForEach-Object { $_.Machine })
        if ($adds.Count) { $rows += [pscustomobject]@{ Label = 'Add to';      Value = "$($group.Name)`r`n" + ($adds -join ', '); Mono = $true } }
        if ($rems.Count) { $rows += [pscustomobject]@{ Label = 'Remove from'; Value = "$($group.Name)`r`n" + ($rems -join ', '); Mono = $true } }
    }
    $hasRemove = @($members | Where-Object { $_.Action -eq 'Remove' }).Count -gt 0
    $ok = Show-Confirm -Title 'Apply' -Danger:$hasRemove `
        -Headline "Change the machines of $($ui.txtPackage.Text.Trim()) in $((Get-SelectedEnvironment))" `
        -Lead 'A machine added to an install collection will install this software; one removed will no longer receive it.' `
        -Rows $rows -NotTouched @('every other machine and collection') -Question 'Apply these machine changes?'
    if (-not $ok) { Set-Status 'Nothing was submitted.'; return }

    try   { $plan = New-PlanFromForm } catch { Set-Status $_.Exception.Message '#FF8A5300'; return }
    # The list keeps showing the pending changes until the server answers;
    # Complete-MemberApply then moves each machine the server confirms.
    $state.PendingMembers = $members
    Submit-AudiAction -Action 'Change' -Plan $plan -MemberChanges $members `
                      -Description ("Applying {0} member change(s)" -f $members.Count)
}

function Complete-MemberApply { param($Result)
    <#  Reflects the server's answer in the list without another Read from
        SCCM. The server reports one step per machine - "X added to C." /
        "X removed from C." / "X was already in C." - so each confirmed
        change is applied to the local picture and dropped from the pending
        list; anything the server did not confirm stays pending, visibly.  #>
    $pending = @($state.PendingMembers)
    $state.PendingMembers = $null
    if ($pending.Count -eq 0) { return }

    $steps = @($(if ($Result -and (Test-HasValue $Result 'Steps')) { $Result.Steps } else { @() }))
    $done  = 0
    foreach ($change in $pending) {
        $confirmed = @($steps | Where-Object {
            $_.Ok -and ([string]$_.Message -like "$($change.Machine) added to $($change.Collection).*" -or
                        [string]$_.Message -like "$($change.Machine) removed from $($change.Collection).*" -or
                        [string]$_.Message -like "$($change.Machine) was already in $($change.Collection).*") }).Count -gt 0
        if (-not $confirmed) { continue }

        if ($script:CollectionMembers.ContainsKey($change.Collection)) {
            $entry = $script:CollectionMembers[$change.Collection]
            $now   = @($entry.Members)
            if ($change.Action -eq 'Add' -and $now -notcontains $change.Machine) { $now += $change.Machine }
            if ($change.Action -eq 'Remove') { $now = @($now | Where-Object { $_ -ne $change.Machine }) }
            $entry.Members = @($now | Sort-Object)
        }
        Remove-MemberChange $change.Collection $change.Machine $change.Action
        $done++
    }
    Show-CollectionMembers -CollectionName (Get-MemberCollectionName)

    $left = @($script:MemberChanges).Count
    if ($left -gt 0) {
        Set-Status ("{0} change(s) applied; {1} not confirmed by the server and still pending - see the Jobs page for why." -f $done, $left) '#FF8A5300'
    }
    Show-Page 'tabMembers'
}
# $Collections, not $State: variable names are case-insensitive, and a parameter
# called $State would shadow the window's shared $state table for every helper
# this calls.
function Show-PackageState { param($Collections, [switch]$KeepMembers)
    <#  Turns what the server found into rows a person can act on.

        Three cases, and the row says which:
          wanted, not there   -> Add     (tickable)
          there, not wanted   -> Remove  (tickable)
          wanted and there    -> shown, nothing to do  #>
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($collection in @($Collections)) {
        if ($collection.Wanted -and -not $collection.Exists) {
            $rows.Add([pscustomobject]@{
                Selected = $false; Actionable = $true; Action = 'Add'; Name = $collection.Name
                State = 'not there'
                Why = 'The environment file asks for it and it is not there.' }) | Out-Null
        }
        elseif (-not $collection.Wanted -and $collection.Exists) {
            $rows.Add([pscustomobject]@{
                Selected = $false; Actionable = $true; Action = 'Remove'; Name = $collection.Name
                State = $(if ($collection.HasDeployment) { 'on site, deployed' } else { 'on site, not deployed' })
                Why = 'Named for this package, but the environment file does not ask for it.' }) | Out-Null
        }
        else {
            # In place and wanted - but still removable. Matching the
            # environment file is not a reason to forbid removing a collection:
            # the file says what a NEW package gets, not what this one must keep
            # for ever. The row says it matches, and lets the packager decide.
            $rows.Add([pscustomobject]@{
                Selected = $false; Actionable = $true; Action = 'Remove'; Name = $collection.Name
                State = $(if ($collection.HasDeployment) { 'on site, deployed' } else { 'on site, not deployed' })
                Why = 'In place and as the environment file asks. Tick only if you want it gone.' }) | Out-Null
        }
    }

    # The picture of the site, kept so an applied change can be folded into
    # it and the page redrawn without another trip to the server.
    $script:SiteState = @($Collections)

    # Keep what each EXISTING collection reported, so the Members page can show
    # its machines without another trip to the server. A collection that is
    # not on the site cannot hold machines, so it is not offered there.
    # -KeepMembers: a redraw after Apply, where the member picture (and any
    # change still pending) has already been brought up to date.
    if (-not $KeepMembers) {
        $script:CollectionMembers = @{}
        $script:MemberChanges     = @()
        foreach ($collection in @($Collections)) {
            if (-not $collection.Exists) { continue }
            $script:CollectionMembers[[string]$collection.Name] = [pscustomobject]@{
                Members    = @($(if (Test-HasValue $collection 'Members')    { $collection.Members }    else { @() }))
                MemberNote =   $(if (Test-HasValue $collection 'MemberNote') { $collection.MemberNote } else { '' })
            }
        }
    }
    Update-MemberCollectionList

    $ui.lstModify.ItemsSource = $rows.ToArray()
    $actionable = @($rows | Where-Object { $_.Actionable }).Count
    $ui.txtModifyHint.Text = if ($actionable -eq 0) {
        'Nothing on the site for this package yet. Integrate it first.'
    } else {
        'Tick the rows to act on. Only ticked rows are touched; nothing else on the site is altered. Machines are on the Members page.'
    }
    Update-ApplyGate
}

function Complete-ChangeApply { param($Result)
    <#  Folds the server's answer to a Modify-page Apply into the picture on
        screen, so the page shows the site as it now is without another Read
        from SCCM. One step per collection ("X created, deployed and filed." /
        "X and its deployment removed.") and one per setting (Step 'Setting',
        named by its label).  #>
    $pending = $state.PendingChange
    $state.PendingChange = $null
    if (-not $pending -or -not $script:SiteState) { return }

    $steps = @($(if ($Result -and (Test-HasValue $Result 'Steps')) { $Result.Steps } else { @() }))
    $okSteps = @($steps | Where-Object { $_.Ok })

    foreach ($name in @($pending.Add)) {
        if (@($okSteps | Where-Object { [string]$_.Message -like "$name created*" }).Count -eq 0) { continue }
        foreach ($c in $script:SiteState) { if ($c.Name -eq $name) { $c.Exists = $true; $c.HasDeployment = $true } }
        if (-not $script:CollectionMembers.ContainsKey($name)) {
            $script:CollectionMembers[$name] = [pscustomobject]@{ Members = @(); MemberNote = '' }
        }
    }
    foreach ($name in @($pending.Remove)) {
        if (@($okSteps | Where-Object { [string]$_.Message -like "$name and its deployment removed*" }).Count -eq 0) { continue }
        foreach ($c in $script:SiteState) { if ($c.Name -eq $name) { $c.Exists = $false; $c.HasDeployment = $false } }
        if ($script:CollectionMembers.ContainsKey($name)) { $script:CollectionMembers.Remove($name) }
        $script:MemberChanges = @($script:MemberChanges | Where-Object { $_.Collection -ne $name })
    }
    foreach ($change in @($pending.Settings)) {
        if (@($okSteps | Where-Object { $_.Step -eq 'Setting' -and [string]$_.Name -eq [string]$change.Label }).Count -eq 0) { continue }
        foreach ($row in @($(if ($ui.lstSettings.ItemsSource) { $ui.lstSettings.ItemsSource } else { @() }))) {
            if ($row.Key -ne $change.Key) { continue }
            $label = [string]$change.To
            foreach ($o in @($row.Options)) { if ([string]$o.Value -eq [string]$change.To) { $label = [string]$o.Label } }
            $row.Current = $change.To; $row.CurrentLabel = $label; $row.NewValue = $change.To
            $script:SettingsBaseline[$row.Key] = [string]$change.To
        }
    }
    # redraw both grids from the updated picture
    $settingsRows = @($(if ($ui.lstSettings.ItemsSource) { $ui.lstSettings.ItemsSource } else { @() }))
    $ui.lstSettings.ItemsSource = $null; $ui.lstSettings.ItemsSource = $settingsRows
    Show-PackageState $script:SiteState -KeepMembers
    $ui.txtModifyState.Text = "Updated from the server's answer at $((Get-Date).ToString('HH:mm')). Read from SCCM again any time to be sure."
    Show-Page 'tabModify'
}

function Update-ApplyGate {
    <#  Apply on the Modify page is live once the site has been read and there
        is something it could change.  #>
    $rows = @($(if ($ui.lstModify.ItemsSource) { $ui.lstModify.ItemsSource } else { @() }))
    $settings = @($(if ($ui.lstSettings.ItemsSource) { $ui.lstSettings.ItemsSource } else { @() }))
    $ui.btnApplyChanges.IsEnabled = (-not $state.Running) -and
        ((@($rows | Where-Object { $_.Actionable }).Count -gt 0) -or (@($settings | Where-Object { $_.Editable }).Count -gt 0))
}

function Update-RemoveGate {
    <#  Remove stays off until the package name has been typed back exactly.
        A destructive job should cost a deliberate act, not a slip of the
        mouse. #>
    $package = $ui.txtPackage.Text.Trim()
    $typed   = $ui.txtRemoveConfirm.Text.Trim()
    $ok = ($package -and ($typed -eq $package) -and -not $state.Running)
    $ui.btnRemove.IsEnabled = [bool]$ok
    # Remove ticked is live as soon as the Find list has rows; pressing it with
    # nothing ticked only says so - the prompt that follows names every one
    $found = @($(if ($ui.lstFound.ItemsSource) { $ui.lstFound.ItemsSource } else { @() })).Count
    $ui.btnRemoveFound.IsEnabled = ($found -gt 0 -and -not $state.Running)
    $ui.txtRemoveHint.Text = if ($found -gt 0) { "$found application(s) in the Find list - tick the ones to go, then Remove ticked. Only the ticked names are removed." }
        elseif (-not $package) { 'Name the package in the header first, or Find one on the site below.' }
        elseif ($ok) { "Ready. Remove '$package' from $((Get-SelectedEnvironment)) - this takes it out of SCCM." }
        else { 'Type the package name above, exactly as in the header, to enable Remove.' }
}

# ------------------------------------------------ Find on the site, then tick
#
# Ewald's case, the other half: applications made by hand, or whose name has a
# * in it. A pattern is a SEARCH here and nowhere else. The server lists what
# matches; the packager ticks; the Remove job carries the exact names ticked
# and the server removes those objects, one each, matched whole.

function Start-FindOnSite {
    $pattern = $ui.txtFindPattern.Text.Trim()
    if (-not $pattern) { Set-Status 'Type a name or a pattern to look for, e.g. INA_ADOBE_*' '#FF8A5300'; $ui.txtFindPattern.Focus() | Out-Null; return }
    if ($pattern -match '[\p{Cc}]' -or $pattern.Length -gt 256) { Set-Status 'That pattern cannot be sent - letters, digits and * ? only, up to 256 characters.' '#FF8A5300'; return }
    $code = Get-SelectedEnvironment
    if (-not $code) { Set-Status (Test-EnvironmentChosen) '#FF8A5300'; $ui.cboEnvironment.Focus() | Out-Null; return }
    $drop = Get-ActiveDropFolder
    if (-not $drop -or -not (Connect-AudiShare -Path $drop -Purpose 'the drop folder')) { return }
    if (Test-PackageJobPending -DropFolder $drop -Code $code -PackageName 'FIND') { return }

    $ui.lstFound.ItemsSource = @()
    Update-RemoveGate
    $state.FindPending = $true
    $state.Note = ''
    Set-Status "Looking on $code for '$pattern' ..."
    Start-Worker -Steps 1 -StayOnTab -Arguments @{
        DropFolder = $drop; Environment = $code; Pattern = $pattern; Rfc = $ui.txtRfc.Text.Trim()
        Timeout = $defaults.Runtime.ResultTimeoutMinutes; DryRun = [bool]$DryRun
    } -Body {
        try {
            . (Join-Path $toolRoot 'Load.ps1')
            $state.Step = 'Asking the server what matches...'
            $doc = New-AudiSwJobFile -PackageName 'FIND' -EnvironmentCode $jobArgs.Environment -Action 'Find' `
                                     -FindPattern $jobArgs.Pattern -Rfc $jobArgs.Rfc -DryRun:([bool]$jobArgs.DryRun)
            $submission = Submit-AudiSwJob -DropFolder $jobArgs.DropFolder -Job $doc
            $state.JobId = $submission.JobId; $state.Waiting = $true
            $state.Step = "Queued in $(Split-Path -Parent $submission.Path). Waiting for the server..."
            $state.Result = Wait-AudiSwJobResult -Submission $submission -TimeoutMinutes $jobArgs.Timeout -PollSeconds 5
        }
        catch { $state.Error = $_.Exception.Message }
        finally { $state.Waiting = $false; $state.Done = $true; $state.Running = $false }
    }
}

function Show-FoundApplications { param($Result)
    <#  The Find answer as a tick list. Nothing is ticked to begin with.  #>
    $apps = @($(if ($Result -and (Test-HasValue $Result 'FoundApps')) { $Result.FoundApps } else { @() }))
    $rows = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($a in $apps) {
        $rows.Add([pscustomobject]@{
            Selected = $false; Name = [string]$a.Name; ContentPath = [string]$a.ContentPath
            Collections = @($a.Collections)
            CollectionList = $(if (@($a.Collections).Count) { @($a.Collections) -join "`r`n" } else { '(no deployment)' })
        }) | Out-Null
    }
    $ui.lstFound.ItemsSource = $rows
    $ui.tglFind.IsChecked = $true      # the list lives behind a disclosure; open it
    Update-RemoveGate
    $text = $(if ($Result) { [string]$Result.Message } else { 'No answer.' })
    Set-Status $text $(if ($Result -and $Result.Ok) { '#FF00707D' } else { '#FFB3261E' })
    Show-Page 'tabRemove'
}

function Start-RemoveFound {
    <#  Remove exactly the applications ticked in the Find list - after a prompt
        that names every one of them, with its collections and its content
        folder, and a second, separate question about the content.  #>
    $ticked = @($(if ($ui.lstFound.ItemsSource) { $ui.lstFound.ItemsSource } else { @() }) | Where-Object { $_.Selected })
    if ($ticked.Count -eq 0) { Set-Status 'Tick at least one application in the Find list.' '#FF8A5300'; return }
    $code = Get-SelectedEnvironment
    if (-not $code) { Set-Status (Test-EnvironmentChosen) '#FF8A5300'; return }
    $drop = Get-ActiveDropFolder
    if (-not $drop -or -not (Connect-AudiShare -Path $drop -Purpose 'the drop folder')) { return }
    if (Test-PackageJobPending -DropFolder $drop -Code $code -PackageName 'REMOVE') { return }

    $rows = @()
    foreach ($t in $ticked) {
        $what = if (@($t.Collections).Count) { (@($t.Collections) | ForEach-Object { "+ $_" }) -join "`r`n" } else { 'application only, no deployment' }
        $rows += [pscustomobject]@{ Label = 'Application'; Value = "$($t.Name)`r`n$what"; Mono = $true }
    }
    $ok = Show-Confirm -Title 'Remove' -Danger `
        -Headline "Remove $($ticked.Count) application(s) from $code" `
        -Lead 'Exactly these - whole names, one object each, nothing matched by pattern.' `
        -Rows $rows -NotTouched @('the files in the store (asked next)', 'any other application or collection') `
        -Question 'Remove these applications and their collections and deployments?'
    if (-not $ok) { Set-Status 'Cancelled.'; return }

    $removeContent = $false
    $withContent = @($ticked | Where-Object { $_.ContentPath })
    if ($withContent.Count -gt 0 -and -not $DryRun) {
        $folderRows = @($withContent | ForEach-Object { [pscustomobject]@{ Label = 'Folder'; Value = $_.ContentPath; Mono = $true } })
        $delete = Show-Confirm -Title 'Delete the files' -Danger `
            -Headline 'Also delete their content folders from the store?' `
            -Lead 'Only these folders, only directly under this environment''s store, and only after SCCM has let go of the application. This cannot be undone.' `
            -Rows $folderRows -NotTouched @('any other folder in the store') `
            -Question 'Delete the files? (Cancel keeps them - the applications are still removed from SCCM.)'
        $removeContent = [bool]$delete
    }

    $targets = @($ticked | ForEach-Object { [pscustomobject]@{ Name = $_.Name; ContentPath = $_.ContentPath; Collections = @($_.Collections) } })
    $state.Note = ''
    Set-Status "Removing $($ticked.Count) application(s) from $code ..."
    Start-Worker -Steps $ticked.Count -Arguments @{
        DropFolder = $drop; Environment = $code; Targets = $targets; RemoveContent = $removeContent; Rfc = $ui.txtRfc.Text.Trim()
        Timeout = $defaults.Runtime.ResultTimeoutMinutes; DryRun = [bool]$DryRun
    } -Body {
        try {
            . (Join-Path $toolRoot 'Load.ps1')
            $state.Step = 'Writing the job file...'
            $doc = New-AudiSwJobFile -PackageName 'REMOVE' -EnvironmentCode $jobArgs.Environment -Action 'Remove' `
                                     -Targets $jobArgs.Targets -RemoveContent:([bool]$jobArgs.RemoveContent) -Rfc $jobArgs.Rfc -DryRun:([bool]$jobArgs.DryRun)
            $submission = Submit-AudiSwJob -DropFolder $jobArgs.DropFolder -Job $doc
            $state.JobId = $submission.JobId; $state.Waiting = $true
            $state.Step = "Queued in $(Split-Path -Parent $submission.Path). Waiting for the server..."
            $state.Result = Wait-AudiSwJobResult -Submission $submission -TimeoutMinutes $jobArgs.Timeout -PollSeconds 5
            $state.Note = ''
        }
        catch { $state.Error = $_.Exception.Message }
        finally { $state.Waiting = $false; $state.Done = $true; $state.Running = $false }
    }
    $ui.lstFound.ItemsSource = @()
    Update-RemoveGate
}

function Show-PackageSettings { param($Settings)
    <#  The settings the application and its deployment type carry right now,
        each with the values SCCM would accept instead.

        The rows are handed to the grid as-is: NewValue starts equal to the
        current value, so a row that nobody touches produces no change. What
        gets sent later is the difference, not the whole set - see
        Get-ChangedSettings.

        A locked row (publisher, version, display name) shows its reason where
        the control would be. Those come out of the package name, so changing
        one in SCCM alone would leave the application disagreeing with the
        folder its content was built from.  #>

    # ToArray, not @(): wrapping a List[object] of PSObjects throws
    # "Argument types do not match" on PowerShell 5.1.
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($s in @($Settings)) { $rows.Add($s) | Out-Null }
    $ui.lstSettings.ItemsSource = $rows.ToArray()

    $script:SettingsBaseline = @{}
    foreach ($s in @($Settings)) { $script:SettingsBaseline[$s.Key] = [string]$s.Current }

    $editable = @($Settings | Where-Object { $_.Editable }).Count
    $locked   = @($Settings | Where-Object { -not $_.Editable }).Count
    Set-Status ("{0} setting(s) can be changed here, {1} are fixed by the package name." -f $editable, $locked)
}

function Get-ChangedSettings {
    <#  Only what the operator actually altered.

        Comparing against the baseline captured at read time - not against the
        catalogue defaults - means an unchanged row is never sent. Writing back
        a value identical to the one already there would still stamp the
        application as modified, for no change at all.  #>
    if (-not $ui.lstSettings.ItemsSource) { return @() }
    $changed = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($ui.lstSettings.ItemsSource)) {
        if (-not $row.Editable) { continue }
        $was = [string]$script:SettingsBaseline[$row.Key]
        $now = [string]$row.NewValue
        if ($now -ne $was) {
            $changed.Add([pscustomobject]@{
                # Key and value only. Deliberately NOT the cmdlet parameter:
                # the server resolves what a key means from its own catalogue,
                # so a window cannot name a parameter for it to call. It is
                # also not carried in the result file, so reading it here threw
                # "The property 'Property' cannot be found on this object".
                Key = $row.Key; Label = $row.Label; From = $was; To = $now }) | Out-Null
        }
    }
    return $changed.ToArray()
}

function Start-Inspect { param([string]$From = 'Modify')
    $notChosen = Test-EnvironmentChosen
    if ($notChosen) { Set-Status $notChosen '#FFB3261E'; $ui.cboEnvironment.Focus() | Out-Null; return }
    try   { $plan = New-PlanFromForm } catch { Set-Status $_.Exception.Message '#FF8A5300'; return }
    $state.InspectFrom = $From
    Submit-AudiAction -Action 'Inspect' -Plan $plan -Description 'Reading the site'
}

function Start-ApplyChanges {
    <#  The Modify page's Apply: settings and collections only. Machines have
        their own page and their own Apply, so a collection change is never
        mixed into a member change by accident.  #>
    $rows     = @($(if ($ui.lstModify.ItemsSource) { $ui.lstModify.ItemsSource } else { @() }) | Where-Object { $_.Selected -and $_.Action -ne '-' })
    $settings = @(Get-ChangedSettings)

    if ($rows.Count -eq 0 -and $settings.Count -eq 0) {
        Set-Status 'Nothing to apply. Change a setting or tick a collection.' '#FF8A5300'; return
    }

    $add    = @($rows | Where-Object { $_.Action -eq 'Add' }    | ForEach-Object { $_.Name })
    $remove = @($rows | Where-Object { $_.Action -eq 'Remove' } | ForEach-Object { $_.Name })

    # ONE prompt that says everything this Apply does, by name - additions,
    # removals and settings before/after - so what is confirmed is what is
    # read (Audi's rule: no change on the site without the person seeing
    # exactly what it is).
    $confirmRows = @()
    foreach ($n in $add)    { $confirmRows += [pscustomobject]@{ Label = 'Create';  Value = "$n`r`nwith a deployment"; Mono = $true } }
    foreach ($n in $remove) { $confirmRows += [pscustomobject]@{ Label = 'Remove';  Value = "$n`r`nwith its deployment"; Mono = $true } }
    foreach ($s in $settings) {
        $confirmRows += [pscustomobject]@{ Label = $s.Label; Mono = $false
            Value = ("{0}  ->  {1}" -f $(if ($s.From) { $s.From } else { '(empty)' }), $(if ($s.To) { $s.To } else { '(empty)' })) }
    }
    $ok = Show-Confirm -Title 'Apply' -Danger:($remove.Count -gt 0) `
        -Headline "Apply $($confirmRows.Count) change(s) to $($ui.txtPackage.Text.Trim()) in $((Get-SelectedEnvironment))" `
        -Lead 'Collections are created or removed by exact name; settings change on the application only.' `
        -Rows $confirmRows -NotTouched @('the application''s content', 'the machines in its other collections') `
        -Question 'Apply these changes?'
    if (-not $ok) { Set-Status 'Nothing was submitted.'; return }

    try   { $plan = New-PlanFromForm } catch { Set-Status $_.Exception.Message '#FF8A5300'; return }
    $state.PendingChange = @{ Add = $add; Remove = $remove; Settings = $settings }
    Submit-AudiAction -Action 'Change' -Plan $plan -Add $add -Remove $remove -SettingChanges $settings `
                      -Description ("Applying {0} change(s)" -f ($add.Count + $remove.Count + $settings.Count))
}

# ------------------------------------------------------------------ copying
#
# Anything the tool says has to be pastable into a ticket or a mail. Clipboard
# writes can fail if another process is holding the clipboard open, so each one
# is guarded - a failed copy must not take the window down.
function Copy-ToClipboard { param([string]$Text, [string]$What)
    if ([string]::IsNullOrWhiteSpace($Text)) { Set-Status 'Nothing to copy.' '#FF8A5300'; return }
    try {
        [System.Windows.Clipboard]::SetText($Text)
        Set-Status "$What copied to the clipboard."
    }
    catch { Set-Status "Could not copy: $($_.Exception.Message)" '#FF8A5300' }
}

function Format-ResultRows { param($Rows)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($row in @($Rows)) { $lines.Add(("{0}`t{1}`t{2}" -f $row.Step, $row.Result, $row.Message)) | Out-Null }
    return ($lines -join "`r`n")
}

$ui.mnuCopyStatus.Add_Click({ Copy-ToClipboard $ui.txtStatus.Text 'The message' })

$ui.mnuCopyRows.Add_Click({
    $rows = @($ui.lstResults.SelectedItems)
    if ($rows.Count -eq 0) { $rows = @($ui.lstResults.ItemsSource) }
    Copy-ToClipboard (Format-ResultRows $rows) "$($rows.Count) row(s)"
})

$ui.mnuCopyAll.Add_Click({
    Copy-ToClipboard (Format-ResultRows @($ui.lstResults.ItemsSource)) 'Every row'
})

# ---- Modify page
$ui.btnInspect.Add_Click({ Invoke-Guarded 'Read from SCCM' { Start-Inspect -From 'Modify' } })
$ui.btnApplyChanges.Add_Click({ Invoke-Guarded 'Apply changes' { Start-ApplyChanges } })

# ---- Members page
$ui.cboMemberCollection.Add_SelectionChanged({ param($s, $e)
    if ($e.Source -ne $ui.cboMemberCollection) { return }
    Show-CollectionMembers -CollectionName (Get-MemberCollectionName)
})
$ui.btnQueueAdd.Add_Click({ Add-QueuedMachine })
$ui.txtAddMachines.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') { Add-QueuedMachine } })
$ui.btnRemoveSelected.Add_Click({ Set-SelectedMembers -To 'Remove' })
$ui.btnKeepSelected.Add_Click({ Set-SelectedMembers -To 'Keep' })
$ui.btnRemoveAll.Add_Click({ Set-AllMembersRemoved })
$ui.btnMembersDiscard.Add_Click({ Clear-QueuedMembers })
$ui.btnMembersRead.Add_Click({ Invoke-Guarded 'Read from SCCM' { Start-Inspect -From 'Members' } })
$ui.btnApplyMembers.Add_Click({ Invoke-Guarded 'Apply' { Start-ApplyMembers } })

# ---- Remove page
$ui.txtRemoveConfirm.Add_TextChanged({ Update-RemoveGate })

function Show-PackageHistory {
    <#  Everything this tool has done to this package, in the Result grid.

        Reads the drop folder's own result files - the same ones the window
        waits on - so it works after the window has been closed and reopened,
        and needs nothing from SCCM.  #>
    $package = $ui.txtPackage.Text.Trim()
    if (-not $package) { Set-Status 'Enter a package name first.' '#FF8A5300'; $ui.txtPackage.Focus() | Out-Null; return }

    $code = (Get-SelectedEnvironment)
    $drop = Get-ActiveDropFolder
    if ([string]::IsNullOrWhiteSpace($drop)) { Set-Status "No drop folder is set - DropFolder in Packager\Settings.txt." '#FFB3261E'; return }
    if (-not (Connect-AudiShare -Path $drop -Purpose 'the drop folder')) { return }

    try   { $runs = @(Get-AudiSwJobHistory -DropFolder $drop -EnvironmentCode $code -PackageName $package) }
    catch { Set-Status "Could not read the history: $($_.Exception.Message)" '#FFB3261E'; return }

    Show-Page 'tabJobs'
    if ($runs.Count -eq 0) {
        $ui.lstResults.ItemsSource = @()
        $ui.txtHistory.Text = "No job has been run for $package in $code."
        Set-Status "No history for $package in $code." '#FF8A5300'
        return
    }

    # One row per run, newest first, then that run's own steps indented under it,
    # so a failure can be read without opening the result file.
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($run in $runs) {
        $when = $(if ($run.Completed) { $run.Completed } else { 'in progress' })
        $rows.Add([pscustomobject]@{
            Step    = $when
            Result  = $run.Outcome
            Message = ("{0}{1} | RFC {2} | {3}" -f `
                        $run.Action, $(if ($run.DryRun) { ' (dry run)' } else { '' }),
                        $(if ($run.Rfc) { $run.Rfc } else { 'none' }), $run.Message)
        }) | Out-Null
        foreach ($step in @($run.Steps)) {
            $rows.Add([pscustomobject]@{
                Step = "    $($step.Step)"
                Result = $(if ($step.Ok) { 'OK' } else { 'FAILED' })
                Message = $step.Message }) | Out-Null
        }
    }
    $ui.lstResults.ItemsSource = $rows.ToArray()
    $ui.txtHistory.Text = ("{0} run(s) for {1} in {2}. Newest first." -f $runs.Count, $package, $code)
    Set-Status ("{0} run(s) found for {1}." -f $runs.Count, $package)
}

$ui.btnHistory.Add_Click({ Invoke-Guarded 'Show all runs' { Show-PackageHistory } })
$ui.btnRunAgain.Add_Click({ Invoke-Guarded 'Run again' { Start-RunAgain } })
$ui.btnCleanUp.Add_Click({ Invoke-Guarded 'Clean up' { Start-CleanUp } })
$ui.btnRefreshContent.Add_Click({ Invoke-Guarded 'Update content' { Start-Run -Mode 'RefreshContent' } })
$ui.btnFind.Add_Click({ Invoke-Guarded 'Find on the site' { Start-FindOnSite } })
$ui.txtFindPattern.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Start-FindOnSite } })
$ui.btnRemoveFound.Add_Click({ Invoke-Guarded 'Remove ticked' { Start-RemoveFound } })
$ui.btnFetchStatus.Add_Click({
    # The same read the timer does, on demand - for the packager who reopened
    # the tool a day later and wants to see it happen rather than trust it.
    $package = $ui.txtPackage.Text.Trim(); $code = Get-SelectedEnvironment
    if (-not $package) { Set-Status 'Name the package (or browse to it) to fetch its status.' '#FF8A5300'; return }
    if (-not $code)    { Set-Status (Test-EnvironmentChosen) '#FF8A5300'; return }
    $drop = Get-ActiveDropFolder
    if (-not $drop -or -not (Connect-AudiShare -Path $drop -Purpose 'the drop folder')) { return }
    Show-PreviousRuns
    Set-Status ("Status read from the drop folder at {0}: {1}" -f (Get-Date).ToString('HH:mm:ss'), $ui.txtHistory.Text)
})
$ui.btnIntegrate.Add_Click({ Invoke-Guarded 'Integrate' { Start-Run -Mode 'Integrate' } })
$ui.btnRemove.Add_Click({ Invoke-Guarded 'Remove' { Start-Run -Mode 'Remove' } })

$ui.btnOpenLog.Add_Click({
    if ($ui.Contains('LogFolder') -and (Test-Path -LiteralPath $ui['LogFolder'])) { Start-Process explorer.exe $ui['LogFolder'] }
})

# ------------------------------------------------------- watching the folder
#
# The nearest thing to a live connection that a one-way drop folder allows. The
# window polls the folder rather than the server, so it costs the server nothing,
# needs no port and no rights, and works exactly the same whether this window was
# the one that submitted the job or not. Close the window mid-job and reopen it,
# and the next tick picks the job back up wherever it has got to.
#
# Five seconds: fast enough to look live, slow enough that a share is not hammered
# by a room full of packagers.
$watch = New-Object System.Windows.Threading.DispatcherTimer
$watch.Interval = [TimeSpan]::FromSeconds(5)
$watch.Add_Tick({ Show-PreviousRuns })
$watch.Start()

# ------------------------------------------------------------------------ start
Set-Theme (Get-SavedTheme)
Update-EnvironmentNotice
Update-NextStep
Update-RemoveGate
Update-MembersSummary
Set-Status 'Start at the top right: choose the environment. Then pick the package folder and press Read details.'

if ($SelfTest) {
    # Drives the same functions the buttons call, synchronously, so the window's
    # own wiring is verified without a screen.
    Write-Output ''
    Write-Output 'Packager window - self test'
    Write-Output ''
    Write-Output ("  environments offered : {0}" -f (@($ui.cboEnvironment.Items | ForEach-Object { $_.Code }) -join ', '))
    Write-Output ("  preselected          : {0}" -f $(if (Get-SelectedEnvironment) { (Get-SelectedEnvironment) + ' - WRONG, nothing may be preselected' } else { 'none - the packager chooses' }))

    # THE INTEGRATE CLICK ITSELF, exactly as the button runs it, up to the
    # confirmation - which Show-Confirm answers No under -SelfTest. Everything
    # a packager PC does before the prompt (environment gate, RFC gate, share
    # check, pending-job check, content plan, the prompt) runs for real here,
    # with no server and no environment files, as on a packager PC. Both the
    # source tree and a packager-only install run this - the packager-only
    # install is where a crash on the click would be found by a packager.
    $testIntegrateClick = {
        Write-Output ''
        Write-Output '  the Integrate click, up to the confirmation:'
        $script:SelfTestBoxes = @()
        $clickDrop = Join-Path ([System.IO.Path]::GetTempPath()) ("AudiClickTest_{0}" -f ([guid]::NewGuid().ToString('N')))
        try {
            New-Item -ItemType Directory -Path $clickDrop -Force | Out-Null
            $keepDrop = $DropFolder; $script:DropFolder = $clickDrop
            $null = Select-Environment 'INA'
            $ui.btnIntegrate.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Button]::ClickEvent)))
            $confirm = @($script:SelfTestBoxes | Where-Object { $_.Title -eq 'Integrate' })
            Write-Output ("    boxes shown        : {0}  ({1})" -f $script:SelfTestBoxes.Count, (@($script:SelfTestBoxes | ForEach-Object { $_.Title }) -join ', '))
            Write-Output ("    confirmation       : {0}" -f $(if ($confirm.Count -eq 1) { 'reached, answered No - ' + (@($confirm[0].Text -split "`r`n"))[0] } else { 'NOT REACHED - WRONG' }))
            Write-Output ("    status line        : {0}" -f $ui.txtStatus.Text)
            Write-Output ("    nothing submitted  : {0}" -f (@(Get-ChildItem -LiteralPath $clickDrop -Filter '*.xml' -Recurse -ErrorAction SilentlyContinue).Count -eq 0))
            $script:DropFolder = $keepDrop
        }
        finally { if (Test-Path -LiteralPath $clickDrop) { Remove-Item -LiteralPath $clickDrop -Recurse -Force -ErrorAction SilentlyContinue } }
    }

    # ---- read a REAL package and check every field the window shows is filled
    Write-Output ''
    $sampleRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("AudiSelfTest_{0}" -f ([guid]::NewGuid().ToString('N')))
    try {
        # The sample package comes from Tests\, which a packager install does
        # not carry. Say so instead of dying: the window's wiring and the
        # Integrate click on a hand-filled form are what a packager install
        # can check; the read / job checks need the source tree.
        $builder = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tests\New-AudiSwSamplePackage.ps1'
        if (-not (Test-Path -LiteralPath $builder)) {
            Write-Output '  This is a packager-only install (no Tests\ beside it), so there is no sample package to read.'
            Write-Output '  The window loaded, every control is wired and the settings were read.'
            $handPkg = Join-Path $sampleRoot 'INA_AUDI_SelfTest_x64_1.0-0001_MUL'
            New-Item -ItemType Directory -Path (Join-Path $handPkg 'Files') -Force | Out-Null
            'self-test' | Set-Content -LiteralPath (Join-Path $handPkg 'Files\setup.txt') -Encoding UTF8
            '# self-test deployment script' | Set-Content -LiteralPath (Join-Path $handPkg 'Invoke-AppDeployToolkit.ps1') -Encoding UTF8
            $ui.txtPackagePath.Text = $handPkg
            $ui.txtPackage.Text     = 'INA_AUDI_SelfTest_x64_1.0-0001_MUL'
            $ui.txtNameEN.Text      = 'Audi Self Test 1.0'
            $ui.txtBranding.Text    = 'AUDI_SelfTest_x64_1.0-0001_MUL'
            $ui.txtRfc.Text         = 'AES-1-000000-A'
            if (@(Get-OperatingSystemTicks).Count -eq 0) { foreach ($box in @($ui.pnlOperatingSystems.Children)) { $box.IsChecked = $true; break } }
            & $testIntegrateClick
            Write-Output ''
            Write-Output '  Run the self-test from the source tree for the full read / prompt / job checks.'
            return
        }
        $made    = & $builder -Path $sampleRoot -PackageName 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0003_MUL'
        Read-PackageFolder -Path $made.Path

        $expect = [ordered]@{
            'Package name'     = 'txtPackage'
            'Publisher'        = 'txtPublisher'
            'Product'          = 'txtProduct'
            'Version'          = 'txtVersion'
            'Architecture'     = 'txtArchitecture'
            'Revision'         = 'txtRevision'
            'Language'         = 'txtLanguage'
            'Branding key'     = 'txtBranding'
            'Install title EN' = 'txtNameEN'
            'Install title DE' = 'txtNameDE'
            'Description (EN)' = 'txtDescEN'
            'Description (DE)' = 'txtDescDE'
            'RFC number'       = 'txtRfc'
        }
        Write-Output '  every field the window shows, after Read details:'
        $blank = 0
        foreach ($label in $expect.Keys) {
            $value = $ui[$expect[$label]].Text
            if ([string]::IsNullOrWhiteSpace($value)) { $blank++ }
            Write-Output ("    {0,-18} {1}" -f $label, $(if ($value) { $value } else { '*** EMPTY ***' }))
        }
        Write-Output ("  {0}" -f $(if ($blank -eq 0) { 'all fields filled' } else { "$blank FIELD(S) EMPTY" }))
        Write-Output ("  install title from   : {0}" -f $(if ($ui.txtNameEN.Text -eq 'Adobe Acrobat Reader 2024.1') { 'the deployment script (InstallTitle)' } else { 'NOT the script - WRONG' }))
        Write-Output ("  window has SoftIdent : {0}" -f $(if (@($ui.Keys) -like '*SoftIdent*') { 'YES - WRONG' } else { 'no - detection is the branding key only' }))
    }
    finally { if (Test-Path -LiteralPath $sampleRoot) { Remove-Item -LiteralPath $sampleRoot -Recurse -Force -ErrorAction SilentlyContinue } }

    # ---- the form kept apart from the package, under a documents location
    $docRootTest = Join-Path ([System.IO.Path]::GetTempPath()) ("AudiSelfTestDocs_{0}" -f ([guid]::NewGuid().ToString('N')))
    try {
        $bare = & $builder -Path $docRootTest -PackageName 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0009_MUL' `
                    -DocumentTarget (Join-Path $docRootTest 'Forms\AES-1-000123-A Adobe Acrobat Reader 2024.1\Documentation')
        $ui.txtDocumentRoot.Text = ''
        Read-PackageFolder -Path $bare.Path
        Write-Output ''
        Write-Output '  form kept apart from the package:'
        Write-Output ("    no documents location: description = '{0}'" -f $ui.txtDescEN.Text)
        $ui.txtDocumentRoot.Text = Join-Path $docRootTest 'Forms'
        Read-PackageFolder -Path $bare.Path
        Write-Output ("    with documents location: description = '{0}'" -f $ui.txtDescEN.Text)
        Write-Output ("    note beside the field : {0}" -f $ui.txtDocumentRootNote.Text)
        $ui.txtDocumentRoot.Text = ''
    }
    finally { if (Test-Path -LiteralPath $docRootTest) { Remove-Item -LiteralPath $docRootTest -Recurse -Force -ErrorAction SilentlyContinue } }

    # ---- the package content row and the copy into a temporary drop folder
    $shareTest = Join-Path ([System.IO.Path]::GetTempPath()) ("AudiSelfTestDrop_{0}" -f ([guid]::NewGuid().ToString('N')))
    try {
        New-Item -ItemType Directory -Path (Join-Path $shareTest 'drop') -Force | Out-Null
        $realDrop = $DropFolder
        $DropFolder = Join-Path $shareTest 'drop'          # Get-ActiveDropFolder honours this
        $pkgTest = & $builder -Path $shareTest -PackageName 'INA_ADOBE_Acrobat_Reader_x64_2024.1-0012_MUL'
        $null = Select-Environment 'INA'
        Read-PackageFolder -Path $pkgTest.Path
        Write-Output ''
        Write-Output '  package content row:'
        Write-Output ("    target             : {0}" -f $ui.txtContentTarget.Text)
        Write-Output ("    before the copy    : {0}   (Copy button {1})" -f $ui.txtContentState.Text, $(if ($ui.btnCopyContent.IsEnabled) { 'enabled' } else { 'disabled' }))
        $cp = Get-ContentCopyPlan -Code 'INA' -SccmName $ui.txtPackage.Text -PackagePath $pkgTest.Path
        Write-Output ("    plan               : from {0}  to {1}" -f $cp.From, $cp.To)
        $sourcesInDrop = (Get-AudiDropFolderPath -DropFolder $DropFolder -EnvironmentCode 'INA').Sources
        Initialize-AudiDropFolder -DropFolder $DropFolder -EnvironmentCode 'INA' | Out-Null
        $done = Copy-AudiPackageContent -PackagePath $pkgTest.Path -ContentShare $sourcesInDrop -SccmName $ui.txtPackage.Text
        Update-ContentState
        Write-Output ("    after the copy     : {0}   ({1} files, Copy button {2})" -f $ui.txtContentState.Text, $done.Files, $(if ($ui.btnCopyContent.IsEnabled) { 'enabled - WRONG' } else { 'disabled' }))
        Write-Output ("    in Sources         : {0}" -f ((Test-Path -LiteralPath (Join-Path $sourcesInDrop 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0012_MUL\Invoke-AppDeployToolkit.ps1')) -and -not (Test-Path -LiteralPath (Join-Path $sourcesInDrop 'INA_ADOBE_Acrobat_Reader_x64_2024.1-0012_MUL'))))
        $DropFolder = $realDrop
    }
    finally { if (Test-Path -LiteralPath $shareTest) { Remove-Item -LiteralPath $shareTest -Recurse -Force -ErrorAction SilentlyContinue } }

    # ---- a REAL package with a hyphen in its folder name, where present
    $wmPkg = 'C:\temp\INA_WinMerge_WinMerge_x64_2.16.58-0001_test'
    if (Test-Path -LiteralPath $wmPkg) {
        Read-PackageFolder -Path $wmPkg
        Write-Output ''
        Write-Output '  real package (WinMerge, hyphen folder):'
        Write-Output ("    header package     : {0}" -f $ui.txtPackage.Text)
        Write-Output ("    branding key       : {0}" -f $ui.txtBranding.Text)
        Write-Output ("    detection rule     : {0}" -f $ui.txtRule1.Text)
        Write-Output ("    install title      : {0}" -f $ui.txtNameEN.Text)
        Write-Output ("    description EN     : {0}" -f $ui.txtDescEN.Text)
        Write-Output ("    RFC                : {0}" -f $ui.txtRfc.Text)
        Write-Output ("    Windows ticked     : {0}   (form said: {1})" -f ((Get-OperatingSystemTicks) -join ', '), ($script:DocOperatingSystems -join ', '))
        Write-Output ("    status line        : {0}" -f $ui.txtStatus.Text)
    }

    # The same INA_ package into ICZ: allowed, and nothing about the name moves.
    $null = Select-Environment 'ICZ'
    $ui.txtPackage.Text = 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0003_MUL'
    Sync-EnvironmentToPackage
    Write-Output ''
    Write-Output ("  INA_ package into ICZ: environment stays {0}, warning strip {1}" -f (Get-SelectedEnvironment), $(if ($ui.brdWarning.Visibility -eq 'Visible') { 'SHOWN - WRONG' } else { 'clear' }))
    Write-Output ("  environments offered : {0}" -f (@($ui.cboEnvironment.Items | ForEach-Object { $_.Label }) -join '  |  '))
    $null = Select-Environment 'INA'
    Update-DerivedFields
    Write-Output ''
    Write-Output ("  publisher/product    : {0} / {1}" -f $ui.txtPublisher.Text, $ui.txtProduct.Text)
    Write-Output ("  branding key         : {0}" -f $ui.txtBranding.Text)
    Write-Output ("  detection rule       : {0}" -f $ui.txtRule1.Text)

    # ---- the pages and the theme, without a screen
    Write-Output ''
    Write-Output ("  pages                : {0}" -f (@($script:PageOf.Values) -join ', '))
    $pageOk = $true
    foreach ($tab in $script:PageOf.Values) { Show-Page $tab; if (-not $ui[$tab].IsSelected) { $pageOk = $false } }
    Show-Page 'tabIntegrate'
    Write-Output ("  every page selectable: {0}" -f $(if ($pageOk) { 'yes' } else { 'NO' }))
    $before = $window.Resources['Bg'].Color
    Set-Theme 'Light'; $light = $window.Resources['Bg'].Color
    Set-Theme 'Dark';  $dark  = $window.Resources['Bg'].Color
    Write-Output ("  theme swap           : light {0} / dark {1} - {2}" -f $light, $dark, $(if ($light -ne $dark) { 'brushes follow' } else { 'NOT CHANGING - WRONG' }))
    Write-Output ("  settings remembered  : {0}" -f $script:UserSettingsFile)

    # ---- the Remove gate
    $ui.txtRemoveConfirm.Text = 'wrong'
    $gateClosed = -not $ui.btnRemove.IsEnabled
    $ui.txtRemoveConfirm.Text = $ui.txtPackage.Text
    $gateOpen = $ui.btnRemove.IsEnabled
    $ui.txtRemoveConfirm.Text = ''
    Write-Output ("  remove gate          : {0}" -f $(if ($gateClosed -and $gateOpen) { 'off until the name is typed back, then on' } else { 'WRONG' }))

    # ---- the Members page, fed the shape an Inspect answer has
    Show-PackageState @(
        [pscustomobject]@{ Name = 'SM1-X_InstallComputer'; Wanted = $true; Exists = $true;  HasDeployment = $true; Members = @('PC001','PC002'); MemberNote = '' },
        [pscustomobject]@{ Name = 'SM1-X_Query';           Wanted = $true; Exists = $false; HasDeployment = $false })
    $ui.cboMemberCollection.SelectedItem = 'SM1-X_InstallComputer'
    $ui.txtAddMachines.Text = "PC003`r`nPC001, PC004"
    Add-QueuedMachine
    # select PC001 in the grid and press "Remove selected"
    $rows = @($ui.lstMembers.ItemsSource)
    $ui.lstMembers.SelectedItems.Clear(); $null = $ui.lstMembers.SelectedItems.Add(@($rows | Where-Object { $_.Machine -eq 'PC001' })[0])
    Set-SelectedMembers -To 'Remove'
    $rows = @($ui.lstMembers.ItemsSource)
    $queued = @(Get-QueuedMemberChange)
    Write-Output ''
    Write-Output ("  member collections   : {0} offered (only the one that exists)" -f $ui.cboMemberCollection.Items.Count)
    Write-Output ("  members grid         : {0}" -f (@($rows | ForEach-Object { "$($_.Machine)=$($_.Status)" }) -join ', '))
    Write-Output ("  not yet applied      : {0}" -f (@($queued | ForEach-Object { "$($_.Action) $($_.Machine)" }) -join ', '))
    Write-Output ("  apply enabled        : {0}" -f $ui.btnApplyMembers.IsEnabled)
    # "Keep selected" undoes a removal
    $ui.lstMembers.SelectedItems.Clear(); $null = $ui.lstMembers.SelectedItems.Add(@($rows | Where-Object { $_.Machine -eq 'PC001' })[0])
    Set-SelectedMembers -To 'Keep'
    Write-Output ("  after Keep selected  : {0}" -f (@($ui.lstMembers.ItemsSource | ForEach-Object { "$($_.Machine)=$($_.Status)" }) -join ', '))
    # the server's answer moves the list without a Read from SCCM
    $ui.lstMembers.SelectedItems.Clear(); $null = $ui.lstMembers.SelectedItems.Add(@($ui.lstMembers.ItemsSource | Where-Object { $_.Machine -eq 'PC002' })[0])
    Set-SelectedMembers -To 'Remove'
    $state.PendingMembers = @(Get-QueuedMemberChange)
    Complete-MemberApply ([pscustomobject]@{ Ok = $true; Steps = @(
        [pscustomobject]@{ Step = 'Machine'; Ok = $true;  Message = 'PC003 added to SM1-X_InstallComputer.' },
        [pscustomobject]@{ Step = 'Machine'; Ok = $false; Message = 'Add PC004 failed. SCCM does not know a machine called PC004.' },
        [pscustomobject]@{ Step = 'Machine'; Ok = $true;  Message = 'PC002 removed from SM1-X_InstallComputer.' }) })
    Write-Output ("  after the answer     : {0}" -f (@($ui.lstMembers.ItemsSource | ForEach-Object { "$($_.Machine)=$($_.Status)" }) -join ', '))
    Write-Output ("  still pending        : {0}" -f (@(Get-QueuedMemberChange | ForEach-Object { "$($_.Action) $($_.Machine)" }) -join ', '))
    Clear-QueuedMembers

    $ui.txtNameEN.Text = 'Adobe - Acrobat Reader - 2024.1'
    $ui.txtRfc.Text    = 'RFC0012345'
    $plan = New-PlanFromForm
    Write-Output ''
    # The window's "plan" is now just the three things it is allowed to decide.
    # Collections, scopes and the executor are the server's, worked out from the
    # environment files it holds and this machine does not.
    Write-Output ("  package              : {0}" -f $plan.PackageName)
    Write-Output ("  environment          : {0}" -f $plan.Environment)
    Write-Output ("  audit link (RFC)     : {0}" -f $plan.Rfc)
    Write-Output ("  carries a person?    : {0}" -f $(if ($plan.PSObject.Properties['Requester']) { 'YES - WRONG' } else { 'no' }))

    # The confirmation texts, built the way the buttons build them - from the
    # FORM plan only, because the packager side has no environment file. Each
    # one must come out without an error; this is what a packager reads before
    # pressing Yes on Integrate, Update content and Remove.
    Write-Output ''
    Write-Output '  confirmation prompts (from the form plan, no server):'
    foreach ($mode in @('Integrate', 'RefreshContent', 'Remove')) {
        $text = Format-PlanEffect -Plan $plan -Mode $mode -RemoveContent:($mode -eq 'Remove')
        $first = (@($text -split "`r`n"))[0]
        Write-Output ("    {0,-15} {1} line(s) - {2}" -f $mode, @($text -split "`r`n").Count, $first)
    }

    & $testIntegrateClick

    # The rest of this self-test plays BOTH sides - it runs the engine to make a
    # result for the window to read back. That is server code, which a packager
    # machine deliberately does not have, so it only runs where the server half
    # is present: in the source tree, or on the SCCM machine.
    $serverEngine = Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine\AudiSwIntegration.ps1'
    if (-not (Test-Path -LiteralPath $serverEngine)) {
        Write-Output ''
        Write-Output '  server half not present - this is a client-only install, which is correct.'
        Write-Output '  Everything the window itself does has been checked above.'
        return
    }
    . $serverEngine

    # The server builds the REAL plan - from the environment files it holds -
    # which is exactly what the collector does with a job file off the share.
    $serverPlan = Get-AudiIntegrationPlan -PackageName $plan.PackageName -EnvironmentCode $plan.Environment `
                      -Rfc $plan.Rfc -LocalizedName $ui.txtNameEN.Text.Trim() `
                      -LocalizedDescription $ui.txtDescEN.Text.Trim() `
                      -PartOverride (Get-PackageDetail) `
                      -BrandingKey $ui.txtBranding.Text.Trim() `
                      -OperatingSystemKeys (Get-OperatingSystemTicks)
    Write-Output ''
    Write-Output ("  server-side plan     : {0} collections, executed as {1}" -f `
                  @($serverPlan.Collections).Count, $serverPlan.Executor)
    $plan = $serverPlan

    $run = Invoke-AudiSwIntegration -Plan $plan -DryRun
    Write-Output ''
    Write-Output ("  dry run              : {0}" -f $run.Message)
    foreach ($s in $run.Steps) { Write-Output ("    {0,-14} {1,-7} {2}" -f $s.Step, $(if ($s.Ok) { 'OK' } else { 'FAILED' }), $s.Message) }
    Write-Output ''
    Write-Output ("  log folder           : {0}" -f (Split-Path -Parent $run.LogPath))

    # --- flow 2: the window submits a file, it does not connect anywhere
    Write-Output ''
    Write-Output ("  drop folder          : {0}" -f $(if ($DropFolder) { $DropFolder } else { 'not set - DropFolder in Packager\Settings.txt' }))
    Write-Output ("  result timeout       : {0} min" -f $defaults.Runtime.ResultTimeoutMinutes)

    # submitted into a temporary folder, so the self test needs no share
    $sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("AudiClientSelfTest_{0}" -f ([guid]::NewGuid().ToString('N')))
    try {
        $doc = New-AudiSwJobFile -PackageName $ui.txtPackage.Text.Trim() -EnvironmentCode 'INA' `
                                 -Action 'Integrate' -Rfc $ui.txtRfc.Text.Trim() `
                                 -NameEn $ui.txtNameEN.Text.Trim() -NameDe $ui.txtNameDE.Text.Trim() `
                                 -DescriptionEn $ui.txtDescEN.Text.Trim() -DescriptionDe $ui.txtDescDE.Text.Trim() `
                                 -Detail (Get-PackageDetail) -DryRun
        $sub   = Submit-AudiSwJob -DropFolder $sandbox -Job $doc
        $check = Test-AudiConfigFile -Path $sub.Path -SchemaPath (Join-Path (Get-AudiConfigRoot) 'Environment.xsd')
        Write-Output ''
        Write-Output ("  job file written     : {0}" -f (Split-Path -Leaf $sub.Path))
        Write-Output ("  valid against schema : {0}" -f $(if ($check.Ok) { 'yes' } else { 'NO - ' + ($check.Errors -join '; ') }))
        Write-Output ("  requester in file    : {0}" -f $(if ($doc.Job.HasAttribute('requester')) { 'PRESENT - WRONG' } else { 'none - no person is sent to the server' }))
        Write-Output ("  no result yet, says  : {0}" -f (Wait-AudiSwJobResult -Submission $sub -TimeoutMinutes 0 -PollSeconds 1).Message)

        # --- and the result is still there after the window has been closed.
        # Stand in for the collector by writing the result it would have written,
        # then ask the window's own lookup for it.
        $null = Write-AudiSwJobResult -Path $sub.ResultPath -Executor $plan.Executor -Result $run -Job ([pscustomobject]@{
            JobId = $sub.JobId; Environment = 'INA'; PackageName = $ui.txtPackage.Text.Trim(); Rfc = $ui.txtRfc.Text.Trim() })

        $DropFolder = $sandbox          # Get-ActiveDropFolder honours this
        Show-PreviousRuns
        Write-Output ''
        Write-Output ("  reopening the tool   : {0}" -f $ui.txtHistory.Text)
        Write-Output ("  steps read back      : {0}" -f @($ui.lstResults.ItemsSource).Count)
    }
    finally { if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue } }
    Write-Output ''
    return
}

$null = $window.ShowDialog()
