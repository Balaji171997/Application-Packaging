##############################################################################################################
# PSADT_V3toV4_Mappings.ps1
# 
# Comprehensive mapping library for converting PSADT v3 (Deploy-Application.ps1) syntax
# to PSADT v4 (Invoke-AppDeployToolkit.ps1 / PSAppDeployToolkit module) syntax.
#
# Usage: dot-source this file, then call Convert-V3ToV4Content -Content $scriptContent
#
# Maintained as a separate file so the mapping tables can be updated without touching
# the main tool code. Add new entries to the hashtables as needed.
#
# Last updated: 2026-04-23
##############################################################################################################

# ==============================================================================
# LAYER 1: Function Name Mappings (v3 name → v4 name + parameter renames)
# ==============================================================================
# Each entry: OldFunctionName = @{ NewName = 'NewFunctionName'; Params = @{ '-OldParam' = '-NewParam' } }
# Params is optional - omit if no parameter renames needed for that function.

$script:V3ToV4Functions = [ordered]@{

    # -- Process / Execution --
    # v3->v4 parameter renames below are taken from the PSADT v4 compatibility wrappers' [Alias(...)] declarations
    # (Frontend\v3\AppDeployToolkit\AppDeployToolkitMain.ps1) - the definitive old->new mapping, not a guess.
    'Execute-Process'               = @{
        NewName = 'Start-ADTProcess'
        Params  = @{ '-Path' = '-FilePath'; '-Parameters' = '-ArgumentList'; '-Arguments' = '-ArgumentList'; '-SecureParameters' = '-SecureArgumentList' }
    }
    'Execute-ProcessAsUser'         = @{
        NewName = 'Start-ADTProcessAsUser'
        Params  = @{ '-Path' = '-FilePath'; '-Parameters' = '-ArgumentList'; '-Arguments' = '-ArgumentList'; '-SecureParameters' = '-SecureArgumentList' }
    }
    'Execute-MSI'                   = @{
        NewName = 'Start-ADTMsiProcess'
        # From the v4 Execute-MSI wrapper aliases: Path->FilePath, Transform->Transforms (v4 plural), Parameters/
        # Arguments->ArgumentList, AddParameters->AdditionalArgumentList, SecureParameters->SecureArgumentList,
        # Patch->Patches (v4 plural), LogName->LogFileName. A leftover v3 name throws "parameter cannot be found".
        Params  = [ordered]@{
            '-Path'             = '-FilePath'
            '-AddParameters'    = '-AdditionalArgumentList'
            '-Parameters'       = '-ArgumentList'
            '-Arguments'        = '-ArgumentList'
            '-SecureParameters' = '-SecureArgumentList'
            '-Transform'        = '-Transforms'
            '-Patch'            = '-Patches'
            '-LogName'          = '-LogFileName'
        }
    }

    # -- File Operations --
    'Remove-File'                   = @{ NewName = 'Remove-ADTFile' }
    'Copy-File'                     = @{ NewName = 'Copy-ADTFile' }
    'Get-FileVersion'               = @{ NewName = 'Get-ADTFileVersion' }
    'Get-MsiExitCodeMessage'        = @{ NewName = 'Get-ADTMsiExitCodeMessage' }
    'Test-MSUpdates'                = @{ NewName = 'Test-ADTMSUpdates' }
    'Install-MSUpdates'             = @{ NewName = 'Install-ADTMSUpdates' }

    # -- Folder Operations --
    'Remove-Folder'                 = @{ NewName = 'Remove-ADTFolder' }
    'New-Folder'                    = @{ NewName = 'New-ADTFolder' }
    'Copy-FileToUserProfiles'       = @{ NewName = 'Copy-ADTFileToUserProfiles' }

    # -- Permissions (team-specific module Add-UGPermission) --
    # The team's v3 helper Add-UGPermission has a fundamentally different
    # call shape than v4 Set-ADTItemPermission (shortcut switches like
    # -Modify map to -Permission Modify, plus implicit -User and
    # -Inheritance arguments). That shape change can't be expressed as a
    # name swap, so the rewrite lives in Layer-4b below, not here.
    # (Set-ItemPermission was also considered but isn't actually used in
    # this team's v3 packages, so no mapping is needed.)

    # -- Branding / Reboot (team-specific module helpers) --
    # In v3 packages this team used Set-Branding to write the branding/
    # detection registry key, and Set-Reboot to handle pending-reboot logic.
    # In v4 the names changed to Set-MTBDetectionKey and Set-MTBReboot.
    # Parameters are identical so no -Params rename needed.
    # The current MTB functions take -Name (positional), NOT the old v3 -InstanceName; -AdditionalRegPaths is gone
    # too (the helper uses its fixed HKLM\SOFTWARE\VWG\CM path). The -AdditionalRegPaths value-list is stripped in
    # Layer 1c below.
    'Set-Branding'                  = @{ NewName = 'Set-MTBDetectionKey';    Params = @{ '-InstanceName' = '-Name' } }
    'Set-Reboot'                    = @{ NewName = 'Set-MTBReboot' }
    'Remove-Branding'               = @{ NewName = 'Remove-MTBDetectionKey'; Params = @{ '-InstanceName' = '-Name' } }

    # -- Application Detection --
    # v3's -Exact / -WildCard / -RegEx name-match SWITCHES became a single v4 -NameMatch VALUE parameter. Leaving the
    # bare switch (e.g. Get-ADTApplication -Name X -Exact) throws "parameter cannot be found" on v4.
    'Get-InstalledApplication'      = @{ NewName = 'Get-ADTApplication';      Params = @{ '-Exact' = "-NameMatch Exact"; '-WildCard' = "-NameMatch WildCard"; '-RegEx' = "-NameMatch Regex" } }
    'Remove-MSIApplications'        = @{ NewName = 'Uninstall-ADTApplication'; Params = @{ '-Exact' = "-NameMatch Exact"; '-WildCard' = "-NameMatch WildCard"; '-RegEx' = "-NameMatch Regex" } }   # Remove-ADTMsiApplications does NOT exist in v4

    # -- Registry --
    # Set-RegistryKey keeps -Value (that's the DATA in both v3 and v4). Get-RegistryKey's v3 -Value is the value NAME ->
    # v4 renamed it to -Name (v4 Get-ADTRegistryKey has NO -Value, so a leftover -Value throws "parameter cannot be found").
    # The param rename is scoped to Get-ADTRegistryKey call lines only, so Set-ADTRegistryKey's -Value (data) is untouched.
    'Set-RegistryKey'               = @{ NewName = 'Set-ADTRegistryKey' }
    'Remove-RegistryKey'            = @{ NewName = 'Remove-ADTRegistryKey' }
    'Get-RegistryKey'               = @{ NewName = 'Get-ADTRegistryKey'; Params = @{ '-Value' = '-Name' } }
    'Test-RegistryValue'            = @{ NewName = 'Test-ADTRegistryValue' }

    # -- INI Files --
    'Get-IniValue'                  = @{ NewName = 'Get-ADTIniValue' }
    'Set-IniValue'                  = @{ NewName = 'Set-ADTIniValue' }

    # -- Shortcuts --
    'New-Shortcut'                  = @{ NewName = 'New-ADTShortcut' }
    'Set-Shortcut'                  = @{ NewName = 'Set-ADTShortcut' }
    'Remove-Shortcut'               = @{ NewName = 'Remove-ADTFile' }   # v4 has no Remove-ADTShortcut; delete the .lnk

    # -- UI / Dialogs --
    'Show-InstallationWelcome'      = @{ NewName = 'Show-ADTInstallationWelcome' }
    'Show-InstallationProgress'     = @{ NewName = 'Show-ADTInstallationProgress' }
    'Close-InstallationProgress'    = @{ NewName = 'Close-ADTInstallationProgress' }
    'Show-InstallationRestartPrompt'= @{ NewName = 'Show-ADTInstallationRestartPrompt' }
    'Show-InstallationPrompt'       = @{ NewName = 'Show-ADTInstallationPrompt' }
    'Show-DialogBox'                = @{ NewName = 'Show-ADTDialogBox' }
    'Show-BalloonTip'               = @{ NewName = 'Show-ADTBalloonTip' }   # Show-ADTBalloonNotification does NOT exist in v4

    # -- Logging --
    'Write-Log'                     = @{
        NewName = 'Write-ADTLogEntry'
        # -Message and -Source params unchanged in name but noted for completeness
    }

    # -- Services --
    'Test-ServiceExists'            = @{ NewName = 'Test-ADTServiceExists' }
    'Get-ServiceStartMode'          = @{ NewName = 'Get-ADTServiceStartMode' }
    'Set-ServiceStartMode'          = @{ NewName = 'Set-ADTServiceStartMode' }
    'Stop-ServiceAndDependencies'   = @{ NewName = 'Stop-ADTServiceAndDependencies' }
    'Start-ServiceAndDependencies'  = @{ NewName = 'Start-ADTServiceAndDependencies' }

    # -- Environment --  (v4.1.5 PSM1: Set-ADTEnvironmentVariable uses -Variable / -Value, NOT -EnvironmentVariable / -EnvironmentValue)
    'Set-EnvironmentVariable'       = @{ NewName = 'Set-ADTEnvironmentVariable';    Params = @{ '-EnvironmentVariable' = '-Variable'; '-EnvironmentValue' = '-Value' } }
    'Remove-EnvironmentVariable'    = @{ NewName = 'Remove-ADTEnvironmentVariable'; Params = @{ '-EnvironmentVariable' = '-Variable' } }
    'Get-EnvironmentVariable'       = @{ NewName = 'Get-ADTEnvironmentVariable' }

    # -- Archive --  (the team's custom Expand-MTBZipFile in the Extensions module, NOT the v3 Expand-ZipFile)
    'Expand-ZipFile'                = @{ NewName = 'Expand-MTBZipFile' }

    # -- Active Setup --
    'Set-ActiveSetup'               = @{ NewName = 'Set-ADTActiveSetup' }

    # -- Reboot / Pending --
    'Get-PendingReboot'             = @{ NewName = 'Get-ADTPendingReboot' }

    # -- Fonts / Pinning -> deprecated (NO v4 module equivalent: Install-ADTFont / Uninstall-ADTFont /
    #    Set-ADTPinnedApplication are NOT exported by PSADT v4). Handled by V3DeprecatedFunctions = manual-review
    #    warning instead of a broken rename. (Fonts: see the team's Remove-MTBFonts helper for removal.)

    # -- Scheduled Task --
    'Test-PowerPoint'               = @{ NewName = 'Test-ADTPowerPoint' }

    # -- User Session --
    'Get-LoggedOnUser'              = @{ NewName = 'Get-ADTLoggedOnUser' }
    'Block-AppExecution'            = @{ NewName = 'Block-ADTAppExecution' }
    'Unblock-AppExecution'          = @{ NewName = 'Unblock-ADTAppExecution' }

    # -- Desktop / Start Menu --
    'Get-DesktopShortcut'           = @{ NewName = 'Get-ADTShortcut' }   # Get-ADTDesktopShortcut does NOT exist in v4

    # -- Power Management -> deprecated (Set-ADTPowerPlan is NOT exported by PSADT v4).

    # -- Misc --
    'Invoke-SCCMTask'               = @{ NewName = 'Invoke-ADTSCCMTask' }
    'Install-SCCMSoftwareUpdates'   = @{ NewName = 'Install-ADTSCCMSoftwareUpdates' }
    'Update-GroupPolicy'            = @{ NewName = 'Update-ADTGroupPolicy' }
    'Get-ObjectProperty'            = @{ NewName = 'Get-ADTObjectProperty' }
    'Resolve-Error'                 = @{ NewName = 'Resolve-ADTErrorRecord' }
    'Exit-Script'                   = @{ NewName = 'Close-ADTSession' }
    'Test-Battery'                  = @{ NewName = 'Test-ADTBattery' }
    'Test-NetworkConnection'        = @{ NewName = 'Test-ADTNetworkConnection' }
    'Get-FreeDiskSpace'             = @{ NewName = 'Get-ADTFreeDiskSpace' }
    'Get-DeferHistory'              = @{ NewName = 'Get-ADTDeferHistory' }
    'Set-DeferHistory'              = @{ NewName = 'Set-ADTDeferHistory' }
    'Get-UniversalDate'             = @{ NewName = 'Get-ADTUniversalDate' }
    'Get-MsiTableProperty'          = @{ NewName = 'Get-ADTMsiTableProperty' }
    'Set-MsiProperty'               = @{ NewName = 'Set-ADTMsiProperty' }
    'New-MsiTransform'              = @{ NewName = 'New-ADTMsiTransform' }
    'Test-IsMutexAvailable'         = @{ NewName = 'Test-ADTMutexAvailability' }
    'Disable-TerminalServerInstallMode' = @{ NewName = 'Disable-ADTTerminalServerInstallMode' }
    'Enable-TerminalServerInstallMode'  = @{ NewName = 'Enable-ADTTerminalServerInstallMode' }
    'Get-UserProfiles'              = @{ NewName = 'Get-ADTUserProfiles' }
    'Invoke-RegisterOrUnregisterDLL'= @{ NewName = 'Invoke-ADTRegSvr32'; Params = @{ '-DLLAction' = '-Action' } }   # was Invoke-ADTRegisterOrUnregisterDLL (does NOT exist)
    'ConvertTo-NTAccountOrSID'      = @{ NewName = 'ConvertTo-ADTNTAccountOrSID' }
    'Convert-RegistryPath'          = @{ NewName = 'Convert-ADTRegistryPath' }
    'Send-Keys'                     = @{ NewName = 'Send-ADTKeys' }
    'Get-WindowTitle'               = @{ NewName = 'Get-ADTWindowTitle' }
    'Show-HelpConsole'              = @{ NewName = 'Show-ADTHelpConsole' }
}


