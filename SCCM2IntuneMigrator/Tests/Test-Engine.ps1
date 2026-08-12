# Loads the migrator's engine WITHOUT the window and exercises every pure/offline function.
$ErrorActionPreference = 'Stop'
$sp   = $PSScriptRoot
$tool = Split-Path -Parent $PSScriptRoot
$fix  = Join-Path $sp 'fixtures'

# --- load the script text up to the end of $Engine, then dot-source it ------------------------
$full = Get-Content -LiteralPath (Join-Path $tool 'SCCM2IntuneMigrator.ps1') -Raw
$cut  = $full.IndexOf('}   # ---- end of $Engine')
if ($cut -lt 0) { throw 'Could not find the end-of-Engine marker.' }
$head = $full.Substring(0, $cut + 1)
$tmpPs1 = Join-Path $sp '_engine_only.ps1'
[IO.File]::WriteAllText($tmpPs1, $head, (New-Object Text.UTF8Encoding($true)))
. $tmpPs1
. $Engine
# the harness runs the engine from a temp copy, so point the tool root back at the real folder
$script:ToolRoot = $tool

$script:pass = 0; $script:fail = 0
function T {
    param([string]$Name, [scriptblock]$Body)
    try {
        $r = & $Body
        if ($r -eq $true) { $script:pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
        else { $script:fail++; Write-Host "  FAIL  $Name  -> $r" -ForegroundColor Red }
    } catch { $script:fail++; Write-Host "  FAIL  $Name  -> EXCEPTION: $($_.Exception.Message)" -ForegroundColor Red }
}

Write-Host "`n=== settings / profiles ===" -ForegroundColor Cyan
$script:Cfg = Import-MigratorSettings -Path (Join-Path $tool 'settings.json')
# read the expected values FROM settings.json - a profile can be renamed at any time
$sjRaw      = Get-Content -LiteralPath (Join-Path $tool 'settings.json') -Raw | ConvertFrom-Json
$activeName = "$($sjRaw.ActiveProfile)"
$activeProf = $sjRaw.Profiles.$activeName
T 'ActiveProfile is honoured'            { $script:Cfg.ProfileName -eq $activeName }
T 'profile value wins over Common'       { $script:Cfg.SiteCode -eq "$($activeProf.SiteCode)" }
T 'Common value is inherited'            { $script:Cfg.BlockSizeMB -eq 10 }
T 'built-in default survives'            { $script:Cfg.MinMaxRuntimeMinutes -eq 10 }
T 'profile list is discoverable'         { (Get-MigratorProfileNames) -contains 'PreLive' }
$pre = Import-MigratorSettings -Path (Join-Path $tool 'settings.json') -ProfileName 'PreLive'
T 'switching profile switches the site'  { $pre.SiteCode -eq 'G08' -and $pre.SiteServer -match 'MBDCASWVTB29843' }
T 'a half-filled profile reports what is missing' {
    $tpl = @{}; foreach ($k in $script:Cfg.Keys) { $tpl[$k] = $script:Cfg[$k] }
    $tpl.SiteCode = ''; $tpl.TenantId = ''; $tpl.UatGroupNamePattern = ''; $tpl.BrandingKeyRoot = ''
    $m = Test-MigratorSettings -Cfg $tpl
    ($m -contains 'SiteCode') -and ($m -contains 'TenantId') -and ($m -contains 'UatGroupNamePattern') -and ($m -contains 'BrandingKeyRoot')
}
T 'launchers come from settings.json' { @(Get-MigLaunchers).Count -ge 4 }
T 'a launcher carries its own commands' {
    $l = @(Get-MigLaunchers | Where-Object { $_.Marker -eq 'Deploy-Application.exe' })[0]
    # the configured command is the BASE form; the ServiceUI wrap is applied by WrapServiceUI
    $l.StageUtilities -eq $true -and $l.WrapServiceUI -eq $true -and $l.InstallCmd -notmatch 'ServiceUI'
}
T 'a direct launcher does not wrap' {
    $l = @(Get-MigLaunchers | Where-Object { $_.Marker -eq 'Invoke-AppDeployToolkit.exe' })[0]
    $l.StageUtilities -eq $false -and $l.WrapServiceUI -eq $false
}
T 'another toolkit can be added by config alone' {
    $keep = $script:Cfg.Launchers
    $script:Cfg.Launchers = @(@{ Marker='Start-Install.cmd'; Name='OtherKit'; SetupFile='Start-Install.cmd'
                                InstallCmd='Start-Install.cmd /S'; UninstallCmd='Start-Install.cmd /U'; StageUtilities=$false })
    $l = @(Get-MigLaunchers)
    $script:Cfg.Launchers = $keep
    $l.Count -eq 1 -and $l[0].Name -eq 'OtherKit' -and $l[0].InstallCmd -eq 'Start-Install.cmd /S'
}
T 'a complete profile reports nothing missing' { (Test-MigratorSettings -Cfg $script:Cfg).Count -eq 0 }

Write-Host "`n=== package-name parsing ===" -ForegroundColor Cyan
$script:Cfg.PackageNameRegex = ''
$n = ConvertFrom-MigPackageName -FullName 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'
T 'split: vendor'    { $n.Vendor   -eq 'Contoso' }
T 'split: app'       { $n.AppName  -eq 'TestAppV4' }
T 'split: arch'      { $n.Arch     -eq 'x64' }
T 'split: version'   { $n.Version  -eq '2.5.1' }
T 'split: revision'  { $n.Revision -eq '0003' }
T 'split: language'  { $n.Language -eq 'ENU' }
T 'split: conforms'  { $n.Conforms -eq $true }
$bad = ConvertFrom-MigPackageName -FullName '7-Zip 23.01 (x64)'
T 'non-conforming name does not throw'   { $bad -ne $null -and $bad.Conforms -eq $false }
T 'non-conforming name reports why'      { @($bad.Warnings).Count -ge 2 }
$script:Cfg.PackageNameRegex = '^(?<Vendor>[^-]+)-(?<AppName>[^-]+)-(?<Version>[\d\.]+)$'
$rx = ConvertFrom-MigPackageName -FullName 'Acme-WidgetPro-4.2.9'
T 'custom regex format is used'          { $rx.ParsedBy -eq 'regex' -and $rx.Vendor -eq 'Acme' -and $rx.AppName -eq 'WidgetPro' -and $rx.Version -eq '4.2.9' }
$rxMiss = ConvertFrom-MigPackageName -FullName 'Contoso_App_x64_1.0-0001_MUL'
T 'regex miss falls back to the split'   { $rxMiss.ParsedBy -eq 'split' -and $rxMiss.Vendor -eq 'Contoso' }
$script:Cfg.PackageNameRegex = '(?<Vendor>['      # deliberately broken
$rxBroken = ConvertFrom-MigPackageName -FullName 'Contoso_App_x64_1.0-0001_MUL'
T 'invalid regex is survivable'          { $rxBroken.Vendor -eq 'Contoso' -and (@($rxBroken.Warnings) -join ' ') -match 'not a valid regular expression' }
$script:Cfg.PackageNameRegex = ''

Write-Host "`n=== UAT group naming ===" -ForegroundColor Cyan
$script:Cfg.UatGroupNamePattern = 'MDM_MN_SWW_{Vendor}_{AppName}_UAT'
T 'group name follows the pattern' {
    (Resolve-MigUatGroupName -Name (ConvertFrom-MigPackageName -FullName 'Contoso_TestAppV4_x64_2.5.1-0003_ENU')) -eq 'MDM_MN_SWW_Contoso_TestAppV4_UAT'
}
T 'spaces and specials are stripped' {
    $nm = ConvertFrom-MigPackageName -FullName 'Con toso G.m.b.H_Widget Pro (x64)_x64_1.0-1_MUL'
    (Resolve-MigUatGroupName -Name $nm) -eq 'MDM_MN_SWW_ContosoGmbH_WidgetProx64_UAT'
}
T 'a missing token leaves no double underscore' {
    $nm = ConvertFrom-MigPackageName -FullName 'OnlyVendor'
    $g = Resolve-MigUatGroupName -Name $nm
    ($g -notmatch '__') -and ($g -eq 'MDM_MN_SWW_OnlyVendor_UAT')
}
T 'another brand pattern works unchanged' {
    $script:Cfg.UatGroupNamePattern = 'GRP-{Vendor}-{AppName}-{Version}-UAT'
    $g = Resolve-MigUatGroupName -Name (ConvertFrom-MigPackageName -FullName 'Acme_Widget_x64_4.2.9-0001_ENU')
    $script:Cfg.UatGroupNamePattern = 'MDM_MN_SWW_{Vendor}_{AppName}_UAT'
    $g -eq 'GRP-Acme-Widget-429-UAT'
}

Write-Host "`n=== registry hive prefixing ===" -ForegroundColor Cyan
T 'bare SOFTWARE gets HKLM'   { (Add-MigHkeyPrefix 'SOFTWARE\Vendor\App') -eq 'HKEY_LOCAL_MACHINE\SOFTWARE\Vendor\App' }
T 'HKLM:\ is normalised'      { (Add-MigHkeyPrefix 'HKLM:\SOFTWARE\X')    -eq 'HKEY_LOCAL_MACHINE\SOFTWARE\X' }
T 'HKLM\ is normalised'       { (Add-MigHkeyPrefix 'HKLM\SOFTWARE\X')     -eq 'HKEY_LOCAL_MACHINE\SOFTWARE\X' }
T 'already-qualified is kept' { (Add-MigHkeyPrefix 'HKEY_CURRENT_USER\S') -eq 'HKEY_CURRENT_USER\S' }
T 'HKCU:\ is normalised'      { (Add-MigHkeyPrefix 'HKCU:\Soft')          -eq 'HKEY_CURRENT_USER\Soft' }

Write-Host "`n=== operator / datatype mapping ===" -ForegroundColor Cyan
T 'IsEquals -> equal'                 { (ConvertTo-MigGraphOperator 'IsEquals') -eq 'equal' }
T 'GreaterEquals -> greaterThanOrEqual' { (ConvertTo-MigGraphOperator 'GreaterEquals') -eq 'greaterThanOrEqual' }
T 'NotEquals -> notEqual'             { (ConvertTo-MigGraphOperator 'NotEquals') -eq 'notEqual' }
T 'unknown operator -> equal'         { (ConvertTo-MigGraphOperator 'Whatever') -eq 'equal' }
T 'Version -> version'                { (ConvertTo-MigDetectionType 'Version') -eq 'version' }
T 'String -> string'                  { (ConvertTo-MigDetectionType 'String') -eq 'string' }
T 'Int64 -> integer'                  { (ConvertTo-MigDetectionType 'Int64') -eq 'integer' }

Write-Host "`n=== placeholder detection ===" -ForegroundColor Cyan
T 'empty is a placeholder'                { (Test-MigPlaceholderText '') -eq $true }
T '"Click here to enter text." caught'    { (Test-MigPlaceholderText 'Click here to enter text.') -eq $true }
T '"n/a" caught'                          { (Test-MigPlaceholderText 'N/A') -eq $true }
T 'real text is not a placeholder'        { (Test-MigPlaceholderText 'Compact CAD viewer.') -eq $false }

Write-Host "`n=== description from the content documents ===" -ForegroundColor Cyan
$v4root = Join-Path $fix 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'
$v3root = Join-Path $fix 'Contoso_TestAppV3_x64_1.0.0-0001_MUL'
$d = Get-MigDescriptionFromContent -ContentPath $v4root -PackageName 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'
T 'short description read from the docx'    { $d.Short -match 'Compact CAD viewer' }
T 'detailed description read from the docx' { $d.Detailed -match 'registers the file associations' }
T 'the source document is recorded'         { $d.Source -match 'Installation instructions.docx' }
$dv3 = Get-MigDescriptionFromContent -ContentPath $v3root -PackageName 'Contoso_TestAppV3_x64_1.0.0-0001_MUL'
T 'placeholder short cell is rejected'      { -not $dv3.Short }
T 'detailed cell still read'                { $dv3.Detailed -match 'legacy client' }

$nm4 = ConvertFrom-MigPackageName -FullName 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'
$r1 = Resolve-MigDescription -SccmDescription 'A proper SCCM description.' -SccmLocalizedDescription '' -ContentPath $v4root -Name $nm4
T 'SCCM description wins when present'      { $r1.Source -eq 'SCCM' -and $r1.Text -eq 'A proper SCCM description.' }
$r2 = Resolve-MigDescription -SccmDescription '' -SccmLocalizedDescription '' -ContentPath $v4root -Name $nm4
T 'falls back to the document'              { $r2.Source -match 'Document' -and $r2.Source -match 'short\+detailed' }
T 'both descriptions are combined'          { $r2.Text -match 'Compact CAD viewer' -and $r2.Text -match 'registers the file associations' }
$r3 = Resolve-MigDescription -SccmDescription '' -SccmLocalizedDescription '' -ContentPath (Join-Path $fix 'nope') -Name $nm4
T 'generated as the last resort'            { $r3.Source -eq 'Generated' -and $r3.Text -match 'Contoso TestAppV4 2.5.1' }
$r4 = Resolve-MigDescription -SccmDescription 'Click here to enter text.' -SccmLocalizedDescription '' -ContentPath $v4root -Name $nm4
T 'a placeholder in SCCM is not trusted'    { $r4.Source -match 'Document' }

Write-Host "`n=== icon resolution ===" -ForegroundColor Cyan
$script:Cfg.NormalizeIconTo256 = $true
$goodPng = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $tool 'Assets\DefaultAppIcon.png')))
$i1 = Resolve-MigIcon -SccmIconBase64 $goodPng -ContentPath $v4root
T 'a valid SCCM icon is used'            { $i1.Source -eq 'SCCM' -and $i1.Base64 }
T 'the SCCM icon is normalised to 256'   { $i1.Detail -match '256x256' }
$icoBytes = [IO.File]::ReadAllBytes((Join-Path $v4root 'Icons\TestAppV4.ico'))
$i2 = Resolve-MigIcon -SccmIconBase64 ([Convert]::ToBase64String($icoBytes)) -ContentPath $v4root
T 'an .ico in SCCM is converted to PNG'  { $i2.Source -eq 'SCCM' -and $i2.Detail -match 'converted to PNG' }
T 'the conversion really produces a PNG' {
    $b = [Convert]::FromBase64String($i2.Base64)
    $b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47
}
$i3 = Resolve-MigIcon -SccmIconBase64 'this-is-not-base64-image-data!!' -ContentPath $v4root
T 'a corrupt SCCM icon falls through to the content' { $i3.Source -eq 'Content' -and $i3.Detail -match 'TestAppV4.ico' }
$i4 = Resolve-MigIcon -SccmIconBase64 '' -ContentPath $v4root
T 'no SCCM icon -> content icon'         { $i4.Source -eq 'Content' }
T 'content icon becomes a real PNG' {
    $b = [Convert]::FromBase64String($i4.Base64); $b[0] -eq 0x89 -and $b[1] -eq 0x50
}
$i5 = Resolve-MigIcon -SccmIconBase64 '' -ContentPath $v3root
T 'nothing anywhere -> the default icon' { $i5.Source -eq 'Default' }
T 'the default icon is a valid PNG too' {
    $b = [Convert]::FromBase64String($i5.Base64); $b[0] -eq 0x89 -and $b[1] -eq 0x50
}
$script:Cfg.NormalizeIconTo256 = $false
$i6 = Resolve-MigIcon -SccmIconBase64 '' -ContentPath $v3root
T 'normalising can be switched off'      { $i6.Detail -notmatch '256x256' }
$script:Cfg.NormalizeIconTo256 = $true

