# ==============================================================================
#  Audi SCCM Integration Tool - packager window
# ==============================================================================
#  Run:   .\Client\Start-AudiSwClient.ps1
#
#  Two buttons, deliberately different:
#
#    Preview on this PC   runs the whole plan locally through the dry-run
#                         provider. Nothing leaves this machine. Needs no SCCM,
#                         no server and no drop folder - use it to test.
#
#    Integrate / Remove   write a job FILE into the environment's drop folder
#                         and then wait for the server's result file. The
#                         window never connects to SCCM and holds no SCCM
#                         rights. It also states no identity: the server takes
#                         the requester from the job file's NTFS owner, which
#                         the packager cannot forge.
#
#  The window never freezes. The old tool ran everything on the interface thread,
#  including a thirty-second wait per deployment. Here the work runs in a
#  background runspace and the window polls a shared table for progress - the
#  same arrangement used in Package Builder.
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
    [switch]$SelfTest
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
# Client\Config is a COPY of Server\Engine\Config. Sync-AudiSwClient.ps1 keeps
# them identical - the server's is the master, and nothing here is edited by
# hand.
. (Join-Path $PSScriptRoot 'Lib\Load.ps1')

# ------------------------------------------------------------- the drop folder
#
# THE ONE THING A PACKAGER MACHINE CONFIGURES.
#
# A single root, shared with the server. The window creates <ENV>\<Package>\New
# underneath it the first time each is needed, and works out the environment
# from the package name - so there is one path to set and nothing else.
#
#   1. -DropFolder on the command line     (testing, shows a SANDBOX badge)
#   2. DropFolder.txt beside this script   (the normal install)
#   3. Transport/@dropFolder in the environment file (single-machine install)
$SandboxDrop = [bool]$DropFolder
if (-not $DropFolder) {
    $dropPointer = Join-Path $PSScriptRoot 'DropFolder.txt'
    if (Test-Path -LiteralPath $dropPointer) {
        $DropFolder = (@(Get-Content -LiteralPath $dropPointer |
                         Where-Object { $_.Trim() -and $_.Trim() -notlike '#*' } |
                         Select-Object -First 1) -join '').Trim()
    }
}

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

function Set-Status { param([string]$Text, [string]$Colour = '#FF16242A')
    $ui.txtStatus.Text = $Text
    $ui.txtStatus.Foreground = $Colour
}

function Show-Warning { param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { $ui.brdWarning.Visibility = 'Collapsed'; return }
    $ui.txtWarning.Text = $Text
    $ui.brdWarning.Visibility = 'Visible'
}

function Set-Busy { param([bool]$Busy)
    foreach ($b in 'btnHistory','btnIntegrate','btnModify','btnRemove','btnBrowse','btnRead') { $ui[$b].IsEnabled = -not $Busy }
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
        SoftIdent    = $ui.txtSoftIdent.Text.Trim()
    }
}

# ---------------------------------------------------------------- populate once
# WHERE THE ENVIRONMENT LIST COMES FROM, NOW THAT THIS MACHINE HAS NO
# ENVIRONMENT FILES.
#
# Environment files describe SCCM topology - collections, security scopes,
# console folders, distribution point groups. That is the server's business and
# has no place on a packager PC, so the window works the list out from two
# things it can see:
#
#   - folders already in the drop root: environments this share is used for
#   - the code at the front of the package name being worked on
#
# The list therefore fills itself in as the tool is used, and a new environment
# appears the moment somebody types a package named for it. Whether that
# environment really exists is the SERVER's decision - it has the files - and it
# refuses the job if it does not.
function Update-EnvironmentList {
    $known = New-Object System.Collections.Generic.List[string]
    if ($DropFolder -and (Test-Path -LiteralPath $DropFolder)) {
        foreach ($d in @(Get-ChildItem -LiteralPath $DropFolder -Directory -ErrorAction SilentlyContinue)) {
            if (-not $known.Contains($d.Name)) { $known.Add($d.Name) | Out-Null }
        }
    }
    $fromPackage = Get-PackageSiteCode
    if ($fromPackage -and -not $known.Contains($fromPackage)) { $known.Add($fromPackage) | Out-Null }

    $selected = [string]$ui.cboEnvironment.SelectedItem
    $ui.cboEnvironment.Items.Clear()
    foreach ($code in @($known | Sort-Object)) { $null = $ui.cboEnvironment.Items.Add($code) }

    # The package decides. It carries the environment as its first part, so a
    # packager never has to choose and cannot choose wrongly by accident.
    if ($fromPackage -and $ui.cboEnvironment.Items.Contains($fromPackage)) {
        $ui.cboEnvironment.SelectedItem = $fromPackage
    }
    elseif ($selected -and $ui.cboEnvironment.Items.Contains($selected)) {
        $ui.cboEnvironment.SelectedItem = $selected
    }
    elseif ($ui.cboEnvironment.Items.Count -gt 0) { $ui.cboEnvironment.SelectedIndex = 0 }
}

