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
})

$defaults = Get-AudiDefaults

# ---------------------------------------------------------------- small helpers
function Set-Status { param([string]$Text, [string]$Colour = '#FFE5E9EB')
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

function Get-SelectedOperatingSystem {
    $keys = @()
    foreach ($child in $ui.pnlOperatingSystems.Children) { if ($child.IsChecked) { $keys += [string]$child.Tag } }
    return $keys
}

# ---------------------------------------------------------------- populate once
foreach ($code in (Get-AudiEnvironmentCode)) { $null = $ui.cboEnvironment.Items.Add($code) }

$detected = if ($EnvironmentCode) { $EnvironmentCode } else { Resolve-AudiEnvironmentCode }
if ($detected -and $ui.cboEnvironment.Items.Contains($detected)) { $ui.cboEnvironment.SelectedItem = $detected }
elseif ($ui.cboEnvironment.Items.Count -gt 0) { $ui.cboEnvironment.SelectedIndex = 0 }

foreach ($os in $defaults.OperatingSystems) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content   = $os.Label
    $cb.Tag       = $os.Key
    $cb.IsChecked = $os.SelectedByDefault
    $cb.Foreground = $ui.txtStatus.Foreground
    $cb.Margin    = '0,0,16,4'
    $null = $ui.pnlOperatingSystems.Children.Add($cb)
}

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
function Update-EnvironmentNotice {
    $code = [string]$ui.cboEnvironment.SelectedItem
    if (-not $code) { return }
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
    foreach ($f in 'txtPublisher','txtProduct','txtVersion','txtArchitecture','txtRevision','txtLanguage','txtBranding','txtDetection') { $ui[$f].Text = '' }
    if (-not $package) { return }
    try {
        $parts = Split-AudiPackageName -PackageName $package
        $ui.txtPublisher.Text    = $parts.Publisher
        $ui.txtProduct.Text      = $parts.Product
        $ui.txtVersion.Text      = $parts.Version
        $ui.txtArchitecture.Text = $parts.Architecture
        $ui.txtRevision.Text     = $parts.Revision
        $ui.txtLanguage.Text     = $parts.Language
        $ui.txtBranding.Text     = Get-AudiBrandingKey -PackageName $package
        $ui.txtDetection.Text    = "$($defaults.Naming.brandingRegistryRoot)$($ui.txtBranding.Text)"
        Set-Status 'Package name understood.'
    }
    catch { Set-Status $_.Exception.Message '#FFFFC107' }
}