Write-Host "`n=== PSADT generation detection ===" -ForegroundColor Cyan
$p3 = Resolve-MigDeployment -ContentFolder $v3root
T 'v3 package detected'              { $p3.Generation -eq 'PSADT v3' }
T 'v3 setup file'                    { $p3.SetupFile -eq 'Deploy-Application.exe' }
T 'v3 install command uses ServiceUI'{ $p3.InstallCmd -match 'ServiceUI\.exe -process:explorer\.exe Deploy-Application\.exe Install' }
T 'v3 uninstall command'             { $p3.UninstallCmd -match 'Deploy-Application\.exe Uninstall' }
T 'v3 asks for utilities staging'    { $p3.StageUtilities -eq $true }
$p4 = Resolve-MigDeployment -ContentFolder $v4root
T 'v4 package detected'              { $p4.Generation -eq 'PSADT v4' }
T 'v4 setup file'                    { $p4.SetupFile -eq 'Invoke-AppDeployToolkit.exe' }
T 'v4 command has no ServiceUI'      { $p4.InstallCmd -eq 'Invoke-AppDeployToolkit.exe Install' -and $p4.InstallCmd -notmatch 'ServiceUI' }
T 'v4 nested launcher root is found' { $p4.Root -match 'MUL_x64_0001$' }
T 'v4 does not stage utilities'      { $p4.StageUtilities -eq $false }
T 'a toolkit-free folder is explained' { (Resolve-MigDeployment -ContentFolder (Join-Path $v4root 'Icons')).Reason -match 'no install command line' }