if ($EnvironmentCode) { $null = $ui.cboEnvironment.Items.Add($EnvironmentCode); $ui.cboEnvironment.SelectedItem = $EnvironmentCode }

# Operating systems are deliberately NOT a field either. The old tool put OS
# requirement rules on the deployment type; this tool does not do that yet, so a
# checkbox here would have changed nothing in SCCM. The list stays in
# Defaults.xml for when that step is built.
#
# Install minutes is deliberately NOT a field. It came from Defaults.xml and was
# never read back, so showing it invited a packager to change something that had
# no effect. The engine takes it from Application/@estimatedInstallMinutes.

# ------------------------------------------------------------- sandbox badge
# A test run must never be mistakable for a real one.
# Only for -DropFolder on the command line. A path from DropFolder.txt is the
# normal install, not a test rig, and badging it SANDBOX would train people to
# ignore the badge on the day it means something.
if ($SandboxDrop) {
    $ui.txtMode.Text = 'SANDBOX'
    $ui.brdMode.ToolTip = "Jobs go to $DropFolder instead of the configured drop folder."
    $ui.brdMode.Visibility = 'Visible'
}

function Get-ActiveDropFolder {
    # One root for every environment - see DropFolder.txt. The per-environment
    # and per-package folders underneath it are worked out from the package name
    # when the job is written.
    return $DropFolder
}

# ------------------------------------------------------- environment awareness
#
# The package name carries the environment as its first part - INA_ETAS_INCA_...
# belongs in INA. So the package decides, and the dropdown follows it. If a name
# has no recognisable prefix the packager chooses, and if the two disagree the
# window says so and refuses to submit. Nothing is ever silently renamed: that
# is what corrupted ADO_ADOBE_Reader into INA_INABE_Reader in the old tool.

function Get-PackageSiteCode {
    <#  The environment a package name is asking for, or $null if it has none
        the tool recognises.  #>
    $package = $ui.txtPackage.Text.Trim()
    if (-not $package) { return $null }
    try { $site = (Split-AudiPackageName -PackageName $package).Site } catch { return $null }

    # Returned whether or not it is already in the dropdown. It used to be
    # checked against the list of environments this machine had files for, but
    # there are none here now - and the list is built FROM this, so checking
    # against it would be circular. Whether the environment really exists is the
    # server's decision; it has the files and refuses the job if it does not.
    return $site
}

