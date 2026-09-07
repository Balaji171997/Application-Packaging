##############################################################
# Predecessor.ps1
# Parse a predecessor package into ONE clean model. We keep only
# authored code (between the standard PSADT section markers) and
# the identity/installer facts. All standard template boilerplate
# is discarded - the new package is built on OUR fresh template.
##############################################################

# Standard PSADT v3/v4 section markers. \s* makes them tolerant of templates
# that put spaces around the words (e.g. "=== MAIN-INSTALLATION BEGIN ===")
# as well as glued forms (e.g. "===MAIN-INSTALLATION BEGIN===").
$script:SectionMarkers = @(
    @{ F='CustomVariables';   B='#\*=+\s*CUSTOM APPLICATION VARIABLES BEGIN\s*=+'; E='#\*=+\s*CUSTOM APPLICATION VARIABLES END\s*=+'; Pre=$false }
    @{ F='PreInstallCode';    B='#{1,2}\*=+\s*PRE-INSTALLATION BEGIN\s*=+';        E='#{1,2}\*=+\s*PRE-INSTALLATION END\s*=+';        Pre=$true  }
    @{ F='MainInstallCode';   B='#\*=+\s*MAIN-INSTALLATION BEGIN\s*=+';            E='#\*=+\s*MAIN-INSTALLATION END\s*=+';            Pre=$true  }
    @{ F='PostInstallCode';   B='#\*=+\s*POST-INSTALLATION BEGIN\s*=+';            E='#\*=+\s*POST-INSTALLATION END\s*=+';            Pre=$false }
    @{ F='PreUninstallCode';  B='#{1,2}\*=+\s*PRE-UNINSTALLATION BEGIN\s*=+';      E='#{1,2}\*=+\s*PRE-UNINSTALLATION END\s*=+';      Pre=$true  }
    @{ F='MainUninstallCode'; B='#\*=+\s*MAIN-UNINSTALLATION BEGIN\s*=+';          E='#\*=+\s*MAIN-UNINSTALLATION END\s*=+';          Pre=$true  }
    @{ F='PostUninstallCode'; B='#\*=+\s*POST-UNINSTALLATION BEGIN\s*=+';          E='#\*=+\s*POST-UNINSTALLATION END\s*=+';          Pre=$false }
    @{ F='PreRepairCode';     B='#\*=+\s*PRE-REPAIR BEGIN\s*=+';                   E='#\*=+\s*PRE-REPAIR END\s*=+';                   Pre=$true  }
    @{ F='MainRepairCode';    B='#\*=+\s*MAIN-REPAIR BEGIN\s*=+';                  E='#\*=+\s*MAIN-REPAIR END\s*=+';                  Pre=$true  }
    @{ F='PostRepairCode';    B='#\*=+\s*POST-REPAIR BEGIN\s*=+';                  E='#\*=+\s*POST-REPAIR END\s*=+';                  Pre=$false }
)

function Get-SectionBody {
    param([string]$Content, [hashtable]$Section)
    if ($Content -match "(?s)$($Section.B)(.*?)$($Section.E)") {
        $body = $Matches[1]
        # For Pre-* / Main-* sections, drop everything before the author marker line.
        if ($Section.Pre) {
            $mk = [regex]::Match($body, '(?m)^\s*##\s*<Perform.*?tasks here>\s*$')
            if ($mk.Success) { $body = $body.Substring($mk.Index + $mk.Length) }
        }
        $body = $body.Trim("`r","`n"," ","`t")
        # CustomVariables keeps its $VWG_* declarations verbatim; everything else
        # gets boilerplate stripped so we don't duplicate what our template provides.
        if ($Section.F -ne 'CustomVariables') { $body = Strip-Boilerplate -Body $body }
        return $body
    }
    return ''
}

# Read a file regardless of encoding: honour UTF-16/UTF-8 BOMs, otherwise try
# UTF-8 and fall back to Windows-1252. v3 packages are frequently UTF-16 LE.
function Read-FileSmart {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $s = $null
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $s = [Text.Encoding]::Unicode.GetString($bytes) }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $s = [Text.Encoding]::BigEndianUnicode.GetString($bytes) }
    elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $s = [Text.Encoding]::UTF8.GetString($bytes) }
    else {
        try   { $s = [Text.Encoding]::GetEncoding('utf-8', [Text.EncoderFallback]::ExceptionFallback, [Text.DecoderFallback]::ExceptionFallback).GetString($bytes) }
        catch { $s = [Text.Encoding]::GetEncoding(1252).GetString($bytes) }
    }
    # Strip a leading BOM character (U+FEFF) - .NET GetString keeps it, and it breaks
    # ConvertFrom-Json / the `<#` help block / any "starts-with" parsing downstream.
    if ($s) { $s = $s.TrimStart([char]0xFEFF) }
    return $s
}