Write-Host "`n=== scenario 3: a plain installer (no toolkit) ===" -ForegroundColor Cyan
$plainRoot = Join-Path $fix 'Contoso_PlainSetup_x64_9.9.9-0001_ENU'
$plainBin  = Join-Path $plainRoot 'Source'
$pp = Resolve-MigDeployment -ContentFolder $plainBin -SccmInstall '"setup.exe" /S /v"/qn"' -SccmUninstall 'setup.exe /uninstall /S'
T 'recognised as a plain installer'   { $pp.Generation -eq 'Plain installer' }
T 'wraps the folder holding the exe'  { $pp.Root -eq $plainBin }
T 'the setup file is the SCCM target' { $pp.SetupFile -eq 'setup.exe' }
T 'the SCCM command is reused'        { $pp.InstallCmd -match [regex]::Escape('setup.exe /S /v"/qn"') }
T 'it is wrapped in ServiceUI'        { $pp.InstallCmd -match '^\.\\ServiceUI\.exe -process:explorer\.exe ' }
T 'the uninstall command too'         { $pp.UninstallCmd -match '^\.\\ServiceUI\.exe .*setup\.exe /uninstall /S$' }
T 'ServiceUI gets staged'             { $pp.StageUtilities -eq $true }
T 'the user is told what happened'    { $pp.Explain -match 'Plain installer' -and $pp.Explain -match 'ServiceUI' }
$ppNoUn = Resolve-MigDeployment -ContentFolder $plainBin -SccmInstall 'setup.exe /S' -SccmUninstall ''
T 'a missing uninstall is flagged'    { $ppNoUn.NoUninstall -eq $true -and -not $ppNoUn.UninstallCmd }
$ppMsi = Resolve-MigDeployment -ContentFolder $plainBin -SccmInstall 'msiexec /i "setup.exe" /qn' -SccmUninstall ''
T 'msiexec is not mistaken for the payload' { $ppMsi.SetupFile -eq 'setup.exe' }
$ppNone = Resolve-MigDeployment -ContentFolder $plainBin -SccmInstall '' -SccmUninstall ''
T 'no toolkit AND no SCCM command -> a clear reason' { $ppNone.Reason -match 'no install command line' }
$ppGone = Resolve-MigDeployment -ContentFolder $plainBin -SccmInstall 'notthere.exe /S' -SccmUninstall ''
T 'a command naming a missing file -> a clear reason' { $ppGone.Reason -match 'is not present in the content location' }

