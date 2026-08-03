##############################################################
# Test-Build.ps1  -  run on the box:  pwsh -File Test-Build.ps1
# Locks in Plan section 1 (version swap) and section 2 (uninstall
# block). If a future change reintroduces the recurring bug, a test
# here fails LOUDLY instead of surfacing "after some days".
##############################################################
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
# Find the modules whether they sit next to this test or one level up.
function Resolve-Module($name) {
    foreach ($p in @("$here\$name", "$here\..\$name")) { if (Test-Path $p) { return $p } }
    throw "Cannot find $name (looked in '$here' and its parent)."
}
. (Resolve-Module 'Core.ps1')
. (Resolve-Module 'Theme.ps1')
. (Resolve-Module 'BundledMsi.ps1')
. (Resolve-Module 'Snapshot.ps1')
. (Resolve-Module 'Predecessor.ps1')
. (Resolve-Module 'Build.ps1')
. (Resolve-Module 'MstBuilder.ps1')
. (Resolve-Module 'Source.ps1')
. (Resolve-Module 'Screenshots.ps1')
. (Resolve-Module 'Sccm.ps1')
. (Resolve-Module 'Intune.ps1')
. (Resolve-Module 'Assemble.ps1')
. (Resolve-Module 'BrandGpf.ps1')
. (Resolve-Module 'PSADT_V3toV4_Mappings.ps1')
Initialize-Log
# GPF copy has NO MTB PSADT_Template - point template resolution at the GPF template for the fixture builds.
# ONLY TemplateRoot is set: Convert/Features stay absent so every engine test still runs with MTB-default flags.
$script:Settings = @{ Brand = @{ TemplateRoot = 'PSADT_Template_GPF' } }

$fail = 0
function Assert($name, $cond) {
    if ($cond) { Write-Host "PASS $name" -ForegroundColor Green }
    else       { Write-Host "FAIL $name" -ForegroundColor Red; $script:fail++ }
}

# ---- Plan section 1: version swap ----
Assert "full 1.2.3.4 -> 1.5.6.7"        ((Invoke-VersionSwap 'v1.2.3.4 here' '1.2.3.4' '1.5.6.7') -eq 'v1.5.6.7 here')
Assert "folder \1.2\ -> \1.5\"          ((Invoke-VersionSwap 'C:\x\1.2\c' '1.2.3.4' '1.5.6.7') -eq 'C:\x\1.5\c')
Assert "3-part 1.2.3 -> 1.5.6"          ((Invoke-VersionSwap 'ref 1.2.3' '1.2.3.4' '1.5.6.7') -eq 'ref 1.5.6')
Assert "11.2 untouched"                 ((Invoke-VersionSwap 'x11.2y' '1.2.3.4' '1.5.6.7') -eq 'x11.2y')
Assert "1.2.3.4.5 untouched"            ((Invoke-VersionSwap 'a 1.2.3.4.5 b' '1.2.3.4' '1.5.6.7') -eq 'a 1.2.3.4.5 b')
Assert "bare year 2025 untouched"       ((Invoke-VersionSwap 'year 2025' '1.2.3.4' '1.5.6.7') -eq 'year 2025')
Assert "PrusaSlicer 2.7.4 -> 2.9.2"     ((Invoke-VersionSwap 'dir 2.7 v2.7.4' '2.7.4' '2.9.2') -eq 'dir 2.9 v2.9.2')
# nCode-style: 3-part name-version 24.1.0 -> 4-part new 26.0.0.0 must ALSO swap a 4-part DisplayVersion + year-form.
Assert "DisplayVersion 24.1.0.0 -> 26.0.0.0" ((Invoke-VersionSwap '[DisplayVersion=24.1.0.0]' '24.1.0' '26.0.0.0') -eq '[DisplayVersion=26.0.0.0]')
Assert "appVersion 24.1.0 -> 26.0.0"        ((Invoke-VersionSwap "v='24.1.0'" '24.1.0' '26.0.0.0') -eq "v='26.0.0'")
Assert "year-form 2024.1 -> 2026.0"         ((Invoke-VersionSwap 'nCode 2024.1 64-bit' '24.1.0' '26.0.0.0') -eq 'nCode 2026.0 64-bit')
Assert "year-form lnk 2024.1 -> 2026.0"     ((Invoke-VersionSwap 'nCode 2024.1.lnk' '24.1.0' '26.0.0.0') -eq 'nCode 2026.0.lnk')
# Predecessor reuse: SoftIdent embedded [DisplayVersion=...] is bumped to the NEW version even when the predecessor's real
# DisplayVersion differs from the version-swap token (team-reported: Inno T1_is1 stayed at the old 3.5.17129.17210).
$siLine = "        SoftIdent = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\T1_is1 [DisplayVersion=3.5.17129.17210]'"
$siOut  = [regex]::Replace($siLine, "(?im)(^[ \t]*SoftIdent[ \t]*=[ \t]*'[^']*\[DisplayVersion[ \t]*=[ \t]*)[^\]']+(\])", '${1}4.0.20204.10321${2}')
Assert "reuse SoftIdent DisplayVersion -> new ver" (($siOut -match '\[DisplayVersion=4\.0\.20204\.10321\]') -and ($siOut -notmatch '3\.5\.17129\.17210') -and ($siOut -match 'T1_is1'))
Assert "reuse SoftIdent w/o DisplayVersion untouched" (("        SoftIdent = 'HKLM:\SOFTWARE\...\Uninstall\{GUID}'" -replace "(?im)(^[ \t]*SoftIdent[ \t]*=[ \t]*'[^']*\[DisplayVersion[ \t]*=[ \t]*)[^\]']+(\])", '${1}9.9${2}') -match "\{GUID\}'$")
# v3->v4 LOG PATH: old flat log-FILE path -> $LogFileMain (a real .log FILE, not the $LogPathMain DIRECTORY); the
# section PHASE is baked into the file name so predecessor-uninstall (pre-install) and main-install differ.
$logIn = @"
##*=============== PRE-INSTALLATION BEGIN ===============
    ## <Perform Pre-Installation tasks here>
    Start-ADTMsiProcess -Action Uninstall -ProductCode '{OLD}' -LogFileName "`$configToolKitLogDir\`$setuplogName"
##*=============== PRE-INSTALLATION END ===============
##*=============== MAIN-INSTALLATION BEGIN ===============
    Start-ADTMsiProcess -Action Install -FilePath `$msi -LogFileName "`$configToolKitLogDir\`$setuplogName"
##*=============== MAIN-INSTALLATION END ===============
"@
$logOut = Convert-LogPathFormat -Text $logIn
Assert "log: old flat path -> `$LogFileMain (file, not folder)" (($logOut -match 'LogFileName "\$LogFileMain"') -and ($logOut -notmatch '\$configToolKitLogDir') -and ($logOut -notmatch '\$setuplogName'))
Assert "log: New-ADTFolder uses `$LogPathMain (dir)"            ($logOut -match 'New-ADTFolder -Path \$LogPathMain')
Assert "log: pre-install -> AppFullName_Setup_PreInstall.log"  ($logOut -match [regex]::Escape('$LogFileMain = "$LogPathMain\$($AppFullName)_Setup_PreInstall.log"'))
Assert "log: main-install -> AppFullName_Setup_Install.log"    ($logOut -match [regex]::Escape('$LogFileMain = "$LogPathMain\$($AppFullName)_Setup_Install.log"'))
Assert "year-form leaves copyright 2023"    ((Invoke-VersionSwap '(C) 2023 Team; date 10/24/2024' '24.1.0' '26.0.0.0') -eq '(C) 2023 Team; date 10/24/2024')
Assert "24.1 inside 2024.1 not double-swapped" ((Invoke-VersionSwap 'x 2024.1 y 24.1.0 z' '24.1.0' '26.0.0.0') -eq 'x 2026.0 y 26.0.0 z')
Assert "1.2.3.4->1.5 (short new) unchanged"  ((Invoke-VersionSwap 'v1.2.3.4' '1.2.3.4' '1.5') -eq 'v1.5')

# ---- LOG-PATH FORMAT: old $configToolKitLogDir\$setuplogName -> $LogPathMain (defined per section via Get-ADTConfig) ----
$logv3 = @'
$adtSession = @{ AppName='App'; AppVersion='1.0.0' }
#*=== CUSTOM APPLICATION VARIABLES BEGIN ===
[string]$setuplogName = $VWG_appFullName + "_" + "Setup" + "_" + $deploymentType + ".log"
[string]$setuplogName1 = "old_Uninstall.log"
#*=== CUSTOM APPLICATION VARIABLES END ===
#*=== PRE-INSTALLATION BEGIN ===
#*=== PRE-INSTALLATION END ===
#*=== MAIN-INSTALLATION BEGIN ===
Start-ADTProcess -FilePath "x.exe" -ArgumentList "/log `"$configToolKitLogDir\$setuplogName`""
Copy-ADTFile -Path "y" -Destination "$configToolKitLogDir\$logfolder\$setuplogName"
#*=== MAIN-INSTALLATION END ===
#*=== POST-INSTALLATION BEGIN ===
#*=== POST-INSTALLATION END ===
#*=== PRE-UNINSTALLATION BEGIN ===
#*=== PRE-UNINSTALLATION END ===
#*=== MAIN-UNINSTALLATION BEGIN ===
Start-ADTProcess -FilePath "z.exe" -ArgumentList "/log `"$configToolKitLogDir\$setuplogName1`""
#*=== MAIN-UNINSTALLATION END ===
#*=== POST-UNINSTALLATION BEGIN ===
#*=== POST-UNINSTALLATION END ===
#*=== PRE-REPAIR BEGIN ===
#*=== PRE-REPAIR END ===
#*=== MAIN-REPAIR BEGIN ===
#*=== MAIN-REPAIR END ===
#*=== POST-REPAIR BEGIN ===
#*=== POST-REPAIR END ===
'@
$logConv = Convert-LogPathFormat -Text $logv3
Assert "logfmt: no `$configToolKitLogDir left"     (-not ($logConv -match '(?i)\$configToolKitLogDir'))
Assert "logfmt: no `$setuplogName left"            (-not ($logConv -match '(?i)\$setuplogName'))
Assert "logfmt: declarations removed"              (-not ($logConv -match '\[string\]\s*\$setuplogName'))
Assert "logfmt: simple flat path -> `$LogFileMain (a FILE)" ($logConv -match [regex]::Escape('/log `"$LogFileMain`"'))
Assert "logfmt: nested keeps subfolder + real filename" ($logConv -match [regex]::Escape('$LogPathMain\$logfolder\$($adtSession.AppName)_$($adtSession.AppVersion)_$($adtSession.DeploymentType).log'))
Assert "logfmt: Get-ADTConfig block in Install"    ($logConv -match '(?s)MAIN-INSTALLATION BEGIN.*?\$adtConfig = Get-ADTConfig.*?\$LogPathMain =.*?MAIN-INSTALLATION END')
Assert "logfmt: Get-ADTConfig block in Uninstall"  ($logConv -match '(?s)MAIN-UNINSTALLATION BEGIN.*?\$adtConfig = Get-ADTConfig.*?MAIN-UNINSTALLATION END')
Assert "logfmt: NO block in section that doesn't log" (-not ($logConv -match '(?s)MAIN-REPAIR BEGIN.*?Get-ADTConfig.*?MAIN-REPAIR END'))
Assert "logfmt: no-op when format absent"          ((Convert-LogPathFormat -Text 'Start-ADTProcess -FilePath x') -eq 'Start-ADTProcess -FilePath x')

# ---- LOG-PATH scaffold-once: pre AND main install both log -> $adtConfig/$LogPathMain/New-ADTFolder defined ONCE for
#      the Install group (shared function scope); only $LogFileMain (phase name) is re-set per section. ----
$logv3c = @'
$adtSession = @{ AppName='App'; AppVersion='1.0.0' }
#*=== CUSTOM APPLICATION VARIABLES BEGIN ===
[string]$setuplogName = "Setup.log"
#*=== CUSTOM APPLICATION VARIABLES END ===
#*=== PRE-INSTALLATION BEGIN ===
Start-ADTProcess -FilePath "pre.exe" -ArgumentList "/log `"$configToolKitLogDir\$setuplogName`""
#*=== PRE-INSTALLATION END ===
#*=== MAIN-INSTALLATION BEGIN ===
Start-ADTProcess -FilePath "x.exe" -ArgumentList "/log `"$configToolKitLogDir\$setuplogName`""
#*=== MAIN-INSTALLATION END ===
#*=== POST-INSTALLATION BEGIN ===
#*=== POST-INSTALLATION END ===
'@
$logC = Convert-LogPathFormat -Text $logv3c
Assert "logfmt: scaffold ($adtConfig) defined ONCE per group"   (([regex]::Matches($logC, '(?m)\$adtConfig = Get-ADTConfig')).Count -eq 1)
Assert "logfmt: New-ADTFolder ONCE per group"                   (([regex]::Matches($logC, 'New-ADTFolder -Path \$LogPathMain')).Count -eq 1)
Assert "logfmt: LogFileMain set per logging section (2x)"       (([regex]::Matches($logC, [regex]::Escape('$LogFileMain = "$LogPathMain'))).Count -eq 2)
Assert "logfmt: pre-install phase = PreInstall"                 ($logC -match [regex]::Escape('_Setup_PreInstall.log'))
Assert "logfmt: main-install reuses LogPathMain (no 2nd scaffold)" (($logC -match '(?s)MAIN-INSTALLATION BEGIN.*?\$LogFileMain =.*?MAIN-INSTALLATION END') -and -not ($logC -match '(?s)MAIN-INSTALLATION BEGIN.*?Get-ADTConfig.*?MAIN-INSTALLATION END'))
# case-insensitive cmdlet rename (PS cmdlets are case-insensitive; 'New-folder' must convert)
if (Get-Command Convert-V3ToV4Content -EA SilentlyContinue) {
    $ci = Convert-V3ToV4Content -Content "New-folder -Path 'x'; copy-file -Path a -Destination b"
    Assert "case-insensitive: New-folder -> New-ADTFolder" ($ci -match 'New-ADTFolder' -and (-not ($ci -match '(?<![\w-])New-folder(?![\w-])')))
    Assert "case-insensitive: copy-file -> Copy-ADTFile"   ($ci -match 'Copy-ADTFile')
}

# ---- Plan section 2: uninstall-previous block ----
$predScript = @'
$adtSession = @{
    AppName='AcmeApp'
    AppVersion='1.2.3.4'
    SoftIdent='AcmeApp [DisplayVersion=1.2.3.4]'
}
#*=== CUSTOM APPLICATION VARIABLES BEGIN ===
#*=== CUSTOM APPLICATION VARIABLES END ===
#*=== PRE-INSTALLATION BEGIN ===
## <Perform Pre-Installation tasks here>
If ((Get-ADTApplication -ProductCode '{11111111-1111-1111-1111-111111111111}')) {
    Write-ADTLogEntry -Message 'Removing old 1.1.0.0'
    Start-ADTMsiProcess -Action Uninstall -ProductCode '{11111111-1111-1111-1111-111111111111}'
}
Copy-ADTFile -Path "$dirSupportFiles\config" -Destination "C:\Pkg\custom\1.2\cfg.ini"
#*=== PRE-INSTALLATION END ===
#*=== MAIN-INSTALLATION BEGIN ===
## <Perform Installation tasks here>
Start-ADTMsiProcess -Action Install -FilePath 'AcmeApp_1.2.3.4.msi' -Transform 'AcmeApp_1.2.3.4.mst' -ProductCode '{22222222-2222-2222-2222-222222222222}'
#*=== MAIN-INSTALLATION END ===
#*=== POST-INSTALLATION BEGIN ===
Write-ADTLogEntry -Message 'Installed AcmeApp 1.2.3.4'
#*=== POST-INSTALLATION END ===
#*=== PRE-UNINSTALLATION BEGIN ===
## <Perform Pre-Uninstallation tasks here>
Close-ADTInstallationProgress
#*=== PRE-UNINSTALLATION END ===
#*=== MAIN-UNINSTALLATION BEGIN ===
## <Perform Uninstallation tasks here>
Start-ADTMsiProcess -Action Uninstall -ProductCode '{22222222-2222-2222-2222-222222222222}'
#*=== MAIN-UNINSTALLATION END ===
#*=== POST-UNINSTALLATION BEGIN ===
#*=== POST-UNINSTALLATION END ===
#*=== PRE-REPAIR BEGIN ===
#*=== PRE-REPAIR END ===
#*=== MAIN-REPAIR BEGIN ===
#*=== MAIN-REPAIR END ===
#*=== POST-REPAIR BEGIN ===
#*=== POST-REPAIR END ===
'@

$model = Read-PredecessorModel -PackageName 'Acme_AcmeApp_x64_1.2.3.4-0001_de-DE' -Content $predScript
$newPkg = @{ Version='1.5.6.7'; MsiFileName='AcmeApp_1.5.6.7.msi'
             ProductCode='{99999999-9999-9999-9999-999999999999}'; SoftIdent='AcmeApp [DisplayVersion=1.5.6.7]' }
# Build onto the REAL blank template (Set-SectionBody inserts into it, preserving its lines).
$tpl = Get-TemplateScript
if (-not $tpl) { Write-Host "WARN: blank template not found - falling back to predecessor-as-template" -ForegroundColor Yellow; $tpl = $predScript }
$out = Build-PredecessorScript -Model $model -NewPkg $newPkg -Template $tpl

Assert "AppVersion = new 1.5.6.7"                 ($out -match "AppVersion\s*=\s*'1\.5\.6\.7'")
Assert "version folder bumped to \1.5\"           ($out -match 'custom\\1\.5\\cfg\.ini')
Assert "post-install log bumped to 1.5.6.7"       ($out -match 'Installed AcmeApp 1\.5\.6\.7')
Assert "MainInstall MSI swapped to new"           (($out -match 'AcmeApp_1\.5\.6\.7\.msi') -and ($out -notmatch 'AcmeApp_1\.2\.3\.4\.msi'))
Assert "MainInstall ProductCode swapped to new"   ($out -match '99999999-9999')
Assert "uninstall-prev block KEEPS predecessor 1.2.3.4" ($out -match 'predecessor version 1\.2\.3\.4')
Assert "uninstall-prev block NOT bumped to new"   ($out -notmatch 'predecessor version 1\.5\.6\.7')
# ---- Plan section 2 (accumulate): keep predecessor's old block AND add one for it ----
Assert "TWO predecessor uninstall blocks"         ((([regex]::Matches($out,'Get-ADTApplication')).Count) -eq 2)
Assert "older block (1.1.0.0 / {1111}) preserved" (($out -match '1\.1\.0\.0') -and ($out -match '11111111-1111'))
Assert "older block NOT bumped to new"            ($out -notmatch 'Removing old 1\.5')
Assert "immediate block targets predecessor PC {2222}" ($out -match '22222222-2222')
Assert "immediate block has predecessor branding key"  ($out -match 'CM\\Acme_AcmeApp_x64_1\.2\.3\.4-0001_de-DE')
Assert "older block precedes newer block"         ($out.IndexOf('11111111-1111') -lt $out.IndexOf('Acme_AcmeApp_x64_1.2.3.4-0001'))
# ---- OPT-OUT bug fix: unchecking "add uninstall previous" must NOT delete the predecessor's OWN uninstall block(s).
#      It only skips the GENERATED immediate-predecessor block; the authored chain stays verbatim. ----
$outNo = Build-PredecessorScript -Model $model -NewPkg $newPkg -Template $tpl -AddUninstallPrevious $false
Assert "opt-out KEEPS predecessor's own block (1.1.0.0/{1111})" (($outNo -match '1\.1\.0\.0') -and ($outNo -match '11111111-1111'))
Assert "opt-out adds NO generated block ({2222} absent)"        ($outNo -notmatch '22222222-2222')
Assert "opt-out leaves exactly the ONE existing block"          ((([regex]::Matches($outNo,'Get-ADTApplication')).Count) -eq 1)

# ---- PRED-OF-PREDECESSOR bump is CHECKBOX-GATED (user rule): the predecessor's own previous-version check (nCode-style,
#      2023.1 / 23.1.0.0) is KEPT verbatim when uninstall-previous is CHECKED (standard: keep + add generated block), but
#      bumped up ONE step (23 -> 24) when UNCHECKED (no generated block, so the kept logic must target the immediate pred).
$ncPred = @'
$adtSession = @{ AppName='nCodeGlyphworks'; AppVersion='24.1.0'; SoftIdent='...nCode 2024.1 64-bit [DisplayVersion=24.1.0.0]' }
#*=== CUSTOM APPLICATION VARIABLES BEGIN ===
#*=== CUSTOM APPLICATION VARIABLES END ===
#*=== PRE-INSTALLATION BEGIN ===
If ((Get-ADTApplication -Name 'nCode 2023.1 64-bit') -and (Test-Path -Path "HKLM:\SOFTWARE\VWG\CM\HBM_nCodeGlyphworks_x64_23.1.0.0-0001_en-US")) { Write-ADTLogEntry -Message 'backup for nCode 2023.1' }
#*=== PRE-INSTALLATION END ===
#*=== MAIN-INSTALLATION BEGIN ===
Start-ADTProcess -FilePath "$envProgramFiles\nCode\nCode 2024.1 64-bit\install.exe"
#*=== MAIN-INSTALLATION END ===
#*=== POST-INSTALLATION BEGIN ===
#*=== POST-INSTALLATION END ===
#*=== PRE-UNINSTALLATION BEGIN ===
#*=== PRE-UNINSTALLATION END ===
#*=== MAIN-UNINSTALLATION BEGIN ===
Start-ADTProcess -FilePath "$envProgramFiles\nCode\nCode 2024.1 64-bit\uninstall.exe"
#*=== MAIN-UNINSTALLATION END ===
#*=== POST-UNINSTALLATION BEGIN ===
#*=== POST-UNINSTALLATION END ===
#*=== PRE-REPAIR BEGIN ===
#*=== PRE-REPAIR END ===
#*=== MAIN-REPAIR BEGIN ===
#*=== MAIN-REPAIR END ===
#*=== POST-REPAIR BEGIN ===
#*=== POST-REPAIR END ===
'@
$ncModel = Read-PredecessorModel -PackageName 'HBM_nCodeGlyphworks_x64_24.1.0-0001_en-US' -Content $ncPred
$ncNew = @{ Vendor='HBM'; AppName='nCodeGlyphworks'; Arch='x64'; Lang='en-US'; Revision='0001'; Version='26.0.0.0'; ExeFileName='install.exe' }
$ncChecked   = Build-PredecessorScript -Model $ncModel -NewPkg $ncNew -Template $tpl -AddUninstallPrevious $true
$ncUnchecked = Build-PredecessorScript -Model $ncModel -NewPkg $ncNew -Template $tpl -AddUninstallPrevious $false
Assert "pred-of-pred CHECKED keeps 2023.1 (standard)"     ($ncChecked -match 'nCode 2023\.1 64-bit' -and $ncChecked -match '23\.1\.0\.0-0001')
Assert "pred-of-pred UNCHECKED bumps 2023.1 -> 2024.1"    ($ncUnchecked -match 'nCode 2024\.1 64-bit' -and (-not ($ncUnchecked -match '2023\.1|23\.1\.0\.0')))
Assert "current version ALWAYS bumped (both) -> 2026.0"   (($ncChecked -match 'nCode 2026\.0 64-bit') -and ($ncUnchecked -match 'nCode 2026\.0 64-bit'))
Assert "gated builds both parse"                          (& { $e1=$null;$e2=$null;[void][System.Management.Automation.Language.Parser]::ParseInput($ncChecked,[ref]$null,[ref]$e1);[void][System.Management.Automation.Language.Parser]::ParseInput($ncUnchecked,[ref]$null,[ref]$e2); (-not $e1.Count) -and (-not $e2.Count) })

# ---- PREDECESSOR REUSE REPORT: the two-part "Done automatically" / "Please check" summary ----
$rep = Get-PredecessorReport -Model $model -NewPkg $newPkg -ScriptText $out -AddUninstallPrevious $true -MismatchText ''
Assert "report Done: version update 1.2.3.4 -> 1.5.6.7" (@($rep.Done | Where-Object { $_ -match '1\.2\.3\.4 -> 1\.5\.6\.7' }).Count -gt 0)
Assert "report Done: installer swap to new msi"         (@($rep.Done | Where-Object { $_ -match 'AcmeApp_1\.5\.6\.7\.msi' }).Count -gt 0)
Assert "report Done: uninstall-previous mentioned"      (@($rep.Done | Where-Object { $_ -match 'uninstall the previous version' }).Count -gt 0)
Assert "report: clean swap -> no 'old name still present' check" (@($rep.Check | Where-Object { $_ -match 'still appears' }).Count -eq 0)
$repText = Format-PredecessorReportText -Report $rep -Model $model -NewPkg $newPkg
Assert "report text has both sections"                  (($repText -match 'DONE AUTOMATICALLY') -and ($repText -match 'PLEASE CHECK'))
$repHtml = Format-PredecessorReportHtml -Report $rep -Model $model -NewPkg $newPkg
Assert "report html well-formed"                        (($repHtml -match '<html') -and ($repHtml -match 'Done automatically'))

# ---- SNAPSHOT-ASSISTED REUSE: Merge-SnapshotDeltas adds net-new only, refreshes FreeSpace/SoftIdent, unions procs ----
$mBase = @"
    ProcToClose = @('app')
    ProcToBlock = @('app')
    FreeSpace = '200'
    SoftIdent = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{11111111-1111-1111-1111-111111111111}'
#*=== POST-INSTALLATION BEGIN ===
    ## <Perform Post-Installation tasks here>
    Remove-ADTFile -Path "`$envCommonDesktopDirectory\App.lnk"
#*=== POST-INSTALLATION END ===
#*=== POST-UNINSTALLATION BEGIN ===
    ## <Perform Post-Uninstallation tasks here>
#*=== POST-UNINSTALLATION END ===
"@
$mNp = @{ Arch='x64'; FreeSpace=512;
    SnapshotSoftIdent='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{22222222-2222-2222-2222-222222222222} [DisplayVersion=2.0]';
    SnapshotProcs=@('app','helper2');
    PostInstallExtra=("Remove-ADTFile -Path `"`$envCommonDesktopDirectory\App.lnk`"" + "`r`n" + "Remove-ADTRegistryKey -Key 'HKLM:\SOFTWARE\App\Run' -Name 'AutoUpd'");
    PostUninstallExtra="Remove-MTBFonts -Pattern 'MyFont.ttf'  # [post-uninstall]" }
$mOut = Merge-SnapshotDeltas -Text $mBase -NewPkg $mNp -Model @{}
Assert "snap-merge: FreeSpace raised 200 -> 512"        ($mOut -match "(?m)^\s*FreeSpace\s*=\s*'512'")
Assert "snap-merge: SoftIdent refreshed to new GUID"    (($mOut -match '\{22222222-2222-2222-2222-222222222222\}') -and ($mOut -match '#\s*\[snapshot-detection\]'))
Assert "snap-merge: ProcToClose unions new proc"        (($mOut -match "(?m)^\s*ProcToClose\s*=.*'app'") -and ($mOut -match "(?m)^\s*ProcToClose\s*=.*'helper2'"))
Assert "snap-merge: ProcToBlock unions new proc"        ($mOut -match "(?m)^\s*ProcToBlock\s*=.*'helper2'")
Assert "snap-merge: duplicate App.lnk NOT re-added"     (([regex]::Matches($mOut, 'App\.lnk')).Count -eq 1)
Assert "snap-merge: net-new cleanup added + tagged"     ($mOut -match "AutoUpd'\s+# \[snapshot-added\]")
Assert "snap-merge: cert/font cleanup -> POST-UNINSTALL" ((([regex]::Match($mOut,'(?is)POST-UNINSTALLATION BEGIN(.*?)POST-UNINSTALLATION END')).Groups[1].Value) -match 'MyFont\.ttf')
# a hand-crafted MULTI-GUID predecessor detection must NOT be overridden by the snapshot
$mBase2 = $mBase -replace "SoftIdent = '[^']*'", "SoftIdent = 'HKLM:\A\{11111111-1111-1111-1111-111111111111};HKLM:\B\{33333333-3333-3333-3333-333333333333}'"
$mOut2 = Merge-SnapshotDeltas -Text $mBase2 -NewPkg $mNp -Model @{}
Assert "snap-merge: multi-GUID detection left intact"   (-not ($mOut2 -match '\{22222222'))
Assert "snap-merge: FreeSpace NOT lowered"              (-not ((Merge-SnapshotDeltas -Text $mBase -NewPkg @{ FreeSpace=50 } -Model @{}) -match "FreeSpace\s*=\s*'50'"))
# report surfaces the snapshot merge
$mRep = Get-PredecessorReport -Model @{ Identity=@{ FullName='x'; Version='1.0' }; Code=@{}; Session=@{} } -NewPkg @{ Version='2.0' } -ScriptText $mOut -AddUninstallPrevious $true
Assert "snap-merge: report Done lists snapshot cleanups" (@($mRep.Done | Where-Object { $_ -match 'Snapshot-assisted.*cleanup' }).Count -gt 0)
Assert "snap-merge: report Check flags snapshot lines"   (@($mRep.Check | Where-Object { $_ -match 'snapshot-added' }).Count -gt 0)

# ---- SCCM dev->test move: Clear-SccmCollectionDirectMembers empties test machines before a hive move (mocked cmdlets) ----
$script:__rmCalls = New-Object System.Collections.Generic.List[string]
function Get-CMDeviceCollectionDirectMembershipRule { param($CollectionName) @(
    [pscustomobject]@{ ResourceID=101; RuleName='PC-A' },
    [pscustomobject]@{ ResourceID=102; RuleName='PC-B' }) }
function Remove-CMDeviceCollectionDirectMembershipRule { param($CollectionName,$ResourceId,[switch]$Force) $script:__rmCalls.Add("$CollectionName/$ResourceId") }
$clr = Clear-SccmCollectionDirectMembers -CollectionName 'App-INSTALL (TEST)'
Assert "sccm clear: removes ALL direct members (count)"  ($clr -eq 2)
Assert "sccm clear: called Remove once per member"       (($script:__rmCalls.Count -eq 2) -and ($script:__rmCalls[0] -match '/101') -and ($script:__rmCalls[1] -match '/102'))
function Get-CMDeviceCollectionDirectMembershipRule { param($CollectionName) @() }   # now empty
Assert "sccm clear: empty collection -> 0 removed"       ((Clear-SccmCollectionDirectMembers -CollectionName 'X') -eq 0)
Remove-Item function:Get-CMDeviceCollectionDirectMembershipRule, function:Remove-CMDeviceCollectionDirectMembershipRule -ErrorAction SilentlyContinue