function Sync-EnvironmentToPackage {
    Update-EnvironmentList
    <#  Points the dropdown at the environment the package name asks for.
        Called after a package is read or its name is typed.  #>
    $site = Get-PackageSiteCode
    if ($site -and $ui.cboEnvironment.SelectedItem -ne $site) { $ui.cboEnvironment.SelectedItem = $site }
    Update-EnvironmentNotice
    Show-PreviousRuns
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
    $package = $ui.txtPackage.Text.Trim()
    $code    = [string]$ui.cboEnvironment.SelectedItem
    if (-not $package -or -not $code) { return }

    try {
        $drop = Get-ActiveDropFolder
        if ([string]::IsNullOrWhiteSpace($drop) -or -not (Test-Path -LiteralPath $drop)) { return }
        $runs = @(Get-AudiSwJobHistory -DropFolder $drop -EnvironmentCode $code -PackageName $package)
    }
    catch { return }   # this is a convenience; it must never break the window

    if ($runs.Count -eq 0) {
        if (-not $state.Running) {
            $ui.txtHistory.Text    = 'No earlier run of this package in this environment.'
            $ui.txtHistory.ToolTip = $null
        }
        return
    }

    $last    = $runs[0]
    $running = ($last.Outcome -eq 'Running')

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

    $ui.txtHistory.Text = if ($running) {
        'IN PROGRESS on the server   -   {0}   (job {1}, started {2})' -f `
            $last.Message, $last.JobId, $last.Completed.ToString('HH:mm')
    } else {
        '{0}   {1}{2}   -   {3}   (job {4}){5}' -f `
            $last.Completed.ToString('dd.MM.yyyy HH:mm'),
            $(if ($last.DryRun) { 'dry run, ' } else { '' }),
            $last.Outcome.ToLowerInvariant(),
            $last.Message,
            $last.JobId,
            $(if ($runs.Count -gt 1) { '    +{0} earlier' -f ($runs.Count - 1) } else { '' })
    }

    $ui.txtHistory.ToolTip = ($runs | ForEach-Object {
        '{0}  {1,-9}  {2}  job {3}' -f $_.Completed.ToString('dd.MM.yyyy HH:mm'), $_.Outcome, $_.Message, $_.JobId
    }) -join "`r`n"

    # Tabs are selected BY NAME, never by position. Inserting the Modify tab in
    # the middle shifted every index by one and quietly sent runs to the wrong
    # tab - which is exactly what happened.
    if ($running -and -not $ui.tabResult.IsSelected) { $ui.tabResult.IsSelected = $true }
}

function Test-EnvironmentMatch {
    <#  Returns the mismatch message, or '' when there is nothing wrong.  #>
    $package = $ui.txtPackage.Text.Trim()
    if (-not $package) { return '' }

    $site = $null
    try { $site = (Split-AudiPackageName -PackageName $package).Site } catch { return '' }
    $code = [string]$ui.cboEnvironment.SelectedItem
    if (-not $code -or -not $site) { return '' }

    # a prefix the tool does not know is not a mismatch - the packager picks
    if (-not $ui.cboEnvironment.Items.Contains($site)) { return '' }
    if ($site -eq $code) { return '' }

    return ("This package is named for {0} but {1} is selected. Rename the package for {1}, or select {0}. " +
            "The package will not be submitted while these disagree.") -f $site, $code
}

function Update-EnvironmentNotice {
    $code = [string]$ui.cboEnvironment.SelectedItem
    if (-not $code) { return }

    # a mismatch outranks anything else the strip might say
    $mismatch = Test-EnvironmentMatch
    if ($mismatch) { Show-Warning $mismatch; return }

    # The "unverified environment" warning used to be raised here by reading the
    # environment file. The server still refuses a real run against an
    # unverified environment - that check has not been weakened, it has simply
    # moved to the side that owns the files. Warning here as well would mean
    # keeping a copy of them on every packager PC to repeat a message the server
    # already gives.
    Show-Warning ''
}

# ----------------------------------------------------------------- derive names
function Update-DerivedFields {
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
    <#  The two rules SCCM will be given, shown as they will be sent.

        There is no "detection key" field to keep in step with the branding key,
        because the branding key IS rule 1. Rule 2 is the SoftIdent. Showing the
        result of both instead of asking for it again means the two can never
        disagree, and a mistyped SoftIdent is visible here rather than on a
        client three days later.  #>
    $branding = $ui.txtBranding.Text.Trim()
    $ui.txtRule1.Text = if ($branding) {
        "1.  HKLM\{0}{1}\{2}={3}" -f $defaults.Naming.brandingRegistryRoot, $branding,
                                     $defaults.Detection.valueName, $ui.txtRevision.Text.Trim()
    } else { '1.  waiting for a package name' }

    $soft = $ui.txtSoftIdent.Text.Trim()
    if (-not $soft) {
        $ui.txtRule2.Text = '2.  none - this package has no SoftIdent, so rule 1 alone detects it'
        return
    }
    try { $parts = Split-AudiSoftIdent -SoftIdent $soft } catch { $parts = $null }
    $ui.txtRule2.Text = if ($parts) {
        if ($parts.ValueName) { "2.  {0}\{1}\{2}={3}" -f $parts.Hive, $parts.Key, $parts.ValueName, $parts.Value }
        else                  { "2.  {0}\{1} exists" -f $parts.Hive, $parts.Key }
    } else {
        '2.  the SoftIdent is not in a shape the tool recognises - rule 1 alone will be used'
    }
}