# Port of the proven boilerplate stripper: removes Show-Installation* calls,
# user-dialog if-blocks ($VWG_/$adtSession./$ UseDialogs etc.), $installPhase
# lines, Start/successful log lines, and section-marker comments - all of which
# our fresh template regenerates.
# Net brace count of a line, IGNORING braces inside quoted strings (e.g. a '{GUID}' or a
# path with braces must not skew block-skipping depth).
function Get-LineBraceDelta {
    param([string]$Line)
    $l = $Line -replace "'[^']*'", '' -replace '"[^"]*"', ''
    return (([regex]::Matches($l,'\{')).Count - ([regex]::Matches($l,'\}')).Count)
}

function Strip-Boilerplate {
    param([string]$Body)
    if (-not $Body) { return $Body }
    $flagPrefix = '(?:\$adtSession\.|\$VWG_|\$)'
    $flagNames  = 'UseDialogs|CheckForReboot|AllowDefer|ProcToClose|ProcToCloseNonUI|ProcToBlock'
    $lines = $Body -split "`r?`n"
    $kept = New-Object System.Collections.Generic.List[string]
    $i = 0
    # Brace depth INSIDE the body: scaffolding log lines are stripped ONLY at depth 0 (top level).
    # A success/start log inside an if/else (e.g. "uninstalled -> successful / else -> not found")
    # is conditional LOGIC, not scaffolding - it must survive verbatim. (The template's own
    # unconditional trailing success line is then suppressed by Set-SectionBody to avoid double logging.)
    $depth = 0
    while ($i -lt $lines.Count) {
        $line = $lines[$i]; $t = $line.Trim()
        $delta = Get-LineBraceDelta $line
        if ($t -match '#\s*user dialogs\s*\(deprecated\)') {
            $i++
            while ($i -lt $lines.Count -and $lines[$i].Trim() -eq '') { $i++ }
            if ($i -lt $lines.Count -and $lines[$i].Trim() -match '^if\s*\(') {
                $depth = 0; $started = $false
                while ($i -lt $lines.Count) {
                    $depth += Get-LineBraceDelta $lines[$i]
                    if ($depth -gt 0) { $started = $true }
                    $i++; if ($started -and $depth -le 0) { break }
                }
            }
            continue
        }
        if ($t -match '(?i)^#\s*check\s+for\s+pending\s+reboot') { $i++; continue }
        if ($t -match "^\s*if\s*\(.*?$flagPrefix($flagNames)\b.*?\)\s*\{?\s*$") {
            $depth = Get-LineBraceDelta $line
            $i++
            if ($depth -le 0) {
                while ($i -lt $lines.Count -and $lines[$i].Trim() -eq '') { $i++ }
                if ($i -lt $lines.Count -and $lines[$i].Contains('{')) {
                    $depth = Get-LineBraceDelta $lines[$i]
                    $i++
                }
            }
            while ($i -lt $lines.Count -and $depth -gt 0) {
                $depth += Get-LineBraceDelta $lines[$i]
                $i++
            }
            continue
        }
        if ($t -match '^\s*#*\s*Show-(ADT)?Installation(Welcome|Progress)\b') { $i++; continue }
        # Strip ONLY the template's own scaffolding log lines - matched by how their MESSAGE BEGINS.
        # (The old loose match - 'Start |successful' ANYWHERE - also deleted CUSTOM log lines like
        # "...Taskschedule ... is successfully deleted" = predecessor corruption.)
        #  - "Start Installation|Uninstallation|Repair ...": stripped at ANY depth. The template announces
        #    the action start unconditionally; a copy inside an if is duplicate scaffolding.
        #  - "Installation|Uninstallation|Repair of <x> is successful": stripped ONLY at top level (depth 0).
        #    Inside an if/else it is conditional LOGIC ("ran -> successful / else -> not found") and is kept;
        #    Set-SectionBody then suppresses the template's unconditional success line (no double success).
        if ($t -match 'Write-(ADT)?Log(Entry)?\b') {
            if ($t -match '(?i)["'']Start\s+(Installation|Uninstallation|Repair)\b') { $depth += $delta; $i++; continue }
            if ($depth -le 0 -and $t -match '(?i)["''](Installation|Uninstallation|Repair)\s+of\b.{0,160}?\bis\s+successful') { $depth += $delta; $i++; continue }
        }
        if ($t -match "(?i)^\[?[Ss]tring\]?\s*\`$installPhase\s*=") { $i++; continue }
        if ($t -match '^#{1,2}\s*<Perform.*?tasks here>\s*$' -or $t -match '^##\s*MARK:' -or $t -match '^##\s*=+') { $i++; continue }
        # Branding SET scaffolding is provided by the fresh template (ACTIVE) - drop the predecessor's copies so the
        # branding key is not SET twice. (Remove-* is KEPT; the uninstall-previous block needs it for the old branding.)
        if ($t -match '^#*\s*Set-MTBDetectionKey\b' -or $t -match '^#*\s*Set-Branding\b') { $i++; continue }
        # Reboot: strip ONLY the COMMENTED placeholder (#Set-MTBReboot). An ACTIVE Set-MTBReboot the predecessor placed
        # (pre-repair / between installs) is AUTHORED logic and must be KEPT - the template's own reboot line is commented,
        # so there is no double-reboot (team finding: predecessor Set-MTBReboot was being lost).
        if ($t -match '^#+\s*Set-MTBReboot\b') { $i++; continue }
        if ($t -match '^#{1,2}\s*Branding (Install|Detection Registry Key)\b') { $i++; continue }
        if ($t -match '^#{1,2}\s*Handling for required reboot\b') { $i++; continue }
        $kept.Add($line); $depth += $delta; $i++
    }
    # collapse repeated blank lines
    $out = New-Object System.Collections.Generic.List[string]; $prevBlank = $false
    foreach ($l in $kept) {
        $b = [string]::IsNullOrWhiteSpace($l)
        if ($b -and $prevBlank) { continue }
        $out.Add($l); $prevBlank = $b
    }
    return ($out -join "`r`n").Trim()
}