Write-Host "`n=== the search only climbs INSIDE the package ===" -ForegroundColor Cyan
$roots = @(Get-MigSearchRoots -ContentPath $plainBin -MaxUp 2 -PackageName 'Contoso_PlainSetup_x64_9.9.9-0001_ENU')
T 'the content folder is searched'    { $roots -contains $plainBin }
T 'the package root is searched'      { $roots -contains $plainRoot }
T 'it stops AT the package root'      { $roots.Count -eq 2 -and -not ($roots -contains $fix) }
$roots2 = @(Get-MigSearchRoots -ContentPath $plainBin -MaxUp 2 -PackageName 'SomethingElse')
T 'a WRONG package name still respects MaxUp' { $roots2.Count -le 3 }
T 'NO package name means no climbing at all' { @(Get-MigSearchRoots -ContentPath $plainBin -MaxUp 2).Count -eq 1 }

Write-Host "`n=== icon + description found one level up ===" -ForegroundColor Cyan
$ic = Resolve-MigIcon -SccmIconBase64 '' -ContentPath $plainBin -PackageName 'Contoso_PlainSetup_x64_9.9.9-0001_ENU'
T 'the Icons folder above is found'   { $ic.Source -eq 'Content' -and $ic.Detail -match 'PlainSetup.ico' }
$de = Get-MigDescriptionFromContent -ContentPath $plainBin -PackageName 'Contoso_PlainSetup_x64_9.9.9-0001_ENU'
T 'the GERMAN form above is read'     { $de.Detailed -match 'unbeaufsichtigt' }
T 'a German placeholder is rejected'  { -not $de.Short }
T 'the source document is recorded'   { $de.Source -match 'Installationsanweisung.docx' }
$deName = ConvertFrom-MigPackageName -FullName 'Contoso_PlainSetup_x64_9.9.9-0001_ENU'
$deR = Resolve-MigDescription -SccmDescription '' -SccmLocalizedDescription '' -ContentPath $plainBin -Name $deName
T 'German detail becomes the description' { $deR.Text -match 'unbeaufsichtigt' -and $deR.Source -match 'detailed' }