# ------------------------------------------------------------- read the package
function Read-PackageFolder { param([string]$Path)
    if (-not $Path) { return }
    $ui.tabPackage.IsSelected = $true
    Set-Status "Reading $Path ..."
    try {
        $detail = Read-AudiPackageDetail -PackagePath $Path

        if ($ui.txtPackagePath.Text -ne $Path) { $ui.txtPackagePath.Text = $Path }
        if (-not $ui.txtPackage.Text.Trim()) { $ui.txtPackage.Text = Split-Path -Leaf $Path }
        Update-DerivedFields
        Sync-EnvironmentToPackage

        # The deployment script is the authority for everything except the
        # description, which comes from the request document. Read-AudiPackageDetail
        # has already applied the short-then-detailed preference.
        $map = @{ ApplicationDescriptionEN = 'txtDescEN'
                  ApplicationDescriptionDE = 'txtDescDE'
                  OrderNumber              = 'txtRfc'
                  SoftIdent                = 'txtSoftIdent' }
        foreach ($key in $map.Keys) {
            if ($detail.Fields.Contains($key) -and -not $ui[$map[$key]].Text) { $ui[$map[$key]].Text = $detail.Fields[$key] }
        }
        # SoftIdent is read-only, so refresh it even if a previous package left one
        if ($detail.Fields.Contains('SoftIdent')) { $ui.txtSoftIdent.Text = $detail.Fields['SoftIdent'] }

        # a sensible starting point rather than a blank form
        if (-not $ui.txtNameEN.Text -and $ui.txtPublisher.Text) {
            $ui.txtNameEN.Text = "$($ui.txtPublisher.Text) - $($ui.txtProduct.Text) - $($ui.txtVersion.Text)"
        }
        if (-not $ui.txtNameDE.Text) { $ui.txtNameDE.Text = $ui.txtNameEN.Text }

        # Where every value came from, on the status line and in full on its
        # tooltip. The card itself stays uncluttered.
        $script   = if ($detail.ScriptPath)   { "$($detail.Generation) $(Split-Path -Leaf $detail.ScriptPath)" } else { 'no script found' }
        $document = if ($detail.DocumentPath) { Split-Path -Leaf $detail.DocumentPath } else { 'no document found' }

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

        $problems = @($detail.Notes)
        if ($problems.Count -gt 0) {
            Set-Status ($problems -join '  ') '#FF8A5300'
        }
        elseif ($detail.Fields.Count -eq 0) {
            Set-Status 'Nothing could be read from this folder - fill the fields in by hand.' '#FF8A5300'
        }
        else {
            Set-Status ("Read {0} value(s) from {1} and the request document. Hover this line to see where each one came from." -f $detail.Fields.Count, $script)
        }
    }
    catch { Set-Status "Could not read the package: $($_.Exception.Message)" '#FFB3261E' }
}

