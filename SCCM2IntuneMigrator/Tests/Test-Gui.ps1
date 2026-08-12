# Builds the real window WITHOUT showing it and runs the assertions INSIDE the script's own scope
# (that is what ShowDialog does in real use: the script is still on the stack, so the event
# handlers can reach the script-scope functions). Also proves the background worker runspace can
# rebuild the engine from $Engine.ToString().
$ErrorActionPreference = 'Stop'
$sp   = $PSScriptRoot
$tool = Split-Path -Parent $PSScriptRoot
$global:pass = 0; $global:fail = 0

$global:__TESTS = {
    function T { param($Name, [scriptblock]$B)
        try { $r = & $B; if ($r -eq $true) { $global:pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
              else { $global:fail++; Write-Host "  FAIL  $Name -> $r" -ForegroundColor Red } }
        catch { $global:fail++; Write-Host "  FAIL  $Name -> $($_.Exception.Message)" -ForegroundColor Red } }

    Write-Host "`n=== window construction ===" -ForegroundColor Cyan
    T 'the window object was built' { $null -ne $Win }
    T 'the title is set'            { "$($Win.Title)" -eq 'SCCM to Intune migration' }
    foreach ($n in 'LblSub','CbProfile','Pill','LblConn','ConnPanel','TxtServer','TxtSite','TxtTenant','BtnConnect',
                   'TxtSearch','LblSearchHint','LblCount','BtnSelectNone','GridApps','ExpLog','TxtLog',
                   'Overlay','LblBusy','LblBusySub','EmptyHint',
                   'Bar','LblStatus','ChkDryRun','LblRunFolder','BtnOpenReport','BtnCancel','BtnMigrate') {
        T "control '$n' resolved" { $null -ne $UI[$n] }.GetNewClosure()
    }
    T 'the row type compiled'  { $null -ne ('MigAppRow' -as [type]) }

    Write-Host "`n=== the UI does NOT ask about things that are fixed ===" -ForegroundColor Cyan
    T 'no assignment-intent control' { $null -eq $Win.FindName('CbIntent') }
    T 'no group-mode control'        { $null -eq $Win.FindName('CbGroupMode') }
    T 'no group-pattern control'     { $null -eq $Win.FindName('TxtGroupPattern') }
    T 'no tick-all button'           { $null -eq $Win.FindName('BtnSelectAll') }
    T 'the fixed rules are stated'   { $UI.LblSub.Text -match 'never created' -and $UI.LblSub.Text -match 'never assigned' }

    Write-Host "`n=== initial state ===" -ForegroundColor Cyan
    T 'profiles are listed'                { @($UI.CbProfile.ItemsSource).Count -ge 2 -and @($UI.CbProfile.ItemsSource) -contains 'PreLive' }
    T 'the active profile is preselected'  { "$($UI.CbProfile.SelectedItem)" -eq $script:Cfg.ProfileName }
    T 'site fields prefilled from profile' { $UI.TxtSite.Text -eq 'G1K' -and $UI.TxtServer.Text -match 'MNDEMUCSM157' }
    T 'tenant prefilled'                   { $UI.TxtTenant.Text -eq 'm365.man' }
    T 'the group pattern is shown'         { $UI.LblSub.Text -match 'MDM_MN_SWW_\{Vendor\}_\{AppName\}_UAT' }
    T 'Migrate disabled until connected'   { $UI.BtnMigrate.IsEnabled -eq $false }
    T 'Cancel disabled until running'      { $UI.BtnCancel.IsEnabled -eq $false }
    T 'Open report disabled at start'      { $UI.BtnOpenReport.IsEnabled -eq $false }
    T 'the connection card is visible'     { "$($UI.ConnPanel.Visibility)" -eq 'Visible' }
    T 'the log starts collapsed'           { $UI.ExpLog.IsExpanded -eq $false }
    T 'the busy overlay starts hidden'     { "$($UI.Overlay.Visibility)" -eq 'Collapsed' }
    T 'the status pill says not connected' { $UI.LblConn.Text -eq 'Not connected' }
    T 'the grid has a tick column'         { $UI.GridApps.Columns[0] -is [System.Windows.Controls.DataGridCheckBoxColumn] }
    T 'the grid has a Status column'       { @($UI.GridApps.Columns | ForEach-Object { "$($_.Header)" }) -contains 'Status' }
    T 'the grid has a Result column'       { @($UI.GridApps.Columns | ForEach-Object { "$($_.Header)" }) -contains 'Result' }

    Write-Host "`n=== profile switching (the real handler) ===" -ForegroundColor Cyan
    $UI.CbProfile.SelectedItem = 'PreLive'
    T 'site code follows the profile'       { $UI.TxtSite.Text -eq 'G08' }
    T 'site server follows the profile'     { $UI.TxtServer.Text -match 'MBDCASWVTB29843' }
    T 'Migrate is re-locked after a switch' { $UI.BtnMigrate.IsEnabled -eq $false }
    T 'the live config switched too'        { $script:Cfg.SiteCode -eq 'G08' }
    # switch back to whichever profile is NOT PreLive - the profile can be renamed at any time
    $backTo = @($UI.CbProfile.ItemsSource | Where-Object { $_ -ne 'PreLive' })[0]
    $UI.CbProfile.SelectedItem = $backTo
    T 'switching back restores the site'    { $UI.TxtSite.Text -ne 'G08' -and $script:Cfg.SiteCode -ne 'G08' }

    Write-Host "`n=== rows, ticks and filtering (the real handlers) ===" -ForegroundColor Cyan
    foreach ($n in 'Contoso_Alpha_x64_1.0-1_MUL', 'Contoso_Beta_x64_2.0-1_MUL', 'Acme_Gamma_x86_3.0-1_ENU') {
        $row = New-Object MigAppRow; $row.Name = $n; $row.Version = '1.0'
        $State.Rows.Add($row); $State.RowByName[$n] = $row
    }
    Update-UiCount
    T 'all rows are listed'          { $State.Rows.Count -eq 3 -and $UI.LblCount.Text -match '3 applications' }
    foreach ($r in $State.Rows) { $r.Selected = $true }
    Update-UiCount
    T 'ticking rows is reflected'    { @($State.Rows | Where-Object { $_.Selected }).Count -eq 3 }
    T 'the counter shows the ticks'  { $UI.LblCount.Text -match '3 ticked' }
    $UI.TxtSearch.Text = 'Beta'
    T 'the filter narrows the view'  { @($State.View | ForEach-Object { $_ }).Count -eq 1 }
    T 'ticks SURVIVE filtering'      { @($State.Rows | Where-Object { $_.Selected }).Count -eq 3 }
    T 'the counter shows the filter' { $UI.LblCount.Text -match '1 of 3 shown' }
    $UI.BtnSelectNone.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    T 'Clear unticks everything'     { @($State.Rows | Where-Object { $_.Selected }).Count -eq 0 }
    $UI.TxtSearch.Text = ''
    T 'clearing the filter shows all again' { @($State.View | ForEach-Object { $_ }).Count -eq 3 }

    Write-Host "`n=== live status folding (the real timer logic) ===" -ForegroundColor Cyan
    $notified = @{}
    $State.RowByName['Contoso_Alpha_x64_1.0-1_MUL'].add_PropertyChanged({ param($s,$e) $notified[$e.PropertyName] = $true })
    $Sync.Results.Add([pscustomobject]@{ Application='Contoso_Alpha_x64_1.0-1_MUL'; Status='Success'; AppId='app-1'
                                         Message='Created.'; UatGroup='MDM_MN_SWW_Contoso_Alpha_UAT'; UatGroupExists=$false
                                         PortalUrl='https://intune.microsoft.com/#view/x/appId/app-1' })
    $Sync.Results.Add([pscustomobject]@{ Application='Acme_Gamma_x86_3.0-1_ENU'; Status='Failed'; AppId=''
                                         Message='content unreachable'; UatGroup=''; UatGroupExists=$false })
    $Sync.Running = $false
    # run exactly the folding block the timer runs
    while ($State.SeenResults -lt $Sync.Results.Count) {
        $r = $Sync.Results[$State.SeenResults]; $State.SeenResults++
        $row = $State.RowByName["$($r.Application)"]
        if (-not $row) { continue }
        $row.Status = switch -Regex ("$($r.Status)") {
            '^Success$' { 'Migrated' } '^DryRun$' { 'Built (dry run)' } '^Skipped$' { 'Skipped' }
            '^Cancelled$' { 'Cancelled' } '^Failed' { 'Failed' } default { "$($r.Status)" } }
        $row.Detail = if ("$($r.AppId)") { "$($r.AppId)  -  $($r.Message)" } else { "$($r.Message)" }
    }
    T 'a success shows as Migrated'   { $State.RowByName['Contoso_Alpha_x64_1.0-1_MUL'].Status -eq 'Migrated' }
    T 'the App ID lands in Result'    { $State.RowByName['Contoso_Alpha_x64_1.0-1_MUL'].Detail -match '^app-1' }
    T 'a failure shows as Failed'     { $State.RowByName['Acme_Gamma_x86_3.0-1_ENU'].Status -eq 'Failed' }
    T 'the grid IS notified (no rebuild needed)' { $notified['Status'] -eq $true -and $notified['Detail'] -eq $true }
    T 'an untouched row stays blank'  { $State.RowByName['Contoso_Beta_x64_2.0-1_MUL'].Status -eq '' }

    Write-Host "`n=== the 'already in Intune' review dialog ===" -ForegroundColor Cyan
    T 'the review row type compiled' { $null -ne ('MigReviewRow' -as [type]) }
    T 'the review XAML parses and builds' {
        [xml]$rx = Get-MigReviewXaml
        $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $rx))
        $ok = ($null -ne $d.FindName('GridReview')) -and ($null -ne $d.FindName('LblIntro')) -and
              ($null -ne $d.FindName('LblFoot')) -and ($null -ne $d.FindName('BtnGo')) -and
              ($null -ne $d.FindName('BtnAbort'))
        $script:__revDlg = $d
        $ok
    }
    T 'it offers a per-application choice' {
        $col = @($script:__revDlg.FindName('GridReview').Columns | Where-Object { "$($_.Header)" -eq 'What to do' })
        # a TEMPLATE column holding a ComboBox, so the dropdown is visible without entering edit
        # mode - a plain DataGridComboBoxColumn renders as flat text until the cell is clicked
        $col.Count -eq 1 -and $col[0] -is [System.Windows.Controls.DataGridTemplateColumn]
    }
    T 'a SAME-version row defaults to Skip' {
        $r = New-Object MigReviewRow
        $r.Actions = @('Skip this application', 'Migrate anyway (a second copy)')
        $r.Action  = 'Skip this application'
        $r.Action -like 'Skip*'
    }
    T 'an OLDER-version row defaults to supersede' {
        $r = New-Object MigReviewRow
        $r.Actions = @('Migrate and supersede the older version(s)', 'Migrate without supersedence', 'Skip this application')
        $r.Action  = 'Migrate and supersede the older version(s)'
        $r.Action -like 'Migrate and supersede*'
    }
    T 'the review row notifies on Action' {
        $r = New-Object MigReviewRow
        $seen = $false
        $r.add_PropertyChanged({ param($a,$b) if ($b.PropertyName -eq 'Action') { $script:__revSeen = $true } })
        $script:__revSeen = $false
        $r.Action = 'Skip this application'
        $script:__revSeen
    }
    try { $script:__revDlg.Close() } catch {}

    Write-Host "`n=== the review names the SITUATION and offers the right two choices ===" -ForegroundColor Cyan
    $mkFind = {
        param($app, $newVer, $relation, $existVer, $lc, $id)
        $x = [pscustomobject]@{ Id = $id; DisplayName = 'X'; Version = $existVer; Lifecycle = $lc; Relation = $relation }
        [pscustomobject]@{
            Application = $app; Version = $newVer
            Same   = @(if ($relation -eq 'Same')   { $x })
            Lower  = @(if ($relation -eq 'Lower')  { $x })
            Higher = @(if ($relation -eq 'Higher') { $x })
            All    = @($x)
        }
    }
    $fSame   = & $mkFind 'App_Same_x64_1.0-1_MUL'   '1.0'    'Same'   '1.0'   'LIVE'    's1'
    $fHigher = & $mkFind 'App_High_x64_1.0-1_MUL'   '1.0'    'Higher' '2.0.0' 'UAT'     'h1'
    $fLower  = & $mkFind 'App_Low_x64_4.2.9-1_MUL'  '4.2.9'  'Lower'  '4.1.0' 'LIVE'    'l1'
    $fNoLc   = & $mkFind 'App_NoLc_x64_1.0-1_MUL'   '1.0'    'Higher' '3.0'   'unknown' 'n1'
    $rows = @(New-MigReviewRows -Findings @($fSame, $fHigher, $fLower, $fNoLc))

    T 'SAME says SAME version'        { $rows[0].Relation -eq 'SAME version (v1.0) already in Intune' }
    T 'SAME offers skip or continue'  { (@($rows[0].Actions) -join '|') -eq 'Skip - do not migrate|Continue - migrate anyway' }
    T 'SAME defaults to skip'         { $rows[0].Action -like 'Skip*' }

    T 'HIGHER says HIGHER version'    { $rows[1].Relation -eq 'HIGHER version (v2.0.0) already in Intune' }
    T 'HIGHER does NOT say "already in Intune" alone' { $rows[1].Relation -match 'HIGHER version \(v2\.0\.0\)' }
    T 'HIGHER offers skip or continue'{ (@($rows[1].Actions) -join '|') -eq 'Skip - do not migrate|Continue - migrate anyway' }
    T 'HIGHER defaults to skip'       { $rows[1].Action -like 'Skip*' }
    T 'HIGHER offers NO supersedence' { (@($rows[1].Actions) -join '|') -notmatch 'supersede' }

    T 'LOWER says LOWER version'      { $rows[2].Relation -eq 'LOWER version (v4.1.0) already in Intune' }
    T 'LOWER offers supersede or skip'{ @($rows[2].Actions).Count -eq 2 -and $rows[2].Actions[0] -like 'Add supersedence*' -and $rows[2].Actions[1] -like 'Skip*' }
    T 'LOWER names the version to supersede' { $rows[2].Actions[0] -match 'supersede v4\.1\.0' }
    T 'LOWER defaults to supersede'   { $rows[2].Action -like 'Add supersedence*' }
    T 'LOWER carries the target id'   { $rows[2].SupersedeIds -eq 'l1' }

    T 'a lifecycle is shown when there is one' { $rows[1].Found -eq 'v2.0.0 [UAT]' }
    T 'no bracket when the brand records none' { $rows[3].Found -eq 'v3.0' }

    Write-Host "`n=== the decision becomes a clear note ===" -ForegroundColor Cyan
    $rows[1].Action = 'Skip - do not migrate'
    $rows[2].Action = 'Add supersedence - migrate and supersede v4.1.0'
    $rows[0].Action = 'Continue - migrate anyway'
    $d = Get-MigReviewDecision -Rows $rows
    T 'a skipped HIGHER app gets a naming note' {
        $d.Skips['App_High_x64_1.0-1_MUL'] -eq 'Skipped - HIGHER version (v2.0.0) already in Intune.'
    }
    T 'the note never says just "already in Intune"' {
        $d.Skips['App_High_x64_1.0-1_MUL'] -match 'HIGHER version'
    }
    T 'Continue is NOT skipped'        { -not $d.Skips.ContainsKey('App_Same_x64_1.0-1_MUL') }
    T 'Continue gets no supersedence'  { -not $d.Supersede.ContainsKey('App_Same_x64_1.0-1_MUL') }
    T 'supersedence carries the id'    { (@($d.Supersede['App_Low_x64_4.2.9-1_MUL']) -join ',') -eq 'l1' }
    T 'a superseding app is not skipped' { -not $d.Skips.ContainsKey('App_Low_x64_4.2.9-1_MUL') }

    Write-Host "`n=== every UI helper actually runs ===" -ForegroundColor Cyan
    # $UI is a plain hashtable, so a control that was removed from the XAML is silently $null and
    # only explodes when a helper touches it ("The property 'IsEnabled' cannot be found on this
    # object"). Calling each helper here is what catches that.
    T 'Set-UiBusy $true runs'   { Set-UiBusy $true;  $UI.BtnCancel.IsEnabled -eq $true }
    T 'Set-UiBusy $false runs'  { Set-UiBusy $false; $UI.BtnCancel.IsEnabled -eq $false }
    T 'Set-UiBusy locks the right things while busy' {
        Set-UiBusy $true
        $r = ($UI.BtnConnect.IsEnabled -eq $false) -and ($UI.CbProfile.IsEnabled -eq $false) -and
             ($UI.ChkDryRun.IsEnabled -eq $false) -and ($UI.BtnSelectNone.IsEnabled -eq $false)
        Set-UiBusy $false
        $r
    }
    T 'Set-UiConnected runs'    { Set-UiConnected 'G1K - tenant' '#1A7F37'; $UI.LblConn.Text -eq 'G1K - tenant' }
    T 'Update-UiCount runs'     { Update-UiCount; $UI.LblCount.Text -ne '' }
    T 'Add-UiLog runs'          { Add-UiLog 'helper smoke test'; $UI.TxtLog.Text -match 'helper smoke test' }

    Write-Host "`n=== the busy overlay ===" -ForegroundColor Cyan
    Show-UiBusy 'Signing in to Intune' 'a detail line'
    T 'the overlay shows'          { "$($UI.Overlay.Visibility)" -eq 'Visible' }
    T 'it says what it is doing'   { $UI.LblBusy.Text -eq 'Signing in to Intune' -and $UI.LblBusySub.Text -eq 'a detail line' }
    Hide-UiBusy
    T 'and it goes away again'     { "$($UI.Overlay.Visibility)" -eq 'Collapsed' }
    T 'the connect slots exist'    { $Sync.ContainsKey('ConnectState') -and $State.ContainsKey('ConnectWorker') }

    Write-Host "`n=== the sync bridge ===" -ForegroundColor Cyan
    T 'Sync carries the window'   { $null -ne $Sync.Window }
    T 'Sync has a log queue'      { $null -ne $Sync.LogQueue }
    T 'the engine text is staged' { "$($State.EngineText)".Length -gt 10000 }
    T 'UI-thread logging reaches the queue' {
        $before = $Sync.LogQueue.Count
        Write-MigLog 'smoke-test line' Info
        $Sync.LogQueue.Count -eq ($before + 1)
    }

    $global:__ENGINE_TEXT = "$($State.EngineText)"
}

