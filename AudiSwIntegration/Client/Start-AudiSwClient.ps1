# ==============================================================================
#  Audi SCCM Integration Tool - packager window
# ==============================================================================
#  Run:   .\Client\Start-AudiSwClient.ps1
#
#  Testable with no SCCM at all: "Dry run" is ticked by default, which walks the
#  whole plan through the dry-run provider and shows exactly what would be done.
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
    foreach ($b in 'btnPreview','btnIntegrate','btnRemove','btnBrowse','btnRead') { $ui[$b].IsEnabled = -not $Busy }
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

$ui.txtEstimate.Text = [string]$defaults.Application.estimatedInstallMinutes

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

        if (-not $ui.txtPackage.Text.Trim()) { $ui.txtPackage.Text = Split-Path -Leaf $Path }
        Update-DerivedFields

        $map = @{ ApplicationNameEN = 'txtNameEN'; ApplicationNameDE = 'txtNameDE'
                  ApplicationDescriptionEN = 'txtDescEN'; ApplicationDescriptionDE = 'txtDescDE'
                  OrderNumber = 'txtRfc' }
        foreach ($key in $map.Keys) {
            if ($detail.Fields.Contains($key) -and -not $ui[$map[$key]].Text) { $ui[$map[$key]].Text = $detail.Fields[$key] }
        }

        # a sensible starting point rather than a blank form
        if (-not $ui.txtNameEN.Text -and $ui.txtPublisher.Text) {
            $ui.txtNameEN.Text = "$($ui.txtPublisher.Text) - $($ui.txtProduct.Text) - $($ui.txtVersion.Text)"
        }
        if (-not $ui.txtNameDE.Text) { $ui.txtNameDE.Text = $ui.txtNameEN.Text }

        $found = if ($detail.Fields.Count -gt 0) { ($detail.Fields.Keys -join ', ') } else { 'nothing' }
        $ui.txtSourceNote.Text = "Script: $(if ($detail.ScriptPath) { "$($detail.Generation) - " + (Split-Path -Leaf $detail.ScriptPath) } else { 'not found' })" +
                                 "`r`nDocument: $(if ($detail.DocumentPath) { Split-Path -Leaf $detail.DocumentPath } else { 'not found' })" +
                                 "`r`nRead: $found"
        Set-Status 'Package read. Anything not found is left for you to fill in.'
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
                                   -LocalizedDescription $ui.txtDescEN.Text.Trim()
}