Write-Host "`n=== the commands come from SCCM for every kind ===" -ForegroundColor Cyan
$sc3 = Resolve-MigDeployment -ContentFolder $v3root -SccmInstall '"Deploy-Application.exe" Install -DeployMode Silent' -SccmUninstall '"Deploy-Application.exe" Uninstall'
T 'v3 takes the SCCM command'        { $sc3.CommandSource -eq 'SCCM' }
T 'v3 keeps the SCCM switches'       { $sc3.InstallCmd -match '-DeployMode Silent' }
T 'v3 wraps it in ServiceUI'         { $sc3.InstallCmd -eq '.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Install -DeployMode Silent' }
T 'v3 unquotes the leading exe'      { $sc3.InstallCmd -notmatch '"Deploy-Application.exe"' }
T 'v3 wraps the uninstall too'       { $sc3.UninstallCmd -eq '.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Uninstall' }
$sc4 = Resolve-MigDeployment -ContentFolder $v4root -SccmInstall '"Invoke-AppDeployToolkit.exe" Install' -SccmUninstall '"Invoke-AppDeployToolkit.exe" Uninstall'
T 'v4 takes the SCCM command'        { $sc4.CommandSource -eq 'SCCM' }
T 'v4 is NOT wrapped in ServiceUI'   { $sc4.InstallCmd -notmatch 'ServiceUI' -and $sc4.InstallCmd -eq '"Invoke-AppDeployToolkit.exe" Install' }
$scNone = Resolve-MigDeployment -ContentFolder $v3root -SccmInstall '' -SccmUninstall ''
T 'no SCCM command -> the launcher default, and it says so' { $scNone.CommandSource -match 'launcher default' }
T 'the fallback is still ServiceUI-wrapped' { $scNone.InstallCmd -match '^\.\\ServiceUI\.exe -process:explorer\.exe Deploy-Application\.exe Install$' }
T 'an already-wrapped command is not double-wrapped' {
    (ConvertTo-MigServiceUiCommand '.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Install') -eq '.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Install'
}

Write-Host "`n=== content size ===" -ForegroundColor Cyan
T 'folder size is measured'          { (Get-MigFolderSize -Path $v4root) -gt 1000 }
T 'a missing folder returns 0'       { (Get-MigFolderSize -Path (Join-Path $fix 'nope')) -eq 0 }

Write-Host "`n=== .intunewin build (real IntuneWinAppUtil) ===" -ForegroundColor Cyan
$script:Sync = $null
$work4 = Join-Path $sp 'work_v4'
if (Test-Path $work4) { Remove-Item $work4 -Recurse -Force }
New-Item $work4 -ItemType Directory -Force | Out-Null
$script:BatchLogPath = Join-Path $work4 'batch.log'; New-Item -Path $script:BatchLogPath -ItemType File -Force | Out-Null
$script:AppLogPath = $null
$iw4 = New-MigIntuneWinPackage -SourceContent $p4.Root -FullName 'Contoso_TestAppV4_x64_2.5.1-0003_ENU' -WorkFolder $work4 -Generation 'PSADT v4' -SetupFile $p4.SetupFile -InstallCommand $p4.InstallCmd
T 'v4 .intunewin was produced'       { Test-Path -LiteralPath $iw4 }
T 'it is named after the package'    { (Split-Path -Leaf $iw4) -eq 'Contoso_TestAppV4_x64_2.5.1-0003_ENU.intunewin' }
T 'the staged content is kept'       { Test-Path -LiteralPath (Join-Path $work4 'StagedContent\Invoke-AppDeployToolkit.exe') }
T 'a build manifest is written'      { Test-Path -LiteralPath (Join-Path $work4 '_IntuneWin-manifest.txt') }
T 'v4 staged NO ServiceUI'           { -not (Test-Path -LiteralPath (Join-Path $work4 'StagedContent\ServiceUI.exe')) }
$meta4 = Get-MigIntuneWinMetadata -Path $iw4
T 'Detection.xml is readable'        { $meta4.InnerFileName -and $meta4.Size -gt 0 }
T 'encryption info is present'       { "$($meta4.Enc.EncryptionKey)".Length -gt 10 -and "$($meta4.Enc.Mac)".Length -gt 10 }
$pay = Expand-MigEncryptedPayload -IntuneWinPath $iw4 -InnerFileName $meta4.InnerFileName -WorkFolder $work4
T 'the encrypted payload extracts'   { (Test-Path -LiteralPath $pay) -and (Get-Item -LiteralPath $pay).Length -gt 0 }
Remove-Item -LiteralPath $pay -Force