# ==============================================================================
# LAYER 2: Variable Mappings (v3 standalone variables → v4 $adtSession properties)
# ==============================================================================
# Format: 'v3VariableName' = 'v4Replacement'
# Note: when inside double-quoted strings, these become $($adtSession.XXX)
#       when standalone, they become $adtSession.XXX

$script:V3ToV4Variables = [ordered]@{
    # -- Application metadata --
    'appVendor'            = 'adtSession.AppVendor'
    'appName'              = 'adtSession.AppName'
    'appVersion'           = 'adtSession.AppVersion'
    'appArch'              = 'adtSession.AppArch'
    'appLang'              = 'adtSession.AppLang'
    'appRevision'          = 'adtSession.AppRevision'
    # -- Team v3 custom "$VWG_app*" aliases -> the v4 canonical form the template uses (AppFullName is the template's
    #    concatenated variable; the rest are $adtSession.*). Longest names FIRST so $VWG_appFullName is consumed before
    #    a shorter prefix could touch it (the ordered-dict order is honoured by the renamer).
    'VWG_appFullName'      = 'AppFullName'
    'VWG_appVendor'        = 'adtSession.AppVendor'
    'VWG_appName'          = 'adtSession.AppName'
    'VWG_appVersion'       = 'adtSession.AppVersion'
    'VWG_appArch'          = 'adtSession.AppArch'
    'VWG_appLang'          = 'adtSession.AppLang'
    'VWG_appRevision'      = 'adtSession.AppRevision'
    'appScriptVersion'     = 'adtSession.AppScriptVersion'
    'appScriptDate'        = 'adtSession.AppScriptDate'
    'appScriptAuthor'      = 'adtSession.AppScriptAuthor'
    'installTitle'         = 'adtSession.InstallTitle'
    'installName'          = 'adtSession.InstallName'

    # -- Deployment context --
    'deploymentType'       = 'adtSession.DeploymentType'
    'deployMode'           = 'adtSession.DeployMode'
    'deployAppScriptFriendlyName' = 'adtSession.DeployAppScriptFriendlyName'

    # -- Directories --
    'dirFiles'             = 'adtSession.DirFiles'
    'dirSupportFiles'      = 'adtSession.DirSupportFiles'
    'scriptDirectory'      = 'adtSession.ScriptDirectory'
    'dirAppDeployTemp'     = 'adtSession.DirAppDeployTemp'

    # -- Script info --
    'scriptParentPath'     = 'adtSession.ScriptDirectory'
    'scriptRoot'           = 'adtSession.ScriptDirectory'
    'invokingScript'       = 'adtSession.CallingScript'

    # -- Deployment status --
    'useDefaultMsi'        = 'adtSession.UseDefaultMsi'
    'defaultMsiFile'       = 'adtSession.DefaultMsiFile'
    'defaultMstFile'       = 'adtSession.DefaultMstFile'
    'defaultMspFiles'      = 'adtSession.DefaultMspFiles'
}


