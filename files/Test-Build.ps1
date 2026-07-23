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
. (Resolve-Module 'PSADT_V3toV4_Mappings.ps1')
Initialize-Log

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
# ---- IMMEDIATE-ONLY policy (team: uninstall ONLY the immediate predecessor; DROP predecessor-of-predecessor) ----
Assert "ONE predecessor uninstall block (immediate only)" ((([regex]::Matches($out,'Get-ADTApplication')).Count) -eq 1)
Assert "pred-of-pred block (1.1.0.0/{1111}) DROPPED"      ((-not ($out -match '1\.1\.0\.0')) -and (-not ($out -match '11111111-1111')))
Assert "immediate block targets predecessor PC {2222}"   ($out -match '22222222-2222')
Assert "immediate block has predecessor branding key"    ($out -match 'CM\\Acme_AcmeApp_x64_1\.2\.3\.4-0001_de-DE')
# ---- OPT-OUT: unchecking "add uninstall previous" skips the generated immediate block; pred-of-pred stays dropped ----
$outNo = Build-PredecessorScript -Model $model -NewPkg $newPkg -Template $tpl -AddUninstallPrevious $false
Assert "opt-out: pred-of-pred STILL dropped (1.1.0.0/{1111} absent)" ((-not ($outNo -match '1\.1\.0\.0')) -and (-not ($outNo -match '11111111-1111')))
Assert "opt-out adds NO generated block ({2222} absent)"             ($outNo -notmatch '22222222-2222')
Assert "opt-out leaves ZERO uninstall-previous blocks"               ((([regex]::Matches($outNo,'Get-ADTApplication')).Count) -eq 0)