$work3 = Join-Path $sp 'work_v3'
if (Test-Path $work3) { Remove-Item $work3 -Recurse -Force }
New-Item $work3 -ItemType Directory -Force | Out-Null
$iw3 = New-MigIntuneWinPackage -SourceContent $p3.Root -FullName 'Contoso_TestAppV3_x64_1.0.0-0001_MUL' -WorkFolder $work3 -Generation 'PSADT v3' -SetupFile $p3.SetupFile -StageUtilities -InstallCommand $p3.InstallCmd
T 'v3 .intunewin was produced'       { Test-Path -LiteralPath $iw3 }
T 'v3 staged ServiceUI.exe'          { Test-Path -LiteralPath (Join-Path $work3 'StagedContent\ServiceUI.exe') }
T 'v3 staged Deploy-Application.exe' { Test-Path -LiteralPath (Join-Path $work3 'StagedContent\Deploy-Application.exe') }
T 'v3 staged the .exe.config'        { Test-Path -LiteralPath (Join-Path $work3 'StagedContent\Deploy-Application.exe.config') }
T 'the SOURCE package was NOT touched' { -not (Test-Path -LiteralPath (Join-Path $p3.Root 'ServiceUI.exe')) }
T 'IntuneWinAppUtil.exe never ships inside' { -not (Test-Path -LiteralPath (Join-Path $work3 'StagedContent\IntuneWinAppUtil.exe')) }

Write-Host "`n=== detection JSON shape ===" -ForegroundColor Cyan
# a single rule must still serialise as an ARRAY, or Graph rejects the create
$single = @(@{ '@odata.type' = '#microsoft.graph.win32LobAppRegistryDetection'; keyPath = 'HKEY_LOCAL_MACHINE\X'; valueName = 'Revision' })
$body = @{ detectionRules = @($single) }
$js = $body | ConvertTo-Json -Depth 20 -Compress
T 'one detection rule serialises as [ ... ]' { $js -match '"detectionRules":\[\{' -and $js -notmatch '"detectionRules":\[\[' }