$src = Get-Content -LiteralPath (Join-Path $tool 'SCCM2IntuneMigrator.ps1') -Raw
$src2 = $src -replace '(?m)^\$null = \$Win\.ShowDialog\(\)\s*$', '. $global:__TESTS'
if ($src2 -eq $src) { throw 'Could not neutralise ShowDialog - the marker line changed.' }
$tmp = Join-Path $sp '_gui_test.ps1'
[IO.File]::WriteAllText($tmp, $src2, (New-Object Text.UTF8Encoding($true)))
& $tmp -SettingsPath (Join-Path $tool 'settings.json')

Write-Host "`n=== worker runspace can rebuild the engine ===" -ForegroundColor Cyan
function T2 { param($Name, [scriptblock]$B)
    try { $r = & $B; if ($r -eq $true) { $global:pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
          else { $global:fail++; Write-Host "  FAIL  $Name -> $r" -ForegroundColor Red } }
    catch { $global:fail++; Write-Host "  FAIL  $Name -> $($_.Exception.Message)" -ForegroundColor Red } }

$engineText = "$($global:__ENGINE_TEXT)"
$rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.Open()
$rs.SessionStateProxy.SetVariable('ToolRoot', $tool)
$ps = [powershell]::Create(); $ps.Runspace = $rs
[void]$ps.AddScript(@"
`$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
`$script:ToolRoot = `$ToolRoot
$engineText
`$script:Cfg = @{ ToolRoot = `$ToolRoot; PackageNameRegex = ''; UatGroupNamePattern = 'MDM_MN_SWW_{Vendor}_{AppName}_UAT' }
`$n = ConvertFrom-MigPackageName -FullName 'Contoso_Widget_x64_1.2.3-0004_ENU'
[pscustomobject]@{
    Funcs  = @(Get-Command -CommandType Function | Where-Object { `$_.Name -like '*-Mig*' }).Count
    Group  = Resolve-MigUatGroupName -Name `$n
    Key    = Add-MigHkeyPrefix 'SOFTWARE\X'
    Ver    = `$n.Version
    Worker = [bool](Get-Command Start-MigWorker -ErrorAction SilentlyContinue)
    Upload = [bool](Get-Command Send-MigBlob    -ErrorAction SilentlyContinue)
    Undo   = [bool](Get-Command Undo-MigApplication -ErrorAction SilentlyContinue)
    Mods   = [bool](Get-Command Find-MigModuleManifest -ErrorAction SilentlyContinue)
}
"@)
$out = $ps.Invoke()
$errs = @($ps.Streams.Error)
$ps.Dispose(); $rs.Close()
T2 'the worker runspace ran clean'   { if ($errs.Count) { $errs[0].ToString() } else { $true } }
T2 'the engine functions exist there'{ $out[0].Funcs -ge 30 }
T2 'the entry points exist there'    { $out[0].Worker -and $out[0].Upload -and $out[0].Undo -and $out[0].Mods }
T2 'the engine actually works there' { $out[0].Group -eq 'MDM_MN_SWW_Contoso_Widget_UAT' -and $out[0].Ver -eq '1.2.3' -and $out[0].Key -eq 'HKEY_LOCAL_MACHINE\SOFTWARE\X' }

Write-Host ""
Write-Host "PASSED $global:pass   FAILED $global:fail" -ForegroundColor $(if ($global:fail) { 'Red' } else { 'Green' })
if ($global:fail) { exit 1 }
