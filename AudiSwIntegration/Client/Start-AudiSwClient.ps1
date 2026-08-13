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

    # exercises the window's own code paths and exits, without showing it
    [switch]$SelfTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

$ToolRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Server\Engine'
. (Join-Path $ToolRoot 'AudiSwIntegration.ps1')

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
    foreach ($b in 'btnPreview','btnIntegrate','btnModify','btnRemove','btnBrowse','btnRead') { $ui[$b].IsEnabled = -not $Busy }
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
foreach ($code in (Get-AudiEnvironmentCode)) { $null = $ui.cboEnvironment.Items.Add($code) }

$detected = if ($EnvironmentCode) { $EnvironmentCode } else { Resolve-AudiEnvironmentCode }
if ($detected -and $ui.cboEnvironment.Items.Contains($detected)) { $ui.cboEnvironment.SelectedItem = $detected }
elseif ($ui.cboEnvironment.Items.Count -gt 0) { $ui.cboEnvironment.SelectedIndex = 0 }

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
if ($DropFolder) {
    $ui.txtMode.Text = 'SANDBOX'
    $ui.brdMode.ToolTip = "Jobs go to $DropFolder instead of the environment's drop folder."
    $ui.brdMode.Visibility = 'Visible'
}

function Get-ActiveDropFolder { param($Environment)
    if ($DropFolder) { return $DropFolder }
    return $Environment.Transport.DropFolder
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
    if ($ui.cboEnvironment.Items.Contains($site)) { return $site }
    return $null
}