# ---- Split-ExistingUninstallBlocks KEEP-checks: only a genuine predecessor-uninstall block is excised; dependency
#      gates (negated), if/else logic, and DIFFERENT components (VC++ etc.) are KEPT. (DSA_PRODISAuthoring CodeMeter bug.)
$sxId = @{ Vendor='DSA'; AppName='PRODISAuthoring'; FullName='DSA_PRODISAuthoring_x64_5.8.9-0001_en-US' }
# (a) NEGATED dependency gate with an else -> KEPT intact (not excised), no dangling else.
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
Assert "split: excises ONLY the real predecessor block"  ($sxR.Blocks.Count -eq 1)
Assert "split: CodeMeter dependency gate KEPT in body"   (($sxR.Body -match "if\(!\(Get-InstalledApplication") -and ($sxR.Body -match "Codemeter found"))
Assert "split: kept gate body parses (no dangling else)" ($(($pe2=$null);[void][System.Management.Automation.Language.Parser]::ParseInput($sxR.Body,[ref]$null,[ref]$pe2);$pe2.Count -eq 0))
# (b) POSITIVE block for a DIFFERENT component (VC++, name mismatch, no branding key) -> KEPT.
$sxVc = "If (Get-ADTApplication -Name 'Microsoft Visual C++ 2019 Redistributable') { Remove-MTBDetectionKey `"x`" }"
Assert "split: different component (VC++) KEPT"          ((Split-ExistingUninstallBlocks -Code $sxVc -Identity $sxId).Blocks.Count -eq 0)
# (c) POSITIVE block whose -Name FUZZY-matches ours (dot difference) -> EXCISED.
$sxOurs = "If (Get-ADTApplication -Name 'PRODIS.Authoring') { Remove-MTBDetectionKey `"y`" }"
Assert "split: our app (fuzzy name match) EXCISED"      ((Split-ExistingUninstallBlocks -Code $sxOurs -Identity $sxId).Blocks.Count -eq 1)
# (d) POSITIVE block with an else (even matching our app) -> KEPT (conditional logic).
$sxElse = "If (Get-ADTApplication -Name 'PRODISAuthoring') { Remove-MTBDetectionKey `"z`" } else { Write-ADTLogEntry -Message 'noop' }"
Assert "split: if/else block KEPT even when app matches" ((Split-ExistingUninstallBlocks -Code $sxElse -Identity $sxId).Blocks.Count -eq 0)
# (e) ProductCode-only block (no -Name) -> still EXCISABLE (version-specific real uninstall).
$sxPc = "If (Get-ADTApplication -ProductCode '{11111111-1111-1111-1111-111111111111}') { Start-ADTMsiProcess -Action Uninstall -ProductCode '{11111111-1111-1111-1111-111111111111}' }"
Assert "split: ProductCode-only block EXCISED"          ((Split-ExistingUninstallBlocks -Code $sxPc -Identity $sxId).Blocks.Count -eq 1)

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
Assert "pred-of-pred CHECKED: 2023.1 DROPPED (immediate only)"   ((-not ($ncChecked -match 'nCode 2023\.1 64-bit')) -and (-not ($ncChecked -match '23\.1\.0\.0')))
Assert "pred-of-pred UNCHECKED: 2023.1 DROPPED"                  ((-not ($ncUnchecked -match 'nCode 2023\.1 64-bit')) -and (-not ($ncUnchecked -match '23\.1\.0\.0')))
Assert "current version ALWAYS bumped (both) -> 2026.0"   (($ncChecked -match 'nCode 2026\.0 64-bit') -and ($ncUnchecked -match 'nCode 2026\.0 64-bit'))
Assert "gated builds both parse"                          (& { $e1=$null;$e2=$null;[void][System.Management.Automation.Language.Parser]::ParseInput($ncChecked,[ref]$null,[ref]$e1);[void][System.Management.Automation.Language.Parser]::ParseInput($ncUnchecked,[ref]$null,[ref]$e2); (-not $e1.Count) -and (-not $e2.Count) })

# ---- MAN round-2: env-var params, Expand-MTBZipFile, active Set-MTBReboot preserved ----
$cEnv = Convert-V3ToV4Content -Content 'Set-EnvironmentVariable -EnvironmentVariable "PVIEW" -EnvironmentValue "1"'
Assert "env: -EnvironmentVariable/-EnvironmentValue -> -Variable/-Value" (($cEnv -match 'Set-ADTEnvironmentVariable\s+-Variable\s+"PVIEW"\s+-Value\s+"1"') -and ($cEnv -notmatch '-EnvironmentVariable'))
Assert "zip: Expand-ZipFile -> Expand-MTBZipFile"                        ((Convert-V3ToV4Content -Content 'Expand-ZipFile -Path "a.zip" -Destination "d"') -match 'Expand-MTBZipFile ')
Assert "reboot: ACTIVE Set-MTBReboot kept, #commented stripped"         (((Strip-Boilerplate -Body 'Set-MTBReboot') -match 'Set-MTBReboot') -and ((Strip-Boilerplate -Body '#Set-MTBReboot') -notmatch 'Set-MTBReboot'))

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
# v3 REAL case: the CUSTOM-VARIABLES SoftIdent is DOUBLE-quoted with the $($VWG_CurrentRegWOW) token and NO literal
# token definition (defined at runtime in the extensions), token NOT followed by an explicit '\'. Old reader (single
# quotes only) MISSED this -> 32-bit box wasn't set from it. Now: double-quoted read + token -> 32-bit + clean key.
$v3dq = Join-Path $env:TEMP ('pbv3dq_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item (Join-Path $v3dq 'Content') -ItemType Directory -Force | Out-Null
@'
[string]$appVendor = 'CUBISCAN'
[string]$appName = 'QbitDB'
[string]$appArch = 'x86'
[string]$appVersion = '02.14.0004'
[string]$appRevision = '0001'
[string]$appLang = 'en-US'
[string]$VWG_SoftIdent = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Qbit-DB [DisplayVersion=02.14.0004]'
#*====================================CUSTOM APPLICATION VARIABLES BEGIN===
[string]$VWG_SoftIdent   =  "HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)Microsoft\Windows\CurrentVersion\Uninstall\Qbit-DB [DisplayVersion=02.14.0004]"
'@ | Set-Content (Join-Path $v3dq 'Content\Deploy-Application.ps1') -Encoding UTF8
$v3d = Get-SccmFieldsFromPackage -PackagePath $v3dq
Assert "v3 double-quoted token: 32-bit box ticked"          ($v3d.Is32Bit -eq $true)
Assert "v3 double-quoted token: key clean (no WoW/no token)" ($v3d.UninstallKey -eq 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Qbit-DB')
Assert "v3 double-quoted token: version parsed"             ($v3d.DetectVersion -eq '02.14.0004')
# ALL fields double-quoted (both quote styles must read) + double-quoted -ProductCode in the uninstall command.
@'
[string]$appVendor = "CUBISCAN"
[string]$appName = "QbitDB"
[string]$appArch = "x86"
[string]$appVersion = "02.14.0004"
[string]$appRevision = "0001"
[string]$appLang = "en-US"
[string]$VWG_CurrentRegWOW = "WoW6432Node\"
[string]$VWG_SoftIdent = "HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)Microsoft\Windows\CurrentVersion\Uninstall\Qbit-DB [DisplayVersion=02.14.0004]"
'@ | Set-Content (Join-Path $v3dq 'Content\Deploy-Application.ps1') -Encoding UTF8
$v3q = Get-SccmFieldsFromPackage -PackagePath $v3dq
Assert "all-double-quoted fields read (vendor/app/arch/ver)"  ($v3q.Publisher -eq 'CUBISCAN' -and $v3q.ProductName -eq 'QbitDB' -and $v3q.Arch -eq 'x86' -and $v3q.Version -eq '02.14.0004')
Assert "all-double-quoted: token still -> 32-bit + clean key" ($v3q.Is32Bit -eq $true -and $v3q.UninstallKey -eq 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Qbit-DB')
Remove-Item $v3dq -Recurse -Force -ErrorAction SilentlyContinue
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

# ---- Intune extra shield: match by uninstall detection (key path incl. 32/64-bit + version / ProductCode) ----
$shieldFields = @{ UninstallKey='SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{c157798c-9519-4e56-98d9-f696f78f4a61}'; Is32Bit=$false; DetectVersion='14.51.36231'; ProductCode='{c157798c-9519-4e56-98d9-f696f78f4a61}'; Version='14.51.36231' }
$shieldSig = Get-IntuneUninstallSignature -Fields $shieldFields
function _RegRule($kp,$ver,$b32){ @{ '@odata.type'='#microsoft.graph.win32LobAppRegistryDetection'; keyPath=$kp; valueName='DisplayVersion'; detectionType='version'; operator='greaterThanOrEqual'; detectionValue=$ver; check32BitOn64System=$b32 } }
$_brand = @{ '@odata.type'='#microsoft.graph.win32LobAppRegistryDetection'; keyPath='HKEY_LOCAL_MACHINE\SOFTWARE\VWG\CM\Other_Name_x64_14.51.36231-0001_MUL'; valueName='Revision'; detectionValue='0001' }
Assert "shield sig: HKLM key + version"          ($shieldSig.KeyPath -match 'Uninstall\\\{c157798c' -and $shieldSig.Version -eq '14.51.36231')
Assert "shield: same uninstall, NO branding->hit" ((Test-IntuneAppMatchesUninstall -DetectionRules @((_RegRule $shieldSig.KeyPath '14.51.36231' $false)) -Sig $shieldSig).Match -and -not (Test-IntuneAppMatchesUninstall -DetectionRules @((_RegRule $shieldSig.KeyPath '14.51.36231' $false)) -Sig $shieldSig).Branded)
$_bRes = Test-IntuneAppMatchesUninstall -DetectionRules @($_brand,(_RegRule $shieldSig.KeyPath '14.51.36231' $false)) -Sig $shieldSig
Assert "shield: same uninstall + branding->skip"  ($_bRes.Match -and $_bRes.Branded)
Assert "shield: different version->no match"       (-not (Test-IntuneAppMatchesUninstall -DetectionRules @((_RegRule $shieldSig.KeyPath '9.9.9' $false)) -Sig $shieldSig).Match)
Assert "shield: different bitness->no match"        (-not (Test-IntuneAppMatchesUninstall -DetectionRules @((_RegRule $shieldSig.KeyPath '14.51.36231' $true)) -Sig $shieldSig).Match)
Assert "shield: ProductCode detection->match"       (Test-IntuneAppMatchesUninstall -DetectionRules @(@{ '@odata.type'='#microsoft.graph.win32LobAppProductCodeDetection'; productCode='{c157798c-9519-4e56-98d9-f696f78f4a61}' }) -Sig $shieldSig).Match
Assert "shield: unrelated app->no match"            (-not (Test-IntuneAppMatchesUninstall -DetectionRules @((_RegRule 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{11111111-1111-1111-1111-111111111111}' '1.0' $false)) -Sig $shieldSig).Match)
# lifecycle parse from the app notes JSON
Assert "shield: lifecycle RETIRED from notes json" ((Get-IntuneAppLifecycle -App @{ notes='{ "managed": true, "status": "OK", "lifecycle": "RETIRED" }' }) -eq 'RETIRED')
Assert "shield: lifecycle LIVE from notes json"    ((Get-IntuneAppLifecycle -App @{ notes='{"lifecycle":"LIVE"}' }) -eq 'LIVE')
Assert "shield: lifecycle unknown when absent"     ((Get-IntuneAppLifecycle -App @{ notes='Created by Package Builder.' }) -eq 'unknown')

# ---- Intune content-root resolver (v3/v4, subfolder nesting, no-PSADT) + v3 ServiceUI staging ----
$ivr = Join-Path $env:TEMP ('pb_ivroot_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
try {
    $v4 = Join-Path $ivr 'v4\Content'; New-Item $v4 -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $v4 'Invoke-AppDeployToolkit.exe') 'x'
    $rv4 = Resolve-IntuneContentRoot -ContentFolder $v4
    Assert "intune root: v4 flat -> gen v4 + Content root"     ($rv4.Generation -eq 'v4' -and $rv4.Root -eq $v4 -and $rv4.SetupFile -eq 'Invoke-AppDeployToolkit.exe')
    # v3 nested in a subfolder (Content\MUL_x64_0001\Deploy-Application.ps1) -> wrap the SUBFOLDER
    $sub = Join-Path $ivr 'v3\Content\MUL_x64_0001'; New-Item $sub -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $sub 'Deploy-Application.ps1') '# v3'
    $rv3 = Resolve-IntuneContentRoot -ContentFolder (Join-Path $ivr 'v3\Content')
    Assert "intune root: v3 subfolder -> wraps the subfolder"  ($rv3.Generation -eq 'v3' -and $rv3.Root -eq $sub -and $rv3.SetupFile -eq 'Deploy-Application.exe')
    Initialize-IntuneV3Content -ContentRoot $rv3.Root
    Assert "intune v3: ServiceUI staged next to launcher"      (Test-Path (Join-Path $sub 'ServiceUI.exe'))
    # bare setup, no PSADT launcher -> null (caller tells the user to integrate manually)
    $raw = Join-Path $ivr 'raw\Content'; New-Item $raw -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $raw 'setup.exe') 'x'
    Assert "intune root: no PSADT launcher -> null"            ($null -eq (Resolve-IntuneContentRoot -ContentFolder $raw))
} finally { Remove-Item $ivr -Recurse -Force -ErrorAction SilentlyContinue }
# v3 Intune commands are ServiceUI-wrapped (SCCM field is Deploy-Application direct; Intune must differ)
Assert "intune v3 cmd: wraps (.\ServiceUI, unquoted, exact)" ((ConvertTo-IntuneV3Command '"Deploy-Application.exe" Install') -eq '.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Install')
Assert "intune v3 cmd: unquoted base wraps exactly"      ((ConvertTo-IntuneV3Command 'Deploy-Application.exe Uninstall') -eq '.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Uninstall')
Assert "intune v3 cmd: no double-wrap (.\ServiceUI)"     ((ConvertTo-IntuneV3Command '.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Uninstall') -eq '.\ServiceUI.exe -process:explorer.exe Deploy-Application.exe Uninstall')
Assert "intune v3 cmd: empty stays empty"                ((ConvertTo-IntuneV3Command '') -eq '')
# .intunewin build keeps a LOCAL copy of the wrapped content + a manifest; source package is left untouched
if (Test-Path '.\lib\IntuneWinAppUtil.exe') {
    $iwp = Join-Path $env:TEMP ('pb_iwkeep_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        $isub = Join-Path $iwp 'Content\MUL_x64_0001'; New-Item $isub -ItemType Directory -Force | Out-Null
        Set-Content (Join-Path $isub 'Deploy-Application.exe') 'x'; New-Item (Join-Path $isub 'Files') -ItemType Directory -Force | Out-Null
        Set-Content (Join-Path $isub 'Files\payload.msi') 'x'
        $ifull = 'Test_IwKeep_x64_1.0-0001_MUL'
        $iwOut = New-IntuneWinPackage -ContentFolder $isub -FullName $ifull -SetupFile 'Deploy-Application.exe' -Generation 'v3'
        $iwDir = Get-WorkPath (Join-Path 'IntuneWin' $ifull)
        Assert "intunewin: .intunewin produced + kept"     ($iwOut -and (Test-Path $iwOut))
        Assert "intunewin: wrapped content copy kept"      (Test-Path (Join-Path $iwDir 'Content\Files\payload.msi'))
        Assert "intunewin: v3 ServiceUI staged in copy"    (Test-Path (Join-Path $iwDir 'Content\ServiceUI.exe'))
        Assert "intunewin: manifest written"               (Test-Path (Join-Path $iwDir '_IntuneWin-manifest.txt'))
        Assert "intunewin: SOURCE package left untouched"  (-not (Test-Path (Join-Path $isub 'ServiceUI.exe')))
        if (Test-Path $iwDir) { Remove-Item $iwDir -Recurse -Force -ErrorAction SilentlyContinue }
    } finally { Remove-Item $iwp -Recurse -Force -ErrorAction SilentlyContinue }
} else { Write-Host "SKIP intunewin build test (IntuneWinAppUtil.exe not under Lib)" -ForegroundColor Yellow }

# ---- Icon-readiness gate (before SCCM/Intune create + Intune update-content): convert .ico->.png (persist) or block ----
$icoTest = Join-Path $env:TEMP ('pbicon_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$realIco = Join-Path (Get-ToolRoot) 'Lib\PackageBuilder.ico'
if (Test-Path $realIco) {
    try {
        $ip1 = Join-Path $icoTest 'IcoOnly'; New-Item (Join-Path $ip1 'Icons') -ItemType Directory -Force | Out-Null
        Copy-Item $realIco (Join-Path $ip1 'Icons\App.ico') -Force
        $ir1 = Confirm-PackageIconReady -PackagePath $ip1
        Assert "icon gate: .ico-only -> ready + converted"   ($ir1.Ready -and $ir1.Converted)
        Assert "icon gate: .png PERSISTED next to the .ico"  (Test-Path (Join-Path $ip1 'Icons\App.png'))
        $ip2 = Join-Path $icoTest 'None'; New-Item (Join-Path $ip2 'Icons') -ItemType Directory -Force | Out-Null
        $ir2 = Confirm-PackageIconReady -PackagePath $ip2
        Assert "icon gate: no icon -> NOT ready (blocks)"    (-not $ir2.Ready)
        Assert "icon gate: no icon -> message tells to add .ico" ($ir2.Message.ToLower().Contains('ico'))
    } finally { Remove-Item $icoTest -Recurse -Force -ErrorAction SilentlyContinue }
} else { Write-Host "SKIP icon-gate test (PackageBuilder.ico not under Lib)" -ForegroundColor Yellow }

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
foreach ($rel in 'PackageBuilder.exe','PackageBuilder.exe.config','PackageBuilder.pak','settings.json','snippets.json','KnowledgeBase.Recommend.json',
                 'Lib\ICSharpCode.AvalonEdit.dll','Lib\PackageBuilder.ico','Lib\PSADT_Template\Content\Invoke-AppDeployToolkit.ps1',
                 'Lib\ConfigurationManagerPrelive\ConfigurationManager.psd1','Lib\PowerShell Module\MSAL.PS 4.37.0.0\MSAL.PS.psd1','Lib\IntuneWinAppUtil.exe',
                 'PsExec64.exe','Tools\extra-helper.exe') {
    $fp = Join-Path $shareD $rel; $dir = Split-Path $fp -Parent; if (-not (Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    Set-Content -LiteralPath $fp -Value 'x' -Force
}
# DEPLOYMENT REALITY: Set-ToolVisibility ships the pak Hidden+ReadOnly. Copy-IfNewer's timestamp compare used
# Get-Item WITHOUT -Force, which THROWS "cannot find path" on a Hidden file -> the self-stage crashed with a dialog
# ("...PackageBuilder.pak konnte nicht gefunden werden"). Reproduce that exact state so the fix stays locked in.
(Get-Item -LiteralPath (Join-Path $shareD 'PackageBuilder.pak') -Force).Attributes = 'Hidden, ReadOnly'
$rl = Invoke-SelfStage -Root $shareD -Local $localD -Force
Assert "self-stage: returns local exe path"             ("$rl" -eq (Join-Path $localD 'PackageBuilder.exe'))
Assert "self-stage: core exe+pak copied"                ((Test-Path (Join-Path $localD 'PackageBuilder.exe')) -and (Test-Path (Join-Path $localD 'PackageBuilder.pak')))
Assert "self-stage: HIDDEN pak copied (no 'cannot find path' crash)" (Test-Path (Join-Path $localD 'PackageBuilder.pak'))
Assert "self-stage: exe.config copied (UNC-share launcher config)"   (Test-Path (Join-Path $localD 'PackageBuilder.exe.config'))

# ---- Intune detection rules: "None (branding only)" = ONE rule, which MUST serialize as a JSON ARRAY not an object.
#      A single-element List unwrapped to a bare hashtable -> `detectionRules` became `{}` -> Graph 400
#      "Property detectionRules in payload has a value that does not match schema". ----
# Build detectionRules EXACTLY like the create body does (@()-wrapped) and assert a FLAT array of rule OBJECTS - never a
# bare object `{}` (single-rule List unwrap) and never a nested `[[{}]]` (a `,$x.ToArray()` return + the caller's @()).
$dr1 = @(Get-IntuneDetectionRules -Fields @{ BrandingKey='SOFTWARE\VWG\CM\App_x64_1.0-0001_en-US'; Revision='0001'; DetectType='None' })
$json1 = @{ detectionRules = $dr1 } | ConvertTo-Json -Depth 12
Assert "intune: branding-only = exactly 1 rule object"           (($dr1.Count -eq 1) -and ($dr1[0] -is [hashtable]) -and ("$($dr1[0]['@odata.type'])" -match 'RegistryDetection'))
Assert "intune: branding-only serialises FLAT (array of objects)" (($json1 -match '"detectionRules":\s*\[\s*\{') -and ($json1 -notmatch '"detectionRules":\s*\[\s*\['))
$dr2 = @(Get-IntuneDetectionRules -Fields @{ BrandingKey='SOFTWARE\VWG\CM\X'; Revision='0001'; DetectType='Version'; UninstallKey='SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Z'; DetectVersion='4.9.0.412'; Is32Bit=$false })
$json2 = @{ detectionRules = $dr2 } | ConvertTo-Json -Depth 12
Assert "intune: 2 rules serialise FLAT (not nested [[..]])"       (($dr2.Count -eq 2) -and ($dr2[0] -is [hashtable]) -and ($json2 -match '"detectionRules":\s*\[\s*\{') -and ($json2 -notmatch '"detectionRules":\s*\[\s*\['))
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

# ---- fuzzy predecessor matching: slight app-name variations ALSO offered (flagged Close); unrelated excluded ----
$pcf = Join-Path $env:TEMP ('pbfuzzy_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
foreach ($n in 'HBM_nCodeGlyphworks_x64_24.1.0-0001_en-US','HBM_nCodeGlyphWorx_x64_23.0.0-0001_en-US','HBM_Catman_x64_1.0.0-0001_en-US','IgorPavlov_7Zip_x64_25.01-0001_MUL') { New-Item (Join-Path $pcf $n) -ItemType Directory -Force | Out-Null }
$oldPredF = $script:Settings['PredecessorPath']
$script:Settings['PredecessorPath'] = $pcf
$fc = @(Get-PredecessorCandidates -Parsed (Parse-PackageName 'HBM_nCodeGlyphworks_x64_26.0.0.0-0001_en-US'))
if ($null -ne $oldPredF) { $script:Settings['PredecessorPath'] = $oldPredF } else { [void]$script:Settings.Remove('PredecessorPath') }
Assert "fuzzy: exact match Score 100 ranks first"       ($fc.Count -ge 1 -and $fc[0].Name -match 'nCodeGlyphworks_x64_24' -and $fc[0].Score -eq 100)
Assert "fuzzy: slight app-name variant offered (Close)" (@($fc | Where-Object { $_.Name -match 'nCodeGlyphWorx' -and $_.Close }).Count -eq 1)
Assert "fuzzy: unrelated app (Catman) NOT offered"      (-not ($fc | Where-Object { $_.Name -match 'Catman' }))
Assert "fuzzy: unrelated vendor (7Zip) NOT offered"     (-not ($fc | Where-Object { $_.Name -match '7Zip' }))
Assert "Get-NameSimilarity identical = 1"               ((Get-NameSimilarity 'reader' 'reader') -eq 1.0)
Assert "Get-NameSimilarity unrelated < 0.4"             ((Get-NameSimilarity 'sevenzip' 'firefox') -lt 0.4)
Remove-Item $pcf -Recurse -Force -ErrorAction SilentlyContinue
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
    Assert "ProcToClose array written"     ($pcOut -match "(?m)^\s*ProcToClose\s*=\s*@\('toolexe', 'helper'\)")
    Assert "ProcToBlock array written"     ($pcOut -match "(?m)^\s*ProcToBlock\s*=\s*@\('toolexe'\)")
    Assert "ProcToCloseNonUI NOT clobbered" ($pcOut -match "(?m)^\s*ProcToCloseNonUI\s*=")
    # ProcToBlock defaults to ProcToClose: when ProcToBlock is left as the template default (@()), it mirrors ProcToClose.
    $pbDefOut = Build-FreshScript -NewPkg @{ Vendor='Acme';AppName='Tool';Arch='x64';Lang='MUL';Revision='0001';Version='1.0.0';MsiFileName='t.msi';ProcToClose=@('toolexe','helper');Author='Me' } -Template $tplF
    Assert "ProcToBlock defaults to ProcToClose" ($pbDefOut -match "(?m)^\s*ProcToBlock\s*=\s*@\('toolexe', 'helper'\)")
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
# ---- Snapshot "Run installer": an .msi has NO 'runas' shell verb, so Start-Process foo.msi -Verb RunAs throws and the
#      install-for-snapshot failed for EVERY MSI. Get-InstallerRunSpec routes MSI/MSP through msiexec; an .exe launches direct.
$rsMsi = Get-InstallerRunSpec -Path 'C:\src\NessusAgent-11.2.0-x64.msi'
Assert "run-installer: MSI -> msiexec /i"    (($rsMsi.File -match '(?i)\\msiexec\.exe$') -and ($rsMsi.Args -match '(?i)^/i\s+".*NessusAgent-11\.2\.0-x64\.msi"$'))
$rsMsp = Get-InstallerRunSpec -Path 'C:\src\hotfix.msp'
Assert "run-installer: MSP -> msiexec /p"    (($rsMsp.File -match '(?i)\\msiexec\.exe$') -and ($rsMsp.Args -match '(?i)^/p\s'))
$rsExe = Get-InstallerRunSpec -Path 'C:\src\Setup.exe'
Assert "run-installer: EXE launches directly" (($rsExe.File -eq 'C:\src\Setup.exe') -and (-not "$($rsExe.Args)".Trim()))
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
} finally { Remove-Item $icRoot -Recurse -Force -ErrorAction SilentlyContinue }

# ---- Snapshot clarity: (1) C:\Windows\INF + .pnf are OS driver-cache NOISE (were leaking into Files), (2) the registry
#      report now shows each KEY's value NAME = DATA [type] (was key-only - "unclear what name/value"). ----
Assert "snap-noise: C:\Windows\INF filtered"     (Test-IsFileNoise 'C:\Windows\INF\oem12.inf')
Assert "snap-noise: .pnf filtered"               (Test-IsFileNoise 'C:\Windows\INF\oem12.pnf')
Assert "snap-noise: real app file NOT filtered"  (-not (Test-IsFileNoise 'C:\Program Files\MyApp\app.exe'))
$snRd = [pscustomobject]@{ New=@([pscustomobject]@{ Path='HKLM\SOFTWARE\MyApp'; Change='new'; IsApp=$true; Values=@([pscustomobject]@{ Name='Server'; Change='added'; New='https://x'; Value='https://x'; Type='String' }) }); Deleted=@(); NoiseItems=@(); NoiseCount=0; ModifiedCount=0; DeletedCount=0; InstalledBytes=0; Total=1 }
$snFd = [pscustomobject]@{ New=@(); Deleted=@(); NoiseItems=@(); NoiseCount=0; ModifiedCount=0; DeletedCount=0; InstalledBytes=0; Total=0 }
$snRep = Get-SnapshotReportText -Diff @{} -FileDiff $snFd -RegDiff $snRd -EnvChanges @() -Un $null -AppTokens @('myapp')
Assert "snap-report: registry shows the KEY"          ($snRep -match 'HKLM\\SOFTWARE\\MyApp')
Assert "snap-report: registry shows value NAME=DATA"  (($snRep -match '(?m)Server = https://x') -and ($snRep -match '\[String\]'))
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
# Execute-MSI / Execute-Process param renames (from the PSADT v4 compat wrapper aliases): AddParameters->
# AdditionalArgumentList, Parameters/Arguments->ArgumentList, SecureParameters->SecureArgumentList, Transform->
# Transforms, Patch->Patches, LogName->LogFileName - no partial-match corruption (-Parameters not inside -AddParameters).
$msiC = Convert-V3ToV4Content -Content "Execute-MSI -Action 'Install' -Path 'a.msi' -Transform 'a.mst' -Parameters 'X=1' -AddParameters 'ALLUSERS=1' -SecureParameters -Patch 'p.msp' -LogName 'log'"
Assert "Execute-MSI -AddParameters -> -AdditionalArgumentList" ($msiC -match "-AdditionalArgumentList 'ALLUSERS=1'")
Assert "Execute-MSI -Parameters -> -ArgumentList"           ($msiC -match "-ArgumentList 'X=1'")
Assert "Execute-MSI -SecureParameters -> -SecureArgumentList" (($msiC -match '-SecureArgumentList') -and ($msiC -notmatch '-SecureParameters'))
Assert "Execute-MSI -Patch -> -Patches"                     (($msiC -match "-Patches 'p.msp'") -and ($msiC -notmatch '(?<!\w)-Patch '))
Assert "Execute-MSI -LogName -> -LogFileName"               (($msiC -match "-LogFileName 'log'") -and ($msiC -notmatch '(?<!\w)-LogName '))
Assert "Execute-MSI: no leftover v3 param names"            ($msiC -notmatch '(?<!\w)-(AddParameters|Parameters|SecureParameters|LogName)(?![A-Za-z])')
$epC = Convert-V3ToV4Content -Content "Execute-Process -Path 'setup.exe' -Arguments '/S' -SecureParameters"
Assert "Execute-Process -Arguments -> -ArgumentList"        ($epC -match "-ArgumentList '/S'")
Assert "Execute-Process -SecureParameters -> -SecureArgumentList" ($epC -match '-SecureArgumentList')

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
# -IfEmpty -> the team house style (QA rule from Vithal): nested Test-Path -> (Get-ChildItem -Path -Force|Measure-Object).Count -eq 0, -Path.
$cIfe = Convert-V3ToV4Content -Content 'Remove-Folder -Path "$envProgramFiles\App" -IfEmpty'
Assert "-IfEmpty -> nested Test-Path/Measure block"     (($cIfe -match 'If \(Test-Path -Path') -and ($cIfe -match '\(Get-ChildItem -Path .* -Force \| Measure-Object\)\.Count -eq 0') -and ($cIfe -match 'Remove-ADTFolder -Path') -and ($cIfe -notmatch '-IfEmpty') -and ($cIfe -notmatch 'LiteralPath'))
Assert "-IfEmpty nested output parses"                  ($(($pfe=$null);[void][System.Management.Automation.Language.Parser]::ParseInput($cIfe,[ref]$null,[ref]$pfe);$pfe.Count -eq 0))
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
# AUDIT GUARD: every v3->v4 mapper TARGET must be a REAL v4 function (PSADT export OR team MTB extension) - else the
# converter would emit a call to a non-existent cmdlet. Reads the live template manifest + extensions module.
$tplRoot0 = Split-Path (Resolve-Module 'PSADT_V3toV4_Mappings.ps1') -Parent
$tplC = Join-Path $tplRoot0 'Lib\PSADT_Template\Content'                                        # consolidated layout (template under Lib\)
if (-not (Test-Path $tplC)) { $tplC = Join-Path $tplRoot0 'PSADT_Template\Content' }            # legacy root layout
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

Write-Host ""
if ($fail -eq 0) { Write-Host "ALL TESTS PASSED" -ForegroundColor Green; exit 0 }   # explicit: a native command's exit code (robocopy's benign 1 in the self-stage test) must not leak as OUR exit code
else { Write-Host "$fail TEST(S) FAILED" -ForegroundColor Red; exit 1 }