# --------------------------------------------------------------- run in the bg
function Start-Run { param([string]$Mode)   # Integrate | Remove

    try   { $plan = New-PlanFromForm }
    catch { Set-Status $_.Exception.Message '#FFFFC107'; return }

    $dryRun = [bool]$ui.chkDryRun.IsChecked
    if (-not $dryRun) {
        $verb = if ($Mode -eq 'Remove') { 'REMOVE' } else { 'INTEGRATE' }
        $answer = [System.Windows.MessageBox]::Show(
            "$verb '$($plan.PackageName)' in $($plan.Environment)?`r`n`r`nThis will make real changes.`r`nRequested by: $($plan.Requester)`r`nCarried out by: $($plan.Executor)",
            'Confirm', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { Set-Status 'Cancelled.'; return }
    }

    $ui.lstResults.ItemsSource = $null
    $ui.prgRun.Value = 0
    $ui.prgRun.Maximum = if ($Mode -eq 'Remove') { 4 } else { 8 }
    $state.StepCount = $ui.prgRun.Maximum
    $state.Running = $true; $state.Done = $false; $state.Result = $null; $state.Error = $null; $state.Step = ''
    Set-Busy $true
    Set-Status "$Mode started..."

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions  = 'ReuseThread'
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable('state', $state)
    $runspace.SessionStateProxy.SetVariable('plan', $plan)
    $runspace.SessionStateProxy.SetVariable('toolRoot', $ToolRoot)
    $runspace.SessionStateProxy.SetVariable('dryRun', $dryRun)
    $runspace.SessionStateProxy.SetVariable('mode', $Mode)

    $worker = [powershell]::Create()
    $worker.Runspace = $runspace
    $null = $worker.AddScript({
        try {
            . (Join-Path $toolRoot 'AudiSwIntegration.ps1')
            $onProgress = { param($stepName) $state.Step = $stepName }
            $state.Result = if ($mode -eq 'Remove') {
                Invoke-AudiSwRemoval     -Plan $plan -DryRun:$dryRun -OnProgress $onProgress
            } else {
                Invoke-AudiSwIntegration -Plan $plan -DryRun:$dryRun -OnProgress $onProgress
            }
        }
        catch { $state.Error = $_.Exception.Message }
        finally { $state.Done = $true; $state.Running = $false }
    })
    $handle = $worker.BeginInvoke()

    # the window polls the shared table; it is never blocked by the work
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if ($state.Step) { $ui.txtStep.Text = $state.Step }
        if (-not $state.Done) { return }

        $timer.Stop()
        try { $null = $worker.EndInvoke($handle) } catch { }
        $worker.Dispose(); $runspace.Close(); $runspace.Dispose()

        Set-Busy $false
        $ui.txtStep.Text = ''

        if ($state.Error) {
            Set-Status "Failed: $($state.Error)" '#FFFF6B6B'
            $ui.prgRun.Value = 0
            return
        }

        $result = $state.Result
        $rows = @($result.Steps | ForEach-Object {
            [pscustomobject]@{ Step = $_.Step; Result = $(if ($_.Ok) { 'OK' } else { 'FAILED' }); Message = $_.Message }
        })
        if ($result.PSObject.Properties['RolledBack'] -and $result.RolledBack.Count -gt 0) {
            foreach ($undone in $result.RolledBack) {
                $rows += [pscustomobject]@{ Step = 'Rolled back'; Result = '--'; Message = $undone }
            }
        }
        $ui.lstResults.ItemsSource = $rows
        $ui.prgRun.Value = @($result.Steps | Where-Object { $_.Ok }).Count

        if ($result.PSObject.Properties['LogPath'] -and $result.LogPath) {
            $ui['LogFolder'] = Split-Path -Parent $result.LogPath
            $ui.btnOpenLog.IsEnabled = $true
        }

        $prefix = if ($result.DryRun) { '[Dry run] ' } else { '' }
        Set-Status "$prefix$($result.Message)  |  job $($result.JobId)" $(if ($result.Ok) { '#FF99D1CD' } else { '#FFFF6B6B' })
    })
    $timer.Start()
}

# --------------------------------------------------------------------- handlers
$ui.cboEnvironment.Add_SelectionChanged({ Update-EnvironmentNotice })
$ui.txtPackage.Add_LostFocus({ Update-DerivedFields })

$ui.btnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the package folder'
    if ($dialog.ShowDialog() -eq 'OK') { $ui['PackagePath'] = $dialog.SelectedPath; Read-PackageFolder -Path $dialog.SelectedPath }
})

$ui.btnRead.Add_Click({
    if ($ui.Contains('PackagePath') -and $ui['PackagePath']) { Read-PackageFolder -Path $ui['PackagePath'] }
    else { Update-DerivedFields; Set-Status 'Names derived from the package name. Use Browse to also read the package contents.' }
})

$ui.btnPreview.Add_Click({ $ui.chkDryRun.IsChecked = $true; Start-Run -Mode 'Integrate' })
$ui.btnIntegrate.Add_Click({ Start-Run -Mode 'Integrate' })
$ui.btnRemove.Add_Click({ Start-Run -Mode 'Remove' })

$ui.btnOpenLog.Add_Click({
    if ($ui.Contains('LogFolder') -and (Test-Path -LiteralPath $ui['LogFolder'])) { Start-Process explorer.exe $ui['LogFolder'] }
})

# ------------------------------------------------------------------------ start
Update-EnvironmentNotice
Set-Status 'Ready. Dry run is on, so nothing will be changed until you turn it off.'

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
    Write-Output ("  requester / executor : {0}  /  {1}" -f $plan.Requester, $plan.Executor)

    $run = Invoke-AudiSwIntegration -Plan $plan -DryRun
    Write-Output ''
    Write-Output ("  dry run              : {0}" -f $run.Message)
    foreach ($s in $run.Steps) { Write-Output ("    {0,-14} {1,-7} {2}" -f $s.Step, $(if ($s.Ok) { 'OK' } else { 'FAILED' }), $s.Message) }
    Write-Output ''
    Write-Output ("  log folder           : {0}" -f (Split-Path -Parent $run.LogPath))
    Write-Output ''
    return
}

$null = $window.ShowDialog()