# ---- SCCM publish fetch from a v3 package: $VWG_SoftIdent (LAST definition wins), $($VWG_CurrentRegWOW) hive token
#      resolved from its own definition -> 32-bit box ticked + clean key, [DisplayVersion = X] with spaces, positional cmds.
$v3fix = Join-Path $env:TEMP ('pbv3_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item (Join-Path $v3fix 'Content') -ItemType Directory -Force | Out-Null
@'
[string]$appVendor = 'Altair'
[string]$appName = 'Pulse'
[string]$appVersion = '2025.1'
[string]$appArch = 'x86'
[string]$appRevision = '0001'
[string]$appLang = 'MUL'
[string]$VWG_SoftIdent			= 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Altair Pulse 2025.1 [DisplayVersion = 2025.1]'
##*=== CUSTOM APPLICATION VARIABLES BEGIN ===
[string]$VWG_CurrentRegWOW = 'WoW6432Node\'
[string]$VWG_SoftIdent			= 'HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)\Microsoft\Windows\CurrentVersion\Uninstall\Altair Pulse 2025.1 [DisplayVersion = 2025.1]'
##*=== CUSTOM APPLICATION VARIABLES END ===
'@ | Set-Content (Join-Path $v3fix 'Content\Deploy-Application.ps1') -Encoding UTF8
$v3f = Get-SccmFieldsFromPackage -PackagePath $v3fix
Assert "v3 fetch: SoftIdent -> uninstall key (VWG_ prefix)"  ($v3f.UninstallKey -eq 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Altair Pulse 2025.1')
Assert "v3 fetch: hive token -> 32-bit box ticked"           ($v3f.Is32Bit -eq $true)
Assert "v3 fetch: key has NO token / NO WoW6432Node"         (($v3f.UninstallKey -notmatch 'VWG_|WoW6432Node'))
Assert "v3 fetch: [DisplayVersion = X] w/ spaces -> version" ($v3f.DetectVersion -eq '2025.1')
Assert "v3 fetch: install cmd POSITIONAL (no -DeploymentType)" (($v3f.InstallCmd -eq '"Deploy-Application.exe" Install') -and ($v3f.UninstallCmd -notmatch 'DeploymentType'))
Assert "v3 fetch: detected as v3"                            ($v3f.PsadtVersion -eq 'v3')
Remove-Item $v3fix -Recurse -Force -ErrorAction SilentlyContinue
# v4 sanity: literal WoW6432Node key -> stripped + 32-bit ticked (user asked to re-verify)
$v4fix = Join-Path $env:TEMP ('pbv4_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item (Join-Path $v4fix 'Content') -ItemType Directory -Force | Out-Null
@'
$adtSession = @{
    AppVendor = 'Acme'
    AppName = 'Tool'
    AppVersion = '1.0'
    AppArch = 'x86'
    SoftIdent = 'HKLM:\SOFTWARE\WoW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{11111111-2222-3333-4444-555555555555} [DisplayVersion=1.0]'
}
'@ | Set-Content (Join-Path $v4fix 'Content\Invoke-AppDeployToolkit.ps1') -Encoding UTF8
$v4f = Get-SccmFieldsFromPackage -PackagePath $v4fix
Assert "v4 fetch: WoW6432Node stripped + 32-bit ticked"      (($v4f.UninstallKey -notmatch 'WoW6432Node') -and $v4f.Is32Bit)
Assert "v4 fetch: version + ProductCode from SoftIdent"      (($v4f.DetectVersion -eq '1.0') -and ($v4f.ProductCode -eq '{11111111-2222-3333-4444-555555555555}'))
Remove-Item $v4fix -Recurse -Force -ErrorAction SilentlyContinue

# ---- Get-PBClientPath: LOCAL machine -> DIRECT path (no admin share, no elevation); REMOTE -> \\host\c$\... admin share
Assert "client path: local -> direct C:\ (no c$)"        ((Get-PBClientPath -Machine $env:COMPUTERNAME -ShareRel 'c$\Windows\CCM\Logs') -eq 'C:\Windows\CCM\Logs')
Assert "client path: '.' local -> direct"                ((Get-PBClientPath -Machine '.' -ShareRel 'c$\ProgramData\VWG\Logs') -eq 'C:\ProgramData\VWG\Logs')
Assert "client path: remote -> \\host\c$ admin share"    ((Get-PBClientPath -Machine 'OTHERPC99' -ShareRel 'c$\Windows\CCM\Logs') -eq '\\OTHERPC99\c$\Windows\CCM\Logs')

# ---- Intune: Get-LocalModuleManifest leaves a LOCAL module path unchanged (only UNC paths get staged locally) ----
Assert "intune stage: local path passes through"         ((Get-LocalModuleManifest 'C:\Tools\Lib\MSAL.PS\MSAL.PS.psd1') -eq 'C:\Tools\Lib\MSAL.PS\MSAL.PS.psd1')
Assert "intune stage: empty path passes through"         ((Get-LocalModuleManifest '') -eq '')
$proxyOk = $true; try { Set-IntuneProxyCreds } catch { $proxyOk = $false }
Assert "intune proxy: Set-IntuneProxyCreds never throws"  $proxyOk

# ---- Remote screenshots: the generated agent is a VALID standalone script with everything baked in ----
$agent = New-PBShotsAgentScript -PkgName 'Acme_Tool_x64_1.0-0001_MUL' -Tokens @('acme',"o'tool") -RefNames @('Acme Tool')
$agErr = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($agent, [ref]$null, [ref]$agErr)
Assert "remote agent: generated script parses"           ($agErr.Count -eq 0)
Assert "remote agent: tokens baked (quote-escaped)"      (($agent -match "'acme'") -and ($agent -match "'o''tool'"))
Assert "remote agent: reference shortcut names baked"    ($agent -match "'Acme Tool'")
Assert "remote agent: PrintWindow capture (locked-safe)" ($agent -match 'PrintWindow')
Assert "remote agent: skips uninstall/help shortcuts"    ($agent -match 'uninstall\|unins')
Assert "remote agent: writes done.flag + index.html"     (($agent -match 'done\.flag') -and ($agent -match 'index\.html'))
Assert "remote agent: stages under C:\temp (not Windows\Temp)" ($agent -match [regex]::Escape('C:\temp\PBShots'))
# Local-machine guard: never runs the remote path against THIS machine.
$rg = Invoke-RemoteShortcutShots -Machine $env:COMPUTERNAME -FullName 'X' -Tokens @('x') -RefShortcuts @()
Assert "remote shots: local machine -> guarded, no remote run" ((-not $rg.Ok) -and ($rg.Message -match 'THIS machine'))

# ---- UNINSTALL LEFTOVER CHECK: live Test-Path over what the install created; folders swallow their files; empty flagged ----
$lo = Join-Path $env:TEMP ('pblo_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item (Join-Path $lo 'AppDir\sub') -ItemType Directory -Force | Out-Null
Set-Content (Join-Path $lo 'AppDir\sub\left.dll') 'x' -Force            # file INSIDE a leftover dir -> swallowed
Set-Content (Join-Path $lo 'stray.log') 'x' -Force                       # standalone leftover file
New-Item (Join-Path $lo 'EmptyDir') -ItemType Directory -Force | Out-Null
$regTest = 'HKCU:\Software\PBTestLeftover'
New-Item $regTest -Force | Out-Null; New-Item "$regTest\Sub" -Force | Out-Null
$cands = @{
    Files = @((Join-Path $lo 'AppDir\sub\left.dll'), (Join-Path $lo 'stray.log'), (Join-Path $lo 'gone.exe'))
    Dirs  = @((Join-Path $lo 'AppDir'), (Join-Path $lo 'AppDir\sub'), (Join-Path $lo 'EmptyDir'), (Join-Path $lo 'GoneDir'))
    Reg   = @('HKCU\Software\PBTestLeftover', 'HKCU\Software\PBTestLeftover\Sub', 'HKCU\Software\PBTestGone')
    Lnk   = @()
}
$left = @(Get-UninstallLeftovers -Candidates $cands)
Assert "leftover: top folder reported, subfolder swallowed"  ((@($left | Where-Object { $_.Label -match [regex]::Escape((Join-Path $lo 'AppDir')) }).Count -eq 1))
Assert "leftover: file under leftover dir NOT re-listed"     (-not ($left | Where-Object { $_.Label -match 'left\.dll' }))
Assert "leftover: standalone file listed"                    ([bool]($left | Where-Object { $_.Label -match 'stray\.log' }))
Assert "leftover: EMPTY folder flagged"                      ([bool]($left | Where-Object { $_.Label -match '\(EMPTY\).*EmptyDir' }))
Assert "leftover: gone items NOT listed"                     (-not ($left | Where-Object { $_.Label -match 'gone\.exe|GoneDir|PBTestGone' }))
Assert "leftover: top reg key reported, subkey swallowed"    ((@($left | Where-Object { $_.Label -match 'PBTestLeftover' }).Count -eq 1))
Assert "leftover: reg cmd uses HKCU:\ drive form + -Recurse" ([bool]($left | Where-Object { $_.Command -match "Remove-ADTRegistryKey -Key 'HKCU:\\Software\\PBTestLeftover' -Recurse" }))
Assert "leftover: all commands tagged post-uninstall"        (@($left | Where-Object { $_.Command -notmatch '\[post-uninstall\]' }).Count -eq 0)
Remove-Item $lo -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $regTest -Recurse -Force -ErrorAction SilentlyContinue
# RUNTIME DATA sweep: app-named data dir (created at RUN time, not install) found + ticked; vendor-named UNTICKED (shared).
$rt = Join-Path $env:TEMP ('pbrt_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item (Join-Path $rt 'CoolTool') -ItemType Directory -Force | Out-Null   # app-named runtime folder
New-Item (Join-Path $rt 'AcmeCorp\OtherProduct') -ItemType Directory -Force | Out-Null   # vendor-named (shared!)
$cands2 = @{ Files=@(); Dirs=@(); Reg=@(); Lnk=@(); Vendor='AcmeCorp'; App='CoolTool' }
$left2 = @(Get-UninstallLeftovers -Candidates $cands2 -DataRoots @($rt))
$appHit  = $left2 | Where-Object { $_.Label -match 'CoolTool' }
$vendHit = $left2 | Where-Object { $_.Label -match 'AcmeCorp' }
Assert "runtime sweep: app-named data dir found + TICKED"    ($appHit -and [bool]$appHit.Default)
Assert "runtime sweep: vendor dir found but UNTICKED+warned" ($vendHit -and (-not [bool]$vendHit.Default) -and ($vendHit.Label -match 'SHARED'))
Assert "runtime sweep: commands tagged post-uninstall"       (@($left2 | Where-Object { $_.Command -notmatch '\[post-uninstall\]' }).Count -eq 0)
Remove-Item $rt -Recurse -Force -ErrorAction SilentlyContinue
# ---- Uninstall derivation: NORMAL exe "uninstall strings" skipped; uninstall-looking exe/msiexec/GUID kept;
#      SoftIdent ProductCode from the MOST-matched GUID entry even when the primary ARP key isn't a GUID ----
$udiff = @{ Programs = @{ Added = @(
    [pscustomobject]@{ Info = @{ DisplayName='CoolTool';          _key='CoolTool_is1';  UninstallString='"C:\Program Files\CoolTool\unins000.exe" /SILENT'; QuietUninstallString=''; DisplayVersion='1.0'; Publisher='Acme'; _root='HKLM' } },
    [pscustomobject]@{ Info = @{ DisplayName='CoolTool Updater';  _key='CoolToolUpd';   UninstallString='"C:\Program Files\CoolTool\updater.exe"';          QuietUninstallString=''; DisplayVersion='1.0'; Publisher='Acme'; _root='HKLM' } },
    [pscustomobject]@{ Info = @{ DisplayName='CoolTool Runtime';  _key='{AAAABBBB-1111-2222-3333-444455556666}'; UninstallString=''; QuietUninstallString=''; DisplayVersion='1.0'; Publisher='Acme'; _root='HKLM' } }
); Noise = @() } }
$ud = Get-UninstallFromSnapshotDiff -Diff $udiff -AppName 'CoolTool'
Assert "uninst: normal exe (updater.exe) SKIPPED"        ($ud.Uninstall -notmatch 'updater\.exe')
Assert "uninst: unins000-style exe KEPT"                 ($ud.Uninstall -match 'unins000\.exe')
Assert "uninst: GUID entry synthesized msiexec KEPT"     ($ud.Uninstall -match '(?i)MsiExec\.exe /X\{AAAABBBB')
Assert "uninst: SoftIdent PC from matching GUID entry"   ($ud.ProductCode -eq '{AAAABBBB-1111-2222-3333-444455556666}')

# ---- Format-PBPathArg: literal paths -> PSADT env vars (double-quoted); unknown roots stay literal (single-quoted) ----
Assert "envpath: Program Files -> `$envProgramFiles"     ((Format-PBPathArg (Join-Path $env:ProgramFiles 'App\x.exe')) -eq '"$envProgramFiles\App\x.exe"')
Assert "envpath: ProgramData -> `$envProgramData"        ((Format-PBPathArg (Join-Path $env:ProgramData 'Acme')) -eq '"$envProgramData\Acme"')
Assert "envpath: unknown root stays literal"             ((Format-PBPathArg 'D:\Data\keep.txt') -eq "'D:\Data\keep.txt'")

# ---- Version-folder docs (one level up): 26.0.0.0_0001\<build>\setup.exe -> docs + doc-folders from the version dir ----
$vd = Join-Path $env:TEMP ('pbvd_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$build = Join-Path $vd '26.0.0.0_0001\nCode26_Build440_win64'
New-Item $build -ItemType Directory -Force | Out-Null
Set-Content (Join-Path $build 'setup.exe') 'x' -Force
Set-Content (Join-Path $vd '26.0.0.0_0001\Install Instructions.docx') 'x' -Force
Set-Content (Join-Path $vd '26.0.0.0_0001\Complexity Sheet.xlsx') 'x' -Force
New-Item (Join-Path $vd '26.0.0.0_0001\Docs') -ItemType Directory -Force | Out-Null
New-Item (Join-Path $vd '26.0.0.0_0001\OtherPayload') -ItemType Directory -Force | Out-Null
$sd = @(Get-SiblingDocItems -InstallerParent $build -ExcludePaths @())
Assert "verdocs: install instructions harvested"         ([bool]($sd | Where-Object { $_ -match 'Install Instructions\.docx' }))
Assert "verdocs: complexity sheet harvested"             ([bool]($sd | Where-Object { $_ -match 'Complexity Sheet\.xlsx' }))
Assert "verdocs: doc-NAMED folder harvested"             ([bool]($sd | Where-Object { $_ -match '\\Docs$' }))
Assert "verdocs: other payload folder NOT in Documents"  (-not ($sd | Where-Object { $_ -match 'OtherPayload' }))
# FETCH parity: Resolve-Source pointed AT the build folder (fetch root) must find the SAME one-level-up docs the
# manual pick finds - via the manual-parity harvest that fires when the root itself holds no docs.
$rsv = Resolve-Source -RootPath $build
Assert "fetch parity: resolver finds installer in build root"   ($rsv.Valid -and (@($rsv.Installers | Where-Object { $_.Name -eq 'setup.exe' }).Count -eq 1))
Assert "fetch parity: one-level-up docs harvested like manual"  ((@($rsv.DocItems | Where-Object { $_ -match 'Install Instructions\.docx' }).Count -eq 1) -and (@($rsv.DocItems | Where-Object { $_ -match 'Complexity Sheet\.xlsx' }).Count -eq 1))
Assert "fetch parity: other payload folder still NOT in docs"   (-not ($rsv.DocItems | Where-Object { $_ -match 'OtherPayload' }))
Remove-Item $vd -Recurse -Force -ErrorAction SilentlyContinue

# ---- Icons: whenever an .ico exists, a SAME-BASENAME .png is generated from it (matched pair), even if a stray png exists ----
$icoT = Join-Path $env:TEMP ('pbico_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item (Join-Path $icoT 'src') -ItemType Directory -Force | Out-Null
New-Item (Join-Path $icoT 'icons') -ItemType Directory -Force | Out-Null
New-Item (Join-Path $icoT 'files') -ItemType Directory -Force | Out-Null
Add-Type -AssemblyName System.Drawing
$exIc = [System.Drawing.Icon]::ExtractAssociatedIcon("$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe")
$fs = [IO.File]::Open((Join-Path $icoT 'src\AppIcon.ico'), 'Create'); $exIc.Save($fs); $fs.Close(); $exIc.Dispose()
Set-Content (Join-Path $icoT 'src\stray.png') 'not-a-real-image' -Force   # mismatched stray png
Copy-PackageIcons -Resolved @{ IconsPath = (Join-Path $icoT 'src') } -IconsDir (Join-Path $icoT 'icons') -FilesDir (Join-Path $icoT 'files')
Assert "icons: matched AppIcon.png generated from ico"   (Test-Path (Join-Path $icoT 'icons\AppIcon.png'))
Assert "icons: ico still present (pair complete)"        (Test-Path (Join-Path $icoT 'icons\AppIcon.ico'))
Remove-Item $icoT -Recurse -Force -ErrorAction SilentlyContinue

# ---- Predecessor reuse: carry forward the Active Setup .ps1 (rename + content version-swap to the new version) ----
$asT = Join-Path $env:TEMP ('pbas_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$asPredSupport = Join-Path $asT 'pred\Content\SupportFiles'
New-Item $asPredSupport -ItemType Directory -Force | Out-Null
$asStub = @'
# nCodeGlyphworks 2024.1 per-user config
$appVer = '24.1.0'
reg.exe add "HKCU\Software\nCode\nCode 2024.1 64-bit" /v Home /d "C:\Program Files\nCode\nCode 2024.1 64-bit" /f
# previous-version note for nCode 2023.1 64-bit (HBM_nCodeGlyphworks_x64_23.1.0.0-0001_en-US)
'@
Set-Content (Join-Path $asPredSupport 'nCodeGlyphworks_24.1.0_ActiveSetup_Install.ps1') $asStub -Encoding UTF8
$asDest = Join-Path $asT 'out\SupportFiles'
$asNp = @{ Vendor='HBM'; AppName='nCodeGlyphworks'; Arch='x64'; Lang='en-US'; Version='26.0.0.0' }
$asN = Copy-PredecessorActiveSetup -PredecessorPath (Join-Path $asT 'pred') -SupportDir $asDest -NewPkg $asNp -PredVersion '24.1.0'
$asNewFile = Join-Path $asDest 'nCodeGlyphworks_26.0.0_ActiveSetup_Install.ps1'
Assert "activesetup carry: one file carried"                 ($asN -eq 1)
Assert "activesetup carry: filename version-swapped"         (Test-Path $asNewFile)
Assert "activesetup carry: OLD-named file NOT present"       (-not (Test-Path (Join-Path $asDest 'nCodeGlyphworks_24.1.0_ActiveSetup_Install.ps1')))
$asOut = if (Test-Path $asNewFile) { Get-Content $asNewFile -Raw } else { '' }
Assert "activesetup carry: content appVer -> 26.0.0"         ($asOut -match "appVer = '26\.0\.0'")
Assert "activesetup carry: content year-form -> 2026.0"      ($asOut -match 'nCode 2026\.0 64-bit')
Assert "activesetup carry: pred-of-pred left as-is (no bump)" ($asOut -match 'nCode 2023\.1 64-bit')
Assert "activesetup carry: still valid PowerShell"           (& { $e=$null;[void][System.Management.Automation.Language.Parser]::ParseInput($asOut,[ref]$null,[ref]$e); -not ($e -and $e.Count) })
Remove-Item $asT -Recurse -Force -ErrorAction SilentlyContinue

# ---- Snapshot change-TREE builders (the SysTracer-style view's data model) ----
$troot = [ordered]@{}
Add-SnapshotTreePath -Root $troot -Path 'C:\Program Files\nCode\app.exe'    -Status 'new'
Add-SnapshotTreePath -Root $troot -Path 'C:\Program Files\nCode\config.ini' -Status 'modified'
Add-SnapshotTreePath -Root $troot -Path 'C:\Program Files\old\legacy.dll'   -Status 'deleted'
Add-SnapshotTreePath -Root $troot -Path 'HKLM\SOFTWARE\nCode'               -Status 'new'
Assert "tree: C: + HKLM roots created"        ($troot.Contains('C:') -and $troot.Contains('HKLM'))
$nc = $troot['C:'].c['Program Files'].c['nCode']
Assert "tree: nCode folder holds both files"  ($nc.c.Contains('app.exe') -and $nc.c.Contains('config.ini'))
Assert "tree: leaf statuses set correctly"    (($nc.c['app.exe'].s -eq 'new') -and ($nc.c['config.ini'].s -eq 'modified'))
Assert "tree: intermediate folder has NO status" ($null -eq $troot['C:'].s -and $null -eq $nc.s)
$allCounts = Get-SnapshotTreeCounts -Node @{ s=$null; c=$troot }
Assert "tree counts: 2 new / 1 mod / 1 del"   (($allCounts.new -eq 2) -and ($allCounts.modified -eq 1) -and ($allCounts.deleted -eq 1))
$ncCounts = Get-SnapshotTreeCounts -Node $nc
Assert "tree: nCode subtree aggregates +1 ~1" (($ncCounts.new -eq 1) -and ($ncCounts.modified -eq 1) -and ($ncCounts.deleted -eq 0))
# COUNT CACHE (perf): the tree UI asks for a count on EVERY node - uncached that re-walks each subtree and the build
# goes O(n^2), which hung the window on a huge install (10 GB app). Cached results MUST equal uncached ones.
$cCache = @{}
$cachedAll = Get-SnapshotTreeCounts -Node @{ s=$null; c=$troot } -Cache $cCache
Assert "tree counts: cached == uncached"      (($cachedAll.new -eq $allCounts.new) -and ($cachedAll.modified -eq $allCounts.modified) -and ($cachedAll.deleted -eq $allCounts.deleted))
$ncCached = Get-SnapshotTreeCounts -Node $nc -Cache $cCache
Assert "tree counts: cached subtree == plain" (($ncCached.new -eq $ncCounts.new) -and ($ncCached.modified -eq $ncCounts.modified) -and ($ncCached.deleted -eq $ncCounts.deleted))
Assert "tree counts: cache got populated"     ($cCache.Count -gt 0)
Assert "tree counts: 2nd call hits the cache" ((Get-SnapshotTreeCounts -Node $nc -Cache $cCache).new -eq $ncCounts.new)

# ---- Snapshot CHANGE SET: normalize -> text/html -> JSON round-trip (Copy / Export / Import) ----
$csFileDiff = @{ New=@([pscustomobject]@{Path='C:\App\a.exe';Change='new'},[pscustomobject]@{Path='C:\App\c.ini';Change='modified'}); Deleted=@([pscustomobject]@{Path='C:\Old\x.dll';Change='deleted'}); NoiseItems=@([pscustomobject]@{Path='C:\Windows\Temp\junk'}); NoiseCount=1 }
$csRegDiff  = @{ New=@([pscustomobject]@{Path='HKLM\SOFTWARE\Acme\App';Change='new'}); Deleted=@(); NoiseItems=@(); NoiseCount=0 }
$csDiff = @{ Shortcuts=@{ Added=@([pscustomobject]@{Id='s1';Info=@{Name='Acme App';Target='a.exe'}}); Noise=@() } }
$cs = New-SnapshotChangeSet -Diff $csDiff -FileDiff $csFileDiff -RegDiff $csRegDiff -EnvChanges @(@{Name='PATHX';Old='';New='c:\x';Change='added'}) -AppName 'Acme App'
Assert "changeset: counts (new/mod/del)"        (($cs.Counts.new -ge 3) -and ($cs.Counts.modified -eq 1) -and ($cs.Counts.deleted -eq 1))
Assert "changeset: file carried w/ change"      ((@($cs.Files | Where-Object { "$($_.Path)" -eq 'C:\App\a.exe' -and "$($_.Change)" -eq 'new' }).Count) -eq 1)
Assert "changeset: registry key carried"        ((@($cs.Registry | Where-Object { "$($_.Path)" -eq 'HKLM\SOFTWARE\Acme\App' }).Count) -eq 1)
Assert "changeset: shortcut list carried"       ($cs.Lists.Contains('Shortcuts') -and (@($cs.Lists['Shortcuts']).Count -eq 1))
$csTxt = Format-SnapshotChangeSetText $cs
Assert "changeset text: [+]/[~]/[-] markers"    (($csTxt -match '\[\+\] C:\\App\\a\.exe') -and ($csTxt -match '\[~\]') -and ($csTxt -match '\[-\]'))
$csHtml = Format-SnapshotChangeSetHtml $cs
Assert "changeset html: valid + colour + path"  (($csHtml -match '<html') -and ($csHtml -match 'added') -and ($csHtml -match 'C:\\App\\a\.exe'))
$csBack = ConvertTo-PBHashtable (($cs | ConvertTo-Json -Depth 10) | ConvertFrom-Json)
Assert "changeset JSON round-trip: files survive" ((@($csBack.Files | Where-Object { "$($_.Path)" -eq 'C:\App\a.exe' }).Count) -eq 1)
Assert "changeset JSON round-trip: counts survive" ([int]$csBack.Counts.deleted -eq 1)
Assert "Format-PBSize human-readable"           ((Format-PBSize 1536000) -match 'MB')
# Registry per-value diff (old -> new) from stored value strings
$SOH=[char]1; $STX=[char]2
$bStr = "InstallDir${SOH}String${SOH}C:\Old${STX}Ver${SOH}String${SOH}24.1${STX}Gone${SOH}String${SOH}x${STX}"
$aStr = "InstallDir${SOH}String${SOH}C:\New${STX}Ver${SOH}String${SOH}26.0${STX}NewOne${SOH}DWord${SOH}1${STX}"
$vd = @(Compare-RegValueStrings -Before $bStr -After $aStr)
Assert "regval: CHANGED old->new"  ((@($vd | Where-Object { $_.Name -eq 'InstallDir' -and $_.Change -eq 'changed' -and $_.Old -eq 'C:\Old' -and $_.New -eq 'C:\New' }).Count) -eq 1)
Assert "regval: ADDED value"       ((@($vd | Where-Object { $_.Name -eq 'NewOne' -and $_.Change -eq 'added' }).Count) -eq 1)
Assert "regval: REMOVED value"     ((@($vd | Where-Object { $_.Name -eq 'Gone' -and $_.Change -eq 'removed' }).Count) -eq 1)
# .reg export: header, key, string (escaped), dword (hex), deleted key
$regCs = @{ App='X'; When='now'; Counts=@{new=1;modified=0;deleted=1}; Files=@()
            Registry=@(@{Path='HKLM\SOFTWARE\App';Change='new'},@{Path='HKLM\SOFTWARE\Old';Change='deleted'})
            RegValues=@{ 'HKLM\SOFTWARE\App'=@(@{Name='InstallDir';Type='String';New='C:\App';Change='added'},@{Name='Count';Type='DWord';New='5';Change='added'}) }
            Lists=[ordered]@{}; Env=@(); Noise=@() }
$reg = Format-SnapshotChangeSetReg $regCs
Assert "reg export: header + key present"  (($reg -match 'Windows Registry Editor Version 5\.00') -and ($reg -match '\[HKEY_LOCAL_MACHINE\\SOFTWARE\\App\]'))
Assert "reg export: string value escaped"  ($reg -match '"InstallDir"="C:\\\\App"')
Assert "reg export: dword hex"             ($reg -match '"Count"=dword:00000005')
Assert "reg export: deleted key -> [-...]" ($reg -match '\[-HKEY_LOCAL_MACHINE\\SOFTWARE\\Old\]')

# Save/Read snapshot state round-trip (the 'Load report...' flexibility)
$ssPath = Join-Path $env:TEMP ('pbss_' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.snapshot.json')
$saved = Save-SnapshotState -Path $ssPath -Data @{ ReportText='REP'; Exclusions=@(@{Label='L1';Command='C1';Checked=$true}); Shortcuts=@(@{Name='S';Target='T'}); LeftoverCandidates=@{Files=@('f1');Dirs=@();Reg=@();Lnk=@()}; InstalledMB=42; Uninstall='U'; ProductCode='{PC}' }
$back = Read-SnapshotState -Path $ssPath
Assert "snapshot state: save + read round-trip"              ($saved -and $back -and ($back.ReportText -eq 'REP') -and ($back.Exclusions[0].Label -eq 'L1') -and [bool]$back.Exclusions[0].Checked)
Assert "snapshot state: leftover candidates survive"         ("$($back.LeftoverCandidates.Files[0])" -eq 'f1')
Assert "snapshot state: shortcuts + footprint survive"       (($back.Shortcuts[0].Target -eq 'T') -and ([int]$back.InstalledMB -eq 42))
Remove-Item $ssPath -Force -ErrorAction SilentlyContinue

# OLD report (no ChangeSet) -> reconstruct a STRUCTURAL change set so the Tree view still works on it.
$oldSt = [pscustomobject]@{ Detection='nCode 26.0'
    LeftoverCandidates=@(
        [pscustomobject]@{ Command="Remove-ADTFolder -Path 'C:\Program Files\nCode\GW'  # [post-uninstall]" },
        [pscustomobject]@{ Command='Remove-ADTFile -Path "C:\ProgramData\nCode\s.ini"' },
        [pscustomobject]@{ Command="Remove-ADTRegistryKey -Key 'HKLM:\SOFTWARE\nCode' -Recurse" } )
    Shortcuts=@([pscustomobject]@{ Name='nCode GW'; Target='C:\Program Files\nCode\GW.exe'; Lnk='C:\p\GW.lnk' }) }
$rcs = New-SnapshotChangeSetFromState -State $oldSt -AppName "$($oldSt.Detection)"
Assert "old-report rebuild: files (folder+file)"  (@($rcs.Files).Count -eq 2)
Assert "old-report rebuild: registry key"         ((@($rcs.Registry | Where-Object { "$($_.Path)" -eq 'HKLM:\SOFTWARE\nCode' }).Count) -eq 1)
Assert "old-report rebuild: shortcut carried"     ($rcs.Lists.Contains('Shortcuts') -and (@($rcs.Lists['Shortcuts']).Count -eq 1))
Assert "old-report rebuild: empty state -> empty" ((@((New-SnapshotChangeSetFromState -State ([pscustomobject]@{}) -AppName 'x').Files).Count) -eq 0)
# Noise filter: reparse farms / OS / UWP churn -> noise; real app + prerequisites -> kept
Assert "noise: !!!!! reparse farm"      (Test-IsFileNoise 'C:\Users\AW140\Downloads\!!!!!28404159\x')
Assert "noise: catroot2"                (Test-IsFileNoise 'C:\Windows\System32\catroot2\dberr.txt')
Assert "noise: wbem repository"         (Test-IsFileNoise 'C:\Windows\System32\wbem\Repository\INDEX.BTR')
Assert "noise: UWP Packages churn"      (Test-IsFileNoise 'C:\Users\AW140\AppData\Local\Packages\Claude_x\LocalCache\y')
Assert "noise: Cyvera/Traps vendor"     (Test-IsVendorNoise -Text 'c:\programdata\cyvera\logs\x.etl' -AppTokens @('acme'))
Assert "noise: real app file kept"      (-not (Test-IsFileNoise 'C:\Program Files\RIB\avasign\AvaSign.exe'))
# Leftover check: Windows \Recent\ MRU is never a cleanup candidate
$lc = @{ Files=@("$env:APPDATA\Microsoft\Windows\Recent\foo.lnk"); Dirs=@("$env:APPDATA\Microsoft\Windows\Recent"); Reg=@(); Lnk=@("$env:APPDATA\Microsoft\Windows\Recent\bar.lnk"); Vendor='x'; App='y' }
$lo = @(Get-UninstallLeftovers -Candidates $lc)
Assert "leftover: \Recent\ excluded"     ((@($lo | Where-Object { "$($_.Label)" -match '(?i)\\Recent\\' }).Count) -eq 0)
# Prerequisite capture: an ADDED file is real footprint even under a vendor path (VC++); modified/cache churn stays noise
$bMapP=@{}; $aMapP=@{ 'C:\Program Files\Microsoft VC\vcruntime140.dll'='100|0'; 'C:\Users\u\AppData\Local\Packages\App\cache'='5|1' }
$beforeP=[pscustomobject]@{ _FileMap=$bMapP }; $afterP=[pscustomobject]@{ _FileMap=$aMapP }
$fdP = Get-SnapshotRawDiff -Before $beforeP -After $afterP -Kind Files -AppTokens @('zzznotanapp')
Assert "prereq: added VC++ file kept (not vendor-filtered)" ((@($fdP.New | Where-Object { "$($_.Path)" -match 'vcruntime140' }).Count) -eq 1)
Assert "prereq: added UWP-cache still noise"                 ((@($fdP.New | Where-Object { "$($_.Path)" -match '\\Packages\\' }).Count) -eq 0)
# Registry capture: ADDED key under a vendor path kept; MODIFIED ARP (Uninstall) key kept (version change); modified vendor value = noise
$SOHr=[char]1;$STXr=[char]2
$bR=@{ 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{VC}'="DisplayVersion${SOHr}String${SOHr}14.29${STXr}"; 'HKLM\SOFTWARE\Microsoft\Edge\B'="version${SOHr}String${SOHr}120${STXr}" }
$aR=@{ 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{VC}'="DisplayVersion${SOHr}String${SOHr}14.38${STXr}"; 'HKLM\SOFTWARE\Policies\Google\Chrome'="H${SOHr}String${SOHr}x${STXr}"; 'HKLM\SOFTWARE\Microsoft\Edge\B'="version${SOHr}String${SOHr}121${STXr}" }
$rdR = Get-SnapshotRawDiff -Before ([pscustomobject]@{_RegMap=$bR}) -After ([pscustomobject]@{_RegMap=$aR}) -Kind Registry -AppTokens @('zzznoapp')
Assert "reg: added vendor policy key kept"      ((@($rdR.New | Where-Object { "$($_.Path)" -match 'Policies\\Google' }).Count) -eq 1)
Assert "reg: modified ARP (Uninstall) key kept" ((@($rdR.New | Where-Object { "$($_.Path)" -match '\{VC\}' }).Count) -eq 1)
Assert "reg: modified vendor value still noise" ((@($rdR.New | Where-Object { "$($_.Path)" -match 'Edge\\B' }).Count) -eq 0)
# After-uninstall change set: present=left(modified), missing=removed(deleted), new-in-dir=added(new)
$utd = Join-Path $env:TEMP ('ucs_' + [Guid]::NewGuid().ToString('N').Substring(0,8)); New-Item $utd -ItemType Directory -Force | Out-Null
$uPresent = Join-Path $utd 'app.exe'; Set-Content $uPresent 'x'; $uAdded = Join-Path $utd 'runtime.log'; Set-Content $uAdded 'y'; $uGone = Join-Path $utd 'removed.dll'
$ucs = New-UninstallChangeSet -Candidates @{ Files=@($uPresent,$uGone); Dirs=@($utd); Reg=@('HKLM\SOFTWARE\NoSuchKeyZZZQ'); Lnk=@() } -AppName 'Acme'
Assert "uninstall diff: present -> left (modified)"   ((@($ucs.Files | Where-Object { $_.Path -eq $uPresent -and $_.Change -eq 'modified' }).Count) -eq 1)
Assert "uninstall diff: missing -> removed (deleted)" ((@($ucs.Files | Where-Object { $_.Path -eq $uGone -and $_.Change -eq 'deleted' }).Count) -eq 1)
Assert "uninstall diff: new-in-dir -> added (new)"    ((@($ucs.Files | Where-Object { $_.Path -eq $uAdded -and $_.Change -eq 'new' }).Count) -eq 1)
# after-uninstall diff includes PREREQUISITES (AllFiles), not just app files
$ucs2 = New-UninstallChangeSet -Candidates @{ Files=@($uPresent); AllFiles=@($uPresent,'C:\NoSuchPrereqZZZ\vcruntime140.dll'); Dirs=@(); Reg=@(); AllReg=@(); Lnk=@() } -AppName 'Acme'
Assert "uninstall diff includes prereq via AllFiles" ((@($ucs2.Files | Where-Object { "$($_.Path)" -match 'vcruntime140' }).Count) -eq 1)
# enriched capture -> label: a certificate (no DisplayName) uses its Subject
$certDiff = @{ Certificates=@{ Added=@([pscustomobject]@{ Id='Root\ABC123'; Info=@{ Subject='CN=Acme Root CA'; Store='Root'; Thumbprint='ABC123' } }); Noise=@() } }
$certCs = New-SnapshotChangeSet -Diff $certDiff -FileDiff @{New=@();Deleted=@()} -RegDiff @{New=@();Deleted=@()} -EnvChanges @() -AppName 'X'
Assert "cert label uses Subject (no DisplayName)" ($certCs.Lists.Contains('Certificates') -and ("$(@($certCs.Lists['Certificates'])[0].Label)" -match 'Acme Root CA'))
# KEYPATH-AWARE MST cleanup plan (Export model): dedicated run-key component -> remove WHOLE component; shared+not-keypath
# -> delete the row; shared+keypath -> reassign keypath then delete. Shortcuts categorised (Desktop/Startup/SendTo/Stray).
$ckReg = @(
  [pscustomobject]@{ Registry='r1'; Root='2'; Key='Software\Microsoft\Windows\CurrentVersion\Run'; Name='Solo';     Value='x'; Component_='CompSolo'     }  # dedicated (run row is its keypath)
  [pscustomobject]@{ Registry='r2'; Root='2'; Key='Software\Microsoft\Windows\CurrentVersion\Run'; Name='Shared';   Value='y'; Component_='CompShared'   }  # shared, run row NOT keypath
  [pscustomobject]@{ Registry='r3'; Root='2'; Key='Software\Acme\Settings';                        Name='Foo';      Value='z'; Component_='CompShared'   }  # other reg in CompShared
  [pscustomobject]@{ Registry='r5'; Root='2'; Key='Software\Microsoft\Windows\CurrentVersion\Run'; Name='SharedKP'; Value='w'; Component_='CompSharedKP' }  # shared, run row IS the keypath
  [pscustomobject]@{ Registry='r6'; Root='1'; Key='Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Name='Solo32'; Value='v'; Component_='CompSolo32' } # dedicated 32-bit
)
$ckFile = @([pscustomobject]@{ File='f1'; Component_='CompShared' }, [pscustomobject]@{ File='f2'; Component_='CompSharedKP' })
$ckComp = @(
  [pscustomobject]@{ Component='CompSolo';     KeyPath='r1'; Attributes='4' }    # registry keypath = the run row -> dedicated
  [pscustomobject]@{ Component='CompShared';   KeyPath='f1'; Attributes='0' }    # file keypath (run row is not the keypath)
  [pscustomobject]@{ Component='CompSharedKP'; KeyPath='r5'; Attributes='4' }    # run row IS the keypath, but has file f2 -> reassignable
  [pscustomobject]@{ Component='CompSolo32';   KeyPath='r6'; Attributes='260' }  # dedicated 32-bit
)
$ckDir = @(
  [pscustomobject]@{ Directory='DesktopFolder';     Directory_Parent='TARGETDIR'; DefaultDir='Desktop' }
  [pscustomobject]@{ Directory='StartupFolder';     Directory_Parent='TARGETDIR'; DefaultDir='Startup' }
  [pscustomobject]@{ Directory='SendToFolder';      Directory_Parent='TARGETDIR'; DefaultDir='SendTo' }
  [pscustomobject]@{ Directory='ProgramMenuFolder'; Directory_Parent='TARGETDIR'; DefaultDir='Programs' }
)
$ckSc = @(
  [pscustomobject]@{ Shortcut='scDesk';    Directory_='DesktopFolder';     Name='App';     Component_='CompShared' }
  [pscustomobject]@{ Shortcut='scStartup'; Directory_='StartupFolder';     Name='AppAuto'; Component_='CompShared' }
  [pscustomobject]@{ Shortcut='scSendTo';  Directory_='SendToFolder';      Name='AppSend'; Component_='CompShared' }
  [pscustomobject]@{ Shortcut='scApp';     Directory_='ProgramMenuFolder'; Name='AppMenu'; Component_='CompShared' }
)
$mp = Resolve-MsiCleanupPlan -Registry $ckReg -File $ckFile -Shortcut $ckSc -Directory $ckDir -Component $ckComp -RemoveRun32 $true -RemoveRun64 $true -RemoveDesktop $true -RemoveStartup $true -RemoveStray $true
Assert "cleanup: dedicated run-key component -> remove WHOLE component"   (@($mp.RemoveComponents) -contains 'CompSolo')
Assert "cleanup: dedicated 32-bit run-key component -> remove component"  (@($mp.RemoveComponents) -contains 'CompSolo32')
Assert "cleanup: shared+not-keypath -> delete the registry row only"      ((@($mp.DeleteRegistry) -contains 'r2') -and -not (@($mp.RemoveComponents) -contains 'CompShared'))
Assert "cleanup: shared+keypath -> reassign keypath to file + delete row" ((@($mp.ReKeyPath | Where-Object { $_.Component -eq 'CompSharedKP' -and $_.NewKeyPath -eq 'f2' }).Count -eq 1) -and (@($mp.DeleteRegistry) -contains 'r5'))
Assert "cleanup: keypath reassign to a file clears the registry-keypath bit" ((@($mp.ReKeyPath | Where-Object { $_.Component -eq 'CompSharedKP' })[0].NewAttributes) -eq 0)
Assert "cleanup: desktop shortcut removed"                (@($mp.DeleteShortcuts) -contains 'scDesk')
Assert "cleanup: startup (autostart) shortcut removed"    (@($mp.DeleteShortcuts) -contains 'scStartup')
Assert "cleanup: sendto/stray shortcut removed"           (@($mp.DeleteShortcuts) -contains 'scSendTo')
Assert "cleanup: Start-Menu app shortcut KEPT"            (-not (@($mp.DeleteShortcuts) -contains 'scApp'))
# user-wins: all toggles OFF -> empty plan (a Keep selection is never overridden by the plan)
$mpOff = Resolve-MsiCleanupPlan -Registry $ckReg -File $ckFile -Shortcut $ckSc -Directory $ckDir -Component $ckComp -RemoveRun32 $false -RemoveRun64 $false -RemoveDesktop $false -RemoveStartup $false -RemoveStray $false
Assert "cleanup: all toggles off -> empty plan (user keep wins)" ((@($mpOff.RemoveComponents).Count -eq 0) -and (@($mpOff.DeleteRegistry).Count -eq 0) -and (@($mpOff.DeleteShortcuts).Count -eq 0))
# startup-only toggle removes ONLY the startup shortcut (independent categories)
$mpSu = Resolve-MsiCleanupPlan -Registry $ckReg -File $ckFile -Shortcut $ckSc -Directory $ckDir -Component $ckComp -RemoveRun32 $false -RemoveRun64 $false -RemoveDesktop $false -RemoveStartup $true -RemoveStray $false
Assert "cleanup: startup-only removes startup, keeps desktop+sendto" ((@($mpSu.DeleteShortcuts) -contains 'scStartup') -and -not (@($mpSu.DeleteShortcuts) -contains 'scDesk') -and -not (@($mpSu.DeleteShortcuts) -contains 'scSendTo'))
# REAL-MSI (only where present): the 3DExperience MSI has a dedicated run-key component -> removed whole; integrity CLEAN.
$ck3dx = 'C:\temp\DassaultSystems_3DExperience_x64_26.10.632-0001_en-US\Content\Files\3DEXPERIENCELauncher.msi'
if (Test-Path $ck3dx) {
  $ckI=New-Object -ComObject WindowsInstaller.Installer; $ckDb=$ckI.OpenDatabase($ck3dx,0)
  $ckPlan=Get-MsiCleanupPlan -Db $ckDb -RemoveRun32 $true -RemoveRun64 $true -RemoveDesktop $true -RemoveStartup $true -RemoveStray $true
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ckDb); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ckI); [GC]::Collect(); [GC]::WaitForPendingFinalizers()
  Assert "real-MSI 3DX: dedicated run-key component removed whole" (@($ckPlan.RemoveComponents) -contains 'C_RegSystray')
  Assert "real-MSI 3DX: startup shortcut queued for removal"        (@($ckPlan.DeleteShortcuts).Count -ge 1)
  $ckTmp=Join-Path $env:TEMP ('tbm_'+[guid]::NewGuid().ToString('N')+'.msi'); Copy-Item $ck3dx $ckTmp -Force
  $ckMst=Join-Path $env:TEMP ('tbm_'+[guid]::NewGuid().ToString('N')+'.mst')
  $ckI2=New-Object -ComObject WindowsInstaller.Installer; $ckDbo=$ckI2.OpenDatabase($ck3dx,0); $ckDbm=$ckI2.OpenDatabase($ckTmp,1)
  $ckPlan2=Get-MsiCleanupPlan -Db $ckDbm -RemoveRun32 $true -RemoveRun64 $true -RemoveDesktop $true -RemoveStartup $true -RemoveStray $true
  Invoke-MsiCleanupPlan -Db $ckDbm -Plan $ckPlan2
  $ckDbm.Commit()|Out-Null; $ckDbm.GenerateTransform($ckDbo,$ckMst)|Out-Null; $ckDbm.CreateTransformSummaryInfo($ckDbo,$ckMst,0,0)|Out-Null
  foreach($o in @($ckDbm,$ckDbo,$ckI2)){ [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o) }; [GC]::Collect(); [GC]::WaitForPendingFinalizers(); Remove-Item $ckTmp -Force -EA SilentlyContinue
  $ckIss=@(Test-MstIntegrity -MsiPath $ck3dx -MstPath $ckMst)
  Assert "real-MSI 3DX: MST integrity CLEAN (no dangling keypath)" ($ckIss.Count -eq 0)
  Remove-Item $ckMst -Force -EA SilentlyContinue
}
# ps1 injection: Add-PsadtRunKeyRemovals writes Remove-ADTRegistryKey into POST-INSTALLATION
$fakePs1 = Join-Path $env:TEMP ('rkps1_' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.ps1')
Set-Content -LiteralPath $fakePs1 -Value "##*=== POST-INSTALLATION BEGIN ===`r`n    ## <Perform Post-Installation tasks here>`r`n##*=== POST-INSTALLATION END ===`r`n" -Encoding UTF8
$nInj = Add-PsadtRunKeyRemovals -Ps1Path $fakePs1 -RunKeys @([pscustomobject]@{ PsKey='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Name='AcmeShared' })
$injTxt = Get-Content -LiteralPath $fakePs1 -Raw
Assert "ps1 injection: Remove-ADTRegistryKey added to POST-INSTALLATION" ($nInj -eq 1 -and $injTxt -match "Remove-ADTRegistryKey -Key 'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -Name 'AcmeShared'" -and $injTxt -match 'POST-INSTALLATION END')
# Auto-save Data now carries ChangeSet -> the Tree works on a LOADED report (was the empty-tree bug).
$csJson = @{ ReportText='R'; ChangeSet=$cs } | ConvertTo-Json -Depth 10
$csLoaded = ConvertTo-PBHashtable (($csJson | ConvertFrom-Json).ChangeSet)
Assert "saved report carries ChangeSet (tree on load)" ((@($csLoaded.Files | Where-Object { "$($_.Path)" -eq 'C:\App\a.exe' }).Count) -eq 1)

# ---- SELF-STAGE (run-from-share -> local): CORE copied first, heavy publish modules DEFERRED until needed ----
$stg = Join-Path $env:TEMP ('pbstage_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$shareD = Join-Path $stg 'share'; $localD = Join-Path $stg 'local'
foreach ($rel in 'PackageAssistance.exe','PackageAssistance.exe.config','PackageAssistance.pak','settings.json','snippets.json','KnowledgeBase.Recommend.json',
                 'Lib\ICSharpCode.AvalonEdit.dll','Lib\PackageBuilder.ico','Lib\PSADT_Template\Content\Invoke-AppDeployToolkit.ps1',
                 'Lib\ConfigurationManagerPrelive\ConfigurationManager.psd1','Lib\PowerShell Module\MSAL.PS 4.37.0.0\MSAL.PS.psd1','Lib\IntuneWinAppUtil.exe',
                 'PsExec64.exe','Tools\extra-helper.exe') {
    $fp = Join-Path $shareD $rel; $dir = Split-Path $fp -Parent; if (-not (Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    Set-Content -LiteralPath $fp -Value 'x' -Force
}
# DEPLOYMENT REALITY: the deployed pak ships Hidden+ReadOnly. Copy-IfNewer's timestamp compare used Get-Item WITHOUT
# -Force, which THROWS "cannot find path" on a Hidden file -> the self-stage crashed with a dialog. Reproduce it.
(Get-Item -LiteralPath (Join-Path $shareD 'PackageAssistance.pak') -Force).Attributes = 'Hidden, ReadOnly'
$rl = Invoke-SelfStage -Root $shareD -Local $localD -Force
Assert "self-stage: returns local exe path"             ("$rl" -eq (Join-Path $localD 'PackageAssistance.exe'))
Assert "self-stage: core exe+pak copied"                ((Test-Path (Join-Path $localD 'PackageAssistance.exe')) -and (Test-Path (Join-Path $localD 'PackageAssistance.pak')))
Assert "self-stage: HIDDEN pak copied (no 'cannot find path' crash)" (Test-Path (Join-Path $localD 'PackageAssistance.pak'))
Assert "self-stage: exe.config copied (UNC-share launcher config)"   (Test-Path (Join-Path $localD 'PackageAssistance.exe.config'))
Assert "self-stage: 3 JSON configs copied"              ((Test-Path (Join-Path $localD 'settings.json')) -and (Test-Path (Join-Path $localD 'snippets.json')) -and (Test-Path (Join-Path $localD 'KnowledgeBase.Recommend.json')))
Assert "self-stage: AvalonEdit + template copied"       ((Test-Path (Join-Path $localD 'Lib\ICSharpCode.AvalonEdit.dll')) -and (Test-Path (Join-Path $localD 'Lib\PSADT_Template\Content\Invoke-AppDeployToolkit.ps1')))
Assert "self-stage: ConfigMgr DEFERRED (not copied)"    (-not (Test-Path (Join-Path $localD 'Lib\ConfigurationManagerPrelive\ConfigurationManager.psd1')))
Assert "self-stage: MSAL DEFERRED (not copied)"         (-not (Test-Path (Join-Path $localD 'Lib\PowerShell Module\MSAL.PS 4.37.0.0\MSAL.PS.psd1')))
Assert "self-stage: .source marker points to share"     ((Get-StageSource -ToolRoot $localD) -eq $shareD)
Assert "self-stage: PsExec + Tools\ mirrored to local"   ((Test-Path (Join-Path $localD 'PsExec64.exe')) -and (Test-Path (Join-Path $localD 'Tools\extra-helper.exe')))
Ensure-PublishModulesStaged -ToolRoot $localD
Assert "ensure-modules: ConfigMgr now local"            (Test-Path (Join-Path $localD 'Lib\ConfigurationManagerPrelive\ConfigurationManager.psd1'))
Assert "ensure-modules: MSAL now local"                 (Test-Path (Join-Path $localD 'Lib\PowerShell Module\MSAL.PS 4.37.0.0\MSAL.PS.psd1'))
Assert "ensure-modules: IntuneWinAppUtil now local"     (Test-Path (Join-Path $localD 'Lib\IntuneWinAppUtil.exe'))
# Copy-IfNewer: create-missing then skip-when-dest-newer
$src1 = Join-Path $stg 's1.txt'; $dst1 = Join-Path $stg 'd1.txt'
Set-Content $src1 'v1' -Force; Copy-IfNewer -Source $src1 -Dest $dst1
Assert "copy-if-newer: creates missing"                 ((Get-Content $dst1) -eq 'v1')
Set-Content $dst1 'edited' -Force; (Get-Item $dst1).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(5)
Copy-IfNewer -Source $src1 -Dest $dst1
Assert "copy-if-newer: skips when dest is newer"        ((Get-Content $dst1) -eq 'edited')
Assert "test-networkpath: UNC true"                     (Test-NetworkPath '\\srv\s')
Assert "test-networkpath: local false"                  (-not (Test-NetworkPath 'C:\x'))
$noMk = Join-Path $stg 'nomarker'; New-Item $noMk -ItemType Directory -Force | Out-Null
$env:PB_SHAREROOT = '\\fallback\share'
Assert "stage-source: PB_SHAREROOT fallback"            ((Get-StageSource -ToolRoot $noMk) -eq '\\fallback\share')

# ---- Background-runspace visibility: functions called via Invoke-PBAsync MUST live in ENGINE modules (the async
#      runspace loads engine only - as GUI.ps1 functions they were invisible there; 'Find predecessor' returned nothing).
Assert "async-visible: Get-PredecessorCandidates in Predecessor.ps1" ((Get-Command Get-PredecessorCandidates).ScriptBlock.File -match 'Predecessor\.ps1$')
Assert "async-visible: Find-SourceFolder in Source.ps1"              ((Get-Command Find-SourceFolder).ScriptBlock.File -match 'Source\.ps1$')
Assert "async-visible: Find-OutgoingPackage in Sccm.ps1"             ((Get-Command Find-OutgoingPackage).ScriptBlock.File -match 'Sccm\.ps1$')
Assert "async-visible: Read-PredecessorModel in Predecessor.ps1"     ((Get-Command Read-PredecessorModel).ScriptBlock.File -match 'Predecessor\.ps1$')
# BtnPred / BtnFetch / BtnLoadOutgoing are SYNCHRONOUS (reverted from async in r156 - the nested-closure/runspace scope
# traps repeatedly broke the predecessor popup). Guard the revert: these handlers must NOT wrap their work in
# Invoke-PBAsync (which would reintroduce the closure-scope bug class the user hit at the demo).
$guiSrc = Get-Content (Resolve-Module 'GUI.ps1') -Raw
$predHandler = [regex]::Match($guiSrc, '(?s)\$BtnPred\.add_Click\(\{.*?\n\}\)').Value
Assert "BtnPred handler is synchronous (no Invoke-PBAsync)"  ($predHandler -and $predHandler -notmatch 'Invoke-PBAsync')
Assert "BtnPred calls Get-PredecessorCandidates directly"    ($predHandler -match 'Get-PredecessorCandidates' -and $predHandler -match 'Show-PredecessorPicker' -and $predHandler -match 'Read-PredecessorModel')
Assert "BtnPred ALWAYS shows picker (no count==1 auto-pick)" ($predHandler -notmatch 'cands\.Count -eq 1')
# Load/Save script buttons: present, Save disabled by default, enabled on Load, cleared on Rebuild
Assert "editor: Load .ps1 button present"            ($guiSrc -match 'x:Name="BtnLoadScript"')
Assert "editor: Save button disabled by default"     ($guiSrc -match '(?s)x:Name="BtnSaveScript".*?IsEnabled="False"')
Assert "editor: Save enabled only after Load"        (($guiSrc -match '\$BtnSaveScript\.IsEnabled = \$true') -and ($guiSrc -match '\$BtnSaveScript\.IsEnabled = \$false'))
Assert "editor: Save writes to the loaded path"      ($guiSrc -match '\[IO\.File\]::WriteAllText\(\$script:LoadedScriptPath')
# Snippet owner gating: write buttons hidden for non-owners
Assert "snippets: owner-only gate on Add/Edit/Del"   ($guiSrc -match 'Test-IsSnippetOwner' -and $guiSrc -match "BtnAddSnip, \`$BtnEditSnip, \`$BtnDelSnip")
Assert "snippets: Test-IsSnippetOwner exists + checks USERNAME" ((Get-Command Test-IsSnippetOwner -EA SilentlyContinue) -and ((Get-Content (Resolve-Module 'Core.ps1') -Raw) -match 'SnippetOwners'))
# Admin / SYSTEM test-console + install/uninstall/repair buttons
Assert "test-console: Admin + SYSTEM CMD buttons present" (($guiSrc -match 'x:Name="BtnAdminCmd"') -and ($guiSrc -match 'x:Name="BtnSystemCmd"'))
Assert "test-console: Admin CMD elevates (RunAs cmd.exe)" ($guiSrc -match "Start-Process 'cmd\.exe' -Verb RunAs")
Assert "test-console: SYSTEM CMD uses PsExec -s -i" (($guiSrc -match 'Find-PsExec') -and ($guiSrc -match '-accepteula -s -i cmd\.exe'))
Assert "test-deploy: Admin+SYSTEM install/uninstall/repair buttons" (($guiSrc -match 'x:Name="BtnAdminInstall"') -and ($guiSrc -match 'x:Name="BtnAdminUninstall"') -and ($guiSrc -match 'x:Name="BtnAdminRepair"') -and ($guiSrc -match 'x:Name="BtnSysInstall"') -and ($guiSrc -match 'x:Name="BtnSysUninstall"') -and ($guiSrc -match 'x:Name="BtnSysRepair"'))
Assert "test-deploy: Invoke-LocalDeploy runs entry exe with positional type" (($guiSrc -match 'function Invoke-LocalDeploy') -and ($guiSrc -match 'Get-LocalDeployEntry') -and ($guiSrc -match "Start-Process \`$exe -Verb RunAs -ArgumentList"))
Assert "test-deploy: SYSTEM deploy uses PsExec -s -w workdir" ($guiSrc -match '-accepteula -s -i -w')
# Loaded .ps1 folder is a valid test target (Admin CMD / deploy work after Load, not just after Create)
Assert "test-target: Get-CreatedContentDir honours LoadedScriptPath" ($guiSrc -match '(?s)function Get-CreatedContentDir.*?LoadedScriptPath.*?Split-Path')
# Candidate logic itself: finds the older version, skips self, newest first
$pcd = Join-Path $env:TEMP ('pbcand_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
foreach ($n in 'HBM_nCodeGlyphworks_x64_24.1.0-0001_en-US','HBM_nCodeGlyphworks_x64_26.0.0.0-0001_en-US','Other_App_x64_1.0-0001_MUL') { New-Item (Join-Path $pcd $n) -ItemType Directory -Force | Out-Null }
if (-not $script:Settings) { $script:Settings = @{} }
$oldPred = $script:Settings['PredecessorPath']
$script:Settings['PredecessorPath'] = $pcd
$cc = @(Get-PredecessorCandidates -Parsed (Parse-PackageName 'HBM_nCodeGlyphworks_x64_26.0.0.0-0001_en-US'))
if ($null -ne $oldPred) { $script:Settings['PredecessorPath'] = $oldPred } else { [void]$script:Settings.Remove('PredecessorPath') }
Assert "candidates: finds the 24.1.0 predecessor"        ((@($cc | Where-Object { $_.Name -match '24\.1\.0' }).Count -eq 1))
Assert "candidates: never offers the package itself"     (-not ($cc | Where-Object { $_.Name -match '26\.0\.0\.0' }))
Assert "candidates: other apps not offered"              (-not ($cc | Where-Object { $_.Name -match 'Other_App' }))
Remove-Item $pcd -Recurse -Force -ErrorAction SilentlyContinue
$env:PB_SHAREROOT = $null
Remove-Item $stg -Recurse -Force -ErrorAction SilentlyContinue

# ---- MULTI-installer predecessor reuse: EVERY component's filename + ProductCode swapped (not just the primary) ----
$predMulti = @'
$adtSession = @{ AppName='Suite'; AppVersion='1.0.0'; SoftIdent='Suite [DisplayVersion=1.0.0]' }
#*=== CUSTOM APPLICATION VARIABLES BEGIN ===
#*=== CUSTOM APPLICATION VARIABLES END ===
#*=== PRE-INSTALLATION BEGIN ===
#*=== PRE-INSTALLATION END ===
#*=== MAIN-INSTALLATION BEGIN ===
Start-ADTMsiProcess -Action Install -FilePath 'CompA_1.0.0.msi' -Transform 'CompA_1.0.0.mst' -ProductCode '{AAAA1111-1111-1111-1111-111111111111}'
Start-ADTMsiProcess -Action Install -FilePath 'CompB_1.0.0.msi' -Transform 'CompB_1.0.0.mst' -ProductCode '{BBBB2222-2222-2222-2222-222222222222}'
#*=== MAIN-INSTALLATION END ===
#*=== POST-INSTALLATION BEGIN ===
#*=== POST-INSTALLATION END ===
#*=== PRE-UNINSTALLATION BEGIN ===
#*=== PRE-UNINSTALLATION END ===
#*=== MAIN-UNINSTALLATION BEGIN ===
Start-ADTMsiProcess -Action Uninstall -ProductCode '{BBBB2222-2222-2222-2222-222222222222}'
Start-ADTMsiProcess -Action Uninstall -ProductCode '{AAAA1111-1111-1111-1111-111111111111}'
#*=== MAIN-UNINSTALLATION END ===
#*=== PRE-REPAIR BEGIN ===
#*=== PRE-REPAIR END ===
#*=== MAIN-REPAIR BEGIN ===
#*=== MAIN-REPAIR END ===
#*=== POST-REPAIR BEGIN ===
#*=== POST-REPAIR END ===
'@
if ($tpl) {
    $modelM  = Read-PredecessorModel -PackageName 'Acme_Suite_x64_1.0.0-0001_MUL' -Content $predMulti
    $newPkgM = @{ Version='2.0.0'; SoftIdent='Suite [DisplayVersion=2.0.0]'; Installers=@(
        @{ Type='MSI'; MsiFileName='CompA_2.0.0.msi'; ProductCode='{AAAA9999-9999-9999-9999-999999999999}' },
        @{ Type='MSI'; MsiFileName='CompB_2.0.0.msi'; ProductCode='{BBBB9999-9999-9999-9999-999999999999}' }
    )}
    $outM = Build-PredecessorScript -Model $modelM -NewPkg $newPkgM -Template $tpl -AddUninstallPrevious $false
    $miM  = [regex]::Match($outM, '(?s)MAIN-INSTALLATION BEGIN(.*?)MAIN-INSTALLATION END').Groups[1].Value
    $muM  = [regex]::Match($outM, '(?s)MAIN-UNINSTALLATION BEGIN(.*?)MAIN-UNINSTALLATION END').Groups[1].Value
    Assert "multi-pred: install swaps BOTH ProductCodes to new"   (($miM -match 'AAAA9999') -and ($miM -match 'BBBB9999'))
    Assert "multi-pred: install drops BOTH old ProductCodes"      (($miM -notmatch 'AAAA1111') -and ($miM -notmatch 'BBBB2222'))
    Assert "multi-pred: uninstall swaps BOTH ProductCodes to new" (($muM -match 'AAAA9999') -and ($muM -match 'BBBB9999'))
    Assert "multi-pred: BOTH new filenames present"               (($miM -match 'CompA_2\.0\.0\.msi') -and ($miM -match 'CompB_2\.0\.0\.msi'))
}

# ---- SoftIdent bitness normalisation ----
Assert "SoftIdent x86 gains WoW6432Node"   ((Normalize-SoftIdent 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\A' 'x86') -match 'SOFTWARE\\WoW6432Node\\')
Assert "SoftIdent x64 drops WoW6432Node"   ((Normalize-SoftIdent 'HKLM:\SOFTWARE\WoW6432Node\Microsoft\X' 'x64') -notmatch 'WoW6432Node')
Assert "SoftIdent resolves CurrentRegWOW"  ((Normalize-SoftIdent 'HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)Microsoft\X' 'x64') -notmatch 'VWG_CurrentRegWOW')
# Auto detection key (SoftIdent) from a ProductCode - single MSI, or an EXE that wraps an MSI (GUID in its uninstall).
Assert "auto-softident: MSI ProductCode -> Uninstall key" ((Get-AutoSoftIdent -ProductCode '{11112222-3333-4444-5555-666677778888}' -Version '1.0') -match 'Uninstall\\\{11112222-3333-4444-5555-666677778888\} \[DisplayVersion=1\.0\]')
Assert "auto-softident: EXE uninstall MSI-GUID -> key"   ((Get-AutoSoftIdent -ProductCode '' -Version '2.0' -SnapshotUninstall 'MsiExec.exe /X{99998888-7777-6666-5555-444433332222} /qn') -match '\{99998888-7777-6666-5555-444433332222\}')
Assert "auto-softident: no GUID -> empty"                 ([string]::IsNullOrEmpty((Get-AutoSoftIdent -ProductCode '' -Version '1.0' -SnapshotUninstall '"setup.exe" /uninstall')))

# ---- Fresh-package standard commands ----
$tplF = Get-TemplateScript
if ($tplF) {
    $msiOut = Build-FreshScript -NewPkg @{ Vendor='Acme';AppName='Tool';Arch='x64';Lang='MUL';Revision='0001';Version='1.0.0';MsiFileName='Tool.msi';ProductCode='{PC}';Author='Me' } -Template $tplF
    Assert "fresh MSI install command"     ($msiOut -match "Start-ADTMsiProcess -Action 'Install' -FilePath")
    Assert "fresh MSI repair has RepairMode" ($msiOut -match "Action 'Repair' -RepairMode 'Repair'")
    $exeOut = Build-FreshScript -NewPkg @{ Vendor='Acme';AppName='Tool';Arch='x64';Lang='MUL';Revision='0001';Version='1.0.0';ExeFileName='s.exe';InstallParams='/S';Author='Me' } -Template $tplF
    Assert "fresh EXE install command (double-quoted ArgumentList)" ($exeOut -match "Start-ADTProcess -FilePath .*s\.exe.* -ArgumentList `"/S`"")
    # ArgumentList double-quoted + inner quotes backtick-escaped:  /v"qn"  ->  "/v`"qn`""
    $qOut = Build-FreshScript -NewPkg @{ Vendor='Acme';AppName='Tool';Arch='x64';Lang='MUL';Revision='0001';Version='1.0.0';ExeFileName='s.exe';InstallParams='/S /v"qn"';Author='Me' } -Template $tplF
    Assert "EXE args inner quotes backtick-escaped" ($qOut -match ([regex]::Escape('-ArgumentList "/S /v`"qn`""')))
    # Snapshot-captured uninstall command is WRITTEN into the ps1 (MSI -> ProductCode; EXE uninstaller -> path+args).
    $unMsi = Build-FreshScript -NewPkg @{ Vendor='Acme';AppName='Tool';Arch='x64';Lang='MUL';Revision='0001';Version='1.0.0';ExeFileName='s.exe';InstallParams='/S';UninstallCommand='MsiExec.exe /X{11112222-3333-4444-5555-666677778888} /qn';Author='Me' } -Template $tplF
    Assert "snapshot MSI uninstall -> ProductCode"  ($unMsi -match "Start-ADTMsiProcess -Action 'Uninstall' -ProductCode '\{11112222-3333-4444-5555-666677778888\}'")
    $unExe = Build-FreshScript -NewPkg @{ Vendor='Acme';AppName='Tool';Arch='x64';Lang='MUL';Revision='0001';Version='1.0.0';ExeFileName='s.exe';InstallParams='/S';UninstallCommand='"C:\Program Files\Tool\unins000.exe" /SILENT';Author='Me' } -Template $tplF
    Assert "snapshot EXE uninstall -> path + args"  ($unExe -match ([regex]::Escape('Start-ADTProcess -FilePath ''C:\Program Files\Tool\unins000.exe'' -ArgumentList "/SILENT"')))
    # Multi-line raw uninstall (a suite: several applicable ARP entries) -> a v4 command PER entry.
    $multiRaw = "MsiExec.exe /X{11112222-3333-4444-5555-666677778888} /qn`r`n`"C:\App\unins000.exe`" /VERYSILENT"
    $multiOut = Convert-RawUninstallToPsadt -Cmd $multiRaw
    Assert "multi-uninstall: MSI line -> ProductCode" ($multiOut -match "Start-ADTMsiProcess -Action 'Uninstall' -ProductCode '\{11112222-3333-4444-5555-666677778888\}'")
    Assert "multi-uninstall: EXE line -> Start-ADTProcess" ($multiOut -match ([regex]::Escape("Start-ADTProcess -FilePath 'C:\App\unins000.exe'")))
    # Get-UninstallFromSnapshotDiff collects ALL applicable Added entries (suite), not just the primary.
    $diffU = @{ Programs = @{ Added = @(
        ([pscustomobject]@{ Id='{11112222-3333-4444-5555-666677778888}'; Info=@{ DisplayName='MASTA'; DisplayVersion='15.1'; _key='{11112222-3333-4444-5555-666677778888}'; _root='HKLM'; UninstallString='MsiExec.exe /X{11112222-3333-4444-5555-666677778888}'; QuietUninstallString='' } }),
        ([pscustomobject]@{ Id='{99998888-7777-6666-5555-444433332222}'; Info=@{ DisplayName='HASP Runtime'; DisplayVersion='8.0'; _key='{99998888-7777-6666-5555-444433332222}'; _root='HKLM'; UninstallString='MsiExec.exe /X{99998888-7777-6666-5555-444433332222}'; QuietUninstallString='' } })
    ); Noise=@() } }
    $un = Get-UninstallFromSnapshotDiff -Diff $diffU -AppName 'MASTA'
    Assert "snapshot: captures ALL uninstall entries" ([int]$un.UninstallCount -eq 2)
    Assert "snapshot: uninstall block has BOTH product codes" (($un.Uninstall -match '11112222') -and ($un.Uninstall -match '99998888'))
    # Shared MS runtimes (VC++/.NET) are SHOWN in the report but NOT auto-uninstalled (count stays 2 with VC++ added).
    $diffVC = @{ Programs = @{ Added = @(@($diffU.Programs.Added) + @(
        ([pscustomobject]@{ Id='{CCCC0000-0000-0000-0000-000000000000}'; Info=@{ DisplayName='Microsoft Visual C++ 2022 Redistributable'; _key='{CCCC0000-0000-0000-0000-000000000000}'; _root='HKLM'; UninstallString='MsiExec.exe /X{CCCC0000-0000-0000-0000-000000000000}'; QuietUninstallString='' } })
    )); Noise=@() } }
    $unVC = Get-UninstallFromSnapshotDiff -Diff $diffVC -AppName 'MASTA'
    Assert "snapshot: shared VC++ runtime NOT auto-uninstalled" (([int]$unVC.UninstallCount -eq 2) -and ($unVC.Uninstall -notmatch 'CCCC0000'))
    # SAME product, TWO registrations (MSI GUID + EXE uninstaller) at the SAME name+version -> collapse to the
    # ProductCode entry only; the redundant EXE uninstall string is dropped (user rule).
    $diffDup = @{ Programs = @{ Added = @(
        ([pscustomobject]@{ Id='{11112222-3333-4444-5555-666677778888}'; Info=@{ DisplayName='Zscaler'; DisplayVersion='4.9.0.412'; _key='{11112222-3333-4444-5555-666677778888}'; _root='HKLM'; UninstallString='MsiExec.exe /X{11112222-3333-4444-5555-666677778888}'; QuietUninstallString='' } }),
        ([pscustomobject]@{ Id='ZscalerEXE'; Info=@{ DisplayName='Zscaler'; DisplayVersion='4.9.0.412'; _key='ZscalerEXE'; _root='HKLM'; UninstallString='"C:\Program Files\Zscaler\ZSAInstaller\uninstall.exe" /S'; QuietUninstallString='' } })
    ); Noise=@() } }
    $unDup = Get-UninstallFromSnapshotDiff -Diff $diffDup -AppName 'Zscaler'
    Assert "snapshot: same product MSI+EXE -> ProductCode only" (([int]$unDup.UninstallCount -eq 1) -and ($unDup.Uninstall -match '11112222') -and ($unDup.Uninstall -notmatch 'uninstall\.exe'))
    # #1: a NEW ARP entry is shown (Added) even if its name matches a noise token (Sentinel HASP, not SentinelOne EDR).
    $cmpP = Compare-MachineSnapshot -Before @{ Programs=@{} } -After @{ Programs=@{ 'HKLM:\U\{A}'=@{ DisplayName='Sentinel HASP Run-time'; _key='{A}'; _root='HKLM'; UninstallString='x' } } } -AppVendor 'EQS' -AppName 'MASTA'
    Assert "Programs: new ARP shown even if vendor-noise" (@($cmpP.Programs.Added).Count -eq 1)
    # #2: FILES report groups by FOLDER; a folder with <=3 files is expanded, a bigger one is summarised.
    $fdG = @{ New=@(
        ([pscustomobject]@{ Path='C:\Program Files\App\app.exe'; Change='new'; IsApp=$true }),
        ([pscustomobject]@{ Path='C:\Program Files\App\bin\a.dll'; Change='new'; IsApp=$true }),
        ([pscustomobject]@{ Path='C:\Program Files\App\bin\b.dll'; Change='new'; IsApp=$true }),
        ([pscustomobject]@{ Path='C:\Program Files\App\bin\c.dll'; Change='new'; IsApp=$true }),
        ([pscustomobject]@{ Path='C:\Program Files\App\bin\d.dll'; Change='new'; IsApp=$true })
    ); Deleted=@(); NoiseCount=0; ModifiedCount=0 }
    $repG = Get-SnapshotReportText -Diff @{} -FileDiff $fdG -RegDiff @{New=@();Deleted=@();NoiseCount=0} -EnvChanges @() -Un $null -AppTokens @('app') -OnlyCat 'Files'
    Assert "files report: groups by folder with count" ($repG -match 'App\\bin\\\s+\(4 files\)')
    Assert "files report: big folder NOT expanded"      ($repG -notmatch 'a\.dll')
    Assert "files report: small folder expanded"         ($repG -match 'app\.exe')
    # Snapshot cleanups (remove desktop shortcut / Run key, disable auto-update) are WRITTEN into POST-INSTALLATION.
    $piOut = Build-FreshScript -NewPkg @{ Vendor='Acme';AppName='Tool';Arch='x64';Lang='MUL';Revision='0001';Version='1.0.0';ExeFileName='s.exe';InstallParams='/S';PostInstallExtra="Remove-ADTFile -Path 'C:\Users\Public\Desktop\Tool.lnk'";Author='Me' } -Template $tplF
    Assert "snapshot cleanup written into POST-INSTALLATION" ($piOut -match "(?s)POST-INSTALLATION BEGIN.*Remove-ADTFile -Path 'C:\\Users\\Public\\Desktop\\Tool\.lnk'.*POST-INSTALLATION END")
    # Get-SnapshotCleanups emits real commands per cleanup kind.
    $cd = [ordered]@{ RunKeys=@{Added=@( [pscustomobject]@{Id='HKLM..Run!Foo'; Info=@{Name='Foo';Command='x';Hive='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'}} )}; Shortcuts=@{Added=@( [pscustomobject]@{Id='C:\Users\Public\Desktop\Foo.lnk'; Info=@{Name='Foo'}} )} }
    $cl = @(Get-SnapshotCleanups -Diff $cd -AppName 'Foo')
    Assert "cleanup: desktop shortcut -> Remove-ADTFile" (@($cl | Where-Object { $_.Kind -eq 'Shortcut' -and $_.Command -match 'Remove-ADTFile' }).Count -eq 1)
    Assert "cleanup: run key -> Remove-ADTRegistryKey"   (@($cl | Where-Object { $_.Kind -eq 'RunKey'   -and $_.Command -match 'Remove-ADTRegistryKey' }).Count -eq 1)
    # Cert/driver cleanup + uninstall-shortcut: certs auto-remove on POST-UNINSTALL (tagged), drivers OFF-by-default,
    # a Start-Menu UNINSTALL shortcut is flagged for POST-INSTALL removal, a normal app shortcut is NOT flagged.
    $cd2 = [ordered]@{
        Certificates=@{Added=@( [pscustomobject]@{Id='TrustedPublisher\ABCDEF0123'; Info=@{Subject='CN=Acme';Store='TrustedPublisher'}} )}
        Drivers=@{Added=@( [pscustomobject]@{Id='heci.inf_amd64_abc123'; Info=@{Name='heci.inf_amd64_abc123'}} )}
        Shortcuts=@{Added=@(
            [pscustomobject]@{Id='C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Acme\Uninstall Acme.lnk'; Info=@{Name='Uninstall Acme'}},
            [pscustomobject]@{Id='C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Acme\Acme.lnk'; Info=@{Name='Acme'}}
        )}
    }
    $cl2 = @(Get-SnapshotCleanups -Diff $cd2 -AppName 'Acme')
    Assert "cleanup: cert -> post-uninstall tag + default on" (@($cl2 | Where-Object { $_.Kind -eq 'Certificate' -and $_.Command -match '\[post-uninstall\]' -and $_.Default }).Count -eq 1)
    Assert "cleanup: uninstall shortcut flagged"              (@($cl2 | Where-Object { $_.Kind -eq 'Shortcut' -and $_.Label -match 'uninstall shortcut' }).Count -eq 1)
    Assert "cleanup: normal app shortcut NOT flagged"         (@($cl2 | Where-Object { $_.Kind -eq 'Shortcut' -and $_.Label -match ': Acme$' }).Count -eq 0)
    Assert "cleanup: driver -> Remove-PnPDrivers helper only + tag + default on" (@($cl2 | Where-Object { $_.Kind -eq 'Driver' -and $_.Default -and $_.Command -match "Remove-PnPDrivers -Delinflist 'heci'" -and $_.Command -match '\[post-uninstall\]' -and $_.Command -notmatch 'Get-WindowsDriver' -and $_.Command -notmatch 'if \(Get-Command' }).Count -eq 1)
    # Tasks now UNREGISTER (not disable); new font + env-var cleanups.
    $cdT = [ordered]@{ Tasks=@{Added=@( [pscustomobject]@{Id='\MS\Up'; Info=@{Name='AcmeUpdate'; Path='\MS\'}} )} }
    $fdF = @{ New=@( [pscustomobject]@{ Path='C:\Windows\Fonts\Acme.ttf'; Change='new' } ) }
    $evA = @( ([pscustomobject]@{ Name='MACHINE\ACME_HOME'; New='C:\Acme'; Change='added' }), ([pscustomobject]@{ Name='MACHINE\Path'; New='x'; Change='changed' }) )
    $cl3 = @(Get-SnapshotCleanups -Diff $cdT -AppName 'Acme' -FileDiff $fdF -EnvChanges $evA)
    Assert "cleanup: task -> Unregister-ScheduledTask"        (@($cl3 | Where-Object { $_.Kind -eq 'Task' -and $_.Command -match 'Unregister-ScheduledTask' }).Count -eq 1)
    Assert "cleanup: font -> Remove-MTBFonts + post-uninstall" (@($cl3 | Where-Object { $_.Kind -eq 'Font' -and $_.Command -match "Remove-MTBFonts -FontName 'Acme.ttf'" -and $_.Command -match '\[post-uninstall\]' }).Count -eq 1)
    Assert "cleanup: added env var -> Remove-ADTEnvironmentVariable" (@($cl3 | Where-Object { $_.Kind -eq 'EnvVar' -and $_.Command -match "Remove-ADTEnvironmentVariable -Variable 'ACME_HOME' -Target 'Machine'" }).Count -eq 1)
    Assert "cleanup: PATH change NOT auto-removed"            (@($cl3 | Where-Object { $_.Kind -eq 'EnvVar' -and $_.Label -match '(?i)path' }).Count -eq 0)
    # POST-UNINSTALL injection INSERTS after the marker and KEEPS the template's branding removal (Set-SectionBody).
    $tplU = "#*=== POST-UNINSTALLATION BEGIN ===`r`n    ## <Perform Post-UnInstallation tasks here>`r`n        Remove-MTBDetectionKey`r`n#*=== POST-UNINSTALLATION END ==="
    $uOut = Add-StandardCommands -Template $tplU -Cmds @{ PostUninstall = "Remove-Item -LiteralPath 'Cert:\LocalMachine\Root\ABC' -Force   # [post-uninstall] remove cert" }
    Assert "post-uninstall cleanup inserted"        ($uOut -match "(?s)POST-UNINSTALLATION BEGIN.*Remove-Item -LiteralPath 'Cert:\\LocalMachine\\Root\\ABC'.*POST-UNINSTALLATION END")
    Assert "post-uninstall keeps branding removal"  ($uOut -match 'Remove-MTBDetectionKey')
    Assert "cleanup runs BEFORE branding removal"   ($uOut.IndexOf('Remove-Item -LiteralPath') -lt $uOut.IndexOf('Remove-MTBDetectionKey'))
    # Custom actions written into PRE-INSTALL / PRE-UNINSTALL sections (packaging-engineer config).
    $caOut = Build-FreshScript -NewPkg @{ Vendor='Acme';AppName='Tool';Arch='x64';Lang='MUL';Revision='0001';Version='1.0.0';ExeFileName='s.exe';InstallParams='/S';PreInstallExtra="Close-ADTInstallationProgress -Force   # custom pre";PreUninstallExtra="Write-ADTLogEntry -Message 'custom pre-uninstall'";Author='Me' } -Template $tplF
    Assert "custom action -> PRE-INSTALLATION"    ($caOut -match "(?s)PRE-INSTALLATION BEGIN.*Close-ADTInstallationProgress -Force.*PRE-INSTALLATION END")
    Assert "custom action -> PRE-UNINSTALLATION"  ($caOut -match "(?s)PRE-UNINSTALLATION BEGIN.*custom pre-uninstall.*PRE-UNINSTALLATION END")
    $looseOut = Build-FreshScript -NewPkg @{ Vendor='Acme';AppName='Tool';Arch='x64';Lang='MUL';Revision='0001';Version='1.0.0';InstallerMode='LooseFiles';CreateArp=$true;Shortcuts=@(@{Target='App.exe'});Author='Me' } -Template $tplF
    Assert "loose extracts zip payload"    ($looseOut -match 'Expand-MTBZipFile -Path .*DirFiles')
    Assert "loose creates ARP entry"       ($looseOut -match 'Set-MTBApplicationWizardEntry')
    Assert "loose shortcut on Start Menu"  ($looseOut -match 'New-ADTShortcut -Path .*envCommonStartMenuPrograms')
    $fsOut = Build-FreshScript -NewPkg @{ Vendor='Acme';AppName='Tool';Arch='x64';Lang='MUL';Revision='0001';Version='1.0.0';MsiFileName='t.msi';FreeSpace=512;Author='Me' } -Template $tplF
    Assert "FreeSpace auto-filled"         ($fsOut -match "FreeSpace\s*=\s*'512'")
    # ProcToClose/ProcToBlock from the app's shortcut exes -> written as array literals into the session.
    $pcOut = Build-FreshScript -NewPkg @{ Vendor='Acme';AppName='Tool';Arch='x64';Lang='MUL';Revision='0001';Version='1.0.0';MsiFileName='t.msi';ProcToClose=@('toolexe','helper');ProcToBlock=@('toolexe');Author='Me' } -Template $tplF
    # GPF template shape: the fields live on wrapper lines ("[string[]] $Global:VWG_ProcToClose = ...").
    $pfx = "^\s*(?:\[[A-Za-z0-9\[\]]+\]\s*)?(?:\`$(?:Global:)?)?(?:VWG_)?"
    Assert "ProcToClose array written"     ($pcOut -match "(?m)${pfx}ProcToClose\s*=\s*@\('toolexe', 'helper'\)")
    Assert "ProcToBlock array written"     ($pcOut -match "(?m)${pfx}ProcToBlock\s*=\s*@\('toolexe'\)")
    Assert "ProcToCloseNonUI NOT clobbered" ($pcOut -match "(?m)${pfx}ProcToCloseNonUI\s*=")
    # ProcToBlock defaults to ProcToClose: when ProcToBlock is left as the template default (@()), it mirrors ProcToClose.
    $pbDefOut = Build-FreshScript -NewPkg @{ Vendor='Acme';AppName='Tool';Arch='x64';Lang='MUL';Revision='0001';Version='1.0.0';MsiFileName='t.msi';ProcToClose=@('toolexe','helper');Author='Me' } -Template $tplF
    Assert "ProcToBlock defaults to ProcToClose" ($pbDefOut -match "(?m)${pfx}ProcToBlock\s*=\s*@\('toolexe', 'helper'\)")
    # Set-ProcToBlockDefault idempotency: mirror empty/reference forms, SKIP an already-authored list.
    Assert "PTB mirror: empty @()"   ((Set-ProcToBlockDefault -Text "ProcToClose = @('a')`r`nProcToBlock = @()`r`n")                       -match "ProcToBlock = @\('a'\)")
    Assert "PTB mirror: \$adtSession ref" ((Set-ProcToBlockDefault -Text "ProcToClose = @('a')`r`nProcToBlock = `$adtSession.ProcToClose`r`n") -match "ProcToBlock = @\('a'\)")
    Assert "PTB mirror: \$VWG_ ref"   ((Set-ProcToBlockDefault -Text "ProcToClose = @('a')`r`nProcToBlock = `$VWG_ProcToClose`r`n")          -match "ProcToBlock = @\('a'\)")
    Assert "PTB skip: authored list"  ((Set-ProcToBlockDefault -Text "ProcToClose = @('a')`r`nProcToBlock = @('b')`r`n")                      -match "ProcToBlock = @\('b'\)")
    Assert "PTB skip: empty ProcToClose" ((Set-ProcToBlockDefault -Text "ProcToClose = @()`r`nProcToBlock = @()`r`n")                          -match "ProcToBlock = @\(\)")
}
# ---- Multiple MSIs (bundled-wrapper suite): install IN ORDER, uninstall in REVERSE, one MST each ----
$multi = Get-MultiCommandSet -Order @(
    @{ Type='MSI'; MsiFileName='A.msi'; MstFileName='A.mst'; ProductCode='{AAA}' },
    @{ Type='MSI'; MsiFileName='B.msi'; MstFileName='B.mst'; ProductCode='{BBB}' })
$mi = @($multi.MainInstall   -split "`r?`n" | Where-Object { $_ -match 'Install' })
$mu = @($multi.MainUninstall -split "`r?`n" | Where-Object { $_ -match 'Uninstall' })
Assert "multi-MSI installs in order (A then B)"        (($mi.Count -eq 2) -and ($mi[0] -match '\\A\.msi') -and ($mi[1] -match '\\B\.msi'))
Assert "multi-MSI uninstalls in reverse (B then A)"    (($mu.Count -eq 2) -and ($mu[0] -match '\{BBB\}') -and ($mu[1] -match '\{AAA\}'))
Assert "multi-MSI references each MST"                 (($multi.MainInstall -match '\\A\.mst') -and ($multi.MainInstall -match '\\B\.mst'))
Assert "multi-MSI repair reinstalls both"              ((@($multi.MainRepair -split "`r?`n" | Where-Object { $_ -match 'Install' }).Count) -eq 2)

# ---- Multiple EXEs: each analyzed installer's OWN install/uninstall args merge independently into the ps1 ----
$multiE = Get-MultiCommandSet -Order @(
    @{ Type='EXE'; ExeFileName='one\a.exe'; InstallParams='/S /A'; UninstallParams='/uninstallA' },
    @{ Type='EXE'; ExeFileName='two\b.exe'; InstallParams='/VERYSILENT'; UninstallParams='/uninstallB' })
Assert "multi-EXE installs A then B, each with its OWN args"  (($multiE.MainInstall -match 'a\.exe.*?/S /A') -and ($multiE.MainInstall -match 'b\.exe.*?/VERYSILENT') -and ($multiE.MainInstall.IndexOf('a.exe') -lt $multiE.MainInstall.IndexOf('b.exe')))
Assert "multi-EXE uninstalls in REVERSE, each with OWN args"  (($multiE.MainUninstall -match 'b\.exe.*?/uninstallB') -and ($multiE.MainUninstall -match 'a\.exe.*?/uninstallA') -and ($multiE.MainUninstall.IndexOf('b.exe') -lt $multiE.MainUninstall.IndexOf('a.exe')))
Assert "multi-EXE repair = reinstall all (A then B)"          (($multiE.MainRepair -match 'a\.exe') -and ($multiE.MainRepair -match 'b\.exe') -and ($multiE.MainRepair.IndexOf('a.exe') -lt $multiE.MainRepair.IndexOf('b.exe')))
# Mixed MSI + EXE in one package: each kind keeps its own command shape, merged in order.
$multiMix = Get-MultiCommandSet -Order @(
    @{ Type='MSI'; MsiFileName='core.msi'; MstFileName='core.mst'; ProductCode='{CORE}' },
    @{ Type='EXE'; ExeFileName='addon.exe'; InstallParams='/silent'; UninstallParams='/x' })
Assert "multi-mix: MSI via Start-ADTMsiProcess + EXE via Start-ADTProcess" (($multiMix.MainInstall -match 'Start-ADTMsiProcess.*core\.msi') -and ($multiMix.MainInstall -match 'Start-ADTProcess.*addon\.exe.*?/silent'))
Assert "multi-mix: uninstall reversed (EXE addon before MSI core)"        ($multiMix.MainUninstall.IndexOf('addon.exe') -lt $multiMix.MainUninstall.IndexOf('{CORE}'))

# ---- Icon/Doc discovery must NEVER climb out of the package into a sibling package on a shared drive ----
Assert "pkg-root from nested source subfolder"  ((Get-PackageRootFolder -Path '\\srv\share\Incoming\Mozilla_Firefox_x86_140.12.0-0001_MUL\source\source') -eq '\\srv\share\Incoming\Mozilla_Firefox_x86_140.12.0-0001_MUL')
Assert "pkg-root null on a multi-package share"  (-not (Get-PackageRootFolder -Path '\\srv\share\Incoming'))

# ---- Find-VendorMst: the "single .mst -> use it" fallback must NOT apply a stray MST across a MULTI-MSI folder ----
$vmDir = Join-Path ([IO.Path]::GetTempPath()) ("vmtest_" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item $vmDir -ItemType Directory -Force | Out-Null
try {
    Set-Content (Join-Path $vmDir 'A.msi') 'x'; Set-Content (Join-Path $vmDir 'B.msi') 'x'; Set-Content (Join-Path $vmDir 'transforms.mst') 'x'
    Assert "vendor-MST: multi-MSI + stray .mst -> no false pairing" (-not (Find-VendorMst (Join-Path $vmDir 'A.msi')))
    Set-Content (Join-Path $vmDir 'A.mst') 'x'
    Assert "vendor-MST: exact-name match still wins"               ((Find-VendorMst (Join-Path $vmDir 'A.msi')) -eq (Join-Path $vmDir 'A.mst'))
    $vmDir2 = Join-Path ([IO.Path]::GetTempPath()) ("vmtest2_" + [guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item $vmDir2 -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $vmDir2 'App.msi') 'x'; Set-Content (Join-Path $vmDir2 'vendor.mst') 'x'
    Assert "vendor-MST: single-MSI folder still uses the lone .mst" ((Find-VendorMst (Join-Path $vmDir2 'App.msi')) -eq (Join-Path $vmDir2 'vendor.mst'))
    Remove-Item $vmDir2 -Recurse -Force -ErrorAction SilentlyContinue
} finally { Remove-Item $vmDir -Recurse -Force -ErrorAction SilentlyContinue }

# ---- Fresh package: detection-key (SoftIdent) sanity warning so a guessed key is flagged before deploy ----
$freshMsiGuess = @"
        AppName = 'DemoApp'
        SoftIdent = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\DemoApp [DisplayVersion = 1.0.0]'
# MAIN-UNINSTALLATION BEGIN
Start-ADTMsiProcess -Action 'Uninstall' -ProductCode '{11111111-1111-1111-1111-111111111111}'
# MAIN-UNINSTALLATION END
"@
$frFresh = @(Get-ScriptReviewFindings -ScriptText $freshMsiGuess -IsPredecessor $false)
Assert "fresh MSI w/ guessed SoftIdent -> detection warning" (@($frFresh | Where-Object { $_ -match '0x87D00324|ProductCode' }).Count -ge 1)
$frPred = @(Get-ScriptReviewFindings -ScriptText $freshMsiGuess -IsPredecessor $true)
Assert "predecessor build does NOT get the fresh-detection warning" (@($frPred | Where-Object { $_ -match 'does NOT use the MSI ProductCode' }).Count -eq 0)
$freshMsiGood = $freshMsiGuess -replace 'Uninstall\\DemoApp ', 'Uninstall\{11111111-1111-1111-1111-111111111111} '
$frGood = @(Get-ScriptReviewFindings -ScriptText $freshMsiGood -IsPredecessor $false)
Assert "fresh MSI w/ ProductCode SoftIdent -> no detection warning" (@($frGood | Where-Object { $_ -match '0x87D00324' }).Count -eq 0)

# ---- KB engine-type tier: suggest install + uninstall from the engine even with no vendor/app match ----
$kbN = Get-KBRecommendation -Vendor 'ZzNoVendor' -App 'ZzNoApp' -Engine 'NSIS' -InstallerName 'brandnew_setup.exe'
Assert "KB engine tier returns install for NSIS"      ($kbN -and "$($kbN.Install)".Trim())
Assert "KB engine tier returns uninstall too"         ($kbN -and "$($kbN.Uninstall)".Trim())
Assert "engine uninstall switch: Inno -> VERYSILENT"  ((Get-EngineUninstallSwitch -Engine 'InnoSetup') -match 'VERYSILENT')
Assert "engine uninstall switch: NSIS -> /S"          ((Get-EngineUninstallSwitch -Engine 'NSIS') -eq '/S')
Assert "clean-switch filter rejects a path/answer blob" (-not (Test-CleanSwitch '-f "$dirFiles\installer.properties" -DACCEPT_EULA=YES'))
Assert "clean-switch filter keeps a plain /S"         (Test-CleanSwitch '/S')
# Engine-match guard: a switch must fit the EXE's engine (don't suggest an Inno switch for an NSIS exe).
Assert "engine-match: NSIS accepts /S"                (Test-SwitchMatchesEngine -Sw '/S' -Engine 'NSIS')
Assert "engine-match: NSIS rejects /VERYSILENT"       (-not (Test-SwitchMatchesEngine -Sw '/VERYSILENT' -Engine 'NSIS'))
Assert "engine-match: Inno accepts /VERYSILENT"       (Test-SwitchMatchesEngine -Sw '/VERYSILENT' -Engine 'InnoSetup')
Assert "engine-match: empty + custom never block"     ((Test-SwitchMatchesEngine -Sw '' -Engine 'NSIS') -and (Test-SwitchMatchesEngine -Sw '/x' -Engine 'Custom'))
Assert "KB names the uninstaller EXE (Inno -> unins000)" ((Get-KBRecommendation -Vendor 'Zz' -App 'Zz' -Engine 'InnoSetup' -InstallerName 'x.exe').UninstallExe -match 'unins000')
Assert "engine uninstaller: MSI -> msiexec /x"        ((Get-EngineUninstaller -Engine 'MSI') -match 'msiexec /x')
Assert "engine uninstaller: NSIS -> Uninstall.exe"    ((Get-EngineUninstaller -Engine 'NSIS') -match 'Uninstall')

# ---- FreeSpace: max(payload, installed footprint, 150 MB floor) ----
Assert "FreeSpace floor 150 when nothing measured"    ((Get-PayloadSizeMB -ChosenInstallers @()) -eq 150)
Assert "FreeSpace uses installed footprint when bigger" ((Get-PayloadSizeMB -ChosenInstallers @() -InstalledMB 800) -eq 800)
Assert "FreeSpace installed below floor -> floor wins"  ((Get-PayloadSizeMB -ChosenInstallers @() -InstalledMB 40) -eq 150)
Assert "FreeSpace custom floor honoured"               ((Get-PayloadSizeMB -ChosenInstallers @() -MinMB 300 -InstalledMB 40) -eq 300)

# ---- Get-SiblingDocItems: carry siblings of a named 'source' folder into Documents; skip generic/temp parents ----
$sibRoot = Join-Path ([IO.Path]::GetTempPath()) ("sib_" + [guid]::NewGuid().ToString('N').Substring(0,8))
try {
    $pkgDir = Join-Path $sibRoot 'Acme_Tool_x64_1.0.0-0001_MUL'
    New-Item (Join-Path $pkgDir 'source')  -ItemType Directory -Force | Out-Null
    New-Item (Join-Path $pkgDir 'extras')  -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $pkgDir 'source\setup.exe')   'x'
    Set-Content (Join-Path $pkgDir 'install.docx')       'x'
    Set-Content (Join-Path $pkgDir 'extras\config.xml')  'x'
    Set-Content (Join-Path $pkgDir 'leftover.msi')       'x'   # stray installer must NOT be carried as a doc
    $sib = @(Get-SiblingDocItems -InstallerParent (Join-Path $pkgDir 'source') -ExcludePaths @())
    Assert "siblings: carries doc file + extras folder"  (($sib.Count -eq 2) -and (@($sib | Where-Object { $_ -match 'install\.docx' }).Count -eq 1) -and (@($sib | Where-Object { $_ -match '\\extras$' }).Count -eq 1))
    Assert "siblings: never carries a stray installer"   (@($sib | Where-Object { $_ -match 'leftover\.msi' }).Count -eq 0)
    Assert "siblings: never carries the source folder"   (@($sib | Where-Object { $_ -match '\\source$' }).Count -eq 0)
    # generic parent (temp\setup.exe) -> nothing harvested
    $tmpDir = Join-Path $sibRoot 'temp'
    New-Item $tmpDir -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $tmpDir 'setup.exe') 'x'; Set-Content (Join-Path $sibRoot 'junk.txt') 'x'
    Assert "siblings: generic temp parent harvests nothing" ((@(Get-SiblingDocItems -InstallerParent $tmpDir -ExcludePaths @())).Count -eq 0)
    # named 'source' but GENERIC grandparent (Downloads\source) -> nothing
    $dlDir = Join-Path $sibRoot 'Downloads'
    New-Item (Join-Path $dlDir 'source') -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $dlDir 'source\setup.exe') 'x'; Set-Content (Join-Path $dlDir 'other.txt') 'x'
    Assert "siblings: generic grandparent harvests nothing" ((@(Get-SiblingDocItems -InstallerParent (Join-Path $dlDir 'source') -ExcludePaths @())).Count -eq 0)
} finally { Remove-Item $sibRoot -Recurse -Force -ErrorAction SilentlyContinue }

# ---- Flat-folder manual pick: docs (by extension) -> Documents; installer + support files -> Files ----
$flatRoot = Join-Path ([IO.Path]::GetTempPath()) ("flat_" + [guid]::NewGuid().ToString('N').Substring(0,8))
try {
    $src = Join-Path $flatRoot 'Vendor_App_x64_1.0-0001_MUL'
    New-Item (Join-Path $src 'plugins') -ItemType Directory -Force | Out-Null   # a payload subfolder (Firefox-style)
    Set-Content (Join-Path $src 'setup.exe')      'x'   # the picked installer -> Files
    Set-Content (Join-Path $src 'support.dll')    'x'   # support file -> Files (NOT docs)
    Set-Content (Join-Path $src 'config.ini')     'x'   # support file -> Files
    Set-Content (Join-Path $src 'Install Guide.pdf') 'x'  # doc -> Documents
    Set-Content (Join-Path $src 'readme.txt')     'x'   # doc -> Documents
    Set-Content (Join-Path $src 'plugins\data.txt') 'x' # inside subfolder -> stays in Files (NOT reclassified)
    $loose = @(Get-LooseDocFiles -Folder $src)
    Assert "flat docs: pdf + txt detected at root"   ((@($loose | Where-Object { $_ -match 'Install Guide\.pdf' }).Count -eq 1) -and (@($loose | Where-Object { $_ -match 'readme\.txt' }).Count -eq 1))
    Assert "flat docs: support .dll/.ini NOT docs"   (@($loose | Where-Object { $_ -match 'support\.dll|config\.ini' }).Count -eq 0)
    Assert "flat docs: subfolder .txt NOT reclassified" (@($loose | Where-Object { $_ -match 'data\.txt' }).Count -eq 0)
    # End-to-end copy: docs -> Documents, everything else (incl. subfolder + support files) -> Files, no doc dup in Files
    $dest = Join-Path $flatRoot 'out'; $fdir = Join-Path $dest 'Files'; $ddir = Join-Path $dest 'Documents'
    $resv = @{ Manual=$false; Mode='manual'; PayloadRoot=$src; DocItems=@($loose); IconsPath=$null }
    Copy-ResolvedSource -Resolved $resv -ChosenInstallers @((Get-Item (Join-Path $src 'setup.exe'))) -InstallerDest $fdir -DocDest $ddir
    Assert "flat copy: docs in Documents"            ((Test-Path (Join-Path $ddir 'Install Guide.pdf')) -and (Test-Path (Join-Path $ddir 'readme.txt')))
    Assert "flat copy: docs NOT duplicated in Files" ((-not (Test-Path (Join-Path $fdir 'Install Guide.pdf'))) -and (-not (Test-Path (Join-Path $fdir 'readme.txt'))))
    Assert "flat copy: installer + support + subfolder in Files" ((Test-Path (Join-Path $fdir 'setup.exe')) -and (Test-Path (Join-Path $fdir 'support.dll')) -and (Test-Path (Join-Path $fdir 'config.ini')) -and (Test-Path (Join-Path $fdir 'plugins\data.txt')))
} finally { Remove-Item $flatRoot -Recurse -Force -ErrorAction SilentlyContinue }

# ---- Predecessor docs NEVER ship: the build-time guard drops predecessor items regardless of mode (manual/fetch/brand).
#      Covers a folder item that IS the predecessor folder AND a file harvested from inside it, on \ or /. Team-reported:
#      a MANUAL installer pick was carrying "...\Predecessor\..." documents into the new package's Documents. ----
$pdIn = @(
    'C:\temp\INA_Tenable_x64_11.2.0-0001_ZXX\Documents\Install Instructions.docx',   # current -> KEEP
    'C:\temp\INA_Tenable_x64_11.2.0-0001_ZXX\Predecessor',                            # folder item -> DROP
    'C:\temp\INA_Tenable_x64_11.2.0-0001_ZXX\Predecessor\Old Install.pdf',            # file inside -> DROP
    'C:/temp/req/predecessor/forward-slash.pdf',                                      # / separators -> DROP
    'C:\temp\req\PredecessorArchive\keep.pdf'                                          # not the folder (no boundary) -> KEEP
)
$pdOut = @(Remove-PredecessorDocItems -DocItems $pdIn)
Assert "pred-docs: current document kept"          (($pdOut -contains 'C:\temp\INA_Tenable_x64_11.2.0-0001_ZXX\Documents\Install Instructions.docx'))
Assert "pred-docs: predecessor FOLDER item dropped" (-not ($pdOut | Where-Object { $_ -eq 'C:\temp\INA_Tenable_x64_11.2.0-0001_ZXX\Predecessor' }))
Assert "pred-docs: file inside Predecessor dropped"  (-not ($pdOut | Where-Object { $_ -match '(?i)\\Predecessor\\Old Install' }))
Assert "pred-docs: forward-slash predecessor dropped" (-not ($pdOut | Where-Object { $_ -match '(?i)/predecessor/' }))
Assert "pred-docs: 'PredecessorArchive' NOT a false hit" (($pdOut -contains 'C:\temp\req\PredecessorArchive\keep.pdf'))

# ---- GPF request document set: a MANUAL installer pick from inside a request tree must ship the CURATED docs
#      (module request, install instructions, Mails, Docs_EQS) and NOTHING else (no Complexity, ~$ lock, Shortcut
#      Behavior, Icons, Sources, Vendor_Sources payload, Thumbs.db, or predecessor docs). Team-reported: manual pick
#      gave an EMPTY Documents folder because sibling-harvest never reached the request root. ----
$rqRoot = Join-Path $env:TEMP ('pbgpfreq_' + [guid]::NewGuid().ToString('N'))
$rqName = 'AES-1-020608-A Tenable_NessusAgentAS_x64_11.2.0.20301-0001_ZXX'
$rq = Join-Path $rqRoot $rqName
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $rq 'Docs_EQS'),(Join-Path $rq 'Mails'),(Join-Path $rq 'Shortcut Behavior'),(Join-Path $rq 'Icons'),(Join-Path $rq 'Sources\Files'),(Join-Path $rq 'Sources\SupportFiles'),(Join-Path $rq 'Vendor_Sources\12560 Nessus (11.2)'),(Join-Path $rq 'Predecessor\Tenable_Old_x64_10.4.2-0001_ZXX\Documents') | Out-Null
    Set-Content (Join-Path $rq 'ModulePack Request_v1.51.xlsx') 'x'                       # KEEP (+ later rename)
    Set-Content (Join-Path $rq '~$ModulePack Request_v1.51.xlsx') 'x'                     # DROP (Office lock file)
    Set-Content (Join-Path $rq 'Complexity_Matrix_Template_2.0.xlsx') 'x'                 # DROP (internal sheet)
    Set-Content (Join-Path $rq 'Thumbs.db') 'x'                                           # DROP (not a doc ext)
    Set-Content (Join-Path $rq 'Docs_EQS\EQS_Checklist_VW_.xlsx') 'x'                     # KEEP (folder)
    Set-Content (Join-Path $rq 'Mails\re query.msg') 'x'                                  # KEEP (folder)
    Set-Content (Join-Path $rq 'Sources\Files\NessusAgent-11.2.0-x64.msi') 'x'           # installer (payload, not a doc)
    Set-Content (Join-Path $rq 'Vendor_Sources\12560 Nessus (11.2)\Installation instructions for Tenable 11.2 AS_RISL.docx') 'x'  # KEEP (install instr)
    Set-Content (Join-Path $rq 'Predecessor\Tenable_Old_x64_10.4.2-0001_ZXX\Documents\Installation instructions.docx') 'x'        # DROP (predecessor)

    # (a) request-root auto-detect from a hand-picked installer deep in Sources\Files
    $foundRoot = Find-GpfRequestRoot -StartPath (Join-Path $rq 'Sources\Files')
    Assert "gpf req: root auto-detected from manual installer pick" ($foundRoot -and ((Split-Path $foundRoot -Leaf) -eq $rqName))
    Assert "gpf req: a bare 'Sources' folder is NOT the root"       ((Find-GpfRequestRoot -StartPath (Join-Path $rq 'Sources') -MaxHops 1) -eq '')

    # (b) curated document set
    $gr = Resolve-GpfRequest -RequestPath $rq
    $di = @($gr.DocItems)
    Assert "gpf req: ModulePack Request collected"        (($di | Where-Object { $_ -match '(?i)\\ModulePack Request_v1\.51\.xlsx$' }).Count -eq 1)
    Assert "gpf req: install instructions collected"       (($di | Where-Object { $_ -match '(?i)Installation instructions for Tenable' }).Count -eq 1)
    Assert "gpf req: Docs_EQS folder collected"            (($di | Where-Object { $_ -match '(?i)\\Docs_EQS$' }).Count -eq 1)
    Assert "gpf req: Mails folder collected"               (($di | Where-Object { $_ -match '(?i)\\Mails$' }).Count -eq 1)
    Assert "gpf req: Complexity Matrix NOT collected"      (($di | Where-Object { $_ -match '(?i)complexity' }).Count -eq 0)
    Assert "gpf req: Office ~$ lock file NOT collected"     (($di | Where-Object { $_ -match '(?i)\\~\$' }).Count -eq 0)
    Assert "gpf req: 'Shortcut Behavior' NOT collected"    (($di | Where-Object { $_ -match '(?i)\\Shortcut Behavior$' }).Count -eq 0)
    Assert "gpf req: Thumbs.db NOT collected"              (($di | Where-Object { $_ -match '(?i)Thumbs\.db' }).Count -eq 0)
    Assert "gpf req: predecessor install instructions NOT collected" (($di | Where-Object { $_ -match '(?i)[\\/]predecessor[\\/]' }).Count -eq 0)

    # (c) MRF rename target carries the CURRENT package name
    $mrfTgt = Get-MrfTargetName -FileBaseName 'ModulePack Request_v1.51' -Vendor 'Tenable' -FullName 'Tenable_NessusAgentAS_x64_11.2.0.20301-0001_ZXX' -Ext '.xlsx'
    Assert "gpf req: MRF rename target = form_<FullName>.xlsx" ($mrfTgt -eq 'ModulePack Request_v1.51_Tenable_NessusAgentAS_x64_11.2.0.20301-0001_ZXX.xlsx')
} finally { Remove-Item $rqRoot -Recurse -Force -ErrorAction SilentlyContinue }

# ---- Set-Reboot LAST in each section: a carried soft-reboot handler that sits BEFORE "## Branding Install / Set-Branding"
#      is reordered so reboot always trails branding (team rule: "Set-Reboot will be last in each section"). ----
$rbText = @"
#*=============== POST-INSTALLATION BEGIN ===============

    ## <Perform Post-Installation tasks here>
    Write-ADTLogEntry -Message 'Install complete.' -Source `$adtSession.DeployAppScriptFriendlyName

    #Enabling Soft reboot if exit code is 3010
    if (`$exit_code.ExitCode -eq '3010')
    {
        #Enabling Soft reboot as exit code was 3010
        Set-Reboot
    }

    ## Branding Install
    Set-Branding
#*=============== POST-INSTALLATION END ===============

#*=============== POST-UNINSTALLATION BEGIN ===============

    ##Removing Folder if present
    Remove-ADTFolder -Path "`$envprogramfiles\Acme"

    Set-Reboot

    ## Branding Uninstall
    Remove-Branding
#*=============== POST-UNINSTALLATION END ===============
"@
$rbOut = Move-GpfRebootLast -Text $rbText
# POST-INSTALL: Set-Branding now comes BEFORE the reboot handler; Set-Reboot is the last statement
Assert "reboot-last: Set-Branding now precedes Set-Reboot" ($rbOut.IndexOf('Set-Branding') -lt $rbOut.IndexOf('Set-Reboot'))
Assert "reboot-last: the 3010 if-block moved below branding"  ($rbOut.IndexOf('## Branding Install') -lt $rbOut.IndexOf("ExitCode -eq '3010'"))
Assert "reboot-last: soft-reboot if-block kept intact"        ($rbOut -match "(?s)if \(\`$exit_code\.ExitCode -eq '3010'\)\s*\r?\n\s*\{\s*\r?\n\s*#Enabling Soft reboot as exit code was 3010\s*\r?\n\s*Set-Reboot\s*\r?\n\s*\}")
Assert "reboot-last: Set-Branding still present exactly once"  ((([regex]::Matches($rbOut,'(?m)^\s*Set-Branding\s*$')).Count) -eq 1)
# POST-UNINSTALL (form c - the real team case): a bare "Set-Reboot" carried from the predecessor sat BEFORE
# "## Branding Uninstall / Remove-Branding" -> it must be moved so Remove-Branding comes first and Set-Reboot is last.
$rbPostUn = [regex]::Match($rbOut, '(?s)POST-UNINSTALLATION BEGIN.*?POST-UNINSTALLATION END').Value
Assert "reboot-last: bare Set-Reboot moved BELOW Remove-Branding (form c)" ($rbPostUn.IndexOf('Remove-Branding') -lt $rbPostUn.IndexOf('Set-Reboot'))
Assert "reboot-last: form-c section still has the Remove-ADTFolder step before both" (($rbPostUn.IndexOf('Remove-ADTFolder') -lt $rbPostUn.IndexOf('Remove-Branding')) -and ($rbPostUn.IndexOf('Remove-ADTFolder') -ge 0))
# idempotent: running twice yields the same text (reboot already trails branding in every section)
Assert "reboot-last: idempotent (second pass = no change)" ((Move-GpfRebootLast -Text $rbOut) -eq $rbOut)
# A nested Set-Reboot (inside an if(){}) and the template's "Set-Reboot -ForceExitScript" are NEVER moved.
$rbSafe = @"
#*=============== POST-INSTALLATION BEGIN ===============
    if (`$VWG_CheckForReboot){
        Set-Reboot -ForceExitScript -OnlyOnPendingReboot -MandatoryDeviceRestart
    }

    ## Branding Install
    Set-Branding
#*=============== POST-INSTALLATION END ===============
"@
Assert "reboot-last: nested/ForceExitScript Set-Reboot left untouched" ((Move-GpfRebootLast -Text $rbSafe) -eq $rbSafe)

# ---- Predecessor from the SOURCE location (priority) - all 4 shapes: the Predecessor FOLDER is normal OR zipped, and the
#      PACKAGE inside is normal OR zipped. Each must resolve so the predecessor is offered as a candidate. ----
$pzRoot = Join-Path $env:TEMP ('pbpredzip_' + [guid]::NewGuid().ToString('N'))
function New-FixturePkg { param($Dir,$Name) $p = Join-Path $Dir $Name; New-Item -ItemType Directory -Force (Join-Path $p 'Content') | Out-Null; Set-Content (Join-Path $p 'Content\Invoke-AppDeployToolkit.ps1') '# fixture deploy'; return (Get-Item -LiteralPath $p) }
try {
    $pzParsed = Parse-PackageName 'PaloAltoNetwork_GlobalProtect_x64_6.3.3-0001_MUL'
    $g = [guid]::NewGuid().ToString('N')
    # S1: normal Predecessor folder + normal package subfolder
    $s1 = Join-Path $pzRoot 's1\Predecessor'; New-Item -ItemType Directory -Force $s1 | Out-Null
    New-FixturePkg $s1 'PaloAltoNetwork_GlobalProtect_x64_6.2.8-0002_MUL' | Out-Null
    $c1 = Get-GpfPredecessorContainer -RequestPath (Split-Path $s1 -Parent)
    Assert "pred-src S1: container = normal Predecessor folder"  ($c1 -eq $s1)
    $cand1 = @(Get-GpfPredecessorCandidates -Parsed $pzParsed -Request @{ PredecessorRoot=$c1; PredecessorPath='' })
    Assert "pred-src S1: normal folder + normal pkg offered"     ((@($cand1 | Where-Object { $_.Version -eq '6.2.8' })).Count -eq 1)
    # S2: normal Predecessor folder + ZIPPED package inside
    $s2 = Join-Path $pzRoot 's2\Predecessor'; New-Item -ItemType Directory -Force $s2 | Out-Null
    $t2 = New-FixturePkg (Join-Path $pzRoot 's2tmp') 'PaloAltoNetwork_GlobalProtect_x64_6.2.5-0001_MUL'
    Compress-Archive -Path $t2.FullName -DestinationPath (Join-Path $s2 "pkg_$g.zip")
    $cand2 = @(Get-GpfPredecessorCandidates -Parsed $pzParsed -Request @{ PredecessorRoot=$s2; PredecessorPath='' })
    Assert "pred-src S2: normal folder + ZIPPED pkg offered"     ((@($cand2 | Where-Object { $_.Version -eq '6.2.5' })).Count -eq 1)
    # S3: ZIPPED Predecessor folder + normal package inside
    $s3 = Join-Path $pzRoot 's3'; New-Item -ItemType Directory -Force $s3 | Out-Null
    $p3 = Join-Path $pzRoot 's3tmp\Predecessor'; New-Item -ItemType Directory -Force $p3 | Out-Null
    New-FixturePkg $p3 'PaloAltoNetwork_GlobalProtect_x64_6.2.4-0001_MUL' | Out-Null
    Compress-Archive -Path $p3 -DestinationPath (Join-Path $s3 "Predecessor_s3_$g.zip")
    $c3 = Get-GpfPredecessorContainer -RequestPath $s3
    Assert "pred-src S3: zipped Predecessor folder extracted"    ($c3 -and (Test-Path -LiteralPath $c3) -and ((Split-Path $c3 -Leaf) -match '(?i)^predecessor$'))
    $cand3 = @(Get-GpfPredecessorCandidates -Parsed $pzParsed -Request @{ PredecessorRoot=$c3; PredecessorPath='' })
    Assert "pred-src S3: ZIPPED folder + normal pkg offered"     ((@($cand3 | Where-Object { $_.Version -eq '6.2.4' })).Count -eq 1)
    # S4: ZIPPED Predecessor folder + ZIPPED package inside (nested)
    $s4 = Join-Path $pzRoot 's4'; New-Item -ItemType Directory -Force $s4 | Out-Null
    $p4 = Join-Path $pzRoot 's4tmp\Predecessor'; New-Item -ItemType Directory -Force $p4 | Out-Null
    $t4 = New-FixturePkg (Join-Path $pzRoot 's4pkgtmp') 'PaloAltoNetwork_GlobalProtect_x64_6.2.3-0001_MUL'
    Compress-Archive -Path $t4.FullName -DestinationPath (Join-Path $p4 "innerpkg_$g.zip")
    Compress-Archive -Path $p4 -DestinationPath (Join-Path $s4 "Predecessor_s4_$g.zip")
    $c4 = Get-GpfPredecessorContainer -RequestPath $s4
    $cand4 = @(Get-GpfPredecessorCandidates -Parsed $pzParsed -Request @{ PredecessorRoot=$c4; PredecessorPath='' })
    Assert "pred-src S4: ZIPPED folder + ZIPPED pkg offered"     ((@($cand4 | Where-Object { $_.Version -eq '6.2.3' })).Count -eq 1)
    # FUZZY match: a curated predecessor whose Vendor spelling differs slightly ("PaloAltoNetworks" vs new "PaloAltoNetwork")
    # must STILL be offered (was rejected by the old exact compare); an UNRELATED app in the same folder must NOT be offered.
    $sf = Join-Path $pzRoot 'fuzzy\Predecessor'; New-Item -ItemType Directory -Force $sf | Out-Null
    New-FixturePkg $sf 'PaloAltoNetworks_GlobalProtect_x64_6.2.7-0001_MUL' | Out-Null   # vendor: extra 's'
    New-FixturePkg $sf 'Adobe_AcrobatReader_x64_23.0-0001_MUL' | Out-Null                # unrelated
    $candF = @(Get-GpfPredecessorCandidates -Parsed $pzParsed -Request @{ PredecessorRoot=$sf; PredecessorPath='' })
    Assert "pred-fuzzy: near-name vendor variant IS offered"     ((@($candF | Where-Object { $_.Version -eq '6.2.7' })).Count -eq 1)
    Assert "pred-fuzzy: unrelated app NOT offered"               ((@($candF | Where-Object { $_.Name -match 'Acrobat' })).Count -eq 0)
} finally { Remove-Item $pzRoot -Recurse -Force -ErrorAction SilentlyContinue }

# ---- Intune detection rules: "None (branding only)" = ONE rule, which MUST serialize as a JSON ARRAY not an object.
#      A single-element List unwrapped to a bare hashtable -> `detectionRules` became `{}` -> Graph 400
#      "Property detectionRules in payload has a value that does not match schema". ----
# Build detectionRules EXACTLY like the create body does (@()-wrapped) and assert a FLAT array of rule OBJECTS - never a
# bare object `{}` (single-rule List unwrap) and never a nested `[[{}]]` (a `,$x.ToArray()` return + the caller's @()).
$dr1 = @(Get-IntuneDetectionRules -Fields @{ BrandingKey='SOFTWARE\VWG\CM\ZSCALER_x64_4.9.0.412-0001_en-US'; Revision='0001'; DetectType='None' })
$json1 = @{ detectionRules = $dr1 } | ConvertTo-Json -Depth 12
Assert "intune: branding-only = exactly 1 rule object"           (($dr1.Count -eq 1) -and ($dr1[0] -is [hashtable]) -and ("$($dr1[0]['@odata.type'])" -match 'RegistryDetection'))
Assert "intune: branding-only serialises FLAT (array of objects)" (($json1 -match '"detectionRules":\s*\[\s*\{') -and ($json1 -notmatch '"detectionRules":\s*\[\s*\['))
$dr2 = @(Get-IntuneDetectionRules -Fields @{ BrandingKey='SOFTWARE\VWG\CM\X'; Revision='0001'; DetectType='Version'; UninstallKey='SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Z'; DetectVersion='4.9.0.412'; Is32Bit=$false })
$json2 = @{ detectionRules = $dr2 } | ConvertTo-Json -Depth 12
Assert "intune: 2 rules serialise FLAT (not nested [[..]])"       (($dr2.Count -eq 2) -and ($dr2[0] -is [hashtable]) -and ($json2 -match '"detectionRules":\s*\[\s*\{') -and ($json2 -notmatch '"detectionRules":\s*\[\s*\['))

# ---- Snapshot "Run installer": an .msi has NO 'runas' shell verb, so `Start-Process foo.msi -Verb RunAs` throws and the
#      "install for snapshot" failed for EVERY MSI (team-reported: Tenable/Zscaler/GlobalProtect). Get-InstallerRunSpec
#      routes MSI/MSP through msiexec.exe (which elevates fine); an .exe launches directly. ----
$rsMsi = Get-InstallerRunSpec -Path 'C:\src\NessusAgent-11.2.0-x64.msi'
Assert "run-installer: MSI -> msiexec /i \"...msi\""   (($rsMsi.File -match '(?i)\\msiexec\.exe$') -and ($rsMsi.Args -match '(?i)^/i\s+".*NessusAgent-11\.2\.0-x64\.msi"$'))
$rsMsp = Get-InstallerRunSpec -Path 'C:\src\hotfix.msp'
Assert "run-installer: MSP -> msiexec /p"              (($rsMsp.File -match '(?i)\\msiexec\.exe$') -and ($rsMsp.Args -match '(?i)^/p\s'))
$rsExe = Get-InstallerRunSpec -Path 'C:\src\Setup.exe'
Assert "run-installer: EXE launches directly (no args)" (($rsExe.File -eq 'C:\src\Setup.exe') -and (-not "$($rsExe.Args)".Trim()))
# ---- Beginner snapshot guidance: MSI optional (product code + MST, PSADT for the rest), EXE recommended, predecessor not needed ----
Assert "snap-guide: MSI = OPTIONAL (product code + MST)" ((Get-SnapshotGuidance -InstallerPath 'C:\x\App.msi' -HasPredecessor $false) -match '(?i)MSI.*OPTIONAL')
Assert "snap-guide: MSI mentions PSADT fallback"          ((Get-SnapshotGuidance -InstallerPath 'C:\x\App.msi' -HasPredecessor $false) -match '(?i)PSADT')
Assert "snap-guide: EXE = RECOMMENDED"                    ((Get-SnapshotGuidance -InstallerPath 'C:\x\Setup.exe' -HasPredecessor $false) -match '(?i)EXE.*RECOMMENDED')
Assert "snap-guide: predecessor = NOT needed"             ((Get-SnapshotGuidance -InstallerPath 'C:\x\App.msi' -HasPredecessor $true) -match '(?i)Predecessor.*NOT needed')
# ---- Icon folder resolves from ANY path level: Icons sits at the package ROOT (sibling of Content), so pointing at
#      the Content folder must still find it - else a content update LOSES the app icon (team-reported for MTB Intune). ----
$icRoot = Join-Path $env:TEMP ('icres_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force (Join-Path $icRoot 'Content'),(Join-Path $icRoot 'Icons') | Out-Null
try {
    Assert "icons-dir: found from package ROOT"   ((Resolve-IconsDir -PackagePath $icRoot) -ieq (Join-Path $icRoot 'Icons'))
    Assert "icons-dir: found from CONTENT folder" ((Resolve-IconsDir -PackagePath (Join-Path $icRoot 'Content')) -ieq (Join-Path $icRoot 'Icons'))
    Assert "icons-dir: '' when there is none"     ((Resolve-IconsDir -PackagePath (Join-Path $env:TEMP ('noic_'+[guid]::NewGuid().ToString('N')))) -eq '')
Assert "snap-noise: Windows INF filtered"        (Test-IsFileNoise 'C:\Windows\INF\oem12.inf')
Assert "snap-noise: .pnf filtered"               (Test-IsFileNoise 'C:\Windows\INF\oem12.pnf')
Assert "snap-noise: real app file NOT filtered"  (-not (Test-IsFileNoise 'D:\Apps\MyApp\app.exe'))
$snRd = [pscustomobject]@{ New=@([pscustomobject]@{ Path='HKLM\SOFTWARE\MyApp'; Change='new'; IsApp=$true; Values=@([pscustomobject]@{ Name='Server'; Change='added'; New='https://x'; Value='https://x'; Type='String' }) }); Deleted=@(); NoiseItems=@(); NoiseCount=0; ModifiedCount=0; DeletedCount=0; InstalledBytes=0; Total=1 }
$snFd = [pscustomobject]@{ New=@(); Deleted=@(); NoiseItems=@(); NoiseCount=0; ModifiedCount=0; DeletedCount=0; InstalledBytes=0; Total=0 }
$snRep = Get-SnapshotReportText -Diff @{} -FileDiff $snFd -RegDiff $snRd -EnvChanges @() -Un $null -AppTokens @('myapp')
Assert "snap-report: registry shows the KEY"          ($snRep -match 'HKLM\\SOFTWARE\\MyApp')
Assert "snap-report: registry shows value NAME=DATA"  (($snRep -match '(?m)Server = https://x') -and ($snRep -match '\[String\]'))
} finally { Remove-Item $icRoot -Recurse -Force -ErrorAction SilentlyContinue }

# ---- nested Files\Files hoist (GPF request drops: payload must land DIRECTLY in Content\Files) ----
$nfRoot = Join-Path $env:TEMP ("pb_nestedfiles_" + [guid]::NewGuid().ToString('N'))
try {
    $nf = Join-Path $nfRoot 'Files'
    New-Item (Join-Path $nf 'Files\sub') -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $nf 'Files\setup.msi') 'x'
    Set-Content (Join-Path $nf 'Files\sub\data.bin') 'x'
    Set-Content (Join-Path $nf 'keep.txt') 'x'
    Invoke-NestedFilesHoist -FilesDir $nf
    Assert "hoist: installer now directly in Files"   (Test-Path (Join-Path $nf 'setup.msi'))
    Assert "hoist: subfolder carried up"              (Test-Path (Join-Path $nf 'sub\data.bin'))
    Assert "hoist: inner Files folder removed"        (-not (Test-Path (Join-Path $nf 'Files')))
    Assert "hoist: sibling file untouched"            (Test-Path (Join-Path $nf 'keep.txt'))
    Invoke-NestedFilesHoist -FilesDir $nf
    Assert "hoist: idempotent no-op on clean Files"   ((Test-Path (Join-Path $nf 'setup.msi')) -and -not (Test-Path (Join-Path $nf 'Files')))
} finally { Remove-Item $nfRoot -Recurse -Force -ErrorAction SilentlyContinue }

# ---- Per-user configuration auto-codegen (All-users registry vs Active Setup) ----
$puA = Get-PerUserConfig -Mode 'AllUsersReg' -Vendor 'Acme' -App 'Tool' -Version '1.0.0'
Assert "per-user AllUsersReg -> Invoke-ADTAllUsersRegistryAction"      ($puA.PostInstall -match 'Invoke-ADTAllUsersRegistryAction')
Assert "per-user AllUsersReg -> Set-ADTRegistryKey -SID + HKCU/app"    (($puA.PostInstall -match 'Set-ADTRegistryKey -SID \$_\.SID') -and ($puA.PostInstall -match 'HKCU\\Software\\Acme\\Tool'))
Assert "per-user AllUsersReg -> no uninstall code, no stub"           ((-not "$($puA.PostUninstall)".Trim()) -and (-not "$($puA.StubName)".Trim()))
$puStubName = Get-ActiveSetupStubName -AppName 'Tool' -Version '1.0.0'
Assert "per-user ActiveSetup stub name format"                        ($puStubName -eq 'Tool_1.0.0_ActiveSetup_Install.ps1')
$puS = Get-PerUserConfig -Mode 'ActiveSetup' -Vendor 'Acme' -App 'Tool' -Version '1.0.0'
Assert "per-user ActiveSetup -> stages stub + registers w/ AppFullName" (($puS.PostInstall -match 'Copy-ADTFile') -and ($puS.PostInstall -match 'Set-ADTActiveSetup -StubExePath') -and ($puS.PostInstall -match [regex]::Escape($puStubName)) -and ($puS.PostInstall -match '-Key \$AppFullName'))
Assert "per-user ActiveSetup -> purge + remove folder on uninstall"   (($puS.PostUninstall -match 'PurgeActiveSetupKey') -and ($puS.PostUninstall -match 'Remove-ADTFolder'))
Assert "per-user ActiveSetup stub is plain PS (Hide-Console+reg+VWG log)" (($puS.StubText -match 'Hide-Console') -and ($puS.StubText -match '(?i)reg\.exe') -and ($puS.StubText -match 'VWG\\Logs') -and ($puS.StubName -eq $puStubName))
Assert "per-user ActiveSetup stub parses as valid PowerShell"         (& { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseInput($puS.StubText,[ref]$null,[ref]$e); -not ($e -and $e.Count) })
# SNAPSHOT-DRIVEN: detected HKCU values auto-fill the per-user code (real values, not placeholders).
$hk = @(
    [pscustomobject]@{ Key='HKCU:\Software\Acme\Tool'; Name='FirstRun'; Value=0;       Type='DWord' },
    [pscustomobject]@{ Key='HKCU:\Software\Acme\Tool'; Name='Server';   Value='srv01'; Type='String' })
$aurH = Get-PerUserConfig -Mode 'AllUsersReg' -Vendor 'Acme' -App 'Tool' -Version '1.0' -HkcuItems $hk
Assert "per-user auto-fill (reg): detected DWord + String lines, no placeholder" (($aurH.PostInstall -match "-Name 'FirstRun' -Value 0 -Type DWord") -and ($aurH.PostInstall -match "-Name 'Server' -Value 'srv01' -Type String") -and (-not ($aurH.PostInstall -match '<ValueName>')))
$actH = Get-PerUserConfig -Mode 'ActiveSetup' -Vendor 'Acme' -App 'Tool' -Version '1.0' -HkcuItems $hk
Assert "per-user auto-fill (stub): New-Item + New-ItemProperty for detected values" (($actH.StubText -match "New-Item -Path 'HKCU:\\Software\\Acme\\Tool' -Force") -and ($actH.StubText -match "New-ItemProperty -Path 'HKCU:\\Software\\Acme\\Tool' -Name 'FirstRun' -Value 0 -PropertyType DWord"))
Assert "per-user auto-fill (stub): still valid PowerShell"            (& { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseInput($actH.StubText,[ref]$null,[ref]$e); -not ($e -and $e.Count) })
# Get-SnapshotHkcuValues reads the live HKCU values for the app's detected keys.
$tk = 'HKCU:\Software\PBTest_' + [guid]::NewGuid().ToString('N').Substring(0,8)
try {
    New-Item -Path $tk -Force | Out-Null
    New-ItemProperty -Path $tk -Name 'Foo' -Value 'bar' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $tk -Name 'Num' -Value 7     -PropertyType DWord  -Force | Out-Null
    $rd = @{ New = @([pscustomobject]@{ Path = ($tk -replace '^HKCU:\\','HKCU\'); IsApp=$true }) }
    $vals = @(Get-SnapshotHkcuValues -RegDiff $rd -AppTokens @('pbtest'))
    Assert "snapshot HKCU: reads live String + DWord values" ((@($vals | Where-Object { $_.Name -eq 'Foo' -and "$($_.Value)" -eq 'bar' -and $_.Type -eq 'String' }).Count -eq 1) -and (@($vals | Where-Object { $_.Name -eq 'Num' -and $_.Type -eq 'DWord' }).Count -eq 1))
    Assert "snapshot HKCU: still reads when IsApp=false (diff already noise-filtered)" ((@(Get-SnapshotHkcuValues -RegDiff @{ New=@([pscustomobject]@{ Path=($tk -replace '^HKCU:\\','HKCU\'); IsApp=$false }) } -AppTokens @())).Count -ge 1)
    Assert "snapshot HKCU: ignores non-HKCU (HKLM) paths" ((@(Get-SnapshotHkcuValues -RegDiff @{ New=@([pscustomobject]@{ Path='HKLM\SOFTWARE\Acme\Tool'; IsApp=$true }) } -AppTokens @())).Count -eq 0)
} finally { Remove-Item -Path $tk -Recurse -Force -ErrorAction SilentlyContinue }
# SNAPSHOT-DRIVEN per-user FILE auto-copy: Get-PerUserFileCopy builds the Get-ADTUserProfiles loop + staging list.
$uf = @(
    [pscustomobject]@{ Source='C:\Users\me\AppData\Roaming\Acme\Tool\settings.ini'; Scope='Roaming'; Rel='Acme\Tool\settings.ini' },
    [pscustomobject]@{ Source='C:\Users\me\AppData\Local\Acme\cache.dat';           Scope='Local';   Rel='Acme\cache.dat' })
$pfc = Get-PerUserFileCopy -Files $uf
Assert "per-user files: Get-ADTUserProfiles loop"               (($pfc.PostInstall -match 'Get-ADTUserProfiles') -and ($pfc.PostInstall -match 'foreach \(\$ProfilePath in \$ProfilePaths\)'))
Assert "per-user files: Roaming file -> AppData\Roaming subdir" ($pfc.PostInstall -match [regex]::Escape('Copy-ADTFile -Path "$($adtSession.DirSupportFiles)\UserProfile\Roaming\Acme\Tool\settings.ini" -Destination "$ProfilePath\AppData\Roaming\Acme\Tool"'))
Assert "per-user files: Local file -> AppData\Local subdir"     ($pfc.PostInstall -match [regex]::Escape('Copy-ADTFile -Path "$($adtSession.DirSupportFiles)\UserProfile\Local\Acme\cache.dat" -Destination "$ProfilePath\AppData\Local\Acme"'))
Assert "per-user files: uninstall removes per profile"          ($pfc.PostUninstall -match [regex]::Escape('Remove-ADTFile -Path "$ProfilePath\AppData\Roaming\Acme\Tool\settings.ini"'))
Assert "per-user files: staged maps Source -> SupportFiles rel" ((@($pfc.Staged | Where-Object { $_.Rel -eq 'UserProfile\Roaming\Acme\Tool\settings.ini' -and $_.Source -match 'settings\.ini' }).Count) -eq 1)
Assert "per-user files: empty input -> nothing staged"          ((@(Get-PerUserFileCopy -Files @()).Staged).Count -eq 0)
# Get-SnapshotUserFiles classifies a real AppData file by scope + relative path.
$utmp = Join-Path $env:APPDATA ('PBT_' + [guid]::NewGuid().ToString('N').Substring(0,8))
try {
    New-Item (Join-Path $utmp 'sub') -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $utmp 'sub\f.ini') 'x'
    $fd = @{ New = @([pscustomobject]@{ Path=(Join-Path $utmp 'sub\f.ini'); Change='new'; IsApp=$true }) }
    $leaf = Split-Path $utmp -Leaf
    Assert "snapshot user files: classifies Roaming + relative path" ((@(Get-SnapshotUserFiles -FileDiff $fd -AppTokens @('pbt') | Where-Object { $_.Scope -eq 'Roaming' -and $_.Rel -eq "$leaf\sub\f.ini" }).Count) -eq 1)
} finally { Remove-Item $utmp -Recurse -Force -ErrorAction SilentlyContinue }
# ---- Snapshot reliability: ignored/noise items are RETAINED (for CMTrace full report + user promotion) ----
$bMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
$aMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
$aMap['C:\Program Files\Acme\app.exe']             = '100|123'   # app file        -> New
$aMap['C:\Windows\Temp\churn.tmp']                 = '10|1'      # temp/churn       -> noise (retained)
$aMap['C:\Program Files\Microsoft\Edge\msedge.dll'] = '5|2'      # 3rd-party vendor -> noise (retained)
$rdN = Get-SnapshotRawDiff -Before @{ _FileMap=$bMap } -After @{ _FileMap=$aMap } -Kind Files -AppTokens @('acme')
Assert "raw diff: app file kept in New"            ((@($rdN.New | Where-Object { $_.Path -match 'app\.exe' }).Count) -eq 1)
Assert "raw diff: noise NOT in New"                ((@($rdN.New | Where-Object { $_.Path -match 'churn\.tmp|msedge' }).Count) -eq 0)
Assert "raw diff: noise RETAINED in NoiseItems"    ((@($rdN.NoiseItems | Where-Object { $_.Path -match 'churn\.tmp' }).Count -eq 1) -and (@($rdN.NoiseItems | Where-Object { $_.Path -match 'msedge' }).Count -eq 1))
$emptyReg = @{ New=@(); Deleted=@(); NoiseItems=@(); NoiseCount=0 }
$repFull = Get-SnapshotReportText -Diff @{} -FileDiff $rdN -RegDiff $emptyReg -EnvChanges @() -Un $null -AppTokens @('acme') -IncludeNoise
$repApp  = Get-SnapshotReportText -Diff @{} -FileDiff $rdN -RegDiff $emptyReg -EnvChanges @() -Un $null -AppTokens @('acme')
Assert "full report: IGNORED section + lists an ignored item" (($repFull -match 'IGNORED \(filtered') -and ($repFull -match 'churn\.tmp|msedge'))
Assert "default report: no IGNORED section"        ($repApp -notmatch 'IGNORED \(filtered')
# -NoiseOnly = the "View ignored OS junk" button: ONLY the ignored items, no APPLICATION/app sections.
$repNoiseOnly = Get-SnapshotReportText -Diff @{} -FileDiff $rdN -RegDiff $emptyReg -EnvChanges @() -Un $null -AppTokens @('acme') -NoiseOnly
Assert "NoiseOnly: IGNORED section present, app sections absent" (($repNoiseOnly -match 'IGNORED \(filtered') -and ($repNoiseOnly -match 'churn\.tmp|msedge') -and ($repNoiseOnly -notmatch '=== APPLICATION ===') -and ($repNoiseOnly -notmatch 'CHANGES BY CATEGORY'))
# Copy-InstallerLocal: a LOCAL source (staged in step 1) is run IN PLACE - no second copy (returns the same path).
$ciTmp = Join-Path ([IO.Path]::GetTempPath()) ('ci_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.exe')
try { Set-Content -LiteralPath $ciTmp 'x'; Assert "Copy-InstallerLocal: local path runs in place (no copy)" ((Copy-InstallerLocal -ExePath $ciTmp) -eq $ciTmp) } finally { Remove-Item $ciTmp -Force -ErrorAction SilentlyContinue }
# ---- App-name match tokens: WORDS of the name (so files deep under the app folder never fall to vendor noise) ----
$amt = @(Get-AppMatchTokens -Vendor 'SMT' -AppName 'MASTA 15.1.8 RLM')
Assert "app tokens: vendor + each word, version dropped" (($amt -contains 'smt') -and ($amt -contains 'masta') -and ($amt -contains 'rlm') -and (-not ($amt -contains '15')) -and (-not ($amt -contains '1')))
$pNested = 'c:\program files\smt\masta 15.1.8 rlm\python\lib\site-packages\jedi\third_party\typeshed\third_party\2and3\google\protobuf\x.pyi'
Assert "app file under app folder is APP even with \google\ inside" (Test-IsAppItem -Text $pNested -AppTokens $amt)
Assert "...so it is NOT mis-filed as 3rd-party vendor noise"        (-not (Test-IsVendorNoise -Text $pNested -AppTokens $amt))
# ---- Shortcut launch filter: keep real TOOLS (Licence Manager), drop docs/uninstall/help ----
Assert "shortcut filter: KEEPS 'MASTA Licence Manager 15.1.8'" (-not ('MASTA Licence Manager 15.1.8' -match $script:ShortcutExcludeRe))
Assert "shortcut filter: KEEPS 'RUNNA 15.1.8' / 'VPS 15.1.8'"   ((-not ('RUNNA 15.1.8' -match $script:ShortcutExcludeRe)) -and (-not ('VPS 15.1.8' -match $script:ShortcutExcludeRe)))
Assert "shortcut filter: DROPS 'MASTA Help 15.1.8'"            ('MASTA Help 15.1.8' -match $script:ShortcutExcludeRe)
Assert "shortcut filter: DROPS 'MASTA Release Notes 15.1.8'"   ('MASTA Release Notes 15.1.8' -match $script:ShortcutExcludeRe)
Assert "shortcut filter: DROPS 'License Agreement'"            ('License Agreement' -match $script:ShortcutExcludeRe)
# Get-SnapshotAppTokens learns the app's identity from the SNAPSHOT (created folders + ARP name), so files under the
# app's own install folder are APP even when the package name doesn't match the install folder.
$diffTok = @{ ProgramDirs = @{ Added = @([pscustomobject]@{ Info = @{ Name = 'SMT' } }) }; Programs = @{ Added = @([pscustomobject]@{ Info = @{ DisplayName = 'MASTA 15.1.8' } }) } }
$stk = @(Get-SnapshotAppTokens -Vendor 'Contoso' -AppName 'Widget' -Diff $diffTok)
Assert "snapshot tokens: created folder 'smt' + ARP 'masta' + pkg 'widget'" (($stk -contains 'smt') -and ($stk -contains 'masta') -and ($stk -contains 'widget'))
Assert "file under the install-created folder is APP (pkg-name mismatch ok)" (Test-IsAppItem -Text 'c:\program files\smt\masta 15.1.8 rlm\python\lib\site-packages\google\protobuf\x.pyi' -AppTokens $stk)
# Fresh build: the generated per-user code lands in POST-INSTALLATION / POST-UNINSTALLATION.
$puFresh = Build-FreshScript -NewPkg @{ Vendor='Acme';AppName='Tool';Arch='x64';Lang='MUL';Revision='0001';Version='1.0.0';ExeFileName='s.exe';InstallParams='/S';PerUserMode='ActiveSetup';PostInstallExtra=$puS.PostInstall;PostUninstallExtra=$puS.PostUninstall;Author='Me' } -Template $tplF
Assert "fresh: Active Setup register in POST-INSTALLATION"            ($puFresh -match '(?s)POST-INSTALLATION BEGIN.*Set-ADTActiveSetup -StubExePath.*POST-INSTALLATION END')
Assert "fresh: Active Setup purge in POST-UNINSTALLATION"             ($puFresh -match '(?s)POST-UNINSTALLATION BEGIN.*PurgeActiveSetupKey.*POST-UNINSTALLATION END')
# Predecessor reuse now MERGES net-new snapshot extras (de-duplicated + tagged '# [snapshot-added]'). Per-user CONFIG is
# still kept out of reuse - but at the GUI layer (PerUserMode is forced to 'None' when a predecessor is loaded), so it
# never reaches these extras in the real flow; per-user in reuse is added via snippets.
$npPU = @{}; foreach ($k in $newPkg.Keys) { $npPU[$k] = $newPkg[$k] }; $npPU.PostInstallExtra = "Remove-ADTFile -Path `"`$envCommonStartMenuPrograms\Brand New Tool.lnk`""
$puPred = Build-PredecessorScript -Model $model -NewPkg $npPU -Template $tpl
Assert "predecessor: net-new snapshot extra merged + tagged"         ($puPred -match 'Brand New Tool\.lnk.*#\s*\[snapshot-added\]')

# ---- Predecessor command SEQUENCE (multi-component install/uninstall is fully parsed + shown) ----
$predSeqCode = @'
        Start-ADTMsiProcess -Action 'Install' -FilePath "$($adtSession.DirFiles)\A.msi" -Transform "$($adtSession.DirFiles)\A.mst"
        Start-ADTMsiProcess -Action 'Install' -FilePath "$($adtSession.DirFiles)\B.msi"
        Start-ADTProcess -FilePath "$($adtSession.DirFiles)\C.exe" -ArgumentList "/S /norestart"
'@
$pseq = @(Get-PredecessorCommandSeq -Code $predSeqCode)
Assert "pred-seq: parses all 3 install steps in order" (($pseq.Count -eq 3) -and ($pseq[0].Name -match 'A\.msi') -and ($pseq[1].Name -match 'B\.msi') -and ($pseq[2].Name -match 'C\.exe'))
Assert "pred-seq: MSI step captures its MST"            ($pseq[0].Kind -eq 'MSI' -and $pseq[0].Mst -match 'A\.mst')
Assert "pred-seq: EXE step captures args"               ($pseq[2].Kind -eq 'EXE' -and $pseq[2].Args -match '/S')
$puninCode = @'
        Start-ADTMsiProcess -Action 'Uninstall' -ProductCode '{11111111-1111-1111-1111-111111111111}'
'@
Assert "pred-seq: uninstall by ProductCode parsed"      ((@(Get-PredecessorCommandSeq -Code $puninCode))[0].ProductCode -match '\{11111111')

# ---- Shortcut validation: keep real app shortcuts, drop uninstall/update/help + desktop; compare sets ----
$smDir = Join-Path ([IO.Path]::GetTempPath()) ("sc_" + [guid]::NewGuid().ToString('N').Substring(0,8))
$smP = Join-Path $smDir 'Start Menu\Programs\App'; $dtP = Join-Path $smDir 'Desktop'
New-Item $smP -ItemType Directory -Force | Out-Null; New-Item $dtP -ItemType Directory -Force | Out-Null
$tgt = Join-Path $env:WINDIR 'System32\notepad.exe'
$wsh = New-Object -ComObject WScript.Shell
function New-TestLnk($dir,$nm,$target){ $l=$wsh.CreateShortcut((Join-Path $dir "$nm.lnk")); $l.TargetPath=$target; $l.Save() }
try {
    New-TestLnk $smP 'CoolApp' $tgt; New-TestLnk $smP 'Uninstall CoolApp' $tgt; New-TestLnk $smP 'CoolApp Help' $tgt; New-TestLnk $smP 'CoolApp Tools' $tgt; New-TestLnk $dtP 'CoolApp Desktop' $tgt
    $diffSc = @{ Shortcuts = @{ Added = @(
        ([pscustomobject]@{ Id=(Join-Path $smP 'CoolApp.lnk') }), ([pscustomobject]@{ Id=(Join-Path $smP 'Uninstall CoolApp.lnk') }),
        ([pscustomobject]@{ Id=(Join-Path $smP 'CoolApp Help.lnk') }), ([pscustomobject]@{ Id=(Join-Path $smP 'CoolApp Tools.lnk') }),
        ([pscustomobject]@{ Id=(Join-Path $dtP 'CoolApp Desktop.lnk') }) ) } }
    $kept = @(Get-AppStartMenuShortcuts -Diff $diffSc -AppTokens @('coolapp'))
    $names = @($kept | ForEach-Object { $_.Name })
    Assert "shortcuts: keeps the real app shortcuts"        (($names -contains 'CoolApp') -and ($names -contains 'CoolApp Tools'))
    Assert "shortcuts: drops uninstall/help/desktop"        (($names -notcontains 'Uninstall CoolApp') -and ($names -notcontains 'CoolApp Help') -and ($names -notcontains 'CoolApp Desktop'))
    $cmpR = Compare-ShortcutSets -Reference @($kept | Where-Object { $_.Name -eq 'CoolApp' }) -Current $kept
    Assert "shortcut diff: new shortcut shows as Added"     (@($cmpR.Added | Where-Object { $_.Name -eq 'CoolApp Tools' }).Count -eq 1)
    Assert "shortcut diff: tolerates an empty reference"    ((Compare-ShortcutSets -Reference @() -Current $kept).Added.Count -eq $kept.Count)
} finally { try { [Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null } catch {}; Remove-Item $smDir -Recurse -Force -ErrorAction SilentlyContinue }

# ---- Snapshot wide scan: whole-drive coverage, OS-churn pruned ----
Assert "snapshot roots include the system drive root" (@($script:SnapshotFileRoots) -contains ($env:SystemDrive + '\'))
$pmDir = Join-Path ([IO.Path]::GetTempPath()) ("pm_" + [Guid]::NewGuid().ToString('N'))
try {
    New-Item (Join-Path $pmDir 'App\sub') -ItemType Directory -Force | Out-Null
    New-Item (Join-Path $pmDir 'WinSxS')   -ItemType Directory -Force | Out-Null   # churn folder NAME -> must be pruned
    New-Item (Join-Path $pmDir 'Temp')     -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $pmDir 'App\sub\real.dll') 'x'
    Set-Content (Join-Path $pmDir 'WinSxS\junk.dll')  'x'
    Set-Content (Join-Path $pmDir 'Temp\junk.tmp')    'x'
    $pm = Get-PathMap -Roots @($pmDir)
    Assert "wide scan: keeps a real nested file"   (@($pm.Keys | Where-Object { $_ -like '*\App\sub\real.dll' }).Count -eq 1)
    Assert "wide scan: prunes WinSxS folder"       (@($pm.Keys | Where-Object { $_ -like (Join-Path $pmDir 'WinSxS\*') }).Count -eq 0)
    Assert "wide scan: prunes Temp folder"         (@($pm.Keys | Where-Object { $_ -like (Join-Path $pmDir 'Temp\*') }).Count -eq 0)
    Assert "wide scan: WinSxS path is file-noise"  (Test-IsFileNoise 'C:\Windows\WinSxS\x.dll')
    Assert "wide scan: pagefile.sys is file-noise" (Test-IsFileNoise 'C:\pagefile.sys')
} finally { Remove-Item $pmDir -Recurse -Force -ErrorAction SilentlyContinue }

# ---- Unblock-PBPath strips Mark-of-the-Web (Zone.Identifier ADS) ----
$ubDir = Join-Path ([IO.Path]::GetTempPath()) ("ub_" + [Guid]::NewGuid().ToString('N'))
try {
    New-Item (Join-Path $ubDir 'sub') -ItemType Directory -Force | Out-Null
    $f1 = Join-Path $ubDir 'setup.exe'; $f2 = Join-Path $ubDir 'sub\helper.dll'
    Set-Content $f1 'x'; Set-Content $f2 'x'
    # stamp the MOTW stream the way a network/internet copy does
    foreach ($f in @($f1,$f2)) { Set-Content -LiteralPath $f -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" }
    $had1 = [bool](Get-Item -LiteralPath $f1 -Stream Zone.Identifier -EA SilentlyContinue)
    Unblock-PBPath -Path $ubDir   # recurse the folder
    $gone1 = -not (Get-Item -LiteralPath $f1 -Stream Zone.Identifier -EA SilentlyContinue)
    $gone2 = -not (Get-Item -LiteralPath $f2 -Stream Zone.Identifier -EA SilentlyContinue)
    Assert "MOTW stamp was present before unblock"   $had1
    Assert "unblock strips MOTW from the file"        $gone1
    Assert "unblock recurses into subfolders"         $gone2
    $safe = $true; try { Unblock-PBPath -Path (Join-Path $ubDir 'nope\none.exe') } catch { $safe = $false }
    Assert "unblock is safe on a missing path"        $safe
} finally { Remove-Item $ubDir -Recurse -Force -ErrorAction SilentlyContinue }

# ---- v3->v4: team $VWG_CurrentRegWOW / $VWG_CurrentSysWOW hardcoded to the WOW path ----
$vwgIn  = 'Set-RegistryKey -Key "HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)SAP\X"' + "`r`n" + '$d = "$envWinDir\$($VWG_CurrentSysWOW)\config"' + "`r`n" + '$bare = $VWG_CurrentRegWOW'
$vwgOut = Convert-VWGRegWOW -Content $vwgIn
Assert 'VWG: subexpr RegWOW -> Wow6432Node'  ($vwgOut -match 'HKLM:\\SOFTWARE\\Wow6432Node\\SAP\\X')
Assert 'VWG: subexpr SysWOW -> SysWOW64'      ($vwgOut -match 'envWinDir\\SysWOW64\\config')
Assert 'VWG: bare RegWOW -> Wow6432Node'      ($vwgOut -match '\$bare = Wow6432Node\\')
Assert 'VWG: no VWG_ vars survive'            ($vwgOut -notmatch 'VWG_Current')
$vwgFull = Convert-V3ToV4Content -Content 'Set-RegistryKey -Key "HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)App_is1" -Name DisplayVersion -Value "1.0"'
Assert "VWG via full converter (rename + hardcode)"   (($vwgFull -match 'Set-ADTRegistryKey') -and ($vwgFull -match 'Wow6432Node\\App_is1') -and ($vwgFull -notmatch 'VWG_Current'))
# Team $VWG_app* aliases -> v4: $VWG_appFullName -> $AppFullName (template var); $VWG_appName/Version/... -> $adtSession.*
$vwgApp = Convert-V3ToV4Content -Content 'Set-ActiveSetup -Key $VWG_appFullName; Write-Log $VWG_appName; $p = "dir_$VWG_appVersion"'
Assert "VWG_appFullName -> `$AppFullName (template var)" ($vwgApp -match '(?<![\w])\$AppFullName(?![\w])')
Assert "VWG_appName -> adtSession.AppName (standalone)"  ($vwgApp -match '\$adtSession\.AppName')
Assert "VWG_appVersion -> subexpr in string"            ($vwgApp -match [regex]::Escape('"dir_$($adtSession.AppVersion)"'))
Assert "no VWG_app* survive after convert"              ($vwgApp -notmatch '(?i)VWG_app')
# v3 name-match SWITCHES -> v4 -NameMatch VALUE (Get-ADTApplication has no -Exact). Also proves the switch is caught
# when a ')' follows it (the old (?=\s|$) missed "-Exact)").
$exC = Convert-V3ToV4Content -Content ("If (Get-InstalledApplication -Name 'X' -Exact) { }`r`nRemove-MSIApplications -Name 'Y' -Exact")
Assert "-Exact -> -NameMatch 'Exact' before ')'"        ($exC -match "Get-ADTApplication -Name 'X' -NameMatch 'Exact'\)")
Assert "-Exact -> -NameMatch 'Exact' at EOL (uninstall)" ($exC -match "Uninstall-ADTApplication -Name 'Y' -NameMatch 'Exact'")
Assert "no bare -Exact switch survives"                 ($exC -notmatch '(?<![\w])-Exact(?![\w])')
# v3's app NAME was POSITIONAL (Get-InstalledApplication -WildCard '*X*'); v4 Get-ADTApplication -Name is NOT positional
# (position 0 is -FilterScript), so the bare name must gain an explicit -Name or it binds to -FilterScript and breaks.
$posN = Convert-V3ToV4Content -Content "if(!(Get-InstalledApplication -WildCard '*CodeMeter Runtime Kit*')){}"
Assert "positional name gains explicit -Name"           ($posN -match "-Name '\*CodeMeter Runtime Kit\*'")
Assert "positional name keeps -NameMatch"               ($posN -match "-NameMatch 'WildCard'")
Assert "positional name: exactly ONE -Name"             ((([regex]::Matches($posN,'(?<!\w)-Name(?!Match)\b')).Count) -eq 1)
Assert "positional name output parses"                  ($(($pe=$null);[void][System.Management.Automation.Language.Parser]::ParseInput($posN,[ref]$null,[ref]$pe);$pe.Count -eq 0))
$posNoSwitch = Convert-V3ToV4Content -Content "Get-InstalledApplication '*CodeMeter*'"
Assert "bare positional (no switch) gains -Name"        (($posNoSwitch -match "-Name '\*CodeMeter\*'") -and ((([regex]::Matches($posNoSwitch,'(?<!\w)-Name(?!Match)\b')).Count) -eq 1))
$pcLookup = Convert-V3ToV4Content -Content "Get-ADTApplication -ProductCode '{11111111-1111-1111-1111-111111111111}'"
Assert "ProductCode lookup gets NO -Name"               (([regex]::Matches($pcLookup,'(?<!\w)-Name(?!Match)\b')).Count -eq 0)
# ---- Split-ExistingUninstallBlocks KEEP-checks: excise ONLY a genuine predecessor-uninstall block; keep dependency
#      gates (negated), if/else logic, and DIFFERENT components (VC++). (DSA_PRODISAuthoring CodeMeter bug.)
$sxId = @{ Vendor='DSA'; AppName='PRODISAuthoring'; FullName='DSA_PRODISAuthoring_x64_5.8.9-0001_en-US' }
$sxGate = @'
        if(!(Get-InstalledApplication -WildCard '*CodeMeter Runtime Kit*')) {
            Exit-Script 69101
        } else {
            Write-ADTLogEntry -Message 'Codemeter found'
        }
        If((Get-ADTApplication -Name 'PRODIS.Authoring') -and (Test-Path -Path "HKLM:\SOFTWARE\VWG\CM\DSA_PRODISAuthoring_x64_5.4.15-0001_MUL")) {
            Remove-MTBDetectionKey "DSA_PRODISAuthoring_x64_5.4.15-0001_MUL"
        }
'@
$sxR = Split-ExistingUninstallBlocks -Code $sxGate -Identity $sxId
Assert "GPF split: excises ONLY the real predecessor block" ($sxR.Blocks.Count -eq 1)
Assert "GPF split: CodeMeter dependency gate KEPT"          (($sxR.Body -match "if\(!\(Get-InstalledApplication") -and ($sxR.Body -match "Codemeter found"))
Assert "GPF split: kept body parses (no dangling else)"     ($(($pe2=$null);[void][System.Management.Automation.Language.Parser]::ParseInput($sxR.Body,[ref]$null,[ref]$pe2);$pe2.Count -eq 0))
Assert "GPF split: different component (VC++) KEPT"         ((Split-ExistingUninstallBlocks -Code "If (Get-ADTApplication -Name 'Microsoft Visual C++ 2019 Redistributable') { Remove-MTBDetectionKey `"x`" }" -Identity $sxId).Blocks.Count -eq 0)
Assert "GPF split: our app (fuzzy name) EXCISED"            ((Split-ExistingUninstallBlocks -Code "If (Get-ADTApplication -Name 'PRODIS.Authoring') { Remove-MTBDetectionKey `"y`" }" -Identity $sxId).Blocks.Count -eq 1)
Assert "GPF split: if/else KEPT even when app matches"      ((Split-ExistingUninstallBlocks -Code "If (Get-ADTApplication -Name 'PRODISAuthoring') { Remove-MTBDetectionKey `"z`" } else { Write-ADTLogEntry -Message 'noop' }" -Identity $sxId).Blocks.Count -eq 0)
Assert "GPF split: ProductCode-only block EXCISED"         ((Split-ExistingUninstallBlocks -Code "If (Get-ADTApplication -ProductCode '{11111111-1111-1111-1111-111111111111}') { Start-ADTMsiProcess -Action Uninstall -ProductCode '{11111111-1111-1111-1111-111111111111}' }" -Identity $sxId).Blocks.Count -eq 1)
# Get-RegistryKey: v3 -Value (the value NAME) -> v4 -Name (v4 Get-ADTRegistryKey has NO -Value). Set-RegistryKey's -Value
# is the DATA and MUST stay -Value. The rename is scoped to Get-ADTRegistryKey call lines, so Set is not touched.
$regC = Convert-V3ToV4Content -Content ("Get-RegistryKey -Key 'HKLM:\SOFTWARE\App' -Value 'Version'`r`nSet-RegistryKey -Key 'HKLM:\SOFTWARE\App' -Name 'Flag' -Value '1'")
Assert "Get-RegistryKey -Value -> -Name (value name)"   ($regC -match "Get-ADTRegistryKey -Key 'HKLM:\\SOFTWARE\\App' -Name 'Version'")
Assert "Get-ADTRegistryKey has NO leftover -Value"      ((@($regC -split "`r?`n" | Where-Object { $_ -match 'Get-ADTRegistryKey' }) -join ' ') -notmatch '(?<!\w)-Value(?!\w)')
Assert "Set-ADTRegistryKey -Value (data) UNTOUCHED"     ($regC -match "Set-ADTRegistryKey -Key 'HKLM:\\SOFTWARE\\App' -Name 'Flag' -Value '1'")
# Branding helper: Remove-Branding -InstanceName + -AdditionalRegPaths -> Remove-MTBDetectionKey -Name (no extra params)
$brand = Convert-V3ToV4Content -Content 'Remove-Branding -InstanceName "*App*" -AdditionalRegPaths "HKLM:\Software\A","HKLM:\Software\B"'
Assert "branding: Remove-Branding -> Remove-MTBDetectionKey -Name" ($brand -match 'Remove-MTBDetectionKey -Name "\*App\*"')
Assert "branding: -InstanceName gone"                  ($brand -notmatch '-InstanceName')
Assert "branding: -AdditionalRegPaths stripped"        ($brand -notmatch '-AdditionalRegPaths')
# GPFT GUARD: every v3->v4 mapper TARGET must be a REAL v4 function (PSADT export OR team MTB extension) - else the
# converter would emit a call to a non-existent cmdlet. Reads the live template manifest + extensions module.
$tplC = Join-Path (Split-Path (Resolve-Module 'PSADT_V3toV4_Mappings.ps1') -Parent) 'PSADT_Template\Content'
$psd1 = Join-Path $tplC 'PSAppDeployToolkit\PSAppDeployToolkit.psd1'
$extM = Join-Path $tplC 'PSAppDeployToolkit.Extensions\PSAppDeployToolkit.Extensions.psm1'
$v4set = @{}
if (Test-Path $psd1) { try { foreach ($fn in (Import-PowerShellDataFile $psd1).FunctionsToExport) { $v4set["$fn"] = $true } } catch {} }
if (Test-Path $extM) { foreach ($mm in [regex]::Matches((Get-Content $extM -Raw), '(?im)^\s*function\s+([\w-]+)')) { $v4set[$mm.Groups[1].Value] = $true } }
if ($v4set.Count -gt 50) {
    $bad = @(); foreach ($k in $script:V3ToV4Functions.Keys) { $nm = "$($script:V3ToV4Functions[$k].NewName)"; if ($nm -and -not $v4set.ContainsKey($nm)) { $bad += "$k -> $nm" } }
    if ($bad.Count) { $bad | ForEach-Object { Write-Host "   BAD MAPPER TARGET: $_" -ForegroundColor Red } }
    Assert "v3->v4 mapper: every target is a real v4 function" ($bad.Count -eq 0)
} else { Write-Host "SKIP mapper-target check (v4 export list not found at $psd1)" -ForegroundColor Yellow }

# ---- Pre-Repair must not carry branding removal / reboot ----
$prn = Remove-PreRepairNoise "## Branding Uninstall`r`nRemove-MTBDetectionKey `"X`"`r`n#Set-MTBReboot`r`nStart-ADTProcess -FilePath x"
Assert "PreRepair drops MTBDetectionKey/Reboot" (($prn -notmatch 'MTBDetectionKey') -and ($prn -notmatch 'MTBReboot') -and ($prn -match 'Start-ADTProcess'))

# ==== GPF BRAND: gold-standard corpus (only where the OtherBrand examples exist) =================================
# Real inputs, real expected outputs: their v3 predecessors + their HUMAN-AUTHORED v4 successors.
$audiRoot = 'C:\Users\AW140\Downloads\OtherBrand'
if ((Test-Path "$audiRoot\Incoming") -and (Test-Path "$audiRoot\Outgoing")) {
    $savedSettings = $script:Settings
    $script:Settings = @{ Brand = @{ Name='GPF'; TemplateRoot='PSADT_Template_GPF'; OrderNumberLabel='AES'
        OutgoingPrefix=[ordered]@{ INA='Gpf'; VWG='Group package'; G1V='VW' }
        Features=@{ Sccm=$false; Intune=$false; Publish=$false }
        Convert=@{ MtbMappings=$false; VwgVarRename=$false; RegWowHardcode=$false; LogPathMain=$false; SectionVarScope=$false; SoftIdentFormat='GPF' } } }
    try {
        # (a) Incoming resolver on the real requests
        $r7 = Resolve-GpfRequest -RequestPath (Join-Path "$audiRoot\Incoming" 'AES-1-020436-A Igor Pavlov 7-Zip 26.01')
        Assert "GPF: AES number parsed"                 ($r7.OrderNumber -eq 'AES-1-020436-A')
        Assert "GPF: request pred (mangled name ok)"    ($r7.PredecessorPath -match 'INA_IgorPavlov_7Zip')
        Assert "GPF: find request w/o AES prefix"       ((Find-GpfRequestFolder "$audiRoot\Incoming" 'Igor Pavlov 7-Zip 26.01') -match '020436')
        $rm = Resolve-GpfRequest -RequestPath (Join-Path "$audiRoot\Incoming" 'AES-1-020419-A Microsoft MECM Console 5.2509')
        Assert "GPF: raw Sources shape -> payload root" ($rm.PayloadRoot -match 'MECM_Console_2509_OFF')
        $pOut = Find-GpfPredecessor -RequestPath '' -OutgoingRoot "$audiRoot\Outgoing" -Vendor 'Microsoft' -AppName 'MECMConsole'
        Assert "GPF: Outgoing fallback w/ brand prefix" ($pOut -and $pOut.Path -match 'INA_Microsoft_MECMConsole')
        # (b) conversion profile on the REAL MECM v3 (authored) sections
        $v3c = Read-FileSmart -Path "$audiRoot\Outgoing\INA_Microsoft_MECMConsole_x86_2503-0002_MUL\Content\Deploy-Application.ps1"
        $mI = Convert-V3ToV4Content -Content (Get-SectionBody -Content $v3c -Section ($script:SectionMarkers | Where-Object { $_.F -eq 'MainInstallCode' }))
        $pI = Convert-V3ToV4Content -Content (Get-SectionBody -Content $v3c -Section ($script:SectionMarkers | Where-Object { $_.F -eq 'PostInstallCode' }))
        Assert "GPF conv: Execute-Process -> Start-ADTProcess" ($mI -match 'Start-ADTProcess' -and $mI -notmatch '(?<![A-Za-z-])Execute-Process\b')
        Assert "GPF conv: dirFiles -> adtSession.DirFiles"     ($mI -match 'adtSession\.DirFiles' -and $mI -notmatch '\$dirFiles\b')
        Assert "GPF conv: logDir -> adtConfig.Toolkit.LogPath" ("$mI$pI" -match 'adtConfig\.Toolkit\.LogPath' -and "$mI$pI" -notmatch '(?i)\$configToolkitLogDir')
        Assert "GPF conv: appVendor STAYS (Global bridge)"     ("$mI$pI" -match '\$appVendor' -and "$mI$pI" -notmatch 'adtSession\.AppVendor')
        Assert "GPF conv: Remove-Branding verbatim"            ((Convert-V3ToV4Content -Content 'Remove-Branding -InstanceName "*x*" -AdditionalRegPaths "HKLM:\Software\$($VWG_CurrentRegWow)VWG\CM"') -match 'Remove-Branding -InstanceName "\*x\*" -AdditionalRegPaths .*VWG_CurrentRegWow')
        # (c) GPF template pack: markers + field fill on their line shapes
        $gpfRoot0 = Split-Path (Resolve-Module 'PSADT_V3toV4_Mappings.ps1') -Parent
        $gpfTplPath = Join-Path $gpfRoot0 'Lib\PSADT_Template_GPF\Content\Invoke-AppDeployToolkit.ps1'                       # consolidated (Lib) layout
        if (-not (Test-Path $gpfTplPath)) { $gpfTplPath = Join-Path $gpfRoot0 'PSADT_Template_GPF\Content\Invoke-AppDeployToolkit.ps1' }
        if (Test-Path $gpfTplPath) {
            $atpl = Read-FileSmart -Path $gpfTplPath
            $mOk = $true; foreach ($s in $script:SectionMarkers) { if (-not ([regex]::Match($atpl,$s.B).Success -and [regex]::Match($atpl,$s.E).Success)) { $mOk = $false } }
            Assert "GPF tpl: all $($script:SectionMarkers.Count) section markers present" $mOk
            # 18. Custom FUNCTIONS section is carried (predecessor helper funcs like Show-HTMLInstallationWelcome were being
            #     DROPPED - the call survived but the definition didn't, breaking the script). Keep verbatim (already v4-converted).
            $cfMk = $script:SectionMarkers | Where-Object { $_.F -eq 'CustomFunctions' } | Select-Object -First 1
            Assert 'GPF: CustomFunctions section marker exists' ($null -ne $cfMk)
            $cfSrc = "#*====CUSTOM APPLICATION FUNCTIONS BEGIN====`r`nFunction Show-HTMLInstallationWelcome { param(`$x) `$x }`r`n#*====CUSTOM APPLICATION FUNCTIONS END===="
            Assert 'GPF: predecessor custom function carried' ((Get-SectionBody -Content $cfSrc -Section $cfMk) -match 'Function Show-HTMLInstallationWelcome')
            # 19. GPF keeps its OWN Set-EnvironmentVariable / Expand-ZipFile customs (defined in their Extensions module) -
            #     NOT renamed to Set-ADTEnvironmentVariable / Expand-MTBZipFile (those are MTB-only).
            Assert 'GPF: Set-EnvironmentVariable kept (GPF custom)' ((Convert-V3ToV4Content -Content 'Set-EnvironmentVariable -EnvironmentVariable "X" -EnvironmentValue "1"') -match 'Set-EnvironmentVariable -EnvironmentVariable "X"')
            Assert 'GPF: Expand-ZipFile kept (GPF custom)'         ((Convert-V3ToV4Content -Content 'Expand-ZipFile -Path "a.zip" -Destination "d"') -match 'Expand-ZipFile ')
            # 20. Uninstall free space FORCED to 200 (overrides a predecessor-carried value).
            $fs500 = Set-SessionValue -Text $atpl -Field 'FreeSpaceUninst' -Value "'500'"
            $fsOut = Set-GpfWrapperDefaults -Text $fs500 -NewPkg @{ Vendor='V'; AppName='A'; Arch='x64'; Version='1.0'; Revision='0001'; Lang='L'; Ritm='R' } -IsMsi $true
            Assert 'GPF: FreeSpaceUninst forced to 200' ($fsOut -match "VWG_FreeSpaceUninst\s*=\s*'200'")
            # 21. Generated immediate-predecessor uninstall block removes the predecessor branding via Remove-Branding.
            $upModel = @{ Identity=@{ FullName='V_A_x64_1.0-0001_L'; AppName='A'; Version='1.0' }; Code=@{ PreUninstallCode=''; MainUninstallCode="Start-ADTMsiProcess -Action 'Uninstall' -ProductCode '{059265e7-6cce-4f39-9740-d436b841c1a1}'"; PostUninstallCode='' }; Installer=@{ ProductCode='{059265e7-6cce-4f39-9740-d436b841c1a1}' } }
            Assert 'GPF: uninstall-prev block removes predecessor branding' ((New-UninstallPreviousBlock -Model $upModel -WrapperLine $null) -match 'Remove-Branding -InstanceName "V_A_x64_1\.0-0001_L"')
            # 22. Predecessor's bare "##Uninstalling <...> if present" self-uninstall guard is stripped from pre-install
            #     (redundant with the generated immediate-predecessor block; reads as a current-version uninstall).
            $suSrc = ('    ## CUSTOM setup BEFORE the guard - MUST survive',
                      '    Set-EnvironmentVariable -EnvironmentVariable "PVIEW" -EnvironmentValue "1"',
                      '    Remove-ADTRegistryKey -Key "HKLM:\SOFTWARE\OtherApp" -Name "Before"','',
                      '    ##Uninstalling "Tenable NessusAgentAS 11.2.0.20301" if present',
                      "    Start-ADTMsiProcess -Action 'Uninstall' -ProductCode '{059265e7}'",'',
                      '    ##Removing Folder if present','    Remove-ADTFolder -Path "$envprogramfiles\Tenable\Nessus Agent"','',
                      '    #Removing TAG registry','    Remove-ADTRegistryKey -Key "HKLM:\SOFTWARE\Tenable" -Name "TAG"','',
                      '    #Removing registry key IfEmpty','    If (Test-Path -Path "HKLM:\SOFTWARE\Tenable")','    {',
                      '        If (((Get-ItemProperty -Path "HKLM:\SOFTWARE\Tenable") -eq $Null) -and ((Get-childitem -Path "HKLM:\SOFTWARE\Tenable") -eq $null))',
                      '        {','            Remove-ADTRegistryKey -Key "HKLM:\SOFTWARE\Tenable"','        }','    }','',
                      '    ## CUSTOM logic AFTER the guard - MUST survive',
                      '    Start-ADTProcess -FilePath "custom.exe" -ArgumentList "/setup"',
                      '    Remove-ADTRegistryKey -Key "HKLM:\SOFTWARE\OtherApp" -Name "After"') -join "`r`n"
            $suOut = Remove-SelfUninstallGuard -Body $suSrc
            # ONLY the guard is gone; ALL surrounding legitimate pre-install code is intact (no missing pre-install code).
            Assert 'GPF: self-uninstall guard stripped, surrounding code kept' (
                ($suOut -notmatch 'Uninstalling .* if present') -and ($suOut -notmatch 'Nessus Agent') -and
                ($suOut -match 'CUSTOM setup BEFORE') -and ($suOut -match 'Name "Before"') -and ($suOut -match 'Set-EnvironmentVariable') -and
                ($suOut -match 'CUSTOM logic AFTER') -and ($suOut -match 'custom\.exe') -and ($suOut -match 'Name "After"'))
            # 23. Review no longer FALSE-flags a SoftIdent product code that was correctly swapped to the NEW package's PC.
            $siRev = "[string] `$Global:VWG_SoftIdent = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{AAAAAAAA-1111-2222-3333-444444444444} [DisplayVersion = 1.0]'"
            Assert 'GPF: review SKIPS SoftIdent PC that equals the new PC' (@(Get-ScriptReviewFindings -ScriptText $siRev -IsPredecessor $true -NewProductCode '{AAAAAAAA-1111-2222-3333-444444444444}').Count -eq 0)
            Assert 'GPF: review KEEPS SoftIdent PC that differs from new PC' (@(Get-ScriptReviewFindings -ScriptText $siRev -IsPredecessor $true -NewProductCode '{BBBBBBBB-0000-0000-0000-000000000000}').Count -ge 1)
            # 24. GPF offers ALL predecessors in the request's Predecessor\ folder (e.g. GlobalProtect's 4), not just latest.
            $gpRoot = Join-Path $env:TEMP ('pbgpcand_' + [guid]::NewGuid().ToString('N')); $gpPred = Join-Path $gpRoot 'Predecessor'
            foreach ($n in 'PaloAltoNetwork_GlobalProtect_x64_6.2.4-0001_MUL','PaloAltoNetwork_GlobalProtect_x64_6.2.5-0001_MUL','PaloAltoNetwork_GlobalProtect_x64_6.2.8-0002_MUL') { New-Item (Join-Path $gpPred $n) -ItemType Directory -Force | Out-Null }
            $gpCands = @(Get-GpfPredecessorCandidates -Parsed (Parse-PackageName 'PaloAltoNetwork_GlobalProtect_x64_6.3.3-0001_MUL') -Request @{ PredecessorRoot=$gpPred; PredecessorPath=(Join-Path $gpPred 'PaloAltoNetwork_GlobalProtect_x64_6.2.8-0002_MUL') })
            Assert 'GPF: ALL predecessors offered (not just latest)' (($gpCands.Count -eq 3) -and ($gpCands[0].Version -eq '6.2.8'))
            Remove-Item $gpRoot -Recurse -Force -ErrorAction SilentlyContinue
            Assert "GPF tpl: Get-TemplateScript picks it up" ((Get-TemplateScript) -match 'Wrapper Variables')
            $fx = Set-SessionField (Set-SessionField $atpl 'AppVendor' 'V1') 'OrderNumber' 'AES-1-000001-A'
            $fx = Set-SessionValue -Text $fx -Field 'SoftIdent' -Value "'HKLM:\X\{AAA} [DisplayVersion]=1.0'"
            Assert "GPF tpl: adtSession + VWG_ lines fill"   (($fx -match "AppVendor\s+=\s+'V1'") -and ($fx -match "VWG_OrderNumber\s*=\s*'AES-1-000001-A'") -and ($fx -match "VWG_SoftIdent\s*=\s*'HKLM:"))
            $fb = [regex]::Replace($fx, "(?im)(^[ \t]*[^\r\n']*SoftIdent[ \t]*=[ \t]*'[^']*\[DisplayVersion\][ \t]*=[ \t]*)[^'\r\n]+(')", "`${1}2.0`${2}")
            Assert "GPF tpl: [DisplayVersion]=x bump form"   ($fb -match '\[DisplayVersion\]=2\.0''')

            # --- GPF test-case fixes (Package_BuilderTesting.docx) ------------------------------------------------
            # 1. Extract-SessionValues reads the real v4 GPF wrapper shape "[type] $Global:VWG_Field = 'x'"
            #    (Freia predecessor). Before the fix the bare "$VWG_" prefix missed $Global:VWG_ -> {Typ}/'' survived.
            $evSrc = "`t[string] `$Global:VWG_SoftinstTyp = 'Legacy'`r`n`t[string] `$Global:VWG_Portfv = 'VW'"
            $ev = Extract-SessionValues -Content $evSrc -Arch 'x64'
            Assert 'GPF: $Global:VWG_ wrapper read (SoftinstTyp)' ($ev['SoftinstTyp'] -eq "'Legacy'")
            Assert 'GPF: $Global:VWG_ wrapper read (Portfv)'      ($ev['Portfv'] -eq "'VW'")
            # 2. An empty process list is an ARRAY @() (not '') - [string[]] with '' would carry an empty string element.
            $evP = Extract-SessionValues -Content "[string[]] `$Global:VWG_ProcToClose = ''" -Arch 'x64'
            Assert 'GPF: empty proc list -> @()' ($evP['ProcToClose'] -eq '@()')
            # 3. Author name carries no comma (matrix "Last, First" -> "Last First").
            Assert 'GPF: author comma stripped' ((Format-AuthorName 'Prajapati, Sunil') -eq 'Prajapati Sunil')
            # 4. Set-GpfWrapperDefaults fills blanks/{Typ} without clobbering real values.
            $np = @{ Vendor='VW'; AppName='Freia'; Arch='x64'; Version='9.1.1'; Revision='0001'; Lang='MUL'; Ritm='AES-1-020658-A' }
            $wd = Set-GpfWrapperDefaults -Text $atpl -NewPkg $np -IsMsi $false
            Assert 'GPF defaults: {Typ} -> Legacy'     ($wd -match "VWG_SoftinstTyp\s*=\s*'Legacy'")
            Assert 'GPF defaults: Portfv -> vendor'     ($wd -match "VWG_Portfv\s*=\s*'VW'")
            Assert 'GPF defaults: FreeSpace filled'     ($wd -match "VWG_FreeSpace\s*=\s*'300'")
            Assert 'GPF defaults: Legacy SoftIdent = CM key' ($wd -match "VWG_SoftIdent\s*=\s*'HKLM:\\SOFTWARE\\VWG\\CM\\VW_Freia_x64_9\.1\.1-0001_MUL'")
            Assert 'GPF defaults: MSI -> SoftinstTyp MSI' ((Set-GpfWrapperDefaults -Text $atpl -NewPkg $np -IsMsi $true) -match "VWG_SoftinstTyp\s*=\s*'MSI'")
            $preP = Set-SessionValue -Text $atpl -Field 'Portfv' -Value "'ZZ'"
            Assert 'GPF defaults: existing Portfv kept' ((Set-GpfWrapperDefaults -Text $preP -NewPkg $np -IsMsi $false) -match "VWG_Portfv\s*=\s*'ZZ'")
            # 5. Post-install body is injected BEFORE the template's branding/reboot trailer (branding stays LAST).
            $secTpl = "#*====POST-INSTALLATION BEGIN====`r`n    ## Branding Install`r`n    Set-Branding`r`n    #Set-Reboot`r`n#*====POST-INSTALLATION END===="
            $bodied = Set-SectionBody -Template $secTpl -Begin '#\*=+\s*POST-INSTALLATION BEGIN\s*=+' -End '#\*=+\s*POST-INSTALLATION END\s*=+' -Body 'Remove-ADTFile -Path "X"' -Pre $false
            Assert 'GPF: post-install body precedes branding' (($bodied.IndexOf('Remove-ADTFile') -ge 0) -and ($bodied.IndexOf('Remove-ADTFile') -lt $bodied.IndexOf('Set-Branding')))
            # 6. SoftIdent stray space after the Uninstall backslash is collapsed (GlobalProtect finding).
            Assert 'GPF: SoftIdent \Uninstall\ {GUID} space collapsed' ((Format-OutputScript -Text "`$x = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ {AAA}'") -match 'Uninstall\\\{AAA\}')
            # 7. v3->v4 param mappings verified against PSAppDeployToolkit.psm1 v4.1.5 (Tenable/Zscaler/GlobalProtect findings).
            $cAdd = Convert-V3ToV4Content -Content 'Execute-MSI -Action Install -Path "x.msi" -AddParameters "K=1"'
            Assert 'map: Execute-MSI -AddParameters -> -AdditionalArgumentList' (($cAdd -match '-AdditionalArgumentList\s+"K=1"') -and ($cAdd -notmatch '-AddParameters'))
            $cSvc = Convert-V3ToV4Content -Content 'Set-ServiceStartMode -Name "Svc" -StartupType Disabled'
            Assert 'map: Set-ServiceStartMode -Name -> -Service' (($cSvc -match 'Set-ADTServiceStartMode\s+-Service\s+"Svc"') -and ($cSvc -notmatch '-Name'))
            # -IfEmpty -> GPF team house style: single If with -PathType Container AND (Get-ChildItem -Force|Measure-Object).Count -eq 0, -Path.
            $cIfe = Convert-V3ToV4Content -Content 'Remove-Folder -Path "$envProgramFiles\App" -IfEmpty'
            Assert 'map: Remove-Folder -IfEmpty -> GPF empty-folder block' (($cIfe -match 'Test-Path -Path .* -PathType Container') -and ($cIfe -match '\(Get-ChildItem .* -Force \| Measure-Object\)\.Count -eq 0') -and ($cIfe -match 'Remove-ADTFolder -Path') -and ($cIfe -notmatch '-IfEmpty') -and ($cIfe -notmatch 'LiteralPath'))
            Assert 'map: -IfEmpty output parses'                ($(($pfe=$null);[void][System.Management.Automation.Language.Parser]::ParseInput($cIfe,[ref]$null,[ref]$pfe);$pfe.Count -eq 0))
            # Final safety net: a -IfEmpty that survived a preserved verbatim block is still rewritten at format time.
            $cIfe2 = Format-OutputScript -Text '        Remove-ADTFolder -Path "$envProgramFiles\App" -IfEmpty'
            Assert 'fmt: leftover Remove-ADTFolder -IfEmpty -> GPF block' (($cIfe2 -match '-PathType Container') -and ($cIfe2 -match 'Measure-Object\)\.Count -eq 0') -and ($cIfe2 -notmatch '-IfEmpty'))
            # 8. Duplicate template scaffold log lines ("...$appVendor $appName $appVersion...") dropped when the injected
            #    body carries its OWN action logging (verified real-gen: Freia had them doubled above the authored lines).
            $scaffTpl = ('#*====================================MAIN-INSTALLATION BEGIN====',
                     '    If ($VWG_UseDialogs){ }',
                     '    Write-ADTLogEntry -Message "Start Installation $appVendor $appName $appVersion." -Source $adtSession.DeployAppScriptFriendlyName',
                     '    Write-ADTLogEntry -Message "Installation of $appVendor $appName $appVersion." -Source $adtSession.DeployAppScriptFriendlyName',
                     '#*====================================MAIN-INSTALLATION END====') -join "`r`n"
            $aBody = ('Write-ADTLogEntry -Message "Start Installation VW Freia 9.1.1." -Source $adtSession.DeployAppScriptFriendlyName',
                      'Start-ADTProcess -FilePath "x"',
                      'Write-ADTLogEntry -Message "Installation of VW Freia 9.1.1 is successful." -Source $adtSession.DeployAppScriptFriendlyName') -join "`r`n"
            $aOut = Set-SectionBody -Template $scaffTpl -Begin '#\*=+\s*MAIN-INSTALLATION BEGIN\s*=+' -End '#\*=+\s*MAIN-INSTALLATION END\s*=+' -Body $aBody -Pre $true
            Assert 'GPF: duplicate template scaffold log dropped' (($aOut -notmatch '\$appVendor \$appName \$appVersion') -and ($aOut -match 'Start Installation VW Freia 9\.1\.1'))
            # 8b. Set-GpfMainSuccessLog upgrades the bare "<Action> of ..." scaffold log to "... is successful." (idempotent).
            $slIn  = '        Write-ADTLogEntry -Message "Installation of $appVendor $appName $appVersion." -Severity 2 -Source $adtSession.DeployAppScriptFriendlyName'
            $slOut = Set-GpfMainSuccessLog -Text $slIn
            Assert 'GPF: main log -> is successful'       ($slOut -match 'Installation of \$appVendor \$appName \$appVersion is successful\.')
            Assert 'GPF: main log upgrade idempotent'     ((Set-GpfMainSuccessLog -Text $slOut) -eq $slOut)
            Assert 'GPF: Start log NOT touched'           ((Set-GpfMainSuccessLog -Text '        Write-ADTLogEntry -Message "Start Installation $appVendor $appName $appVersion." -Severity 2') -notmatch 'is successful')
            # 8c. FRESH MSI build: the install command lands BETWEEN the Start log and the "is successful" log (gold layout),
            #     not after both (which read as a duplicated pair).
            $flOut = Build-FreshScript -NewPkg @{ Vendor='VW';AppName='Freia';Arch='x64';Lang='MUL';Revision='0001';Version='9.1.1';MsiFileName='Freia.msi';ProductCode='{PC}';Author='Me' } -Template $atpl
            $iStart = $flOut.IndexOf('Start Installation'); $iCmd = $flOut.IndexOf('Start-ADTMsiProcess'); $iDone = $flOut.IndexOf('is successful')
            Assert 'GPF: install cmd sits between Start/success logs' (($iStart -ge 0) -and ($iCmd -gt $iStart) -and ($iDone -gt $iCmd))
            # 8d. FRESH SoftIdent - x64: SINGLE wrapper, PLAIN single-quoted, NO $($VWG_CurrentRegWOW) token (a 64-bit
            #     package never redirects through WoW6432Node, so the token would be wrong syntax). Freia x64 style.
            $siPkg = @{ Vendor='VW';AppName='Freia';Arch='x64';Lang='MUL';Revision='0001';Version='9.1.1';MsiFileName='Freia.msi';ProductCode='{PC}';Author='Me'
                        SoftIdent='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{48EEA2D2-0D25-45F7-9438-1AFD813BF2FB} [DisplayVersion=9.1.1]' }
            $siOut = Build-FreshScript -NewPkg $siPkg -Template $atpl
            Assert 'GPF x64: wrapper SoftIdent plain (no WoW token)' ($siOut -match "(?m)^\s*\[string\]\s*\`$Global:VWG_SoftIdent\s*=\s*'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\{48EEA2D2-0D25-45F7-9438-1AFD813BF2FB\} \[DisplayVersion=9\.1\.1\]'")
            Assert 'GPF x64: SoftIdent has NO WoW token'            ($siOut -notmatch 'VWG_CurrentRegWOW')
            Assert 'GPF x64: SoftIdent defined exactly once'        (([regex]::Matches($siOut, '\$Global:VWG_SoftIdent\s*=')).Count -eq 1)
            # 8e. FRESH SoftIdent - x86: TWO places (GandalfClient style) - wrapper PLAIN (no token) + CUSTOM VARIABLES
            #     re-assigned WITH the $($VWG_CurrentRegWOW) token (WoW6432Node redirects on 32-bit, resolved at runtime).
            $siPkg86 = @{ Vendor='VW';AppName='Gandalf';Arch='x86';Lang='MUL';Revision='0001';Version='6.1.0';MsiFileName='G.msi';ProductCode='{PC}';Author='Me'
                          SoftIdent='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GandalfClient_is1 [DisplayVersion=6.1.0]' }
            $siOut86 = Build-FreshScript -NewPkg $siPkg86 -Template $atpl
            Assert 'GPF x86: SoftIdent two-place'                   (([regex]::Matches($siOut86, '\$Global:VWG_SoftIdent\s*=')).Count -eq 2)
            Assert 'GPF x86: custom-vars SoftIdent has WoW token'   ($siOut86 -match ([regex]::Escape('$Global:VWG_SoftIdent') + '\s*=\s*"HKLM:\\SOFTWARE\\\$\(\$VWG_CurrentRegWOW\)Microsoft'))
            Assert 'GPF x86: wrapper SoftIdent plain (no token)'    ($siOut86 -match "(?m)^\s*\[string\]\s*\`$Global:VWG_SoftIdent\s*=\s*'HKLM:")
            # 8f. Set-GpfSoftIdentTwoPlace - the shared enforcement used by BOTH build paths (fresh AND predecessor
            #     reuse). Never hardcode WoW6432Node: wrapper stays PLAIN, the tokened copy is x86-only (user rule).
            $twA  = Set-SessionValue -Text $atpl -Field 'SoftIdent' -Value "'HKLM:\SOFTWARE\WoW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\App_is1 [DisplayVersion=1.0]'"
            $twA1 = Set-GpfSoftIdentTwoPlace -Text $twA -Arch 'x86'
            Assert 'GPF 2place: x86 hardcoded WoW -> wrapper plain' ($twA1 -match "(?m)^\s*\[string\]\s*\`$Global:VWG_SoftIdent\s*=\s*'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\App_is1")
            Assert 'GPF 2place: x86 gains tokened custom-var'       ((([regex]::Matches($twA1,'\$Global:VWG_SoftIdent\s*=')).Count -eq 2) -and ($twA1 -match ([regex]::Escape('$Global:VWG_SoftIdent') + '\s*=\s*"HKLM:\\SOFTWARE\\\$\(\$VWG_CurrentRegWOW\)Microsoft')))
            Assert 'GPF 2place: no hardcoded WoW6432Node left'      (@(($twA1 -split "`r?`n") | Where-Object { $_ -match '(?i)WoW6432Node' -and $_ -notmatch 'CurrentRegWOW' }).Count -eq 0)
            Assert 'GPF 2place: idempotent'                         ((Set-GpfSoftIdentTwoPlace -Text $twA1 -Arch 'x86') -eq $twA1)
            $twB  = Set-SessionValue -Text $atpl -Field 'SoftIdent' -Value '"HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)Microsoft\Windows\CurrentVersion\Uninstall\{AAA} [DisplayVersion=1.0]"'
            $twB1 = Set-GpfSoftIdentTwoPlace -Text $twB -Arch 'x64'
            Assert 'GPF 2place: x64 strips token from wrapper'      ($twB1 -notmatch 'VWG_CurrentRegWOW')
            Assert 'GPF 2place: x64 stays single'                   (([regex]::Matches($twB1,'\$Global:VWG_SoftIdent\s*=')).Count -eq 1)
            $twC  = Set-SessionValue -Text $atpl -Field 'SoftIdent' -Value "'HKLM:\SOFTWARE\VWG\CM\VW_App_x86_1.0-0001_MUL'"
            $twC1 = Set-GpfSoftIdentTwoPlace -Text $twC -Arch 'x86'
            Assert 'GPF 2place: CM branding key stays single/plain' ((([regex]::Matches($twC1,'\$Global:VWG_SoftIdent\s*=')).Count -eq 1) -and ($twC1 -notmatch 'VWG_CurrentRegWOW'))
            # 9. Uninstall-previous block: empty If($flag){} + orphan $flag=$true stripped (belongs to CURRENT uninstall fn).
            $bBody = ('If (Test-Path -Path "x") {','    Start-ADTProcess -FilePath "y"','    $flag = $true','}','If ($flag)','{','}') -join "`r`n"
            $bOut = Get-UninstallBody -Model @{ Code = @{ PreUninstallCode=''; MainUninstallCode=$bBody; PostUninstallCode='' } }
            Assert 'GPF: empty If($flag) + orphan $flag stripped from uninstall-prev' (($bOut -notmatch 'If\s*\(\s*\$flag\s*\)') -and ($bOut -notmatch '\$flag\s*=\s*\$true'))
            # 10. Duplicate "#*====PHASE BEGIN/END====" banners stripped from GPF output (only the ## MARK: fences remain).
            $bnr = Format-OutputScript -Text ("code above" + "`r`n#*====================================PRE-INSTALLATION BEGIN====`r`n    Set-Reboot`r`n#*====================================POST-INSTALLATION END====`r`ncode below")
            Assert 'GPF: #*==== duplicate banners stripped' (($bnr -notmatch '#\*=+') -and ($bnr -match 'Set-Reboot'))
            # 11. Flag-logic: Post-Uninstall branding removal is wrapped in If($flag){} (drops the dead empty guard +
            #     the unconditional Remove-Branding) when the Uninstall function sets $flag (finding #14 / gold standard).
            $fgTpl = ('#*====================================MAIN-UNINSTALLATION BEGIN====','    $flag = $true','#*====================================MAIN-UNINSTALLATION END====',
                      '#*====================================POST-UNINSTALLATION BEGIN====','    If ($flag)','    {','    }','    ## Branding Uninstall','    Remove-Branding','    #Set-Reboot','#*====================================POST-UNINSTALLATION END====') -join "`r`n"
            $fgOut = Set-GpfFlagGuardedBranding -Text $fgTpl
            Assert 'GPF: Post-Uninstall branding guarded by If($flag)' (($fgOut -match '(?s)If\s*\(\s*\$flag\s*\)\s*\{\s*##[ \t]*Branding Uninstall\s*Remove-Branding\s*\}') -and (([regex]::Matches($fgOut,'Remove-Branding')).Count -eq 1))
            # 12. Copy-ADTFile from an EXTERNAL $env source is Test-Path guarded - CRLF-safe (BOTH lines, not just the last).
            $cpTest = Format-OutputScript -Text ((('        Copy-ADTFile -Path "$envSystemRoot\a.log" -Destination "d"'),('        Copy-ADTFile -Path "$envProgramFiles\b.log" -Destination "d"')) -join "`r`n")
            Assert 'GPF: external Copy-ADTFile guarded (both CRLF lines)' (([regex]::Matches($cpTest,'if \(Test-Path')).Count -eq 2)
            $cpPkg = Format-OutputScript -Text '        Copy-ADTFile -Path "$($adtSession.DirFiles)\app.exe" -Destination "d"'
            Assert 'GPF: package-payload Copy-ADTFile NOT guarded' ($cpPkg -notmatch 'if \(Test-Path')
            # 13. Literal \WOW6432Node\ tokenized to $($VWG_CurrentRegWOW) (Gandalf x86 snapshot-cleanup finding).
            $wowOut = Format-OutputScript -Text "Remove-ADTRegistryKey -Key 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\GandalfClient_is1' -Recurse"
            Assert 'GPF: WOW6432Node -> $($VWG_CurrentRegWOW) token' (($wowOut -match 'VWG_CurrentRegWOW') -and ($wowOut -notmatch 'WOW6432Node'))
            # 14. HTML prompt block placed ABOVE the UseDialogs block (finding: above line 265 as per predecessor).
            $htmlTpl = ('#*====================================PRE-INSTALLATION BEGIN====','    if ($VWG_CheckForReboot){ Set-Reboot }','    # user dialogs (deprecated)','    if ($VWG_UseDialogs){ Show-ADTInstallationWelcome }','#*====================================PRE-INSTALLATION END====') -join "`r`n"
            $htmlOut = Set-SectionBody -Template $htmlTpl -Begin '#\*=+\s*PRE-INSTALLATION BEGIN\s*=+' -End '#\*=+\s*PRE-INSTALLATION END\s*=+' -Body 'Show-HTMLInstallationWelcome -CustomHtmlFile "x.html"' -Pre $true
            Assert 'GPF: HTML prompt placed above UseDialogs' (($htmlOut.IndexOf('Show-HTMLInstallationWelcome') -ge 0) -and ($htmlOut.IndexOf('Show-HTMLInstallationWelcome') -lt $htmlOut.IndexOf('# user dialogs')))
            # 15. v4 layout: SupportFiles hoisted OUT of Content\Files to Content\SupportFiles (team finding).
            $hRoot = Join-Path $env:TEMP ('pbhoist_' + [guid]::NewGuid().ToString('N'))
            $hFiles = Join-Path $hRoot 'Files'; $hSup = Join-Path $hRoot 'SupportFiles'
            New-Item (Join-Path $hFiles 'SupportFiles') -ItemType Directory -Force | Out-Null
            Set-Content (Join-Path $hFiles 'SupportFiles\cfg.html') 'x' -Force
            Invoke-SupportFilesHoist -FilesDir $hFiles -SupportDir $hSup
            Assert 'GPF: SupportFiles hoisted out of Files' ((Test-Path (Join-Path $hSup 'cfg.html')) -and -not (Test-Path (Join-Path $hFiles 'SupportFiles')))
            Remove-Item $hRoot -Recurse -Force -ErrorAction SilentlyContinue
            # 16. MRF form renamed to carry the package full name; idempotent when an old fullname suffix is present.
            Assert 'GPF: MRF gets package full name'        ((Get-MrfTargetName -FileBaseName 'ModulePack Request_v1.51' -Vendor 'G1V' -FullName 'G1V_X_x64_1.0-0001_en-US' -Ext '.xlsx') -eq 'ModulePack Request_v1.51_G1V_X_x64_1.0-0001_en-US.xlsx')
            Assert 'GPF: MRF re-run replaces old suffix'     ((Get-MrfTargetName -FileBaseName 'ModulePack Request_v1.51_G1V_X_x64_0.9-0001_en-US' -Vendor 'G1V' -FullName 'G1V_X_x64_1.0-0001_en-US' -Ext '.xlsx') -eq 'ModulePack Request_v1.51_G1V_X_x64_1.0-0001_en-US.xlsx')
            # MRF now carries the BRAND PREFIX (INA_/VWG_/G1V_) since the output folder is prefixed - and stays idempotent
            # (a prior prefixed name must not double to "..._INA_INA_ZSCALER..."). Vendor here is ZSCALER, prefix is INA.
            Assert 'GPF: MRF prefixed name (INA_ZSCALER...)'  ((Get-MrfTargetName -FileBaseName 'ModulePack Request_v1.51' -Vendor 'ZSCALER' -FullName 'INA_ZSCALER_ClientConnectorVWGroup_x64_4.9.0.412-0001_en-US' -Ext '.xlsx') -eq 'ModulePack Request_v1.51_INA_ZSCALER_ClientConnectorVWGroup_x64_4.9.0.412-0001_en-US.xlsx')
            Assert 'GPF: MRF prefixed re-run idempotent'      ((Get-MrfTargetName -FileBaseName 'ModulePack Request_v1.51_INA_ZSCALER_ClientConnectorVWGroup_x64_4.9.0.412-0001_en-US' -Vendor 'ZSCALER' -FullName 'INA_ZSCALER_ClientConnectorVWGroup_x64_4.9.0.412-0001_en-US' -Ext '.xlsx') -eq 'ModulePack Request_v1.51_INA_ZSCALER_ClientConnectorVWGroup_x64_4.9.0.412-0001_en-US.xlsx')
            # 17. v4 path normalisation: $scriptDirectory\SupportFiles -> $adtSession.DirSupportFiles.
            Assert 'GPF: $scriptDirectory\SupportFiles -> DirSupportFiles' ((Convert-V3ToV4Content -Content 'Copy-File -Path "$scriptDirectory\SupportFiles\x.html" -Destination "d"') -match 'DirSupportFiles')
        } else { Write-Host "SKIP GPF template asserts (PSADT_Template_GPF not present)" -ForegroundColor Yellow }
        # (d) marker-set detection: their authored v4 kept standard markers; sections extract non-empty
        $a7 = Read-FileSmart -Path "$audiRoot\Outgoing\VWG_IgorPavlov_7Zip_x64_26.01-0001_MUL\Content\Invoke-AppDeployToolkit.ps1"
        $set7 = Get-PBMarkerSet -Content $a7
        $pre7 = Get-SectionBody -Content $a7 -Section ($set7 | Where-Object { $_.F -eq 'PreInstallCode' })
        Assert "GPF v4 authored: sections extract (version-check kept)" ($pre7 -match 'Get-ADTApplication' -and $pre7 -match '23170F69-40C1-2701-0920')
        Assert "GPF v4 authored: template boilerplate stripped"         ($pre7 -notmatch 'Show-ADTInstallationWelcome' -and $pre7 -notmatch 'VWG_CheckForReboot')
    } finally { $script:Settings = $savedSettings }
} else { Write-Host "SKIP GPF corpus tests (Downloads\OtherBrand not present)" -ForegroundColor Yellow }

# ==== GPF New_Findings batch (2026-07-24) - UNGATED (do NOT depend on OtherBrand), so they always run ============
$__saved = $script:Settings
$script:Settings = @{ Brand = @{ Name='GPF'; ToolName='Package Assistance'; TemplateRoot='PSADT_Template_GPF'; OrderNumberLabel='AES'
    Convert=@{ MtbMappings=$false; VwgVarRename=$false; RegWowHardcode=$false; LogPathMain=$false; SectionVarScope=$false; SoftIdentFormat='GPF' } } }
try {
    $nfTpl = $null
    $nfPath = Join-Path (Split-Path (Resolve-Module 'PSADT_V3toV4_Mappings.ps1') -Parent) 'lib\PSADT_Template_GPF\Content\Invoke-AppDeployToolkit.ps1'
    if (Test-Path $nfPath) { $nfTpl = Read-FileSmart -Path $nfPath }
    # F12: Write-ADTLogEntry -Source back to $adtSession.DeployAppScriptFriendlyName
    $nf12 = Convert-V3ToV4Content -Content "Write-Log -Message 'x' -Source `$deployAppScriptFriendlyName"
    Assert "NF F12: -Source -> adtSession.DeployAppScriptFriendlyName" (($nf12 -match '\$adtSession\.DeployAppScriptFriendlyName') -and ($nf12 -notmatch '(?<!\.)\$deployAppScriptFriendlyName'))
    # F18: generated per-user registry uses -Key not -LiteralPath
    $nf18 = Get-PBHkcuLines -Items @(@{Key='HKCU:\Software\JavaSoft\Prefs';Name='v';Value='1';Type='DWord'}) -Style 'ADT'
    Assert "NF F18: generated reg -Key not -LiteralPath" (($nf18 -match '-Key ') -and ($nf18 -notmatch '-LiteralPath'))
    # F15: GPF if-empty style (single -and, -PathType Container, Measure-Object, -Path)
    $nf15 = Convert-V3ToV4Content -Content 'Remove-Folder -Path "$envProgramFiles\App" -IfEmpty'
    Assert "NF F15: GPF empty-folder single-and block" (($nf15 -match 'Test-Path -Path .* -PathType Container') -and ($nf15 -match 'Measure-Object\)\.Count -eq 0') -and ($nf15 -notmatch 'LiteralPath') -and ($nf15 -notmatch '-IfEmpty'))
    # F36: variable-GUID -FilePath -> -ProductCode (scoped), real file -FilePath untouched
    $nf36 = Convert-V3ToV4Content -Content "`$MSIGUID = '{A886A286-7184-448D-9D93-CCE7F5D28174}'`r`nExecute-MSI -Action Uninstall -Path `$MSIGUID"
    Assert "NF F36: -FilePath `$MSIGUID -> -ProductCode" (($nf36 -match '-ProductCode \$MSIGUID') -and ($nf36 -notmatch '-FilePath \$MSIGUID'))
    Assert "NF F36: real -FilePath `$msiFile untouched"  ((Convert-V3ToV4Content -Content 'Execute-MSI -Action Install -Path $msiFile') -match '-FilePath \$msiFile')
    # F9: predecessor DisplayName from SoftIdent (strip _is1; MSI GUID -> '')
    Assert "NF F9: DisplayName from SoftIdent (_is1 stripped)" ((Get-PredecessorDisplayName -Model @{ Session=@{ SoftIdent="'HKLM:\...\Uninstall\Animator4_v2.8.1_64_is1 [DisplayVersion=2.8.1]'" } }) -eq 'Animator4_v2.8.1_64')
    Assert "NF F9: MSI GUID subkey -> '' (use ProductCode)"   ((Get-PredecessorDisplayName -Model @{ Session=@{ SoftIdent="'HKLM:\...\Uninstall\{A886A286-7184-448D-9D93-CCE7F5D28174}'" } }) -eq '')
    # F32: GPF LooseFiles ARP -> Set-ApplicationWizardEntry (no MTB)
    $nfLf = Get-LooseFilesCommandSet -InstallPath 'C:\App' -ZipName 'x' -Shortcuts @() -CreateArp $true -AppName 'MyApp'
    Assert "NF F32: GPF ARP -> Set-ApplicationWizardEntry" (($nfLf.MainInstall -match 'Set-ApplicationWizardEntry') -and ($nfLf.MainInstall -notmatch 'Set-MTBApplicationWizardEntry'))
    if ($nfTpl) {
        # F22: Portfv forced to vendor (from carried 'blank'); AppAddInfo01-04 all NA
        $nfW = Set-GpfWrapperDefaults -Text ($nfTpl -replace "VWG_Portfv\s*=\s*''", "VWG_Portfv = 'blank'") -NewPkg @{ Vendor='Volkswagen'; AppName='iDEX'; Arch='x64'; Version='3.0.6.4'; Revision='0001'; Lang='MUL'; Ritm='AES-1-020574-A' } -IsMsi $false
        Assert "NF F22: Portfv forced to vendor (was 'blank')" ($nfW -match "VWG_Portfv\s*=\s*'Volkswagen'")
        Assert "NF F22: AppAddInfo01-04 all NA"                (([regex]::Matches($nfW,"VWG_AppAddInfo0[1-4]\s*=\s*'NA'")).Count -eq 4)
        # F40: carried non-global custom-vars $VWG_SoftIdent -> $Global
        $nfCv = $nfTpl -replace '(?s)(CUSTOM APPLICATION VARIABLES BEGIN[^\r\n]*\r?\n)', "`$1`t[string]`$VWG_SoftIdent = `"HKLM:\SOFTWARE\`$(`$VWG_CurrentRegWOW)Microsoft\Windows\CurrentVersion\Uninstall\App_is1`"`r`n"
        $nfCvOut = Set-GpfSoftIdentTwoPlace -Text $nfCv -Arch 'x86'
        Assert "NF F40: carried `$VWG_SoftIdent -> `$Global" (($nfCvOut -match '\$Global:VWG_SoftIdent\s*=\s*"HKLM') -and ($nfCvOut -notmatch '(?m)^\s*\[string\]\s*\$VWG_SoftIdent\s*='))
        # F47: fresh EXE with NO snapshot -> best-guess Uninstall\<AppName> [DisplayVersion=<ver>] (not the VWG\CM path)
        $nf47 = Set-GpfWrapperDefaults -Text $nfTpl -NewPkg @{ Vendor='Acme'; AppName='CoolTool'; Arch='x64'; Version='3.2.1'; Revision='0001'; Lang='MUL'; Ritm='AES-1-1' } -IsMsi $false
        $nf47si = ([regex]::Match($nf47, "(?im)$(Get-FieldLinePrefix 'SoftIdent')['`"]([^'`"]*)")).Groups[2].Value
        Assert "NF F47: EXE-no-snap Uninstall\<App> [DisplayVersion=ver]" (($nf47si -match 'Uninstall\\CoolTool') -and ($nf47si -match '\[DisplayVersion=3\.2\.1\]') -and ($nf47si -notmatch 'VWG\\CM'))
    }
    # F47: fresh MSI detection carries ProductCode + DisplayVersion (independent of snapshot)
    Assert "NF F47: MSI ProductCode + DisplayVersion" ((Get-AutoSoftIdent -ProductCode '{11112222-3333-4444-5555-666677778888}' -Version '3.2.1') -match 'Uninstall\\\{11112222-3333-4444-5555-666677778888\} \[DisplayVersion=3\.2\.1\]')
    # Review-item audit: fresh EXE bare-app-name detection must be flagged with CHECK AND FILL
    $nfRfFresh = Get-ScriptReviewFindings -ScriptText "    AppName = 'CoolTool'`r`n    SoftIdent = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\CoolTool [DisplayVersion=3.2.1]'" -IsPredecessor $false
    Assert "NF audit: fresh bare-app-name SoftIdent flagged" ((($nfRfFresh -join "`n") -match 'bare app name') -and (($nfRfFresh -join "`n") -match 'CHECK AND FILL'))
    # Review-item audit: predecessor uninstall by bare-AppName fallback must be flagged
    $nfPredFb = "    AppName = 'Animator4'`r`n#Upgrade Acme_Animator4_x64_2.0-0001_MUL`r`nIf ((Get-ADTApplication -Name `"Animator4`") -and (Test-Path -Path `"x`")) {`r`n}"
    Assert "NF audit: pred bare-name fallback flagged" (((Get-ScriptReviewFindings -ScriptText $nfPredFb -IsPredecessor $true) -join "`n") -match 'bare package name')
    # Review-item audit: predecessor detection by ProductCode must NOT raise a name-detection finding
    $nfPredPc = "    AppName = 'Animator4'`r`n#Upgrade Acme_Animator4_x64_2.0-0001_MUL`r`nIf ((Get-ADTApplication -ProductCode `"{AAAABBBB-CCCC-DDDD-EEEE-FFFF00001111}`") -and (Test-Path -Path `"x`")) {`r`n}"
    Assert "NF audit: pred ProductCode no false name finding" (((Get-ScriptReviewFindings -ScriptText $nfPredPc -IsPredecessor $true) -join "`n") -notmatch 'detection is by NAME|bare package name')
    # F52: progress bar carried from predecessor (section-scoped). Predecessor active in INSTALL only -> enable install line, review item raised.
    if ($nfTpl) {
        $nfPredProg = "MAIN-INSTALLATION BEGIN`r`n    If (`$VWG_UseDialogs){`r`n        Show-ADTInstallationProgress`r`n    }`r`nMAIN-INSTALLATION END`r`nMAIN-UNINSTALLATION BEGIN`r`n    If (`$VWG_UseDialogs){`r`n        #Show-ADTInstallationProgress`r`n    }`r`nMAIN-UNINSTALLATION END"
        $nfPb = Set-PredecessorProgressBar -Text $nfTpl -Model @{ RawV4Content = $nfPredProg }
        Assert "NF F52: enables progress in the section predecessor had it" ($nfPb.Enabled -ge 1)
        $nfSecI = [regex]::Match($nfPb.Text,'(?s)MAIN-INSTALLATION BEGIN(.*?)MAIN-INSTALLATION END').Groups[1].Value
        Assert "NF F52: install progress line uncommented" ($nfSecI -match '(?m)^[ \t]*Show-ADTInstallationProgress')
        # Predecessor reuse: the template's bare Main "Installation of ..." log is upgraded to "... is successful." so the
        # carried command lands BETWEEN Start/success (gold layout) instead of leaving two consecutive template logs (iDEX).
        $nfLogUp = Set-GpfMainSuccessLog -Text $nfTpl
        $nfSec = ($script:SectionMarkers | Where-Object { $_.F -eq 'MainInstallCode' })
        $nfMi = Set-SectionBody -Template $nfLogUp -Begin $nfSec.B -End $nfSec.E -Body "Start-ADTMsiProcess -Action 'Install' -FilePath `"x.msi`"" -Pre $nfSec.Pre
        $nfMiSec = [regex]::Match($nfMi,'(?s)MAIN-INSTALLATION BEGIN(.*?)MAIN-INSTALLATION END').Groups[1].Value
        Assert "NF log: reuse main log upgraded + command between Start/success" (($nfMiSec -match 'Installation of \$appVendor \$appName \$appVersion is successful') -and ($nfMiSec -notmatch 'Installation of \$appVendor \$appName \$appVersion\."') -and ($nfMiSec.IndexOf('Start-ADTMsiProcess') -lt $nfMiSec.IndexOf('is successful')) -and ($nfMiSec.IndexOf('Start-ADTMsiProcess') -gt $nfMiSec.IndexOf('Start Installation')))
        # SoftIdent: a real …\Uninstall\{GUID} detection key must carry [DisplayVersion=<new ver>] even if the predecessor
        # only had a bare ProductCode; a VWG\CM branding key must NOT get one.
        $nfU = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{E042B62E-F230-4A0E-A38D-7D5E788F27A7}'
        $nfSi = [regex]::Replace($nfTpl, "(?im)($(Get-FieldLinePrefix 'SoftIdent'))[""'][^""']*[""']", "`${1}'$nfU'")
        $nfSiOut = Set-GpfSoftIdentTwoPlace -Text $nfSi -Arch 'x64' -Version '2.8.2'
        Assert "NF SoftIdent: bare Uninstall\{GUID} gets [DisplayVersion]" (($nfSiOut -match 'Uninstall\\\{E042B62E-F230-4A0E-A38D-7D5E788F27A7\} \[DisplayVersion=2\.8\.2\]') -and -not (($nfSiOut -split "`r?`n") | Where-Object { $_ -match 'Uninstall\\\{E042B62E' -and $_ -notmatch 'DisplayVersion' }))
    }
    Assert "NF SoftIdent: helper adds DV to Uninstall key"        ((Add-SoftIdentDisplayVersion -Value 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{AAAA1111-2222-3333-4444-555566667777}' -Version '3.0') -match '\[DisplayVersion=3\.0\]')
    Assert "NF SoftIdent: helper leaves VWG\CM branding key alone" ((Add-SoftIdentDisplayVersion -Value 'HKLM:\SOFTWARE\VWG\CM\Vendor_App_x64_1.0-0001_MUL' -Version '3.0') -notmatch 'DisplayVersion')
    Assert "NF SoftIdent: helper no double DV"                    ((Add-SoftIdentDisplayVersion -Value 'HKLM:\...\Uninstall\{G} [DisplayVersion=1.0]' -Version '3.0') -notmatch 'DisplayVersion=3\.0')
    # GPF zip source: resolver keeps a Sources\Files\*.zip VERBATIM (no fetch-time extraction), and the zip index reader
    # surfaces installer entries shallowest-first (top-level real entry points before deep app binaries).
    $zsTmp = Join-Path $env:TEMP ("nfzs_" + [guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        $zsSf = Join-Path $zsTmp 'Sources\Files'; New-Item -ItemType Directory -Path $zsSf -Force | Out-Null
        $zsStage = Join-Path $zsTmp 'stage\App'; New-Item -ItemType Directory -Path (Join-Path $zsStage 'bin\deep') -Force | Out-Null
        'x' | Set-Content (Join-Path $zsStage 'Setup.exe'); 'x' | Set-Content (Join-Path $zsStage 'bin\deep\Helper.exe')
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $zsTmp 'stage'), (Join-Path $zsSf 'Payload.zip'))
        $zsRes = Resolve-Source -RootPath (Join-Path $zsTmp 'Sources')
        Assert "NF zipsrc: GPF keeps source zip verbatim (ZipPayload set, no extract)" ([bool]$zsRes.ZipPayload -and (@($zsRes.Installers).Count -eq 1) -and ($zsRes.Installers[0].Name -eq 'Payload.zip'))
        $zsEnt = Get-ZipInstallerEntries -ZipPath $zsRes.ZipPayload
        # one step into the single wrapper folder: Setup.exe shows, deep bin\deep\Helper.exe does NOT
        Assert "NF zipsrc: one-step reader shows Setup.exe, hides deep Helper.exe" ((@($zsEnt).Count -eq 1) -and ($zsEnt[0].Name -eq 'Setup.exe'))
    } finally { Remove-Item -LiteralPath $zsTmp -Recurse -Force -EA SilentlyContinue }
    # ZipPayload install command: Expand-ZipFile to $envTemp\<App>_<Ver> then run the selected inner installers by type
    $zpCmd = New-StandardCommands -NewPkg @{ InstallerMode='ZipPayload'; AppName='App'; Version='1.0'; ZipName='Files.zip'; ZipRunItems=@(
        @{ RelPath='Pkg\install.msi'; Extension='.msi'; Name='install.msi' },
        @{ RelPath='Pkg\SC-Preinstall.ps1'; Extension='.ps1'; Name='SC-Preinstall.ps1' },
        @{ RelPath='Pkg\run.cmd'; Extension='.cmd'; Name='run.cmd' }) }
    Assert "NF zippay: Expand-ZipFile to `$envTemp\<App>_<Ver>" ($zpCmd.MainInstall -match 'Expand-ZipFile[\s\S]*Destination "\$envTemp\\App_1\.0"')
    Assert "NF zippay: msi -> Start-ADTMsiProcess" ($zpCmd.MainInstall -match "Start-ADTMsiProcess -Action 'Install' -FilePath `"\`$envTemp\\App_1\.0\\Pkg\\install\.msi`"")
    Assert "NF zippay: ps1 -> powershell -File"   ($zpCmd.MainInstall -match "powershell\.exe[\s\S]*Pkg\\SC-Preinstall\.ps1")
    Assert "NF zippay: cmd -> cmd /c"             ($zpCmd.MainInstall -match "cmd\.exe`" -ArgumentList '/c'")
    Assert "NF F52: no-op when predecessor had no progress" ((Set-PredecessorProgressBar -Text $nfTpl -Model @{ RawV4Content = $nfTpl }).Enabled -eq 0)
    # F52 review item: active progress on predecessor reuse
    Assert "NF F52: review item on active progress" (((Get-ScriptReviewFindings -ScriptText "    AppName='X'`r`n        Show-ADTInstallationProgress`r`n" -IsPredecessor $true) -join "`n") -match 'progress bar is ENABLED')
    # F54 review item: empty ProcToBlock on predecessor reuse flagged; populated one not flagged
    Assert "NF F54: empty ProcToBlock flagged"     (((Get-ScriptReviewFindings -ScriptText "    AppName='X'`r`n    [string[]] `$Global:VWG_ProcToBlock = @()`r`n" -IsPredecessor $true) -join "`n") -match 'ProcToBlock .* is empty')
    Assert "NF F54: populated ProcToBlock not flagged" (((Get-ScriptReviewFindings -ScriptText "    AppName='X'`r`n    [string[]] `$Global:VWG_ProcToBlock = @('firefox')`r`n" -IsPredecessor $true) -join "`n") -notmatch 'ProcToBlock .* is empty')
    # Invalid characters: Format-OutputScript strips invisible chars a predecessor may carry (NBSP -> space; zero-width /
    # direction marks / inline BOM -> removed) so the generated script parses.
    $nfBad = "Write-Host$([char]0x00A0)'x'$([char]0x200B)  # c$([char]0xFEFF)"
    $nfClean = Format-OutputScript -Text $nfBad
    Assert "NF chars: output has no invisible chars"  (-not ($nfClean.ToCharArray() | Where-Object { [int]$_ -gt 127 }))
    Assert "NF chars: NBSP became a normal space"      ($nfClean -match "Write-Host 'x'")
    # F45: zipped predecessor is detected/extracted (both a .zip file path AND a folder holding a package .zip)
    $f45tmp = Join-Path $env:TEMP ("PBnf45_" + [guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        $f45pkg = 'VWG_ZipPred_x86_1.0.0-0001_MUL'
        $f45c   = Join-Path $f45tmp "$f45pkg\Content"; New-Item -ItemType Directory -Path $f45c -Force | Out-Null
        "[String]`$appName='ZipPred'" | Set-Content -Path (Join-Path $f45c 'Invoke-AppDeployToolkit.ps1') -Encoding UTF8
        $f45zip = Join-Path $f45tmp "$f45pkg.zip"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $f45tmp $f45pkg), $f45zip)
        Remove-Item (Get-PredZipCache -ZipPath $f45zip) -Recurse -Force -EA SilentlyContinue
        Assert "NF F45: Expand-PredecessorZip -> Content-at-root package root" ((Test-Path (Join-Path (Expand-PredecessorZip -ZipPath $f45zip) 'Content\Invoke-AppDeployToolkit.ps1')))
        Assert "NF F45: model loads from a .zip file path" ((Read-PredecessorModel -PackagePath $f45zip -PackageName $f45pkg).Identity.AppName -eq 'ZipPred')
        $f45pf = Join-Path $f45tmp 'Predecessor'; New-Item -ItemType Directory -Path $f45pf -Force | Out-Null
        Copy-Item $f45zip -Destination (Join-Path $f45pf "$f45pkg.zip")
        Assert "NF F45: model loads from folder holding a package .zip" ((Read-PredecessorModel -PackagePath $f45pf -PackageName $f45pkg).Identity.AppName -eq 'ZipPred')
        Assert "NF F45: bad zip path -> '' (no throw)" ((Expand-PredecessorZip -ZipPath (Join-Path $f45tmp 'nope.zip')) -eq '')
    } finally { Remove-Item -LiteralPath $f45tmp -Recurse -Force -EA SilentlyContinue }
    # Predecessor-zip MAX_PATH fix: deeply-nested package zipped WITH a long top folder must still extract (short cache +
    # \\?\ extractor), AND a prior EMPTY/incomplete cache must be re-extracted (not reused). Build a zip whose top folder
    # is the 46-char package name + a nested Content\Invoke, then extract, empty the cache, and re-extract.
    $zpTmp = Join-Path $env:TEMP ("PBzip_" + [guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        $zpName = 'SAP_EnableNowProducer_x86_10.4.0.0133-0001_MUL'
        $zpStage = Join-Path $zpTmp "$zpName\Content"; New-Item -ItemType Directory -Path $zpStage -Force | Out-Null
        "[String]`$appName='EnableNowProducer'" | Set-Content -Path (Join-Path $zpStage 'Invoke-AppDeployToolkit.ps1') -Encoding UTF8
        $zpZip = Join-Path $zpTmp "$zpName.zip"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $zpTmp $zpName), $zpZip, 'Optimal', $true)  # includeBaseDir -> top folder = pkg name
        $zpCache = Get-PredZipCache -ZipPath $zpZip
        if (Test-Path $zpCache) { Remove-Item $zpCache -Recurse -Force -EA SilentlyContinue }
        $zpInner = Expand-GpfPredecessorZip -ZipPath $zpZip
        Assert "NF zipfix: extracts (short cache) + finds inner root" ($zpInner -and (Test-Path (Join-Path $zpInner 'Content\Invoke-AppDeployToolkit.ps1')))
        Assert "NF zipfix: cache path stays short (<120)" ($zpCache.Length -lt 120)
        # empty the cache (folder remains) -> next call must RE-extract, not reuse the empty folder
        Get-ChildItem $zpCache -Force | Remove-Item -Recurse -Force -EA SilentlyContinue
        Assert "NF zipfix: emptied cache detected incomplete" (-not (Test-PredZipComplete -CacheDir $zpCache))
        $zpInner2 = Expand-GpfPredecessorZip -ZipPath $zpZip
        Assert "NF zipfix: re-extracts an emptied cache" ($zpInner2 -and (Test-Path (Join-Path $zpInner2 'Content\Invoke-AppDeployToolkit.ps1')))
    } finally { Remove-Item -LiteralPath $zpTmp -Recurse -Force -EA SilentlyContinue }
    # F57-59: predecessor SupportFiles helper scripts (e.g. sc-uninstall.ps1) suggested for copy; only on reuse
    $nfSf = "    AppName='Bentley'`r`nStart-ADTProcess -FilePath 'powershell.exe' -ArgumentList `"-File `$(`$adtSession.DirSupportFiles)\sc-uninstall.ps1`""
    Assert "NF F57: sc-uninstall.ps1 helper suggested (reuse)" (((Get-ScriptReviewFindings -ScriptText $nfSf -IsPredecessor $true) -join "`n") -match 'sc-uninstall\.ps1')
    Assert "NF F57: helper NOT flagged on fresh package"       (((Get-ScriptReviewFindings -ScriptText $nfSf -IsPredecessor $false) -join "`n") -notmatch 'helper file')
    # F27/F29: MST-generation toggle. ON -> built <msi>.mst; OFF+no src -> plain; OFF+src -> reuse source mst.
    Assert "NF F27: generate ON -> -Transform <msi>.mst" ((New-StandardCommands -NewPkg @{ InstallerMode='SingleMSI'; MsiFileName='app.msi'; ProductCode='{PC}' }).MainInstall -match 'app\.mst')
    Assert "NF F27: generate OFF + no src -> no -Transform" ((New-StandardCommands -NewPkg @{ InstallerMode='SingleMSI'; MsiFileName='app.msi'; ProductCode='{PC}'; GenerateMst=$false; NoMst=$true }).MainInstall -notmatch '-Transform')
    Assert "NF F27: generate OFF + src -> reuse source mst" (((New-StandardCommands -NewPkg @{ InstallerMode='SingleMSI'; MsiFileName='Firefox.msi'; ProductCode='{PC}'; GenerateMst=$false; MstFileName='firefox-esr.mst' }).MainInstall -match 'firefox-esr\.mst') -and ((New-StandardCommands -NewPkg @{ InstallerMode='SingleMSI'; MsiFileName='Firefox.msi'; ProductCode='{PC}'; GenerateMst=$false; MstFileName='firefox-esr.mst' }).MainInstall -notmatch 'Firefox\.mst'))
    # F2: GPF tool display name = "Package Assistance" - from Brand.ToolName AND as the GPF build's hardcoded default
    # (so it's correct even if a portable settings.json lacks ToolName).
    if (Get-Command Get-PBToolName -EA SilentlyContinue) {
        Assert "NF F2: GPF tool name = Package Assistance" ((Get-PBToolName) -eq 'Package Assistance')
        $__b = $script:Settings; $script:Settings = @{ Brand = @{ Name='GPF' } }   # no ToolName
        Assert "NF F2: default (no ToolName) still Package Assistance" ((Get-PBToolName) -eq 'Package Assistance')
        $script:Settings = $__b
    }
    # F25/F34: GPF loose/zip source -> Expand-ZipFile (no MTB) to $envTemp\<App>_<Ver>, referencing the source zip name
    $nfLz = New-StandardCommands -NewPkg @{ InstallerMode='LooseFiles'; AppName='TmxDIKAB'; Version='2408.1700'; Arch='x64'; Vendor='Siemens'; ZipName='TmxDIKAB_source.zip'; CreateArp=$true }
    Assert "NF F25: GPF Expand-ZipFile (no MTB)"         (($nfLz.MainInstall -match 'Expand-ZipFile ') -and ($nfLz.MainInstall -notmatch 'Expand-MTBZipFile'))
    Assert "NF F25: GPF extract to `$envTemp\<App>_<Ver>" ($nfLz.MainInstall -match 'Destination "\$envTemp\\TmxDIKAB_2408\.1700"')
    Assert "NF F25: GPF references source zip name"      ($nfLz.MainInstall -match 'TmxDIKAB_source\.zip')
    # Remove-BrandingREG -> Remove-Branding (GPF modern branding removal; -BrandingKey dropped, -Name/-AdditionalRegPaths kept)
    $nfRb = Convert-V3ToV4Content -Content 'Remove-BrandingREG -Name "*iDEX*" -BrandingKey "HKLM:\Software\VWG\CM" -AdditionalRegPaths "HKLM:\Software\$($VWG_CurrentRegWow)VWG\InstalledProducts", "HKLM:\Software\$($VWG_CurrentRegWow)VWG\CM"'
    Assert "NF branding: GPF Remove-BrandingREG -> Remove-Branding" (($nfRb -match '(?<!REG)\bRemove-Branding\b') -and ($nfRb -notmatch 'Remove-BrandingREG') -and ($nfRb -notmatch '-BrandingKey') -and ($nfRb -match '-Name "\*iDEX\*"') -and ($nfRb -match '-AdditionalRegPaths') -and ($nfRb -match [regex]::Escape('$($VWG_CurrentRegWow)')))
    # Set-EnvironmentVariable: GPF keeps it (valid Extensions fn); MTB converts to Set-ADTEnvironmentVariable (checked in the MTB block below)
    Assert "NF env: GPF keeps Set-EnvironmentVariable" ((Convert-V3ToV4Content -Content 'Set-EnvironmentVariable -EnvironmentVariable "X" -EnvironmentValue "Y"') -match '\bSet-EnvironmentVariable\b')
    # Doc harvest: exclude dependency-named folders (like predecessor); accept "Software Package Request Form" as an
    # alternative install-instructions doc name. Build a mini request tree and run Resolve-GpfRequest.
    $nfDoc = Join-Path $env:TEMP ("PBnfdoc_" + [guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        $nfReq = Join-Path $nfDoc 'AES-1-020607-A GNS_Animator4_x64_2.8.2-0001_en-US'
        $nfVs  = Join-Path $nfReq 'Vendor_Sources'
        New-Item -ItemType Directory -Path (Join-Path $nfVs 'Dependencies') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $nfVs 'Files') -Force | Out-Null
        'x' | Set-Content (Join-Path $nfVs 'Files\Software Package Request Form.docx')
        'x' | Set-Content (Join-Path $nfVs 'Files\Install Instructions.docx')
        'x' | Set-Content (Join-Path $nfVs 'Dependencies\Install Instructions.docx')
        $nfRes = Resolve-GpfRequest -RequestPath $nfReq
        Assert "NF docs: alt-named 'Software Package Request Form' = install instructions" ([bool](@($nfRes.DocItems | Where-Object { $_ -match 'Software Package Request Form\.docx' }).Count))
        Assert "NF docs: dependency-folder doc EXCLUDED" (-not [bool](@($nfRes.DocItems | Where-Object { $_ -match '[\\/]Dependencies[\\/]' }).Count))
    } finally { Remove-Item -LiteralPath $nfDoc -Recurse -Force -EA SilentlyContinue }
    # Intune/SCCM module import: execution-policy is lifted for THIS PROCESS before importing script modules (MSAL.PS /
    # ConfigMgr) - both integrations must call the shared guard so "running scripts is disabled" can't block the import.
    Assert "NF Intune: Enable-PBProcessScripts exists"   ([bool](Get-Command Enable-PBProcessScripts -EA SilentlyContinue))
    $nfToolRoot = Split-Path (Resolve-Module 'PSADT_V3toV4_Mappings.ps1') -Parent
    Assert "NF Intune: guard runs BEFORE MSAL import"    ((Get-Content (Join-Path $nfToolRoot 'Intune.ps1') -Raw) -match 'Enable-PBProcessScripts[\s\S]{0,400}Import-Module \$msalPath')
    Assert "NF SCCM: still lifts policy (shared guard)"  ((Get-Content (Join-Path $nfToolRoot 'Sccm.ps1') -Raw) -match 'Enable-PBProcessScripts')
    # PREDECESSOR REUSE, Main section (-DropTemplateLogs): team decision "use whatever the predecessor has and remove our
    # v4 template log lines". The iDEX predecessor owns DIFFERENTLY-WORDED logging ("Installation finished successfully
    # with: [exitcode]" / "failed with") that bodyOwnsAction CANNOT detect - the flag drops the template Start/Installation-of
    # scaffold anyway, keeps the predecessor's own logs, and the layout stays clean (self-contained; no AUDI corpus needed).
    $nfReuseTpl = ('#*====================================MAIN-INSTALLATION BEGIN====',
                 "`t    # user dialogs (deprecated)", "`t    If (`$VWG_UseDialogs){", "`t    }", '', '',
                 '        Write-ADTLogEntry -Message "Start Installation $appVendor $appName $appVersion." -Severity 2 -Source $adtSession.DeployAppScriptFriendlyName',
                 '        ', '                ', '',
                 '        Write-ADTLogEntry -Message "Installation of $appVendor $appName $appVersion." -Severity 2 -Source $adtSession.DeployAppScriptFriendlyName',
                 '    ', '#*====================================MAIN-INSTALLATION END====') -join "`r`n"
    $nfIdexBody = ('$ret = Start-ADTProcess -FilePath "$($adtSession.DirFiles)\$Installer" -ArgumentList $InstallerParams -WindowStyle Hidden -PassThru',
                   'If ( $ret.ExitCode -eq 0 -or $ret.ExitCode -eq 3010 ) {',
                   '    Write-ADTLogEntry -Message "Installation finished successfully with: [$($ret.ExitCode)]" -Source ''INSTALLATION'' -Severity 2',
                   '} else {',
                   '    Write-ADTLogEntry -Message "Installation failed with Exitocde: [$($ret.ExitCode)]" -Source ''INSTALLATION'' -Severity 3',
                   '}') -join "`r`n"
    $nfRB = '#\*=+\s*MAIN-INSTALLATION BEGIN\s*=+'; $nfRE = '#\*=+\s*MAIN-INSTALLATION END\s*=+'
    $nfROut = Set-SectionBody -Template $nfReuseTpl -Begin $nfRB -End $nfRE -Body $nfIdexBody -Pre $true -DropTemplateLogs $true
    $nfRMid = [regex]::Match($nfROut, '(?s)MAIN-INSTALLATION BEGIN=+(.*?)#\*=+MAIN-INSTALLATION END').Groups[1].Value
    Assert 'NF reuse: template Start scaffold dropped'         ($nfRMid -notmatch 'Start Installation \$appVendor')
    Assert 'NF reuse: template Installation-of scaffold dropped' ($nfRMid -notmatch 'Installation of \$appVendor \$appName \$appVersion')
    Assert 'NF reuse: predecessor own log KEPT'                ($nfRMid -match 'Installation finished successfully with')
    Assert 'NF reuse: predecessor install command KEPT'       ($nfRMid -match 'Start-ADTProcess -FilePath .*\$Installer')
    Assert 'NF reuse: kept UseDialogs scaffolding'            ($nfRMid -match 'If \(\$VWG_UseDialogs\)')
    Assert 'NF reuse: no ragged whitespace-only lines'        (@(($nfRMid -split "`r?`n") | Where-Object { $_ -match '^[ \t]+$' }).Count -eq 0)
    Assert 'NF reuse: single blank gap (no 3+ newlines)'      ($nfRMid -notmatch "`r`n`r`n`r`n")
    Assert 'NF reuse: exactly the two predecessor logs'       (([regex]::Matches($nfRMid,'Write-ADTLogEntry')).Count -eq 2)
    # EMPTY body under -DropTemplateLogs -> section PRISTINE (predecessor authored nothing here; e.g. iDEX has no Repair).
    $nfREmpty = [regex]::Match((Set-SectionBody -Template $nfReuseTpl -Begin $nfRB -End $nfRE -Body '' -Pre $true -DropTemplateLogs $true), '(?s)MAIN-INSTALLATION BEGIN=+(.*?)#\*=+MAIN-INSTALLATION END').Groups[1].Value
    Assert 'NF reuse: EMPTY body keeps template scaffold'     (($nfREmpty -match 'Start Installation \$appVendor') -and ($nfREmpty -match 'Installation of \$appVendor \$appName \$appVersion'))
    # bare command under -DropTemplateLogs -> scaffold dropped, command kept (use whatever predecessor has, even with no log).
    $nfRBare = [regex]::Match((Set-SectionBody -Template $nfReuseTpl -Begin $nfRB -End $nfRE -Body 'Start-ADTMsiProcess -Action ''Install'' -FilePath "x.msi"' -Pre $true -DropTemplateLogs $true), '(?s)MAIN-INSTALLATION BEGIN=+(.*?)#\*=+MAIN-INSTALLATION END').Groups[1].Value
    Assert 'NF reuse: bare command kept, scaffold dropped'    (($nfRBare -match 'Start-ADTMsiProcess') -and ($nfRBare -notmatch '\$appVendor \$appName \$appVersion'))
    # NOT reuse (DropTemplateLogs=$false) + bare command -> old behaviour: template scaffold KEPT (fresh path untouched).
    $nfRKeep = Set-SectionBody -Template $nfReuseTpl -Begin $nfRB -End $nfRE -Body 'Start-ADTMsiProcess -Action ''Install'' -FilePath "x.msi"' -Pre $true -DropTemplateLogs $false
    Assert 'NF reuse: NOT-reuse keeps template scaffold'      ($nfRKeep -match 'Start Installation \$appVendor')
} finally { $script:Settings = $__saved }
# F25/F34: MTB loose-files path stays on Program Files + Expand-MTBZipFile (brand isolation) - checked with MTB settings
$__savedMtb = $script:Settings
$script:Settings = @{ Brand = @{ Name='MTB' } }
try {
    $nfMtbLz = New-StandardCommands -NewPkg @{ InstallerMode='LooseFiles'; AppName='App'; Version='1.0'; Arch='x64'; Vendor='Acme'; FullName='Acme_App_x64_1.0-0001_MUL'; CreateArp=$true }
    Assert "NF F25: MTB keeps Expand-MTBZipFile + Program Files" (($nfMtbLz.MainInstall -match 'Expand-MTBZipFile ') -and ($nfMtbLz.MainInstall -match '\$envProgramFiles\\Acme\\App') -and ($nfMtbLz.MainInstall -notmatch '\$envTemp'))
    # env: MTB converts Set-EnvironmentVariable -> Set-ADTEnvironmentVariable (-Variable/-Value); GPF-only Remove-BrandingREG block must NOT touch MTB
    Assert "NF env: MTB Set-EnvironmentVariable -> Set-ADTEnvironmentVariable" ((Convert-V3ToV4Content -Content 'Set-EnvironmentVariable -EnvironmentVariable "X" -EnvironmentValue "Y"') -match 'Set-ADTEnvironmentVariable')
} finally { $script:Settings = $__savedMtb }

# ---- 30th-July findings (GPF) --------------------------------------------------------------------------------------
$__savedFj = $script:Settings; $script:Settings = @{ Brand = @{ Name = 'GPF'; Convert = @{ MtbMappings = $false } } }
try {
    # #4/#5: external Copy-ADTFile/Folder gets ONE Test-Path guard; a copy already inside an outer Test-Path for the same
    # source is NOT double-guarded; package-payload copies stay bare.
    $fjA = Format-OutputScript -Text '        Copy-ADTFile -Path "$envProgramFilesX86\Java\jre8\bin\java.exe" -Destination "d"'
    Assert 'FJ#4: bare external file copy IS guarded'      ($fjA -match 'if \(Test-Path -Path "\$envProgramFilesX86\\Java\\jre8\\bin\\java\.exe"\) \{ Copy-ADTFile')
    $fjB = Format-OutputScript -Text ("        If(Test-Path -Path `"`$envProgramFilesX86\Java\jre8\bin\java.exe`")`r`n        {`r`n            Copy-ADTFile -Path `"`$envProgramFilesX86\Java\jre8\bin\java.exe`" -Destination `"d`"`r`n        }")
    Assert 'FJ#4: copy already inside outer Test-Path NOT re-wrapped' ((([regex]::Matches($fjB,'Test-Path')).Count) -eq 1)
    $fjC = Format-OutputScript -Text '        Copy-ADTFolder -Path "$envAppData\Vendor\cfg" -Destination "d"'
    Assert 'FJ#5: external Copy-ADTFolder IS guarded'      ($fjC -match 'if \(Test-Path -Path "\$envAppData\\Vendor\\cfg"\) \{ Copy-ADTFolder')
    $fjD = Format-OutputScript -Text '        Copy-ADTFile -Path "$($adtSession.DirFiles)\app.exe" -Destination "d"'
    Assert 'FJ#4: package-payload copy NOT guarded'        ($fjD -notmatch 'if \(Test-Path')
    # brand resolver + brand-gated rules
    Assert 'FJ brand: explicit TargetBrand wins'   ((Get-GpfTargetBrand -NewPkg @{TargetBrand='G1V'}) -eq 'G1V')
    Assert 'FJ brand: INA_ prefix auto-detected'   ((Get-GpfTargetBrand -NewPkg @{FullName='INA_A_B_x64_1-0001_MUL'}) -eq 'INA')
    Assert 'FJ brand: default VWG'                 ((Get-GpfTargetBrand -NewPkg @{FullName='A_B_x64_1-0001_MUL'}) -eq 'VWG')
    # #13 InstallTitle
    Assert 'FJ#13: VW vendor -> Volkswagen'        ((Get-GpfInstallTitle -NewPkg @{Vendor='Audi';AppName='MyApp';Version='1.0'} -Brand 'G1V') -eq 'Volkswagen MyApp 1.0')
    Assert 'FJ#13: non-VW keeps vendor'            ((Get-GpfInstallTitle -NewPkg @{Vendor='Adobe';AppName='Reader';Version='23'} -Brand 'VWG') -eq 'Adobe Reader 23')
    Assert 'FJ#13: Vendor==AppName not repeated'   ((Get-GpfInstallTitle -NewPkg @{Vendor='Freia';AppName='Freia';Version='9.1'} -Brand 'VWG') -eq 'Freia 9.1')
    # #16 ProcToClose -> ProcToCloseNonUI (Audi only)
    $fjWrap = "`t[string[]] `$Global:VWG_ProcToClose`t= @('app.exe')`r`n`t[string[]] `$Global:VWG_ProcToCloseNonUI`t= @()"
    $fjIna = Set-GpfProcToCloseNonUI -Text $fjWrap -Brand 'INA'
    Assert 'FJ#16: INA ProcToClose -> NonUI'       (($fjIna -match "VWG_ProcToCloseNonUI\s*=\s*@\('app\.exe'\)") -and ($fjIna -match "VWG_ProcToClose\s*=\s*@\(\)"))
    Assert 'FJ#16: non-Audi unchanged'             ((Set-GpfProcToCloseNonUI -Text $fjWrap -Brand 'VWG') -eq $fjWrap)
    # #14 34-char length
    Assert 'FJ#14: name length sum'                ((Get-GpfVwgNameLength -NewPkg @{Vendor='AB';AppName='CD';Version='1';Lang='MUL'}) -eq 8)
    # #8 branding guard matches predecessor
    $fjTpl = "#*====================================POST-UNINSTALLATION BEGIN====`r`n    `$flag = `$true`r`n    ## Branding Uninstall`r`n    Remove-Branding`r`n#*====================================POST-UNINSTALLATION END===="
    Assert 'FJ#8: predecessor bare -> NOT wrapped'  ((Set-GpfFlagGuardedBranding -Text $fjTpl -Model @{ RawV4Content = "## Branding Uninstall`r`nRemove-Branding" }) -notmatch '(?is)If\s*\(\s*\$flag\s*\)\s*\{[^}]*Remove-Branding')
    Assert 'FJ#8: predecessor guarded -> wrapped'   ((Set-GpfFlagGuardedBranding -Text $fjTpl -Model @{ RawV4Content = "If (`$flag) { Remove-Branding }" }) -match '(?is)If\s*\(\s*\$flag\s*\)\s*\{[^}]*Remove-Branding')
    # #10: GPF custom functions from the v4 Extensions module PASS THROUGH the converter unchanged (Add-UGPermission is
    # defined in v4 so it is preserved, not rewritten to Set-ADTItemPermission); the one intended rename still happens.
    Assert 'FJ#10: Add-UGPermission preserved (v4 native)'  ((Convert-V3ToV4Content -Content "Add-UGPermission -Path `"`$envProgramData\App`" -Modify") -match '(?im)^\s*Add-UGPermission\b' -and (Convert-V3ToV4Content -Content "Add-UGPermission -Path `"x`" -Modify") -notmatch 'Set-ADTItemPermission')
    Assert 'FJ#10: no "unusual shape" warning emitted'      ((Convert-V3ToV4Content -Content "Add-UGPermission -weird") -notmatch 'unusual shape')
    $fjSb = "$(Convert-V3ToV4Content -Content 'Set-Branding -Name X')".Trim()
    $fjIc = "$(Convert-V3ToV4Content -Content 'Import-Certificates -Path X')".Trim()
    Assert 'FJ#10: Set-Branding passes through'      ($fjSb -eq 'Set-Branding -Name X')
    Assert 'FJ#10: Import-Certificates passes through' ($fjIc -eq 'Import-Certificates -Path X')
    $fjRb = "$(Convert-V3ToV4Content -Content 'Remove-BrandingREG -Name X')".Trim()
    Assert 'FJ#10: Remove-BrandingREG -> Remove-Branding' ($fjRb -eq 'Remove-Branding -Name X')
    # Point1: leading tabs -> spaces (packager machines have no Invoke-Formatter); here-string interiors untouched.
    Assert 'FJ-indent: leading TAB+3sp -> 7 spaces'  ((Convert-LeadingTabsToSpaces -Text "`t   Start-ADTProcess") -eq ('       ' + 'Start-ADTProcess'))
    Assert 'FJ-indent: command + tab-log align'      ($(($z = Convert-LeadingTabsToSpaces -Text ("       cmd`r`n`t   log") -split "`r?`n"); ([regex]::Match($z[0],'^ *').Length) -eq ([regex]::Match($z[1],'^ *').Length)))
    Assert 'FJ-indent: here-string interior tab kept' ((Convert-LeadingTabsToSpaces -Text "`$x = @`"`r`n`tinner`r`n`"@") -match "(?m)^\tinner\r?$")
    # Point1b: the "…is successful." scaffold log aligns to the install command's indent (a changed template pushed it right).
    $fjAlign = Align-GpfScaffoldLogs -Text ("Write-ADTLogEntry -Message 'Start Installation A B 1.0' -Severity 2 -Source `$adtSession.DeployAppScriptFriendlyName`r`n`r`nStart-ADTMsiProcess -Action 'Install' -FilePath 'x.msi'`r`n`r`n    Write-ADTLogEntry -Message 'Installation of A B 1.0 is successful.' -Severity 2 -Source `$adtSession.DeployAppScriptFriendlyName")
    $fjAl = $fjAlign -split "`r?`n"
    Assert 'FJ-align: successful-log matches command indent' (([regex]::Match(($fjAl | Where-Object { $_ -match 'is successful' })[0],'^ *').Length) -eq ([regex]::Match(($fjAl | Where-Object { $_ -match 'Start-ADTMsiProcess' })[0],'^ *').Length))
    Assert 'FJ-align: non-template log NOT touched' ((Align-GpfScaffoldLogs -Text "        Write-ADTLogEntry -Message 'Installation finished with' -Source 'INSTALLATION'") -eq "        Write-ADTLogEntry -Message 'Installation finished with' -Source 'INSTALLATION'")
    # Point2: heads-up notices channel works (reset/add/get).
    Reset-GpfNotices; Add-GpfNotice 'test notice'
    Assert 'FJ-notice: add + get'                     ((@(Get-GpfNotices)).Count -eq 1 -and (@(Get-GpfNotices))[0] -eq 'test notice')
    Reset-GpfNotices
    Assert 'FJ-notice: reset clears'                  ((@(Get-GpfNotices)).Count -eq 0)
    # Point2b: only MUST-SEE review items are promoted to the heads-up popup; nice-to-know ones are not.
    Assert 'FJ-crit: "## REVIEW:" IS critical'        (Test-GpfCriticalReview -Item '## REVIEW: no UNINSTALL command for X. Add the uninstaller path.')
    Assert 'FJ-crit: name-detection IS critical'      (Test-GpfCriticalReview -Item "detection is by NAME - confirm it matches the installed app's real ARP DisplayName")
    Assert 'FJ-crit: source-type IS critical'         (Test-GpfCriticalReview -Item 'Source TYPE changed - predecessor was an MSI, your source is a zip.')
    Assert 'FJ-crit: snapshot-added NOT critical'     (-not (Test-GpfCriticalReview -Item "Review the 3 '# [snapshot-added]' cleanup lines - confirm each removal is wanted."))
    Assert 'FJ-crit: MST note NOT critical'           (-not (Test-GpfCriticalReview -Item 'Predecessor MST also modified -> Component table (not auto-applied)'))
    # Add-CriticalNoticesFromScript promotes a "## REVIEW:" line from the built script into the notices channel.
    Reset-GpfNotices
    Add-CriticalNoticesFromScript -ScriptText "Start-ADTProcess -FilePath x`r`n## REVIEW: no UNINSTALL command for 'App'. Add the uninstaller path + silent switches." -IsPredecessor $false -NewProductCode ''
    Assert 'FJ-crit: REVIEW line promoted to notices'  ((@(Get-GpfNotices) | Where-Object { $_ -match 'no UNINSTALL command' }).Count -ge 1)
    Reset-GpfNotices
} finally { $script:Settings = $__savedFj }

Write-Host ""
if ($fail -eq 0) { Write-Host "ALL TESTS PASSED" -ForegroundColor Green; exit 0 }   # explicit: a native command's exit code (robocopy's benign 1 in the self-stage test) must not leak as OUR exit code
else { Write-Host "$fail TEST(S) FAILED" -ForegroundColor Red; exit 1 }