# Read MSI ProductCode (COM). Returns $null off-Windows / on failure.
function Get-MsiProductCode {
    param([string]$MsiPath)
    if (-not (Test-Path $MsiPath)) { return $null }
    $i=$null;$db=$null;$v=$null;$r=$null
    try {
        $i  = New-Object -ComObject WindowsInstaller.Installer
        $db = $i.OpenDatabase($MsiPath,0)
        $v  = $db.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = 'ProductCode'")
        $v.Execute($null); $r = $v.Fetch()
        if ($r) { return $r.StringData(1) }
    } catch { Write-Log "ProductCode read failed: $($_.Exception.Message)" Warning }
    finally {
        foreach($o in @($r,$v,$db,$i)){ if($o){[Runtime.InteropServices.Marshal]::ReleaseComObject($o)|Out-Null} }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }
    return $null
}

# Pull MTB session values (ProcToClose, FreeSpace, SoftIdent, ...) from a predecessor script.
# Works for v4 ($adtSession block entries) AND v3 ($VWG_* / converted assignments). Returns a
# hashtable of v4 field -> ready-to-insert RHS literal (arrays normalised, SoftIdent hive resolved).
function Extract-SessionValues {
    param([string]$Content, [string]$Arch)
    if (-not $Content) { return @{} }
    $fields     = 'ProcToClose','ProcToCloseNonUI','ProcToBlock','FreeSpace','FreeSpaceUninst','SoftIdent','CheckForReboot','AllowDefer','ShowBalloonTips'
    $procFields = 'ProcToClose','ProcToCloseNonUI','ProcToBlock'
    $out = @{}
    foreach ($f in $fields) {
        $rx = "(?im)^[ \t]*(?:\[[^\]]+\][ \t]*)?(?:\`$VWG_|\`$adtSession\.|\`$)?$f(?![A-Za-z0-9_])[ \t]*=[ \t]*(@\([^\r\n]*\)|\`$\([^\r\n]*\)|'[^']*'|""[^""]*"")"
        $m = [regex]::Match($Content, $rx)
        if (-not $m.Success) { continue }
        $val = $m.Groups[1].Value.Trim()
        if ($f -in $procFields -and $val -notmatch '^@\(' -and $val -notmatch '^\$\(') {
            $inner = $val.Trim('"',"'")
            if ($inner) {
                $items = ($inner -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $val = '@(' + (($items | ForEach-Object { "'$_'" }) -join ',') + ')'
            } else { $val = "''" }
        }
        if ($f -eq 'SoftIdent') {
            $inner = $val.Trim('"',"'")
            $wow = if ("$Arch" -match '(?i)x86') { 'WoW6432Node\' } else { '' }
            $inner = [regex]::Replace($inner, '(?i)\$\(\$?VWG_CurrentRegWO?W\)', $wow)
            $val = "'" + $inner + "'"
        }
        $out[$f] = $val
    }
    return $out
}

# Read predecessor package -> clean model hashtable.
#   $Content lets callers (and tests) pass script text directly;
#   otherwise it is read from <PackagePath>\...\Invoke-AppDeployToolkit.ps1
# Parse a PSADT code block into the ORDERED sequence of installer commands (MSI + EXE), so a MULTI-component
# predecessor (install A,B,C / uninstall C,B,A) is fully represented - not just its first installer. Skips helper
# calls (schtasks/reg/cmd/powershell/msiexec wrappers). Returns @(@{ Kind; Action; Name; Mst; ProductCode; Args;
# Display }) in source order.
function Get-PredecessorCommandSeq {
    param([string]$Code)
    $out = New-Object System.Collections.Generic.List[object]
    if (-not $Code) { return $out.ToArray() }
    $joined = [regex]::Replace($Code, '`[ \t]*\r?\n[ \t]*', ' ')   # join backtick-continued lines into one
    foreach ($raw in ($joined -split '\r?\n')) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $isMsi = $line -match '(?i)\b(Start-ADTMsiProcess|Execute-MSI)\b'
        $isExe = $line -match '(?i)\b(Start-ADTProcess|Execute-Process)\b'
        if (-not ($isMsi -or $isExe)) { continue }
        $fp   = ([regex]::Match($line, "(?i)-(?:FilePath|Path)\s+[`"']([^`"'\r\n]+?)[`"']")).Groups[1].Value
        $leaf = if ($fp) { ($fp -split '[\\/]')[-1] } else { '' }
        if ($isMsi) {
            $act = ([regex]::Match($line, "(?i)-Action\s+['""]?(Install|Uninstall|Repair|Patch)")).Groups[1].Value; if (-not $act) { $act = 'Install' }
            $mst = (([regex]::Match($line, "(?i)-Transform\s+[`"']([^`"'\r\n]+?)[`"']")).Groups[1].Value -split '[\\/]')[-1]
            $pc  = ([regex]::Match($line, '\{[0-9A-Fa-f\-]{36}\}')).Value
            $name = if ($leaf) { $leaf } elseif ($pc) { $pc } else { 'MSI' }
            $disp = "MSI   {0,-9} {1}{2}" -f $act, $name, $(if($mst){"  +$mst"}else{''})
            $out.Add([pscustomobject]@{ Kind='MSI'; Action=$act; Name=$name; Mst=$mst; ProductCode=$pc; Args=''; Display=$disp })
        } else {
            if (-not $leaf -or $leaf -match '(?i)schtasks|reg\.exe|cmd\.exe|powershell|msiexec') { continue }
            $al = ([regex]::Match($line, "(?i)-(?:ArgumentList|Parameters)\s+[`"']([^`"'\r\n]*)")).Groups[1].Value
            $disp = "EXE   {0}{1}" -f $leaf, $(if($al){"  $al"}else{''})
            $out.Add([pscustomobject]@{ Kind='EXE'; Action='Run'; Name=$leaf; Mst=''; ProductCode=''; Args=$al; Display=$disp })
        }
    }
    return $out.ToArray()
}
# Human-readable "how it installs / uninstalls" for a predecessor model (for the UI: tooltip + a details dialog).
function Format-PredecessorSeq {
    param($Model)
    if (-not $Model) { return '' }
    $ins = @($Model.InstallSeq); $un = @($Model.UninstallSeq)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("INSTALL  ($($ins.Count) step$(if($ins.Count -ne 1){'s'}), in order):")
    if ($ins.Count) { $i=0; foreach ($s in $ins) { $i++; [void]$sb.AppendLine(("  {0}. {1}" -f $i, $s.Display)) } } else { [void]$sb.AppendLine('  (none parsed)') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("UNINSTALL  ($($un.Count) step$(if($un.Count -ne 1){'s'}), reverse order):")
    if ($un.Count) { $i=0; foreach ($s in $un) { $i++; [void]$sb.AppendLine(("  {0}. {1}" -f $i, $s.Display)) } } else { [void]$sb.AppendLine('  (none parsed)') }
    return $sb.ToString().TrimEnd()
}

function Read-PredecessorModel {
    param([string]$PackagePath, [string]$PackageName, [string]$Content)

    if (-not $Content) {
        $ps1 = Get-ChildItem -Path $PackagePath -Filter 'Invoke-AppDeployToolkit.ps1' -Recurse -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if (-not $ps1) {
            $ps1 = Get-ChildItem -Path $PackagePath -Filter 'Deploy-Application.ps1' -Recurse -ErrorAction SilentlyContinue |
                   Select-Object -First 1   # v3 packages
        }
        if (-not $ps1) { Write-Log "No Invoke-AppDeployToolkit.ps1 / Deploy-Application.ps1 under $PackagePath" Error; return $null }
        $Content = Read-FileSmart -Path $ps1.FullName
    }

    $rawContent = $Content   # pre-conversion text (v3 $VWG_* survive here) for session extraction

    # v3 vs v4 detection (for the TemplateVer label). $isV3 = clearly a v3 script.
    $isV3 = ($Content -match 'Execute-Process|Show-InstallationWelcome|\$appName\b') -and
            ($Content -notmatch '\$adtSession')
    # Run the v3->v4 conversion whenever ANY v3-only PSADT syntax is present - NOT only when the whole script is v3.
    # Corpus finding (250-pkg scan): a few "v4" packages (they DO have an $adtSession block) still carry stray v3
    # cmdlets the author never migrated (Set-RegistryKey, Execute-MSP, ...). The old "$isV3 AND no $adtSession" gate
    # skipped them, leaving v3 cmdlets in the v4 output. Converting is safe on a v4 script: the v3 tables only match v3
    # names/vars, which a real v4 script doesn't use except as these very leftovers.
    $hasV3Syntax = $Content -match '(?<![A-Za-z\-])(Execute-Process|Execute-MSI|Execute-MSP|Execute-ProcessAsUser|Set-RegistryKey|Remove-RegistryKey|Get-RegistryKey|Test-RegistryValue|Copy-File|Remove-File|New-Folder|Remove-Folder|Get-FileVersion|Get-InstalledApplication|Remove-MSIApplications|Set-ActiveSetup|Block-AppExecution|Unblock-AppExecution|Get-PendingReboot|Set-Reboot|Set-Branding|Remove-Branding|Add-UGPermission|Show-Installation\w+|Show-DialogBox|Show-BalloonTip|New-Shortcut|Set-Shortcut|Get-IniValue|Set-IniValue|Test-ServiceExists|Get-LoggedOnUser|Invoke-RegisterOrUnregisterDLL|Convert-RegistryPath|Invoke-SCCMTask|Exit-Script|Write-Log)(?![A-Za-z\-])'
    if (($isV3 -or $hasV3Syntax) -and (Get-Command Convert-V3ToV4Content -ErrorAction SilentlyContinue)) {
        $Content = Convert-V3ToV4Content -Content $Content
    }
    # $VWG_CurrentRegWOW / $VWG_CurrentSysWOW don't exist in v4 - hardcode them in the BODY for BOTH v3 and v4
    # predecessors (a v4 package that still references them skips the v3 converter above and would keep a broken
    # variable). $rawContent KEEPS the originals - it's used for session/SoftIdent extraction, not the script body.
    if (Get-Command Convert-VWGRegWOW -ErrorAction SilentlyContinue) { $Content = Convert-VWGRegWOW -Content $Content }

    $model = @{
        Identity   = @{}
        Installer  = @{}
        Code       = @{}
        TemplateVer = $(if ($isV3) {'v3'} else {'v4'})
        RawV4Content = $Content   # post-conversion full script; used as the Step-3 template (interim)
    }

    if ($PackageName) {
        $pn = Parse-PackageName $PackageName
        if ($pn.IsValid) {
            $model.Identity = @{ Vendor=$pn.Vendor; AppName=$pn.AppName; Arch=$pn.Arch
                                 Version=$pn.Version; Release=$pn.Release; Lang=$pn.Lang; FullName=$pn.FullName }
        }
    }

    foreach ($s in $script:SectionMarkers) { $model.Code[$s.F] = Get-SectionBody -Content $Content -Section $s }

    # MTB session values (for populating the blank template's $adtSession), from pre-conversion text.
    $model.Session = Extract-SessionValues -Content $rawContent -Arch "$($model.Identity.Arch)"

    # Installer facts from the main-install command body.
    $mi = $model.Code.MainInstallCode
    $model.Installer.Type = if ($mi -match 'Start-ADTMsiProcess|\.msi\b') { 'MSI' }
                            elseif ($mi -match '\.exe\b') { 'EXE' } else { 'Unknown' }
    # Installer file names: prefer the QUOTED string (real names contain SPACES - 'Firefox Setup 140.10.2esr.msi';
    # the old bare [^\s]+ pattern truncated at the space, which broke the installer swap: the literal replace
    # then doubled the prefix or silently missed, leaving the OLD installer in the new script).
    $grab = {
        param($text, $ext)
        $q = [regex]::Match($text, "[`"']([^`"'\r\n]*?\.$ext)[`"']")
        if ($q.Success) { return [IO.Path]::GetFileName($q.Groups[1].Value) }
        $b = [regex]::Match($text, "[^\s`"']+\.$ext")
        if ($b.Success) { return [IO.Path]::GetFileName($b.Value) }
        return $null
    }
    $v = & $grab $mi 'msi'; if ($v) { $model.Installer.MsiFileName = $v }
    $v = & $grab $mi 'exe'; if ($v) { $model.Installer.ExeFileName = $v }
    $v = & $grab $mi 'mst'; if ($v) { $model.Installer.MstFileName = $v }
    $pc      = [regex]::Match($mi, '\{[0-9A-Fa-f\-]{36}\}'); if ($pc.Success){ $model.Installer.ProductCode = $pc.Value }

    # Full install/uninstall SEQUENCES (multi-component predecessors install A,B,C and uninstall C,B,A). Kept
    # alongside the single-installer fields the swap uses, so the tool can SHOW exactly how the predecessor goes.
    $model.InstallSeq   = @(Get-PredecessorCommandSeq -Code "$($model.Code.MainInstallCode)" | Where-Object { $_.Action -ne 'Uninstall' })
    $model.UninstallSeq = @(Get-PredecessorCommandSeq -Code "$($model.Code.MainUninstallCode)")
    $model.InstallCount = @($model.InstallSeq).Count
    $model.IsMulti      = ($model.InstallCount -gt 1)

    Write-Log "Predecessor model: $($model.Identity.FullName) [$($model.TemplateVer), $($model.Installer.Type) v$($model.Identity.Version)$(if($model.IsMulti){", MULTI: $($model.InstallCount) installs / $(@($model.UninstallSeq).Count) uninstalls"})]"
    return $model
}