# ------------------------------------------------------------------- build plan
function New-PlanFromForm {
    $package = $ui.txtPackage.Text.Trim()
    if (-not $package) { throw 'Enter a package name first.' }
    $code = [string]$ui.cboEnvironment.SelectedItem
    # The package name carries the environment as its first part, so the PACKAGE
    # decides and the dropdown only confirms it. Falling back to the package's
    # own code means the window works before the list has been refreshed, and
    # that no job can be submitted whose environment disagrees with the name of
    # the package it is for.
    if (-not $code) { $code = Get-PackageSiteCode }
    if (-not $code) {
        throw "Cannot tell which environment '$package' belongs to. A package name starts with its site code - for example INA_ETAS_INCA_x64_7.5.7-0001_MUL."
    }

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
    $rows = @($Result.Steps | ForEach-Object {
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
    $ui.prgRun.Value = @($Result.Steps | Where-Object { $_.Ok }).Count

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

    # Show the Result tab AS THE RUN STARTS, not when it finishes. A packager who
    # presses Integrate wants to watch it happen, and anyone looking over their
    # shoulder should see the same thing without being told which tab to open.
    #
    # -StayOnTab is for Inspect, which is not a run: its answer belongs on the
    # Modify tab, and switching away and back would just make the window flicker.
    if (-not $StayOnTab) { $ui.tabResult.IsSelected = $true }
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

        if ($state.Error) { Set-Status "Failed: $($state.Error)" '#FFB3261E'; $ui.prgRun.Value = 0; return }

        # An Inspect answer fills the Modify tab rather than the Result grid -
        # it is a picture of the site, not a run.
        if ((Test-HasValue $state.Result 'State') -and @($state.Result.State).Count -gt 0) {
            Show-PackageState $state.Result.State
            if (Test-HasValue $state.Result 'Settings') { Show-PackageSettings $state.Result.Settings }
            $ui.txtModifyState.Text = $state.Result.Message
            $ui.tabModify.IsSelected = $true
            Set-Status $state.Result.Message '#FF00707D'
            return
        }

        Show-RunOutcome $state.Result $state.Note
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
# The window writes a job file into the environment's drop folder and waits for
# the result file. It never connects to the SCCM server, holds no SCCM rights
# and states no identity: the server takes the requester from the file's owner.
function Start-Run { param([string]$Mode)   # Integrate | Modify | Remove

    # The package name and the chosen environment must agree. Refuse here, in
    # front of the packager, rather than letting the server reject it minutes
    # later.
    $mismatch = Test-EnvironmentMatch
    if ($mismatch) {
        Show-Warning $mismatch
        Set-Status $mismatch '#FFB3261E'
        [void][System.Windows.MessageBox]::Show($mismatch, 'Wrong environment', 'OK', 'Error')
        return
    }

    try   { $plan = New-PlanFromForm }      # validates the form before queuing
    catch { Set-Status $_.Exception.Message '#FF8A5300'; return }

    $code = [string]$ui.cboEnvironment.SelectedItem
    $drop = Get-ActiveDropFolder
    if ([string]::IsNullOrWhiteSpace($drop)) {
        Set-Status ("No drop folder is set. Put the UNC path of the shared drop folder in {0}." -f `
                    (Join-Path $PSScriptRoot 'DropFolder.txt')) '#FFB3261E'
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
    $blankDetail = -not ($ui.txtNameEN.Text.Trim() -or $ui.txtDescEN.Text.Trim())
    if ($Mode -eq 'Integrate' -and $blankDetail) {
        Set-Status 'Read the package folder first - Integrate needs its script and instruction document.' '#FF8A5300'
        $ui.tabPackage.IsSelected = $true
        $ui.txtPackagePath.Focus() | Out-Null
        return
    }
    $detailNote = $(if ($Mode -eq 'Modify' -and $blankDetail) {
        "`r`n`r`nNo package details are loaded, so the name and descriptions" +
        "`r`nalready in SCCM are left as they are. Collections and settings" +
        "`r`nare still reconciled."
    } else { '' })

    $dryRun = [bool]$ui.chkDryRun.IsChecked
    $verb   = switch ($Mode) { 'Remove' { 'REMOVE' } 'Modify' { 'MODIFY' } default { 'INTEGRATE' } }
    $what   = if ($dryRun) { "The server will rehearse this and change nothing." }
              else         { "The server will make real changes in $code." }
    $answer = [System.Windows.MessageBox]::Show(
        ("$verb '$($plan.PackageName)' in $code" + "?`r`n`r`n" + $what + $detailNote +
         "`r`n`r`nThe job goes to:`r`n$drop`r`n`r`n" +
         "The work is carried out by the server's service account. Your name is`r`n" +
         "not sent and is not recorded on the server. RFC: $rfcShown."),
        'Confirm', 'YesNo', $(if ($dryRun) { 'Question' } else { 'Warning' }))
    if ($answer -ne 'Yes') { Set-Status 'Cancelled.'; return }

    $state.Note = ''
    Set-Status "Submitting to $code ..."
    Start-Worker -Steps $(switch ($Mode) { 'Remove' { 4 } 'Modify' { 9 } default { 8 } }) -Arguments @{
        Action        = $Mode
        DropFolder    = $drop
        Timeout       = $defaults.Runtime.ResultTimeoutMinutes
        PackageName   = $plan.PackageName
        Environment   = $code
        Rfc           = $ui.txtRfc.Text.Trim()
        NameEn        = $ui.txtNameEN.Text.Trim()
        NameDe        = $ui.txtNameDE.Text.Trim()
        DescriptionEn = $ui.txtDescEN.Text.Trim()
        DescriptionDe = $ui.txtDescDE.Text.Trim()
        Detail        = Get-PackageDetail
        # The Windows versions the instruction document ticked. Without these in
        # the job file the server requires every platform it knows about, which
        # is not what the document asked for.
        OperatingSystems = $script:DocOperatingSystems
        DryRun        = $dryRun
    } -Body {
        try {
            . (Join-Path $toolRoot 'Load.ps1')

            $wantsDryRun = [bool]$jobArgs.DryRun
            $state.Step = 'Writing the job file...'
            $doc = New-AudiSwJobFile -PackageName $jobArgs.PackageName -EnvironmentCode $jobArgs.Environment `
                                     -Action $jobArgs.Action -Rfc $jobArgs.Rfc `
                                     -NameEn $jobArgs.NameEn -NameDe $jobArgs.NameDe `
                                     -DescriptionEn $jobArgs.DescriptionEn -DescriptionDe $jobArgs.DescriptionDe `
                                     -Detail $jobArgs.Detail -OperatingSystems $jobArgs.OperatingSystems `
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
            $state.Note = "  |  job $($submission.JobId)"
        }
        catch { $state.Error = $_.Exception.Message }
        finally { $state.Waiting = $false; $state.Done = $true; $state.Running = $false }
    }
}

# --------------------------------------------------------------------- handlers
$ui.cboEnvironment.Add_SelectionChanged({ Update-EnvironmentNotice })
$ui.txtPackage.Add_LostFocus({ Update-DerivedFields; Sync-EnvironmentToPackage })

# The detection read-out follows whatever is on screen, so an edit to the
# branding key, the revision or the SoftIdent is reflected in the rules SCCM
# will get before anything is submitted.
foreach ($field in 'txtBranding','txtRevision','txtSoftIdent') {
    $ui[$field].Add_TextChanged({ Show-DetectionRules })
}

$ui.btnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the package folder'
    if ($ui.txtPackagePath.Text -and (Test-Path -LiteralPath $ui.txtPackagePath.Text)) { $dialog.SelectedPath = $ui.txtPackagePath.Text }
    if ($dialog.ShowDialog() -eq 'OK') {
        $ui.txtPackagePath.Text = $dialog.SelectedPath
        Read-PackageFolder -Path $dialog.SelectedPath
    }
})

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
          [object[]]$SettingChanges = @(), [string]$Description)

    $code = [string]$ui.cboEnvironment.SelectedItem
    $drop = Get-ActiveDropFolder
    if ([string]::IsNullOrWhiteSpace($drop)) {
        Set-Status "No drop folder is set - see DropFolder.txt." '#FFB3261E'; return
    }

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
    } -Body {
        try {
            . (Join-Path $toolRoot 'Load.ps1')
            $state.Step = 'Writing the job file...'
            $doc = New-AudiSwJobFile -PackageName $jobArgs.PackageName -EnvironmentCode $jobArgs.Environment `
                                     -Action $jobArgs.Action -Rfc $jobArgs.Rfc -Detail $jobArgs.Detail `
                                     -AddCollections $jobArgs.Add -RemoveCollections $jobArgs.Remove `
                                     -SettingChanges $jobArgs.SettingChanges

            $submission = Submit-AudiSwJob -DropFolder $jobArgs.DropFolder -Job $doc
            $state.JobId = $submission.JobId
            $state.Waiting = $true
            $state.Step = "Queued in $(Split-Path -Parent $submission.Path). Waiting for the server..."

            $state.Result = Wait-AudiSwJobResult -Submission $submission `
                                -TimeoutMinutes $jobArgs.Timeout -PollSeconds 5
            $state.Note = "  |  job $($submission.JobId)"
        }
        catch { $state.Error = $_.Exception.Message }
        finally { $state.Waiting = $false; $state.Done = $true; $state.Running = $false }
    }
}