# ==============================================================================
# LAYER 3: Deprecated / Removed functions (v3 functions with no v4 equivalent)
# ==============================================================================
# These get a WARNING comment prepended when detected

$script:V3DeprecatedFunctions = @(
    'Refresh-Desktop'            # Removed in v4 (use Update-ADTDesktop)
    'Refresh-SessionEnvironment' # Removed - use Update-SessionEnvironment if available
    'Install-Font'               # No v4 equivalent - copy the font + register, or use the team helper
    'Uninstall-Font'             # No v4 equivalent - see the team's Remove-MTBFonts helper
    'Set-PinnedApplication'      # No v4 equivalent - pin via shell verbs manually
    'Set-PowerPlan'              # No v4 equivalent - use powercfg.exe via Start-ADTProcess
)

# --- v3 -> v4 conversion additions -----------------------------------------

# (b) HKCU all-users registry pattern.
#  v3: [ScriptBlock]$VAR = { ... $UserProfile.SID ... }
#      Invoke-HKCURegistrySettingsForAllUsers -RegistrySettings $VAR
#  v4: Invoke-ADTAllUsersRegistryAction -ScriptBlock { ... $_.SID ... }
# Find the index of the '}' matching the '{' at $OpenIndex (quote-aware depth count). v3 HKCU
# scriptblocks routinely contain nested If { } blocks, so brace matching MUST be balanced - a
# non-greedy regex stops at the FIRST '}', truncating the body and leaving orphaned braces that
# corrupt the whole Pre-Install section downstream.
function Find-ClosingBrace {
    param([string]$Text, [int]$OpenIndex)
    # Use the PowerShell TOKENIZER to match braces. The old hand-rolled counter only skipped simple quotes,
    # so braces inside COMMENTS (# ... }), HERE-STRINGS (@"..."@), and backtick-ESCAPED quotes (`") were
    # miscounted - that returned the wrong '}', truncating the scriptblock body and corrupting the script
    # (found via the corpus scan: ~12% of v3 packages produced a non-parsing script). The tokenizer classifies
    # LCurly/RCurly correctly and ignores braces inside strings/comments/here-strings. Lexing is robust even
    # when the whole text has grammar errors (we're mid-conversion), so this is safe.
    try {
        $tokens = $null; $perr = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$perr)
        $depth = 0; $started = $false
        foreach ($t in $tokens) {
            if ($t.Extent.StartOffset -lt $OpenIndex) { continue }
            if     ($t.Kind -eq [System.Management.Automation.Language.TokenKind]::LCurly) { $depth++; $started = $true }
            elseif ($t.Kind -eq [System.Management.Automation.Language.TokenKind]::RCurly) { $depth--; if ($started -and $depth -le 0) { return $t.Extent.StartOffset } }
        }
    } catch {}
    # Fallback: simple quote-aware counter (only if tokenization somehow yields nothing).
    $depth = 0; $q = $null
    for ($j = $OpenIndex; $j -lt $Text.Length; $j++) {
        $c = $Text[$j]
        if ($q) { if ($c -eq $q) { $q = $null } }
        elseif ($c -eq "'" -or $c -eq '"') { $q = $c }
        elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return $j } }
    }
    return -1
}