# List the LIVE-share predecessor candidates for a parsed package name (newest first). ENGINE-level (not GUI): it runs
# inside background runspaces (Invoke-PBAsync) that load only the engine modules.
# ALL live-share roots searched for predecessors: the primary PredecessorPath, any extra repos from settings
# ('PredecessorPaths' array), PLUS the second live repository. De-duplicated; only existing (reachable) paths returned.
function Get-PredecessorRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $add = { param($p) if ("$p".Trim()) { $k = "$p".TrimEnd('\').ToLower(); if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; $roots.Add("$p") } } }
    & $add (Get-Setting PredecessorPath)
    foreach ($p in @(Get-Setting 'PredecessorPaths')) { & $add $p }
    & $add '\\MNDEMUCFS120.mn-man.biz\SWDistribution-Gate\CMLib_LIVE\Apps'   # 2nd LIVE repo - always searched too
    return @($roots | Where-Object { Test-Path $_ })
}

# Cheap normalized key for fuzzy comparison: lowercase, strip non-alphanumeric (so 'Adobe Reader'~'AdobeReader'~'adobe_reader').
function Get-PredNameKey { param([string]$s) return ([regex]::Replace("$s", '[^A-Za-z0-9]', '')).ToLowerInvariant() }
# Levenshtein-based similarity ratio 0..1. Inputs are short package tokens, so the DP cost is negligible.
function Get-NameSimilarity {
    param([string]$a, [string]$b)
    $a = "$a"; $b = "$b"
    if (-not $a -and -not $b) { return 1.0 }
    if (-not $a -or  -not $b) { return 0.0 }
    $la = $a.Length; $lb = $b.Length
    # two-row (1D) Levenshtein - avoids 2D-array indexing (which the PS 5.1 parser mishandles inside method calls)
    $prev = New-Object 'int[]' ($lb+1)
    $cur  = New-Object 'int[]' ($lb+1)
    for ($j=0; $j -le $lb; $j++) { $prev[$j] = $j }
    for ($i=1; $i -le $la; $i++) {
        $cur[0] = $i
        $ai = $a[$i-1]
        for ($j=1; $j -le $lb; $j++) {
            $cost = if ($ai -eq $b[$j-1]) { 0 } else { 1 }
            $del = $prev[$j] + 1
            $ins = $cur[$j-1] + 1
            $sub = $prev[$j-1] + $cost
            $m = $del; if ($ins -lt $m) { $m = $ins }; if ($sub -lt $m) { $m = $sub }
            $cur[$j] = $m
        }
        $tmp = $prev; $prev = $cur; $cur = $tmp
    }
    return (1.0 - ($prev[$lb] / [Math]::Max($la,$lb)))
}
# Predecessor candidates from the live share(s). EXACT vendor+app matches rank first (Score 100); when the app name
# (or vendor/app split) differs SLIGHTLY, close matches are ALSO offered - flagged Close/MatchNote so the packager
# can pick one instead of getting a dead "no predecessor". Levenshtein is gated (same-vendor / vendor-prefix) so a
# big share isn't scored pair-wise. When NOTHING scores, the BtnPred handler offers a manual Browse.
function Get-PredecessorCandidates {
    param($Parsed)
    $newFull = "$($Parsed.FullName)"
    $wantV  = Get-PredNameKey $Parsed.Vendor
    $wantA  = Get-PredNameKey $Parsed.AppName
    $wantVA = "$wantV$wantA"
    $vPre   = if ($wantV.Length -ge 3) { $wantV.Substring(0,3) } else { $wantV }
    $list = New-Object System.Collections.Generic.List[object]
    $seenNames = @{}                                    # same package present in BOTH repos -> first (primary) wins
    foreach ($base in (Get-PredecessorRoots)) {
        foreach ($c in (Get-ChildItem $base -Directory -ErrorAction SilentlyContinue)) {
            if ($c.Name -ieq $newFull) { continue }    # never offer the package as its OWN predecessor
            if ($seenNames.ContainsKey($c.Name.ToLower())) { continue }
            $p = Parse-PackageName $c.Name
            if (-not $p.IsValid) { continue }
            $cv = Get-PredNameKey $p.Vendor
            $ca = Get-PredNameKey $p.AppName
            $score = 0; $note = ''
            if ($cv -eq $wantV -and $ca -eq $wantA) {
                $score = 100
            } elseif ("$cv$ca" -eq $wantVA) {
                $score = 92; $note = 'vendor/name split differs'
            } elseif ($cv -eq $wantV) {                                 # same vendor -> fuzzy app name
                if ($wantA -and $ca -and ($ca.Contains($wantA) -or $wantA.Contains($ca))) { $score = 80; $note = 'similar app name' }
                else { $sim = Get-NameSimilarity $wantA $ca; if ($sim -ge 0.60) { $score = [int](45 + 45*$sim); $note = 'similar app name - verify' } }
            } elseif ($cv -and $cv.StartsWith($vPre)) {                 # vendor close too (prefix-gated) -> fuzzy vendor+app
                $sim = Get-NameSimilarity $wantVA "$cv$ca"; if ($sim -ge 0.70) { $score = [int](35 + 40*$sim); $note = 'similar vendor/name - verify' }
            }
            if ($score -le 0) { continue }
            $seenNames[$c.Name.ToLower()] = $true
            try { $v = [version]($p.Version -replace '[^0-9.]','') } catch { $v = $null }
            $list.Add([pscustomobject]@{
                Name=$c.Name; FullName=$c.FullName; Version=$p.Version; Ver=$v
                Revision=$p.Release; SameVersion=($p.Version -eq $Parsed.Version)
                Score=$score; Close=($score -lt 100); MatchNote=$note
            })
        }
    }
    return @($list | Sort-Object @{e={$_.Score};Descending=$true}, @{e={$_.Ver};Descending=$true}, @{e={$_.Revision};Descending=$true})
}