# ------------------------------------------------------------- read the package
function Read-PackageFolder { param([string]$Path)
    if (-not $Path) { return }
    Set-Status "Reading $Path ..."
    try {
        $detail = Read-AudiPackageDetail -PackagePath $Path

        if ($ui.txtPackagePath.Text -ne $Path) { $ui.txtPackagePath.Text = $Path }
        if (-not $ui.txtPackage.Text.Trim()) { $ui.txtPackage.Text = Split-Path -Leaf $Path }
        Update-DerivedFields

        $map = @{ ApplicationNameEN = 'txtNameEN'; ApplicationNameDE = 'txtNameDE'
                  ApplicationDescriptionEN = 'txtDescEN'; ApplicationDescriptionDE = 'txtDescDE'
                  OrderNumber = 'txtRfc' }
        foreach ($key in $map.Keys) {
            if ($detail.Fields.Contains($key) -and -not $ui[$map[$key]].Text) { $ui[$map[$key]].Text = $detail.Fields[$key] }
        }

        # The request form states which operating systems the software supports,
        # as ticked boxes. A field named OperatingSystem:<key> means that box was
        # ticked, so tick the matching one here rather than making the packager
        # copy it across by eye.
        $ticked = @($detail.Fields.Keys | Where-Object { $_ -like 'OperatingSystem:*' -and $detail.Fields[$_] })
        if ($ticked.Count -gt 0) {
            foreach ($child in $ui.pnlOperatingSystems.Children) { $child.IsChecked = $false }
            foreach ($key in $ticked) {
                $wanted = $key.Substring('OperatingSystem:'.Length)
                foreach ($child in $ui.pnlOperatingSystems.Children) {
                    if ([string]$child.Tag -eq $wanted) { $child.IsChecked = $true }
                }
            }
        }

        # a sensible starting point rather than a blank form
        if (-not $ui.txtNameEN.Text -and $ui.txtPublisher.Text) {
            $ui.txtNameEN.Text = "$($ui.txtPublisher.Text) - $($ui.txtProduct.Text) - $($ui.txtVersion.Text)"
        }
        if (-not $ui.txtNameDE.Text) { $ui.txtNameDE.Text = $ui.txtNameEN.Text }

        # One line, so the card stays compact. The full detail - including which
        # field came from where - is on the tooltip.
        $script   = if ($detail.ScriptPath)   { "$($detail.Generation) $(Split-Path -Leaf $detail.ScriptPath)" } else { 'no script found' }
        $document = if ($detail.DocumentPath) { Split-Path -Leaf $detail.DocumentPath } else { 'no document found' }
        $ui.txtSourceNote.Text = "{0}  |  {1}  |  {2} field(s) read" -f $script, $document, $detail.Fields.Count

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("Script:   $script")
        $lines.Add("Document: $document")
        $lines.Add('')
        if ($detail.Fields.Count -gt 0) {
            foreach ($key in $detail.Fields.Keys) {
                $lines.Add(("{0,-26} {1}   [{2}]" -f $key, $detail.Fields[$key], $detail.Origin[$key]))
            }
        } else { $lines.Add('Nothing could be read - fill the fields in by hand.') }
        foreach ($n in @($detail.Notes)) { $lines.Add(''); $lines.Add($n) }
        $ui.txtSourceNote.ToolTip = ($lines -join "`r`n")

        Set-Status 'Package read. Hover the grey line for where each value came from. Anything not found is left for you to fill in.'
    }
    catch { Set-Status "Could not read the package: $($_.Exception.Message)" '#FFFF6B6B' }
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
                                   -LocalizedDescriptionDe $ui.txtDescDE.Text.Trim()
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
    Set-Status "$prefix$($Result.Message)$Note" $(if ($Result.Ok) { '#FF99D1CD' } else { '#FFFF6B6B' })
}

# --------------------------------------------------------------- run in the bg
# One background worker for both buttons. The window only ever polls $state, so
# it stays responsive however long the server takes.
function Start-Worker { param([scriptblock]$Body, [hashtable]$Arguments, [int]$Steps)

    $ui.lstResults.ItemsSource = $null
    $ui.prgRun.Value = 0
    $ui.prgRun.Maximum = $Steps
    $ui.prgRun.IsIndeterminate = $false
    $state.Running = $true; $state.Done = $false; $state.Result = $null; $state.Error = $null
    $state.Step = ''; $state.Waiting = $false
    Set-Busy $true

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions  = 'ReuseThread'
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable('state', $state)
    $runspace.SessionStateProxy.SetVariable('toolRoot', $ToolRoot)
    # NOT called 'args': inside a script $args is the automatic argument list
    $runspace.SessionStateProxy.SetVariable('jobArgs', $Arguments)

    $worker = [powershell]::Create()
    $worker.Runspace = $runspace
    $null = $worker.AddScript($Body)
    $handle = $worker.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if ($state.Step) { $ui.txtStep.Text = $state.Step }
        # nothing to count while the job sits in the folder - show movement only
        if ($state.Waiting -and -not $ui.prgRun.IsIndeterminate) { $ui.prgRun.IsIndeterminate = $true }
        if (-not $state.Done) { return }

        $timer.Stop()
        try { $null = $worker.EndInvoke($handle) } catch { }
        $worker.Dispose(); $runspace.Close(); $runspace.Dispose()

        Set-Busy $false
        $ui.txtStep.Text = ''
        $ui.prgRun.IsIndeterminate = $false

        if ($state.Error) { Set-Status "Failed: $($state.Error)" '#FFFF6B6B'; $ui.prgRun.Value = 0; return }
        Show-RunOutcome $state.Result $state.Note
    })
    $timer.Start()
}