function Sync-EnvironmentToPackage {
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
        $environment = Get-AudiEnvironment -Code $code
        $drop = Get-ActiveDropFolder -Environment $environment
        if ([string]::IsNullOrWhiteSpace($drop) -or -not (Test-Path -LiteralPath $drop)) { return }
        $runs = @(Get-AudiSwJobHistory -DropFolder $drop -PackageName $package)
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

    try {
        $env = Get-AudiEnvironment -Code $code
        if (-not $env.Verified) {
            Show-Warning ("Environment {0} is marked unverified - some of its settings were carried over from another environment and still need confirming by Audi. Preview works; a real run is refused." -f $code)
        } else { Show-Warning '' }
    }
    catch { Show-Warning "Environment $code could not be read: $($_.Exception.Message)" }
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
    if (-not $code) { throw 'Choose an environment first.' }

    return Get-AudiIntegrationPlan -PackageName $package -EnvironmentCode $code `
                                   -Rfc $ui.txtRfc.Text.Trim() `
                                   -LocalizedName $ui.txtNameEN.Text.Trim() `
                                   -LocalizedDescription $ui.txtDescEN.Text.Trim() `
                                   -LocalizedNameDe $ui.txtNameDE.Text.Trim() `
                                   -LocalizedDescriptionDe $ui.txtDescDE.Text.Trim() `
                                   -PartOverride (Get-PackageDetail) `
                                   -BrandingKey $ui.txtBranding.Text.Trim() `
                                   -SoftIdent $ui.txtSoftIdent.Text.Trim()
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
    $state.Runspace.SessionStateProxy.SetVariable('toolRoot', $ToolRoot)
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
function Start-Preview {
    try   { $plan = New-PlanFromForm }
    catch { Set-Status $_.Exception.Message '#FF8A5300'; return }

    $state.Note = '  |  preview only - nothing was queued'
    Set-Status 'Preview running on this machine...'
    Start-Worker -Steps 8 -Arguments @{ Plan = $plan } -Body {
        try {
            . (Join-Path $toolRoot 'AudiSwIntegration.ps1')
            $state.Result = Invoke-AudiSwIntegration -Plan $jobArgs.Plan -DryRun `
                                -OnProgress { param($stepName) $state.Step = $stepName }
        }
        catch { $state.Error = $_.Exception.Message }
        finally { $state.Done = $true; $state.Running = $false }
    }
}

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
    try   { $env = Get-AudiEnvironment -Code $code }
    catch { Set-Status $_.Exception.Message '#FFB3261E'; return }

    if ($env.Transport.Mode -ne 'DropFolder' -and -not $DropFolder) {
        Set-Status "Environment $code is set to transport '$($env.Transport.Mode)', which this window does not use." '#FFB3261E'
        return
    }
    $drop = Get-ActiveDropFolder -Environment $env
    if ([string]::IsNullOrWhiteSpace($drop)) {
        Set-Status "Environment $code has no drop folder set. Fill in Transport/@dropFolder in $($env.Path)." '#FFB3261E'
        return
    }

    # With no personal name kept on the server, the RFC is the only record of
    # who asked - so stop here rather than queue an untraceable change.
    $rfc = $ui.txtRfc.Text.Trim()
    if ((Get-AudiDefaults).Audit.RequireRfc -and -not $rfc) {
        Set-Status 'Enter the RFC number first. It is the only record of who requested this change, so the server refuses a job without one.' '#FF8A5300'
        $ui.txtRfc.Focus() | Out-Null
        return
    }
    $rfcShown = if ($rfc) { $rfc } else { 'not given' }

    $dryRun = [bool]$ui.chkDryRun.IsChecked
    $verb   = switch ($Mode) { 'Remove' { 'REMOVE' } 'Modify' { 'MODIFY' } default { 'INTEGRATE' } }
    $what   = if ($dryRun) { "The server will rehearse this and change nothing." }
              else         { "The server will make real changes in $code." }
    $answer = [System.Windows.MessageBox]::Show(
        ("$verb '$($plan.PackageName)' in $code" + "?`r`n`r`n" + $what +
         "`r`n`r`nThe job goes to:`r`n$drop`r`n`r`n" +
         "The work is carried out by the server's service account. Your name is`r`n" +
         "not sent and is not recorded on the server - the RFC number ($rfcShown)`r`n" +
         "is what ties this change back to you."),
        'Confirm', 'YesNo', $(if ($dryRun) { 'Question' } else { 'Warning' }))
    if ($answer -ne 'Yes') { Set-Status 'Cancelled.'; return }

    $state.Note = ''
    Set-Status "Submitting to $code ..."
    Start-Worker -Steps $(switch ($Mode) { 'Remove' { 4 } 'Modify' { 9 } default { 8 } }) -Arguments @{
        Action        = $Mode
        DropFolder    = $drop
        Timeout       = $env.Transport.ResultTimeoutMinutes
        PackageName   = $plan.PackageName
        Environment   = $code
        Rfc           = $ui.txtRfc.Text.Trim()
        NameEn        = $ui.txtNameEN.Text.Trim()
        NameDe        = $ui.txtNameDE.Text.Trim()
        DescriptionEn = $ui.txtDescEN.Text.Trim()
        DescriptionDe = $ui.txtDescDE.Text.Trim()
        Detail        = Get-PackageDetail
        DryRun        = $dryRun
    } -Body {
        try {
            . (Join-Path $toolRoot 'AudiSwIntegration.ps1')

            $wantsDryRun = [bool]$jobArgs.DryRun
            $state.Step = 'Writing the job file...'
            $doc = New-AudiSwJobFile -PackageName $jobArgs.PackageName -EnvironmentCode $jobArgs.Environment `
                                     -Action $jobArgs.Action -Rfc $jobArgs.Rfc `
                                     -NameEn $jobArgs.NameEn -NameDe $jobArgs.NameDe `
                                     -DescriptionEn $jobArgs.DescriptionEn -DescriptionDe $jobArgs.DescriptionDe `
                                     -Detail $jobArgs.Detail -DryRun:$wantsDryRun

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
    try   { $environment = Get-AudiEnvironment -Code $code }
    catch { Set-Status $_.Exception.Message '#FFB3261E'; return }

    $drop = Get-ActiveDropFolder -Environment $environment
    if ([string]::IsNullOrWhiteSpace($drop)) {
        Set-Status "Environment $code has no drop folder set." '#FFB3261E'; return
    }

    $state.Note = ''
    Set-Status "$Description in $code ..."
    # Inspect is not a run - its answer belongs on the Modify tab, so the window
    # stays where it is instead of jumping to Result and back.
    Start-Worker -Steps 1 -StayOnTab:($Action -eq 'Inspect') -Arguments @{
        Action      = $Action
        DropFolder  = $drop
        Timeout     = $environment.Transport.ResultTimeoutMinutes
        PackageName = $Plan.PackageName
        Environment = $code
        Rfc         = $ui.txtRfc.Text.Trim()
        Detail      = Get-PackageDetail
        Add         = $Add
        Remove      = $Remove
        SettingChanges = $SettingChanges
    } -Body {
        try {
            . (Join-Path $toolRoot 'AudiSwIntegration.ps1')
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
                OnSite = 'no'; Deployment = '-'
                Why = 'The environment file asks for it and it is not there.' }) | Out-Null
        }
        elseif (-not $collection.Wanted -and $collection.Exists) {
            $rows.Add([pscustomobject]@{
                Selected = $false; Actionable = $true; Action = 'Remove'; Name = $collection.Name
                OnSite = 'yes'; Deployment = $(if ($collection.HasDeployment) { 'yes' } else { 'no' })
                Why = 'Named for this package, but the environment file does not ask for it.' }) | Out-Null
        }
        else {
            $rows.Add([pscustomobject]@{
                Selected = $false; Actionable = $false; Action = '-'; Name = $collection.Name
                OnSite = 'yes'; Deployment = $(if ($collection.HasDeployment) { 'yes' } else { 'no' })
                Why = 'In place, nothing to do.' }) | Out-Null
        }
    }

    $ui.lstModify.ItemsSource = $rows.ToArray()
    $actionable = @($rows | Where-Object { $_.Action -ne '-' }).Count
    $ui.btnApplyChanges.IsEnabled = ($actionable -gt 0)
    $ui.txtModifyHint.Text = if ($actionable -eq 0) {
        'Nothing to change - the site matches the environment file.'
    } else {
        "$actionable row(s) can be acted on. Tick the ones you want, then Apply. Only ticked rows are touched."
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
                Key = $row.Key; Label = $row.Label; Scope = $row.Scope
                Property = $row.Property; From = $was; To = $now }) | Out-Null
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

$ui.btnPreview.Add_Click({ Start-Preview })
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
    Write-Output ("  plan collections     : {0}" -f $plan.Collections.Count)
    Write-Output ("  executed as          : {0}" -f $plan.Executor)
    Write-Output ("  audit link (RFC)     : {0}" -f $plan.Rfc)
    Write-Output ("  carries a person?    : {0}" -f $(if ($plan.PSObject.Properties['Requester']) { 'YES - WRONG' } else { 'no' }))

    $run = Invoke-AudiSwIntegration -Plan $plan -DryRun
    Write-Output ''
    Write-Output ("  dry run              : {0}" -f $run.Message)
    foreach ($s in $run.Steps) { Write-Output ("    {0,-14} {1,-7} {2}" -f $s.Step, $(if ($s.Ok) { 'OK' } else { 'FAILED' }), $s.Message) }
    Write-Output ''
    Write-Output ("  log folder           : {0}" -f (Split-Path -Parent $run.LogPath))

    # --- flow 2: the window submits a file, it does not connect anywhere
    $envINA = Get-AudiEnvironment -Code 'INA'
    Write-Output ''
    Write-Output ("  transport            : {0}" -f $envINA.Transport.Mode)
    Write-Output ("  drop folder          : {0}" -f $envINA.Transport.DropFolder)
    Write-Output ("  result timeout       : {0} min" -f $envINA.Transport.ResultTimeoutMinutes)

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