function Show-PackageState { param($State)
    <#  Turns what the server found into rows a person can act on.

        Three cases, and the row says which:
          wanted, not there   -> Add     (tickable)
          there, not wanted   -> Remove  (tickable)
          wanted and there    -> shown, nothing to do  #>
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($collection in @($State)) {
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

    $ui.lstModify.ItemsSource = $rows.ToArray()
    $actionable = @($rows | Where-Object { $_.Actionable }).Count
    $ui.btnApplyChanges.IsEnabled = ($actionable -gt 0)
    $ui.txtModifyHint.Text = if ($actionable -eq 0) {
        'Nothing on the site for this package yet.'
    } else {
        "Tick what you want changed, then Apply. Nothing is touched unless it is ticked."
    }
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

function Start-Inspect {
    $mismatch = Test-EnvironmentMatch
    if ($mismatch) { Set-Status $mismatch '#FFB3261E'; return }
    try   { $plan = New-PlanFromForm } catch { Set-Status $_.Exception.Message '#FF8A5300'; return }
    Submit-AudiAction -Action 'Inspect' -Plan $plan -Description 'Reading the site'
}

function Start-ApplyChanges {
    $rows     = @($ui.lstModify.ItemsSource | Where-Object { $_.Selected -and $_.Action -ne '-' })
    $settings = @(Get-ChangedSettings)

    if ($rows.Count -eq 0 -and $settings.Count -eq 0) {
        Set-Status 'Nothing to apply. Change a setting, or tick a collection row.' '#FF8A5300'; return
    }

    $add    = @($rows | Where-Object { $_.Action -eq 'Add' }    | ForEach-Object { $_.Name })
    $remove = @($rows | Where-Object { $_.Action -eq 'Remove' } | ForEach-Object { $_.Name })

    # Settings are edited in place, so unlike a ticked row there is no separate
    # confirming gesture. Show the before and after and ask once.
    if ($settings.Count -gt 0) {
        $lines = @($settings | ForEach-Object { "{0}:`r`n    was  {1}`r`n    now  {2}" -f $_.Label, $(if ($_.From) { $_.From } else { '(empty)' }), $(if ($_.To) { $_.To } else { '(empty)' }) })
        $answer = [System.Windows.MessageBox]::Show(
            ("This changes {0} setting(s) on {1} in {2}:`r`n`r`n{3}`r`n`r`nContinue?" -f `
                $settings.Count, $ui.txtPackage.Text, [string]$ui.cboEnvironment.SelectedItem, ($lines -join "`r`n`r`n")),
            'Change settings', 'YesNo', 'Question')
        if ($answer -ne 'Yes') { Set-Status 'Nothing was submitted.'; return }
    }

    # Removing a collection takes its deployment with it. Say so before doing it,
    # rather than after - this is the one action here that destroys something.
    if ($remove.Count -gt 0) {
        $answer = [System.Windows.MessageBox]::Show(
            ("This removes {0} collection(s) and their deployments from {1}:`r`n`r`n{2}`r`n`r`nThe application itself is not touched. Continue?" -f `
                $remove.Count, [string]$ui.cboEnvironment.SelectedItem, ($remove -join "`r`n")),
            'Remove collections', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { Set-Status 'Nothing was submitted.'; return }
    }

    try   { $plan = New-PlanFromForm } catch { Set-Status $_.Exception.Message '#FF8A5300'; return }
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

$ui.btnInspect.Add_Click({ Start-Inspect })
$ui.btnApplyChanges.Add_Click({ Start-ApplyChanges })

function Show-PackageHistory {
    <#  Everything this tool has done to this package, in the Result grid.

        Reads the drop folder's own result files - the same ones the window
        waits on - so it works after the window has been closed and reopened,
        and needs nothing from SCCM.  #>
    $package = $ui.txtPackage.Text.Trim()
    if (-not $package) { Set-Status 'Enter a package name first.' '#FF8A5300'; $ui.txtPackage.Focus() | Out-Null; return }

    $code = [string]$ui.cboEnvironment.SelectedItem
    $drop = Get-ActiveDropFolder
    if ([string]::IsNullOrWhiteSpace($drop)) { Set-Status "No drop folder is set - see DropFolder.txt." '#FFB3261E'; return }

    try   { $runs = @(Get-AudiSwJobHistory -DropFolder $drop -EnvironmentCode $code -PackageName $package) }
    catch { Set-Status "Could not read the history: $($_.Exception.Message)" '#FFB3261E'; return }

    $ui.tabResult.IsSelected = $true
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
            Message = ("{0}{1} | RFC {2} | job {3} | {4}" -f `
                        $run.Action, $(if ($run.DryRun) { ' (dry run)' } else { '' }),
                        $(if ($run.Rfc) { $run.Rfc } else { 'none' }), $run.JobId, $run.Message)
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

$ui.btnHistory.Add_Click({ Show-PackageHistory })
$ui.btnIntegrate.Add_Click({ Start-Run -Mode 'Integrate' })
$ui.btnModify.Add_Click({ Start-Run -Mode 'Modify' })
$ui.btnRemove.Add_Click({ Start-Run -Mode 'Remove' })

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
Update-EnvironmentNotice
Set-Status 'Ready. Preview runs here; Integrate and Remove hand the job to the server. Dry run is on, so nothing will be changed until you turn it off.'

if ($SelfTest) {
    # Drives the same functions the buttons call, synchronously, so the window's
    # own wiring is verified without a screen.
    Write-Output ''
    Write-Output 'Packager window - self test'
    Write-Output ''
    Write-Output ("  environments offered : {0}" -f (@($ui.cboEnvironment.Items) -join ', '))
    Write-Output ("  detected environment : {0}" -f $ui.cboEnvironment.SelectedItem)

    # ---- read a REAL package and check every field the window shows is filled
    Write-Output ''
    $sampleRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("AudiSelfTest_{0}" -f ([guid]::NewGuid().ToString('N')))
    try {
        $builder = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tests\New-AudiSwSamplePackage.ps1'
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
            'SoftIdent'        = 'txtSoftIdent'
            'Name (EN)'        = 'txtNameEN'
            'Name (DE)'        = 'txtNameDE'
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
    }
    finally { if (Test-Path -LiteralPath $sampleRoot) { Remove-Item -LiteralPath $sampleRoot -Recurse -Force -ErrorAction SilentlyContinue } }

    $ui.cboEnvironment.SelectedItem = 'INA'
    $ui.txtPackage.Text = 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0003_MUL'
    Update-DerivedFields
    Write-Output ''
    Write-Output ("  publisher/product    : {0} / {1}" -f $ui.txtPublisher.Text, $ui.txtProduct.Text)
    Write-Output ("  branding key         : {0}" -f $ui.txtBranding.Text)
    Write-Output ("  detection rules      : {0} | {1}" -f $ui.txtRule1.Text, $ui.txtRule2.Text)

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

    # The rest of this self-test plays BOTH sides - it runs the engine to make a
    # result for the window to read back. That is server code, which a packager
    # machine deliberately does not have, so it only runs where the server half
    # is present: in the source tree, or on the SCCM machine.
    $serverEngine = Join-Path (Split-Path -Parent $PSScriptRoot) 'Server\Engine\AudiSwIntegration.ps1'
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
                      -SoftIdent $ui.txtSoftIdent.Text.Trim() `
                      -OperatingSystemKeys $script:DocOperatingSystems
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
    Write-Output ("  drop folder          : {0}" -f $(if ($DropFolder) { $DropFolder } else { 'not set - see DropFolder.txt' }))
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