# ------------------------------------------------------ preview: local, no server
# Runs the plan through the dry-run provider on this machine. Nothing is written
# to the drop folder and the server is never involved, so a packager can check a
# package before queuing anything.
function Start-Preview {
    try   { $plan = New-PlanFromForm }
    catch { Set-Status $_.Exception.Message '#FFFFC107'; return }

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

    try   { $plan = New-PlanFromForm }      # validates the form before queuing
    catch { Set-Status $_.Exception.Message '#FFFFC107'; return }

    $code = [string]$ui.cboEnvironment.SelectedItem
    try   { $env = Get-AudiEnvironment -Code $code }
    catch { Set-Status $_.Exception.Message '#FFFF6B6B'; return }

    if ($env.Transport.Mode -ne 'DropFolder' -and -not $DropFolder) {
        Set-Status "Environment $code is set to transport '$($env.Transport.Mode)', which this window does not use." '#FFFF6B6B'
        return
    }
    $drop = Get-ActiveDropFolder -Environment $env
    if ([string]::IsNullOrWhiteSpace($drop)) {
        Set-Status "Environment $code has no drop folder set. Fill in Transport/@dropFolder in $($env.Path)." '#FFFF6B6B'
        return
    }

    # With no personal name kept on the server, the RFC is the only record of
    # who asked - so stop here rather than queue an untraceable change.
    $rfc = $ui.txtRfc.Text.Trim()
    if ((Get-AudiDefaults).Audit.RequireRfc -and -not $rfc) {
        Set-Status 'Enter the RFC number first. It is the only record of who requested this change, so the server refuses a job without one.' '#FFFFC107'
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
        OperatingSystems = Get-SelectedOperatingSystem
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
                                     -OperatingSystems $jobArgs.OperatingSystems -DryRun:$wantsDryRun

            $submission = Submit-AudiSwJob -DropFolder $jobArgs.DropFolder -Job $doc
            $state.JobId = $submission.JobId

            $state.Waiting = $true
            $started = Get-Date
            $state.Step = "Queued as job $($submission.JobId). Waiting for the server..."

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
$ui.txtPackage.Add_LostFocus({ Update-DerivedFields })

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

$ui.btnPreview.Add_Click({ Start-Preview })
$ui.btnIntegrate.Add_Click({ Start-Run -Mode 'Integrate' })
$ui.btnModify.Add_Click({ Start-Run -Mode 'Modify' })
$ui.btnRemove.Add_Click({ Start-Run -Mode 'Remove' })

$ui.btnOpenLog.Add_Click({
    if ($ui.Contains('LogFolder') -and (Test-Path -LiteralPath $ui['LogFolder'])) { Start-Process explorer.exe $ui['LogFolder'] }
})

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
    Write-Output ("  OS checkboxes        : {0}" -f $ui.pnlOperatingSystems.Children.Count)
    Write-Output ("  ticked by default    : {0}" -f ((Get-SelectedOperatingSystem) -join ', '))

    # ---- read a REAL package and check every field the window shows is filled
    Write-Output ''
    $sampleRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("AudiSelfTest_{0}" -f ([guid]::NewGuid().ToString('N')))
    try {
        $builder = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools\New-AudiSwSamplePackage.ps1'
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
            'Detection key'    = 'txtDetection'
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
    Write-Output ("  detection key        : {0}" -f $ui.txtDetection.Text)

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
                                 -OperatingSystems (Get-SelectedOperatingSystem) -DryRun
        $sub   = Submit-AudiSwJob -DropFolder $sandbox -Job $doc
        $check = Test-AudiConfigFile -Path $sub.Path -SchemaPath (Join-Path (Get-AudiConfigRoot) 'Environment.xsd')
        Write-Output ''
        Write-Output ("  job file written     : {0}" -f (Split-Path -Leaf $sub.Path))
        Write-Output ("  valid against schema : {0}" -f $(if ($check.Ok) { 'yes' } else { 'NO - ' + ($check.Errors -join '; ') }))
        Write-Output ("  requester in file    : {0}" -f $(if ($doc.Job.HasAttribute('requester')) { 'PRESENT - WRONG' } else { 'none - no person is sent to the server' }))
        Write-Output ("  no result yet, says  : {0}" -f (Wait-AudiSwJobResult -Submission $sub -TimeoutMinutes 0 -PollSeconds 1).Message)
    }
    finally { if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue } }
    Write-Output ''
    return
}

$null = $window.ShowDialog()