# v3's Get-InstalledApplication / Remove-MSIApplications took the app NAME as a POSITIONAL argument (their -Name was
# Position 0), so scripts wrote "Get-InstalledApplication -WildCard '*CodeMeter Runtime Kit*'" or "Get-InstalledApplication
# '*X*'". After the function+switch rename that becomes "Get-ADTApplication -NameMatch 'Wildcard' '*CodeMeter Runtime Kit*'".
# But v4's Get-ADTApplication -Name is NOT positional - POSITION 0 IS -FilterScript (a ScriptBlock) - so the bare name
# string binds to -FilterScript and the call BREAKS (matches nothing / "cannot bind"). This pass inserts an explicit -Name
# before that positional name literal. No-op when -Name or -ProductCode is already present (already-correct calls / a
# ProductCode lookup). Standard PSADT - identical in MTB and GPF.
function Add-AdtApplicationNameParam {
    param([string]$Content)
    if (-not $Content) { return $Content }
    $rx = New-Object System.Text.RegularExpressions.Regex '(?i)(?:Get-ADTApplication|Uninstall-ADTApplication)\b[^\r\n\)]*'
    return $rx.Replace($Content, [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $call = $m.Value
        # Already explicit -Name, or a ProductCode lookup (no -Name expected) -> leave untouched.
        if ($call -match '(?i)(?<!\w)-Name\b' -or $call -match '(?i)(?<!\w)-ProductCode\b') { return $call }
        # Mask the -NameMatch VALUE so its quoted/bareword arg is not mistaken for the positional Name.
        $masked = [regex]::Replace($call, "(?i)(-NameMatch\s+)('[^']*'|`"[^`"]*`"|\w+)", '${1}@@NM@@')
        # The positional Name is the first remaining quoted string OR a $variable.
        $qm = [regex]::Match($masked, "('[^']*'|`"[^`"]*`"|\`$\w[\w.]*)")
        if (-not $qm.Success) { return $call }
        $lit = $qm.Groups[1].Value
        $pos = $call.IndexOf($lit)
        if ($pos -lt 0) { return $call }
        return $call.Substring(0, $pos) + '-Name ' + $call.Substring($pos)
    })
}

# Canonicalize Get-ADTApplication / Uninstall-ADTApplication to the PREFERRED v4 syntax, so the order is stable no matter
# which v3 form we started from (positional "-WildCard '*X*'" comes out -NameMatch-first; explicit "-Name X -Exact" comes
# out -Name-first). Team house style + PSADT's own doc example ("Get-ADTApplication -Name 'Adobe Acrobat Reader' -NameMatch
# 'Exact'"): -Name FIRST, then -NameMatch with a BAREWORD (unquoted) ValidateSet value (Exact/WildCard/Regex/Contains).
# Only rewrites calls that have BOTH -Name and -NameMatch (leaves -ProductCode / -Name-only / dynamic-value calls alone).
function Set-AdtApplicationNameOrder {
    param([string]$Content)
    if (-not $Content) { return $Content }
    $rx = New-Object System.Text.RegularExpressions.Regex '(?i)(Get-ADTApplication|Uninstall-ADTApplication)\b([^\r\n\)]*)'
    return $rx.Replace($Content, [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $cmd  = $m.Groups[1].Value
        $args = $m.Groups[2].Value
        $nameM  = [regex]::Match($args, "(?i)-Name\s+('[^']*'|`"[^`"]*`"|\`$\w[\w.]*)")
        $matchM = [regex]::Match($args, "(?i)-NameMatch\s+('[^']*'|`"[^`"]*`"|\w+)")
        if (-not ($nameM.Success -and $matchM.Success)) { return $m.Value }   # need both to canonicalize
        $nameVal  = $nameM.Groups[1].Value
        $matchVal = $matchM.Groups[1].Value.Trim("'", '"')                    # unquote the ValidateSet value
        # Strip the two params out of the arg tail, keep anything else in place, then re-emit -Name then -NameMatch first.
        $rest = $args
        $rest = [regex]::Replace($rest, "(?i)\s*-Name\s+('[^']*'|`"[^`"]*`"|\`$\w[\w.]*)", '')
        $rest = [regex]::Replace($rest, "(?i)\s*-NameMatch\s+('[^']*'|`"[^`"]*`"|\w+)", '')
        $rest = $rest.Trim()
        $out  = "$cmd -Name $nameVal -NameMatch $matchVal"
        if ($rest) { $out += " $rest" }
        return $out
    })
}
function Convert-HKCUAllUsers {
    param([string]$Content)
    if (-not $Content) { return $Content }

    # POSITIONAL PAIRING. v3 scripts routinely repeat the SAME variable name for many HKCU blocks
    # (corpus scan: 8x "[scriptblock]$HKCURegistrySettings = {...}" each with its own Invoke). The old
    # design recorded defs in a name->body HASHTABLE (duplicate names collided), removed all defs, then
    # replaced invokes by name - the multi-step splice mangled text mid-line ("[scriptblrySettings...") and
    # broke ~12% of v3 conversions. Now: find each "[ScriptBlock]$VAR = {body}" IMMEDIATELY followed by its
    # "Invoke-...ForAllUsers -RegistrySettings $VAR", and replace the WHOLE def+invoke span (processed
    # BACKWARDS so indices stay valid) with one "Invoke-ADTAllUsersRegistryAction -ScriptBlock {body}".
    # INCREMENTAL rebuild (no multi-edit index staleness): find ONE def, balance-match it, pair it with its
    # immediately-following invoke, splice the combined span out and continue scanning from AFTER the
    # replacement. Doing all edits at once over a precomputed list could overlap on duplicate var names and
    # spliced text mid-token ("$UserProfile" -> "$UserP" + insert); rebuilding per match cannot.
    $defRe = [regex]'(?i)\[ScriptBlock\]\s*\$(\w+)\s*=\s*\{'
    $from = 0; $guard = 0
    while ($guard -lt 1000) {
        $guard++
        $m = $defRe.Match($Content, $from)
        if (-not $m.Success) { break }
        $open  = $m.Index + $m.Length - 1
        $close = Find-ClosingBrace -Text $Content -OpenIndex $open
        if ($close -lt 0) { $from = $m.Index + $m.Length; continue }
        $var  = $m.Groups[1].Value
        $body = $Content.Substring($open + 1, $close - $open - 1)
        $after  = $Content.Substring($close + 1)
        $invPat = '(?is)^\s*(?:#[^\r\n]*\r?\n\s*)*Invoke-HKCURegistrySettingsForAllUsers\s+-RegistrySettings\s+\$' + [regex]::Escape($var) + '\b[^\r\n]*'
        $im = [regex]::Match($after, $invPat)
        if ($im.Success) {
            $endAbs = $close + 1 + $im.Index + $im.Length
            $repl   = "Invoke-ADTAllUsersRegistryAction -ScriptBlock {$body}"
            $Content = $Content.Substring(0, $m.Index) + $repl + $Content.Substring($endAbs)
            $from = $m.Index + $repl.Length
        } else {
            $from = $close + 1   # no paired invoke right after -> leave the def, scan on
        }
    }

    # Fallback a) inline form: Invoke-...ForAllUsers -RegistrySettings { ... }  (no separate def).
    while ($true) {
        $m = [regex]::Match($Content, '(?i)Invoke-HKCURegistrySettingsForAllUsers\s+-RegistrySettings\s*\{')
        if (-not $m.Success) { break }
        $open  = $m.Index + $m.Length - 1
        $close = Find-ClosingBrace -Text $Content -OpenIndex $open
        if ($close -lt 0) { break }
        $body = $Content.Substring($open + 1, $close - $open - 1)
        $Content = $Content.Substring(0, $m.Index) + "Invoke-ADTAllUsersRegistryAction -ScriptBlock {$body}" + $Content.Substring($close + 1)
    }
    # Fallback b) any leftover invoke we couldn't pair: at minimum rename the cmdlet to its v4 name so the
    # script stays valid (the [scriptblock] def, if any remains, is valid v4 syntax on its own).
    $Content = [regex]::Replace($Content, '(?i)Invoke-HKCURegistrySettingsForAllUsers\b', 'Invoke-ADTAllUsersRegistryAction')

    # SID token: $UserProfile.SID -> $_.SID   ('$$' escapes to a literal '$' in a .NET replacement string;
    # '$_' alone would be the whole-input substitution token).
    $Content = $Content -replace '\$UserProfile\.SID', '$$_.SID'
    return $Content
}

# $VWG_CurrentRegWOW / $VWG_CurrentSysWOW are team-custom v3 variables that DO NOT exist in PSADT v4. Hardcode the
# WOW (32-bit) path directly: $VWG_CurrentRegWOW carried a trailing '\' (i.e. "Wow6432Node\"), $VWG_CurrentSysWOW
# was "SysWOW64". For a 64-bit app the packager removes the Wow6432Node\ segment. Done for v3 AND v4 predecessors
# (a v4 package that still references these would otherwise leave a broken, undefined variable in the script).
# The $(...) subexpression form is replaced FIRST so the bare-var pass below doesn't mangle the inner name.
function Convert-VWGRegWOW {
    param([string]$Content)
    if (-not $Content) { return $Content }
    $c = $Content
    $c = [regex]::Replace($c, '\$\(\s*\$VWG_CurrentRegWOW\s*\)', 'Wow6432Node\')
    $c = [regex]::Replace($c, '(?<![\w])\$VWG_CurrentRegWOW(?![\w])', 'Wow6432Node\')
    $c = [regex]::Replace($c, '\$\(\s*\$VWG_CurrentSysWOW\s*\)', 'SysWOW64')
    $c = [regex]::Replace($c, '(?<![\w])\$VWG_CurrentSysWOW(?![\w])', 'SysWOW64')
    return $c
}


# ==============================================================================
# CONVERSION FUNCTION
# ==============================================================================

function Convert-V3ToV4Content {
    <#
    .SYNOPSIS
    Converts PSADT v3 script content to v4 syntax.
    
    .DESCRIPTION
    Applies three layers of conversion:
    1. Function name swaps (with optional parameter renames per function)
    2. Variable renames ($appName → $adtSession.AppName, etc.)
    3. Deprecated function warnings
    
    .PARAMETER Content
    The script content string to convert.
    
    .PARAMETER ReportOnly
    If set, returns a report of what WOULD change without modifying content.
    
    .OUTPUTS
    Converted content string (or report hashtable if -ReportOnly)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,
        [switch]$ReportOnly
    )

    if ([string]::IsNullOrWhiteSpace($Content)) { return $Content }

    $changes = New-Object System.Collections.Generic.List[string]
    $result = $Content

    # -- LAYER 1: Function name swaps + parameter renames --
    foreach ($oldFunc in $script:V3ToV4Functions.Keys) {
        $mapping = $script:V3ToV4Functions[$oldFunc]
        $newFunc = $mapping.NewName

        # Check if this function exists in content (word-boundary match)
        if ($result -match "(?<![A-Za-z\-])$([regex]::Escape($oldFunc))(?![A-Za-z\-])") {

            if ($ReportOnly) {
                $changes.Add("Function: $oldFunc → $newFunc")
            }

            # Replace function name (word-boundary safe)
            # (?i): PowerShell cmdlet names are CASE-INSENSITIVE, so v3 scripts contain 'New-folder', 'copy-file',
            # 'execute-process' etc. The detection above uses -match (already case-insensitive); this Replace must be too,
            # or a mixed-case call is DETECTED but left unconverted (real gap seen in live GIMP: 'New-folder' survived).
            $funcPattern = "(?i)(?<![A-Za-z\-])$([regex]::Escape($oldFunc))(?![A-Za-z\-])"
            $result = [regex]::Replace($result, $funcPattern, $newFunc)

            # Parameter renames for this specific function (if any). Renames apply on the line
            # containing the call AND on its backtick-continuation lines (v3 scripts often split
            # long Execute-MSI calls with ` ) - otherwise params on continuation lines stayed v3.
            if ($mapping.Params) {
                foreach ($oldParam in $mapping.Params.Keys) {
                    $newParam = $mapping.Params[$oldParam]
                    if ($oldParam -eq $newParam) { continue }

                    $lines = $result -split "`r?`n"
                    $inCall = $false
                    for ($i = 0; $i -lt $lines.Count; $i++) {
                        $isCallLine = $lines[$i] -match [regex]::Escape($newFunc)
                        if ($isCallLine -or $inCall) {
                            # Delimiter after the param: whitespace, EOL, OR an expression-closer ) ] } ; , - so a SWITCH
                            # param at the end of a call like "Get-ADTApplication -Name X -Exact)" is matched too (the old
                            # (?=\s|$) missed -Exact) because ')' followed it).
                            $paramPattern = "(?<!\w)$([regex]::Escape($oldParam))(?=[\s\)\]\};,]|$)"
                            if ($lines[$i] -match $paramPattern) {
                                $lines[$i] = [regex]::Replace($lines[$i], $paramPattern, $newParam)
                                if ($ReportOnly) {
                                    $changes.Add("  Param on $newFunc`: $oldParam → $newParam (line $($i+1))")
                                }
                            }
                        }
                        # call continues onto the next line only when this line ends with a backtick
                        $inCall = ($isCallLine -or $inCall) -and ($lines[$i] -match '`\s*$')
                    }
                    $result = $lines -join "`r`n"
                }
            }
        }
    }

    # -- LAYER 1a-MSP: Execute-MSP (v3, applies an .msp patch) has NO standalone v4 cmdlet - v4 applies patches through
    #    Start-ADTMsiProcess -Action 'Patch'. Found genuinely unmapped in the corpus (EPLAN Platform updates etc.).
    #    Rewrite the call shape: add -Action 'Patch' and turn -Path into -FilePath. The bare fallback covers other forms
    #    (e.g. -FilePath already present); it just inserts -Action 'Patch'.
    $result = [regex]::Replace($result, "(?<![A-Za-z\-])Execute-MSP\b\s+-Path\b", "Start-ADTMsiProcess -Action 'Patch' -FilePath")
    $result = [regex]::Replace($result, "(?<![A-Za-z\-])Execute-MSP(?![A-Za-z\-])", "Start-ADTMsiProcess -Action 'Patch'")

    # -- LAYER 1b: Start-ADTMsiProcess with a ProductCode GUID must use -ProductCode,
    #    not -FilePath. v3 'Execute-MSI -Path "{GUID}"' meant a ProductCode (Execute-MSI
    #    accepted either a file or a GUID on -Path); the blind -Path->-FilePath rename
    #    above mis-tags the GUID case. Retarget those to -ProductCode.
    $result = [regex]::Replace($result,
        "(Start-ADTMsiProcess\b[^\r\n]*?)-FilePath(\s+(?:'|`")\{[0-9A-Fa-f-]{36}\}(?:'|`"))",
        '$1-ProductCode$2')

    # Remove the leftover v3 SoftIdent declaration (SoftIdent now lives in $adtSession).
    $result = [regex]::Replace($result, '(?im)^[ \t]*\[?string\]?[ \t]*\$VWG_SoftIdent\b.*\r?\n?', '')

    # LAYER 1c: the v3 branding helpers passed -AdditionalRegPaths "p1","p2"; the v4 MTB functions don't have it
    # (they use the fixed VWG\CM path) - strip the parameter and its comma-separated value list.
    $result = [regex]::Replace($result, '(?i)\s*-AdditionalRegPaths\s+"(?:[^"]*)"(?:\s*,\s*"(?:[^"]*)")*', '')

    # Team v3 vars not in v4 -> hardcode the WOW path (Wow6432Node\ / SysWOW64).
    $result = Convert-VWGRegWOW -Content $result

    # -- LAYER 1d: Active Setup with a PowerShell (.ps1) stub must be launched with -ExecutionPolicy 'Bypass'. The v3
    #    Set-ActiveSetup wrapper had NO -ExecutionPolicy param, so a converted line lacks it and v4 falls back to
    #    (Get-ExecutionPolicy) - which blocks the stub on a locked-down machine. Append it to each Create-form
    #    Set-ADTActiveSetup line whose stub is a .ps1 and that doesn't already specify it (skip -PurgeActiveSetupKey and
    #    backtick-continued lines). The team's house form is single-line, matching the fresh generator's output.
    if ($result -match '(?i)Set-ADTActiveSetup') {
        $asLines = $result -split "`r?`n"
        for ($li = 0; $li -lt $asLines.Count; $li++) {
            $ln = $asLines[$li]
            if ($ln -match '(?i)Set-ADTActiveSetup\b' -and $ln -match '(?i)-StubExePath' -and $ln -match '(?i)\.ps1' -and
                $ln -notmatch '(?i)-ExecutionPolicy' -and $ln -notmatch '(?i)-PurgeActiveSetupKey' -and $ln -notmatch '`\s*$') {
                $asLines[$li] = ($ln -replace '[ \t]+$', '') + " -ExecutionPolicy 'Bypass'"
                if ($ReportOnly) { $changes.Add("Param on Set-ADTActiveSetup: + -ExecutionPolicy 'Bypass' (.ps1 stub, line $($li+1))") }
            }
        }
        $result = $asLines -join "`r`n"
    }

    # -- LAYER 2: Variable renames --
    foreach ($oldVar in $script:V3ToV4Variables.Keys) {
        $newVar = $script:V3ToV4Variables[$oldVar]

        # Pattern: $oldVar followed by word boundary (dot, space, quote, end of line, etc.)
        # Must not be preceded by another letter (to avoid partial matches).
        # (?i) - hand-edited v3 scripts mix casing ($AppName vs $appName); the PS gate below is
        # case-insensitive but [regex]::Match is NOT, so without (?i) mixed-case occurrences
        # passed the gate yet were silently left unconverted (broken v3 vars in the v4 script).
        $varPattern = '(?i)\$' + [regex]::Escape($oldVar) + '(?=[.\s\)\}\]"''\\,;:|+\-*/=!<>@`r`n]|$)'

        if ($result -match $varPattern) {
            if ($ReportOnly) {
                $changes.Add("Variable: `$$oldVar → `$$newVar")
            }

            # Check each occurrence: if inside a double-quoted string, wrap in $()
            $lines = $result -split "`r?`n"
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                if ($line -match $varPattern) {
                    # Determine if inside a double-quoted string
                    # Simple heuristic: count " before the match position
                    # If odd number of " before it, we're inside a string → use $() wrapper
                    $matchObj = [regex]::Match($line, $varPattern)
                    while ($matchObj.Success) {
                        $beforeMatch = $line.Substring(0, $matchObj.Index)
                        $quoteCount = ([regex]::Matches($beforeMatch, '(?<!`)\"')).Count
                        
                        if ($quoteCount % 2 -eq 1) {
                            # Inside double-quoted string → $($adtSession.XXX)
                            $replacement = "`$(`$$newVar)"
                        } else {
                            # Standalone → $adtSession.XXX
                            $replacement = "`$$newVar"
                        }

                        $line = $line.Substring(0, $matchObj.Index) + $replacement + $line.Substring($matchObj.Index + $matchObj.Length)
                        
                        # Find next match (offset adjusted for replacement length difference)
                        $searchStart = $matchObj.Index + $replacement.Length
                        if ($searchStart -ge $line.Length) { break }
                        # Substring trick: avoids the 3-arg Match(str,pat,RegexOptions) overload
                        # which PS resolves as RegexOptions not startAt.
                        $subMatch = [regex]::Match($line.Substring($searchStart), $varPattern)
                        if (-not $subMatch.Success) { break }
                        # Re-create a match object with the correct absolute index
                        $matchObj = [regex]::Match($line, $varPattern)
                        $skip = $searchStart
                        while ($matchObj.Success -and $matchObj.Index -lt $skip) {
                            $matchObj = $matchObj.NextMatch()
                        }
                    }
                    $lines[$i] = $line
                }
            }
            $result = $lines -join "`r`n"
        }
    }

    # -- LAYER 3: Deprecated function warnings --
    foreach ($depFunc in $script:V3DeprecatedFunctions) {
        if ($result -match "(?<![A-Za-z\-])$([regex]::Escape($depFunc))(?![A-Za-z\-])") {
            # Check if already in the V3ToV4Functions table (some deprecated funcs have replacements)
            $replacement = if ($script:V3ToV4Functions.ContainsKey($depFunc)) {
                $script:V3ToV4Functions[$depFunc].NewName
            } else {
                'no direct v4 equivalent'
            }

            if ($ReportOnly) {
                $changes.Add("DEPRECATED: $depFunc → $replacement")
            }

            # Add warning comment above each usage
            $lines = $result -split "`r?`n"
            for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                if ($lines[$i] -match "(?<![A-Za-z\-])$([regex]::Escape($depFunc))(?![A-Za-z\-])") {
                    $indent = if ($lines[$i] -match '^(\s*)') { $matches[1] } else { '' }
                    $warningLine = "${indent}# WARNING: v3 function '$depFunc' - review manually ($replacement)"
                    # NOTE: $i=0 must be handled separately - $lines[0..(-1)] wraps around in PS
                    # (returns first + LAST line) and would scramble the script.
                    $pre = if ($i -gt 0) { @($lines[0..($i-1)]) } else { @() }
                    $lines = $pre + @($warningLine) + @($lines[$i..($lines.Count-1)])
                }
            }
            $result = $lines -join "`r`n"
        }
    }

    # -- LAYER 4: Contextual rewrites (shape-changing conversions) --
    # These can't be done with simple name/parameter swaps because the
    # surrounding control flow changes.

    # 4a. Remove-Folder -Path X -IfEmpty
    # The -IfEmpty parameter doesn't exist in v4. Convert to a Test +
    # Remove-ADTFolder pattern that checks the folder is non-empty before
    # calling Remove-ADTFolder. We rewrite the call into a multi-line
    # if/else block, preserving the original indent.
    #
    # Before:
    #     Remove-Folder -Path "$env:ProgramFiles\App" -IfEmpty
    # After (the team's house style - QA rule from Vithal: nested Test-Path -> Get-ChildItem|Measure-Object -eq 0,
    # Allman braces, -Path not -LiteralPath):
    #     If (Test-Path -Path "$env:ProgramFiles\App")
    #     {
    #         If ((Get-ChildItem -Path "$env:ProgramFiles\App" -Force | Measure-Object).Count -eq 0)
    #         {
    #             Remove-ADTFolder -Path "$env:ProgramFiles\App"
    #         }
    #     }
    #
    # Note: the function-name mapping above ALREADY rewrites
    # `Remove-Folder` -> `Remove-ADTFolder` in Layer 1, so by this point
    # the source has `Remove-ADTFolder -Path X -IfEmpty`. We match that.
    # Both `-Path` and `-LiteralPath` are handled.
    $rxIfEmpty = '(?m)^(\s*)Remove-ADTFolder\s+(?:(?:-LiteralPath|-Path)\s+)?("[^"]+"|''[^'']+''|\$\S+)(?:\s+-\w+\s+\S+)*\s+-IfEmpty\b'
    $result = [regex]::Replace($result, $rxIfEmpty, {
        param($m)
        $indent = $m.Groups[1].Value
        $path   = $m.Groups[2].Value
        if ($ReportOnly) { $changes.Add("Shape: Remove-Folder -IfEmpty -> nested Test-Path/Get-ChildItem block") }
        return @(
            "${indent}If (Test-Path -Path $path)"
            "${indent}{"
            "${indent}    If ((Get-ChildItem -Path $path -Force | Measure-Object).Count -eq 0)"
            "${indent}    {"
            "${indent}        Remove-ADTFolder -Path $path"
            "${indent}    }"
            "${indent}}"
        ) -join "`r`n"
    })

    # 4b. Add-UGPermission -path X -<PermissionSwitch>
    # The team-internal v3 helper Add-UGPermission accepted ONE of five
    # permission shortcut switches: -Modify, -FullControl, -ReadAndExecute,
    # -Read, -Write.  Target user was always the Users group (SID
    # *S-1-5-32-545) and inheritance was always
    # ObjectInherit,ContainerInherit.  The v4 standard equivalent is
    # Set-ADTItemPermission with explicit -User, -Permission, -Inheritance.
    #
    # Before (v3):
    #     Add-UGPermission -path "$envProgramdata\GT-SUITE_working_data" -Modify
    #
    # After (v4):
    #     Set-ADTItemPermission -LiteralPath "$envProgramdata\GT-SUITE_working_data" `
    #         -User '*S-1-5-32-545' -Permission Modify -Inheritance ObjectInherit,ContainerInherit
    #
    # Notes:
    #   - We accept -path (v3 default), -Path, and -LiteralPath as aliases.
    #   - The switch can be anywhere on the line after -path X.
    #   - We preserve the line's original indent.
    #   - Output is a single line; if the v4 call exceeds a reasonable
    #     length the user can manually wrap it later.
    $permSwitches = 'Modify|FullControl|ReadAndExecute|Read|Write'
    # A path can be a comma-separated LIST: Add-UGPermission -Path "a","b" -FullControl (corpus shape). We capture the
    # whole list and emit ONE Set-ADTItemPermission per path. Helper builds the per-path v4 lines.
    $pathItem = '(?:"[^"]+"|''[^'']+''|\$\S+)'
    $pathList = "$pathItem(?:\s*,\s*$pathItem)*"
    $emitPerms = {
        param($indent, $list, $permission)
        $paths = [regex]::Matches($list, '"[^"]+"|''[^'']+''|\$\S+') | ForEach-Object { $_.Value }
        ($paths | ForEach-Object { "${indent}Set-ADTItemPermission -LiteralPath $_ -User '*S-1-5-32-545' -Permission $permission -Inheritance ObjectInherit,ContainerInherit" }) -join "`r`n"
    }
    $rxUGPerm = '(?im)^(\s*)Add-UGPermission\s+(?:-LiteralPath|-Path|-path)\s+(' + $pathList + ')\s+-(' + $permSwitches + ')(?!\w)'
    $result = [regex]::Replace($result, $rxUGPerm, {
        param($m)
        if ($ReportOnly) { $changes.Add("Shape: Add-UGPermission -$($m.Groups[3].Value) -> Set-ADTItemPermission") }
        return (& $emitPerms $m.Groups[1].Value $m.Groups[2].Value $m.Groups[3].Value)
    })
    # Reverse switch order: -<Permission> first, then -path (some v3 packages bound params either way).
    # No trailing \b - a closing quote is not a word char, so \b after a quoted path would never match.
    $rxUGPermRev = '(?im)^(\s*)Add-UGPermission\s+-(' + $permSwitches + ')(?!\w)\s+(?:-LiteralPath|-Path|-path)\s+(' + $pathList + ')'
    $result = [regex]::Replace($result, $rxUGPermRev, {
        param($m)
        if ($ReportOnly) { $changes.Add("Shape: Add-UGPermission -$($m.Groups[2].Value) (reverse order) -> Set-ADTItemPermission") }
        return (& $emitPerms $m.Groups[1].Value $m.Groups[3].Value $m.Groups[2].Value)
    })
    # Safety net: any Add-UGPermission shape the two rewrites still didn't catch (an unknown switch, a non-quoted/odd
    # path) must NEVER be left as a silently-broken v3 call in v4 output - flag it for a quick manual convert.
    if ($result -match '(?<![A-Za-z\-])Add-UGPermission(?![A-Za-z\-])') {
        $lines = $result -split "`r?`n"
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i] -match '(?<![A-Za-z\-])Add-UGPermission(?![A-Za-z\-])') {
                $ind = if ($lines[$i] -match '^(\s*)') { $matches[1] } else { '' }
                $warn = "${ind}# WARNING: v3 'Add-UGPermission' (unusual shape) - convert manually to Set-ADTItemPermission"
                $pre = if ($i -gt 0) { @($lines[0..($i-1)]) } else { @() }
                $lines = $pre + @($warn) + @($lines[$i..($lines.Count-1)])
            }
        }
        $result = $lines -join "`r`n"
    }

    if ($ReportOnly) {
        return @{
            ChangeCount = $changes.Count
            Changes     = $changes
        }
    }

    # Run the HKCU-all-users conversion on the CONVERTED text ($result), not the stale $content -
    # the old line computed it on the wrong variable and then discarded it, so $UserProfile.SID and
    # Invoke-HKCURegistrySettingsForAllUsers were never converted in the returned script.
    $result = Convert-HKCUAllUsers -Content $result
    # Give Get-ADTApplication/Uninstall-ADTApplication their explicit -Name (v3's positional name breaks on v4).
    $result = Add-AdtApplicationNameParam -Content $result
    # Then normalise to the preferred order/syntax: -Name first, -NameMatch bareword value.
    $result = Set-AdtApplicationNameOrder -Content $result
    return $result
}


# ==============================================================================
# HELPER: Apply conversion to all Custom Logic textboxes
# ==============================================================================

function Convert-AllTextboxesV3ToV4 {
    <#
    .SYNOPSIS
    Applies v3→v4 conversion to all Custom Logic textboxes.
    Call this from Apply-PredecessorMetadata when SourceGeneration is 'v3'.
    #>
    param(
        [System.Windows.Controls.TextBox]$tbCustomVars,
        [System.Windows.Controls.TextBox]$tbPreInstall,
        [System.Windows.Controls.TextBox]$tbMainInstall,
        [System.Windows.Controls.TextBox]$tbPostInstall,
        [System.Windows.Controls.TextBox]$tbPreUninstall,
        [System.Windows.Controls.TextBox]$tbMainUninstall,
        [System.Windows.Controls.TextBox]$tbPostUninstall,
        [System.Windows.Controls.TextBox]$tbPreRepair,
        [System.Windows.Controls.TextBox]$tbMainRepair,
        [System.Windows.Controls.TextBox]$tbPostRepair
    )

    $textboxes = @(
        $tbCustomVars, $tbPreInstall, $tbMainInstall, $tbPostInstall,
        $tbPreUninstall, $tbMainUninstall, $tbPostUninstall,
        $tbPreRepair, $tbMainRepair, $tbPostRepair
    )

    $totalChanges = 0
    foreach ($tb in $textboxes) {
        if ($tb -and $tb.Text.Trim()) {
            $report = Convert-V3ToV4Content -Content $tb.Text -ReportOnly
            if ($report.ChangeCount -gt 0) {
                $tb.Text = Convert-V3ToV4Content -Content $tb.Text
                $totalChanges += $report.ChangeCount
            }
        }
    }

    return $totalChanges
}





# ==============================================================================
# HELPER: Generate conversion report (for logging / review)
# ==============================================================================

function Get-V3ToV4ConversionReport {
    <#
    .SYNOPSIS
    Analyzes content and returns a report of what would change without modifying it.
    #>
    param([string]$Content)

    return Convert-V3ToV4Content -Content $Content -ReportOnly
}