Write-Host "`n=== return codes ===" -ForegroundColor Cyan
$digest = ([xml]@'
<AppMgmtDigest><DeploymentType><Installer><CustomData><ExitCodes>
  <ExitCode Code="0" Class="Success"/>
  <ExitCode Code="3010" Class="SoftReboot"/>
  <ExitCode Code="1618" Class="FastRetry"/>
  <ExitCode Code="9999" Class="Failure"/>
</ExitCodes></CustomData></Installer></DeploymentType></AppMgmtDigest>
'@).AppMgmtDigest
$rc = Get-MigReturnCodes -Digest $digest
T 'SCCM exit codes are carried over'  { @($rc | Where-Object { $_.returnCode -eq 9999 -and $_.type -eq 'failed' }).Count -eq 1 }
T 'FastRetry maps to retry'           { @($rc | Where-Object { $_.returnCode -eq 1618 -and $_.type -eq 'retry' }).Count -eq 1 }
T 'SoftReboot maps to softReboot'     { @($rc | Where-Object { $_.returnCode -eq 3010 -and $_.type -eq 'softReboot' }).Count -eq 1 }
T 'defaults fill the gaps'            { @($rc | Where-Object { $_.returnCode -eq 1641 -and $_.type -eq 'hardReboot' }).Count -eq 1 }
T 'no duplicate return codes'         { $codes = @($rc | ForEach-Object { $_.returnCode }); @($codes).Count -eq @($codes | Sort-Object -Unique).Count }
T 'return codes serialise as JSON'    { (@{ returnCodes = @($rc) } | ConvertTo-Json -Depth 5 -Compress) -match '"returnCodes":\[\{' }

Write-Host "`n=== reports ===" -ForegroundColor Cyan
$repFolder = Join-Path $sp 'report_test'
if (Test-Path $repFolder) { Remove-Item $repFolder -Recurse -Force }
New-Item $repFolder -ItemType Directory -Force | Out-Null
$fake = @(
  [pscustomobject]@{ Application='Contoso_A_x64_1.0-1_MUL'; Status='Success'; AppId='11111111-2222-3333-4444-555555555555'
                     UatGroup='MDM_MN_SWW_Contoso_A_UAT'; UatGroupId='aaaa-bbbb'; UatGroupExists=$true; Publisher='Contoso'
                     Version='1.0'; Revision='1'; Psadt='v4'; IconSource='SCCM'; IconDetail='converted to PNG, 256x256'
                     DescriptionSrc='Document: Installation instructions.docx (short+detailed)'
                     Detection='branding: HKEY_LOCAL_MACHINE\Software\X\A [Revision] equal 1'; ContentSizeMB=2048
                     Message='Created.'; Warnings=''; LogPath='' }
  [pscustomobject]@{ Application='Contoso_B & Sons <x86>'; Status='Failed'; AppId=''; UatGroup=''; UatGroupId=''
                     UatGroupExists=$false; Publisher=''; Version=''; Revision=''; Psadt=''; IconSource=''; IconDetail=''
                     DescriptionSrc=''; Detection=''; ContentSizeMB=0
                     Message='Content location "\\srv\share" unreachable & <not> found'; Warnings='large content'; LogPath='' }
  [pscustomobject]@{ Application='Contoso_C_x64_2.0-1_MUL'; Status='Skipped'; AppId='99999999-0000-0000-0000-000000000000'
                     UatGroup='MDM_MN_SWW_Contoso_C_UAT'; UatGroupId=''; UatGroupExists=$false; Publisher='Contoso'; Version='2.0'; Revision='1'
                     Psadt='v3'; IconSource='Default'; IconDetail='default icon (256x256)'; DescriptionSrc='Generated'
                     Detection=''; ContentSizeMB=100; Message='Skipped - HIGHER version (v9.0) already in Intune.'; Warnings='default icon used'; LogPath='' }
)
$rep = Write-MigReports -Results $fake -RunFolder $repFolder
T 'HTML report written'  { Test-Path -LiteralPath $rep.Html }
T 'ONLY the HTML report' {
    (-not (Test-Path -LiteralPath (Join-Path $repFolder 'MigrationReport.csv'))) -and
    (-not (Test-Path -LiteralPath (Join-Path $repFolder 'MigrationReport.json')))
}
$h = Get-Content -LiteralPath $rep.Html -Raw
T 'HTML has the counters'         { $h -match '<div class="n">1</div><div class="l">Migrated' -and $h -match '<div class="n">1</div><div class="l">Failed' }
T 'HTML shows the App ID'         { $h -match '11111111-2222-3333-4444-555555555555' }
T 'HTML shows the UAT group'      { $h -match 'MDM_MN_SWW_Contoso_A_UAT' }
T 'HTML lists every group needed' { $h -match 'MDM_MN_SWW_Contoso_C_UAT' }
T 'HTML drops the noisy columns'  { $h -notmatch '<th>Publisher' -and $h -notmatch '<th>Detection' }
T 'failures are listed first'     { $h.IndexOf('Contoso_B') -lt $h.IndexOf('Contoso_A_x64') }
T 'HTML escapes angle brackets'   { $h -match 'Contoso_B &amp; Sons &lt;x86&gt;' -and $h -notmatch 'Contoso_B & Sons <x86>' }
T 'every application is in the table' { @([regex]::Matches($h, '<tr>')).Count -ge 3 }
T 'the note stays short'          {
    # the long failure message is trimmed, not dumped in full
    $cell = [regex]::Match($h, '(?s)Contoso_B.*?<td class="wrap">(?<n>.*?)</td>')
    $cell.Success -and $cell.Groups['n'].Value.Length -lt 300
}
T 'a skip names the situation'    { $h -match 'HIGHER version \(v9\.0\) already in Intune' }
T 'a skip is not a generic phrase' { $h -notmatch '>already in Intune<' }

Write-Host "`n=== version comparison + lifecycle ===" -ForegroundColor Cyan
T '1.0 < 2.0'                       { (Compare-MigVersion '1.0' '2.0') -lt 0 }
T '2.5.1 > 2.5'                     { (Compare-MigVersion '2.5.1' '2.5') -gt 0 }
T 'equal is 0'                      { (Compare-MigVersion '23.006.20320' '23.006.20320') -eq 0 }
T 'single-part versions work'       { (Compare-MigVersion '8' '9') -lt 0 }
T 'odd versions do not throw'       { $null -ne (Compare-MigVersion '2024a' 'R2') }
T 'lifecycle from JSON notes'       { (Get-MigAppLifecycle -App ([pscustomobject]@{ notes = '{"lifecycle":"LIVE","notes":"x"}' })) -eq 'LIVE' }
T 'lifecycle from loose text'       { (Get-MigAppLifecycle -App ([pscustomobject]@{ notes = 'lifecycle: retired' })) -eq 'RETIRED' }
T 'plain notes -> unknown'          { (Get-MigAppLifecycle -App ([pscustomobject]@{ notes = 'Created by the packaging team.' })) -eq 'unknown' }
T 'no notes -> unknown'             { (Get-MigAppLifecycle -App ([pscustomobject]@{ notes = '' })) -eq 'unknown' }

Write-Host "`n=== the uninstall-signature shield (Package Builder's 2nd check) ===" -ForegroundColor Cyan
$sigRules = @(
  @{ '@odata.type'='#microsoft.graph.win32LobAppRegistryDetection'; keyPath='HKEY_LOCAL_MACHINE\Software\VWG\CM\Contoso_App_x64_1.0-1_MUL'; valueName='Revision'; detectionValue='1'; check32BitOn64System=$false }
  @{ '@odata.type'='#microsoft.graph.win32LobAppRegistryDetection'; keyPath='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{AAA}'; valueName='DisplayVersion'; detectionValue='1.0'; check32BitOn64System=$true }
  @{ '@odata.type'='#microsoft.graph.win32LobAppProductCodeDetection'; productCode='{AAA-BBB}' }
)
$sig = Get-MigUninstallSignature -Rules $sigRules
T 'the branding rule is NOT the identity' { $sig.KeyPath -notmatch 'VWG' }
T 'the uninstall key IS the identity'     { $sig.KeyPath -match 'CurrentVersion\\Uninstall' -and $sig.Version -eq '1.0' -and $sig.Is32Bit -eq $true }
T 'the product code is captured'          { $sig.ProductCode -eq '{AAA-BBB}' }
T 'an identical app matches'              { (Test-MigAppMatchesUninstall -DetectionRules $sigRules -Sig $sig).Match -eq $true }
T 'and is recognised as branded'          { (Test-MigAppMatchesUninstall -DetectionRules $sigRules -Sig $sig).Branded -eq $true }
T 'an UNBRANDED copy still matches' {
    $other = @(@{ '@odata.type'='#microsoft.graph.win32LobAppRegistryDetection'; keyPath='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{AAA}'; valueName='DisplayVersion'; detectionValue='1.0'; check32BitOn64System=$true })
    $r = Test-MigAppMatchesUninstall -DetectionRules $other -Sig $sig
    $r.Match -eq $true -and $r.Branded -eq $false
}
T 'a different version does NOT match' {
    $other = @(@{ '@odata.type'='#microsoft.graph.win32LobAppRegistryDetection'; keyPath='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{AAA}'; valueName='DisplayVersion'; detectionValue='2.0'; check32BitOn64System=$true })
    (Test-MigAppMatchesUninstall -DetectionRules $other -Sig $sig).Match -eq $false
}
T 'the other hive does NOT match' {
    $other = @(@{ '@odata.type'='#microsoft.graph.win32LobAppRegistryDetection'; keyPath='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{AAA}'; valueName='DisplayVersion'; detectionValue='1.0'; check32BitOn64System=$false })
    (Test-MigAppMatchesUninstall -DetectionRules $other -Sig $sig).Match -eq $false
}
T 'a branding-only app has no signature' {
    $only = @(@{ '@odata.type'='#microsoft.graph.win32LobAppRegistryDetection'; keyPath='HKEY_LOCAL_MACHINE\Software\VWG\CM\X'; valueName='Revision'; detectionValue='1' })
    $s2 = Get-MigUninstallSignature -Rules $only
    (-not $s2.KeyPath) -and (-not $s2.ProductCode)
}

Write-Host "`n=== another brand: no lifecycle, its own group format ===" -ForegroundColor Cyan
T 'a different group format just works' {
    $keep = $script:Cfg.UatGroupNamePattern
    $script:Cfg.UatGroupNamePattern = 'GRP-{Vendor}-{AppName}-UAT'
    $g = Resolve-MigUatGroupName -Name (ConvertFrom-MigPackageName -FullName 'Acme_Widget_x64_1.0-1_ENU')
    $script:Cfg.UatGroupNamePattern = $keep
    $g -eq 'GRP-Acme-Widget-UAT'
}
T 'Notes is a single plain line'  { $script:Cfg.NotesText -eq 'Created by SCCM2IntuneMigrator' -and $script:Cfg.NotesText -notmatch '[{}]' }
T 'the shield can be turned off'  { $null -ne $script:Cfg.UninstallSignatureShield }


Write-Host "`n=== running on an SCCM console machine ===" -ForegroundColor Cyan
T 'the installed console is preferred over the bundled copy' {
    # the order matters: the console on the machine matches the site's version, the bundled copy
    # only matches wherever it was taken from
    $src = Get-Content -LiteralPath (Join-Path $tool 'SCCM2IntuneMigrator.ps1') -Raw
    $body = [regex]::Match($src, '(?s)function Connect-MigSccm \{.*?\r?\n\}').Value
    $iInstalled = $body.IndexOf('SMS_ADMIN_UI_PATH')
    $iBundled   = $body.IndexOf("Lib\ConfigurationManager\ConfigurationManager.psd1")
    if ($iInstalled -lt 0) { 'installed-console path not checked at all' }
    elseif ($iBundled -lt 0) { 'bundled copy not used as a fallback' }
    elseif ($iInstalled -lt $iBundled) { $true }
    else { 'the bundled copy is still tried first' }
}
T 'the module path is built without a ".." segment' {
    # Join-Path "$env:SMS_ADMIN_UI_PATH" '..\ConfigurationManager.psd1' produces a path with '..'
    # in it, which Test-Path handles but is needlessly fragile; Split-Path -Parent is exact
    $src = Get-Content -LiteralPath (Join-Path $tool 'SCCM2IntuneMigrator.ps1') -Raw
    $body = [regex]::Match($src, '(?s)function Connect-MigSccm \{.*?\r?\n\}').Value
    $body -notmatch '\.\.\\ConfigurationManager\.psd1'
}
T 'a missing module names BOTH places it looked' {
    $src = Get-Content -LiteralPath (Join-Path $tool 'SCCM2IntuneMigrator.ps1') -Raw
    $body = [regex]::Match($src, '(?s)function Connect-MigSccm \{.*?\r?\n\}').Value
    $body -match 'Looked for' -and $body -match '\$tried'
}

Write-Host "`n=== free-space pre-check ===" -ForegroundColor Cyan
T 'a real local path reports free space'  { (Get-MigFreeSpace -Path $env:TEMP) -gt 0 }
T 'a UNC path is not judged'              { (Get-MigFreeSpace -Path '\\srv\share\x') -eq -1 }
T 'an empty path does not throw'          { (Get-MigFreeSpace -Path '') -eq -1 }
T 'a nonsense path does not throw'        { (Get-MigFreeSpace -Path '::::') -eq -1 }
T 'the work-space factor is configured'   { [double]$script:Cfg.WorkSpaceFactor -ge 2 }
T 'the check runs BEFORE the content copy' {
    # it must sit between measuring the content and building the .intunewin, or it would only
    # fire after the copy that fills the disk
    $src = Get-Content -LiteralPath (Join-Path $tool 'SCCM2IntuneMigrator.ps1') -Raw
    $iMeasure = $src.IndexOf('Measuring the source content')
    $iCheck   = $src.IndexOf('Not enough free space to package this application')
    $iBuild   = $src.IndexOf('# ---------- 8. build the .intunewin')
    ($iMeasure -gt 0) -and ($iCheck -gt $iMeasure) -and ($iBuild -gt $iCheck)
}
T 'the message says where to point ReportRoot' {
    $src = Get-Content -LiteralPath (Join-Path $tool 'SCCM2IntuneMigrator.ps1') -Raw
    $src -match 'point ReportRoot in settings.json at a bigger drive'
}


Write-Host "`n=== safe names ===" -ForegroundColor Cyan
T 'illegal characters removed'    { (Get-MigSafeName 'App: v1/2 <x86>?') -notmatch '[\\/:*?"<>|]' }
T 'spaces become underscores'     { (Get-MigSafeName 'My App Name') -eq 'My_App_Name' }

Write-Host ""
Write-Host "PASSED $script:pass   FAILED $script:fail" -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail) { exit 1 }
